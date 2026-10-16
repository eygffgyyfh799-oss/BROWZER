-- الثلج يطلع بس عند اللاعبين اللي داخل العالم الثلجي
-- اللاعبين العاديين يكملون بجوهم الطبيعي وما يشوفون أي شي
--
-- طريقة منع التعارض مع سكربت الطقس:
-- ما نوقف سكربت الطقس (إيقافه في qb-weathersync يجبر جو صافي والساعة 11 بالليل)
-- بدال كذا نخلي سكربت الطقس نفسه يطبق الثلج عند هذا اللاعب، فما يصير بينهم قتال ولا رمشة
-- والوقت ما نلمسه أبد، يبقى متزامن مع السيرفر مثل باقي اللاعبين

local inSnow = false
local version = 0          -- يمنع التداخل لو انتقل اللاعب ورجع بسرعة
local SNOW = Config.Weather
local snowHash = joaat(SNOW)

-- آخر طقس حقيقي وصل من سكربت الطقس، عشان نرجعه لما يطلع اللاعب
local real = {}

-- نستخدم الشات لأن خط اللعبة ما يدعم العربي
local function notify(text)
    TriggerEvent('chat:addMessage', { args = { 'snow_world', text } })
end

-- ===================== سكربتات الطقس المشهورة =====================

-- qb-weathersync / qbx_weathersync
RegisterNetEvent('qb-weathersync:client:SyncWeather', function(weather, blackout)
    if weather == SNOW and inSnow then return end
    real.qb = { weather, blackout }
    if inSnow then
        -- سكربت الطقس حاول يغير الجو، نرجعه ثلج عن طريقه هو
        SetTimeout(0, function()
            if inSnow then TriggerEvent('qb-weathersync:client:SyncWeather', SNOW, false) end
        end)
    end
end)

-- vSync
RegisterNetEvent('vSync:updateWeather', function(weather, blackout)
    if weather == SNOW and inSnow then return end
    real.vsync = { weather, blackout }
    if inSnow then
        SetTimeout(0, function()
            if inSnow then TriggerEvent('vSync:updateWeather', SNOW, false) end
        end)
    end
end)

local function redirectWeather(toSnow)
    if toSnow then
        TriggerEvent('qb-weathersync:client:SyncWeather', SNOW, false)
        TriggerEvent('vSync:updateWeather', SNOW, false)
        LocalPlayer.state:set('syncWeather', false, false) -- Renewed-Weathersync
    else
        -- نرجع آخر طقس حقيقي فوراً، ونطلب من السيرفر يزامن الطقس والوقت من جديد
        if real.qb then TriggerEvent('qb-weathersync:client:SyncWeather', real.qb[1], real.qb[2]) end
        if real.vsync then TriggerEvent('vSync:updateWeather', real.vsync[1], real.vsync[2]) end
        TriggerServerEvent('qb-weathersync:server:RequestStateSync')
        TriggerServerEvent('vSync:requestSync')
        LocalPlayer.state:set('syncWeather', true, false)
    end
end

-- ===================== الثلج =====================

local function applySnow(force)
    -- نغير الطقس بس لو فعلاً تغير، عشان ما يرمش الجو ولا يثقل
    if force or GetPrevWeatherTypeHashName() ~= snowHash or GetNextWeatherTypeHashName() ~= snowHash then
        SetWeatherTypeNowPersist(SNOW)
        SetOverrideWeather(SNOW)
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

    redirectWeather(true)
    RequestScriptAudioBank('ICE_FOOTSTEPS', false)
    RequestScriptAudioBank('SNOW_FOOTSTEPS', false)
    applySnow(true)
    if Config.Timecycle then
        SetTimecycleModifier(Config.Timecycle)
        SetTimecycleModifierStrength(Config.TimecycleStrength)
    end

    -- حماية لأي سكربت طقس ثاني مو معروف: فحص خفيف ونرجع الثلج بس لو انغير
    CreateThread(function()
        while inSnow and v == version do
            applySnow(false)
            Wait(250)
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
    redirectWeather(false)

    Wait(1000)
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
    redirectWeather(false)
    DoScreenFadeIn(0)
end)

-- للسكربتات الثانية في الكلاينت: exports.snow_world:IsInSnowWorld()
exports('IsInSnowWorld', function() return inSnow end)
