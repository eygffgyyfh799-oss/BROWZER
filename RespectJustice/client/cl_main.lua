local data = JC.Config
local Settings = JC.Settings
local JOB = JC.Job

local created_blips = {}
local created_zones = {}
local created_peds = {}

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- دوال مساعدة
-- ════════════════════════════════════════════════════════════════════════════════════════════════

local IsJustice = JC.IsJustice
local IsJusticeBoss = JC.IsBoss

local dutyCooldownEnd = 0
local function GetDutyCooldown()
    return math.max(0, math.ceil((dutyCooldownEnd - GetGameTimer()) / 1000))
end

-- منطقة تفاعل حول الإحداثية (مربع بحجم ZoneSize وارتفاع 3 متر)
local function AddZone(name, coords, options)
    local size = data.ZoneSize or 2.5
    exports['RespectTarget']:AddBoxZone(name, vector3(coords.x, coords.y, coords.z), size, size, {
        name = name,
        heading = coords.w or 0.0,
        debugPoly = data.DebugZones == true,
        minZ = coords.z - 1.5,
        maxZ = coords.z + 1.5,
    }, {
        options = options,
        distance = 2.0,
    })
    created_zones[#created_zones + 1] = name
end

local function SpawnPed(key, pedData, targetOptions)
    if not pedData or not pedData.coords then return end
    local model = type(pedData.model) == 'string' and joaat(pedData.model) or pedData.model
    pcall(lib.requestModel, model, 10000)
    if not HasModelLoaded(model) then
        return print(('^1[RespectJustice]^7 Failed to load ped model: %s'):format(tostring(pedData.model)))
    end

    local c = pedData.coords
    local ped = CreatePed(4, model, c.x, c.y, c.z - 1.0, c.w or 0.0, false, false)
    SetModelAsNoLongerNeeded(model)
    FreezeEntityPosition(ped, true)
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)

    if pedData.animation then
        lib.requestAnimDict(pedData.animation[1])
        TaskPlayAnim(ped, pedData.animation[1], pedData.animation[2], 8.0, 8.0, -1, 1, 0, false, false, false)
        RemoveAnimDict(pedData.animation[1])
    end

    if pedData.scenario then
        TaskStartScenarioInPlace(ped, pedData.scenario, 0, true)
    end

    exports['RespectTarget']:AddTargetEntity(ped, {
        options = targetOptions,
        distance = 2.5,
    })

    created_peds[key] = ped
end

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- القوائم
-- ════════════════════════════════════════════════════════════════════════════════════════════════

local function OpenDutyHistory()
    RTCore.Functions.TriggerCallback('RespectJustice:server:getDutyHistory', function(playersHistory)
        if not playersHistory or not next(playersHistory) then
            return RTCore.Functions.Notify('لا يوجد سجل بالوقت الحالي', 'error', 5000)
        end

        local options = {}
        for _, history in ipairs(playersHistory) do
            options[#options + 1] = {
                title = history.name,
                description = ('%s - %s'):format(history.dutyStatus, history.timeFormated),
                icon = history.dutyStatus == 'بدأ الدوام' and 'fas fa-right-to-bracket' or 'fas fa-right-from-bracket',
            }
        end

        lib.registerContext({
            id = 'justice_laptop_duty',
            title = 'سجل البصمة',
            options = options,
        })
        lib.showContext('justice_laptop_duty')
    end)
end

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- إنشاء البلبس والمناطق والشخصيات
-- ════════════════════════════════════════════════════════════════════════════════════════════════

local function create_blips()
    local blipData = data.Points.Blip
    if not blipData or not blipData.show then return end

    local blip = AddBlipForCoord(blipData.coords.x, blipData.coords.y, blipData.coords.z)
    SetBlipSprite(blip, blipData.sprite or 176)
    SetBlipColour(blip, blipData.colour or 0)
    SetBlipAsShortRange(blip, true)
    SetBlipScale(blip, blipData.scale or 0.45)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString(exports['RespectScripts']:escape(blipData.label))
    EndTextCommandSetBlipName(blip)
    created_blips[#created_blips + 1] = blip
end

-- الخيارات اللي تظهر عند كل نوع من الإحداثيات
local PointOptions = {
    Duty = {
        {
            icon = 'fas fa-clipboard',
            label = 'البصمة',
            job = JOB,
            action = function()
                local remaining = GetDutyCooldown()
                if remaining > 0 then
                    return RTCore.Functions.Notify(('يجب ان تنتظر %s ثانية'):format(remaining), 'error', 5000)
                end
                dutyCooldownEnd = GetGameTimer() + Settings.DutyCooldown * 1000
                -- الترتيب مهم: نبدل الدوام أولاً ثم نسجل الحالة الجديدة
                TriggerServerEvent('QBCore:ToggleDuty')
                TriggerServerEvent('RespectJustice:server:updateDutyHistory')
            end,
        },
        {
            icon = 'fas fa-laptop',
            label = 'سجل البصمة',
            job = JOB,
            canInteract = IsJusticeBoss,
            action = OpenDutyHistory,
        },
    },

    Stash = {
        {
            icon = 'fas fa-box',
            label = 'الخزنة الشخصية',
            job = JOB,
            action = function()
                local stashId = 'justice_stash_' .. RTCore.Functions.GetPlayerData().citizenid
                TriggerServerEvent('inventory:server:OpenInventory', 'stash', stashId, Settings.PersonalStash)
                TriggerEvent('inventory:client:SetCurrentStash', stashId)
            end,
        },
        {
            icon = 'fas fa-box-archive',
            label = 'الأرشيف',
            job = JOB,
            canInteract = IsJusticeBoss,
            action = function()
                local input = lib.inputDialog('قائمة الارشيف', {
                    { type = 'number', label = 'الرقم الوطني للارشيف', required = true, min = 1 },
                })
                local archiveId = input and tonumber(input[1])
                if not archiveId or archiveId < 1 then return end
                archiveId = math.floor(archiveId)

                local stashId = 'justice_archive_' .. archiveId
                TriggerServerEvent('inventory:server:OpenInventory', 'stash', stashId, Settings.ArchiveStash)
                TriggerEvent('inventory:client:SetCurrentStash', stashId)
            end,
        },
    },

    ReportsView = {
        {
            icon = 'fas fa-scale-balanced',
            label = 'رؤية القضايا المقدمة',
            job = JOB,
            action = function() JC.Reports.OpenList() end,
        },
    },

    CitizenPanel = {
        {
            icon = 'fas fa-address-card',
            label = 'نظام معلومات المواطنين',
            job = JOB,
            action = function() JC.Panel.Open() end,
        },
    },
}

local PointOrder = { 'Duty', 'Stash', 'ReportsView', 'CitizenPanel' }

local function create_zones()
    -- تجميع الإحداثيات المتطابقة في منطقة وحدة حتى ما تغطي منطقة على الثانية
    local zones, zoneOrder = {}, {}
    for _, pointType in ipairs(PointOrder) do
        for _, coords in ipairs(data.Points[pointType] or {}) do
            local key = ('%.1f_%.1f_%.1f'):format(coords.x, coords.y, coords.z)
            if not zones[key] then
                zones[key] = { coords = coords, options = {} }
                zoneOrder[#zoneOrder + 1] = key
            end
            for _, option in ipairs(PointOptions[pointType]) do
                table.insert(zones[key].options, option)
            end
        end
    end

    for i, key in ipairs(zoneOrder) do
        AddZone('justice_point_' .. i, zones[key].coords, zones[key].options)
    end

    -- بوت تقديم القضايا
    SpawnPed('report_ped', data.Points.ReportPed, {
        {
            icon = 'fa-solid fa-comment',
            label = 'تحدث',
            action = function()
                local ok, phoneNumber = pcall(function()
                    return exports['lb-phone']:GetEquippedPhoneNumber()
                end)
                if not ok or not phoneNumber then
                    return RTCore.Functions.Notify('يجب ان يتوفر لديك رقم جوال', 'error', 5000)
                end

                lib.registerContext({
                    id = 'justice_player_select_menu_reports',
                    title = 'قائمة القضايا',
                    options = {
                        {
                            title = 'تقديم دعوى قضائية',
                            icon = 'fas fa-file-signature',
                            description = ('اضغط هنا لكتابة ولطلب تقديم دعوى إلى وزارة العدل برسوم %d دولار'):format(Settings.ReportFee),
                            onSelect = JC.Reports.OpenSubmit,
                        },
                        {
                            title = 'متابعة دعاواي',
                            icon = 'fas fa-list-check',
                            description = 'حالة الدعاوى التي قدمتها',
                            onSelect = function() JC.Reports.OpenMine('justice_player_select_menu_reports') end,
                        },
                    },
                })
                lib.showContext('justice_player_select_menu_reports')
            end,
        },
    })

    -- بوت مركبات العدل
    SpawnPed('vehicle_ped', data.Points.VehiclePed, {
        {
            icon = 'fa-solid fa-car',
            label = 'تحدث',
            job = JOB,
            canInteract = IsJustice,
            action = function()
                TriggerEvent('RespectJustice:client:spawnVehicleMenu', {
                    vehicles = data.Vehicles,
                    vehSpawns = data.Points.VehicleSpawns,
                })
            end,
        },
    })
end

local function cleanup()
    for _, ped in pairs(created_peds) do
        if DoesEntityExist(ped) then
            DeleteEntity(ped)
        end
    end
    created_peds = {}

    for _, blip in ipairs(created_blips) do
        if DoesBlipExist(blip) then
            RemoveBlip(blip)
        end
    end
    created_blips = {}

    for _, name in ipairs(created_zones) do
        pcall(function() exports['RespectTarget']:RemoveZone(name) end)
    end
    created_zones = {}
end

CreateThread(function()
    create_blips()
    create_zones()
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        cleanup()
    end
end)

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- التعويض
-- ════════════════════════════════════════════════════════════════════════════════════════════════

RegisterNetEvent('RespectJustice:client:giveMoney', function()
    if not IsJustice() then
        return RTCore.Functions.Notify('يجب أن تكون من موظفي العدل لاستخدام هذه الميزة', 'error', 5000)
    end

    local playerPed = PlayerPedId()
    local coords = GetEntityCoords(playerPed)
    local closestPlayer, closestDistance = nil, Settings.CompensationMaxDistance

    for _, player in ipairs(GetActivePlayers()) do
        local targetPed = GetPlayerPed(player)
        if targetPed ~= playerPed then
            local distance = #(coords - GetEntityCoords(targetPed))
            if distance < closestDistance then
                closestPlayer = player
                closestDistance = distance
            end
        end
    end

    if not closestPlayer then
        return RTCore.Functions.Notify('لا يوجد شخص قريب', 'error', 5000)
    end

    local input = lib.inputDialog('تعويض الشخص', {
        { type = 'input', label = 'الرقم الوطني', required = true },
        { type = 'number', label = 'المبلغ', required = true, min = 1, max = Settings.CompensationMax },
    })
    if not input then return end

    local citizenid = _2rayan.Functions.trim(input[1])
    local amount = tonumber(input[2])
    if not citizenid or citizenid == '' or not amount or amount <= 0 then
        return RTCore.Functions.Notify('البيانات المدخلة غير صحيحة', 'error', 5000)
    end

    TriggerServerEvent('RespectJustice:server:giveMoneyToPlayer', citizenid, math.floor(amount))
end)
