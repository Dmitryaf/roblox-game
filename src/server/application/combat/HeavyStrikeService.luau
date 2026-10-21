--!strict
-- A second explicit sword action; timing/hit rules stay owned by MeleeService.
local MeleeService = require(script.Parent.MeleeService)
local TimedSlow = require(script.Parent.TimedSlowService)
local HeavyStrikeService = {}
function HeavyStrikeService.new(ports: any, config: any)
    local slows = TimedSlow.new({ alive = ports.alive, token = ports.token,
        owner = ports.targetOwner, apply = ports.slow })
    local strike = MeleeService.new({ alive = ports.alive, origin = ports.origin, face = ports.face,
        targets = ports.targets, damage = ports.damage, impact = ports.impact, reaction = ports.reaction, emit = ports.emit,
        onStrike = ports.onStrike,
        onHit = function(owner, target, now) slows.hit(owner, target, config.slowMultiplier, config.slowDuration, now) end,
    }, config, "heavy")
    return {
        join = function(owner: number, life: number) slows.reset(owner); strike.join(owner, life) end,
        leave = function(owner: number) strike.leave(owner); slows.reset(owner) end,
        die = function(owner: number) strike.die(owner); slows.reset(owner) end,
        pause = function(owner: number, now: number) strike.pause(owner, now); slows.reset(owner) end,
        resume = strike.resume,
        step = function(now: number) strike.step(now); slows.step(now) end,
        destroy = function() strike.destroy(); slows.destroy() end,
        cast = strike.cast, snapshot = strike.snapshot,
    }
end
return HeavyStrikeService
