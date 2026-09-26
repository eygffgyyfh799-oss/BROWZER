local Framework = Config.Framework
local QBCore, ESX

local function detect()
    if Framework ~= 'auto' then return Framework end
    if GetResourceState('ox_inventory') == 'started' then return 'ox' end
    if GetResourceState('qb-core') == 'started' then return 'qb' end
    if GetResourceState('es_extended') == 'started' then return 'esx' end
    return 'standalone'
end

local function hasBypass(src)
    if not src or src <= 0 then return false end
    return IsPlayerAceAllowed(src, Config.BypassAce)
end

-- ============ تحذير + لوق ============
local lastWarn = {}

local function log(src, text)
    print(('[anti-explosives] %s (%s): %s'):format(GetPlayerName(src) or '?', src, text))
    if Config.Webhook ~= '' then
        PerformHttpRequest(Config.Webhook, function() end, 'POST', json.encode({
            username = 'Anti Explosives',
            embeds = { {
                title = '🚫 حماية المتفجرات',
                color = 16711680,
                description = ('**اللاعب:** %s\n**الآيدي:** %s\n**التفاصيل:** %s'):format(GetPlayerName(src) or '?', src, text),
            } },
        }), { ['Content-Type'] = 'application/json' })
    end
end

local function warn(src, msg)
    local now = GetGameTimer()
    if lastWarn[src] and now - lastWarn[src] < 1000 then return end
    lastWarn[src] = now
    TriggerClientEvent('anti-explosives:warn', src, msg)
    if QBCore then
        TriggerClientEvent('QBCore:Notify', src, msg, 'error', 7000)
    elseif ESX then
        TriggerClientEvent('esx:showNotification', src, msg)
    elseif GetResourceState('ox_lib') == 'started' then
        TriggerClientEvent('ox_lib:notify', src, { title = 'الحماية', description = msg, type = 'error', duration = 7000 })
    end
end

local function punish(src, itemName, count)
    warn(src, Config.WarningMessage:format(itemName))
    log(src, ('تم حذف %sx %s من الحقيبة'):format(count or 1, itemName))
end

-- ============ فحص الحقيبة حسب الفريم ورك ============
local scanPlayer

local function setupOx()
    local ox = exports.ox_inventory

    scanPlayer = function(src)
        local items = ox:GetInventoryItems(src)
        if not items then return end
        for _, item in pairs(items) do
            if item and IsExplosive(item.name) then
                ox:RemoveItem(src, item.name, item.count, nil, item.slot)
                punish(src, item.label or item.name, item.count)
            end
        end
    end

    -- منع نقل غرض متفجر لحقيبة لاعب (من ستاش / أرض / سيارة / لاعب ثاني)
    ox:registerHook('swapItems', function(p)
        local item = p.fromSlot
        if type(item) == 'table' and IsExplosive(item.name) and p.toType == 'player' then
            local target = tonumber(p.toInventory) or p.source
            if hasBypass(target) then return true end
            punish(target, item.label or item.name, p.count)
            return false
        end
    end)

    -- منع الشراء والتصنيع
    ox:registerHook('buyItem', function(p)
        if IsExplosive(p.itemName) and not hasBypass(p.source) then
            punish(p.source, p.itemName, p.count)
            return false
        end
    end)
    ox:registerHook('craftItem', function(p)
        local name = p.recipe and p.recipe.name
        if IsExplosive(name) and not hasBypass(p.source) then
            punish(p.source, name, 1)
            return false
        end
    end)

    -- أي غرض ينضاف بـ AddItem (سكربتات، أدمن، هكر...) ينحذف فوراً
    ox:registerHook('createItem', function(p)
        local inv = tonumber(p.inventoryId)
        if inv and GetPlayerName(inv) and IsExplosive(p.item and p.item.name) and not hasBypass(inv) then
            SetTimeout(100, function() scanPlayer(inv) end)
        end
    end)
end

local function setupQB()
    QBCore = exports['qb-core']:GetCoreObject()

    scanPlayer = function(src)
        local Player = QBCore.Functions.GetPlayer(src)
        if not Player then return end
        for _, item in pairs(Player.PlayerData.items or {}) do
            if item and IsExplosive(item.name) then
                local count = item.amount or item.count or 1
                Player.Functions.RemoveItem(item.name, count, item.slot)
                punish(src, item.label or item.name, count)
            end
        end
    end

    -- qb-inventory الجديد يطلق هذا الحدث عند الإضافة
    AddEventHandler('qb-inventory:server:itemAdded', function(src)
        if src then SetTimeout(100, function() if not hasBypass(src) then scanPlayer(src) end end) end
    end)
end

local function setupESX()
    ESX = exports['es_extended']:getSharedObject()

    scanPlayer = function(src)
        local xPlayer = ESX.GetPlayerFromId(src)
        if not xPlayer then return end
        for _, item in pairs(xPlayer.getInventory() or {}) do
            if item.count and item.count > 0 and IsExplosive(item.name) then
                xPlayer.removeInventoryItem(item.name, item.count)
                punish(src, item.label or item.name, item.count)
            end
        end
        for _, weapon in pairs(xPlayer.getLoadout() or {}) do
            if IsExplosive(weapon.name) then
                xPlayer.removeWeapon(weapon.name)
                punish(src, weapon.label or weapon.name, 1)
            end
        end
    end

    -- حذف فوري عند إضافة غرض
    AddEventHandler('esx:onAddInventoryItem', function(src, itemName)
        if IsExplosive(itemName) and not hasBypass(src) then
            SetTimeout(100, function() scanPlayer(src) end)
        end
    end)
end

-- ============ التشغيل ============
CreateThread(function()
    Wait(1000)
    Framework = detect()
    if Framework == 'ox' then
        if GetResourceState('qb-core') == 'started' then QBCore = exports['qb-core']:GetCoreObject() end
        if GetResourceState('es_extended') == 'started' then ESX = exports['es_extended']:getSharedObject() end
        setupOx()
    elseif Framework == 'qb' then
        setupQB()
    elseif Framework == 'esx' then
        setupESX()
    else
        scanPlayer = function() end
    end
    print(('[anti-explosives] شغال على: %s'):format(Framework))

    -- فحص دوري لكل اللاعبين (احتياط)
    while true do
        Wait(Config.ScanInterval)
        for _, id in ipairs(GetPlayers()) do
            local src = tonumber(id)
            if not hasBypass(src) then
                local ok, err = pcall(scanPlayer, src)
                if not ok then print('[anti-explosives] خطأ: ' .. tostring(err)) end
            end
        end
    end
end)

-- إرسال حالة الاستثناء للكلاينت (الإدارة)
AddEventHandler('playerJoining', function()
    local src = source
    SetTimeout(5000, function()
        TriggerClientEvent('anti-explosives:setBypass', src, hasBypass(src))
    end)
end)
AddEventHandler('onResourceStart', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, id in ipairs(GetPlayers()) do
        TriggerClientEvent('anti-explosives:setBypass', tonumber(id), hasBypass(tonumber(id)))
    end
end)

-- الكلاينت شال سلاح متفجر من يد اللاعب
RegisterNetEvent('anti-explosives:weaponRemoved', function(weaponName)
    local src = source
    if hasBypass(src) or not IsExplosive(weaponName) then return end
    if scanPlayer then pcall(scanPlayer, src) end
    warn(src, Config.WarningMessage:format(weaponName))
    log(src, 'كان ماسك سلاح متفجر: ' .. tostring(weaponName))
end)

-- منع الانفجارات من اللاعبين
local blockedExplosion = {}
for _, t in ipairs(Config.BlockedExplosionTypes) do blockedExplosion[t] = true end

AddEventHandler('explosionEvent', function(sender, ev)
    if not Config.BlockExplosions then return end
    local src = tonumber(sender)
    if blockedExplosion[ev.explosionType] and not hasBypass(src) then
        CancelEvent()
        warn(src, Config.ExplosionWarning)
        log(src, 'حاول يسوي انفجار نوع ' .. tostring(ev.explosionType))
    end
end)

AddEventHandler('playerDropped', function() lastWarn[source] = nil end)
