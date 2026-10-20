--!strict
-- First playtest parameters; the server owns damage and the slow lease.
return table.freeze({ windup = 0.65, recovery = 0.6, cooldown = 8, range = 7,
    arcDegrees = 100, damage = 25, slowMultiplier = 0.6, slowDuration = 2 })
