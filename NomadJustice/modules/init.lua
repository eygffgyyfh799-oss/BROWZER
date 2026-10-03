JUtil = {}
JUtil.Functions = {}

-- Core: qb-core (you can change the name from server.cfg:  setr justice_core "qb-core")
JCoreResource = GetConvar('justice_core', 'qb-core')
QBCore = exports[JCoreResource]:GetCoreObject()

local resourceName = GetCurrentResourceName()

local function Warn(msg)
	print(('^3[NomadJustice] %s^7'):format(msg))
end

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- Load module files
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

-- Like Load but never stops the script: prints the error clearly (file name + line number) and returns nil
local function SafeLoad(name)
	local chunk = LoadResourceFile(resourceName, ('modules/%s.lua'):format(name))
	if not chunk then
		print(('^1[NomadJustice] File modules/%s.lua not found^7'):format(name))
		return nil
	end
	local fn, err = load(chunk, ('=%s.lua'):format(name), 't')
	if not fn then
		print(('^1[NomadJustice] Syntax error in %s.lua -> %s^7'):format(name, tostring(err)))
		print('^1[NomadJustice] Usually a missing comma , a missing brace } or a missing quote \' on that line or the one before it^7')
		return nil
	end
	local ok, result = pcall(fn)
	if not ok then
		print(('^1[NomadJustice] Error in %s.lua -> %s^7'):format(name, tostring(result)))
		return nil
	end
	return result
end

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- Defaults: any setting removed or forgotten in config.lua falls back to these values instead of breaking the script
-- ════════════════════════════════════════════════════════════════════════════════════════════════

local Defaults = {
	Settings = {
		Job = 'judge', TargetResource = 'deep-target', InventoryResource = 'deep-inventory',
		DutyCooldown = 15, DutyHistoryLimit = 100,
		ReportFee = 200, ReportMaxLength = 800, ReportMinLength = 10, ReportCooldown = 300,
		CompensationMax = 1000000, CompensationDailyMax = 3000000, CompensationMaxDistance = 5.0, CompensationCooldown = 10, CompensationHardCap = 2000000000,
		PersonalStash = { maxweight = 100000, slots = 100 },
		ArchiveStash = { maxweight = 100000, slots = 200 },
		MaxSpawnedVehicles = 1, VehicleFuel = 75.0,
		CaseTypes = { 'Civil', 'Criminal', 'Traffic', 'Real Estate', 'Commercial', 'Family', 'Labor', 'Other' },
		ReportTitleMax = 80, ReportWitnessesMax = 200, ReportEvidenceMax = 500, ReportNoteMax = 500,
		Panel = {
			Command = 'justice', RequireDuty = true, FullAccessGrade = 11, OwnerCitizenIds = {}, PhoneItems = { 'phone' }, UseTablet = true, Key = '9', TabletAnimation = true,
			Permissions = {
				view = 0, reports = 0, city = 0, deleteReport = 8, locate = 4, withdraw = 9, suspend = 9, edit = 8,
				logs = 8, compensation = 9, unlimitedCompensation = 11, jobs = 11, summon = 1, vehicles = 9, properties = 9,
				licenses = 1, gangs = 9, announce = 8, economy = 8, undo = 11, delete = 11,
				verdicts = 8, warrants = 8, suspects = 4, lawyers = 8, policeRequests = 8, stats = 8,
			},
			UnemployedJob = 'unemployed', JobsBlacklist = {},
			WithdrawMax = 5000000, WithdrawCooldown = 5, LocateBlipTime = 60, LogViews = true,
			Society = { enabled = false, resource = 'qb-management', func = 'AddMoney' },
			WebhookSkip = { view = true, police_view = true },
			WithdrawTo = 'officer',
		},
		Police = {
			Jobs = { 'police' }, RequireDuty = true, GrantMinutes = 30, RequestCooldown = 60,
			Permissions = { search = 0, profile = 0, vehicles = 2, warrants = 0, executeWarrant = 3, suspects = 0, requests = 6 },
		},
		Lawyers = { License = 'lawyer', Jobs = {}, DocumentMax = 2000 },
		Finance = { RequireDuty = true, MaxPerTransaction = 1000000, Provider = 'auto', Resource = 'deep-Banking', Sectors = {} },
		Verdicts = { MaxFine = 10000000, MaxJail = 120, JailEvent = '', WarrantHours = 72 },
		City = {
			ImpoundFee = 500, ImpoundGarage = 'impoundlot', AnnounceCooldown = 60,
			AnnounceMaxLength = 250, SummonMaxLength = 200, NoGang = 'none',
		},
		Cleanup = { LogsDays = 120, DutyDays = 60, ClosedReportsDays = 0 },
		Database = {
			Players = 'players', Vehicles = 'player_vehicles',
			Houses = { table = 'player_houses', owner = 'citizenid', label = 'house', id = 'id' },
		},
		Licenses = { driver = 'Driver License', weapon = 'Weapon License' },
	},
	Peds = {
		['Case Clerk'] = { model = 'cs_josh' },
		['Motor Pool Clerk'] = { model = 'csb_trafficwarden' },
	},
	Blip = { sprite = 176, colour = 0, scale = 0.45 },
	Vehicles = {},
	ZoneSize = 2.5,
	DebugZones = false,
}

-- Lists (arrays) are copied whole, plain tables are merged key by key
local function IsArray(t)
	return type(t) == 'table' and (next(t) == nil or t[1] ~= nil)
end

-- Tables fully owned by the server owner: if present we add nothing (so removed entries stay removed)
local NoMerge = { Licenses = true, Peds = true, WebhookSkip = true, Society = true, Houses = true, Sectors = true }

local quiet = false

local function FillDefaults(target, defaults, path)
	for key, value in pairs(defaults) do
		local current = target[key]
		if NoMerge[key] and type(current) == 'table' then
			-- Present: keep as is
		elseif current == false and type(value) ~= 'table' then
			-- false = intentionally disabled (e.g. a locked permission)
		elseif current == nil then
			target[key] = value
			if path ~= '' and not quiet then Warn(('Setting %s%s is missing in config.lua, using the default'):format(path, key)) end
		elseif type(value) == 'table' and not IsArray(value) then
			if type(current) ~= 'table' then
				Warn(('Setting %s%s must be a table { }, using the default'):format(path, key))
				target[key] = value
			else
				FillDefaults(current, value, path .. key .. '.')
			end
		elseif type(value) ~= type(current) and not (type(value) == 'number' and tonumber(current)) then
			Warn(('Setting %s%s has the wrong type (expected %s), using the default'):format(path, key, type(value)))
			target[key] = value
		end
	end
end

local configCache

function LoadConfig()
	if configCache then return configCache end

	local cfg = SafeLoad('config')
	if type(cfg) ~= 'table' then
		print('^1[NomadJustice] config.lua has an error, the script runs on defaults until you fix it^7')
		cfg = {}
		quiet = true
	end
	cfg.Settings = type(cfg.Settings) == 'table' and cfg.Settings or {}
	FillDefaults(cfg, Defaults, '')
	quiet = false

	-- Permissions: the value must be a number or 'boss'
	for action, value in pairs(cfg.Settings.Panel.Permissions) do
		if value ~= 'boss' and value ~= false and not tonumber(value) then
			Warn(("Permission %s has an invalid value (%s), it must be a number or 'boss', converted to 'boss'"):format(action, tostring(value)))
			cfg.Settings.Panel.Permissions[action] = 'boss'
		end
	end
	if #cfg.Settings.CaseTypes == 0 then cfg.Settings.CaseTypes = Defaults.Settings.CaseTypes end

	configCache = cfg
	return cfg
end

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- Coordinates: validates every line and skips bad ones with a clear message instead of breaking everything
-- ════════════════════════════════════════════════════════════════════════════════════════════════

local coordsCache

function LoadCoords()
	if coordsCache then return coordsCache end

	local list = SafeLoad('coords')
	if type(list) ~= 'table' then
		print('^1[NomadJustice] coords.lua has an error, no points will appear until you fix it^7')
		coordsCache = {}
		return coordsCache
	end

	local valid = {}
	for i, entry in ipairs(list) do
		local label = type(entry) == 'table' and tostring(entry.name or '?') or '?'
		local c = type(entry) == 'table' and entry.coords
		local ok = c ~= nil and tonumber(c.x) and tonumber(c.y) and tonumber(c.z)
		if type(entry) ~= 'table' then
			Warn(('coords.lua line %d: must be wrapped in { }'):format(i))
		elseif type(entry.type) ~= 'string' then
			Warn(('coords.lua line %d (%s): type is missing'):format(i, label))
		elseif not ok then
			Warn(('coords.lua line %d (%s): invalid coords, must be vector4(X, Y, Z, heading)'):format(i, label))
		else
			valid[#valid + 1] = entry
		end
	end

	coordsCache = valid
	return valid
end

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- General helpers
-- ════════════════════════════════════════════════════════════════════════════════════════════════

JUtil.Functions.formatDateReports = function(timestamp)
	local dateTable = os.date("*t", math.floor(timestamp / 1000))
	return string.format("%02d/%02d/%04d | %02d:%02d:%02d", dateTable.month, dateTable.day, dateTable.year, dateTable.hour, dateTable.min, dateTable.sec)
end

JUtil.Functions.trim = function(str)
	if type(str) ~= 'string' then return nil end
	return (str:gsub('^%s+', ''):gsub('%s+$', ''))
end
