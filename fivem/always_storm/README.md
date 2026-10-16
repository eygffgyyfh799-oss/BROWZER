# always_storm

مطر وبرق دايم لكل اللاعبين، تلقائي بدون أي أمر.

## التركيب (مرة وحدة بس)
1. **احذف `always_snow`** (ما يشتغلون مع بعض).
2. حط مجلد `always_storm` داخل `resources\[assets]\[Swat]` وسوّ restart للسيرفر.

لو المجلد في مكان ثاني أضف في `server.cfg`: `ensure always_storm`

## بدون تعارض
- لو عندك qb-weathersync أو qbx_weathersync: يثبت المطر والبرق من السيرفر نفسه ويوقف تغيير الطقس التلقائي
- ما يوقف سكربت الطقس، يخليه هو نفسه يطبق المطر (qb-weathersync، qbx، vSync، Renewed-Weathersync)
- أي سكربت طقس ثاني: فحص خفيف يرجع المطر بس لو الجو تغير
- الوقت ما يتغير
- يوقف نفسه مؤقتاً لما تكون المدينة محروقة (missile_city) أو وقت فلم النووي، أو للي في العالم الثلجي (snow_world)

## الإعدادات (`config.lua`)
- `Weather`: `THUNDER` (مطر ورعد وبرق) أو `RAIN`
- `RainLevel`: قوة المطر
- `ExtraLightning` و `LightningEvery`: برق زيادة وكل كم ثانية
