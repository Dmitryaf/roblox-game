--!strict
-- One explicit combination; the two abilities retain their own lifecycle and cooldown.
local HandsTransferService = {}
function HandsTransferService.new(arrow: any, hands: any)
    local service = {}
    function service.transferHands(owner: number, life: number, castId: number, now: number): (boolean, string?)
        local projectile, reason = arrow.flying(owner, life, castId, now)
        if not projectile then return false, reason end
        local commit, placementReason = hands.planTransfer(owner, life, projectile.position, now)
        if not commit then return false, placementReason end
        -- Detach first so notifications/death callbacks cannot teleport/reuse this arrow.
        if not arrow.consume(owner, projectile, commit) then return false, "stale_arrow" end
        return true, nil
    end
    return service
end
return HandsTransferService
