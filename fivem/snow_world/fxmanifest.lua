fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'snow_world'
description 'Multiple separate worlds (snow, desert, night, horror...) with their own weather and time, portals, saved world per player, and isolated voice, radio, calls, chat, police alerts and scoreboard'

shared_script 'config.lua'

client_scripts {
    'client/main.lua',
    'client/portals.lua',
    'client/ui.lua',
}

server_scripts {
    'server/main.lua',
    'server/isolation.lua',
    'server/chat.lua',
    'server/scoreboard.lua',
    'server/portals.lua',
}

ui_page 'html/index.html'
files {
    'html/index.html',
}
