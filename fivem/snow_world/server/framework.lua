-- التعامل مع الفريمورك: رقم الهوية، الاسم، الوظيفة، وصلاحية الأدمن
-- يتعرف تلقائياً على Qbox و QBCore و ESX، ولو ما فيه فريمورك يستخدم license

Framework = {}

local QB, ESX

function Framework.name()
    if GetResourceState('qbx_core') == 'started' then return 'qbx' end
    if GetResourceState('qb-core') == 'started' then
        QB = QB or exports['qb-core']:GetCoreObject()
        return 'qb'
    end
    if GetResourceState('es_extended') == 'started' then
        ESX = ESX or exports.es_extended:getSharedObject()
        return 'esx'
    end
    return 'none'
end

-- بيانات الشخصية الحالية (nil لو ما اختار شخصية)
function Framework.player(id)
    local fw = Framework.name()
    if fw == 'qbx' then
        local p = exports.qbx_core:GetPlayer(id)
        return p and p.PlayerData, fw
    elseif fw == 'qb' then
        local p = QB.Functions.GetPlayer(id)
        return p and p.PlayerData, fw
    elseif fw == 'esx' then
        return ESX.GetPlayerFromId(id), fw
    end
    return nil, fw
end

-- رقم الهوية (citizenid في QB/Qbox، identifier في ESX، license بدون فريمورك)
function Framework.citizenId(id)
    local data, fw = Framework.player(id)
    if fw == 'qb' or fw == 'qbx' then return data and data.citizenid end
    if fw == 'esx' then return data and data.identifier end
    return GetPlayerIdentifierByType(id, 'license')
end

-- آيدي السيرفر للاعب صاحب رقم الهوية لو متصل
function Framework.sourceOf(cid)
    local fw = Framework.name()
    if fw == 'qbx' then
        local p = exports.qbx_core:GetPlayerByCitizenId(cid)
        return p and p.PlayerData.source
    elseif fw == 'qb' then
        local p = QB.Functions.GetPlayerByCitizenId(cid)
        return p and p.PlayerData.source
    elseif fw == 'esx' then
        local p = ESX.GetPlayerFromIdentifier(cid)
        return p and p.source
    end
    for _, s in ipairs(GetPlayers()) do
        local id = tonumber(s)
        if GetPlayerIdentifierByType(id, 'license') == cid then return id end
    end
end

-- اسم الشخصية
function Framework.charName(id)
    local data, fw = Framework.player(id)
    if data then
        if fw == 'esx' then
            local ok, name = pcall(function() return data.getName() end)
            if ok and name then return name end
        elseif data.charinfo then
            return ('%s %s'):format(data.charinfo.firstname or '', data.charinfo.lastname or '')
        end
    end
    return GetPlayerName(id) or ('#' .. id)
end

local policeJobs = {}
for _, job in ipairs(Config.PoliceJobs) do policeJobs[job] = true end

-- شرطي وعلى رأس العمل؟
function Framework.isPolice(id)
    local data, fw = Framework.player(id)
    if not data or not data.job or not policeJobs[data.job.name] then return false end
    if fw == 'esx' then return true end
    return data.job.onduty ~= false
end

-- أدمن god؟ (الكونسول دايم مسموح)
function Framework.isGod(id)
    if id == 0 then return true end
    for _, ace in ipairs(Config.Admin.Aces) do
        if IsPlayerAceAllowed(id, ace) then return true end
    end
    local fw = Framework.name()
    if fw == 'qbx' then
        local ok, res = pcall(function() return exports.qbx_core:HasPermission(id, Config.Admin.QBPermission) end)
        if ok and res then return true end
    elseif fw == 'qb' then
        local ok, res = pcall(QB.Functions.HasPermission, id, Config.Admin.QBPermission)
        if ok and res then return true end
    elseif fw == 'esx' then
        local x = ESX.GetPlayerFromId(id)
        if x then
            for _, g in ipairs(Config.Admin.ESXGroups) do
                if x.getGroup() == g then return true end
            end
        end
    end
    return false
end
