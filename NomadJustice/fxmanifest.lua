fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'NomadJustice'
description 'Nomad Justice - Department of Justice suite: citizen records, cases, duty clock, lockers, evidence archive, compensation and motor pool'
author '2rayan'
version '8.2.0'

shared_scripts {
    '@ox_lib/init.lua',
    'modules/init.lua',
}

client_scripts {
    'client/cl_utils.lua',
    'client/cl_main.lua',
    'client/cl_reports.lua',
    'client/cl_panel.lua',
    'client/cl_jobs.lua',
    'client/cl_city.lua',
    'client/cl_tablet.lua',
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
    'server/sv_court.lua',
    'server/sv_police.lua',
    'server/sv_finance.lua',
    'server/sv_undo.lua',
    'server/sv_diagnostics.lua',
}

ui_page 'html/index.html'

files {
    'modules/config.lua',
    'modules/coords.lua',
    'html/index.html',
    'html/style.css',
    'html/app.js',
    'html/charts.js',
    'html/vendor/d3.min.js',
}

dependencies {
    'qb-core',
    'ox_lib',
    'deep-target',
    'deep-Banking',
    'deep-inventory',
    'oxmysql',
}

use_fxv2_oal 'yes'
