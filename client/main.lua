local RESOURCE = GetCurrentResourceName()
local CALLBACK_TIMEOUT = 15000
local PED_SPAWN_DISTANCE = 50.0
local MARKER_DISTANCE = 100.0
local VEHICLE_REQUEST_INTERVAL = 5000
local SLOW_TICK = 250
local LEAVE_TIMEOUT = 3000
-- How close (meters) the player has to be to the quest vehicle to load a box (the server allows a bit more)
local LOAD_DISTANCE = 3.0
-- Time between two attempts to start / finish scrapping while the server says "not yet"
local SCRAP_RETRY = 2000
local KEY_E = 38
local BLIP_COLOUR = 46
local TRUNK_DOOR = 5
local PICKUP_DICT, PICKUP_CLIP = "mini@repair", "fixing_a_ped"
local CARRY_DICT, CARRY_CLIP = "anim@heists@box_carry@", "idle"
local CARRY_PROP = "prop_cs_cardbox_01"
local STOP_TEXT = "stop"

local ped = nil          -- Philip: { entity, point, blip }
local requesting = false -- menu / dialog / server request at Philip in progress
local quest = nil        -- the running quest, see beginQuest()
local lastPress = 0

local function notify(message, notifyType)
  lib.notify({ description = message, type = notifyType or "inform" })
end

local function playerLoaded()
  local ok, loaded = pcall(IsPlayerLoaded)
  return ok and loaded == true
end

--- A locale text, or the fallback when the locale has no such key
local function textOr(key, fallback)
  local text = locale(key)
  if text == key then return fallback end
  return text
end

local function questLabel(def)
  return def.label or textOr("quest_" .. def.id, def.id)
end

local function questDescription(def)
  return def.description or textOr("quest_" .. def.id .. "_desc", "")
end

--- lib.callback with its own timeout (ox_lib waits 5 minutes and throws). Returns nil when the server didn't answer.
local function awaitServer(name, ...)
  local p = promise.new()
  local settled = false
  local function settle(value)
    if settled then return end
    settled = true
    p:resolve(value)
  end
  lib.callback(name, false, function(...)
    settle({ n = select("#", ...), ... })
  end, ...)
  SetTimeout(CALLBACK_TIMEOUT, function() settle(false) end)
  local result = Citizen.Await(p)
  if not result then return nil end
  return table.unpack(result, 1, result.n)
end

--- Notification for a reason the server returned
local function notifyReason(reason, def, stop, extra)
  if reason == "cooldown" then
    return notify(locale("cooldown", math.max(1, math.ceil((tonumber(extra) or 60) / 60))), "error")
  end
  if reason == "wrong_vehicle" and def and stop and stop.vehicle then
    return notify(locale("wrong_vehicle", def.vehicles[stop.vehicle].label), "error")
  end
  if reason == "no_trailer" and def and stop and stop.trailer then
    return notify(locale("no_trailer", def.vehicles[stop.trailer].label), "error")
  end
  if reason == "payment_failed" then return notify(locale("payment_failed", Config.Ped.name), "error") end
  local key = type(reason) == "string" and reason or "failed"
  local text = locale(key)
  notify(text == key and locale("failed") or text, "error")
end

local function drawText2D(text, y)
  SetTextFont(4)
  SetTextScale(0.5, 0.5)
  SetTextColour(255, 255, 255, 255)
  SetTextEdge(2, 0, 0, 0, 150)
  SetTextOutline()
  SetTextCentre(true)
  BeginTextCommandDisplayText("STRING")
  AddTextComponentSubstringPlayerName(text)
  EndTextCommandDisplayText(0.5, y)
end

local function setBlipName(blip, text)
  BeginTextCommandSetBlipName("STRING")
  AddTextComponentSubstringPlayerName(text)
  EndTextCommandSetBlipName(blip)
end

local function removeBlip(blip)
  if blip and DoesBlipExist(blip) then RemoveBlip(blip) end
end

local function deleteEntity(entity)
  if entity and DoesEntityExist(entity) then DeleteEntity(entity) end
end

--- Loads a model (pcall: lib.requestModel throws on a bad model or timeout). Returns the hash or nil.
local function loadModel(model)
  local hash = type(model) == "number" and model or joaat(model)
  local ok, err = pcall(lib.requestModel, hash, 10000)
  if not ok then
    Debug("error", "Model '%s' could not be loaded: %s", tostring(model), tostring(err))
    return nil
  end
  return hash
end

--- Plays an animation on the player (pcall: lib.requestAnimDict throws). Returns true when it plays.
local function playAnim(dict, clip, flag)
  local ok, err = pcall(lib.requestAnimDict, dict, 5000)
  if not ok then
    Debug("error", "Animation '%s' could not be loaded: %s", dict, tostring(err))
    return false
  end
  TaskPlayAnim(PlayerPedId(), dict, clip, 8.0, -8.0, -1, flag, 0, false, false, false)
  RemoveAnimDict(dict)
  return true
end

local function playerCoords()
  return GetEntityCoords(PlayerPedId())
end

-------------------------------------------------------------------------------------------------------------------
-- Quest vehicles (spawned by the server; the client only knows their net ids)
-------------------------------------------------------------------------------------------------------------------

--- The local handle of a quest vehicle, nil when it doesn't exist here (not spawned, out of scope, deleted)
local function vehicleEntity(current, name)
  local netId = current.netIds[name]
  if not netId or not NetworkDoesNetworkIdExist(netId) then return nil end
  local vehicle = NetToEnt(netId)
  if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return nil end
  return vehicle
end

local function inVehicle(current, name)
  local vehicle = vehicleEntity(current, name)
  return vehicle ~= nil and cache.vehicle == vehicle
end

--- Asks the server for a vehicle that spawns near its spot (or a replacement when it was destroyed)
local function requestVehicle(current, name)
  local now = GetGameTimer()
  if (current.vehicleRequests[name] or 0) + VEHICLE_REQUEST_INTERVAL > now then return end
  current.vehicleRequests[name] = now
  CreateThread(function()
    local ok, netId = awaitServer(RESOURCE .. ":server:vehicle", name)
    if quest ~= current or not ok then return end
    current.netIds[name] = tonumber(netId)
  end)
end

--- True when the truck pulls the quest's trailer (or any trailer, when the game can't tell which)
local function trailerHooked(current, stop)
  local truck = vehicleEntity(current, stop.vehicle)
  if not truck or not IsVehicleAttachedToTrailer(truck) then return false end
  local trailer = vehicleEntity(current, stop.trailer)
  local hasTrailer, attached = GetVehicleTrailerVehicle(truck)
  return not trailer or not hasTrailer or attached == trailer
end

-------------------------------------------------------------------------------------------------------------------
-- Quest
-------------------------------------------------------------------------------------------------------------------

local function boxId(index) return "box:" .. index end
local function taskId(index) return "task:" .. index end

--- Removes the box from the player's hands
local function dropCarry(current)
  if not current.carrying then return end
  current.carrying = nil
  local prop = current.carryProp
  current.carryProp = nil
  if prop and DoesEntityExist(prop) then
    DetachEntity(prop, true, false)
    DeleteEntity(prop)
  end
  ClearPedTasks(PlayerPedId())
end

--- Removes everything a quest put in the world. Safe to call more than once.
local function endQuest()
  local current = quest
  if not current then return end
  quest = nil
  if current.busy then pcall(lib.cancelProgress) end
  dropCarry(current)
  for _, blip in pairs(current.blips) do removeBlip(blip) end
  removeBlip(current.areaBlip)
  for index, prop in pairs(current.boxes) do
    deleteEntity(prop)
    Interact.remove(boxId(index))
  end
  for index in pairs(current.tasks) do Interact.remove(taskId(index)) end
  Interact.hideText(STOP_TEXT)
end

local function cancelQuest()
  if not quest then return end
  TriggerServerEvent(RESOURCE .. ":server:cancel")
  endQuest()
end

--- Done / total of the stops of one type
local function progressOf(current, stopType)
  local done, total = 0, 0
  for index, stop in ipairs(current.def.stops) do
    if stop.type == stopType then
      total = total + 1
      if current.done[index] then done = done + 1 end
    end
  end
  return done, total
end

--- The stops of the current group, nil when every stop is done
local function currentStops(current)
  local group = GetCurrentGroup(current.def, current.done)
  if not group then return nil end
  local list = {}
  for index, stop in ipairs(current.def.stops) do
    if not current.done[index] and stop.group == group then list[#list + 1] = stop end
  end
  return list
end

--- Vehicles that unfinished stops still use (only those are requested from the server)
local function vehiclesInUse(current)
  local used = {}
  for index, stop in ipairs(current.def.stops) do
    if not current.done[index] then
      if stop.vehicle then used[stop.vehicle] = true end
      if stop.trailer then used[stop.trailer] = true end
      if stop.target then used[stop.target] = true end
    end
  end
  return used
end

local function markDone(current, stop)
  current.done[stop.index] = true
  if not GetCurrentGroup(current.def, current.done) then notify(locale("all_done", Config.Ped.name)) end
end

--- Detaches the trailer and tells the player to bring the truck back
local function onDelivered(current, stop)
  local truck = vehicleEntity(current, stop.vehicle)
  if truck then DetachVehicleFromTrailer(truck) end
  notify(locale("delivered", current.def.vehicles[stop.trailer].label), "success")
end

--- Gets out of the quest vehicle before it is handed back
local function leaveVehicle(current)
  local vehicle = cache.vehicle
  if not vehicle then return end
  TaskLeaveVehicle(PlayerPedId(), vehicle, 0)
  local deadline = GetGameTimer() + LEAVE_TIMEOUT
  while IsPedInVehicle(PlayerPedId(), vehicle, false) and GetGameTimer() < deadline and quest == current do Wait(100) end
end

--- [E] at a vehicle stop: deliver the trailer or hand the vehicle back
local function runVehicleStop(current, stop)
  if stop.type == "deliver" and not trailerHooked(current, stop) then
    return notify(locale("need_trailer", current.def.vehicles[stop.trailer].label), "error")
  end
  if stop.type == "return" then leaveVehicle(current) end
  if quest ~= current then return end
  local ok, result = awaitServer(RESOURCE .. ":server:complete", stop.index)
  if quest ~= current then return end
  if ok == nil then return notify(locale("server_no_response"), "error") end
  if not ok then
    notifyReason(result, current.def, stop)
    if result == "no_quest" or result == "expired" then endQuest() end
    return
  end
  if stop.type == "deliver" then
    onDelivered(current, stop)
  else
    notify(locale("returned", current.def.vehicles[stop.vehicle].label), "success")
  end
  markDone(current, stop)
end

--- A timed stop: the server starts the timer, the progress bar runs, the server checks the time
--- @return boolean finished, any result
local function runTimed(current, stop, progress)
  local ok, reason = awaitServer(RESOURCE .. ":server:begin", stop.index)
  if quest ~= current then return false end
  if ok == nil then notify(locale("server_no_response"), "error") return false end
  if not ok then notifyReason(reason, current.def, stop) return false end

  local okBar, finished = pcall(lib.progressBar, progress)
  ClearPedTasks(PlayerPedId())
  if quest ~= current then return false end
  if not okBar then Debug("error", "Progress failed: %s", tostring(finished)) return false end
  if not finished then return false end

  local done, result = awaitServer(RESOURCE .. ":server:complete", stop.index)
  if quest ~= current then return false end
  if done == nil then notify(locale("server_no_response"), "error") return false end
  if not done then
    notifyReason(result, current.def, stop)
    if result == "no_quest" or result == "expired" then endQuest() end
    return false
  end
  return true, result
end

local function pickupBox(current, stop)
  local finished = runTimed(current, stop, {
    duration = stop.duration,
    label = locale("progress_carry"),
    useWhileDead = false,
    canCancel = true,
    disable = { move = true, car = true, combat = true },
    anim = { dict = PICKUP_DICT, clip = PICKUP_CLIP, flag = 1 },
  })
  if not finished then return end
  local index = stop.index
  deleteEntity(current.boxes[index])
  current.boxes[index] = nil
  Interact.remove(boxId(index))
  current.carrying = index

  local hash = loadModel(CARRY_PROP)
  if hash and quest == current and current.carrying == index then
    local playerPed = PlayerPedId()
    local pos = GetEntityCoords(playerPed)
    local prop = CreateObject(hash, pos.x, pos.y, pos.z + 0.2, false, false, false)
    SetModelAsNoLongerNeeded(hash)
    AttachEntityToEntity(prop, playerPed, GetPedBoneIndex(playerPed, 60309), 0.025, 0.08, 0.255, -145.0, 290.0, 0.0,
      true, true, false, true, 1, true)
    current.carryProp = prop
  end
  if quest ~= current or current.carrying ~= index then return end
  playAnim(CARRY_DICT, CARRY_CLIP, 51)
  notify(locale("picked_box", current.def.vehicles[stop.vehicle].label))
end

local function loadBox(current, stop)
  local ok, done, total = awaitServer(RESOURCE .. ":server:load", stop.index)
  if quest ~= current then return end
  if ok == nil then return notify(locale("server_no_response"), "error") end
  if not ok then
    notifyReason(done, current.def, stop)
    if done == "no_quest" or done == "expired" then endQuest() end
    if done == "not_carrying" then dropCarry(current) end
    return
  end
  dropCarry(current)
  notify(locale("loaded", tonumber(done) or 0, tonumber(total) or 0), "success")
  markDone(current, stop)
end

local function doTask(current, stop)
  if stop.heading then SetEntityHeading(PlayerPedId(), stop.heading) end
  local finished = runTimed(current, stop, {
    duration = stop.duration,
    label = textOr("progress_" .. stop.action, locale("progress_clean")),
    useWhileDead = false,
    canCancel = true,
    disable = { move = true, car = true, combat = true },
    anim = stop.scenario and { scenario = stop.scenario } or nil,
  })
  if not finished then return end
  markDone(current, stop)
  local done, total = progressOf(current, "task")
  notify(locale("task_done", done, total), "success")
end

--- Runs one interaction of the quest; only one at a time
local function handle(current, fn, ...)
  if current.busy then return end
  current.busy = true
  Interact.hideText(STOP_TEXT)
  local ok, err = pcall(fn, current, ...)
  if not ok then Debug("error", "Quest step failed: %s", tostring(err)) end
  current.busy = false
end

--- Starts and finishes scrapping on its own while the player rams the vehicle with the right one
local function scrapStep(current, stop)
  local now = GetGameTimer()
  if current.scrapPending or now < current.nextScrap then return end
  local bulldozer = vehicleEntity(current, stop.vehicle)
  local target = vehicleEntity(current, stop.target)
  local inPlace = bulldozer and target and cache.vehicle == bulldozer
      and #(GetEntityCoords(bulldozer) - GetEntityCoords(target)) <= stop.radius
  if not inPlace then
    current.scrapBegun = false
    return
  end
  if current.scrapBegun and GetVehicleBodyHealth(target) >= stop.bodyHealth then return end
  current.scrapPending = true
  CreateThread(function()
    local ok, result = awaitServer(RESOURCE .. ":server:" .. (current.scrapBegun and "complete" or "begin"), stop.index)
    current.scrapPending = false
    if quest ~= current then return end
    current.nextScrap = GetGameTimer() + SCRAP_RETRY
    if not ok then
      if ok == false and result ~= "not_scrapped" and result ~= "too_fast" then
        current.scrapBegun = false
        if result == "no_quest" or result == "expired" then
          notifyReason(result)
          endQuest()
        end
      end
      return
    end
    if not current.scrapBegun then
      current.scrapBegun = true
      return
    end
    notify(locale("scrapped"), "success")
    markDone(current, stop)
  end)
end

--- Adds, moves and removes the quest's blips. wanted[key] = { coords = vector3 | entity = handle, label, route, sprite }
local function setBlips(current, wanted)
  for key, blip in pairs(current.blips) do
    local want = wanted[key]
    local stale = not DoesBlipExist(blip)
    if not want or stale or (want.entity and current.blipEntity[key] ~= want.entity) then
      removeBlip(blip)
      current.blips[key], current.blipEntity[key] = nil, nil
    end
  end
  for key, want in pairs(wanted) do
    if not current.blips[key] then
      local blip
      if want.entity then
        blip = AddBlipForEntity(want.entity)
        current.blipEntity[key] = want.entity
      else
        blip = AddBlipForCoord(want.coords.x, want.coords.y, want.coords.z)
      end
      if want.sprite then SetBlipSprite(blip, want.sprite) end
      SetBlipColour(blip, BLIP_COLOUR)
      setBlipName(blip, want.label)
      if want.route then
        SetBlipRoute(blip, true)
        SetBlipRouteColour(blip, BLIP_COLOUR)
      end
      current.blips[key] = blip
    end
  end
end

--- Blip for a quest vehicle: on the vehicle when it exists here, otherwise where it was last seen (or spawns)
local function vehicleBlip(current, name, route)
  local vehicle = current.def.vehicles[name]
  local entity = vehicleEntity(current, name)
  if entity and not IsEntityDead(entity) then
    return { entity = entity, label = vehicle.label, route = route, sprite = vehicle.sprite }
  end
  return { coords = current.lastSeen[name] or vehicle.position, label = vehicle.label, route = route, sprite = vehicle.sprite }
end

--- Box props and their interactions, while the player is close and the box isn't done or carried
local function updateBoxes(current, stops, pos)
  for _, stop in ipairs(current.def.stops) do
    if stop.type == "carry" then
      local index = stop.index
      local wanted = stops and not current.done[index] and current.carrying ~= index and stop.group == stops[1].group
          and #(pos - stop.coords) <= PED_SPAWN_DISTANCE
      if not wanted then
        if current.boxes[index] ~= nil then
          deleteEntity(current.boxes[index])
          current.boxes[index] = nil
          Interact.remove(boxId(index))
        end
      elseif current.boxes[index] == nil then
        current.boxes[index] = false -- spawning
        CreateThread(function()
          local prop
          local hash = stop.prop and loadModel(stop.prop)
          if hash and quest == current and current.boxes[index] == false then
            local c = stop.coords
            prop = CreateObject(hash, c.x, c.y, c.z, false, false, false)
            SetModelAsNoLongerNeeded(hash)
            FreezeEntityPosition(prop, true)
          end
          if quest ~= current or current.boxes[index] ~= false then return deleteEntity(prop) end
          current.boxes[index] = prop or 0
          local c = stop.coords
          Interact.add(boxId(index), {
            coords = vector3(c.x, c.y, c.z + 0.4),
            distance = GetInteractDistance(),
            size = 0.8,
            label = locale("box_label"),
            icon = "fa-solid fa-box",
            text = locale("box_textui"),
            canInteract = function()
              return quest == current and not current.busy and not current.carrying and not current.done[index]
                  and not cache.vehicle
            end,
            onSelect = function() CreateThread(function() handle(current, pickupBox, stop) end) end,
          })
        end)
      end
    end
  end
end

--- Interactions of the cleaning spots of the current group while the player is close
local function updateTasks(current, stops, pos)
  for _, stop in ipairs(current.def.stops) do
    if stop.type == "task" then
      local index = stop.index
      local wanted = stops and not current.done[index] and stop.group == stops[1].group
          and #(pos - stop.coords) <= PED_SPAWN_DISTANCE
      if not wanted and current.tasks[index] then
        current.tasks[index] = nil
        Interact.remove(taskId(index))
      elseif wanted and not current.tasks[index] then
        current.tasks[index] = true
        local label = textOr("task_" .. stop.action, stop.action)
        Interact.add(taskId(index), {
          coords = stop.coords,
          distance = GetInteractDistance(),
          size = 1.0,
          label = label,
          icon = "fa-solid fa-broom",
          text = locale("task_textui", label),
          canInteract = function() return quest == current and not current.busy and not current.done[index] end,
          onSelect = function() CreateThread(function() handle(current, doTask, stop) end) end,
        })
      end
    end
  end
end

--- Blips, hint, props, interactions and vehicle requests (every SLOW_TICK ms)
local function update(current)
  local def = current.def
  local pos = playerCoords()
  local wanted = {}

  -- remember where the quest vehicles are, and that the player got in
  for name in pairs(def.vehicles) do
    local vehicle = vehicleEntity(current, name)
    if vehicle then
      current.lastSeen[name] = GetEntityCoords(vehicle)
      if cache.vehicle == vehicle then current.entered[name] = true end
    end
  end

  -- a box can't be carried into a vehicle or through death
  if current.carrying and (cache.vehicle or IsEntityDead(PlayerPedId())) then
    dropCarry(current)
    notify(locale("dropped_box"), "error")
  elseif current.carrying and not current.busy and not IsEntityPlayingAnim(PlayerPedId(), CARRY_DICT, CARRY_CLIP, 3) then
    playAnim(CARRY_DICT, CARRY_CLIP, 51)
  end

  -- vehicles that spawn near their spot (or were destroyed) are asked for when the player is close
  for name in pairs(vehiclesInUse(current)) do
    local vehicle = def.vehicles[name]
    local entity = vehicleEntity(current, name)
    if (not entity or IsEntityDead(entity)) and #(pos - vehicle.position) <= (vehicle.spawnDistance or PED_SPAWN_DISTANCE) then
      requestVehicle(current, name)
    end
  end

  local stops = currentStops(current)
  current.stops = stops
  updateBoxes(current, stops, pos)
  updateTasks(current, stops, pos)
  if not stops then
    wanted.ped = { coords = Config.Ped.position, label = Config.Ped.name, route = true }
    current.hint = locale("hint_ped", Config.Ped.name)
    return setBlips(current, wanted)
  end

  local first = stops[1]
  if first.type == "deliver" then
    if not inVehicle(current, first.vehicle) then
      wanted["vehicle:" .. first.vehicle] = vehicleBlip(current, first.vehicle, true)
      current.hint = locale("hint_vehicle", def.vehicles[first.vehicle].label)
    elseif not trailerHooked(current, first) then
      wanted["vehicle:" .. first.trailer] = vehicleBlip(current, first.trailer, true)
      current.hint = locale("hint_trailer", def.vehicles[first.trailer].label)
    else
      wanted["stop:" .. first.index] = { coords = first.coords, label = locale("blip_stop"), route = true }
      current.hint = locale("hint_deliver", def.vehicles[first.trailer].label)
    end
  elseif first.type == "return" then
    wanted["stop:" .. first.index] = { coords = first.coords, label = locale("blip_return"), route = true }
    current.hint = locale("hint_return", def.vehicles[first.vehicle].label)
  elseif first.type == "carry" then
    local van = def.vehicles[first.vehicle]
    if current.carrying then
      wanted["vehicle:" .. first.vehicle] = vehicleBlip(current, first.vehicle, true)
      current.hint = locale("hint_load", van.label)
    else
      local closest, closestDistance = nil, math.huge
      for _, stop in ipairs(stops) do
        local distance = #(pos - stop.coords)
        if distance < closestDistance then closest, closestDistance = stop, distance end
      end
      for _, stop in ipairs(stops) do
        wanted["stop:" .. stop.index] = { coords = stop.coords, label = locale("blip_box"), route = stop == closest, sprite = 478 }
      end
      if not current.entered[first.vehicle] and not inVehicle(current, first.vehicle) then
        current.hint = locale("hint_vehicle", van.label)
      else
        local done, total = progressOf(current, "carry")
        current.hint = locale("hint_carry", van.label, done, total)
      end
    end
  elseif first.type == "scrap" then
    local target = def.vehicles[first.target]
    if not inVehicle(current, first.vehicle) then
      wanted["vehicle:" .. first.vehicle] = vehicleBlip(current, first.vehicle, true)
      current.hint = locale("hint_vehicle", def.vehicles[first.vehicle].label)
    else
      wanted["vehicle:" .. first.target] = vehicleBlip(current, first.target, true)
      current.hint = locale("hint_scrap", target.label, def.vehicles[first.vehicle].label)
    end
    scrapStep(current, first)
  elseif first.type == "task" then
    local area = def.area
    if area and #(pos - area.coords) > area.radius then
      wanted.area = { coords = area.coords, label = locale("blip_area"), route = true }
    end
    local done, total = progressOf(current, "task")
    current.hint = locale("hint_task", done, total)
  end

  -- vehicles that wait at Philip: marked until the player got in once (unless the stop marks them already)
  for name, vehicle in pairs(def.vehicles) do
    local entity = not vehicle.spawnDistance and not current.entered[name] and not wanted["vehicle:" .. name]
        and vehicleEntity(current, name)
    if entity and not cache.vehicle and vehicle.type ~= "trailer" then
      wanted["start:" .. name] = { entity = entity, label = vehicle.label, sprite = vehicle.sprite }
    end
  end
  setBlips(current, wanted)
end

local function drawMarker(stop, inside)
  local c = stop.coords
  local r, g = inside and 0 or 255, inside and 255 or 0
  if stop.type == "return" then
    DrawMarker(39, c.x, c.y, c.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, r, g, 0, 100, false, true, 2, false, nil, nil, false)
  else
    DrawMarker(28, c.x, c.y, c.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, stop.radius, stop.radius, stop.radius,
      r, g, 0, 50, false, false, 2, false, nil, nil, false)
  end
end

local function pressed()
  if IsControlJustReleased(0, KEY_E) and GetGameTimer() - lastPress > 500 then
    lastPress = GetGameTimer()
    return true
  end
  return false
end

--- [E] next to the quest vehicle while carrying a box: open the trunk, then load the box
local function loadPrompt(current, stops)
  if not current.carrying then return nil end
  local stop = current.def.stops[current.carrying]
  local van = vehicleEntity(current, stop.vehicle)
  if not van or cache.vehicle or #(playerCoords() - GetEntityCoords(van)) > LOAD_DISTANCE then return nil end
  if not current.trunkOpen then
    return locale("prompt_open_trunk"), function()
      SetVehicleDoorOpen(van, TRUNK_DOOR, false, false)
      current.trunkOpen = true
    end
  end
  return locale("prompt_load", current.def.vehicles[stop.vehicle].label), function()
    CreateThread(function() handle(current, loadBox, stop) end)
  end
end

--- Markers and the [E] prompts of the vehicle stops, and the hint (every frame while a quest runs)
local function frame(current)
  if Config.ShowHints ~= false and current.hint then drawText2D(current.hint, 0.93) end
  local stops = current.stops
  if not stops or current.busy then return Interact.hideText(STOP_TEXT) end

  local text, action = loadPrompt(current, stops)
  if not text then
    local pos = playerCoords()
    for _, stop in ipairs(stops) do
      if stop.type == "deliver" or stop.type == "return" then
        local distance = #(pos - stop.coords)
        if distance <= MARKER_DISTANCE then
          local inside = distance <= stop.radius and (stop.type == "return" or inVehicle(current, stop.vehicle))
          drawMarker(stop, inside)
          if inside and not text then
            local label = current.def.vehicles[stop.type == "deliver" and stop.trailer or stop.vehicle].label
            text = locale(stop.type == "deliver" and "prompt_deliver" or "prompt_return", label)
            action = function() CreateThread(function() handle(current, runVehicleStop, stop) end) end
          end
        end
      end
    end
  end
  if not text then return Interact.hideText(STOP_TEXT) end
  Interact.showText(STOP_TEXT, text)
  if pressed() then action() end
end

local function runQuest(current)
  local nextUpdate = 0
  while quest == current do
    if GetGameTimer() >= nextUpdate then
      nextUpdate = GetGameTimer() + SLOW_TICK
      local ok, err = pcall(update, current)
      if not ok then Debug("error", "Quest update failed: %s", tostring(err)) end
    end
    local ok, err = pcall(frame, current)
    if not ok then Debug("error", "Quest frame failed: %s", tostring(err)) end
    Wait(0)
  end
end

local function beginQuest(def, netIds)
  local current = {
    def = def,
    done = {},
    netIds = {},
    vehicleRequests = {},
    lastSeen = {},
    entered = {},
    blips = {},
    blipEntity = {},
    boxes = {},
    tasks = {},
    nextScrap = 0,
  }
  for name, netId in pairs(type(netIds) == "table" and netIds or {}) do
    if def.vehicles[name] then current.netIds[name] = tonumber(netId) end
  end
  if def.area then
    local a = def.area
    current.areaBlip = AddBlipForRadius(a.coords.x, a.coords.y, a.coords.z, a.radius)
    SetBlipColour(current.areaBlip, BLIP_COLOUR)
    SetBlipAlpha(current.areaBlip, 100)
  end
  quest = current
  CreateThread(function() runQuest(current) end)
  CreateThread(function()
    for i = 1, 4 do
      local key = ("dialog_%s_%d"):format(def.id, i)
      local text = locale(key)
      if quest ~= current or text == key then return end
      notify(text)
      Wait(3000)
    end
  end)
end

-------------------------------------------------------------------------------------------------------------------
-- Philip
-------------------------------------------------------------------------------------------------------------------

local function startQuest(def)
  if quest then return notify(locale("busy"), "error") end
  local ok, result, extra = awaitServer(RESOURCE .. ":server:start", def.id)
  if ok == nil then return notify(locale("server_no_response"), "error") end
  if not ok then return notifyReason(result, def, nil, extra) end
  beginQuest(def, result)
end

local function openMenu()
  local options = {}
  for _, id in ipairs(GetQuestIds()) do
    local def = GetQuest(id)
    options[#options + 1] = {
      title = questLabel(def),
      description = ("%s %s"):format(questDescription(def), locale("menu_reward", def.reward.min, def.reward.max)),
      icon = "fa-solid fa-briefcase",
      onSelect = function()
        CreateThread(function()
          if requesting then return end
          requesting = true
          local ok, err = pcall(startQuest, def)
          requesting = false
          if not ok then
            Debug("error", "Starting a quest failed: %s", tostring(err))
            notify(locale("server_no_response"), "error")
          end
        end)
      end,
    }
  end
  local id = RESOURCE .. ":menu"
  lib.registerContext({ id = id, title = locale("menu_title", Config.Ped.name), options = options })
  lib.showContext(id)
end

local function deliver(current)
  local ok, result = awaitServer(RESOURCE .. ":server:finish")
  if quest ~= current then return end
  if ok == nil then return notify(locale("server_no_response"), "error") end
  if not ok then
    notifyReason(result, current.def)
    if result == "no_quest" or result == "expired" then endQuest() end
    return
  end
  notify(locale("rewarded", tonumber(result) or 0), "success")
  endQuest()
end

local function askCancel(current)
  local answer = lib.alertDialog({
    header = locale("not_finished_header", Config.Ped.name),
    content = locale("not_finished_content"),
    centered = true,
    cancel = true,
  })
  if answer == "confirm" and quest == current then
    cancelQuest()
    notify(locale("cancelled"))
  end
end

local function talkToPed()
  if requesting then return end
  if not IsFrameworkReady() or not playerLoaded() then return notify(locale("not_ready"), "error") end
  local current = quest
  if not current then return openMenu() end
  if current.busy then return end
  requesting = true
  local ok, err = pcall(GetCurrentGroup(current.def, current.done) and askCancel or deliver, current)
  requesting = false
  if not ok then
    Debug("error", "Talking to %s failed: %s", Config.Ped.name, tostring(err))
    notify(locale("server_no_response"), "error")
  end
end

local function deletePed()
  if not ped then return end
  deleteEntity(ped.entity)
  ped.entity = nil
end

local function spawnPed()
  if not ped or (ped.entity and DoesEntityExist(ped.entity)) then return end
  local def = Config.Ped
  local hash = loadModel(def.model)
  if not hash then return end
  -- the player may have walked away while the model loaded
  if not ped.near or (ped.entity and DoesEntityExist(ped.entity)) then
    SetModelAsNoLongerNeeded(hash)
    return
  end
  local c = def.position
  local entity = CreatePed(4, hash, c.x, c.y, c.z, def.heading, false, false)
  SetModelAsNoLongerNeeded(hash)
  FreezeEntityPosition(entity, true)
  SetEntityInvincible(entity, true)
  SetBlockingOfNonTemporaryEvents(entity, true)
  SetPedCanRagdoll(entity, false)
  ped.entity = entity
  if def.anim then
    local ok, err = pcall(lib.requestAnimDict, def.anim.dict, 5000)
    if not ok then return Debug("error", "%s's animation could not be loaded: %s", def.name, tostring(err)) end
    if not DoesEntityExist(entity) then return end
    TaskPlayAnim(entity, def.anim.dict, def.anim.clip, 8.0, -8.0, -1, 1, 0, false, false, false)
    RemoveAnimDict(def.anim.dict)
  end
end

local function setupPed()
  local def = Config.Ped
  if not def then return end
  ped = {}
  local c = def.position
  ped.point = lib.points.new({
    coords = c,
    distance = PED_SPAWN_DISTANCE,
    onEnter = function()
      ped.near = true
      CreateThread(spawnPed)
    end,
    onExit = function()
      ped.near = false
      deletePed()
    end,
  })
  Interact.add("ped", {
    coords = vector3(c.x, c.y, c.z + 1.0),
    distance = GetInteractDistance(),
    size = 1.0,
    label = locale("talk_label", def.name),
    icon = "fa-solid fa-comments",
    text = locale("talk_textui", def.name),
    canInteract = function() return not requesting and not (quest and quest.busy) and playerLoaded() end,
    onSelect = function() CreateThread(talkToPed) end,
  })
  local blip = def.blip
  if blip then
    ped.blip = AddBlipForCoord(c.x, c.y, c.z)
    SetBlipSprite(ped.blip, tonumber(blip.sprite) or 351)
    SetBlipColour(ped.blip, tonumber(blip.colour) or 49)
    SetBlipScale(ped.blip, (tonumber(blip.scale) or 1.2) + 0.0)
    SetBlipAsShortRange(ped.blip, true)
    setBlipName(ped.blip, type(blip.label) == "string" and blip.label or locale("blip_ped"))
  end
end

-- The server ended the quest (Config.MaxDuration)
RegisterNetEvent(RESOURCE .. ":client:ended", function(reason)
  if not quest then return end
  endQuest()
  if reason == "expired" then notify(locale("expired"), "error") end
end)

OnEnvironmentReady(function()
  local ok, err = pcall(setupPed)
  if not ok then Log("error", ("The quest giver could not be set up: %s"):format(tostring(err))) end
end)

AddEventHandler("onResourceStop", function(resource)
  if resource ~= RESOURCE then return end
  if lib.getOpenContextMenu() == RESOURCE .. ":menu" then pcall(lib.hideContext) end
  if requesting then pcall(lib.closeAlertDialog) end
  endQuest()
  if ped then
    deletePed()
    removeBlip(ped.blip)
    if ped.point then ped.point:remove() end
  end
  Interact.removeAll()
end)
