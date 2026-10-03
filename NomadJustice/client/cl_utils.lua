-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- Shared client helpers (loaded first)
-- ════════════════════════════════════════════════════════════════════════════════════════════════

JC = {}
JC.Config = LoadConfig()
JC.Coords = LoadCoords()
JC.Settings = JC.Config.Settings
JC.Job = JC.Settings.Job

local LibTypes = { primary = 'inform', success = 'success', error = 'error', inform = 'inform', warning = 'warning' }

-- Notification: uses the core notification, falls back to ox_lib
function JC.Notify(msg, msgType, length)
    msgType, length = msgType or 'primary', length or 5000
    local ok = pcall(QBCore.Functions.Notify, msg, msgType, length)
    if not ok then
        pcall(lib.notify, { description = msg, type = LibTypes[msgType] or 'inform', duration = length })
    end
end

-- Fallback: if the server-side core notification fails, the server sends it here
RegisterNetEvent('NomadJustice:client:notify', function(msg, msgType, length)
    if type(msg) == 'string' then JC.Notify(msg, msgType, length) end
end)

-- Owner citizen IDs keep full access whatever their job (the server makes the real decision)
function JC.IsOwner()
    local cid = QBCore.Functions.GetPlayerData().citizenid
    if not cid then return false end
    for _, owner in ipairs(JC.Settings.Panel.OwnerCitizenIds or {}) do
        if tostring(owner) == cid then return true end
    end
    return false
end

function JC.IsJustice()
    if JC.IsOwner() then return true end
    local job = QBCore.Functions.GetPlayerData().job
    return job ~= nil and job.name == JC.Job
end

function JC.IsBoss()
    if JC.IsOwner() then return true end
    local job = QBCore.Functions.GetPlayerData().job
    if not job or job.name ~= JC.Job then return false end
    if job.isboss == true then return true end
    local grade = type(job.grade) == 'table' and job.grade.level or job.grade
    local fullAccess = tonumber(JC.Settings.Panel.FullAccessGrade)
    return fullAccess ~= nil and (tonumber(grade) or 0) >= fullAccess
end

-- Full access grade (Chief Justice / Supreme Court Justice) - display only, the server decides
function JC.HasFullAccess()
    if JC.IsOwner() then return true end
    local job = QBCore.Functions.GetPlayerData().job
    if not job or job.name ~= JC.Job then return false end
    local grade = type(job.grade) == 'table' and job.grade.level or job.grade
    local fullAccess = tonumber(JC.Settings.Panel.FullAccessGrade)
    return fullAccess ~= nil and (tonumber(grade) or 0) >= fullAccess
end

-- Expected role from player data (the server makes the real decision)
function JC.GuessRole()
    local pd = QBCore.Functions.GetPlayerData()
    local job = pd.job or {}
    if job.name == JC.Job or JC.IsOwner() then return 'justice' end
    for _, name in ipairs(JC.Settings.Police.Jobs or {}) do
        if job.name == name then return 'police' end
    end
    local md = pd.metadata or {}
    local licenses = md.licences or md.licenses or {}
    if licenses[JC.Settings.Lawyers.License] == true then return 'lawyer' end
    for _, name in ipairs(JC.Settings.Lawyers.Jobs or {}) do
        if job.name == name then return 'lawyer' end
    end
    local sector = (JC.Settings.Finance.Sectors or {})[job.name]
    if sector then
        local grade = tonumber(type(job.grade) == 'table' and job.grade.level or job.grade) or -1
        for _, level in ipairs(sector.managers or {}) do
            if tonumber(level) == grade then return 'sector' end
        end
    end
    return nil
end

-- Waits for a server callback result (max 10 seconds so menus never hang)
function JC.Await(name, ...)
    local p = promise.new()
    local finished = false
    QBCore.Functions.TriggerCallback(name, function(result)
        if finished then return end
        finished = true
        p:resolve(result)
    end, ...)
    SetTimeout(10000, function()
        if finished then return end
        finished = true
        p:resolve(nil)
    end)
    return Citizen.Await(p)
end

-- Like Await but: blocks double clicks, shows the error automatically and returns nil on failure
local inFlight = {}

function JC.Call(name, ...)
    if inFlight[name] then return nil end
    inFlight[name] = true
    local ok, result = pcall(JC.Await, name, ...)
    inFlight[name] = nil

    if not ok then
        print(('^1[NomadJustice] %s: %s^7'):format(name, tostring(result)))
        JC.Notify('An unexpected error occurred, try again', 'error')
        return nil
    end
    if type(result) ~= 'table' then
        JC.Notify('The server did not respond, try again', 'error')
        return nil
    end
    if result.ok == false then
        JC.Notify(result.err or 'Something went wrong', 'error')
        return nil
    end
    return result
end

function JC.Money(value)
    local number = math.floor(tonumber(value) or 0)
    local formatted = tostring(math.abs(number)):reverse():gsub('(%d%d%d)', '%1,'):reverse():gsub('^,', '')
    return (number < 0 and '-$' or '$') .. formatted
end

function JC.Gender(value)
    if tonumber(value) == 0 then return 'Male' end
    if tonumber(value) == 1 then return 'Female' end
    return '-'
end

function JC.Value(value)
    if value == nil or value == '' then return '-' end
    return tostring(value)
end

function JC.Utf8Len(str)
    return utf8.len(str) or #str
end

-- Street and area name from coordinates
function JC.GetStreet(coords)
    if not coords then return 'Unknown' end
    local streetHash, crossingHash = GetStreetNameAtCoord(coords.x, coords.y, coords.z)
    local street = GetStreetNameFromHashKey(streetHash)
    local crossing = crossingHash ~= 0 and GetStreetNameFromHashKey(crossingHash) or nil
    local zone = GetLabelText(GetNameOfZone(coords.x, coords.y, coords.z))
    local text = street
    if crossing and crossing ~= '' then text = text .. ' / ' .. crossing end
    if zone and zone ~= '' and zone ~= 'NULL' then text = text .. ' - ' .. zone end
    return text
end

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- Place a temporary map blip
-- ════════════════════════════════════════════════════════════════════════════════════════════════

local tempBlips = {}

function JC.TempBlip(coords, label, seconds, sprite, colour)
    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, sprite or 280)
    SetBlipColour(blip, colour or 1)
    SetBlipScale(blip, 0.9)
    SetBlipFlashes(blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(label)
    EndTextCommandSetBlipName(blip)
    SetNewWaypoint(coords.x, coords.y)
    tempBlips[blip] = true

    SetTimeout((seconds or 60) * 1000, function()
        if DoesBlipExist(blip) then RemoveBlip(blip) end
        tempBlips[blip] = nil
    end)
end

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for blip in pairs(tempBlips) do
        if DoesBlipExist(blip) then RemoveBlip(blip) end
    end
end)
