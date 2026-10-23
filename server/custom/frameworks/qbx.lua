-- Runs once force_quests knows the framework is "qbx" (Config.Framework, or detected by the server).
-- Keep your code inside this function.
RegisterFramework("qbx", function()
  local function getPlayer(source)
    if GetResourceState("qbx_core") ~= "started" then return nil end
    local ok, player = pcall(function() return exports.qbx_core:GetPlayer(source) end)
    return ok and player or nil
  end

  --- Citizen id (a quest and its cooldown belong to this character), nil while no character is loaded
  --- @param source number
  --- @return string|nil
  function GetIdentifier(source)
    local player = getPlayer(source)
    return player and player.PlayerData and player.PlayerData.citizenid or nil
  end

  --- Pays the quest reward. Return true only when the money was added.
  --- @param account "cash"|"bank"
  --- @return boolean
  function AddMoney(source, account, amount)
    local player = getPlayer(source)
    if not player then return false end
    return player.Functions.AddMoney(account, amount, "quick-job") ~= false
  end

  --- qbx_vehiclekeys (Config.GiveKeys)
  function GiveVehicleKeys(source, vehicle, plate)
    if GetResourceState("qbx_vehiclekeys") ~= "started" then return end
    local ok, err = pcall(function() exports.qbx_vehiclekeys:GiveKeys(source, vehicle) end)
    if not ok then Log("error", ("qbx_vehiclekeys GiveKeys failed: %s"):format(tostring(err))) end
  end
end)
