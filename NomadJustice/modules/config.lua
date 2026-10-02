return {
    -- ════════════════════════════════════════════════════════════
    -- General settings
    -- ════════════════════════════════════════════════════════════
    Settings = {
        Job = 'judge',                   -- Job name (Judicial Department)
        TargetResource = 'deep-target',  -- Target resource
        InventoryResource = 'deep-inventory', -- Inventory resource used for lockers and the evidence archive

        DutyCooldown = 15,               -- Seconds between duty clock punches
        DutyHistoryLimit = 100,          -- Duty records kept in memory

        ReportFee = 200,                 -- Lawsuit filing fee
        ReportMaxLength = 800,           -- Maximum lawsuit length (characters)
        ReportMinLength = 10,            -- Minimum lawsuit length (characters)
        ReportCooldown = 300,            -- Seconds between lawsuits for the same player

        CompensationMax = 1000000,       -- Maximum compensation per transaction
        CompensationDailyMax = 3000000,  -- Maximum total compensation per employee per day
        CompensationMaxDistance = 5.0,   -- Maximum distance between employee and recipient
        CompensationCooldown = 10,       -- Seconds between compensations
        -- Grades with the 'unlimitedCompensation' permission (Chief Justice + Supreme Court Justice) have no amount,
        -- daily or distance limits and may compensate themselves. Only a technical ceiling per transaction applies:
        CompensationHardCap = 2000000000,

        PersonalStash = { maxweight = 100000, slots = 100 },
        ArchiveStash  = { maxweight = 100000, slots = 200 },

        MaxSpawnedVehicles = 1,          -- Motor pool vehicles allowed per employee at once
        VehicleFuel = 75.0,

        -- ════════════════════════════════════════════════════════
        -- Cases
        -- ════════════════════════════════════════════════════════
        CaseTypes = { 'Civil', 'Criminal', 'Traffic', 'Real Estate', 'Commercial', 'Family', 'Labor', 'Other' },
        ReportTitleMax = 80,             -- Maximum case title length
        ReportWitnessesMax = 200,        -- Maximum witnesses field length
        ReportEvidenceMax = 500,         -- Maximum evidence field length
        ReportNoteMax = 500,             -- Maximum staff note length

        -- ════════════════════════════════════════════════════════
        -- State Records (tablet)
        -- ════════════════════════════════════════════════════════
        Panel = {
            Command = 'justice',         -- Command that opens the system ('' to disable)
            UseTablet = true,            -- true = tablet UI | false = legacy ox_lib menus
            Key = '9',                   -- Key that opens the tablet anywhere (players can rebind it in FiveM settings)
            TabletAnimation = true,      -- Tablet holding animation
            RequireDuty = true,          -- Employee must be on duty

            -- 👑 Full access: this grade and above get EVERYTHING in State Records -
            -- every DOJ permission, every police permission, every department's finances (Police, EMS...),
            -- duty log and evidence archive. 11 = Chief Justice, 12 = Supreme Court Justice
            FullAccessGrade = 11,

            -- Permissions:  number = this grade and above  |  'boss' = grades flagged isboss  |  false = locked
            -- Judicial Department grades:
            --   0 Trainee | 1 Court Clerk | 2 Lawyer | 3 Senior Lawyer | 4 Prosecutor | 5 Senior Prosecutor
            --   6 Public Defender | 7 Senior Public Defender | 8 Junior Judge | 9 Judge | 10 Senior Judge
            --   11 Chief Justice (everything) | 12 Supreme Court Justice (everything)
            Permissions = {
                view = 0,                -- View players, search and citizen records (everyone)
                reports = 0,             -- View cases, change status, add notes (everyone)
                deleteReport = 8,        -- Delete cases (Junior Judge and above)
                locate = 4,              -- Locate a citizen (Prosecutor and above)
                withdraw = 9,            -- Seize money from a citizen's bank (Judge and above)
                suspend = 9,             -- Suspend services (Judge and above)
                edit = 8,                -- Edit citizen identity (Junior Judge and above)
                logs = 8,                -- Audit log (Junior Judge and above)
                compensation = 9,        -- Compensate a citizen (Judge and above)
                unlimitedCompensation = 11, -- No limits + may compensate themselves (Chief Justice and Supreme Court Justice only)
                jobs = 11,               -- Change jobs and grades in every department (Chief Justice and above)

                -- City affairs
                city = 0,                -- Overview + vehicle and property registry (everyone)
                summon = 1,              -- Court summons (Court Clerk and above)
                vehicles = 9,            -- Impound / release / transfer vehicle title (Judge and above)
                properties = 9,          -- Transfer property deed (Judge and above)
                licenses = 1,            -- Grant / revoke licenses and bar license (Court Clerk and above)
                gangs = 9,               -- Change / remove a citizen's gang (Judge and above)
                announce = 8,            -- City-wide announcement (Junior Judge and above)
                economy = 8,             -- City economy and richest citizens (Junior Judge and above)

                -- Undo and delete
                undo = 11,               -- Undo any action (Chief Justice and above)
                delete = 11,             -- Delete records and summonses (Chief Justice and above)

                -- Judiciary
                verdicts = 8,            -- Issue verdicts (Junior Judge and above)
                warrants = 8,            -- Arrest and search warrants (Junior Judge and above)
                suspects = 4,            -- Add / remove persons of interest (Prosecutor and above)
                lawyers = 8,             -- Assign attorneys to cases (Junior Judge and above)
                policeRequests = 8,      -- Accept / reject police requests (Junior Judge and above)
                stats = 8,               -- Statistics (Junior Judge and above)
            },

            UnemployedJob = 'unemployed',   -- Job a citizen is moved to when terminated
            JobsBlacklist = {               -- Departments the system may not manage (e.g. 'admin')
                -- 'admin',
            },

            WithdrawMax = 5000000,       -- Maximum seizure per transaction
            WithdrawCooldown = 5,        -- Seconds between seizures
            LocateBlipTime = 60,         -- How long the locate blip stays on the map (seconds)
            LogViews = true,             -- Log every time a citizen record is opened
            WebhookSkip = { view = true, police_view = true },  -- Actions saved to the log but not sent to Discord (to avoid spam)

            -- Deposit seized money into the department account (optional)
            -- Example qb-management: resource = 'qb-management', func = 'AddMoney'
            -- Example deep-Banking:  resource = 'deep-Banking',  func = 'AddMoney'
            Society = { enabled = false, resource = 'qb-management', func = 'AddMoney' },

            -- 💰 Where money seized from citizens goes (seizures and fines)
            --   'officer' = to the account of the employee who seized it (bank)
            --   'society' = to the department account (Society above)
            --   'none'    = removed
            WithdrawTo = 'officer',
        },

        -- ════════════════════════════════════════════════════════
        -- 🚓 Police in State Records (limited permissions)
        -- ════════════════════════════════════════════════════════
        Police = {
            Jobs = { 'police' },         -- Police jobs (add 'sheriff' and others)
            RequireDuty = true,          -- Must be on duty
            -- Permissions: number = this grade and above | 'boss' = command staff (isboss) | false = locked
            -- Police grades:
            --   0 Cadet | 1 Solo Cadet | 2 Officer I | 3 Officer II | 4 Officer III | 5 Senior Officer | 6 Sergeant
            --   7 Staff Sergeant | 8 First Sergeant | 9 Lieutenant | 10 First Lieutenant | 11 Captain | 12 General
            --   13 Deputy Police Chief | 14 Police Chief | 15 Deputy Minister of Interior | 16 Minister of Interior
            Permissions = {
                search = 0,              -- Search citizens (everyone)
                profile = 0,             -- Basic info + case and verdict history (everyone)
                vehicles = 2,            -- Citizen vehicles (Officer I and above)
                warrants = 0,            -- View active warrants (everyone)
                executeWarrant = 3,      -- Log warrant execution (Officer II and above)
                suspects = 0,            -- View persons of interest (everyone)
                requests = 6,            -- Request authorization from DOJ: location, bank statement, warrant (Sergeant and above)
            },
            GrantMinutes = 30,           -- Authorization lifetime after approval (bank statement)
            RequestCooldown = 60,        -- Seconds between requests for the same officer
        },

        -- ════════════════════════════════════════════════════════
        -- 💰 Department finances (in State Records)
        -- Only the listed managers can see the department balance, withdraw and deposit
        -- ════════════════════════════════════════════════════════
        Finance = {
            RequireDuty = true,          -- Must be on duty
            MaxPerTransaction = 1000000, -- Maximum amount per transaction
            -- Where the department balance lives:
            --   'auto'     = detects the banking resource (Resource) automatically, otherwise uses an internal fund
            --   'qb'       = exports[Resource]:GetAccountBalance / AddMoney / RemoveMoney
            --   'renewed'  = exports[Resource]:getAccountMoney / addAccountMoney / removeAccountMoney
            --   'internal' = internal fund in the database (justice_sector_funds)
            Provider = 'auto',
            Resource = 'deep-Banking',
            Sectors = {
                -- job name = { label, grades allowed }
                police = { label = 'Police Department', managers = { 13, 14, 15, 16 } },   -- Deputy Police Chief, Police Chief, Deputy Minister, Minister of Interior
                ambulance = { label = 'EMS', managers = { 11, 12 } },                             -- Deputy EMS Chief, EMS Chief
            },
        },

        -- ════════════════════════════════════════════════════════
        -- ⚖️ Attorneys
        -- ════════════════════════════════════════════════════════
        Lawyers = {
            License = 'lawyer',          -- Bar license key (granted from the Licenses tab)
            Jobs = {},                   -- Or jobs treated as attorneys automatically, e.g. { 'lawyer' }
            DocumentMax = 2000,          -- Maximum document text length
        },

        -- ════════════════════════════════════════════════════════
        -- 🔨 Verdicts
        -- ════════════════════════════════════════════════════════
        Verdicts = {
            MaxFine = 10000000,          -- Maximum fine/damages per verdict
            MaxJail = 120,               -- Maximum jail time (months)
            JailEvent = '',              -- (optional) server event for your jail script: TriggerEvent(JailEvent, serverId, months, reason)
            WarrantHours = 72,           -- Warrant validity (hours)
        },

        -- City affairs
        City = {
            ImpoundFee = 500,            -- Impound release fee the citizen pays at the impound (if the garage supports it)
            ImpoundGarage = 'impoundlot',-- Impound garage name
            AnnounceCooldown = 60,       -- Seconds between announcements
            AnnounceMaxLength = 250,
            SummonMaxLength = 200,
            NoGang = 'none',             -- Name used for "no gang"
        },

        -- Automatic cleanup of old records (in days, 0 = never delete)
        Cleanup = {
            LogsDays = 120,              -- Audit log
            DutyDays = 60,               -- Duty log
            ClosedReportsDays = 0,       -- Closed cases
        },

        -- Database table names (change them if they differ on your server)
        Database = {
            Players = 'players',
            Vehicles = 'player_vehicles',
            Houses = { table = 'player_houses', owner = 'citizenid', label = 'house', id = 'id' },
        },

        Licenses = {
            lawyer = 'Bar License',
            driver = 'Driver License',
            weapon = 'Weapon License',
            business = 'Business License',
            id = 'State ID',
            pilot = 'Pilot License',
            hunting = 'Hunting License',
        },
    },

    -- 📍 All coordinates live in: modules/coords.lua

    -- 🧍 Ped appearance
    Peds = {
        ['Case Clerk'] = { model = 'cs_josh', animation = { 'anim@amb@nightclub@lazlow@ig1_vip@', 'clubvip_base_laz' } },
        ['Motor Pool Clerk'] = { model = 'csb_trafficwarden', scenario = 'WORLD_HUMAN_AA_SMOKE' },
    },

    -- 🗺️ Map blip style
    Blip = { sprite = 176, colour = 0, scale = 0.45 },

    -- 🚗 DOJ motor pool  (label = name shown in the menu, model = spawn name)
    Vehicles = {
        { label = 'Audi', model = 'audi1' },
        { label = 'Expedition', model = 'expxl22', windowTint = 3 },
        -- { label = 'BMW', model = 'bmw251' },
    },

    -- Interaction zone size around each point (meters)
    ZoneSize = 2.5,
    -- true = shows the zone box in game (testing only)
    DebugZones = false,
}
