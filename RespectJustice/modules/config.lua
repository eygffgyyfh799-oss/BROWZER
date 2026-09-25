return {
    -- ════════════════════════════════════════════════════════════
    -- الإعدادات العامة
    -- ════════════════════════════════════════════════════════════
    Settings = {
        Job = 'justice',                 -- اسم الوظيفة

        DutyCooldown = 15,               -- ثواني الانتظار بين كل بصمة
        DutyHistoryLimit = 100,          -- عدد سجلات البصمة المحفوظة في الذاكرة

        ReportFee = 200,                 -- رسوم تقديم الدعوى
        ReportMaxLength = 800,           -- الحد الأقصى لعدد أحرف الدعوى
        ReportMinLength = 10,            -- الحد الأدنى لعدد أحرف الدعوى
        ReportCooldown = 300,            -- ثواني الانتظار بين كل دعوى لنفس اللاعب

        CompensationMax = 1000000,       -- الحد الأقصى للتعويض في العملية الواحدة
        CompensationMinGrade = 0,        -- أقل رتبة مسموح لها بالتعويض (المدير مسموح دائماً)
        CompensationRequireDuty = true,  -- يجب أن يكون الموظف في الدوام
        CompensationMaxDistance = 5.0,   -- أقصى مسافة بين الموظف والمستفيد
        CompensationCooldown = 10,       -- ثواني الانتظار بين كل تعويض

        PersonalStash = { maxweight = 100000, slots = 100 },
        ArchiveStash  = { maxweight = 100000, slots = 200 },

        MaxSpawnedVehicles = 1,          -- عدد مركبات العدل المسموحة لكل موظف في نفس الوقت
        VehicleFuel = 75.0,
    },

    Locations = {
        {
            coords = vector4(-1579.48, 215.69, 74.34, 297.27),
            duty = {
                { coords = vector3(-1579.48, 215.69, 74.34), size = { 0.8, 1 }, heading = 340, debugPoly = false, minZ = 73.34, maxZ = 75.54 }
            },
            personal_stash = {
                { coords = vector3(-1579.48, 215.69, 74.34), size = { 1.8, 1 }, heading = 70,  debugPoly = false, minZ = 73.34, maxZ = 75.54 },
                { coords = vector3(248.71, -444.59, 48.09), size = { 3.0, 1 }, heading = 340, debugPoly = false, minZ = 47.09, maxZ = 50.49 },
                -- js1
                { coords = vector3(-1014.5, -425.37, 50.85), size = { 2.6, 0.8 }, heading = 296, debugPoly = false, minZ = 49.9, maxZ = 51.9 },
                { coords = vector3(-1018.21, -418.02, 50.85), size = { 2.6, 0.6 }, heading = 297, debugPoly = false, minZ = 49.85, maxZ = 52.05 },
                { coords = vector3(-997.15, -423.63, 50.83), size = { 0.6, 2.6 }, heading = 27, debugPoly = false, minZ = 49.83, maxZ = 52.03 },
                { coords = vector3(-1000.88, -416.29, 50.83), size = { 0.6, 2.6 }, heading = 27, debugPoly = false, minZ = 49.83, maxZ = 52.03 },
                { coords = vector3(-1015.69, -433.08, 50.85), size = { 2.6, 0.6 }, heading = 297, debugPoly = false, minZ = 49.85, maxZ = 52.05 },
                { coords = vector3(-1019.4, -425.76, 50.86), size = { 2.8, 0.6 }, heading = 296, debugPoly = false, minZ = 49.86, maxZ = 52.06 },
                { coords = vector3(-1033.11, -434.83, 50.87), size = { 2.8, 0.6 }, heading = 296, debugPoly = false, minZ = 49.86, maxZ = 52.06 },
                { coords = vector3(-1036.84, -427.59, 50.87), size = { 2.8, 0.6 }, heading = 297, debugPoly = false, minZ = 49.87, maxZ = 52.07 },
                { coords = vector3(-1013.04, -414.03, 58.33), size = { 2.8, 0.6 }, heading = 26, debugPoly = false, minZ = 57.33, maxZ = 59.53 },
                { coords = vector3(-1005.37, -428.99, 58.33), size = { 2.8, 0.6 }, heading = 26, debugPoly = false, minZ = 57.28, maxZ = 59.48 },
                { coords = vector3(-1020.97, -437.13, 58.33), size = { 2.8, 0.6 }, heading = 28, debugPoly = false, minZ = 57.33 , maxZ = 59.53 }
            },
            reports = {
                { pedModel = "cs_josh", coords = vector4(234.08, -422.77, 48.10, 248.29), animation = { 'anim@amb@nightclub@lazlow@ig1_vip@', 'clubvip_base_laz' } }
            },
            spawn_vehicles = {
                {
                    pedModel = "csb_trafficwarden",
                    coords = vector4(202.0, -379.4, 44.34, 340.0),
                    scenario = 'WORLD_HUMAN_AA_SMOKE',
                    vehSpawns = {
                        [1] = vector4(200.35, -370.84, 43.62, 335.0),
                        [2] = vector4(197.26, -378.55, 43.71, 340.0),
                    },
                    vehicles = {
                        [1] = {
                            vehLabel = "اودي",
                            vehName = "audi1"
                        },
                        [2] = {
                            vehLabel = "اكسبدشن",
                            vehName = "expxl22"
                        },
                        -- [3] = {
                        --     vehLabel = "بي ام",
                        --     vehName = "bmw251"
                        -- },
                    }
                }
            },
            reports_check = {
                { coords = vector3(193.86, -424.76, 47.33), size = { 2.8, 1 }, heading = 70, debugPoly = false, minZ = 46.33, maxZ = 47.73 }
            },
            blip = {
                show = true,
                sprite = 176,
                scale = 0.45,
                colour = 0,
                label = 'محكمة ريسبكت'
            }
        },
    },
}
