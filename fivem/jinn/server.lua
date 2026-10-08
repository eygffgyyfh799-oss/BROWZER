-- الحالة تنحفظ في state bag اللاعب عشان كل اللاعبين يشوفون الجني
local lastPuff, lastScream = {}, {}

local function isJinn(src)
    return Player(src).state.jinn == true
end

-- /jinn : يحولك جني أو يرجعك
RegisterCommand(Config.Command, function(src)
    if src == 0 or not IsPlayerAceAllowed(src, Config.Ace) then return end
    local state = Player(src).state
    local on = not state.jinn
    state:set('jinn', on, true)
    if not on then state:set('jinnInvis', false, true) end
end, false)

RegisterNetEvent('jinn:invisible', function(on)
    local src = source
    if not isJinn(src) then return end
    Player(src).state:set('jinnInvis', on == true, true)
end)

-- دخان الانتقال: نرسله لكل اللاعبين عشان يشوفونه
RegisterNetEvent('jinn:puff', function(x, y, z)
    local src = source
    if not isJinn(src) or type(x) ~= 'number' or type(y) ~= 'number' or type(z) ~= 'number' then return end
    local now = GetGameTimer()
    if lastPuff[src] and now - lastPuff[src] < 300 then return end
    lastPuff[src] = now
    TriggerClientEvent('jinn:puff', -1, x, y, z)
end)

RegisterNetEvent('jinn:scream', function()
    local src = source
    if not isJinn(src) then return end
    local now = GetGameTimer()
    if lastScream[src] and now - lastScream[src] < Config.ScreamCooldown then return end
    lastScream[src] = now
    TriggerClientEvent('jinn:scream', -1, src, GetEntityCoords(GetPlayerPed(src)))
end)

AddEventHandler('playerDropped', function()
    lastPuff[source], lastScream[source] = nil, nil
end)
