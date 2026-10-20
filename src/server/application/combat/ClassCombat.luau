--!strict
-- Explicit class authorization and lifecycle; no ability registry or dynamic dispatch.
local ClassCombat = {}
function ClassCombat.new(warlock: any, melee: any, selected: (number) -> string, dash: any, heavy: any?)
    return {
        join = function(owner: number, life: number) warlock.join(owner, life); melee.join(owner, life); dash.join(owner, life); if heavy then heavy.join(owner, life) end end,
        leave = function(owner: number) warlock.leave(owner); melee.leave(owner); dash.leave(owner); if heavy then heavy.leave(owner) end end,
        die = function(owner: number) warlock.die(owner); melee.die(owner); dash.die(owner); if heavy then heavy.die(owner) end end,
        pause = function(owner: number, now: number) warlock.pause(owner, now); melee.pause(owner, now); dash.pause(owner, now); if heavy then heavy.pause(owner, now) end end,
        resume = function(owner: number, now: number) warlock.resume(owner, now); melee.resume(owner, now); dash.resume(owner, now); if heavy then heavy.resume(owner, now) end end,
        step = function(now: number) warlock.step(now); melee.step(now); dash.step(now); if heavy then heavy.step(now) end end,
        destroy = function() warlock.destroy(); melee.destroy(); dash.destroy(); if heavy then heavy.destroy() end end,
        snapshot = warlock.snapshot, handsSnapshot = warlock.handsSnapshot, meleeSnapshot = melee.snapshot,
        dashSnapshot = dash.snapshot,
        heavySnapshot = if heavy then heavy.snapshot else nil,
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
            dash.step(now)
            for _, active in dash.snapshot(owner).active do
                if active.owner == owner then return false, "busy" end
            end
            if heavy then
                heavy.step(now)
                for _, active in heavy.snapshot(owner).active do
                    if active.owner == owner then return false, "busy" end
                end
            end
            return melee.cast(owner, life, direction, now)
        end,
        heavyStrike = function(owner: number, life: number, direction: Vector3, now: number): (boolean, string?)
            if selected(owner) ~= "warrior" then return false, "wrong_class" end
            if not heavy then return false, "not_ready" end
            melee.step(now); dash.step(now)
            for _, active in melee.snapshot(owner).active do
                if active.owner == owner then return false, "busy" end
            end
            for _, active in dash.snapshot(owner).active do
                if active.owner == owner then return false, "busy" end
            end
            return heavy.cast(owner, life, direction, now)
        end,
        dash = function(owner: number, life: number, direction: Vector3, now: number): (boolean, string?)
            if selected(owner) ~= "warrior" then return false, "wrong_class" end
            melee.step(now)
            for _, active in melee.snapshot(owner).active do
                if active.owner == owner then return false, "busy" end
            end
            if heavy then
                heavy.step(now)
                for _, active in heavy.snapshot(owner).active do
                    if active.owner == owner then return false, "busy" end
                end
            end
            return dash.cast(owner, life, direction, now)
        end,
    }
end
return ClassCombat
