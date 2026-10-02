local Settings = JC.Settings

JC.Reports = {}

local StatusIcons = { new = 'fas fa-circle-exclamation', review = 'fas fa-hourglass-half', closed = 'fas fa-circle-check' }
local StatusColors = { new = 'red', review = 'yellow', closed = 'green' }
local currentFilter = nil

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- Filing a lawsuit (citizens)
-- ════════════════════════════════════════════════════════════════════════════════════════════════

function JC.Reports.OpenSubmit()
    local caseTypes = {}
    for i, label in ipairs(Settings.CaseTypes) do
        caseTypes[i] = { value = tostring(i), label = label }
    end

    local input = lib.inputDialog(('File a Lawsuit (fee %s)'):format(JC.Money(Settings.ReportFee)), {
        { type = 'input', label = 'Case title', description = 'A short summary of the case', required = true, min = 3, max = Settings.ReportTitleMax, icon = 'heading' },
        { type = 'select', label = 'Case type', options = caseTypes, required = true, icon = 'scale-balanced' },
        { type = 'input', label = 'Defendant name', description = 'Leave empty if none', max = 60, icon = 'user' },
        { type = 'input', label = 'Defendant citizen ID', description = 'Optional, helps process the case faster', max = 50, icon = 'id-card' },
        { type = 'input', label = 'Witnesses', description = 'Witness names and numbers (optional)', max = Settings.ReportWitnessesMax, icon = 'users' },
        { type = 'textarea', label = 'Evidence', description = 'Photos, videos, links or a description of the evidence (optional)', max = Settings.ReportEvidenceMax, autosize = true },
        { type = 'textarea', label = 'Complaint', description = ('Explain what happened in detail (%d - %d characters)'):format(Settings.ReportMinLength, Settings.ReportMaxLength), required = true, min = Settings.ReportMinLength, max = Settings.ReportMaxLength, autosize = true },
    })
    if not input then return end

    local data = {
        title = JUtil.Functions.trim(input[1]) or '',
        caseType = tonumber(input[2]),
        defendantName = JUtil.Functions.trim(input[3]) or '',
        defendantCitizenid = JUtil.Functions.trim(input[4]) or '',
        witnesses = JUtil.Functions.trim(input[5]) or '',
        evidence = JUtil.Functions.trim(input[6]) or '',
        report = JUtil.Functions.trim(input[7]) or '',
    }

    local length = JC.Utf8Len(data.report)
    if length < Settings.ReportMinLength or length > Settings.ReportMaxLength then
        return JC.Notify(('The complaint must be between %d and %d characters'):format(Settings.ReportMinLength, Settings.ReportMaxLength), 'error')
    end
    if JC.Utf8Len(data.title) < 3 then
        return JC.Notify('The case title is too short', 'error')
    end

    local confirm = lib.alertDialog({
        header = 'Confirm Filing',
        content = ('**Title:** %s\n\n**Type:** %s\n\n**Defendant:** %s\n\n**%s** will be taken from your cash. Continue?'):format(
            data.title, Settings.CaseTypes[data.caseType] or '-', data.defendantName ~= '' and data.defendantName or '-', JC.Money(Settings.ReportFee)),
        centered = true,
        cancel = true,
    })
    if confirm ~= 'confirm' then return end

    TriggerServerEvent('NomadJustice:server:submitReport', data)
end

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- Case list (staff)
-- ════════════════════════════════════════════════════════════════════════════════════════════════

function JC.Reports.OpenList(filter, parent)
    currentFilter = filter
    local result = JC.Call('NomadJustice:server:getJobReports', filter)
    if not result then return end

    local counts = result.counts or {}
    local options = {
        {
            title = 'Filter Cases',
            description = ('Current: %s'):format(filter and JC.StatusLabel(filter) or 'All'),
            icon = 'fas fa-filter',
            onSelect = function()
                local choice = lib.inputDialog('Filter Cases', {
                    { type = 'select', label = 'Status', required = true, default = filter or 'all', options = {
                        { value = 'all', label = 'All' },
                        { value = 'new', label = ('New (%d)'):format(counts.new or 0) },
                        { value = 'review', label = ('Under Review (%d)'):format(counts.review or 0) },
                        { value = 'closed', label = ('Closed (%d)'):format(counts.closed or 0) },
                    } },
                })
                if not choice then return JC.Reports.OpenList(filter, parent) end
                JC.Reports.OpenList(choice[1] ~= 'all' and choice[1] or nil, parent)
            end,
        },
    }

    if #result.reports == 0 then
        options[#options + 1] = { title = 'No cases', disabled = true }
    end

    for _, report in ipairs(result.reports) do
        options[#options + 1] = {
            title = ('#%d | %s'):format(report.id, report.title),
            description = ('%s | %s %s | %s%s'):format(report.caseType, report.submitterOnline and '🟢' or '⚫', report.name, report.date,
                report.defendantName and (' | v. ' .. report.defendantName) or ''),
            icon = StatusIcons[report.status] or StatusIcons.new,
            iconColor = StatusColors[report.status],
            metadata = {
                { label = 'Status', value = report.statusLabel },
                { label = 'Handled by', value = report.handledBy or '-' },
            },
            arrow = true,
            onSelect = function() JC.Reports.OpenDetails(report.id) end,
        }
    end

    lib.registerContext({
        id = 'justice_reports_list',
        title = ('Cases | New %d | Under Review %d | Closed %d'):format(counts.new or 0, counts.review or 0, counts.closed or 0),
        menu = parent,
        options = options,
    })
    lib.showContext('justice_reports_list')
end

function JC.StatusLabel(status)
    return ({ new = 'New', review = 'Under Review', closed = 'Closed' })[status] or status
end

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- Case details
-- ════════════════════════════════════════════════════════════════════════════════════════════════

local function ShowText(title, text)
    lib.alertDialog({ header = title, content = text or '-', centered = true, size = 'lg' })
end

function JC.Reports.OpenDetails(reportId, parent)
    local result = JC.Call('NomadJustice:server:getReport', reportId)
    if not result then return end

    local report, perms = result.report, result.perms or {}
    local submitter = report.submitter or {}
    local reopen = function() JC.Reports.OpenDetails(reportId, parent) end

    local options = {
        {
            title = ('Status: %s'):format(report.statusLabel),
            description = report.handledBy and ('Last updated by: ' .. report.handledBy) or 'Not handled yet',
            icon = StatusIcons[report.status],
            iconColor = StatusColors[report.status],
        },
        { title = 'Case type', description = report.caseType, icon = 'fas fa-scale-balanced' },
        { title = 'Filed on', description = report.date, icon = 'fas fa-calendar' },
        {
            title = 'Complaint',
            description = report.report,
            icon = 'fas fa-file-lines',
            onSelect = function() ShowText('Case #' .. report.id .. ' complaint', report.report) reopen() end,
        },
    }

    -- Plaintiff
    options[#options + 1] = {
        title = ('Plaintiff: %s'):format(report.name),
        description = ('%s\nCitizen ID: %s | Phone: %s'):format(report.submitterStatus or (report.submitterOnline and '🟢 Online' or '⚫ Offline'),
            report.citizenid, JC.Value(report.phoneNumber)),
        icon = 'fas fa-user',
        iconColor = report.submitterOnline and 'green' or 'gray',
        metadata = {
            { label = 'Date of birth', value = JC.Value(submitter.birthdate) },
            { label = 'Sex', value = JC.Gender(submitter.gender) },
            { label = 'Nationality', value = JC.Value(submitter.nationality) },
            { label = 'Job', value = JC.Value(submitter.job) .. (submitter.jobGrade and (' - ' .. submitter.jobGrade) or '') },
            { label = 'Gang', value = JC.Value(submitter.gang) },
            { label = 'Bank account', value = JC.Value(submitter.account) },
            { label = 'Filing location', value = JC.GetStreet(submitter.coords) },
        },
        arrow = perms.view,
        onSelect = perms.view and function() JC.Panel.OpenProfile(report.citizenid, 'justice_report_details') end or nil,
    }

    -- Defendant
    options[#options + 1] = {
        title = ('Defendant: %s'):format(report.defendantName or 'Not specified'),
        description = report.defendantCitizenid and ('%s\nCitizen ID: %s'):format(report.defendantStatus or '', report.defendantCitizenid) or 'No citizen ID given',
        icon = 'fas fa-user-slash',
        arrow = perms.view and report.defendantCitizenid ~= nil,
        onSelect = (perms.view and report.defendantCitizenid) and function()
            JC.Panel.OpenProfile(report.defendantCitizenid, 'justice_report_details')
        end or nil,
    }

    if report.witnesses then
        options[#options + 1] = {
            title = 'Witnesses', description = report.witnesses, icon = 'fas fa-users',
            onSelect = function() ShowText('Witnesses', report.witnesses) reopen() end,
        }
    end
    if report.evidence then
        options[#options + 1] = {
            title = 'Evidence', description = report.evidence, icon = 'fas fa-magnifying-glass',
            onSelect = function() ShowText('Evidence', report.evidence) reopen() end,
        }
    end

    -- Notes
    options[#options + 1] = {
        title = ('Staff Notes (%d)'):format(#report.notes),
        icon = 'fas fa-note-sticky',
        arrow = #report.notes > 0,
        disabled = #report.notes == 0,
        onSelect = function()
            local noteOptions = {}
            for i, note in ipairs(report.notes) do
                noteOptions[i] = { title = note.author, description = note.note, metadata = { { label = 'Date', value = JC.Value(note.date) } } }
            end
            lib.registerContext({ id = 'justice_report_notes', title = 'Case #' .. report.id .. ' notes', menu = 'justice_report_details', options = noteOptions })
            lib.showContext('justice_report_notes')
        end,
    }

    -- Actions
    if submitter.coords then
        options[#options + 1] = {
            title = 'Mark Filing Location', icon = 'fas fa-location-dot',
            onSelect = function()
                JC.TempBlip(submitter.coords, 'Case #' .. report.id .. ' location', 60, 162, 5)
                JC.Notify('Location marked on the map', 'success')
            end,
        }
    end

    options[#options + 1] = {
        title = 'Change Case Status', icon = 'fas fa-pen-to-square',
        onSelect = function()
            local input = lib.inputDialog('Change status of case #' .. report.id, {
                { type = 'select', label = 'Status', required = true, default = report.status, options = {
                    { value = 'new', label = 'New' },
                    { value = 'review', label = 'Under Review' },
                    { value = 'closed', label = 'Closed' },
                } },
            })
            if input and input[1] ~= report.status then
                if JC.Call('NomadJustice:server:setReportStatus', report.id, input[1]) then
                    JC.Notify('Case status updated', 'success')
                end
            end
            reopen()
        end,
    }

    options[#options + 1] = {
        title = 'Add Note', icon = 'fas fa-comment-medical',
        onSelect = function()
            local input = lib.inputDialog('Note on case #' .. report.id, {
                { type = 'textarea', label = 'Note', required = true, max = JC.Settings.ReportNoteMax, autosize = true },
            })
            if input and input[1] and JC.Call('NomadJustice:server:addReportNote', report.id, input[1]) then
                JC.Notify('Note added', 'success')
            end
            reopen()
        end,
    }

    if perms.deleteReport then
        options[#options + 1] = {
            title = 'Delete Case', icon = 'fas fa-trash', iconColor = 'red',
            onSelect = function()
                local confirm = lib.alertDialog({
                    header = 'Delete case #' .. report.id,
                    content = 'Are you sure you want to delete this case and all its notes? This cannot be undone.',
                    centered = true,
                    cancel = true,
                })
                if confirm == 'confirm' and JC.Call('NomadJustice:server:deleteReport', report.id) then
                    JC.Notify('Case deleted', 'success')
                    return JC.Reports.OpenList(currentFilter)
                end
                reopen()
            end,
        }
    end

    lib.registerContext({
        id = 'justice_report_details',
        title = ('Case #%d | %s'):format(report.id, report.title),
        menu = parent or 'justice_reports_list',
        options = options,
    })
    lib.showContext('justice_report_details')
end

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- A citizen's own lawsuits
-- ════════════════════════════════════════════════════════════════════════════════════════════════

function JC.Reports.OpenMine(parent)
    local result = JC.Call('NomadJustice:server:getMyReports')
    if not result then return end

    local options = {}
    for i, report in ipairs(result.reports) do
        options[i] = {
            title = ('#%d | %s'):format(report.id, report.title),
            description = ('%s | %s%s'):format(report.caseType, report.date, report.defendantName and (' | v. ' .. report.defendantName) or ''),
            icon = StatusIcons[report.status] or StatusIcons.new,
            iconColor = StatusColors[report.status],
            metadata = { { label = 'Status', value = report.statusLabel }, { label = 'Handled by', value = report.handledBy or '-' } },
        }
    end
    if #options == 0 then options[1] = { title = 'You have not filed any lawsuit', disabled = true } end

    lib.registerContext({ id = 'justice_my_reports', title = 'My Lawsuits', menu = parent, options = options })
    lib.showContext('justice_my_reports')
end
