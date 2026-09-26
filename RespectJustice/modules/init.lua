_2rayan = {}
_2rayan.Functions = {}
RTCore = exports['RespectCore']:GetCoreObject()

local resourceName = GetCurrentResourceName()

local function Warn(msg)
	print(('^3[RespectJustice] %s^7'):format(msg))
end

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- تحميل ملفات modules
-- ════════════════════════════════════════════════════════════════════════════════════════════════

function Load(name)
	local chunk = LoadResourceFile(resourceName, ('modules/%s.lua'):format(name))
	if not chunk then
		error(('\n^1[%s] Unable to load modules/%s.lua^0'):format(resourceName, name), 0)
	end
	local fn, err = load(chunk, ('@@%s/modules/%s.lua'):format(resourceName, name), 't')
	if not fn then
		error(('\n^1 %s'):format(err), 0)
	end
	return fn()
end

-- مثل Load لكن ما يوقف السكربت: يطبع الخطأ بشكل واضح (اسم الملف + رقم السطر) ويرجع nil
local function SafeLoad(name)
	local chunk = LoadResourceFile(resourceName, ('modules/%s.lua'):format(name))
	if not chunk then
		print(('^1[RespectJustice] الملف modules/%s.lua غير موجود^7'):format(name))
		return nil
	end
	local fn, err = load(chunk, ('=%s.lua'):format(name), 't')
	if not fn then
		print(('^1[RespectJustice] خطأ كتابة في ملف %s.lua ← %s^7'):format(name, tostring(err)))
		print('^1[RespectJustice] غالباً فاصلة ناقصة , أو قوس ناقص } أو علامة \' ناقصة في السطر المذكور أو اللي قبله^7')
		return nil
	end
	local ok, result = pcall(fn)
	if not ok then
		print(('^1[RespectJustice] خطأ في ملف %s.lua ← %s^7'):format(name, tostring(result)))
		return nil
	end
	return result
end

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- الإعدادات الافتراضية: أي إعداد ينحذف أو ينسى من config.lua ياخذ القيمة هذي بدل ما يعطل السكربت
-- ════════════════════════════════════════════════════════════════════════════════════════════════

local Defaults = {
	Settings = {
		Job = 'justice',
		DutyCooldown = 15, DutyHistoryLimit = 100,
		ReportFee = 200, ReportMaxLength = 800, ReportMinLength = 10, ReportCooldown = 300,
		CompensationMax = 1000000, CompensationDailyMax = 3000000, CompensationMaxDistance = 5.0, CompensationCooldown = 10,
		PersonalStash = { maxweight = 100000, slots = 100 },
		ArchiveStash = { maxweight = 100000, slots = 200 },
		MaxSpawnedVehicles = 1, VehicleFuel = 75.0,
		CaseTypes = { 'مدنية', 'جنائية', 'مرورية', 'عقارية', 'تجارية', 'أسرية', 'عمالية', 'أخرى' },
		ReportTitleMax = 80, ReportWitnessesMax = 200, ReportEvidenceMax = 500, ReportNoteMax = 500,
		Panel = {
			Command = 'justice', RequireDuty = true, FullAccessGrade = 10,
			Permissions = {
				view = 0, reports = 0, city = 0, summon = 0,
				deleteReport = 'boss', locate = 'boss', withdraw = 'boss', suspend = 'boss', edit = 'boss',
				logs = 'boss', compensation = 'boss', jobs = 'boss', vehicles = 'boss', properties = 'boss',
				licenses = 'boss', gangs = 'boss', announce = 'boss', economy = 'boss',
			},
			UnemployedJob = 'unemployed', JobsBlacklist = {},
			WithdrawMax = 5000000, WithdrawCooldown = 5, LocateBlipTime = 60, LogViews = true,
			Society = { enabled = false, resource = 'qb-management', func = 'AddMoney' },
			WebhookSkip = { view = true },
		},
		City = {
			ImpoundFee = 500, ImpoundGarage = 'impoundlot', AnnounceCooldown = 60,
			AnnounceMaxLength = 250, SummonMaxLength = 200, NoGang = 'none',
		},
		Cleanup = { LogsDays = 120, DutyDays = 60, ClosedReportsDays = 0 },
		Database = {
			Players = 'players', Vehicles = 'player_vehicles',
			Houses = { table = 'player_houses', owner = 'citizenid', label = 'house', id = 'id' },
		},
		Licenses = { driver = 'رخصة القيادة', weapon = 'رخصة السلاح' },
	},
	Peds = {
		['بوت القضايا'] = { model = 'cs_josh' },
		['بوت المركبات'] = { model = 'csb_trafficwarden' },
	},
	Blip = { sprite = 176, colour = 0, scale = 0.45 },
	Vehicles = {},
	ZoneSize = 2.5,
	DebugZones = false,
}

-- القوائم (مصفوفات) تنسخ كاملة، والجداول العادية تنكمل مفتاح مفتاح
local function IsArray(t)
	return type(t) == 'table' and (next(t) == nil or t[1] ~= nil)
end

-- جداول يحددها صاحب السيرفر بالكامل: إذا موجودة ما نضيف فيها شي (عشان ما يرجع شي حذفته)
local NoMerge = { Licenses = true, Peds = true, WebhookSkip = true, Society = true, Houses = true }

local quiet = false

local function FillDefaults(target, defaults, path)
	for key, value in pairs(defaults) do
		local current = target[key]
		if NoMerge[key] and type(current) == 'table' then
			-- موجود: نتركه مثل ما هو
		elseif current == nil then
			target[key] = value
			if path ~= '' and not quiet then Warn(('الإعداد %s%s ناقص في config.lua، تم استخدام القيمة الافتراضية'):format(path, key)) end
		elseif type(value) == 'table' and not IsArray(value) then
			if type(current) ~= 'table' then
				Warn(('الإعداد %s%s لازم يكون جدول { }، تم استخدام القيمة الافتراضية'):format(path, key))
				target[key] = value
			else
				FillDefaults(current, value, path .. key .. '.')
			end
		elseif type(value) ~= type(current) and not (type(value) == 'number' and tonumber(current)) then
			Warn(('الإعداد %s%s نوعه غلط (المفروض %s)، تم استخدام القيمة الافتراضية'):format(path, key, type(value)))
			target[key] = value
		end
	end
end

local configCache

function LoadConfig()
	if configCache then return configCache end

	local cfg = SafeLoad('config')
	if type(cfg) ~= 'table' then
		print('^1[RespectJustice] ملف config.lua فيه خطأ، السكربت يشتغل بالإعدادات الافتراضية لين تصلحه^7')
		cfg = {}
		quiet = true
	end
	cfg.Settings = type(cfg.Settings) == 'table' and cfg.Settings or {}
	FillDefaults(cfg, Defaults, '')
	quiet = false

	-- الصلاحيات: القيمة لازم تكون رقم أو 'boss'
	for action, value in pairs(cfg.Settings.Panel.Permissions) do
		if value ~= 'boss' and not tonumber(value) then
			Warn(("الصلاحية %s قيمتها غلط (%s)، لازم رقم أو 'boss'، تم تحويلها إلى 'boss'"):format(action, tostring(value)))
			cfg.Settings.Panel.Permissions[action] = 'boss'
		end
	end
	if #cfg.Settings.CaseTypes == 0 then cfg.Settings.CaseTypes = Defaults.Settings.CaseTypes end

	configCache = cfg
	return cfg
end

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- الإحداثيات: يتأكد من كل سطر ويتخطى السطر الغلط مع رسالة واضحة بدل ما يعطل الكل
-- ════════════════════════════════════════════════════════════════════════════════════════════════

local coordsCache

function LoadCoords()
	if coordsCache then return coordsCache end

	local list = SafeLoad('coords')
	if type(list) ~= 'table' then
		print('^1[RespectJustice] ملف coords.lua فيه خطأ، ما راح تطلع أي نقطة لين تصلحه^7')
		coordsCache = {}
		return coordsCache
	end

	local valid = {}
	for i, entry in ipairs(list) do
		local label = type(entry) == 'table' and tostring(entry.name or '?') or '?'
		local c = type(entry) == 'table' and entry.coords
		local ok = c ~= nil and tonumber(c.x) and tonumber(c.y) and tonumber(c.z)
		if type(entry) ~= 'table' then
			Warn(('coords.lua السطر رقم %d: لازم يكون بين { }'):format(i))
		elseif type(entry.type) ~= 'string' then
			Warn(('coords.lua السطر رقم %d (%s): type ناقص'):format(i, label))
		elseif not ok then
			Warn(('coords.lua السطر رقم %d (%s): coords غلط، لازم vector4(X, Y, Z, الاتجاه)'):format(i, label))
		else
			valid[#valid + 1] = entry
		end
	end

	coordsCache = valid
	return valid
end

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- أدوات عامة
-- ════════════════════════════════════════════════════════════════════════════════════════════════

_2rayan.Functions.formatDateReports = function(timestamp)
	local dateTable = os.date("*t", math.floor(timestamp / 1000))
	return string.format("%02d/%02d/%04d | %02d:%02d:%02d", dateTable.month, dateTable.day, dateTable.year, dateTable.hour, dateTable.min, dateTable.sec)
end

_2rayan.Functions.trim = function(str)
	if type(str) ~= 'string' then return nil end
	return (str:gsub('^%s+', ''):gsub('%s+$', ''))
end
