fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'carplay'
description 'CarPlay - تشغيل صوت مقاطع يوتيوب داخل السيارة مع صوت 3D وبوست ومفضلة وسجل واستكمال من آخر نقطة'
version '2.0.0'

shared_script 'config.lua'
client_script 'client.lua'
server_script 'server.lua'

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/script.js',
}
