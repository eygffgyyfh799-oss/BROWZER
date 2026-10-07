-- الجلسات محفوظة حسب لوحة السيارة، عشان لو السيارة انحذفت ورجعت يكمل من نفس النقطة
local Sessions = {}
local LastEvent = {}

-- وقت بالثواني بدقة الملي ثانية (os.time دقته ثانية كاملة وتسبب تأخير بالمزامنة)
local function now() return GetGameTimer() / 1000.0 end

local function curPos(s)
    local p = s.pos
    if s.playing then p = p + (now() - s.startedAt) end
    if s.duration and s.duration > 0 and p > s.duration then p = s.duration end
    return p
end

local function snapshot(s)
    if not s then return nil end
    return {
        videoId = s.videoId,
        title   = s.title,
        pos     = curPos(s),
        playing = s.playing,
        volume  = s.volume,
        boost   = s.boost,
    }
end

local function getVehicle(netId)
    if not netId then return 0 end
    local veh = NetworkGetEntityFromNetworkId(netId)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return 0 end
    return veh
end

local function occupants(veh)
    local list = {}
    if veh == 0 then return list end
    for _, p in ipairs(GetPlayers()) do
        local ped = GetPlayerPed(p)
        if ped ~= 0 and GetVehiclePedIsIn(ped, false) == veh then
            list[#list + 1] = tonumber(p)
        end
    end
    return list
end

-- نرسل للكل (مو بس اللي بالسيارة) عشان اللي حولها يسمعون الصوت 3D
-- كل لاعب يحسب قوة الصوت عنده حسب بعده عن السيارة
local function broadcast(plate, target)
    local s = Sessions[plate]
    TriggerClientEvent('carplay:sync', target or -1, plate, s and s.netId, s and not s.off and snapshot(s) or nil)
end

local function rateLimited(src)
    local t = GetGameTimer()
    if LastEvent[src] and t - LastEvent[src] < 150 then return true end
    LastEvent[src] = t
    return false
end

local function canControl(src, netId)
    local veh = getVehicle(netId)
    if veh == 0 then return false end
    local ped = GetPlayerPed(src)
    if GetVehiclePedIsIn(ped, false) ~= veh then return false end
    if Config.DriverOnly and GetPedInVehicleSeat(veh, -1) ~= ped then
        TriggerClientEvent('carplay:notify', src, Config.Locale.driver_only)
        return false
    end
    return true
end

local function nearVehicle(src, netId, maxDist)
    local veh = getVehicle(netId)
    if veh == 0 then return false end
    local ped = GetPlayerPed(src)
    if ped == 0 then return false end
    return #(GetEntityCoords(ped) - GetEntityCoords(veh)) <= maxDist
end

local function validPlate(plate)
    return type(plate) == 'string' and #plate > 0 and #plate <= 12
end

local function endSong(s)
    s.pos, s.playing = 0, false
end

RegisterNetEvent('carplay:play', function(netId, plate, videoId, title, startAt)
    local src = source
    if rateLimited(src) or not validPlate(plate) then return end
    if type(videoId) ~= 'string' or not videoId:match('^[%w_%-]+$') or #videoId ~= 11 then
        TriggerClientEvent('carplay:notify', src, Config.Locale.invalid_link)
        return
    end
    if not canControl(src, netId) then return end

    local old = Sessions[plate]
    Sessions[plate] = {
        videoId   = videoId,
        title     = type(title) == 'string' and title:sub(1, 150) or nil,
        pos       = math.max(0, tonumber(startAt) or 0),
        playing   = true,
        startedAt = now(),
        volume    = old and old.volume or Config.DefaultVolume,
        boost     = old and old.boost or 1,
        netId     = netId,
        touched   = os.time(),
    }
    broadcast(plate)
end)

RegisterNetEvent('carplay:control', function(netId, plate, action, value)
    local src = source
    local s = Sessions[plate]
    if not s or s.off then return end

    if action == 'ended' then
        -- أي شخص قريب من السيارة يقدر يبلغ بنهاية المقطع
        if not s.playing or not nearVehicle(src, netId, Config.Sound.Range * 4) then return end
        endSong(s)
        broadcast(plate)
        return
    end

    if rateLimited(src) or not canControl(src, netId) then return end
    s.netId = netId
    s.touched = os.time()
    value = tonumber(value)

    if action == 'pause' then
        s.pos = curPos(s); s.playing = false
    elseif action == 'resume' then
        s.startedAt = now(); s.playing = true
    elseif action == 'seek' and value then
        s.pos = math.max(0, value); s.startedAt = now()
    elseif action == 'skip' and value then
        s.pos = math.max(0, curPos(s) + value); s.startedAt = now()
    elseif action == 'volume' and value then
        s.volume = math.max(0, math.min(100, math.floor(value)))
    elseif action == 'boost' and value then
        value = math.floor(value)
        if not Config.BoostLevels[value] then return end
        s.boost = value
    elseif action == 'stop' then
        Sessions[plate] = nil
    else
        return
    end
    broadcast(plate)
end)

RegisterNetEvent('carplay:title', function(plate, videoId, title, duration)
    local s = Sessions[plate]
    if not s or s.videoId ~= videoId or rateLimited(source) then return end
    if not s.title and type(title) == 'string' then s.title = title:sub(1, 150) end
    duration = tonumber(duration)
    if duration and duration > 0 then s.duration = duration end
end)

-- لاعب جديد (أو الواجهة انعادت) يطلب كل السيارات الشغالة عشان يسمع اللي حوله
RegisterNetEvent('carplay:requestAll', function()
    local src = source
    local all = {}
    for plate, s in pairs(Sessions) do
        if not s.off then all[plate] = { netId = s.netId, state = snapshot(s) } end
    end
    TriggerClientEvent('carplay:syncAll', src, all)
end)

RegisterNetEvent('carplay:enter', function(netId, plate)
    local src = source
    if not validPlate(plate) then return end
    local s = Sessions[plate]
    if not s then return end

    s.netId = netId
    s.exitToken = nil -- رجع أحد قبل ما تنطفي: نلغي المؤقت والأغنية كملت عادي
    s.touched = os.time()

    if s.off then
        -- كانت منطفية (مر عليها 3 دقايق): نكمل من آخر نقطة انحفظت
        s.off = false
        if s.resumeOnEnter and Config.ResumeAfterOff then
            s.playing = true
            s.startedAt = now()
            TriggerClientEvent('carplay:notify', src, Config.Locale.resumed)
        end
        s.resumeOnEnter = false
    end
    broadcast(plate)
end)

local function scheduleOff(plate, netId)
    local s = Sessions[plate]
    if not s then return end
    CreateThread(function()
        Wait(800) -- نعطي السيرفر وقت يحدّث أن اللاعب نزل
        if Sessions[plate] ~= s or s.off or s.exitToken then return end
        if #occupants(getVehicle(netId or s.netId)) > 0 then return end -- باقي أحد داخل

        -- ما بقى أحد: CarPlay تظل شغالة (واللي حول السيارة يسمعونها) وبعدها تنطفي وتحفظ النقطة
        local token = {}
        s.exitToken = token
        SetTimeout(Config.OffAfterMinutes * 60000, function()
            if Sessions[plate] ~= s or s.exitToken ~= token then return end
            s.exitToken = nil
            s.pos = curPos(s)
            s.resumeOnEnter = s.playing
            s.playing = false
            s.off = true
            s.touched = os.time()
            broadcast(plate) -- نوقف الصوت عند اللي حول السيارة
        end)
    end)
end

RegisterNetEvent('carplay:exit', function(netId, plate)
    if validPlate(plate) then scheduleOff(plate, netId) end
end)

-- لو لاعب طلع من السيرفر وهو بالسيارة، نعامله كأنه نزل
AddEventHandler('playerDropped', function()
    LastEvent[source] = nil
    for plate, s in pairs(Sessions) do
        if s.netId and not s.exitToken and not s.off then scheduleOff(plate, s.netId) end
    end
end)

-- نهاية الأغنية حسب مدتها (حتى لو ما أحد قريب يبلغ) + تنظيف الجلسات القديمة
CreateThread(function()
    while true do
        Wait(1000)
        local t = os.time()
        for plate, s in pairs(Sessions) do
            if s.playing and s.duration and s.duration > 0 and curPos(s) >= s.duration then
                endSong(s)
                broadcast(plate)
            elseif s.off and t - (s.touched or t) > Config.ForgetAfterHours * 3600 then
                Sessions[plate] = nil
            end
        end
    end
end)
