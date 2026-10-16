-- من جهة السيرفر: لو عندك qb-weathersync أو qbx_weathersync نخليه هو يثبت المطر والبرق للسيرفر كله
-- (يوقف تغيير الطقس التلقائي ويحط المطر والبرق)، ونعيدها كل 10 دقايق احتياط

local function lockWeather()
    for _, res in ipairs({ 'qb-weathersync', 'qbx_weathersync' }) do
        if GetResourceState(res) == 'started' then
            pcall(function() exports[res]:setDynamicWeather(false) end)
            pcall(function() exports[res]:setWeather(Config.Weather) end)
        end
    end
end

CreateThread(function()
    Wait(5000)
    while true do
        lockWeather()
        Wait(10 * 60 * 1000)
    end
end)

-- لو سكربت الطقس انعاد تشغيله نثبت المطر من جديد
AddEventHandler('onResourceStart', function(res)
    if res == 'qb-weathersync' or res == 'qbx_weathersync' then
        SetTimeout(3000, lockWeather)
    end
end)
