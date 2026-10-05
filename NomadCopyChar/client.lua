CreateThread(function()
    TriggerEvent('chat:addSuggestion', '/' .. Config.Command, 'Copy a character into a new character slot (admin)', {
        { name = 'player', help = 'Server ID or citizen ID of the character to copy' },
        { name = 'owner', help = '(optional) Server ID of the player who receives the copy - default: you' },
    })
end)
