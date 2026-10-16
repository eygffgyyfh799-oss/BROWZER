-- الثلج يطلع بس عند اللاعبين اللي داخل العالم الثلجي
-- اللاعبين العاديين يكملون بجوهم الطبيعي وما يشوفون أي شي

local inSnow = false

-- نستخدم الشات لأن خط اللعبة ما يدعم العربي
local function notify(text)
    TriggerEvent('chat:addMessage', { args = { 'snow_world', text } })
end

local function applySnow()
    SetOverrideWeather(Config.Weather)
    SetWeatherTypeNowPersist(Config.Weather)
    ForceSnowPass(true)
    if Config.FootTracks then
        SetForcePedFootstepsTracks(true)
        SetForceVehicleTrails(true)
    end
end

local function enterSnow()
    inSnow = true
    DoScreenFadeOut(800)
    Wait(900)

    RequestScriptAudioBank('ICE_FOOTSTEPS', false)
    RequestScriptAudioBank('SNOW_FOOTSTEPS', false)
    RequestNamedPtfxAsset('core_snow')
    applySnow()
    if Config.Timecycle then
        SetTimecycleModifier(Config.Timecycle)
        SetTimecycleModifierStrength(Config.TimecycleStrength)
    end

    -- نعيد تطبيق الثلج باستمرار عشان سكربتات مزامنة الطقس ما تلغيه
    CreateThread(function()
        while inSnow do
            applySnow()
            Wait(3000)
        end
    end)

    Wait(1200)
    DoScreenFadeIn(1500)
    notify(Config.EnterText)
end

local function leaveSnow()
    inSnow = false
    DoScreenFadeOut(800)
    Wait(900)

    ClearOverrideWeather()
    ClearWeatherTypePersist()
    ForceSnowPass(false)
    SetForcePedFootstepsTracks(false)
    SetForceVehicleTrails(false)
    if Config.Timecycle then ClearTimecycleModifier() end
    ReleaseNamedScriptAudioBank('ICE_FOOTSTEPS')
    ReleaseNamedScriptAudioBank('SNOW_FOOTSTEPS')

    Wait(800)
    DoScreenFadeIn(1500)
    notify(Config.LeaveText)
end

AddStateBagChangeHandler('snowWorld', ('player:%d'):format(GetPlayerServerId(PlayerId())), function(_, _, value)
    if value and not inSnow then
        CreateThread(enterSnow)
    elseif not value and inSnow then
        CreateThread(leaveSnow)
    end
end)

CreateThread(function()
    local c = Config.Commands
    TriggerEvent('chat:addSuggestion', '/' .. c.enter, 'ينقل لاعب للعالم الثلجي', { { name = 'آيدي', help = 'آيدي اللاعب (فاضي = انت)' } })
    TriggerEvent('chat:addSuggestion', '/' .. c.leave, 'يرجع لاعب للعالم العادي', { { name = 'آيدي', help = 'آيدي اللاعب (فاضي = انت)' } })
    TriggerEvent('chat:addSuggestion', '/' .. c.list, 'مين داخل العالم الثلجي')
    TriggerEvent('chat:addSuggestion', '/' .. c.leaveAll, 'يرجع الكل للعالم العادي')
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and inSnow then
        inSnow = false
        ClearOverrideWeather()
        ClearWeatherTypePersist()
        ForceSnowPass(false)
        SetForcePedFootstepsTracks(false)
        SetForceVehicleTrails(false)
        if Config.Timecycle then ClearTimecycleModifier() end
        DoScreenFadeIn(0)
    end
end)
