-- Runs once force_quests knows the framework is "esx" (Config.Framework, or detected by the server).
-- Keep your code inside this function.
RegisterFramework("esx", function()
  local ESX
  local resource = GetFrameworkResource() or "es_extended"
  -- Loaded again when es_extended restarts: the old shared object points at the stopped resource
  LoadFrameworkObject(resource, function()
    return exports[resource]:getSharedObject()
  end, function(obj)
    ESX = obj
  end)

  local function getPlayer(source)
    return ESX and ESX.GetPlayerFromId(source)
  end

  --- Character identifier (a quest and its cooldown belong to this character), nil while no character is loaded
  --- @param source number
  --- @return string|nil
  function GetIdentifier(source)
    local xPlayer = getPlayer(source)
    return xPlayer and xPlayer.identifier or nil
  end

  -- Config quest account -> ESX account
  local ACCOUNTS = { cash = "money", bank = "bank" }

  --- Pays the quest reward. Return true only when the money was added.
  --- @param account "cash"|"bank"
  --- @return boolean
  function AddMoney(source, account, amount)
    local xPlayer = getPlayer(source)
    local name = ACCOUNTS[account]
    if not xPlayer or not name or not xPlayer.getAccount(name) then return false end
    xPlayer.addAccountMoney(name, amount, "Quick job")
    return true
  end

  --- ESX has no vehicle keys by default. Add your key resource here (Config.GiveKeys).
  function GiveVehicleKeys(source, vehicle, plate)
  end
end)
