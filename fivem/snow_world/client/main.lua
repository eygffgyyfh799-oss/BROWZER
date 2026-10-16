-- شكل كل عالم: الطقس والوقت والأنوار والفلتر
--
-- منع التعارض مع سكربت الطقس والوقت:
-- ما نوقف سكربت الطقس (إيقافه في qb-weathersync يجبر جو صافي والساعة 11 بالليل)
-- بدال كذا نخليه هو نفسه يطبق طقس ووقت العالم عند هذا اللاعب، فما يصير بينهم قتال ولا رمشة
-- يدعم qb-weathersync و qbx و vSync و Renewed-Weathersync، وأي سكربت ثاني فيه فحص خفيف كل ربع ثانية
-- اللي في العالم العادي ما يتغير عنده أي شي أبد

local current = nil        -- مفتاح العالم الحالي (nil = العادي)
local version = 0          -- يمنع التداخل لو انتقل اللاعب بسرعة
local echo = false         -- عشان نعرف الأحداث اللي احنا أرسلناها
local real = {}            -- آخر طقس ووقت حقيقي من السيرفر

local function W() return current and Config.Worlds[current] end

-- ===================== توجيه سكربتات الطقس =====================

local function send(event, ...)
    echo = true
    TriggerEvent(event, ...)
    echo = false
end

local function blackoutFor(w, realBlackout)
    if w.blackout ~= nil then return w.blackout end
    return realBlackout or false
end

-- نخلي سكربت الطقس يطبق جو العالم
local function redirect()
    local w = W()
    if not w then return end
    send('qb-weathersync:client:SyncWeather', w.weather, blackoutFor(w, real.qbW and real.qbW[2]))
    send('vSync:updateWeather', w.weather, blackoutFor(w, real.vW and real.vW[2]))
    if w.time then
        local base = w.time[1] * 60 + (w.time[2] or 0)
        send('qb-weathersync:client:SyncTime', base, 0, true)
        send('vSync:updateTime', base, 0, true)
    end
    LocalPlayer.state:set('syncWeather', false, false) -- Renewed-Weathersync
end

-- نرجع طقس ووقت السيرفر الحقيقي
local function restore(hadTime)
    if real.qbW then send('qb-weathersync:client:SyncWeather', table.unpack(real.qbW)) end
    if real.vW then send('vSync:updateWeather', table.unpack(real.vW)) end
    if hadTime then
        if real.qbT then send('qb-weathersync:client:SyncTime', table.unpack(real.qbT)) end
        if real.vT then send('vSync:updateTime', table.unpack(real.vT)) end
    end
    LocalPlayer.state:set('syncWeather', true, false)
    TriggerServerEvent('qb-weathersync:server:RequestStateSync')
    TriggerServerEvent('vSync:requestSync')
end

-- لو السيرفر أرسل طقس أو وقت جديد ونحن في عالم ثاني: نحفظه ونرجع جو العالم
local function watch(event, slot, isTime)
    RegisterNetEvent(event, function(...)
        if echo then return end
        real[slot] = { ... }
        local w = W()
        if w and (not isTime or w.time) then
            SetTimeout(0, function()
                if W() then redirect() end
            end)
        end
    end)
end

watch('qb-weathersync:client:SyncWeather', 'qbW', false)
watch('qb-weathersync:client:SyncTime', 'qbT', true)
watch('vSync:updateWeather', 'vW', false)
watch('vSync:updateTime', 'vT', true)

-- ===================== تطبيق شكل العالم =====================

local function applyLook(w, force)
    local hash = joaat(w.weather)
    if force or GetPrevWeatherTypeHashName() ~= hash or GetNextWeatherTypeHashName() ~= hash then
        SetWeatherTypeNowPersist(w.weather)
        SetOverrideWeather(w.weather)
    end
    if w.time then
        local h, m = w.time[1], w.time[2] or 0
        if force or GetClockHours() ~= h or math.abs(GetClockMinutes() - m) > 1 then
            NetworkOverrideClockTime(h, m, 0)
        end
    end
    if w.blackout ~= nil then SetArtificialLightsState(w.blackout) end
    if w.snow then
        ForceSnowPass(true)
        SetForcePedFootstepsTracks(true)
        SetForceVehicleTrails(true)
    end
end

local function enterLook(w)
    redirect()
    if w.snow then
        RequestScriptAudioBank('ICE_FOOTSTEPS', false)
        RequestScriptAudioBank('SNOW_FOOTSTEPS', false)
    end
    if w.timecycle then
        SetTimecycleModifier(w.timecycle)
        SetTimecycleModifierStrength(w.timecycleStrength or 0.5)
    end
    applyLook(w, true)
end

local function leaveLook(w)
    ClearOverrideWeather()
    ClearWeatherTypePersist()
    if w.time then NetworkClearClockTimeOverride() end
    if w.blackout ~= nil then SetArtificialLightsState(false) end
    if w.timecycle then ClearTimecycleModifier() end
    if w.snow then
        ForceSnowPass(false)
        SetForcePedFootstepsTracks(false)
        SetForceVehicleTrails(false)
        ReleaseNamedScriptAudioBank('ICE_FOOTSTEPS')
        ReleaseNamedScriptAudioBank('SNOW_FOOTSTEPS')
    end
end

local function switchTo(key, instant)
    if key == current then return end
    version = version + 1
    local v = version
    local old = W()
    local new = key and Config.Worlds[key] or nil

    CreateThread(function()
        if not instant then
            DoScreenFadeOut(700)
            Wait(800)
            if v ~= version then return end
        end

        if old then leaveLook(old) end
        current = new and key or nil
        if new then
            enterLook(new)
        else
            restore(old and old.time ~= nil)
        end

        -- فحص خفيف: لو أي سكربت غير الجو أو الوقت نرجعه
        if new then
            CreateThread(function()
                while v == version and current == key do
                    applyLook(new, false)
                    Wait(250)
                end
            end)
        end

        if not instant then
            Wait(900)
            DoScreenFadeIn(1200)
        end
    end)
end

AddStateBagChangeHandler('world', ('player:%d'):format(GetPlayerServerId(PlayerId())), function(_, _, value)
    switchTo(value or nil, false)
end)

-- ===================== جاهزية اللاعب (للحفظ) =====================
-- لما اللاعب ينزل أو يختار شخصيته نقول للسيرفر يرجعه لعالمه المحفوظ

local lastReady = 0
local function ready()
    if GetGameTimer() - lastReady < 10000 then return end
    lastReady = GetGameTimer()
    TriggerServerEvent('worlds:ready')
end

AddEventHandler('playerSpawned', ready)
RegisterNetEvent('QBCore:Client:OnPlayerLoaded', ready)
RegisterNetEvent('esx:playerLoaded', ready)

CreateThread(function()
    Wait(1500)
    local key = LocalPlayer.state.world
    if key then switchTo(key, true) end
end)

-- ===================== للسكربتات الثانية =====================
-- exports.snow_world:GetWorld()      -> 'main' أو 'snow' ...
-- exports.snow_world:IsInSnowWorld() -> true لو في أي عالم غير العادي
exports('GetWorld', function() return current or 'main' end)
exports('IsInSnowWorld', function() return current ~= nil end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() or not current then return end
    local w = W()
    version = version + 1
    current = nil
    leaveLook(w)
    restore(w.time ~= nil)
    DoScreenFadeIn(0)
end)
