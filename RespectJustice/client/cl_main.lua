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
            return JC.Notify('لا يوجد سجل بالوقت الحالي', 'error', 5000)
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

-- ترجمة الأنواع المكتوبة في coords.lua
local TypeNames = {
    ['بصمة'] = 'Duty',
    ['خزنة'] = 'Stash',
    ['رؤية القضايا'] = 'ReportsView',
    ['نظام المواطنين'] = 'CitizenPanel',
    ['بوت القضايا'] = 'ReportPed',
    ['بوت المركبات'] = 'VehiclePed',
    ['خروج المركبات'] = 'VehicleSpawn',
    ['علامة الخريطة'] = 'Blip',
}

-- تجميع الإحداثيات حسب النوع: Points.Duty = { {name, coords, model}, ... }
local Points = {}
for i, entry in ipairs(JC.Coords) do
    local pointType = type(entry) == 'table' and TypeNames[entry.type]
    if not pointType or not entry.coords then
        print(('^1[RespectJustice]^7 coords.lua سطر %d: نوع غير معروف "%s" (%s)'):format(i, tostring(entry and entry.type), tostring(entry and entry.name)))
    else
        Points[pointType] = Points[pointType] or {}
        table.insert(Points[pointType], entry)
    end
end

local function create_blips()
    local style = data.Blip or {}
    for _, entry in ipairs(Points.Blip or {}) do
        local c = entry.coords
        local blip = AddBlipForCoord(c.x, c.y, c.z)
        SetBlipSprite(blip, entry.sprite or style.sprite or 176)
        SetBlipColour(blip, entry.colour or style.colour or 0)
        SetBlipAsShortRange(blip, true)
        SetBlipScale(blip, entry.scale or style.scale or 0.45)
        BeginTextCommandSetBlipName("STRING")
        local label = entry.name or 'وزارة العدل'
        local ok, escaped = pcall(function() return exports['RespectScripts']:escape(label) end)
        AddTextComponentString(ok and escaped or label)
        EndTextCommandSetBlipName(blip)
        created_blips[#created_blips + 1] = blip
    end
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
                    return JC.Notify(('يجب ان تنتظر %s ثانية'):format(remaining), 'error', 5000)
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
            action = function()
                if Settings.Panel.UseTablet ~= false and JC.Tablet then return JC.Tablet.Open('reports') end
                JC.Reports.OpenList()
            end,
        },
    },

    CitizenPanel = {
        {
            icon = 'fas fa-address-card',
            label = 'نظام الدولة',
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
        for _, entry in ipairs(Points[pointType] or {}) do
            local coords = entry.coords
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

    local spawns = {}
    for i, entry in ipairs(Points.VehicleSpawn or {}) do
        spawns[i] = entry.coords
    end

    -- بوت تقديم القضايا
    local reportPedOptions = {
        {
            icon = 'fa-solid fa-comment',
            label = 'تحدث',
            action = function()
                -- التحقق من الجوال فقط إذا lb-phone شغال (لو مو موجود ما نمنع تقديم الدعوى)
                if GetResourceState('lb-phone') == 'started' then
                    local ok, phoneNumber = pcall(function()
                        return exports['lb-phone']:GetEquippedPhoneNumber()
                    end)
                    if ok and not phoneNumber then
                        return JC.Notify('يجب ان يتوفر لديك رقم جوال', 'error', 5000)
                    end
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
                        {
                            title = 'استدعاءاتي',
                            icon = 'fas fa-envelope',
                            description = 'استدعاءات المحكمة الموجهة لك',
                            onSelect = function() JC.City.OpenMySummons('justice_player_select_menu_reports') end,
                        },
                    },
                })
                lib.showContext('justice_player_select_menu_reports')
            end,
        },
    }

    -- بوت مركبات العدل
    local vehiclePedOptions = {
        {
            icon = 'fa-solid fa-car',
            label = 'تحدث',
            job = JOB,
            canInteract = IsJustice,
            action = function()
                TriggerEvent('RespectJustice:client:spawnVehicleMenu', {
                    vehicles = data.Vehicles,
                    vehSpawns = spawns,
                })
            end,
        },
    }

    local peds = data.Peds or {}
    for i, entry in ipairs(Points.ReportPed or {}) do
        local look = peds['بوت القضايا'] or {}
        SpawnPed('report_ped_' .. i, {
            coords = entry.coords,
            model = entry.model or look.model or 'cs_josh',
            animation = look.animation,
            scenario = look.scenario,
        }, reportPedOptions)
    end
    for i, entry in ipairs(Points.VehiclePed or {}) do
        local look = peds['بوت المركبات'] or {}
        SpawnPed('vehicle_ped_' .. i, {
            coords = entry.coords,
            model = entry.model or look.model or 'csb_trafficwarden',
            animation = look.animation,
            scenario = look.scenario,
        }, vehiclePedOptions)
    end
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

-- كل جزء لحاله: لو فشل واحد ما يوقف الباقي
CreateThread(function()
    local ok, err = pcall(create_blips)
    if not ok then print('^1[RespectJustice]^7 create_blips: ' .. tostring(err)) end
    ok, err = pcall(create_zones)
    if not ok then print('^1[RespectJustice]^7 create_zones: ' .. tostring(err)) end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        cleanup()
    end
end)

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- /jcoords : ينسخ إحداثيتك الحالية بنفس شكل ملف coords.lua
-- ════════════════════════════════════════════════════════════════════════════════════════════════

RegisterCommand('jcoords', function()
    local ped = PlayerPedId()
    local c = GetEntityCoords(ped)
    local text = ('vector4(%.2f, %.2f, %.2f, %.2f)'):format(c.x, c.y, c.z, GetEntityHeading(ped))
    pcall(lib.setClipboard, text)
    print(text)
    JC.Notify('تم نسخ الإحداثية: ' .. text, 'success', 10000)
end, false)

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- التعويض
-- ════════════════════════════════════════════════════════════════════════════════════════════════

RegisterNetEvent('RespectJustice:client:giveMoney', function()
    if not IsJustice() then
        return JC.Notify('يجب أن تكون من موظفي العدل لاستخدام هذه الميزة', 'error', 5000)
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
        return JC.Notify('لا يوجد شخص قريب', 'error', 5000)
    end

    local input = lib.inputDialog('تعويض الشخص', {
        { type = 'input', label = 'الرقم الوطني', required = true },
        { type = 'number', label = 'المبلغ', required = true, min = 1, max = Settings.CompensationMax },
    })
    if not input then return end

    local citizenid = _2rayan.Functions.trim(input[1])
    local amount = tonumber(input[2])
    if not citizenid or citizenid == '' or not amount or amount <= 0 then
        return JC.Notify('البيانات المدخلة غير صحيحة', 'error', 5000)
    end

    TriggerServerEvent('RespectJustice:server:giveMoneyToPlayer', citizenid, math.floor(amount))
end)
