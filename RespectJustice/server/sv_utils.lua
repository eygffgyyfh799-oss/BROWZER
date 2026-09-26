-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- أدوات مشتركة لملفات السيرفر (يُحمّل أولاً)
-- ════════════════════════════════════════════════════════════════════════════════════════════════

JS = {}
JS.Config = LoadConfig()
JS.Settings = JS.Config.Settings
JS.Job = JS.Settings.Job
JS.Ready = false
JS.Suspended = {}

local Settings = JS.Settings
local schemaCache = {}

JS.StatusLabels = { new = 'جديدة', review = 'قيد النظر', closed = 'مغلقة' }

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- نصوص وتنسيق
-- ════════════════════════════════════════════════════════════════════════════════════════════════

function JS.Notify(src, msg, msgType, length)
    msgType, length = msgType or 'primary', length or 5000
    local ok = pcall(RTCore.Functions.Notify, src, msg, msgType, length)
    if not ok then
        TriggerClientEvent('RespectJustice:client:notify', src, msg, msgType, length)
    end
end

function JS.Now()
    return os.date('%d/%m/%Y %H:%M', os.time())
end

function JS.Len(str)
    return utf8.len(str) or #str
end

-- يمنع حقن HTML و Markdown (مثل صور خارجية تكشف IP الموظفين عند فتح القائمة)
function JS.Safe(str)
    if type(str) ~= 'string' then return str end
    str = str:gsub('[<>]', ''):gsub('!%[', '['):gsub('%]%(', '] ('):gsub('`', "'")
    return str
end

-- ينظف النص: يحذف المسافات الزائدة ورموز التحكم و < >
-- يرجع nil إذا كان النص غير صالح أو أطول من الحد
function JS.CleanText(value, maxLen, required)
    if value == nil then
        return (not required) and '' or nil
    end
    if type(value) ~= 'string' and type(value) ~= 'number' then return nil end

    local str = _2rayan.Functions.trim(tostring(value)) or ''
    if not utf8.len(str) then return nil end -- نص تالف (UTF-8 غير صالح)
    str = JS.Safe(str:gsub('[\0-\9\11-\31]', ''))
    if required and str == '' then return nil end
    if maxLen and JS.Len(str) > maxLen then return nil end
    return str
end

-- قص النص بعدد أحرف بدون كسر الأحرف العربية
function JS.Truncate(str, maxChars)
    local ok, cut = pcall(utf8.offset, str, maxChars + 1)
    if ok and cut then return str:sub(1, cut - 1) end
    return str
end

function JS.ValidCitizenId(cid)
    if type(cid) ~= 'string' and type(cid) ~= 'number' then return nil end
    cid = _2rayan.Functions.trim(tostring(cid))
    if not cid or cid == '' or #cid > 50 or not cid:match('^[%w_%-]+$') then return nil end
    return cid
end

function JS.Decode(value)
    if type(value) == 'table' then return value end
    if type(value) ~= 'string' or value == '' then return {} end
    local ok, result = pcall(json.decode, value)
    return (ok and type(result) == 'table') and result or {}
end

function JS.FullName(charinfo)
    charinfo = charinfo or {}
    local name = ('%s %s'):format(tostring(charinfo.firstname or ''), tostring(charinfo.lastname or ''))
    return JS.Safe((name:gsub('^%s+', ''):gsub('%s+$', '')))
end

function JS.PlayerName(Player)
    return JS.FullName(Player.PlayerData.charinfo)
end

-- oxmysql يرجع التواريخ كأرقام (ميلي ثانية)
function JS.FormatDbDate(value)
    if type(value) == 'number' then
        return os.date('%d/%m/%Y %H:%M', math.floor(value / 1000))
    end
    return value and tostring(value) or nil
end

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- حالة الاتصال: متصل / غير متصل + منذ متى
-- ════════════════════════════════════════════════════════════════════════════════════════════════

local joinTimes = {}   -- [source] = وقت الدخول
local lastSeen = {}    -- [citizenid] = وقت الخروج (خلال تشغيل السيرفر الحالي)

AddEventHandler('playerJoining', function()
    joinTimes[source] = os.time()
end)

AddEventHandler('playerDropped', function()
    local src = source
    joinTimes[src] = nil
    local ok, Player = pcall(RTCore.Functions.GetPlayer, src)
    if ok and Player and Player.PlayerData then
        lastSeen[Player.PlayerData.citizenid] = os.time()
    end
end)

-- صيغة عربية صحيحة: دقيقة / دقيقتين / 3 دقائق / 11 دقيقة
local function Plural(n, one, two, few, many)
    if n == 1 then return one end
    if n == 2 then return two end
    if n >= 3 and n <= 10 then return ('%d %s'):format(n, few) end
    return ('%d %s'):format(n, many)
end

function JS.Ago(seconds)
    seconds = math.max(0, math.floor(tonumber(seconds) or 0))
    if seconds < 60 then return 'الآن' end
    local minutes = math.floor(seconds / 60)
    if minutes < 60 then return 'منذ ' .. Plural(minutes, 'دقيقة', 'دقيقتين', 'دقائق', 'دقيقة') end
    local hours = math.floor(minutes / 60)
    if hours < 24 then return 'منذ ' .. Plural(hours, 'ساعة', 'ساعتين', 'ساعات', 'ساعة') end
    local days = math.floor(hours / 24)
    if days < 30 then return 'منذ ' .. Plural(days, 'يوم', 'يومين', 'أيام', 'يوم') end
    local months = math.floor(days / 30)
    if months < 12 then return 'منذ ' .. Plural(months, 'شهر', 'شهرين', 'أشهر', 'شهر') end
    return 'منذ ' .. Plural(math.floor(months / 12), 'سنة', 'سنتين', 'سنوات', 'سنة')
end

-- lastUpdated: قيمة last_updated من جدول players (ميلي ثانية) إن وجدت
-- يرجع { online, serverId, text }
function JS.GetStatus(citizenid, lastUpdated)
    local Player = RTCore.Functions.GetPlayerByCitizenId(citizenid)
    if Player then
        local src = Player.PlayerData.source
        local joined = joinTimes[src]
        return {
            online = true,
            serverId = src,
            text = ('🟢 متصل الآن [%d]%s'):format(src, joined and (' - دخل ' .. JS.Ago(os.time() - joined)) or ''),
        }
    end

    local seen = lastSeen[citizenid]
    if not seen and type(lastUpdated) == 'number' then
        seen = math.floor(lastUpdated / 1000)
    end
    return {
        online = false,
        text = seen and ('⚫ غير متصل - آخر ظهور ' .. JS.Ago(os.time() - seen)) or '⚫ غير متصل',
    }
end

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- الصلاحيات
-- ════════════════════════════════════════════════════════════════════════════════════════════════

function JS.GetGrade(Player)
    local grade = Player.PlayerData.job.grade
    return tonumber(type(grade) == 'table' and grade.level or grade) or 0
end

function JS.IsJustice(Player)
    return Player ~= nil and Player.PlayerData.job ~= nil and Player.PlayerData.job.name == JS.Job
end

-- المدير أو رتبة المسؤول ورئيس المحكمة (FullAccessGrade) وأعلى
function JS.IsBoss(Player)
    if not JS.IsJustice(Player) then return false end
    if Player.PlayerData.job.isboss == true then return true end
    local fullAccess = tonumber(Settings.Panel.FullAccessGrade)
    return fullAccess ~= nil and JS.GetGrade(Player) >= fullAccess
end

function JS.Can(Player, action)
    if not JS.IsJustice(Player) then
        return false, 'يجب أن تكون من موظفي العدل'
    end

    local job = Player.PlayerData.job
    if Settings.Panel.RequireDuty and not job.onduty then
        return false, 'يجب أن تكون في الدوام'
    end

    local required = Settings.Panel.Permissions[action]
    if required == nil then return false, 'صلاحية غير معروفة' end
    if required == false then return false, 'هذه الصلاحية مقفلة' end
    if JS.IsBoss(Player) then return true end
    if required == 'boss' then return false, 'هذه الصلاحية للمدير فقط' end
    if JS.GetGrade(Player) < (tonumber(required) or 0) then
        return false, 'رتبتك لا تسمح بهذا الإجراء'
    end
    return true
end

function JS.GetPermissions(Player)
    local perms = {}
    for action in pairs(Settings.Panel.Permissions) do
        perms[action] = JS.Can(Player, action) == true
    end
    return perms
end

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- الأدوار: العدل / الشرطة / المحامي
-- ════════════════════════════════════════════════════════════════════════════════════════════════

local function InList(list, value)
    for _, v in ipairs(list or {}) do
        if v == value then return true end
    end
    return false
end

function JS.IsPolice(Player)
    local job = Player and Player.PlayerData.job
    return job ~= nil and InList(Settings.Police.Jobs, job.name)
end

function JS.CanPolice(Player, action)
    if not JS.IsPolice(Player) then return false, 'هذا القسم للشرطة فقط' end
    local job = Player.PlayerData.job
    if Settings.Police.RequireDuty and not job.onduty then return false, 'يجب أن تكون في الدوام' end
    local required = Settings.Police.Permissions[action]
    if required == nil or required == false then return false, 'هذه الصلاحية غير متاحة للشرطة' end
    if job.isboss then return true end
    if required == 'boss' then return false, 'هذه الصلاحية لمدير الشرطة فقط' end
    if JS.GetGrade(Player) < (tonumber(required) or 0) then return false, 'رتبتك لا تسمح بهذا الإجراء' end
    return true
end

function JS.GetPolicePermissions(Player)
    local perms = {}
    for action in pairs(Settings.Police.Permissions) do
        perms[action] = JS.CanPolice(Player, action) == true
    end
    return perms
end

-- يرجع دالة تحقق تُستخدم مع JS.RegisterCallback
function JS.PoliceOnly(action)
    return function(Player) return JS.CanPolice(Player, action) end
end

-- المحامي: عنده رخصة محاماة أو وظيفته من وظائف المحامين
function JS.HasLawyerLicense(metadata, job)
    local licenses = metadata and (metadata.licences or metadata.licenses) or {}
    if licenses[Settings.Lawyers.License] == true then return true end
    return job ~= nil and InList(Settings.Lawyers.Jobs, job.name)
end

function JS.IsLawyer(Player)
    return Player ~= nil and JS.HasLawyerLicense(Player.PlayerData.metadata, Player.PlayerData.job)
end

function JS.GetRole(Player)
    if JS.IsJustice(Player) then return 'justice' end
    if JS.IsPolice(Player) then return 'police' end
    if JS.IsLawyer(Player) then return 'lawyer' end
    return nil
end

function JS.PoliceInfo(Player)
    local job, md = Player.PlayerData.job or {}, Player.PlayerData.metadata or {}
    return {
        citizenid = Player.PlayerData.citizenid,
        name = JS.PlayerName(Player),
        job = JS.Safe(job.label or job.name or '-'),
        grade = JS.Safe(type(job.grade) == 'table' and job.grade.name or tostring(job.grade or '-')),
        callsign = md.callsign and JS.Safe(tostring(md.callsign)) or nil,
    }
end

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- إشعارات مباشرة للتابلت (مع صوت إذا التابلت مفتوح، وإشعار عادي إذا مقفل)
-- event = { type, title, text, coords? }
-- ════════════════════════════════════════════════════════════════════════════════════════════════

function JS.TabletEvent(src, event)
    TriggerClientEvent('RespectJustice:client:tabletEvent', src, event)
end

function JS.BroadcastTablet(filter, event)
    for _, playerId in pairs(RTCore.Functions.GetPlayers()) do
        local target = RTCore.Functions.GetPlayer(playerId)
        if target and filter(target) then JS.TabletEvent(playerId, event) end
    end
end

function JS.JusticeOnDuty(target)
    return JS.IsJustice(target) and target.PlayerData.job.onduty == true
end

function JS.PoliceOnDuty(target)
    return JS.IsPolice(target) and target.PlayerData.job.onduty == true
end

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- تحريك الفلوس (بنك) للمتصل وغير المتصل
-- ════════════════════════════════════════════════════════════════════════════════════════════════

function JS.GetBank(citizenid)
    local target = RTCore.Functions.GetPlayerByCitizenId(citizenid)
    if target then return math.floor(tonumber(target.PlayerData.money.bank) or 0) end
    local row = JS.GetPlayerRow(citizenid)
    return row and math.floor(tonumber(JS.Decode(row.money).bank) or 0) or nil
end

-- يسحب من بنك المواطن (يرفض إذا الرصيد ما يكفي)
function JS.TakeMoney(citizenid, amount, reason)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return false, 'مبلغ غير صحيح' end
    local target = RTCore.Functions.GetPlayerByCitizenId(citizenid)
    if target then
        if (tonumber(target.PlayerData.money.bank) or 0) < amount then return false, 'الرصيد غير كافٍ' end
        if not target.Functions.RemoveMoney('bank', amount, reason) then return false, 'تعذر السحب' end
        return true
    end
    local row = JS.GetPlayerRow(citizenid)
    if not row then return false, 'المواطن غير موجود' end
    local money = JS.Decode(row.money)
    local bank = tonumber(money.bank) or 0
    if bank < amount then return false, 'الرصيد غير كافٍ' end
    money.bank = bank - amount
    if not JS.UpdatePlayerJson(citizenid, 'money', money, row.money) then return false, 'تغيرت بيانات المواطن، حاول مرة أخرى' end
    return true
end

-- يضيف لبنك المواطن
function JS.GiveMoney(citizenid, amount, reason)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return false, 'مبلغ غير صحيح' end
    local target = RTCore.Functions.GetPlayerByCitizenId(citizenid)
    if target then
        if not target.Functions.AddMoney('bank', amount, reason) then return false, 'تعذر الإيداع' end
        return true
    end
    local row = JS.GetPlayerRow(citizenid)
    if not row then return false, 'المواطن غير موجود' end
    local money = JS.Decode(row.money)
    money.bank = (tonumber(money.bank) or 0) + amount
    if not JS.UpdatePlayerJson(citizenid, 'money', money, row.money) then return false, 'تغيرت بيانات المواطن، حاول مرة أخرى' end
    return true
end

-- وين تروح الفلوس المسحوبة (WithdrawTo) - يرجع وجهة التحويل عشان التراجع
function JS.DepositWithdrawn(Player, amount, reason)
    local to = Settings.Panel.WithdrawTo
    if to == 'officer' and Player then
        local ok = JS.GiveMoney(Player.PlayerData.citizenid, amount, reason)
        if ok then
            JS.Notify(Player.PlayerData.source, ('تم إيداع $%d في حسابك'):format(amount), 'success')
            return { to = 'officer', cid = Player.PlayerData.citizenid }
        end
    elseif to == 'society' then
        JS.AddSocietyMoney(amount, reason)
        return { to = 'society' }
    end
    return { to = 'none' }
end

-- عكس DepositWithdrawn (للتراجع): يسحب المبلغ من الموظف اللي استلمه
function JS.ReverseDeposit(dest, amount)
    if type(dest) ~= 'table' or dest.to ~= 'officer' or not dest.cid then return true end
    local ok, err = JS.TakeMoney(dest.cid, amount, 'justice-undo')
    if not ok then return false, 'الموظف اللي استلم المبلغ رصيده ما يكفي لإرجاعه (' .. tostring(err) .. ')' end
    return true
end

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- فترات الانتظار والحماية من التكرار
-- ════════════════════════════════════════════════════════════════════════════════════════════════

local cooldowns = {}
local throttles = {}

-- يرجع true والوقت المتبقي إذا كان في فترة انتظار، وإلا يبدأ فترة جديدة
function JS.OnCooldown(kind, key, seconds)
    cooldowns[kind] = cooldowns[kind] or {}
    local now = os.time()
    local expires = cooldowns[kind][key]
    if expires and expires > now then
        return true, expires - now
    end
    cooldowns[kind][key] = now + seconds
    return false
end

function JS.ClearCooldown(kind, key)
    if cooldowns[kind] then cooldowns[kind][key] = nil end
end

function JS.Throttle(src, name, ms)
    throttles[src] = throttles[src] or {}
    local now = GetGameTimer()
    local last = throttles[src][name]
    if last and now - last < ms then return true end
    throttles[src][name] = now
    return false
end

AddEventHandler('playerDropped', function()
    throttles[source] = nil
end)

CreateThread(function()
    while true do
        Wait(600000)
        local now = os.time()
        for _, list in pairs(cooldowns) do
            for key, expires in pairs(list) do
                if expires <= now then list[key] = nil end
            end
        end
    end
end)

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- Callbacks آمنة: تتحقق من الجاهزية والصلاحية وتلتقط الأخطاء
-- كل callback يرجع { ok = true, ... } أو { ok = false, err = '...' }
-- ════════════════════════════════════════════════════════════════════════════════════════════════

-- كل الإجراءات مسجلة هنا عشان نظام التراجع يستخدم نفس الكود بنفس التحققات
JS.Handlers = {}

function JS.RegisterCallback(name, action, handler)
    JS.Handlers[name] = handler
    RTCore.Functions.CreateCallback(name, function(source, cb, ...)
        local src = source

        if not JS.Ready then
            return cb({ ok = false, err = 'النظام قيد التحميل، حاول بعد قليل' })
        end
        if JS.Throttle(src, name, 300) then
            return cb({ ok = false, err = 'الرجاء الانتظار قليلاً' })
        end

        local Player = RTCore.Functions.GetPlayer(src)
        if not Player then
            return cb({ ok = false, err = 'تعذر العثور على بياناتك' })
        end

        if action then
            local allowed, err
            if type(action) == 'function' then
                allowed, err = action(Player)
            else
                allowed, err = JS.Can(Player, action)
            end
            if not allowed then return cb({ ok = false, err = err or 'غير مسموح' }) end
        end

        local success, result = pcall(handler, src, Player, ...)
        if not success then
            print(('^1[RespectJustice] %s error: %s^7'):format(name, tostring(result)))
            return cb({ ok = false, err = 'حدث خطأ غير متوقع' })
        end

        cb(result or { ok = true })
    end)
end

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- قاعدة البيانات
-- ════════════════════════════════════════════════════════════════════════════════════════════════

function JS.SafeIdentifier(name)
    return type(name) == 'string' and name:match('^[%w_]+$') ~= nil
end

function JS.TableExists(tableName)
    if not JS.SafeIdentifier(tableName) then return false end
    local key = 't:' .. tableName
    if schemaCache[key] == nil then
        local count = MySQL.scalar.await(
            'SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ?',
            { tableName })
        schemaCache[key] = (tonumber(count) or 0) > 0
    end
    return schemaCache[key]
end

function JS.ColumnExists(tableName, column)
    if not JS.SafeIdentifier(tableName) or not JS.SafeIdentifier(column) then return false end
    local key = ('c:%s.%s'):format(tableName, column)
    if schemaCache[key] == nil then
        local count = MySQL.scalar.await(
            'SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?',
            { tableName, column })
        schemaCache[key] = (tonumber(count) or 0) > 0
    end
    return schemaCache[key]
end

-- تنفيذ استعلام تحديث للجداول بدون ما يوقف التشغيل لو فشل
function JS.TryQuery(query, params)
    local ok, err = pcall(MySQL.query.await, query, params)
    if not ok then
        print(('^3[RespectJustice]^7 DB step skipped: %s'):format(tostring(err)))
    end
    return ok
end

function JS.EnsureColumn(tableName, column, definition)
    if JS.ColumnExists(tableName, column) then return end
    if JS.TryQuery(('ALTER TABLE `%s` ADD COLUMN `%s` %s'):format(tableName, column, definition)) then
        schemaCache[('c:%s.%s'):format(tableName, column)] = true
        print(('^3[RespectJustice]^7 Added column %s.%s'):format(tableName, column))
    end
end

-- أعمدة خفيفة من جدول players (بدون المخزون الثقيل) + last_updated إذا موجود
function JS.PlayerListColumns()
    local cols = 'citizenid, charinfo, job'
    if JS.ColumnExists(Settings.Database.Players, 'last_updated') then
        cols = cols .. ', last_updated'
    end
    return cols
end

function JS.EnsureIndex(tableName, column)
    if not JS.SafeIdentifier(tableName) or not JS.SafeIdentifier(column) then return end
    local count = MySQL.scalar.await(
        'SELECT COUNT(*) FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?',
        { tableName, column })
    if (tonumber(count) or 0) == 0 then
        JS.TryQuery(('ALTER TABLE `%s` ADD INDEX `idx_%s` (`%s`)'):format(tableName, column, column))
    end
end

-- تحديث عمود JSON لمواطن غير متصل بأمان:
-- يتأكد إن البيانات ما تغيرت أثناء العملية، ويعتبر العملية ناجحة إذا القيمة الجديدة نفس القديمة
local PlayerJsonColumns = { money = true, charinfo = true, job = true, gang = true, metadata = true }

function JS.UpdatePlayerJson(citizenid, column, newValue, oldRaw)
    if not PlayerJsonColumns[column] then return false end
    local encoded = json.encode(newValue)
    if encoded == oldRaw then return true end

    local tableName = Settings.Database.Players
    local affected = MySQL.update.await(('UPDATE `%s` SET `%s` = ? WHERE citizenid = ? AND `%s` = ?'):format(tableName, column, column), {
        encoded, citizenid, oldRaw
    })
    if affected and affected > 0 then return true end

    -- بعض قواعد البيانات ترجع 0 إذا القيمة ما تغيرت فعلياً
    local current = MySQL.scalar.await(('SELECT `%s` FROM `%s` WHERE citizenid = ?'):format(column, tableName), { citizenid })
    return current == encoded
end

function JS.GetPlayerRow(citizenid)
    local tableName = Settings.Database.Players
    if not JS.TableExists(tableName) then return nil end
    return MySQL.single.await(('SELECT * FROM `%s` WHERE citizenid = ? LIMIT 1'):format(tableName), { citizenid })
end

-- يرجع بيانات المواطن سواء كان متصلاً أو غير متصل
-- { online = Player|nil, citizenid, charinfo, money, job, gang, metadata, items, lastUpdated }
function JS.GetCitizen(citizenid)
    local Player = RTCore.Functions.GetPlayerByCitizenId(citizenid)
    if Player then
        local pd = Player.PlayerData
        return {
            online = Player,
            citizenid = pd.citizenid,
            charinfo = pd.charinfo or {},
            money = pd.money or {},
            job = pd.job or {},
            gang = pd.gang or {},
            metadata = pd.metadata or {},
            items = pd.items or {},
        }
    end

    local row = JS.GetPlayerRow(citizenid)
    if not row then return nil end
    return {
        citizenid = row.citizenid,
        charinfo = JS.Decode(row.charinfo),
        money = JS.Decode(row.money),
        job = JS.Decode(row.job),
        gang = JS.Decode(row.gang),
        metadata = JS.Decode(row.metadata),
        items = JS.Decode(row.inventory),
        lastUpdated = JS.FormatDbDate(row.last_updated),
        lastUpdatedRaw = row.last_updated,
        raw = row,
    }
end

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- السجلات (قاعدة البيانات + Discord اختياري)
-- ضع في server.cfg:  set justice_webhook "https://discord.com/api/webhooks/..."
-- ════════════════════════════════════════════════════════════════════════════════════════════════

JS.ActionLabels = {
    view = 'فتح ملف مواطن',
    locate = 'تحديد موقع',
    withdraw = 'سحب من البنك',
    suspend = 'إيقاف خدمات',
    unsuspend = 'رفع إيقاف الخدمات',
    edit = 'تعديل بيانات',
    compensation = 'تعويض',
    report_status = 'تغيير حالة قضية',
    report_note = 'ملاحظة على قضية',
    report_delete = 'حذف قضية',
    job = 'تغيير وظيفة',
    duty = 'تغيير دوام موظف',
    vehicle_impound = 'حجز مركبة',
    vehicle_release = 'فك حجز مركبة',
    vehicle_transfer = 'نقل ملكية مركبة',
    property_transfer = 'نقل ملكية عقار',
    license_grant = 'منح ترخيص',
    license_revoke = 'سحب ترخيص',
    gang = 'تغيير عصابة',
    summon = 'استدعاء للمحكمة',
    announce = 'إعلان للمدينة',
    log_delete = 'حذف سجل',
    undo = 'تراجع عن إجراء',
    verdict = 'إصدار حكم',
    suspect_add = 'إضافة مشبوه',
    suspect_remove = 'إزالة مشبوه',
    warrant_issue = 'إصدار أمر',
    warrant_cancel = 'إلغاء أمر',
    warrant_execute = 'تنفيذ أمر (شرطة)',
    lawyer_assign = 'تعيين محامي',
    lawyer_remove = 'إزالة محامي',
    police_request = 'طلب تصريح (شرطة)',
    police_answer = 'الرد على طلب شرطة',
    summon_delete = 'حذف استدعاء',
}

local webhook = GetConvar('justice_webhook', '')

-- undo: بيانات التراجع عن الإجراء (nil = ما يمكن التراجع عنه)
function JS.Log(Player, action, targetCitizenid, targetName, details, undo)
    local officerCid = Player and Player.PlayerData.citizenid or 'system'
    local officerName = Player and JS.PlayerName(Player) or 'system'
    local encoded = details and json.encode(details) or nil

    MySQL.insert('INSERT INTO justice_logs (officer_citizenid, officer_name, action, target_citizenid, target_name, details, undo_data) VALUES (?, ?, ?, ?, ?, ?, ?)', {
        officerCid, officerName, action, targetCitizenid, targetName, encoded, undo and json.encode(undo) or nil
    })

    if webhook == '' or (Settings.Panel.WebhookSkip or {})[action] then return end

    local lines = {
        ('**الموظف:** %s (%s)'):format(officerName, officerCid),
    }
    if targetCitizenid then
        lines[#lines + 1] = ('**المواطن:** %s (%s)'):format(targetName or '-', targetCitizenid)
    end
    for key, value in pairs(details or {}) do
        lines[#lines + 1] = ('**%s:** %s'):format(key, type(value) == 'table' and json.encode(value) or tostring(value))
    end

    JS.QueueWebhook({
        title = JS.ActionLabels[action] or action,
        description = JS.Truncate(table.concat(lines, '\n'), 3900),
        color = 13280380,
        timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ'),
    })
end

-- طابور Discord: رسالة كل ثانية ونص عشان ما ينحظر الـ webhook (حد Discord للطلبات)
local webhookQueue = {}

function JS.QueueWebhook(embed)
    if #webhookQueue >= 200 then table.remove(webhookQueue, 1) end
    webhookQueue[#webhookQueue + 1] = embed
end

CreateThread(function()
    if webhook == '' then return end
    while true do
        local embed = table.remove(webhookQueue, 1)
        if embed then
            PerformHttpRequest(webhook, function(status)
                if status == 429 then table.insert(webhookQueue, 1, embed) end
            end, 'POST', json.encode({ username = 'RespectJustice', embeds = { embed } }), { ['Content-Type'] = 'application/json' })
        end
        Wait(embed and 1500 or 1000)
    end
end)

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- حساب الوزارة (اختياري)
-- ════════════════════════════════════════════════════════════════════════════════════════════════

function JS.AddSocietyMoney(amount, reason)
    local society = Settings.Panel.Society
    if not society or not society.enabled then return end
    local ok, err = pcall(function()
        local resource = exports[society.resource]
        resource[society.func](resource, JS.Job, amount, reason)
    end)
    if not ok then
        print(('^1[RespectJustice]^7 Society deposit failed: %s'):format(tostring(err)))
    end
end

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- إيقاف الخدمات - Exports لباقي السكربتات
-- exports['RespectJustice']:IsCitizenSuspended(citizenid) -> boolean
-- exports['RespectJustice']:GetCitizenSuspension(citizenid) -> { reason, officer, date } | nil
-- ════════════════════════════════════════════════════════════════════════════════════════════════

exports('IsCitizenSuspended', function(citizenid)
    return JS.Suspended[tostring(citizenid)] ~= nil
end)

exports('GetCitizenSuspension', function(citizenid)
    return JS.Suspended[tostring(citizenid)]
end)
