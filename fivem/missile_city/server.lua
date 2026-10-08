-- حالة المدينة محفوظة في GlobalState عشان اللاعبين اللي يدخلون بعدين يشوفونها محروقة
GlobalState.missileCity = false

-- /missile : يسقط الصاروخ على مكان اللاعب اللي كتب الأمر
RegisterCommand(Config.MissileCommand, function(source)
    if source == 0 then
        print('[missile_city] لازم تكتب الأمر من داخل اللعبة')
        return
    end

    local coords = GetEntityCoords(GetPlayerPed(source))
    GlobalState.missileCity = { x = coords.x, y = coords.y, z = coords.z, t = os.time() }
end, true)

-- /resetcity : يرجع المدينة طبيعية
RegisterCommand(Config.ResetCommand, function()
    GlobalState.missileCity = false
end, true)
