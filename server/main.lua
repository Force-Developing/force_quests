local RESOURCE = GetCurrentResourceName()
-- Extra meters on top of a radius (the player's position on the server lags a little behind)
local DISTANCE_MARGIN = 3.0
-- A timed stop may be reported this much before its duration is up (network and frame timing)
local FINISH_EARLY_MS = 1500
-- Minimum time between two finished stops
local STOP_INTERVAL_MS = 2000
-- Minimum time between two quest starts of one player (every start spawns vehicles)
local START_INTERVAL_MS = 10000
-- Fastest believable travel speed (m/s): moving between two places faster than this is rejected
local TRAVEL_SPEED = 80.0
-- How far the trailer's center may be from the delivery spot on top of its radius (it hangs behind the truck)
local TRAILER_MARGIN = 15.0
-- How close (meters) the player has to stand to the vehicle to load a box
local LOAD_DISTANCE = 4.0
-- Minimum time between starting to ram a vehicle and scrapping it
local SCRAP_MIN_MS = 5000
-- Minimum time between two spawns of the same quest vehicle (a destroyed vehicle can be replaced)
local RESPAWN_INTERVAL_MS = 10000
-- How long the server waits for a spawned vehicle to exist
local SPAWN_TIMEOUT_MS = 3000
-- A spawn spot counts as blocked when another vehicle is this close
local SPOT_CLEAR_DISTANCE = 3.0
-- A new vehicle's health is only known on the server once a client synced it
local HEALTH_GRACE_MS = 30000
-- Quest vehicles are sampled every 5 s (and at every step): a vehicle may not move farther than TRAVEL_SPEED allows in
-- the time since its last accepted position, plus this many meters (network sync, physics, hooking a trailer)
local VEHICLE_JUMP_SLACK = 100.0
-- A sample where the vehicle didn't move proves nothing (parked, or its position isn't synced for a moment), so it
-- doesn't reset the time of the last accepted position; but at most this much time counts toward the next sample:
-- a truck parked at the depot can't jump to the drop afterwards.
local VEHICLE_STILL_MOVED = 1.0
local VEHICLE_MAX_GAP_MS = 20000

local quests = {}    -- [source] = { id, identifier, player, startedAt, deadline, progressAt, done = { [index] = true },
                     --              begun, carrying, lastStop, place, placeAt, vehicles = { [name] = entity },
                     --              spawnedAt = { [name] = ms }, track = { [name] = { coords, at } },
                     --              destroyed = { [name] = true when the server saw it destroyed } }
local takenBy = {}   -- [quest id] = source running it (Config.OneAtATime)
local cooldowns = {} -- [identifier] = { [quest id] = GetGameTimer() when the cooldown ends }
-- [license] = { [quest id] = GetGameTimer() when it ends }: after a quest was cancelled, ran out of time or its player left
local cancelCooldowns = {}
local lastStart = {} -- [source] = GetGameTimer() of the last accepted start

local function maxDurationMs()
  return math.max(5, tonumber(Config.MaxDuration) or 45) * 60000
end

local function cancelCooldownMs()
  return math.max(0, tonumber(Config.CancelCooldown) or 5) * 60000
end

--- 0 = no limit
local function idleTimeoutMs()
  local minutes = tonumber(Config.IdleTimeout) or 15
  if minutes <= 0 then return 0 end
  return math.max(1, minutes) * 60000
end

local function playerPed(source)
  local ped = GetPlayerPed(source)
  if not ped or ped == 0 then return nil end
  return ped
end

local function isNear(source, coords, distance)
  local ped = playerPed(source)
  return ped ~= nil and #(GetEntityCoords(ped) - coords) <= distance + DISTANCE_MARGIN
end

local function identifierOf(source)
  local ok, identifier = pcall(GetIdentifier, source)
  if not ok then
    Log("error", ("Reading the player's identifier failed: %s"):format(tostring(identifier)))
    return nil
  end
  return type(identifier) == "string" and identifier ~= "" and identifier or nil
end

--- The key of a player's cancel cooldown: the license, so switching character or reconnecting doesn't reset it
local function playerKey(source, identifier)
  local license = GetPlayerIdentifierByType(source, "license")
  return type(license) == "string" and license ~= "" and license or identifier
end

--- Milliseconds left of an entry in cooldowns / cancelCooldowns (0 when none; an ended entry is removed)
local function msLeft(list, key, id)
  local ends = list[key] and list[key][id]
  if not ends then return 0 end
  local left = ends - GetGameTimer()
  if left <= 0 then
    list[key][id] = nil
    if next(list[key]) == nil then list[key] = nil end
    return 0
  end
  return left
end

--- Seconds left on the cooldowns for a quest: the character's after a payout, the player's after a cancel (0 when none)
local function cooldownLeft(identifier, key, id)
  return math.ceil(math.max(msLeft(cooldowns, identifier, id), msLeft(cancelCooldowns, key, id)) / 1000)
end

local function startCooldown(identifier, quest)
  if not identifier or not quest or quest.cooldown <= 0 then return end
  cooldowns[identifier] = cooldowns[identifier] or {}
  cooldowns[identifier][quest.id] = GetGameTimer() + quest.cooldown * 1000
end

--- False when the vehicle is gone or destroyed (it may then be replaced)
local function vehicleAlive(entity, spawnedAt)
  if not entity or entity == 0 or not DoesEntityExist(entity) then return false end
  if spawnedAt and GetGameTimer() - spawnedAt < HEALTH_GRACE_MS then return true end
  return GetEntityHealth(entity) > 0
end

--- Remembers that the server saw the quest vehicle `name` destroyed (a vehicle that later vanishes was destroyed first)
local function noteDestroyed(running, name)
  local entity = running.vehicles[name]
  if entity and DoesEntityExist(entity) and not vehicleAlive(entity, running.spawnedAt[name]) then
    running.destroyed[name] = true
  end
end

--- True when the quest vehicle `name` vanished without the server seeing it destroyed (a modified client deleted it)
local function vehicleLost(running, name)
  local entity = running.vehicles[name]
  return entity ~= nil and not DoesEntityExist(entity) and not running.destroyed[name]
end

local function deleteVehicle(entity)
  if entity and entity ~= 0 and DoesEntityExist(entity) then DeleteEntity(entity) end
end

-- Ends that start no cancel cooldown: paid (the quest's own cooldown), a resource stop, a start whose vehicles failed
local NO_CANCEL_COOLDOWN = { paid = true, ["resource stopped"] = true, ["start vehicle failed"] = true }

--- Ends the player's quest (if any) and removes its vehicles. Every way a quest ends goes through here.
local function endQuest(source, why)
  local running = quests[source]
  if not running then return nil end
  quests[source] = nil
  if takenBy[running.id] == source then takenBy[running.id] = nil end
  -- cancelled, out of time, logout, left the server: the same player can't take this quest again at once (with
  -- Config.OneAtATime one player could otherwise hold a quest for everyone by taking it again and again)
  if not NO_CANCEL_COOLDOWN[why] and running.player and cancelCooldownMs() > 0 then
    cancelCooldowns[running.player] = cancelCooldowns[running.player] or {}
    cancelCooldowns[running.player][running.id] = GetGameTimer() + cancelCooldownMs()
  end
  for _, entity in pairs(running.vehicles) do deleteVehicle(entity) end
  Debug("info", "Quest '%s' of %s ended: %s", running.id, tostring(GetPlayerName(source)), why)
  return running
end

--- Ends a quest that ran past Config.MaxDuration or went Config.IdleTimeout without progress, and tells the client.
--- Returns true when it did.
local function expire(source)
  local running = quests[source]
  if not running or running.finishing then return false end
  local now = GetGameTimer()
  local idle = idleTimeoutMs()
  local why
  if now > running.deadline then why = "max duration"
  elseif idle > 0 and now - running.progressAt > idle then why = "no progress"
  else return false end
  endQuest(source, why)
  TriggerClientEvent(RESOURCE .. ":client:ended", source, "expired")
  return true
end

--- The quest moved on (a stop begun or done, a box picked up or loaded, a vehicle spawned near its spot)
local function progressed(running)
  running.progressAt = GetGameTimer()
end

--- True when the player could have travelled from the last place of the quest to `coords` since being there
local function travelled(running, coords)
  local needed = #(coords - running.place) / TRAVEL_SPEED * 1000
  return GetGameTimer() - running.placeAt >= needed
end

local function arrive(running, coords)
  running.place = coords
  running.placeAt = GetGameTimer()
end

--- True when no other vehicle stands on the spot (the quest's own vehicles don't count)
local function spotClear(running, position)
  local ok, all = pcall(GetAllVehicles)
  if not ok or type(all) ~= "table" then return true end
  local own = {}
  for _, entity in pairs(running.vehicles) do own[entity] = true end
  for _, entity in ipairs(all) do
    if not own[entity] and DoesEntityExist(entity) and #(GetEntityCoords(entity) - position) < SPOT_CLEAR_DISTANCE then
      return false
    end
  end
  return true
end

--- Spawns a quest vehicle on the server (networked, kept when its driver walks away) and gives keys
--- @return number|nil entity
local function spawnVehicle(source, vehicle)
  local c = vehicle.position
  local ok, entity = pcall(CreateVehicleServerSetter, joaat(vehicle.model), vehicle.type, c.x, c.y, c.z, vehicle.heading)
  if not ok or not entity or entity == 0 then
    Log("error", ("Quest vehicle '%s' (%s) could not be created: %s"):format(vehicle.name, vehicle.model, tostring(entity)))
    return nil
  end
  local deadline = GetGameTimer() + SPAWN_TIMEOUT_MS
  while not DoesEntityExist(entity) and GetGameTimer() < deadline do Wait(50) end
  if not DoesEntityExist(entity) then
    Log("error", ("Quest vehicle '%s' (%s) did not appear"):format(vehicle.name, vehicle.model))
    -- it may still show up later: it must not stay in the world without a quest
    pcall(DeleteEntity, entity)
    return nil
  end
  pcall(SetEntityOrphanMode, entity, 2)
  local plate = ("JOB%04d"):format(math.random(0, 9999))
  SetVehicleNumberPlateText(entity, plate)
  if vehicle.frozen then FreezeEntityPosition(entity, true) end
  if vehicle.locked then SetVehicleDoorsLocked(entity, 2) end
  -- ox_fuel reads the fuel level from this state bag
  if vehicle.type ~= "trailer" then Entity(entity).state:set("fuel", 100.0, true) end
  if Config.GiveKeys ~= false and vehicle.keys then
    local okKeys, err = pcall(GiveVehicleKeys, source, entity, plate)
    if not okKeys then Log("error", ("Giving vehicle keys failed: %s"):format(tostring(err))) end
  end
  return entity
end

--- The quest vehicle `name` as a net id, spawning it when it doesn't exist (or was destroyed)
--- @return number|nil netId, string|nil reason
local function ensureVehicle(source, running, name)
  local vehicle = GetQuest(running.id).vehicles[name]
  local current = running.vehicles[name]
  local last = running.spawnedAt[name]
  if vehicleAlive(current, last) then return NetworkGetNetworkIdFromEntity(current) end
  if last and GetGameTimer() - last < RESPAWN_INTERVAL_MS then return nil, "too_fast" end
  noteDestroyed(running, name)
  -- a replacement would stand on its spot, which is the return spot: a vehicle to hand back has to be brought back
  if vehicleLost(running, name) then
    local quest = GetQuest(running.id)
    local group = GetCurrentGroup(quest, running.done)
    for index, stop in ipairs(quest.stops) do
      if stop.type == "return" and stop.vehicle == name and stop.group == group and not running.done[index] then
        return nil, "vehicle_lost"
      end
    end
  end
  deleteVehicle(current)
  running.vehicles[name] = nil
  if not spotClear(running, vehicle.position) then return nil, "spot_blocked" end
  running.spawnedAt[name] = GetGameTimer()
  local entity = spawnVehicle(source, vehicle)
  -- the quest may have ended while the vehicle spawned
  if quests[source] ~= running then
    deleteVehicle(entity)
    return nil, "no_quest"
  end
  if not entity then return nil, "vehicle_failed" end
  running.vehicles[name] = entity
  running.destroyed[name] = nil
  running.track[name] = { coords = vehicle.position, at = GetGameTimer() }
  return NetworkGetNetworkIdFromEntity(entity)
end

--- Net ids of the quest vehicles that exist
local function vehicleNetIds(running)
  local out = {}
  for name, entity in pairs(running.vehicles) do
    if DoesEntityExist(entity) then out[name] = NetworkGetNetworkIdFromEntity(entity) end
  end
  return out
end

local function inVehicle(source, running, name)
  local entity = running.vehicles[name]
  local ped = playerPed(source)
  return entity ~= nil and ped ~= nil and DoesEntityExist(entity) and GetVehiclePedIsIn(ped, false) == entity
end

--- Coords of a quest vehicle, nil when it doesn't exist
local function vehicleCoords(running, name)
  local entity = running.vehicles[name]
  if not entity or not DoesEntityExist(entity) then return nil end
  return GetEntityCoords(entity)
end

--- Compares every quest vehicle's position with its last accepted one. False (and the quest ended) when one moved
--- farther than it can drive in the time between, i.e. a modified client teleported it. A vehicle that doesn't exist
--- for a moment, isn't synced or didn't move is skipped; the next sample is compared over the time since the last
--- accepted one (up to VEHICLE_MAX_GAP_MS). Also notes vehicles the server sees destroyed.
local function trackVehicles(source, running)
  local now = GetGameTimer()
  for name, entity in pairs(running.vehicles) do
    local track = running.track[name]
    if track and DoesEntityExist(entity) then
      noteDestroyed(running, name)
      local coords = GetEntityCoords(entity)
      local moved = #(coords - track.coords)
      if #coords >= 1.0 and moved >= VEHICLE_STILL_MOVED then
        local gap = math.min(now - track.at, VEHICLE_MAX_GAP_MS)
        if moved > TRAVEL_SPEED * gap / 1000 + VEHICLE_JUMP_SLACK then
          Log("warn", ("Quest vehicle '%s' of %s moved %d m in %.1f s, faster than it can drive: quest ended"):format(
            name, tostring(GetPlayerName(source)), math.floor(moved), (now - track.at) / 1000))
          endQuest(source, "vehicle moved faster than it can drive")
          return false
        end
        track.coords, track.at = coords, now
      end
    end
  end
  return true
end

--- What the client needs to pick up the player's quest: its id, the stops done, the vehicles and the carried box
local function questState(running)
  local done = {}
  for index in pairs(running.done) do done[#done + 1] = index end
  return { id = running.id, done = done, netIds = vehicleNetIds(running), carrying = running.carrying }
end

lib.callback.register(RESOURCE .. ":server:start", function(source, id)
  if not IsFrameworkReady() then return false, "not_ready" end
  local quest = GetQuest(id)
  if not quest then return false, "unknown_quest" end
  local identifier = identifierOf(source)
  if not identifier then return false, "not_ready" end
  expire(source)
  -- the state lets a client that missed the answer to its start (or to a step) pick the quest up again
  if quests[source] then return false, "busy", questState(quests[source]) end
  if not Config.Ped or not isNear(source, Config.Ped.position, GetInteractDistance()) then return false, "too_far" end
  local key = playerKey(source, identifier)
  local left = cooldownLeft(identifier, key, quest.id)
  if left > 0 then return false, "cooldown", left end
  if Config.OneAtATime ~= false and takenBy[quest.id] then return false, "quest_busy" end
  if lastStart[source] and GetGameTimer() - lastStart[source] < START_INTERVAL_MS then return false, "too_fast" end
  lastStart[source] = GetGameTimer()

  local startedAt = GetGameTimer()
  local running = {
    id = quest.id,
    identifier = identifier,
    player = key,
    startedAt = startedAt,
    deadline = startedAt + maxDurationMs(),
    progressAt = startedAt,
    done = {},
    lastStop = 0,
    place = Config.Ped.position,
    placeAt = startedAt,
    vehicles = {},
    spawnedAt = {},
    track = {},
    destroyed = {},
  }
  quests[source] = running
  takenBy[quest.id] = source

  -- vehicles without a spawnDistance wait at the quest giver
  for name, vehicle in pairs(quest.vehicles) do
    if not vehicle.spawnDistance then
      local netId, reason = ensureVehicle(source, running, name)
      if not netId then
        endQuest(source, "start vehicle failed")
        return false, reason or "vehicle_failed"
      end
    end
  end
  Debug("info", "%s started quest '%s'", tostring(GetPlayerName(source)), quest.id)
  return true, vehicleNetIds(running)
end)

-- The client lost track of its quest (an answer came after it stopped waiting): the server's state, false for none
lib.callback.register(RESOURCE .. ":server:state", function(source)
  local running = quests[source]
  if not running or expire(source) then return false end
  return questState(running)
end)

-- The client asks for a vehicle that spawns near its spot (or for a replacement of a destroyed one)
lib.callback.register(RESOURCE .. ":server:vehicle", function(source, name)
  local running = quests[source]
  if not running then return false, "no_quest" end
  if expire(source) then return false, "expired" end
  local vehicle = type(name) == "string" and GetQuest(running.id).vehicles[name]
  if not vehicle then return false, "failed" end
  local current = running.vehicles[name]
  if vehicleAlive(current, running.spawnedAt[name]) then return true, NetworkGetNetworkIdFromEntity(current) end
  if not isNear(source, vehicle.position, vehicle.spawnDistance or 50.0) then return false, "too_far" end
  local netId, reason = ensureVehicle(source, running, name)
  if not netId then return false, reason end
  progressed(running)
  return true, netId
end)

--- The stop `index` when it belongs to the current group and isn't done
--- @return table|nil stop, string|nil reason
local function checkStop(running, index)
  local quest = GetQuest(running.id)
  index = math.tointeger(tonumber(index))
  local stop = index and quest.stops[index]
  if not stop or running.done[index] then return nil, "failed" end
  if stop.group ~= GetCurrentGroup(quest, running.done) then return nil, "failed" end
  return stop
end

--- Body health of the vehicle to scrap, nil while the server can't know it yet
local function scrapHealth(running, stop)
  local entity = running.vehicles[stop.target]
  if not entity or not DoesEntityExist(entity) then return nil end
  local spawnedAt = running.spawnedAt[stop.target]
  if spawnedAt and GetGameTimer() - spawnedAt < HEALTH_GRACE_MS then return nil end
  return GetVehicleBodyHealth(entity)
end

--- Where the player has to be to start or finish a stop
--- @return boolean ok, string|nil reason
local function checkPlace(source, running, stop)
  local t = stop.type
  if t == "carry" or t == "task" then
    if not isNear(source, stop.coords, GetInteractDistance()) then return false, "too_far" end
    return true
  end
  if t == "scrap" then
    if not inVehicle(source, running, stop.vehicle) then return false, "wrong_vehicle" end
    local target = vehicleCoords(running, stop.target)
    if not target or not isNear(source, target, stop.radius) then return false, "too_far" end
    return true
  end
  if not isNear(source, stop.coords, stop.radius) then return false, "too_far" end
  if t == "deliver" then
    if not inVehicle(source, running, stop.vehicle) then return false, "wrong_vehicle" end
    local trailer = vehicleCoords(running, stop.trailer)
    if not trailer or #(trailer - stop.coords) > stop.radius + TRAILER_MARGIN + DISTANCE_MARGIN then
      return false, "no_trailer"
    end
    return true
  end
  -- "return": a vehicle the server saw destroyed doesn't block the quest (the player still has to come back here); one
  -- that vanished without that has to be brought back
  local coords = vehicleCoords(running, stop.vehicle)
  if not coords then
    if vehicleLost(running, stop.vehicle) then return false, "vehicle_lost" end
    return true
  end
  if #(coords - stop.coords) > stop.radius + DISTANCE_MARGIN then return false, "too_far" end
  return true
end

-- A box pickup, a cleaning spot or ramming the vehicle to scrap starts here (the player is in place)
lib.callback.register(RESOURCE .. ":server:begin", function(source, index)
  local running = quests[source]
  if not running then return false, "no_quest" end
  if expire(source) then return false, "expired" end
  if not trackVehicles(source, running) then return false, "no_quest" end
  local stop, reason = checkStop(running, index)
  if not stop then return false, reason end
  if stop.type ~= "carry" and stop.type ~= "task" and stop.type ~= "scrap" then return false, "failed" end
  local ok, why = checkPlace(source, running, stop)
  if not ok then return false, why end
  if not travelled(running, stop.coords) then return false, "too_fast" end
  -- Picking up another box drops the one in the player's hands (it stays where it was and can be picked up again)
  if stop.type == "carry" then running.carrying = nil end
  running.begun = { index = stop.index, at = GetGameTimer() }
  progressed(running)
  return true, stop.duration
end)

lib.callback.register(RESOURCE .. ":server:complete", function(source, index)
  local running = quests[source]
  if not running then return false, "no_quest" end
  if expire(source) then return false, "expired" end
  if not trackVehicles(source, running) then return false, "no_quest" end
  local stop, reason = checkStop(running, index)
  if not stop then return false, reason end
  local begun = running.begun
  local now = GetGameTimer()
  local timed = stop.duration > 0 or stop.type == "scrap"
  if timed then
    local minimum = stop.type == "scrap" and SCRAP_MIN_MS or stop.duration - FINISH_EARLY_MS
    if not begun or begun.index ~= stop.index or now - begun.at < minimum then return false, "too_fast" end
  end
  local ok, why = checkPlace(source, running, stop)
  if not ok then return false, why end
  -- (timed stops checked the travel time when they began)
  if not timed and not travelled(running, stop.coords) then return false, "too_fast" end
  if stop.type ~= "carry" and now - running.lastStop < STOP_INTERVAL_MS then return false, "too_fast" end
  if stop.type == "scrap" then
    local health = scrapHealth(running, stop)
    if not health or health >= stop.bodyHealth then return false, "not_scrapped" end
  end

  running.begun = nil
  progressed(running)
  -- A picked up box is done once it is in the vehicle (:server:load)
  if stop.type == "carry" then
    running.carrying = stop.index
    arrive(running, stop.coords)
    return true, "carrying"
  end
  running.done[stop.index] = true
  running.lastStop = now
  arrive(running, stop.coords)
  if stop.type == "return" then
    deleteVehicle(running.vehicles[stop.vehicle])
    running.vehicles[stop.vehicle] = nil
  end
  local quest = GetQuest(running.id)
  local done = 0
  for _ in pairs(running.done) do done = done + 1 end
  return true, done, #quest.stops
end)

-- The player puts the box in their hands into the quest vehicle
lib.callback.register(RESOURCE .. ":server:load", function(source, index)
  local running = quests[source]
  if not running then return false, "no_quest" end
  if expire(source) then return false, "expired" end
  if not trackVehicles(source, running) then return false, "no_quest" end
  local stop, reason = checkStop(running, index)
  if not stop then return false, reason end
  if stop.type ~= "carry" or running.carrying ~= stop.index then return false, "not_carrying" end
  local coords = vehicleCoords(running, stop.vehicle)
  if not coords or not isNear(source, coords, LOAD_DISTANCE) then return false, "too_far" end
  if not travelled(running, coords) then return false, "too_fast" end

  running.carrying = nil
  running.done[stop.index] = true
  running.lastStop = GetGameTimer()
  progressed(running)
  arrive(running, coords)
  local done, total = 0, 0
  for i, s in ipairs(GetQuest(running.id).stops) do
    if s.type == "carry" then
      total = total + 1
      if running.done[i] then done = done + 1 end
    end
  end
  return true, done, total
end)

--- Pays the reward. The quest stays open when the payment failed.
--- @return number|nil amount, string|nil reason
local function payout(source, quest)
  local amount = math.random(quest.reward.min, quest.reward.max)
  local okPay, paid = pcall(AddMoney, source, quest.account, amount)
  if okPay and paid then return amount end
  Log("error", ("Paying $%s (%s) to %s failed%s"):format(amount, quest.account, tostring(GetPlayerName(source)),
    okPay and "" or (": " .. tostring(paid))))
  return nil, "payment_failed"
end

lib.callback.register(RESOURCE .. ":server:finish", function(source)
  local running = quests[source]
  if not running then return false, "no_quest" end
  if running.finishing then return false, "busy" end
  if expire(source) then return false, "expired" end
  local quest = GetQuest(running.id)
  -- The character changed (logout / multichar) since the quest started: it belonged to the old one
  if identifierOf(source) ~= running.identifier then
    endQuest(source, "character changed")
    return false, "no_quest"
  end
  if GetCurrentGroup(quest, running.done) then return false, "not_done" end
  if not Config.Ped or not isNear(source, Config.Ped.position, GetInteractDistance()) then return false, "too_far" end
  if not travelled(running, Config.Ped.position) then return false, "too_fast" end

  -- Money exports may yield: a second finish (or a cancel) must not run while this one pays
  running.finishing = true
  local okRun, amount, reason = pcall(payout, source, quest)
  running.finishing = nil
  if not okRun then
    Log("error", ("Paying the quest failed: %s"):format(tostring(amount)))
    return false, "payment_failed"
  end
  if not amount then return false, reason end

  endQuest(source, "paid")
  startCooldown(running.identifier, quest)
  Debug("info", "%s finished quest '%s' for $%s (%s)", tostring(GetPlayerName(source)), quest.id, amount, quest.account)
  TriggerEvent(RESOURCE .. ":questFinished", source, quest.id, amount, quest.account)
  return true, amount
end)

-- The player cancelled the quest. Nothing is paid.
RegisterNetEvent(RESOURCE .. ":server:cancel", function()
  local src = source
  -- A payout in progress decides the quest; it ends the quest itself
  if quests[src] and quests[src].finishing then return end
  endQuest(src, "cancelled")
end)

AddEventHandler("playerDropped", function()
  local src = source
  endQuest(src, "player left")
  lastStart[src] = nil
end)

AddEventHandler("onResourceStop", function(resource)
  if resource ~= RESOURCE then return end
  for src in pairs(quests) do endQuest(src, "resource stopped") end
end)

--- Ends the quest when its player logged out or switched character (multichar) without leaving the server: otherwise
--- the quest would keep its vehicles and block everyone else (Config.OneAtATime) until Config.MaxDuration.
local function checkCharacter(source)
  local running = quests[source]
  if not running or running.finishing or identifierOf(source) == running.identifier then return end
  endQuest(source, "character changed")
  TriggerClientEvent(RESOURCE .. ":client:ended", source, "character")
end

-- Every 5 s: ends quests that ran past Config.MaxDuration, went Config.IdleTimeout without progress, whose character is
-- gone or whose vehicle was teleported
CreateThread(function()
  while true do
    Wait(5000)
    for src in pairs(quests) do
      if not expire(src) then
        checkCharacter(src)
        local running = quests[src]
        if running and not running.finishing and not trackVehicles(src, running) then
          TriggerClientEvent(RESOURCE .. ":client:ended", src, "vehicle")
        end
      end
    end
  end
end)

--- The quest id the player is running, or nil
exports("GetActiveQuest", function(source)
  local running = quests[tonumber(source) or -1]
  return running and running.id or nil
end)
