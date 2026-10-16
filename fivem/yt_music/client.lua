-- الصوت ثلاثي الأبعاد: كل لاعب يسمع الصوت حسب بعده عن مكان التشغيل
-- قريب = قوي جداً، بعيد = يخف شوي شوي (ولو EveryoneHears يبقى مسموع للكل)

local current = nil   -- { pos, follow, volume }
local muted = false
local lastSent = -1

local function nui(data) SendNUIMessage(data) end

-- مكان مصدر الصوت (لو يمشي مع الأدمن ونشوفه، ناخذ مكانه مباشرة عشان يكون ناعم)
local function sourcePos()
    if current.follow then
        local player = GetPlayerFromServerId(current.follow)
        if player ~= -1 then
            local ped = GetPlayerPed(player)
            if DoesEntityExist(ped) then return GetEntityCoords(ped) end
        end
    end
    local p = current.pos
    return vector3(p.x, p.y, p.z)
end

local function volumeFor(dist)
    local f = math.max(0.0, 1.0 - dist / Config.Range)
    f = f ^ 1.2
    if Config.EveryoneHears then f = math.max(f, Config.FarVolume) end
    return f
end

CreateThread(function()
    while true do
        if current then
            local v = 0
            if not muted then
                local dist = #(GetFinalRenderedCamCoord() - sourcePos())
                v = math.floor(current.volume * volumeFor(dist) + 0.5)
            end
            if v ~= lastSent then
                lastSent = v
                nui({ type = 'volume', volume = v })
            end
            Wait(100)
        else
            Wait(500)
        end
    end
end)

RegisterNetEvent('yt_music:play', function(data)
    current = { pos = data.pos, follow = data.follow, volume = data.volume }
    lastSent = -1
    nui({ type = 'play', id = data.id, at = data.at, loop = data.loop, volume = 0 })
end)

RegisterNetEvent('yt_music:stop', function()
    current = nil
    nui({ type = 'stop' })
end)

RegisterNetEvent('yt_music:volume', function(v)
    if current then
        current.volume = v
        lastSent = -1
    end
end)

RegisterNetEvent('yt_music:pos', function(pos)
    if current then current.pos = pos end
end)

-- /mutemusic : يكتم الصوت عندك انت بس
RegisterCommand(Config.Commands.mute, function()
    muted = not muted
    lastSent = -1
    TriggerEvent('chat:addMessage', { args = { '🎵', muted and 'تم كتم الصوت عندك' or 'رجع الصوت' } })
end, false)

RegisterNUICallback('ended', function(_, cb)
    TriggerServerEvent('yt_music:ended')
    cb('ok')
end)

RegisterNUICallback('error', function(data, cb)
    TriggerServerEvent('yt_music:error', data and data.code)
    cb('ok')
end)

-- اللي يدخل والصوت شغال يسمعه من نفس الثانية
CreateThread(function()
    Wait(3000)
    TriggerServerEvent('yt_music:sync')
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then nui({ type = 'stop' }) end
end)
