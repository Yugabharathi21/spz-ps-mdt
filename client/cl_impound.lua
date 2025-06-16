local Framework = nil

if Config.Framework == "qb" then
    Framework = exports['qb-core']:GetCoreObject()
elseif Config.Framework == "esx" then
    Framework = exports['es_extended']:getSharedObject()
end

local currentGarage = 1

local function doCarDamage(currentVehicle, veh)
	local smash = false
	local damageOutside = false
	local damageOutside2 = false
	local engine = veh.engine + 0.0
	local body = veh.body + 0.0

	if engine < 200.0 then engine = 200.0 end
    if engine  > 1000.0 then engine = 950.0 end
	if body < 150.0 then body = 150.0 end
	if body < 950.0 then smash = true end
	if body < 920.0 then damageOutside = true end
	if body < 920.0 then damageOutside2 = true end

    Citizen.Wait(100)
    SetVehicleEngineHealth(currentVehicle, engine)

	if smash then
		SmashVehicleWindow(currentVehicle, 0)
		SmashVehicleWindow(currentVehicle, 1)
		SmashVehicleWindow(currentVehicle, 2)
		SmashVehicleWindow(currentVehicle, 3)
		SmashVehicleWindow(currentVehicle, 4)
	end

	if damageOutside then
		SetVehicleDoorBroken(currentVehicle, 1, true)
		SetVehicleDoorBroken(currentVehicle, 6, true)
		SetVehicleDoorBroken(currentVehicle, 4, true)
	end

	if damageOutside2 then
		SetVehicleTyreBurst(currentVehicle, 1, false, 990.0)
		SetVehicleTyreBurst(currentVehicle, 2, false, 990.0)
		SetVehicleTyreBurst(currentVehicle, 3, false, 990.0)
		SetVehicleTyreBurst(currentVehicle, 4, false, 990.0)
	end

	if body < 1000 then
		SetVehicleBodyHealth(currentVehicle, 985.1)
	end
end

local function TakeOutImpound(vehicle)
    local coords = Config.ImpoundLocations[currentGarage]
    if coords then
        if Config.Framework == "qb" then
            Framework.Functions.SpawnVehicle(vehicle.vehicle, function(veh)
                Framework.Functions.TriggerCallback('qb-garage:server:GetVehicleProperties', function(properties)
                    Framework.Functions.SetVehicleProperties(veh, properties)
                    SetVehicleNumberPlateText(veh, vehicle.plate)
                    SetEntityHeading(veh, coords.w)
                    exports[Config.Fuel]:SetFuel(veh, vehicle.fuel)
                    doCarDamage(veh, vehicle)
                    TriggerServerEvent('police:server:TakeOutImpound', vehicle.plate)
                    TriggerEvent("vehiclekeys:client:SetOwner", Framework.Functions.GetPlate(veh))
                    SetVehicleEngineOn(veh, true, true)
                end, vehicle.plate)
            end, coords, true)
        elseif Config.Framework == "esx" then
            Framework.Game.SpawnVehicle(vehicle.vehicle, coords, coords.w, function(veh)
                Framework.TriggerServerCallback('esx_garage:getVehicleProperties', function(properties)
                    Framework.Game.SetVehicleProperties(veh, properties)
                    SetVehicleNumberPlateText(veh, vehicle.plate)
                    exports[Config.Fuel]:SetFuel(veh, vehicle.fuel)
                    doCarDamage(veh, vehicle)
                    TriggerServerEvent('police:server:TakeOutImpound', vehicle.plate)
                    SetVehicleEngineOn(veh, true, true)
                end, vehicle.plate)
            end)
        end
    end
end

RegisterNetEvent('ps-mdt:client:TakeOutImpound', function(data)
    local pos = GetEntityCoords(PlayerPedId())
    currentGarage = data.currentSelection
    local takeDist = Config.ImpoundLocations[data.currentSelection]
    takeDist = vector3(takeDist.x, takeDist.y, takeDist.z)
    if #(pos - takeDist) <= 15.0 then
        local vehicle = data.vehicle
        TakeOutImpound(data)
    else
        if Config.Framework == "qb" then
            Framework.Functions.Notify("You are too far away from the impound location!")
        else
            Framework.ShowNotification("You are too far away from the impound location!")
        end
    end
end)