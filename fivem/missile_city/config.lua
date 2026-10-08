Config = {}

-- أوامر التحكم (محمية بصلاحية ACE: command.missile و command.resetcity)
Config.MissileCommand = 'missile'
Config.ResetCommand = 'resetcity'

-- الصاروخ
Config.MissileHeight = 400.0      -- ارتفاع بداية سقوط الصاروخ فوق الهدف
Config.FallTime = 4000            -- مدة السقوط بالملي ثانية

-- المدينة المحروقة
Config.Radius = 300.0             -- نصف قطر منطقة النيران والدخان حول مكان السقوط
Config.FireCount = 45             -- عدد النيران (شكل فقط، ما تضر أحد)
Config.SmokeCount = 20            -- عدد أعمدة الدخان
Config.TimecycleModifier = 'REDMIST'  -- فلتر لون الجو المحروق
Config.TimecycleStrength = 0.55
Config.Weather = 'SMOG'           -- طقس دخاني
Config.Blackout = true            -- إطفاء أنوار المدينة
