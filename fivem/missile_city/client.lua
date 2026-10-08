-- كل المؤثرات هنا جزيئات (particles) وأصوات وفلاتر فقط
-- ما فيه AddExplosion ولا StartScriptFire، يعني ما فيه ضرر ولا يموت أي أحد

local active = false
local strikeId = 0
local plumeFx = {}        -- أعمدة الدخان الضخمة مكان الصواريخ
local cells = {}          -- النيران المرسومة حول اللاعب: [key] = { fx... }

local function loadPtfx(asset)
    RequestNamedPtfxAsset(asset)
    local timeout = GetGameTimer() + 5000
    while not HasNamedPtfxAssetLoaded(asset) and GetGameTimer() < timeout do Wait(0) end
end

local function loadModel(model)
    RequestModel(model)
    local timeout = GetGameTimer() + 5000
    while not HasModelLoaded(model) and GetGameTimer() < timeout do Wait(0) end
end

-- يرجع ارتفاع أعلى سطح (أرض أو سطح مبنى)
local function surfaceZ(x, y, fallback)
    local found, z = GetGroundZFor_3dCoord(x, y, fallback + 800.0, false)
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

-- رقم عشوائي ثابت لكل مربع، عشان النار تطلع بنفس المكان كل مرة ترجع له
local function cellRng(seed, ix, iy)
    local state = (seed * 73856093 ~ ix * 19349663 ~ iy * 83492791) & 0x7fffffff
    return function(a, b)
        state = (state * 1103515245 + 12345) & 0x7fffffff
        return a + (state / 0x7fffffff) * (b - a)
    end
end

-- ===================== الصواريخ والانفجار =====================

local function dropMissile(x, y, z)
    local model = `w_lr_rpg_rocket`
    loadModel(model)

    local startZ = z + Config.MissileHeight
    local missile = CreateObject(model, x, y, startZ, false, false, false)
    SetEntityCollision(missile, false, false)
    SetEntityRotation(missile, -90.0, 0.0, 0.0, 2, true)
    SetEntityLodDist(missile, 3000)

    UseParticleFxAssetNextCall('scr_ar_planes')
    local trail = StartParticleFxLoopedOnEntity('scr_ar_trail_smoke', missile, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 4.0, false, false, false)
    UseParticleFxAssetNextCall('core')
    local flame = StartParticleFxLoopedOnEntity('fire_wrecked_plane_cockpit', missile, 0.0, -1.2, 0.0, 0.0, 0.0, 0.0, 1.2, false, false, false)

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

local function explosionFx(x, y, z, id)
    -- الانفجار الرئيسي: انفجار مداري + انفجارات وقود فوق بعض
    burst('scr_xm_orbital', 'scr_xm_orbital_blast', x, y, z, Config.BlastScale)
    burst('core', 'exp_grd_petrol_pump', x, y, z + 5.0, Config.BlastScale)
    burst('core', 'exp_grd_petrol_pump', x, y, z + 25.0, Config.BlastScale * 0.8)
    PlaySoundFromCoord(-1, 'DLC_XM_Explosions_Orbital_Cannon', x, y, z, 0, true, 0, false)

    local dist = #(GetEntityCoords(PlayerPedId()) - vector3(x, y, z))
    ShakeGameplayCam('LARGE_EXPLOSION_SHAKE', math.max(0.4, 3.0 - dist / 400.0))
    if dist < 600.0 then
        AnimpostfxPlay('ExplosionJosh3', 0, false)
    end

    -- عمود دخان ضخم ونار كبيرة يبقون مكان السقوط
    local plume = looped('scr_agencyheistb', 'scr_env_agency3b_smoke', x, y, z, 6.0)
    local plume2 = looped('scr_trevor3', 'scr_trev3_trailer_plume', x, y, z, 4.0)
    local core = looped('core', 'ent_ray_heli_aprtmnt_l_fire', x, y, z, 6.0)
    for _, fx in ipairs({ plume, plume2, core }) do plumeFx[#plumeFx + 1] = fx end

    -- انفجارات ثانوية متتالية حول مكان السقوط
    CreateThread(function()
        for _ = 1, Config.SecondaryBlasts do
            Wait(math.random(120, 450))
            if strikeId ~= id then return end
            local a = math.random() * 2 * math.pi
            local r = math.random(20, 160) + 0.0
            local bx, by = x + math.cos(a) * r, y + math.sin(a) * r
            local _, bz = surfaceZ(bx, by, z)
            if math.random() < 0.4 then
                burst('scr_xm_orbital', 'scr_xm_orbital_blast', bx, by, bz, 1.0)
            else
                burst('core', 'exp_grd_petrol_pump', bx, by, bz, 2.0)
            end
            ShakeGameplayCam('SMALL_EXPLOSION_SHAKE', 0.4)
        end
    end)
end

-- ===================== النار المنتشرة في المدينة =====================

local function spawnCell(state, ix, iy, refZ)
    local rnd = cellRng(state.seed, ix, iy)
    local cs = Config.CellSize
    local list = {}

    local function point()
        local x = (ix + rnd(0, 1)) * cs
        local y = (iy + rnd(0, 1)) * cs
        local found, z = surfaceZ(x, y, refZ)
        return found, x, y, z
    end

    for i = 1, Config.FiresPerCell + Config.BigFiresPerCell + Config.SmokePerCell do
        local found, x, y, z = point()
        local scale = rnd(Config.FireScale[1], Config.FireScale[2])
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

local function streamFires(state, id)
    local cs = Config.CellSize
    local reach = math.ceil(Config.StreamDistance / cs)
    local center = vector2(state.x, state.y)

    while active and strikeId == id do
        local p = GetEntityCoords(PlayerPedId())
        local pcx, pcy = math.floor(p.x / cs), math.floor(p.y / cs)
        local wanted = {}

        for dx = -reach, reach do
            for dy = -reach, reach do
                local ix, iy = pcx + dx, pcy + dy
                local mid = vector2((ix + 0.5) * cs, (iy + 0.5) * cs)
                if #(mid - vector2(p.x, p.y)) <= Config.StreamDistance and #(mid - center) <= Config.Radius then
                    local key = ix .. ':' .. iy
                    wanted[key] = true
                    if not cells[key] then
                        cells[key] = spawnCell(state, ix, iy, p.z)
                        Wait(0)
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

local function applyAtmosphere(id)
    SetTimecycleModifier(Config.TimecycleModifier)
    SetTimecycleModifierStrength(Config.TimecycleStrength)
    if Config.Blackout then
        SetArtificialLightsState(true)
        SetArtificialLightsStateAffectsVehicles(false)
    end

    -- نعيد تطبيق الطقس باستمرار عشان سكربتات مزامنة الطقس ما تلغيه
    CreateThread(function()
        while active and strikeId == id do
            SetOverrideWeather(Config.Weather)
            SetWeatherTypeNowPersist(Config.Weather)
            Wait(5000)
        end
    end)
end

local function resetCity()
    active = false
    strikeId = strikeId + 1
    for _, fx in ipairs(plumeFx) do StopParticleFxLooped(fx, false) end
    plumeFx = {}
    for _, list in pairs(cells) do clearCell(list) end
    cells = {}
    ClearTimecycleModifier()
    ClearOverrideWeather()
    SetArtificialLightsState(false)
    AnimpostfxStopAll()
end

local function strike(state, animated)
    resetCity()
    local id = strikeId
    active = true

    for _, asset in ipairs({ 'core', 'scr_ar_planes', 'scr_xm_orbital', 'scr_agencyheistb', 'scr_trevor3' }) do
        loadPtfx(asset)
    end
    RequestScriptAudioBank('DLC_CHRISTMAS2017/XM_ION_CANNON', false)

    if animated then
        for i, imp in ipairs(state.impacts) do
            CreateThread(function()
                Wait((i - 1) * Config.MissileDelay)
                local _, z = surfaceZ(imp.x, imp.y, state.z)
                dropMissile(imp.x, imp.y, z)
                if strikeId == id then explosionFx(imp.x, imp.y, z, id) end
            end)
        end
        -- النار تبدأ تنتشر مع أول انفجار
        Wait(Config.FallTime + 300)
    else
        for _, imp in ipairs(state.impacts) do
            local _, z = surfaceZ(imp.x, imp.y, state.z)
            plumeFx[#plumeFx + 1] = looped('scr_agencyheistb', 'scr_env_agency3b_smoke', imp.x, imp.y, z, 6.0)
            plumeFx[#plumeFx + 1] = looped('core', 'ent_ray_heli_aprtmnt_l_fire', imp.x, imp.y, z, 6.0)
        end
    end

    if strikeId ~= id then return end
    applyAtmosphere(id)
    streamFires(state, id)
end

AddStateBagChangeHandler('missileCity', 'global', function(_, _, value)
    CreateThread(function()
        if value then
            strike(value, true)
        else
            resetCity()
        end
    end)
end)

-- اللي يدخل السيرفر والمدينة محروقة يشوفها محروقة مباشرة بدون الصواريخ
CreateThread(function()
    Wait(2000)
    local state = GlobalState.missileCity
    if state and not active then
        strike(state, false)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then resetCity() end
end)
