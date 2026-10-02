local Settings = JS.Settings
local Panel = Settings.Panel
local Notify = JS.Notify

local VehicleStates = { [0] = 'Out of garage', [1] = 'In garage', [2] = 'Impounded' }

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- Citizen record builders
-- ════════════════════════════════════════════════════════════════════════════════════════════════

local function GradeName(grade)
    if type(grade) == 'table' then return grade.name or grade.label or tostring(grade.level or '') end
    return grade and tostring(grade) or nil
end

local function GetVehicles(citizenid)
    local tableName = Settings.Database.Vehicles
    if not tableName or not JS.TableExists(tableName) then return nil end

    local rows = MySQL.query.await(('SELECT * FROM `%s` WHERE citizenid = ?'):format(tableName), { citizenid }) or {}
    local vehicles = {}
    for i, row in ipairs(rows) do
        local shared = QBCore.Shared.Vehicles and QBCore.Shared.Vehicles[row.vehicle]
        local label = shared and (('%s %s'):format(shared.brand or '', shared.name or row.vehicle):gsub('^%s+', '')) or row.vehicle
        vehicles[i] = {
            label = label or 'Unknown',
            model = row.vehicle,
            plate = row.plate,
            garage = row.garage,
            state = VehicleStates[tonumber(row.state)] or tostring(row.state or '-'),
            fuel = tonumber(row.fuel) and math.floor(tonumber(row.fuel)) or nil,
            engine = tonumber(row.engine) and math.floor(tonumber(row.engine) / 10) or nil,
            body = tonumber(row.body) and math.floor(tonumber(row.body) / 10) or nil,
        }
    end
    return vehicles
end

local function GetHouses(citizenid)
    local houses = Settings.Database.Houses
    if not houses or not JS.TableExists(houses.table) or not JS.ColumnExists(houses.table, houses.owner) then
        return nil
    end

    local rows = MySQL.query.await(('SELECT * FROM `%s` WHERE `%s` = ?'):format(houses.table, houses.owner), { citizenid }) or {}
    local list = {}
    for i, row in ipairs(rows) do
        list[i] = { label = tostring(row[houses.label] or row.id or ('Property #' .. i)) }
    end
    return list
end

local function GetItems(items)
    local shared = QBCore.Shared.Items or {}
    local grouped, order = {}, {}
    for _, item in pairs(items or {}) do
        if type(item) == 'table' and item.name then
            local amount = tonumber(item.amount or item.count) or 1
            if not grouped[item.name] then
                grouped[item.name] = 0
                order[#order + 1] = item.name
            end
            grouped[item.name] = grouped[item.name] + amount
        end
    end

    local list = {}
    for i, name in ipairs(order) do
        list[i] = { label = shared[name] and shared[name].label or name, amount = grouped[name] }
    end
    table.sort(list, function(a, b) return a.label < b.label end)
    return list
end

local function GetLicenses(metadata)
    local list, seen = {}, {}
    local current = metadata.licences or metadata.licenses or {}
    for key, value in pairs(current) do
        seen[key] = true
        list[#list + 1] = { key = key, label = Settings.Licenses[key] or key, active = value == true }
    end
    -- License types from the config and which ones the citizen holds (so they can be granted)
    for key, label in pairs(Settings.Licenses) do
        if not seen[key] then list[#list + 1] = { key = key, label = label, active = false } end
    end
    table.sort(list, function(a, b) return a.label < b.label end)
    return list
end

local function BuildProfile(citizen, Viewer)
    local ci, job, gang, md, money = citizen.charinfo, citizen.job, citizen.gang, citizen.metadata, citizen.money
    local cid = citizen.citizenid

    local transactions = {}
    for i, row in ipairs(MySQL.query.await('SELECT * FROM justice_transactions WHERE target_citizenid = ? ORDER BY id DESC LIMIT 15', { cid }) or {}) do
        transactions[i] = {
            type = row.type,
            amount = row.amount,
            reason = row.reason,
            officer = row.officer_name,
            date = row.date,
        }
    end

    local reports = {}
    for i, row in ipairs(MySQL.query.await(
        'SELECT id, title, case_type, status, date, citizenid FROM justice_reports WHERE job = ? AND (citizenid = ? OR defendant_citizenid = ?) ORDER BY id DESC LIMIT 25',
        { JS.Job, cid, cid }) or {}) do
        reports[i] = {
            id = row.id,
            title = row.title ~= '' and row.title or ('Case #' .. row.id),
            caseType = row.case_type,
            status = JS.StatusLabels[row.status] or row.status,
            date = row.date,
            role = row.citizenid == cid and 'Plaintiff' or 'Defendant',
        }
    end

    local record = md.criminalrecord or {}
    local profile = {
        citizenid = cid,
        name = JS.FullName(ci),
        online = citizen.online ~= nil,
        status = JS.GetStatus(cid, citizen.lastUpdatedRaw),
        serverId = citizen.online and citizen.online.PlayerData.source or nil,
        ping = citizen.online and GetPlayerPing(citizen.online.PlayerData.source) or nil,
        lastUpdated = citizen.lastUpdated,

        firstname = ci.firstname,
        lastname = ci.lastname,
        birthdate = ci.birthdate,
        gender = tonumber(ci.gender),
        nationality = ci.nationality,
        phone = ci.phone,
        account = ci.account,

        job = {
            name = job.name,
            label = job.label or job.name or 'Unemployed',
            grade = GradeName(job.grade),
            onduty = job.onduty == true,
            isboss = job.isboss == true,
        },
        gang = (gang.name and gang.name ~= 'none') and { label = gang.label or gang.name, grade = GradeName(gang.grade) } or nil,

        money = {
            cash = math.floor(tonumber(money.cash) or 0),
            bank = math.floor(tonumber(money.bank) or 0),
            crypto = tonumber(money.crypto),
        },

        info = {
            bloodtype = md.bloodtype,
            fingerprint = md.fingerprint,
            walletid = md.walletid,
            callsign = md.callsign,
            injail = tonumber(md.injail) or 0,
            isdead = md.isdead == true,
            criminalRecord = record.hasRecord == true,
            criminalRecordDate = record.date and tostring(record.date) or nil,
        },

        licenses = GetLicenses(md),
        vehicles = GetVehicles(cid),
        houses = GetHouses(cid),
        items = GetItems(citizen.items),
        transactions = transactions,
        reports = reports,
        suspension = JS.Suspended[cid],
        summons = JS.GetSummons and JS.GetSummons(cid) or {},
        court = JS.GetCourtInfo and JS.GetCourtInfo(cid) or nil,
        licenseTypes = Settings.Licenses,
        isSelf = Viewer.PlayerData.citizenid == cid,
    }

    return profile
end

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- Dashboard
-- ════════════════════════════════════════════════════════════════════════════════════════════════

JS.RegisterCallback('NomadJustice:server:panelInfo', 'view', function(src, Player)
    local newReports = MySQL.scalar.await("SELECT COUNT(*) FROM justice_reports WHERE job = ? AND status = 'new'", { JS.Job }) or 0
    local suspended = 0
    for _ in pairs(JS.Suspended) do suspended = suspended + 1 end

    local players = QBCore.Functions.GetPlayers()
    local justiceOnDuty = 0
    for _, playerId in pairs(players) do
        local target = QBCore.Functions.GetPlayer(playerId)
        if JS.IsJustice(target) and target.PlayerData.job.onduty then justiceOnDuty = justiceOnDuty + 1 end
    end

    local totalCitizens = 0
    if JS.TableExists(Settings.Database.Players) then
        totalCitizens = tonumber(MySQL.scalar.await(('SELECT COUNT(*) FROM `%s`'):format(Settings.Database.Players))) or 0
    end

    local warrants = tonumber(MySQL.scalar.await("SELECT COUNT(*) FROM justice_warrants WHERE status = 'active' AND (expires_at IS NULL OR expires_at > NOW())")) or 0
    local suspects = tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM justice_suspects WHERE active = 1')) or 0
    local policeRequests = tonumber(MySQL.scalar.await("SELECT COUNT(*) FROM justice_police_requests WHERE status = 'pending'")) or 0

    return {
        ok = true,
        role = 'justice',
        perms = JS.GetPermissions(Player),
        finance = JS.GetFinanceSector and JS.GetFinanceSector(Player) or nil,
        judge = JS.IsJudge(Player) or nil,
        policePerms = JS.IsJudge(Player) and JS.GetPolicePermissions(Player) or nil,
        warrants = warrants,
        suspects = suspects,
        policeRequests = policeRequests,
        online = #players,
        totalCitizens = totalCitizens,
        justiceOnDuty = justiceOnDuty,
        newReports = tonumber(newReports) or 0,
        suspended = suspended,
    }
end)

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- Citizen registry (paged) - filter: 'all' | 'online' | 'offline'
-- ════════════════════════════════════════════════════════════════════════════════════════════════

local PAGE_SIZE = 40

JS.RegisterCallback('NomadJustice:server:getAllCitizens', 'view', function(src, Player, page, filter)
    page = math.max(0, math.floor(tonumber(page) or 0))
    if filter ~= 'online' and filter ~= 'offline' then filter = 'all' end

    local onlineIds = {}
    for _, playerId in pairs(QBCore.Functions.GetPlayers()) do
        local target = QBCore.Functions.GetPlayer(playerId)
        if target then onlineIds[#onlineIds + 1] = target.PlayerData.citizenid end
    end

    local function entry(cid, charinfo, job, lastUpdated)
        local status = JS.GetStatus(cid, lastUpdated)
        return {
            citizenid = cid,
            name = JS.FullName(charinfo),
            job = job and JS.Safe(job.label or job.name) or '-',
            phone = charinfo and charinfo.phone or '-',
            online = status.online,
            serverId = status.serverId,
            status = status,
            suspended = JS.Suspended[cid] ~= nil,
        }
    end

    local list, total = {}, 0

    if filter == 'online' then
        total = #onlineIds
        for _, playerId in pairs(QBCore.Functions.GetPlayers()) do
            local target = QBCore.Functions.GetPlayer(playerId)
            if target then
                local pd = target.PlayerData
                list[#list + 1] = entry(pd.citizenid, pd.charinfo, pd.job)
            end
        end
        table.sort(list, function(a, b) return (a.serverId or 0) < (b.serverId or 0) end)
        local paged = {}
        for i = page * PAGE_SIZE + 1, math.min(#list, (page + 1) * PAGE_SIZE) do paged[#paged + 1] = list[i] end
        list = paged
    else
        local tableName = Settings.Database.Players
        if not JS.TableExists(tableName) then return { ok = false, err = 'Players table not found' } end

        local where, params = '', {}
        if filter == 'offline' and #onlineIds > 0 then
            where = ('WHERE citizenid NOT IN (%s)'):format(('?,'):rep(#onlineIds):sub(1, -2))
            params = onlineIds
        end

        total = tonumber(MySQL.scalar.await(('SELECT COUNT(*) FROM `%s` %s'):format(tableName, where), params)) or 0

        local order = JS.ColumnExists(tableName, 'last_updated') and 'last_updated DESC' or 'citizenid'
        local query = ('SELECT %s FROM `%s` %s ORDER BY %s LIMIT %d OFFSET %d'):format(
            JS.PlayerListColumns(), tableName, where, order, PAGE_SIZE, page * PAGE_SIZE)
        for _, row in ipairs(MySQL.query.await(query, params) or {}) do
            list[#list + 1] = entry(row.citizenid, JS.Decode(row.charinfo), JS.Decode(row.job), row.last_updated)
        end

        -- Online first, keeping last-seen order
        local onlineFirst, offline = {}, {}
        for _, item in ipairs(list) do
            table.insert(item.online and onlineFirst or offline, item)
        end
        for _, item in ipairs(offline) do onlineFirst[#onlineFirst + 1] = item end
        list = onlineFirst
    end

    return {
        ok = true,
        list = list,
        page = page,
        pages = math.max(1, math.ceil(total / PAGE_SIZE)),
        total = total,
        online = #onlineIds,
        filter = filter,
    }
end)

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- Online players
-- ════════════════════════════════════════════════════════════════════════════════════════════════

JS.RegisterCallback('NomadJustice:server:getOnlinePlayers', 'view', function()
    local list = {}
    for _, playerId in pairs(QBCore.Functions.GetPlayers()) do
        local target = QBCore.Functions.GetPlayer(playerId)
        if target then
            local pd = target.PlayerData
            list[#list + 1] = {
                serverId = pd.source,
                citizenid = pd.citizenid,
                name = JS.FullName(pd.charinfo),
                job = pd.job and (pd.job.label or pd.job.name) or '-',
                phone = pd.charinfo and pd.charinfo.phone or '-',
                suspended = JS.Suspended[pd.citizenid] ~= nil,
                online = true,
                status = JS.GetStatus(pd.citizenid),
            }
        end
    end
    table.sort(list, function(a, b) return a.serverId < b.serverId end)
    return { ok = true, players = list }
end)

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- Search (online and offline): by name, citizen ID, phone number or server ID
-- ════════════════════════════════════════════════════════════════════════════════════════════════

JS.RegisterCallback('NomadJustice:server:searchCitizens', 'view', function(src, Player, query)
    query = JS.CleanText(query, 40, true)
    if not query or JS.Len(query) < 2 then
        return { ok = false, err = 'Type at least 2 characters to search' }
    end

    local results, seen = {}, {}
    local function add(cid, charinfo, job, lastUpdated)
        if seen[cid] then return end
        seen[cid] = true
        local status = JS.GetStatus(cid, lastUpdated)
        results[#results + 1] = {
            citizenid = cid,
            name = JS.FullName(charinfo),
            job = job and JS.Safe(job.label or job.name) or '-',
            phone = charinfo and charinfo.phone or '-',
            online = status.online,
            serverId = status.serverId,
            status = status,
            suspended = JS.Suspended[cid] ~= nil,
        }
    end

    -- Search by server ID
    local serverId = tonumber(query)
    if serverId then
        local target = QBCore.Functions.GetPlayer(serverId)
        if target then add(target.PlayerData.citizenid, target.PlayerData.charinfo, target.PlayerData.job) end
    end

    -- Online
    local lower = query:lower()
    for _, playerId in pairs(QBCore.Functions.GetPlayers()) do
        local target = QBCore.Functions.GetPlayer(playerId)
        if target then
            local pd = target.PlayerData
            local charinfo = pd.charinfo or {}
            local name = JS.FullName(charinfo):lower()
            if pd.citizenid == query or tostring(charinfo.phone) == query or name:find(lower, 1, true) then
                add(pd.citizenid, pd.charinfo, pd.job)
            end
        end
    end

    -- Database
    local tableName = Settings.Database.Players
    if JS.TableExists(tableName) then
        local like = '%' .. query:gsub('[%%_\\]', '\\%0') .. '%'
        local rows = MySQL.query.await(([[
            SELECT %s FROM `%s`
            WHERE citizenid = ?
               OR JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.phone')) = ?
               OR CONCAT(JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.firstname')), ' ', JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.lastname'))) LIKE ?
            LIMIT 30
        ]]):format(JS.PlayerListColumns(), tableName), { query, query, like }) or {}

        for _, row in ipairs(rows) do
            add(row.citizenid, JS.Decode(row.charinfo), JS.Decode(row.job), row.last_updated)
        end
    end

    return { ok = true, results = results }
end)

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- Citizen record
-- ════════════════════════════════════════════════════════════════════════════════════════════════

JS.RegisterCallback('NomadJustice:server:getProfile', 'view', function(src, Player, citizenid)
    citizenid = JS.ValidCitizenId(citizenid)
    if not citizenid then return { ok = false, err = 'Invalid citizen ID' } end

    local citizen = JS.GetCitizen(citizenid)
    if not citizen then return { ok = false, err = 'No citizen with this citizen ID' } end

    local profile = BuildProfile(citizen, Player)
    if Panel.LogViews and not JS.OnCooldown('view', Player.PlayerData.citizenid .. ':' .. citizenid, 300) then
        JS.Log(Player, 'view', citizenid, profile.name)
    end

    return { ok = true, profile = profile, perms = JS.GetPermissions(Player) }
end)

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- Locate
-- ════════════════════════════════════════════════════════════════════════════════════════════════

JS.RegisterCallback('NomadJustice:server:locateCitizen', 'locate', function(src, Player, citizenid)
    citizenid = JS.ValidCitizenId(citizenid)
    local target = citizenid and QBCore.Functions.GetPlayerByCitizenId(citizenid)
    if not target then return { ok = false, err = 'The citizen is not online' } end

    local ped = GetPlayerPed(target.PlayerData.source)
    if ped == 0 then return { ok = false, err = 'Could not determine the location' } end

    local coords = GetEntityCoords(ped)
    local name = JS.PlayerName(target)
    JS.Log(Player, 'locate', citizenid, name, { ['Coordinates'] = ('%.1f, %.1f, %.1f'):format(coords.x, coords.y, coords.z) })

    return { ok = true, coords = { x = coords.x, y = coords.y, z = coords.z }, name = name, inVehicle = GetVehiclePedIsIn(ped, false) ~= 0 }
end)

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- Bank seizure
-- ════════════════════════════════════════════════════════════════════════════════════════════════

JS.RegisterCallback('NomadJustice:server:withdrawBank', 'withdraw', function(src, Player, citizenid, amount, reason)
    citizenid = JS.ValidCitizenId(citizenid)
    amount = math.floor(tonumber(amount) or 0)
    reason = JS.CleanText(reason, 200, true)

    if not citizenid then return { ok = false, err = 'Invalid citizen ID' } end
    if amount <= 0 then return { ok = false, err = 'Invalid amount' } end
    if amount > Panel.WithdrawMax then return { ok = false, err = ('Maximum seizure is $%d'):format(Panel.WithdrawMax) } end
    if not reason then return { ok = false, err = 'A reason is required (200 characters max)' } end
    if citizenid == Player.PlayerData.citizenid then return { ok = false, err = 'You cannot perform this action on yourself' } end

    local officerCid = Player.PlayerData.citizenid
    local blocked, remaining = JS.OnCooldown('withdraw', officerCid, Panel.WithdrawCooldown)
    if blocked then return { ok = false, err = ('You must wait %d seconds'):format(remaining) } end

    -- Any failure after this point cancels the cooldown
    local function fail(err)
        JS.ClearCooldown('withdraw', officerCid)
        return { ok = false, err = err }
    end

    local targetName, newBalance
    local target = QBCore.Functions.GetPlayerByCitizenId(citizenid)

    if target then
        local bank = tonumber(target.PlayerData.money.bank) or 0
        if bank < amount then
            return fail(('Insufficient bank balance (balance: $%d)'):format(math.floor(bank)))
        end
        if not JS.RemoveBank(target, amount, 'justice-withdraw') then
            return fail('Could not seize the amount')
        end
        targetName = JS.PlayerName(target)
        newBalance = math.floor(tonumber(target.PlayerData.money.bank) or 0)
        Notify(target.PlayerData.source, ('$%d was seized from your bank account by order of the Department of Justice. Reason: %s'):format(amount, reason), 'error', 10000)
    else
        -- Offline: safe update (fails if the balance changed meanwhile)
        local tableName = Settings.Database.Players
        local row = JS.GetPlayerRow(citizenid)
        if not row then return fail('No citizen with this citizen ID') end

        local money = JS.OfflineMoney(row)
        local bank = tonumber(money.bank) or 0
        if bank < amount then
            return fail(('Insufficient bank balance (balance: $%d)'):format(math.floor(bank)))
        end
        money.bank = bank - amount

        if not JS.UpdatePlayerJson(citizenid, 'money', money, row.money) then
            return fail('Citizen data changed during the operation, try again')
        end
        targetName = JS.FullName(JS.Decode(row.charinfo))
        newBalance = math.floor(money.bank)
    end

    local dest = JS.DepositWithdrawn(Player, amount, 'justice-withdraw')

    MySQL.insert('INSERT INTO justice_transactions (officer_citizenid, officer_name, target_citizenid, target_name, amount, reason, date, type) VALUES (?, ?, ?, ?, ?, ?, ?, ?)', {
        Player.PlayerData.citizenid, JS.PlayerName(Player), citizenid, targetName, amount, reason, JS.Now(), 'withdraw'
    })
    JS.Log(Player, 'withdraw', citizenid, targetName, { ['Amount'] = amount, ['Reason'] = reason, ['New balance'] = newBalance }, { amount = amount, dest = dest })

    return { ok = true, newBalance = newBalance, name = targetName }
end)

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- Suspend / lift service suspension
-- ════════════════════════════════════════════════════════════════════════════════════════════════

JS.RegisterCallback('NomadJustice:server:suspendCitizen', 'suspend', function(src, Player, citizenid, reason)
    citizenid = JS.ValidCitizenId(citizenid)
    reason = JS.CleanText(reason, 200, true)
    if not citizenid then return { ok = false, err = 'Invalid citizen ID' } end
    if not reason then return { ok = false, err = 'A suspension reason is required (200 characters max)' } end
    if citizenid == Player.PlayerData.citizenid then return { ok = false, err = 'You cannot perform this action on yourself' } end
    if JS.Suspended[citizenid] then return { ok = false, err = 'This citizen is already suspended' } end

    local citizen = JS.GetCitizen(citizenid)
    if not citizen then return { ok = false, err = 'No citizen with this citizen ID' } end

    local name = JS.FullName(citizen.charinfo)
    local officerName = JS.PlayerName(Player)
    local id = MySQL.insert.await('INSERT INTO justice_suspensions (citizenid, name, reason, officer_citizenid, officer_name) VALUES (?, ?, ?, ?, ?)', {
        citizenid, name, reason, Player.PlayerData.citizenid, officerName
    })
    if not id then return { ok = false, err = 'Could not save the suspension' } end

    JS.Suspended[citizenid] = { id = id, name = name, reason = reason, officer = officerName, date = JS.Now() }

    if citizen.online then
        pcall(citizen.online.Functions.SetMetaData, 'justice_suspended', true)
        Notify(citizen.online.PlayerData.source, ('Your services have been suspended by order of the Department of Justice. Reason: %s'):format(reason), 'error', 10000)
    end

    TriggerEvent('NomadJustice:server:suspensionChanged', citizenid, true, reason)
    JS.Log(Player, 'suspend', citizenid, name, { ['Reason'] = reason }, { reason = reason })

    return { ok = true }
end)

JS.RegisterCallback('NomadJustice:server:unsuspendCitizen', 'suspend', function(src, Player, citizenid)
    citizenid = JS.ValidCitizenId(citizenid)
    local suspension = citizenid and JS.Suspended[citizenid]
    if not suspension then return { ok = false, err = 'This citizen is not suspended' } end

    MySQL.update.await('UPDATE justice_suspensions SET active = 0, lifted_by = ?, lifted_at = NOW() WHERE citizenid = ? AND active = 1', {
        JS.PlayerName(Player), citizenid
    })
    JS.Suspended[citizenid] = nil

    local target = QBCore.Functions.GetPlayerByCitizenId(citizenid)
    if target then
        pcall(target.Functions.SetMetaData, 'justice_suspended', false)
        Notify(target.PlayerData.source, 'Your service suspension has been lifted by the Department of Justice', 'success', 8000)
    end

    TriggerEvent('NomadJustice:server:suspensionChanged', citizenid, false)
    JS.Log(Player, 'unsuspend', citizenid, suspension.name, { ['Previous reason'] = suspension.reason }, { reason = suspension.reason })

    return { ok = true }
end)

JS.RegisterCallback('NomadJustice:server:getSuspended', 'view', function()
    local list = {}
    for cid, data in pairs(JS.Suspended) do
        list[#list + 1] = { citizenid = cid, name = data.name, reason = data.reason, officer = data.officer, date = data.date, id = data.id, status = JS.GetStatus(cid) }
    end
    table.sort(list, function(a, b) return (a.id or 0) > (b.id or 0) end)
    return { ok = true, list = list }
end)

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- Edit citizen identity
-- data = { firstname, lastname, birthdate, gender, nationality }
-- ════════════════════════════════════════════════════════════════════════════════════════════════

local EditLabels = {
    firstname = 'First name',
    lastname = 'Last name',
    birthdate = 'Date of birth',
    gender = 'Sex',
    nationality = 'Nationality',
}

local function ValidName(value)
    value = JS.CleanText(value, 20, true)
    if not value or JS.Len(value) < 2 or value:find('[%d%c"\\{}%[%]]') then return nil end
    return value
end

local function ValidBirthdate(value)
    value = JS.CleanText(value, 10, true)
    if not value then return nil end
    local y, m, d = value:match('^(%d%d%d%d)%-(%d%d)%-(%d%d)$')
    y, m, d = tonumber(y), tonumber(m), tonumber(d)
    if not y or y < 1900 or y > 2025 or m < 1 or m > 12 or d < 1 or d > 31 then return nil end
    return value
end

JS.RegisterCallback('NomadJustice:server:editCitizen', 'edit', function(src, Player, citizenid, data)
    citizenid = JS.ValidCitizenId(citizenid)
    if not citizenid or type(data) ~= 'table' then return { ok = false, err = 'Invalid data' } end
    if citizenid == Player.PlayerData.citizenid then return { ok = false, err = 'You cannot edit your own identity' } end

    local new = {
        firstname = ValidName(data.firstname),
        lastname = ValidName(data.lastname),
        birthdate = ValidBirthdate(data.birthdate),
        gender = (tonumber(data.gender) == 0 or tonumber(data.gender) == 1) and tonumber(data.gender) or nil,
        nationality = JS.CleanText(data.nationality, 30, true),
    }
    for key, label in pairs(EditLabels) do
        if new[key] == nil then
            return { ok = false, err = ('Invalid value for %s'):format(label) }
        end
    end

    local citizen = JS.GetCitizen(citizenid)
    if not citizen then return { ok = false, err = 'No citizen with this citizen ID' } end

    local charinfo = citizen.charinfo
    local old = {}
    for key in pairs(EditLabels) do old[key] = charinfo[key] end
    local changes = {}
    for key, label in pairs(EditLabels) do
        if tostring(charinfo[key]) ~= tostring(new[key]) then
            changes[label] = ('%s ← %s'):format(tostring(new[key]), tostring(charinfo[key] or '-'))
            charinfo[key] = new[key]
        end
    end
    if not next(changes) then return { ok = false, err = 'Nothing was changed' } end

    if citizen.online then
        citizen.online.Functions.SetPlayerData('charinfo', charinfo)
        if citizen.online.Functions.Save then pcall(citizen.online.Functions.Save) end
        Notify(citizen.online.PlayerData.source, 'Your personal details were updated by the Department of Justice', 'primary', 8000)
    else
        if not JS.UpdatePlayerJson(citizenid, 'charinfo', charinfo, citizen.raw.charinfo) then
            return { ok = false, err = 'Citizen data changed during the operation, try again' }
        end
    end

    JS.Log(Player, 'edit', citizenid, JS.FullName(charinfo), changes, { old = old })
    return { ok = true }
end)

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- Audit log
-- ════════════════════════════════════════════════════════════════════════════════════════════════

JS.RegisterCallback('NomadJustice:server:getLogs', 'logs', function(src, Player, citizenid, page)
    citizenid = citizenid and JS.ValidCitizenId(citizenid)
    page = math.max(0, math.floor(tonumber(page) or 0))
    local pageSize = 50

    local where, params = '', {}
    if citizenid then
        where = 'WHERE target_citizenid = ? OR officer_citizenid = ?'
        params = { citizenid, citizenid }
    end
    local total = tonumber(MySQL.scalar.await(('SELECT COUNT(*) FROM justice_logs %s'):format(where), params)) or 0
    local rows = MySQL.query.await(('SELECT * FROM justice_logs %s ORDER BY id DESC LIMIT %d OFFSET %d'):format(where, pageSize, page * pageSize), params)

    local logs = {}
    for i, row in ipairs(rows or {}) do
        local details = JS.Decode(row.details)
        local parts = {}
        for key, value in pairs(details) do
            parts[#parts + 1] = ('%s: %s'):format(key, JS.Safe(tostring(value)))
        end
        logs[i] = {
            id = row.id,
            key = row.action,
            action = JS.ActionLabels[row.action] or row.action,
            officer = JS.Safe(row.officer_name),
            officerCitizenid = row.officer_citizenid,
            targetCitizenid = row.target_citizenid,
            target = row.target_name and ('%s (%s)'):format(JS.Safe(row.target_name), row.target_citizenid) or nil,
            details = #parts > 0 and table.concat(parts, ' | ') or nil,
            date = JS.FormatDbDate(row.created_at),
            undoable = row.undo_data ~= nil and row.undone_by == nil and JS.UndoActions ~= nil and JS.UndoActions[row.action] ~= nil,
            undoneBy = row.undone_by and JS.Safe(row.undone_by) or nil,
        }
    end

    return { ok = true, logs = logs, page = page, pages = math.max(1, math.ceil(total / pageSize)), total = total, perms = JS.GetPermissions(Player) }
end)
