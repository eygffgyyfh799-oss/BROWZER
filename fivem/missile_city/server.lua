-- حالة المدينة محفوظة في GlobalState عشان اللاعبين اللي يدخلون بعدين يشوفونها محروقة
GlobalState.missileCity = false

local nextImpactId = 1

local function clampCount(arg, default)
    local n = math.floor(tonumber(arg) or default)
    return math.max(1, math.min(n, Config.MaxPerCommand))
end

-- يضيف صواريخ جديدة ويرسلها لكل اللاعبين
-- reset = true يمسح الحريق القديم ويبدأ ضربة جديدة
-- target (اختياري): آيدي لاعب، والصواريخ تلاحقه
local function launch(cx, cy, cz, count, spread, reset, target)
    local state = GlobalState.missileCity

    -- صاروخ موجّه والمدينة مو محروقة: انفجار بس بدون ما تحترق المدينة (لو الإعداد كذا)
    local temp = target and not state and not Config.TargetBurnsCity
    if temp then
        state = { x = cx, y = cy, z = cz, seed = 0, impacts = {} }
    elseif reset or not state then
        state = { x = cx, y = cy, z = cz, seed = math.random(1, 1000000), impacts = {} }
        reset = true
    end

    local new = {}
    for i = 1, count do
        local x, y = cx, cy
        if (i > 1 or spread > Config.MissileSpread) and spread > 0 then
            local a = math.random() * 2 * math.pi
            local r = math.sqrt(math.random()) * spread
            x, y = cx + math.cos(a) * r, cy + math.sin(a) * r
        end
        local imp = { id = nextImpactId, x = x, y = y, z = cz, temp = temp or nil }
        if target then
            -- الأول على اللاعب بالضبط، والباقي حوله بمسافة صغيرة
            imp.target = target
            imp.ox, imp.oy = x - cx, y - cy
        end
        nextImpactId = nextImpactId + 1
        new[#new + 1] = imp
        state.impacts[#state.impacts + 1] = imp
    end

    -- نخلي آخر 300 صاروخ بس عشان الحالة ما تكبر بزيادة
    while #state.impacts > 300 do table.remove(state.impacts, 1) end

    if temp then
        TriggerClientEvent('missile_city:strike', -1, false, new, false)
        return
    end

    GlobalState.missileCity = state
    TriggerClientEvent('missile_city:strike', -1, state, new, reset)
end

local function playerCoords(src)
    return GetEntityCoords(GetPlayerPed(src))
end

local function inGame(src)
    if src == 0 then
        print('[missile_city] لازم تكتب الأمر من داخل اللعبة')
        return false
    end
    return IsPlayerAceAllowed(src, Config.Ace)
end

-- /missile [عدد] : ضربة جديدة
RegisterCommand(Config.Commands.missile, function(src, args)
    if not inGame(src) then return end
    local c = playerCoords(src)
    launch(c.x, c.y, c.z, clampCount(args[1], Config.DefaultCount), Config.MissileSpread, true)
end, false)

-- /addmissile [عدد] : زيادة صواريخ بدون مسح الحريق
RegisterCommand(Config.Commands.add, function(src, args)
    if not inGame(src) then return end
    local c = playerCoords(src)
    launch(c.x, c.y, c.z, clampCount(args[1], Config.DefaultAddCount), Config.MissileSpread, false)
end, false)

-- /missilerain [عدد] : مطر صواريخ عشوائي حولك
RegisterCommand(Config.Commands.rain, function(src, args)
    if not inGame(src) then return end
    local c = playerCoords(src)
    launch(c.x, c.y, c.z, clampCount(args[1], Config.DefaultRainCount), Config.RainRadius, false)
end, false)

-- /resetcity : يرجع المدينة طبيعية
RegisterCommand(Config.Commands.reset, function(src)
    if src ~= 0 and not IsPlayerAceAllowed(src, Config.Ace) then return end
    GlobalState.missileCity = false
    TriggerClientEvent('missile_city:reset', -1)
end, false)

-- /missilewp : النقطة في الخريطة تجي من اللاعب، فنتأكد من صلاحيته هنا
RegisterNetEvent('missile_city:waypoint', function(x, y, z, count)
    local src = source
    if not IsPlayerAceAllowed(src, Config.Ace) then return end
    if type(x) ~= 'number' or type(y) ~= 'number' or type(z) ~= 'number' then return end
    launch(x, y, z, clampCount(count, Config.DefaultAddCount), Config.MissileSpread, false)
end)

-- /nuke        : نووي حقيقي، المواطنين عندهم دقيقتين يهربون للبحر
-- /nuke dream  : الفلم القديم اللي ينتهي بحلم
local nukeReadyAt = 0
local realNukeActive = false

RegisterCommand(Config.Commands.nuke, function(src, args)
    if not inGame(src) then return end
    if os.time() < nukeReadyAt or realNukeActive then
        TriggerClientEvent('chat:addMessage', src, { args = { 'missile_city', ('انتظر %d ثانية'):format(math.max(0, nukeReadyAt - os.time())) } })
        return
    end
    nukeReadyAt = os.time() + Config.Nuke.Cooldown

    local t = Config.Nuke.Target or playerCoords(src)
    local data = { x = t.x, y = t.y, z = t.z, seed = math.random(1, 1000000) }

    if args[1] == 'dream' then
        TriggerClientEvent('missile_city:nuke', -1, data)
        return
    end

    -- النووي الحقيقي
    local R = Config.NukeReal
    realNukeActive = true
    data.countdown = R.Countdown
    TriggerClientEvent('missile_city:nukeReal', -1, data)

    SetTimeout(R.Countdown * 1000, function()
        realNukeActive = false
        if not R.BurnCity then return end
        -- المدينة تبقى محروقة (للي يدخل بعدين بعد)، وتنمسح بـ /resetcity
        local imp = { id = nextImpactId, x = data.x, y = data.y, z = data.z }
        nextImpactId = nextImpactId + 1
        GlobalState.missileCity = { x = data.x, y = data.y, z = data.z, seed = data.seed, impacts = { imp } }
    end)
end, false)

-- /missileid [آيدي] [عدد] : صاروخ موجّه يلاحق لاعب معين
RegisterCommand(Config.Commands.target, function(src, args)
    if not inGame(src) then return end
    local id = tonumber(args[1])
    if not id or not GetPlayerName(id) then
        TriggerClientEvent('chat:addMessage', src, { args = { 'missile_city', 'اكتب آيدي لاعب موجود، مثال: /' .. Config.Commands.target .. ' 12' } })
        return
    end

    local count = clampCount(args[2], 1)
    local c = GetEntityCoords(GetPlayerPed(id))
    launch(c.x, c.y, c.z, count, Config.TargetSpread, false, id)
    TriggerClientEvent('missile_city:targeted', id, count)
    TriggerClientEvent('chat:addMessage', src, { args = { 'missile_city', ('🎯 تم إطلاق %d صاروخ على %s'):format(count, GetPlayerName(id)) } })
end, false)
