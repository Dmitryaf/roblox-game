--!strict
-- Explicit class authorization and lifecycle; no ability registry or dynamic dispatch.
local ClassCombat = {}
function ClassCombat.new(warlock: any, melee: any, selected: (number) -> string)
    return {
        join = function(owner: number, life: number) warlock.join(owner, life); melee.join(owner, life) end,
        leave = function(owner: number) warlock.leave(owner); melee.leave(owner) end,
        die = function(owner: number) warlock.die(owner); melee.die(owner) end,
        pause = function(owner: number, now: number) warlock.pause(owner, now); melee.pause(owner, now) end,
        resume = function(owner: number, now: number) warlock.resume(owner, now); melee.resume(owner, now) end,
        step = function(now: number) warlock.step(now); melee.step(now) end,
        destroy = function() warlock.destroy(); melee.destroy() end,
        snapshot = warlock.snapshot, handsSnapshot = warlock.handsSnapshot, meleeSnapshot = melee.snapshot,
        cast = function(owner: number, life: number, direction: Vector3, now: number): (boolean, string?)
            if selected(owner) ~= "warlock" then return false, "wrong_class" end
            return warlock.cast(owner, life, direction, now)
        end,
        teleport = function(owner: number, life: number, castId: number, now: number): (boolean, string?)
            if selected(owner) ~= "warlock" then return false, "wrong_class" end
            return warlock.teleport(owner, life, castId, now)
        end,
        castHands = function(owner: number, life: number, position: Vector3, now: number): (boolean, string?)
            if selected(owner) ~= "warlock" then return false, "wrong_class" end
            return warlock.castHands(owner, life, position, now)
        end,
        swing = function(owner: number, life: number, direction: Vector3, now: number): (boolean, string?)
            if selected(owner) ~= "warrior" then return false, "wrong_class" end
            return melee.cast(owner, life, direction, now)
        end,
    }
end
return ClassCombat
