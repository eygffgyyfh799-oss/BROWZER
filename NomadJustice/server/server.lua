local Settings = JS.Settings
local Notify = JS.Notify

local DutyHistory = {}

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- Create, update and load the database tables
-- ════════════════════════════════════════════════════════════════════════════════════════════════

local function InitDatabase()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `justice_duty_history` (
            `id` int(11) NOT NULL AUTO_INCREMENT,
            `citizenid` varchar(50) NOT NULL,
            `name` varchar(100) NOT NULL,
            `duty_status` varchar(50) NOT NULL,
            `time` varchar(50) NOT NULL,
            `timestamp` bigint(20) NOT NULL,
            `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            KEY `citizenid` (`citizenid`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])
    -- Older versions stored duty states in Arabic: convert them to the English values once
    JS.TryQuery([[UPDATE `justice_duty_history`
        SET `duty_status` = CASE WHEN `duty_status` LIKE ? THEN 'Clocked in' ELSE 'Clocked out' END
        WHERE `duty_status` NOT IN ('Clocked in', 'Clocked out')]], { '%\u{628}\u{62F}\u{623}%' })

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `justice_reports` (
            `id` int(11) NOT NULL AUTO_INCREMENT,
            `citizenid` varchar(50) NOT NULL,
            `name` varchar(100) NOT NULL,
            `phone_number` varchar(20) NOT NULL,
            `report` text NOT NULL,
            `date` varchar(50) NOT NULL,
            `job` varchar(50) NOT NULL DEFAULT 'justice',
            `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            KEY `citizenid` (`citizenid`),
            KEY `job` (`job`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])

    -- New case columns (added to old tables automatically without deleting any data)
    JS.EnsureColumn('justice_reports', 'title', "varchar(120) NOT NULL DEFAULT ''")
    JS.EnsureColumn('justice_reports', 'case_type', "varchar(50) NOT NULL DEFAULT ''")
    JS.EnsureColumn('justice_reports', 'defendant_name', "varchar(100) NOT NULL DEFAULT ''")
    JS.EnsureColumn('justice_reports', 'defendant_citizenid', "varchar(50) NOT NULL DEFAULT ''")
    JS.EnsureColumn('justice_reports', 'witnesses', 'text NULL')
    JS.EnsureColumn('justice_reports', 'evidence', 'text NULL')
    JS.EnsureColumn('justice_reports', 'status', "varchar(20) NOT NULL DEFAULT 'new'")
    JS.EnsureColumn('justice_reports', 'handled_by', "varchar(100) NOT NULL DEFAULT ''")
    JS.EnsureColumn('justice_reports', 'submitter_info', 'longtext NULL')
    JS.EnsureIndex('justice_reports', 'status')
    JS.EnsureIndex('justice_reports', 'defendant_citizenid')

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `justice_report_notes` (
            `id` int(11) NOT NULL AUTO_INCREMENT,
            `report_id` int(11) NOT NULL,
            `author_citizenid` varchar(50) NOT NULL,
            `author_name` varchar(100) NOT NULL,
            `note` text NOT NULL,
            `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            KEY `report_id` (`report_id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `justice_transactions` (
            `id` int(11) NOT NULL AUTO_INCREMENT,
            `officer_citizenid` varchar(50) NOT NULL,
            `officer_name` varchar(100) NOT NULL,
            `target_citizenid` varchar(50) NOT NULL,
            `target_name` varchar(100) NOT NULL,
            `amount` int(11) NOT NULL,
            `reason` varchar(100) NOT NULL,
            `date` varchar(50) NOT NULL,
            `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            KEY `officer_citizenid` (`officer_citizenid`),
            KEY `target_citizenid` (`target_citizenid`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])
    JS.EnsureColumn('justice_transactions', 'type', "varchar(30) NOT NULL DEFAULT 'compensation'")
    JS.TryQuery("ALTER TABLE `justice_transactions` MODIFY `reason` varchar(255) NOT NULL")
    JS.TryQuery("ALTER TABLE `justice_transactions` MODIFY `amount` bigint(20) NOT NULL")

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `justice_suspensions` (
            `id` int(11) NOT NULL AUTO_INCREMENT,
            `citizenid` varchar(50) NOT NULL,
            `name` varchar(100) NOT NULL,
            `reason` varchar(255) NOT NULL,
            `officer_citizenid` varchar(50) NOT NULL,
            `officer_name` varchar(100) NOT NULL,
            `active` tinyint(1) NOT NULL DEFAULT 1,
            `lifted_by` varchar(100) NULL,
            `lifted_at` timestamp NULL DEFAULT NULL,
            `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            KEY `citizenid` (`citizenid`),
            KEY `active` (`active`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `justice_logs` (
            `id` int(11) NOT NULL AUTO_INCREMENT,
            `officer_citizenid` varchar(50) NOT NULL,
            `officer_name` varchar(100) NOT NULL,
            `action` varchar(50) NOT NULL,
            `target_citizenid` varchar(50) NULL,
            `target_name` varchar(100) NULL,
            `details` longtext NULL,
            `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            KEY `officer_citizenid` (`officer_citizenid`),
            KEY `target_citizenid` (`target_citizenid`),
            KEY `action` (`action`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])
    JS.EnsureColumn('justice_logs', 'undo_data', 'longtext NULL')
    JS.EnsureColumn('justice_logs', 'undone_by', 'varchar(100) NULL')
    JS.EnsureColumn('justice_logs', 'undone_at', 'timestamp NULL DEFAULT NULL')

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `justice_summons` (
            `id` int(11) NOT NULL AUTO_INCREMENT,
            `citizenid` varchar(50) NOT NULL,
            `name` varchar(100) NOT NULL,
            `reason` varchar(255) NOT NULL,
            `appointment` varchar(100) NOT NULL DEFAULT '',
            `location` varchar(100) NOT NULL DEFAULT '',
            `officer_citizenid` varchar(50) NOT NULL,
            `officer_name` varchar(100) NOT NULL,
            `status` varchar(20) NOT NULL DEFAULT 'pending',
            `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            KEY `citizenid` (`citizenid`),
            KEY `status` (`status`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `justice_suspects` (
            `id` int(11) NOT NULL AUTO_INCREMENT,
            `citizenid` varchar(50) NOT NULL,
            `name` varchar(100) NOT NULL,
            `reason` varchar(255) NOT NULL,
            `danger` varchar(20) NOT NULL DEFAULT 'medium',
            `added_by` varchar(100) NOT NULL,
            `added_by_cid` varchar(50) NOT NULL,
            `active` tinyint(1) NOT NULL DEFAULT 1,
            `removed_by` varchar(100) NULL,
            `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            KEY `citizenid` (`citizenid`),
            KEY `active` (`active`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `justice_warrants` (
            `id` int(11) NOT NULL AUTO_INCREMENT,
            `type` varchar(20) NOT NULL,
            `citizenid` varchar(50) NOT NULL,
            `name` varchar(100) NOT NULL,
            `reason` varchar(255) NOT NULL,
            `place` varchar(150) NOT NULL DEFAULT '',
            `issued_by` varchar(100) NOT NULL,
            `issued_by_cid` varchar(50) NOT NULL,
            `requested_by` varchar(150) NOT NULL DEFAULT '',
            `status` varchar(20) NOT NULL DEFAULT 'active',
            `executed_by` varchar(150) NULL,
            `expires_at` timestamp NULL DEFAULT NULL,
            `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            KEY `citizenid` (`citizenid`),
            KEY `status` (`status`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `justice_police_requests` (
            `id` int(11) NOT NULL AUTO_INCREMENT,
            `type` varchar(30) NOT NULL,
            `citizenid` varchar(50) NOT NULL,
            `name` varchar(100) NOT NULL,
            `reason` varchar(255) NOT NULL,
            `details` varchar(255) NOT NULL DEFAULT '',
            `officer_cid` varchar(50) NOT NULL,
            `officer_name` varchar(100) NOT NULL,
            `officer_job` varchar(100) NOT NULL DEFAULT '',
            `officer_grade` varchar(100) NOT NULL DEFAULT '',
            `officer_callsign` varchar(50) NOT NULL DEFAULT '',
            `status` varchar(20) NOT NULL DEFAULT 'pending',
            `answered_by` varchar(100) NULL,
            `answer_note` varchar(255) NOT NULL DEFAULT '',
            `answered_at` timestamp NULL DEFAULT NULL,
            `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            KEY `status` (`status`),
            KEY `officer_cid` (`officer_cid`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `justice_case_lawyers` (
            `id` int(11) NOT NULL AUTO_INCREMENT,
            `report_id` int(11) NOT NULL,
            `lawyer_cid` varchar(50) NOT NULL,
            `lawyer_name` varchar(100) NOT NULL,
            `side` varchar(20) NOT NULL DEFAULT 'plaintiff',
            `assigned_by` varchar(100) NOT NULL,
            `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            UNIQUE KEY `report_lawyer` (`report_id`, `lawyer_cid`),
            KEY `lawyer_cid` (`lawyer_cid`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `justice_case_documents` (
            `id` int(11) NOT NULL AUTO_INCREMENT,
            `report_id` int(11) NOT NULL,
            `author_cid` varchar(50) NOT NULL,
            `author_name` varchar(100) NOT NULL,
            `author_role` varchar(20) NOT NULL DEFAULT 'justice',
            `title` varchar(120) NOT NULL,
            `content` text NOT NULL,
            `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            KEY `report_id` (`report_id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `justice_verdicts` (
            `id` int(11) NOT NULL AUTO_INCREMENT,
            `report_id` int(11) NULL,
            `citizenid` varchar(50) NOT NULL,
            `name` varchar(100) NOT NULL,
            `type` varchar(20) NOT NULL,
            `amount` bigint(20) NOT NULL DEFAULT 0,
            `target_citizenid` varchar(50) NOT NULL DEFAULT '',
            `plate` varchar(15) NOT NULL DEFAULT '',
            `months` int(11) NOT NULL DEFAULT 0,
            `text` varchar(500) NOT NULL DEFAULT '',
            `dest` varchar(100) NOT NULL DEFAULT '',
            `judge_cid` varchar(50) NOT NULL,
            `judge_name` varchar(100) NOT NULL,
            `status` varchar(20) NOT NULL DEFAULT 'active',
            `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            KEY `citizenid` (`citizenid`),
            KEY `report_id` (`report_id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `justice_sector_funds` (
            `job` varchar(50) NOT NULL,
            `balance` bigint(20) NOT NULL DEFAULT 0,
            PRIMARY KEY (`job`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `justice_sector_transactions` (
            `id` int(11) NOT NULL AUTO_INCREMENT,
            `job` varchar(50) NOT NULL,
            `type` varchar(20) NOT NULL,
            `amount` bigint(20) NOT NULL,
            `reason` varchar(150) NOT NULL,
            `officer_cid` varchar(50) NOT NULL,
            `officer_name` varchar(100) NOT NULL,
            `officer_grade` varchar(100) NOT NULL DEFAULT '',
            `balance_after` bigint(20) NULL,
            `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            KEY `job` (`job`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])

    -- Duty history
    local history = MySQL.query.await('SELECT * FROM justice_duty_history ORDER BY timestamp DESC, id DESC LIMIT ?', {
        Settings.DutyHistoryLimit
    }) or {}
    DutyHistory = {}
    for i = 1, #history do
        local row = history[i]
        DutyHistory[i] = {
            citizenid = row.citizenid,
            name = row.name,
            dutyStatus = row.duty_status,
            timeFormated = row.time,
            timestamp = row.timestamp,
        }
    end

    -- Suspended services
    local suspensions = MySQL.query.await('SELECT * FROM justice_suspensions WHERE active = 1') or {}
    for i = 1, #suspensions do
        local row = suspensions[i]
        JS.Suspended[row.citizenid] = {
            id = row.id,
            name = row.name,
            reason = row.reason,
            officer = row.officer_name,
            date = JS.FormatDbDate(row.created_at),
        }
    end

    -- Check external tables and warn if they are missing
    local db = Settings.Database
    for _, tableName in ipairs({ db.Players, db.Vehicles, db.Houses and db.Houses.table }) do
        if tableName and not JS.TableExists(tableName) then
            print(('^3[NomadJustice]^7 Table `%s` not found, related info will be hidden. Check Settings.Database in config.lua'):format(tableName))
        end
    end

    print(('^2[NomadJustice]^7 Ready: %d duty records, %d active suspensions'):format(#DutyHistory, #suspensions))
end

CreateThread(function()
    local ok, err = pcall(InitDatabase)
    if not ok then
        print(('^1[NomadJustice]^7 Database init error: %s'):format(tostring(err)))
    end
    JS.Ready = true
    TriggerEvent('NomadJustice:server:ready')
end)

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- Duty history
-- Called by the client after QBCore:ToggleDuty, and events reach the server in the same order
-- so the duty state here is the new state after toggling
-- ════════════════════════════════════════════════════════════════════════════════════════════════

RegisterNetEvent('NomadJustice:server:updateDutyHistory', function()
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not JS.HasJusticeJob(Player) then return end

    local citizenid = Player.PlayerData.citizenid
    if JS.OnCooldown('duty', citizenid, math.max(Settings.DutyCooldown - 2, 1)) then return end

    local entry = {
        citizenid = citizenid,
        name = JS.PlayerName(Player),
        dutyStatus = Player.PlayerData.job.onduty and 'Clocked in' or 'Clocked out',
        timeFormated = JS.Now(),
        timestamp = os.time(),
    }

    table.insert(DutyHistory, 1, entry)
    while #DutyHistory > Settings.DutyHistoryLimit do
        table.remove(DutyHistory)
    end

    MySQL.insert('INSERT INTO justice_duty_history (citizenid, name, duty_status, time, timestamp) VALUES (?, ?, ?, ?, ?)', {
        entry.citizenid, entry.name, entry.dutyStatus, entry.timeFormated, entry.timestamp
    })
end)

QBCore.Functions.CreateCallback('NomadJustice:server:getDutyHistory', function(source, cb)
    local Player = QBCore.Functions.GetPlayer(source)
    if not JS.IsBoss(Player) then return cb({}) end
    cb(DutyHistory)
end)

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- Compensation
-- ════════════════════════════════════════════════════════════════════════════════════════════════

RegisterNetEvent('NomadJustice:server:giveMoneyToPlayer', function(targetCitizenid, amount)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player or not JS.Ready then return end

    local allowed, err = JS.Can(Player, 'compensation')
    if not allowed then
        return Notify(src, err, 'error')
    end

    -- Chief Justice / Supreme Court Justice: no amount, daily or distance limits, and may compensate themselves
    local unlimited = JS.Can(Player, 'unlimitedCompensation') == true

    local moneyAmount = math.floor(tonumber(amount) or 0)
    if moneyAmount <= 0 or moneyAmount ~= moneyAmount then
        return Notify(src, 'The amount entered is invalid', 'error')
    end

    local maxAmount = unlimited and (tonumber(Settings.CompensationHardCap) or 2000000000) or Settings.CompensationMax
    if moneyAmount > maxAmount then
        return Notify(src, ('The amount is too large (maximum: $%d)'):format(maxAmount), 'error')
    end

    targetCitizenid = JS.ValidCitizenId(targetCitizenid)
    if not targetCitizenid then
        return Notify(src, 'Invalid citizen ID', 'error')
    end

    local TargetPlayer = QBCore.Functions.GetPlayerByCitizenId(targetCitizenid)
    if not TargetPlayer then
        return Notify(src, 'The player is offline or the citizen ID is invalid', 'error')
    end

    local targetSrc = TargetPlayer.PlayerData.source
    local isSelf = targetSrc == src
    if isSelf and not unlimited then
        return Notify(src, 'You cannot compensate yourself', 'error')
    end

    -- Server-side check that the recipient is really near the employee
    if not unlimited then
        local officerPed, targetPed = GetPlayerPed(src), GetPlayerPed(targetSrc)
        if officerPed == 0 or targetPed == 0
            or #(GetEntityCoords(officerPed) - GetEntityCoords(targetPed)) > Settings.CompensationMaxDistance then
            return Notify(src, 'The recipient must be near you', 'error')
        end
    end

    local blocked, remaining = JS.OnCooldown('compensation', Player.PlayerData.citizenid, Settings.CompensationCooldown)
    if blocked then
        return Notify(src, ('You must wait %d seconds'):format(remaining), 'error')
    end

    -- Daily limit per employee
    local todayTotal = 0
    if not unlimited then todayTotal = tonumber(MySQL.scalar.await(
        "SELECT COALESCE(SUM(amount), 0) FROM justice_transactions WHERE officer_citizenid = ? AND type = 'compensation' AND created_at >= CURDATE()",
        { Player.PlayerData.citizenid })) or 0 end
    if not unlimited and todayTotal + moneyAmount > Settings.CompensationDailyMax then
        return Notify(src, ('You reached the daily compensation limit (remaining today: $%d)'):format(math.max(0, Settings.CompensationDailyMax - todayTotal)), 'error', 7000)
    end

    if not TargetPlayer.Functions.AddMoney('bank', moneyAmount, 'justice-compensation') then
        return Notify(src, 'Could not transfer the amount', 'error')
    end

    local officerName = JS.PlayerName(Player)
    local targetName = JS.PlayerName(TargetPlayer)

    Notify(src, ('$%d transferred to %s successfully'):format(moneyAmount, targetName), 'success')
    if not isSelf then Notify(targetSrc, ('$%d was transferred to your bank account by the Department of Justice - officer: %s'):format(moneyAmount, officerName), 'success', 7000) end

    MySQL.insert.await('INSERT INTO justice_transactions (officer_citizenid, officer_name, target_citizenid, target_name, amount, reason, date, type) VALUES (?, ?, ?, ?, ?, ?, ?, ?)', {
        Player.PlayerData.citizenid, officerName, targetCitizenid, targetName, moneyAmount, isSelf and 'Compensation (self)' or 'Compensation', JS.Now(), 'compensation'
    })
    JS.Log(Player, 'compensation', targetCitizenid, targetName, { ['Amount'] = moneyAmount, ['Self'] = isSelf and 'Yes' or nil }, { amount = moneyAmount })
end)

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- Lockers and evidence archive (deep-inventory)
-- The server checks the job/grade and opens the stash; inventories without a server export fall back to the client event
-- ════════════════════════════════════════════════════════════════════════════════════════════════

RegisterNetEvent('NomadJustice:server:openStash', function(kind, archiveId)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player or not JS.IsJustice(Player) then return end

    local stashId, data
    if kind == 'personal' then
        stashId = 'justice_stash_' .. Player.PlayerData.citizenid
        data = { label = 'Personal Locker', maxweight = Settings.PersonalStash.maxweight, slots = Settings.PersonalStash.slots }
    elseif kind == 'archive' then
        if not JS.IsBoss(Player) then return Notify(src, 'The evidence archive is for management only', 'error') end
        archiveId = math.floor(tonumber(archiveId) or 0)
        if archiveId < 1 or archiveId > 999999999 then return Notify(src, 'Invalid archive ID', 'error') end
        stashId = 'justice_archive_' .. archiveId
        data = { label = 'Evidence Archive #' .. archiveId, maxweight = Settings.ArchiveStash.maxweight, slots = Settings.ArchiveStash.slots }
    else
        return
    end

    local inv = Settings.InventoryResource or 'deep-inventory'
    if GetResourceState(inv) == 'started' then
        local ok = pcall(function() exports[inv]:OpenInventory(src, stashId, data) end)
        if ok then return end
    end
    TriggerClientEvent('NomadJustice:client:openStashLegacy', src, stashId, data)
end)

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- Clean up old records (on start, then every 24 hours)
-- ════════════════════════════════════════════════════════════════════════════════════════════════

local function CleanupOldData()
    local cleanup = Settings.Cleanup or {}
    local removed = 0

    local logsDays = tonumber(cleanup.LogsDays) or 0
    if logsDays > 0 then
        removed = removed + (MySQL.update.await('DELETE FROM justice_logs WHERE created_at < NOW() - INTERVAL ? DAY', { logsDays }) or 0)
    end

    local dutyDays = tonumber(cleanup.DutyDays) or 0
    if dutyDays > 0 then
        removed = removed + (MySQL.update.await('DELETE FROM justice_duty_history WHERE timestamp < ?', { os.time() - dutyDays * 86400 }) or 0)
    end

    local reportDays = tonumber(cleanup.ClosedReportsDays) or 0
    if reportDays > 0 then
        removed = removed + (MySQL.update.await(
            "DELETE FROM justice_report_notes WHERE report_id IN (SELECT id FROM (SELECT id FROM justice_reports WHERE status = 'closed' AND created_at < NOW() - INTERVAL ? DAY) AS old)",
            { reportDays }) or 0)
        removed = removed + (MySQL.update.await("DELETE FROM justice_reports WHERE status = 'closed' AND created_at < NOW() - INTERVAL ? DAY", { reportDays }) or 0)
    end

    if removed > 0 then
        print(('^2[NomadJustice]^7 Cleanup removed %d old records'):format(removed))
    end
end

CreateThread(function()
    while not JS.Ready do Wait(1000) end
    while true do
        local ok, err = pcall(CleanupOldData)
        if not ok then print(('^1[NomadJustice]^7 Cleanup failed: %s'):format(tostring(err))) end
        Wait(24 * 60 * 60 * 1000)
    end
end)
