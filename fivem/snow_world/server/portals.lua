-- البوابات: تمشي لها وتضغط E وتنتقل للعالم، ولو twoWay نفس المكان داخل العالم يرجعك
-- البوابات اللي تنحط بأمر /portal تنحفظ في portals.json

local FILE = 'portals.json'
local portals = {}
local lastUse = {}

local function sync()
    local list = {}
    for i, p in ipairs(portals) do
        list[i] = { id = i, world = p.world, x = p.x, y = p.y, z = p.z, twoWay = p.twoWay, blip = p.blip, label = Worlds.label(p.world) }
    end
    GlobalState.worldPortals = list
end

local function saveFile()
    local saved = {}
    for _, p in ipairs(portals) do
        if not p.static then saved[#saved + 1] = { world = p.world, x = p.x, y = p.y, z = p.z, twoWay = p.twoWay, ace = p.ace, blip = p.blip } end
    end
    SaveResourceFile(GetCurrentResourceName(), FILE, json.encode(saved, { indent = true }), -1)
end

local function load()
    portals = {}
    for _, p in ipairs(Config.Portals) do
        if Config.Worlds[p.world] then
            portals[#portals + 1] = { world = p.world, x = p.coords.x, y = p.coords.y, z = p.coords.z, twoWay = p.twoWay ~= false, ace = p.ace, blip = p.blip, static = true }
        end
    end
    local raw = LoadResourceFile(GetCurrentResourceName(), FILE)
    local ok, saved = pcall(json.decode, raw or '[]')
    if ok and type(saved) == 'table' then
        for _, p in ipairs(saved) do
            if Config.Worlds[p.world] then portals[#portals + 1] = p end
        end
    end
    sync()
end

load()

-- اللاعب ضغط E عند بوابة
RegisterNetEvent('worlds:usePortal', function(index)
    local src = source
    local p = portals[tonumber(index) or 0]
    if not p then return end

    local now = os.time()
    if lastUse[src] and now - lastUse[src] < Config.PortalCooldown then return end
    if p.ace and not IsPlayerAceAllowed(src, p.ace) then
        return Worlds.reply(src, 'هذي البوابة مقفلة عليك')
    end

    -- نتأكد إنه فعلاً عند البوابة
    local pos = GetEntityCoords(GetPlayerPed(src))
    if #(pos - vector3(p.x, p.y, p.z)) > 4.0 then return end

    local current = Worlds.of(src)
    local target
    if current == 'main' then
        target = p.world
    elseif current == p.world and p.twoWay then
        target = 'main'
    else
        return
    end

    lastUse[src] = now
    Worlds.move(src, target)
end)

AddEventHandler('playerDropped', function() lastUse[source] = nil end)

-- /portal add [عالم] [صلاحية اختيارية]  |  /portal del  |  /portal list
RegisterCommand(Config.Commands.portal, function(src, args)
    if src == 0 or not Worlds.allowed(src) then return end
    local action = args[1]
    local pos = GetEntityCoords(GetPlayerPed(src))

    if action == 'add' then
        local key = args[2]
        if not Config.Worlds[key] then
            return Worlds.reply(src, 'اكتب اسم العالم، مثال: /' .. Config.Commands.portal .. ' add snow')
        end
        portals[#portals + 1] = { world = key, x = pos.x, y = pos.y, z = pos.z - 1.0, twoWay = true, ace = args[3] }
        saveFile()
        sync()
        Worlds.reply(src, ('تم إضافة بوابة إلى %s (رقم %d)'):format(Worlds.label(key), #portals))

    elseif action == 'del' then
        local best, bestDist
        for i, p in ipairs(portals) do
            local d = #(pos - vector3(p.x, p.y, p.z))
            if not p.static and (not bestDist or d < bestDist) then best, bestDist = i, d end
        end
        if not best or bestDist > 10.0 then
            return Worlds.reply(src, 'ما فيه بوابة قريبة منك (البوابات الثابتة في config.lua تنحذف من هناك)')
        end
        table.remove(portals, best)
        saveFile()
        sync()
        Worlds.reply(src, 'تم حذف البوابة')

    elseif action == 'list' then
        if #portals == 0 then return Worlds.reply(src, 'ما فيه بوابات') end
        for i, p in ipairs(portals) do
            Worlds.reply(src, ('%d) %s — %.0f, %.0f, %.0f%s'):format(i, Worlds.label(p.world), p.x, p.y, p.z, p.static and ' (ثابتة)' or ''))
        end
    else
        Worlds.reply(src, '/' .. Config.Commands.portal .. ' add [عالم]  |  del  |  list')
    end
end, false)
