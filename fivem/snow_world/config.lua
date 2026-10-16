Config = {}

-- الصلاحية المطلوبة لأوامر الأدمن (نفس القديمة عشان ما تحتاج تغير server.cfg)
Config.Ace = 'command.snowworld'

-- ===================== العوالم =====================
-- كل عالم منفصل بالكامل عن الباقي: لاعبين، سيارات، صوت، راديو، شات، بلاغات
-- bucket   : رقم العالم (لازم يكون مختلف لكل عالم، والعالم العادي = 0)
-- weather  : الطقس (XMAS, EXTRASUNNY, CLEAR, CLOUDS, SMOG, FOGGY, OVERCAST, RAIN, THUNDER, CLEARING, NEUTRAL, SNOW, BLIZZARD, SNOWLIGHT, HALLOWEEN)
-- time     : { ساعة, دقيقة } وقت ثابت للعالم، أو nil = نفس وقت السيرفر
-- blackout : true = أنوار المدينة طافية، false = شغالة، nil = نفس السيرفر
-- timecycle: فلتر لون للشاشة (اختياري)
-- snow     : true = آثار أقدام وكفرات وأصوات مشي على الثلج
-- population: ناس وسيارات NPC
Config.Worlds = {
    snow = {
        label = '❄ العالم الثلجي',
        bucket = 777,
        weather = 'XMAS',
        snow = true,
        population = true,
    },
    desert = {
        label = '🏜 العالم الرملي',
        bucket = 778,
        weather = 'EXTRASUNNY',
        time = { 13, 0 },
        timecycle = 'NG_filmic02',
        timecycleStrength = 0.6,
        population = true,
    },
    night = {
        label = '🌙 عالم الليل',
        bucket = 779,
        weather = 'CLEAR',
        time = { 0, 0 },
        population = true,
    },
    horror = {
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

-- ===================== الأوامر =====================
-- /world [آيدي] [عالم]   ينقل لاعب لعالم (main = العالم العادي). مثال: /world 12 snow  أو  /world desert
-- /worlds                 قائمة العوالم ومين فيها
-- /worldall [عالم]        يرجع كل اللي في العالم (أو كل العوالم) للعالم العادي
-- /portal add [عالم]      يحط بوابة في مكانك  |  /portal del  يحذف أقرب بوابة  |  /portal list
-- /snow [آيدي] و /unsnow [آيدي]  مثل قبل
Config.Commands = {
    world = 'world',
    list = 'worlds',
    all = 'worldall',
    portal = 'portal',
    snow = 'snow',
    unsnow = 'unsnow',
}

-- ===================== الحفظ =====================
-- اللاعب يرجع لنفس عالمه لو طلع من السيرفر ورجع
Config.SaveWorld = true

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

-- ===================== البوابات =====================
-- بوابات ثابتة (غير اللي تحطها بأمر /portal وتنحفظ تلقائياً)
-- twoWay = true: نفس البوابة داخل العالم ترجعك للعالم العادي
-- ace = 'اسم صلاحية' لو تبي البوابة بس لناس معينين
Config.Portals = {
    -- { world = 'snow', coords = vector3(195.0, -933.0, 30.7), twoWay = true, blip = 'Snow World' },
}
Config.PortalKey = 38             -- E
Config.PortalCooldown = 5         -- ثواني
Config.PortalMarkerColor = { 120, 200, 255 }
