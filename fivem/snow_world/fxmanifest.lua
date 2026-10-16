fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'snow_world'
description 'Multiple separate worlds (snow, desert, night, horror...) with their own weather and time and a light ruined look, locked membership by character ID stored in the database, and isolated voice, radio, calls, chat, police alerts and scoreboard'

shared_script 'config.lua'

client_scripts {
    'client/main.lua',
    'client/ruins.lua',
    'client/ui.lua',
}

server_scripts {
    'server/framework.lua',
    'server/database.lua',
    'server/main.lua',
    'server/isolation.lua',
    'server/chat.lua',
    'server/scoreboard.lua',
}

ui_page 'html/index.html'
files {
    'html/index.html',
}
