-- النواة: العوالم، نقل اللاعبين، الحفظ، والأوامر
-- كل عالم = Routing Bucket منفصل، فاللي في عالم ما يشوف ولا يسمع ولا يتأثر باللي في عالم ثاني

Worlds = {
    members = {},   -- [serverId] = مفتاح العالم (snow, desert ...)
    index = {},     -- [مفتاح العالم] = رقم ترتيبه (للراديو والمكالمات)
    hooks = {},     -- دوال تشتغل لما لاعب ينتقل
}

local members = Worlds.members
local pending = {}  -- عوالم محفوظة تنتظر اللاعب يجهز

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

function Worlds.reply(src, msg)
    if src == 0 then
        print('[worlds] ' .. msg)
    else
        TriggerClientEvent('chat:addMessage', src, { color = { 120, 200, 255 }, args = { 'العوالم', msg } })
    end
end

function Worlds.allowed(src)
    return src == 0 or IsPlayerAceAllowed(src, Config.Ace)
end

local function license(id)
    return GetPlayerIdentifierByType(id, 'license')
end

local function save(id, key)
    if not Config.SaveWorld then return end
    local lic = license(id)
    if not lic then return end
    if key == 'main' then
        DeleteResourceKvp('world:' .. lic)
    else
        SetResourceKvp('world:' .. lic, key)
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

function Worlds.move(id, key, silent)
    if key ~= 'main' and not Config.Worlds[key] then return false end
    local old = Worlds.of(id)
    if old == key then return false end

    local bucket = key == 'main' and 0 or Config.Worlds[key].bucket
    members[id] = key ~= 'main' and key or nil
    moveVehicle(id, bucket)
    setBucket(id, bucket)

    local state = Player(id).state
    state:set('world', key ~= 'main' and key or false, true)
    state:set('snowWorld', key ~= 'main', true) -- للتوافق مع missile_city
    save(id, key)

    for _, hook in ipairs(Worlds.hooks) do hook(id, key, old) end
    if not silent then
        TriggerClientEvent('chat:addMessage', id, { color = { 120, 200, 255 }, args = { 'العوالم', 'انتقلت إلى ' .. Worlds.label(key) } })
    end
    return true
end

-- اللاعب جهز (اختار شخصيته / نزل)، نرجعه لعالمه المحفوظ
RegisterNetEvent('worlds:ready', function()
    local src = source
    local key = pending[src]
    pending[src] = nil
    if key and Config.Worlds[key] and not members[src] then
        Worlds.move(src, key, true)
        Worlds.reply(src, 'رجعت إلى عالمك: ' .. Worlds.label(key))
    end
end)

AddEventHandler('playerJoining', function()
    local src = source
    if not Config.SaveWorld then return end
    local lic = license(src)
    local key = lic and GetResourceKvpString('world:' .. lic)
    if key and Config.Worlds[key] then pending[src] = key end
end)

AddEventHandler('playerDropped', function()
    members[source] = nil
    pending[source] = nil
end)

-- لو سكربت ثاني رجّع اللاعب للعالم العادي (مثلاً طلع من شقة أو اختار شخصيته) نرجعه لعالمه
-- لو حطه في عالم ثالث (بيت/شقة) نخليه، ولما يطلع منه يرجع لعالمه
CreateThread(function()
    while true do
        Wait(3000)
        for id, key in pairs(members) do
            if not GetPlayerName(id) then
                members[id] = nil
            elseif GetPlayerRoutingBucket(id) == 0 then
                setBucket(id, Config.Worlds[key].bucket)
            end
        end
    end
end)

-- لو انطفى السكربت نرجع الكل للعالم العادي (بدون ما نمسح الحفظ)
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for id in pairs(members) do
        moveVehicle(id, 0)
        setBucket(id, 0)
        Player(id).state:set('world', false, true)
        Player(id).state:set('snowWorld', false, true)
    end
end)

-- لو السكربت انعاد تشغيله، اللاعبين الموجودين يرجعون لعوالمهم المحفوظة
AddEventHandler('onResourceStart', function(res)
    if res ~= GetCurrentResourceName() or not Config.SaveWorld then return end
    SetTimeout(1000, function()
        for _, p in ipairs(GetPlayers()) do
            local id = tonumber(p)
            local lic = license(id)
            local key = lic and GetResourceKvpString('world:' .. lic)
            if key and Config.Worlds[key] then Worlds.move(id, key, true) end
        end
    end)
end)

-- ===================== الأوامر =====================

local function resolveTarget(src, arg)
    local id = tonumber(arg) or (src ~= 0 and src or nil)
    if not id or not GetPlayerName(id) then return nil end
    return id
end

local function worldKeys()
    local keys = { 'main' }
    for key in pairs(Config.Worlds) do keys[#keys + 1] = key end
    return table.concat(keys, ', ')
end

-- /world [آيدي] [عالم]
RegisterCommand(Config.Commands.world, function(src, args)
    if not Worlds.allowed(src) then return end
    local id, key
    if #args >= 2 then
        id, key = resolveTarget(src, args[1]), args[2]
    elseif tonumber(args[1]) then
        id = resolveTarget(src, args[1])
        if not id then return Worlds.reply(src, 'ما فيه لاعب بهالآيدي') end
        return Worlds.reply(src, ('%s في %s'):format(GetPlayerName(id), Worlds.label(Worlds.of(id))))
    else
        id, key = resolveTarget(src, nil), args[1]
    end

    if not id then return Worlds.reply(src, 'ما فيه لاعب بهالآيدي') end
    if not key or (key ~= 'main' and not Config.Worlds[key]) then
        return Worlds.reply(src, 'العوالم: ' .. worldKeys() .. ' — مثال: /' .. Config.Commands.world .. ' 12 snow')
    end
    if Worlds.move(id, key) then
        Worlds.reply(src, ('تم نقل %s إلى %s'):format(GetPlayerName(id), Worlds.label(key)))
    else
        Worlds.reply(src, ('%s أصلاً في %s'):format(GetPlayerName(id), Worlds.label(key)))
    end
end, false)

RegisterCommand(Config.Commands.snow, function(src, args)
    if not Worlds.allowed(src) then return end
    local id = resolveTarget(src, args[1])
    if not id then return Worlds.reply(src, 'ما فيه لاعب بهالآيدي') end
    if Worlds.move(id, 'snow') then Worlds.reply(src, 'تم نقل ' .. GetPlayerName(id) .. ' إلى ' .. Worlds.label('snow')) end
end, false)

RegisterCommand(Config.Commands.unsnow, function(src, args)
    if not Worlds.allowed(src) then return end
    local id = resolveTarget(src, args[1])
    if not id then return Worlds.reply(src, 'ما فيه لاعب بهالآيدي') end
    if Worlds.move(id, 'main') then Worlds.reply(src, 'تم إرجاع ' .. GetPlayerName(id) .. ' للعالم العادي') end
end, false)

-- /worlds
RegisterCommand(Config.Commands.list, function(src)
    if not Worlds.allowed(src) then return end
    local lines = {}
    for key in pairs(Config.Worlds) do
        local names = {}
        for _, id in ipairs(Worlds.players(key)) do names[#names + 1] = ('%s (%d)'):format(GetPlayerName(id), id) end
        lines[#lines + 1] = ('%s [%s]: %s'):format(Worlds.label(key), key, #names == 0 and 'فاضي' or table.concat(names, '، '))
    end
    for _, line in ipairs(lines) do Worlds.reply(src, line) end
end, false)

-- /worldall [عالم]
RegisterCommand(Config.Commands.all, function(src, args)
    if not Worlds.allowed(src) then return end
    local only = args[1]
    local n = 0
    for id, key in pairs(members) do
        if not only or only == key then
            Worlds.move(id, 'main')
            n = n + 1
        end
    end
    Worlds.reply(src, ('تم إرجاع %d لاعب للعالم العادي'):format(n))
end, false)

-- ===================== exports للسكربتات الثانية =====================
-- exports.snow_world:GetWorld(source)              -> 'main' أو 'snow' ...
-- exports.snow_world:SetWorld(source, 'snow')      -> ينقل اللاعب
-- exports.snow_world:IsSameWorld(a, b)
-- exports.snow_world:GetPlayersInWorld('snow')
-- exports.snow_world:TriggerWorldEvent(source, 'event', ...)  يرسل الحدث بس للي في نفس عالم source
exports('GetWorld', function(id) return Worlds.of(id) end)
exports('SetWorld', function(id, key) return Worlds.move(id, key) end)
exports('IsSameWorld', function(a, b) return Worlds.of(a) == Worlds.of(b) end)
exports('GetPlayersInWorld', function(key) return Worlds.players(key) end)
exports('TriggerWorldEvent', function(src, eventName, ...)
    for _, id in ipairs(Worlds.players(Worlds.of(src))) do TriggerClientEvent(eventName, id, ...) end
end)
