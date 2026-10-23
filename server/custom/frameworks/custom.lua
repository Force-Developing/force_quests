-- Runs once force_quests knows the framework is "custom": Config.Framework = "custom", or "auto" when none
-- of qbx_core, es_extended and qb-core is installed. Keep your code inside this function.
RegisterFramework("custom", function()
  --- TODO: a stable id of the player's character (a quest and its cooldown belong to this id). nil while no
  --- character is loaded: nobody can start a quest until this returns something.
  --- @param source number
  --- @return string|nil
  function GetIdentifier(source)
    return nil
  end

  --- TODO: pay the quest reward. Return true only when the money was added.
  --- @param account "cash"|"bank"
  --- @return boolean
  function AddMoney(source, account, amount)
    return false
  end

  --- Optional: give the player keys for a quest vehicle (Config.GiveKeys).
  function GiveVehicleKeys(source, vehicle, plate)
  end
end)
