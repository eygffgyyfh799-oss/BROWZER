-- كل المؤثرات شكل فقط: دخان، شفافية، توهج، أصوات، اهتزاز كاميرا
-- ما فيه أي ضرر على اللاعبين الثانيين

local auras = {}          -- [serverId] = { ped = ped, fx = {...} }
local isJinn = false
local flying = false
local invisible = false
local lastBlink, lastScream = 0, 0

local function loadPtfx(asset)
    RequestNamedPtfxAsset(asset)
    local timeout = GetGameTimer() + 5000
    while not HasNamedPtfxAssetLoaded(asset) and GetGameTimer() < timeout do Wait(0) end
end

local function burst(asset, name, x, y, z, scale)
    loadPtfx(asset)
    UseParticleFxAssetNextCall(asset)
    StartParticleFxNonLoopedAtCoord(name, x, y, z, 0.0, 0.0, 0.0, scale, false, false, false)
end

-- ===================== شكل الجني (يشوفه كل اللاعبين) =====================

local function attachAura(ped)
    loadPtfx('core')
    local fx = {}

    -- دخان أسود يطلع من الجني
    UseParticleFxAssetNextCall('core')
    fx[#fx + 1] = StartParticleFxLoopedOnEntity('ent_amb_smoke_foundry', ped, 0.0, 0.0, -0.9, 0.0, 0.0, 0.0, 0.35, false, false, false)

    -- عيون نار
    if Config.FireEyes then
        local head = GetPedBoneIndex(ped, 31086)
        local o = Config.EyeOffset
        for _, side in ipairs({ 1, -1 }) do
            UseParticleFxAssetNextCall('core')
            fx[#fx + 1] = StartParticleFxLoopedOnEntityBone('fire_wrecked_plane_cockpit', ped, o.x, o.y, o.z * side, 0.0, 0.0, 0.0, head, Config.EyeScale, false, false, false)
        end
    end

    return fx
end

local function removeAura(serverId)
    local a = auras[serverId]
    if not a then return end
    for _, fx in ipairs(a.fx) do StopParticleFxLooped(fx, false) end
    if DoesEntityExist(a.ped) then ResetEntityAlpha(a.ped) end
    auras[serverId] = nil
end

-- يرسم الجن القريبين كل فريم
CreateThread(function()
    while true do
        local myPed = PlayerPedId()
        local myPos = GetEntityCoords(myPed)
        local seen = {}
        local sleep = 500

        for _, player in ipairs(GetActivePlayers()) do
            local sid = GetPlayerServerId(player)
            local state = Player(sid).state
            local ped = GetPlayerPed(player)

            if state.jinn and DoesEntityExist(ped) and #(GetEntityCoords(ped) - myPos) < Config.RenderDistance then
                seen[sid] = true
                sleep = 0

                -- لو اللاعب رسبن ونتغير الـ ped نركب المؤثرات من جديد
                if auras[sid] and auras[sid].ped ~= ped then removeAura(sid) end
                if not auras[sid] then auras[sid] = { ped = ped, fx = attachAura(ped) } end

                local invis = state.jinnInvis
                if invis then
                    SetEntityAlpha(ped, ped == myPed and Config.InvisibleSelfAlpha or 0, false)
                else
                    SetEntityAlpha(ped, Config.GhostAlpha, false)
                    local p = GetEntityCoords(ped)
                    local c = Config.GlowColor
                    DrawLightWithRange(p.x, p.y, p.z, c[1], c[2], c[3], 4.0, 6.0)
                end
            end
        end

        for sid in pairs(auras) do
            if not seen[sid] then removeAura(sid) end
        end

        Wait(sleep)
    end
end)

-- ===================== التحول =====================

local function setFlying(on)
    local ped = PlayerPedId()
    flying = on
    FreezeEntityPosition(ped, on)
    SetEntityCollision(ped, not on, not on)
    if not on then
        -- ينزل على الأرض بهدوء
        local p = GetEntityCoords(ped)
        local found, z = GetGroundZFor_3dCoord(p.x, p.y, p.z, false)
        if found then SetEntityCoordsNoOffset(ped, p.x, p.y, z, false, false, false) end
    end
end

local function transform(on)
    local ped = PlayerPedId()
    local p = GetEntityCoords(ped)
    isJinn = on

    burst('scr_rcbarry2', 'scr_clown_appears', p.x, p.y, p.z, 2.5)
    burst('scr_trevor1', 'scr_trev1_trailer_boosh', p.x, p.y, p.z, 1.5)
    PlaySoundFrontend(-1, 'ScreenFlash', 'WastedSounds', true)
    ShakeGameplayCam('MEDIUM_EXPLOSION_SHAKE', 0.6)

    if on then
        AnimpostfxPlay('DrugsMichaelAliensFightIn', 0, false)
        SetTimeout(1500, function() AnimpostfxStop('DrugsMichaelAliensFightIn') end)
        SetTimecycleModifier(Config.Timecycle)
        SetTimecycleModifierStrength(Config.TimecycleStrength)
        if Config.Invincible then SetEntityInvincible(ped, true) end
        SetPedCanRagdoll(ped, false)
        if Config.FastRun then SetRunSprintMultiplierForPlayer(PlayerId(), 1.49) end
    else
        if flying then setFlying(false) end
        invisible = false
        ClearTimecycleModifier()
        AnimpostfxStopAll()
        SetEntityInvincible(ped, false)
        SetPedCanRagdoll(ped, true)
        SetRunSprintMultiplierForPlayer(PlayerId(), 1.0)
    end
end

AddStateBagChangeHandler('jinn', ('player:%d'):format(GetPlayerServerId(PlayerId())), function(_, _, value)
    if (value == true) ~= isJinn then transform(value == true) end
end)

-- ===================== الطيران =====================

CreateThread(function()
    while true do
        if isJinn and flying then
            local ped = PlayerPedId()
            local rot = GetGameplayCamRot(2)
            local h, pitch = math.rad(rot.z), math.rad(rot.x)
            local fwd = vector3(-math.sin(h) * math.cos(pitch), math.cos(h) * math.cos(pitch), math.sin(pitch))
            local right = vector3(math.cos(h), math.sin(h), 0.0)
            local speed = Config.FlySpeed * (IsControlPressed(0, 21) and Config.FlyFastMultiplier or 1.0)
            local move = vector3(0.0, 0.0, 0.0)

            DisableControlAction(0, 22, true) -- القفز
            DisableControlAction(0, 36, true) -- الانحناء

            if IsControlPressed(0, 32) then move = move + fwd end
            if IsControlPressed(0, 33) then move = move - fwd end
            if IsControlPressed(0, 35) then move = move + right end
            if IsControlPressed(0, 34) then move = move - right end
            if IsDisabledControlPressed(0, 22) then move = move + vector3(0.0, 0.0, 1.0) end
            if IsDisabledControlPressed(0, 36) then move = move - vector3(0.0, 0.0, 1.0) end

            local p = GetEntityCoords(ped) + move * speed
            SetEntityCoordsNoOffset(ped, p.x, p.y, p.z, false, false, false)
            SetEntityHeading(ped, rot.z)
            Wait(0)
        elseif isJinn then
            -- نعيدها كل فريم عشان لو رسبنت تبقى القدرات
            if Config.FastRun then SetSuperJumpThisFrame(PlayerId()) end
            if Config.Invincible then SetEntityInvincible(PlayerPedId(), true) end
            Wait(0)
        else
            Wait(500)
        end
    end
end)

-- ===================== الأزرار =====================

RegisterCommand('+jinn_fly', function()
    if isJinn then setFlying(not flying) end
end, false)
RegisterCommand('-jinn_fly', function() end, false)
RegisterKeyMapping('+jinn_fly', 'جني: طيران', 'keyboard', Config.Keys.fly)

RegisterCommand('+jinn_blink', function()
    if not isJinn or GetGameTimer() - lastBlink < Config.BlinkCooldown then return end
    lastBlink = GetGameTimer()
    local ped = PlayerPedId()
    local from = GetEntityCoords(ped)
    local h = math.rad(GetGameplayCamRot(2).z)
    local to = from + vector3(-math.sin(h), math.cos(h), 0.0) * Config.BlinkDistance

    if not flying then
        local found, z = GetGroundZFor_3dCoord(to.x, to.y, to.z + 50.0, false)
        if found then to = vector3(to.x, to.y, z) end
    end

    TriggerServerEvent('jinn:puff', from.x, from.y, from.z)
    SetEntityCoordsNoOffset(ped, to.x, to.y, to.z, false, false, false)
    TriggerServerEvent('jinn:puff', to.x, to.y, to.z)
end, false)
RegisterCommand('-jinn_blink', function() end, false)
RegisterKeyMapping('+jinn_blink', 'جني: انتقال سريع', 'keyboard', Config.Keys.blink)

RegisterCommand('+jinn_invisible', function()
    if not isJinn then return end
    invisible = not invisible
    local p = GetEntityCoords(PlayerPedId())
    TriggerServerEvent('jinn:puff', p.x, p.y, p.z)
    TriggerServerEvent('jinn:invisible', invisible)
end, false)
RegisterCommand('-jinn_invisible', function() end, false)
RegisterKeyMapping('+jinn_invisible', 'جني: اختفاء', 'keyboard', Config.Keys.invisible)

RegisterCommand('+jinn_scream', function()
    if not isJinn or GetGameTimer() - lastScream < Config.ScreamCooldown then return end
    lastScream = GetGameTimer()
    TriggerServerEvent('jinn:scream')
end, false)
RegisterCommand('-jinn_scream', function() end, false)
RegisterKeyMapping('+jinn_scream', 'جني: صرخة', 'keyboard', Config.Keys.scream)

-- ===================== مؤثرات من السيرفر =====================

RegisterNetEvent('jinn:puff', function(x, y, z)
    if #(GetEntityCoords(PlayerPedId()) - vector3(x, y, z)) > Config.RenderDistance then return end
    burst('scr_rcbarry2', 'scr_clown_appears', x, y, z, 1.5)
end)

RegisterNetEvent('jinn:scream', function(src, coords)
    local dist = #(GetEntityCoords(PlayerPedId()) - coords)
    if dist > Config.RenderDistance then return end

    burst('scr_rcbarry2', 'scr_clown_death', coords.x, coords.y, coords.z, 3.0)
    burst('scr_trevor1', 'scr_trev1_trailer_boosh', coords.x, coords.y, coords.z, 2.0)

    if dist <= Config.ScreamRadius then
        PlaySoundFrontend(-1, 'Bed', 'WastedSounds', true)
        ShakeGameplayCam('LARGE_EXPLOSION_SHAKE', 0.5)
        -- الجني نفسه ما يتأثر بالفلتر
        if src ~= GetPlayerServerId(PlayerId()) then
            AnimpostfxPlay('Rampage', 0, false)
            SetTimeout(2500, function() AnimpostfxStop('Rampage') end)
        end
    end
end)

-- اقتراح الأمر في الشات
TriggerEvent('chat:addSuggestion', '/' .. Config.Command, 'تتحول جني أو ترجع طبيعي')

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for sid in pairs(auras) do removeAura(sid) end
    if isJinn then transform(false) end
end)
