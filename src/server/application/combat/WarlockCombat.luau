--!strict
-- One lifecycle entry for the two explicit abilities; each retains its own state/cooldown.
local WarlockCombat = {}
local HandsTransferService = require(script.Parent.HandsTransferService)
function WarlockCombat.new(arrow: any, hands: any)
    local transfer = HandsTransferService.new(arrow, hands)
    local function preparing(state: any, owner: number): boolean
        for _, active in state.active do
            if active.owner == owner and active.kind == "preparing" then return true end
        end
        return false
    end
    return {
        join = function(owner: number, life: number) arrow.join(owner, life); hands.join(owner, life) end,
        leave = function(owner: number) arrow.leave(owner); hands.leave(owner) end,
        die = function(owner: number) arrow.die(owner); hands.die(owner) end,
        pause = function(owner: number, now: number) arrow.pause(owner, now); hands.pause(owner, now) end,
        resume = function(owner: number, now: number) arrow.resume(owner, now); hands.resume(owner, now) end,
        step = function(now: number) arrow.step(now); hands.step(now) end,
        destroy = function() arrow.destroy(); hands.destroy() end,
        snapshot = arrow.snapshot, handsSnapshot = hands.snapshot, teleport = arrow.teleport,
        transferHands = transfer.transferHands,
        cast = function(owner: number, life: number, direction: Vector3, now: number, requestId: number?): (boolean, string?)
            if preparing(hands.snapshot(owner), owner) then return false, "busy" end
            return arrow.cast(owner, life, direction, now, requestId)
        end,
        castHands = function(owner: number, life: number, position: Vector3, now: number): (boolean, string?)
            if preparing(arrow.snapshot(owner), owner) then return false, "busy" end
            return hands.cast(owner, life, position, now)
        end,
    }
end
return WarlockCombat
