--!strict
-- Experimental values only; these two open sites do not seal a route or touch a spawn.
return table.freeze({
    windup = 0.8, duration = 8, cooldown = 9, range = 30, pickRadius = 8,
    strikeRange = 7, strikeArcDegrees = 100,
    size = Vector3.new(12, 9, 2.5),
    slots = table.freeze({ Vector3.new(-22, 0, -28), Vector3.new(22, 0, 28) }),
})
