Config = {}

-- الأوامر (للأدمن بس)
--   /music [رابط يوتيوب]   يشغل الصوت من مكانك ويمشي معك مثل السماعة
--   /musichere [رابط]      يشغله ثابت في مكانك (ما يمشي معك)
--   /musicstop             يوقفه
--   /musicvol [0-100]      قوة الصوت للكل
-- للاعبين:
--   /mutemusic             يكتم الصوت عنده هو بس (ويرجعه)
Config.Commands = {
    play = 'music',
    here = 'musichere',
    stop = 'musicstop',
    volume = 'musicvol',
    mute = 'mutemusic',
}

-- مين الأدمن (يكفي واحد منهم)
Config.AdminAces = { 'command', 'group.admin', 'admin', 'god', 'group.god' }
Config.QBPermissions = { 'admin', 'god' }
Config.ESXGroups = { 'admin', 'superadmin' }

-- الصوت
Config.Volume = 100          -- قوة الصوت (0 - 100)
Config.Range = 400.0         -- المسافة اللي يكون فيها الصوت قوي ويخف شوي شوي
Config.EveryoneHears = true  -- true = كل اللي في السيرفر يسمعونه حتى لو بعيدين
Config.FarVolume = 0.25      -- قوة الصوت للبعيدين (من قوة الصوت الأصلية) لو EveryoneHears
Config.Loop = false          -- يعيد المقطع لما يخلص
