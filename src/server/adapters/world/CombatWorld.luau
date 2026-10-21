--!strict
local Players = game:GetService("Players")
local AreaWorld = require(script.Parent.AreaWorld)
local DashWorld = require(script.Parent.DashWorld)
local MovementSweep = require(script.Parent.MovementSweep)
local CombatWorld = {}
type Body = { character: Model, root: BasePart, humanoid: Humanoid, trusted: CFrame, at: number, budget: number, vertical: number, warned: boolean, baseSpeed: number, slow: number, slows: { [string]: number } }

export type Policy = {
	contains: (number, Vector3) -> boolean,
	allowed: (number, Vector3) -> boolean,
	accepted: (number, Vector3) -> (),
	castAllowed: (number) -> boolean,
	damageAllowed: (number, number?, Humanoid) -> boolean,
	barrier: (number, Vector3, Vector3) -> Vector3?,
}
function CombatWorld.new(spawns: { CFrame }?, policy: Policy?)
	local bodies: { [number]: Body } = {}
	local world = {}
	local dash = DashWorld.new(function(owner) return bodies[owner] end, function(owner, p)
		if policy then return policy.contains(owner, p) and policy.allowed(owner, p) end
		return math.abs(p.X) < 77 and math.abs(p.Z) < 77 and p.Y > 1 and p.Y < 24
	end, function(owner, p, delta) return if policy then policy.barrier(owner, p, delta) else nil end)
	local function params(character: Model): RaycastParams
		local p = RaycastParams.new()
		p.FilterType = Enum.RaycastFilterType.Exclude
		p.FilterDescendantsInstances = { character }
		p.RespectCanCollide = true
		return p
	end
	local function inArena(p: Vector3): boolean
		return p.X == p.X and p.Y == p.Y and p.Z == p.Z
			and math.abs(p.X) < 77 and math.abs(p.Z) < 77 and p.Y > 1 and p.Y < 24
	end

	function world.register(owner: number, character: Model, root: BasePart, humanoid: Humanoid, base: CFrame?)
		dash.stop(owner, "reset")
		-- CharacterAdded can expose a root at (0,0,0) before Roblox finishes spawning.
		-- Establish a valid server-owned initial position instead of trusting that transient frame.
		if base or (spawns and #spawns > 0) then
			local height = if humanoid.RigType == Enum.HumanoidRigType.R6 then 3 else humanoid.HipHeight + root.Size.Y / 2
			local spawn = base or (spawns :: { CFrame })[(math.abs(owner) % #(spawns :: { CFrame })) + 1]
			local destination = spawn + Vector3.new(0, height + 0.2, 0)
			character:PivotTo(destination * root.CFrame:Inverse() * character:GetPivot())
			root.AssemblyLinearVelocity = Vector3.zero
		end
		assert(if policy then policy.contains(owner, root.Position) else inArena(root.Position), "Character needs a valid server spawn before registration")
		bodies[owner] = { character = character, root = root, humanoid = humanoid,
            trusted = root.CFrame, at = os.clock(), budget = 8, vertical = 10, warned = false, baseSpeed = humanoid.WalkSpeed, slow = 1, slows = {} }
	end
	function world.remove(owner: number)
        dash.stop(owner, "removed")
        local b = bodies[owner]
        if b then b.humanoid.WalkSpeed = b.baseSpeed end
        bodies[owner] = nil
    end
    function world.slow(target: Humanoid, multiplier: number, source: string?)
        for _, b in bodies do
            if b.humanoid == target then
                local key = source or "hands"
                if multiplier < 1 then b.slows[key] = math.clamp(multiplier, 0.1, 1) else b.slows[key] = nil end
                local strongest = 1
                for _, amount in b.slows do strongest = math.min(strongest, amount) end
                b.slow = strongest
                b.humanoid.WalkSpeed = b.baseSpeed * strongest
                b.budget = math.min(b.budget, 8 * strongest)
                return
            end
        end
    end
    function world.targetOwner(target: Humanoid): number?
        for owner, b in bodies do if b.humanoid == target then return owner end end
        return nil
    end
    function world.slowToken(target: Humanoid): any
        local model = target.Parent
        if not model or not model:IsA("Model") or not model.Parent or target.Health <= 0 then return nil end
        for _, b in bodies do
            if b.humanoid == target and b.character == model then return model:GetAttribute("CombatLife") or model end
        end
        return if model:GetAttribute("TrainingTarget") == true then model else nil
    end

	function world.alive(owner: number): boolean
		local b = bodies[owner]
		return b ~= nil and b.character.Parent ~= nil and b.root.Parent ~= nil and b.humanoid.Health > 0
	end

	function world.validate(owner: number, source: string?): boolean
		local b = bodies[owner]
		if not b or not world.alive(owner) then return false end
		local now = os.clock()
		local dt = math.max(0, now - b.at)
		b.at = now
		b.budget = math.min(8 * b.slow, b.budget + 24 * b.slow * dt)
		b.vertical = math.min(12, b.vertical + 80 * dt)
		local delta = b.root.Position - b.trusted.Position
		local flat = Vector3.new(delta.X, 0, delta.Z)
		local bounded = if policy then policy.contains(owner, b.root.Position) and policy.allowed(owner, b.root.Position) else inArena(b.root.Position)
		local extra = dash.allowance(owner, delta)
		local normal = (flat - extra).Magnitude
		local valid = bounded and normal <= b.budget and math.abs(delta.Y) <= b.vertical
		local obstruction: RaycastResult? = nil
		if valid and delta.Magnitude > 0.05 then
			obstruction = MovementSweep.blocker(b.character, b.root, b.trusted, delta)
			valid = obstruction == nil
		end
		if not valid then
			dash.stop(owner, "invalid_position")
			local corrections = b.character:GetAttribute("CombatMovementCorrections")
			b.character:SetAttribute("CombatMovementCorrections", if type(corrections) == "number" then corrections + 1 else 1)
			if not b.warned then
				local reason = if not bounded then "bounds" else if normal > b.budget then "speed"
					else if math.abs(delta.Y) > b.vertical then "vertical" else "collision"
				warn("Combat movement rejected", owner, "reason", reason, "source", source or "query",
					"hit", if obstruction then obstruction.Instance:GetFullName() else "none",
					"observed", b.root.Position, "trusted", b.trusted.Position, "budget", b.budget, b.vertical)
				b.warned = true
			end
			b.root.CFrame = b.trusted
			b.root.AssemblyLinearVelocity = Vector3.zero
			b.root.AssemblyAngularVelocity = Vector3.zero
			return false
		end
		b.warned = false
		dash.consume(owner, extra.Magnitude)
		b.budget = math.max(0, b.budget - normal)
		b.vertical -= math.abs(delta.Y)
		b.trusted = b.root.CFrame
		if policy then policy.accepted(owner, b.trusted.Position) end
		return true
	end

	function world.origin(owner: number): Vector3?
		if not world.validate(owner, "origin") then return nil end
		if policy and not policy.castAllowed(owner) then return nil end
		return bodies[owner].trusted.Position + Vector3.new(0, 1, 0)
	end

	function world.sweep(owner: number, position: Vector3, delta: Vector3, radius: number): (Vector3?, Humanoid?, Instance?, number?)
		local b = bodies[owner]
		if not b then return position, nil, nil, 0 end
		local p = params(b.character)
		p.RespectCanCollide = false -- Humanoid parts can be queryable without being collidable.
		local overlap = OverlapParams.new()
		overlap.FilterType = Enum.RaycastFilterType.Exclude
		overlap.FilterDescendantsInstances = { b.character }
		local initial = workspace:GetPartBoundsInRadius(position, radius, overlap)
		local hit = workspace:Spherecast(position, radius, delta, p)
		local barrier = if policy then policy.barrier(owner, position, delta) else nil
		if barrier and (not hit or (barrier - position).Magnitude <= hit.Distance) and #initial == 0 then
			return barrier, nil, nil, (barrier - position).Magnitude
		end
		local instance = if #initial > 0 then initial[1] else if hit then hit.Instance else nil
		if not instance then return nil, nil, nil, nil end
		local model = instance:FindFirstAncestorOfClass("Model")
		local humanoid = if model then model:FindFirstChildOfClass("Humanoid") else nil
		return if #initial > 0 then position else (hit :: RaycastResult).Position, humanoid, instance,
			if #initial > 0 then 0 else (hit :: RaycastResult).Distance
	end

	function world.damage(owner: number, target: Humanoid, amount: number): boolean
		if not world.alive(owner) or target.Health <= 0 then return false end
		local model = target.Parent
		if not model or not model:IsA("Model") or model == bodies[owner].character then return false end
		if model:GetAttribute("TrainingTarget") then
			if policy and not policy.damageAllowed(owner, nil, target) then return false end
			-- An inert target, not a bot. Reset before death so it remains usable.
			target.Health = if target.Health <= amount then target.MaxHealth else target.Health - amount
			return true
		end
		local player = Players:GetPlayerFromCharacter(model)
		if policy and not policy.damageAllowed(owner, if player then player.UserId else nil, target) then return false end
		if player and world.alive(player.UserId) and world.validate(player.UserId, "damage") then
			local health = target.Health
			target:TakeDamage(amount)
			return target.Health < health
		end
		return false
	end

	function world.landing(owner: number, position: Vector3, direction: Vector3): Vector3?
		if not world.validate(owner) then return nil end
		local b = bodies[owner]
		local candidate = position - direction * 3
		local p = params(b.character)
		local ground = workspace:Raycast(candidate + Vector3.new(0, 2, 0), Vector3.new(0, -12, 0), p)
		if not ground or ground.Normal.Y < 0.85 or ground.Instance:FindFirstAncestorOfClass("Model") then return nil end
		local height = b.humanoid.HipHeight + b.root.Size.Y / 2
		if b.humanoid.RigType == Enum.HumanoidRigType.R6 then height = 3 end
		local destination = ground.Position + Vector3.new(0, height + 0.2, 0)
		if policy then
			if not policy.contains(owner, destination) or not policy.allowed(owner, destination) then return nil end
		elseif not inArena(destination) then return nil end
		-- Conservative avatar envelope: accept only supported, empty, reachable space.
		local size = Vector3.new(4, math.max(5, height * 2 - 0.2), 4)
		local overlap = OverlapParams.new()
		overlap.FilterType = Enum.RaycastFilterType.Exclude
		overlap.FilterDescendantsInstances = { b.character }
		for _, part in workspace:GetPartBoundsInBox(CFrame.new(destination), size, overlap) do
			if part.CanCollide or part:FindFirstAncestorOfClass("Model") then return nil end
		end
		local delta = destination - b.trusted.Position
		if policy and policy.barrier(owner, b.trusted.Position, delta) then return nil end
		if delta.Magnitude > 0.05 and workspace:Blockcast(b.trusted, Vector3.new(4, 4, 4), delta, p) then return nil end
		return destination
	end

	function world.move(owner: number, destination: Vector3)
		dash.stop(owner, "moved")
		local b = bodies[owner]
		b.root.CFrame = CFrame.new(destination) * b.root.CFrame.Rotation
		b.root.AssemblyLinearVelocity = Vector3.zero
		b.root.AssemblyAngularVelocity = Vector3.zero
		b.trusted, b.at = b.root.CFrame, os.clock()
		if policy then policy.accepted(owner, destination) end
	end
    function world.face(owner: number, direction: Vector3): boolean
        if not world.validate(owner) then return false end
        local flat = direction * Vector3.new(1, 0, 1)
        if flat.Magnitude < 0.1 then return false end
        -- Approval only. A server CFrame write replays its delayed position to the running owner.
        -- Direction still defines the authoritative hit arc; the owner animates its facing locally.
        return true
    end
	function world.position(owner: number): Vector3?
		local b = bodies[owner]
		return if b and world.alive(owner) then b.trusted.Position else nil
	end
	function world.place(owner: number, base: CFrame, frozen: boolean): boolean
		dash.stop(owner, "reset")
		local b = bodies[owner]
		if not b or not world.alive(owner) then return false end
		local height = if b.humanoid.RigType == Enum.HumanoidRigType.R6 then 3 else b.humanoid.HipHeight + b.root.Size.Y / 2
		b.root.Anchored = frozen
		b.root.CFrame = base + Vector3.new(0, height + 0.2, 0)
		b.root.AssemblyLinearVelocity, b.root.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
		b.trusted, b.at, b.budget, b.vertical = b.root.CFrame, os.clock(), 8, 10
		b.humanoid.Health = b.humanoid.MaxHealth
        b.slow, b.humanoid.WalkSpeed, b.slows = 1, b.baseSpeed, {}
		return true
	end
	function world.freeze(owner: number, frozen: boolean)
		if frozen then dash.stop(owner, "paused") end
		local b = bodies[owner]
		if b then b.root.Anchored = frozen; b.root.AssemblyLinearVelocity = Vector3.zero end
	end
	function world.step()
		for owner, b in bodies do
            -- Dead targets cannot retain a movement actuator contribution until respawn.
            if b.humanoid.Health <= 0 and b.slow ~= 1 then
                b.slow, b.slows, b.humanoid.WalkSpeed = 1, {}, b.baseSpeed
            end
            world.validate(owner, "heartbeat")
        end
	end
	local area = AreaWorld.new(world, policy)
	world.placement, world.areaTargets = area.placement, area.targets
	function world.startDash(owner: number, direction: Vector3, distance: number, duration: number, requestId: number?): (Vector3?, number?, string?)
		if not world.origin(owner) then return nil, nil, "invalid_position" end
		return dash.start(owner, direction, distance, duration, requestId)
	end
	world.stopDash = dash.stop
	return world
end
return CombatWorld
