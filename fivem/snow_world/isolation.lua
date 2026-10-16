-- الفصل الكامل بين العالم الثلجي والعالم العادي
-- الصوت القريب، الراديو، المكالمات، والشات: كل عالم ما يوصله إلا اللي فيه
-- وفيه exports عشان أي سكربت ثاني (شرطة، بلاغات، جوال) يقدر يفلتر حسب العالم

local I = Config.Isolation
local OFFSET = I.ChannelOffset

Isolation = {}

local function voiceStarted()
    return GetResourceState('pma-voice') == 'started'
end

local function inSnow(id)
    return Isolation.isMember and Isolation.isMember(id)
end

-- ===================== العالم (Routing Bucket) =====================

Isolation.setBucket = function(id, bucket)
    -- pma-voice لازم يعرف بتغيير العالم عشان الصوت القريب ينفصل صح
    if I.Voice and voiceStarted() then
        exports['pma-voice']:updateRoutingBucket(id, bucket)
    else
        SetPlayerRoutingBucket(id, bucket)
    end
end

-- ===================== الراديو والمكالمات =====================
-- اللي في العالم الثلجي ينقل لنسخة ثانية من نفس الموجة (الموجة + OFFSET)
-- فاللي على موجة 1 في الثلج يسمعون بعض بس، وما يسمعون موجة 1 في العالم العادي

local function setRadio(id, ch)
    if voiceStarted() then exports['pma-voice']:setPlayerRadio(id, ch) end
end

local function setCall(id, ch)
    if voiceStarted() then exports['pma-voice']:setPlayerCall(id, ch) end
end

-- ننقل الموجة والمكالمة للعالم الصحيح
local function fixChannels(id)
    local state = Player(id).state
    local snow = inSnow(id)

    if I.Radio then
        local ch = tonumber(state.radioChannel) or 0
        if snow and ch > 0 and ch < OFFSET then
            setRadio(id, ch + OFFSET)
        elseif not snow and ch >= OFFSET then
            setRadio(id, ch - OFFSET)
        end
    end

    if I.Calls then
        local ch = tonumber(state.callChannel) or 0
        if snow and ch > 0 and ch < OFFSET then
            setCall(id, ch + OFFSET)
        elseif not snow and ch >= OFFSET then
            setCall(id, ch - OFFSET)
        end
    end
end

Isolation.onMove = function(id, _)
    fixChannels(id)
end

-- لما اللاعب يغير الموجة أو يدخل مكالمة وهو في الثلج، نحوله للنسخة الثلجية
local function onChannelChange(bagName, _, value)
    local id = tonumber(bagName:match('^player:(%d+)$'))
    if not id or not tonumber(value) then return end
    local ch = tonumber(value)
    local snow = inSnow(id)
    if (snow and ch > 0 and ch < OFFSET) or (not snow and ch >= OFFSET) then
        SetTimeout(0, function() fixChannels(id) end)
    end
end

AddStateBagChangeHandler('radioChannel', nil, onChannelChange)
AddStateBagChangeHandler('callChannel', nil, onChannelChange)

-- ===================== الشات =====================
-- الرسائل العادية (مو الأوامر) توصل بس للاعبين في نفس العالم

AddEventHandler('chatMessage', function(src, author, message)
    -- لو ما فيه أحد في العالم الثلجي نخلي الشات طبيعي بدون أي تدخل
    if not I.Chat or not Isolation.anyMembers() then return end
    CancelEvent()
    local snow = inSnow(src)
    for _, p in ipairs(GetPlayers()) do
        local id = tonumber(p)
        if inSnow(id) == snow then
            TriggerClientEvent('chat:addMessage', id, { args = { author, message } })
        end
    end
end)

-- ===================== exports للسكربتات الثانية =====================
-- أمثلة:
--   exports.snow_world:GetWorld(source)            -> 'snow' أو 'main'
--   exports.snow_world:IsSameWorld(a, b)           -> true / false
--   exports.snow_world:GetPlayersInWorld('snow')   -> { 3, 7, ... }
--   exports.snow_world:TriggerWorldEvent(source, 'event', ...) يرسل حدث للاعبين اللي في نفس عالم source بس

local function worldOf(id)
    return inSnow(id) and 'snow' or 'main'
end

exports('GetWorld', worldOf)

exports('IsSameWorld', function(a, b)
    return worldOf(a) == worldOf(b)
end)

exports('GetPlayersInWorld', function(world)
    local list = {}
    for _, p in ipairs(GetPlayers()) do
        local id = tonumber(p)
        if worldOf(id) == world then list[#list + 1] = id end
    end
    return list
end)

exports('TriggerWorldEvent', function(src, eventName, ...)
    local world = worldOf(src)
    for _, p in ipairs(GetPlayers()) do
        local id = tonumber(p)
        if worldOf(id) == world then TriggerClientEvent(eventName, id, ...) end
    end
end)
