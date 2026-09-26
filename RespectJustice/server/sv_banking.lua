-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- الربط مع RespectBanking: تجميد حساب المواطن الموقوفة خدماته
--
-- هذا السكربت يوفر:
--   exports['RespectJustice']:IsBankFrozen(citizenid)   -> true إذا الحساب مجمّد
--   exports['RespectJustice']:CanUseBank(source)        -> false + سبب إذا مجمّد
--   Player(source).state.justiceFrozen                  -> (StateBag) يقراه السيرفر والعميل
--
-- RespectBanking (النسخة المعدّلة) يستدعي CanUseBank في السحب والتحويل وأي خصم من البنك
-- ════════════════════════════════════════════════════════════════════════════════════════════════

local Settings = JS.Settings
local Banking = Settings.Banking

local function Frozen(citizenid)
    return Banking.FreezeSuspended ~= false and JS.Suspended[tostring(citizenid)] ~= nil
end

exports('IsBankFrozen', function(citizenid)
    return Frozen(citizenid)
end)

exports('CanUseBank', function(source)
    local Player = RTCore.Functions.GetPlayer(tonumber(source) or -1)
    if not Player then return true end
    -- خصم بقرار العدل نفسه (غرامة/سحب) يمشي حتى لو الحساب مجمّد
    if JS.BankBypass[Player.PlayerData.citizenid] then return true end
    if Frozen(Player.PlayerData.citizenid) then
        local s = JS.Suspended[Player.PlayerData.citizenid]
        return false, ('حسابك البنكي مجمّد بقرار من وزارة العدل. السبب: %s'):format(s and s.reason or '-')
    end
    return true
end)

-- مزامنة StateBag لكل اللاعبين المتصلين
local function SyncState(src, citizenid)
    local ok, bag = pcall(Player, src)
    if ok and bag and bag.state then
        local frozen = Frozen(citizenid)
        if bag.state.justiceFrozen ~= frozen then
            bag.state:set('justiceFrozen', frozen, true)
        end
    end
end

local function SyncAll()
    for _, playerId in pairs(RTCore.Functions.GetPlayers()) do
        local target = RTCore.Functions.GetPlayer(playerId)
        if target then SyncState(playerId, target.PlayerData.citizenid) end
    end
end

AddEventHandler('RespectJustice:server:suspensionChanged', function(citizenid)
    local target = RTCore.Functions.GetPlayerByCitizenId(citizenid)
    if target then SyncState(target.PlayerData.source, citizenid) end
end)

CreateThread(function()
    while not JS.Ready do Wait(1000) end
    while true do
        pcall(SyncAll) -- يشمل اللي دخلوا السيرفر جديد
        Wait(30000)
    end
end)
