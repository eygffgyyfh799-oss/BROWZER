Config = {}

-- ===================== الأدمن =====================
-- الأوامر لأي أدمن (يكفي واحد من هذول):
--   QBCore / Qbox : صلاحية admin أو god
--   ESX           : قروب admin أو superadmin
--   أو أي ACE من القائمة (group.admin من server.cfg أو txAdmin)
Config.Admin = {
    QBPermissions = { 'admin', 'god' },
    ESXGroups = { 'admin', 'superadmin' },
    Aces = { 'group.admin', 'admin', 'group.god', 'god', 'command' },
}

-- ===================== العوالم =====================
-- كل عالم منفصل بالكامل عن الباقي: لاعبين، سيارات، صوت، راديو، شات، بلاغات
-- bucket   : رقم العالم (لازم يكون مختلف لكل عالم، والعالم العادي = 0)
-- weather  : الطقس (XMAS, EXTRASUNNY, CLEAR, CLOUDS, SMOG, FOGGY, OVERCAST, RAIN, THUNDER, CLEARING, NEUTRAL, SNOW, BLIZZARD, SNOWLIGHT, HALLOWEEN)
-- time     : { ساعة, دقيقة } وقت ثابت للعالم، أو nil = نفس وقت السيرفر
-- blackout : true = أنوار المدينة طافية، false = شغالة، nil = نفس السيرفر
-- timecycle: فلتر لون للشاشة (اختياري)
-- snow     : true = آثار أقدام وكفرات وأصوات مشي على الثلج
-- population: ناس وسيارات NPC
-- ruins    : المدينة خربانة بشكل بسيط (سيارات محروقة، ركام، دخان) تطلع بس عند اللي في هذا العالم
Config.Worlds = {
    snow = {
        ruins = true,          -- المدينة خربانة بشكل بسيط
        label = '❄ العالم الثلجي',
        bucket = 777,
        weather = 'XMAS',
        snow = true,
        population = true,
    },
    desert = {
        ruins = true,          -- المدينة خربانة بشكل بسيط
        label = '🏜 العالم الرملي',
        bucket = 778,
        weather = 'EXTRASUNNY',
        time = { 13, 0 },
        timecycle = 'NG_filmic02',
        timecycleStrength = 0.6,
        population = true,
    },
    night = {
        ruins = true,          -- المدينة خربانة بشكل بسيط
        label = '🌙 عالم الليل',
        bucket = 779,
        weather = 'CLEAR',
        time = { 0, 0 },
        population = true,
    },
    horror = {
        ruins = true,          -- المدينة خربانة بشكل بسيط
        label = '👻 عالم الرعب',
        bucket = 780,
        weather = 'HALLOWEEN',
        time = { 0, 30 },
        blackout = true,
        timecycle = 'REDMIST',
        timecycleStrength = 0.25,
        population = false,
    },
}

-- ===================== الأوامر (للأدمن بس) =====================
-- كلها برقم الهوية (citizenid)، وتشتغل سواء اللاعب متصل أو مطفي
-- /setworld [رقم الهوية] [عالم]   يسجله في العالم ويقفل عليه (لو متصل ينتقل الحين)
-- /unsetworld [رقم الهوية]        يطلعه ويرجعه للعالم العادي
-- /worldlist [عالم]               مين مسجل (ومين متصل)
-- /checkworld [رقم الهوية]        وين مسجل
-- ما فيه أي طريقة ثانية للدخول أو الخروج
Config.Commands = {
    add = 'setworld',
    remove = 'unsetworld',
    list = 'worldlist',
    check = 'checkworld',
}

-- ===================== الفصل بين العوالم =====================
Config.Isolation = {
    Voice = true,        -- الصوت القريب (pma-voice)
    Radio = true,        -- موجات الراديو: نفس رقم الموجة بس كل عالم لحاله
    Calls = true,        -- مكالمات الجوال الصوتية (pma-voice)
    Chat = true,         -- رسائل الشات العادية توصل بس لنفس العالم
    ChannelOffset = 100000,
}

-- ===================== أوامر الشات =====================
-- كل أمر يوصل بس للي في نفس عالمك
-- لو عندك نفس الأمر في سكربت ثاني، حط هنا false أو غير الاسم عشان ما يصير تعارض
Config.ChatCommands = {
    me = 'me',          -- /me تسوي حركة، يشوفها اللي حولك
    ['do'] = 'do',      -- /do توصف شي، يشوفه اللي حولك
    ooc = 'ooc',        -- /ooc كلام خارج الرول، يشوفه كل اللي في عالمك
    ['911'] = '911',    -- /911 بلاغ للشرطة اللي في عالمك بس
}
Config.MeRange = 20.0
Config.ReportCooldown = 30       -- ثواني بين كل بلاغ 911 لنفس اللاعب
Config.ReportBlipTime = 120      -- ثواني يبقى مكان البلاغ على الخريطة

-- ===================== الشرطة =====================
-- يتعرف تلقائياً على QBCore و Qbox و ESX
Config.PoliceJobs = { 'police', 'sheriff', 'bcso', 'sasp', 'lspd', 'state' }

-- ===================== قائمة اللاعبين =====================
Config.Scoreboard = {
    Enabled = true,
    Key = 'HOME',        -- اضغط وثبت عشان تشوفها (يتغير من إعدادات FiveM)
    ShowPoliceCount = true,
}

-- ===================== شكل المدينة الخربانة =====================
-- كل شي هنا يطلع بس على شاشة اللاعبين اللي داخل العالم (أشياء محلية مو متزامنة)
-- العالم العادي والعوالم الثانية ما يتأثرون أبد، وما يتغير أي شي في المدينة الحقيقية
-- ينرسم حولك وانت تتحرك وينشال لما تبعد، عشان ما يثقل
Config.Ruins = {
    CellSize = 70.0,
    StreamDistance = 170.0,
    Wrecks = { 0, 2 },          -- سيارات محروقة في كل مربع (من - إلى)
    Debris = { 1, 3 },          -- ركام وزبالة في كل مربع
    SmokeChance = 0.35,         -- احتمال دخان في المربع
    FireChance = 0.08,          -- احتمال نار صغيرة في المربع
    Collision = true,           -- السيارات المحروقة والركام لها تصادم
    TrafficMultiplier = 0.5,    -- سيارات NPC أقل (1.0 = طبيعي)
    Models = {
        wrecks = {
            'prop_rub_carwreck_2', 'prop_rub_carwreck_3', 'prop_rub_carwreck_5',
            'prop_rub_carwreck_7', 'prop_rub_carwreck_8', 'prop_rub_carwreck_9',
            'prop_rub_carwreck_10', 'prop_rub_carwreck_11', 'prop_rub_carwreck_12',
            'prop_rub_carwreck_13', 'prop_rub_carwreck_14', 'prop_rub_carwreck_15',
        },
        debris = {
            'prop_rub_tyre_01', 'prop_rub_tyre_02', 'prop_rub_tyre_03',
            'prop_rub_binbag_01', 'prop_rub_binbag_03', 'prop_rub_binbag_04',
            'prop_rub_binbag_05', 'prop_rub_binbag_06', 'prop_rub_cardpile_01',
            'prop_rub_cardpile_03', 'prop_rub_pile_01', 'prop_rub_pile_02',
            'prop_rub_scrap_02', 'prop_rub_scrap_05', 'prop_rub_carpart_02',
            'prop_rub_carpart_03', 'prop_rub_trolley01a', 'prop_barrier_work05',
            'prop_mp_barrier_02b', 'prop_rub_planks_01',
        },
    },
}
