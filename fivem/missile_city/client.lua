-- كل المؤثرات هنا جزيئات (particles) وأصوات وفلاتر فقط
-- ما فيه AddExplosion ولا StartScriptFire، يعني ما فيه ضرر ولا يموت أي أحد

local active = false
local loopedFx = {}

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

local function groundZ(x, y, fallback)
    local found, z = GetGroundZFor_3dCoord(x, y, fallback + 500.0, false)
    return found and z or fallback
end

local function startLooped(asset, name, x, y, z, scale)
    UseParticleFxAssetNextCall(asset)
    local fx = StartParticleFxLoopedAtCoord(name, x, y, z, 0.0, 0.0, 0.0, scale, false, false, false, false)
    loopedFx[#loopedFx + 1] = fx
end

-- سقوط الصاروخ من السما
local function dropMissile(target)
    local model = `w_lr_rpg_rocket`
    loadModel(model)
    loadPtfx('scr_ar_planes')
    loadPtfx('core')

    local startZ = target.z + Config.MissileHeight
    local missile = CreateObject(model, target.x, target.y, startZ, false, false, false)
    SetEntityCollision(missile, false, false)
    SetEntityRotation(missile, -90.0, 0.0, 0.0, 2, true)
    SetEntityLodDist(missile, 2000)
    SetModelAsNoLongerNeeded(model)

    UseParticleFxAssetNextCall('scr_ar_planes')
    local trail = StartParticleFxLoopedOnEntity('scr_ar_trail_smoke', missile, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 3.0, false, false, false)
    UseParticleFxAssetNextCall('core')
    local flame = StartParticleFxLoopedOnEntity('fire_wrecked_plane_cockpit', missile, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 0.6, false, false, false)

    local startTime = GetGameTimer()
    while true do
        local t = (GetGameTimer() - startTime) / Config.FallTime
        if t >= 1.0 then break end
        -- تسارع بسيط أثناء السقوط
        SetEntityCoordsNoOffset(missile, target.x, target.y, startZ - (startZ - target.z) * (t * t), false, false, false)
        Wait(0)
    end

    StopParticleFxLooped(trail, false)
    StopParticleFxLooped(flame, false)
    DeleteEntity(missile)
end

-- الانفجار (شكل وصوت واهتزاز فقط)
local function explosionFx(target)
    loadPtfx('scr_xm_orbital')
    RequestScriptAudioBank('DLC_CHRISTMAS2017/XM_ION_CANNON', false)

    UseParticleFxAssetNextCall('scr_xm_orbital')
    StartParticleFxNonLoopedAtCoord('scr_xm_orbital_blast', target.x, target.y, target.z, 0.0, 0.0, 0.0, 2.0, false, false, false)
    PlaySoundFromCoord(-1, 'DLC_XM_Explosions_Orbital_Cannon', target.x, target.y, target.z, 0, true, 0, false)

    local dist = #(GetEntityCoords(PlayerPedId()) - vector3(target.x, target.y, target.z))
    ShakeGameplayCam('LARGE_EXPLOSION_SHAKE', math.max(0.3, 2.0 - dist / 500.0))
    AnimpostfxPlay('ExplosionJosh3', 0, false)

    -- انفجارات ثانوية حول مكان السقوط
    CreateThread(function()
        for _ = 1, 6 do
            Wait(math.random(250, 700))
            local a = math.random() * 2 * math.pi
            local r = math.random(30, 120) + 0.0
            local x, y = target.x + math.cos(a) * r, target.y + math.sin(a) * r
            UseParticleFxAssetNextCall('scr_xm_orbital')
            StartParticleFxNonLoopedAtCoord('scr_xm_orbital_blast', x, y, groundZ(x, y, target.z), 0.0, 0.0, 0.0, 0.8, false, false, false)
        end
    end)
end

-- تحويل المدينة لمدينة محروقة
local function burnCity(target)
    active = true

    loadPtfx('core')
    loadPtfx('scr_agencyheistb')

    -- عمود دخان ضخم في مكان السقوط
    startLooped('scr_agencyheistb', 'scr_env_agency3b_smoke', target.x, target.y, target.z, 4.0)

    -- نيران ودخان موزعة على المنطقة
    for i = 1, Config.FireCount + Config.SmokeCount do
        local a = math.random() * 2 * math.pi
        local r = math.sqrt(math.random()) * Config.Radius
        local x, y = target.x + math.cos(a) * r, target.y + math.sin(a) * r
        local z = groundZ(x, y, target.z)
        if i <= Config.FireCount then
            startLooped('core', 'fire_wrecked_plane_cockpit', x, y, z, math.random(15, 35) / 10.0)
        else
            startLooped('core', 'ent_amb_smoke_foundry', x, y, z, math.random(20, 40) / 10.0)
        end
    end

    -- جو المدينة: فلتر أحمر محروق + دخان + انطفاء الأنوار
    SetTimecycleModifier(Config.TimecycleModifier)
    SetTimecycleModifierStrength(Config.TimecycleStrength)
    if Config.Blackout then
        SetArtificialLightsState(true)
        SetArtificialLightsStateAffectsVehicles(false)
    end

    -- نعيد تطبيق الطقس باستمرار عشان سكربتات مزامنة الطقس ما تلغيه
    CreateThread(function()
        while active do
            SetOverrideWeather(Config.Weather)
            SetWeatherTypeNowPersist(Config.Weather)
            Wait(5000)
        end
    end)
end

local function resetCity()
    active = false
    for _, fx in ipairs(loopedFx) do
        StopParticleFxLooped(fx, false)
    end
    loopedFx = {}
    ClearTimecycleModifier()
    ClearOverrideWeather()
    SetArtificialLightsState(false)
    AnimpostfxStopAll()
end

local function strike(target, animated)
    if active then resetCity() end
    if animated then
        dropMissile(target)
        explosionFx(target)
        Wait(800)
    end
    burnCity(target)
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

-- اللي يدخل السيرفر والمدينة محروقة يشوفها محروقة مباشرة بدون الصاروخ
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
