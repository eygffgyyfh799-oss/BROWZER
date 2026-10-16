-- البوابات: دائرة على الأرض، ولما توقف عندها يطلع لك "اضغط E"
-- خفيف: يفحص كل ثانية، ويرسم بس لما تكون قريب

local blips = {}
local hintShown = false

local function myWorld()
    return LocalPlayer.state.world or 'main'
end

-- البوابة تشتغل هنا؟ (في العادي تدخلك، وفي عالمها ترجعك لو twoWay)
local function activeHere(p)
    local w = myWorld()
    return w == 'main' or (w == p.world and p.twoWay)
end

local function refreshBlips()
    for _, b in ipairs(blips) do RemoveBlip(b) end
    blips = {}
    for _, p in ipairs(GlobalState.worldPortals or {}) do
        if p.blip and activeHere(p) then
            local b = AddBlipForCoord(p.x, p.y, p.z)
            SetBlipSprite(b, 590)
            SetBlipColour(b, 3)
            SetBlipScale(b, 0.8)
            SetBlipAsShortRange(b, true)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName(p.blip)
            EndTextCommandSetBlipName(b)
            blips[#blips + 1] = b
        end
    end
end

AddStateBagChangeHandler('worldPortals', 'global', function() SetTimeout(100, refreshBlips) end)
AddStateBagChangeHandler('world', ('player:%d'):format(GetPlayerServerId(PlayerId())), function() SetTimeout(100, refreshBlips) end)

local function hint(text)
    if text then
        SendNUIMessage({ type = 'hint', text = text })
        hintShown = true
    elseif hintShown then
        SendNUIMessage({ type = 'hint', text = false })
        hintShown = false
    end
end

CreateThread(function()
    Wait(2000)
    refreshBlips()
    local c = Config.PortalMarkerColor

    while true do
        local near = {}
        local pos = GetEntityCoords(PlayerPedId())
        for _, p in ipairs(GlobalState.worldPortals or {}) do
            if activeHere(p) and #(pos - vector3(p.x, p.y, p.z)) < 40.0 then near[#near + 1] = p end
        end

        if #near == 0 then
            hint(false)
            Wait(1000)
        else
            -- قريب من بوابة: نرسم كل فريم لمدة ثانية
            local untilT = GetGameTimer() + 1000
            while GetGameTimer() < untilT do
                pos = GetEntityCoords(PlayerPedId())
                local inside = nil
                for _, p in ipairs(near) do
                    DrawMarker(1, p.x, p.y, p.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 2.5, 2.5, 1.2, c[1], c[2], c[3], 120, false, false, 2, false, nil, nil, false)
                    if #(pos - vector3(p.x, p.y, p.z)) < 2.0 then inside = p end
                end

                if inside then
                    local text = myWorld() == 'main' and ('اضغط E للدخول إلى ' .. inside.label) or 'اضغط E للرجوع إلى العالم العادي'
                    hint(text)
                    if IsControlJustPressed(0, Config.PortalKey) then
                        hint(false)
                        TriggerServerEvent('worlds:usePortal', inside.id)
                        Wait(1500)
                    end
                else
                    hint(false)
                end
                Wait(0)
            end
        end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, b in ipairs(blips) do RemoveBlip(b) end
end)
