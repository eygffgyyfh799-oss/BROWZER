-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- القضاء: المشبوهين، أوامر القبض والتفتيش، المحامين والمستندات، الأحكام، الإحصائيات
-- ════════════════════════════════════════════════════════════════════════════════════════════════

local Settings = JS.Settings
local V = Settings.Verdicts
local Notify = JS.Notify

local function H(name) return JS.Handlers['RespectJustice:server:' .. name] end

JS.DangerLabels = { low = 'منخفض', medium = 'متوسط', high = 'عالي' }
JS.WarrantTypes = { arrest = 'أمر قبض', search = 'أمر تفتيش' }
JS.WarrantStatus = { active = 'ساري', executed = 'تم التنفيذ', cancelled = 'ملغي', expired = 'منتهي' }
JS.VerdictTypes = {
    fine = 'غرامة مالية',
    compensation = 'تعويض للمتضرر',
    impound = 'حجز مركبة',
    jail = 'سجن',
    suspend = 'إيقاف خدمات',
    acquittal = 'براءة',
}

local function FormatAt(value)
    return JS.FormatDbDate(value)
end

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- المشبوهين
-- ════════════════════════════════════════════════════════════════════════════════════════════════

local function MapSuspect(row)
    return {
        id = row.id,
        citizenid = row.citizenid,
        name = JS.Safe(row.name),
        reason = JS.Safe(row.reason),
        danger = row.danger,
        dangerLabel = JS.DangerLabels[row.danger] or row.danger,
        addedBy = JS.Safe(row.added_by),
        date = FormatAt(row.created_at),
        status = JS.GetStatus(row.citizenid),
    }
end

function JS.GetSuspects()
    local list = {}
    for i, row in ipairs(MySQL.query.await("SELECT * FROM justice_suspects WHERE active = 1 ORDER BY FIELD(danger, 'high', 'medium', 'low'), id DESC LIMIT 200") or {}) do
        list[i] = MapSuspect(row)
    end
    return list
end

function JS.GetSuspect(citizenid)
    local row = MySQL.single.await('SELECT * FROM justice_suspects WHERE citizenid = ? AND active = 1 ORDER BY id DESC LIMIT 1', { citizenid })
    return row and MapSuspect(row) or nil
end

JS.RegisterCallback('RespectJustice:server:getSuspects', 'view', function()
    return { ok = true, suspects = JS.GetSuspects() }
end)

JS.RegisterCallback('RespectJustice:server:addSuspect', 'suspects', function(src, Player, citizenid, reason, danger)
    citizenid = JS.ValidCitizenId(citizenid)
    reason = JS.CleanText(reason, 200, true)
    if not JS.DangerLabels[danger] then danger = 'medium' end
    if not citizenid or not reason then return { ok = false, err = 'الرقم الوطني والسبب مطلوبين' } end
    if JS.GetSuspect(citizenid) then return { ok = false, err = 'المواطن موجود في قائمة المشبوهين مسبقاً' } end

    local citizen = JS.GetCitizen(citizenid)
    if not citizen then return { ok = false, err = 'لا يوجد مواطن بهذا الرقم الوطني' } end
    local name = JS.FullName(citizen.charinfo)

    local id = MySQL.insert.await('INSERT INTO justice_suspects (citizenid, name, reason, danger, added_by, added_by_cid) VALUES (?, ?, ?, ?, ?, ?)', {
        citizenid, name, reason, danger, JS.PlayerName(Player), Player.PlayerData.citizenid
    })
    if not id then return { ok = false, err = 'تعذر الحفظ' } end

    if danger == 'high' then
        JS.BroadcastTablet(JS.PoliceOnDuty, { type = 'suspect', title = '⚠️ مشبوه خطورة عالية', text = ('%s (%s): %s'):format(name, citizenid, reason) })
    end
    JS.Log(Player, 'suspect_add', citizenid, name, { ['السبب'] = reason, ['الخطورة'] = JS.DangerLabels[danger] }, { id = id })
    return { ok = true }
end)

JS.RegisterCallback('RespectJustice:server:removeSuspect', 'suspects', function(src, Player, suspectId)
    suspectId = tonumber(suspectId)
    local row = suspectId and MySQL.single.await('SELECT * FROM justice_suspects WHERE id = ? AND active = 1', { suspectId })
    if not row then return { ok = false, err = 'غير موجود في القائمة' } end
    MySQL.update.await('UPDATE justice_suspects SET active = 0, removed_by = ? WHERE id = ?', { JS.PlayerName(Player), suspectId })
    JS.Log(Player, 'suspect_remove', row.citizenid, row.name, { ['السبب السابق'] = row.reason }, { id = suspectId })
    return { ok = true }
end)

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- أوامر القبض والتفتيش
-- ════════════════════════════════════════════════════════════════════════════════════════════════

local function ExpireWarrants()
    MySQL.update.await("UPDATE justice_warrants SET status = 'expired' WHERE status = 'active' AND expires_at IS NOT NULL AND expires_at < NOW()")
end

local function MapWarrant(row)
    return {
        id = row.id,
        type = row.type,
        typeLabel = JS.WarrantTypes[row.type] or row.type,
        citizenid = row.citizenid,
        name = JS.Safe(row.name),
        reason = JS.Safe(row.reason),
        place = row.place ~= '' and JS.Safe(row.place) or nil,
        issuedBy = JS.Safe(row.issued_by),
        requestedBy = row.requested_by ~= '' and JS.Safe(row.requested_by) or nil,
        status = row.status,
        statusLabel = JS.WarrantStatus[row.status] or row.status,
        executedBy = row.executed_by and JS.Safe(row.executed_by) or nil,
        expires = FormatAt(row.expires_at),
        date = FormatAt(row.created_at),
        citizenStatus = JS.GetStatus(row.citizenid),
    }
end

function JS.GetWarrants(citizenid, activeOnly)
    ExpireWarrants()
    local where, params = {}, {}
    if citizenid then where[#where + 1] = 'citizenid = ?' params[#params + 1] = citizenid end
    if activeOnly then where[#where + 1] = "status = 'active'" end
    local query = ('SELECT * FROM justice_warrants %s ORDER BY id DESC LIMIT 100'):format(#where > 0 and ('WHERE ' .. table.concat(where, ' AND ')) or '')
    local list = {}
    for i, row in ipairs(MySQL.query.await(query, params) or {}) do list[i] = MapWarrant(row) end
    return list
end

-- إصدار أمر (يستخدمه القاضي مباشرة أو عند قبول طلب شرطة)
function JS.IssueWarrant(Player, citizenid, wType, reason, place, requestedBy)
    citizenid = JS.ValidCitizenId(citizenid)
    reason = JS.CleanText(reason, 200, true)
    place = JS.CleanText(place, 150, false)
    if not citizenid or not JS.WarrantTypes[wType] then return { ok = false, err = 'بيانات غير صحيحة' } end
    if not reason then return { ok = false, err = 'سبب الأمر مطلوب' } end
    if not place then return { ok = false, err = 'المكان 150 حرف كحد أقصى' } end

    local citizen = JS.GetCitizen(citizenid)
    if not citizen then return { ok = false, err = 'لا يوجد مواطن بهذا الرقم الوطني' } end
    local name = JS.FullName(citizen.charinfo)

    local id = MySQL.insert.await(
        'INSERT INTO justice_warrants (type, citizenid, name, reason, place, issued_by, issued_by_cid, requested_by, expires_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, NOW() + INTERVAL ? HOUR)',
        { wType, citizenid, name, reason, place, JS.PlayerName(Player), Player.PlayerData.citizenid, requestedBy or '', tonumber(V.WarrantHours) or 72 })
    if not id then return { ok = false, err = 'تعذر إصدار الأمر' } end

    JS.BroadcastTablet(JS.PoliceOnDuty, {
        type = 'warrant', title = ('🚨 %s جديد #%d'):format(JS.WarrantTypes[wType], id),
        text = ('%s (%s): %s%s'):format(name, citizenid, reason, place ~= '' and (' | المكان: ' .. place) or ''),
    })
    JS.Log(Player, 'warrant_issue', citizenid, name, { ['النوع'] = JS.WarrantTypes[wType], ['السبب'] = reason, ['المكان'] = place }, { id = id })
    return { ok = true, id = id }
end

JS.RegisterCallback('RespectJustice:server:getWarrants', 'view', function(src, Player, citizenid, activeOnly)
    return { ok = true, warrants = JS.GetWarrants(citizenid and JS.ValidCitizenId(citizenid) or nil, activeOnly == true) }
end)

JS.RegisterCallback('RespectJustice:server:issueWarrant', 'warrants', function(src, Player, citizenid, wType, reason, place)
    return JS.IssueWarrant(Player, citizenid, wType, reason, place)
end)

JS.RegisterCallback('RespectJustice:server:cancelWarrant', 'warrants', function(src, Player, warrantId)
    warrantId = tonumber(warrantId)
    local row = warrantId and MySQL.single.await("SELECT * FROM justice_warrants WHERE id = ? AND status = 'active'", { warrantId })
    if not row then return { ok = false, err = 'الأمر غير ساري أو غير موجود' } end
    MySQL.update.await("UPDATE justice_warrants SET status = 'cancelled' WHERE id = ?", { warrantId })
    JS.BroadcastTablet(JS.PoliceOnDuty, { type = 'warrant', title = ('إلغاء %s #%d'):format(JS.WarrantTypes[row.type] or '', warrantId), text = ('%s (%s)'):format(row.name, row.citizenid) })
    JS.Log(Player, 'warrant_cancel', row.citizenid, row.name, { ['الأمر'] = warrantId }, { id = warrantId })
    return { ok = true }
end)

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- المحامين والمستندات
-- ════════════════════════════════════════════════════════════════════════════════════════════════

local function IsAssignedLawyer(Player, reportId)
    return MySQL.scalar.await('SELECT id FROM justice_case_lawyers WHERE report_id = ? AND lawyer_cid = ?', { reportId, Player.PlayerData.citizenid }) ~= nil
end

-- مستخدم يقدر يشوف القضية: موظف عدل عنده صلاحية القضايا، أو محامي معيّن فيها
local function CanAccessCase(Player, reportId)
    if JS.Can(Player, 'reports') == true then return true, 'justice' end
    if JS.IsLawyer(Player) and IsAssignedLawyer(Player, reportId) then return true, 'lawyer' end
    return false
end

function JS.GetCaseExtras(reportId)
    local lawyers, documents = {}, {}
    for i, row in ipairs(MySQL.query.await('SELECT * FROM justice_case_lawyers WHERE report_id = ? ORDER BY id', { reportId }) or {}) do
        lawyers[i] = { id = row.id, citizenid = row.lawyer_cid, name = JS.Safe(row.lawyer_name), side = row.side,
            sideLabel = row.side == 'defendant' and 'محامي المدعى عليه' or 'محامي المدعي', status = JS.GetStatus(row.lawyer_cid) }
    end
    for i, row in ipairs(MySQL.query.await('SELECT * FROM justice_case_documents WHERE report_id = ? ORDER BY id DESC', { reportId }) or {}) do
        documents[i] = { id = row.id, title = JS.Safe(row.title), content = JS.Safe(row.content), author = JS.Safe(row.author_name),
            role = row.author_role == 'lawyer' and 'محامي' or 'وزارة العدل', date = FormatAt(row.created_at) }
    end
    return { lawyers = lawyers, documents = documents, verdicts = JS.GetVerdicts(nil, reportId) }
end

JS.RegisterCallback('RespectJustice:server:assignLawyer', 'lawyers', function(src, Player, reportId, lawyerCid, side)
    reportId = tonumber(reportId)
    lawyerCid = JS.ValidCitizenId(lawyerCid)
    if side ~= 'defendant' then side = 'plaintiff' end
    if not reportId or not lawyerCid then return { ok = false, err = 'بيانات غير صحيحة' } end
    if not MySQL.scalar.await('SELECT id FROM justice_reports WHERE id = ? AND job = ?', { reportId, JS.Job }) then return { ok = false, err = 'القضية غير موجودة' } end

    local lawyer = JS.GetCitizen(lawyerCid)
    if not lawyer then return { ok = false, err = 'لا يوجد مواطن بهذا الرقم الوطني' } end
    if not JS.HasLawyerLicense(lawyer.metadata, lawyer.job) then return { ok = false, err = 'هذا المواطن ما عنده رخصة محاماة' } end

    local name = JS.FullName(lawyer.charinfo)
    local ok = pcall(MySQL.insert.await, 'INSERT INTO justice_case_lawyers (report_id, lawyer_cid, lawyer_name, side, assigned_by) VALUES (?, ?, ?, ?, ?)', {
        reportId, lawyerCid, name, side, JS.PlayerName(Player)
    })
    if not ok then return { ok = false, err = 'المحامي معيّن في هذه القضية مسبقاً' } end

    if lawyer.online then
        JS.TabletEvent(lawyer.online.PlayerData.source, { type = 'lawyer', title = '⚖️ تم تعيينك محامياً', text = ('في القضية #%d - افتح التابلت (زر 9)'):format(reportId) })
    end
    JS.Log(Player, 'lawyer_assign', lawyerCid, name, { ['القضية'] = reportId, ['الطرف'] = side == 'defendant' and 'المدعى عليه' or 'المدعي' })
    return { ok = true }
end)

JS.RegisterCallback('RespectJustice:server:removeLawyer', 'lawyers', function(src, Player, assignmentId)
    assignmentId = tonumber(assignmentId)
    local row = assignmentId and MySQL.single.await('SELECT * FROM justice_case_lawyers WHERE id = ?', { assignmentId })
    if not row then return { ok = false, err = 'غير موجود' } end
    MySQL.update.await('DELETE FROM justice_case_lawyers WHERE id = ?', { assignmentId })
    JS.Log(Player, 'lawyer_remove', row.lawyer_cid, row.lawyer_name, { ['القضية'] = row.report_id })
    return { ok = true }
end)

-- إضافة مستند: موظف العدل أو المحامي المعيّن
JS.RegisterCallback('RespectJustice:server:addDocument', nil, function(src, Player, reportId, title, content)
    reportId = tonumber(reportId)
    title = JS.CleanText(title, 120, true)
    content = JS.CleanText(content, Settings.Lawyers.DocumentMax, true)
    if not reportId or not title or not content then
        return { ok = false, err = ('العنوان والمحتوى مطلوبين (المحتوى %d حرف كحد أقصى)'):format(Settings.Lawyers.DocumentMax) }
    end
    local allowed, role = CanAccessCase(Player, reportId)
    if not allowed then return { ok = false, err = 'ليس لديك صلاحية على هذه القضية' } end

    MySQL.insert.await('INSERT INTO justice_case_documents (report_id, author_cid, author_name, author_role, title, content) VALUES (?, ?, ?, ?, ?, ?)', {
        reportId, Player.PlayerData.citizenid, JS.PlayerName(Player), role, title, content
    })
    if role == 'lawyer' then
        JS.BroadcastTablet(JS.JusticeOnDuty, { type = 'document', title = '📎 مستند جديد من محامي', text = ('القضية #%d: %s'):format(reportId, title) })
    end
    return { ok = true }
end)

-- ═════ واجهة المحامي ═════
local function LawyerOnly(Player)
    if JS.IsLawyer(Player) then return true end
    return false, 'هذا القسم للمحامين فقط'
end

JS.RegisterCallback('RespectJustice:server:lawyerCases', LawyerOnly, function(src, Player)
    local rows = MySQL.query.await([[
        SELECT r.*, l.side FROM justice_reports r
        JOIN justice_case_lawyers l ON l.report_id = r.id
        WHERE l.lawyer_cid = ? ORDER BY r.id DESC LIMIT 100
    ]], { Player.PlayerData.citizenid }) or {}
    local list = {}
    for i, row in ipairs(rows) do
        list[i] = {
            id = row.id, title = JS.Safe(row.title ~= '' and row.title or ('قضية #' .. row.id)), caseType = row.case_type,
            status = row.status, statusLabel = JS.StatusLabels[row.status] or row.status, date = row.date,
            client = JS.Safe(row.side == 'defendant' and (row.defendant_name ~= '' and row.defendant_name or 'المدعى عليه') or row.name),
            sideLabel = row.side == 'defendant' and 'المدعى عليه' or 'المدعي',
        }
    end
    return { ok = true, cases = list }
end)

JS.RegisterCallback('RespectJustice:server:lawyerCase', LawyerOnly, function(src, Player, reportId)
    reportId = tonumber(reportId)
    if not reportId or not IsAssignedLawyer(Player, reportId) then return { ok = false, err = 'أنت غير معيّن في هذه القضية' } end
    local row = MySQL.single.await('SELECT * FROM justice_reports WHERE id = ?', { reportId })
    if not row then return { ok = false, err = 'القضية غير موجودة' } end

    local notes = {}
    for i, note in ipairs(MySQL.query.await('SELECT * FROM justice_report_notes WHERE report_id = ? ORDER BY id DESC', { reportId }) or {}) do
        notes[i] = { author = JS.Safe(note.author_name), note = JS.Safe(note.note), date = FormatAt(note.created_at) }
    end
    local extras = JS.GetCaseExtras(reportId)
    return { ok = true, case = {
        id = row.id, title = JS.Safe(row.title ~= '' and row.title or ('قضية #' .. row.id)), caseType = row.case_type,
        status = row.status, statusLabel = JS.StatusLabels[row.status] or row.status, date = row.date,
        plaintiff = JS.Safe(row.name), defendant = JS.Safe(row.defendant_name ~= '' and row.defendant_name or 'غير محدد'),
        report = JS.Safe(row.report), witnesses = JS.Safe(row.witnesses), evidence = JS.Safe(row.evidence),
        notes = notes, documents = extras.documents, lawyers = extras.lawyers, verdicts = extras.verdicts,
    } }
end)

JS.RegisterCallback('RespectJustice:server:lawyerNote', LawyerOnly, function(src, Player, reportId, note)
    reportId = tonumber(reportId)
    note = JS.CleanText(note, Settings.ReportNoteMax, true)
    if not reportId or not note then return { ok = false, err = 'الملاحظة مطلوبة' } end
    if not IsAssignedLawyer(Player, reportId) then return { ok = false, err = 'أنت غير معيّن في هذه القضية' } end
    MySQL.insert.await('INSERT INTO justice_report_notes (report_id, author_citizenid, author_name, note) VALUES (?, ?, ?, ?)', {
        reportId, Player.PlayerData.citizenid, 'المحامي ' .. JS.PlayerName(Player), note
    })
    return { ok = true }
end)

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- الأحكام (تتنفذ تلقائياً وتنلغى بالتراجع)
-- ════════════════════════════════════════════════════════════════════════════════════════════════

local function MapVerdict(row)
    return {
        id = row.id, reportId = row.report_id, citizenid = row.citizenid, name = JS.Safe(row.name),
        type = row.type, typeLabel = JS.VerdictTypes[row.type] or row.type,
        amount = tonumber(row.amount) or 0, target = row.target_citizenid ~= '' and row.target_citizenid or nil,
        plate = row.plate ~= '' and row.plate or nil, months = tonumber(row.months) or 0,
        text = JS.Safe(row.text), judge = JS.Safe(row.judge_name), status = row.status,
        statusLabel = row.status == 'cancelled' and 'ملغي' or 'نافذ', date = FormatAt(row.created_at),
    }
end

function JS.GetVerdicts(citizenid, reportId)
    local rows
    if reportId then
        rows = MySQL.query.await('SELECT * FROM justice_verdicts WHERE report_id = ? ORDER BY id DESC', { reportId })
    else
        rows = MySQL.query.await('SELECT * FROM justice_verdicts WHERE citizenid = ? ORDER BY id DESC LIMIT 50', { citizenid })
    end
    local list = {}
    for i, row in ipairs(rows or {}) do list[i] = MapVerdict(row) end
    return list
end

-- data = { reportId?, citizenid, type, amount?, target?, plate?, months?, text }
JS.RegisterCallback('RespectJustice:server:issueVerdict', 'verdicts', function(src, Player, data)
    if type(data) ~= 'table' then return { ok = false, err = 'بيانات غير صحيحة' } end
    local vType = data.type
    if not JS.VerdictTypes[vType] then return { ok = false, err = 'نوع الحكم غير معروف' } end

    local citizenid = JS.ValidCitizenId(data.citizenid)
    local text = JS.CleanText(data.text, 400, true)
    local reportId = tonumber(data.reportId)
    if not citizenid then return { ok = false, err = 'الرقم الوطني للمحكوم عليه غير صحيح' } end
    if not text then return { ok = false, err = 'نص الحكم مطلوب (400 حرف كحد أقصى)' } end
    if citizenid == Player.PlayerData.citizenid then return { ok = false, err = 'لا يمكنك إصدار حكم على نفسك' } end
    if reportId and not MySQL.scalar.await('SELECT id FROM justice_reports WHERE id = ?', { reportId }) then reportId = nil end

    local citizen = JS.GetCitizen(citizenid)
    if not citizen then return { ok = false, err = 'لا يوجد مواطن بهذا الرقم الوطني' } end
    local name = JS.FullName(citizen.charinfo)

    local amount, target, plate, months, dest = 0, '', '', 0, nil

    if vType == 'fine' or vType == 'compensation' then
        amount = math.floor(tonumber(data.amount) or 0)
        if amount <= 0 or amount > V.MaxFine then return { ok = false, err = ('المبلغ بين 1 و %d'):format(V.MaxFine) } end
        if vType == 'compensation' then
            target = JS.ValidCitizenId(data.target) or ''
            if target == '' or target == citizenid then return { ok = false, err = 'الرقم الوطني للمتضرر غير صحيح' } end
            if not JS.GetCitizen(target) then return { ok = false, err = 'المتضرر غير موجود' } end
        end
        local ok, err = JS.TakeMoney(citizenid, amount, 'justice-verdict')
        if not ok then return { ok = false, err = 'تعذر تنفيذ الحكم: ' .. tostring(err) } end
        if vType == 'fine' then
            dest = JS.DepositWithdrawn(Player, amount, 'justice-fine')
        else
            local gave = JS.GiveMoney(target, amount, 'justice-compensation-verdict')
            if not gave then
                JS.GiveMoney(citizenid, amount, 'justice-verdict-rollback')
                return { ok = false, err = 'تعذر تحويل التعويض للمتضرر، تم إرجاع المبلغ' }
            end
            local t = RTCore.Functions.GetPlayerByCitizenId(target)
            if t then Notify(t.PlayerData.source, ('⚖️ صدر حكم لصالحك بتعويض $%d'):format(amount), 'success', 10000) end
        end

    elseif vType == 'impound' then
        plate = tostring(data.plate or ''):upper():gsub('^%s+', ''):gsub('%s+$', '')
        if plate == '' then return { ok = false, err = 'رقم اللوحة مطلوب' } end
        local owner = MySQL.scalar.await(('SELECT citizenid FROM `%s` WHERE UPPER(plate) = ?'):format(Settings.Database.Vehicles), { plate })
        if owner ~= citizenid then return { ok = false, err = 'المركبة غير مسجلة باسم المحكوم عليه' } end
        local r = H('vehicleAction')(src, Player, plate, 'impound')
        if not r or not r.ok then return r or { ok = false, err = 'تعذر حجز المركبة' } end

    elseif vType == 'jail' then
        months = math.floor(tonumber(data.months) or 0)
        if months <= 0 or months > V.MaxJail then return { ok = false, err = ('مدة السجن بين 1 و %d شهر'):format(V.MaxJail) } end
        if V.JailEvent ~= '' and citizen.online then
            TriggerEvent(V.JailEvent, citizen.online.PlayerData.source, months, text)
        end
        JS.BroadcastTablet(JS.PoliceOnDuty, { type = 'verdict', title = '🔨 حكم سجن', text = ('%s (%s): %d شهر - %s'):format(name, citizenid, months, text) })

    elseif vType == 'suspend' then
        if JS.Suspended[citizenid] then return { ok = false, err = 'خدماته موقوفة مسبقاً' } end
        local r = H('suspendCitizen')(src, Player, citizenid, 'حكم قضائي: ' .. text)
        if not r or not r.ok then return r or { ok = false, err = 'تعذر إيقاف الخدمات' } end
    end

    local id = MySQL.insert.await([[
        INSERT INTO justice_verdicts (report_id, citizenid, name, type, amount, target_citizenid, plate, months, text, dest, judge_cid, judge_name)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], { reportId, citizenid, name, vType, amount, target, plate, months, text, dest and json.encode(dest) or '', Player.PlayerData.citizenid, JS.PlayerName(Player) })

    if reportId then
        MySQL.update.await("UPDATE justice_reports SET status = 'closed', handled_by = ? WHERE id = ?", { JS.PlayerName(Player), reportId })
        MySQL.insert('INSERT INTO justice_report_notes (report_id, author_citizenid, author_name, note) VALUES (?, ?, ?, ?)', {
            reportId, Player.PlayerData.citizenid, JS.PlayerName(Player), ('صدر حكم #%d: %s - %s'):format(id or 0, JS.VerdictTypes[vType], text)
        })
    end

    if citizen.online then
        Notify(citizen.online.PlayerData.source, ('⚖️ صدر بحقك حكم: %s\n%s'):format(JS.VerdictTypes[vType], text), 'error', 12000)
    end

    JS.Log(Player, 'verdict', citizenid, name, {
        ['الحكم'] = JS.VerdictTypes[vType], ['النص'] = text,
        ['المبلغ'] = amount > 0 and amount or nil, ['المركبة'] = plate ~= '' and plate or nil, ['المدة'] = months > 0 and months or nil,
        ['القضية'] = reportId,
    }, { id = id })

    return { ok = true, id = id }
end)

-- عكس الحكم (يستخدمه نظام التراجع)
function JS.ReverseVerdict(src, Player, verdictId)
    local row = MySQL.single.await("SELECT * FROM justice_verdicts WHERE id = ? AND status = 'active'", { verdictId })
    if not row then return { ok = false, err = 'الحكم غير موجود أو ملغي' } end
    local amount = tonumber(row.amount) or 0

    if row.type == 'fine' then
        local ok, err = JS.ReverseDeposit(JS.Decode(row.dest), amount)
        if not ok then return { ok = false, err = err } end
        JS.GiveMoney(row.citizenid, amount, 'justice-verdict-undo')
    elseif row.type == 'compensation' then
        local ok, err = JS.TakeMoney(row.target_citizenid, amount, 'justice-verdict-undo')
        if not ok then return { ok = false, err = 'المتضرر رصيده ما يكفي لإرجاع التعويض (' .. tostring(err) .. ')' } end
        JS.GiveMoney(row.citizenid, amount, 'justice-verdict-undo')
    elseif row.type == 'impound' then
        local r = H('vehicleAction')(src, Player, row.plate, 'release')
        if not r or not r.ok then return r or { ok = false, err = 'تعذر فك الحجز' } end
    elseif row.type == 'suspend' and JS.Suspended[row.citizenid] then
        H('unsuspendCitizen')(src, Player, row.citizenid)
    end

    MySQL.update.await("UPDATE justice_verdicts SET status = 'cancelled' WHERE id = ?", { verdictId })
    local target = RTCore.Functions.GetPlayerByCitizenId(row.citizenid)
    if target then Notify(target.PlayerData.source, ('⚖️ تم إلغاء الحكم #%d الصادر بحقك'):format(verdictId), 'success', 10000) end
    return { ok = true }
end

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- معلومات القضاء في ملف المواطن
-- ════════════════════════════════════════════════════════════════════════════════════════════════

function JS.GetCourtInfo(citizenid)
    return {
        suspect = JS.GetSuspect(citizenid),
        warrants = JS.GetWarrants(citizenid, false),
        verdicts = JS.GetVerdicts(citizenid),
    }
end

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- الإحصائيات
-- ════════════════════════════════════════════════════════════════════════════════════════════════

local function DutyHours(days)
    local since = os.time() - days * 86400
    local rows = MySQL.query.await('SELECT citizenid, name, duty_status, timestamp FROM justice_duty_history WHERE timestamp >= ? ORDER BY citizenid, timestamp', { since - 86400 }) or {}
    local totals, names, open = {}, {}, {}
    for _, row in ipairs(rows) do
        local cid, t = row.citizenid, tonumber(row.timestamp) or 0
        names[cid] = row.name
        if row.duty_status == 'بدأ الدوام' then
            open[cid] = t
        elseif open[cid] then
            local from = math.max(open[cid], since)
            if t > from then totals[cid] = (totals[cid] or 0) + math.min(t - from, 16 * 3600) end
            open[cid] = nil
        end
    end
    -- اللي لسا في الدوام الآن
    for cid, startedAt in pairs(open) do
        local P = RTCore.Functions.GetPlayerByCitizenId(cid)
        if P and P.PlayerData.job.onduty then
            local from = math.max(startedAt, since)
            totals[cid] = (totals[cid] or 0) + math.min(os.time() - from, 16 * 3600)
        end
    end
    local list = {}
    for cid, seconds in pairs(totals) do
        list[#list + 1] = { label = JS.Safe(names[cid] or cid), value = math.floor(seconds / 360) / 10 }
    end
    table.sort(list, function(a, b) return a.value > b.value end)
    for i = #list, 11, -1 do list[i] = nil end
    return list
end

JS.RegisterCallback('RespectJustice:server:getStats', 'stats', function()
    -- القضايا بالأسبوع (آخر 8 أسابيع)
    local weeks = {}
    for i = 1, 8 do weeks[i] = 0 end
    for _, row in ipairs(MySQL.query.await('SELECT FLOOR(DATEDIFF(CURDATE(), DATE(created_at)) / 7) AS w, COUNT(*) AS c FROM justice_reports WHERE job = ? AND created_at >= CURDATE() - INTERVAL 55 DAY GROUP BY w', { JS.Job }) or {}) do
        local w = tonumber(row.w)
        if w and w >= 0 and w < 8 then weeks[8 - w] = tonumber(row.c) or 0 end
    end
    local weekLabels = { 'قبل 7 أسابيع', 'قبل 6', 'قبل 5', 'قبل 4', 'قبل 3', 'قبل أسبوعين', 'الأسبوع الماضي', 'هذا الأسبوع' }
    local casesPerWeek = {}
    for i = 1, 8 do casesPerWeek[i] = { label = weekLabels[i], value = weeks[i] } end

    local caseTypes = {}
    for i, row in ipairs(MySQL.query.await("SELECT IF(case_type = '', 'غير محدد', case_type) AS t, COUNT(*) AS c FROM justice_reports WHERE job = ? GROUP BY t ORDER BY c DESC LIMIT 10", { JS.Job }) or {}) do
        caseTypes[i] = { label = JS.Safe(row.t), value = tonumber(row.c) or 0 }
    end

    local officers = {}
    for i, row in ipairs(MySQL.query.await("SELECT officer_name AS n, COUNT(*) AS c FROM justice_logs WHERE created_at >= NOW() - INTERVAL 30 DAY AND action NOT IN ('view', 'locate', 'log_delete') GROUP BY officer_citizenid, officer_name ORDER BY c DESC LIMIT 10") or {}) do
        officers[i] = { label = JS.Safe(row.n), value = tonumber(row.c) or 0 }
    end

    local verdictTypes = {}
    for i, row in ipairs(MySQL.query.await("SELECT type AS t, COUNT(*) AS c FROM justice_verdicts WHERE status = 'active' GROUP BY t ORDER BY c DESC") or {}) do
        verdictTypes[i] = { label = JS.VerdictTypes[row.t] or row.t, value = tonumber(row.c) or 0 }
    end

    ExpireWarrants()
    return {
        ok = true,
        casesPerWeek = casesPerWeek,
        caseTypes = caseTypes,
        officers = officers,
        dutyHours = DutyHours(7),
        verdictTypes = verdictTypes,
        totals = {
            cases = tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM justice_reports WHERE job = ?', { JS.Job })) or 0,
            verdicts = tonumber(MySQL.scalar.await("SELECT COUNT(*) FROM justice_verdicts WHERE status = 'active'")) or 0,
            warrants = tonumber(MySQL.scalar.await("SELECT COUNT(*) FROM justice_warrants WHERE status = 'active'")) or 0,
            suspects = tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM justice_suspects WHERE active = 1')) or 0,
        },
    }
end)
