local RESOURCE = GetCurrentResourceName()
local IS_SERVER = IsDuplicityVersion()

--- Prints to the console regardless of Config.Debug (setup problems must always be visible).
--- @param level "error"|"warn"|"info"
function Log(level, message)
  local color = level == "error" and "^1" or level == "warn" and "^3" or "^2"
  print(("%s[%s] %s^7"):format(color, RESOURCE, tostring(message)))
end

--- Debug output. Errors are always printed, everything else only with Config.Debug.
function Debug(level, message, ...)
  message = tostring(message)
  if select("#", ...) > 0 then
    local ok, formatted = pcall(string.format, message, ...)
    if ok then message = formatted end
  end
  if level == "error" then
    lib.print.error(message)
    return
  end
  if not Config.Debug then return end
  local fn = ({ warn = lib.print.warn, info = lib.print.info, debug = lib.print.debug })[level] or lib.print.info
  fn(message)
end

--- Loads the configured locale. "auto" follows the replicated ox:locale convar; anything without a file -> "en".
local function InitLocale()
  local key = Config.Locale
  if type(key) ~= "string" or key == "auto" then key = GetConvar("ox:locale", "en") end
  local function hasLocale(name)
    return name and LoadResourceFile(RESOURCE, ("locales/%s.json"):format(name)) ~= nil
  end
  if not hasLocale(key) then
    local language = key:match("^(%a+)")
    key = hasLocale(language) and language or "en"
  end
  lib.locale(key)
end

-------------------------------------------------------------------------------------------------------------------
-- Quests (validated once per side; the server repeats every check, the client only uses them for the UI)
-------------------------------------------------------------------------------------------------------------------

local function isVector(value)
  local t = type(value)
  return (t == "vector3" or t == "vector4" or t == "table") and tonumber(value.x) and tonumber(value.y)
      and tonumber(value.z) and true or false
end

--- Heading of a vec4 (nil for a vec3: reading .w from a vector3 errors in cfx)
local function headingOf(value)
  local t = type(value)
  if t == "vector4" then return value.w + 0.0 end
  if t == "table" and tonumber(value.w) then return tonumber(value.w) + 0.0 end
  return nil
end

local function toVector3(v)
  return vector3(v.x + 0.0, v.y + 0.0, v.z + 0.0)
end

--- Whole number >= minimum, or the fallback
local function wholeNumber(value, fallback, minimum)
  local n = math.tointeger(math.floor(tonumber(value) or fallback))
  if not n or n < minimum then return fallback end
  return n
end

local ACCOUNTS = { cash = true, bank = true }
local STOP_TYPES = { deliver = true, ["return"] = true, carry = true, scrap = true, task = true }
local VEHICLE_TYPES = { automobile = true, bike = true, boat = true, heli = true, plane = true, submarine = true, trailer = true }
-- Stop types that need `vehicle`
local NEEDS_VEHICLE = { deliver = true, ["return"] = true, carry = true, scrap = true }

local function PreparePed()
  local ped = Config.Ped
  if type(ped) ~= "table" or not isVector(ped.coords) then
    Log("error", "Config.Ped needs coords: nobody can take a quest")
    Config.Ped = nil
    return
  end
  local anim = ped.anim
  if type(anim) ~= "table" or type(anim.dict) ~= "string" or type(anim.clip) ~= "string" then anim = nil end
  local blip = ped.blip
  if type(blip) ~= "table" then blip = nil end
  Config.Ped = {
    name = type(ped.name) == "string" and ped.name or "Philip",
    model = type(ped.model) == "string" and ped.model or "a_m_y_cyclist_01",
    position = toVector3(ped.coords),
    heading = headingOf(ped.coords) or 0.0,
    anim = anim,
    blip = blip,
  }
end

local function PrepareVehicles(id, vehicles)
  local out = {}
  for name, vehicle in pairs(type(vehicles) == "table" and vehicles or {}) do
    if type(name) ~= "string" or type(vehicle) ~= "table" or type(vehicle.model) ~= "string" or not isVector(vehicle.coords) then
      Log("error", ("Quest '%s': vehicle '%s' is skipped, it needs a model and coords"):format(id, tostring(name)))
    else
      local vehicleType = VEHICLE_TYPES[vehicle.type] and vehicle.type or "automobile"
      local locked = vehicle.locked == true
      out[name] = {
        name = name,
        model = vehicle.model,
        type = vehicleType,
        label = type(vehicle.label) == "string" and vehicle.label or name,
        sprite = tonumber(vehicle.sprite),
        position = toVector3(vehicle.coords),
        heading = headingOf(vehicle.coords) or 0.0,
        spawnDistance = tonumber(vehicle.spawnDistance) and (tonumber(vehicle.spawnDistance) + 0.0) or nil,
        frozen = vehicle.frozen == true,
        locked = locked,
        keys = vehicle.keys ~= false and not locked and vehicleType ~= "trailer",
      }
    end
  end
  return out
end

local function PrepareStop(index, stop, vehicles)
  if type(stop) ~= "table" then return nil, "it must be a table" end
  if not STOP_TYPES[stop.type] then return nil, "type must be deliver, return, carry, scrap or task" end
  if not isVector(stop.coords) then return nil, "it needs coords" end
  if NEEDS_VEHICLE[stop.type] and not vehicles[stop.vehicle] then
    return nil, ("vehicle '%s' is not in the quest's vehicles"):format(tostring(stop.vehicle))
  end
  if stop.type == "deliver" and not vehicles[stop.trailer] then
    return nil, ("trailer '%s' is not in the quest's vehicles"):format(tostring(stop.trailer))
  end
  if stop.type == "scrap" and not vehicles[stop.target] then
    return nil, ("target '%s' is not in the quest's vehicles"):format(tostring(stop.target))
  end
  local duration = wholeNumber(stop.duration, 0, 0) * 1000
  if (stop.type == "carry" or stop.type == "task") and duration <= 0 then return nil, "it needs a duration" end
  return {
    index = index,
    type = stop.type,
    group = wholeNumber(stop.group, index, 0),
    coords = toVector3(stop.coords),
    radius = math.max(1.0, (tonumber(stop.radius) or 5.0) + 0.0),
    vehicle = NEEDS_VEHICLE[stop.type] and stop.vehicle or nil,
    trailer = stop.type == "deliver" and stop.trailer or nil,
    target = stop.type == "scrap" and stop.target or nil,
    bodyHealth = stop.type == "scrap" and math.max(1.0, (tonumber(stop.bodyHealth) or 360) + 0.0) or nil,
    duration = (stop.type == "carry" or stop.type == "task") and duration or 0,
    prop = type(stop.prop) == "string" and stop.prop or nil,
    scenario = type(stop.scenario) == "string" and stop.scenario or nil,
    heading = tonumber(stop.heading) and (tonumber(stop.heading) + 0.0) or nil,
    action = type(stop.action) == "string" and stop.action or "clean",
  }
end

local function PrepareQuest(id, quest)
  if type(id) ~= "string" then return nil, "the quest id must be a string" end
  if type(quest) ~= "table" then return nil, "it must be a table" end
  local vehicles = PrepareVehicles(id, quest.vehicles)
  local stops = {}
  for index, stop in ipairs(type(quest.stops) == "table" and quest.stops or {}) do
    local prepared, why = PrepareStop(index, stop, vehicles)
    if not prepared then return nil, ("stop %d: %s"):format(index, why) end
    stops[#stops + 1] = prepared
  end
  if #stops == 0 then return nil, "it needs at least one stop" end
  local account = quest.account
  if not ACCOUNTS[account] then
    if account ~= nil then Log("error", ("Quest '%s': unknown account '%s', using \"cash\""):format(id, tostring(account))) end
    account = "cash"
  end
  local reward = type(quest.reward) == "table" and quest.reward or { min = quest.reward, max = quest.reward }
  local min = wholeNumber(reward.min, 0, 0)
  local max = wholeNumber(reward.max, min, min)
  local area = quest.area
  if type(area) ~= "table" or not isVector(area.coords) then area = nil end

  quest.id = id
  quest.label = type(quest.label) == "string" and quest.label or nil
  quest.description = type(quest.description) == "string" and quest.description or nil
  quest.reward = { min = min, max = max }
  quest.account = account
  quest.cooldown = wholeNumber(quest.cooldown, 0, 0)
  quest.area = area and { coords = toVector3(area.coords), radius = math.max(1.0, (tonumber(area.radius) or 30.0) + 0.0) } or nil
  quest.vehicles = vehicles
  quest.stops = stops
  return quest
end

local function PrepareQuests()
  if type(Config.Quests) ~= "table" then
    Log("error", "Config.Quests is missing or not a table")
    Config.Quests = {}
    return
  end
  for id, quest in pairs(Config.Quests) do
    local prepared, why = PrepareQuest(id, quest)
    if not prepared then
      Log("error", ("Quest '%s' is skipped: %s"):format(tostring(id), why))
      Config.Quests[id] = nil
    end
  end
end

--- @param id any
--- @return table|nil
function GetQuest(id)
  if type(id) ~= "string" then return nil end
  return Config.Quests[id]
end

--- Quest ids sorted by key
--- @return string[]
function GetQuestIds()
  local ids = {}
  for id in pairs(Config.Quests) do ids[#ids + 1] = id end
  table.sort(ids)
  return ids
end

--- Lowest group with an unfinished stop (nil when every stop is done)
--- @param quest table
--- @param done table<number, boolean>
--- @return number|nil
function GetCurrentGroup(quest, done)
  local group
  for index, stop in ipairs(quest.stops) do
    if not done[index] and (not group or stop.group < group) then group = stop.group end
  end
  return group
end

--- Meters the player has to be within of Philip, a box or a cleaning spot
function GetInteractDistance()
  return math.max(1.0, (tonumber(Config.InteractDistance) or 2.0) + 0.0)
end

-------------------------------------------------------------------------------------------------------------------
-- Environment: framework and target
--
-- The server decides, because only the server sees every resource: a client only knows the resources it has
-- mounted already, so a framework ensured after this resource reads "missing" there. A candidate that is
-- installed but not started yet is waited for without a time limit, with a red warning every 10 seconds.
-- The decisions are replicated through GlobalState; clients wait for them and never detect on their own.
-------------------------------------------------------------------------------------------------------------------

local FRAMEWORK_KEY = RESOURCE .. ":framework"
local TARGET_KEY = RESOURCE .. ":target"

-- qbx_core before qb-core: qbx_core `provide`s qb-core, so GetResourceState('qb-core') is "started" on QBox too
local FRAMEWORKS = {
  { name = "qbx", resource = "qbx_core" },
  { name = "esx", resource = "es_extended" },
  { name = "qb",  resource = "qb-core" },
}
local FRAMEWORK_RESOURCES = { qbx = "qbx_core", esx = "es_extended", qb = "qb-core" }

local TARGETS = {
  { name = "ox_target", resource = "ox_target" },
  { name = "qb-target", resource = "qb-target" },
}

local environment = {}    -- framework = { name, resource }, target = "ox_target" | "qb-target" | "none"
local frameworkInits = {} -- [name] = init functions registered by the framework files
local frameworkActive = false
local readyCallbacks = {}

local function IsStartedOrStarting(resource)
  local state = GetResourceState(resource)
  return state == "started" or state == "starting"
end

local function IsInstalled(resource)
  local state = GetResourceState(resource)
  return state ~= "missing" and state ~= "unknown"
end

--- First running candidate, otherwise nil and the candidates that are installed but not started yet
local function FindRunning(list)
  for _, entry in ipairs(list) do
    if IsStartedOrStarting(entry.resource) then return entry end
  end
  local waiting = {}
  for _, entry in ipairs(list) do
    if IsInstalled(entry.resource) then waiting[#waiting + 1] = entry.resource end
  end
  return nil, waiting
end

--- Server only: calls onResolved(entry) once a candidate runs, or onResolved(false) when none is installed.
local function ResolveOnServer(what, list, onResolved)
  local entry, waiting = FindRunning(list)
  if entry or #waiting == 0 then return onResolved(entry or false) end

  CreateThread(function()
    local nextWarning = GetGameTimer() + 10000
    while true do
      Wait(250)
      entry, waiting = FindRunning(list)
      if entry or #waiting == 0 then return onResolved(entry or false) end
      if GetGameTimer() >= nextWarning then
        Log("error", ("Waiting for the %s (%s) to start. Ensure it before %s in server.cfg, or remove it if you " ..
          "don't use it."):format(what, table.concat(waiting, ", "), RESOURCE))
        nextWarning = GetGameTimer() + 10000
      end
    end
  end)
end

local function NormalizeFramework(name)
  if name == "qbcore" then return "qb" end
  if name == "qbox" then return "qbx" end
  return name
end

local function RunSafe(label, fn)
  local ok, err = pcall(fn)
  if not ok then Log("error", ("%s failed: %s"):format(label, tostring(err))) end
end

--- Framework files (server/custom/frameworks, client/custom/frameworks) register their body here. It runs once
--- the framework is known: right away when it already is, otherwise as soon as the server has decided.
--- @param name string "esx" | "qb" | "qbx" | "custom"
--- @param init function
function RegisterFramework(name, init)
  name = NormalizeFramework(name)
  if frameworkActive then
    if Config.Framework == name then RunSafe("Framework file '" .. name .. "'", init) end
    return
  end
  frameworkInits[name] = frameworkInits[name] or {}
  table.insert(frameworkInits[name], init)
end

--- True once the framework is known on this side
function IsFrameworkReady()
  return frameworkActive
end

--- Resource name of the active framework (nil for custom)
function GetFrameworkResource()
  return environment.framework and environment.framework.resource
end

--- "ox_target" | "qb-target" | "none", nil until known
function GetTargetSystem()
  return environment.target
end

local function IsReady()
  return frameworkActive and environment.target ~= nil
end

--- Runs fn once framework and target are known on this side (immediately when they already are)
function OnEnvironmentReady(fn)
  if IsReady() then return RunSafe("Environment callback", fn) end
  readyCallbacks[#readyCallbacks + 1] = fn
end

local function NotifyReady()
  if not IsReady() then return end
  local callbacks = readyCallbacks
  readyCallbacks = {}
  for _, fn in ipairs(callbacks) do RunSafe("Environment callback", fn) end
end

local function ActivateFramework(framework)
  if frameworkActive then return end
  environment.framework = framework
  Config.Framework = framework.name
  frameworkActive = true
  local inits = frameworkInits[framework.name]
  frameworkInits = {}
  for _, init in ipairs(inits or {}) do RunSafe("Framework file '" .. framework.name .. "'", init) end
  Debug("info", "Framework: " .. framework.name)
end

local function SetTarget(target)
  if environment.target ~= nil then return end
  environment.target = target
  Config.Target = target
  Debug("info", "Target: " .. target)
end

local function InitServer()
  local configured = NormalizeFramework(Config.Framework)
  -- Replaces a decision a previous run of this resource left in GlobalState
  GlobalState[FRAMEWORK_KEY] = nil
  GlobalState[TARGET_KEY] = nil

  local function publish()
    GlobalState[FRAMEWORK_KEY] = environment.framework
    GlobalState[TARGET_KEY] = environment.target
    NotifyReady()
  end

  if configured ~= "auto" then
    if configured ~= "custom" and not FRAMEWORK_RESOURCES[configured] then
      Log("error", ("Unknown Config.Framework '%s', using \"auto\""):format(tostring(Config.Framework)))
      configured = "auto"
    end
  end

  if configured == "auto" then
    ResolveOnServer("framework", FRAMEWORKS, function(entry)
      if entry then
        ActivateFramework({ name = entry.name, resource = entry.resource })
      else
        Log("warn", "No supported framework found (qbx_core, es_extended, qb-core), using the custom framework files " ..
          "(server/custom/frameworks/custom.lua, client/custom/frameworks/custom.lua).")
        ActivateFramework({ name = "custom" })
      end
      publish()
    end)
  else
    ActivateFramework({ name = configured, resource = FRAMEWORK_RESOURCES[configured] })
    publish()
  end

  local target = Config.Target
  if target == "auto" then
    ResolveOnServer("target resource", TARGETS, function(entry)
      SetTarget(entry and entry.name or "none")
      publish()
    end)
  else
    if target ~= "ox_target" and target ~= "qb-target" then target = "none" end
    SetTarget(target)
    publish()
  end
end

local function InitClient()
  local function Apply()
    local framework, target = GlobalState[FRAMEWORK_KEY], GlobalState[TARGET_KEY]
    if type(target) == "string" then SetTarget(target) end
    if type(framework) == "table" and type(framework.name) == "string" then ActivateFramework(framework) end
    NotifyReady()
  end

  -- Usually the server decided long before the client joined
  Apply()
  if IsReady() then return end

  AddStateBagChangeHandler(FRAMEWORK_KEY, "global", function() SetTimeout(0, Apply) end)
  AddStateBagChangeHandler(TARGET_KEY, "global", function() SetTimeout(0, Apply) end)

  CreateThread(function()
    local nextWarning = GetGameTimer() + 15000
    while not IsReady() do
      Wait(500)
      Apply()
      if not IsReady() and GetGameTimer() >= nextWarning then
        Log("warn", "Still waiting for the server to detect the framework / target resource (see the server console).")
        nextWarning = GetGameTimer() + 15000
      end
    end
  end)
end

--- Calls getter() until it returns a value. If the framework isn't running on this side yet, waits for it without
--- a time limit and warns every 10 seconds. Runs again when the framework restarts (cached objects go stale).
--- @param resource string
--- @param getter fun(): any
--- @param onLoaded fun(obj: any)
function LoadFrameworkObject(resource, getter, onLoaded)
  local loading = false
  local function load()
    if loading then return end
    loading = true
    CreateThread(function()
      local nextWarning = GetGameTimer() + 10000
      while true do
        if GetResourceState(resource) == "started" then
          local ok, obj = pcall(getter)
          if ok and obj then
            onLoaded(obj)
            loading = false
            return
          end
        end
        if GetGameTimer() >= nextWarning then
          Log("warn", ("Still waiting for %s to start. Ensure it before %s in server.cfg."):format(resource, RESOURCE))
          nextWarning = GetGameTimer() + 10000
        end
        Wait(250)
      end
    end)
  end

  load()
  AddEventHandler(IS_SERVER and "onServerResourceStart" or "onClientResourceStart", function(started)
    if started == resource then load() end
  end)
end

-- Safe defaults until a framework file is active: requests that arrive earlier are refused cleanly
if IS_SERVER then
  function GetIdentifier(source) return nil end
  function AddMoney(source, account, amount) return false end
  function GiveVehicleKeys(source, vehicle, plate) end
else
  function IsPlayerLoaded() return false end
end

InitLocale()
PreparePed()
PrepareQuests()
RunSafe("Environment initialization", IS_SERVER and InitServer or InitClient)
