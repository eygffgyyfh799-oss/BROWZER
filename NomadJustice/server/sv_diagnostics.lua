-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- Readiness check: runs automatically on start, and with the  justicecheck  command from the server console
-- ════════════════════════════════════════════════════════════════════════════════════════════════

local Settings = JS.Settings

local function RunDiagnostics()
    local ok, warn, bad = 0, 0, 0
    local lines = {}
    local function line(state, text)
        if state == 'ok' then ok = ok + 1 lines[#lines + 1] = '^2  ✔ ' .. text .. '^7'
        elseif state == 'warn' then warn = warn + 1 lines[#lines + 1] = '^3  ⚠ ' .. text .. '^7'
        else bad = bad + 1 lines[#lines + 1] = '^1  ✖ ' .. text .. '^7' end
    end

    -- Required resources
    for _, res in ipairs({ JCoreResource, 'ox_lib', Settings.TargetResource or 'deep-target', 'oxmysql' }) do
        local state = GetResourceState(res)
        line(state == 'started' and 'ok' or 'bad', ('%s: %s'):format(res, state == 'started' and 'running' or ('not running (' .. state .. ') - required')))
    end
    -- Optional resources
    for res, feature in pairs({ ['lb-phone'] = 'phone requirement when filing a lawsuit' }) do
        if GetResourceState(res) ~= 'started' then
            line('warn', ('%s is not running: %s is disabled (everything else works)'):format(res, feature))
        end
    end

    line('ok', ('Department finance: %s'):format(JS.FinanceProvider == 'internal'
        and 'internal fund (no department account functions found in ' .. tostring(Settings.Finance.Resource) .. ')' or ('linked with ' .. JS.FinanceProvider)))
    local police = {}
    for _, name in ipairs(Settings.Police.Jobs or {}) do
        if not (QBCore.Shared.Jobs or {})[name] then police[#police + 1] = name end
    end
    if #police > 0 then line('warn', ('Police jobs missing from the core: %s - edit Settings.Police.Jobs'):format(table.concat(police, ', '))) end

    -- Job and grades
    local jobs = QBCore.Shared.Jobs or {}
    local job = jobs[Settings.Job]
    if not job then
        line('bad', ("Job '%s' does not exist in the core jobs - edit Settings.Job"):format(Settings.Job))
    else
        line('ok', ('Justice job: %s'):format(job.label or Settings.Job))
        local full = tonumber(Settings.Panel.FullAccessGrade)
        if full and job.grades and not (job.grades[tostring(full)] or job.grades[full]) then
            line('warn', ('Grade %d (full access) does not exist in the justice job - any higher grade gets it, otherwise managers only'):format(full))
        end
    end
    if not jobs[Settings.Panel.UnemployedJob] then
        line('warn', ("Unemployed job '%s' does not exist - terminating will not work, edit UnemployedJob"):format(tostring(Settings.Panel.UnemployedJob)))
    end
    if not QBCore.Shared.Gangs or not QBCore.Shared.Gangs[Settings.City.NoGang] then
        line('warn', ("Gang '%s' (no gang) does not exist - removing gangs may not work"):format(tostring(Settings.City.NoGang)))
    end

    -- Database
    local db = Settings.Database
    line(JS.TableExists(db.Players) and 'ok' or 'bad', ('Players table `%s`'):format(db.Players))
    if not JS.TableExists(db.Vehicles) then
        line('warn', ('Vehicle table `%s` not found - vehicle registry hidden'):format(tostring(db.Vehicles)))
    end
    if not (db.Houses and JS.TableExists(db.Houses.table)) then
        line('warn', ('Property table `%s` not found - property registry hidden'):format(tostring(db.Houses and db.Houses.table)))
    elseif not JS.ColumnExists(db.Houses.table, db.Houses.owner) or not JS.ColumnExists(db.Houses.table, db.Houses.id) then
        line('warn', 'Property table columns (owner / id) are wrong - check Settings.Database.Houses')
    end
    for _, t in ipairs({ 'justice_reports', 'justice_logs', 'justice_suspensions', 'justice_summons', 'justice_transactions' }) do
        if not JS.TableExists(t) then line('bad', ('Table `%s` not found - run NomadJustice.sql'):format(t)) end
    end

    line('ok', GetConvar('justice_webhook', '') ~= '' and 'Discord: enabled' or 'Discord: disabled (optional)')

    print('^5════════ NomadJustice - readiness check ════════^7')
    for _, text in ipairs(lines) do print(text) end
    print(('^5════════ %s | ok: %d | warnings: %d | problems: %d ════════^7'):format(
        bad == 0 and '^2ready^5' or '^1needs fixing^5', ok, warn, bad))
    return bad, warn
end

CreateThread(function()
    while not JS.Ready do Wait(500) end
    Wait(2000)
    local ok, err = pcall(RunDiagnostics)
    if not ok then print('^1[NomadJustice] diagnostics: ' .. tostring(err) .. '^7') end
end)

RegisterCommand('justicecheck', function(source)
    if source ~= 0 then return end -- server console only
    RunDiagnostics()
end, true)
