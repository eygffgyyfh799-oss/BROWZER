JC.City = {}

local function Menu(id, title, parent, options, emptyText)
    if #options == 0 then options[1] = { title = emptyText or 'Nothing here', disabled = true } end
    lib.registerContext({ id = id, title = title, menu = parent, options = options })
    lib.showContext(id)
end

local function Confirm(header, content)
    return lib.alertDialog({ header = header, content = content, centered = true, cancel = true }) == 'confirm'
end

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- City affairs main menu
-- ════════════════════════════════════════════════════════════════════════════════════════════════

function JC.City.Open(parent)
    local result = JC.Call('NomadJustice:server:getCityOverview')
    if not result then return end
    local o, perms = result.overview, result.perms or {}

    local dutyText = {}
    for i, entry in ipairs(o.duty or {}) do
        if i > 6 then break end
        dutyText[#dutyText + 1] = ('%s: %d'):format(entry.label, entry.count)
    end

    local options = {
        {
            title = 'City Status',
            description = ('🟢 Online: %d | 👥 Citizens: %s | ⛔ Suspended: %d | 📜 Open summonses: %d'):format(
                o.online or 0, o.citizens and tostring(o.citizens) or '-', o.suspended or 0, o.pendingSummons or 0),
            icon = 'fas fa-city', readOnly = true,
        },
        {
            title = 'Departments On Duty',
            description = #dutyText > 0 and table.concat(dutyText, ' | ') or 'Nobody on duty',
            icon = 'fas fa-building-shield', readOnly = true,
        },
    }

    if o.vehicles then
        options[#options + 1] = {
            title = ('🚗 Vehicle Registry (%d)'):format(o.vehicles.total),
            description = ('Impounded: %s | Out of garage: %s'):format(tostring(o.vehicles.impounded or '-'), tostring(o.vehicles.outside or '-')),
            icon = 'fas fa-car', arrow = true,
            onSelect = function() JC.City.SearchVehicles('justice_city') end,
        }
    end

    if o.houses then
        options[#options + 1] = {
            title = ('🏠 Property Registry (%d)'):format(o.houses),
            icon = 'fas fa-house', arrow = true,
            onSelect = function() JC.City.SearchProperties('justice_city') end,
        }
    end

    if perms.summon then
        options[#options + 1] = {
            title = ('📜 Open Summonses (%d)'):format(o.pendingSummons or 0),
            icon = 'fas fa-envelope-open-text', arrow = true,
            onSelect = function() JC.City.OpenSummons('justice_city') end,
        }
    end

    if o.economy then
        local e = o.economy
        options[#options + 1] = {
            title = ('💰 City Economy: %s'):format(JC.Money(e.total)),
            description = ('Bank deposits: %s | Cash: %s'):format(JC.Money(e.bank), JC.Money(e.cash)),
            icon = 'fas fa-sack-dollar', arrow = true,
            onSelect = function() JC.City.OpenRichest(e, 'justice_city') end,
        }
    end

    if perms.announce then
        options[#options + 1] = {
            title = '📢 City-wide Announcement',
            icon = 'fas fa-bullhorn', iconColor = 'orange',
            onSelect = function() JC.City.Announce() end,
        }
    end

    lib.registerContext({ id = 'justice_city', title = 'City Affairs', menu = parent, options = options })
    lib.showContext('justice_city')
end

function JC.City.OpenRichest(economy, parent)
    local options = {}
    for i, entry in ipairs(economy.richest or {}) do
        options[i] = {
            title = ('%d. %s%s'):format(i, entry.status and entry.status.online and '🟢 ' or '⚫ ', entry.name),
            description = ('Total: %s | Bank: %s | Cash: %s'):format(JC.Money(entry.bank + entry.cash), JC.Money(entry.bank), JC.Money(entry.cash)),
            icon = 'fas fa-crown', iconColor = i <= 3 and 'yellow' or nil, arrow = true,
            onSelect = function() JC.Panel.OpenProfile(entry.citizenid, 'justice_city_richest') end,
        }
    end
    Menu('justice_city_richest', 'Top 10 Richest Citizens', parent, options)
end

function JC.City.Announce()
    local input = lib.inputDialog('City-wide Announcement', {
        { type = 'textarea', label = 'Announcement', required = true, min = 5, max = JC.Settings.City.AnnounceMaxLength, autosize = true },
    })
    if not input or not input[1] then return JC.City.Open() end
    if Confirm('Confirm Announcement', ('This announcement will be shown to every player:\n\n%s'):format(input[1]))
        and JC.Call('NomadJustice:server:announce', input[1]) then
        JC.Notify('Announcement sent', 'success')
    end
end

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- Vehicles
-- ════════════════════════════════════════════════════════════════════════════════════════════════

function JC.City.SearchVehicles(parent)
    local input = lib.inputDialog('Vehicle Registry', {
        { type = 'input', label = 'Plate number or owner citizen ID', required = true, min = 2, max = 20, icon = 'car' },
    })
    if not input or not input[1] then return end

    local result = JC.Call('NomadJustice:server:searchVehicles', input[1])
    if not result then return end

    local options = {}
    for i, v in ipairs(result.vehicles) do
        options[i] = {
            title = ('%s | %s'):format(v.plate, v.label),
            description = ('Owner: %s (%s) | %s%s'):format(JC.Value(v.ownerName), v.owner, v.state, v.inWorld and ' | 📍 On the street' or ''),
            icon = v.stateCode == 2 and 'fas fa-lock' or 'fas fa-car',
            iconColor = v.stateCode == 2 and 'red' or (v.inWorld and 'green' or nil),
            arrow = true,
            onSelect = function() JC.City.OpenVehicle(v.plate, 'justice_city_vehicles') end,
        }
    end
    Menu('justice_city_vehicles', ('Vehicle Results (%d)'):format(#result.vehicles), parent, options, 'No vehicles found')
end

function JC.City.OpenVehicle(plate, parent)
    local result = JC.Call('NomadJustice:server:getVehicle', plate)
    if not result then return end
    local v, perms = result.vehicle, result.perms or {}
    local reopen = function() JC.City.OpenVehicle(plate, parent) end

    local options = {
        { title = v.label, description = ('Plate: %s | Model: %s'):format(v.plate, JC.Value(v.model)), icon = 'fas fa-car' },
        { title = 'State', description = ('%s | Garage: %s%s'):format(v.state, JC.Value(v.garage), v.inWorld and ' | 📍 On the street now' or ''), icon = 'fas fa-warehouse' },
        {
            title = 'Owner: ' .. JC.Value(v.ownerName),
            description = ('%s\nCitizen ID: %s'):format(JC.Value(v.ownerStatus), v.owner),
            icon = 'fas fa-user', arrow = true,
            onSelect = function() JC.Panel.OpenProfile(v.owner, 'justice_city_vehicle') end,
        },
    }

    if perms.locate and v.inWorld then
        options[#options + 1] = {
            title = 'Locate Vehicle', icon = 'fas fa-location-crosshairs', iconColor = 'blue',
            onSelect = function()
                local located = JC.Call('NomadJustice:server:getVehicle', plate, true)
                if located and located.vehicle.coords then
                    JC.TempBlip(located.vehicle.coords, 'Vehicle ' .. plate, JC.Settings.Panel.LocateBlipTime, 225, 1)
                    JC.Notify(('Vehicle %s is at: %s'):format(plate, JC.GetStreet(located.vehicle.coords)), 'success', 10000)
                else
                    JC.Notify('The vehicle is no longer on the street', 'error')
                end
            end,
        }
    end

    if perms.vehicles then
        if v.stateCode == 2 then
            options[#options + 1] = {
                title = 'Release from Impound', icon = 'fas fa-lock-open', iconColor = 'green',
                onSelect = function()
                    if Confirm('Release from Impound', ('Release vehicle **%s** from impound?'):format(plate)) then
                        local r = JC.Call('NomadJustice:server:vehicleAction', plate, 'release')
                        if r then JC.Notify(r.message, 'success') end
                    end
                    reopen()
                end,
            }
        else
            options[#options + 1] = {
                title = 'Impound Vehicle', description = v.inWorld and 'It will be removed from the street' or nil,
                icon = 'fas fa-lock', iconColor = 'red',
                onSelect = function()
                    if Confirm('Impound Vehicle', ('Impound vehicle **%s** owned by **%s**?'):format(plate, JC.Value(v.ownerName))) then
                        local r = JC.Call('NomadJustice:server:vehicleAction', plate, 'impound')
                        if r then JC.Notify(r.message, 'success') end
                    end
                    reopen()
                end,
            }
        end
        options[#options + 1] = {
            title = 'Transfer Title', icon = 'fas fa-right-left', iconColor = 'yellow',
            onSelect = function()
                local input = lib.inputDialog('Transfer title of ' .. plate, {
                    { type = 'input', label = 'New owner citizen ID', required = true, max = 50, icon = 'id-card' },
                })
                if input and input[1] and Confirm('Transfer Title', ('Transfer **%s** to citizen ID **%s**?'):format(plate, input[1])) then
                    local r = JC.Call('NomadJustice:server:vehicleAction', plate, 'transfer', input[1])
                    if r then JC.Notify(r.message, 'success') end
                end
                reopen()
            end,
        }
    end

    Menu('justice_city_vehicle', 'Vehicle ' .. plate, parent, options)
end

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- Properties
-- ════════════════════════════════════════════════════════════════════════════════════════════════

function JC.City.SearchProperties(parent)
    local input = lib.inputDialog('Property Registry', {
        { type = 'input', label = 'Property name or owner citizen ID', required = true, min = 2, max = 40, icon = 'house' },
    })
    if not input or not input[1] then return end

    local result = JC.Call('NomadJustice:server:searchProperties', input[1])
    if not result then return end
    local perms = result.perms or {}

    local options = {}
    for i, p in ipairs(result.properties) do
        options[i] = {
            title = p.label,
            description = ('Owner: %s (%s)\n%s'):format(JC.Value(p.ownerName), JC.Value(p.owner), JC.Value(p.ownerStatus)),
            icon = 'fas fa-house', arrow = true,
            onSelect = function()
                local sub = {
                    { title = p.label, description = 'Owner: ' .. JC.Value(p.ownerName), icon = 'fas fa-house' },
                }
                if p.owner then
                    sub[#sub + 1] = {
                        title = 'Open Owner Record', icon = 'fas fa-id-card', arrow = true,
                        onSelect = function() JC.Panel.OpenProfile(p.owner, 'justice_city_property') end,
                    }
                end
                if perms.properties then
                    sub[#sub + 1] = {
                        title = 'Transfer Deed', icon = 'fas fa-right-left', iconColor = 'yellow',
                        onSelect = function()
                            local nInput = lib.inputDialog('Transfer deed of ' .. p.label, {
                                { type = 'input', label = 'New owner citizen ID', required = true, max = 50 },
                            })
                            if nInput and nInput[1] and Confirm('Transfer Deed', ('Transfer **%s** to **%s**?'):format(p.label, nInput[1])) then
                                local r = JC.Call('NomadJustice:server:transferProperty', p.id, nInput[1])
                                if r then JC.Notify(r.message, 'success') end
                            end
                        end,
                    }
                end
                Menu('justice_city_property', p.label, 'justice_city_properties', sub)
            end,
        }
    end
    Menu('justice_city_properties', ('Property Results (%d)'):format(#result.properties), parent, options, 'No properties found')
end

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- Summonses
-- ════════════════════════════════════════════════════════════════════════════════════════════════

local SummonActions = {
    { value = 'attended', label = 'Appeared' },
    { value = 'absent', label = 'Failed to appear' },
    { value = 'cancelled', label = 'Cancel summons' },
}

function JC.City.UpdateSummon(summon, after)
    local input = lib.inputDialog('Update summons #' .. summon.id, {
        { type = 'select', label = 'Status', required = true, options = SummonActions },
    })
    if input and input[1] and JC.Call('NomadJustice:server:setSummonStatus', summon.id, input[1]) then
        JC.Notify('Summons updated', 'success')
    end
    if after then after() end
end

function JC.City.OpenSummons(parent)
    local result = JC.Call('NomadJustice:server:getAllSummons')
    if not result then return end

    local options = {}
    for i, s in ipairs(result.summons) do
        options[i] = {
            title = ('#%d | %s%s'):format(s.id, s.citizenStatus and s.citizenStatus.online and '🟢 ' or '⚫ ', s.name),
            description = ('%s\nWhen: %s | Where: %s | %s'):format(s.reason, JC.Value(s.appointment), JC.Value(s.location), s.statusLabel),
            icon = 'fas fa-envelope', iconColor = s.status == 'pending' and 'yellow' or 'blue',
            metadata = { { label = 'By', value = JC.Value(s.officer) }, { label = 'Date', value = JC.Value(s.date) } },
            onSelect = function()
                Menu('justice_city_summon', 'Summons #' .. s.id, 'justice_city_summons', {
                    { title = 'Open Citizen Record', icon = 'fas fa-id-card', arrow = true, onSelect = function() JC.Panel.OpenProfile(s.citizenid, 'justice_city_summon') end },
                    { title = 'Update Status', icon = 'fas fa-pen', onSelect = function() JC.City.UpdateSummon(s, function() JC.City.OpenSummons(parent) end) end },
                })
            end,
        }
    end
    Menu('justice_city_summons', ('Open Summonses (%d)'):format(#result.summons), parent, options, 'No open summonses')
end

function JC.City.SendSummon(citizenid, name, after)
    local input = lib.inputDialog('Summon ' .. name .. ' to Court', {
        { type = 'input', label = 'Reason', required = true, max = JC.Settings.City.SummonMaxLength, icon = 'pen' },
        { type = 'input', label = 'Date & time', description = 'e.g. Thursday at 9 PM', max = 100, icon = 'clock' },
        { type = 'input', label = 'Location', description = 'e.g. Main Courtroom', max = 100, icon = 'location-dot' },
    })
    if input and input[1] then
        local r = JC.Call('NomadJustice:server:sendSummon', citizenid, input[1], input[2] or '', input[3] or '')
        if r then
            JC.Notify(r.delivered and 'Summons delivered' or 'Summons saved, it will be delivered when they join', 'success', 8000)
        end
    end
    if after then after() end
end

-- For citizens: my summonses
function JC.City.OpenMySummons(parent)
    local result = JC.Call('NomadJustice:server:getMySummons')
    if not result then return end
    local options = {}
    for i, s in ipairs(result.summons) do
        options[i] = {
            title = ('Summons #%d | %s'):format(s.id, s.statusLabel),
            description = ('%s\nWhen: %s | Where: %s'):format(s.reason, JC.Value(s.appointment), JC.Value(s.location)),
            icon = 'fas fa-envelope',
            metadata = { { label = 'Date', value = JC.Value(s.date) } },
        }
    end
    Menu('justice_my_summons', 'My Summonses', parent, options, 'No summonses')
end
