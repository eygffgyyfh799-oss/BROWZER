local Settings = JC.Settings
local Panel = Settings.Panel

JC.Panel = {}

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- أدوات
-- ════════════════════════════════════════════════════════════════════════════════════════════════

local function ListMenu(id, title, parent, items, emptyText)
    local options = {}
    for i, item in ipairs(items or {}) do options[i] = item end
    if #options == 0 then options[1] = { title = emptyText or 'لا يوجد', disabled = true } end
    lib.registerContext({ id = id, title = title, menu = parent, options = options })
    lib.showContext(id)
end

local function StatusText(entry)
    if entry.status and entry.status.text then return entry.status.text end
    return entry.online and '🟢 متصل' or '⚫ غير متصل'
end

local function CitizenOption(entry, parent)
    return {
        title = ('%s%s%s'):format(entry.online and '🟢 ' or '⚫ ', entry.serverId and ('[%d] '):format(entry.serverId) or '', entry.name ~= '' and entry.name or 'بدون اسم'),
        description = ('%s\nالرقم الوطني: %s | %s | الجوال: %s%s'):format(StatusText(entry), entry.citizenid, JC.Value(entry.job), JC.Value(entry.phone),
            entry.suspended and ' | ⛔ خدماته موقوفة' or ''),
        icon = entry.suspended and 'fas fa-user-lock' or 'fas fa-user',
        iconColor = entry.suspended and 'red' or (entry.online and 'green' or 'gray'),
        arrow = true,
        onSelect = function() JC.Panel.OpenProfile(entry.citizenid, parent) end,
    }
end

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- الصفحة الرئيسية
-- ════════════════════════════════════════════════════════════════════════════════════════════════

function JC.Panel.Open()
    if not JC.IsJustice() then
        return JC.Notify('يجب أن تكون من موظفي العدل', 'error')
    end

    local info = JC.Call('RespectJustice:server:panelInfo')
    if not info then return end
    local perms = info.perms or {}

    local options = {
        {
            title = 'إحصائيات',
            description = ('🟢 متصل: %d | 👥 المواطنين: %d | ⚖️ العدل في الدوام: %d | 📂 قضايا جديدة: %d | ⛔ موقوفين: %d'):format(
                info.online or 0, info.totalCitizens or 0, info.justiceOnDuty or 0, info.newReports or 0, info.suspended or 0),
            icon = 'fas fa-chart-simple',
            readOnly = true,
        },
        {
            title = ('🟢 اللاعبين المتصلين (%d)'):format(info.online or 0),
            description = 'جميع اللاعبين الموجودين في السيرفر الآن',
            icon = 'fas fa-users', arrow = true,
            onSelect = JC.Panel.OpenOnline,
        },
        {
            title = ('👥 جميع المواطنين (%d)'):format(info.totalCitizens or 0),
            description = 'المتصلين وغير المتصلين مع آخر ظهور',
            icon = 'fas fa-address-book', arrow = true,
            onSelect = function() JC.Panel.OpenAll(0, 'all') end,
        },
        {
            title = 'البحث عن مواطن',
            description = 'بالاسم أو الرقم الوطني أو رقم الجوال أو رقم السيرفر (يشمل غير المتصلين)',
            icon = 'fas fa-magnifying-glass', arrow = true,
            onSelect = JC.Panel.OpenSearch,
        },
    }

    if perms.reports then
        options[#options + 1] = {
            title = 'القضايا',
            description = ('قضايا جديدة: %d'):format(info.newReports or 0),
            icon = 'fas fa-scale-balanced', arrow = true,
            onSelect = function() JC.Reports.OpenList(nil, 'justice_panel_main') end,
        }
    end

    options[#options + 1] = {
        title = 'القطاعات',
        description = perms.jobs and 'كل القطاعات: الموظفين، التوظيف، الرتب، الفصل، الدوام' or 'كل القطاعات وموظفينها',
        icon = 'fas fa-sitemap', arrow = true,
        onSelect = function() JC.Jobs.OpenList('justice_panel_main') end,
    }

    options[#options + 1] = {
        title = ('المواطنين الموقوفة خدماتهم (%d)'):format(info.suspended or 0),
        icon = 'fas fa-user-lock', arrow = true,
        onSelect = JC.Panel.OpenSuspended,
    }

    if perms.logs then
        options[#options + 1] = {
            title = 'سجل العمليات',
            description = 'جميع عمليات موظفي العدل',
            icon = 'fas fa-clock-rotate-left', arrow = true,
            onSelect = function() JC.Panel.OpenLogs(nil, 'justice_panel_main') end,
        }
    end

    lib.registerContext({ id = 'justice_panel_main', title = 'نظام معلومات المواطنين', options = options, rt_logo = true })
    lib.showContext('justice_panel_main')
end

function JC.Panel.OpenOnline()
    local result = JC.Call('RespectJustice:server:getOnlinePlayers')
    if not result then return end

    local items = {}
    for i, entry in ipairs(result.players) do
        entry.online = true
        items[i] = CitizenOption(entry, 'justice_panel_online')
    end
    ListMenu('justice_panel_online', ('اللاعبين المتصلين (%d)'):format(#items), 'justice_panel_main', items, 'لا يوجد لاعبين')
end

local FilterLabels = { all = 'الكل', online = '🟢 المتصلين', offline = '⚫ غير المتصلين' }

function JC.Panel.OpenAll(page, filter)
    local result = JC.Call('RespectJustice:server:getAllCitizens', page, filter)
    if not result then return end

    local items = {
        {
            title = ('العرض: %s | الصفحة %d من %d'):format(FilterLabels[result.filter], result.page + 1, result.pages),
            description = ('الإجمالي: %d | المتصلين الآن: %d'):format(result.total, result.online),
            icon = 'fas fa-filter', arrow = true,
            onSelect = function()
                local input = lib.inputDialog('عرض المواطنين', {
                    { type = 'select', label = 'العرض', required = true, default = result.filter, options = {
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
            title = 'الصفحة السابقة', icon = 'fas fa-arrow-right',
            onSelect = function() JC.Panel.OpenAll(result.page - 1, result.filter) end,
        }
    end

    for _, entry in ipairs(result.list) do
        items[#items + 1] = CitizenOption(entry, 'justice_panel_all')
    end

    if result.page + 1 < result.pages then
        items[#items + 1] = {
            title = 'الصفحة التالية', icon = 'fas fa-arrow-left',
            onSelect = function() JC.Panel.OpenAll(result.page + 1, result.filter) end,
        }
    end

    ListMenu('justice_panel_all', ('جميع المواطنين (%d)'):format(result.total), 'justice_panel_main', items, 'لا يوجد مواطنين')
end

function JC.Panel.OpenSearch()
    local input = lib.inputDialog('البحث عن مواطن', {
        { type = 'input', label = 'الاسم / الرقم الوطني / الجوال / رقم السيرفر', required = true, min = 1, max = 40, icon = 'magnifying-glass' },
    })
    if not input or not input[1] then return lib.showContext('justice_panel_main') end

    local result = JC.Call('RespectJustice:server:searchCitizens', input[1])
    if not result then return end

    local items = {}
    for i, entry in ipairs(result.results) do
        items[i] = CitizenOption(entry, 'justice_panel_search')
    end
    ListMenu('justice_panel_search', ('نتائج البحث (%d)'):format(#items), 'justice_panel_main', items, 'لا توجد نتائج')
end

function JC.Panel.OpenSuspended()
    local result = JC.Call('RespectJustice:server:getSuspended')
    if not result then return end

    local items = {}
    for i, entry in ipairs(result.list) do
        items[i] = {
            title = ('%s%s (%s)'):format(entry.status and entry.status.online and '🟢 ' or '⚫ ', entry.name, entry.citizenid),
            description = ('%s\nالسبب: %s'):format(StatusText(entry), JC.Value(entry.reason)),
            icon = 'fas fa-user-lock', iconColor = 'red', arrow = true,
            metadata = { { label = 'بواسطة', value = JC.Value(entry.officer) }, { label = 'التاريخ', value = JC.Value(entry.date) } },
            onSelect = function() JC.Panel.OpenProfile(entry.citizenid, 'justice_panel_suspended') end,
        }
    end
    ListMenu('justice_panel_suspended', 'المواطنين الموقوفة خدماتهم', 'justice_panel_main', items, 'لا يوجد مواطنين موقوفين')
end

function JC.Panel.OpenLogs(citizenid, parent)
    local result = JC.Call('RespectJustice:server:getLogs', citizenid)
    if not result then return end

    local items = {}
    for i, log in ipairs(result.logs) do
        items[i] = {
            title = ('%s | %s'):format(log.action, log.officer),
            description = (log.target and ('المواطن: ' .. log.target .. '\n') or '') .. (log.details or ''),
            icon = 'fas fa-clock-rotate-left',
            metadata = { { label = 'التاريخ', value = JC.Value(log.date) } },
        }
    end
    ListMenu('justice_panel_logs', 'سجل العمليات', parent, items, 'لا توجد عمليات')
end

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- ملف المواطن
-- ════════════════════════════════════════════════════════════════════════════════════════════════

local function ProfileSections(p, perms, menuId, reopen)
    local sections = {}

    -- البيانات الشخصية
    sections[#sections + 1] = {
        title = 'البيانات الشخصية', icon = 'fas fa-id-card', arrow = true,
        description = ('%s | %s | %s'):format(JC.Value(p.birthdate), JC.Gender(p.gender), JC.Value(p.nationality)),
        onSelect = function()
            ListMenu('justice_profile_personal', 'البيانات الشخصية', menuId, {
                { title = 'الاسم الكامل', description = JC.Value(p.name), icon = 'fas fa-user' },
                { title = 'الرقم الوطني', description = p.citizenid, icon = 'fas fa-hashtag' },
                { title = 'تاريخ الميلاد', description = JC.Value(p.birthdate), icon = 'fas fa-cake-candles' },
                { title = 'الجنس', description = JC.Gender(p.gender), icon = 'fas fa-venus-mars' },
                { title = 'الجنسية', description = JC.Value(p.nationality), icon = 'fas fa-flag' },
                { title = 'رقم الجوال', description = JC.Value(p.phone), icon = 'fas fa-phone' },
                { title = 'رقم الحساب البنكي', description = JC.Value(p.account), icon = 'fas fa-building-columns' },
                { title = 'فصيلة الدم', description = JC.Value(p.info.bloodtype), icon = 'fas fa-droplet' },
                { title = 'البصمة', description = JC.Value(p.info.fingerprint), icon = 'fas fa-fingerprint' },
                { title = 'رقم المحفظة', description = JC.Value(p.info.walletid), icon = 'fas fa-wallet' },
                { title = 'آخر تحديث للبيانات', description = JC.Value(p.lastUpdated), icon = 'fas fa-clock' },
            })
        end,
    }

    -- المالية
    sections[#sections + 1] = {
        title = 'الحالة المالية', icon = 'fas fa-sack-dollar', arrow = true,
        description = ('البنك: %s | الكاش: %s'):format(JC.Money(p.money.bank), JC.Money(p.money.cash)),
        onSelect = function()
            local items = {
                { title = 'رصيد البنك', description = JC.Money(p.money.bank), icon = 'fas fa-building-columns' },
                { title = 'الكاش', description = JC.Money(p.money.cash), icon = 'fas fa-money-bill' },
            }
            if p.money.crypto then
                items[#items + 1] = { title = 'الكريبتو', description = tostring(p.money.crypto), icon = 'fab fa-bitcoin' }
            end
            for _, t in ipairs(p.transactions or {}) do
                items[#items + 1] = {
                    title = ('%s %s | %s'):format(t.type == 'withdraw' and 'سحب' or 'تعويض', JC.Money(t.amount), JC.Value(t.date)),
                    description = ('بواسطة: %s | %s'):format(JC.Value(t.officer), JC.Value(t.reason)),
                    icon = t.type == 'withdraw' and 'fas fa-arrow-down' or 'fas fa-arrow-up',
                    iconColor = t.type == 'withdraw' and 'red' or 'green',
                }
            end
            ListMenu('justice_profile_money', 'الحالة المالية وعمليات الوزارة', menuId, items)
        end,
    }

    -- الوظيفة والعصابة والسجل
    sections[#sections + 1] = {
        title = 'الوظيفة والسجل', icon = 'fas fa-briefcase', arrow = true,
        description = ('%s - %s%s'):format(JC.Value(p.job.label), JC.Value(p.job.grade), p.job.onduty and ' (في الدوام)' or ''),
        onSelect = function()
            ListMenu('justice_profile_job', 'الوظيفة والسجل', menuId, {
                { title = 'الوظيفة', description = ('%s - %s'):format(JC.Value(p.job.label), JC.Value(p.job.grade)), icon = 'fas fa-briefcase' },
                { title = 'حالة الدوام', description = p.job.onduty and 'في الدوام' or 'خارج الدوام', icon = 'fas fa-clock' },
                { title = 'مدير', description = p.job.isboss and 'نعم' or 'لا', icon = 'fas fa-user-tie' },
                { title = 'العصابة', description = p.gang and ('%s - %s'):format(p.gang.label, JC.Value(p.gang.grade)) or 'لا يوجد', icon = 'fas fa-mask' },
                { title = 'السجن', description = p.info.injail > 0 and ('مسجون (%d شهر)'):format(p.info.injail) or 'غير مسجون', icon = 'fas fa-handcuffs' },
                { title = 'السجل الجنائي', description = p.info.criminalRecord and ('يوجد سجل' .. (p.info.criminalRecordDate and (' - ' .. p.info.criminalRecordDate) or '')) or 'نظيف', icon = 'fas fa-file-shield' },
                { title = 'الحالة الصحية', description = p.info.isdead and 'ميت / مصاب' or 'سليم', icon = 'fas fa-heart-pulse' },
                { title = 'رمز النداء', description = JC.Value(p.info.callsign), icon = 'fas fa-tag' },
            })
        end,
    }

    -- التراخيص
    local licenseItems = {}
    for i, license in ipairs(p.licenses or {}) do
        licenseItems[i] = {
            title = license.label, description = license.active and 'فعالة' or 'غير فعالة',
            icon = license.active and 'fas fa-circle-check' or 'fas fa-circle-xmark', iconColor = license.active and 'green' or 'red',
        }
    end
    sections[#sections + 1] = {
        title = ('التراخيص (%d)'):format(#licenseItems), icon = 'fas fa-id-badge', arrow = true,
        onSelect = function() ListMenu('justice_profile_licenses', 'التراخيص', menuId, licenseItems, 'لا توجد تراخيص') end,
    }

    -- المركبات
    if p.vehicles then
        sections[#sections + 1] = {
            title = ('المركبات (%d)'):format(#p.vehicles), icon = 'fas fa-car', arrow = true,
            onSelect = function()
                local items = {}
                for i, v in ipairs(p.vehicles) do
                    items[i] = {
                        title = ('%s | %s'):format(v.label, JC.Value(v.plate)),
                        description = ('%s | الكراج: %s'):format(v.state, JC.Value(v.garage)),
                        icon = 'fas fa-car',
                        metadata = {
                            { label = 'الموديل', value = JC.Value(v.model) },
                            { label = 'الوقود', value = v.fuel and (v.fuel .. '%') or '-' },
                            { label = 'المحرك', value = v.engine and (v.engine .. '%') or '-' },
                            { label = 'الهيكل', value = v.body and (v.body .. '%') or '-' },
                        },
                    }
                end
                ListMenu('justice_profile_vehicles', 'المركبات', menuId, items, 'لا توجد مركبات')
            end,
        }
    end

    -- العقارات
    if p.houses then
        sections[#sections + 1] = {
            title = ('العقارات (%d)'):format(#p.houses), icon = 'fas fa-house', arrow = true,
            onSelect = function()
                local items = {}
                for i, h in ipairs(p.houses) do items[i] = { title = h.label, icon = 'fas fa-house' } end
                ListMenu('justice_profile_houses', 'العقارات', menuId, items, 'لا توجد عقارات')
            end,
        }
    end

    -- الممتلكات
    sections[#sections + 1] = {
        title = ('الممتلكات (%d)'):format(#(p.items or {})), icon = 'fas fa-box-open', arrow = true,
        onSelect = function()
            local items = {}
            for i, item in ipairs(p.items or {}) do
                items[i] = { title = item.label, description = ('العدد: %d'):format(item.amount), icon = 'fas fa-box' }
            end
            ListMenu('justice_profile_items', 'الممتلكات', menuId, items, 'لا توجد ممتلكات')
        end,
    }

    -- القضايا
    sections[#sections + 1] = {
        title = ('القضايا (%d)'):format(#(p.reports or {})), icon = 'fas fa-scale-balanced', arrow = true,
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
            ListMenu('justice_profile_reports', 'قضايا المواطن', menuId, items, 'لا توجد قضايا')
        end,
    }

    if perms.logs then
        sections[#sections + 1] = {
            title = 'سجل العمليات على المواطن', icon = 'fas fa-clock-rotate-left', arrow = true,
            onSelect = function() JC.Panel.OpenLogs(p.citizenid, menuId) end,
        }
    end

    return sections
end

local function ProfileActions(p, perms, reopen)
    local actions = {}

    if perms.locate then
        actions[#actions + 1] = {
            title = 'تحديد الموقع الحالي', icon = 'fas fa-location-crosshairs', iconColor = 'blue',
            description = p.online and 'وضع علامة على الخريطة' or 'المواطن غير متصل',
            disabled = not p.online,
            onSelect = function()
                local result = JC.Call('RespectJustice:server:locateCitizen', p.citizenid)
                if not result then return reopen() end
                JC.TempBlip(result.coords, 'موقع ' .. result.name, Panel.LocateBlipTime, 280, 1)
                JC.Notify(('%s موجود في: %s%s'):format(result.name, JC.GetStreet(result.coords), result.inVehicle and ' (داخل مركبة)' or ''), 'success', 10000)
            end,
        }
    end

    if perms.withdraw and not p.isSelf then
        actions[#actions + 1] = {
            title = 'سحب أموال من البنك', icon = 'fas fa-money-bill-transfer', iconColor = 'orange',
            description = ('الرصيد الحالي: %s'):format(JC.Money(p.money.bank)),
            onSelect = function()
                local input = lib.inputDialog('سحب من حساب ' .. p.name, {
                    { type = 'number', label = 'المبلغ', required = true, min = 1, max = math.min(Panel.WithdrawMax, math.max(p.money.bank, 1)), icon = 'dollar-sign' },
                    { type = 'input', label = 'السبب', required = true, max = 200, icon = 'pen' },
                })
                if not input then return reopen() end

                local confirm = lib.alertDialog({
                    header = 'تأكيد السحب',
                    content = ('سيتم سحب **%s** من حساب **%s**\n\nالسبب: %s'):format(JC.Money(input[1]), p.name, input[2]),
                    centered = true, cancel = true,
                })
                if confirm == 'confirm' then
                    local result = JC.Call('RespectJustice:server:withdrawBank', p.citizenid, input[1], input[2])
                    if result then
                        JC.Notify(('تم سحب %s، الرصيد الجديد: %s'):format(JC.Money(input[1]), JC.Money(result.newBalance)), 'success', 8000)
                    end
                end
                reopen()
            end,
        }
    end

    if perms.suspend and not p.isSelf then
        if p.suspension then
            actions[#actions + 1] = {
                title = 'رفع إيقاف الخدمات', icon = 'fas fa-lock-open', iconColor = 'green',
                description = 'السبب الحالي: ' .. JC.Value(p.suspension.reason),
                onSelect = function()
                    local confirm = lib.alertDialog({ header = 'رفع الإيقاف', content = ('هل تريد رفع إيقاف خدمات **%s**؟'):format(p.name), centered = true, cancel = true })
                    if confirm == 'confirm' and JC.Call('RespectJustice:server:unsuspendCitizen', p.citizenid) then
                        JC.Notify('تم رفع إيقاف الخدمات', 'success')
                    end
                    reopen()
                end,
            }
        else
            actions[#actions + 1] = {
                title = 'إيقاف الخدمات', icon = 'fas fa-user-lock', iconColor = 'red',
                onSelect = function()
                    local input = lib.inputDialog('إيقاف خدمات ' .. p.name, {
                        { type = 'input', label = 'سبب الإيقاف', required = true, max = 200, icon = 'pen' },
                    })
                    if input and input[1] and JC.Call('RespectJustice:server:suspendCitizen', p.citizenid, input[1]) then
                        JC.Notify('تم إيقاف خدمات المواطن', 'success')
                    end
                    reopen()
                end,
            }
        end
    end

    if perms.jobs and not p.isSelf then
        actions[#actions + 1] = {
            title = 'تغيير الوظيفة والرتبة', icon = 'fas fa-briefcase', iconColor = 'blue',
            description = ('الحالية: %s - %s'):format(JC.Value(p.job.label), JC.Value(p.job.grade)),
            onSelect = function()
                JC.Jobs.ChangeCitizenJob(p.citizenid, p.name)
                reopen()
            end,
        }
        if p.job.name ~= Panel.UnemployedJob then
            actions[#actions + 1] = {
                title = 'فصل من الوظيفة', icon = 'fas fa-user-xmark', iconColor = 'red',
                onSelect = function()
                    JC.Jobs.Fire(p.citizenid, p.name)
                    reopen()
                end,
            }
        end
    end

    if perms.edit and not p.isSelf then
        actions[#actions + 1] = {
            title = 'تعديل البيانات الشخصية', icon = 'fas fa-user-pen', iconColor = 'yellow',
            onSelect = function()
                local input = lib.inputDialog('تعديل بيانات ' .. p.name, {
                    { type = 'input', label = 'الاسم الأول', default = p.firstname, required = true, min = 2, max = 20 },
                    { type = 'input', label = 'اسم العائلة', default = p.lastname, required = true, min = 2, max = 20 },
                    { type = 'input', label = 'تاريخ الميلاد (YYYY-MM-DD)', default = p.birthdate, required = true, min = 10, max = 10 },
                    { type = 'select', label = 'الجنس', default = tostring(p.gender or 0), required = true, options = {
                        { value = '0', label = 'ذكر' }, { value = '1', label = 'أنثى' },
                    } },
                    { type = 'input', label = 'الجنسية', default = p.nationality, required = true, max = 30 },
                })
                if not input then return reopen() end

                local result = JC.Call('RespectJustice:server:editCitizen', p.citizenid, {
                    firstname = input[1], lastname = input[2], birthdate = input[3], gender = tonumber(input[4]), nationality = input[5],
                })
                if result then JC.Notify('تم تحديث بيانات المواطن', 'success') end
                reopen()
            end,
        }
    end

    if perms.compensation and p.online and not p.isSelf then
        actions[#actions + 1] = {
            title = 'تعويض المواطن', icon = 'fas fa-hand-holding-dollar', iconColor = 'green',
            description = ('يجب أن يكون بالقرب منك (%.0f متر)'):format(Settings.CompensationMaxDistance),
            onSelect = function()
                local input = lib.inputDialog('تعويض ' .. p.name, {
                    { type = 'number', label = 'المبلغ', required = true, min = 1, max = Settings.CompensationMax, icon = 'dollar-sign' },
                })
                if input and tonumber(input[1]) then
                    TriggerServerEvent('RespectJustice:server:giveMoneyToPlayer', p.citizenid, math.floor(tonumber(input[1])))
                end
            end,
        }
    end

    actions[#actions + 1] = { title = 'تحديث البيانات', icon = 'fas fa-rotate', onSelect = reopen }
    return actions
end

function JC.Panel.OpenProfile(citizenid, parent)
    local result = JC.Call('RespectJustice:server:getProfile', citizenid)
    if not result then return end

    local p, perms = result.profile, result.perms or {}
    local menuId = 'justice_profile_' .. p.citizenid
    local reopen = function() JC.Panel.OpenProfile(citizenid, parent) end

    local status = StatusText(p) .. (p.online and (' | البنق %dms'):format(p.ping or 0) or '')
    local options = {
        {
            title = p.name ~= '' and p.name or 'بدون اسم',
            description = ('%s\nالرقم الوطني: %s'):format(status, p.citizenid),
            icon = p.online and 'fas fa-circle' or 'far fa-circle',
            iconColor = p.online and 'green' or 'gray',
        },
    }

    if p.suspension then
        options[#options + 1] = {
            title = 'الخدمات موقوفة',
            description = ('السبب: %s | بواسطة: %s | %s'):format(JC.Value(p.suspension.reason), JC.Value(p.suspension.officer), JC.Value(p.suspension.date)),
            icon = 'fas fa-triangle-exclamation', iconColor = 'red',
        }
    end

    for _, option in ipairs(ProfileSections(p, perms, menuId, reopen)) do options[#options + 1] = option end
    for _, option in ipairs(ProfileActions(p, perms, reopen)) do options[#options + 1] = option end

    lib.registerContext({
        id = menuId,
        title = 'ملف المواطن | ' .. p.citizenid,
        menu = parent,
        options = options,
        rt_logo = true,
    })
    lib.showContext(menuId)
end

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- أمر الفتح
-- ════════════════════════════════════════════════════════════════════════════════════════════════

if Panel.Command and Panel.Command ~= '' then
    RegisterCommand(Panel.Command, function()
        JC.Panel.Open()
    end, false)

    TriggerEvent('chat:addSuggestion', '/' .. Panel.Command, 'نظام معلومات المواطنين - وزارة العدل')
end

RegisterNetEvent('RespectJustice:client:openPanel', function()
    JC.Panel.Open()
end)
