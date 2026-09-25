local ignored = {}
for _, model in ipairs(Config.IgnoredModels) do
    ignored[GetHashKey(model)] = true
end

local cleanupRunning = false

local function normalizePlate(plate)
    return plate and plate:gsub('%s+', ''):upper() or ''
end

local function getOwnedTable()
    local fw = Config.Framework
    if fw == 'auto' then
        if GetResourceState('es_extended') == 'started' then
            fw = 'esx'
        elseif GetResourceState('qb-core') == 'started' then
            fw = 'qb'
        end
    end
    if fw == 'esx' then return 'owned_vehicles' end
    if fw == 'qb' then return 'player_vehicles' end
    return nil
end

-- يرجع جدول فيه كل اللوحات المحمية (المملوكة + اللي في الكونفق)
local function getProtectedPlates()
    local plates = {}
    for _, plate in ipairs(Config.ProtectedPlates) do
        plates[normalizePlate(plate)] = true
    end
    if not Config.ProtectOwned then return plates end

    local tbl = getOwnedTable()
    if not tbl or GetResourceState('oxmysql') ~= 'started' then
        print('^1[history_deletecars] ما قدرت أقرأ السيارات المملوكة (تأكد من oxmysql و Config.Framework)^0')
        return nil
    end

    local p = promise.new()
    exports.oxmysql:query(('SELECT plate FROM %s'):format(tbl), {}, function(rows)
        p:resolve(rows or {})
    end)
    for _, row in ipairs(Citizen.Await(p)) do
        plates[normalizePlate(row.plate)] = true
    end
    return plates
end

local function isProtected(veh, protectedPlates)
    return ignored[GetEntityModel(veh)]
        or protectedPlates[normalizePlate(GetVehicleNumberPlateText(veh))]
end

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
    local protectedPlates = getProtectedPlates()
    -- إذا ما قدرنا نعرف المملوكة، نوقف الحذف عشان ما ننحذف سيارات لاعبين بالغلط
    if not protectedPlates then return 0 end

    local count = 0
    for _, veh in ipairs(GetAllVehicles()) do
        if DoesEntityExist(veh)
            and not isProtected(veh, protectedPlates)
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

    local protectedPlates = getProtectedPlates()
    if not protectedPlates then
        return notify(src, '^1ما قدرت أتحقق من السيارات المملوكة، تم إلغاء الحذف.')
    end

    local ped = GetPlayerPed(src)
    local current = GetVehiclePedIsIn(ped, false)
    if current ~= 0 then
        if isProtected(current, protectedPlates) then
            return notify(src, '^1هذي السيارة مملوكة لاعب وما تنحذف.')
        end
        DeleteEntity(current)
        return notify(src, '^2تم حذف السيارة.')
    end

    local radius = tonumber(args[1]) or Config.DefaultDvRadius
    local coords = GetEntityCoords(ped)
    local count = 0
    for _, veh in ipairs(GetAllVehicles()) do
        if #(GetEntityCoords(veh) - coords) <= radius
            and not isOccupied(veh)
            and not isProtected(veh, protectedPlates) then
            DeleteEntity(veh)
            count = count + 1
        end
    end
    notify(src, count > 0 and ('^2تم حذف %d سيارة.'):format(count) or '^1ما فيه سيارات قريبة.')
end, false)
