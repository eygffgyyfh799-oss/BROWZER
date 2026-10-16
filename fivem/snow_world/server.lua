-- العالم الثلجي = Routing Bucket منفصل
-- اللي داخله ما يشوف ولا يسمع ولا يتأثر باللاعبين أو السيارات اللي برا، والعكس
-- ويشوف بس اللي معه في نفس العالم

local members = {}   -- [serverId] = true

SetRoutingBucketPopulationEnabled(Config.Bucket, Config.Population)
SetRoutingBucketEntityLockdownMode(Config.Bucket, 'relaxed')

local function allowed(src)
    return src == 0 or IsPlayerAceAllowed(src, Config.Ace)
end

local function reply(src, msg)
    if src == 0 then
        print('[snow_world] ' .. msg)
    else
        TriggerClientEvent('chat:addMessage', src, { args = { 'snow_world', msg } })
    end
end

-- آيدي من الأمر، أو اللي كتب الأمر لو ما حدد
local function targetFrom(src, arg)
    local id = tonumber(arg) or (src ~= 0 and src or nil)
    if not id or not GetPlayerName(id) then return nil end
    return id
end

-- ننقل اللاعب وسيارته (لو هو السايق ولحاله فيها) للعالم المطلوب
local function moveTo(id, bucket)
    local ped = GetPlayerPed(id)
    local veh = GetVehiclePedIsIn(ped, false)
    if veh ~= 0 and GetPedInVehicleSeat(veh, -1) == ped then
        local alone = true
        for seat = 0, 14 do
            local other = GetPedInVehicleSeat(veh, seat)
            if other ~= 0 and other ~= ped then alone = false break end
        end
        if alone then SetEntityRoutingBucket(veh, bucket) end
    end
    SetPlayerRoutingBucket(id, bucket)
    Player(id).state:set('snowWorld', bucket == Config.Bucket, true)
    members[id] = bucket == Config.Bucket or nil
end

RegisterCommand(Config.Commands.enter, function(src, args)
    if not allowed(src) then return end
    local id = targetFrom(src, args[1])
    if not id then return reply(src, 'اكتب آيدي لاعب موجود، مثال: /' .. Config.Commands.enter .. ' 12') end
    if members[id] then return reply(src, GetPlayerName(id) .. ' أصلاً في العالم الثلجي') end
    moveTo(id, Config.Bucket)
    reply(src, '❄ تم نقل ' .. GetPlayerName(id) .. ' إلى العالم الثلجي')
end, false)

RegisterCommand(Config.Commands.leave, function(src, args)
    if not allowed(src) then return end
    local id = targetFrom(src, args[1])
    if not id then return reply(src, 'اكتب آيدي لاعب موجود، مثال: /' .. Config.Commands.leave .. ' 12') end
    if not members[id] then return reply(src, GetPlayerName(id) .. ' مو في العالم الثلجي') end
    moveTo(id, 0)
    reply(src, 'تم إرجاع ' .. GetPlayerName(id) .. ' إلى العالم العادي')
end, false)

RegisterCommand(Config.Commands.list, function(src)
    if not allowed(src) then return end
    local names = {}
    for id in pairs(members) do names[#names + 1] = ('%s (%d)'):format(GetPlayerName(id) or '?', id) end
    reply(src, #names == 0 and 'ما فيه أحد في العالم الثلجي' or ('❄ في العالم الثلجي: ' .. table.concat(names, '، ')))
end, false)

RegisterCommand(Config.Commands.leaveAll, function(src)
    if not allowed(src) then return end
    local n = 0
    for id in pairs(members) do
        moveTo(id, 0)
        n = n + 1
    end
    reply(src, ('تم إرجاع %d لاعب إلى العالم العادي'):format(n))
end, false)

-- لو سكربت ثاني (مثل اختيار الشخصية أو الشقق) غير عالم اللاعب، نحدث الحالة عشان ما يعلق الثلج عنده
CreateThread(function()
    while true do
        Wait(5000)
        for id in pairs(members) do
            if not GetPlayerName(id) then
                members[id] = nil
            elseif GetPlayerRoutingBucket(id) ~= Config.Bucket then
                members[id] = nil
                Player(id).state:set('snowWorld', false, true)
            end
        end
    end
end)

AddEventHandler('playerDropped', function()
    members[source] = nil
end)

-- لو انطفى السكربت نرجع الكل للعالم العادي
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for id in pairs(members) do moveTo(id, 0) end
end)
