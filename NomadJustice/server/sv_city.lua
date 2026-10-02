-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- City affairs: overview, economy, vehicle registry, property registry, licenses, gangs,
-- court summonses, announcements
-- ════════════════════════════════════════════════════════════════════════════════════════════════

local Settings = JS.Settings
local City = Settings.City
local DB = Settings.Database
local Notify = JS.Notify

local VehicleStates = { [0] = 'Out of garage', [1] = 'In garage', [2] = 'Impounded' }
local SummonStatus = { pending = 'Not delivered yet', delivered = 'Served', attended = 'Appeared', absent = 'Failed to appear', cancelled = 'Cancelled' }

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- Helpers
-- ════════════════════════════════════════════════════════════════════════════════════════════════

local function Placeholders(count)
    return ('?,'):rep(count):sub(1, -2)
end

local function Money(value)
    return math.floor(tonumber(value) or 0)
end

-- Names of a batch of citizens at once { [citizenid] = name }
local function GetNames(citizenids)
    local names, missing = {}, {}
    for _, cid in ipairs(citizenids) do
        local Player = QBCore.Functions.GetPlayerByCitizenId(cid)
        if Player then
            names[cid] = JS.PlayerName(Player)
        elseif not names[cid] then
            missing[#missing + 1] = cid
        end
    end
    if #missing > 0 and JS.TableExists(DB.Players) then
        local rows = MySQL.query.await(('SELECT citizenid, charinfo FROM `%s` WHERE citizenid IN (%s)'):format(DB.Players, Placeholders(#missing)), missing) or {}
        for _, row in ipairs(rows) do
            names[row.citizenid] = JS.FullName(JS.Decode(row.charinfo))
        end
    end
    return names
end

local function NormalizePlate(plate)
    if type(plate) ~= 'string' and type(plate) ~= 'number' then return nil end
    plate = tostring(plate):upper():gsub('^%s+', ''):gsub('%s+$', '')
    if plate == '' or #plate > 12 or not plate:match('^[%w%s%-]+$') then return nil end
    return plate
end

local function CleanPlate(text)
    return ((text or ''):upper():gsub('^%s+', ''):gsub('%s+$', ''))
end

-- Every plate on the street right now in one pass { [plate] = entity } (faster than searching per vehicle)
local function WorldPlates()
    local plates = {}
    for _, vehicle in ipairs(GetAllVehicles()) do
        if DoesEntityExist(vehicle) then
            plates[CleanPlate(GetVehicleNumberPlateText(vehicle))] = vehicle
        end
    end
    return plates
end

-- Is the vehicle in the world right now?
local function FindWorldVehicle(plate)
    for _, vehicle in ipairs(GetAllVehicles()) do
        if DoesEntityExist(vehicle) then
            local vehPlate = (GetVehicleNumberPlateText(vehicle) or ''):upper():gsub('^%s+', ''):gsub('%s+$', '')
            if vehPlate == plate then return vehicle end
        end
    end
end

local function VehiclesReady()
    return DB.Vehicles and JS.TableExists(DB.Vehicles) and JS.ColumnExists(DB.Vehicles, 'plate') and JS.ColumnExists(DB.Vehicles, 'citizenid')
end

local function HousesReady()
    local h = DB.Houses
    return h and JS.TableExists(h.table) and JS.ColumnExists(h.table, h.owner) and JS.ColumnExists(h.table, h.id)
end

local function MapVehicle(row, names, worldPlates)
    local shared = QBCore.Shared.Vehicles and QBCore.Shared.Vehicles[row.vehicle]
    local label = shared and (('%s %s'):format(shared.brand or '', shared.name or row.vehicle):gsub('^%s+', '')) or row.vehicle
    local plate = (row.plate or ''):upper():gsub('^%s+', ''):gsub('%s+$', '')
    return {
        plate = plate,
        label = JS.Safe(label or 'Unknown'),
        model = row.vehicle,
        owner = row.citizenid,
        ownerName = names and names[row.citizenid] or nil,
        ownerStatus = JS.GetStatus(row.citizenid).text,
        garage = row.garage,
        stateCode = tonumber(row.state),
        state = VehicleStates[tonumber(row.state)] or tostring(row.state or '-'),
        depotprice = tonumber(row.depotprice),
        inWorld = (worldPlates and worldPlates[plate] or FindWorldVehicle(plate)) ~= nil,
    }
end

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- City overview + economy
-- ════════════════════════════════════════════════════════════════════════════════════════════════

local function GetEconomy()
    if not JS.TableExists(DB.Players) then return nil end

    local bankExpr = "CAST(COALESCE(JSON_UNQUOTE(JSON_EXTRACT(money, '$.bank')), '0') AS DECIMAL(20,0))"
    local cashExpr = "CAST(COALESCE(JSON_UNQUOTE(JSON_EXTRACT(money, '$.cash')), '0') AS DECIMAL(20,0))"

    local totals = MySQL.single.await(('SELECT COALESCE(SUM(%s), 0) AS bank, COALESCE(SUM(%s), 0) AS cash FROM `%s`'):format(bankExpr, cashExpr, DB.Players)) or {}
    local totalBank, totalCash = Money(totals.bank), Money(totals.cash)

    local candidates = {}
    for _, row in ipairs(MySQL.query.await(('SELECT citizenid, charinfo, %s AS bank, %s AS cash FROM `%s` ORDER BY bank DESC LIMIT 15'):format(bankExpr, cashExpr, DB.Players)) or {}) do
        candidates[row.citizenid] = { citizenid = row.citizenid, name = JS.FullName(JS.Decode(row.charinfo)), bank = Money(row.bank), cash = Money(row.cash) }
    end

    -- Live values for online players (the database only updates every few minutes)
    local online = {}
    for _, playerId in pairs(QBCore.Functions.GetPlayers()) do
        local Player = QBCore.Functions.GetPlayer(playerId)
        if Player then online[#online + 1] = Player end
    end

    if #online > 0 then
        local ids = {}
        for i, Player in ipairs(online) do ids[i] = Player.PlayerData.citizenid end
        local stored = {}
        for _, row in ipairs(MySQL.query.await(('SELECT citizenid, money FROM `%s` WHERE citizenid IN (%s)'):format(DB.Players, Placeholders(#ids)), ids) or {}) do
            stored[row.citizenid] = JS.Decode(row.money)
        end

        for _, Player in ipairs(online) do
            local pd = Player.PlayerData
            local liveBank, liveCash = Money(pd.money.bank), Money(pd.money.cash)
            local old = stored[pd.citizenid] or {}
            totalBank = totalBank + liveBank - Money(old.bank)
            totalCash = totalCash + liveCash - Money(old.cash)
            candidates[pd.citizenid] = { citizenid = pd.citizenid, name = JS.PlayerName(Player), bank = liveBank, cash = liveCash }
        end
    end

    local richest = {}
    for _, entry in pairs(candidates) do richest[#richest + 1] = entry end
    table.sort(richest, function(a, b) return (a.bank + a.cash) > (b.bank + b.cash) end)
    for i = #richest, 11, -1 do richest[i] = nil end
    for _, entry in ipairs(richest) do entry.status = JS.GetStatus(entry.citizenid) end

    return { bank = totalBank, cash = totalCash, total = totalBank + totalCash, richest = richest }
end

JS.RegisterCallback('NomadJustice:server:getCityOverview', 'city', function(src, Player)
    local perms = JS.GetPermissions(Player)
    local overview = { online = #QBCore.Functions.GetPlayers() }

    if JS.TableExists(DB.Players) then
        overview.citizens = tonumber(MySQL.scalar.await(('SELECT COUNT(*) FROM `%s`'):format(DB.Players))) or 0
    end

    if VehiclesReady() then
        local query = JS.ColumnExists(DB.Vehicles, 'state')
            and 'SELECT COUNT(*) AS total, SUM(state = 2) AS impounded, SUM(state = 0) AS outside FROM `%s`'
            or 'SELECT COUNT(*) AS total FROM `%s`'
        local counts = MySQL.single.await(query:format(DB.Vehicles)) or {}
        overview.vehicles = { total = tonumber(counts.total) or 0, impounded = tonumber(counts.impounded) or 0, outside = tonumber(counts.outside) or 0 }
    end

    if HousesReady() then
        overview.houses = tonumber(MySQL.scalar.await(('SELECT COUNT(*) FROM `%s`'):format(DB.Houses.table))) or 0
    end

    -- Departments on duty
    local duty = {}
    for _, playerId in pairs(QBCore.Functions.GetPlayers()) do
        local target = QBCore.Functions.GetPlayer(playerId)
        local job = target and target.PlayerData.job
        if job and job.onduty and job.name ~= Settings.Panel.UnemployedJob then
            duty[job.name] = duty[job.name] or { label = JS.Safe(job.label or job.name), count = 0 }
            duty[job.name].count = duty[job.name].count + 1
        end
    end
    overview.duty = {}
    for _, entry in pairs(duty) do overview.duty[#overview.duty + 1] = entry end
    table.sort(overview.duty, function(a, b) return a.count > b.count end)

    overview.pendingSummons = tonumber(MySQL.scalar.await("SELECT COUNT(*) FROM justice_summons WHERE status IN ('pending', 'delivered')")) or 0
    local suspended = 0
    for _ in pairs(JS.Suspended) do suspended = suspended + 1 end
    overview.suspended = suspended

    if perms.economy then
        overview.economy = GetEconomy()
        if overview.economy and JS.GetSectorBalances then overview.economy.sectors = JS.GetSectorBalances() end
    end

    return { ok = true, overview = overview, perms = perms }
end)

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- Vehicle registry
-- ════════════════════════════════════════════════════════════════════════════════════════════════

JS.RegisterCallback('NomadJustice:server:searchVehicles', 'city', function(src, Player, query)
    if not VehiclesReady() then return { ok = false, err = 'Vehicle table not found, check Settings.Database' } end

    query = JS.CleanText(query, 20, true)
    if not query or JS.Len(query) < 2 then return { ok = false, err = 'Type at least 2 characters of the plate or citizen ID' } end

    local like = '%' .. query:upper():gsub('[%%_\\]', '\\%0') .. '%'
    local rows = MySQL.query.await(('SELECT * FROM `%s` WHERE UPPER(plate) LIKE ? OR citizenid = ? LIMIT 30'):format(DB.Vehicles), { like, query }) or {}

    local ids = {}
    for i, row in ipairs(rows) do ids[i] = row.citizenid end
    local names = GetNames(ids)

    local list, worldPlates = {}, WorldPlates()
    for i, row in ipairs(rows) do list[i] = MapVehicle(row, names, worldPlates) end
    return { ok = true, vehicles = list, perms = JS.GetPermissions(Player) }
end)

JS.RegisterCallback('NomadJustice:server:getVehicle', 'city', function(src, Player, plate, locate)
    plate = NormalizePlate(plate)
    if not plate or not VehiclesReady() then return { ok = false, err = 'Invalid plate' } end

    local row = MySQL.single.await(('SELECT * FROM `%s` WHERE UPPER(plate) = ? LIMIT 1'):format(DB.Vehicles), { plate })
    if not row then return { ok = false, err = 'No vehicle registered with this plate' } end

    local perms = JS.GetPermissions(Player)
    local vehicle = MapVehicle(row, GetNames({ row.citizenid }))

    -- Vehicle location if it is on the street (for those allowed to locate)
    if locate == true and perms.locate and vehicle.inWorld then
        local entity = FindWorldVehicle(plate)
        if entity then
            local c = GetEntityCoords(entity)
            vehicle.coords = { x = c.x, y = c.y, z = c.z }
            JS.Log(Player, 'locate', row.citizenid, vehicle.ownerName, { ['Vehicle'] = plate })
        end
    end

    return { ok = true, vehicle = vehicle, perms = perms }
end)

-- action: 'impound' | 'release' | 'transfer'
JS.RegisterCallback('NomadJustice:server:vehicleAction', 'vehicles', function(src, Player, plate, action, extra)
    plate = NormalizePlate(plate)
    if not plate or not VehiclesReady() then return { ok = false, err = 'Invalid plate' } end

    local row = MySQL.single.await(('SELECT * FROM `%s` WHERE UPPER(plate) = ? LIMIT 1'):format(DB.Vehicles), { plate })
    if not row then return { ok = false, err = 'No vehicle registered with this plate' } end

    local ownerName = GetNames({ row.citizenid })[row.citizenid]
    local details = { ['Plate'] = plate, ['Model'] = row.vehicle }

    if action == 'impound' then
        local sets, params = { 'state = ?' }, { 2 }
        if JS.ColumnExists(DB.Vehicles, 'garage') then sets[#sets + 1] = 'garage = ?' params[#params + 1] = City.ImpoundGarage end
        if JS.ColumnExists(DB.Vehicles, 'depotprice') then sets[#sets + 1] = 'depotprice = ?' params[#params + 1] = City.ImpoundFee end
        params[#params + 1] = row.plate
        MySQL.update.await(('UPDATE `%s` SET %s WHERE plate = ?'):format(DB.Vehicles, table.concat(sets, ', ')), params)

        local vehicle = FindWorldVehicle(plate)
        if vehicle then DeleteEntity(vehicle) end

        local owner = QBCore.Functions.GetPlayerByCitizenId(row.citizenid)
        if owner then Notify(owner.PlayerData.source, ('Your vehicle %s has been impounded by order of the Department of Justice'):format(plate), 'error', 10000) end
        JS.Log(Player, 'vehicle_impound', row.citizenid, ownerName, details, { plate = plate })
        return { ok = true, message = 'Vehicle impounded' .. (vehicle and ' and removed from the street' or '') }

    elseif action == 'release' then
        local sets, params = { 'state = ?' }, { 1 }
        if JS.ColumnExists(DB.Vehicles, 'depotprice') then sets[#sets + 1] = 'depotprice = ?' params[#params + 1] = 0 end
        params[#params + 1] = row.plate
        MySQL.update.await(('UPDATE `%s` SET %s WHERE plate = ?'):format(DB.Vehicles, table.concat(sets, ', ')), params)

        local owner = QBCore.Functions.GetPlayerByCitizenId(row.citizenid)
        if owner then Notify(owner.PlayerData.source, ('Your vehicle %s has been released from impound by the Department of Justice'):format(plate), 'success', 10000) end
        JS.Log(Player, 'vehicle_release', row.citizenid, ownerName, details, { plate = plate })
        return { ok = true, message = 'Vehicle released' }

    elseif action == 'transfer' then
        local newOwner = JS.ValidCitizenId(extra)
        if not newOwner then return { ok = false, err = 'Invalid new owner citizen ID' } end
        if newOwner == row.citizenid then return { ok = false, err = 'The vehicle is already registered to them' } end

        local newRow = JS.GetPlayerRow(newOwner)
        if not newRow then return { ok = false, err = 'No citizen with this citizen ID' } end

        local sets, params = { 'citizenid = ?' }, { newOwner }
        if JS.ColumnExists(DB.Vehicles, 'license') and newRow.license then
            sets[#sets + 1] = 'license = ?' params[#params + 1] = newRow.license
        end
        params[#params + 1] = row.plate
        params[#params + 1] = row.citizenid
        local affected = MySQL.update.await(('UPDATE `%s` SET %s WHERE plate = ? AND citizenid = ?'):format(DB.Vehicles, table.concat(sets, ', ')), params)
        if not affected or affected == 0 then return { ok = false, err = 'Vehicle data changed, try again' } end

        local newName = JS.FullName(JS.Decode(newRow.charinfo))
        details['Previous owner'] = ('%s (%s)'):format(ownerName or '-', row.citizenid)
        details['New owner'] = ('%s (%s)'):format(newName, newOwner)
        JS.Log(Player, 'vehicle_transfer', newOwner, newName, details, { plate = plate, from = row.citizenid })

        for _, cid in ipairs({ row.citizenid, newOwner }) do
            local target = QBCore.Functions.GetPlayerByCitizenId(cid)
            if target then Notify(target.PlayerData.source, ('The title of vehicle %s was transferred by order of the Department of Justice'):format(plate), 'primary', 10000) end
        end
        return { ok = true, message = 'Vehicle title transferred to ' .. newName }
    end

    return { ok = false, err = 'Unknown action' }
end)

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- Property registry
-- ════════════════════════════════════════════════════════════════════════════════════════════════

JS.RegisterCallback('NomadJustice:server:searchProperties', 'city', function(src, Player, query)
    if not HousesReady() then return { ok = false, err = 'Property table not found, check Settings.Database.Houses' } end
    local h = DB.Houses

    query = JS.CleanText(query, 40, true)
    if not query or JS.Len(query) < 2 then return { ok = false, err = 'Type at least 2 characters' } end

    local like = '%' .. query:gsub('[%%_\\]', '\\%0') .. '%'
    local labelCol = JS.ColumnExists(h.table, h.label) and h.label or h.id
    local rows = MySQL.query.await(('SELECT * FROM `%s` WHERE `%s` LIKE ? OR `%s` = ? LIMIT 30'):format(h.table, labelCol, h.owner), { like, query }) or {}

    local ids = {}
    for i, row in ipairs(rows) do ids[i] = row[h.owner] end
    local names = GetNames(ids)

    local list = {}
    for i, row in ipairs(rows) do
        local owner = row[h.owner]
        list[i] = {
            id = row[h.id],
            label = JS.Safe(tostring(row[labelCol] or row[h.id])),
            owner = owner,
            ownerName = names[owner],
            ownerStatus = owner and JS.GetStatus(owner).text or nil,
        }
    end
    return { ok = true, properties = list, perms = JS.GetPermissions(Player) }
end)

JS.RegisterCallback('NomadJustice:server:transferProperty', 'properties', function(src, Player, propertyId, newOwner)
    if not HousesReady() then return { ok = false, err = 'Property table not found' } end
    local h = DB.Houses

    newOwner = JS.ValidCitizenId(newOwner)
    if not newOwner or (type(propertyId) ~= 'number' and type(propertyId) ~= 'string') then
        return { ok = false, err = 'Invalid data' }
    end

    local row = MySQL.single.await(('SELECT * FROM `%s` WHERE `%s` = ? LIMIT 1'):format(h.table, h.id), { propertyId })
    if not row then return { ok = false, err = 'Property not found' } end
    if row[h.owner] == newOwner then return { ok = false, err = 'The property is already registered to them' } end

    local newRow = JS.GetPlayerRow(newOwner)
    if not newRow then return { ok = false, err = 'No citizen with this citizen ID' } end

    local affected = MySQL.update.await(('UPDATE `%s` SET `%s` = ? WHERE `%s` = ?'):format(h.table, h.owner, h.id), { newOwner, propertyId })
    if not affected or affected == 0 then return { ok = false, err = 'Could not transfer the deed' } end

    local newName = JS.FullName(JS.Decode(newRow.charinfo))
    local label = tostring(row[h.label] or propertyId)
    JS.Log(Player, 'property_transfer', newOwner, newName, {
        ['Property'] = label,
        ['Previous owner'] = tostring(row[h.owner] or '-'),
    }, row[h.owner] and { id = propertyId, from = row[h.owner] } or nil)
    return { ok = true, message = ('Deed of %s transferred to %s'):format(label, newName) }
end)

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- Licenses
-- ════════════════════════════════════════════════════════════════════════════════════════════════

JS.RegisterCallback('NomadJustice:server:setLicense', 'licenses', function(src, Player, citizenid, key, state)
    citizenid = JS.ValidCitizenId(citizenid)
    state = state == true
    if not citizenid or type(key) ~= 'string' or not key:match('^[%w_]+$') or #key > 30 then
        return { ok = false, err = 'Invalid data' }
    end
    if citizenid == Player.PlayerData.citizenid then return { ok = false, err = 'You cannot change your own licenses' } end

    local citizen = JS.GetCitizen(citizenid)
    if not citizen then return { ok = false, err = 'No citizen with this citizen ID' } end

    local metadata = citizen.metadata
    local field = metadata.licenses and not metadata.licences and 'licenses' or 'licences'
    local licenses = metadata[field] or {}
    if Settings.Licenses[key] == nil and licenses[key] == nil then
        return { ok = false, err = 'Unknown license type' }
    end
    local previous = licenses[key] == true
    licenses[key] = state

    if citizen.online then
        citizen.online.Functions.SetMetaData(field, licenses)
        Notify(citizen.online.PlayerData.source, ('%s %s by order of the Department of Justice'):format(state and 'You were granted' or 'Revoked:', Settings.Licenses[key] or key), state and 'success' or 'error', 8000)
    else
        metadata[field] = licenses
        if not JS.UpdatePlayerJson(citizenid, 'metadata', metadata, citizen.raw.metadata) then return { ok = false, err = 'Citizen data changed, try again' } end
    end

    JS.Log(Player, state and 'license_grant' or 'license_revoke', citizenid, JS.FullName(citizen.charinfo), { ['License'] = Settings.Licenses[key] or key }, { key = key, state = previous })
    return { ok = true }
end)

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- Gangs
-- ════════════════════════════════════════════════════════════════════════════════════════════════

local function GradeList(entry)
    local list = {}
    for key, grade in pairs(entry.grades or {}) do
        local level = tonumber(key)
        if level then list[#list + 1] = { level = level, name = JS.Safe(grade.name or ('Rank ' .. level)), isboss = grade.isboss == true } end
    end
    table.sort(list, function(a, b) return a.level < b.level end)
    return list
end

JS.RegisterCallback('NomadJustice:server:getGangs', 'view', function()
    local list = {}
    for name, gang in pairs(QBCore.Shared.Gangs or {}) do
        list[#list + 1] = { name = name, label = JS.Safe(gang.label or name), grades = GradeList(gang) }
    end
    table.sort(list, function(a, b)
        if a.name == City.NoGang then return true end
        if b.name == City.NoGang then return false end
        return a.label < b.label
    end)
    return { ok = true, gangs = list }
end)

JS.RegisterCallback('NomadJustice:server:setGang', 'gangs', function(src, Player, citizenid, gangName, level)
    citizenid = JS.ValidCitizenId(citizenid)
    level = math.floor(tonumber(level) or -1)
    if not citizenid then return { ok = false, err = 'Invalid citizen ID' } end
    if citizenid == Player.PlayerData.citizenid then return { ok = false, err = 'You cannot change your own gang' } end

    local gangs = QBCore.Shared.Gangs or {}
    local gang = type(gangName) == 'string' and gangs[gangName]
    if not gang then return { ok = false, err = 'Gang not found' } end
    local grade = gang.grades and (gang.grades[tostring(level)] or gang.grades[level])
    if not grade then return { ok = false, err = 'Rank not found' } end

    local citizen = JS.GetCitizen(citizenid)
    if not citizen then return { ok = false, err = 'No citizen with this citizen ID' } end

    local oldGang = citizen.gang and (citizen.gang.label or citizen.gang.name) or '-'
    local oldGangName = citizen.gang and citizen.gang.name or City.NoGang
    local oldGangLevel = citizen.gang and type(citizen.gang.grade) == 'table' and tonumber(citizen.gang.grade.level) or 0
    if citizen.online then
        if not citizen.online.Functions.SetGang(gangName, level) then return { ok = false, err = 'Could not change the gang' } end
    else
        local data = {
            name = gangName, label = gang.label or gangName, isboss = grade.isboss == true,
            grade = { name = grade.name, level = level },
        }
        if not JS.UpdatePlayerJson(citizenid, 'gang', data, citizen.raw.gang) then return { ok = false, err = 'Citizen data changed, try again' } end
    end

    JS.Log(Player, 'gang', citizenid, JS.FullName(citizen.charinfo), { ['From'] = oldGang, ['To'] = ('%s - %s'):format(gang.label or gangName, grade.name or level) }, { gang = oldGangName, level = oldGangLevel })
    return { ok = true }
end)

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- Court summonses
-- ════════════════════════════════════════════════════════════════════════════════════════════════

local pendingSummons = {} -- [citizenid] = { summon, ... }

local function SummonText(s)
    return ('📜 Summons from the Department of Justice\nReason: %s\nWhen: %s\nWhere: %s'):format(s.reason, s.appointment ~= '' and s.appointment or 'To be scheduled', s.location ~= '' and s.location or 'Courthouse')
end

local function DeliverSummons(Player)
    local cid = Player.PlayerData.citizenid
    local list = pendingSummons[cid]
    if not list then return end
    pendingSummons[cid] = nil
    for _, summon in ipairs(list) do
        Notify(Player.PlayerData.source, SummonText(summon), 'primary', 20000)
        MySQL.update("UPDATE justice_summons SET status = 'delivered' WHERE id = ? AND status = 'pending'", { summon.id })
    end
end

CreateThread(function()
    while not JS.Ready do Wait(1000) end
    for _, row in ipairs(MySQL.query.await("SELECT * FROM justice_summons WHERE status = 'pending'") or {}) do
        pendingSummons[row.citizenid] = pendingSummons[row.citizenid] or {}
        table.insert(pendingSummons[row.citizenid], row)
    end

    -- Deliver summonses to players who join (works with any core version)
    while true do
        if next(pendingSummons) then
            for _, playerId in pairs(QBCore.Functions.GetPlayers()) do
                local Player = QBCore.Functions.GetPlayer(playerId)
                if Player and pendingSummons[Player.PlayerData.citizenid] then
                    DeliverSummons(Player)
                end
            end
        end
        Wait(30000)
    end
end)

JS.RegisterCallback('NomadJustice:server:sendSummon', 'summon', function(src, Player, citizenid, reason, appointment, location)
    citizenid = JS.ValidCitizenId(citizenid)
    reason = JS.CleanText(reason, City.SummonMaxLength, true)
    appointment = JS.CleanText(appointment, 100, false)
    location = JS.CleanText(location, 100, false)
    if not citizenid then return { ok = false, err = 'Invalid citizen ID' } end
    if not reason then return { ok = false, err = ('A reason is required (%d characters max)'):format(City.SummonMaxLength) } end
    if not appointment or not location then return { ok = false, err = 'Date and location are 100 characters max' } end
    if JS.OnCooldown('summon', Player.PlayerData.citizenid .. ':' .. citizenid, 30) then
        return { ok = false, err = 'A summons was sent to this citizen moments ago' }
    end

    local citizen = JS.GetCitizen(citizenid)
    if not citizen then return { ok = false, err = 'No citizen with this citizen ID' } end

    local name = JS.FullName(citizen.charinfo)
    local summon = { citizenid = citizenid, reason = reason, appointment = appointment, location = location }
    summon.id = MySQL.insert.await('INSERT INTO justice_summons (citizenid, name, reason, appointment, location, officer_citizenid, officer_name) VALUES (?, ?, ?, ?, ?, ?, ?)', {
        citizenid, name, reason, appointment, location, Player.PlayerData.citizenid, JS.PlayerName(Player)
    })
    if not summon.id then return { ok = false, err = 'Could not save the summons' } end

    pendingSummons[citizenid] = pendingSummons[citizenid] or {}
    table.insert(pendingSummons[citizenid], summon)
    if citizen.online then DeliverSummons(citizen.online) end

    JS.Log(Player, 'summon', citizenid, name, { ['Reason'] = reason, ['Date & time'] = appointment, ['Location'] = location }, { id = summon.id })
    return { ok = true, delivered = citizen.online ~= nil }
end)

JS.RegisterCallback('NomadJustice:server:setSummonStatus', 'summon', function(src, Player, summonId, status)
    summonId = tonumber(summonId)
    if not summonId or not SummonStatus[status] or status == 'pending' then return { ok = false, err = 'Invalid data' } end

    local affected = MySQL.update.await('UPDATE justice_summons SET status = ? WHERE id = ?', { status, summonId })
    if not affected or affected == 0 then return { ok = false, err = 'Summons not found' } end

    for cid, list in pairs(pendingSummons) do
        for i = #list, 1, -1 do
            if list[i].id == summonId then table.remove(list, i) end
        end
        if #list == 0 then pendingSummons[cid] = nil end
    end
    return { ok = true }
end)

-- Used by the citizen record
function JS.GetSummons(citizenid, limit)
    local list = {}
    for i, row in ipairs(MySQL.query.await('SELECT * FROM justice_summons WHERE citizenid = ? ORDER BY id DESC LIMIT ?', { citizenid, limit or 15 }) or {}) do
        list[i] = {
            id = row.id,
            reason = JS.Safe(row.reason),
            appointment = JS.Safe(row.appointment),
            location = JS.Safe(row.location),
            officer = JS.Safe(row.officer_name),
            status = row.status,
            statusLabel = SummonStatus[row.status] or row.status,
            date = JS.FormatDbDate(row.created_at),
        }
    end
    return list
end

JS.RegisterCallback('NomadJustice:server:getAllSummons', 'summon', function()
    local list = {}
    for i, row in ipairs(MySQL.query.await("SELECT * FROM justice_summons WHERE status IN ('pending', 'delivered') ORDER BY id DESC LIMIT 100") or {}) do
        list[i] = {
            id = row.id,
            citizenid = row.citizenid,
            name = JS.Safe(row.name),
            reason = JS.Safe(row.reason),
            appointment = JS.Safe(row.appointment),
            location = JS.Safe(row.location),
            officer = JS.Safe(row.officer_name),
            status = row.status,
            statusLabel = SummonStatus[row.status] or row.status,
            date = JS.FormatDbDate(row.created_at),
            citizenStatus = JS.GetStatus(row.citizenid),
        }
    end
    return { ok = true, summons = list }
end)

-- A citizen views their own summonses
JS.RegisterCallback('NomadJustice:server:getMySummons', nil, function(src, Player)
    return { ok = true, summons = JS.GetSummons(Player.PlayerData.citizenid, 10) }
end)

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- City-wide announcement
-- ════════════════════════════════════════════════════════════════════════════════════════════════

JS.RegisterCallback('NomadJustice:server:announce', 'announce', function(src, Player, text)
    text = JS.CleanText(text, City.AnnounceMaxLength, true)
    if not text or JS.Len(text) < 5 then
        return { ok = false, err = ('The announcement must be 5 to %d characters'):format(City.AnnounceMaxLength) }
    end

    local blocked, remaining = JS.OnCooldown('announce', 'global', City.AnnounceCooldown)
    if blocked then return { ok = false, err = ('You can send another announcement in %d seconds'):format(remaining) } end

    for _, playerId in pairs(QBCore.Functions.GetPlayers()) do
        Notify(playerId, '⚖️ Department of Justice announcement\n' .. text, 'primary', 15000)
    end
    JS.Log(Player, 'announce', nil, nil, { ['Announcement'] = text })
    return { ok = true }
end)
