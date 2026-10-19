--!strict
local CombatWorld = require(script.Parent.CombatWorld)
local MatchWorld = {}
local function inPad(team: number, p: Vector3): boolean
	return math.abs(p.X) < 22 and math.abs(p.Z - (if team == 1 then 118 else -118)) < 16
end
local function intersects(a: Vector3, delta: Vector3, low: Vector3, high: Vector3): number?
	local enter, leave = 0, 1
	for _, axis in { "X", "Y", "Z" } do
		local p, d, lo, hi = (a :: any)[axis], (delta :: any)[axis], (low :: any)[axis], (high :: any)[axis]
		if math.abs(d) < 0.00001 then
			if p < lo or p > hi then return nil end
		else
			local t1, t2 = (lo - p) / d, (hi - p) / d
			enter, leave = math.max(enter, math.min(t1, t2)), math.min(leave, math.max(t1, t2))
			if enter > leave then return nil end
		end
	end
	return enter
end
function MatchWorld.new(arena: any, context: (number) -> any, canAct: (number) -> boolean)
	local leftPad: { [number]: boolean } = {}
	local world: any
	local function contains(owner: number, p: Vector3): boolean
		if p.X ~= p.X or p.Y ~= p.Y or p.Z ~= p.Z or p.Y < 1 or p.Y > 30 then return false end
		local c = context(owner)
		return if c.mode == "match" then math.abs(p.X) < 93 and math.abs(p.Z) < 141
			else math.abs(p.X - 230) < 33 and math.abs(p.Z) < 69
	end
	local function allowed(owner: number, p: Vector3): boolean
		local c = context(owner)
		if c.mode ~= "match" then return true end
		local team = c.team
		return team ~= nil and not inPad(3 - team, p) and not (leftPad[owner] and inPad(team, p))
	end
	local function protected(owner: number): boolean
		local c, p = context(owner), world.position(owner)
		return c.team ~= nil and p ~= nil and inPad(c.team, p)
	end
	world = CombatWorld.new(nil, {
		contains = contains, allowed = allowed,
		accepted = function(owner, p)
			local c = context(owner)
			if c.team and not inPad(c.team, p) then leftPad[owner] = true end
		end,
		castAllowed = function(owner) return canAct(owner) and not protected(owner) end,
		damageAllowed = function(owner, targetOwner, target)
			if not canAct(owner) then return false end
			local source = context(owner)
			if not targetOwner then return source.mode == "training" and target.Parent ~= nil and target.Parent:GetAttribute("TrainingTarget") == true end
			local destination = context(targetOwner)
			return source.mode == "match" and destination.mode == "match" and canAct(targetOwner)
				and source.matchId == destination.matchId and source.team ~= destination.team
				and not protected(owner) and not protected(targetOwner)
		end,
		barrier = function(owner, position, delta)
			if context(owner).mode ~= "match" then return nil end
			local first: number? = nil
			for _, z in { -118, 118 } do
				local at = intersects(position, delta, Vector3.new(-23, -5, z - 17), Vector3.new(23, 35, z + 17))
				if at and (not first or at < first) then first = at end
			end
			return if first then position + delta * first else nil
		end,
	})
	function world.resetContext(owner: number, team: number?, frozen: boolean): boolean
		leftPad[owner] = nil
		return world.place(owner, arena.spawn(team, owner), frozen)
	end
	function world.attackReason(owner: number): string?
		return if protected(owner) then "spawn_protected" else nil
	end
	local removeBody = world.remove
	function world.remove(owner: number)
		leftPad[owner] = nil
		removeBody(owner)
	end
	function world.onZone(): { [number]: boolean }
		local result: { [number]: boolean } = {}
		-- Registered bodies are supplied by Players only; training never contributes.
		for _, player in game:GetService("Players"):GetPlayers() do
			local p = world.position(player.UserId)
			local c = context(player.UserId)
			if p and c.mode == "match" and not c.frozen and math.abs(p.X) <= 18 and math.abs(p.Z) <= 18 and p.Y <= 9 then
				result[player.UserId] = true
			end
		end
		return result
	end
	return world
end
return MatchWorld
