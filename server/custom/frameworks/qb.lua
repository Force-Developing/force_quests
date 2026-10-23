-- Runs once force_quests knows the framework is "qb" (Config.Framework, or detected by the server).
-- Keep your code inside this function.
RegisterFramework("qb", function()
  local QBCore
  local resource = GetFrameworkResource() or "qb-core"
  -- Loaded again when qb-core restarts: the old core object points at the stopped resource
  LoadFrameworkObject(resource, function()
    return exports[resource]:GetCoreObject()
  end, function(obj)
    QBCore = obj
  end)

  local function getPlayer(source)
    return QBCore and QBCore.Functions.GetPlayer(source)
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

  --- qb-vehiclekeys (Config.GiveKeys)
  function GiveVehicleKeys(source, vehicle, plate)
    if GetResourceState("qb-vehiclekeys") ~= "started" then return end
    TriggerClientEvent("vehiclekeys:client:SetOwner", source, plate)
  end
end)
