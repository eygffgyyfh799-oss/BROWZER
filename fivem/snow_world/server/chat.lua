-- أوامر الشات والبلاغات والشرطة، كلها حسب العالم

-- بلاغ لشرطة عالم معين (تقدر تستخدمه من أي سكربت بلاغات)
-- exports.snow_world:SendWorldDispatch(source, { title = '...', text = '...', coords = vector3(...) })
local function dispatch(src, data)
    local coords = data.coords or GetEntityCoords(GetPlayerPed(src))
    local alert = {
        title = data.title or 'بلاغ',
        text = data.text or '',
        caller = data.caller,
        coords = { x = coords.x, y = coords.y, z = coords.z },
        world = Worlds.label(Worlds.of(src)),
    }
    local cops = Worlds.police(Worlds.of(src))
    for _, id in ipairs(cops) do TriggerClientEvent('worlds:dispatch', id, alert) end
    return #cops
end
exports('SendWorldDispatch', dispatch)

-- ===================== الأوامر =====================

local C = Config.ChatCommands
local lastReport = {}

local function nearby(src, range)
    local list = {}
    local from = GetEntityCoords(GetPlayerPed(src))
    for _, id in ipairs(Worlds.players(Worlds.of(src))) do
        if #(GetEntityCoords(GetPlayerPed(id)) - from) <= range then list[#list + 1] = id end
    end
    return list
end

local function send(ids, color, title, text)
    for _, id in ipairs(ids) do
        TriggerClientEvent('chat:addMessage', id, { color = color, multiline = true, args = { title, text } })
    end
end

if C.me then
    RegisterCommand(C.me, function(src, args)
        if src == 0 or #args == 0 then return end
        send(nearby(src, Config.MeRange), { 200, 130, 255 }, '* ' .. Framework.charName(src), table.concat(args, ' '))
    end, false)
end

if C['do'] then
    RegisterCommand(C['do'], function(src, args)
        if src == 0 or #args == 0 then return end
        send(nearby(src, Config.MeRange), { 120, 220, 160 }, '** ' .. Framework.charName(src), table.concat(args, ' '))
    end, false)
end

if C.ooc then
    RegisterCommand(C.ooc, function(src, args)
        if src == 0 or #args == 0 then return end
        send(Worlds.players(Worlds.of(src)), { 170, 170, 170 }, ('[OOC] %s (%d)'):format(GetPlayerName(src), src), table.concat(args, ' '))
    end, false)
end

if C['911'] then
    RegisterCommand(C['911'], function(src, args)
        if src == 0 then return end
        if #args == 0 then return Worlds.reply(src, 'اكتب البلاغ، مثال: /' .. C['911'] .. ' فيه حادث عند البنك') end
        local now = os.time()
        if lastReport[src] and now - lastReport[src] < Config.ReportCooldown then
            return Worlds.reply(src, ('انتظر %d ثانية قبل بلاغ ثاني'):format(Config.ReportCooldown - (now - lastReport[src])))
        end
        lastReport[src] = now

        local n = dispatch(src, { title = '🚨 بلاغ 911', text = table.concat(args, ' '), caller = ('%s (%d)'):format(Framework.charName(src), src) })
        Worlds.reply(src, n > 0 and ('تم إرسال بلاغك لـ %d شرطي'):format(n) or 'ما فيه شرطة متواجدين في عالمك')
    end, false)
end

AddEventHandler('playerDropped', function() lastReport[source] = nil end)
