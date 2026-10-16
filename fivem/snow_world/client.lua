-- الثلج يطلع بس عند اللاعبين اللي داخل العالم الثلجي
-- اللاعبين العاديين يكملون بجوهم الطبيعي وما يشوفون أي شي

local inSnow = false
local version = 0          -- يمنع التداخل لو انتقل اللاعب ورجع بسرعة
local weatherHash = joaat(Config.Weather)

-- نستخدم الشات لأن خط اللعبة ما يدعم العربي
local function notify(text)
    TriggerEvent('chat:addMessage', { args = { 'snow_world', text } })
end

-- نوقف سكربتات مزامنة الطقس المشهورة عند هذا اللاعب بس، عشان ما يصير تعارض
-- (لو السكربت مو موجود عندك ما يصير شي)
local function setWeatherSync(enabled)
    if enabled then
        TriggerEvent('qb-weathersync:client:EnableSync')
    else
        TriggerEvent('qb-weathersync:client:DisableSync')
    end
    TriggerEvent('cd_easytime:PauseSync', not enabled)
    LocalPlayer.state:set('syncWeather', enabled, false) -- Renewed-Weathersync
end

local function applySnow(force)
    -- نغير الطقس بس لو تغير، عشان ما يرمش الجو ولا يثقل
    if force or GetPrevWeatherTypeHashName() ~= weatherHash or GetNextWeatherTypeHashName() ~= weatherHash then
        ClearWeatherTypePersist()
        SetWeatherTypeOvertimePersist(Config.Weather, 0.0)
        SetWeatherTypeNowPersist(Config.Weather)
        SetOverrideWeather(Config.Weather)
    end
    ForceSnowPass(true)
    if Config.FootTracks then
        SetForcePedFootstepsTracks(true)
        SetForceVehicleTrails(true)
    end
end

local function clearSnow()
    ClearOverrideWeather()
    ClearWeatherTypePersist()
    ForceSnowPass(false)
    SetForcePedFootstepsTracks(false)
    SetForceVehicleTrails(false)
    if Config.Timecycle then ClearTimecycleModifier() end
    ReleaseNamedScriptAudioBank('ICE_FOOTSTEPS')
    ReleaseNamedScriptAudioBank('SNOW_FOOTSTEPS')
end

local function enterSnow(v)
    DoScreenFadeOut(800)
    Wait(900)
    if v ~= version then return end

    setWeatherSync(false)
    RequestScriptAudioBank('ICE_FOOTSTEPS', false)
    RequestScriptAudioBank('SNOW_FOOTSTEPS', false)
    applySnow(true)
    if Config.Timecycle then
        SetTimecycleModifier(Config.Timecycle)
        SetTimecycleModifierStrength(Config.TimecycleStrength)
    end

    -- فحص خفيف كل 5 ثواني: لو سكربت ثاني غير الطقس نرجعه ثلج
    CreateThread(function()
        while inSnow and v == version do
            Wait(5000)
            if inSnow and v == version then applySnow(false) end
        end
    end)

    Wait(1000)
    DoScreenFadeIn(1500)
    notify(Config.EnterText)
end

local function leaveSnow(v)
    DoScreenFadeOut(800)
    Wait(900)
    if v ~= version then return end

    clearSnow()
    setWeatherSync(true)

    Wait(800)
    DoScreenFadeIn(1500)
    notify(Config.LeaveText)
end

local function setSnow(on)
    if on == inSnow then return end
    inSnow = on
    version = version + 1
    local v = version
    CreateThread(function()
        if on then enterSnow(v) else leaveSnow(v) end
    end)
end

AddStateBagChangeHandler('snowWorld', ('player:%d'):format(GetPlayerServerId(PlayerId())), function(_, _, value)
    setSnow(value == true)
end)

-- لو السكربت اشتغل واللاعب أصلاً داخل العالم الثلجي (مثلاً بعد restart)
CreateThread(function()
    Wait(1000)
    if LocalPlayer.state.snowWorld then setSnow(true) end

    local c = Config.Commands
    TriggerEvent('chat:addSuggestion', '/' .. c.enter, 'ينقل لاعب للعالم الثلجي', { { name = 'آيدي', help = 'آيدي اللاعب (فاضي = انت)' } })
    TriggerEvent('chat:addSuggestion', '/' .. c.leave, 'يرجع لاعب للعالم العادي', { { name = 'آيدي', help = 'آيدي اللاعب (فاضي = انت)' } })
    TriggerEvent('chat:addSuggestion', '/' .. c.list, 'مين داخل العالم الثلجي')
    TriggerEvent('chat:addSuggestion', '/' .. c.leaveAll, 'يرجع الكل للعالم العادي')
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() or not inSnow then return end
    inSnow = false
    version = version + 1
    clearSnow()
    setWeatherSync(true)
    DoScreenFadeIn(0)
end)
