-- حالة المدينة محفوظة في GlobalState عشان اللاعبين اللي يدخلون بعدين يشوفونها محروقة
GlobalState.missileCity = false

local nextImpactId = 1

local function clampCount(arg, default)
    local n = math.floor(tonumber(arg) or default)
    return math.max(1, math.min(n, Config.MaxPerCommand))
end

-- يضيف صواريخ جديدة ويرسلها لكل اللاعبين
-- reset = true يمسح الحريق القديم ويبدأ ضربة جديدة
local function launch(cx, cy, cz, count, spread, reset)
    local state = GlobalState.missileCity
    if reset or not state then
        state = { x = cx, y = cy, z = cz, seed = math.random(1, 1000000), impacts = {} }
        reset = true
    end

    local new = {}
    for i = 1, count do
        local x, y = cx, cy
        if i > 1 or spread > Config.MissileSpread then
            local a = math.random() * 2 * math.pi
            local r = math.sqrt(math.random()) * spread
            x, y = cx + math.cos(a) * r, cy + math.sin(a) * r
        end
        local imp = { id = nextImpactId, x = x, y = y, z = cz }
        nextImpactId = nextImpactId + 1
        new[#new + 1] = imp
        state.impacts[#state.impacts + 1] = imp
    end

    -- نخلي آخر 300 صاروخ بس عشان الحالة ما تكبر بزيادة
    while #state.impacts > 300 do table.remove(state.impacts, 1) end

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
