-- قائمة اللاعبين، وتنبيهات البلاغات للشرطة، واقتراحات الأوامر

-- ===================== قائمة اللاعبين =====================
local showing = false

RegisterCommand('+worlds_scoreboard', function()
    if not Config.Scoreboard.Enabled then return end
    showing = true
    TriggerServerEvent('worlds:scoreboard')
    -- نحدثها كل ثانيتين وهي مفتوحة
    CreateThread(function()
        while showing do
            Wait(2000)
            if showing then TriggerServerEvent('worlds:scoreboard') end
        end
    end)
end, false)

RegisterCommand('-worlds_scoreboard', function()
    showing = false
    SendNUIMessage({ type = 'scoreboard', show = false })
end, false)

RegisterKeyMapping('+worlds_scoreboard', 'قائمة اللاعبين في عالمك', 'keyboard', Config.Scoreboard.Key)

RegisterNetEvent('worlds:scoreboard', function(data)
    if not showing then return end
    data.type = 'scoreboard'
    data.show = true
    data.me = GetPlayerServerId(PlayerId())
    SendNUIMessage(data)
end)

-- ===================== البلاغات =====================
RegisterNetEvent('worlds:dispatch', function(alert)
    local c = alert.coords
    local street = GetStreetNameFromHashKey(GetStreetNameAtCoord(c.x, c.y, c.z))
    SendNUIMessage({ type = 'dispatch', title = alert.title, text = alert.text, caller = alert.caller, street = street })
    PlaySoundFrontend(-1, 'Lose_1st', 'GTAO_FM_Events_Soundset', false)

    local blip = AddBlipForCoord(c.x, c.y, c.z)
    SetBlipSprite(blip, 161)
    SetBlipColour(blip, 1)
    SetBlipScale(blip, 1.1)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName('911')
    EndTextCommandSetBlipName(blip)
    SetTimeout(Config.ReportBlipTime * 1000, function() RemoveBlip(blip) end)
end)

-- ===================== اقتراحات الأوامر =====================
CreateThread(function()
    local c, cc = Config.Commands, Config.ChatCommands
    local add = function(cmd, help, params) if cmd then TriggerEvent('chat:addSuggestion', '/' .. cmd, help, params) end end
    add(c.add, 'ينقل لاعب للعالم الثلجي', { { name = 'آيدي', help = 'آيدي اللاعب' } })
    add(c.remove, 'يرجع لاعب للعالم العادي', { { name = 'آيدي', help = 'آيدي اللاعب' } })
    add(cc.me, 'حركة يشوفها اللي حولك في عالمك', { { name = 'نص', help = '' } })
    add(cc['do'], 'وصف يشوفه اللي حولك في عالمك', { { name = 'نص', help = '' } })
    add(cc.ooc, 'كلام خارج الرول لكل اللي في عالمك', { { name = 'نص', help = '' } })
    add(cc['911'], 'بلاغ للشرطة اللي في عالمك', { { name = 'البلاغ', help = '' } })
end)
