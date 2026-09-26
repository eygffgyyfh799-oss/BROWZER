local Settings = JS.Settings
local Notify = JS.Notify

local DutyHistory = {}

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- إنشاء جداول قاعدة البيانات وتحديثها وتحميل البيانات
-- ════════════════════════════════════════════════════════════════════════════════════════════════

CreateThread(function()
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

    -- أعمدة جديدة للقضايا (تضاف تلقائياً للجداول القديمة بدون حذف أي بيانات)
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
    MySQL.query.await("ALTER TABLE `justice_transactions` MODIFY `reason` varchar(255) NOT NULL")
    MySQL.query.await("ALTER TABLE `justice_transactions` MODIFY `amount` bigint(20) NOT NULL")

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

    -- سجل البصمة
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

    -- الخدمات الموقوفة
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

    -- فحص الجداول الخارجية وإظهار تحذير إذا لم تكن موجودة
    local db = Settings.Database
    for _, tableName in ipairs({ db.Players, db.Vehicles, db.Houses and db.Houses.table }) do
        if tableName and not JS.TableExists(tableName) then
            print(('^3[RespectJustice]^7 Table `%s` not found, related info will be hidden. Check Settings.Database in config.lua'):format(tableName))
        end
    end

    JS.Ready = true
    print(('^2[RespectJustice]^7 Ready: %d duty records, %d active suspensions'):format(#DutyHistory, #suspensions))
end)

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- سجل البصمة
-- يُستدعى من العميل بعد QBCore:ToggleDuty، والأحداث تصل للسيرفر بنفس الترتيب
-- لذلك حالة الدوام هنا هي الحالة الجديدة بعد التبديل
-- ════════════════════════════════════════════════════════════════════════════════════════════════

RegisterNetEvent('RespectJustice:server:updateDutyHistory', function()
    local src = source
    local Player = RTCore.Functions.GetPlayer(src)
    if not JS.IsJustice(Player) then return end

    local citizenid = Player.PlayerData.citizenid
    if JS.OnCooldown('duty', citizenid, math.max(Settings.DutyCooldown - 2, 1)) then return end

    local entry = {
        citizenid = citizenid,
        name = JS.PlayerName(Player),
        dutyStatus = Player.PlayerData.job.onduty and 'بدأ الدوام' or 'أنهى الدوام',
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

RTCore.Functions.CreateCallback('RespectJustice:server:getDutyHistory', function(source, cb)
    local Player = RTCore.Functions.GetPlayer(source)
    if not JS.IsBoss(Player) then return cb({}) end
    cb(DutyHistory)
end)

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- التعويض
-- ════════════════════════════════════════════════════════════════════════════════════════════════

RegisterNetEvent('RespectJustice:server:giveMoneyToPlayer', function(targetCitizenid, amount)
    local src = source
    local Player = RTCore.Functions.GetPlayer(src)
    if not Player or not JS.Ready then return end

    local allowed, err = JS.Can(Player, 'compensation')
    if not allowed then
        return Notify(src, err, 'error')
    end

    local moneyAmount = math.floor(tonumber(amount) or 0)
    if moneyAmount <= 0 then
        return Notify(src, 'المبلغ المدخل غير صحيح', 'error')
    end

    if moneyAmount > Settings.CompensationMax then
        return Notify(src, ('المبلغ المدخل كبير جداً (الحد الأقصى: $%d)'):format(Settings.CompensationMax), 'error')
    end

    targetCitizenid = JS.ValidCitizenId(targetCitizenid)
    if not targetCitizenid then
        return Notify(src, 'الرقم الوطني غير صحيح', 'error')
    end

    local TargetPlayer = RTCore.Functions.GetPlayerByCitizenId(targetCitizenid)
    if not TargetPlayer then
        return Notify(src, 'اللاعب غير متصل أو الرقم الوطني غير صحيح', 'error')
    end

    local targetSrc = TargetPlayer.PlayerData.source
    if targetSrc == src then
        return Notify(src, 'لا يمكنك تعويض نفسك', 'error')
    end

    -- التحقق من السيرفر أن المستفيد قريب فعلاً من الموظف
    local officerPed, targetPed = GetPlayerPed(src), GetPlayerPed(targetSrc)
    if officerPed == 0 or targetPed == 0
        or #(GetEntityCoords(officerPed) - GetEntityCoords(targetPed)) > Settings.CompensationMaxDistance then
        return Notify(src, 'يجب أن يكون المستفيد بالقرب منك', 'error')
    end

    local blocked, remaining = JS.OnCooldown('compensation', Player.PlayerData.citizenid, Settings.CompensationCooldown)
    if blocked then
        return Notify(src, ('يجب أن تنتظر %d ثانية'):format(remaining), 'error')
    end

    -- الحد اليومي لكل موظف
    local todayTotal = tonumber(MySQL.scalar.await(
        "SELECT COALESCE(SUM(amount), 0) FROM justice_transactions WHERE officer_citizenid = ? AND type = 'compensation' AND created_at >= CURDATE()",
        { Player.PlayerData.citizenid })) or 0
    if todayTotal + moneyAmount > Settings.CompensationDailyMax then
        return Notify(src, ('وصلت الحد اليومي للتعويضات (المتبقي اليوم: $%d)'):format(math.max(0, Settings.CompensationDailyMax - todayTotal)), 'error', 7000)
    end

    if not TargetPlayer.Functions.AddMoney('bank', moneyAmount, 'justice-compensation') then
        return Notify(src, 'تعذر تحويل المبلغ', 'error')
    end

    local officerName = JS.PlayerName(Player)
    local targetName = JS.PlayerName(TargetPlayer)

    Notify(src, ('تم تحويل $%d إلى %s بنجاح'):format(moneyAmount, targetName), 'success')
    Notify(targetSrc, ('تم تحويل $%d إلى حسابك البنكي من وزارة العدل - الموظف: %s'):format(moneyAmount, officerName), 'success', 7000)

    MySQL.insert.await('INSERT INTO justice_transactions (officer_citizenid, officer_name, target_citizenid, target_name, amount, reason, date, type) VALUES (?, ?, ?, ?, ?, ?, ?, ?)', {
        Player.PlayerData.citizenid, officerName, targetCitizenid, targetName, moneyAmount, 'تعويض', JS.Now(), 'compensation'
    })
    JS.Log(Player, 'compensation', targetCitizenid, targetName, { ['المبلغ'] = moneyAmount })
end)

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- تنظيف السجلات القديمة (عند التشغيل ثم كل 24 ساعة)
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
        print(('^2[RespectJustice]^7 Cleanup removed %d old records'):format(removed))
    end
end

CreateThread(function()
    while not JS.Ready do Wait(1000) end
    while true do
        local ok, err = pcall(CleanupOldData)
        if not ok then print(('^1[RespectJustice]^7 Cleanup failed: %s'):format(tostring(err))) end
        Wait(24 * 60 * 60 * 1000)
    end
end)
