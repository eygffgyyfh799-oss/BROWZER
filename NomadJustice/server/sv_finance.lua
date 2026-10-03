-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- 💰 Department finance office (police, medical...) in the state system
-- Only the managers listed in Settings.Finance.Sectors: department balance + withdraw + deposit + ledger
-- ════════════════════════════════════════════════════════════════════════════════════════════════

local Settings = JS.Settings
local Finance = Settings.Finance
local Notify = JS.Notify

-- ═════ Balance provider: the bank script (business / qb / renewed style) or an internal fund ═════
local function Bank() return exports[Finance.Resource] end

local Providers = {
    -- Business/department accounts (getBusinessAccount / AddMoney / RemoveMoney)
    business = {
        label = Finance.Resource .. ' (business accounts)',
        balance = function(job)
            local account = Bank():getBusinessAccount(job)
            return type(account) == 'table' and tonumber(account.balance) or nil
        end,
        add = function(job, amount, reason) return Bank():AddMoney(job, amount, reason) == true end,
        remove = function(job, amount, reason) return Bank():RemoveMoney(job, amount, reason) == true end,
    },
    qb = {
        label = Finance.Resource .. ' (GetAccountBalance)',
        balance = function(job) return tonumber(Bank():GetAccountBalance(job)) end,
        add = function(job, amount, reason) return Bank():AddMoney(job, amount, reason) ~= false end,
        remove = function(job, amount, reason) return Bank():RemoveMoney(job, amount, reason) ~= false end,
    },
    renewed = {
        label = Finance.Resource .. ' (getAccountMoney)',
        balance = function(job) return tonumber(Bank():getAccountMoney(job)) end,
        add = function(job, amount) return Bank():addAccountMoney(job, amount) ~= false end,
        remove = function(job, amount) return Bank():removeAccountMoney(job, amount) ~= false end,
    },
    internal = {
        label = 'Internal fund (justice_sector_funds)',
        balance = function(job)
            MySQL.insert.await('INSERT IGNORE INTO justice_sector_funds (job, balance) VALUES (?, 0)', { job })
            return tonumber(MySQL.scalar.await('SELECT balance FROM justice_sector_funds WHERE job = ?', { job })) or 0
        end,
        add = function(job, amount)
            MySQL.insert.await('INSERT IGNORE INTO justice_sector_funds (job, balance) VALUES (?, 0)', { job })
            return (MySQL.update.await('UPDATE justice_sector_funds SET balance = balance + ? WHERE job = ?', { amount, job }) or 0) > 0
        end,
        remove = function(job, amount)
            -- Atomic: only withdraws when the balance is enough (never negative, even with simultaneous withdrawals)
            return (MySQL.update.await('UPDATE justice_sector_funds SET balance = balance - ? WHERE job = ? AND balance >= ?', { amount, job, amount }) or 0) > 0
        end,
    },
}

JS.FinanceProvider = 'internal'

local function Provider() return Providers[JS.FinanceProvider] end

local function DetectProvider()
    local wanted = Finance.Provider
    if Providers[wanted] then
        JS.FinanceProvider = wanted
        return
    end
    -- auto: try the bank script functions
    local job = next(Finance.Sectors or {})
    if job and GetResourceState(Finance.Resource) == 'started' then
        for _, name in ipairs({ 'business', 'qb', 'renewed' }) do
            local ok, balance = pcall(Providers[name].balance, job)
            if ok and type(balance) == 'number' then
                JS.FinanceProvider = name
                return
            end
        end
    end
    JS.FinanceProvider = 'internal'
end
JS.DetectFinanceProvider = DetectProvider

-- ═════ Who can use the finance office ═════
function JS.SectorList()
    local list = {}
    for job, sector in pairs(Finance.Sectors or {}) do list[#list + 1] = { job = job, label = JS.Safe(sector.label or job) } end
    table.sort(list, function(a, b) return a.label < b.label end)
    return list
end

-- requestedJob: the judge can pick any department
function JS.GetFinanceSector(Player, ignoreDuty, requestedJob)
    if Player and JS.IsJudge(Player) then
        if not ignoreDuty and Settings.Panel.RequireDuty and not JS.IsOwner(Player) and not Player.PlayerData.job.onduty then return nil, 'You must be on duty' end
        local list = JS.SectorList()
        if #list == 0 then return nil end
        local chosen = list[1]
        for _, s in ipairs(list) do if s.job == requestedJob then chosen = s end end
        return { job = chosen.job, label = chosen.label, judge = true }
    end
    local job = Player and Player.PlayerData.job
    local sector = job and Finance.Sectors and Finance.Sectors[job.name]
    if not sector then return nil end
    local grade = JS.GetGrade(Player)
    local allowed = false
    for _, level in ipairs(sector.managers or {}) do
        if tonumber(level) == grade then allowed = true break end
    end
    if not allowed then return nil end
    if not ignoreDuty and Finance.RequireDuty and not job.onduty then return nil, 'You must be on duty' end
    return { job = job.name, label = sector.label or job.label or job.name }
end

local function FinanceOnly(Player)
    local sector, err = JS.GetFinanceSector(Player)
    if sector then return true end
    return false, err or 'The finance office is for department managers only'
end

-- ═════ Ledger ═════
local function History(job)
    local list = {}
    for i, row in ipairs(MySQL.query.await('SELECT * FROM justice_sector_transactions WHERE job = ? ORDER BY id DESC LIMIT 40', { job }) or {}) do
        list[i] = {
            id = row.id, type = row.type, typeLabel = row.type == 'deposit' and 'Deposit' or 'Withdrawal',
            amount = tonumber(row.amount) or 0, reason = JS.Safe(row.reason), officer = JS.Safe(row.officer_name),
            grade = JS.Safe(row.officer_grade), balance = tonumber(row.balance_after), date = JS.FormatDbDate(row.created_at),
        }
    end
    return list
end

local function Record(Player, job, tType, amount, reason, balanceAfter)
    local info = JS.PoliceInfo(Player)
    MySQL.insert.await('INSERT INTO justice_sector_transactions (job, type, amount, reason, officer_cid, officer_name, officer_grade, balance_after) VALUES (?, ?, ?, ?, ?, ?, ?, ?)', {
        job, tType, amount, reason, info.citizenid, info.name, info.grade, balanceAfter
    })
    JS.Log(Player, tType == 'deposit' and 'sector_deposit' or 'sector_withdraw', nil, nil, {
        ['Department'] = job, ['Amount'] = amount, ['Reason'] = reason, ['Balance after'] = balanceAfter,
    })
    -- Notify the other managers of the same department
    JS.BroadcastTablet(function(t)
        local s = JS.GetFinanceSector(t, true)
        return s and s.job == job and t.PlayerData.citizenid ~= info.citizenid
    end, {
        type = 'finance', title = ('💰 Department %s'):format(tType == 'deposit' and 'deposit' or 'withdrawal'),
        text = ('%s: $%d - %s'):format(info.name, amount, reason),
    })
end

local function Validate(amount, reason)
    amount = math.floor(tonumber(amount) or 0)
    reason = JS.CleanText(reason, 150, true)
    if amount <= 0 then return nil, nil, 'Invalid amount' end
    if amount > Finance.MaxPerTransaction then return nil, nil, ('The maximum per transaction is $%d'):format(Finance.MaxPerTransaction) end
    if not reason then return nil, nil, 'A reason is required' end
    return amount, reason
end

-- ═════ Callbacks ═════
JS.RegisterCallback('NomadJustice:server:financeInfo', FinanceOnly, function(src, Player, requestedJob)
    local sector = JS.GetFinanceSector(Player, false, requestedJob)
    local ok, balance = pcall(Provider().balance, sector.job)
    if not ok then
        print(('^1[NomadJustice] finance balance error (%s): %s^7'):format(JS.FinanceProvider, tostring(balance)))
        return { ok = false, err = 'Could not read the department balance' }
    end
    return {
        ok = true, job = sector.job, label = JS.Safe(sector.label), balance = math.floor(balance or 0),
        provider = Provider().label, maxPerTransaction = Finance.MaxPerTransaction,
        myBank = math.floor(tonumber(Player.PlayerData.money.bank) or 0),
        history = History(sector.job),
        sectors = sector.judge and JS.SectorList() or nil,
    }
end)

JS.RegisterCallback('NomadJustice:server:financeDeposit', FinanceOnly, function(src, Player, amount, reason, requestedJob)
    local sector = JS.GetFinanceSector(Player, false, requestedJob)
    local err
    amount, reason, err = Validate(amount, reason)
    if err then return { ok = false, err = err } end
    if JS.OnCooldown('finance', Player.PlayerData.citizenid, 3) then return { ok = false, err = 'Wait a few seconds' } end

    local took, takeErr = JS.TakeMoney(Player.PlayerData.citizenid, amount, 'sector-deposit')
    if not took then return { ok = false, err = 'Your bank account: ' .. tostring(takeErr) } end

    local ok, added = pcall(Provider().add, sector.job, amount, 'Deposit: ' .. reason)
    if not ok or not added then
        JS.GiveMoney(Player.PlayerData.citizenid, amount, 'sector-deposit-refund')
        return { ok = false, err = 'Could not deposit to the department account, the amount was returned' }
    end
    local _, balance = pcall(Provider().balance, sector.job)
    Record(Player, sector.job, 'deposit', amount, reason, math.floor(tonumber(balance) or 0))
    return { ok = true, balance = math.floor(tonumber(balance) or 0) }
end)

JS.RegisterCallback('NomadJustice:server:financeWithdraw', FinanceOnly, function(src, Player, amount, reason, requestedJob)
    local sector = JS.GetFinanceSector(Player, false, requestedJob)
    local err
    amount, reason, err = Validate(amount, reason)
    if err then return { ok = false, err = err } end
    if JS.OnCooldown('finance', Player.PlayerData.citizenid, 3) then return { ok = false, err = 'Wait a few seconds' } end

    local okB, balance = pcall(Provider().balance, sector.job)
    if not okB or (tonumber(balance) or 0) < amount then
        return { ok = false, err = ('Insufficient department balance (balance: $%d)'):format(math.floor(tonumber(balance) or 0)) }
    end

    local ok, removed = pcall(Provider().remove, sector.job, amount, 'Withdrawal: ' .. reason)
    if not ok or not removed then return { ok = false, err = 'Could not withdraw from the department account' } end

    local gave = JS.GiveMoney(Player.PlayerData.citizenid, amount, 'sector-withdraw')
    if not gave then
        pcall(Provider().add, sector.job, amount, 'Failed withdrawal refund')
        return { ok = false, err = 'Could not deposit to your account, the amount was returned to the department' }
    end
    local _, after = pcall(Provider().balance, sector.job)
    Record(Player, sector.job, 'withdraw', amount, reason, math.floor(tonumber(after) or 0))
    return { ok = true, balance = math.floor(tonumber(after) or 0) }
end)

-- Balances of all departments (for the DOJ city economy view)
function JS.GetSectorBalances()
    local list = {}
    for job, sector in pairs(Finance.Sectors or {}) do
        local ok, balance = pcall(Provider().balance, job)
        list[#list + 1] = { job = job, label = JS.Safe(sector.label or job), balance = ok and math.floor(tonumber(balance) or 0) or nil }
    end
    table.sort(list, function(a, b) return a.label < b.label end)
    return list
end

CreateThread(function()
    while not JS.Ready do Wait(500) end
    Wait(1500) -- give the bank script time to start
    DetectProvider()
    print(('^2[NomadJustice]^7 Finance provider: %s'):format(Provider().label))
end)
