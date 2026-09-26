-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- التراجع عن الإجراءات وحذفها
-- التراجع يستخدم نفس دوال الإجراءات الأصلية (نفس التحققات والصلاحيات)
-- ════════════════════════════════════════════════════════════════════════════════════════════════

local Notify = JS.Notify

local function H(name)
    return JS.Handlers['RespectJustice:server:' .. name]
end

-- إرجاع مبلغ لبنك المواطن (للتراجع عن السحب)
local function Refund(citizenid, amount)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return { ok = false, err = 'مبلغ غير صحيح' } end

    local target = RTCore.Functions.GetPlayerByCitizenId(citizenid)
    if target then
        if not target.Functions.AddMoney('bank', amount, 'justice-withdraw-refund') then
            return { ok = false, err = 'تعذر إرجاع المبلغ' }
        end
        Notify(target.PlayerData.source, ('تم إرجاع $%d إلى حسابك البنكي من وزارة العدل'):format(amount), 'success', 8000)
        return { ok = true }
    end

    local row = JS.GetPlayerRow(citizenid)
    if not row then return { ok = false, err = 'المواطن غير موجود' } end
    local money = JS.Decode(row.money)
    money.bank = (tonumber(money.bank) or 0) + amount
    if not JS.UpdatePlayerJson(citizenid, 'money', money, row.money) then
        return { ok = false, err = 'تغيرت بيانات المواطن، حاول مرة أخرى' }
    end
    return { ok = true }
end

-- إرجاع البيانات الشخصية كما كانت بالضبط (حتى لو كانت ناقصة أو ما تطابق شروط التعديل الحالية)
local EditKeys = { firstname = true, lastname = true, birthdate = true, gender = true, nationality = true }

local function RestoreCharinfo(citizenid, old)
    local citizen = JS.GetCitizen(citizenid)
    if not citizen then return { ok = false, err = 'المواطن غير موجود' } end

    local charinfo = citizen.charinfo
    for key in pairs(EditKeys) do
        charinfo[key] = old[key] -- nil = كان فاضي أصلاً
    end

    if citizen.online then
        citizen.online.Functions.SetPlayerData('charinfo', charinfo)
        if citizen.online.Functions.Save then pcall(citizen.online.Functions.Save) end
        Notify(citizen.online.PlayerData.source, 'تم إرجاع بياناتك الشخصية من وزارة العدل', 'primary', 8000)
    elseif not JS.UpdatePlayerJson(citizenid, 'charinfo', charinfo, citizen.raw.charinfo) then
        return { ok = false, err = 'تغيرت بيانات المواطن، حاول مرة أخرى' }
    end
    return { ok = true }
end

-- لكل إجراء: الصلاحية المطلوبة + طريقة التراجع
local UndoActions = {
    withdraw = { perm = 'withdraw', run = function(src, P, log, u) return Refund(log.target_citizenid, u.amount) end },
    compensation = { perm = 'withdraw', run = function(src, P, log, u)
        JS.ClearCooldown('withdraw', P.PlayerData.citizenid)
        return H('withdrawBank')(src, P, log.target_citizenid, u.amount, ('تراجع عن تعويض #%d'):format(log.id))
    end },
    suspend = { perm = 'suspend', run = function(src, P, log) return H('unsuspendCitizen')(src, P, log.target_citizenid) end },
    unsuspend = { perm = 'suspend', run = function(src, P, log, u) return H('suspendCitizen')(src, P, log.target_citizenid, u.reason or 'إعادة إيقاف') end },
    edit = { perm = 'edit', run = function(src, P, log, u) return RestoreCharinfo(log.target_citizenid, u.old or {}) end },
    job = { perm = 'jobs', run = function(src, P, log, u)
        JS.ClearCooldown('jobs', P.PlayerData.citizenid .. ':' .. log.target_citizenid)
        return H('setCitizenJob')(src, P, log.target_citizenid, u.job, u.level)
    end },
    duty = { perm = 'jobs', run = function(src, P, log, u) return H('setCitizenDuty')(src, P, log.target_citizenid, u.state == true) end },
    vehicle_impound = { perm = 'vehicles', run = function(src, P, log, u) return H('vehicleAction')(src, P, u.plate, 'release') end },
    vehicle_release = { perm = 'vehicles', run = function(src, P, log, u) return H('vehicleAction')(src, P, u.plate, 'impound') end },
    vehicle_transfer = { perm = 'vehicles', run = function(src, P, log, u) return H('vehicleAction')(src, P, u.plate, 'transfer', u.from) end },
    property_transfer = { perm = 'properties', run = function(src, P, log, u) return H('transferProperty')(src, P, u.id, u.from) end },
    license_grant = { perm = 'licenses', run = function(src, P, log, u) return H('setLicense')(src, P, log.target_citizenid, u.key, u.state == true) end },
    license_revoke = { perm = 'licenses', run = function(src, P, log, u) return H('setLicense')(src, P, log.target_citizenid, u.key, u.state == true) end },
    gang = { perm = 'gangs', run = function(src, P, log, u) return H('setGang')(src, P, log.target_citizenid, u.gang, u.level) end },
    summon = { perm = 'summon', run = function(src, P, log, u) return H('setSummonStatus')(src, P, u.id, 'cancelled') end },
    report_status = { perm = 'reports', run = function(src, P, log, u) return H('setReportStatus')(src, P, u.id, u.status) end },
}

JS.UndoActions = UndoActions

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- التراجع
-- ════════════════════════════════════════════════════════════════════════════════════════════════

JS.RegisterCallback('RespectJustice:server:undoLog', 'undo', function(src, Player, logId)
    logId = tonumber(logId)
    if not logId then return { ok = false, err = 'رقم السجل غير صحيح' } end

    local log = MySQL.single.await('SELECT * FROM justice_logs WHERE id = ?', { logId })
    if not log then return { ok = false, err = 'السجل غير موجود' } end
    if log.undone_by then return { ok = false, err = ('تم التراجع عنه مسبقاً بواسطة %s'):format(log.undone_by) } end

    local handler = UndoActions[log.action]
    if not handler or not log.undo_data then return { ok = false, err = 'هذا الإجراء لا يمكن التراجع عنه' } end

    local allowed, err = JS.Can(Player, handler.perm)
    if not allowed then return { ok = false, err = err } end

    -- حجز السجل أولاً (يمنع موظفين يتراجعون عن نفس الإجراء بنفس اللحظة)
    local officerName = JS.PlayerName(Player)
    local claimed = MySQL.update.await('UPDATE justice_logs SET undone_by = ?, undone_at = NOW() WHERE id = ? AND undone_by IS NULL', { officerName, logId })
    if not claimed or claimed == 0 then return { ok = false, err = 'تم التراجع عنه مسبقاً' } end

    local ok, result = pcall(handler.run, src, Player, log, JS.Decode(log.undo_data))
    if not ok or type(result) ~= 'table' or not result.ok then
        MySQL.update.await('UPDATE justice_logs SET undone_by = NULL, undone_at = NULL WHERE id = ?', { logId })
        if not ok then print(('^1[RespectJustice] undo #%d error: %s^7'):format(logId, tostring(result))) end
        return { ok = false, err = (ok and type(result) == 'table' and result.err) or 'تعذر التراجع عن الإجراء' }
    end

    JS.Log(Player, 'undo', log.target_citizenid, log.target_name, {
        ['السجل'] = logId,
        ['الإجراء'] = JS.ActionLabels[log.action] or log.action,
        ['الموظف الأصلي'] = log.officer_name,
    })
    return { ok = true, message = ('تم التراجع عن: %s'):format(JS.ActionLabels[log.action] or log.action) }
end)

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- الحذف (يبقى أثر في السجل: من حذف وإيش حذف)
-- ════════════════════════════════════════════════════════════════════════════════════════════════

JS.RegisterCallback('RespectJustice:server:deleteLog', 'delete', function(src, Player, logId)
    logId = tonumber(logId)
    local log = logId and MySQL.single.await('SELECT * FROM justice_logs WHERE id = ?', { logId })
    if not log then return { ok = false, err = 'السجل غير موجود' } end

    local affected = MySQL.update.await('DELETE FROM justice_logs WHERE id = ?', { logId })
    if not affected or affected == 0 then return { ok = false, err = 'السجل غير موجود' } end

    JS.Log(Player, 'log_delete', log.target_citizenid, log.target_name, {
        ['السجل'] = logId,
        ['الإجراء'] = JS.ActionLabels[log.action] or log.action,
        ['الموظف الأصلي'] = log.officer_name,
        ['تاريخه'] = JS.FormatDbDate(log.created_at),
    })
    return { ok = true }
end)

JS.RegisterCallback('RespectJustice:server:deleteSummon', 'delete', function(src, Player, summonId)
    summonId = tonumber(summonId)
    local row = summonId and MySQL.single.await('SELECT * FROM justice_summons WHERE id = ?', { summonId })
    if not row then return { ok = false, err = 'الاستدعاء غير موجود' } end

    -- إلغاء أولاً عشان ينشال من قائمة الانتظار في الذاكرة
    if row.status == 'pending' or row.status == 'delivered' then
        H('setSummonStatus')(src, Player, summonId, 'cancelled')
    end
    MySQL.update.await('DELETE FROM justice_summons WHERE id = ?', { summonId })

    JS.Log(Player, 'summon_delete', row.citizenid, row.name, { ['الاستدعاء'] = summonId, ['السبب'] = row.reason })
    return { ok = true }
end)
