-- كل المؤثرات هنا جزيئات (particles) وأصوات وفلاتر فقط
-- ما فيه AddExplosion ولا StartScriptFire، يعني ما فيه ضرر ولا يموت أي أحد

local active = false      -- المدينة محروقة حالياً
local current = nil       -- حالة الضربة الحالية (المركز والـ seed)
local session = 0         -- يزيد مع كل مسح، عشان نوقف الثريدات القديمة
local plumeFx = {}        -- أعمدة الدخان الضخمة مكان الصواريخ
local plumed = {}         -- الصواريخ اللي انرسم لها عمود دخان
local cells = {}          -- النيران المرسومة حول اللاعب: [key] = { fx... }

local PTFX_ASSETS = { 'core', 'scr_ar_planes', 'scr_xm_orbital', 'scr_agencyheistb', 'scr_trevor3' }

local function loadPtfx(asset)
    RequestNamedPtfxAsset(asset)
    local timeout = GetGameTimer() + 5000
    while not HasNamedPtfxAssetLoaded(asset) and GetGameTimer() < timeout do Wait(0) end
end

local function loadAssets()
    for _, asset in ipairs(PTFX_ASSETS) do loadPtfx(asset) end
    RequestScriptAudioBank('DLC_CHRISTMAS2017/XM_ION_CANNON', false)
end

local function loadModel(model)
    RequestModel(model)
    local timeout = GetGameTimer() + 5000
    while not HasModelLoaded(model) and GetGameTimer() < timeout do Wait(0) end
end

-- يرجع ارتفاع أعلى سطح (أرض أو سطح مبنى)
local function surfaceZ(x, y, fallback)
    local found, z = GetGroundZFor_3dCoord(x, y, 1000.0, false)
    return found, found and z or fallback
end

local function looped(asset, name, x, y, z, scale)
    UseParticleFxAssetNextCall(asset)
    return StartParticleFxLoopedAtCoord(name, x, y, z, 0.0, 0.0, 0.0, scale, false, false, false, false)
end

local function burst(asset, name, x, y, z, scale)
    UseParticleFxAssetNextCall(asset)
    StartParticleFxNonLoopedAtCoord(name, x, y, z, 0.0, 0.0, 0.0, scale, false, false, false)
end

-- رقم عشوائي ثابت لكل مربع، عشان النار تطلع بنفس المكان عند كل اللاعبين
local function cellRng(seed, ix, iy)
    local state = (seed * 73856093 ~ ix * 19349663 ~ iy * 83492791) & 0x7fffffff
    return function(a, b)
        state = (state * 1103515245 + 12345) & 0x7fffffff
        return a + (state / 0x7fffffff) * (b - a)
    end
end

-- ===================== الصاروخ =====================

local function dropMissile(x, y, z)
    local model = `w_lr_rpg_rocket`
    loadModel(model)

    local startZ = z + Config.MissileHeight
    local missile = CreateObject(model, x, y, startZ, false, false, false)
    SetEntityCollision(missile, false, false)
    SetEntityRotation(missile, -90.0, 0.0, 0.0, 2, true)
    SetEntityLodDist(missile, 3000)

    UseParticleFxAssetNextCall('scr_ar_planes')
    local trail = StartParticleFxLoopedOnEntity('scr_ar_trail_smoke', missile, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 5.0, false, false, false)
    UseParticleFxAssetNextCall('core')
    local flame = StartParticleFxLoopedOnEntity('fire_wrecked_plane_cockpit', missile, 0.0, -1.2, 0.0, 0.0, 0.0, 0.0, 1.5, false, false, false)

    local startTime = GetGameTimer()
    while true do
        local t = (GetGameTimer() - startTime) / Config.FallTime
        if t >= 1.0 then break end
        SetEntityCoordsNoOffset(missile, x, y, startZ - (startZ - z) * (t * t), false, false, false)
        Wait(0)
    end

    StopParticleFxLooped(trail, false)
    StopParticleFxLooped(flame, false)
    DeleteEntity(missile)
end

-- ===================== الانفجار =====================

local function addPlume(imp, z)
    if plumed[imp.id] then return end
    plumed[imp.id] = true
    -- حد لأعمدة الدخان الضخمة، الباقي تكفيه نار المدينة
    if #plumeFx >= Config.MaxPlumes * 3 then return end
    plumeFx[#plumeFx + 1] = looped('scr_agencyheistb', 'scr_env_agency3b_smoke', imp.x, imp.y, z, 7.0)
    plumeFx[#plumeFx + 1] = looped('scr_trevor3', 'scr_trev3_trailer_plume', imp.x, imp.y, z, 5.0)
    plumeFx[#plumeFx + 1] = looped('core', 'ent_ray_heli_aprtmnt_l_fire', imp.x, imp.y, z, 7.0)
end

local function explosionFx(imp, z, sid)
    local x, y = imp.x, imp.y
    local s = Config.BlastScale

    -- الانفجار الرئيسي
    burst('scr_xm_orbital', 'scr_xm_orbital_blast', x, y, z, s)
    burst('core', 'exp_grd_petrol_pump', x, y, z + 5.0, s)
    burst('core', 'exp_grd_petrol_pump', x, y, z + 30.0, s * 0.8)
    PlaySoundFromCoord(-1, 'DLC_XM_Explosions_Orbital_Cannon', x, y, z, 0, true, 0, false)

    local dist = #(GetEntityCoords(PlayerPedId()) - vector3(x, y, z))
    ShakeGameplayCam('LARGE_EXPLOSION_SHAKE', math.max(0.5, 4.0 - dist / 350.0))
    if dist < 800.0 then
        AnimpostfxPlay('ExplosionJosh3', 0, false)
        SetPadShake(0, 800, 255)
    end

    addPlume(imp, z)

    -- سحابة فطر: انفجارات تطلع لفوق وتكبر
    if Config.MushroomCloud then
        CreateThread(function()
            for i = 1, 8 do
                Wait(180)
                if session ~= sid then return end
                local h = z + i * 22.0
                local cap = i >= 6 and 1.6 or 1.0
                burst('scr_xm_orbital', 'scr_xm_orbital_blast', x, y, h, s * 0.35 * cap)
                burst('core', 'exp_grd_petrol_pump', x, y, h, s * 0.5 * cap)
            end
        end)
    end

    -- حلقة انفجارات تتوسع (موجة صدمة)
    if Config.ShockwaveRing then
        CreateThread(function()
            for ring = 1, 3 do
                Wait(220)
                if session ~= sid then return end
                local r = ring * 45.0
                local n = 8 + ring * 4
                for k = 1, n do
                    local a = (k / n) * 2 * math.pi
                    local bx, by = x + math.cos(a) * r, y + math.sin(a) * r
                    local _, bz = surfaceZ(bx, by, z)
                    burst('core', 'exp_grd_petrol_pump', bx, by, bz, 1.6)
                end
            end
        end)
    end

    -- انفجارات ثانوية عشوائية
    CreateThread(function()
        for _ = 1, Config.SecondaryBlasts do
            Wait(math.random(120, 400))
            if session ~= sid then return end
            local a = math.random() * 2 * math.pi
            local r = math.random(20, 200) + 0.0
            local bx, by = x + math.cos(a) * r, y + math.sin(a) * r
            local _, bz = surfaceZ(bx, by, z)
            if math.random() < 0.4 then
                burst('scr_xm_orbital', 'scr_xm_orbital_blast', bx, by, bz, 1.3)
            else
                burst('core', 'exp_grd_petrol_pump', bx, by, bz, 2.5)
            end
            ShakeGameplayCam('SMALL_EXPLOSION_SHAKE', 0.5)
        end
    end)
end

-- ===================== النار المنتشرة في المدينة =====================

local function spawnCell(ix, iy, refZ)
    local rnd = cellRng(current.seed, ix, iy)
    local cs = Config.CellSize
    local list = {}
    local total = Config.FiresPerCell + Config.BigFiresPerCell + Config.SmokePerCell

    for i = 1, total do
        local x = (ix + rnd(0, 1)) * cs
        local y = (iy + rnd(0, 1)) * cs
        local scale = rnd(Config.FireScale[1], Config.FireScale[2])
        local found, z = surfaceZ(x, y, refZ)
        if found then
            if i <= Config.FiresPerCell then
                list[#list + 1] = looped('core', 'fire_wrecked_plane_cockpit', x, y, z, scale)
            elseif i <= Config.FiresPerCell + Config.BigFiresPerCell then
                list[#list + 1] = looped('core', 'ent_ray_heli_aprtmnt_l_fire', x, y, z, scale)
            else
                list[#list + 1] = looped('core', 'ent_amb_smoke_foundry', x, y, z, scale * 1.5)
            end
        end
    end

    -- لو المنطقة ما تحملت بعد ما نحفظ المربع، عشان نحاول مرة ثانية
    if #list == 0 then return nil end
    return list
end

local function clearCell(list)
    for _, fx in ipairs(list) do StopParticleFxLooped(fx, false) end
end

local function streamFires(sid)
    local cs = Config.CellSize
    local reach = math.ceil(Config.StreamDistance / cs)

    while active and session == sid do
        local p = GetEntityCoords(PlayerPedId())
        local p2 = vector2(p.x, p.y)
        local center = vector2(current.x, current.y)
        local pcx, pcy = math.floor(p.x / cs), math.floor(p.y / cs)
        local wanted = {}

        for dx = -reach, reach do
            for dy = -reach, reach do
                local ix, iy = pcx + dx, pcy + dy
                local mid = vector2((ix + 0.5) * cs, (iy + 0.5) * cs)
                if #(mid - p2) <= Config.StreamDistance and #(mid - center) <= Config.Radius then
                    local key = ix .. ':' .. iy
                    wanted[key] = true
                    if not cells[key] then
                        cells[key] = spawnCell(ix, iy, p.z)
                        Wait(0)
                        if session ~= sid then return end
                    end
                end
            end
        end

        for key, list in pairs(cells) do
            if not wanted[key] then
                clearCell(list)
                cells[key] = nil
            end
        end

        Wait(1000)
    end
end

-- ===================== الجو والتحكم =====================

local function resetCity()
    active = false
    current = nil
    session = session + 1
    for _, fx in ipairs(plumeFx) do StopParticleFxLooped(fx, false) end
    plumeFx, plumed = {}, {}
    for _, list in pairs(cells) do clearCell(list) end
    cells = {}
    ClearTimecycleModifier()
    ClearOverrideWeather()
    SetArtificialLightsState(false)
    AnimpostfxStopAll()
end

-- يحرق المدينة (الجو + النار المنتشرة) لو مو محروقة
local function igniteCity(state)
    current = state
    if active then return end
    active = true
    local sid = session

    SetTimecycleModifier(Config.TimecycleModifier)
    SetTimecycleModifierStrength(Config.TimecycleStrength)
    if Config.Blackout then
        SetArtificialLightsState(true)
        SetArtificialLightsStateAffectsVehicles(false)
    end

    -- نعيد تطبيق الطقس باستمرار عشان سكربتات مزامنة الطقس ما تلغيه
    CreateThread(function()
        while active and session == sid do
            SetOverrideWeather(Config.Weather)
            SetWeatherTypeNowPersist(Config.Weather)
            Wait(5000)
        end
    end)

    CreateThread(function() streamFires(sid) end)
end

-- صواريخ جديدة وصلت من السيرفر
RegisterNetEvent('missile_city:strike', function(state, impacts, reset)
    if reset then resetCity() end
    local sid = session
    loadAssets()

    for i, imp in ipairs(impacts) do
        CreateThread(function()
            Wait((i - 1) * Config.MissileDelay)
            if session ~= sid then return end
            local _, z = surfaceZ(imp.x, imp.y, imp.z)
            dropMissile(imp.x, imp.y, z)
            if session ~= sid then return end
            explosionFx(imp, z, sid)
            igniteCity(state)
        end)
    end
end)

RegisterNetEvent('missile_city:reset', resetCity)

-- /missilewp [عدد] : صواريخ على النقطة اللي حاطها في الخريطة
RegisterCommand(Config.Commands.waypoint, function(_, args)
    local blip = GetFirstBlipInfoId(8)
    if not DoesBlipExist(blip) then
        TriggerEvent('chat:addMessage', { args = { 'missile_city', 'حط نقطة (Waypoint) في الخريطة أول' } })
        return
    end
    local c = GetBlipInfoIdCoord(blip)
    local _, z = surfaceZ(c.x, c.y, GetEntityCoords(PlayerPedId()).z)
    TriggerServerEvent('missile_city:waypoint', c.x, c.y, z, tonumber(args[1]))
end, false)

-- اقتراحات الأوامر في الشات
CreateThread(function()
    local c = Config.Commands
    TriggerEvent('chat:addSuggestion', '/' .. c.missile, 'ضربة صواريخ جديدة على مكانك', { { name = 'عدد', help = 'عدد الصواريخ' } })
    TriggerEvent('chat:addSuggestion', '/' .. c.add, 'زيادة صواريخ على مكانك', { { name = 'عدد', help = 'عدد الصواريخ' } })
    TriggerEvent('chat:addSuggestion', '/' .. c.waypoint, 'زيادة صواريخ على النقطة في الخريطة', { { name = 'عدد', help = 'عدد الصواريخ' } })
    TriggerEvent('chat:addSuggestion', '/' .. c.rain, 'مطر صواريخ عشوائي حولك', { { name = 'عدد', help = 'عدد الصواريخ' } })
    TriggerEvent('chat:addSuggestion', '/' .. c.reset, 'يرجع المدينة طبيعية')
end)

-- اللي يدخل السيرفر والمدينة محروقة يشوفها محروقة مباشرة بدون الصواريخ
CreateThread(function()
    Wait(2000)
    local state = GlobalState.missileCity
    if state and not active then
        loadAssets()
        for _, imp in ipairs(state.impacts) do
            local _, z = surfaceZ(imp.x, imp.y, imp.z)
            addPlume(imp, z)
        end
        igniteCity(state)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then resetCity() end
end)
