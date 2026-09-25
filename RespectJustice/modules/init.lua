_2rayan = {}
_2rayan.Functions = {}
RTCore = exports['RespectCore']:GetCoreObject()

function Load(name)
	local resourceName = GetCurrentResourceName()
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

_2rayan.Functions.formatDateReports = function(timestamp)
	local dateTable = os.date("*t", math.floor(timestamp / 1000))
	return string.format("%02d/%02d/%04d | %02d:%02d:%02d", dateTable.month, dateTable.day, dateTable.year, dateTable.hour, dateTable.min, dateTable.sec)
end

_2rayan.Functions.trim = function(str)
	if type(str) ~= 'string' then return nil end
	return (str:gsub('^%s+', ''):gsub('%s+$', ''))
end
