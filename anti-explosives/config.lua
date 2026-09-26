Config = {}

-- تحديد الفريم ورك تلقائياً: 'auto' | 'ox' | 'qb' | 'esx' | 'standalone'
Config.Framework = 'auto'

-- كل كم ملي ثانية يفحص حقائب اللاعبين (احتياط، الحذف الأساسي فوري عند الإضافة)
Config.ScanInterval = 2000

-- كل كم ملي ثانية يفحص الأسلحة اللي بيد اللاعب (كلاينت)
Config.ClientCheckInterval = 500

-- صلاحية تتخطى النظام (للإدارة): add_ace group.admin antiexplosives.bypass allow
Config.BypassAce = 'antiexplosives.bypass'

-- منع الانفجارات الناتجة من اللاعبين (حتى لو جاب السلاح بهكر)
Config.BlockExplosions = true

-- رسالة التحذير
Config.WarningMessage = '⚠️ تحذير: المتفجرات ممنوعة في السيرفر! تم حذف (%s) من حقيبتك.'
Config.ExplosionWarning = '⚠️ تحذير: استخدام المتفجرات ممنوع في السيرفر!'

-- رابط ويب هوك دسكورد للّوق (اتركه فاضي لو ما تبي)
Config.Webhook = ''

-- أسماء الأغراض/الأسلحة الممنوعة (بالحروف الصغيرة)
Config.BlockedItems = {
    -- آر بي جي وقاذفات
    'weapon_rpg', 'weapon_hominglauncher', 'weapon_grenadelauncher',
    'weapon_grenadelauncher_smoke', 'weapon_compactlauncher', 'weapon_emplauncher',
    'weapon_railgun', 'weapon_railgunxm3', 'weapon_firework',
    -- قرنيد وقنابل
    'weapon_grenade', 'weapon_stickybomb', 'weapon_pipebomb', 'weapon_proxmine',
    'weapon_molotov',
    -- ذخيرة المتفجرات
    'ammo-rocket', 'ammo-grenade', 'ammo-firework', 'ammo-emp', 'ammo-railgun',
    'rpg_ammo', 'grenade_ammo',
    -- أغراض متفجرة (C4 وغيرها)
    'c4', 'c4_bomb', 'weapon_c4', 'thermite', 'dynamite', 'explosive',
    'explosives', 'bomb', 'pipebomb', 'stickybomb', 'grenade', 'tnt',
}

-- أي غرض اسمه يحتوي على وحدة من هذي الكلمات ينحذف
Config.BlockedKeywords = {
    'rpg', 'grenade', 'bomb', 'c4', 'explosive', 'launcher',
    'dynamite', 'thermite', 'rocket', 'railgun', 'proxmine',
}

-- أغراض مستثناة حتى لو فيها كلمة ممنوعة
Config.Whitelist = {
    -- 'bath_bomb',
}

-- أنواع الانفجارات اللي تنمنع (من أسلحة اللاعبين)
-- 0 قرنيد | 1 قاذف قرنيد | 2 قنبلة لاصقة | 3 مولوتوف | 4 صاروخ RPG | 5 قذيفة دبابة
-- 25 قاذف مبرمج | 32 صاروخ طيارة | 36 ريل قن | 38 ألعاب نارية | 40 لغم | 43 قنبلة أنبوبية
Config.BlockedExplosionTypes = { 0, 1, 2, 3, 4, 5, 25, 32, 36, 38, 40, 43 }

-- ================== لا تعدل تحت ==================
local blockedSet, whiteSet = {}, {}
for _, n in ipairs(Config.BlockedItems) do blockedSet[n:lower()] = true end
for _, n in ipairs(Config.Whitelist) do whiteSet[n:lower()] = true end

function IsExplosive(name)
    if type(name) ~= 'string' then return false end
    name = name:lower()
    if whiteSet[name] then return false end
    if blockedSet[name] then return true end
    for _, kw in ipairs(Config.BlockedKeywords) do
        if name:find(kw, 1, true) then return true end
    end
    return false
end
