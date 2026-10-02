JC.Jobs = {}

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- Pick a department then a grade (used in the citizen record)
-- ════════════════════════════════════════════════════════════════════════════════════════════════

local function PickGrade(job, title, currentLevel)
    if #job.grades == 0 then
        JC.Notify('This department has no grades', 'error')
        return nil
    end

    local options = {}
    for i, grade in ipairs(job.grades) do
        options[i] = { value = tostring(grade.level), label = ('%d - %s%s'):format(grade.level, grade.name, grade.isboss and ' (manager)' or '') }
    end

    local input = lib.inputDialog(title, {
        { type = 'select', label = 'Grade', required = true, options = options, default = currentLevel and tostring(currentLevel) or options[1].value },
    })
    return input and tonumber(input[1]) or nil
end

local function ConfirmAndSet(citizenid, name, jobName, jobLabel, level, gradeName)
    local confirm = lib.alertDialog({
        header = 'Confirm Job Change',
        content = ('**%s** will be appointed to **%s** as **%s**'):format(name, jobLabel, gradeName or level),
        centered = true,
        cancel = true,
    })
    if confirm ~= 'confirm' then return false end

    local result = JC.Call('NomadJustice:server:setCitizenJob', citizenid, jobName, level)
    if result then
        JC.Notify('Appointed: ' .. result.newJob, 'success', 8000)
        return true
    end
    return false
end

local function GradeName(job, level)
    for _, grade in ipairs(job.grades) do
        if grade.level == level then return grade.name end
    end
    return tostring(level)
end

-- Change a citizen's job from their record (any department and grade)
function JC.Jobs.ChangeCitizenJob(citizenid, name)
    local result = JC.Call('NomadJustice:server:getJobs')
    if not result then return end

    local options = {}
    for i, job in ipairs(result.jobs) do
        options[i] = { value = tostring(i), label = ('%s (%s)'):format(job.label, job.name) }
    end

    local input = lib.inputDialog('Change job of ' .. name, {
        { type = 'select', label = 'Department', required = true, searchable = true, options = options },
    })
    local job = input and result.jobs[tonumber(input[1])]
    if not job then return end

    local level = PickGrade(job, ('Grade of %s in %s'):format(name, job.label))
    if not level then return end

    ConfirmAndSet(citizenid, name, job.name, job.label, level, GradeName(job, level))
end

-- Terminate a citizen's employment
function JC.Jobs.Fire(citizenid, name)
    local confirm = lib.alertDialog({
        header = 'Terminate Employment',
        content = ('Are you sure you want to terminate **%s**?'):format(name),
        centered = true,
        cancel = true,
    })
    if confirm ~= 'confirm' then return false end

    local result = JC.Call('NomadJustice:server:setCitizenJob', citizenid, JC.Settings.Panel.UnemployedJob, 0)
    if result then JC.Notify('Employment terminated', 'success') end
    return result ~= nil
end

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- Department list
-- ════════════════════════════════════════════════════════════════════════════════════════════════

function JC.Jobs.OpenList(parent)
    local result = JC.Call('NomadJustice:server:getJobs')
    if not result then return end

    local options = {}
    for _, job in ipairs(result.jobs) do
        options[#options + 1] = {
            title = job.label,
            description = ('Online: %d | On duty: %d | Total staff: %d'):format(job.online, job.onduty, job.total),
            icon = job.onduty > 0 and 'fas fa-building-circle-check' or 'fas fa-building',
            iconColor = job.onduty > 0 and 'green' or nil,
            metadata = { { label = 'Department name', value = job.name }, { label = 'Grades', value = #job.grades } },
            arrow = true,
            onSelect = function() JC.Jobs.OpenJob(job.name) end,
        }
    end
    if #options == 0 then options[1] = { title = 'No departments', disabled = true } end

    lib.registerContext({ id = 'justice_jobs_list', title = ('Departments (%d)'):format(#result.jobs), menu = parent, options = options })
    lib.showContext('justice_jobs_list')
end

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- One department: staff + hiring
-- ════════════════════════════════════════════════════════════════════════════════════════════════

local function OpenMember(job, member, perms)
    local reopen = function() OpenMember(job, member, perms) end
    local back = function() JC.Jobs.OpenJob(job.name) end

    local options = {
        {
            title = member.name ~= '' and member.name or 'Unnamed',
            description = ('%s\nCitizen ID: %s%s'):format(member.status and member.status.text or (member.online and '🟢 Online' or '⚫ Offline'), member.citizenid,
                member.online and (member.onduty and ' | On duty' or ' | Off duty') or ''),
            icon = 'fas fa-user', iconColor = member.online and 'green' or 'gray',
        },
        { title = 'Current grade', description = ('%d - %s%s'):format(member.gradeLevel, member.gradeName, member.isboss and ' (manager)' or ''), icon = 'fas fa-ranking-star' },
        {
            title = 'Open Citizen Record', icon = 'fas fa-id-card', arrow = true,
            onSelect = function() JC.Panel.OpenProfile(member.citizenid, 'justice_job_member') end,
        },
    }

    if perms.jobs then
        options[#options + 1] = {
            title = 'Change Grade', icon = 'fas fa-arrows-up-down', iconColor = 'blue',
            onSelect = function()
                local level = PickGrade(job, ('Grade of %s'):format(member.name), member.gradeLevel)
                if level and level ~= member.gradeLevel
                    and ConfirmAndSet(member.citizenid, member.name, job.name, job.label, level, GradeName(job, level)) then
                    return back()
                end
                reopen()
            end,
        }
        options[#options + 1] = {
            title = 'Transfer to Another Department', icon = 'fas fa-right-left', iconColor = 'yellow',
            onSelect = function()
                JC.Jobs.ChangeCitizenJob(member.citizenid, member.name)
                back()
            end,
        }
        if member.online then
            options[#options + 1] = {
                title = member.onduty and 'Clock Them Out' or 'Clock Them In',
                icon = member.onduty and 'fas fa-right-from-bracket' or 'fas fa-right-to-bracket',
                onSelect = function()
                    if JC.Call('NomadJustice:server:setCitizenDuty', member.citizenid, not member.onduty) then
                        JC.Notify('Duty status changed', 'success')
                        return back()
                    end
                    reopen()
                end,
            }
        end
        if job.name ~= JC.Settings.Panel.UnemployedJob then
            options[#options + 1] = {
                title = 'Terminate from Department', icon = 'fas fa-user-xmark', iconColor = 'red',
                onSelect = function()
                    if JC.Jobs.Fire(member.citizenid, member.name) then return back() end
                    reopen()
                end,
            }
        end
    end

    lib.registerContext({ id = 'justice_job_member', title = ('%s | %s'):format(job.label, member.name), menu = 'justice_job_view', options = options })
    lib.showContext('justice_job_member')
end

function JC.Jobs.OpenJob(jobName)
    local result = JC.Call('NomadJustice:server:getJobMembers', jobName)
    if not result then return end

    local job, perms = result.job, result.perms or {}
    local onlineCount, dutyCount = 0, 0
    for _, m in ipairs(result.members) do
        if m.online then onlineCount = onlineCount + 1 end
        if m.onduty then dutyCount = dutyCount + 1 end
    end

    local options = {
        {
            title = ('%s | Staff: %d'):format(job.label, #result.members),
            description = ('Online: %d | On duty: %d'):format(onlineCount, dutyCount),
            icon = 'fas fa-building',
        },
    }

    if perms.jobs then
        options[#options + 1] = {
            title = 'Hire Citizen', icon = 'fas fa-user-plus', iconColor = 'green',
            description = 'By citizen ID',
            onSelect = function()
                local input = lib.inputDialog('Hire into ' .. job.label, {
                    { type = 'input', label = 'Citizen ID', required = true, max = 50, icon = 'id-card' },
                })
                local citizenid = input and JUtil.Functions.trim(input[1])
                if not citizenid or citizenid == '' then return JC.Jobs.OpenJob(jobName) end

                local level = PickGrade(job, 'Grade for the new employee')
                if level then
                    ConfirmAndSet(citizenid, citizenid, job.name, job.label, level, GradeName(job, level))
                end
                JC.Jobs.OpenJob(jobName)
            end,
        }
    end

    for _, member in ipairs(result.members) do
        options[#options + 1] = {
            title = ('%s%s%s'):format(member.online and '🟢 ' or '⚫ ', member.online and ('[%d] '):format(member.serverId or 0) or '', member.name ~= '' and member.name or member.citizenid),
            description = ('%d - %s%s | %s'):format(member.gradeLevel, member.gradeName, member.isboss and ' (manager)' or '',
                member.online and (member.onduty and 'On duty' or 'Online - off duty') or (member.status and member.status.text or '⚫ Offline')),
            icon = member.isboss and 'fas fa-user-tie' or 'fas fa-user',
            iconColor = member.onduty and 'green' or (member.online and 'yellow' or 'gray'),
            arrow = true,
            onSelect = function() OpenMember(job, member, perms) end,
        }
    end
    if #result.members == 0 then options[#options + 1] = { title = 'No employees', disabled = true } end

    lib.registerContext({ id = 'justice_job_view', title = 'Department: ' .. job.label, menu = 'justice_jobs_list', options = options })
    lib.showContext('justice_job_view')
end
