-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- Undoing and deleting actions
-- Undo reuses the original action functions (same checks and permissions)
-- ════════════════════════════════════════════════════════════════════════════════════════════════

local Notify = JS.Notify

local function H(name)
    return JS.Handlers['NomadJustice:server:' .. name]
end

-- Return money to the citizen's bank (to undo a seizure)
local function Refund(citizenid, amount)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return { ok = false, err = 'Invalid amount' } end

    local target = QBCore.Functions.GetPlayerByCitizenId(citizenid)
    if target then
        if not target.Functions.AddMoney('bank', amount, 'justice-withdraw-refund') then
            return { ok = false, err = 'Could not return the amount' }
        end
        Notify(target.PlayerData.source, ('$%d was returned to your bank account by the Department of Justice'):format(amount), 'success', 8000)
        return { ok = true }
    end

    local row = JS.GetPlayerRow(citizenid)
    if not row then return { ok = false, err = 'Citizen not found' } end
    local money = JS.OfflineMoney(row)
    money.bank = (tonumber(money.bank) or 0) + amount
    if not JS.UpdatePlayerJson(citizenid, 'money', money, row.money) then
        return { ok = false, err = 'Citizen data changed, try again' }
    end
    return { ok = true }
end

-- Restore personal data exactly as it was (even if incomplete or not matching the current edit rules)
local EditKeys = { firstname = true, lastname = true, birthdate = true, gender = true, nationality = true }

local function RestoreCharinfo(citizenid, old)
    local citizen = JS.GetCitizen(citizenid)
    if not citizen then return { ok = false, err = 'Citizen not found' } end

    local charinfo = citizen.charinfo
    for key in pairs(EditKeys) do
        charinfo[key] = old[key] -- nil = it was empty to begin with
    end

    if citizen.online then
        citizen.online.Functions.SetPlayerData('charinfo', charinfo)
        if citizen.online.Functions.Save then pcall(citizen.online.Functions.Save) end
        Notify(citizen.online.PlayerData.source, 'Your personal details were restored by the Department of Justice', 'primary', 8000)
    elseif not JS.UpdatePlayerJson(citizenid, 'charinfo', charinfo, citizen.raw.charinfo) then
        return { ok = false, err = 'Citizen data changed, try again' }
    end
    return { ok = true }
end

-- For each action: the required permission + how to undo it
local UndoActions = {
    withdraw = { perm = 'withdraw', run = function(src, P, log, u)
        -- Takes the money back from where it went (the officer's account) first
        local ok, err = JS.ReverseDeposit(u.dest, u.amount)
        if not ok then return { ok = false, err = err } end
        return Refund(log.target_citizenid, u.amount)
    end },
    compensation = { perm = 'withdraw', run = function(src, P, log, u)
        JS.ClearCooldown('withdraw', P.PlayerData.citizenid)
        return H('withdrawBank')(src, P, log.target_citizenid, u.amount, ('Undo of compensation #%d'):format(log.id))
    end },
    suspend = { perm = 'suspend', run = function(src, P, log) return H('unsuspendCitizen')(src, P, log.target_citizenid) end },
    unsuspend = { perm = 'suspend', run = function(src, P, log, u) return H('suspendCitizen')(src, P, log.target_citizenid, u.reason or 'Re-suspension') end },
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
    verdict = { perm = 'verdicts', run = function(src, P, log, u) return JS.ReverseVerdict(src, P, u.id) end },
    suspect_add = { perm = 'suspects', run = function(src, P, log, u) return H('removeSuspect')(src, P, u.id) end },
    suspect_remove = { perm = 'suspects', run = function(src, P, log, u)
        if JS.GetSuspect(log.target_citizenid) then return { ok = false, err = 'The citizen is currently on the list' } end
        MySQL.update.await('UPDATE justice_suspects SET active = 1, removed_by = NULL WHERE id = ?', { u.id })
        return { ok = true }
    end },
    warrant_issue = { perm = 'warrants', run = function(src, P, log, u) return H('cancelWarrant')(src, P, u.id) end },
    warrant_cancel = { perm = 'warrants', run = function(src, P, log, u)
        local affected = MySQL.update.await("UPDATE justice_warrants SET status = 'active' WHERE id = ? AND status = 'cancelled' AND (expires_at IS NULL OR expires_at > NOW())", { u.id })
        if not affected or affected == 0 then return { ok = false, err = 'The warrant has expired, issue a new one' } end
        return { ok = true }
    end },
}

JS.UndoActions = UndoActions

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- Undo
-- ════════════════════════════════════════════════════════════════════════════════════════════════

JS.RegisterCallback('NomadJustice:server:undoLog', 'undo', function(src, Player, logId)
    logId = tonumber(logId)
    if not logId then return { ok = false, err = 'Invalid log entry' } end

    local log = MySQL.single.await('SELECT * FROM justice_logs WHERE id = ?', { logId })
    if not log then return { ok = false, err = 'Log entry not found' } end
    if log.undone_by then return { ok = false, err = ('Already undone by %s'):format(log.undone_by) } end

    local handler = UndoActions[log.action]
    if not handler or not log.undo_data then return { ok = false, err = 'This action cannot be undone' } end

    local allowed, err = JS.Can(Player, handler.perm)
    if not allowed then return { ok = false, err = err } end

    -- Claim the entry first (stops two employees undoing the same action at the same time)
    local officerName = JS.PlayerName(Player)
    local claimed = MySQL.update.await('UPDATE justice_logs SET undone_by = ?, undone_at = NOW() WHERE id = ? AND undone_by IS NULL', { officerName, logId })
    if not claimed or claimed == 0 then return { ok = false, err = 'Already undone' } end

    local ok, result = pcall(handler.run, src, Player, log, JS.Decode(log.undo_data))
    if not ok or type(result) ~= 'table' or not result.ok then
        MySQL.update.await('UPDATE justice_logs SET undone_by = NULL, undone_at = NULL WHERE id = ?', { logId })
        if not ok then print(('^1[NomadJustice] undo #%d error: %s^7'):format(logId, tostring(result))) end
        return { ok = false, err = (ok and type(result) == 'table' and result.err) or 'Could not undo the action' }
    end

    JS.Log(Player, 'undo', log.target_citizenid, log.target_name, {
        ['Entry'] = logId,
        ['Action'] = JS.ActionLabels[log.action] or log.action,
        ['Original officer'] = log.officer_name,
    })
    return { ok = true, message = ('Undone: %s'):format(JS.ActionLabels[log.action] or log.action) }
end)

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- Delete (a trace stays in the log: who deleted what)
-- ════════════════════════════════════════════════════════════════════════════════════════════════

JS.RegisterCallback('NomadJustice:server:deleteLog', 'delete', function(src, Player, logId)
    logId = tonumber(logId)
    local log = logId and MySQL.single.await('SELECT * FROM justice_logs WHERE id = ?', { logId })
    if not log then return { ok = false, err = 'Log entry not found' } end

    local affected = MySQL.update.await('DELETE FROM justice_logs WHERE id = ?', { logId })
    if not affected or affected == 0 then return { ok = false, err = 'Log entry not found' } end

    JS.Log(Player, 'log_delete', log.target_citizenid, log.target_name, {
        ['Entry'] = logId,
        ['Action'] = JS.ActionLabels[log.action] or log.action,
        ['Original officer'] = log.officer_name,
        ['Original date'] = JS.FormatDbDate(log.created_at),
    })
    return { ok = true }
end)

JS.RegisterCallback('NomadJustice:server:deleteSummon', 'delete', function(src, Player, summonId)
    summonId = tonumber(summonId)
    local row = summonId and MySQL.single.await('SELECT * FROM justice_summons WHERE id = ?', { summonId })
    if not row then return { ok = false, err = 'Summons not found' } end

    -- Cancel first so it is removed from the in-memory queue
    if row.status == 'pending' or row.status == 'delivered' then
        H('setSummonStatus')(src, Player, summonId, 'cancelled')
    end
    MySQL.update.await('DELETE FROM justice_summons WHERE id = ?', { summonId })

    JS.Log(Player, 'summon_delete', row.citizenid, row.name, { ['Summons'] = summonId, ['Reason'] = row.reason })
    return { ok = true }
end)
