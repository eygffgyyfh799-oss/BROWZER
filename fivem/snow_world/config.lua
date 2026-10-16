Config = {}

-- الأوامر (محمية بصلاحية ACE: command.snowworld)
--   /snow [آيدي]     ينقل اللاعب للعالم الثلجي (بدون آيدي = انت)
--   /unsnow [آيدي]   يرجع اللاعب للعالم العادي (بدون آيدي = انت)
--   /snowlist        يعرض مين داخل العالم الثلجي
--   /unsnowall       يرجع الكل للعالم العادي
Config.Commands = {
    enter = 'snow',
    leave = 'unsnow',
    list = 'snowlist',
    leaveAll = 'unsnowall',
}
Config.Ace = 'command.snowworld'

-- رقم العالم (Routing Bucket). العالم العادي = 0
Config.Bucket = 777

-- فيه ناس وسيارات NPC في العالم الثلجي؟
Config.Population = true

-- شكل العالم الثلجي
Config.Weather = 'XMAS'           -- ثلج يطيح وأرض بيضا
Config.FootTracks = true          -- آثار أقدام وكفرات على الثلج
Config.Timecycle = nil            -- فلتر إضافي اختياري، مثال: 'NG_filmic02'
Config.TimecycleStrength = 0.3

Config.EnterText = '❄ انتقلت إلى العالم الثلجي'
Config.LeaveText = 'رجعت إلى العالم العادي'
