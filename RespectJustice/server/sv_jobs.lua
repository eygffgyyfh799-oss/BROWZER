local Settings = JS.Settings
local Panel = Settings.Panel
local Notify = JS.Notify

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- أدوات القطاعات (الوظائف)
-- ════════════════════════════════════════════════════════════════════════════════════════════════

local function IsBlacklisted(jobName)
    for _, name in ipairs(Panel.JobsBlacklist or {}) do
        if name == jobName then return true end
    end
    return false
end

local function GetSharedJob(jobName)
    if type(jobName) ~= 'string' or not jobName:match('^[%w_%-]+$') then return nil end
    local jobs = RTCore.Shared.Jobs or {}
    return jobs[jobName]
end

-- الرتب في QBCore مفاتيحها نصوص ('0', '1') وأحياناً أرقام
local function GetGrade(job, level)
    level = tonumber(level)
    if not job or not job.grades or not level then return nil end
    return job.grades[tostring(level)] or job.grades[level]
end

local function GetGradeList(job)
    local list = {}
    for key, grade in pairs(job.grades or {}) do
        local level = tonumber(key)
        if level then
            list[#list + 1] = {
                level = level,
                name = grade.name or ('رتبة ' .. level),
                isboss = grade.isboss == true,
                payment = grade.payment,
            }
        end
    end
    table.sort(list, function(a, b) return a.level < b.level end)
    return list
end

-- بناء بيانات الوظيفة بنفس شكل QBCore (للمواطن غير المتصل)
local function BuildJobData(jobName, job, level, grade)
    return {
        name = jobName,
        label = job.label or jobName,
        type = job.type or 'none',
        onduty = job.defaultDuty == true,
        payment = grade.payment or 30,
        isboss = grade.isboss == true,
        grade = { name = grade.name, level = level },
    }
end

local function JobLabel(jobData)
    if type(jobData) ~= 'table' then return '-' end
    local grade = type(jobData.grade) == 'table' and (jobData.grade.name or jobData.grade.level) or jobData.grade
    return ('%s - %s'):format(jobData.label or jobData.name or '-', tostring(grade or '-'))
end

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- قائمة كل القطاعات مع عدد الموظفين
-- ════════════════════════════════════════════════════════════════════════════════════════════════

JS.RegisterCallback('RespectJustice:server:getJobs', 'view', function(src, Player)
    local online, onduty = {}, {}
    for _, playerId in pairs(RTCore.Functions.GetPlayers()) do
        local target = RTCore.Functions.GetPlayer(playerId)
        local job = target and target.PlayerData.job
        if job and job.name then
            online[job.name] = (online[job.name] or 0) + 1
            if job.onduty then onduty[job.name] = (onduty[job.name] or 0) + 1 end
        end
    end

    local totals = {}
    local tableName = Settings.Database.Players
    if JS.TableExists(tableName) then
        local rows = MySQL.query.await(("SELECT JSON_UNQUOTE(JSON_EXTRACT(job, '$.name')) AS job_name, COUNT(*) AS total FROM `%s` GROUP BY job_name"):format(tableName)) or {}
        for _, row in ipairs(rows) do
            if row.job_name then totals[row.job_name] = tonumber(row.total) or 0 end
        end
    end

    local list = {}
    for name, job in pairs(RTCore.Shared.Jobs or {}) do
        if not IsBlacklisted(name) then
            list[#list + 1] = {
                name = name,
                label = JS.Safe(job.label or name),
                grades = GetGradeList(job),
                online = online[name] or 0,
                onduty = onduty[name] or 0,
                total = totals[name] or online[name] or 0,
            }
        end
    end
    table.sort(list, function(a, b)
        if a.name == Panel.UnemployedJob then return false end
        if b.name == Panel.UnemployedJob then return true end
        return a.label < b.label
    end)

    return { ok = true, jobs = list, perms = JS.GetPermissions(Player), unemployed = Panel.UnemployedJob }
end)

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- أعضاء قطاع (متصلين + غير متصلين)
-- ════════════════════════════════════════════════════════════════════════════════════════════════

JS.RegisterCallback('RespectJustice:server:getJobMembers', 'view', function(src, Player, jobName)
    local job = GetSharedJob(jobName)
    if not job or IsBlacklisted(jobName) then return { ok = false, err = 'القطاع غير موجود' } end

    local members, seen = {}, {}
    local function add(cid, charinfo, jobData, target, lastUpdated)
        if seen[cid] then return end
        seen[cid] = true
        local status = JS.GetStatus(cid, lastUpdated)
        local grade = type(jobData.grade) == 'table' and jobData.grade or {}
        members[#members + 1] = {
            citizenid = cid,
            name = JS.FullName(charinfo),
            gradeLevel = tonumber(grade.level) or 0,
            gradeName = JS.Safe(grade.name or tostring(grade.level or 0)),
            isboss = jobData.isboss == true,
            online = target ~= nil,
            onduty = target ~= nil and jobData.onduty == true,
            serverId = target and target.PlayerData.source or nil,
            status = status,
        }
    end

    for _, playerId in pairs(RTCore.Functions.GetPlayers()) do
        local target = RTCore.Functions.GetPlayer(playerId)
        if target and target.PlayerData.job and target.PlayerData.job.name == jobName then
            add(target.PlayerData.citizenid, target.PlayerData.charinfo, target.PlayerData.job, target)
        end
    end

    local tableName = Settings.Database.Players
    if JS.TableExists(tableName) then
        local rows = MySQL.query.await(("SELECT %s FROM `%s` WHERE JSON_UNQUOTE(JSON_EXTRACT(job, '$.name')) = ? LIMIT 300"):format(JS.PlayerListColumns(), tableName), { jobName }) or {}
        for _, row in ipairs(rows) do
            add(row.citizenid, JS.Decode(row.charinfo), JS.Decode(row.job), nil, row.last_updated)
        end
    end

    table.sort(members, function(a, b)
        if a.gradeLevel ~= b.gradeLevel then return a.gradeLevel > b.gradeLevel end
        if a.online ~= b.online then return a.online end
        return a.name < b.name
    end)

    return {
        ok = true,
        job = { name = jobName, label = JS.Safe(job.label or jobName), grades = GetGradeList(job) },
        members = members,
        perms = JS.GetPermissions(Player),
    }
end)

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- تغيير وظيفة ورتبة المواطن (توظيف / ترقية / تنزيل / فصل)
-- ════════════════════════════════════════════════════════════════════════════════════════════════

JS.RegisterCallback('RespectJustice:server:setCitizenJob', 'jobs', function(src, Player, citizenid, jobName, level)
    citizenid = JS.ValidCitizenId(citizenid)
    level = math.floor(tonumber(level) or -1)
    if not citizenid then return { ok = false, err = 'الرقم الوطني غير صحيح' } end
    if citizenid == Player.PlayerData.citizenid then
        return { ok = false, err = 'لا يمكنك تغيير وظيفتك بنفسك' }
    end

    local job = GetSharedJob(jobName)
    if not job or IsBlacklisted(jobName) then return { ok = false, err = 'القطاع غير موجود أو غير مسموح' } end

    local grade = GetGrade(job, level)
    if not grade then return { ok = false, err = 'الرتبة غير موجودة في هذا القطاع' } end

    if JS.OnCooldown('jobs', Player.PlayerData.citizenid .. ':' .. citizenid, 2) then
        return { ok = false, err = 'انتظر ثانيتين قبل تعديل نفس المواطن مرة ثانية' }
    end

    local citizen = JS.GetCitizen(citizenid)
    if not citizen then return { ok = false, err = 'لا يوجد مواطن بهذا الرقم الوطني' } end

    if citizen.job and citizen.job.name and IsBlacklisted(citizen.job.name) then
        return { ok = false, err = 'لا يمكن تغيير وظيفة هذا المواطن' }
    end

    local oldJob = JobLabel(citizen.job)
    local name = JS.FullName(citizen.charinfo)

    if citizen.online then
        if not citizen.online.Functions.SetJob(jobName, level) then
            return { ok = false, err = 'تعذر تغيير الوظيفة' }
        end
        Notify(citizen.online.PlayerData.source,
            ('تم تغيير وظيفتك من وزارة العدل إلى: %s - %s'):format(job.label or jobName, grade.name or level), 'primary', 10000)
    else
        if not JS.UpdatePlayerJson(citizenid, 'job', BuildJobData(jobName, job, level, grade), citizen.raw.job) then
            return { ok = false, err = 'تغيرت بيانات المواطن أثناء العملية، حاول مرة أخرى' }
        end
    end

    local newJob = ('%s - %s'):format(job.label or jobName, grade.name or level)
    JS.Log(Player, 'job', citizenid, name, { ['من'] = oldJob, ['إلى'] = newJob })

    return { ok = true, newJob = newJob }
end)

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- تشغيل / إيقاف دوام موظف (متصل فقط)
-- ════════════════════════════════════════════════════════════════════════════════════════════════

JS.RegisterCallback('RespectJustice:server:setCitizenDuty', 'jobs', function(src, Player, citizenid, state)
    citizenid = JS.ValidCitizenId(citizenid)
    state = state == true
    local target = citizenid and RTCore.Functions.GetPlayerByCitizenId(citizenid)
    if not target then return { ok = false, err = 'المواطن غير متصل' } end
    if citizenid == Player.PlayerData.citizenid then return { ok = false, err = 'استخدم البصمة لتغيير دوامك' } end
    if IsBlacklisted(target.PlayerData.job.name) then return { ok = false, err = 'القطاع غير مسموح' } end

    local targetSrc = target.PlayerData.source
    target.Functions.SetJobDuty(state)
    TriggerEvent('QBCore:Server:SetDuty', targetSrc, state)
    TriggerClientEvent('QBCore:Client:SetDuty', targetSrc, state)

    Notify(targetSrc, state and 'تم تسجيل دخولك للدوام من وزارة العدل' or 'تم إنهاء دوامك من وزارة العدل', 'primary', 8000)
    JS.Log(Player, 'duty', citizenid, JS.PlayerName(target), {
        ['القطاع'] = target.PlayerData.job.label or target.PlayerData.job.name,
        ['الحالة'] = state and 'في الدوام' or 'خارج الدوام',
    })

    return { ok = true }
end)
