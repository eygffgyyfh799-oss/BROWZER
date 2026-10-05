local QBCore = exports['qb-core']:GetCoreObject()
local T = Config.Tables
local busy = false

-- ════════════════════════════════════════════════════════════
-- Helpers
-- ════════════════════════════════════════════════════════════

local function Notify(src, msg, msgType)
    if src == 0 then
        print('^3[NomadCopyChar]^7 ' .. msg)
    else
        TriggerClientEvent('QBCore:Notify', src, msg, msgType or 'primary', 8000)
    end
end

local function IsAllowed(src)
    if src == 0 then return true end -- server console
    if IsPlayerAceAllowed(src, 'command.' .. Config.Command) then return true end
    for _, group in ipairs(Config.Permissions or {}) do
        local ok, has = pcall(QBCore.Functions.HasPermission, src, group)
        if ok and has then return true end
    end
    local Player = QBCore.Functions.GetPlayer(src)
    if Player then
        for _, cid in ipairs(Config.AllowedCitizenIds or {}) do
            if Player.PlayerData.citizenid == tostring(cid) then return true end
        end
    end
    return false
end

local function Decode(value)
    if type(value) == 'table' then return value end
    if type(value) ~= 'string' or value == '' then return {} end
    local ok, data = pcall(json.decode, value)
    return ok and type(data) == 'table' and data or {}
end

local function RandomString(length, chars)
    local out = {}
    for i = 1, length do
        local n = math.random(1, #chars)
        out[i] = chars:sub(n, n)
    end
    return table.concat(out)
end

local LETTERS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
local DIGITS = '0123456789'
local ALNUM = LETTERS .. DIGITS

local function TableExists(name)
    return MySQL.scalar.await('SHOW TABLES LIKE ?', { name }) ~= nil
end

local function Unique(generate, query)
    for _ = 1, 50 do
        local value = generate()
        if not MySQL.scalar.await(query, { value }) then return value end
    end
    return nil
end

local function NewCitizenId()
    return Unique(function() return RandomString(3, LETTERS) .. RandomString(5, DIGITS) end,
        ('SELECT 1 FROM `%s` WHERE citizenid = ? LIMIT 1'):format(T.players))
end

local function NewPhone()
    local phone = Unique(function() return RandomString(10, DIGITS):gsub('^0', tostring(math.random(1, 9))) end,
        ('SELECT 1 FROM `%s` WHERE charinfo LIKE CONCAT(\'%%"phone":"\', ?, \'"%%\') LIMIT 1'):format(T.players))
    return phone
end

local function NewAccount()
    return Unique(function() return 'US0' .. math.random(1, 9) .. 'QBCore' .. RandomString(10, DIGITS) end,
        ('SELECT 1 FROM `%s` WHERE charinfo LIKE CONCAT(\'%%"account":"\', ?, \'"%%\') LIMIT 1'):format(T.players))
end

local function NewPlate(used)
    return Unique(function()
        local plate
        repeat plate = RandomString(4, LETTERS) .. RandomString(4, DIGITS) until not used[plate]
        used[plate] = true
        return plate
    end, ('SELECT 1 FROM `%s` WHERE plate = ? LIMIT 1'):format(T.vehicles))
end

-- First free character slot on an account
local function FreeSlot(license)
    local used = {}
    for _, row in ipairs(MySQL.query.await(('SELECT cid FROM `%s` WHERE license = ?'):format(T.players), { license }) or {}) do
        used[tonumber(row.cid) or -1] = true
    end
    for slot = 1, Config.MaxSlots do
        if not used[slot] then return slot end
    end
    return nil
end

-- Builds an INSERT from every column of a row (works whatever extra columns your tables have)
local function InsertQuery(tableName, row, skip)
    local cols, marks, values = {}, {}, {}
    for column, value in pairs(row) do
        if type(column) == 'string' and column:match('^%a[%w_]*$') and not skip[column] then
            if type(value) == 'table' then value = json.encode(value) end
            cols[#cols + 1] = '`' .. column .. '`'
            marks[#marks + 1] = '?'
            values[#values + 1] = value
        end
    end
    return { query = ('INSERT INTO `%s` (%s) VALUES (%s)'):format(tableName, table.concat(cols, ', '), table.concat(marks, ', ')), values = values }
end

-- Accepts an online server ID or a citizen ID (online or offline)
local function ResolveCharacter(arg)
    if not arg or arg == '' then return nil end
    local id = tonumber(arg)
    if id then
        local Player = QBCore.Functions.GetPlayer(id)
        if Player then return Player.PlayerData.citizenid, Player end
    end
    if arg:match('^[%w]+$') and #arg <= 50 then
        return arg, QBCore.Functions.GetPlayerByCitizenId(arg)
    end
    return nil
end

local DEFAULT_JOB = { name = 'unemployed', label = 'Civilian', payment = 10, onduty = true, isboss = false, grade = { name = 'Freelancer', level = 0 } }
local DEFAULT_GANG = { name = 'none', label = 'No Gang Affiliaton', isboss = false, grade = { name = 'none', level = 0 } }

-- ════════════════════════════════════════════════════════════
-- Copy
-- ════════════════════════════════════════════════════════════

local function CopyCharacter(src, sourceArg, ownerArg)
    local sourceCid, SourcePlayer = ResolveCharacter(sourceArg)
    if not sourceCid then
        return false, ('Usage: /%s [server ID or citizen ID] [optional: server ID who receives the copy]'):format(Config.Command)
    end

    -- Who receives the copy (account license)
    local ownerSrc = ownerArg and tonumber(ownerArg) or src
    local Owner = ownerSrc and ownerSrc > 0 and QBCore.Functions.GetPlayer(ownerSrc)
    if not Owner then
        return false, src == 0 and 'From the console, give the server ID of the player who receives the copy' or 'The player who should receive the copy is not online'
    end
    local license = Owner.PlayerData.license
    if not license then return false, 'Could not read the receiving account license' end

    -- Save the source first so the copy has its latest data
    if SourcePlayer then pcall(SourcePlayer.Functions.Save) end

    local row = MySQL.single.await(('SELECT * FROM `%s` WHERE citizenid = ? LIMIT 1'):format(T.players), { sourceCid })
    if not row then return false, 'No character with citizen ID ' .. sourceCid end

    local slot = FreeSlot(license)
    if not slot then return false, ('The account has no free character slot (max %d)'):format(Config.MaxSlots) end

    local newCid = NewCitizenId()
    if not newCid then return false, 'Could not generate a new citizen ID' end

    -- Character info
    local charinfo = Decode(row.charinfo)
    charinfo.cid = slot
    if Config.NameSuffix ~= '' and charinfo.firstname then charinfo.firstname = charinfo.firstname .. Config.NameSuffix end
    if Config.NewPhoneNumber then charinfo.phone = NewPhone() or charinfo.phone end
    if Config.NewBankAccount then charinfo.account = NewAccount() or charinfo.account end

    local metadata = Config.Copy.metadata and Decode(row.metadata) or {}
    if Config.NewFingerprint then
        metadata.fingerprint = RandomString(2, ALNUM) .. RandomString(3, DIGITS) .. RandomString(1, LETTERS) .. RandomString(2, ALNUM) .. RandomString(3, DIGITS) .. RandomString(4, ALNUM)
        metadata.walletid = 'QB-' .. RandomString(8, DIGITS)
    end

    local money = Decode(row.money)
    if not Config.Copy.money then
        for k in pairs(money) do money[k] = 0 end
        if not next(money) then money = { cash = 0, bank = 0, crypto = 0 } end
    end

    local copy = {}
    for k, v in pairs(row) do copy[k] = v end
    copy.citizenid = newCid
    copy.cid = slot
    copy.license = license
    copy.name = GetPlayerName(Owner.PlayerData.source) or row.name
    copy.charinfo = json.encode(charinfo)
    copy.money = json.encode(money)
    copy.metadata = json.encode(metadata)
    if not Config.Copy.job then copy.job = json.encode(DEFAULT_JOB) end
    if not Config.Copy.gang then copy.gang = json.encode(DEFAULT_GANG) end
    if not Config.Copy.inventory and copy.inventory ~= nil then copy.inventory = '[]' end
    if not Config.Copy.position and copy.position ~= nil then
        local spawn = QBCore.Config and QBCore.Config.DefaultSpawn
        copy.position = json.encode(spawn and { x = spawn.x, y = spawn.y, z = spawn.z, w = spawn.w or 0.0 } or { x = -1035.71, y = -2731.87, z = 12.86, w = 0.0 })
    end
    if copy.phone_number ~= nil and Config.NewPhoneNumber then copy.phone_number = charinfo.phone end

    local queries = { InsertQuery(T.players, copy, { id = true, last_updated = true }) }

    -- Appearance
    local skins = 0
    if Config.Copy.appearance and TableExists(T.skins) then
        for _, skin in ipairs(MySQL.query.await(('SELECT * FROM `%s` WHERE citizenid = ?'):format(T.skins), { sourceCid }) or {}) do
            skin.citizenid = newCid
            queries[#queries + 1] = InsertQuery(T.skins, skin, { id = true })
            skins = skins + 1
        end
    end

    -- Vehicles (new unique plates, parked)
    local vehicles = 0
    if Config.Copy.vehicles and TableExists(T.vehicles) then
        local usedPlates = {}
        for _, veh in ipairs(MySQL.query.await(('SELECT * FROM `%s` WHERE citizenid = ?'):format(T.vehicles), { sourceCid }) or {}) do
            local plate = NewPlate(usedPlates)
            if plate then
                veh.citizenid = newCid
                veh.license = license
                veh.plate = plate
                if veh.fakeplate ~= nil then veh.fakeplate = nil end
                if veh.state ~= nil then veh.state = 1 end
                if veh.mods then
                    local mods = Decode(veh.mods)
                    if next(mods) then mods.plate = plate veh.mods = json.encode(mods) end
                end
                queries[#queries + 1] = InsertQuery(T.vehicles, veh, { id = true })
                vehicles = vehicles + 1
            end
        end
    end

    local ok = MySQL.transaction.await(queries)
    if not ok then return false, 'Database error while saving the copy (nothing was saved)' end

    local name = ('%s %s'):format(charinfo.firstname or '?', charinfo.lastname or '?')
    print(('^2[NomadCopyChar]^7 %s copied %s (%s) -> %s, slot %d of %s | skins: %d | vehicles: %d'):format(
        src == 0 and 'console' or (GetPlayerName(src) or src), name, sourceCid, newCid, slot, license, skins, vehicles))
    return true, ('Copied %s (%s) to slot %d - new citizen ID: %s. Log out to the character menu to play it.'):format(name, sourceCid, slot, newCid)
end

RegisterCommand(Config.Command, function(src, args)
    if not IsAllowed(src) then
        return Notify(src, 'You do not have permission to use this command', 'error')
    end
    if busy then
        return Notify(src, 'A copy is already running, try again in a moment', 'error')
    end
    busy = true
    local ok, success, message = pcall(CopyCharacter, src, args[1], args[2])
    busy = false
    if not ok then
        print('^1[NomadCopyChar] error: ' .. tostring(success) .. '^7')
        return Notify(src, 'Unexpected error, see the server console', 'error')
    end
    Notify(src, message, success and 'success' or 'error')
end, false)
