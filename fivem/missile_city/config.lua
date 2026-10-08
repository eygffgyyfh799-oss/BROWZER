Config = {}

-- أوامر التحكم (محمية بصلاحية ACE: command.missile و command.resetcity)
Config.MissileCommand = 'missile'
Config.ResetCommand = 'resetcity'

-- الصواريخ
Config.MissileCount = 6           -- عدد الصواريخ (الأول على مكانك والباقي حوله)
Config.MissileSpread = 180.0      -- مسافة انتشار الصواريخ الإضافية
Config.MissileDelay = 600         -- الفرق الزمني بين كل صاروخ (ملي ثانية)
Config.MissileHeight = 450.0      -- ارتفاع بداية السقوط
Config.FallTime = 3500            -- مدة السقوط (ملي ثانية)
Config.BlastScale = 3.0           -- حجم الانفجار الرئيسي
Config.SecondaryBlasts = 14       -- انفجارات صغيرة بعد كل صاروخ

-- المدينة المحروقة
-- المنطقة مقسمة مربعات، والنار تنرسم حولك وانت تمشي عشان تكون كثيفة في كل مكان
Config.Radius = 2500.0            -- نصف قطر المنطقة المحروقة (2500 = تقريباً المدينة كلها)
Config.CellSize = 50.0            -- حجم كل مربع
Config.StreamDistance = 160.0     -- المسافة اللي تنرسم فيها النار حولك
Config.FiresPerCell = 5           -- نيران في كل مربع
Config.BigFiresPerCell = 1        -- نيران كبيرة في كل مربع
Config.SmokePerCell = 1           -- أعمدة دخان في كل مربع
Config.FireScale = { 2.0, 4.5 }   -- أصغر وأكبر حجم للنار

-- الجو
Config.TimecycleModifier = 'REDMIST'
Config.TimecycleStrength = 0.75
Config.Weather = 'SMOG'
Config.Blackout = true
