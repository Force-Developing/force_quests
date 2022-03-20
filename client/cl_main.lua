-- Cargo Quests --
local deleiverCargoIsStarted = false
--Boxes quests --
local pickUpBoxesIsStarted = false
local pickUpPositions 		   = 0

--trash car
local trashCarIsStarted = false

--Clean quest hehe
local cleanQuestIsStarted = false
local cleanPositions = 0

Citizen.CreateThread(function()
    while ESX == nil do
        Citizen.Wait(1);

        ESX = exports["btrp_base"]:getSharedObject()  
    end 

    if ESX.IsPlayerLoaded() then
        ESX.PlayerData = ESX.GetPlayerData()
    end

	local blip = AddBlipForCoord(ConfigDeliverCargo.MainPedPos)

		SetBlipSprite(blip, 351)
		SetBlipDisplay(blip, 4)
		SetBlipScale(blip, 1.2)
		SetBlipColour(blip, 49)
		SetBlipAsShortRange(blip, true)
	
		BeginTextCommandSetBlipName("STRING")
		AddTextComponentString("Quick Jobs")
		EndTextCommandSetBlipName(blip)

	while true do

		local sleepThread = 850

		local player = PlayerPedId()
		local pCoords = GetEntityCoords(player)
		
		local dist1 = #(pCoords - ConfigDeliverCargo.MainPedPos)

		if dist1 <= 50 then
			RequestModel(ConfigDeliverCargo.MainPedModel) while not HasModelLoaded(ConfigDeliverCargo.MainPedModel) do Wait(7) end
			if not DoesEntityExist(mainPed) then
				mainPed = CreatePed(4, ConfigDeliverCargo.MainPedModel, ConfigDeliverCargo.MainPedPos.x, ConfigDeliverCargo.MainPedPos.y, ConfigDeliverCargo.MainPedPos.z - 1.0, ConfigDeliverCargo.MainPedHeading, false, true)
				FreezeEntityPosition(mainPed, true)
				SetBlockingOfNonTemporaryEvents(mainPed, true)
				SetEntityInvincible(mainPed, true)
				ESX.LoadAnimDict("mini@strip_club@idles@bouncer@base")
                TaskPlayAnim(mainPed, 'mini@strip_club@idles@bouncer@base', 'base', 1.0, -1.0, -1, 69, 0, 0, 0, 0)
			end
		end

		if dist1 >= 1.2 and dist1 <= 6 and not deleiverCargoIsStarted and not pickUpBoxesIsStarted and not trashCarIsStarted and not cleanQuestIsStarted then
			sleepThread = 5
			DrawText3Ds(ConfigDeliverCargo.MainPedPos.x, ConfigDeliverCargo.MainPedPos.y, ConfigDeliverCargo.MainPedPos.z+1, 'Philip', 0.4)
		end

		if dist1 <= 1.2 and not deleiverCargoIsStarted and not pickUpBoxesIsStarted and not trashCarIsStarted and not cleanQuestIsStarted then
			sleepThread = 5
			DrawText3Ds(ConfigDeliverCargo.MainPedPos.x, ConfigDeliverCargo.MainPedPos.y, ConfigDeliverCargo.MainPedPos.z+1, '[~g~E~w~] Philip', 0.4)
			if IsControlJustPressed(1, 38) then
				SetDisplay(not display)
			end
		end
		Wait(sleepThread)
	end
end)

RegisterNetEvent('force_questsDeliverCargoDialog')
AddEventHandler('force_questsDeliverCargoDialog', function()
	ESX.ShowNotification('Hello! Get in the truck and connect the trailer to it!')
	Wait(3000)
	ESX.ShowNotification('Then you look at the GPS and you will have a specified position!')
	Wait(3000)
	ESX.ShowNotification('At this position, leave the trailer and then come down here again.')
	Wait(3000)
	ESX.ShowNotification('Good luck!')
end)

RegisterNetEvent('force_questsDeliverCargo')
AddEventHandler('force_questsDeliverCargo', function()
	deleiverCargoIsStarted = true
	while deleiverCargoIsStarted do 
		Wait(5)
		
		local player = PlayerPedId()
		local pCoords = GetEntityCoords(player)


			for _,truck in pairs(ConfigDeliverCargo.MainTruck) do
				if not truck.hasSpawned then
					RequestModel(truck.model) while not HasModelLoaded(truck.model) do Wait(7) end
					truck.name = CreateVehicle(truck.model, truck.x, truck.y, truck.z, truck.h, true, true)
					truck.hasSpawned = true
					showTruckText = true
				end

				if not DoesBlipExist(truckBlip) then
					truckBlip = AddBlipForEntity(truck.name)
					Blip(truckBlip, 'Truck', 477, 46, 0.7)
				end

				if IsPedInVehicle(player, truck.name, false) then
					RemoveBlip(truckBlip)
					showTruckText = false
					if not showTrailerText and not hasDeliveredTrailer then
						DrawMissionText('Put on the trailer!', 0.00, 0.5)
					end
				else
					if showTruckText then
						DrawMissionText('Get in the truck!', 0.00, 0.5)
					end
				end

				if not DoesEntityExist(truck.name) then
					deleiverCargoIsStarted = false
					hasReturnedTruck = false
					hasDeliveredTrailer = false
					showTrailerText = false
					trailer.hasSpawned = false
					truck.hasSpawned = false
					RemoveBlip(deliverPosBlip)
					RemoveBlip(trailerBlip)
					RemoveBlip(truckBlip)
					DeleteVehicle(truck.name)
					DeleteVehicle(trailer.name)
					ESX.ShowNotification('The truck has disappeared and with that the mission ends!')
				end

			for _,trailer in pairs(ConfigDeliverCargo.Trailer) do
				if not trailer.hasSpawned then
					RequestModel(trailer.model) while not HasModelLoaded(trailer.model) do Wait(7) end
					trailer.name = CreateVehicle(trailer.model, trailer.x, trailer.y, trailer.z, trailer.h, true, true)
					trailer.hasSpawned = true
				end

				if not DoesEntityExist(trailer.name) then
					deleiverCargoIsStarted = false
					hasReturnedTruck = false
					hasDeliveredTrailer = false
					showTrailerText = false
					trailer.hasSpawned = false
					truck.hasSpawned = false
					RemoveBlip(deliverPosBlip)
					RemoveBlip(trailerBlip)
					RemoveBlip(truckBlip)
					DeleteVehicle(truck.name)
					DeleteVehicle(trailer.name)
					ESX.ShowNotification('The trailer has disappeared and the mission was canceled!')
				end

				if not DoesBlipExist(trailerBlip) and not hasDeliveredTrailer then
					trailerBlip = AddBlipForEntity(trailer.name)
					Blip(trailerBlip, 'Trailer', 479, 46, 0.7)
				end

				if IsVehicleAttachedToTrailer(truck.name) then
					showTrailerText = true
					RemoveBlip(trailerBlip)

					if not DoesBlipExist(deliverPosBlip) then
						deliverPosBlip = AddBlipForCoord(ConfigDeliverCargo.TrailerDeliverPos)
						BlipDetails(deliverPosBlip, 'Delivery position', 46, true)
					end
				else
					RemoveBlip(deliverPosBlip)
					showTrailerText = false
				end

				local trailerDeliverPos = #(pCoords - ConfigDeliverCargo.TrailerDeliverPos)

				if trailerDeliverPos >= 7.5 and trailerDeliverPos <= 50 and not hasDeliveredTrailer then
					DrawMarker(28, ConfigDeliverCargo.TrailerDeliverPos, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 10.0, 10.0, 10.0, 255, 0, 0, 50, false, true, 2, false, false, false, false)
				end

				if trailerDeliverPos <= 7.5 and not hasDeliveredTrailer then
					DrawMarker(28, ConfigDeliverCargo.TrailerDeliverPos, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 10.0, 10.0, 10.0, 0, 255, 0, 50, false, true, 2, false, false, false, false)
					ESX.ShowHelpNotification('~INPUT_PICKUP~ leave of trailer')
					if IsControlJustPressed(1, 38) then
						if IsVehicleAttachedToTrailer(truck.name) then
							ESX.ShowNotification('You have delivered the trailer, now get back to me and return the vehicle.')
							DetachVehicleFromTrailer(truck.name)
							RemoveBlip(deliverPosBlip)

							if not DoesBlipExist(leaveTruck) then
								leaveTruck = AddBlipForCoord(ConfigDeliverCargo.LeaveTruck)
								BlipDetails(leaveTruck, 'Leave the truck', 46, true)
							end
							
							hasDeliveredTrailer = true
						else
							ESX.ShowNotification('You need to have the trailer connected to the vehicle.')
						end
					end
				end

				local truckLeavePos = #(pCoords - ConfigDeliverCargo.LeaveTruck)

				if truckLeavePos >= 5.0 and truckLeavePos <= 50.0 and not hasReturnedTruck and hasDeliveredTrailer then
					DrawMarker(39, ConfigDeliverCargo.LeaveTruck, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 255, 0, 0, 100, false, true, 2, false, false, false, false)
				end

				if truckLeavePos <= 5.0 and not hasReturnedTruck and hasDeliveredTrailer then
					ESX.ShowHelpNotification('~INPUT_PICKUP~ leave truck')
					DrawMarker(39, ConfigDeliverCargo.LeaveTruck, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 0, 255, 0, 100, false, true, 2, false, false, false, false)
					if IsControlJustPressed(1, 38) then
						FreezeEntityPosition(truck.name, true)
						TaskLeaveVehicle(player, truck.name, 0)
						ESX.ShowNotification('Come to me now and you will get your reward!')
						hasReturnedTruck = true
					end
				end

				local pedDist = #(pCoords - ConfigDeliverCargo.MainPedPos)

				if hasReturnedTruck then
					if pedDist >= 1.2 and pedDist <= 6 then
						DrawText3Ds(ConfigDeliverCargo.MainPedPos.x, ConfigDeliverCargo.MainPedPos.y, ConfigDeliverCargo.MainPedPos.z+1, 'Receive reward', 0.4)
					end
			
					if pedDist <= 1.2 then
						DrawText3Ds(ConfigDeliverCargo.MainPedPos.x, ConfigDeliverCargo.MainPedPos.y, ConfigDeliverCargo.MainPedPos.z+1, '[~g~E~w~] Receive reward', 0.4)
						if IsControlJustPressed(1, 38) then
							TriggerServerEvent('force_questsDeliverCargoReward')
							deleiverCargoIsStarted = false
							hasReturnedTruck = false
							hasDeliveredTrailer = false
							showTrailerText = false
							trailer.hasSpawned = false
							truck.hasSpawned = false
							RemoveBlip(deliverPosBlip)
							RemoveBlip(leaveTruck)
							RemoveBlip(trailerBlip)
							RemoveBlip(truckBlip)
							DeleteVehicle(truck.name)
							DeleteVehicle(trailer.name)
						end
					end
				end
			end
		end
	end
end)

RegisterNetEvent('force_questsPickUpBoxes')
AddEventHandler('force_questsPickUpBoxes', function()
	pickUpBoxesIsStarted = true
	while pickUpBoxesIsStarted do
		Wait(5)

		local player = PlayerPedId()
		local pCoords = GetEntityCoords(player)

		for _,mainVehicle in pairs(ConfigPickupBoxes.MainVehicle) do
			if not mainVehicle.hasSpawned then
				RequestModel(mainVehicle.model) while not HasModelLoaded(mainVehicle.model) do Wait(5) end
				mainVehicle.name = CreateVehicle(mainVehicle.model, mainVehicle.x, mainVehicle.y, mainVehicle.z, mainVehicle.h, true, true)
				mainVehicle.hasSpawned = true
			end

			if not DoesBlipExist(mainVehicleBlip) then
				mainVehicleBlip = AddBlipForEntity(mainVehicle.name)
				Blip(mainVehicleBlip, 'Vehicle', 669, 46, 0.7)
			end

			if IsPedInVehicle(player, mainVehicle.name, false) then
				RemoveBlip(mainVehicleBlip)
				hasBeenInVehicle = true
			else
				if not hasBeenInVehicle then
					DrawMissionText('Get in the vehicle!', 0.00, 0.5)
				end
				if not hasDoneAllBoxes and hasBeenInVehicle then
					DrawMissionText('Number of drawers: ' .. pickUpPositions .. '/' .. ConfigPickupBoxes.pickUpPositions, 0.0, 0.5)
				end
			end

			for _,boxes in pairs(ConfigPickupBoxes.PickUpPos) do

				if not boxesBlipHasSpawned then
					boxesBlip = AddBlipForCoord(boxes.x, boxes.y, boxes.z)
					Blip(boxesBlip, 'Box', 478, 46, 0.7)
					boxesBlipHasSpawned = true
				end

				if not boxesBlipRouteHasSpawned then
					boxesBlipRoute = AddBlipForCoord(boxes.x, boxes.y, boxes.z)
					BlipDetails(boxesBlipRoute, 'Box', 46, true)
					boxesBlipRouteHasSpawned = true
				end

				if GetDistanceBetweenCoords(pCoords, boxes.x, boxes.y, boxes.z) < 50 then
				RequestModel(boxes.objectHash) while not HasModelLoaded(boxes.objectHash) do Wait(7) end
					if not boxes.hasSpawned then
						boxes.objectName = CreateObject(boxes.objectHash, boxes.x, boxes.y, boxes.z, true, true, false)
						FreezeEntityPosition(boxes.objectName, true)
						boxes.hasSpawned = true
					end
				end
				if GetDistanceBetweenCoords(pCoords, boxes.x, boxes.y, boxes.z, true) < 1.5 and not boxes.hasPickedUp and not isCaryingBox then
					ESX.ShowHelpNotification('~INPUT_PICKUP~ Pick up the goods')
					if IsControlJustPressed(1, 38) then
						exports["btrp_progressbar"]:StartDelayedFunction({
							["text"] = "Picks up the box...",
							["delay"] = 5000
						})
						DisableControls = true
						ESX.LoadAnimDict("mini@repair")
						TaskPlayAnim(player, 'mini@repair', 'fixing_a_ped', 1.0, -1.0, 5000, 69, 0, 0, 0, 0)
						FreezeEntityPosition(player, true)
						Wait(5000)
						DisableControls = false
						FreezeEntityPosition(player, false)
						DeleteObject(boxes.objectName)
						boxes.hasPickedUp = true
						pickUpPositions = pickUpPositions + 1
						ESX.ShowNotification('You picked up ' .. pickUpPositions .. '/' .. ConfigPickupBoxes.pickUpPositions .. ' boxes')
						isCaryingBox = true
						hasShownLeaveBox = false
						showMissionText = false
						if pickUpPositions >= ConfigPickupBoxes.pickUpPositions then
							RemoveBlip(boxesBlip)
							RemoveBlip(boxesBlipRoute)
							hasDoneAllBoxes = true
							deliverProducts = true
							Wait(1000)
							ESX.ShowNotification('Now come back to me and get your reward!')
							if not DoesBlipExist(returnToPhilip) then
								returnToPhilip = AddBlipForCoord(ConfigDeliverCargo.MainPedPos)
								BlipDetails(returnToPhilip, 'Philip', 46, true)
							end
						end
					end
				end
				if isCaryingBox then
					local x,y,z = table.unpack(GetEntityCoords(player))
					if not boxHasBeenSpawnedInHand then
						boxProp = CreateObject(GetHashKey('prop_cs_cardbox_01'), x, y, z+0.2,  true,  true, true)
						AttachEntityToEntity(boxProp, player, GetPedBoneIndex(player, 60309), 0.025, 0.08, 0.255, -145.0, 290.0, 0.0, true, true, false, true, 1, true)
						boxHasBeenSpawnedInHand = true
						Wait(250)
					end
					if not hasStartedAnim then
						ESX.LoadAnimDict("anim@heists@box_carry@")
						TaskPlayAnim(player, 'anim@heists@box_carry@', 'idle', 1.0, -1.0, -1, 51, 0, 0, 0, 0)
						ESX.ShowNotification('Get to your vehicle and leave the package there!')
						hasStartedAnim = true
					end
					if not showMissionText then
						DrawMissionText('Leave the drawers in the car!', 0.97, 0.5)
					end
					local mainVehicleCoords = GetEntityCoords(mainVehicle.name)
					if GetDistanceBetweenCoords(pCoords, mainVehicleCoords, true) < 3.0 and not hasShownOpenTrunk then
						if not hasShownOpenTrunk then
							DrawText3Ds(mainVehicleCoords.x, mainVehicleCoords.y, mainVehicleCoords.z+1, '[~g~E~w~] Open luggage', 0.4)
						end
						if IsControlJustPressed(1, 38) then
							SetVehicleDoorOpen(mainVehicle.name, 5, false, true)
							hasShownOpenTrunk = true
							Wait(250)
						end
					end
					if GetDistanceBetweenCoords(pCoords, mainVehicleCoords, true) < 3.0 and hasShownOpenTrunk and not hasShownLeaveBox then
						if not hasShownLeaveBox then
							DrawText3Ds(mainVehicleCoords.x, mainVehicleCoords.y, mainVehicleCoords.z+1, '[~g~E~w~] Leave the box', 0.4)
						end
						if IsControlJustPressed(1, 38) then
							ClearPedTasks(player)
							showMissionText = true
							isCaryingBox = false
							boxHasBeenSpawnedInHand = false
							hasStartedAnim = false
							DeleteObject(boxProp)
							hasShownLeaveBox = true
							showMissionText = false
						end
					end
				end
				if deliverProducts then
					
					local pedDist = #(pCoords - ConfigDeliverCargo.MainPedPos)

					if pedDist >= 1.2 and pedDist <= 6 then
						DrawText3Ds(ConfigDeliverCargo.MainPedPos.x, ConfigDeliverCargo.MainPedPos.y, ConfigDeliverCargo.MainPedPos.z+1, 'Receive reward', 0.4)
					end
			
					if pedDist <= 1.2 then
						DrawText3Ds(ConfigDeliverCargo.MainPedPos.x, ConfigDeliverCargo.MainPedPos.y, ConfigDeliverCargo.MainPedPos.z+1, '[~g~E~w~] Receive reward', 0.4)
						if IsControlJustPressed(1, 38) then
							TriggerServerEvent('force_questsPickupBoxesReward')
							showMissionText = false
							hasShownOpenTrunk = false
							hasStartedAnim = false
							boxHasBeenSpawnedInHand = false
							hasShownLeaveBox = false
							hasDoneAllBoxes = false
							deliverProducts = false
							isCaryingBox = false
							boxes.hasPickedUp = false
							boxes.hasSpawned = false
							hasBeenInVehicle = false
							mainVehicle.hasSpawned = false
							pickUpBoxesIsStarted = false
							boxesBlipRouteHasSpawned = false
							boxesBlipHasSpawned = false
							DeleteVehicle(mainVehicle.name)
							RemoveBlip(returnToPhilip)
						end
					end
				end
			end
		end
	end
end)

RegisterNetEvent('force_questsPickUpBoxesDialog')
AddEventHandler('force_questsPickUpBoxesDialog', function()
	ESX.ShowNotification('Well! Get in the vehicle behind you!')
	Wait(3000)
	ESX.ShowNotification('Then you look at the GPS and you will have a specified position!')
	Wait(3000)
	ESX.ShowNotification('Once you have arrived at this position, you will receive further information.')
	Wait(3000)
	ESX.ShowNotification('Good luck!')
end)

RegisterNetEvent('force_questsTrashCar')
AddEventHandler('force_questsTrashCar', function()
	trashCarIsStarted = true
	while trashCarIsStarted do
		Wait(5)

		local player = PlayerPedId()
		local pCoords = GetEntityCoords(player)

		for _,mainVehicle in pairs(ConfigTrashCar.MainVehicle) do
			if not mainVehicle.hasSpawned then
				RequestModel(mainVehicle.model) while not HasModelLoaded(mainVehicle.model) do Wait(5) end
				mainVehicle.name = CreateVehicle(mainVehicle.model, mainVehicle.x, mainVehicle.y, mainVehicle.z, mainVehicle.h, true, true)
				mainVehicle.hasSpawned = true
			end

			if not DoesBlipExist(mainVehicleBlip) then
				mainVehicleBlip = AddBlipForEntity(mainVehicle.name)
				Blip(mainVehicleBlip, 'Vehicle', 227, 46, 0.7)
			end

			if IsPedInVehicle(player, mainVehicle.name, false) then
				RemoveBlip(mainVehicleBlip)
				hasShownGetInVehicleText = true
				if not showMainMissionText then
					DrawMissionText('Get to your specified position on the GPS!', 0.0, 0.5)
				end
			else
				if not hasShownGetInVehicleText then
					DrawMissionText('Get in the vehicle!', 0.0, 0.5)
				end
			end

			for _,bulldozerVehicle in pairs(ConfigTrashCar.BulldozerVehicle) do
				if not bulldozerVehicle.hasSpawned then
					RequestModel(bulldozerVehicle.model) while not HasModelLoaded(bulldozerVehicle.model) do Wait(5) end
					bulldozerVehicle.name = CreateVehicle(bulldozerVehicle.model, bulldozerVehicle.x, bulldozerVehicle.y, bulldozerVehicle.z, bulldozerVehicle.h, true, true)
					bulldozerVehicle.hasSpawned = true
				end

				if not bulldozerVehicleBlipExist then
					bulldozerVehicleBlip = AddBlipForEntity(bulldozerVehicle.name)
					Blip(bulldozerVehicleBlip, 'Bulldozer', 227, 46, 0.7)
					bulldozerVehicleBlipExist = true
				end
				
				if not bulldozerVehicleBlipRouteExist then
					bulldozerVehicleBlipRoute = AddBlipForCoord(bulldozerVehicle.x, bulldozerVehicle.y, bulldozerVehicle.z)
					BlipDetails(bulldozerVehicleBlipRoute, 'Bulldozer', 46, true)
					bulldozerVehicleBlipRouteExist = true
				end

				for _,trashVehicle in pairs(ConfigTrashCar.TrashVehicle) do
					if not trashVehicle.hasSpawned then
						RequestModel(trashVehicle.model) while not HasModelLoaded(trashVehicle.model) do Wait(5) end
						trashVehicle.name = CreateVehicle(trashVehicle.model, trashVehicle.x, trashVehicle.y, trashVehicle.z, trashVehicle.h, true, true)
						FreezeEntityPosition(trashVehicle.name, true)
						trashVehicle.hasSpawned = true
					end
					if IsPedInVehicle(player, bulldozerVehicle.name, false) then
						RemoveBlip(bulldozerVehicleBlip)
						RemoveBlip(bulldozerVehicleBlipRoute)
						showMainMissionText = true
						if not shownBulldozerHelpText then
							DrawMissionText('Get to the vehicle you are going to scrap!', 0.0, 0.5)
						end
						if not trashVehicleBlipExist then
							trashVehicleBlipRoute = AddBlipForEntity(trashVehicle.name)
							BlipDetails(trashVehicleBlipRoute, 'Scrap vehicles', 46, true)
							trashVehicleBlipExist = true
						end
						if not trashVehicleBlipRouteExist then
							trashVehicleBlip = AddBlipForEntity(trashVehicle.name)
							Blip(trashVehicleBlip, 'Scrap vehicles', 227, 46, 0.7)
							trashVehicleBlipRouteExist = true
						end
					end

					if GetDistanceBetweenCoords(pCoords, trashVehicle.x, trashVehicle.y, trashVehicle.z, true) <= 15 then
						shownBulldozerHelpText = true
						if not shownTrashCarHelpText then
							DrawMissionText('Start scrapping the vehicle!', 0.0, 0.5)
						end
						RemoveBlip(trashVehicleBlipRoute)
						RemoveBlip(trashVehicleBlip)
					end

					if GetVehicleBodyHealth(trashVehicle.name) < 360 then
						shownTrashCarHelpText = true
						if not hasCompletedTrashingCar then
							ESX.ShowNotification("You've finished scrapping the vehicle, now get back to me for your reward!")
							RemoveBlip(trashVehicleBlip)
							RemoveBlip(trashVehicleBlipRoute)
						end
						DrawMissionText('Get back to me!', 0.0, 0.5)
						hasCompletedTrashingCar = true
					end

					if hasCompletedTrashingCar then

						if not DoesBlipExist(returnToPhilip) then
							returnToPhilip = AddBlipForCoord(ConfigDeliverCargo.MainPedPos)
							BlipDetails(returnToPhilip, 'Philip', 46, true)
						end

						local pedDist = #(pCoords - ConfigDeliverCargo.MainPedPos)

						if pedDist >= 1.2 and pedDist <= 6 then
							DrawText3Ds(ConfigDeliverCargo.MainPedPos.x, ConfigDeliverCargo.MainPedPos.y, ConfigDeliverCargo.MainPedPos.z+1, 'Ta emot belöning', 0.4)
						end
				
						if pedDist <= 1.2 then
							DrawText3Ds(ConfigDeliverCargo.MainPedPos.x, ConfigDeliverCargo.MainPedPos.y, ConfigDeliverCargo.MainPedPos.z+1, '[~g~E~w~] Ta emot belöning', 0.4)
							if IsControlJustPressed(1, 38) then
								TriggerServerEvent('force_questsTrashCarReward')
								hasCompletedTrashingCar = false
								shownBulldozerHelpText = false
								trashVehicleBlipRouteExist = false
								trashVehicleBlipExist = false
								showMainMissionText = false
								trashVehicle.hasSpawned = false
								bulldozerVehicleBlipRouteExist = false
								bulldozerVehicleBlipExist = false
								bulldozerVehicle.hasSpawned = false
								hasShownGetInVehicleText = false
								mainVehicle.hasSpawned = false
								trashCarIsStarted = false
								shownTrashCarHelpText = false
							end
						end
					end
				end
			end
		end
	end
end)

RegisterNetEvent('force_questsTrashCarDialog')
AddEventHandler('force_questsTrashCarDialog', function()
	ESX.ShowNotification('Well! Get in the vehicle behind you!')
	Wait(3000)
	ESX.ShowNotification('Then you look at the GPS and you will have a specified position')
	Wait(3000)
	ESX.ShowNotification('Once you have arrived at this position, you will receive further information.')
	Wait(3000)
	ESX.ShowNotification('Good luck!')
end)

RegisterNetEvent('force_questsCleanQuest')
AddEventHandler('force_questsCleanQuest', function()
	cleanQuestIsStarted = true
	while cleanQuestIsStarted do
		Wait(5)

		local player = PlayerPedId()
		local pCoords = GetEntityCoords(player)

		for _,cleanPos in pairs(ConfigClean.CleanPos) do
			local cleanDist = GetDistanceBetweenCoords(pCoords, cleanPos.x, cleanPos.y, cleanPos.z, true)

			if cleanDist >= 1.5 and cleanDist <= 6 and not cleanPos.hasDone then
				DrawText3Ds(cleanPos.x, cleanPos.y, cleanPos.z, 'Clean', 0.4)
			end

			if cleanDist <= 1.5 and not cleanPos.hasDone then
				DrawText3Ds(cleanPos.x, cleanPos.y, cleanPos.z, '[~g~E~s~] Clean', 0.4)
				if IsControlJustPressed(1, 38) then
					exports["btrp_progressbar"]:StartDelayedFunction({
						["text"] = "Cleaning...",
						["delay"] = 15000
					})
					SetEntityHeading(player, cleanPos.h)
					FreezeEntityPosition(player, true)
					TaskStartScenarioInPlace(player, "WORLD_HUMAN_MAID_CLEAN", 0, true)
					Wait(15000)
					ClearPedTasks(player)
					FreezeEntityPosition(player, false)
					cleanPositions = cleanPositions + 1
					cleanPos.hasDone = true
					print(cleanPositions)
				end
			end

			for _,borstaPos in pairs(ConfigClean.BorstePos) do
				local borsteDist = GetDistanceBetweenCoords(pCoords, borstaPos.x, borstaPos.y, borstaPos.z, true)
	
				if borsteDist >= 1.5 and borsteDist <= 6 and not borstaPos.hasDone then
					DrawText3Ds(borstaPos.x, borstaPos.y, borstaPos.z, 'Brush', 0.4)
				end
	
				if borsteDist <= 1.5 and not borstaPos.hasDone then
					DrawText3Ds(borstaPos.x, borstaPos.y, borstaPos.z, '[~g~E~s~] Brush', 0.4)
					if IsControlJustPressed(1, 38) then
						exports["btrp_progressbar"]:StartDelayedFunction({
							["text"] = "Brushing...",
							["delay"] = 15000
						})
						SetEntityHeading(player, borstaPos.h)
						FreezeEntityPosition(player, true)
						TaskStartScenarioInPlace(player, "WORLD_HUMAN_JANITOR", 0, true)
						Wait(15000)
						ClearPedTasks(player)
						FreezeEntityPosition(player, false)
						cleanPositions = cleanPositions + 1
						borstaPos.hasDone = true
						print(cleanPositions)
					end
				end

				for _,blowPos in pairs(ConfigClean.BlowPos) do
					local blowDist = GetDistanceBetweenCoords(pCoords, blowPos.x, blowPos.y, blowPos.z, true)
		
					if blowDist >= 1.5 and blowDist <= 6 and not blowPos.hasDone then
						DrawText3Ds(blowPos.x, blowPos.y, blowPos.z, 'Blow', 0.4)
					end
		
					if blowDist <= 1.5 and not blowPos.hasDone then
						DrawText3Ds(blowPos.x, blowPos.y, blowPos.z, '[~g~E~s~] Blow', 0.4)
						if IsControlJustPressed(1, 38) then
							exports["btrp_progressbar"]:StartDelayedFunction({
								["text"] = "Blowing...",
								["delay"] = 15000
							})
							SetEntityHeading(player, blowPos.h)
							FreezeEntityPosition(player, true)
							TaskStartScenarioInPlace(player, "WORLD_HUMAN_GARDENER_LEAF_BLOWER", 0, true)
							Wait(15000)
							ClearPedTasks(player)
							FreezeEntityPosition(player, false)
							cleanPositions = cleanPositions + 1
							blowPos.hasDone = true
							print(cleanPositions)
						end
					end

					if not cleaningBlips then
						cleanposRadius = AddBlipForRadius(ConfigClean.CleanRadius, 30.0)
						SetBlipAlpha(cleanposRadius, 100)
						SetBlipColour(cleanposRadius, 46)
						cleaningBlips = true
					end

					if not hasDoneAllCleaning then
						DrawMissionText('Run down to the subway and clean up!', 0.0, 0.5)
					end

					if cleanPositions > ConfigClean.MaxCleanPositions-1 then
						hasDoneAllCleaning = true
						if not hasShownNotification then
							ESX.ShowNotification("You've done the cleaning, get back to me for your reward!")
							hasShownNotification = true
						end
						DrawMissionText('Get back to me!', 0.0, 0.5)
						doneWithCleaning = true
					end

					if doneWithCleaning then
						local pedDist = #(pCoords - ConfigDeliverCargo.MainPedPos)

						if pedDist >= 1.2 and pedDist <= 6 then
							DrawText3Ds(ConfigDeliverCargo.MainPedPos.x, ConfigDeliverCargo.MainPedPos.y, ConfigDeliverCargo.MainPedPos.z+1, 'Ta emot belöning', 0.4)
						end
				
						if pedDist <= 1.2 then
							DrawText3Ds(ConfigDeliverCargo.MainPedPos.x, ConfigDeliverCargo.MainPedPos.y, ConfigDeliverCargo.MainPedPos.z+1, '[~g~E~w~] Ta emot belöning', 0.4)
							if IsControlJustPressed(1, 38) then
								Wait(350)
								TriggerServerEvent('force_questsCleanReward')
								cleanQuestIsStarted = false
							end
						end
					end
				end
			end
		end
	end
end)

RegisterNetEvent('force_questsCleanDialog')
AddEventHandler('force_questsCleanDialog', function()
	ESX.ShowNotification('Well! Run down the stairs behind you!')
	Wait(3000)
	ESX.ShowNotification('Then you look at the GPS and you will have a specified radius!')
	Wait(3000)
	ESX.ShowNotification('You should clean in this radius until you get a message that you are done!')
	Wait(3000)
	ESX.ShowNotification('Good luck!')
end)

RegisterCommand('force', function()
	TriggerEvent('force_questsCleanQuest')
end, false)

RegisterCommand('force1', function()
	cleanPositions = cleanPositions + 1
end, false)