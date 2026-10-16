-- قاعدة البيانات: مين مسجل في أي عالم حسب رقم الهوية
-- تستخدم oxmysql لو موجود (وتسوي الجدول لحالها)، ولو ما فيه تحفظ في members.json

DB = {
    members = {},   -- [رقم الهوية] = { world, name, added_by, added_at }
}

local FILE = 'members.json'

local function useSQL()
    return GetResourceState('oxmysql') == 'started'
end

local function sql(query, params)
    local p = promise.new()
    exports.oxmysql:query(query, params or {}, function(result) p:resolve(result) end)
    return Citizen.Await(p)
end

local function saveFile()
    SaveResourceFile(GetCurrentResourceName(), FILE, json.encode(DB.members, { indent = true }), -1)
end

function DB.load()
    DB.members = {}
    if useSQL() then
        sql([[
            CREATE TABLE IF NOT EXISTS `world_members` (
                `citizenid` VARCHAR(64) NOT NULL,
                `world` VARCHAR(32) NOT NULL,
                `name` VARCHAR(100) NULL,
                `added_by` VARCHAR(100) NULL,
                `added_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (`citizenid`)
            )
        ]])
        local rows = sql('SELECT citizenid, world, name, added_by, added_at FROM world_members') or {}
        for _, row in ipairs(rows) do
            local at = row.added_at
            if type(at) == 'number' then at = os.date('%Y-%m-%d %H:%M', math.floor(at / 1000)) end
            DB.members[row.citizenid] = { world = row.world, name = row.name, added_by = row.added_by, added_at = at }
        end
    else
        local raw = LoadResourceFile(GetCurrentResourceName(), FILE)
        local ok, data = pcall(json.decode, raw or '{}')
        if ok and type(data) == 'table' then DB.members = data end
    end
end

function DB.get(cid)
    return DB.members[cid]
end

function DB.set(cid, world, name, by)
    DB.members[cid] = { world = world, name = name, added_by = by, added_at = os.date('%Y-%m-%d %H:%M') }
    if useSQL() then
        sql([[
            INSERT INTO world_members (citizenid, world, name, added_by) VALUES (?, ?, ?, ?)
            ON DUPLICATE KEY UPDATE world = VALUES(world), name = VALUES(name), added_by = VALUES(added_by), added_at = CURRENT_TIMESTAMP
        ]], { cid, world, name, by })
    else
        saveFile()
    end
end

function DB.remove(cid)
    DB.members[cid] = nil
    if useSQL() then
        sql('DELETE FROM world_members WHERE citizenid = ?', { cid })
    else
        saveFile()
    end
end

-- اسم الشخصية من قاعدة بيانات الفريمورك (للاعب المطفي)، ويرجع nil لو رقم الهوية مو موجود
function DB.lookupName(cid)
    if not useSQL() then return '' end
    local fw = Framework.name()
    if fw == 'qb' or fw == 'qbx' then
        local row = (sql('SELECT charinfo FROM players WHERE citizenid = ? LIMIT 1', { cid }) or {})[1]
        if not row then return nil end
        local ok, info = pcall(json.decode, row.charinfo or '{}')
        return ok and info and ('%s %s'):format(info.firstname or '', info.lastname or '') or ''
    elseif fw == 'esx' then
        local row = (sql('SELECT firstname, lastname FROM users WHERE identifier = ? LIMIT 1', { cid }) or {})[1]
        if not row then return nil end
        return ('%s %s'):format(row.firstname or '', row.lastname or '')
    end
    return ''
end
