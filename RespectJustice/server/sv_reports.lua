local Settings = JS.Settings
local Notify = JS.Notify

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- تحويل صف القضية لشكل مناسب للعميل
-- ════════════════════════════════════════════════════════════════════════════════════════════════

local function MapReport(row, full)
    local report = {
        id = row.id,
        title = (row.title and row.title ~= '') and row.title or ('قضية #' .. row.id),
        caseType = row.case_type ~= '' and row.case_type or 'غير محدد',
        citizenid = row.citizenid,
        name = row.name,
        date = row.date,
        status = row.status or 'new',
        statusLabel = JS.StatusLabels[row.status] or JS.StatusLabels.new,
        handledBy = row.handled_by ~= '' and row.handled_by or nil,
        defendantName = row.defendant_name ~= '' and row.defendant_name or nil,
        defendantCitizenid = row.defendant_citizenid ~= '' and row.defendant_citizenid or nil,
    }

    if full then
        report.phoneNumber = row.phone_number
        report.report = row.report
        report.witnesses = (row.witnesses and row.witnesses ~= '') and row.witnesses or nil
        report.evidence = (row.evidence and row.evidence ~= '') and row.evidence or nil
        report.submitter = JS.Decode(row.submitter_info)
        report.submitterOnline = RTCore.Functions.GetPlayerByCitizenId(row.citizenid) ~= nil
        report.submitterStatus = JS.GetStatus(row.citizenid).text
        if report.defendantCitizenid then
            report.defendantStatus = JS.GetStatus(report.defendantCitizenid).text
        end
    else
        report.submitterOnline = RTCore.Functions.GetPlayerByCitizenId(row.citizenid) ~= nil
    end

    -- حماية البيانات القديمة المحفوظة قبل التنظيف
    for _, key in ipairs({ 'title', 'name', 'defendantName', 'report', 'witnesses', 'evidence', 'handledBy' }) do
        report[key] = JS.Safe(report[key])
    end

    return report
end

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- تقديم دعوى
-- data = { title, caseType, defendantName, defendantCitizenid, witnesses, evidence, report }
-- ════════════════════════════════════════════════════════════════════════════════════════════════

RegisterNetEvent('RespectJustice:server:submitReport', function(data)
    local src = source
    local Player = RTCore.Functions.GetPlayer(src)
    if not Player then return end
    if not JS.Ready then return Notify(src, 'النظام قيد التحميل، حاول بعد قليل', 'error') end

    if type(data) == 'string' then data = { report = data } end
    if type(data) ~= 'table' then return end

    -- التحقق من الحقول
    local report = JS.CleanText(data.report, Settings.ReportMaxLength, true)
    if not report or JS.Len(report) < Settings.ReportMinLength then
        return Notify(src, ('تفاصيل الدعوى يجب أن تكون بين %d و %d حرف'):format(Settings.ReportMinLength, Settings.ReportMaxLength), 'error')
    end

    local title = JS.CleanText(data.title, Settings.ReportTitleMax, false)
    if not title then
        return Notify(src, ('عنوان الدعوى يجب ألا يتجاوز %d حرف'):format(Settings.ReportTitleMax), 'error')
    end
    if title == '' then
        title = JS.Truncate(report, 60)
    end

    local caseType = Settings.CaseTypes[tonumber(data.caseType) or 0] or Settings.CaseTypes[#Settings.CaseTypes]

    local defendantName = JS.CleanText(data.defendantName, 60, false)
    local witnesses = JS.CleanText(data.witnesses, Settings.ReportWitnessesMax, false)
    local evidence = JS.CleanText(data.evidence, Settings.ReportEvidenceMax, false)
    if not defendantName or not witnesses or not evidence then
        return Notify(src, 'أحد الحقول أطول من المسموح', 'error')
    end

    local defendantCitizenid = ''
    if data.defendantCitizenid and tostring(data.defendantCitizenid) ~= '' then
        defendantCitizenid = JS.ValidCitizenId(data.defendantCitizenid)
        if not defendantCitizenid then
            return Notify(src, 'الرقم الوطني للمدعى عليه غير صحيح', 'error')
        end
        local defendant = JS.GetCitizen(defendantCitizenid)
        if not defendant then
            return Notify(src, 'لا يوجد مواطن بهذا الرقم الوطني', 'error')
        end
        if defendantName == '' then
            defendantName = JS.FullName(defendant.charinfo)
        end
    end

    local citizenid = Player.PlayerData.citizenid
    local blocked, remaining = JS.OnCooldown('report', citizenid, Settings.ReportCooldown)
    if blocked then
        return Notify(src, ('يجب أن تنتظر %d ثانية قبل تقديم دعوى جديدة'):format(remaining), 'error')
    end

    local fee = Settings.ReportFee
    if (Player.PlayerData.money.cash or 0) < fee or not Player.Functions.RemoveMoney('cash', fee, 'justice-report-fee') then
        JS.ClearCooldown('report', citizenid)
        return Notify(src, ('ليس لديك مبلغ كافٍ لتقديم الدعوى (تحتاج إلى $%d)'):format(fee), 'error')
    end

    -- معلومات مقدم الدعوى تُجمع من السيرفر (لا يمكن تزويرها من العميل)
    local charinfo = Player.PlayerData.charinfo or {}
    local job = Player.PlayerData.job or {}
    local gang = Player.PlayerData.gang or {}
    local ped = GetPlayerPed(src)
    local coords = ped ~= 0 and GetEntityCoords(ped) or nil

    local submitter = {
        birthdate = charinfo.birthdate,
        gender = charinfo.gender,
        nationality = charinfo.nationality,
        account = charinfo.account,
        job = job.label or job.name,
        jobGrade = type(job.grade) == 'table' and job.grade.name or nil,
        gang = (gang.name and gang.name ~= 'none') and (gang.label or gang.name) or nil,
        serverId = src,
        coords = coords and { x = coords.x, y = coords.y, z = coords.z } or nil,
    }

    local name = JS.PlayerName(Player)
    local phoneNumber = tostring(charinfo.phone or 'غير متوفر')
    local date = JS.Now()

    local insertId = MySQL.insert.await([[
        INSERT INTO justice_reports
            (citizenid, name, phone_number, report, date, job, title, case_type, defendant_name, defendant_citizenid, witnesses, evidence, status, submitter_info)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'new', ?)
    ]], {
        citizenid, name, phoneNumber, report, date, JS.Job, title, caseType,
        defendantName, defendantCitizenid, witnesses, evidence, json.encode(submitter)
    })

    if not insertId then
        Player.Functions.AddMoney('cash', fee, 'justice-report-refund')
        JS.ClearCooldown('report', citizenid)
        return Notify(src, 'حدث خطأ أثناء تقديم الدعوى، تم إرجاع المبلغ', 'error')
    end

    Notify(src, ('تم تقديم الدعوى بنجاح برقم #%d مقابل $%d، سيتم التواصل معك على رقمك %s'):format(insertId, fee, phoneNumber), 'success', 8000)

    local message = ('دعوى جديدة #%d (%s) من %s: %s'):format(insertId, caseType, name, title)
    for _, playerId in pairs(RTCore.Functions.GetPlayers()) do
        local target = RTCore.Functions.GetPlayer(playerId)
        if JS.IsJustice(target) and target.PlayerData.job.onduty then
            Notify(playerId, message, 'primary', 8000)
        end
    end

    print(('^2[RespectJustice]^7 New report #%d by %s (%s)'):format(insertId, name, citizenid))
end)

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- قائمة القضايا
-- ════════════════════════════════════════════════════════════════════════════════════════════════

JS.RegisterCallback('RespectJustice:server:getJobReports', 'reports', function(src, Player, statusFilter)
    local rows
    if statusFilter and JS.StatusLabels[statusFilter] then
        rows = MySQL.query.await('SELECT * FROM justice_reports WHERE job = ? AND status = ? ORDER BY id DESC LIMIT 200', { JS.Job, statusFilter })
    else
        rows = MySQL.query.await('SELECT * FROM justice_reports WHERE job = ? ORDER BY id DESC LIMIT 200', { JS.Job })
    end

    local counts = { new = 0, review = 0, closed = 0 }
    for _, row in ipairs(MySQL.query.await('SELECT status, COUNT(*) AS total FROM justice_reports WHERE job = ? GROUP BY status', { JS.Job }) or {}) do
        counts[row.status] = row.total
    end

    local reports = {}
    for i, row in ipairs(rows or {}) do
        reports[i] = MapReport(row, false)
    end

    return { ok = true, reports = reports, counts = counts, perms = JS.GetPermissions(Player) }
end)

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- تفاصيل قضية
-- ════════════════════════════════════════════════════════════════════════════════════════════════

JS.RegisterCallback('RespectJustice:server:getReport', 'reports', function(src, Player, reportId)
    reportId = tonumber(reportId)
    if not reportId then return { ok = false, err = 'رقم القضية غير صحيح' } end

    local row = MySQL.single.await('SELECT * FROM justice_reports WHERE id = ? AND job = ?', { reportId, JS.Job })
    if not row then return { ok = false, err = 'القضية غير موجودة' } end

    local notes = {}
    for i, note in ipairs(MySQL.query.await('SELECT * FROM justice_report_notes WHERE report_id = ? ORDER BY id DESC', { reportId }) or {}) do
        notes[i] = { author = JS.Safe(note.author_name), note = JS.Safe(note.note), date = JS.FormatDbDate(note.created_at) }
    end

    local report = MapReport(row, true)
    report.notes = notes
    if JS.GetCaseExtras then
        local extras = JS.GetCaseExtras(reportId)
        report.lawyers, report.documents, report.verdicts = extras.lawyers, extras.documents, extras.verdicts
    end

    return { ok = true, report = report, perms = JS.GetPermissions(Player) }
end)

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- تغيير حالة قضية
-- ════════════════════════════════════════════════════════════════════════════════════════════════

JS.RegisterCallback('RespectJustice:server:setReportStatus', 'reports', function(src, Player, reportId, status)
    reportId = tonumber(reportId)
    if not reportId or not JS.StatusLabels[status] then
        return { ok = false, err = 'بيانات غير صحيحة' }
    end

    local officerName = JS.PlayerName(Player)
    local previousStatus = MySQL.scalar.await('SELECT status FROM justice_reports WHERE id = ? AND job = ?', { reportId, JS.Job })
    local affected = MySQL.update.await('UPDATE justice_reports SET status = ?, handled_by = ? WHERE id = ? AND job = ?', {
        status, officerName, reportId, JS.Job
    })
    if not affected or affected == 0 then
        return { ok = false, err = 'القضية غير موجودة' }
    end

    MySQL.insert('INSERT INTO justice_report_notes (report_id, author_citizenid, author_name, note) VALUES (?, ?, ?, ?)', {
        reportId, Player.PlayerData.citizenid, officerName, ('تم تغيير الحالة إلى: %s'):format(JS.StatusLabels[status])
    })
    JS.Log(Player, 'report_status', nil, nil, { ['القضية'] = reportId, ['الحالة'] = JS.StatusLabels[status] }, previousStatus and { id = reportId, status = previousStatus } or nil)

    -- إشعار مقدم الدعوى إذا كان متصلاً
    local row = MySQL.single.await('SELECT citizenid FROM justice_reports WHERE id = ?', { reportId })
    local owner = row and RTCore.Functions.GetPlayerByCitizenId(row.citizenid)
    if owner then
        Notify(owner.PlayerData.source, ('تم تحديث حالة دعواك #%d إلى: %s'):format(reportId, JS.StatusLabels[status]), 'primary', 8000)
    end

    return { ok = true }
end)

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- إضافة ملاحظة على قضية
-- ════════════════════════════════════════════════════════════════════════════════════════════════

JS.RegisterCallback('RespectJustice:server:addReportNote', 'reports', function(src, Player, reportId, note)
    reportId = tonumber(reportId)
    note = JS.CleanText(note, Settings.ReportNoteMax, true)
    if not reportId or not note then
        return { ok = false, err = ('الملاحظة مطلوبة ويجب ألا تتجاوز %d حرف'):format(Settings.ReportNoteMax) }
    end

    local exists = MySQL.scalar.await('SELECT id FROM justice_reports WHERE id = ? AND job = ?', { reportId, JS.Job })
    if not exists then return { ok = false, err = 'القضية غير موجودة' } end

    MySQL.insert.await('INSERT INTO justice_report_notes (report_id, author_citizenid, author_name, note) VALUES (?, ?, ?, ?)', {
        reportId, Player.PlayerData.citizenid, JS.PlayerName(Player), note
    })
    JS.Log(Player, 'report_note', nil, nil, { ['القضية'] = reportId, ['الملاحظة'] = note })

    return { ok = true }
end)

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- حذف قضية
-- ════════════════════════════════════════════════════════════════════════════════════════════════

JS.RegisterCallback('RespectJustice:server:deleteReport', 'deleteReport', function(src, Player, reportId)
    reportId = tonumber(reportId)
    if not reportId then return { ok = false, err = 'رقم القضية غير صحيح' } end

    local affected = MySQL.update.await('DELETE FROM justice_reports WHERE id = ? AND job = ?', { reportId, JS.Job })
    if not affected or affected == 0 then
        return { ok = false, err = 'القضية غير موجودة أو تم حذفها مسبقاً' }
    end

    MySQL.update('DELETE FROM justice_report_notes WHERE report_id = ?', { reportId })
    JS.Log(Player, 'report_delete', nil, nil, { ['القضية'] = reportId })

    return { ok = true }
end)

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- دعاوى المواطن نفسه (لمتابعة حالتها)
-- ════════════════════════════════════════════════════════════════════════════════════════════════

JS.RegisterCallback('RespectJustice:server:getMyReports', nil, function(src, Player)
    local rows = MySQL.query.await('SELECT * FROM justice_reports WHERE job = ? AND citizenid = ? ORDER BY id DESC LIMIT 25', {
        JS.Job, Player.PlayerData.citizenid
    }) or {}
    local reports = {}
    for i, row in ipairs(rows) do
        reports[i] = MapReport(row, false)
    end
    return { ok = true, reports = reports }
end)
