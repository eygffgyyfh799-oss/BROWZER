local ignored = {}
for _, model in ipairs(Config.IgnoredModels) do
    ignored[GetHashKey(model)] = true
end

local cleanupRunning = false

local function notify(target, msg)
    TriggerClientEvent('chat:addMessage', target, { args = { Config.Prefix .. msg } })
end

local function isAdmin(src)
    return src == 0 or IsPlayerAceAllowed(src, Config.AdminAce)
end

local function isOccupied(veh)
    for seat = -1, 14 do
        if GetPedInVehicleSeat(veh, seat) ~= 0 then
            return true
        end
    end
    return false
end

local function isNearPlayer(coords, radius)
    for _, id in ipairs(GetPlayers()) do
        local ped = GetPlayerPed(id)
        if ped ~= 0 and #(GetEntityCoords(ped) - coords) <= radius then
            return true
        end
    end
    return false
end

-- يحذف كل السيارات الفاضية ويرجع عدد المحذوف
local function deleteEmptyVehicles()
    local count = 0
    for _, veh in ipairs(GetAllVehicles()) do
        if DoesEntityExist(veh)
            and not ignored[GetEntityModel(veh)]
            and not isOccupied(veh)
            and not (Config.SafeRadius > 0 and isNearPlayer(GetEntityCoords(veh), Config.SafeRadius)) then
            DeleteEntity(veh)
            count = count + 1
        end
    end
    return count
end

local function formatTime(seconds)
    if seconds >= 60 then
        return ('%d دقيقة'):format(math.floor(seconds / 60))
    end
    return ('%d ثانية'):format(seconds)
end

-- عد تنازلي مع تنبيهات ثم حذف
local function runCleanup()
    if cleanupRunning then return false end
    cleanupRunning = true

    local warnings = {}
    for _, w in ipairs(Config.Warnings) do warnings[#warnings + 1] = w end
    table.sort(warnings, function(a, b) return a > b end)

    for i, remaining in ipairs(warnings) do
        notify(-1, ('^1سيتم حذف السيارات الفاضية بعد %s، اركب سيارتك!'):format(formatTime(remaining)))
        Wait((remaining - (warnings[i + 1] or 0)) * 1000)
    end

    local count = deleteEmptyVehicles()
    notify(-1, ('^2تم حذف %d سيارة.'):format(count))
    cleanupRunning = false
    return true
end

-- الحذف التلقائي
if Config.IntervalMinutes > 0 then
    CreateThread(function()
        while true do
            Wait(Config.IntervalMinutes * 60 * 1000)
            runCleanup()
        end
    end)
end

-- /dvall : حذف كل السيارات الفاضية (مع عد تنازلي)
-- /dvall now : حذف فوري بدون عد تنازلي
RegisterCommand('dvall', function(src, args)
    if not isAdmin(src) then
        return notify(src, '^1ما عندك صلاحية.')
    end
    if args[1] == 'now' then
        notify(-1, ('^2تم حذف %d سيارة.'):format(deleteEmptyVehicles()))
    elseif not runCleanup() then
        notify(src, '^1فيه حذف شغال حالياً.')
    end
end, false)

-- /dv [مسافة] : حذف السيارة اللي راكبها أو القريبة منك
RegisterCommand('dv', function(src, args)
    if src == 0 then return print('هذا الأمر للاعبين داخل اللعبة فقط') end
    if not isAdmin(src) then
        return notify(src, '^1ما عندك صلاحية.')
    end

    local ped = GetPlayerPed(src)
    local current = GetVehiclePedIsIn(ped, false)
    if current ~= 0 then
        DeleteEntity(current)
        return notify(src, '^2تم حذف السيارة.')
    end

    local radius = tonumber(args[1]) or Config.DefaultDvRadius
    local coords = GetEntityCoords(ped)
    local count = 0
    for _, veh in ipairs(GetAllVehicles()) do
        if #(GetEntityCoords(veh) - coords) <= radius and not isOccupied(veh) then
            DeleteEntity(veh)
            count = count + 1
        end
    end
    notify(src, count > 0 and ('^2تم حذف %d سيارة.'):format(count) or '^1ما فيه سيارات قريبة.')
end, false)
