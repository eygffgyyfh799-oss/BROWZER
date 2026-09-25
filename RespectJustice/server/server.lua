local Config = Load('config')
local Settings = Config.Settings
local JOB = Settings.Job

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- المتغيرات العامة
-- ════════════════════════════════════════════════════════════════════════════════════════════════

local DutyHistory = {}
local Cooldowns = { duty = {}, report = {}, compensation = {} }

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- دوال مساعدة
-- ════════════════════════════════════════════════════════════════════════════════════════════════

local function Notify(src, msg, msgType, length)
    RTCore.Functions.Notify(src, msg, msgType, length or 5000)
end

local function GetFormattedDateTime()
    return os.date("%d/%m/%Y %H:%M", os.time())
end

local function GetCurrentTime()
    return os.date("%Y-%m-%d %H:%M:%S", os.time())
end

local function GetFullName(Player)
    local charinfo = Player.PlayerData.charinfo or {}
    return ('%s %s'):format(charinfo.firstname or '', charinfo.lastname or '')
end

local function IsJustice(Player)
    return Player and Player.PlayerData.job and Player.PlayerData.job.name == JOB
end

local function IsJusticeBoss(Player)
    return IsJustice(Player) and Player.PlayerData.job.isboss == true
end

-- يرجع true إذا كان اللاعب في فترة انتظار، ويبدأ فترة جديدة إذا لم يكن كذلك
local function OnCooldown(kind, key, seconds)
    local now = os.time()
    local expires = Cooldowns[kind][key]
    if expires and expires > now then
        return true, expires - now
    end
    Cooldowns[kind][key] = now + seconds
    return false
end

local function MapReportRow(row)
    return {
        id = row.id,
        citizenid = row.citizenid,
        name = row.name,
        phoneNumber = row.phone_number,
        report = row.report,
        date = row.date,
    }
end

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- إنشاء جداول قاعدة البيانات وتحميل البيانات
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

    local result = MySQL.query.await('SELECT * FROM justice_duty_history ORDER BY timestamp DESC, id DESC LIMIT ?', {
        Settings.DutyHistoryLimit
    }) or {}

    DutyHistory = {}
    for i = 1, #result do
        local row = result[i]
        DutyHistory[#DutyHistory + 1] = {
            citizenid = row.citizenid,
            name = row.name,
            dutyStatus = row.duty_status,
            timeFormated = row.time,
            timestamp = row.timestamp,
        }
    end

    print(('^2[RespectJustice]^7 Database ready, loaded %d duty history records'):format(#DutyHistory))
end)

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- تحديث سجل البصمة
-- يُستدعى من العميل بعد QBCore:ToggleDuty، والأحداث تصل للسيرفر بنفس الترتيب
-- لذلك حالة الدوام هنا هي الحالة الجديدة بعد التبديل
-- ════════════════════════════════════════════════════════════════════════════════════════════════

RegisterNetEvent('RespectJustice:server:updateDutyHistory', function()
    local src = source
    local Player = RTCore.Functions.GetPlayer(src)
    if not IsJustice(Player) then return end

    local citizenid = Player.PlayerData.citizenid
    if OnCooldown('duty', citizenid, math.max(Settings.DutyCooldown - 2, 1)) then return end

    local name = GetFullName(Player)
    local dutyStatus = Player.PlayerData.job.onduty and 'بدأ الدوام' or 'أنهى الدوام'
    local timeFormated = GetFormattedDateTime()
    local timestamp = os.time()

    table.insert(DutyHistory, 1, {
        citizenid = citizenid,
        name = name,
        dutyStatus = dutyStatus,
        timeFormated = timeFormated,
        timestamp = timestamp,
    })

    while #DutyHistory > Settings.DutyHistoryLimit do
        table.remove(DutyHistory)
    end

    MySQL.insert('INSERT INTO justice_duty_history (citizenid, name, duty_status, time, timestamp) VALUES (?, ?, ?, ?, ?)', {
        citizenid, name, dutyStatus, timeFormated, timestamp
    })
end)

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- الحصول على سجل البصمة (للمدير فقط)
-- ════════════════════════════════════════════════════════════════════════════════════════════════

RTCore.Functions.CreateCallback('RespectJustice:server:getDutyHistory', function(source, cb)
    local Player = RTCore.Functions.GetPlayer(source)
    if not IsJusticeBoss(Player) then return cb({}) end
    cb(DutyHistory)
end)

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- تقديم قضية
-- ════════════════════════════════════════════════════════════════════════════════════════════════

RegisterNetEvent('RespectJustice:server:submitReport', function(reportText)
    local src = source
    local Player = RTCore.Functions.GetPlayer(src)
    if not Player then return end

    reportText = _2rayan.Functions.trim(reportText)
    -- utf8.len يحسب الأحرف العربية بشكل صحيح، و # يحسب البايتات
    local length = reportText and (utf8.len(reportText) or #reportText) or 0
    if length < Settings.ReportMinLength then
        return Notify(src, ('يجب أن يكون موضوع الدعوى %d أحرف على الأقل'):format(Settings.ReportMinLength), 'error')
    end
    if length > Settings.ReportMaxLength then
        return Notify(src, ('عذرًا، يجب أن يكون الموضوع أقل من %d حرف'):format(Settings.ReportMaxLength), 'error')
    end

    local citizenid = Player.PlayerData.citizenid
    local blocked, remaining = OnCooldown('report', citizenid, Settings.ReportCooldown)
    if blocked then
        return Notify(src, ('يجب أن تنتظر %d ثانية قبل تقديم دعوى جديدة'):format(remaining), 'error')
    end

    local reportFee = Settings.ReportFee
    if (Player.PlayerData.money.cash or 0) < reportFee or not Player.Functions.RemoveMoney('cash', reportFee, 'justice-report-fee') then
        Cooldowns.report[citizenid] = nil
        return Notify(src, ('ليس لديك مبلغ كافٍ لتقديم الدعوى (تحتاج إلى $%d)'):format(reportFee), 'error')
    end

    local name = GetFullName(Player)
    local phoneNumber = tostring(Player.PlayerData.charinfo.phone or 'غير متوفر')
    local date = GetFormattedDateTime()

    local insertId = MySQL.insert.await('INSERT INTO justice_reports (citizenid, name, phone_number, report, date, job) VALUES (?, ?, ?, ?, ?, ?)', {
        citizenid, name, phoneNumber, reportText, date, JOB
    })

    if not insertId then
        Player.Functions.AddMoney('cash', reportFee, 'justice-report-refund')
        Cooldowns.report[citizenid] = nil
        return Notify(src, 'حدث خطأ أثناء تقديم الدعوى، تم إرجاع المبلغ', 'error')
    end

    Notify(src, ('تم تقديم الدعوى القضائية بنجاح برقم #%d مقابل $%d'):format(insertId, reportFee), 'success')

    for _, playerId in pairs(RTCore.Functions.GetPlayers()) do
        local target = RTCore.Functions.GetPlayer(playerId)
        if IsJustice(target) and target.PlayerData.job.onduty then
            Notify(playerId, ('تم تقديم دعوى قضائية جديدة #%d من: %s'):format(insertId, name), 'primary', 7000)
        end
    end

    print(('^2[RespectJustice]^7 New report #%d submitted by: %s (%s)'):format(insertId, name, citizenid))
end)

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- الحصول على القضايا (مرتبة من الأحدث إلى الأقدم)
-- ════════════════════════════════════════════════════════════════════════════════════════════════

RTCore.Functions.CreateCallback('RespectJustice:server:getJobReports', function(source, cb)
    local Player = RTCore.Functions.GetPlayer(source)
    if not IsJustice(Player) then return cb({}) end

    local result = MySQL.query.await('SELECT * FROM justice_reports WHERE job = ? ORDER BY id DESC', { JOB }) or {}
    local reports = {}
    for i = 1, #result do
        reports[i] = MapReportRow(result[i])
    end
    cb(reports)
end)

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- حذف قضية (للمدير فقط)
-- ════════════════════════════════════════════════════════════════════════════════════════════════

RegisterNetEvent('RespectJustice:server:removeReport', function(reportId)
    local src = source
    local Player = RTCore.Functions.GetPlayer(src)
    if not Player then return end

    if not IsJusticeBoss(Player) then
        return Notify(src, 'ليس لديك صلاحية لحذف القضايا', 'error')
    end

    reportId = tonumber(reportId)
    if not reportId then return end

    local affectedRows = MySQL.update.await('DELETE FROM justice_reports WHERE id = ? AND job = ?', { reportId, JOB })
    if affectedRows and affectedRows > 0 then
        Notify(src, 'تم حذف القضية بنجاح', 'success')
        print(('^2[RespectJustice]^7 Report #%d deleted by: %s (%s)'):format(reportId, GetFullName(Player), Player.PlayerData.citizenid))
    else
        Notify(src, 'القضية غير موجودة أو تم حذفها مسبقاً', 'error')
    end
end)

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- إعطاء تعويض للشخص
-- ════════════════════════════════════════════════════════════════════════════════════════════════

RegisterNetEvent('RespectJustice:server:giveMoneyToPlayer', function(targetCitizenid, amount)
    local src = source
    local Player = RTCore.Functions.GetPlayer(src)
    if not Player then return end

    if not IsJustice(Player) then
        return Notify(src, 'يجب أن تكون من موظفي العدل لاستخدام هذه الميزة', 'error')
    end

    local job = Player.PlayerData.job
    local grade = job.grade and tonumber(job.grade.level) or 0
    if not job.isboss and grade < Settings.CompensationMinGrade then
        return Notify(src, 'ليس لديك صلاحية لإعطاء التعويضات', 'error')
    end

    if Settings.CompensationRequireDuty and not job.onduty then
        return Notify(src, 'يجب أن تكون في الدوام لإعطاء التعويضات', 'error')
    end

    local moneyAmount = math.floor(tonumber(amount) or 0)
    if moneyAmount <= 0 then
        return Notify(src, 'المبلغ المدخل غير صحيح', 'error')
    end

    if moneyAmount > Settings.CompensationMax then
        return Notify(src, ('المبلغ المدخل كبير جداً (الحد الأقصى: $%d)'):format(Settings.CompensationMax), 'error')
    end

    targetCitizenid = _2rayan.Functions.trim(tostring(targetCitizenid or ''))
    if not targetCitizenid or targetCitizenid == '' then
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

    local blocked, remaining = OnCooldown('compensation', Player.PlayerData.citizenid, Settings.CompensationCooldown)
    if blocked then
        return Notify(src, ('يجب أن تنتظر %d ثانية'):format(remaining), 'error')
    end

    if not TargetPlayer.Functions.AddMoney('bank', moneyAmount, 'justice-compensation') then
        return Notify(src, 'تعذر تحويل المبلغ', 'error')
    end

    local officerName = GetFullName(Player)
    local targetName = GetFullName(TargetPlayer)

    Notify(src, ('تم تحويل $%d إلى %s بنجاح'):format(moneyAmount, targetName), 'success')
    Notify(targetSrc, ('تم تحويل $%d إلى حسابك البنكي من وزارة العدل - الموظف: %s'):format(moneyAmount, officerName), 'success', 7000)

    print(('^2[RespectJustice]^7 %s (%s) gave $%d to %s (%s)'):format(
        officerName, Player.PlayerData.citizenid, moneyAmount, targetName, targetCitizenid))

    MySQL.insert('INSERT INTO justice_transactions (officer_citizenid, officer_name, target_citizenid, target_name, amount, reason, date) VALUES (?, ?, ?, ?, ?, ?, ?)', {
        Player.PlayerData.citizenid, officerName, targetCitizenid, targetName, moneyAmount, 'compensation', GetCurrentTime()
    })
end)

-- تنظيف فترات الانتظار المنتهية كل 10 دقائق
CreateThread(function()
    while true do
        Wait(600000)
        local now = os.time()
        for _, list in pairs(Cooldowns) do
            for key, expires in pairs(list) do
                if expires <= now then list[key] = nil end
            end
        end
    end
end)
