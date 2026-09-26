local Settings = JS.Settings
local Panel = Settings.Panel
local Notify = JS.Notify

local VehicleStates = { [0] = 'خارج الكراج', [1] = 'في الكراج', [2] = 'في الحجز' }

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- أدوات بناء ملف المواطن
-- ════════════════════════════════════════════════════════════════════════════════════════════════

local function GradeName(grade)
    if type(grade) == 'table' then return grade.name or grade.label or tostring(grade.level or '') end
    return grade and tostring(grade) or nil
end

local function GetVehicles(citizenid)
    local tableName = Settings.Database.Vehicles
    if not tableName or not JS.TableExists(tableName) then return nil end

    local rows = MySQL.query.await(('SELECT * FROM `%s` WHERE citizenid = ?'):format(tableName), { citizenid }) or {}
    local vehicles = {}
    for i, row in ipairs(rows) do
        local shared = RTCore.Shared.Vehicles and RTCore.Shared.Vehicles[row.vehicle]
        local label = shared and (('%s %s'):format(shared.brand or '', shared.name or row.vehicle):gsub('^%s+', '')) or row.vehicle
        vehicles[i] = {
            label = label or 'غير معروف',
            model = row.vehicle,
            plate = row.plate,
            garage = row.garage,
            state = VehicleStates[tonumber(row.state)] or tostring(row.state or '-'),
            fuel = tonumber(row.fuel) and math.floor(tonumber(row.fuel)) or nil,
            engine = tonumber(row.engine) and math.floor(tonumber(row.engine) / 10) or nil,
            body = tonumber(row.body) and math.floor(tonumber(row.body) / 10) or nil,
        }
    end
    return vehicles
end

local function GetHouses(citizenid)
    local houses = Settings.Database.Houses
    if not houses or not JS.TableExists(houses.table) or not JS.ColumnExists(houses.table, houses.owner) then
        return nil
    end

    local rows = MySQL.query.await(('SELECT * FROM `%s` WHERE `%s` = ?'):format(houses.table, houses.owner), { citizenid }) or {}
    local list = {}
    for i, row in ipairs(rows) do
        list[i] = { label = tostring(row[houses.label] or row.id or ('عقار #' .. i)) }
    end
    return list
end

local function GetItems(items)
    local shared = RTCore.Shared.Items or {}
    local grouped, order = {}, {}
    for _, item in pairs(items or {}) do
        if type(item) == 'table' and item.name then
            local amount = tonumber(item.amount or item.count) or 1
            if not grouped[item.name] then
                grouped[item.name] = 0
                order[#order + 1] = item.name
            end
            grouped[item.name] = grouped[item.name] + amount
        end
    end

    local list = {}
    for i, name in ipairs(order) do
        list[i] = { label = shared[name] and shared[name].label or name, amount = grouped[name] }
    end
    table.sort(list, function(a, b) return a.label < b.label end)
    return list
end

local function GetLicenses(metadata)
    local list = {}
    for key, value in pairs(metadata.licences or metadata.licenses or {}) do
        list[#list + 1] = { label = Settings.Licenses[key] or key, active = value == true }
    end
    table.sort(list, function(a, b) return a.label < b.label end)
    return list
end

local function BuildProfile(citizen, Viewer)
    local ci, job, gang, md, money = citizen.charinfo, citizen.job, citizen.gang, citizen.metadata, citizen.money
    local cid = citizen.citizenid

    local transactions = {}
    for i, row in ipairs(MySQL.query.await('SELECT * FROM justice_transactions WHERE target_citizenid = ? ORDER BY id DESC LIMIT 15', { cid }) or {}) do
        transactions[i] = {
            type = row.type,
            amount = row.amount,
            reason = row.reason,
            officer = row.officer_name,
            date = row.date,
        }
    end

    local reports = {}
    for i, row in ipairs(MySQL.query.await(
        'SELECT id, title, case_type, status, date, citizenid FROM justice_reports WHERE job = ? AND (citizenid = ? OR defendant_citizenid = ?) ORDER BY id DESC LIMIT 25',
        { JS.Job, cid, cid }) or {}) do
        reports[i] = {
            id = row.id,
            title = row.title ~= '' and row.title or ('قضية #' .. row.id),
            caseType = row.case_type,
            status = JS.StatusLabels[row.status] or row.status,
            date = row.date,
            role = row.citizenid == cid and 'مدعي' or 'مدعى عليه',
        }
    end

    local record = md.criminalrecord or {}
    local profile = {
        citizenid = cid,
        name = JS.FullName(ci),
        online = citizen.online ~= nil,
        serverId = citizen.online and citizen.online.PlayerData.source or nil,
        ping = citizen.online and GetPlayerPing(citizen.online.PlayerData.source) or nil,
        lastUpdated = citizen.lastUpdated,

        firstname = ci.firstname,
        lastname = ci.lastname,
        birthdate = ci.birthdate,
        gender = tonumber(ci.gender),
        nationality = ci.nationality,
        phone = ci.phone,
        account = ci.account,

        job = {
            name = job.name,
            label = job.label or job.name or 'عاطل',
            grade = GradeName(job.grade),
            onduty = job.onduty == true,
            isboss = job.isboss == true,
        },
        gang = (gang.name and gang.name ~= 'none') and { label = gang.label or gang.name, grade = GradeName(gang.grade) } or nil,

        money = {
            cash = math.floor(tonumber(money.cash) or 0),
            bank = math.floor(tonumber(money.bank) or 0),
            crypto = tonumber(money.crypto),
        },

        info = {
            bloodtype = md.bloodtype,
            fingerprint = md.fingerprint,
            walletid = md.walletid,
            callsign = md.callsign,
            injail = tonumber(md.injail) or 0,
            isdead = md.isdead == true,
            criminalRecord = record.hasRecord == true,
            criminalRecordDate = record.date and tostring(record.date) or nil,
        },

        licenses = GetLicenses(md),
        vehicles = GetVehicles(cid),
        houses = GetHouses(cid),
        items = GetItems(citizen.items),
        transactions = transactions,
        reports = reports,
        suspension = JS.Suspended[cid],
        isSelf = Viewer.PlayerData.citizenid == cid,
    }

    return profile
end

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- الصفحة الرئيسية
-- ════════════════════════════════════════════════════════════════════════════════════════════════

JS.RegisterCallback('RespectJustice:server:panelInfo', 'view', function(src, Player)
    local newReports = MySQL.scalar.await("SELECT COUNT(*) FROM justice_reports WHERE job = ? AND status = 'new'", { JS.Job }) or 0
    local suspended = 0
    for _ in pairs(JS.Suspended) do suspended = suspended + 1 end

    return {
        ok = true,
        perms = JS.GetPermissions(Player),
        online = #RTCore.Functions.GetPlayers(),
        newReports = newReports,
        suspended = suspended,
    }
end)

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- اللاعبين المتصلين
-- ════════════════════════════════════════════════════════════════════════════════════════════════

JS.RegisterCallback('RespectJustice:server:getOnlinePlayers', 'view', function()
    local list = {}
    for _, playerId in pairs(RTCore.Functions.GetPlayers()) do
        local target = RTCore.Functions.GetPlayer(playerId)
        if target then
            local pd = target.PlayerData
            list[#list + 1] = {
                serverId = pd.source,
                citizenid = pd.citizenid,
                name = JS.FullName(pd.charinfo),
                job = pd.job and (pd.job.label or pd.job.name) or '-',
                phone = pd.charinfo and pd.charinfo.phone or '-',
                suspended = JS.Suspended[pd.citizenid] ~= nil,
            }
        end
    end
    table.sort(list, function(a, b) return a.serverId < b.serverId end)
    return { ok = true, players = list }
end)

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- البحث (متصل وغير متصل): بالاسم أو الرقم الوطني أو رقم الجوال أو رقم السيرفر
-- ════════════════════════════════════════════════════════════════════════════════════════════════

JS.RegisterCallback('RespectJustice:server:searchCitizens', 'view', function(src, Player, query)
    query = JS.CleanText(query, 40, true)
    if not query or JS.Len(query) < 2 then
        return { ok = false, err = 'اكتب حرفين على الأقل للبحث' }
    end

    local results, seen = {}, {}
    local function add(cid, charinfo, job, online)
        if seen[cid] then return end
        seen[cid] = true
        results[#results + 1] = {
            citizenid = cid,
            name = JS.FullName(charinfo),
            job = job and (job.label or job.name) or '-',
            phone = charinfo and charinfo.phone or '-',
            online = online,
            suspended = JS.Suspended[cid] ~= nil,
        }
    end

    -- البحث برقم السيرفر
    local serverId = tonumber(query)
    if serverId then
        local target = RTCore.Functions.GetPlayer(serverId)
        if target then add(target.PlayerData.citizenid, target.PlayerData.charinfo, target.PlayerData.job, true) end
    end

    -- المتصلين
    local lower = query:lower()
    for _, playerId in pairs(RTCore.Functions.GetPlayers()) do
        local target = RTCore.Functions.GetPlayer(playerId)
        if target then
            local pd = target.PlayerData
            local charinfo = pd.charinfo or {}
            local name = JS.FullName(charinfo):lower()
            if pd.citizenid == query or tostring(charinfo.phone) == query or name:find(lower, 1, true) then
                add(pd.citizenid, pd.charinfo, pd.job, true)
            end
        end
    end

    -- قاعدة البيانات
    local tableName = Settings.Database.Players
    if JS.TableExists(tableName) then
        local like = '%' .. query:gsub('[%%_\\]', '\\%0') .. '%'
        local rows = MySQL.query.await(([[
            SELECT citizenid, charinfo, job FROM `%s`
            WHERE citizenid = ?
               OR JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.phone')) = ?
               OR CONCAT(JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.firstname')), ' ', JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.lastname'))) LIKE ?
            LIMIT 30
        ]]):format(tableName), { query, query, like }) or {}

        for _, row in ipairs(rows) do
            add(row.citizenid, JS.Decode(row.charinfo), JS.Decode(row.job), RTCore.Functions.GetPlayerByCitizenId(row.citizenid) ~= nil)
        end
    end

    return { ok = true, results = results }
end)

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- ملف المواطن
-- ════════════════════════════════════════════════════════════════════════════════════════════════

JS.RegisterCallback('RespectJustice:server:getProfile', 'view', function(src, Player, citizenid)
    citizenid = JS.ValidCitizenId(citizenid)
    if not citizenid then return { ok = false, err = 'الرقم الوطني غير صحيح' } end

    local citizen = JS.GetCitizen(citizenid)
    if not citizen then return { ok = false, err = 'لا يوجد مواطن بهذا الرقم الوطني' } end

    local profile = BuildProfile(citizen, Player)
    if Panel.LogViews and not JS.OnCooldown('view', Player.PlayerData.citizenid .. ':' .. citizenid, 300) then
        JS.Log(Player, 'view', citizenid, profile.name)
    end

    return { ok = true, profile = profile, perms = JS.GetPermissions(Player) }
end)

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- تحديد الموقع
-- ════════════════════════════════════════════════════════════════════════════════════════════════

JS.RegisterCallback('RespectJustice:server:locateCitizen', 'locate', function(src, Player, citizenid)
    citizenid = JS.ValidCitizenId(citizenid)
    local target = citizenid and RTCore.Functions.GetPlayerByCitizenId(citizenid)
    if not target then return { ok = false, err = 'المواطن غير متصل حالياً' } end

    local ped = GetPlayerPed(target.PlayerData.source)
    if ped == 0 then return { ok = false, err = 'تعذر تحديد الموقع' } end

    local coords = GetEntityCoords(ped)
    local name = JS.PlayerName(target)
    JS.Log(Player, 'locate', citizenid, name, { ['الإحداثيات'] = ('%.1f, %.1f, %.1f'):format(coords.x, coords.y, coords.z) })

    return { ok = true, coords = { x = coords.x, y = coords.y, z = coords.z }, name = name, inVehicle = GetVehiclePedIsIn(ped, false) ~= 0 }
end)

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- سحب أموال من البنك
-- ════════════════════════════════════════════════════════════════════════════════════════════════

JS.RegisterCallback('RespectJustice:server:withdrawBank', 'withdraw', function(src, Player, citizenid, amount, reason)
    citizenid = JS.ValidCitizenId(citizenid)
    amount = math.floor(tonumber(amount) or 0)
    reason = JS.CleanText(reason, 200, true)

    if not citizenid then return { ok = false, err = 'الرقم الوطني غير صحيح' } end
    if amount <= 0 then return { ok = false, err = 'المبلغ غير صحيح' } end
    if amount > Panel.WithdrawMax then return { ok = false, err = ('الحد الأقصى للسحب $%d'):format(Panel.WithdrawMax) } end
    if not reason then return { ok = false, err = 'سبب السحب مطلوب (200 حرف كحد أقصى)' } end
    if citizenid == Player.PlayerData.citizenid then return { ok = false, err = 'لا يمكنك تنفيذ هذا الإجراء على نفسك' } end

    local officerCid = Player.PlayerData.citizenid
    local blocked, remaining = JS.OnCooldown('withdraw', officerCid, Panel.WithdrawCooldown)
    if blocked then return { ok = false, err = ('يجب أن تنتظر %d ثانية'):format(remaining) } end

    -- أي فشل بعد هذه النقطة يلغي فترة الانتظار
    local function fail(err)
        JS.ClearCooldown('withdraw', officerCid)
        return { ok = false, err = err }
    end

    local targetName, newBalance
    local target = RTCore.Functions.GetPlayerByCitizenId(citizenid)

    if target then
        local bank = tonumber(target.PlayerData.money.bank) or 0
        if bank < amount then
            return fail(('رصيد البنك غير كافٍ (الرصيد: $%d)'):format(math.floor(bank)))
        end
        if not target.Functions.RemoveMoney('bank', amount, 'justice-withdraw') then
            return fail('تعذر سحب المبلغ')
        end
        targetName = JS.PlayerName(target)
        newBalance = math.floor(tonumber(target.PlayerData.money.bank) or 0)
        Notify(target.PlayerData.source, ('تم سحب $%d من حسابك البنكي بقرار من وزارة العدل. السبب: %s'):format(amount, reason), 'error', 10000)
    else
        -- غير متصل: تحديث آمن (يفشل إذا تغير الرصيد أثناء العملية)
        local tableName = Settings.Database.Players
        local row = JS.GetPlayerRow(citizenid)
        if not row then return fail('لا يوجد مواطن بهذا الرقم الوطني') end

        local money = JS.Decode(row.money)
        local bank = tonumber(money.bank) or 0
        if bank < amount then
            return fail(('رصيد البنك غير كافٍ (الرصيد: $%d)'):format(math.floor(bank)))
        end
        money.bank = bank - amount

        local affected = MySQL.update.await(('UPDATE `%s` SET money = ? WHERE citizenid = ? AND money = ?'):format(tableName), {
            json.encode(money), citizenid, row.money
        })
        if not affected or affected == 0 then
            return fail('تغيرت بيانات المواطن أثناء العملية، حاول مرة أخرى')
        end
        targetName = JS.FullName(JS.Decode(row.charinfo))
        newBalance = math.floor(money.bank)
    end

    JS.AddSocietyMoney(amount, 'justice-withdraw')

    MySQL.insert('INSERT INTO justice_transactions (officer_citizenid, officer_name, target_citizenid, target_name, amount, reason, date, type) VALUES (?, ?, ?, ?, ?, ?, ?, ?)', {
        Player.PlayerData.citizenid, JS.PlayerName(Player), citizenid, targetName, amount, reason, JS.Now(), 'withdraw'
    })
    JS.Log(Player, 'withdraw', citizenid, targetName, { ['المبلغ'] = amount, ['السبب'] = reason, ['الرصيد الجديد'] = newBalance })

    return { ok = true, newBalance = newBalance, name = targetName }
end)

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- إيقاف / رفع إيقاف الخدمات
-- ════════════════════════════════════════════════════════════════════════════════════════════════

JS.RegisterCallback('RespectJustice:server:suspendCitizen', 'suspend', function(src, Player, citizenid, reason)
    citizenid = JS.ValidCitizenId(citizenid)
    reason = JS.CleanText(reason, 200, true)
    if not citizenid then return { ok = false, err = 'الرقم الوطني غير صحيح' } end
    if not reason then return { ok = false, err = 'سبب الإيقاف مطلوب (200 حرف كحد أقصى)' } end
    if citizenid == Player.PlayerData.citizenid then return { ok = false, err = 'لا يمكنك تنفيذ هذا الإجراء على نفسك' } end
    if JS.Suspended[citizenid] then return { ok = false, err = 'خدمات هذا المواطن موقوفة مسبقاً' } end

    local citizen = JS.GetCitizen(citizenid)
    if not citizen then return { ok = false, err = 'لا يوجد مواطن بهذا الرقم الوطني' } end

    local name = JS.FullName(citizen.charinfo)
    local officerName = JS.PlayerName(Player)
    local id = MySQL.insert.await('INSERT INTO justice_suspensions (citizenid, name, reason, officer_citizenid, officer_name) VALUES (?, ?, ?, ?, ?)', {
        citizenid, name, reason, Player.PlayerData.citizenid, officerName
    })
    if not id then return { ok = false, err = 'تعذر حفظ الإيقاف' } end

    JS.Suspended[citizenid] = { id = id, name = name, reason = reason, officer = officerName, date = JS.Now() }

    if citizen.online then
        pcall(citizen.online.Functions.SetMetaData, 'justice_suspended', true)
        Notify(citizen.online.PlayerData.source, ('تم إيقاف خدماتك بقرار من وزارة العدل. السبب: %s'):format(reason), 'error', 10000)
    end

    TriggerEvent('RespectJustice:server:suspensionChanged', citizenid, true, reason)
    JS.Log(Player, 'suspend', citizenid, name, { ['السبب'] = reason })

    return { ok = true }
end)

JS.RegisterCallback('RespectJustice:server:unsuspendCitizen', 'suspend', function(src, Player, citizenid)
    citizenid = JS.ValidCitizenId(citizenid)
    local suspension = citizenid and JS.Suspended[citizenid]
    if not suspension then return { ok = false, err = 'خدمات هذا المواطن غير موقوفة' } end

    MySQL.update.await('UPDATE justice_suspensions SET active = 0, lifted_by = ?, lifted_at = NOW() WHERE citizenid = ? AND active = 1', {
        JS.PlayerName(Player), citizenid
    })
    JS.Suspended[citizenid] = nil

    local target = RTCore.Functions.GetPlayerByCitizenId(citizenid)
    if target then
        pcall(target.Functions.SetMetaData, 'justice_suspended', false)
        Notify(target.PlayerData.source, 'تم رفع إيقاف خدماتك من وزارة العدل', 'success', 8000)
    end

    TriggerEvent('RespectJustice:server:suspensionChanged', citizenid, false)
    JS.Log(Player, 'unsuspend', citizenid, suspension.name)

    return { ok = true }
end)

JS.RegisterCallback('RespectJustice:server:getSuspended', 'view', function()
    local list = {}
    for cid, data in pairs(JS.Suspended) do
        list[#list + 1] = { citizenid = cid, name = data.name, reason = data.reason, officer = data.officer, date = data.date, id = data.id }
    end
    table.sort(list, function(a, b) return (a.id or 0) > (b.id or 0) end)
    return { ok = true, list = list }
end)

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- تعديل بيانات المواطن
-- data = { firstname, lastname, birthdate, gender, nationality }
-- ════════════════════════════════════════════════════════════════════════════════════════════════

local EditLabels = {
    firstname = 'الاسم الأول',
    lastname = 'اسم العائلة',
    birthdate = 'تاريخ الميلاد',
    gender = 'الجنس',
    nationality = 'الجنسية',
}

local function ValidName(value)
    value = JS.CleanText(value, 20, true)
    if not value or JS.Len(value) < 2 or value:find('[%d%c"\\{}%[%]]') then return nil end
    return value
end

local function ValidBirthdate(value)
    value = JS.CleanText(value, 10, true)
    if not value then return nil end
    local y, m, d = value:match('^(%d%d%d%d)%-(%d%d)%-(%d%d)$')
    y, m, d = tonumber(y), tonumber(m), tonumber(d)
    if not y or y < 1900 or y > 2025 or m < 1 or m > 12 or d < 1 or d > 31 then return nil end
    return value
end

JS.RegisterCallback('RespectJustice:server:editCitizen', 'edit', function(src, Player, citizenid, data)
    citizenid = JS.ValidCitizenId(citizenid)
    if not citizenid or type(data) ~= 'table' then return { ok = false, err = 'بيانات غير صحيحة' } end
    if citizenid == Player.PlayerData.citizenid then return { ok = false, err = 'لا يمكنك تعديل بياناتك بنفسك' } end

    local new = {
        firstname = ValidName(data.firstname),
        lastname = ValidName(data.lastname),
        birthdate = ValidBirthdate(data.birthdate),
        gender = (tonumber(data.gender) == 0 or tonumber(data.gender) == 1) and tonumber(data.gender) or nil,
        nationality = JS.CleanText(data.nationality, 30, true),
    }
    for key, label in pairs(EditLabels) do
        if new[key] == nil then
            return { ok = false, err = ('قيمة %s غير صحيحة'):format(label) }
        end
    end

    local citizen = JS.GetCitizen(citizenid)
    if not citizen then return { ok = false, err = 'لا يوجد مواطن بهذا الرقم الوطني' } end

    local charinfo = citizen.charinfo
    local changes = {}
    for key, label in pairs(EditLabels) do
        if tostring(charinfo[key]) ~= tostring(new[key]) then
            changes[label] = ('%s ← %s'):format(tostring(new[key]), tostring(charinfo[key] or '-'))
            charinfo[key] = new[key]
        end
    end
    if not next(changes) then return { ok = false, err = 'لم يتم تغيير أي بيانات' } end

    if citizen.online then
        citizen.online.Functions.SetPlayerData('charinfo', charinfo)
        if citizen.online.Functions.Save then pcall(citizen.online.Functions.Save) end
        Notify(citizen.online.PlayerData.source, 'تم تحديث بياناتك الشخصية من وزارة العدل', 'primary', 8000)
    else
        local affected = MySQL.update.await(('UPDATE `%s` SET charinfo = ? WHERE citizenid = ? AND charinfo = ?'):format(Settings.Database.Players), {
            json.encode(charinfo), citizenid, citizen.raw.charinfo
        })
        if not affected or affected == 0 then
            return { ok = false, err = 'تغيرت بيانات المواطن أثناء العملية، حاول مرة أخرى' }
        end
    end

    JS.Log(Player, 'edit', citizenid, JS.FullName(charinfo), changes)
    return { ok = true }
end)

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- سجل العمليات
-- ════════════════════════════════════════════════════════════════════════════════════════════════

JS.RegisterCallback('RespectJustice:server:getLogs', 'logs', function(src, Player, citizenid)
    local rows
    citizenid = citizenid and JS.ValidCitizenId(citizenid)
    if citizenid then
        rows = MySQL.query.await('SELECT * FROM justice_logs WHERE target_citizenid = ? OR officer_citizenid = ? ORDER BY id DESC LIMIT 100', { citizenid, citizenid })
    else
        rows = MySQL.query.await('SELECT * FROM justice_logs ORDER BY id DESC LIMIT 100')
    end

    local logs = {}
    for i, row in ipairs(rows or {}) do
        local details = JS.Decode(row.details)
        local parts = {}
        for key, value in pairs(details) do
            parts[#parts + 1] = ('%s: %s'):format(key, tostring(value))
        end
        logs[i] = {
            action = JS.ActionLabels[row.action] or row.action,
            officer = row.officer_name,
            target = row.target_name and ('%s (%s)'):format(row.target_name, row.target_citizenid) or nil,
            details = #parts > 0 and table.concat(parts, ' | ') or nil,
            date = JS.FormatDbDate(row.created_at),
        }
    end

    return { ok = true, logs = logs }
end)
