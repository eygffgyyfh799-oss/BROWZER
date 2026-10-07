local curVeh, curPlate, curNet = 0, nil, nil
local uiOpen, lastCanControl = false, nil
local sessions = {} -- [plate] = { netId = , state = } كل السيارات الشغالة بالسيرفر
local lastMix = ''

local function trim(s) return (s:gsub('^%s*(.-)%s*$', '%1')) end
local function notify(msg) Config.Notify(msg) end

local function loadStore(key, default)
    local raw = GetResourceKvpString('carplay_' .. key)
    local ok, data = pcall(json.decode, raw or '')
    return (ok and type(data) == 'table') and data or default
end

local function canControl()
    if curVeh == 0 then return false end
    if not Config.DriverOnly then return true end
    return GetPedInVehicleSeat(curVeh, -1) == PlayerPedId()
end

local function closeUI()
    if not uiOpen then return end
    uiOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

local function openUI()
    if curVeh == 0 then return notify(Config.Locale.not_in_vehicle) end
    uiOpen = true
    lastCanControl = canControl()
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'open', canControl = lastCanControl })
end

local function vehicleAllowed(veh)
    if not NetworkGetEntityIsNetworked(veh) then return false end
    return not Config.BlacklistedClasses[GetVehicleClass(veh)]
end

local function onEnter(veh)
    curVeh = veh
    curPlate = trim(GetVehicleNumberPlateText(veh))
    curNet = NetworkGetNetworkIdFromEntity(veh)
    SendNUIMessage({ action = 'focus', plate = curPlate })
    TriggerServerEvent('carplay:enter', curNet, curPlate)
end

local function onExit()
    -- الأغنية ما توقف: تظل تنسمع 3D من برا السيارة حسب بعدك عنها
    SendNUIMessage({ action = 'focus', plate = nil })
    TriggerServerEvent('carplay:exit', curNet, curPlate)
    closeUI()
    curVeh, curPlate, curNet = 0, nil, nil
end

-- مراقبة الركوب والنزول
CreateThread(function()
    while true do
        local veh = GetVehiclePedIsIn(PlayerPedId(), false)
        if veh ~= curVeh then
            if curVeh ~= 0 then onExit() end
            if veh ~= 0 and vehicleAllowed(veh) then onEnter(veh) end
        elseif uiOpen then
            -- لو تغير مقعدك (سائق / راكب) والواجهة مفتوحة
            local cc = canControl()
            if cc ~= lastCanControl then
                lastCanControl = cc
                SendNUIMessage({ action = 'perm', canControl = cc })
            end
        end
        Wait(500)
    end
end)

-- ===== الصوت ثلاثي الأبعاد =====
local S = Config.Sound

-- هل صوت السيارة يطلع برا؟ (باب / شنطة / كبوت مفتوح، شباك نازل أو مكسور، سقف مكشوف، دباب)
local function cabinOpen(veh)
    if IsThisModelABike(GetEntityModel(veh)) or IsThisModelAQuadbike(GetEntityModel(veh)) then return true end
    if IsVehicleAConvertible(veh, false) and GetConvertibleRoofState(veh) ~= 0 then return true end
    for i = 0, 5 do
        if GetIsDoorValid(veh, i) and GetVehicleDoorAngleRatio(veh, i) > 0.05 then return true end
    end
    for i = 0, 3 do
        if not IsVehicleWindowIntact(veh, i) then return true end
    end
    return false
end

local function boostOf(state)
    return Config.BoostLevels[state.boost or 1] or 1.0
end

-- قوة الصوت عندك (0 - 1) لسيارة معينة
local function gainFor(veh, state, ped, pcoords, myVeh)
    if veh == myVeh then return 1.0, 0.0 end -- داخل نفس السيارة: الصوت كامل
    if not S.Enabled3D then return 0.0 end

    local d = #(pcoords - GetEntityCoords(veh))
    local range = S.Range * boostOf(state)
    if d >= range then return 0.0 end

    local g = (1.0 - d / range) ^ S.Rolloff
    if not cabinOpen(veh) then g = g * S.ClosedCabin end
    if myVeh ~= 0 then g = g * S.OtherVehicle end
    if d > 4.0 and not HasEntityClearLosToEntity(ped, veh, 17) then g = g * S.Occlusion end
    return g, d
end

CreateThread(function()
    while true do
        Wait(S.UpdateMs)
        local ped = PlayerPedId()
        local pcoords = GetEntityCoords(ped)
        local myVeh = GetVehiclePedIsIn(ped, false)
        local list = {}

        for plate, s in pairs(sessions) do
            local st = s.state
            if st and st.playing and s.netId and NetworkDoesEntityExistWithNetworkId(s.netId) then
                local veh = NetworkGetEntityFromNetworkId(s.netId)
                if veh ~= 0 and DoesEntityExist(veh) then
                    local g, d = gainFor(veh, st, ped, pcoords, myVeh)
                    if g > 0.005 then list[#list + 1] = { plate = plate, g = g, d = d } end
                end
            end
        end

        -- نخلي بس أقرب السيارات عشان الأداء
        table.sort(list, function(a, b) return a.d < b.d end)
        local mix = {}
        for i = 1, math.min(#list, S.MaxStreams) do
            mix[list[i].plate] = math.floor(list[i].g * 1000 + 0.5) / 1000
        end

        local enc = json.encode(mix)
        if enc ~= lastMix then
            lastMix = enc
            SendNUIMessage({ action = 'mix', mix = mix })
        end
    end
end)

RegisterNetEvent('carplay:sync', function(plate, netId, state)
    sessions[plate] = state and { netId = netId, state = state } or nil
    SendNUIMessage({ action = 'sync', plate = plate, state = state })
end)

RegisterNetEvent('carplay:syncAll', function(all)
    sessions = {}
    local states = {}
    for plate, s in pairs(all or {}) do
        sessions[plate] = s
        states[plate] = s.state
    end
    SendNUIMessage({ action = 'syncAll', states = states, focus = curPlate })
end)

RegisterNetEvent('carplay:notify', function(msg) notify(msg) end)

RegisterCommand(Config.Command, openUI, false)
if Config.DefaultKey ~= '' then
    RegisterKeyMapping(Config.Command, Config.Locale.open_key, 'keyboard', Config.DefaultKey)
end

-- ===== NUI =====
RegisterNUICallback('ready', function(_, cb)
    cb({
        fav = loadStore('fav', {}),
        hist = loadStore('hist', {}),
        settings = loadStore('settings', {}),
        cfg = { skip = Config.SkipSeconds, maxHist = Config.MaxHistory, boost = Config.BoostLevels, sound3d = Config.Sound.Enabled3D },
    })
    TriggerServerEvent('carplay:requestAll')
end)

RegisterNUICallback('close', function(_, cb) closeUI(); cb('ok') end)

RegisterNUICallback('play', function(d, cb)
    cb('ok')
    if curVeh == 0 then return notify(Config.Locale.not_in_vehicle) end
    if not canControl() then return notify(Config.Locale.driver_only) end
    TriggerServerEvent('carplay:play', curNet, curPlate, d.id, d.title, d.startAt)
end)

RegisterNUICallback('control', function(d, cb)
    cb('ok')
    if curVeh == 0 then return end
    if not canControl() then return notify(Config.Locale.driver_only) end
    TriggerServerEvent('carplay:control', curNet, curPlate, d.action, d.value)
end)

RegisterNUICallback('ended', function(d, cb)
    cb('ok')
    local s = d.plate and sessions[d.plate]
    if s then TriggerServerEvent('carplay:control', s.netId, d.plate, 'ended') end
end)

RegisterNUICallback('title', function(d, cb)
    cb('ok')
    if curPlate then TriggerServerEvent('carplay:title', curPlate, d.id, d.title, d.duration) end
end)

RegisterNUICallback('error', function(d, cb)
    cb('ok')
    local code = tonumber(d.code)
    if code == 101 or code == 150 or code == 153 then
        notify(Config.Locale.embed_blocked)
    else
        notify(Config.Locale.video_error)
    end
end)

RegisterNUICallback('store', function(d, cb)
    if (d.key == 'fav' or d.key == 'hist' or d.key == 'settings') and type(d.data) == 'table' then
        SetResourceKvp('carplay_' .. d.key, json.encode(d.data))
    end
    cb('ok')
end)

RegisterNUICallback('notify', function(d, cb) notify(tostring(d.msg or '')); cb('ok') end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and uiOpen then SetNuiFocus(false, false) end
end)
