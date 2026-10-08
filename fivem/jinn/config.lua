Config = {}

Config.Command = 'jinn'           -- /jinn يحولك جني ويرجعك
Config.Ace = 'command.jinn'       -- الصلاحية المطلوبة

-- الأزرار الافتراضية (كل لاعب يقدر يغيرها من إعدادات اللعبة > Key Bindings > FiveM)
Config.Keys = {
    fly = 'X',        -- طيران
    blink = 'E',      -- انتقال سريع لقدام وسط دخان
    invisible = 'G',  -- اختفاء
    scream = 'H',     -- صرخة الجني
}

-- الشكل
Config.GhostAlpha = 140           -- شفافية الجني (0 مخفي - 255 طبيعي)
Config.InvisibleSelfAlpha = 60    -- كيف تشوف نفسك وانت مختفي (الباقين ما يشوفونك)
Config.GlowColor = { 255, 20, 0 } -- لون التوهج حول الجني
Config.FireEyes = true            -- عيون نار
Config.Timecycle = 'REDMIST'      -- فلتر الشاشة عند الجني نفسه
Config.TimecycleStrength = 0.35
Config.RenderDistance = 150.0     -- المسافة اللي يشوف فيها اللاعبين مؤثرات الجني

-- القدرات
Config.Invincible = true          -- الجني ما يتأذى
Config.FlySpeed = 0.6             -- سرعة الطيران
Config.FlyFastMultiplier = 4.0    -- سرعة الطيران مع Shift
Config.BlinkDistance = 25.0       -- مسافة الانتقال السريع
Config.BlinkCooldown = 1500       -- ملي ثانية
Config.ScreamRadius = 60.0        -- اللي داخل هالمسافة يحس بالصرخة (اهتزاز وفلتر فقط)
Config.ScreamCooldown = 5000
Config.FastRun = true             -- ركض أسرع

-- مكان العيون على عظمة الراس (لو طلعت النار بعيد عن العيون عدل هالأرقام)
Config.EyeOffset = { x = 0.04, y = 0.08, z = 0.033 }
Config.EyeScale = 0.12
