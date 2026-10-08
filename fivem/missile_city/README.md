# missile_city

سكربت FiveM يطيّح صاروخ ويحول المدينة لمدينة محروقة. **شكل فقط**: ما يضر أحد ولا يموت أي شخص ولا يخرب أي سيارة.

## التركيب
1. انسخ مجلد `missile_city` إلى `resources`.
2. أضف في `server.cfg`:
   ```cfg
   ensure missile_city
   add_ace group.admin command.missile allow
   add_ace group.admin command.resetcity allow
   ```

## الأوامر
| الأمر | الوظيفة |
|---|---|
| `/missile` | يطيح الصاروخ على مكانك وتحترق المدينة عند كل اللاعبين |
| `/resetcity` | يرجع المدينة طبيعية |

الإعدادات (المساحة، عدد النيران، الفلتر، الطقس) في `config.lua`.
