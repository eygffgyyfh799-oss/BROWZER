fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'NomadCopyChar'
description 'Admin command that copies a character (data, money, job, inventory, appearance, vehicles) into a new character slot'
version '1.0.0'

shared_script 'config.lua'
client_script 'client.lua'
server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server.lua',
}

dependencies {
    'qb-core',
    'oxmysql',
}
