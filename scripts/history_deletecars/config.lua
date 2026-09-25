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

-- الصلاحية المطلوبة لأوامر الإدارة (ضيفها في server.cfg)
-- add_ace group.admin history.deletecars allow
Config.AdminAce = 'history.deletecars'

-- المسافة الافتراضية لأمر /dv (بالمتر)
Config.DefaultDvRadius = 5.0

Config.Prefix = '^3[HISTORY]^0 '
