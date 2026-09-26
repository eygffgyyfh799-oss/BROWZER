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
        CompensationDailyMax = 3000000,  -- الحد الأقصى لمجموع تعويضات الموظف الواحد في اليوم
        CompensationMaxDistance = 5.0,   -- أقصى مسافة بين الموظف والمستفيد
        CompensationCooldown = 10,       -- ثواني الانتظار بين كل تعويض

        PersonalStash = { maxweight = 100000, slots = 100 },
        ArchiveStash  = { maxweight = 100000, slots = 200 },

        MaxSpawnedVehicles = 1,          -- عدد مركبات العدل المسموحة لكل موظف في نفس الوقت
        VehicleFuel = 75.0,

        -- ════════════════════════════════════════════════════════
        -- القضايا
        -- ════════════════════════════════════════════════════════
        CaseTypes = { 'مدنية', 'جنائية', 'مرورية', 'عقارية', 'تجارية', 'أسرية', 'عمالية', 'أخرى' },
        ReportTitleMax = 80,             -- الحد الأقصى لعنوان الدعوى
        ReportWitnessesMax = 200,        -- الحد الأقصى لخانة الشهود
        ReportEvidenceMax = 500,         -- الحد الأقصى لخانة الأدلة
        ReportNoteMax = 500,             -- الحد الأقصى لملاحظة الموظف على القضية

        -- ════════════════════════════════════════════════════════
        -- نظام معلومات المواطنين
        -- ════════════════════════════════════════════════════════
        Panel = {
            Command = 'justice',         -- أمر فتح النظام ('' لإلغاء الأمر)
            RequireDuty = true,          -- يجب أن يكون الموظف في الدوام

            -- 👑 رتبة المسؤول ورئيس المحكمة: هذي الرتبة وأعلى منها يكون عندها كل شيء متاح
            -- (مثل المدير بالضبط: كل الصلاحيات + سجل البصمة + الأرشيف)
            FullAccessGrade = 10,

            -- الصلاحيات: رقم = أقل رتبة مسموحة، 'boss' = المدير ورتبة FullAccessGrade فقط
            Permissions = {
                view = 0,                -- رؤية اللاعبين والبحث وملف المواطن
                reports = 0,             -- رؤية القضايا وتغيير حالتها وإضافة ملاحظات
                deleteReport = 'boss',   -- حذف القضايا
                locate = 'boss',         -- تحديد موقع المواطن الحالي
                withdraw = 'boss',       -- سحب أموال من بنك المواطن
                suspend = 'boss',        -- إيقاف / رفع إيقاف خدمات المواطن
                edit = 'boss',           -- تعديل بيانات المواطن
                logs = 'boss',           -- سجل العمليات
                compensation = 'boss',   -- تعويض مواطن (مبلغ يُضاف لحسابه)
                jobs = 'boss',           -- تغيير وظيفة ورتبة المواطن + التحكم بالقطاعات (توظيف، ترقية، فصل، دوام)

                -- نظام المدينة
                city = 0,                -- رؤية نظرة عامة على المدينة + سجل المركبات والعقارات
                summon = 0,              -- إرسال استدعاء للمحكمة
                vehicles = 'boss',       -- حجز / فك حجز / نقل ملكية مركبة
                properties = 'boss',     -- نقل ملكية عقار
                licenses = 'boss',       -- منح / سحب التراخيص
                gangs = 'boss',          -- تغيير / إزالة عصابة المواطن
                announce = 'boss',       -- إعلان لكل المدينة
                economy = 'boss',        -- اقتصاد المدينة وأغنى المواطنين
            },

            UnemployedJob = 'unemployed',   -- الوظيفة اللي يروح لها المواطن عند الفصل
            JobsBlacklist = {               -- قطاعات ممنوع التحكم فيها من النظام (مثال: 'admin')
                -- 'admin',
            },

            WithdrawMax = 5000000,       -- الحد الأقصى للسحب في العملية الواحدة
            WithdrawCooldown = 5,        -- ثواني الانتظار بين كل سحب
            LocateBlipTime = 60,         -- مدة بقاء علامة الموقع على الخريطة (ثانية)
            LogViews = true,             -- تسجيل كل مرة يتم فيها فتح ملف مواطن
            WebhookSkip = { view = true },  -- عمليات تنحفظ في السجل بس ما تنرسل لـ Discord (عشان ما يمتلي)

            -- إيداع المبالغ المسحوبة في حساب الوزارة (اختياري)
            -- مثال qb-management: resource = 'qb-management', func = 'AddMoney'
            -- مثال qb-banking:    resource = 'qb-banking',    func = 'AddMoney'
            Society = { enabled = false, resource = 'qb-management', func = 'AddMoney' },
        },

        -- نظام المدينة
        City = {
            ImpoundFee = 500,            -- رسوم فك الحجز اللي يدفعها المواطن في الحجز (إذا الكراج يدعمها)
            ImpoundGarage = 'impoundlot',-- اسم كراج الحجز
            AnnounceCooldown = 60,       -- ثواني بين كل إعلان
            AnnounceMaxLength = 250,
            SummonMaxLength = 200,
            NoGang = 'none',             -- اسم "بدون عصابة"
        },

        -- تنظيف تلقائي للسجلات القديمة (بالأيام، 0 = لا يحذف أبداً)
        Cleanup = {
            LogsDays = 120,              -- سجل العمليات
            DutyDays = 60,               -- سجل البصمة
            ClosedReportsDays = 0,       -- القضايا المغلقة
        },

        -- أسماء جداول قاعدة البيانات (غيّرها إذا كانت مختلفة في سيرفرك)
        Database = {
            Players = 'players',
            Vehicles = 'player_vehicles',
            Houses = { table = 'player_houses', owner = 'citizenid', label = 'house', id = 'id' },
        },

        Licenses = {
            driver = 'رخصة القيادة',
            weapon = 'رخصة السلاح',
            business = 'رخصة تجارية',
            id = 'الهوية',
            pilot = 'رخصة الطيران',
            hunting = 'رخصة الصيد',
        },
    },

    -- 📍 كل الإحداثيات صارت في ملف: modules/coords.lua

    -- 🧍 شكل البوتات
    Peds = {
        ['بوت القضايا'] = { model = 'cs_josh', animation = { 'anim@amb@nightclub@lazlow@ig1_vip@', 'clubvip_base_laz' } },
        ['بوت المركبات'] = { model = 'csb_trafficwarden', scenario = 'WORLD_HUMAN_AA_SMOKE' },
    },

    -- 🗺️ شكل علامة الخريطة
    Blip = { sprite = 176, colour = 0, scale = 0.45 },

    -- 🚗 مركبات العدل  (label = الاسم اللي يطلع بالقائمة، model = اسم الموديل)
    Vehicles = {
        { label = 'اودي', model = 'audi1' },
        { label = 'اكسبدشن', model = 'expxl22', windowTint = 3 },
        -- { label = 'بي ام', model = 'bmw251' },
    },

    -- حجم منطقة التفاعل حول كل إحداثية (بالمتر)
    ZoneSize = 2.5,
    -- true = يظهر لك مربع المنطقة داخل اللعبة (للتجربة فقط)
    DebugZones = false,
}
