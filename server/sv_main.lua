ESX = nil

TriggerEvent('esx:getSharedObject', function(obj) ESX = obj end)

RegisterServerEvent('force_questsDeliverCargoReward')
AddEventHandler('force_questsDeliverCargoReward', function()
    local player = ESX.GetPlayerFromId(source)
    local money = math.random(ConfigDeliverCargo.DeliverCargoMinReward, ConfigDeliverCargo.DeliverCargoMaxReward)

    player.addMoney(money)
    TriggerClientEvent('esx:showNotification', source, 'You got ' .. money .. '$ in reward, welcome back!')
end)

RegisterServerEvent('force_questsPickupBoxesReward')
AddEventHandler('force_questsPickupBoxesReward', function()
    local player = ESX.GetPlayerFromId(source)
    local money = math.random(ConfigPickupBoxes.DeliverCargoMinReward, ConfigPickupBoxes.DeliverCargoMaxReward)

    player.addMoney(money)
    TriggerClientEvent('esx:showNotification', source, 'You got ' .. money .. '$ in reward, welcome back!')
end)

RegisterServerEvent('force_questsTrashCarReward')
AddEventHandler('force_questsTrashCarReward', function()
    local player = ESX.GetPlayerFromId(source)
    local money = math.random(ConfigTrashCar.TrashCarMinReward, ConfigTrashCar.TrashCarMaxReward)

    player.addMoney(money)
    TriggerClientEvent('esx:showNotification', source, 'You got ' .. money .. '$ in reward, welcome back!')
end)

RegisterServerEvent('force_questsCleanReward')
AddEventHandler('force_questsCleanReward', function()
    local player = ESX.GetPlayerFromId(source)
    local money = math.random(ConfigClean.CleanMinReward, ConfigClean.CleanMaxReward)

    player.addMoney(money)
    TriggerClientEvent('esx:showNotification', source, 'You got ' .. money .. '$ in reward, welcome back!')
end)