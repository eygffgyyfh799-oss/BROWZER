local weaponHashes = {}
for _, name in ipairs(Config.BlockedItems) do
    if name:sub(1, 7) == 'weapon_' then
        weaponHashes[#weaponHashes + 1] = { name = name, hash = joaat(name:upper()) }
    end
end

local bypass = false
RegisterNetEvent('anti-explosives:setBypass', function(state) bypass = state end)

-- حذف أي سلاح متفجر من يد اللاعب فوراً
CreateThread(function()
    while true do
        Wait(Config.ClientCheckInterval)
        if not bypass then
            local ped = PlayerPedId()
            for _, w in ipairs(weaponHashes) do
                if HasPedGotWeapon(ped, w.hash, false) then
                    RemoveWeaponFromPed(ped, w.hash)
                    SetCurrentPedWeapon(ped, `WEAPON_UNARMED`, true)
                    TriggerServerEvent('anti-explosives:weaponRemoved', w.name)
                end
            end
        end
    end
end)

RegisterNetEvent('anti-explosives:warn', function(msg)
    -- إشعار فوق الشاشة
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(msg)
    EndTextCommandThefeedPostTicker(true, true)
    -- رسالة بالشات
    TriggerEvent('chat:addMessage', { color = { 255, 60, 60 }, args = { 'الحماية', msg } })
    PlaySoundFrontend(-1, 'CHECKPOINT_MISSED', 'HUD_MINI_GAME_SOUNDSET', true)
end)
