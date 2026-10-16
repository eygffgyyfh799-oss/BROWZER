-- فلم التفجير النووي: كاميرا سينمائية، إنذار، صاروخ، انفجار، سحابة فطر، موجة صدمة، مدينة محروقة
-- وبالأخير يطلع كله حلم: الكاميرا ترجع، والمدينة ترجع مثل ما كانت، وكل لاعب يرجع مكانه
-- كله شكل فقط: اللاعب مجمد وما يتأذى، وما فيه أي انفجار حقيقي

local N = Config.Nuke
local running = false
local cams = {}
local nukeFx = {}
local saved = nil

-- ===================== أدوات =====================

local function ui(data) SendNUIMessage(data) end

local function caption(text, duration, alarm)
    ui({ type = 'caption', text = text, duration = duration, alarm = alarm })
end

local function makeCam(pos, look, fov)
    local cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', pos.x, pos.y, pos.z, 0.0, 0.0, 0.0, fov or 50.0, false, 2)
    PointCamAtCoord(cam, look.x, look.y, look.z)
    cams[#cams + 1] = cam
    return cam
end

-- لقطة: الكاميرا تتحرك بهدوء من from إلى to
local function shot(from, to, duration)
    SetCamActive(from, true)
    RenderScriptCams(true, false, 0, true, true)
    if to then SetCamActiveWithInterp(to, from, duration, 1, 1) end
end

local function keepFx(fx) nukeFx[#nukeFx + 1] = fx end

local function ring(x, y, r, n, cb)
    for k = 1, n do
        local a = (k / n) * 2 * math.pi
        cb(x + math.cos(a) * r, y + math.sin(a) * r)
    end
end

-- ===================== المؤثرات =====================

local function mushroomCloud(x, y, z)
    local H = N.MushroomHeight

    -- الساق: انفجارات تطلع لفوق
    CreateThread(function()
        for i = 1, 22 do
            Wait(180)
            if not running then return end
            local h = z + i * (H / 22)
            MC.burst('scr_xm_orbital', 'scr_xm_orbital_blast', x, y, h, 3.5)
            MC.burst('core', 'exp_grd_petrol_pump', x, y, h, 4.5)
        end

        -- الراس: حلقات انفجارات كبيرة فوق
        for k = 1, 7 do
            Wait(260)
            if not running then return end
            ring(x, y, 50.0 + k * 18.0, 10, function(cx, cy)
                MC.burst('scr_xm_orbital', 'scr_xm_orbital_blast', cx, cy, z + H + math.random(-35, 35), 5.0)
            end)
        end
    end)

    -- دخان ثابت يشكل الفطر
    keepFx(MC.looped('core', 'ent_ray_heli_aprtmnt_l_fire', x, y, z, 15.0))
    for _, f in ipairs({ 0.0, 0.33, 0.66 }) do
        keepFx(MC.looped('scr_agencyheistb', 'scr_env_agency3b_smoke', x, y, z + H * f, 18.0))
    end
    ring(x, y, 90.0, 6, function(cx, cy)
        keepFx(MC.looped('scr_agencyheistb', 'scr_env_agency3b_smoke', cx, cy, z + H, 20.0))
        keepFx(MC.looped('scr_trevor3', 'scr_trev3_trailer_plume', cx, cy, z + H - 40.0, 12.0))
    end)
end

local function shockwave(x, y, z)
    CreateThread(function()
        for r = 80.0, N.ShockwaveRadius, 80.0 do
            Wait(220)
            if not running then return end
            local n = math.min(36, math.floor(r / 30) + 8)
            local i = 0
            ring(x, y, r, n, function(cx, cy)
                i = i + 1
                local _, gz = MC.surfaceZ(cx, cy, z)
                MC.burst('core', 'exp_grd_petrol_pump', cx, cy, gz, 3.0)
                if i % 3 == 0 then MC.burst('scr_xm_orbital', 'scr_xm_orbital_blast', cx, cy, gz, 1.5) end
            end)
        end
    end)

    -- انفجارات متفرقة في المدينة بعد الموجة
    CreateThread(function()
        Wait(2500)
        for _ = 1, 60 do
            Wait(math.random(150, 450))
            if not running then return end
            local a = math.random() * 2 * math.pi
            local r = math.random(100, math.floor(N.ShockwaveRadius * 0.6)) + 0.0
            local cx, cy = x + math.cos(a) * r, y + math.sin(a) * r
            local _, gz = MC.surfaceZ(cx, cy, z)
            MC.burst('core', 'exp_grd_petrol_pump', cx, cy, gz, 3.5)
        end
    end)
end

local function alarmSound()
    CreateThread(function()
        local untilT = GetGameTimer() + 2500 + N.FallTime
        while running and GetGameTimer() < untilT do
            PlaySoundFrontend(-1, 'Beep_Red', 'DLC_HEIST_HACKING_SNAKE_SOUNDS', true)
            Wait(700)
        end
    end)
end

local function impactSound(x, y, z)
    CreateThread(function()
        for _ = 1, 4 do
            PlaySoundFromCoord(-1, 'DLC_XM_Explosions_Orbital_Cannon', x, y, z, 0, true, 0, false)
            Wait(600)
        end
    end)
end

-- ===================== التجميد والإرجاع =====================

local function freezePlayer()
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    saved = {
        pos = GetEntityCoords(ped),
        heading = GetEntityHeading(ped),
        veh = veh ~= 0 and GetPedInVehicleSeat(veh, -1) == ped and veh or 0,
        invincible = GetPlayerInvincible(PlayerId()),
    }
    FreezeEntityPosition(ped, true)
    if saved.veh ~= 0 then FreezeEntityPosition(saved.veh, true) end
    SetPlayerInvincible(PlayerId(), true)
    SetEntityInvincible(ped, true)
end

local function restorePlayer()
    if not saved then return end
    local ped = PlayerPedId()
    if not IsPedInAnyVehicle(ped, false) then
        SetEntityCoordsNoOffset(ped, saved.pos.x, saved.pos.y, saved.pos.z, false, false, false)
        SetEntityHeading(ped, saved.heading)
    end
    FreezeEntityPosition(ped, false)
    if saved.veh ~= 0 and DoesEntityExist(saved.veh) then FreezeEntityPosition(saved.veh, false) end
    SetPlayerInvincible(PlayerId(), saved.invincible)
    SetEntityInvincible(ped, saved.invincible)
    saved = nil
end

local function cleanup()
    running = false
    for _, fx in ipairs(nukeFx) do StopParticleFxLooped(fx, false) end
    nukeFx = {}
    RenderScriptCams(false, false, 0, true, true)
    for _, cam in ipairs(cams) do DestroyCam(cam, false) end
    cams = {}
    ClearFocus()
    MC.setStreamCenter(nil)
    MC.resetCity()
    NetworkClearClockTimeOverride()
    ClearOverrideWeather()
    ui({ type = 'clear' })
    restorePlayer()
    MC.setDreaming(false)
end

-- ===================== الفلم =====================

local function playWakeUp()
    local ped = PlayerPedId()
    AnimpostfxPlay('DrugsDrivingOut', 0, false)
    if IsPedInAnyVehicle(ped, false) then return end
    local dict = 'anim@mp_player_intcelebrationmale@face_palm'
    RequestAnimDict(dict)
    local timeout = GetGameTimer() + 3000
    while not HasAnimDictLoaded(dict) and GetGameTimer() < timeout do Wait(0) end
    TaskPlayAnim(ped, dict, 'face_palm', 8.0, -8.0, -1, 48, 0, false, false, false)
end

local function runNuke(t)
    running = true
    MC.setDreaming(true)

    -- البداية: الشاشة تسود ونجهز الحلم
    DoScreenFadeOut(1500)
    Wait(1600)

    freezePlayer()
    MC.resetCity()
    MC.loadAssets()

    SetFocusPosAndVel(t.x, t.y, t.z + 50.0, 0.0, 0.0, 0.0)
    NetworkOverrideClockTime(N.ClockHour, 0, 0)
    SetOverrideWeather('CLEAR')
    SetWeatherTypeNowPersist('CLEAR')
    Wait(1500)

    local _, z = MC.surfaceZ(t.x, t.y, t.z)
    local T = vector3(t.x, t.y, z)

    -- كل فريم: نخفي الواجهة ونمنع التحكم
    CreateThread(function()
        while running do
            HideHudAndRadarThisFrame()
            DisableAllControlActions(0)
            Wait(0)
        end
    end)

    ui({ type = 'letterbox', on = true })

    -- لقطة 1: المدينة من فوق، مساء هادي
    local c1 = makeCam(T + vector3(-420.0, -420.0, 220.0), T + vector3(0.0, 0.0, 30.0), 50.0)
    local c2 = makeCam(T + vector3(-300.0, -460.0, 150.0), T, 50.0)
    shot(c1, c2, 8000)
    DoScreenFadeIn(2500)
    Wait(1500)
    caption(N.Captions.intro, 5000)
    Wait(6500)
    if not running then return end

    -- لقطة 2: من الشارع نطالع السما، والإنذار يشتغل
    local c3 = makeCam(T + vector3(70.0, -90.0, 8.0), T + vector3(0.0, 0.0, 350.0), 60.0)
    SetCamActive(c3, true)
    ui({ type = 'alarm', on = true })
    caption(N.Captions.alarm, 4000 + N.FallTime, true)
    alarmSound()
    Wait(2500)
    if not running then return end

    -- لقطة 3: الصاروخ النووي ينزل والكاميرا تلاحقه
    local model = `w_lr_rpg_rocket`
    MC.loadModel(model)
    local startZ = z + N.MissileHeight
    local missile = CreateObject(model, T.x, T.y, startZ, false, false, false)
    SetEntityCollision(missile, false, false)
    SetEntityRotation(missile, -90.0, 0.0, 0.0, 2, true)
    SetEntityLodDist(missile, 5000)
    UseParticleFxAssetNextCall('scr_ar_planes')
    local trail = StartParticleFxLoopedOnEntity('scr_ar_trail_smoke', missile, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 9.0, false, false, false)
    UseParticleFxAssetNextCall('core')
    local flame = StartParticleFxLoopedOnEntity('fire_wrecked_plane_cockpit', missile, 0.0, -1.2, 0.0, 0.0, 0.0, 0.0, 2.5, false, false, false)
    PointCamAtEntity(c3, missile, 0.0, 0.0, 0.0, true)

    local start = GetGameTimer()
    while running do
        local p = (GetGameTimer() - start) / N.FallTime
        if p >= 1.0 then break end
        SetEntityCoordsNoOffset(missile, T.x, T.y, startZ - (startZ - z) * (p * p), false, false, false)
        SetCamFov(c3, 60.0 - 25.0 * p)
        Wait(0)
    end
    StopParticleFxLooped(trail, false)
    StopParticleFxLooped(flame, false)
    DeleteEntity(missile)
    if not running then return end

    -- الانفجار: وميض أبيض يعمي، صوت، والكاميرا تقطع لمنظر بعيد
    ui({ type = 'alarm', on = false })
    caption('', 0)
    ui({ type = 'flash', strength = 1, hold = 1400, fade = 4000 })
    impactSound(T.x, T.y, T.z)
    PlaySoundFrontend(-1, 'ScreenFlash', 'WastedSounds', true)

    MC.burst('scr_xm_orbital', 'scr_xm_orbital_blast', T.x, T.y, T.z, N.BlastScale)
    MC.burst('scr_xm_orbital', 'scr_xm_orbital_blast', T.x, T.y, T.z + 60.0, N.BlastScale * 0.8)
    MC.burst('core', 'exp_grd_petrol_pump', T.x, T.y, T.z + 10.0, N.BlastScale)

    local c4 = makeCam(T + vector3(-950.0, -950.0, 180.0), T + vector3(0.0, 0.0, N.MushroomHeight * 0.5), 55.0)
    local c5 = makeCam(T + vector3(-780.0, -820.0, 170.0), T + vector3(0.0, 0.0, N.MushroomHeight * 0.55), 50.0)
    SetFocusPosAndVel(T.x - 600.0, T.y - 600.0, T.z, 0.0, 0.0, 0.0)
    shot(c4, c5, 15000)
    ShakeCam(c4, 'LARGE_EXPLOSION_SHAKE', 1.5)
    ShakeCam(c5, 'LARGE_EXPLOSION_SHAKE', 1.0)

    MC.igniteCity({ x = T.x, y = T.y, z = T.z, seed = t.seed })
    MC.setStreamCenter(T)
    mushroomCloud(T.x, T.y, T.z)
    shockwave(T.x, T.y, T.z)

    -- موجة الصدمة توصل للكاميرا
    Wait(7000)
    if not running then return end
    ui({ type = 'flash', strength = 0.55, hold = 200, fade = 1500 })
    ShakeCam(c5, 'LARGE_EXPLOSION_SHAKE', 3.0)
    PlaySoundFrontend(-1, 'ScreenFlash', 'WastedSounds', true)

    -- نجهز مكان لقطة الدمار عشان النار تتحمل قبل ما نوصل لها
    local street = T + vector3(90.0, -110.0, 0.0)
    SetFocusPosAndVel(street.x, street.y, street.z, 0.0, 0.0, 0.0)
    MC.setStreamCenter(street)
    Wait(8000)
    if not running then return end

    -- لقطة 4: الدمار من الشارع، الكاميرا تمشي ببطء وسط النار
    local c6 = makeCam(T + vector3(140.0, -180.0, 6.0), T + vector3(40.0, -40.0, 20.0), 55.0)
    local c7 = makeCam(T + vector3(60.0, -70.0, 12.0), T + vector3(0.0, 0.0, 120.0), 55.0)
    shot(c6, c7, 12000)
    ShakeCam(c6, 'HAND_SHAKE', 0.6)
    ShakeCam(c7, 'HAND_SHAKE', 0.6)
    Wait(1500)
    caption(N.Captions.after, 6000)
    Wait(10500)
    if not running then return end

    -- النهاية: سكوت، الشاشة تسود
    caption(N.Captions.silence, 3000)
    DoScreenFadeOut(3000)
    Wait(3500)

    -- يصحى من الحلم: كل شي يرجع مثل ما كان
    cleanup()
    MC.syncFromGlobal()
    Wait(1000)
    DoScreenFadeIn(2500)
    caption(N.Captions.wake, 4500)
    playWakeUp()
end

RegisterNetEvent('missile_city:nuke', function(t)
    if running then return end
    CreateThread(function() runNuke(t) end)
end)

TriggerEvent('chat:addSuggestion', '/' .. Config.Commands.nuke, 'فلم تفجير نووي للمدينة (حلم)')

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and running then
        cleanup()
        DoScreenFadeIn(0)
    end
end)
