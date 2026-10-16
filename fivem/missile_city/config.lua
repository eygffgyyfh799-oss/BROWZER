Config = {}

-- ===================== الأوامر =====================
-- كلها محمية بصلاحية ACE: command.missile
--   /missile [عدد]      ضربة جديدة على مكانك (تمسح الضربة القديمة)
--   /addmissile [عدد]   زيادة صواريخ على مكانك بدون ما تمسح الحريق الموجود
--   /missilewp [عدد]    زيادة صواريخ على النقطة (Waypoint) في الخريطة
--   /missilerain [عدد]  مطر صواريخ عشوائي حولك
--   /resetcity          يرجع المدينة طبيعية
Config.Commands = {
    missile = 'missile',
    add = 'addmissile',
    waypoint = 'missilewp',
    rain = 'missilerain',
    reset = 'resetcity',
    nuke = 'nuke',
}
Config.Ace = 'command.missile'
Config.MaxPerCommand = 60         -- أكبر عدد صواريخ في الأمر الواحد

-- ===================== الصواريخ =====================
Config.DefaultCount = 8           -- العدد الافتراضي لـ /missile
Config.DefaultAddCount = 1        -- العدد الافتراضي لـ /addmissile و /missilewp
Config.DefaultRainCount = 25      -- العدد الافتراضي لـ /missilerain
Config.MissileSpread = 200.0      -- انتشار الصواريخ حول الهدف
Config.RainRadius = 700.0         -- مساحة مطر الصواريخ
Config.MissileDelay = 450         -- الفرق الزمني بين كل صاروخ (ملي ثانية)
Config.MissileHeight = 600.0      -- ارتفاع بداية السقوط
Config.FallTime = 3200            -- مدة السقوط (ملي ثانية)

-- ===================== الانفجار =====================
Config.BlastScale = 4.5           -- حجم الانفجار الرئيسي
Config.MushroomCloud = true       -- سحابة فطر نارية فوق كل صاروخ
Config.ShockwaveRing = true       -- حلقة انفجارات تتوسع من مكان السقوط
Config.SecondaryBlasts = 18       -- انفجارات صغيرة متتالية بعد كل صاروخ
Config.MaxPlumes = 40             -- حد أعمدة الدخان الضخمة (عشان ما يثقل الجهاز)

-- ===================== المدينة المحروقة =====================
-- المنطقة مقسمة مربعات، والنار تنرسم حولك وانت تتحرك عشان تكون كثيفة في كل مكان
Config.Radius = 2500.0            -- نصف قطر المنطقة المحروقة (2500 = تقريباً المدينة كلها)
Config.CellSize = 45.0            -- حجم كل مربع
Config.StreamDistance = 150.0     -- المسافة اللي تنرسم فيها النار حولك
Config.FiresPerCell = 5           -- نيران في كل مربع
Config.BigFiresPerCell = 2        -- نيران كبيرة في كل مربع
Config.SmokePerCell = 1           -- أعمدة دخان في كل مربع
Config.FireScale = { 2.5, 5.5 }   -- أصغر وأكبر حجم للنار

-- ===================== الجو =====================
Config.TimecycleModifier = 'REDMIST'
Config.TimecycleStrength = 0.85
Config.Weather = 'SMOG'
Config.Blackout = true

-- ===================== النووي (حلم) =====================
-- /nuke : فلم كامل لتفجير نووي يشوفه كل اللاعبين، وبالأخير يطلع حلم
-- وكل واحد يرجع مكانه كأن ما صار شي
Config.Nuke = {
    Target = nil,                 -- nil = مكان اللي كتب الأمر، أو مكان ثابت مثل vector3(-75.0, -818.0, 32.0)
    ClockHour = 19,               -- وقت المغرب في الحلم
    ClockMinute = 2,
    Volume = 0.8,                 -- صوت المؤثرات (صفارة، انفجار، طنين، قلب) من 0 إلى 1
    SlowMotion = true,            -- حركة بطيئة لحظة الانفجار

    MissileHeight = 1800.0,       -- الصاروخ يجي من بعيد بزاوية
    MissileDistance = 2600.0,
    FallTime = 6000,
    BlastScale = 14.0,
    MushroomHeight = 560.0,       -- ارتفاع سحابة الفطر
    CameraDistance = 1300.0,      -- بعد الكاميرا البعيدة عن الانفجار
    ShockwaveRadius = 1700.0,     -- إلى وين توصل موجة الصدمة
    ShockwaveSpeed = 230.0,       -- متر في الثانية (عشان تشوفها جاية)
    Cooldown = 150,               -- ثواني بين كل نووي

    Text = {
        stamp = 'لوس سانتوس — 7:02 مساءً',
        intro = 'كان مساء عادي... مثل كل يوم',
        easTitle = 'تنبيه طوارئ — EMERGENCY ALERT',
        easBody = 'تم رصد صاروخ باليستي متجه إلى لوس سانتوس.\nتوجهوا إلى أقرب ملجأ فوراً.\nهذه ليست تجربة.',
        easTicker = 'نظام الإنذار الوطني  •  ابقوا بعيداً عن النوافذ  •  لا تنظروا إلى الوميض  •  هذه ليست تجربة  •',
        alarm = 'باقي أقل من دقيقة...',
        after = 'في ثانية... راح كل شي',
        alone = '...',
        wake = 'كان مجرد حلم...',
    },
}
