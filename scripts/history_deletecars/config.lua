Config = {}

-- كل كم دقيقة يتم حذف السيارات الفاضية تلقائياً (0 = إيقاف الحذف التلقائي)
Config.IntervalMinutes = 30

-- التنبيهات قبل الحذف (بالثواني)
Config.Warnings = { 300, 60, 30, 10 }

-- لا تحذف السيارة إذا فيه لاعب قريب منها (بالمتر) - 0 = احذف كل شي
Config.SafeRadius = 0.0

-- موديلات ما تنحذف أبداً (سيارات الشرطة والإسعاف مثلاً)
Config.IgnoredModels = {
    'police', 'police2', 'police3', 'ambulance', 'firetruk',
}

-- لا تحذف السيارات المملوكة للاعبين (المسجلة في قاعدة البيانات)
Config.ProtectOwned = true

-- نوع الفريم ورك: 'custom' أو 'esx' أو 'qb' أو 'auto'
-- RespectCore: خله 'custom' وحط اسم جدول السيارات تحت
-- يحتاج oxmysql أو mysql-async
Config.Framework = 'custom'

-- اسم جدول السيارات المملوكة واسم عمود اللوحة (يُستخدم مع 'custom')
-- افتح قاعدة البيانات وتأكد من اسم الجدول اللي فيه سيارات اللاعبين
Config.OwnedTable = 'owned_vehicles'
Config.PlateColumn = 'plate'

-- لوحات ما تنحذف أبداً (غير المملوكة من قاعدة البيانات)
Config.ProtectedPlates = {
    -- 'ABC 123',
}

-- الصلاحية المطلوبة لأوامر الإدارة (ضيفها في server.cfg)
-- add_ace group.admin history.deletecars allow
Config.AdminAce = 'history.deletecars'

-- المسافة الافتراضية لأمر /dv (بالمتر)
Config.DefaultDvRadius = 5.0

Config.Prefix = '^3[HISTORY]^0 '
