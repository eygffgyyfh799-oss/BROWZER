-- فلم التفجير النووي (حلم)
-- الترتيب: مساء هادي ← بث طوارئ وصفارة إنذار ← الصاروخ جاي من بعيد ← سكوت ← وميض يعمي وحركة بطيئة
-- ← منظر بعيد: كرة نار وسحابة فطر وموجة صدمة جاية للكاميرا ← انقطاع الإشارة ← الدمار والرماد
-- ← اللاعب نفسه في مكانه وسط الخراب ← نور أبيض ← يصحى: كان مجرد حلم
-- كله شكل فقط: اللاعب مجمد وما يتأذى، وما فيه أي انفجار حقيقي، وبالأخير كل شي يرجع مثل ما كان

local N = Config.Nuke
local running = false
local cams = {}
local nukeFx = {}
local saved = nil

-- ===================== أدوات =====================

local function ui(data) SendNUIMessage(data) end

local function caption(text, duration, style)
    ui({ type = 'caption', text = text, duration = duration, style = style })
end

local function sound(name, opts)
    local d = opts or {}
    d.type, d.name = 'sound', name
    ui(d)
end

-- ننتظر ونرجع false لو الفلم انلغى
local function wait(ms)
    Wait(ms)
    return running
end

-- مكان كاميرا ما يطلع تحت الأرض أو داخل مبنى
local function camPos(base, off, minAbove)
    local x, y = base.x + off.x, base.y + off.y
    local z = base.z + off.z
    local found, gz = MC.surfaceZ(x, y, base.z)
    if found and z < gz + minAbove then z = gz + minAbove end
    return vector3(x, y, z)
end

local function makeCam(pos, look, fov)
    local cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', pos.x, pos.y, pos.z, 0.0, 0.0, 0.0, fov or 50.0, false, 2)
    if look then PointCamAtCoord(cam, look.x, look.y, look.z) end
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

local function rand(a, b) return a + math.random() * (b - a) end

-- ===================== مؤثرات الانفجار =====================

-- كرة النار: تكبر وتطلع لفوق خلال كم ثانية
local function fireball(T)
    CreateThread(function()
        local start = GetGameTimer()
        while running do
            local p = (GetGameTimer() - start) / 4000
            if p >= 1.0 then break end
            local a = rand(0, 2 * math.pi)
            local r = rand(0, 40 + 60 * p)
            local h = 20 + p * 160 + rand(-30, 30)
            MC.burst('scr_xm_orbital', 'scr_xm_orbital_blast', T.x + math.cos(a) * r, T.y + math.sin(a) * r, T.z + h, rand(6.0, 10.0))
            MC.burst('core', 'exp_grd_petrol_pump', T.x + math.cos(a) * r, T.y + math.sin(a) * r, T.z + h, 8.0)
            Wait(90)
        end
    end)
end

local function mushroomCloud(T)
    local H = N.MushroomHeight

    CreateThread(function()
        Wait(1500)
        -- الساق
        for i = 1, 26 do
            if not wait(170) then return end
            local h = T.z + 120 + i * ((H - 120) / 26)
            MC.burst('scr_xm_orbital', 'scr_xm_orbital_blast', T.x + rand(-15, 15), T.y + rand(-15, 15), h, 4.5)
            MC.burst('core', 'exp_grd_petrol_pump', T.x, T.y, h, 6.0)
        end

        -- الراس
        for k = 1, 9 do
            if not wait(230) then return end
            ring(T.x, T.y, 40.0 + k * 22.0, 12, function(cx, cy)
                MC.burst('scr_xm_orbital', 'scr_xm_orbital_blast', cx, cy, T.z + H + rand(-40, 40), 6.0)
            end)
        end
    end)

    -- حلقة التكثف (الغيمة البيضا اللي تطلع حول الساق)
    CreateThread(function()
        Wait(3500)
        for _ = 1, 4 do
            if not running then return end
            ring(T.x, T.y, 170.0, 18, function(cx, cy)
                MC.burst('core', 'exp_grd_bzgas_smoke', cx, cy, T.z + H * 0.45, 12.0)
            end)
            Wait(600)
        end
    end)

    -- دخان ثابت يشكل الفطر ويبقى
    keepFx(MC.looped('core', 'ent_ray_heli_aprtmnt_l_fire', T.x, T.y, T.z, 18.0))
    for _, f in ipairs({ 0.0, 0.3, 0.6 }) do
        keepFx(MC.looped('scr_agencyheistb', 'scr_env_agency3b_smoke', T.x, T.y, T.z + H * f, 20.0))
    end
    ring(T.x, T.y, 100.0, 8, function(cx, cy)
        keepFx(MC.looped('scr_agencyheistb', 'scr_env_agency3b_smoke', cx, cy, T.z + H, 22.0))
        keepFx(MC.looped('scr_trevor3', 'scr_trev3_trailer_plume', cx, cy, T.z + H - 50.0, 14.0))
    end)
end

-- موجة الصدمة: حلقة غبار وانفجارات تتوسع، ولما توصل مسافة الكاميرا نشغل onReach
local function shockwave(T, reachDist, onReach)
    CreateThread(function()
        local step = N.ShockwaveSpeed * 0.2
        local reached = false
        local r = 60.0
        while running and r <= N.ShockwaveRadius do
            local n = math.min(40, math.floor(r / 35) + 10)
            local i = 0
            ring(T.x, T.y, r, n, function(cx, cy)
                i = i + 1
                local _, gz = MC.surfaceZ(cx, cy, T.z)
                MC.burst('core', 'exp_grd_bzgas_smoke', cx, cy, gz, 7.0)
                if i % 2 == 0 then MC.burst('core', 'exp_grd_petrol_pump', cx, cy, gz, 3.5) end
            end)
            if not reached and r >= reachDist then
                reached = true
                onReach()
            end
            r = r + step
            Wait(200)
        end
        if running and not reached then onReach() end
    end)

    -- انفجارات متفرقة في المدينة ورا الموجة
    CreateThread(function()
        Wait(3000)
        for _ = 1, 70 do
            if not wait(math.random(150, 400)) then return end
            local a = rand(0, 2 * math.pi)
            local d = rand(150, N.ShockwaveRadius * 0.7)
            local cx, cy = T.x + math.cos(a) * d, T.y + math.sin(a) * d
            local _, gz = MC.surfaceZ(cx, cy, T.z)
            MC.burst('core', 'exp_grd_petrol_pump', cx, cy, gz, 4.0)
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
    if IsPedInAnyVehicle(ped, false) then
        ClearPedTasks(ped)
    else
        ClearPedTasksImmediately(ped)
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
    SetTimeScale(1.0)
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

local function playAnim(ped, dict, name, flag)
    RequestAnimDict(dict)
    local timeout = GetGameTimer() + 3000
    while not HasAnimDictLoaded(dict) and GetGameTimer() < timeout do Wait(0) end
    TaskPlayAnim(ped, dict, name, 4.0, -4.0, -1, flag, 0, false, false, false)
end

-- ===================== الفلم =====================

local function runNuke(t)
    running = true
    MC.setDreaming(true)

    DoScreenFadeOut(2000)
    if not wait(2100) then return end

    freezePlayer()
    MC.resetCity()
    MC.loadAssets()

    SetFocusPosAndVel(t.x, t.y, t.z + 50.0, 0.0, 0.0, 0.0)
    NetworkOverrideClockTime(N.ClockHour, N.ClockMinute, 0)
    SetOverrideWeather('CLEAR')
    SetWeatherTypeNowPersist('CLEAR')
    if not wait(1800) then return end

    local _, gz = MC.surfaceZ(t.x, t.y, t.z)
    local T = vector3(t.x, t.y, gz)

    -- كل فريم: نخفي الواجهة ونمنع التحكم
    CreateThread(function()
        while running do
            HideHudAndRadarThisFrame()
            DisableAllControlActions(0)
            Wait(0)
        end
    end)

    ui({ type = 'film', on = true })
    ui({ type = 'letterbox', on = true })
    sound('wind', { on = false, volume = N.Volume })

    -- ========== 1) مساء عادي ==========
    local c1 = makeCam(camPos(T, vector3(-520.0, -380.0, 260.0), 60.0), T + vector3(0.0, 0.0, 40.0), 45.0)
    local c2 = makeCam(camPos(T, vector3(-380.0, -470.0, 190.0), 60.0), T + vector3(0.0, 0.0, 20.0), 45.0)
    shot(c1, c2, 12000)
    DoScreenFadeIn(3000)
    if not wait(1500) then return end
    ui({ type = 'stamp', text = N.Text.stamp })
    if not wait(2000) then return end
    caption(N.Text.intro, 5000)
    if not wait(7000) then return end
    ui({ type = 'stamp', text = false })

    -- ========== 2) بث الطوارئ وصفارة الإنذار ==========
    local street = camPos(T, vector3(95.0, -125.0, 0.0), 1.8)
    local c3 = makeCam(street, T + vector3(0.0, 0.0, 60.0), 55.0)
    shot(c3)
    ShakeCam(c3, 'HAND_SHAKE', 0.8)
    ui({ type = 'tint', color = '#000', opacity = 0.45, ms = 500 })
    ui({ type = 'eas', on = true, title = N.Text.easTitle, text = N.Text.easBody, ticker = N.Text.easTicker })
    sound('siren')
    ui({ type = 'alarm', on = true })
    for _ = 1, 4 do
        PlaySoundFrontend(-1, 'Beep_Red', 'DLC_HEIST_HACKING_SNAKE_SOUNDS', true)
        if not wait(400) then return end
    end
    if not wait(5500) then return end
    ui({ type = 'eas', on = false })
    ui({ type = 'tint', color = '#000', opacity = 0, ms = 800 })

    -- ========== 3) الصاروخ جاي من بعيد ==========
    local c4 = makeCam(street, T + vector3(0.0, 0.0, 400.0), 55.0)
    shot(c4)
    ShakeCam(c4, 'HAND_SHAKE', 1.2)
    caption(N.Text.alarm, 3500, 'alarm')
    sound('heartbeat', { bpm = 115 })

    local away = vector3(T.x - street.x, T.y - street.y, 0.0)
    away = away / math.max(#away, 1.0)
    local from = T + away * N.MissileDistance + vector3(0.0, 0.0, N.MissileHeight)
    local dir = T - from

    local model = `w_lr_rpg_rocket`
    MC.loadModel(model)
    local missile = CreateObject(model, from.x, from.y, from.z, false, false, false)
    SetEntityCollision(missile, false, false)
    SetEntityLodDist(missile, 6000)
    local horiz = math.sqrt(dir.x * dir.x + dir.y * dir.y)
    SetEntityRotation(missile, math.deg(math.atan(dir.z, horiz)), 0.0, math.deg(math.atan(-dir.x, dir.y)), 2, true)

    UseParticleFxAssetNextCall('scr_ar_planes')
    local trail = StartParticleFxLoopedOnEntity('scr_ar_trail_smoke', missile, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 12.0, false, false, false)
    UseParticleFxAssetNextCall('core')
    local flame = StartParticleFxLoopedOnEntity('fire_wrecked_plane_cockpit', missile, 0.0, -1.2, 0.0, 0.0, 0.0, 0.0, 3.0, false, false, false)
    PointCamAtEntity(c4, missile, 0.0, 0.0, 0.0, true)

    local start = GetGameTimer()
    local silent = false
    while running do
        local p = (GetGameTimer() - start) / N.FallTime
        if p >= 1.0 then break end
        local e = p ^ 1.7
        local pos = from + dir * e
        SetEntityCoordsNoOffset(missile, pos.x, pos.y, pos.z, false, false, false)
        SetCamFov(c4, 55.0 - 30.0 * p)

        -- قبل الضربة بلحظة: كل شي يسكت
        if not silent and p > 0.88 then
            silent = true
            sound('siren', { on = false, fade = 0.4 })
            sound('heartbeat', { on = false, fade = 0.3 })
            ui({ type = 'alarm', on = false })
            caption('', 0)
        end
        Wait(0)
    end
    StopParticleFxLooped(trail, false)
    StopParticleFxLooped(flame, false)
    DeleteEntity(missile)
    if not running then return end

    -- ========== 4) الوميض ==========
    if N.SlowMotion then SetTimeScale(0.25) end
    ui({ type = 'flash', color = '#fffaf0', strength = 1, hold = 2200, fade = 5500 })
    sound('tinnitus', { seconds = 10 })
    MC.burst('scr_xm_orbital', 'scr_xm_orbital_blast', T.x, T.y, T.z, N.BlastScale)
    MC.burst('scr_xm_orbital', 'scr_xm_orbital_blast', T.x, T.y, T.z + 80.0, N.BlastScale * 0.8)
    MC.burst('core', 'exp_grd_petrol_pump', T.x, T.y, T.z + 10.0, N.BlastScale)
    fireball(T)
    MC.igniteCity({ x = T.x, y = T.y, z = T.z, seed = t.seed })
    MC.setStreamCenter(T)

    -- نجهز مكان الكاميرا البعيدة وهي مخفية ورا الوميض
    local D = N.CameraDistance
    local farOff = vector3(-0.72 * D, -0.69 * D, 0.0)
    SetFocusPosAndVel(T.x + farOff.x, T.y + farOff.y, T.z, 0.0, 0.0, 0.0)
    Wait(600)
    SetTimeScale(1.0)
    if not wait(1400) then return end

    -- ========== 5) المنظر البعيد: كرة النار والفطر والموجة جاية ==========
    local cFar1 = makeCam(camPos(T, farOff + vector3(0.0, 0.0, 70.0), 35.0), T + vector3(0.0, 0.0, N.MushroomHeight * 0.45), 48.0)
    local cFar2 = makeCam(camPos(T, farOff * 0.92 + vector3(0.0, 0.0, 75.0), 35.0), T + vector3(0.0, 0.0, N.MushroomHeight * 0.55), 44.0)
    shot(cFar1, cFar2, 17000)
    ShakeCam(cFar1, 'HAND_SHAKE', 0.5)
    ShakeCam(cFar2, 'HAND_SHAKE', 0.5)
    ui({ type = 'tint', color = '#ff7a1a', opacity = 0.35, ms = 300 })
    Wait(400)
    ui({ type = 'tint', color = '#ff7a1a', opacity = 0, ms = 7000 })
    sound('rumble')
    mushroomCloud(T)

    shockwave(T, D * 0.95, function()
        -- الموجة وصلت للكاميرا: صوت الانفجار يوصل معها، اهتزاز، وانقطاع الإشارة
        sound('boom', { power = 1.3 })
        ShakeCam(cFar2, 'LARGE_EXPLOSION_SHAKE', 4.0)
        ui({ type = 'flash', color = '#c8b8a0', strength = 0.5, hold = 100, fade = 900 })
        ui({ type = 'static', duration = 1500 })
        PlaySoundFrontend(-1, 'ScreenFlash', 'WastedSounds', true)
    end)
    if not wait(15000) then return end

    -- ========== 6) الدمار من فوق، والرماد يطيح ==========
    SetFocusPosAndVel(T.x, T.y, T.z + 100.0, 0.0, 0.0, 0.0)
    MC.setStreamCenter(T + vector3(0.0, -120.0, 0.0))
    local c7 = makeCam(camPos(T, vector3(-280.0, -170.0, 170.0), 60.0), T + vector3(0.0, 0.0, 30.0), 50.0)
    local c8 = makeCam(camPos(T, vector3(170.0, -230.0, 140.0), 60.0), T + vector3(0.0, 0.0, 90.0), 50.0)
    shot(c7, c8, 11000)
    ShakeCam(c7, 'HAND_SHAKE', 0.4)
    ShakeCam(c8, 'HAND_SHAKE', 0.4)
    ui({ type = 'ash', on = true })
    sound('wind')
    sound('rumble', { on = false, fade = 6 })
    if not wait(1500) then return end
    caption(N.Text.after, 6000)

    -- نجهز النار حول اللاعب قبل اللقطة الجاية
    local ped = PlayerPedId()
    local me = GetEntityCoords(ped)
    if not wait(5000) then return end
    SetFocusPosAndVel(me.x, me.y, me.z, 0.0, 0.0, 0.0)
    MC.setStreamCenter(me)
    if not wait(4500) then return end

    -- ========== 7) انت في مكانك وسط الخراب ==========
    local inVeh = IsPedInAnyVehicle(ped, false)
    if not inVeh then playAnim(ped, 'random@arrests@busted', 'idle_a', 1) end
    TaskLookAtCoord(ped, T.x, T.y, T.z + 300.0, 20000, 0, 2)

    local orbit = makeCam(me, nil, 50.0)
    shot(orbit)
    ShakeCam(orbit, 'HAND_SHAKE', 0.5)
    sound('heartbeat', { bpm = 90 })

    local radius, height = inVeh and 9.0 or 6.0, inVeh and 2.5 or 1.2
    local a0 = math.rad(GetEntityHeading(ped) + 200.0)
    local oStart = GetGameTimer()
    local beat = 90
    local shownAlone = false
    while running do
        local p = (GetGameTimer() - oStart) / 13000
        if p >= 1.0 then break end
        local a = a0 + p * math.rad(70.0)
        local r = radius - p * 2.0
        SetCamCoord(orbit, me.x + math.cos(a) * r, me.y + math.sin(a) * r, me.z + height)
        PointCamAtCoord(orbit, me.x, me.y, me.z + 0.4)

        -- القلب يبطى شوي شوي
        local want = math.floor(90 - 45 * p)
        if want <= beat - 10 then
            beat = want
            sound('heartbeat', { bpm = beat })
        end
        if not shownAlone and p > 0.35 then
            shownAlone = true
            caption(N.Text.alone, 3000, 'big')
        end
        Wait(0)
    end
    if not running then return end

    -- ========== 8) نور أبيض... وسكوت ==========
    sound('heartbeat', { on = false, fade = 2 })
    sound('wind', { on = false, fade = 3 })
    ui({ type = 'tint', color = '#ffffff', opacity = 1, ms = 3500 })
    if not wait(4200) then return end
    DoScreenFadeOut(0)
    ui({ type = 'tint', color = '#000000', opacity = 1, ms = 1200 })
    if not wait(1800) then return end

    -- ========== 9) يصحى: كان مجرد حلم ==========
    cleanup()
    MC.syncFromGlobal()
    Wait(1200)

    sound('heartbeat', { bpm = 125, volume = N.Volume })
    DoScreenFadeIn(1200)
    AnimpostfxPlay('DrugsDrivingOut', 0, false)
    ShakeGameplayCam('HAND_SHAKE', 0.6)
    if not IsPedInAnyVehicle(PlayerPedId(), false) then
        playAnim(PlayerPedId(), 'anim@mp_player_intcelebrationmale@face_palm', 'face_palm', 48)
    end
    caption(N.Text.wake, 5500, 'big')
    Wait(2500)
    sound('heartbeat', { bpm = 70 })
    Wait(3500)
    sound('heartbeat', { on = false, fade = 1.5 })
    StopGameplayCamShaking(false)
end

RegisterNetEvent('missile_city:nuke', function(t)
    if running then return end
    -- اللي في العالم الثلجي ما يدخل الحلم
    if LocalPlayer.state.snowWorld then return end
    CreateThread(function() runNuke(t) end)
end)

TriggerEvent('chat:addSuggestion', '/' .. Config.Commands.nuke, 'نووي حقيقي: دقيقتين للهروب للبحر (أو dream للحلم)', { { name = 'dream', help = 'اختياري: الفلم اللي ينتهي بحلم' } })

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and running then
        cleanup()
        DoScreenFadeIn(0)
    end
end)
