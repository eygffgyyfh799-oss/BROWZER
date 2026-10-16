-- النووي الحقيقي:
-- إنذار طوارئ + صفارة + عداد دقيقتين: "اهرب إلى البحر"
-- اللي يكون عند البحر (أو في الماء أو في قارب) لما توصله موجة الانفجار ينجو، والباقي يموت
-- اللي في العالم الثلجي (snow_world) ما يتأثر

local R = Config.NukeReal
local active = false
local fx = {}

local function ui(data) SendNUIMessage(data) end
local function sound(name, opts)
    local d = opts or {}
    d.type, d.name = 'sound', name
    ui(d)
end
local function rand(a, b) return a + math.random() * (b - a) end

-- ===================== هل اللاعب في أمان؟ =====================
-- في قارب، أو في الماء، أو قريب من البحر (مو بحيرة)
local function isSafe()
    local ped = PlayerPedId()
    if IsPedInAnyBoat(ped) or IsPedInAnySub(ped) or IsPedSwimming(ped) or IsEntityInWater(ped) then return true end
    local veh = GetVehiclePedIsIn(ped, false)
    if veh ~= 0 and IsEntityInWater(veh) then return true end

    local p = GetEntityCoords(ped)
    local function sea(x, y)
        local found, h = GetWaterHeight(x, y, p.z)
        return found and h <= R.SeaLevelMax
    end
    if sea(p.x, p.y) then return true end
    for i = 1, 16 do
        local a = (i / 16) * 2 * math.pi
        if sea(p.x + math.cos(a) * R.SafeRadius, p.y + math.sin(a) * R.SafeRadius) then return true end
    end
    return false
end

-- نقطة GPS على أقرب بحر
local function waypointToSea()
    if not R.SetWaypoint then return end
    local p = GetEntityCoords(PlayerPedId())
    local best, bestDist
    for _, pt in ipairs(R.SeaPoints) do
        local d = #(vector2(p.x, p.y) - pt)
        if not bestDist or d < bestDist then best, bestDist = pt, d end
    end
    if best then SetNewWaypoint(best.x, best.y) end
end

-- ===================== مؤثرات الانفجار =====================

local function blast(T)
    MC.burst('scr_xm_orbital', 'scr_xm_orbital_blast', T.x, T.y, T.z, 14.0)
    MC.burst('scr_xm_orbital', 'scr_xm_orbital_blast', T.x, T.y, T.z + 80.0, 11.0)
    MC.burst('core', 'exp_grd_petrol_pump', T.x, T.y, T.z + 10.0, 14.0)

    -- كرة النار وسحابة الفطر
    CreateThread(function()
        for i = 1, 30 do
            local a, r = rand(0, 2 * math.pi), rand(0, 90)
            MC.burst('scr_xm_orbital', 'scr_xm_orbital_blast', T.x + math.cos(a) * r, T.y + math.sin(a) * r, T.z + 20 + i * 5, rand(6.0, 10.0))
            Wait(100)
        end
        for i = 1, 24 do
            MC.burst('scr_xm_orbital', 'scr_xm_orbital_blast', T.x, T.y, T.z + 150 + i * 16, 4.5)
            Wait(150)
        end
        for k = 1, 8 do
            for j = 1, 12 do
                local a = (j / 12) * 2 * math.pi
                local r = 40 + k * 22
                MC.burst('scr_xm_orbital', 'scr_xm_orbital_blast', T.x + math.cos(a) * r, T.y + math.sin(a) * r, T.z + 540 + rand(-40, 40), 6.0)
            end
            Wait(220)
        end
    end)

    fx[#fx + 1] = MC.looped('core', 'ent_ray_heli_aprtmnt_l_fire', T.x, T.y, T.z, 18.0)
    for _, h in ipairs({ 0, 180, 360, 540 }) do
        fx[#fx + 1] = MC.looped('scr_agencyheistb', 'scr_env_agency3b_smoke', T.x, T.y, T.z + h, 20.0)
    end

    -- موجة الصدمة على الأرض
    CreateThread(function()
        for r = 80.0, 1800.0, 60.0 do
            local n = math.min(40, math.floor(r / 35) + 10)
            for j = 1, n do
                local a = (j / n) * 2 * math.pi
                local x, y = T.x + math.cos(a) * r, T.y + math.sin(a) * r
                local _, gz = MC.surfaceZ(x, y, T.z)
                MC.burst('core', 'exp_grd_bzgas_smoke', x, y, gz, 7.0)
                if j % 2 == 0 then MC.burst('core', 'exp_grd_petrol_pump', x, y, gz, 3.5) end
            end
            Wait(250)
        end
    end)
end

-- الصاروخ اللي ينشاف في السما آخر 10 ثواني
local function incomingMissile(T, ms)
    CreateThread(function()
        local model = `w_lr_rpg_rocket`
        MC.loadModel(model)
        local from = T + vector3(-1800.0, -1200.0, 1800.0)
        local dir = T - from
        local obj = CreateObject(model, from.x, from.y, from.z, false, false, false)
        SetEntityCollision(obj, false, false)
        SetEntityLodDist(obj, 6000)
        local horiz = math.sqrt(dir.x * dir.x + dir.y * dir.y)
        SetEntityRotation(obj, math.deg(math.atan(dir.z, horiz)), 0.0, math.deg(math.atan(-dir.x, dir.y)), 2, true)
        UseParticleFxAssetNextCall('scr_ar_planes')
        local trail = StartParticleFxLoopedOnEntity('scr_ar_trail_smoke', obj, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 12.0, false, false, false)
        UseParticleFxAssetNextCall('core')
        local flame = StartParticleFxLoopedOnEntity('fire_wrecked_plane_cockpit', obj, 0.0, -1.2, 0.0, 0.0, 0.0, 0.0, 3.0, false, false, false)

        local start = GetGameTimer()
        while active do
            local p = (GetGameTimer() - start) / ms
            if p >= 1.0 then break end
            local pos = from + dir * (p ^ 1.6)
            SetEntityCoordsNoOffset(obj, pos.x, pos.y, pos.z, false, false, false)
            Wait(0)
        end
        StopParticleFxLooped(trail, false)
        StopParticleFxLooped(flame, false)
        DeleteEntity(obj)
    end)
end

-- ===================== التسلسل =====================

local function run(t)
    active = true
    MC.loadAssets()
    local _, gz = MC.surfaceZ(t.x, t.y, t.z)
    local T = vector3(t.x, t.y, gz)
    local deadline = GetGameTimer() + t.countdown * 1000

    -- الإنذار
    ui({ type = 'sound', name = 'wind', on = false, volume = Config.Nuke.Volume })
    ui({ type = 'eas', on = true, title = R.Text.easTitle, text = R.Text.easBody, ticker = R.Text.easTicker })
    ui({ type = 'alarm', on = true })
    sound('siren')
    for _ = 1, 4 do
        PlaySoundFrontend(-1, 'Beep_Red', 'DLC_HEIST_HACKING_SNAKE_SOUNDS', true)
        Wait(400)
    end
    waypointToSea()
    SetTimeout(12000, function() ui({ type = 'eas', on = false }) end)

    -- العداد
    local missileShown, heart = false, false
    while active do
        local left = (deadline - GetGameTimer()) / 1000
        if left <= 0 then break end
        local safe = isSafe()
        ui({ type = 'countdown', on = true, seconds = left, label = R.Text.countdown, safe = safe, safeText = safe and R.Text.safe or R.Text.unsafe })

        if left <= 10 and not missileShown then
            missileShown = true
            incomingMissile(T, left * 1000)
            ui({ type = 'caption', text = R.Text.last, duration = 4000, style = 'alarm' })
        end
        if left <= 20 and not heart then
            heart = true
            sound('heartbeat', { bpm = 120 })
        end
        Wait(250)
    end
    if not active then return end

    -- الانفجار: الوميض يشوفه الكل فوراً
    ui({ type = 'countdown', on = false })
    ui({ type = 'alarm', on = false })
    sound('siren', { on = false, fade = 0.2 })
    sound('heartbeat', { on = false, fade = 0.2 })
    ui({ type = 'flash', color = '#fffaf0', strength = 1, hold = 1200, fade = 4000 })
    sound('tinnitus', { seconds = 8 })
    blast(T)
    MC.igniteCity({ x = T.x, y = T.y, z = T.z, seed = t.seed })

    -- الموجة توصل حسب بعدك عن الانفجار
    local dist = #(GetEntityCoords(PlayerPedId()) - T)
    local delay = math.min(dist / Config.Nuke.ShockwaveSpeed, R.KillDelayMax)
    Wait(math.floor(delay * 1000))
    if not active then return end

    sound('boom', { power = 1.3 })
    ShakeGameplayCam('LARGE_EXPLOSION_SHAKE', 2.5)
    ui({ type = 'flash', color = '#c8b8a0', strength = 0.6, hold = 200, fade = 1500 })

    if isSafe() then
        ui({ type = 'caption', text = R.Text.survived, duration = 5000, style = 'big' })
    else
        ui({ type = 'flash', color = '#ffffff', strength = 1, hold = 600, fade = 3000 })
        SetEntityHealth(PlayerPedId(), 0)
    end

    active = false
end

RegisterNetEvent('missile_city:nukeReal', function(t)
    if active then return end
    -- اللي في العالم الثلجي في عالم ثاني، ما يتأثر
    if LocalPlayer.state.snowWorld then return end
    CreateThread(function() run(t) end)
end)

-- /resetcity يشيل الفطر والدخان بعد
RegisterNetEvent('missile_city:reset', function()
    for _, f in ipairs(fx) do StopParticleFxLooped(f, false) end
    fx = {}
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    active = false
    for _, f in ipairs(fx) do StopParticleFxLooped(f, false) end
    ui({ type = 'clear' })
end)
