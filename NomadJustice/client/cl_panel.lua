local Settings = JC.Settings
local Panel = Settings.Panel

JC.Panel = {}

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- Helpers
-- ════════════════════════════════════════════════════════════════════════════════════════════════

local function ListMenu(id, title, parent, items, emptyText)
    local options = {}
    for i, item in ipairs(items or {}) do options[i] = item end
    if #options == 0 then options[1] = { title = emptyText or 'Nothing here', disabled = true } end
    lib.registerContext({ id = id, title = title, menu = parent, options = options })
    lib.showContext(id)
end

local function StatusText(entry)
    if entry.status and entry.status.text then return entry.status.text end
    return entry.online and '🟢 Online' or '⚫ Offline'
end

local function CitizenOption(entry, parent)
    return {
        title = ('%s%s%s'):format(entry.online and '🟢 ' or '⚫ ', entry.serverId and ('[%d] '):format(entry.serverId) or '', entry.name ~= '' and entry.name or 'Unnamed'),
        description = ('%s\nCitizen ID: %s | %s | Phone: %s%s'):format(StatusText(entry), entry.citizenid, JC.Value(entry.job), JC.Value(entry.phone),
            entry.suspended and ' | ⛔ Services suspended' or ''),
        icon = entry.suspended and 'fas fa-user-lock' or 'fas fa-user',
        iconColor = entry.suspended and 'red' or (entry.online and 'green' or 'gray'),
        arrow = true,
        onSelect = function() JC.Panel.OpenProfile(entry.citizenid, parent) end,
    }
end

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- Dashboard
-- ════════════════════════════════════════════════════════════════════════════════════════════════

function JC.Panel.Open()
    if not JC.IsJustice() then
        return JC.Notify('You must be a Department of Justice employee', 'error')
    end
    if Panel.UseTablet ~= false and JC.Tablet then
        return JC.Tablet.Open()
    end

    local info = JC.Call('NomadJustice:server:panelInfo')
    if not info then return end
    local perms = info.perms or {}

    local options = {
        {
            title = 'Statistics',
            description = ('🟢 Online: %d | 👥 Citizens: %d | ⚖️ DOJ on duty: %d | 📂 New cases: %d | ⛔ Suspended: %d'):format(
                info.online or 0, info.totalCitizens or 0, info.justiceOnDuty or 0, info.newReports or 0, info.suspended or 0),
            icon = 'fas fa-chart-simple',
            readOnly = true,
        },
        {
            title = ('🟢 Online Players (%d)'):format(info.online or 0),
            description = 'Everyone on the server right now',
            icon = 'fas fa-users', arrow = true,
            onSelect = JC.Panel.OpenOnline,
        },
        {
            title = ('👥 Citizen Registry (%d)'):format(info.totalCitizens or 0),
            description = 'Online and offline, with last seen',
            icon = 'fas fa-address-book', arrow = true,
            onSelect = function() JC.Panel.OpenAll(0, 'all') end,
        },
        {
            title = 'Citizen Search',
            description = 'By name, citizen ID, phone number or server ID (includes offline)',
            icon = 'fas fa-magnifying-glass', arrow = true,
            onSelect = JC.Panel.OpenSearch,
        },
    }

    if perms.reports then
        options[#options + 1] = {
            title = 'Case Files',
            description = ('New cases: %d'):format(info.newReports or 0),
            icon = 'fas fa-scale-balanced', arrow = true,
            onSelect = function() JC.Reports.OpenList(nil, 'justice_panel_main') end,
        }
    end

    if perms.city then
        options[#options + 1] = {
            title = '🏙️ City Affairs',
            description = 'Vehicles, properties, summonses, economy, announcements',
            icon = 'fas fa-city', arrow = true,
            onSelect = function() JC.City.Open('justice_panel_main') end,
        }
    end

    options[#options + 1] = {
        title = 'Departments',
        description = perms.jobs and 'All departments: staff, hiring, grades, terminations, duty' or 'All departments and their staff',
        icon = 'fas fa-sitemap', arrow = true,
        onSelect = function() JC.Jobs.OpenList('justice_panel_main') end,
    }

    options[#options + 1] = {
        title = ('Citizens with Suspended Services (%d)'):format(info.suspended or 0),
        icon = 'fas fa-user-lock', arrow = true,
        onSelect = JC.Panel.OpenSuspended,
    }

    if perms.logs then
        options[#options + 1] = {
            title = 'Audit Log',
            description = 'Every action by DOJ staff',
            icon = 'fas fa-clock-rotate-left', arrow = true,
            onSelect = function() JC.Panel.OpenLogs(nil, 'justice_panel_main') end,
        }
    end

    lib.registerContext({ id = 'justice_panel_main', title = 'State Records', options = options })
    lib.showContext('justice_panel_main')
end

function JC.Panel.OpenOnline()
    local result = JC.Call('NomadJustice:server:getOnlinePlayers')
    if not result then return end

    local items = {}
    for i, entry in ipairs(result.players) do
        entry.online = true
        items[i] = CitizenOption(entry, 'justice_panel_online')
    end
    ListMenu('justice_panel_online', ('Online Players (%d)'):format(#items), 'justice_panel_main', items, 'No players online')
end

local FilterLabels = { all = 'All', online = '🟢 Online', offline = '⚫ Offline' }

function JC.Panel.OpenAll(page, filter)
    local result = JC.Call('NomadJustice:server:getAllCitizens', page, filter)
    if not result then return end

    local items = {
        {
            title = ('Showing: %s | Page %d of %d'):format(FilterLabels[result.filter], result.page + 1, result.pages),
            description = ('Total: %d | Online now: %d'):format(result.total, result.online),
            icon = 'fas fa-filter', arrow = true,
            onSelect = function()
                local input = lib.inputDialog('Show Citizens', {
                    { type = 'select', label = 'Show', required = true, default = result.filter, options = {
                        { value = 'all', label = FilterLabels.all },
                        { value = 'online', label = FilterLabels.online },
                        { value = 'offline', label = FilterLabels.offline },
                    } },
                })
                JC.Panel.OpenAll(0, input and input[1] or result.filter)
            end,
        },
    }

    if result.page > 0 then
        items[#items + 1] = {
            title = 'Previous Page', icon = 'fas fa-arrow-left',
            onSelect = function() JC.Panel.OpenAll(result.page - 1, result.filter) end,
        }
    end

    for _, entry in ipairs(result.list) do
        items[#items + 1] = CitizenOption(entry, 'justice_panel_all')
    end

    if result.page + 1 < result.pages then
        items[#items + 1] = {
            title = 'Next Page', icon = 'fas fa-arrow-right',
            onSelect = function() JC.Panel.OpenAll(result.page + 1, result.filter) end,
        }
    end

    ListMenu('justice_panel_all', ('Citizen Registry (%d)'):format(result.total), 'justice_panel_main', items, 'No citizens')
end

function JC.Panel.OpenSearch()
    local input = lib.inputDialog('Citizen Search', {
        { type = 'input', label = 'Name / citizen ID / phone / server ID', required = true, min = 1, max = 40, icon = 'magnifying-glass' },
    })
    if not input or not input[1] then return lib.showContext('justice_panel_main') end

    local result = JC.Call('NomadJustice:server:searchCitizens', input[1])
    if not result then return end

    local items = {}
    for i, entry in ipairs(result.results) do
        items[i] = CitizenOption(entry, 'justice_panel_search')
    end
    ListMenu('justice_panel_search', ('Search Results (%d)'):format(#items), 'justice_panel_main', items, 'No results')
end

function JC.Panel.OpenSuspended()
    local result = JC.Call('NomadJustice:server:getSuspended')
    if not result then return end

    local items = {}
    for i, entry in ipairs(result.list) do
        items[i] = {
            title = ('%s%s (%s)'):format(entry.status and entry.status.online and '🟢 ' or '⚫ ', entry.name, entry.citizenid),
            description = ('%s\nReason: %s'):format(StatusText(entry), JC.Value(entry.reason)),
            icon = 'fas fa-user-lock', iconColor = 'red', arrow = true,
            metadata = { { label = 'By', value = JC.Value(entry.officer) }, { label = 'Date', value = JC.Value(entry.date) } },
            onSelect = function() JC.Panel.OpenProfile(entry.citizenid, 'justice_panel_suspended') end,
        }
    end
    ListMenu('justice_panel_suspended', 'Citizens with Suspended Services', 'justice_panel_main', items, 'No suspended citizens')
end

function JC.Panel.OpenLogs(citizenid, parent)
    local result = JC.Call('NomadJustice:server:getLogs', citizenid)
    if not result then return end

    local items = {}
    for i, log in ipairs(result.logs) do
        items[i] = {
            title = ('%s | %s'):format(log.action, log.officer),
            description = (log.target and ('Citizen: ' .. log.target .. '\n') or '') .. (log.details or ''),
            icon = 'fas fa-clock-rotate-left',
            metadata = { { label = 'Date', value = JC.Value(log.date) } },
        }
    end
    ListMenu('justice_panel_logs', 'Audit Log', parent, items, 'No actions')
end

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- Citizen record
-- ════════════════════════════════════════════════════════════════════════════════════════════════

local function ProfileSections(p, perms, menuId, reopen)
    local sections = {}

    -- Identity
    sections[#sections + 1] = {
        title = 'Identity', icon = 'fas fa-id-card', arrow = true,
        description = ('%s | %s | %s'):format(JC.Value(p.birthdate), JC.Gender(p.gender), JC.Value(p.nationality)),
        onSelect = function()
            ListMenu('justice_profile_personal', 'Identity', menuId, {
                { title = 'Full name', description = JC.Value(p.name), icon = 'fas fa-user' },
                { title = 'Citizen ID', description = p.citizenid, icon = 'fas fa-hashtag' },
                { title = 'Date of birth', description = JC.Value(p.birthdate), icon = 'fas fa-cake-candles' },
                { title = 'Sex', description = JC.Gender(p.gender), icon = 'fas fa-venus-mars' },
                { title = 'Nationality', description = JC.Value(p.nationality), icon = 'fas fa-flag' },
                { title = 'Phone number', description = JC.Value(p.phone), icon = 'fas fa-phone' },
                { title = 'Bank account', description = JC.Value(p.account), icon = 'fas fa-building-columns' },
                { title = 'Blood type', description = JC.Value(p.info.bloodtype), icon = 'fas fa-droplet' },
                { title = 'Fingerprint', description = JC.Value(p.info.fingerprint), icon = 'fas fa-fingerprint' },
                { title = 'Wallet ID', description = JC.Value(p.info.walletid), icon = 'fas fa-wallet' },
                { title = 'Last data update', description = JC.Value(p.lastUpdated), icon = 'fas fa-clock' },
            })
        end,
    }

    -- Finances
    sections[#sections + 1] = {
        title = 'Finances', icon = 'fas fa-sack-dollar', arrow = true,
        description = ('Bank: %s | Cash: %s'):format(JC.Money(p.money.bank), JC.Money(p.money.cash)),
        onSelect = function()
            local items = {
                { title = 'Bank balance', description = JC.Money(p.money.bank), icon = 'fas fa-building-columns' },
                { title = 'Cash', description = JC.Money(p.money.cash), icon = 'fas fa-money-bill' },
            }
            if p.money.crypto then
                items[#items + 1] = { title = 'Crypto', description = tostring(p.money.crypto), icon = 'fab fa-bitcoin' }
            end
            for _, t in ipairs(p.transactions or {}) do
                items[#items + 1] = {
                    title = ('%s %s | %s'):format(t.type == 'withdraw' and 'Seizure' or 'Compensation', JC.Money(t.amount), JC.Value(t.date)),
                    description = ('By: %s | %s'):format(JC.Value(t.officer), JC.Value(t.reason)),
                    icon = t.type == 'withdraw' and 'fas fa-arrow-down' or 'fas fa-arrow-up',
                    iconColor = t.type == 'withdraw' and 'red' or 'green',
                }
            end
            ListMenu('justice_profile_money', 'Finances and DOJ Transactions', menuId, items)
        end,
    }

    -- Job, gang and record
    sections[#sections + 1] = {
        title = 'Employment & Record', icon = 'fas fa-briefcase', arrow = true,
        description = ('%s - %s%s'):format(JC.Value(p.job.label), JC.Value(p.job.grade), p.job.onduty and ' (on duty)' or ''),
        onSelect = function()
            ListMenu('justice_profile_job', 'Employment & Record', menuId, {
                { title = 'Job', description = ('%s - %s'):format(JC.Value(p.job.label), JC.Value(p.job.grade)), icon = 'fas fa-briefcase' },
                { title = 'Duty', description = p.job.onduty and 'On duty' or 'Off duty', icon = 'fas fa-clock' },
                { title = 'Manager', description = p.job.isboss and 'Yes' or 'No', icon = 'fas fa-user-tie' },
                { title = 'Gang', description = p.gang and ('%s - %s'):format(p.gang.label, JC.Value(p.gang.grade)) or 'None', icon = 'fas fa-mask' },
                { title = 'Jail', description = p.info.injail > 0 and ('Incarcerated (%d months)'):format(p.info.injail) or 'Not incarcerated', icon = 'fas fa-handcuffs' },
                { title = 'Criminal record', description = p.info.criminalRecord and ('On file' .. (p.info.criminalRecordDate and (' - ' .. p.info.criminalRecordDate) or '')) or 'Clean', icon = 'fas fa-file-shield' },
                { title = 'Medical status', description = p.info.isdead and 'Deceased / Injured' or 'Healthy', icon = 'fas fa-heart-pulse' },
                { title = 'Callsign', description = JC.Value(p.info.callsign), icon = 'fas fa-tag' },
            })
        end,
    }

    -- Licenses
    local licenseItems, activeCount = {}, 0
    for i, license in ipairs(p.licenses or {}) do
        if license.active then activeCount = activeCount + 1 end
        local canToggle = perms.licenses and not p.isSelf
        licenseItems[i] = {
            title = license.label,
            description = (license.active and 'Valid' or 'Not held') .. (canToggle and (license.active and ' - click to revoke' or ' - click to grant') or ''),
            icon = license.active and 'fas fa-circle-check' or 'fas fa-circle-xmark', iconColor = license.active and 'green' or 'red',
            onSelect = canToggle and function()
                local action = license.active and 'Revoke' or 'Grant'
                local ok = lib.alertDialog({ header = action .. ' License', content = ('%s **%s** for **%s**?'):format(action, license.label, p.name), centered = true, cancel = true })
                if ok == 'confirm' and JC.Call('NomadJustice:server:setLicense', p.citizenid, license.key, not license.active) then
                    JC.Notify(('License %s'):format(license.active and 'revoked' or 'granted'), 'success')
                end
                reopen()
            end or nil,
        }
    end
    sections[#sections + 1] = {
        title = ('Licenses (%d valid)'):format(activeCount), icon = 'fas fa-id-badge', arrow = true,
        onSelect = function() ListMenu('justice_profile_licenses', 'Licenses', menuId, licenseItems, 'No licenses') end,
    }

    -- Vehicles
    if p.vehicles then
        sections[#sections + 1] = {
            title = ('Vehicles (%d)'):format(#p.vehicles), icon = 'fas fa-car', arrow = true,
            onSelect = function()
                local items = {}
                for i, v in ipairs(p.vehicles) do
                    items[i] = {
                        title = ('%s | %s'):format(v.label, JC.Value(v.plate)),
                        description = ('%s | Garage: %s'):format(v.state, JC.Value(v.garage)),
                        icon = 'fas fa-car',
                        arrow = perms.city and v.plate ~= nil,
                        onSelect = (perms.city and v.plate) and function() JC.City.OpenVehicle(v.plate, 'justice_profile_vehicles') end or nil,
                        metadata = {
                            { label = 'Model', value = JC.Value(v.model) },
                            { label = 'Fuel', value = v.fuel and (v.fuel .. '%') or '-' },
                            { label = 'Engine', value = v.engine and (v.engine .. '%') or '-' },
                            { label = 'Body', value = v.body and (v.body .. '%') or '-' },
                        },
                    }
                end
                ListMenu('justice_profile_vehicles', 'Vehicles', menuId, items, 'No registered vehicles')
            end,
        }
    end

    -- Properties
    if p.houses then
        sections[#sections + 1] = {
            title = ('Properties (%d)'):format(#p.houses), icon = 'fas fa-house', arrow = true,
            onSelect = function()
                local items = {}
                for i, h in ipairs(p.houses) do items[i] = { title = h.label, icon = 'fas fa-house' } end
                ListMenu('justice_profile_houses', 'Properties', menuId, items, 'No properties')
            end,
        }
    end

    -- Possessions
    sections[#sections + 1] = {
        title = ('Possessions (%d)'):format(#(p.items or {})), icon = 'fas fa-box-open', arrow = true,
        onSelect = function()
            local items = {}
            for i, item in ipairs(p.items or {}) do
                items[i] = { title = item.label, description = ('Quantity: %d'):format(item.amount), icon = 'fas fa-box' }
            end
            ListMenu('justice_profile_items', 'Possessions', menuId, items, 'No possessions')
        end,
    }

    -- Cases
    sections[#sections + 1] = {
        title = ('Cases (%d)'):format(#(p.reports or {})), icon = 'fas fa-scale-balanced', arrow = true,
        onSelect = function()
            local items = {}
            for i, r in ipairs(p.reports or {}) do
                items[i] = {
                    title = ('#%d | %s'):format(r.id, r.title),
                    description = ('%s | %s | %s | %s'):format(r.role, JC.Value(r.caseType), JC.Value(r.status), JC.Value(r.date)),
                    icon = 'fas fa-file-lines', arrow = perms.reports,
                    onSelect = perms.reports and function() JC.Reports.OpenDetails(r.id, 'justice_profile_reports') end or nil,
                }
            end
            ListMenu('justice_profile_reports', 'Citizen Cases', menuId, items, 'No cases')
        end,
    }

    local summonItems = {}
    for i, sm in ipairs(p.summons or {}) do
        summonItems[i] = {
            title = ('#%d | %s'):format(sm.id, sm.statusLabel),
            description = ('%s\nWhen: %s | Where: %s'):format(sm.reason, JC.Value(sm.appointment), JC.Value(sm.location)),
            icon = 'fas fa-envelope',
            metadata = { { label = 'By', value = JC.Value(sm.officer) }, { label = 'Date', value = JC.Value(sm.date) } },
            onSelect = (perms.summon and (sm.status == 'pending' or sm.status == 'delivered')) and function() JC.City.UpdateSummon(sm, reopen) end or nil,
        }
    end
    sections[#sections + 1] = {
        title = ('Summonses (%d)'):format(#summonItems), icon = 'fas fa-envelope-open-text', arrow = true,
        onSelect = function() ListMenu('justice_profile_summons', 'Citizen Summonses', menuId, summonItems, 'No summonses') end,
    }

    if perms.logs then
        sections[#sections + 1] = {
            title = 'Audit Log for this Citizen', icon = 'fas fa-clock-rotate-left', arrow = true,
            onSelect = function() JC.Panel.OpenLogs(p.citizenid, menuId) end,
        }
    end

    return sections
end

local function ProfileActions(p, perms, reopen)
    local actions = {}

    if perms.locate then
        actions[#actions + 1] = {
            title = 'Locate Now', icon = 'fas fa-location-crosshairs', iconColor = 'blue',
            description = p.online and 'Mark on the map' or 'The citizen is offline',
            disabled = not p.online,
            onSelect = function()
                local result = JC.Call('NomadJustice:server:locateCitizen', p.citizenid)
                if not result then return reopen() end
                JC.TempBlip(result.coords, 'Location: ' .. result.name, Panel.LocateBlipTime, 280, 1)
                JC.Notify(('%s is at: %s%s'):format(result.name, JC.GetStreet(result.coords), result.inVehicle and ' (in a vehicle)' or ''), 'success', 10000)
            end,
        }
    end

    if perms.withdraw and not p.isSelf then
        actions[#actions + 1] = {
            title = 'Bank Seizure', icon = 'fas fa-money-bill-transfer', iconColor = 'orange',
            description = ('Current balance: %s'):format(JC.Money(p.money.bank)),
            onSelect = function()
                local input = lib.inputDialog('Seize from ' .. p.name .. "'s account", {
                    { type = 'number', label = 'Amount', required = true, min = 1, max = math.min(Panel.WithdrawMax, math.max(p.money.bank, 1)), icon = 'dollar-sign' },
                    { type = 'input', label = 'Reason', required = true, max = 200, icon = 'pen' },
                })
                if not input then return reopen() end

                local confirm = lib.alertDialog({
                    header = 'Confirm Seizure',
                    content = ('**%s** will be seized from **%s**\n\nReason: %s'):format(JC.Money(input[1]), p.name, input[2]),
                    centered = true, cancel = true,
                })
                if confirm == 'confirm' then
                    local result = JC.Call('NomadJustice:server:withdrawBank', p.citizenid, input[1], input[2])
                    if result then
                        JC.Notify(('Seized %s, new balance: %s'):format(JC.Money(input[1]), JC.Money(result.newBalance)), 'success', 8000)
                    end
                end
                reopen()
            end,
        }
    end

    if perms.suspend and not p.isSelf then
        if p.suspension then
            actions[#actions + 1] = {
                title = 'Lift Service Suspension', icon = 'fas fa-lock-open', iconColor = 'green',
                description = 'Current reason: ' .. JC.Value(p.suspension.reason),
                onSelect = function()
                    local confirm = lib.alertDialog({ header = 'Lift Suspension', content = ('Lift the service suspension for **%s**?'):format(p.name), centered = true, cancel = true })
                    if confirm == 'confirm' and JC.Call('NomadJustice:server:unsuspendCitizen', p.citizenid) then
                        JC.Notify('Service suspension lifted', 'success')
                    end
                    reopen()
                end,
            }
        else
            actions[#actions + 1] = {
                title = 'Suspend Services', icon = 'fas fa-user-lock', iconColor = 'red',
                onSelect = function()
                    local input = lib.inputDialog('Suspend services for ' .. p.name, {
                        { type = 'input', label = 'Suspension reason', required = true, max = 200, icon = 'pen' },
                    })
                    if input and input[1] and JC.Call('NomadJustice:server:suspendCitizen', p.citizenid, input[1]) then
                        JC.Notify('Citizen services suspended', 'success')
                    end
                    reopen()
                end,
            }
        end
    end

    if perms.jobs and not p.isSelf then
        actions[#actions + 1] = {
            title = 'Change Job & Grade', icon = 'fas fa-briefcase', iconColor = 'blue',
            description = ('Current: %s - %s'):format(JC.Value(p.job.label), JC.Value(p.job.grade)),
            onSelect = function()
                JC.Jobs.ChangeCitizenJob(p.citizenid, p.name)
                reopen()
            end,
        }
        if p.job.name ~= Panel.UnemployedJob then
            actions[#actions + 1] = {
                title = 'Terminate Employment', icon = 'fas fa-user-xmark', iconColor = 'red',
                onSelect = function()
                    JC.Jobs.Fire(p.citizenid, p.name)
                    reopen()
                end,
            }
        end
    end

    if perms.summon then
        actions[#actions + 1] = {
            title = 'Court Summons', icon = 'fas fa-envelope', iconColor = 'blue',
            description = p.online and 'Delivered now' or 'Delivered when they join the server',
            onSelect = function() JC.City.SendSummon(p.citizenid, p.name, reopen) end,
        }
    end

    if perms.gangs and not p.isSelf then
        actions[#actions + 1] = {
            title = 'Change Gang', icon = 'fas fa-mask', iconColor = 'purple',
            description = 'Current: ' .. (p.gang and p.gang.label or 'None'),
            onSelect = function()
                local result = JC.Call('NomadJustice:server:getGangs')
                if not result then return reopen() end
                local gangOptions = {}
                for i, g in ipairs(result.gangs) do gangOptions[i] = { value = tostring(i), label = ('%s (%s)'):format(g.label, g.name) } end
                local input = lib.inputDialog('Gang of ' .. p.name, {
                    { type = 'select', label = 'Gang', required = true, searchable = true, options = gangOptions },
                })
                local gang = input and result.gangs[tonumber(input[1])]
                if not gang or #gang.grades == 0 then return reopen() end
                local gradeOptions = {}
                for i, g in ipairs(gang.grades) do gradeOptions[i] = { value = tostring(g.level), label = ('%d - %s'):format(g.level, g.name) } end
                local gInput = lib.inputDialog('Rank in ' .. gang.label, {
                    { type = 'select', label = 'Rank', required = true, options = gradeOptions, default = gradeOptions[1].value },
                })
                if gInput and gInput[1] and JC.Call('NomadJustice:server:setGang', p.citizenid, gang.name, tonumber(gInput[1])) then
                    JC.Notify('Gang changed', 'success')
                end
                reopen()
            end,
        }
    end

    if perms.edit and not p.isSelf then
        actions[#actions + 1] = {
            title = 'Edit Identity', icon = 'fas fa-user-pen', iconColor = 'yellow',
            onSelect = function()
                local input = lib.inputDialog('Edit identity of ' .. p.name, {
                    { type = 'input', label = 'First name', default = p.firstname, required = true, min = 2, max = 20 },
                    { type = 'input', label = 'Last name', default = p.lastname, required = true, min = 2, max = 20 },
                    { type = 'input', label = 'Date of birth (YYYY-MM-DD)', default = p.birthdate, required = true, min = 10, max = 10 },
                    { type = 'select', label = 'Sex', default = tostring(p.gender or 0), required = true, options = {
                        { value = '0', label = 'Male' }, { value = '1', label = 'Female' },
                    } },
                    { type = 'input', label = 'Nationality', default = p.nationality, required = true, max = 30 },
                })
                if not input then return reopen() end

                local result = JC.Call('NomadJustice:server:editCitizen', p.citizenid, {
                    firstname = input[1], lastname = input[2], birthdate = input[3], gender = tonumber(input[4]), nationality = input[5],
                })
                if result then JC.Notify('Citizen identity updated', 'success') end
                reopen()
            end,
        }
    end

    local unlimitedComp = perms.unlimitedCompensation == true
    if perms.compensation and p.online and (not p.isSelf or unlimitedComp) then
        actions[#actions + 1] = {
            title = p.isSelf and 'Compensate Myself' or 'Compensate Citizen', icon = 'fas fa-hand-holding-dollar', iconColor = 'green',
            description = unlimitedComp and 'No limit' or ('They must be near you (%.0f m)'):format(Settings.CompensationMaxDistance),
            onSelect = function()
                local input = lib.inputDialog('Compensate ' .. p.name, {
                    { type = 'number', label = 'Amount', required = true, min = 1, max = unlimitedComp and Settings.CompensationHardCap or Settings.CompensationMax, icon = 'dollar-sign' },
                })
                if input and tonumber(input[1]) then
                    TriggerServerEvent('NomadJustice:server:giveMoneyToPlayer', p.citizenid, math.floor(tonumber(input[1])))
                end
            end,
        }
    end

    actions[#actions + 1] = { title = 'Refresh', icon = 'fas fa-rotate', onSelect = reopen }
    return actions
end

function JC.Panel.OpenProfile(citizenid, parent)
    local result = JC.Call('NomadJustice:server:getProfile', citizenid)
    if not result then return end

    local p, perms = result.profile, result.perms or {}
    local menuId = 'justice_profile_' .. p.citizenid
    local reopen = function() JC.Panel.OpenProfile(citizenid, parent) end

    local status = StatusText(p) .. (p.online and (' | Ping %dms'):format(p.ping or 0) or '')
    local options = {
        {
            title = p.name ~= '' and p.name or 'Unnamed',
            description = ('%s\nCitizen ID: %s'):format(status, p.citizenid),
            icon = p.online and 'fas fa-circle' or 'far fa-circle',
            iconColor = p.online and 'green' or 'gray',
        },
    }

    if p.suspension then
        options[#options + 1] = {
            title = 'Services Suspended',
            description = ('Reason: %s | By: %s | %s'):format(JC.Value(p.suspension.reason), JC.Value(p.suspension.officer), JC.Value(p.suspension.date)),
            icon = 'fas fa-triangle-exclamation', iconColor = 'red',
        }
    end

    for _, option in ipairs(ProfileSections(p, perms, menuId, reopen)) do options[#options + 1] = option end
    for _, option in ipairs(ProfileActions(p, perms, reopen)) do options[#options + 1] = option end

    lib.registerContext({
        id = menuId,
        title = 'Citizen Record | ' .. p.citizenid,
        menu = parent,
        options = options,
    })
    lib.showContext(menuId)
end

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- Open command
-- ════════════════════════════════════════════════════════════════════════════════════════════════

if Panel.Command and Panel.Command ~= '' then
    RegisterCommand(Panel.Command, function()
        JC.Panel.Open()
    end, false)

    TriggerEvent('chat:addSuggestion', '/' .. Panel.Command, 'State Records - Department of Justice')
end

RegisterNetEvent('NomadJustice:client:openPanel', function()
    JC.Panel.Open()
end)
