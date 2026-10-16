-- قائمة اللاعبين: كل لاعب يشوف بس اللي في نفس عالمه

local last = {}

RegisterNetEvent('worlds:scoreboard', function()
    local src = source
    if not Config.Scoreboard.Enabled then return end
    local now = GetGameTimer()
    if last[src] and now - last[src] < 1000 then return end
    last[src] = now

    local key = Worlds.of(src)
    local list = {}
    for _, id in ipairs(Worlds.players(key)) do
        list[#list + 1] = { id = id, name = GetPlayerName(id), ping = GetPlayerPing(id) }
    end
    table.sort(list, function(a, b) return a.id < b.id end)

    TriggerClientEvent('worlds:scoreboard', src, {
        world = Worlds.label(key),
        players = list,
        police = Config.Scoreboard.ShowPoliceCount and #Worlds.police(key) or nil,
    })
end)

AddEventHandler('playerDropped', function() last[source] = nil end)
