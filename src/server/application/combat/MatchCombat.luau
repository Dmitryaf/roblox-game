--!strict
-- Match authorization is shared by both public combat commands; ArrowService keeps ability ownership.
local MatchCombat = {}
function MatchCombat.new(combat: any, matches: any, tick: () -> (), attackReason: (number) -> string?)
	local function allowed(owner: number, life: number): string?
		tick()
		if combat.snapshot(owner).life ~= life then return "stale_life" end
		if not matches.canAct(owner) then return "paused" end
		return attackReason(owner)
	end
	return {
		snapshot = combat.snapshot,
		cast = function(owner: number, life: number, direction: Vector3, now: number): (boolean, string?)
			local reason = allowed(owner, life)
			if reason then return false, reason end
			return combat.cast(owner, life, direction, now)
		end,
		teleport = function(owner: number, life: number, castId: number, now: number): (boolean, string?)
			local reason = allowed(owner, life)
			if reason then return false, reason end
			return combat.teleport(owner, life, castId, now)
		end,
	}
end
return MatchCombat
