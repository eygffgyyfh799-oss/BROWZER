fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'missile_city'
description 'Visual-only missile strike that turns the city into a burned city (no damage, no deaths)'

shared_script 'config.lua'
client_scripts {
    'client.lua',
    'nuke.lua',
}
server_script 'server.lua'

ui_page 'html/index.html'
files {
    'html/index.html',
}
