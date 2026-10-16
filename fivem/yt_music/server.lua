-- تشغيل رابط يوتيوب كصوت ثلاثي الأبعاد لكل اللاعبين
-- الصوت يطلع من مكان الأدمن (ويمشي معه)، وكل لاعب يسمعه أقوى كل ما قرب

local current = nil   -- { id, startedAt, follow, pos, volume, bucket }
local QB, ESX

local function isAdmin(src)
    if src == 0 then return true end
    for _, ace in ipairs(Config.AdminAces) do
        if IsPlayerAceAllowed(src, ace) then return true end
    end
    if GetResourceState('qb-core') == 'started' then
        QB = QB or exports['qb-core']:GetCoreObject()
        for _, perm in ipairs(Config.QBPermissions) do
            local ok, res = pcall(QB.Functions.HasPermission, src, perm)
            if ok and res then return true end
        end
    end
    if GetResourceState('qbx_core') == 'started' then
        for _, perm in ipairs(Config.QBPermissions) do
            local ok, res = pcall(function() return exports.qbx_core:HasPermission(src, perm) end)
            if ok and res then return true end
        end
    end
    if GetResourceState('es_extended') == 'started' then
        ESX = ESX or exports.es_extended:getSharedObject()
        local x = ESX.GetPlayerFromId(src)
        local group = x and x.getGroup()
        for _, g in ipairs(Config.ESXGroups) do
            if group == g then return true end
        end
    end
    return false
end

local function reply(src, msg)
    if src == 0 then print('[yt_music] ' .. msg) return end
    TriggerClientEvent('chat:addMessage', src, { args = { '🎵', msg } })
end

-- يطلع رقم المقطع من أي شكل رابط يوتيوب
local function videoId(url)
    if not url then return nil end
    local patterns = {
        'youtu%.be/([%w_%-]+)',
        '[?&]v=([%w_%-]+)',
        'youtube%.com/shorts/([%w_%-]+)',
        'youtube%.com/embed/([%w_%-]+)',
        'youtube%.com/live/([%w_%-]+)',
        '^([%w_%-]+)$',
    }
    for _, p in ipairs(patterns) do
        local id = url:match(p)
        if id and #id == 11 then return id end
    end
end

-- اللاعبين اللي في نفس العالم (لو عندك snow_world، اللي في عالم ثاني ما يسمع)
local function listeners()
    local list = {}
    for _, p in ipairs(GetPlayers()) do
        local id = tonumber(p)
        if not current or GetPlayerRoutingBucket(id) == current.bucket then list[#list + 1] = id end
    end
    return list
end

local function elapsed()
    return (GetGameTimer() - current.startedAt) / 1000
end

local function packet()
    return { id = current.id, at = elapsed(), pos = current.pos, follow = current.follow, volume = current.volume, loop = Config.Loop }
end

local function play(src, url, follow)
    if not isAdmin(src) then return end
    local id = videoId(url)
    if not id then return reply(src, 'حط رابط يوتيوب صحيح، مثال: /' .. Config.Commands.play .. ' https://youtu.be/xxxxxxxxxxx') end
    if src == 0 then return reply(src, 'لازم تكتب الأمر من داخل اللعبة') end

    local c = GetEntityCoords(GetPlayerPed(src))
    current = {
        id = id,
        startedAt = GetGameTimer(),
        follow = follow and src or nil,
        pos = { x = c.x, y = c.y, z = c.z },
        volume = current and current.volume or Config.Volume,
        bucket = GetPlayerRoutingBucket(src),
        admin = src,
    }
    for _, pid in ipairs(listeners()) do TriggerClientEvent('yt_music:play', pid, packet()) end
end

RegisterCommand(Config.Commands.play, function(src, args) play(src, args[1], true) end, false)
RegisterCommand(Config.Commands.here, function(src, args) play(src, args[1], false) end, false)

RegisterCommand(Config.Commands.stop, function(src)
    if not isAdmin(src) then return end
    current = nil
    TriggerClientEvent('yt_music:stop', -1)
end, false)

RegisterCommand(Config.Commands.volume, function(src, args)
    if not isAdmin(src) or not current then return end
    local v = tonumber(args[1])
    if not v then return end
    current.volume = math.max(0, math.min(100, v))
    TriggerClientEvent('yt_music:volume', -1, current.volume)
end, false)

-- لو الصوت يمشي مع الأدمن نرسل مكانه كل ثانية
CreateThread(function()
    while true do
        Wait(1000)
        if current and current.follow then
            if GetPlayerName(current.follow) then
                local c = GetEntityCoords(GetPlayerPed(current.follow))
                current.pos = { x = c.x, y = c.y, z = c.z }
                for _, pid in ipairs(listeners()) do TriggerClientEvent('yt_music:pos', pid, current.pos) end
            else
                current.follow = nil -- الأدمن طلع، الصوت يبقى في آخر مكان
            end
        end
    end
end)

-- اللي يدخل السيرفر والصوت شغال يسمعه من نفس الثانية
RegisterNetEvent('yt_music:sync', function()
    local src = source
    if current and GetPlayerRoutingBucket(src) == current.bucket then
        TriggerClientEvent('yt_music:play', src, packet())
    end
end)

-- المقطع خلص
RegisterNetEvent('yt_music:ended', function()
    if current and not Config.Loop and source == current.admin then
        current = nil
        TriggerClientEvent('yt_music:stop', -1)
    end
end)

-- المقطع ما يشتغل (صاحبه مانع تشغيله خارج يوتيوب)
RegisterNetEvent('yt_music:error', function(code)
    local src = source
    if current and src == current.admin then
        reply(src, ('هذا المقطع ما يشتغل خارج يوتيوب (خطأ %s)، جرب رابط ثاني'):format(tostring(code)))
    end
end)
