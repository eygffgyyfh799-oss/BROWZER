-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- أدوات مشتركة لملفات العميل (يُحمّل أولاً)
-- ════════════════════════════════════════════════════════════════════════════════════════════════

JC = {}
JC.Config = LoadConfig()
JC.Coords = LoadCoords()
JC.Settings = JC.Config.Settings
JC.Job = JC.Settings.Job

local LibTypes = { primary = 'inform', success = 'success', error = 'error', inform = 'inform', warning = 'warning' }

-- إشعار: يستخدم إشعار الكور، ولو فشل يستخدم إشعار RespectLib
function JC.Notify(msg, msgType, length)
    msgType, length = msgType or 'primary', length or 5000
    local ok = pcall(RTCore.Functions.Notify, msg, msgType, length)
    if not ok then
        pcall(lib.notify, { description = msg, type = LibTypes[msgType] or 'inform', duration = length })
    end
end

-- احتياطي: لو إشعار الكور في السيرفر ما اشتغل، السيرفر يرسل هنا
RegisterNetEvent('RespectJustice:client:notify', function(msg, msgType, length)
    if type(msg) == 'string' then JC.Notify(msg, msgType, length) end
end)

function JC.IsJustice()
    local job = RTCore.Functions.GetPlayerData().job
    return job ~= nil and job.name == JC.Job
end

function JC.IsBoss()
    local job = RTCore.Functions.GetPlayerData().job
    if not job or job.name ~= JC.Job then return false end
    if job.isboss == true then return true end
    local grade = type(job.grade) == 'table' and job.grade.level or job.grade
    local fullAccess = tonumber(JC.Settings.Panel.FullAccessGrade)
    return fullAccess ~= nil and (tonumber(grade) or 0) >= fullAccess
end

-- ينتظر نتيجة callback من السيرفر (بحد أقصى 10 ثواني عشان ما تعلق القائمة)
function JC.Await(name, ...)
    local p = promise.new()
    local finished = false
    RTCore.Functions.TriggerCallback(name, function(result)
        if finished then return end
        finished = true
        p:resolve(result)
    end, ...)
    SetTimeout(10000, function()
        if finished then return end
        finished = true
        p:resolve(nil)
    end)
    return Citizen.Await(p)
end

-- مثل Await لكن: يمنع الضغط المزدوج، ويعرض رسالة الخطأ تلقائياً ويرجع nil عند الفشل
local inFlight = {}

function JC.Call(name, ...)
    if inFlight[name] then return nil end
    inFlight[name] = true
    local ok, result = pcall(JC.Await, name, ...)
    inFlight[name] = nil

    if not ok then
        print(('^1[RespectJustice] %s: %s^7'):format(name, tostring(result)))
        JC.Notify('حدث خطأ غير متوقع، حاول مرة ثانية', 'error')
        return nil
    end
    if type(result) ~= 'table' then
        JC.Notify('السيرفر ما رد، حاول مرة ثانية', 'error')
        return nil
    end
    if result.ok == false then
        JC.Notify(result.err or 'حدث خطأ', 'error')
        return nil
    end
    return result
end

function JC.Money(value)
    local number = math.floor(tonumber(value) or 0)
    local formatted = tostring(math.abs(number)):reverse():gsub('(%d%d%d)', '%1,'):reverse():gsub('^,', '')
    return (number < 0 and '-$' or '$') .. formatted
end

function JC.Gender(value)
    if tonumber(value) == 0 then return 'ذكر' end
    if tonumber(value) == 1 then return 'أنثى' end
    return '-'
end

function JC.Value(value)
    if value == nil or value == '' then return '-' end
    return tostring(value)
end

function JC.Utf8Len(str)
    return utf8.len(str) or #str
end

-- اسم الشارع والمنطقة من الإحداثيات
function JC.GetStreet(coords)
    if not coords then return 'غير معروف' end
    local streetHash, crossingHash = GetStreetNameAtCoord(coords.x, coords.y, coords.z)
    local street = GetStreetNameFromHashKey(streetHash)
    local crossing = crossingHash ~= 0 and GetStreetNameFromHashKey(crossingHash) or nil
    local zone = GetLabelText(GetNameOfZone(coords.x, coords.y, coords.z))
    local text = street
    if crossing and crossing ~= '' then text = text .. ' / ' .. crossing end
    if zone and zone ~= '' and zone ~= 'NULL' then text = text .. ' - ' .. zone end
    return text
end

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- وضع علامة مؤقتة على الخريطة
-- ════════════════════════════════════════════════════════════════════════════════════════════════

local tempBlips = {}

function JC.TempBlip(coords, label, seconds, sprite, colour)
    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, sprite or 280)
    SetBlipColour(blip, colour or 1)
    SetBlipScale(blip, 0.9)
    SetBlipFlashes(blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(label)
    EndTextCommandSetBlipName(blip)
    SetNewWaypoint(coords.x, coords.y)
    tempBlips[blip] = true

    SetTimeout((seconds or 60) * 1000, function()
        if DoesBlipExist(blip) then RemoveBlip(blip) end
        tempBlips[blip] = nil
    end)
end

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for blip in pairs(tempBlips) do
        if DoesBlipExist(blip) then RemoveBlip(blip) end
    end
end)
