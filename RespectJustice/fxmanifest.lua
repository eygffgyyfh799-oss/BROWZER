fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'RespectJustice'
description 'نظام وزارة العدل - البصمة، الخزائن، الأرشيف، القضايا، التعويضات، ومركبات العدل'
author '2rayan'
version '2.0.0'

shared_scripts {
    '@RespectLib/init.lua',
    'modules/init.lua',
}

client_scripts {
    'client/*.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/*.lua',
}

files {
    'modules/config.lua',
}

dependencies {
    'RespectCore',
    'RespectLib',
    'RespectTarget',
    'oxmysql',
}

use_fxv2_oal 'yes'
