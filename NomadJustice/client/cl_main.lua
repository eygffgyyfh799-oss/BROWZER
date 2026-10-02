local data = JC.Config
local Settings = JC.Settings
local JOB = JC.Job

local created_blips = {}
local created_zones = {}
local created_peds = {}
local Target = Settings.TargetResource or 'deep-target'

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- Helpers
-- ════════════════════════════════════════════════════════════════════════════════════════════════

local IsJustice = JC.IsJustice
local IsJusticeBoss = JC.IsBoss

local dutyCooldownEnd = 0
local function GetDutyCooldown()
    return math.max(0, math.ceil((dutyCooldownEnd - GetGameTimer()) / 1000))
end

-- Interaction zone around a point (ZoneSize box, 3 m tall)
local function AddZone(name, coords, options)
    local size = data.ZoneSize or 2.5
    exports[Target]:AddBoxZone(name, vector3(coords.x, coords.y, coords.z), size, size, {
        name = name,
        heading = coords.w or 0.0,
        debugPoly = data.DebugZones == true,
        minZ = coords.z - 1.5,
        maxZ = coords.z + 1.5,
    }, {
        options = options,
        distance = 2.0,
    })
    created_zones[#created_zones + 1] = name
end

local function SpawnPed(key, pedData, targetOptions)
    if not pedData or not pedData.coords then return end
    local model = type(pedData.model) == 'string' and joaat(pedData.model) or pedData.model
    pcall(lib.requestModel, model, 10000)
    if not HasModelLoaded(model) then
        return print(('^1[NomadJustice]^7 Failed to load ped model: %s'):format(tostring(pedData.model)))
    end

    local c = pedData.coords
    local ped = CreatePed(4, model, c.x, c.y, c.z - 1.0, c.w or 0.0, false, false)
    SetModelAsNoLongerNeeded(model)
    FreezeEntityPosition(ped, true)
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)

    if pedData.animation then
        lib.requestAnimDict(pedData.animation[1])
        TaskPlayAnim(ped, pedData.animation[1], pedData.animation[2], 8.0, 8.0, -1, 1, 0, false, false, false)
        RemoveAnimDict(pedData.animation[1])
    end

    if pedData.scenario then
        TaskStartScenarioInPlace(ped, pedData.scenario, 0, true)
    end

    exports[Target]:AddTargetEntity(ped, {
        options = targetOptions,
        distance = 2.5,
    })

    created_peds[key] = ped
end

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- Menus
-- ════════════════════════════════════════════════════════════════════════════════════════════════

local function OpenDutyHistory()
    QBCore.Functions.TriggerCallback('NomadJustice:server:getDutyHistory', function(playersHistory)
        if not playersHistory or not next(playersHistory) then
            return JC.Notify('No duty records yet', 'error', 5000)
        end

        local options = {}
        for _, history in ipairs(playersHistory) do
            options[#options + 1] = {
                title = history.name,
                description = ('%s - %s'):format(history.dutyStatus, history.timeFormated),
                icon = history.dutyStatus == 'Clocked in' and 'fas fa-right-to-bracket' or 'fas fa-right-from-bracket',
            }
        end

        lib.registerContext({
            id = 'justice_laptop_duty',
            title = 'Duty Log',
            options = options,
        })
        lib.showContext('justice_laptop_duty')
    end)
end

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- Create blips, zones and peds
-- ════════════════════════════════════════════════════════════════════════════════════════════════

-- Point types used in coords.lua
local TypeNames = {
    ['Duty'] = 'Duty', ['Stash'] = 'Stash', ['Case Files'] = 'ReportsView', ['Citizen Panel'] = 'CitizenPanel',
    ['Case Clerk'] = 'ReportPed', ['Motor Pool Clerk'] = 'VehiclePed', ['Vehicle Spawn'] = 'VehicleSpawn', ['Blip'] = 'Blip',
}

-- Group points by type: Points.Duty = { {name, coords, model}, ... }
local Points = {}
for i, entry in ipairs(JC.Coords) do
    local pointType = type(entry) == 'table' and TypeNames[entry.type]
    if not pointType or not entry.coords then
        print(('^1[NomadJustice]^7 coords.lua line %d: unknown type "%s" (%s)'):format(i, tostring(entry and entry.type), tostring(entry and entry.name)))
    else
        Points[pointType] = Points[pointType] or {}
        table.insert(Points[pointType], entry)
    end
end

local function create_blips()
    local style = data.Blip or {}
    for _, entry in ipairs(Points.Blip or {}) do
        local c = entry.coords
        local blip = AddBlipForCoord(c.x, c.y, c.z)
        SetBlipSprite(blip, entry.sprite or style.sprite or 176)
        SetBlipColour(blip, entry.colour or style.colour or 0)
        SetBlipAsShortRange(blip, true)
        SetBlipScale(blip, entry.scale or style.scale or 0.45)
        BeginTextCommandSetBlipName("STRING")
        AddTextComponentString(entry.name or 'Department of Justice')
        EndTextCommandSetBlipName(blip)
        created_blips[#created_blips + 1] = blip
    end
end

-- Options shown at each point type
local PointOptions = {
    Duty = {
        {
            icon = 'fas fa-clipboard',
            label = 'Clock In / Out',
            job = JOB,
            action = function()
                local remaining = GetDutyCooldown()
                if remaining > 0 then
                    return JC.Notify(('You must wait %s seconds'):format(remaining), 'error', 5000)
                end
                dutyCooldownEnd = GetGameTimer() + Settings.DutyCooldown * 1000
                -- Order matters: toggle duty first, then log the new state
                TriggerServerEvent('QBCore:ToggleDuty')
                TriggerServerEvent('NomadJustice:server:updateDutyHistory')
            end,
        },
        {
            icon = 'fas fa-laptop',
            label = 'Duty Log',
            job = JOB,
            canInteract = IsJusticeBoss,
            action = OpenDutyHistory,
        },
    },

    Stash = {
        {
            icon = 'fas fa-box',
            label = 'Personal Locker',
            job = JOB,
            action = function()
                TriggerServerEvent('NomadJustice:server:openStash', 'personal')
            end,
        },
        {
            icon = 'fas fa-box-archive',
            label = 'Evidence Archive',
            job = JOB,
            canInteract = IsJusticeBoss,
            action = function()
                local input = lib.inputDialog('Evidence Archive', {
                    { type = 'number', label = 'Archive citizen ID', required = true, min = 1 },
                })
                local archiveId = input and tonumber(input[1])
                if not archiveId or archiveId < 1 then return end
                archiveId = math.floor(archiveId)

                TriggerServerEvent('NomadJustice:server:openStash', 'archive', archiveId)
            end,
        },
    },

    ReportsView = {
        {
            icon = 'fas fa-scale-balanced',
            label = 'View Filed Cases',
            job = JOB,
            action = function()
                if Settings.Panel.UseTablet ~= false and JC.Tablet then return JC.Tablet.Open('reports') end
                JC.Reports.OpenList()
            end,
        },
    },

    CitizenPanel = {
        {
            icon = 'fas fa-address-card',
            label = 'State Records',
            job = JOB,
            action = function() JC.Panel.Open() end,
        },
    },
}

local PointOrder = { 'Duty', 'Stash', 'ReportsView', 'CitizenPanel' }

local function create_zones()
    -- Merge identical points into one zone so zones never overlap
    local zones, zoneOrder = {}, {}
    for _, pointType in ipairs(PointOrder) do
        for _, entry in ipairs(Points[pointType] or {}) do
            local coords = entry.coords
            local key = ('%.1f_%.1f_%.1f'):format(coords.x, coords.y, coords.z)
            if not zones[key] then
                zones[key] = { coords = coords, options = {} }
                zoneOrder[#zoneOrder + 1] = key
            end
            for _, option in ipairs(PointOptions[pointType]) do
                table.insert(zones[key].options, option)
            end
        end
    end

    for i, key in ipairs(zoneOrder) do
        AddZone('justice_point_' .. i, zones[key].coords, zones[key].options)
    end

    local spawns = {}
    for i, entry in ipairs(Points.VehicleSpawn or {}) do
        spawns[i] = entry.coords
    end

    -- Case clerk ped
    local reportPedOptions = {
        {
            icon = 'fa-solid fa-comment',
            label = 'Talk',
            action = function()
                -- Check for a phone only when lb-phone is running (otherwise filing is not blocked)
                if GetResourceState('lb-phone') == 'started' then
                    local ok, phoneNumber = pcall(function()
                        return exports['lb-phone']:GetEquippedPhoneNumber()
                    end)
                    if ok and not phoneNumber then
                        return JC.Notify('You need a phone number', 'error', 5000)
                    end
                end

                lib.registerContext({
                    id = 'justice_player_select_menu_reports',
                    title = 'Court Clerk',
                    options = {
                        {
                            title = 'File a Lawsuit',
                            icon = 'fas fa-file-signature',
                            description = ('Write and file a lawsuit with the Department of Justice. Filing fee: $%d'):format(Settings.ReportFee),
                            onSelect = JC.Reports.OpenSubmit,
                        },
                        {
                            title = 'Track My Lawsuits',
                            icon = 'fas fa-list-check',
                            description = 'Status of the lawsuits you filed',
                            onSelect = function() JC.Reports.OpenMine('justice_player_select_menu_reports') end,
                        },
                        {
                            title = 'My Summonses',
                            icon = 'fas fa-envelope',
                            description = 'Court summonses addressed to you',
                            onSelect = function() JC.City.OpenMySummons('justice_player_select_menu_reports') end,
                        },
                    },
                })
                lib.showContext('justice_player_select_menu_reports')
            end,
        },
    }

    -- Motor pool clerk ped
    local vehiclePedOptions = {
        {
            icon = 'fa-solid fa-car',
            label = 'Talk',
            job = JOB,
            canInteract = IsJustice,
            action = function()
                TriggerEvent('NomadJustice:client:spawnVehicleMenu', {
                    vehicles = data.Vehicles,
                    vehSpawns = spawns,
                })
            end,
        },
    }

    local peds = data.Peds or {}
    for i, entry in ipairs(Points.ReportPed or {}) do
        local look = peds['Case Clerk'] or {}
        SpawnPed('report_ped_' .. i, {
            coords = entry.coords,
            model = entry.model or look.model or 'cs_josh',
            animation = look.animation,
            scenario = look.scenario,
        }, reportPedOptions)
    end
    for i, entry in ipairs(Points.VehiclePed or {}) do
        local look = peds['Motor Pool Clerk'] or {}
        SpawnPed('vehicle_ped_' .. i, {
            coords = entry.coords,
            model = entry.model or look.model or 'csb_trafficwarden',
            animation = look.animation,
            scenario = look.scenario,
        }, vehiclePedOptions)
    end
end

local function cleanup()
    for _, ped in pairs(created_peds) do
        if DoesEntityExist(ped) then
            DeleteEntity(ped)
        end
    end
    created_peds = {}

    for _, blip in ipairs(created_blips) do
        if DoesBlipExist(blip) then
            RemoveBlip(blip)
        end
    end
    created_blips = {}

    for _, name in ipairs(created_zones) do
        pcall(function() exports[Target]:RemoveZone(name) end)
    end
    created_zones = {}
end

-- Each part on its own: one failing does not stop the rest
CreateThread(function()
    local ok, err = pcall(create_blips)
    if not ok then print('^1[NomadJustice]^7 create_blips: ' .. tostring(err)) end
    ok, err = pcall(create_zones)
    if not ok then print('^1[NomadJustice]^7 create_zones: ' .. tostring(err)) end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        cleanup()
    end
end)

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- /jcoords : copies your current position in the coords.lua format
-- ════════════════════════════════════════════════════════════════════════════════════════════════

RegisterCommand('jcoords', function()
    local ped = PlayerPedId()
    local c = GetEntityCoords(ped)
    local text = ('vector4(%.2f, %.2f, %.2f, %.2f)'):format(c.x, c.y, c.z, GetEntityHeading(ped))
    pcall(lib.setClipboard, text)
    print(text)
    JC.Notify('Coordinates copied: ' .. text, 'success', 10000)
end, false)

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- Fallback for inventories that open stashes from the client (older qb-inventory style)
RegisterNetEvent('NomadJustice:client:openStashLegacy', function(stashId, data)
    if type(stashId) ~= 'string' or not stashId:find('^justice_') then return end
    TriggerServerEvent('inventory:server:OpenInventory', 'stash', stashId, data)
    TriggerEvent('inventory:client:SetCurrentStash', stashId)
end)

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- Compensation
-- ════════════════════════════════════════════════════════════════════════════════════════════════

RegisterNetEvent('NomadJustice:client:giveMoney', function()
    if not IsJustice() then
        return JC.Notify('You must be a DOJ employee to use this', 'error', 5000)
    end

    local playerPed = PlayerPedId()
    local coords = GetEntityCoords(playerPed)
    local closestPlayer, closestDistance = nil, Settings.CompensationMaxDistance

    for _, player in ipairs(GetActivePlayers()) do
        local targetPed = GetPlayerPed(player)
        if targetPed ~= playerPed then
            local distance = #(coords - GetEntityCoords(targetPed))
            if distance < closestDistance then
                closestPlayer = player
                closestDistance = distance
            end
        end
    end

    local unlimited = JC.HasFullAccess()
    if not closestPlayer and not unlimited then
        return JC.Notify('Nobody nearby', 'error', 5000)
    end

    local input = lib.inputDialog('Compensation', {
        { type = 'input', label = 'Citizen ID', required = true, default = unlimited and not closestPlayer and QBCore.Functions.GetPlayerData().citizenid or nil },
        { type = 'number', label = 'Amount', required = true, min = 1, max = unlimited and Settings.CompensationHardCap or Settings.CompensationMax },
    })
    if not input then return end

    local citizenid = JUtil.Functions.trim(input[1])
    local amount = tonumber(input[2])
    if not citizenid or citizenid == '' or not amount or amount <= 0 then
        return JC.Notify('The data entered is invalid', 'error', 5000)
    end

    TriggerServerEvent('NomadJustice:server:giveMoneyToPlayer', citizenid, math.floor(amount))
end)
