-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- أدوات مشتركة لملفات العميل (يُحمّل أولاً)
-- ════════════════════════════════════════════════════════════════════════════════════════════════

JC = {}
JC.Config = Load('config')
JC.Settings = JC.Config.Settings
JC.Job = JC.Settings.Job

function JC.Notify(msg, msgType, length)
    RTCore.Functions.Notify(msg, msgType or 'primary', length or 5000)
end

function JC.IsJustice()
    local job = RTCore.Functions.GetPlayerData().job
    return job ~= nil and job.name == JC.Job
end

function JC.IsBoss()
    local job = RTCore.Functions.GetPlayerData().job
    return job ~= nil and job.name == JC.Job and job.isboss == true
end

-- ينتظر نتيجة callback من السيرفر
function JC.Await(name, ...)
    local p = promise.new()
    RTCore.Functions.TriggerCallback(name, function(result)
        p:resolve(result)
    end, ...)
    return Citizen.Await(p)
end

-- مثل Await لكن يعرض رسالة الخطأ تلقائياً ويرجع nil عند الفشل
function JC.Call(name, ...)
    local result = JC.Await(name, ...)
    if type(result) ~= 'table' then
        JC.Notify('تعذر الاتصال بالسيرفر', 'error')
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
