-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- التابلت: واجهة نظام الدولة (html/) - يفتح بزر 9 من أي مكان
-- كل الصلاحيات والتحقق في السيرفر، الواجهة بس تعرض
-- ════════════════════════════════════════════════════════════════════════════════════════════════

local Settings = JC.Settings
local Panel = Settings.Panel

JC.Tablet = {}

local isOpen = false
local tabletProp

-- الدوال اللي تقدر الواجهة تطلبها من السيرفر (أي اسم ثاني ينرفض)
local Allowed = {}
for _, name in ipairs({
    'panelInfo', 'getOnlinePlayers', 'getAllCitizens', 'searchCitizens', 'getProfile', 'getSuspended',
    'locateCitizen', 'withdrawBank', 'suspendCitizen', 'unsuspendCitizen', 'editCitizen',
    'getJobReports', 'getReport', 'setReportStatus', 'addReportNote', 'deleteReport',
    'getJobs', 'getJobMembers', 'setCitizenJob', 'setCitizenDuty', 'getGangs', 'setGang',
    'getCityOverview', 'searchVehicles', 'getVehicle', 'vehicleAction', 'searchProperties', 'transferProperty',
    'setLicense', 'sendSummon', 'setSummonStatus', 'getAllSummons', 'announce',
    'getLogs', 'undoLog', 'deleteLog', 'deleteSummon',
    'tabletInfo', 'getSuspects', 'addSuspect', 'removeSuspect', 'getWarrants', 'issueWarrant', 'cancelWarrant',
    'assignLawyer', 'removeLawyer', 'addDocument', 'lawyerCases', 'lawyerCase', 'lawyerNote',
    'issueVerdict', 'getStats', 'getPoliceRequests', 'answerPoliceRequest',
    'policeSearch', 'policeProfile', 'policeWarrants', 'executeWarrant', 'policeSuspects', 'policeRequest', 'policeMyRequests',
}) do Allowed[name] = true end

-- ═════ أنيميشن التابلت ═════
local AnimDict, AnimName, PropModel = 'amb@code_human_in_bus_passenger_idles@female@tablet@base', 'base', GetHashKey('prop_cs_tablet')

local function StopAnimation()
    local ped = PlayerPedId()
    if tabletProp and DoesEntityExist(tabletProp) then
        DeleteEntity(tabletProp)
    end
    tabletProp = nil
    if IsEntityPlayingAnim(ped, AnimDict, AnimName, 3) then
        StopAnimTask(ped, AnimDict, AnimName, 1.0)
    end
end

local function StartAnimation()
    if Panel.TabletAnimation == false then return end
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) or IsEntityDead(ped) then return end

    pcall(lib.requestAnimDict, AnimDict, 3000)
    pcall(lib.requestModel, PropModel, 3000)
    if not HasAnimDictLoaded(AnimDict) or not HasModelLoaded(PropModel) then return end

    local coords = GetEntityCoords(ped)
    tabletProp = CreateObject(PropModel, coords.x, coords.y, coords.z + 0.2, true, true, true)
    SetModelAsNoLongerNeeded(PropModel)
    AttachEntityToEntity(tabletProp, ped, GetPedBoneIndex(ped, 60309), 0.03, 0.002, -0.0, 10.0, 160.0, 0.0, true, false, false, false, 2, true)
    TaskPlayAnim(ped, AnimDict, AnimName, 3.0, 3.0, -1, 49, 0, false, false, false)
end

-- ═════ الفتح والإغلاق ═════
function JC.Tablet.Close()
    if not isOpen then return end
    isOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
    StopAnimation()
end

function JC.Tablet.Open(page, arg)
    if isOpen then return end
    if not JC.GuessRole() then
        return JC.Notify('نظام الدولة لموظفي العدل والشرطة والمحامين فقط', 'error')
    end
    if IsPauseMenuActive() or IsNuiFocused() then return end

    local info = JC.Call('RespectJustice:server:tabletInfo')
    if not info then return end

    local pd = RTCore.Functions.GetPlayerData()
    local job = pd.job or {}
    isOpen = true
    SetNuiFocus(true, true)
    StartAnimation()

    SendNUIMessage({
        action = 'open',
        page = page,
        arg = arg,
        info = info,
        me = {
            name = ('%s %s'):format(pd.charinfo and pd.charinfo.firstname or '', pd.charinfo and pd.charinfo.lastname or ''),
            job = job.label or job.name,
            grade = type(job.grade) == 'table' and job.grade.name or job.grade,
        },
        role = info.role,
        config = {
            maxFine = Settings.Verdicts.MaxFine,
            maxJail = Settings.Verdicts.MaxJail,
            warrantHours = Settings.Verdicts.WarrantHours,
            grantMinutes = Settings.Police.GrantMinutes,
            documentMax = Settings.Lawyers.DocumentMax,
            unemployed = Panel.UnemployedJob,
            withdrawMax = Panel.WithdrawMax,
            compensationMax = Settings.CompensationMax,
            compensationDistance = Settings.CompensationMaxDistance,
            summonMax = Settings.City.SummonMaxLength,
            announceMax = Settings.City.AnnounceMaxLength,
            noteMax = Settings.ReportNoteMax,
        },
    })
end

-- ═════ طلبات الواجهة ═════
RegisterNUICallback('close', function(_, cb)
    JC.Tablet.Close()
    cb({ ok = true })
end)

RegisterNUICallback('call', function(data, cb)
    if not isOpen or type(data) ~= 'table' or type(data.name) ~= 'string' or not Allowed[data.name] then
        return cb({ ok = false, err = 'طلب غير مسموح' })
    end

    local args = type(data.args) == 'table' and data.args or {}
    local result = JC.Await('RespectJustice:server:' .. data.name, table.unpack(args, 1, 6))
    if type(result) ~= 'table' then
        return cb({ ok = false, err = 'السيرفر ما رد، حاول مرة ثانية' })
    end

    -- معالجة تحتاج العميل: أسماء الشوارع وعلامات الخريطة
    if result.ok ~= false then
        if data.name == 'locateCitizen' and result.coords then
            result.street = JC.GetStreet(result.coords)
            JC.TempBlip(result.coords, 'موقع ' .. tostring(result.name), Panel.LocateBlipTime, 280, 1)
        elseif data.name == 'getVehicle' and result.vehicle and result.vehicle.coords then
            result.vehicle.street = JC.GetStreet(result.vehicle.coords)
            JC.TempBlip(result.vehicle.coords, 'مركبة ' .. tostring(result.vehicle.plate), Panel.LocateBlipTime, 225, 1)
        elseif data.name == 'getReport' and result.report and result.report.submitter and result.report.submitter.coords then
            result.report.submitter.street = JC.GetStreet(result.report.submitter.coords)
        end
    end

    cb(result)
end)

RegisterNUICallback('waypoint', function(data, cb)
    local c = type(data) == 'table' and data.coords
    if type(c) == 'table' and tonumber(c.x) and tonumber(c.y) and tonumber(c.z) then
        JC.TempBlip({ x = tonumber(c.x), y = tonumber(c.y), z = tonumber(c.z) }, tostring(data.label or 'موقع'), Panel.LocateBlipTime, 162, 5)
    end
    cb({ ok = true })
end)

RegisterNUICallback('compensate', function(data, cb)
    if isOpen and type(data) == 'table' and type(data.citizenid) == 'string' and tonumber(data.amount) then
        TriggerServerEvent('RespectJustice:server:giveMoneyToPlayer', data.citizenid, math.floor(tonumber(data.amount)))
    end
    cb({ ok = true })
end)

-- ═════ زر الفتح (9 افتراضياً، واللاعب يقدر يغيره من إعدادات اللعبة ← Key Bindings ← FiveM) ═════
RegisterCommand('justicetablet', function()
    if isOpen then return end
    if JC.GuessRole() then JC.Tablet.Open() end
end, false)

RegisterKeyMapping('justicetablet', 'فتح نظام الدولة (العدل / الشرطة / المحامين)', 'keyboard', Panel.Key or '9')

-- ═════ الإشعارات المباشرة (قضية جديدة، طلب شرطة، أمر جديد...) ═════
RegisterNetEvent('RespectJustice:client:tabletEvent', function(event)
    if type(event) ~= 'table' then return end
    if type(event.coords) == 'table' and tonumber(event.coords.x) then
        JC.TempBlip({ x = tonumber(event.coords.x), y = tonumber(event.coords.y), z = tonumber(event.coords.z) }, tostring(event.label or event.title or 'موقع'), Panel.LocateBlipTime, 280, 1)
    end
    if isOpen then
        SendNUIMessage({ action = 'event', event = event })
    else
        JC.Notify(('%s\n%s'):format(tostring(event.title or ''), tostring(event.text or '')), 'primary', 9000)
        PlaySoundFrontend(-1, 'Event_Message_Purple', 'GTAO_FM_Events_Soundset', false)
    end
end)

-- إغلاق تلقائي إذا مات اللاعب أو تغيرت وظيفته
CreateThread(function()
    while true do
        Wait(1000)
        if isOpen and (IsEntityDead(PlayerPedId()) or not JC.GuessRole()) then
            JC.Tablet.Close()
        end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if isOpen then SetNuiFocus(false, false) end
    StopAnimation()
end)
