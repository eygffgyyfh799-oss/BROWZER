local Settings = Load('config').Settings

-- { label = string, vehicle = entity }
local spawnedVehicles = {}

local function GetVehicleModel(value)
    return value.model or value.vehName
end

local function GetVehicleLabel(value)
    if value.label or value.vehLabel then return value.label or value.vehLabel end
    local model = GetVehicleModel(value)
    local shared = RTCore.Shared.Vehicles and RTCore.Shared.Vehicles[model]
    return shared and shared.name or model
end

local function CleanupSpawnedVehicles()
    for i = #spawnedVehicles, 1, -1 do
        if not DoesEntityExist(spawnedVehicles[i].vehicle) then
            table.remove(spawnedVehicles, i)
        end
    end
end

local function IsSpawnPointClear(coords, maxDistance)
    for _, vehicle in pairs(RTCore.Functions.GetVehicles()) do
        if #(coords - GetEntityCoords(vehicle)) <= maxDistance then
            return false
        end
    end
    return true
end

local function GetSpawn(spawns)
    for _, spawn in pairs(spawns) do
        if IsSpawnPointClear(vector3(spawn.x, spawn.y, spawn.z), 5.0) then
            return spawn
        end
    end
end

local function SpawnJusticeVehicle(data, value)
    CleanupSpawnedVehicles()

    if #spawnedVehicles >= Settings.MaxSpawnedVehicles then
        return RTCore.Functions.Notify('يجب ارجاع المركبة الحالية قبل استخراج مركبة جديدة', 'error', 7500)
    end

    local modelName = GetVehicleModel(value)
    local model = joaat(modelName)
    if not IsModelInCdimage(model) or not IsModelAVehicle(model) then
        return RTCore.Functions.Notify('المركبة غير متوفرة: ' .. tostring(modelName), 'error', 7500)
    end

    local coords = GetSpawn(data.vehSpawns or {})
    if not coords then
        return RTCore.Functions.Notify('لا يوجد مكان فارغ لاستخراج المركبة', 'error', 7500)
    end

    pcall(lib.requestModel, model, 10000)
    if not HasModelLoaded(model) then
        return RTCore.Functions.Notify('تعذر تحميل المركبة، حاول مرة أخرى', 'error', 7500)
    end

    DoScreenFadeOut(300)
    Wait(500)

    local heading = coords.w or 0.0
    local veh = CreateVehicle(model, coords.x, coords.y, coords.z, heading, true, false)
    SetModelAsNoLongerNeeded(model)

    if not DoesEntityExist(veh) then
        DoScreenFadeIn(500)
        return RTCore.Functions.Notify('تعذر استخراج المركبة', 'error', 7500)
    end

    local netId = NetworkGetNetworkIdFromEntity(veh)
    SetNetworkIdCanMigrate(netId, true)
    SetEntityAsMissionEntity(veh, true, true)
    SetVehicleHasBeenOwnedByPlayer(veh, true)
    SetVehicleNeedsToBeHotwired(veh, false)
    SetEntityHeading(veh, heading)

    SetVehicleModKit(veh, 0)
    local livery = value.livery or value.vehLivery
    if livery then
        SetVehicleMod(veh, 48, livery, false)
    end
    ToggleVehicleMod(veh, 18, true)
    SetVehicleFixed(veh)
    SetVehicleCustomPrimaryColour(veh, 0, 0, 0)
    SetVehicleCustomSecondaryColour(veh, 0, 0, 0)
    if value.windowTint then
        SetVehicleWindowTint(veh, value.windowTint)
    end

    -- لوحة المركبة لا تتجاوز 8 أحرف
    SetVehicleNumberPlateText(veh, ('J' .. RTCore.Functions.GetPlayerData().citizenid):sub(1, 8))

    pcall(function() exports['RespectFuel']:SetFuel(veh, Settings.VehicleFuel) end)
    TaskWarpPedIntoVehicle(PlayerPedId(), veh, -1)
    TriggerEvent('vehiclekeys:client:SetOwner', GetVehicleNumberPlateText(veh))

    spawnedVehicles[#spawnedVehicles + 1] = { label = GetVehicleLabel(value), vehicle = veh }

    Wait(300)
    DoScreenFadeIn(1000)
end

local function ReturnVehicle(index)
    local entry = spawnedVehicles[index]
    if not entry then return end

    local veh = entry.vehicle
    if DoesEntityExist(veh) then
        local ped = PlayerPedId()
        if GetVehiclePedIsIn(ped, false) == veh then
            TaskLeaveVehicle(ped, veh, 0)
            Wait(1500)
        end
        NetworkRequestControlOfEntity(veh)
        SetEntityAsMissionEntity(veh, true, true)
        DeleteEntity(veh)
    end

    table.remove(spawnedVehicles, index)
    RTCore.Functions.Notify('تم ارجاع المركبة', 'success', 5000)
end

AddEventHandler('RespectJustice:client:spawnVehicleMenu', function(data)
    local job = RTCore.Functions.GetPlayerData().job
    if not job or job.name ~= Settings.Job then return end

    CleanupSpawnedVehicles()
    local options = {}

    for index, entry in ipairs(spawnedVehicles) do
        options[#options + 1] = {
            title = ('%s | %s'):format(entry.label, GetVehicleNumberPlateText(entry.vehicle)),
            description = 'ارجاع المركبة',
            icon = 'fas fa-rotate-left',
            onSelect = function() ReturnVehicle(index) end,
        }
    end

    for _, value in ipairs(data.vehicles or {}) do
        options[#options + 1] = {
            title = GetVehicleLabel(value),
            icon = 'fas fa-car',
            onSelect = function() SpawnJusticeVehicle(data, value) end,
        }
    end

    lib.registerContext({
        id = 'openJusticeVehiclesGarage',
        title = 'قائمة سيارات العدل',
        rt_logo = true,
        logo = true,
        options = options,
    })
    lib.showContext('openJusticeVehiclesGarage')
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for _, entry in ipairs(spawnedVehicles) do
        if DoesEntityExist(entry.vehicle) then
            DeleteEntity(entry.vehicle)
        end
    end
end)
