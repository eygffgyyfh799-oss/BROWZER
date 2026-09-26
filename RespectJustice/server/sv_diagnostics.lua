-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- فحص جاهزية السكربت: يشتغل تلقائياً عند التشغيل، وبالأمر  justicecheck  من كونسول السيرفر
-- ════════════════════════════════════════════════════════════════════════════════════════════════

local Settings = JS.Settings

local function RunDiagnostics()
    local ok, warn, bad = 0, 0, 0
    local lines = {}
    local function line(state, text)
        if state == 'ok' then ok = ok + 1 lines[#lines + 1] = '^2  ✔ ' .. text .. '^7'
        elseif state == 'warn' then warn = warn + 1 lines[#lines + 1] = '^3  ⚠ ' .. text .. '^7'
        else bad = bad + 1 lines[#lines + 1] = '^1  ✖ ' .. text .. '^7' end
    end

    -- السكربتات المطلوبة
    for _, res in ipairs({ 'RespectCore', 'RespectLib', 'RespectTarget', 'oxmysql' }) do
        local state = GetResourceState(res)
        line(state == 'started' and 'ok' or 'bad', ('%s: %s'):format(res, state == 'started' and 'شغال' or ('غير شغال (' .. state .. ') - مطلوب')))
    end
    -- السكربتات الاختيارية
    for res, feature in pairs({ ['lb-phone'] = 'شرط وجود جوال عند تقديم الدعوى', RespectFuel = 'وقود مركبات العدل', RespectScripts = 'اسم علامة الخريطة' }) do
        if GetResourceState(res) ~= 'started' then
            line('warn', ('%s غير شغال: %s ما يشتغل (باقي السكربت طبيعي)'):format(res, feature))
        end
    end

    -- الوظيفة والرتب
    local jobs = RTCore.Shared.Jobs or {}
    local job = jobs[Settings.Job]
    if not job then
        line('bad', ("الوظيفة '%s' غير موجودة في وظائف الكور - عدّل Settings.Job"):format(Settings.Job))
    else
        line('ok', ('وظيفة العدل: %s'):format(job.label or Settings.Job))
        local full = tonumber(Settings.Panel.FullAccessGrade)
        if full and job.grades and not (job.grades[tostring(full)] or job.grades[full]) then
            line('warn', ('الرتبة %d (صلاحية كاملة) غير موجودة في وظيفة العدل - أي رتبة أعلى منها تاخذ الصلاحية، أو المدير فقط'):format(full))
        end
    end
    if not jobs[Settings.Panel.UnemployedJob] then
        line('warn', ("وظيفة العاطل '%s' غير موجودة - الفصل ما يشتغل، عدّل UnemployedJob"):format(tostring(Settings.Panel.UnemployedJob)))
    end
    if not RTCore.Shared.Gangs or not RTCore.Shared.Gangs[Settings.City.NoGang] then
        line('warn', ("العصابة '%s' (بدون عصابة) غير موجودة - إزالة العصابة قد لا تعمل"):format(tostring(Settings.City.NoGang)))
    end

    -- قاعدة البيانات
    local db = Settings.Database
    line(JS.TableExists(db.Players) and 'ok' or 'bad', ('جدول اللاعبين `%s`'):format(db.Players))
    if not JS.TableExists(db.Vehicles) then
        line('warn', ('جدول المركبات `%s` غير موجود - سجل المركبات مخفي'):format(tostring(db.Vehicles)))
    end
    if not (db.Houses and JS.TableExists(db.Houses.table)) then
        line('warn', ('جدول العقارات `%s` غير موجود - سجل العقارات مخفي'):format(tostring(db.Houses and db.Houses.table)))
    elseif not JS.ColumnExists(db.Houses.table, db.Houses.owner) or not JS.ColumnExists(db.Houses.table, db.Houses.id) then
        line('warn', 'أعمدة جدول العقارات (owner / id) غير صحيحة - راجع Settings.Database.Houses')
    end
    for _, t in ipairs({ 'justice_reports', 'justice_logs', 'justice_suspensions', 'justice_summons', 'justice_transactions' }) do
        if not JS.TableExists(t) then line('bad', ('جدول `%s` غير موجود - شغّل RespectJustice.sql'):format(t)) end
    end

    line('ok', GetConvar('justice_webhook', '') ~= '' and 'Discord: مفعّل' or 'Discord: غير مفعّل (اختياري)')

    print('^5════════ RespectJustice - فحص الجاهزية ════════^7')
    for _, text in ipairs(lines) do print(text) end
    print(('^5════════ %s | سليم: %d | تنبيه: %d | مشكلة: %d ════════^7'):format(
        bad == 0 and '^2جاهز للعمل^5' or '^1يحتاج إصلاح^5', ok, warn, bad))
    return bad, warn
end

CreateThread(function()
    while not JS.Ready do Wait(500) end
    Wait(2000)
    local ok, err = pcall(RunDiagnostics)
    if not ok then print('^1[RespectJustice] diagnostics: ' .. tostring(err) .. '^7') end
end)

RegisterCommand('justicecheck', function(source)
    if source ~= 0 then return end -- من كونسول السيرفر فقط
    RunDiagnostics()
end, true)
