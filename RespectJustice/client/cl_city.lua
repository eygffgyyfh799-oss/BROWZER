JC.City = {}

local function Menu(id, title, parent, options, emptyText)
    if #options == 0 then options[1] = { title = emptyText or 'لا يوجد', disabled = true } end
    lib.registerContext({ id = id, title = title, menu = parent, options = options })
    lib.showContext(id)
end

local function Confirm(header, content)
    return lib.alertDialog({ header = header, content = content, centered = true, cancel = true }) == 'confirm'
end

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- القائمة الرئيسية للمدينة
-- ════════════════════════════════════════════════════════════════════════════════════════════════

function JC.City.Open(parent)
    local result = JC.Call('RespectJustice:server:getCityOverview')
    if not result then return end
    local o, perms = result.overview, result.perms or {}

    local dutyText = {}
    for i, entry in ipairs(o.duty or {}) do
        if i > 6 then break end
        dutyText[#dutyText + 1] = ('%s: %d'):format(entry.label, entry.count)
    end

    local options = {
        {
            title = 'حالة المدينة الآن',
            description = ('🟢 متصل: %d | 👥 المواطنين: %s | ⛔ موقوفين: %d | 📜 استدعاءات مفتوحة: %d'):format(
                o.online or 0, o.citizens and tostring(o.citizens) or '-', o.suspended or 0, o.pendingSummons or 0),
            icon = 'fas fa-city', readOnly = true,
        },
        {
            title = 'القطاعات في الدوام الآن',
            description = #dutyText > 0 and table.concat(dutyText, ' | ') or 'لا يوجد أحد في الدوام',
            icon = 'fas fa-building-shield', readOnly = true,
        },
    }

    if o.vehicles then
        options[#options + 1] = {
            title = ('🚗 سجل المركبات (%d)'):format(o.vehicles.total),
            description = ('محجوزة: %s | خارج الكراج: %s'):format(tostring(o.vehicles.impounded or '-'), tostring(o.vehicles.outside or '-')),
            icon = 'fas fa-car', arrow = true,
            onSelect = function() JC.City.SearchVehicles('justice_city') end,
        }
    end

    if o.houses then
        options[#options + 1] = {
            title = ('🏠 سجل العقارات (%d)'):format(o.houses),
            icon = 'fas fa-house', arrow = true,
            onSelect = function() JC.City.SearchProperties('justice_city') end,
        }
    end

    if perms.summon then
        options[#options + 1] = {
            title = ('📜 الاستدعاءات المفتوحة (%d)'):format(o.pendingSummons or 0),
            icon = 'fas fa-envelope-open-text', arrow = true,
            onSelect = function() JC.City.OpenSummons('justice_city') end,
        }
    end

    if o.economy then
        local e = o.economy
        options[#options + 1] = {
            title = ('💰 اقتصاد المدينة: %s'):format(JC.Money(e.total)),
            description = ('البنوك: %s | الكاش: %s'):format(JC.Money(e.bank), JC.Money(e.cash)),
            icon = 'fas fa-sack-dollar', arrow = true,
            onSelect = function() JC.City.OpenRichest(e, 'justice_city') end,
        }
    end

    if perms.announce then
        options[#options + 1] = {
            title = '📢 إعلان لكل المدينة',
            icon = 'fas fa-bullhorn', iconColor = 'orange',
            onSelect = function() JC.City.Announce() end,
        }
    end

    lib.registerContext({ id = 'justice_city', title = 'نظام المدينة', menu = parent, options = options, rt_logo = true })
    lib.showContext('justice_city')
end

function JC.City.OpenRichest(economy, parent)
    local options = {}
    for i, entry in ipairs(economy.richest or {}) do
        options[i] = {
            title = ('%d. %s%s'):format(i, entry.status and entry.status.online and '🟢 ' or '⚫ ', entry.name),
            description = ('المجموع: %s | البنك: %s | الكاش: %s'):format(JC.Money(entry.bank + entry.cash), JC.Money(entry.bank), JC.Money(entry.cash)),
            icon = 'fas fa-crown', iconColor = i <= 3 and 'yellow' or nil, arrow = true,
            onSelect = function() JC.Panel.OpenProfile(entry.citizenid, 'justice_city_richest') end,
        }
    end
    Menu('justice_city_richest', 'أغنى 10 مواطنين', parent, options)
end

function JC.City.Announce()
    local input = lib.inputDialog('إعلان لكل المدينة', {
        { type = 'textarea', label = 'نص الإعلان', required = true, min = 5, max = JC.Settings.City.AnnounceMaxLength, autosize = true },
    })
    if not input or not input[1] then return JC.City.Open() end
    if Confirm('تأكيد الإعلان', ('سيظهر هذا الإعلان لكل اللاعبين:\n\n%s'):format(input[1]))
        and JC.Call('RespectJustice:server:announce', input[1]) then
        JC.Notify('تم إرسال الإعلان', 'success')
    end
end

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- المركبات
-- ════════════════════════════════════════════════════════════════════════════════════════════════

function JC.City.SearchVehicles(parent)
    local input = lib.inputDialog('سجل المركبات', {
        { type = 'input', label = 'رقم اللوحة أو الرقم الوطني للمالك', required = true, min = 2, max = 20, icon = 'car' },
    })
    if not input or not input[1] then return end

    local result = JC.Call('RespectJustice:server:searchVehicles', input[1])
    if not result then return end

    local options = {}
    for i, v in ipairs(result.vehicles) do
        options[i] = {
            title = ('%s | %s'):format(v.plate, v.label),
            description = ('المالك: %s (%s) | %s%s'):format(JC.Value(v.ownerName), v.owner, v.state, v.inWorld and ' | 📍 في الشارع' or ''),
            icon = v.stateCode == 2 and 'fas fa-lock' or 'fas fa-car',
            iconColor = v.stateCode == 2 and 'red' or (v.inWorld and 'green' or nil),
            arrow = true,
            onSelect = function() JC.City.OpenVehicle(v.plate, 'justice_city_vehicles') end,
        }
    end
    Menu('justice_city_vehicles', ('نتائج المركبات (%d)'):format(#result.vehicles), parent, options, 'لا توجد مركبات')
end

function JC.City.OpenVehicle(plate, parent)
    local result = JC.Call('RespectJustice:server:getVehicle', plate)
    if not result then return end
    local v, perms = result.vehicle, result.perms or {}
    local reopen = function() JC.City.OpenVehicle(plate, parent) end

    local options = {
        { title = v.label, description = ('اللوحة: %s | الموديل: %s'):format(v.plate, JC.Value(v.model)), icon = 'fas fa-car' },
        { title = 'الحالة', description = ('%s | الكراج: %s%s'):format(v.state, JC.Value(v.garage), v.inWorld and ' | 📍 موجودة في الشارع الآن' or ''), icon = 'fas fa-warehouse' },
        {
            title = 'المالك: ' .. JC.Value(v.ownerName),
            description = ('%s\nالرقم الوطني: %s'):format(JC.Value(v.ownerStatus), v.owner),
            icon = 'fas fa-user', arrow = true,
            onSelect = function() JC.Panel.OpenProfile(v.owner, 'justice_city_vehicle') end,
        },
    }

    if perms.locate and v.inWorld then
        options[#options + 1] = {
            title = 'تحديد موقع المركبة', icon = 'fas fa-location-crosshairs', iconColor = 'blue',
            onSelect = function()
                local located = JC.Call('RespectJustice:server:getVehicle', plate, true)
                if located and located.vehicle.coords then
                    JC.TempBlip(located.vehicle.coords, 'مركبة ' .. plate, JC.Settings.Panel.LocateBlipTime, 225, 1)
                    JC.Notify(('المركبة %s في: %s'):format(plate, JC.GetStreet(located.vehicle.coords)), 'success', 10000)
                else
                    JC.Notify('المركبة لم تعد في الشارع', 'error')
                end
            end,
        }
    end

    if perms.vehicles then
        if v.stateCode == 2 then
            options[#options + 1] = {
                title = 'فك الحجز', icon = 'fas fa-lock-open', iconColor = 'green',
                onSelect = function()
                    if Confirm('فك الحجز', ('فك حجز المركبة **%s**؟'):format(plate)) then
                        local r = JC.Call('RespectJustice:server:vehicleAction', plate, 'release')
                        if r then JC.Notify(r.message, 'success') end
                    end
                    reopen()
                end,
            }
        else
            options[#options + 1] = {
                title = 'حجز المركبة', description = v.inWorld and 'سيتم سحبها من الشارع' or nil,
                icon = 'fas fa-lock', iconColor = 'red',
                onSelect = function()
                    if Confirm('حجز المركبة', ('حجز المركبة **%s** للمالك **%s**؟'):format(plate, JC.Value(v.ownerName))) then
                        local r = JC.Call('RespectJustice:server:vehicleAction', plate, 'impound')
                        if r then JC.Notify(r.message, 'success') end
                    end
                    reopen()
                end,
            }
        end
        options[#options + 1] = {
            title = 'نقل الملكية', icon = 'fas fa-right-left', iconColor = 'yellow',
            onSelect = function()
                local input = lib.inputDialog('نقل ملكية ' .. plate, {
                    { type = 'input', label = 'الرقم الوطني للمالك الجديد', required = true, max = 50, icon = 'id-card' },
                })
                if input and input[1] and Confirm('نقل الملكية', ('نقل ملكية **%s** إلى الرقم الوطني **%s**؟'):format(plate, input[1])) then
                    local r = JC.Call('RespectJustice:server:vehicleAction', plate, 'transfer', input[1])
                    if r then JC.Notify(r.message, 'success') end
                end
                reopen()
            end,
        }
    end

    Menu('justice_city_vehicle', 'مركبة ' .. plate, parent, options)
end

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- العقارات
-- ════════════════════════════════════════════════════════════════════════════════════════════════

function JC.City.SearchProperties(parent)
    local input = lib.inputDialog('سجل العقارات', {
        { type = 'input', label = 'اسم العقار أو الرقم الوطني للمالك', required = true, min = 2, max = 40, icon = 'house' },
    })
    if not input or not input[1] then return end

    local result = JC.Call('RespectJustice:server:searchProperties', input[1])
    if not result then return end
    local perms = result.perms or {}

    local options = {}
    for i, p in ipairs(result.properties) do
        options[i] = {
            title = p.label,
            description = ('المالك: %s (%s)\n%s'):format(JC.Value(p.ownerName), JC.Value(p.owner), JC.Value(p.ownerStatus)),
            icon = 'fas fa-house', arrow = true,
            onSelect = function()
                local sub = {
                    { title = p.label, description = 'المالك: ' .. JC.Value(p.ownerName), icon = 'fas fa-house' },
                }
                if p.owner then
                    sub[#sub + 1] = {
                        title = 'فتح ملف المالك', icon = 'fas fa-id-card', arrow = true,
                        onSelect = function() JC.Panel.OpenProfile(p.owner, 'justice_city_property') end,
                    }
                end
                if perms.properties then
                    sub[#sub + 1] = {
                        title = 'نقل الملكية', icon = 'fas fa-right-left', iconColor = 'yellow',
                        onSelect = function()
                            local nInput = lib.inputDialog('نقل ملكية ' .. p.label, {
                                { type = 'input', label = 'الرقم الوطني للمالك الجديد', required = true, max = 50 },
                            })
                            if nInput and nInput[1] and Confirm('نقل الملكية', ('نقل **%s** إلى **%s**؟'):format(p.label, nInput[1])) then
                                local r = JC.Call('RespectJustice:server:transferProperty', p.id, nInput[1])
                                if r then JC.Notify(r.message, 'success') end
                            end
                        end,
                    }
                end
                Menu('justice_city_property', p.label, 'justice_city_properties', sub)
            end,
        }
    end
    Menu('justice_city_properties', ('نتائج العقارات (%d)'):format(#result.properties), parent, options, 'لا توجد عقارات')
end

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- الاستدعاءات
-- ════════════════════════════════════════════════════════════════════════════════════════════════

local SummonActions = {
    { value = 'attended', label = 'حضر' },
    { value = 'absent', label = 'لم يحضر' },
    { value = 'cancelled', label = 'إلغاء الاستدعاء' },
}

function JC.City.UpdateSummon(summon, after)
    local input = lib.inputDialog('تحديث الاستدعاء #' .. summon.id, {
        { type = 'select', label = 'الحالة', required = true, options = SummonActions },
    })
    if input and input[1] and JC.Call('RespectJustice:server:setSummonStatus', summon.id, input[1]) then
        JC.Notify('تم تحديث الاستدعاء', 'success')
    end
    if after then after() end
end

function JC.City.OpenSummons(parent)
    local result = JC.Call('RespectJustice:server:getAllSummons')
    if not result then return end

    local options = {}
    for i, s in ipairs(result.summons) do
        options[i] = {
            title = ('#%d | %s%s'):format(s.id, s.citizenStatus and s.citizenStatus.online and '🟢 ' or '⚫ ', s.name),
            description = ('%s\nالموعد: %s | المكان: %s | %s'):format(s.reason, JC.Value(s.appointment), JC.Value(s.location), s.statusLabel),
            icon = 'fas fa-envelope', iconColor = s.status == 'pending' and 'yellow' or 'blue',
            metadata = { { label = 'بواسطة', value = JC.Value(s.officer) }, { label = 'التاريخ', value = JC.Value(s.date) } },
            onSelect = function()
                Menu('justice_city_summon', 'استدعاء #' .. s.id, 'justice_city_summons', {
                    { title = 'فتح ملف المواطن', icon = 'fas fa-id-card', arrow = true, onSelect = function() JC.Panel.OpenProfile(s.citizenid, 'justice_city_summon') end },
                    { title = 'تحديث الحالة', icon = 'fas fa-pen', onSelect = function() JC.City.UpdateSummon(s, function() JC.City.OpenSummons(parent) end) end },
                })
            end,
        }
    end
    Menu('justice_city_summons', ('الاستدعاءات المفتوحة (%d)'):format(#result.summons), parent, options, 'لا توجد استدعاءات مفتوحة')
end

function JC.City.SendSummon(citizenid, name, after)
    local input = lib.inputDialog('استدعاء ' .. name .. ' للمحكمة', {
        { type = 'input', label = 'السبب', required = true, max = JC.Settings.City.SummonMaxLength, icon = 'pen' },
        { type = 'input', label = 'الموعد', description = 'مثال: الخميس الساعة 9 مساءً', max = 100, icon = 'clock' },
        { type = 'input', label = 'المكان', description = 'مثال: قاعة المحكمة الرئيسية', max = 100, icon = 'location-dot' },
    })
    if input and input[1] then
        local r = JC.Call('RespectJustice:server:sendSummon', citizenid, input[1], input[2] or '', input[3] or '')
        if r then
            JC.Notify(r.delivered and 'تم إرسال الاستدعاء ووصله الآن' or 'تم حفظ الاستدعاء وبيوصله أول ما يدخل السيرفر', 'success', 8000)
        end
    end
    if after then after() end
end

-- للمواطن: استدعاءاتي
function JC.City.OpenMySummons(parent)
    local result = JC.Call('RespectJustice:server:getMySummons')
    if not result then return end
    local options = {}
    for i, s in ipairs(result.summons) do
        options[i] = {
            title = ('استدعاء #%d | %s'):format(s.id, s.statusLabel),
            description = ('%s\nالموعد: %s | المكان: %s'):format(s.reason, JC.Value(s.appointment), JC.Value(s.location)),
            icon = 'fas fa-envelope',
            metadata = { { label = 'التاريخ', value = JC.Value(s.date) } },
        }
    end
    Menu('justice_my_summons', 'استدعاءاتي', parent, options, 'لا توجد استدعاءات')
end
