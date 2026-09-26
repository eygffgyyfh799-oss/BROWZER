JC.Jobs = {}

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- اختيار قطاع ثم رتبة (يُستخدم في ملف المواطن)
-- ════════════════════════════════════════════════════════════════════════════════════════════════

local function PickGrade(job, title, currentLevel)
    if #job.grades == 0 then
        JC.Notify('لا توجد رتب في هذا القطاع', 'error')
        return nil
    end

    local options = {}
    for i, grade in ipairs(job.grades) do
        options[i] = { value = tostring(grade.level), label = ('%d - %s%s'):format(grade.level, grade.name, grade.isboss and ' (مدير)' or '') }
    end

    local input = lib.inputDialog(title, {
        { type = 'select', label = 'الرتبة', required = true, options = options, default = currentLevel and tostring(currentLevel) or options[1].value },
    })
    return input and tonumber(input[1]) or nil
end

local function ConfirmAndSet(citizenid, name, jobName, jobLabel, level, gradeName)
    local confirm = lib.alertDialog({
        header = 'تأكيد تغيير الوظيفة',
        content = ('سيتم تعيين **%s** في **%s** برتبة **%s**'):format(name, jobLabel, gradeName or level),
        centered = true,
        cancel = true,
    })
    if confirm ~= 'confirm' then return false end

    local result = JC.Call('RespectJustice:server:setCitizenJob', citizenid, jobName, level)
    if result then
        JC.Notify('تم التعيين: ' .. result.newJob, 'success', 8000)
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

-- تغيير وظيفة مواطن من ملفه (أي قطاع وأي رتبة)
function JC.Jobs.ChangeCitizenJob(citizenid, name)
    local result = JC.Call('RespectJustice:server:getJobs')
    if not result then return end

    local options = {}
    for i, job in ipairs(result.jobs) do
        options[i] = { value = tostring(i), label = ('%s (%s)'):format(job.label, job.name) }
    end

    local input = lib.inputDialog('تغيير وظيفة ' .. name, {
        { type = 'select', label = 'القطاع', required = true, searchable = true, options = options },
    })
    local job = input and result.jobs[tonumber(input[1])]
    if not job then return end

    local level = PickGrade(job, ('رتبة %s في %s'):format(name, job.label))
    if not level then return end

    ConfirmAndSet(citizenid, name, job.name, job.label, level, GradeName(job, level))
end

-- فصل المواطن من وظيفته
function JC.Jobs.Fire(citizenid, name)
    local confirm = lib.alertDialog({
        header = 'فصل من الوظيفة',
        content = ('هل أنت متأكد من فصل **%s** من وظيفته؟'):format(name),
        centered = true,
        cancel = true,
    })
    if confirm ~= 'confirm' then return false end

    local result = JC.Call('RespectJustice:server:setCitizenJob', citizenid, JC.Settings.Panel.UnemployedJob, 0)
    if result then JC.Notify('تم فصل المواطن', 'success') end
    return result ~= nil
end

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- قائمة القطاعات
-- ════════════════════════════════════════════════════════════════════════════════════════════════

function JC.Jobs.OpenList(parent)
    local result = JC.Call('RespectJustice:server:getJobs')
    if not result then return end

    local options = {}
    for _, job in ipairs(result.jobs) do
        options[#options + 1] = {
            title = job.label,
            description = ('متصل: %d | في الدوام: %d | إجمالي الموظفين: %d'):format(job.online, job.onduty, job.total),
            icon = job.onduty > 0 and 'fas fa-building-circle-check' or 'fas fa-building',
            iconColor = job.onduty > 0 and 'green' or nil,
            metadata = { { label = 'اسم القطاع', value = job.name }, { label = 'عدد الرتب', value = #job.grades } },
            arrow = true,
            onSelect = function() JC.Jobs.OpenJob(job.name) end,
        }
    end
    if #options == 0 then options[1] = { title = 'لا توجد قطاعات', disabled = true } end

    lib.registerContext({ id = 'justice_jobs_list', title = ('القطاعات (%d)'):format(#result.jobs), menu = parent, options = options, rt_logo = true })
    lib.showContext('justice_jobs_list')
end

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- قطاع واحد: الموظفين + توظيف
-- ════════════════════════════════════════════════════════════════════════════════════════════════

local function OpenMember(job, member, perms)
    local reopen = function() OpenMember(job, member, perms) end
    local back = function() JC.Jobs.OpenJob(job.name) end

    local options = {
        {
            title = member.name ~= '' and member.name or 'بدون اسم',
            description = ('%s\nالرقم الوطني: %s%s'):format(member.status and member.status.text or (member.online and '🟢 متصل' or '⚫ غير متصل'), member.citizenid,
                member.online and (member.onduty and ' | في الدوام' or ' | خارج الدوام') or ''),
            icon = 'fas fa-user', iconColor = member.online and 'green' or 'gray',
        },
        { title = 'الرتبة الحالية', description = ('%d - %s%s'):format(member.gradeLevel, member.gradeName, member.isboss and ' (مدير)' or ''), icon = 'fas fa-ranking-star' },
        {
            title = 'فتح ملف المواطن', icon = 'fas fa-id-card', arrow = true,
            onSelect = function() JC.Panel.OpenProfile(member.citizenid, 'justice_job_member') end,
        },
    }

    if perms.jobs then
        options[#options + 1] = {
            title = 'تغيير الرتبة', icon = 'fas fa-arrows-up-down', iconColor = 'blue',
            onSelect = function()
                local level = PickGrade(job, ('رتبة %s'):format(member.name), member.gradeLevel)
                if level and level ~= member.gradeLevel
                    and ConfirmAndSet(member.citizenid, member.name, job.name, job.label, level, GradeName(job, level)) then
                    return back()
                end
                reopen()
            end,
        }
        options[#options + 1] = {
            title = 'نقل لقطاع آخر', icon = 'fas fa-right-left', iconColor = 'yellow',
            onSelect = function()
                JC.Jobs.ChangeCitizenJob(member.citizenid, member.name)
                back()
            end,
        }
        if member.online then
            options[#options + 1] = {
                title = member.onduty and 'إنهاء دوامه' or 'تسجيل دخوله للدوام',
                icon = member.onduty and 'fas fa-right-from-bracket' or 'fas fa-right-to-bracket',
                onSelect = function()
                    if JC.Call('RespectJustice:server:setCitizenDuty', member.citizenid, not member.onduty) then
                        JC.Notify('تم تغيير حالة الدوام', 'success')
                        return back()
                    end
                    reopen()
                end,
            }
        end
        if job.name ~= JC.Settings.Panel.UnemployedJob then
            options[#options + 1] = {
                title = 'فصل من القطاع', icon = 'fas fa-user-xmark', iconColor = 'red',
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
    local result = JC.Call('RespectJustice:server:getJobMembers', jobName)
    if not result then return end

    local job, perms = result.job, result.perms or {}
    local onlineCount, dutyCount = 0, 0
    for _, m in ipairs(result.members) do
        if m.online then onlineCount = onlineCount + 1 end
        if m.onduty then dutyCount = dutyCount + 1 end
    end

    local options = {
        {
            title = ('%s | الموظفين: %d'):format(job.label, #result.members),
            description = ('متصل: %d | في الدوام: %d'):format(onlineCount, dutyCount),
            icon = 'fas fa-building',
        },
    }

    if perms.jobs then
        options[#options + 1] = {
            title = 'توظيف مواطن', icon = 'fas fa-user-plus', iconColor = 'green',
            description = 'بالرقم الوطني',
            onSelect = function()
                local input = lib.inputDialog('توظيف في ' .. job.label, {
                    { type = 'input', label = 'الرقم الوطني', required = true, max = 50, icon = 'id-card' },
                })
                local citizenid = input and _2rayan.Functions.trim(input[1])
                if not citizenid or citizenid == '' then return JC.Jobs.OpenJob(jobName) end

                local level = PickGrade(job, 'رتبة الموظف الجديد')
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
            description = ('%d - %s%s | %s'):format(member.gradeLevel, member.gradeName, member.isboss and ' (مدير)' or '',
                member.online and (member.onduty and 'في الدوام' or 'متصل - خارج الدوام') or (member.status and member.status.text or '⚫ غير متصل')),
            icon = member.isboss and 'fas fa-user-tie' or 'fas fa-user',
            iconColor = member.onduty and 'green' or (member.online and 'yellow' or 'gray'),
            arrow = true,
            onSelect = function() OpenMember(job, member, perms) end,
        }
    end
    if #result.members == 0 then options[#options + 1] = { title = 'لا يوجد موظفين', disabled = true } end

    lib.registerContext({ id = 'justice_job_view', title = 'قطاع ' .. job.label, menu = 'justice_jobs_list', options = options, rt_logo = true })
    lib.showContext('justice_job_view')
end
