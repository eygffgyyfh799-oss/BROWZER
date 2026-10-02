-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- Police section of the state system
-- Police: limited access (search, basic identity, case and verdict history, warrants, persons of interest)
-- Anything sensitive (locate, bank statement, arrest/search warrant) = a request the DOJ approves or denies
-- ════════════════════════════════════════════════════════════════════════════════════════════════

local Settings = JS.Settings
local Police = Settings.Police
local Notify = JS.Notify

local function H(name) return JS.Handlers['NomadJustice:server:' .. name] end

JS.RequestTypes = {
    locate = 'Locate citizen',
    bank = 'Bank statement',
    arrest_warrant = 'Arrest warrant request',
    search_warrant = 'Search warrant request',
    other = 'Other request',
}
JS.RequestStatus = { pending = 'Pending', approved = 'Approved', rejected = 'Denied' }

-- Temporary clearances after approval: grants[officerCid][citizenid .. ':' .. type] = expiry time
local grants = {}

local function HasGrant(officerCid, citizenid, gType)
    local list = grants[officerCid]
    local expires = list and list[citizenid .. ':' .. gType]
    if expires and expires > os.time() then return true, expires - os.time() end
    return false
end

local function Grant(officerCid, citizenid, gType, minutes)
    grants[officerCid] = grants[officerCid] or {}
    grants[officerCid][citizenid .. ':' .. gType] = os.time() + minutes * 60
end

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- Tablet info by role (justice / police / attorney)
-- ════════════════════════════════════════════════════════════════════════════════════════════════

JS.RegisterCallback('NomadJustice:server:tabletInfo', nil, function(src, Player)
    local role = JS.GetRole(Player)

    if role == 'justice' then
        local allowed, err = JS.Can(Player, 'view')
        if not allowed then return { ok = false, err = err } end
        local info = H('panelInfo')(src, Player)
        info.role = 'justice'
        return info
    end

    if role == 'police' then
        if Police.RequireDuty and not Player.PlayerData.job.onduty then
            return { ok = false, err = 'You must be on duty' }
        end
        return {
            ok = true,
            role = 'police',
            perms = JS.GetPolicePermissions(Player),
            warrants = tonumber(MySQL.scalar.await("SELECT COUNT(*) FROM justice_warrants WHERE status = 'active' AND (expires_at IS NULL OR expires_at > NOW())")) or 0,
            suspects = tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM justice_suspects WHERE active = 1')) or 0,
            myPending = tonumber(MySQL.scalar.await("SELECT COUNT(*) FROM justice_police_requests WHERE officer_cid = ? AND status = 'pending'", { Player.PlayerData.citizenid })) or 0,
            finance = JS.GetFinanceSector and JS.GetFinanceSector(Player) or nil,
        }
    end

    if role == 'sector' then
        local sector, err = JS.GetFinanceSector(Player)
        if not sector then return { ok = false, err = err or 'The finance office is for department managers only' } end
        return { ok = true, role = 'sector', perms = {}, finance = sector }
    end

    if role == 'lawyer' then
        return {
            ok = true,
            role = 'lawyer',
            cases = tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM justice_case_lawyers WHERE lawyer_cid = ?', { Player.PlayerData.citizenid })) or 0,
        }
    end

    return { ok = false, err = 'State Records is for DOJ staff, police, attorneys and department managers only' }
end)

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- Search and record (police)
-- ════════════════════════════════════════════════════════════════════════════════════════════════

JS.RegisterCallback('NomadJustice:server:policeSearch', JS.PoliceOnly('search'), function(src, Player, query)
    return H('searchCitizens')(src, Player, query)
end)

local function PoliceLicenses(metadata)
    local list = {}
    for key, value in pairs(metadata.licences or metadata.licenses or {}) do
        list[#list + 1] = { label = Settings.Licenses[key] or key, active = value == true }
    end
    table.sort(list, function(a, b) return a.label < b.label end)
    return list
end

local function PoliceVehicles(citizenid)
    local tableName = Settings.Database.Vehicles
    if not tableName or not JS.TableExists(tableName) then return nil end
    local list = {}
    for i, row in ipairs(MySQL.query.await(('SELECT vehicle, plate, state FROM `%s` WHERE citizenid = ?'):format(tableName), { citizenid }) or {}) do
        local shared = QBCore.Shared.Vehicles and QBCore.Shared.Vehicles[row.vehicle]
        list[i] = {
            plate = row.plate,
            label = JS.Safe(shared and (('%s %s'):format(shared.brand or '', shared.name or row.vehicle)) or row.vehicle),
            state = ({ [0] = 'Out of garage', [1] = 'In garage', [2] = 'Impounded' })[tonumber(row.state)] or '-',
        }
    end
    return list
end

JS.RegisterCallback('NomadJustice:server:policeProfile', JS.PoliceOnly('profile'), function(src, Player, citizenid)
    citizenid = JS.ValidCitizenId(citizenid)
    if not citizenid then return { ok = false, err = 'Invalid citizen ID' } end
    local citizen = JS.GetCitizen(citizenid)
    if not citizen then return { ok = false, err = 'No citizen with this citizen ID' } end

    local perms = JS.GetPolicePermissions(Player)
    local ci, job = citizen.charinfo, citizen.job or {}
    local officerCid = Player.PlayerData.citizenid

    local cases = {}
    for i, row in ipairs(MySQL.query.await(
        'SELECT id, title, case_type, status, date, citizenid FROM justice_reports WHERE job = ? AND (citizenid = ? OR defendant_citizenid = ?) ORDER BY id DESC LIMIT 30',
        { JS.Job, citizenid, citizenid }) or {}) do
        cases[i] = {
            id = row.id, title = JS.Safe(row.title ~= '' and row.title or ('Case #' .. row.id)), caseType = row.case_type,
            status = JS.StatusLabels[row.status] or row.status, date = row.date,
            role = row.citizenid == citizenid and 'Plaintiff' or 'Defendant',
        }
    end

    local profile = {
        citizenid = citizenid,
        name = JS.FullName(ci),
        status = JS.GetStatus(citizenid, citizen.lastUpdatedRaw),
        birthdate = ci.birthdate, gender = tonumber(ci.gender), nationality = ci.nationality, phone = ci.phone,
        job = { label = JS.Safe(job.label or job.name or 'Unemployed'), grade = JS.Safe(type(job.grade) == 'table' and job.grade.name or tostring(job.grade or '-')) },
        licenses = PoliceLicenses(citizen.metadata or {}),
        suspended = JS.Suspended[citizenid] ~= nil,
        suspect = JS.GetSuspect(citizenid),
        warrants = JS.GetWarrants(citizenid, false),
        verdicts = JS.GetVerdicts(citizenid),
        cases = cases,
        vehicles = perms.vehicles and PoliceVehicles(citizenid) or nil,
    }

    -- Bank statement only with an active DOJ clearance
    local bankGrant, remaining = HasGrant(officerCid, citizenid, 'bank')
    if bankGrant then
        profile.bank = {
            bank = math.floor(tonumber(citizen.money.bank) or 0),
            cash = math.floor(tonumber(citizen.money.cash) or 0),
            remaining = math.ceil(remaining / 60),
        }
    end

    if not JS.OnCooldown('policeview', officerCid .. ':' .. citizenid, 300) then
        JS.Log(Player, 'police_view', citizenid, profile.name)
    end
    return { ok = true, profile = profile, perms = perms }
end)

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- Warrants and persons of interest (police)
-- ════════════════════════════════════════════════════════════════════════════════════════════════

JS.RegisterCallback('NomadJustice:server:policeWarrants', JS.PoliceOnly('warrants'), function(src, Player)
    return { ok = true, warrants = JS.GetWarrants(nil, true), perms = JS.GetPolicePermissions(Player) }
end)

JS.RegisterCallback('NomadJustice:server:executeWarrant', JS.PoliceOnly('executeWarrant'), function(src, Player, warrantId)
    warrantId = tonumber(warrantId)
    local row = warrantId and MySQL.single.await("SELECT * FROM justice_warrants WHERE id = ? AND status = 'active' AND (expires_at IS NULL OR expires_at > NOW())", { warrantId })
    if not row then return { ok = false, err = 'Warrant is not active' } end

    local info = JS.PoliceInfo(Player)
    local by = ('%s - %s%s'):format(info.name, info.grade, info.callsign and (' [' .. info.callsign .. ']') or '')
    local affected = MySQL.update.await("UPDATE justice_warrants SET status = 'executed', executed_by = ? WHERE id = ? AND status = 'active'", { by, warrantId })
    if not affected or affected == 0 then return { ok = false, err = 'Already executed' } end

    JS.BroadcastTablet(JS.JusticeOnDuty, { type = 'warrant', title = ('✅ %s #%d executed'):format(JS.WarrantTypes[row.type] or '', warrantId), text = ('%s (%s) by %s'):format(row.name, row.citizenid, by) })
    JS.Log(Player, 'warrant_execute', row.citizenid, row.name, { ['Warrant'] = warrantId, ['Type'] = JS.WarrantTypes[row.type] })
    return { ok = true }
end)

JS.RegisterCallback('NomadJustice:server:policeSuspects', JS.PoliceOnly('suspects'), function()
    return { ok = true, suspects = JS.GetSuspects() }
end)

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- Clearance requests (police → justice)
-- ════════════════════════════════════════════════════════════════════════════════════════════════

local function MapRequest(row)
    return {
        id = row.id,
        type = row.type,
        typeLabel = JS.RequestTypes[row.type] or row.type,
        citizenid = row.citizenid,
        name = JS.Safe(row.name),
        reason = JS.Safe(row.reason),
        details = row.details ~= '' and JS.Safe(row.details) or nil,
        officer = {
            citizenid = row.officer_cid, name = JS.Safe(row.officer_name), job = JS.Safe(row.officer_job),
            grade = JS.Safe(row.officer_grade), callsign = row.officer_callsign ~= '' and JS.Safe(row.officer_callsign) or nil,
            status = JS.GetStatus(row.officer_cid),
        },
        status = row.status,
        statusLabel = JS.RequestStatus[row.status] or row.status,
        answeredBy = row.answered_by and JS.Safe(row.answered_by) or nil,
        answerNote = row.answer_note ~= '' and JS.Safe(row.answer_note) or nil,
        date = JS.FormatDbDate(row.created_at),
        citizenStatus = JS.GetStatus(row.citizenid),
    }
end

JS.RegisterCallback('NomadJustice:server:policeRequest', JS.PoliceOnly('requests'), function(src, Player, citizenid, rType, reason, details)
    citizenid = JS.ValidCitizenId(citizenid)
    reason = JS.CleanText(reason, 200, true)
    details = JS.CleanText(details, 200, false)
    if not citizenid or not JS.RequestTypes[rType] then return { ok = false, err = 'Invalid data' } end
    if not reason or JS.Len(reason) < 5 then return { ok = false, err = 'Write a clear reason (at least 5 characters)' } end
    if not details then return { ok = false, err = 'Details are 200 characters max' } end

    local citizen = JS.GetCitizen(citizenid)
    if not citizen then return { ok = false, err = 'No citizen with this citizen ID' } end

    local blocked, remaining = JS.OnCooldown('policerequest', Player.PlayerData.citizenid, Police.RequestCooldown)
    if blocked then return { ok = false, err = ('You can send a new request in %d seconds'):format(remaining) } end

    local info = JS.PoliceInfo(Player)
    local name = JS.FullName(citizen.charinfo)
    local id = MySQL.insert.await([[
        INSERT INTO justice_police_requests (type, citizenid, name, reason, details, officer_cid, officer_name, officer_job, officer_grade, officer_callsign)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], { rType, citizenid, name, reason, details, info.citizenid, info.name, info.job, info.grade, info.callsign or '' })
    if not id then
        JS.ClearCooldown('policerequest', Player.PlayerData.citizenid)
        return { ok = false, err = 'Could not send the request' }
    end

    JS.BroadcastTablet(function(t) return JS.Can(t, 'policeRequests') == true end, {
        type = 'police_request',
        title = ('🚓 Police request #%d: %s'):format(id, JS.RequestTypes[rType]),
        text = ('From %s (%s%s) regarding %s: %s'):format(info.name, info.grade, info.callsign and (' - ' .. info.callsign) or '', name, reason),
    })
    JS.Log(Player, 'police_request', citizenid, name, { ['Type'] = JS.RequestTypes[rType], ['Reason'] = reason })
    return { ok = true, id = id }
end)

JS.RegisterCallback('NomadJustice:server:policeMyRequests', JS.PoliceOnly('requests'), function(src, Player)
    local list = {}
    for i, row in ipairs(MySQL.query.await('SELECT * FROM justice_police_requests WHERE officer_cid = ? ORDER BY id DESC LIMIT 30', { Player.PlayerData.citizenid }) or {}) do
        list[i] = MapRequest(row)
    end
    return { ok = true, requests = list }
end)

-- ═════ Justice side ═════
JS.RegisterCallback('NomadJustice:server:getPoliceRequests', 'policeRequests', function(src, Player, status)
    local rows
    if JS.RequestStatus[status] then
        rows = MySQL.query.await('SELECT * FROM justice_police_requests WHERE status = ? ORDER BY id DESC LIMIT 100', { status })
    else
        rows = MySQL.query.await("SELECT * FROM justice_police_requests ORDER BY (status = 'pending') DESC, id DESC LIMIT 100")
    end
    local list = {}
    for i, row in ipairs(rows or {}) do list[i] = MapRequest(row) end
    local pending = tonumber(MySQL.scalar.await("SELECT COUNT(*) FROM justice_police_requests WHERE status = 'pending'")) or 0
    return { ok = true, requests = list, pending = pending }
end)

JS.RegisterCallback('NomadJustice:server:answerPoliceRequest', 'policeRequests', function(src, Player, requestId, approve, note)
    requestId = tonumber(requestId)
    approve = approve == true
    note = JS.CleanText(note, 200, false) or ''
    local row = requestId and MySQL.single.await("SELECT * FROM justice_police_requests WHERE id = ? AND status = 'pending'", { requestId })
    if not row then return { ok = false, err = 'Request not found or already answered' } end

    -- Claim the request (stops two employees answering at the same time)
    local claimed = MySQL.update.await("UPDATE justice_police_requests SET status = ?, answered_by = ?, answer_note = ?, answered_at = NOW() WHERE id = ? AND status = 'pending'", {
        approve and 'approved' or 'rejected', JS.PlayerName(Player), note, requestId
    })
    if not claimed or claimed == 0 then return { ok = false, err = 'This request was already answered' } end

    local officer = QBCore.Functions.GetPlayerByCitizenId(row.officer_cid)
    local resultText = approve and 'Approved' or 'Denied'

    if approve then
        if row.type == 'locate' then
            local target = QBCore.Functions.GetPlayerByCitizenId(row.citizenid)
            local ped = target and GetPlayerPed(target.PlayerData.source) or 0
            if ped ~= 0 and officer then
                local c = GetEntityCoords(ped)
                JS.TabletEvent(officer.PlayerData.source, {
                    type = 'locate', title = ('📍 Location of %s'):format(row.name),
                    text = 'Locate request approved - marked on the map',
                    coords = { x = c.x, y = c.y, z = c.z }, label = 'Location: ' .. row.name,
                })
                resultText = 'Location sent to the officer'
            else
                resultText = target and 'The officer is offline' or 'The citizen was offline at approval time'
            end
        elseif row.type == 'bank' then
            Grant(row.officer_cid, row.citizenid, 'bank', Police.GrantMinutes)
            resultText = ('Bank statement clearance granted for %d minutes'):format(Police.GrantMinutes)
        elseif row.type == 'arrest_warrant' or row.type == 'search_warrant' then
            local requestedBy = ('%s - %s%s'):format(row.officer_name, row.officer_grade, row.officer_callsign ~= '' and (' [' .. row.officer_callsign .. ']') or '')
            local r = JS.IssueWarrant(Player, row.citizenid, row.type == 'arrest_warrant' and 'arrest' or 'search', row.reason, row.details, requestedBy)
            if not r.ok then
                MySQL.update.await("UPDATE justice_police_requests SET status = 'pending', answered_by = NULL, answer_note = '', answered_at = NULL WHERE id = ?", { requestId })
                return r
            end
            resultText = ('Warrant #%d issued'):format(r.id)
        end
    end

    if officer then
        JS.TabletEvent(officer.PlayerData.source, {
            type = 'request_answered',
            title = ('%s your request #%d (%s)'):format(approve and '✅ Approved:' or '❌ Denied:', requestId, JS.RequestTypes[row.type] or ''),
            text = (note ~= '' and ('Response: ' .. note .. ' | ') or '') .. resultText,
        })
    end

    JS.Log(Player, 'police_answer', row.citizenid, row.name, {
        ['Request'] = requestId, ['Type'] = JS.RequestTypes[row.type], ['Officer'] = row.officer_name,
        ['Decision'] = approve and 'Approved' or 'Denied', ['Note'] = note ~= '' and note or nil,
    })
    return { ok = true, message = resultText }
end)

-- Clean up expired clearances
CreateThread(function()
    while true do
        Wait(300000)
        local now = os.time()
        for officerCid, list in pairs(grants) do
            for key, expires in pairs(list) do
                if expires <= now then list[key] = nil end
            end
            if not next(list) then grants[officerCid] = nil end
        end
    end
end)
