local display = false

RegisterNUICallback("exit", function(data)
    SetDisplay(false)
end)

RegisterNUICallback("deleiverCargo", function(data)
    SetDisplay(false)
    TriggerEvent('force_questsDeliverCargoDialog')
    TriggerEvent('force_questsDeliverCargo')
end)

RegisterNUICallback("pickupBoxes", function(data)
    SetDisplay(false)
    TriggerEvent('force_questsPickUpBoxes')
    TriggerEvent('force_questsPickUpBoxesDialog')
end)

RegisterNUICallback("trashCar", function(data)
    SetDisplay(false)
    TriggerEvent('force_questsTrashCarDialog')
    TriggerEvent('force_questsTrashCar')
end)

RegisterNUICallback("cleaning", function(data)
    SetDisplay(false)
    TriggerEvent('force_questsCleanDialog')
    TriggerEvent('force_questsCleanQuest')
end)

function SetDisplay(bool)
    display = bool
    SetNuiFocus(bool, bool)
    SendNUIMessage({
        type = "ui",
        status = bool,
    })
end