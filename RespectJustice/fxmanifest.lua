fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'RespectJustice'
description 'نظام وزارة العدل - نظام معلومات المواطنين، القضايا، البصمة، الخزائن، الأرشيف، التعويضات، ومركبات العدل'
author '2rayan'
version '5.1.0'

shared_scripts {
    '@RespectLib/init.lua',
    'modules/init.lua',
}

client_scripts {
    'client/cl_utils.lua',
    'client/cl_main.lua',
    'client/cl_reports.lua',
    'client/cl_panel.lua',
    'client/cl_jobs.lua',
    'client/cl_city.lua',
    'client/cl_events.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/sv_utils.lua',
    'server/server.lua',
    'server/sv_reports.lua',
    'server/sv_panel.lua',
    'server/sv_jobs.lua',
    'server/sv_city.lua',
}

files {
    'modules/config.lua',
    'modules/coords.lua',
}

dependencies {
    'RespectCore',
    'RespectLib',
    'RespectTarget',
    'oxmysql',
}

use_fxv2_oal 'yes'
