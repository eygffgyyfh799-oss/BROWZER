-- جو ثلج دايم لكل اللاعبين
--
-- بدون تعارض مع سكربت الطقس:
-- ما نوقف سكربت الطقس، نخليه هو نفسه يطبق الثلج (qb-weathersync و qbx و vSync و Renewed)
-- وأي سكربت ثاني فيه فحص خفيف يرجع الثلج بس لو الجو فعلاً تغير
-- الوقت ما نلمسه أبد، يبقى متزامن مع السيرفر

local SNOW = Config.Weather
local snowHash = joaat(SNOW)
local echo = false
local paused = false
local manualPause = false

-- يوقف مؤقتاً لما سكربت ثاني يحتاج الجو (حريق المدينة، العالم الثلجي، فلم النووي)
local function shouldPause()
    return manualPause or GlobalState.missileCity or LocalPlayer.state.world
end

local function send(event, ...)
    echo = true
    TriggerEvent(event, ...)
    echo = false
end

-- نخلي سكربت الطقس يطبق الثلج
local function redirect()
    send('qb-weathersync:client:SyncWeather', SNOW, false)
    send('vSync:updateWeather', SNOW, false)
    LocalPlayer.state:set('syncWeather', false, false) -- Renewed-Weathersync
end

-- لو السيرفر أرسل طقس ثاني نرجعه ثلج عن طريق سكربت الطقس نفسه
for _, event in ipairs({ 'qb-weathersync:client:SyncWeather', 'vSync:updateWeather' }) do
    RegisterNetEvent(event, function(weather)
        if echo or paused or weather == SNOW then return end
        SetTimeout(0, function()
            if not paused then redirect() end
        end)
    end)
end

local function applySnow(force)
    if force or GetPrevWeatherTypeHashName() ~= snowHash or GetNextWeatherTypeHashName() ~= snowHash then
        SetWeatherTypeNowPersist(SNOW)
        SetOverrideWeather(SNOW)
    end
    if Config.GroundSnow then ForceSnowPass(true) end
    if Config.FootTracks then
        SetForcePedFootstepsTracks(true)
        SetForceVehicleTrails(true)
    end
end

local function stopSnow()
    ClearOverrideWeather()
    ClearWeatherTypePersist()
    ForceSnowPass(false)
    SetForcePedFootstepsTracks(false)
    SetForceVehicleTrails(false)
    LocalPlayer.state:set('syncWeather', true, false)
    TriggerServerEvent('qb-weathersync:server:RequestStateSync')
    TriggerServerEvent('vSync:requestSync')
end

CreateThread(function()
    if Config.SnowSounds then
        RequestScriptAudioBank('ICE_FOOTSTEPS', false)
        RequestScriptAudioBank('SNOW_FOOTSTEPS', false)
    end
    Wait(1000)
    redirect()
    applySnow(true)

    -- فحص خفيف كل ربع ثانية: يرجع الثلج بس لو الجو تغير
    while true do
        local pause = shouldPause() and true or false
        if pause ~= paused then
            paused = pause
            if paused then
                -- نخلي الجو للسكربت الثاني
                stopSnow()
            else
                redirect()
                applySnow(true)
            end
        end
        if not paused then applySnow(false) end
        Wait(250)
    end
end)

-- لسكربتات ثانية: exports.always_snow:Pause(true / false)
exports('Pause', function(on) manualPause = on and true or false end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    stopSnow()
    if Config.SnowSounds then
        ReleaseNamedScriptAudioBank('ICE_FOOTSTEPS')
        ReleaseNamedScriptAudioBank('SNOW_FOOTSTEPS')
    end
end)
