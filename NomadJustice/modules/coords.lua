-- ═══════════════════════════════════════════════════════════════════════════
--  📍 Coordinates - every location used by the script lives here
-- ═══════════════════════════════════════════════════════════════════════════
--
--  One line = one location:
--      name   = any name you like so you know what the place is
--      type   = location type (copy it exactly from the list below)
--      coords = vector4(X, Y, Z, heading)
--
--  Types:
--      'Duty'              Clock in / out + duty log for managers
--      'Stash'             Personal locker + evidence archive for managers
--      'Case Files'        List of filed cases (staff)
--      'Citizen Panel'     State Records (staff)
--      'Case Clerk'        Ped where citizens file lawsuits
--      'Motor Pool Clerk'  Ped where staff take out DOJ vehicles
--      'Vehicle Spawn'     Spot where the DOJ vehicle spawns
--      'Blip'              Map blip (the name is shown on the map)
--
--  • Add a location?      copy any line and change the numbers
--  • Remove a location?   delete the line or put -- in front of it
--  • Get your position?   type  /jcoords  in game and it is copied for you
--  • Same coordinates for several types (e.g. Stash + Case Files) = merged into one point
--  • Peds: the last number = the direction the ped faces (0 to 360)
-- ═══════════════════════════════════════════════════════════════════════════

return {

    -- ─────────────── Courthouse ───────────────
    { name = 'Courthouse Duty',            type = 'Duty',             coords = vector4(-1643.99, 174.14, 60.93, 300.72) },
    { name = 'Courthouse Locker',          type = 'Stash',            coords = vector4(-1577.84, 208.23, 64.66, 300.68) },
    { name = 'Courthouse Case Files',      type = 'Case Files',       coords = vector4(-1577.84, 208.23, 64.66, 300.68) },
    -- State Records opens with key 9 anywhere; enable this line if you also want a point for it:
    -- { name = 'Courthouse Citizen Panel', type = 'Citizen Panel',    coords = vector4(-1577.84, 208.23, 64.66, 300.68) },
    { name = 'Court Clerk',                type = 'Case Clerk',       coords = vector4(-1643.68, 177.25, 61.76, 0.0) },
    { name = 'Courthouse',                 type = 'Blip',             coords = vector4(-1579.48, 215.69, 74.34, 0.0) },

    -- ─────────────── DOJ Motor Pool ───────────────
    { name = 'Motor Pool Clerk',           type = 'Motor Pool Clerk', coords = vector4(202.0, -379.4, 44.34, 340.0) },
    { name = 'Vehicle Spawn 1',            type = 'Vehicle Spawn',    coords = vector4(200.35, -370.84, 43.62, 335.0) },
    { name = 'Vehicle Spawn 2',            type = 'Vehicle Spawn',    coords = vector4(197.26, -378.55, 43.71, 340.0) },

    -- ─────────────── Other lockers ───────────────
    { name = 'Locker 2',                   type = 'Stash',            coords = vector4(248.71, -444.59, 48.09, 340.0) },
    { name = 'Locker JS1 - 1',             type = 'Stash',            coords = vector4(-1014.5, -425.37, 50.85, 296.0) },
    { name = 'Locker JS1 - 2',             type = 'Stash',            coords = vector4(-1018.21, -418.02, 50.85, 297.0) },
    { name = 'Locker JS1 - 3',             type = 'Stash',            coords = vector4(-997.15, -423.63, 50.83, 27.0) },
    { name = 'Locker JS1 - 4',             type = 'Stash',            coords = vector4(-1000.88, -416.29, 50.83, 27.0) },
    { name = 'Locker JS1 - 5',             type = 'Stash',            coords = vector4(-1015.69, -433.08, 50.85, 297.0) },
    { name = 'Locker JS1 - 6',             type = 'Stash',            coords = vector4(-1019.4, -425.76, 50.86, 296.0) },
    { name = 'Locker JS1 - 7',             type = 'Stash',            coords = vector4(-1033.11, -434.83, 50.87, 296.0) },
    { name = 'Locker JS1 - 8',             type = 'Stash',            coords = vector4(-1036.84, -427.59, 50.87, 297.0) },
    { name = 'Locker JS1 - 9 (upstairs)',  type = 'Stash',            coords = vector4(-1013.04, -414.03, 58.33, 26.0) },
    { name = 'Locker JS1 - 10 (upstairs)', type = 'Stash',            coords = vector4(-1005.37, -428.99, 58.33, 26.0) },
    { name = 'Locker JS1 - 11 (upstairs)', type = 'Stash',            coords = vector4(-1020.97, -437.13, 58.33, 28.0) },

}
