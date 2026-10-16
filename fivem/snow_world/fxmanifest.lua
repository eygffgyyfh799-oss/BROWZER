fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'snow_world'
description 'A separate snowy world: move players into their own routing bucket where only they see snow and each other'

shared_script 'config.lua'
client_script 'client.lua'
server_scripts {
    'isolation.lua',
    'server.lua',
}
