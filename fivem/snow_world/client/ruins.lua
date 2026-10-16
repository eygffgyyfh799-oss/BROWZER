-- المدينة الخربانة بشكل بسيط: سيارات محروقة، ركام، زبالة، دخان، ونار صغيرة
-- كل شي هنا محلي (CreateObject بدون مزامنة) فيطلع بس على شاشة هذا اللاعب وهو داخل العالم
-- ما ينشاف في العالم العادي ولا عند أي لاعب ثاني، وما يغير أي شي حقيقي في المدينة

local R = Config.Ruins
local cells = {}       -- [key] = { objects = {...}, fx = {...} }
local models = { wrecks = {}, debris = {} }
local session = 0

-- نستخدم بس الموديلات الموجودة فعلاً في اللعبة
for kind, list in pairs(R.Models) do
    for _, name in ipairs(list) do
        local hash = joaat(name)
        if IsModelInCdimage(hash) then models[kind][#models[kind] + 1] = hash end
    end
end

local function worldConfig()
    local key = LocalPlayer.state.world
    return key and Config.Worlds[key]
end

-- رقم عشوائي ثابت لكل مربع، عشان الخراب يطلع بنفس المكان كل مرة ترجع له
local function cellRng(ix, iy, salt)
    local state = (ix * 73856093 ~ iy * 19349663 ~ salt * 83492791) & 0x7fffffff
    return function(a, b)
        state = (state * 1103515245 + 12345) & 0x7fffffff
        return a + (state / 0x7fffffff) * (b - a)
    end
end

local function loadModel(hash)
    if HasModelLoaded(hash) then return true end
    RequestModel(hash)
    local timeout = GetGameTimer() + 3000
    while not HasModelLoaded(hash) and GetGameTimer() < timeout do Wait(0) end
    return HasModelLoaded(hash)
end

-- مكان على طرف الشارع داخل المربع
local function roadside(rnd, ix, iy)
    local cs = R.CellSize
    local x = (ix + rnd(0.1, 0.9)) * cs
    local y = (iy + rnd(0.1, 0.9)) * cs
    local pz = GetEntityCoords(PlayerPedId()).z
    local found, node, heading = GetClosestVehicleNodeWithHeading(x, y, pz, 1, 3.0, 0)
    if not found then return nil end
    -- لازم النقطة تكون داخل المربع تقريباً
    if math.abs(node.x - x) > cs or math.abs(node.y - y) > cs then return nil end
    local side = rnd(0, 1) < 0.5 and -1 or 1
    local h = math.rad(heading)
    local off = rnd(4.5, 7.0) * side
    return vector3(node.x + math.cos(h) * off, node.y + math.sin(h) * off, node.z), heading + rnd(-35, 35)
end

local function spawnObject(list, hash, pos, heading)
    if not loadModel(hash) then return end
    local obj = CreateObjectNoOffset(hash, pos.x, pos.y, pos.z, false, false, false)
    SetEntityHeading(obj, heading)
    PlaceObjectOnGroundProperly(obj)
    FreezeEntityPosition(obj, true)
    SetEntityCollision(obj, R.Collision, R.Collision)
    SetEntityAsMissionEntity(obj, true, true)
    SetModelAsNoLongerNeeded(hash)
    list[#list + 1] = obj
end

local function looped(list, asset, name, pos, scale)
    RequestNamedPtfxAsset(asset)
    local timeout = GetGameTimer() + 2000
    while not HasNamedPtfxAssetLoaded(asset) and GetGameTimer() < timeout do Wait(0) end
    UseParticleFxAssetNextCall(asset)
    list[#list + 1] = StartParticleFxLoopedAtCoord(name, pos.x, pos.y, pos.z, 0.0, 0.0, 0.0, scale, false, false, false, false)
end

local function spawnCell(ix, iy)
    local rnd = cellRng(ix, iy, 7)
    local cell = { objects = {}, fx = {} }

    if #models.wrecks > 0 then
        for _ = 1, math.floor(rnd(R.Wrecks[1], R.Wrecks[2] + 0.99)) do
            local pos, h = roadside(rnd, ix, iy)
            local hash = models.wrecks[math.floor(rnd(1, #models.wrecks + 0.99))]
            if pos then
                spawnObject(cell.objects, hash, pos, h)
                -- دخان خفيف من بعض السيارات المحروقة
                if rnd(0, 1) < 0.4 then looped(cell.fx, 'core', 'ent_amb_smoke_foundry', pos + vector3(0.0, 0.0, 0.5), 0.35) end
            end
        end
    end

    if #models.debris > 0 then
        for _ = 1, math.floor(rnd(R.Debris[1], R.Debris[2] + 0.99)) do
            local pos, h = roadside(rnd, ix, iy)
            local hash = models.debris[math.floor(rnd(1, #models.debris + 0.99))]
            if pos then spawnObject(cell.objects, hash, pos, h) end
        end
    end

    if rnd(0, 1) < R.SmokeChance then
        local pos = roadside(rnd, ix, iy)
        if pos then looped(cell.fx, 'core', 'ent_amb_smoke_foundry', pos, rnd(0.6, 1.2)) end
    end
    if rnd(0, 1) < R.FireChance then
        local pos = roadside(rnd, ix, iy)
        if pos then looped(cell.fx, 'core', 'fire_wrecked_plane_cockpit', pos, rnd(0.6, 1.0)) end
    end

    return cell
end

local function clearCell(cell)
    for _, obj in ipairs(cell.objects) do
        if DoesEntityExist(obj) then DeleteObject(obj) end
    end
    for _, fx in ipairs(cell.fx) do StopParticleFxLooped(fx, false) end
end

local function clearAll()
    for key, cell in pairs(cells) do
        clearCell(cell)
        cells[key] = nil
    end
end

-- يرسم الخراب حول اللاعب ويشيله لما يبعد
local function stream(sid)
    local cs = R.CellSize
    local reach = math.ceil(R.StreamDistance / cs)

    while session == sid do
        local p = GetEntityCoords(PlayerPedId())
        local p2 = vector2(p.x, p.y)
        local pcx, pcy = math.floor(p.x / cs), math.floor(p.y / cs)
        local wanted = {}

        for dx = -reach, reach do
            for dy = -reach, reach do
                local ix, iy = pcx + dx, pcy + dy
                if #(vector2((ix + 0.5) * cs, (iy + 0.5) * cs) - p2) <= R.StreamDistance then
                    local key = ix .. ':' .. iy
                    wanted[key] = true
                    if not cells[key] then
                        cells[key] = spawnCell(ix, iy)
                        Wait(0)
                        if session ~= sid then return end
                    end
                end
            end
        end

        for key, cell in pairs(cells) do
            if not wanted[key] then
                clearCell(cell)
                cells[key] = nil
            end
        end

        Wait(1500)
    end
end

-- سيارات NPC أقل في العالم الخربان (عند هذا اللاعب بس)
local function traffic(sid)
    while session == sid do
        SetVehicleDensityMultiplierThisFrame(R.TrafficMultiplier)
        SetRandomVehicleDensityMultiplierThisFrame(R.TrafficMultiplier)
        SetParkedVehicleDensityMultiplierThisFrame(R.TrafficMultiplier)
        Wait(0)
    end
end

local function refresh()
    session = session + 1
    clearAll()
    local w = worldConfig()
    if not (w and w.ruins) then return end
    local sid = session
    SetTimeout(1500, function()
        if session ~= sid then return end
        CreateThread(function() stream(sid) end)
        if R.TrafficMultiplier < 1.0 then CreateThread(function() traffic(sid) end) end
    end)
end

AddStateBagChangeHandler('world', ('player:%d'):format(GetPlayerServerId(PlayerId())), function()
    SetTimeout(0, refresh)
end)

CreateThread(function()
    Wait(2000)
    refresh()
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    session = session + 1
    clearAll()
end)
