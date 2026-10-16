-- فصل الراديو والمكالمات والشات العادي بين العوالم
-- الراديو والمكالمات: كل عالم له نسخة من نفس الموجة (الموجة + رقم العالم × OFFSET)
-- فاللي على موجة 1 في الثلج يسمعون بعض بس، وما يسمعون موجة 1 في العالم العادي أو الرملي

local I = Config.Isolation
local OFFSET = I.ChannelOffset

local function voiceStarted()
    return GetResourceState('pma-voice') == 'started'
end

local function worldIndex(id)
    local key = Worlds.of(id)
    return key == 'main' and 0 or Worlds.index[key]
end

-- يحول الموجة لنسخة العالم الصحيح، ويرجع nil لو ما تحتاج تغيير
local function correctChannel(ch, idx)
    ch = tonumber(ch) or 0
    if ch <= 0 then return nil end
    local base = ch % OFFSET
    if base <= 0 then return nil end
    local want = base + idx * OFFSET
    if math.abs(want - ch) < 0.0001 then return nil end
    return want
end

local function fixChannels(id)
    if not voiceStarted() then return end
    local state = Player(id).state
    local idx = worldIndex(id)

    if I.Radio then
        local want = correctChannel(state.radioChannel, idx)
        if want then exports['pma-voice']:setPlayerRadio(id, want) end
    end
    if I.Calls then
        local want = correctChannel(state.callChannel, idx)
        if want then exports['pma-voice']:setPlayerCall(id, want) end
    end
end

-- لما ينتقل اللاعب لعالم ثاني ننقل موجته ومكالمته معه
Worlds.hooks[#Worlds.hooks + 1] = function(id)
    fixChannels(id)
end

-- لما يغير الموجة أو يدخل مكالمة، نتأكد إنها نسخة عالمه
local function onChannelChange(bagName, _, value)
    local id = tonumber(bagName:match('^player:(%d+)$'))
    if not id or not tonumber(value) then return end
    if correctChannel(value, worldIndex(id)) then
        SetTimeout(0, function() fixChannels(id) end)
    end
end

AddStateBagChangeHandler('radioChannel', nil, onChannelChange)
AddStateBagChangeHandler('callChannel', nil, onChannelChange)

-- ===================== الشات العادي =====================
-- لو ما فيه أحد في عالم ثاني نخلي الشات طبيعي بدون أي تدخل
-- ما نلمس الأوامر (تبدأ بـ /) ولا الرسائل اللي سكربت ثاني منعها، عشان ما تطلع رسائل مثل /-toggleSiren
AddEventHandler('chatMessage', function(src, author, message)
    if not I.Chat or not Worlds.any() then return end
    if WasEventCanceled() or type(message) ~= 'string' or message:sub(1, 1) == '/' then return end
    CancelEvent()
    for _, id in ipairs(Worlds.players(Worlds.of(src))) do
        TriggerClientEvent('chat:addMessage', id, { args = { author, message } })
    end
end)
