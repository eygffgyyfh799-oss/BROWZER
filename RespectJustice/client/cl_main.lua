local data = Load('config')
local Settings = data.Settings
local JOB = Settings.Job

local created_blips = {}
local created_zones = {}
local created_peds = {}

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- دوال مساعدة
-- ════════════════════════════════════════════════════════════════════════════════════════════════

local function IsJustice()
    local job = RTCore.Functions.GetPlayerData().job
    return job and job.name == JOB
end

local function IsJusticeBoss()
    local job = RTCore.Functions.GetPlayerData().job
    return job and job.name == JOB and job.isboss == true
end

local dutyCooldownEnd = 0
local function GetDutyCooldown()
    return math.max(0, math.ceil((dutyCooldownEnd - GetGameTimer()) / 1000))
end

local function AddZone(name, value, options)
    exports['RespectTarget']:AddBoxZone(name, value.coords, value.size[1], value.size[2], {
        name = name,
        heading = value.heading,
        debugPoly = value.debugPoly,
        minZ = value.minZ,
        maxZ = value.maxZ,
    }, {
        options = options,
        distance = value.distance or 1.5,
    })
    created_zones[#created_zones + 1] = name
end

local function SpawnPed(key, pedData, targetOptions)
    local model = type(pedData.pedModel) == 'string' and joaat(pedData.pedModel) or pedData.pedModel
    pcall(lib.requestModel, model, 10000)
    if not HasModelLoaded(model) then
        return print(('^1[RespectJustice]^7 Failed to load ped model: %s'):format(pedData.pedModel))
    end

    local ped = CreatePed(4, model, pedData.coords.x, pedData.coords.y, pedData.coords.z - 1.0, pedData.coords.w, false, false)
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

local OpenReportsMenu

local function OpenReportDetails(report)
    local options = {
        { title = 'رجوع', icon = 'fas fa-arrow-right', onSelect = function() OpenReportsMenu() end },
        { title = 'الرقم الوطني', description = tostring(report.citizenid) },
        { title = 'اسم المواطن', description = report.name },
        { title = 'تاريخ القضية', description = report.date },
        { title = 'رقم الجوال', description = tostring(report.phoneNumber) },
        { title = 'تفاصيل القضية', description = report.report },
    }

    if IsJusticeBoss() then
        options[#options + 1] = {
            title = 'حذف القضية',
            icon = 'fas fa-trash',
            onSelect = function()
                local confirm = lib.alertDialog({
                    header = 'حذف القضية #' .. report.id,
                    content = 'هل أنت متأكد من حذف هذه القضية؟ لا يمكن التراجع عن هذا الإجراء.',
                    centered = true,
                    cancel = true,
                })
                if confirm == 'confirm' then
                    TriggerServerEvent('RespectJustice:server:removeReport', report.id)
                    Wait(500)
                    OpenReportsMenu()
                end
            end,
        }
    end

    lib.registerContext({
        id = 'justice_office_reports_menu_option',
        title = 'تفاصيل القضية رقم #' .. report.id,
        menu = 'justice_office_reports_menu',
        options = options,
        rt_logo = true,
    })
    lib.showContext('justice_office_reports_menu_option')
end

OpenReportsMenu = function()
    RTCore.Functions.TriggerCallback('RespectJustice:server:getJobReports', function(reports)
        local options = {}

        if not reports or #reports == 0 then
            options[1] = { title = 'لا توجد قضايا متاحة حالياً', disabled = true }
        else
            for _, report in ipairs(reports) do
                options[#options + 1] = {
                    title = 'القضية رقم #' .. report.id,
                    description = ('%s | %s | %s'):format(report.name, report.citizenid, report.date),
                    icon = 'fas fa-scale-balanced',
                    onSelect = function() OpenReportDetails(report) end,
                }
            end
        end

        lib.registerContext({
            id = 'justice_office_reports_menu',
            title = ('قائمة القضايا (%d)'):format(reports and #reports or 0),
            options = options,
            desc = 'لمشاهدة تفاصيل قضية، يرجى اختيار القضية المطلوبة',
            rt_logo = true,
        })
        lib.showContext('justice_office_reports_menu')
    end)
end

local function OpenSubmitReport()
    local input = lib.inputDialog('قائمة القضايا', {
        { type = 'textarea', label = 'موضوع الدعوى القضائية', required = true, min = Settings.ReportMinLength, max = Settings.ReportMaxLength },
    })
    if not input or not input[1] then return end

    local text = _2rayan.Functions.trim(input[1]) or ''
    local length = utf8.len(text) or #text
    if length < Settings.ReportMinLength then
        return RTCore.Functions.Notify(('يجب أن يكون موضوع الدعوى %d أحرف على الأقل'):format(Settings.ReportMinLength), 'error')
    end
    if length > Settings.ReportMaxLength then
        return RTCore.Functions.Notify(('عذرًا، يجب أن يكون الموضوع أقل من %d حرف'):format(Settings.ReportMaxLength), 'error')
    end

    TriggerServerEvent('RespectJustice:server:submitReport', text)
end

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- إنشاء البلبس والمناطق والشخصيات
-- ════════════════════════════════════════════════════════════════════════════════════════════════

local function create_blips()
    for _, v in pairs(data.Locations) do
        if v.blip and v.blip.show then
            local blip = AddBlipForCoord(v.coords.x, v.coords.y, v.coords.z)
            SetBlipSprite(blip, v.blip.sprite)
            SetBlipColour(blip, v.blip.colour)
            SetBlipAsShortRange(blip, true)
            SetBlipScale(blip, v.blip.scale)
            BeginTextCommandSetBlipName("STRING")
            AddTextComponentString(exports['RespectScripts']:escape(v.blip.label))
            EndTextCommandSetBlipName(blip)
            created_blips[#created_blips + 1] = blip
        end
    end
end

local function create_zones()
    for k, v in pairs(data.Locations) do
        for key, value in pairs(v.duty or {}) do
            AddZone(('justice_duty_%s_%s'):format(k, key), value, {
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
            })
        end

        for key, value in pairs(v.personal_stash or {}) do
            local stashOptions = {
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
            }

            -- showReports: إضافة خيار رؤية القضايا لنفس المنطقة بدل منطقتين متداخلتين
            if value.showReports then
                stashOptions[#stashOptions + 1] = {
                    icon = 'fas fa-scale-balanced',
                    label = 'رؤية القضايا المقدمة',
                    job = JOB,
                    action = OpenReportsMenu,
                }
            end

            AddZone(('justice_personal_stash_%s_%s'):format(k, key), value, stashOptions)
        end

        for key, value in pairs(v.reports_check or {}) do
            AddZone(('justice_reports_check_%s_%s'):format(k, key), value, {
                {
                    icon = 'fas fa-circle',
                    label = 'رؤية القضايا المقدمة',
                    job = JOB,
                    action = OpenReportsMenu,
                },
            })
        end

        for _k, _v in pairs(v.reports or {}) do
            SpawnPed(('reports_%s_%s'):format(k, _k), _v, {
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
                                    onSelect = OpenSubmitReport,
                                },
                            },
                        })
                        lib.showContext('justice_player_select_menu_reports')
                    end,
                },
            })
        end

        for _k, _v in pairs(v.spawn_vehicles or {}) do
            SpawnPed(('spawn_vehicles_%s_%s'):format(k, _k), _v, {
                {
                    icon = 'fa-solid fa-car',
                    label = 'تحدث',
                    job = JOB,
                    canInteract = IsJustice,
                    action = function()
                        TriggerEvent('RespectJustice:client:spawnVehicleMenu', _v)
                    end,
                },
            })
        end
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
