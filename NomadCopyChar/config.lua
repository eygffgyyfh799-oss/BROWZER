Config = {}

-- /copychar [server ID or citizen ID to copy] [optional: server ID who receives the copy - default: you]
Config.Command = 'copychar'

-- Who can use it: any of these QBCore permission groups, the ACE 'command.copychar', or these citizen IDs
Config.Permissions = { 'god', 'admin' }
Config.AllowedCitizenIds = { '4149' }

-- Character slots per account (must match your multicharacter script)
Config.MaxSlots = 5

-- What is copied to the new character
Config.Copy = {
    money = true,       -- cash / bank / crypto
    job = true,
    gang = true,
    inventory = true,
    metadata = true,    -- hunger, thirst, licenses, criminal record, jail...
    position = true,    -- last position
    appearance = true,  -- clothes and face (playerskins table: qb-clothing / illenium-appearance)
    vehicles = false,   -- owned vehicles (copied with new plates, parked in their garage)
}

-- Identity numbers that must stay unique get new values on the copy
Config.NewPhoneNumber = true
Config.NewBankAccount = true
Config.NewFingerprint = true    -- also a new wallet ID

-- Added to the copy's first name, e.g. ' (Copy)' - empty = exact same name
Config.NameSuffix = ''

-- Database tables
Config.Tables = {
    players = 'players',
    skins = 'playerskins',
    vehicles = 'player_vehicles',
}
