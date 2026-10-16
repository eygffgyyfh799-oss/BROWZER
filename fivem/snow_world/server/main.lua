-- النواة: العوالم، نقل اللاعبين، القفل، والأوامر
-- كل عالم = Routing Bucket منفصل، فاللي في عالم ما يشوف ولا يسمع ولا يتأثر باللي في عالم ثاني
--
-- التسجيل حسب رقم الهوية ومحفوظ في قاعدة البيانات:
-- اللي ينضاف لعالم يدخله كل ما يدخل بشخصيته، وما يقدر يطلع منه إلا بأمر أدمن god
-- ما فيه أي طريقة ثانية للدخول أو الخروج (لا بوابات ولا أوامر للاعبين)

Worlds = {
    members = {},   -- [serverId] = مفتاح العالم (للمتصلين الحين)
    index = {},     -- [مفتاح العالم] = رقم ترتيبه (للراديو والمكالمات)
    hooks = {},     -- دوال تشتغل لما لاعب ينتقل
}

local members = Worlds.members

-- ترتيب ثابت للعوالم حسب رقم الـ bucket
do
    local keys = {}
    for key, w in pairs(Config.Worlds) do
        keys[#keys + 1] = key
        SetRoutingBucketPopulationEnabled(w.bucket, w.population ~= false)
        SetRoutingBucketEntityLockdownMode(w.bucket, 'relaxed')
    end
    table.sort(keys, function(a, b) return Config.Worlds[a].bucket < Config.Worlds[b].bucket end)
    for i, key in ipairs(keys) do Worlds.index[key] = i end
end

-- ===================== أدوات =====================

function Worlds.of(id)
    return members[id] or 'main'
end

function Worlds.label(key)
    return key == 'main' and 'العالم العادي' or (Config.Worlds[key] and Config.Worlds[key].label or key)
end

function Worlds.players(key)
    local list = {}
    for _, p in ipairs(GetPlayers()) do
        local id = tonumber(p)
        if Worlds.of(id) == key then list[#list + 1] = id end
    end
    return list
end

function Worlds.any()
    return next(members) ~= nil
end

function Worlds.police(key)
    local list = {}
    for _, id in ipairs(Worlds.players(key)) do
        if Framework.isPolice(id) then list[#list + 1] = id end
    end
    return list
end

function Worlds.reply(src, msg)
    if src == 0 then
        print('[worlds] ' .. msg)
    else
        TriggerClientEvent('chat:addMessage', src, { color = { 120, 200, 255 }, args = { 'العوالم', msg } })
    end
end

local function setBucket(id, bucket)
    -- pma-voice لازم يعرف بتغيير العالم عشان الصوت القريب ينفصل صح
    if Config.Isolation.Voice and GetResourceState('pma-voice') == 'started' then
        exports['pma-voice']:updateRoutingBucket(id, bucket)
    else
        SetPlayerRoutingBucket(id, bucket)
    end
end

-- السيارة تنتقل مع اللاعب لو هو السايق ولحاله فيها
local function moveVehicle(id, bucket)
    local ped = GetPlayerPed(id)
    local veh = GetVehiclePedIsIn(ped, false)
    if veh == 0 or GetPedInVehicleSeat(veh, -1) ~= ped then return end
    for seat = 0, 14 do
        local other = GetPedInVehicleSeat(veh, seat)
        if other ~= 0 and other ~= ped then return end
    end
    SetEntityRoutingBucket(veh, bucket)
end

-- ===================== النقل =====================

local function move(id, key, notify)
    local old = Worlds.of(id)
    if old == key then return end

    local bucket = key == 'main' and 0 or Config.Worlds[key].bucket
    members[id] = key ~= 'main' and key or nil
    moveVehicle(id, bucket)
    setBucket(id, bucket)

    local state = Player(id).state
    state:set('world', key ~= 'main' and key or false, true)
    state:set('snowWorld', key ~= 'main', true) -- للتوافق مع missile_city

    for _, hook in ipairs(Worlds.hooks) do hook(id, key, old) end
    if notify then
        TriggerClientEvent('chat:addMessage', id, { color = { 120, 200, 255 }, args = { 'العوالم', 'انتقلت إلى ' .. Worlds.label(key) } })
    end
end

-- يطبق عالم اللاعب حسب قاعدة البيانات (لما يختار شخصيته)
local function apply(id, notify)
    local cid = Framework.citizenId(id)
    local entry = cid and DB.get(cid)
    local key = entry and Config.Worlds[entry.world] and entry.world or 'main'
    move(id, key, notify)
end

-- ===================== دخول وخروج الشخصيات =====================

-- QBCore و Qbox
AddEventHandler('QBCore:Server:PlayerLoaded', function(Player)
    local id = Player and Player.PlayerData and Player.PlayerData.source
    if id then SetTimeout(500, function() apply(id, false) end) end
end)

-- خرج من شخصيته (رجع لاختيار الشخصيات): نشيل جو العالم، وسكربت الشخصيات يحطه في مكانه
local function unload(id)
    if not members[id] then return end
    members[id] = nil
    Player(id).state:set('world', false, true)
    Player(id).state:set('snowWorld', false, true)
end
AddEventHandler('QBCore:Server:OnPlayerUnload', unload)
AddEventHandler('esx:playerLogout', unload)

-- ESX
AddEventHandler('esx:playerLoaded', function(id)
    SetTimeout(500, function() apply(id, false) end)
end)

-- بدون فريمورك: حسب license لما يدخل السيرفر
AddEventHandler('playerJoining', function()
    local src = source
    if Framework.name() == 'none' then SetTimeout(3000, function() apply(src, false) end) end
end)

AddEventHandler('playerDropped', function()
    members[source] = nil
end)

-- القفل: لو أي سكربت ثاني رجّعه للعالم العادي، نرجعه لعالمه
-- لو حطه في عالم ثالث (بيت/شقة/اختيار شخصية) نخليه، ولما يرجع للعادي نرجعه لعالمه
CreateThread(function()
    while true do
        Wait(2000)
        for id, key in pairs(members) do
            if not GetPlayerName(id) then
                members[id] = nil
            elseif GetPlayerRoutingBucket(id) == 0 then
                setBucket(id, Config.Worlds[key].bucket)
            end
        end
    end
end)

AddEventHandler('onResourceStart', function(res)
    if res ~= GetCurrentResourceName() then return end
    CreateThread(function()
        DB.load()
        -- اللاعبين المتصلين الحين يرجعون لعوالمهم
        Wait(1000)
        for _, p in ipairs(GetPlayers()) do apply(tonumber(p), false) end
    end)
end)

-- لو انطفى السكربت نرجع الكل للعالم العادي مؤقتاً (التسجيل يبقى في قاعدة البيانات)
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for id in pairs(members) do
        moveVehicle(id, 0)
        setBucket(id, 0)
        Player(id).state:set('world', false, true)
        Player(id).state:set('snowWorld', false, true)
    end
end)

-- ===================== أوامر الأدمن (god بس) =====================

local C = Config.Commands

local function guard(src)
    if Framework.isGod(src) then return true end
    if src ~= 0 then Worlds.reply(src, 'هذا الأمر لأدمن god بس') end
    return false
end

local function adminName(src)
    if src == 0 then return 'console' end
    return ('%s (%s)'):format(GetPlayerName(src), Framework.citizenId(src) or src)
end

local function worldKeys()
    local keys = {}
    for key in pairs(Config.Worlds) do keys[#keys + 1] = key end
    table.sort(keys)
    return table.concat(keys, ', ')
end

-- /setworld [رقم الهوية] [عالم]
RegisterCommand(C.add, function(src, args) CreateThread(function()
    if not guard(src) then return end
    local cid, key = args[1], args[2]
    if not cid or not key or not Config.Worlds[key] then
        return Worlds.reply(src, ('الاستخدام: /%s [رقم الهوية] [عالم] — العوالم: %s'):format(C.add, worldKeys()))
    end

    local online = Framework.sourceOf(cid)
    local name = online and Framework.charName(online) or DB.lookupName(cid)
    if name == nil then
        return Worlds.reply(src, 'رقم الهوية ' .. cid .. ' مو موجود')
    end

    DB.set(cid, key, name, adminName(src))
    if online then move(online, key, true) end
    Worlds.reply(src, ('تم تسجيل %s [%s] في %s %s'):format(name, cid, Worlds.label(key), online and '(متصل، انتقل الحين)' or '(مطفي، بيدخله أول ما يدخل)'))
end) end, false)

-- /unsetworld [رقم الهوية]
RegisterCommand(C.remove, function(src, args) CreateThread(function()
    if not guard(src) then return end
    local cid = args[1]
    if not cid then return Worlds.reply(src, ('الاستخدام: /%s [رقم الهوية]'):format(C.remove)) end
    local entry = DB.get(cid)
    if not entry then return Worlds.reply(src, 'رقم الهوية ' .. cid .. ' مو مسجل في أي عالم') end

    DB.remove(cid)
    local online = Framework.sourceOf(cid)
    if online then move(online, 'main', true) end
    Worlds.reply(src, ('تم إخراج %s [%s] من %s %s'):format(entry.name or '', cid, Worlds.label(entry.world), online and '(رجع للعادي الحين)' or ''))
end) end, false)

-- /worldlist [عالم]
RegisterCommand(C.list, function(src, args)
    if not guard(src) then return end
    local only = args[1]
    local n = 0
    for cid, e in pairs(DB.members) do
        if not only or e.world == only then
            n = n + 1
            local online = Framework.sourceOf(cid)
            Worlds.reply(src, ('%s [%s] — %s — %s — أضافه %s %s'):format(
                e.name or '', cid, Worlds.label(e.world), online and ('🟢 متصل (' .. online .. ')') or '⚫ مطفي', e.added_by or '?', e.added_at or ''))
        end
    end
    if n == 0 then Worlds.reply(src, 'ما فيه أحد مسجل') end
end, false)

-- /checkworld [رقم الهوية]
RegisterCommand(C.check, function(src, args)
    if not guard(src) then return end
    local cid = args[1]
    if not cid then return Worlds.reply(src, ('الاستخدام: /%s [رقم الهوية]'):format(C.check)) end
    local e = DB.get(cid)
    Worlds.reply(src, e and ('%s [%s] مسجل في %s'):format(e.name or '', cid, Worlds.label(e.world)) or (cid .. ' في العالم العادي'))
end, false)

-- ===================== exports للسكربتات الثانية =====================
-- exports.snow_world:GetWorld(source)              -> 'main' أو 'snow' ...
-- exports.snow_world:IsSameWorld(a, b)
-- exports.snow_world:GetPlayersInWorld('snow')
-- exports.snow_world:GetPoliceInWorld('snow') / GetPoliceCount(source)
-- exports.snow_world:TriggerWorldEvent(source, 'event', ...)  يرسل الحدث بس للي في نفس عالم source
exports('GetWorld', function(id) return Worlds.of(id) end)
exports('IsSameWorld', function(a, b) return Worlds.of(a) == Worlds.of(b) end)
exports('GetPlayersInWorld', function(key) return Worlds.players(key) end)
exports('GetPoliceInWorld', function(key) return Worlds.police(key) end)
exports('GetPoliceCount', function(src) return #Worlds.police(Worlds.of(src)) end)
exports('TriggerWorldEvent', function(src, eventName, ...)
    for _, id in ipairs(Worlds.players(Worlds.of(src))) do TriggerClientEvent(eventName, id, ...) end
end)
