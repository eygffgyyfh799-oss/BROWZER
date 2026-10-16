-- مطر وبرق دايم لكل اللاعبين
--
-- بدون تعارض مع سكربت الطقس:
-- ما نوقف سكربت الطقس، نخليه هو نفسه يطبق المطر والبرق (qb-weathersync و qbx و vSync و Renewed)
-- وأي سكربت ثاني فيه فحص خفيف يرجع المطر بس لو الجو فعلاً تغير
-- الوقت ما نلمسه أبد، يبقى متزامن مع السيرفر

local WEATHER = Config.Weather
local weatherHash = joaat(WEATHER)
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

-- نخلي سكربت الطقس يطبق المطر والبرق
local function redirect()
    send('qb-weathersync:client:SyncWeather', WEATHER, false)
    send('vSync:updateWeather', WEATHER, false)
    LocalPlayer.state:set('syncWeather', false, false) -- Renewed-Weathersync
end

-- لو السيرفر أرسل طقس ثاني نرجعه مطر عن طريق سكربت الطقس نفسه
for _, event in ipairs({ 'qb-weathersync:client:SyncWeather', 'vSync:updateWeather' }) do
    RegisterNetEvent(event, function(weather)
        if echo or paused or weather == WEATHER then return end
        SetTimeout(0, function()
            if not paused then redirect() end
        end)
    end)
end

local function applyStorm(force)
    if force or GetPrevWeatherTypeHashName() ~= weatherHash or GetNextWeatherTypeHashName() ~= weatherHash then
        SetWeatherTypeNowPersist(WEATHER)
        SetOverrideWeather(WEATHER)
    end
    SetRainLevel(Config.RainLevel)
end

local function stopStorm()
    ClearOverrideWeather()
    ClearWeatherTypePersist()
    SetRainLevel(-1.0)
    LocalPlayer.state:set('syncWeather', true, false)
    TriggerServerEvent('qb-weathersync:server:RequestStateSync')
    TriggerServerEvent('vSync:requestSync')
end

CreateThread(function()
    Wait(1000)
    redirect()
    applyStorm(true)

    -- فحص خفيف كل ربع ثانية: يرجع المطر بس لو الجو تغير
    while true do
        local pause = shouldPause() and true or false
        if pause ~= paused then
            paused = pause
            if paused then
                stopStorm()
            else
                redirect()
                applyStorm(true)
            end
        end
        if not paused then applyStorm(false) end
        Wait(250)
    end
end)

-- برق زيادة بين فترة وفترة (يطلع عند كل لاعب لحاله، بدون أي ضرر)
CreateThread(function()
    if not Config.ExtraLightning then return end
    local range = Config.LightningEvery
    while true do
        Wait(math.random(range[1], range[2]) * 1000)
        if not paused then
            ForceLightningFlash()
            -- أحياناً برقتين ورا بعض
            if math.random() < 0.35 then
                Wait(math.random(150, 400))
                ForceLightningFlash()
            end
        end
    end
end)

-- لسكربتات ثانية: exports.always_storm:Pause(true / false)
exports('Pause', function(on) manualPause = on and true or false end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then stopStorm() end
end)
