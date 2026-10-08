-- حالة المدينة محفوظة في GlobalState عشان اللاعبين اللي يدخلون بعدين يشوفونها محروقة
GlobalState.missileCity = false

-- /missile : يطيح الصواريخ على مكان اللاعب اللي كتب الأمر
RegisterCommand(Config.MissileCommand, function(source)
    if source == 0 then
        print('[missile_city] لازم تكتب الأمر من داخل اللعبة')
        return
    end

    local c = GetEntityCoords(GetPlayerPed(source))

    -- أماكن سقوط الصواريخ تنحسب في السيرفر عشان تكون نفسها عند كل اللاعبين
    local impacts = { { x = c.x, y = c.y } }
    for _ = 2, Config.MissileCount do
        local a = math.random() * 2 * math.pi
        local r = math.random() * Config.MissileSpread
        impacts[#impacts + 1] = { x = c.x + math.cos(a) * r, y = c.y + math.sin(a) * r }
    end

    GlobalState.missileCity = { x = c.x, y = c.y, z = c.z, seed = math.random(1, 1000000), impacts = impacts }
end, true)

-- /resetcity : يرجع المدينة طبيعية
RegisterCommand(Config.ResetCommand, function()
    GlobalState.missileCity = false
end, true)
