-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- Shared server helpers (loaded first)
-- ════════════════════════════════════════════════════════════════════════════════════════════════

-- [security] every number from a player goes through tonumber: reject NaN and inf
-- (math.floor(NaN) = NaN passes the "amount <= 0" check and reaches money code)
local rawtonumber = tonumber
function tonumber(value, base)
    local n
    if base then n = rawtonumber(value, base) else n = rawtonumber(value) end
    if n and (n ~= n or n == math.huge or n == -math.huge) then return nil end
    return n
end

JS = {}
JS.Config = LoadConfig()
JS.Settings = JS.Config.Settings
JS.Job = JS.Settings.Job
JS.Ready = false
JS.Suspended = {}

local Settings = JS.Settings
local schemaCache = {}

JS.StatusLabels = { new = 'New', review = 'Under Review', closed = 'Closed' }

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- Text and formatting
-- ════════════════════════════════════════════════════════════════════════════════════════════════

function JS.Notify(src, msg, msgType, length)
    msgType, length = msgType or 'primary', length or 5000
    local ok = pcall(QBCore.Functions.Notify, src, msg, msgType, length)
    if not ok then
        TriggerClientEvent('NomadJustice:client:notify', src, msg, msgType, length)
    end
end

function JS.Now()
    return os.date('%d/%m/%Y %H:%M', os.time())
end

function JS.Len(str)
    return utf8.len(str) or #str
end

-- Blocks HTML and Markdown injection (e.g. external images that leak staff IPs when a list is opened)
function JS.Safe(str)
    if type(str) ~= 'string' then return str end
    str = str:gsub('[<>]', ''):gsub('!%[', '['):gsub('%]%(', '] ('):gsub('`', "'")
    return str
end

-- Cleans text: removes extra spaces, control characters and < >
-- Returns nil if the text is invalid or longer than the limit
function JS.CleanText(value, maxLen, required)
    if value == nil then
        return (not required) and '' or nil
    end
    if type(value) ~= 'string' and type(value) ~= 'number' then return nil end

    local str = JUtil.Functions.trim(tostring(value)) or ''
    if not utf8.len(str) then return nil end -- broken text (invalid UTF-8)
    str = JS.Safe(str:gsub('[\0-\9\11-\31]', ''))
    if required and str == '' then return nil end
    if maxLen and JS.Len(str) > maxLen then return nil end
    return str
end

-- Cut text by character count without breaking multi-byte characters
function JS.Truncate(str, maxChars)
    local ok, cut = pcall(utf8.offset, str, maxChars + 1)
    if ok and cut then return str:sub(1, cut - 1) end
    return str
end

function JS.ValidCitizenId(cid)
    if type(cid) ~= 'string' and type(cid) ~= 'number' then return nil end
    cid = JUtil.Functions.trim(tostring(cid))
    if not cid or cid == '' or #cid > 50 or not cid:match('^[%w_%-]+$') then return nil end
    return cid
end

function JS.Decode(value)
    if type(value) == 'table' then return value end
    if type(value) ~= 'string' or value == '' then return {} end
    local ok, result = pcall(json.decode, value)
    return (ok and type(result) == 'table') and result or {}
end

function JS.FullName(charinfo)
    charinfo = charinfo or {}
    local name = ('%s %s'):format(tostring(charinfo.firstname or ''), tostring(charinfo.lastname or ''))
    return JS.Safe((name:gsub('^%s+', ''):gsub('%s+$', '')))
end

function JS.PlayerName(Player)
    return JS.FullName(Player.PlayerData.charinfo)
end

-- oxmysql returns dates as numbers (milliseconds)
function JS.FormatDbDate(value)
    if type(value) == 'number' then
        return os.date('%d/%m/%Y %H:%M', math.floor(value / 1000))
    end
    return value and tostring(value) or nil
end

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- Connection status: online / offline + since when
-- ════════════════════════════════════════════════════════════════════════════════════════════════

local joinTimes = {}   -- [source] = join time
local lastSeen = {}    -- [citizenid] = leave time (during the current server run)

AddEventHandler('playerJoining', function()
    joinTimes[source] = os.time()
end)

AddEventHandler('playerDropped', function()
    local src = source
    joinTimes[src] = nil
    local ok, Player = pcall(QBCore.Functions.GetPlayer, src)
    if ok and Player and Player.PlayerData then
        lastSeen[Player.PlayerData.citizenid] = os.time()
    end
end)

-- "1 minute" / "5 minutes"
local function Plural(n, unit)
    return ('%d %s%s'):format(n, unit, n == 1 and '' or 's')
end

function JS.Ago(seconds)
    seconds = math.max(0, math.floor(tonumber(seconds) or 0))
    if seconds < 60 then return 'just now' end
    local minutes = math.floor(seconds / 60)
    if minutes < 60 then return Plural(minutes, 'minute') .. ' ago' end
    local hours = math.floor(minutes / 60)
    if hours < 24 then return Plural(hours, 'hour') .. ' ago' end
    local days = math.floor(hours / 24)
    if days < 30 then return Plural(days, 'day') .. ' ago' end
    local months = math.floor(days / 30)
    if months < 12 then return Plural(months, 'month') .. ' ago' end
    return Plural(math.floor(months / 12), 'year') .. ' ago'
end

-- lastUpdated: last_updated value from the players table (milliseconds) if present
-- Returns { online, serverId, text }
function JS.GetStatus(citizenid, lastUpdated)
    local Player = QBCore.Functions.GetPlayerByCitizenId(citizenid)
    if Player then
        local src = Player.PlayerData.source
        local joined = joinTimes[src]
        return {
            online = true,
            serverId = src,
            text = ('🟢 Online now [%d]%s'):format(src, joined and (' - joined ' .. JS.Ago(os.time() - joined)) or ''),
        }
    end

    local seen = lastSeen[citizenid]
    if not seen and type(lastUpdated) == 'number' then
        seen = math.floor(lastUpdated / 1000)
    end
    return {
        online = false,
        text = seen and ('⚫ Offline - last seen ' .. JS.Ago(os.time() - seen)) or '⚫ Offline',
    }
end

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- Permissions
-- ════════════════════════════════════════════════════════════════════════════════════════════════

function JS.GetGrade(Player)
    local grade = Player.PlayerData.job.grade
    return tonumber(type(grade) == 'table' and grade.level or grade) or 0
end

-- Owner citizen IDs (Settings.Panel.OwnerCitizenIds): full access to everything, whatever their job or grade,
-- and allowed to act on their own record (to test on themselves)
function JS.IsOwner(Player)
    local cid = Player and Player.PlayerData and Player.PlayerData.citizenid
    if not cid then return false end
    for _, owner in ipairs(Settings.Panel.OwnerCitizenIds or {}) do
        if tostring(owner) == cid then return true end
    end
    return false
end

-- Holds the DOJ job (owners excluded)
function JS.HasJusticeJob(Player)
    return Player ~= nil and Player.PlayerData.job ~= nil and Player.PlayerData.job.name == JS.Job
end

function JS.IsJustice(Player)
    return JS.HasJusticeJob(Player) or JS.IsOwner(Player)
end

-- Blocks actions on your own record, except for owners
function JS.SelfBlocked(Player, citizenid)
    return citizenid == Player.PlayerData.citizenid and not JS.IsOwner(Player)
end

-- Has a phone item: required to locate someone
function JS.HasPhone(Player)
    local list = Settings.Panel.PhoneItems or { 'phone' }
    if #list == 0 then return true end
    for _, name in ipairs(list) do
        local ok, item = pcall(Player.Functions.GetItemByName, name)
        if ok and item and (tonumber(item.amount) or 1) > 0 then return true end
    end
    for _, item in pairs(Player.PlayerData.items or {}) do
        for _, name in ipairs(list) do
            if type(item) == 'table' and item.name == name and (tonumber(item.amount) or 1) > 0 then return true end
        end
    end
    return false
end

-- Manager, or the full access grade (FullAccessGrade) and above
function JS.IsBoss(Player)
    if JS.IsOwner(Player) then return true end
    if not JS.IsJustice(Player) then return false end
    if Player.PlayerData.job.isboss == true then return true end
    local fullAccess = tonumber(Settings.Panel.FullAccessGrade)
    return fullAccess ~= nil and JS.GetGrade(Player) >= fullAccess
end

function JS.Can(Player, action)
    if not JS.IsJustice(Player) then
        return false, 'You must be a Department of Justice employee'
    end

    local required = Settings.Panel.Permissions[action]
    if JS.IsOwner(Player) then
        if required == nil then return false, 'Unknown permission' end
        return true
    end

    local job = Player.PlayerData.job
    if Settings.Panel.RequireDuty and not job.onduty then
        return false, 'You must be on duty'
    end

    if required == nil then return false, 'Unknown permission' end
    if required == false then return false, 'This permission is disabled' end

    -- Full access grade (judge) = everything
    local fullAccess = tonumber(Settings.Panel.FullAccessGrade)
    local grade = JS.GetGrade(Player)
    if fullAccess and grade >= fullAccess then return true end

    -- 'boss' = grades flagged isboss | number = that grade and above only
    if required == 'boss' then
        if job.isboss then return true end
        return false, 'This permission is for management only'
    end
    if grade < (tonumber(required) or 0) then
        return false, 'Your grade does not allow this action'
    end
    return true
end

function JS.GetPermissions(Player)
    local perms = {}
    for action in pairs(Settings.Panel.Permissions) do
        perms[action] = JS.Can(Player, action) == true
    end
    return perms
end

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- Roles: Justice / Police / Attorney
-- ════════════════════════════════════════════════════════════════════════════════════════════════

local function InList(list, value)
    for _, v in ipairs(list or {}) do
        if v == value then return true end
    end
    return false
end

function JS.IsPolice(Player)
    local job = Player and Player.PlayerData.job
    return job ~= nil and InList(Settings.Police.Jobs, job.name)
end

-- The judge (full access grade) has full access to the whole state system
function JS.IsJudge(Player)
    local full = tonumber(Settings.Panel.FullAccessGrade)
    if JS.IsOwner(Player) then return true end
    return JS.HasJusticeJob(Player) and full ~= nil and JS.GetGrade(Player) >= full
end

function JS.CanPolice(Player, action)
    if JS.IsJudge(Player) then
        if Settings.Panel.RequireDuty and not JS.IsOwner(Player) and not Player.PlayerData.job.onduty then return false, 'You must be on duty' end
        if Settings.Police.Permissions[action] == nil then return false, 'Unknown permission' end
        return true
    end
    if not JS.IsPolice(Player) then return false, 'This section is for police only' end
    local job = Player.PlayerData.job
    if Settings.Police.RequireDuty and not job.onduty then return false, 'You must be on duty' end
    local required = Settings.Police.Permissions[action]
    if required == nil or required == false then return false, 'This permission is not available to police' end
    if required == 'boss' then
        if job.isboss then return true end
        return false, 'This permission is for police officers only'
    end
    if JS.GetGrade(Player) < (tonumber(required) or 0) then return false, 'Your grade does not allow this action' end
    return true
end

function JS.GetPolicePermissions(Player)
    local perms = {}
    for action in pairs(Settings.Police.Permissions) do
        perms[action] = JS.CanPolice(Player, action) == true
    end
    return perms
end

-- Returns a check function used with JS.RegisterCallback
function JS.PoliceOnly(action)
    return function(Player) return JS.CanPolice(Player, action) end
end

-- Attorney: holds a law license or has one of the attorney jobs
function JS.HasLawyerLicense(metadata, job)
    local licenses = metadata and (metadata.licences or metadata.licenses) or {}
    if licenses[Settings.Lawyers.License] == true then return true end
    return job ~= nil and InList(Settings.Lawyers.Jobs, job.name)
end

function JS.IsLawyer(Player)
    return Player ~= nil and JS.HasLawyerLicense(Player.PlayerData.metadata, Player.PlayerData.job)
end

function JS.GetRole(Player)
    if JS.IsJustice(Player) then return 'justice' end
    if JS.IsPolice(Player) then return 'police' end
    if JS.IsLawyer(Player) then return 'lawyer' end
    if JS.GetFinanceSector and JS.GetFinanceSector(Player, true) then return 'sector' end
    return nil
end

function JS.PoliceInfo(Player)
    local job, md = Player.PlayerData.job or {}, Player.PlayerData.metadata or {}
    return {
        citizenid = Player.PlayerData.citizenid,
        name = JS.PlayerName(Player),
        job = JS.Safe(job.label or job.name or '-'),
        grade = JS.Safe(type(job.grade) == 'table' and job.grade.name or tostring(job.grade or '-')),
        callsign = md.callsign and JS.Safe(tostring(md.callsign)) or nil,
    }
end

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- Live tablet notifications (sound when the tablet is open, normal notification when closed)
-- event = { type, title, text, coords? }
-- ════════════════════════════════════════════════════════════════════════════════════════════════

function JS.TabletEvent(src, event)
    TriggerClientEvent('NomadJustice:client:tabletEvent', src, event)
end

function JS.BroadcastTablet(filter, event)
    for _, playerId in pairs(QBCore.Functions.GetPlayers()) do
        local target = QBCore.Functions.GetPlayer(playerId)
        if target and filter(target) then JS.TabletEvent(playerId, event) end
    end
end

function JS.JusticeOnDuty(target)
    return JS.IsOwner(target) or (JS.HasJusticeJob(target) and target.PlayerData.job.onduty == true)
end

function JS.PoliceOnDuty(target)
    return JS.IsPolice(target) and target.PlayerData.job.onduty == true
end

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- Moving money (bank) for online and offline citizens
-- ════════════════════════════════════════════════════════════════════════════════════════════════

function JS.GetBank(citizenid)
    local target = QBCore.Functions.GetPlayerByCitizenId(citizenid)
    if target then return math.floor(tonumber(target.PlayerData.money.bank) or 0) end
    local row = JS.GetPlayerRow(citizenid)
    return row and math.floor(tonumber(JS.OfflineMoney(row).bank) or 0) or nil
end

-- Takes from the citizen's bank (refuses if the balance is not enough)
-- Deduct from an online player's bank by DOJ order
function JS.RemoveBank(target, amount, reason)
    local ok, removed = pcall(target.Functions.RemoveMoney, 'bank', amount, reason)
    return ok and removed ~= false
end

function JS.TakeMoney(citizenid, amount, reason)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return false, 'Invalid amount' end
    local target = QBCore.Functions.GetPlayerByCitizenId(citizenid)
    if target then
        if (tonumber(target.PlayerData.money.bank) or 0) < amount then return false, 'Insufficient balance' end
        if not JS.RemoveBank(target, amount, reason) then return false, 'Could not withdraw' end
        return true
    end
    local row = JS.GetPlayerRow(citizenid)
    if not row then return false, 'Citizen not found' end
    local money = JS.OfflineMoney(row)
    local bank = tonumber(money.bank) or 0
    if bank < amount then return false, 'Insufficient balance' end
    money.bank = bank - amount
    if not JS.UpdatePlayerJson(citizenid, 'money', money, row.money) then return false, 'Citizen data changed, try again' end
    return true
end

-- Adds to the citizen's bank
function JS.GiveMoney(citizenid, amount, reason)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return false, 'Invalid amount' end
    local target = QBCore.Functions.GetPlayerByCitizenId(citizenid)
    if target then
        if not target.Functions.AddMoney('bank', amount, reason) then return false, 'Could not deposit' end
        return true
    end
    local row = JS.GetPlayerRow(citizenid)
    if not row then return false, 'Citizen not found' end
    local money = JS.OfflineMoney(row)
    money.bank = (tonumber(money.bank) or 0) + amount
    if not JS.UpdatePlayerJson(citizenid, 'money', money, row.money) then return false, 'Citizen data changed, try again' end
    return true
end

-- Where seized money goes (WithdrawTo) - returns the destination for undo
function JS.DepositWithdrawn(Player, amount, reason)
    local to = Settings.Panel.WithdrawTo
    if to == 'officer' and Player then
        local ok = JS.GiveMoney(Player.PlayerData.citizenid, amount, reason)
        if ok then
            JS.Notify(Player.PlayerData.source, ('$%d has been deposited to your account'):format(amount), 'success')
            return { to = 'officer', cid = Player.PlayerData.citizenid }
        end
    elseif to == 'society' then
        JS.AddSocietyMoney(amount, reason)
        return { to = 'society' }
    end
    return { to = 'none' }
end

-- Reverse of DepositWithdrawn (for undo): takes the amount back from the officer who received it
function JS.ReverseDeposit(dest, amount)
    if type(dest) ~= 'table' or dest.to ~= 'officer' or not dest.cid then return true end
    local ok, err = JS.TakeMoney(dest.cid, amount, 'justice-undo')
    if not ok then return false, 'The officer who received the money does not have enough to return it (' .. tostring(err) .. ')' end
    return true
end

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- Cooldowns and duplicate protection
-- ════════════════════════════════════════════════════════════════════════════════════════════════

local cooldowns = {}
local throttles = {}

-- Returns true and the remaining time while on cooldown, otherwise starts a new one
function JS.OnCooldown(kind, key, seconds)
    cooldowns[kind] = cooldowns[kind] or {}
    local now = os.time()
    local expires = cooldowns[kind][key]
    if expires and expires > now then
        return true, expires - now
    end
    cooldowns[kind][key] = now + seconds
    return false
end

function JS.ClearCooldown(kind, key)
    if cooldowns[kind] then cooldowns[kind][key] = nil end
end

function JS.Throttle(src, name, ms)
    throttles[src] = throttles[src] or {}
    local now = GetGameTimer()
    local last = throttles[src][name]
    if last and now - last < ms then return true end
    throttles[src][name] = now
    return false
end

-- Global limit: 25 requests per 5 seconds per player (prevents flooding the server and database)
local floods = {}

function JS.Flooding(src)
    local now = GetGameTimer()
    local f = floods[src]
    if not f or now - f.start > 5000 then
        floods[src] = { start = now, count = 1 }
        return false
    end
    f.count = f.count + 1
    if f.count == 26 then
        print(('^3[NomadJustice] ⚠ Player [%d] sent too many requests (possible tampering)^7'):format(src))
    end
    return f.count > 25
end

AddEventHandler('playerDropped', function()
    throttles[source] = nil
    floods[source] = nil
end)

CreateThread(function()
    while true do
        Wait(600000)
        local now = os.time()
        for _, list in pairs(cooldowns) do
            for key, expires in pairs(list) do
                if expires <= now then list[key] = nil end
            end
        end
    end
end)

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- Safe callbacks: check readiness and permission and catch errors
-- Every callback returns { ok = true, ... } or { ok = false, err = '...' }
-- ════════════════════════════════════════════════════════════════════════════════════════════════

-- Every action is registered here so undo reuses the same code with the same checks
JS.Handlers = {}

function JS.RegisterCallback(name, action, handler)
    JS.Handlers[name] = handler
    QBCore.Functions.CreateCallback(name, function(source, cb, ...)
        local src = source

        if not JS.Ready then
            return cb({ ok = false, err = 'The system is still loading, try again shortly' })
        end
        if JS.Throttle(src, name, 300) then
            return cb({ ok = false, err = 'Please wait a moment' })
        end
        if JS.Flooding(src) then
            return cb({ ok = false, err = 'Too many requests, wait a few seconds' })
        end

        local Player = QBCore.Functions.GetPlayer(src)
        if not Player then
            return cb({ ok = false, err = 'Could not find your character data' })
        end

        if action then
            local allowed, err
            if type(action) == 'function' then
                allowed, err = action(Player)
            else
                allowed, err = JS.Can(Player, action)
            end
            if not allowed then
                -- An attempt from someone with no role is usually tampering (executor)
                if not JS.GetRole(Player) then
                    print(('^3[NomadJustice] ⚠ Unauthorized attempt: %s [%d] (%s) → %s^7'):format(
                        JS.PlayerName(Player), src, Player.PlayerData.citizenid, name))
                end
                return cb({ ok = false, err = err or 'Not allowed' })
            end
        end

        local success, result = pcall(handler, src, Player, ...)
        if not success then
            print(('^1[NomadJustice] %s error: %s^7'):format(name, tostring(result)))
            return cb({ ok = false, err = 'An unexpected error occurred' })
        end

        cb(result or { ok = true })
    end)
end

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- Database
-- ════════════════════════════════════════════════════════════════════════════════════════════════

function JS.SafeIdentifier(name)
    return type(name) == 'string' and name:match('^[%w_]+$') ~= nil
end

function JS.TableExists(tableName)
    if not JS.SafeIdentifier(tableName) then return false end
    local key = 't:' .. tableName
    if schemaCache[key] == nil then
        local count = MySQL.scalar.await(
            'SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ?',
            { tableName })
        schemaCache[key] = (tonumber(count) or 0) > 0
    end
    return schemaCache[key]
end

function JS.ColumnExists(tableName, column)
    if not JS.SafeIdentifier(tableName) or not JS.SafeIdentifier(column) then return false end
    local key = ('c:%s.%s'):format(tableName, column)
    if schemaCache[key] == nil then
        local count = MySQL.scalar.await(
            'SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?',
            { tableName, column })
        schemaCache[key] = (tonumber(count) or 0) > 0
    end
    return schemaCache[key]
end

-- Run a schema update query without stopping startup if it fails
function JS.TryQuery(query, params)
    local ok, err = pcall(MySQL.query.await, query, params)
    if not ok then
        print(('^3[NomadJustice]^7 DB step skipped: %s'):format(tostring(err)))
    end
    return ok
end

function JS.EnsureColumn(tableName, column, definition)
    if JS.ColumnExists(tableName, column) then return end
    if JS.TryQuery(('ALTER TABLE `%s` ADD COLUMN `%s` %s'):format(tableName, column, definition)) then
        schemaCache[('c:%s.%s'):format(tableName, column)] = true
        print(('^3[NomadJustice]^7 Added column %s.%s'):format(tableName, column))
    end
end

-- Light columns from the players table (without the heavy inventory) + last_updated if present
function JS.PlayerListColumns()
    local cols = 'citizenid, charinfo, job'
    if JS.ColumnExists(Settings.Database.Players, 'last_updated') then
        cols = cols .. ', last_updated'
    end
    return cols
end

function JS.EnsureIndex(tableName, column)
    if not JS.SafeIdentifier(tableName) or not JS.SafeIdentifier(column) then return end
    local count = MySQL.scalar.await(
        'SELECT COUNT(*) FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?',
        { tableName, column })
    if (tonumber(count) or 0) == 0 then
        JS.TryQuery(('ALTER TABLE `%s` ADD INDEX `idx_%s` (`%s`)'):format(tableName, column, column))
    end
end

-- Safely update a JSON column for an offline citizen:
-- makes sure the data did not change meanwhile, and counts it as success if the new value equals the old
local PlayerJsonColumns = { money = true, charinfo = true, job = true, gang = true, metadata = true }

-- Money of an offline player (from the database row)
function JS.OfflineMoney(row)
    return JS.Decode(row.money)
end

function JS.UpdatePlayerJson(citizenid, column, newValue, oldRaw)
    if not PlayerJsonColumns[column] then return false end
    local encoded = json.encode(newValue)
    if encoded == oldRaw then return true end

    local tableName = Settings.Database.Players
    local affected = MySQL.update.await(('UPDATE `%s` SET `%s` = ? WHERE citizenid = ? AND `%s` = ?'):format(tableName, column, column), {
        encoded, citizenid, oldRaw
    })
    if affected and affected > 0 then return true end

    -- Some databases return 0 when the value did not actually change
    local current = MySQL.scalar.await(('SELECT `%s` FROM `%s` WHERE citizenid = ?'):format(column, tableName), { citizenid })
    return current == encoded
end

function JS.GetPlayerRow(citizenid)
    local tableName = Settings.Database.Players
    if not JS.TableExists(tableName) then return nil end
    return MySQL.single.await(('SELECT * FROM `%s` WHERE citizenid = ? LIMIT 1'):format(tableName), { citizenid })
end

-- Returns citizen data whether online or offline
-- { online = Player|nil, citizenid, charinfo, money, job, gang, metadata, items, lastUpdated }
function JS.GetCitizen(citizenid)
    local Player = QBCore.Functions.GetPlayerByCitizenId(citizenid)
    if Player then
        local pd = Player.PlayerData
        return {
            online = Player,
            citizenid = pd.citizenid,
            charinfo = pd.charinfo or {},
            money = pd.money or {},
            job = pd.job or {},
            gang = pd.gang or {},
            metadata = pd.metadata or {},
            items = pd.items or {},
        }
    end

    local row = JS.GetPlayerRow(citizenid)
    if not row then return nil end
    return {
        citizenid = row.citizenid,
        charinfo = JS.Decode(row.charinfo),
        money = JS.OfflineMoney(row),
        job = JS.Decode(row.job),
        gang = JS.Decode(row.gang),
        metadata = JS.Decode(row.metadata),
        items = JS.Decode(row.inventory),
        lastUpdated = JS.FormatDbDate(row.last_updated),
        lastUpdatedRaw = row.last_updated,
        raw = row,
    }
end

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- Logs (database + optional Discord)
-- Put in server.cfg:  set justice_webhook "https://discord.com/api/webhooks/..."
-- ════════════════════════════════════════════════════════════════════════════════════════════════

JS.ActionLabels = {
    view = 'Viewed citizen record',
    locate = 'Located citizen',
    withdraw = 'Bank seizure',
    suspend = 'Service suspension',
    unsuspend = 'Suspension lifted',
    edit = 'Identity edited',
    compensation = 'Compensation',
    report_status = 'Case status changed',
    report_note = 'Case note',
    report_delete = 'Case deleted',
    job = 'Job changed',
    duty = 'Employee duty changed',
    vehicle_impound = 'Vehicle impounded',
    vehicle_release = 'Vehicle released',
    vehicle_transfer = 'Vehicle title transferred',
    property_transfer = 'Property deed transferred',
    license_grant = 'License granted',
    license_revoke = 'License revoked',
    gang = 'Gang changed',
    summon = 'Court summons',
    announce = 'City announcement',
    log_delete = 'Log entry deleted',
    undo = 'Action undone',
    verdict = 'Verdict issued',
    suspect_add = 'Person of interest added',
    suspect_remove = 'Person of interest removed',
    warrant_issue = 'Warrant issued',
    warrant_cancel = 'Warrant cancelled',
    warrant_execute = 'Warrant executed (police)',
    lawyer_assign = 'Attorney assigned',
    lawyer_remove = 'Attorney removed',
    police_request = 'Clearance request (police)',
    police_answer = 'Police request answered',
    police_view = 'Officer viewed record',
    sector_deposit = 'Department deposit',
    sector_withdraw = 'Department withdrawal',
    summon_delete = 'Summons deleted',
}

local webhook = GetConvar('justice_webhook', '')

-- undo: data needed to reverse the action (nil = cannot be undone)
function JS.Log(Player, action, targetCitizenid, targetName, details, undo)
    local officerCid = Player and Player.PlayerData.citizenid or 'system'
    local officerName = Player and JS.PlayerName(Player) or 'system'
    local encoded = details and json.encode(details) or nil

    MySQL.insert('INSERT INTO justice_logs (officer_citizenid, officer_name, action, target_citizenid, target_name, details, undo_data) VALUES (?, ?, ?, ?, ?, ?, ?)', {
        officerCid, officerName, action, targetCitizenid, targetName, encoded, undo and json.encode(undo) or nil
    })

    if webhook == '' or (Settings.Panel.WebhookSkip or {})[action] then return end

    local lines = {
        ('**Officer:** %s (%s)'):format(officerName, officerCid),
    }
    if targetCitizenid then
        lines[#lines + 1] = ('**Citizen:** %s (%s)'):format(targetName or '-', targetCitizenid)
    end
    for key, value in pairs(details or {}) do
        lines[#lines + 1] = ('**%s:** %s'):format(key, type(value) == 'table' and json.encode(value) or tostring(value))
    end

    JS.QueueWebhook({
        title = JS.ActionLabels[action] or action,
        description = JS.Truncate(table.concat(lines, '\n'), 3900),
        color = 13280380,
        timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ'),
    })
end

-- Discord queue: one message every 1.5 seconds so the webhook is not rate limited
local webhookQueue = {}

function JS.QueueWebhook(embed)
    if #webhookQueue >= 200 then table.remove(webhookQueue, 1) end
    webhookQueue[#webhookQueue + 1] = embed
end

CreateThread(function()
    if webhook == '' then return end
    while true do
        local embed = table.remove(webhookQueue, 1)
        if embed then
            PerformHttpRequest(webhook, function(status)
                if status == 429 then table.insert(webhookQueue, 1, embed) end
            end, 'POST', json.encode({ username = 'NomadJustice', embeds = { embed } }), { ['Content-Type'] = 'application/json' })
        end
        Wait(embed and 1500 or 1000)
    end
end)

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- Department society account (optional)
-- ════════════════════════════════════════════════════════════════════════════════════════════════

function JS.AddSocietyMoney(amount, reason)
    local society = Settings.Panel.Society
    if not society or not society.enabled then return end
    local ok, err = pcall(function()
        local resource = exports[society.resource]
        resource[society.func](resource, JS.Job, amount, reason)
    end)
    if not ok then
        print(('^1[NomadJustice]^7 Society deposit failed: %s'):format(tostring(err)))
    end
end

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- Service suspension - exports for other scripts
-- exports['NomadJustice']:IsCitizenSuspended(citizenid) -> boolean
-- exports['NomadJustice']:GetCitizenSuspension(citizenid) -> { reason, officer, date } | nil
-- ════════════════════════════════════════════════════════════════════════════════════════════════

exports('IsCitizenSuspended', function(citizenid)
    return JS.Suspended[tostring(citizenid)] ~= nil
end)

exports('GetCitizenSuspension', function(citizenid)
    return JS.Suspended[tostring(citizenid)]
end)
