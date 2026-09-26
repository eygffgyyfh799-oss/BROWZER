local Settings = JC.Settings

JC.Reports = {}

local StatusIcons = { new = 'fas fa-circle-exclamation', review = 'fas fa-hourglass-half', closed = 'fas fa-circle-check' }
local StatusColors = { new = 'red', review = 'yellow', closed = 'green' }
local currentFilter = nil

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- تقديم دعوى (للمواطنين)
-- ════════════════════════════════════════════════════════════════════════════════════════════════

function JC.Reports.OpenSubmit()
    local caseTypes = {}
    for i, label in ipairs(Settings.CaseTypes) do
        caseTypes[i] = { value = tostring(i), label = label }
    end

    local input = lib.inputDialog(('تقديم دعوى قضائية (الرسوم %s)'):format(JC.Money(Settings.ReportFee)), {
        { type = 'input', label = 'عنوان الدعوى', description = 'وصف مختصر للدعوى', required = true, min = 3, max = Settings.ReportTitleMax, icon = 'heading' },
        { type = 'select', label = 'نوع الدعوى', options = caseTypes, required = true, icon = 'scale-balanced' },
        { type = 'input', label = 'اسم المدعى عليه', description = 'اتركه فارغاً إذا لا يوجد', max = 60, icon = 'user' },
        { type = 'input', label = 'الرقم الوطني للمدعى عليه', description = 'اختياري، يساعد في سرعة معالجة الدعوى', max = 50, icon = 'id-card' },
        { type = 'input', label = 'الشهود', description = 'أسماء الشهود وأرقامهم (اختياري)', max = Settings.ReportWitnessesMax, icon = 'users' },
        { type = 'textarea', label = 'الأدلة', description = 'صور، فيديوهات، روابط أو وصف الأدلة (اختياري)', max = Settings.ReportEvidenceMax, autosize = true },
        { type = 'textarea', label = 'تفاصيل الدعوى', description = ('اشرح ما حدث بالتفصيل (%d - %d حرف)'):format(Settings.ReportMinLength, Settings.ReportMaxLength), required = true, min = Settings.ReportMinLength, max = Settings.ReportMaxLength, autosize = true },
    })
    if not input then return end

    local data = {
        title = _2rayan.Functions.trim(input[1]) or '',
        caseType = tonumber(input[2]),
        defendantName = _2rayan.Functions.trim(input[3]) or '',
        defendantCitizenid = _2rayan.Functions.trim(input[4]) or '',
        witnesses = _2rayan.Functions.trim(input[5]) or '',
        evidence = _2rayan.Functions.trim(input[6]) or '',
        report = _2rayan.Functions.trim(input[7]) or '',
    }

    local length = JC.Utf8Len(data.report)
    if length < Settings.ReportMinLength or length > Settings.ReportMaxLength then
        return JC.Notify(('تفاصيل الدعوى يجب أن تكون بين %d و %d حرف'):format(Settings.ReportMinLength, Settings.ReportMaxLength), 'error')
    end
    if JC.Utf8Len(data.title) < 3 then
        return JC.Notify('عنوان الدعوى قصير جداً', 'error')
    end

    local confirm = lib.alertDialog({
        header = 'تأكيد تقديم الدعوى',
        content = ('**العنوان:** %s\n\n**النوع:** %s\n\n**المدعى عليه:** %s\n\nسيتم خصم **%s** من الكاش. هل تريد المتابعة؟'):format(
            data.title, Settings.CaseTypes[data.caseType] or '-', data.defendantName ~= '' and data.defendantName or '-', JC.Money(Settings.ReportFee)),
        centered = true,
        cancel = true,
    })
    if confirm ~= 'confirm' then return end

    TriggerServerEvent('RespectJustice:server:submitReport', data)
end

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- قائمة القضايا (للموظفين)
-- ════════════════════════════════════════════════════════════════════════════════════════════════

function JC.Reports.OpenList(filter, parent)
    currentFilter = filter
    local result = JC.Call('RespectJustice:server:getJobReports', filter)
    if not result then return end

    local counts = result.counts or {}
    local options = {
        {
            title = 'تصفية القضايا',
            description = ('الحالية: %s'):format(filter and JC.StatusLabel(filter) or 'الكل'),
            icon = 'fas fa-filter',
            onSelect = function()
                local choice = lib.inputDialog('تصفية القضايا', {
                    { type = 'select', label = 'الحالة', required = true, default = filter or 'all', options = {
                        { value = 'all', label = 'الكل' },
                        { value = 'new', label = ('جديدة (%d)'):format(counts.new or 0) },
                        { value = 'review', label = ('قيد النظر (%d)'):format(counts.review or 0) },
                        { value = 'closed', label = ('مغلقة (%d)'):format(counts.closed or 0) },
                    } },
                })
                if not choice then return JC.Reports.OpenList(filter, parent) end
                JC.Reports.OpenList(choice[1] ~= 'all' and choice[1] or nil, parent)
            end,
        },
    }

    if #result.reports == 0 then
        options[#options + 1] = { title = 'لا توجد قضايا', disabled = true }
    end

    for _, report in ipairs(result.reports) do
        options[#options + 1] = {
            title = ('#%d | %s'):format(report.id, report.title),
            description = ('%s | %s | %s%s'):format(report.caseType, report.name, report.date,
                report.defendantName and (' | ضد: ' .. report.defendantName) or ''),
            icon = StatusIcons[report.status] or StatusIcons.new,
            iconColor = StatusColors[report.status],
            metadata = {
                { label = 'الحالة', value = report.statusLabel },
                { label = 'المعالج', value = report.handledBy or '-' },
            },
            arrow = true,
            onSelect = function() JC.Reports.OpenDetails(report.id) end,
        }
    end

    lib.registerContext({
        id = 'justice_reports_list',
        title = ('القضايا | جديدة %d | قيد النظر %d | مغلقة %d'):format(counts.new or 0, counts.review or 0, counts.closed or 0),
        menu = parent,
        options = options,
        rt_logo = true,
    })
    lib.showContext('justice_reports_list')
end

function JC.StatusLabel(status)
    return ({ new = 'جديدة', review = 'قيد النظر', closed = 'مغلقة' })[status] or status
end

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- تفاصيل القضية
-- ════════════════════════════════════════════════════════════════════════════════════════════════

local function ShowText(title, text)
    lib.alertDialog({ header = title, content = text or '-', centered = true, size = 'lg' })
end

function JC.Reports.OpenDetails(reportId, parent)
    local result = JC.Call('RespectJustice:server:getReport', reportId)
    if not result then return end

    local report, perms = result.report, result.perms or {}
    local submitter = report.submitter or {}
    local reopen = function() JC.Reports.OpenDetails(reportId, parent) end

    local options = {
        {
            title = ('الحالة: %s'):format(report.statusLabel),
            description = report.handledBy and ('آخر تحديث بواسطة: ' .. report.handledBy) or 'لم يتم التعامل معها بعد',
            icon = StatusIcons[report.status],
            iconColor = StatusColors[report.status],
        },
        { title = 'نوع الدعوى', description = report.caseType, icon = 'fas fa-scale-balanced' },
        { title = 'تاريخ التقديم', description = report.date, icon = 'fas fa-calendar' },
        {
            title = 'تفاصيل الدعوى',
            description = report.report,
            icon = 'fas fa-file-lines',
            onSelect = function() ShowText('تفاصيل القضية #' .. report.id, report.report) reopen() end,
        },
    }

    -- مقدم الدعوى
    options[#options + 1] = {
        title = ('مقدم الدعوى: %s'):format(report.name),
        description = ('الرقم الوطني: %s | الجوال: %s | %s'):format(report.citizenid, JC.Value(report.phoneNumber),
            report.submitterOnline and 'متصل' or 'غير متصل'),
        icon = 'fas fa-user',
        iconColor = report.submitterOnline and 'green' or 'gray',
        metadata = {
            { label = 'تاريخ الميلاد', value = JC.Value(submitter.birthdate) },
            { label = 'الجنس', value = JC.Gender(submitter.gender) },
            { label = 'الجنسية', value = JC.Value(submitter.nationality) },
            { label = 'الوظيفة', value = JC.Value(submitter.job) .. (submitter.jobGrade and (' - ' .. submitter.jobGrade) or '') },
            { label = 'العصابة', value = JC.Value(submitter.gang) },
            { label = 'رقم الحساب', value = JC.Value(submitter.account) },
            { label = 'موقع التقديم', value = JC.GetStreet(submitter.coords) },
        },
        arrow = perms.view,
        onSelect = perms.view and function() JC.Panel.OpenProfile(report.citizenid, 'justice_report_details') end or nil,
    }

    -- المدعى عليه
    options[#options + 1] = {
        title = ('المدعى عليه: %s'):format(report.defendantName or 'غير محدد'),
        description = report.defendantCitizenid and ('الرقم الوطني: ' .. report.defendantCitizenid) or 'لم يتم تحديد رقم وطني',
        icon = 'fas fa-user-slash',
        arrow = perms.view and report.defendantCitizenid ~= nil,
        onSelect = (perms.view and report.defendantCitizenid) and function()
            JC.Panel.OpenProfile(report.defendantCitizenid, 'justice_report_details')
        end or nil,
    }

    if report.witnesses then
        options[#options + 1] = {
            title = 'الشهود', description = report.witnesses, icon = 'fas fa-users',
            onSelect = function() ShowText('الشهود', report.witnesses) reopen() end,
        }
    end
    if report.evidence then
        options[#options + 1] = {
            title = 'الأدلة', description = report.evidence, icon = 'fas fa-magnifying-glass',
            onSelect = function() ShowText('الأدلة', report.evidence) reopen() end,
        }
    end

    -- الملاحظات
    options[#options + 1] = {
        title = ('ملاحظات الموظفين (%d)'):format(#report.notes),
        icon = 'fas fa-note-sticky',
        arrow = #report.notes > 0,
        disabled = #report.notes == 0,
        onSelect = function()
            local noteOptions = {}
            for i, note in ipairs(report.notes) do
                noteOptions[i] = { title = note.author, description = note.note, metadata = { { label = 'التاريخ', value = JC.Value(note.date) } } }
            end
            lib.registerContext({ id = 'justice_report_notes', title = 'ملاحظات القضية #' .. report.id, menu = 'justice_report_details', options = noteOptions })
            lib.showContext('justice_report_notes')
        end,
    }

    -- الإجراءات
    if submitter.coords then
        options[#options + 1] = {
            title = 'تحديد موقع تقديم الدعوى', icon = 'fas fa-location-dot',
            onSelect = function()
                JC.TempBlip(submitter.coords, 'موقع دعوى #' .. report.id, 60, 162, 5)
                JC.Notify('تم تحديد الموقع على الخريطة', 'success')
            end,
        }
    end

    options[#options + 1] = {
        title = 'تغيير حالة القضية', icon = 'fas fa-pen-to-square',
        onSelect = function()
            local input = lib.inputDialog('تغيير حالة القضية #' .. report.id, {
                { type = 'select', label = 'الحالة', required = true, default = report.status, options = {
                    { value = 'new', label = 'جديدة' },
                    { value = 'review', label = 'قيد النظر' },
                    { value = 'closed', label = 'مغلقة' },
                } },
            })
            if input and input[1] ~= report.status then
                if JC.Call('RespectJustice:server:setReportStatus', report.id, input[1]) then
                    JC.Notify('تم تحديث حالة القضية', 'success')
                end
            end
            reopen()
        end,
    }

    options[#options + 1] = {
        title = 'إضافة ملاحظة', icon = 'fas fa-comment-medical',
        onSelect = function()
            local input = lib.inputDialog('ملاحظة على القضية #' .. report.id, {
                { type = 'textarea', label = 'الملاحظة', required = true, max = JC.Settings.ReportNoteMax, autosize = true },
            })
            if input and input[1] and JC.Call('RespectJustice:server:addReportNote', report.id, input[1]) then
                JC.Notify('تمت إضافة الملاحظة', 'success')
            end
            reopen()
        end,
    }

    if perms.deleteReport then
        options[#options + 1] = {
            title = 'حذف القضية', icon = 'fas fa-trash', iconColor = 'red',
            onSelect = function()
                local confirm = lib.alertDialog({
                    header = 'حذف القضية #' .. report.id,
                    content = 'هل أنت متأكد من حذف هذه القضية وجميع ملاحظاتها؟ لا يمكن التراجع عن هذا الإجراء.',
                    centered = true,
                    cancel = true,
                })
                if confirm == 'confirm' and JC.Call('RespectJustice:server:deleteReport', report.id) then
                    JC.Notify('تم حذف القضية', 'success')
                    return JC.Reports.OpenList(currentFilter)
                end
                reopen()
            end,
        }
    end

    lib.registerContext({
        id = 'justice_report_details',
        title = ('القضية #%d | %s'):format(report.id, report.title),
        menu = parent or 'justice_reports_list',
        options = options,
        rt_logo = true,
    })
    lib.showContext('justice_report_details')
end

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- متابعة دعاوى المواطن
-- ════════════════════════════════════════════════════════════════════════════════════════════════

function JC.Reports.OpenMine(parent)
    local result = JC.Call('RespectJustice:server:getMyReports')
    if not result then return end

    local options = {}
    for i, report in ipairs(result.reports) do
        options[i] = {
            title = ('#%d | %s'):format(report.id, report.title),
            description = ('%s | %s%s'):format(report.caseType, report.date, report.defendantName and (' | ضد: ' .. report.defendantName) or ''),
            icon = StatusIcons[report.status] or StatusIcons.new,
            iconColor = StatusColors[report.status],
            metadata = { { label = 'الحالة', value = report.statusLabel }, { label = 'المعالج', value = report.handledBy or '-' } },
        }
    end
    if #options == 0 then options[1] = { title = 'لم تقدم أي دعوى', disabled = true } end

    lib.registerContext({ id = 'justice_my_reports', title = 'دعاواي', menu = parent, options = options })
    lib.showContext('justice_my_reports')
end
