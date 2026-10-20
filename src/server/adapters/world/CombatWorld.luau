--!strict
local Players = game:GetService("Players")
local AreaWorld = require(script.Parent.AreaWorld)
local CombatWorld = {}
type Body = { character: Model, root: BasePart, humanoid: Humanoid, trusted: CFrame, at: number, budget: number, vertical: number, warned: boolean, baseSpeed: number, slow: number }

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
			trusted = root.CFrame, at = os.clock(), budget = 8, vertical = 10, warned = false, baseSpeed = humanoid.WalkSpeed, slow = 1 }
	end
	function world.remove(owner: number)
        local b = bodies[owner]
        if b then b.humanoid.WalkSpeed = b.baseSpeed end
        bodies[owner] = nil
    end
    function world.slow(target: Humanoid, multiplier: number)
        for _, b in bodies do
            if b.humanoid == target then
                b.slow = math.clamp(multiplier, 0.1, 1)
                b.humanoid.WalkSpeed = b.baseSpeed * b.slow
                b.budget = math.min(b.budget, 8 * b.slow)
                return
            end
        end
    end
	function world.alive(owner: number): boolean
		local b = bodies[owner]
		return b ~= nil and b.character.Parent ~= nil and b.root.Parent ~= nil and b.humanoid.Health > 0
	end

	function world.validate(owner: number): boolean
		local b = bodies[owner]
		if not b or not world.alive(owner) then return false end
		local now = os.clock()
		local dt = math.max(0, now - b.at)
		b.at = now
		b.budget = math.min(8 * b.slow, b.budget + 24 * b.slow * dt)
		b.vertical = math.min(12, b.vertical + 80 * dt)
		local delta = b.root.Position - b.trusted.Position
		local flat = Vector3.new(delta.X, 0, delta.Z).Magnitude
		local bounded = if policy then policy.contains(owner, b.root.Position) and policy.allowed(owner, b.root.Position) else inArena(b.root.Position)
		local valid = bounded and flat <= b.budget and math.abs(delta.Y) <= b.vertical
		if valid and delta.Magnitude > 0.05 then
			valid = workspace:Blockcast(b.trusted, Vector3.new(2, 3, 2), delta, params(b.character)) == nil
		end
		if not valid then
			if not b.warned then
				warn("Combat movement rejected", owner, "observed", b.root.Position, "trusted", b.trusted.Position, "budget", b.budget, b.vertical)
				b.warned = true
			end
			b.root.CFrame = b.trusted
			b.root.AssemblyLinearVelocity = Vector3.zero
			b.root.AssemblyAngularVelocity = Vector3.zero
			return false
		end
		b.warned = false
		b.budget -= flat
		b.vertical -= math.abs(delta.Y)
		b.trusted = b.root.CFrame
		if policy then policy.accepted(owner, b.trusted.Position) end
		return true
	end

	function world.origin(owner: number): Vector3?
		if not world.validate(owner) then return nil end
		if policy and not policy.castAllowed(owner) then return nil end
		return bodies[owner].trusted.Position + Vector3.new(0, 1, 0)
	end

	function world.sweep(owner: number, position: Vector3, delta: Vector3, radius: number): (Vector3?, Humanoid?)
		local b = bodies[owner]
		if not b then return position, nil end
		local p = params(b.character)
		p.RespectCanCollide = false -- Humanoid parts can be queryable without being collidable.
		local overlap = OverlapParams.new()
		overlap.FilterType = Enum.RaycastFilterType.Exclude
		overlap.FilterDescendantsInstances = { b.character }
		local initial = workspace:GetPartBoundsInRadius(position, radius, overlap)
		local hit = workspace:Spherecast(position, radius, delta, p)
		local barrier = if policy then policy.barrier(owner, position, delta) else nil
		if barrier and (not hit or (barrier - position).Magnitude <= (hit.Position - position).Magnitude) and #initial == 0 then
			return barrier, nil
		end
		local instance = if #initial > 0 then initial[1] else if hit then hit.Instance else nil
		if not instance then return nil, nil end
		local model = instance:FindFirstAncestorOfClass("Model")
		local humanoid = if model then model:FindFirstChildOfClass("Humanoid") else nil
		return if #initial > 0 then position else (hit :: RaycastResult).Position, humanoid
	end

	function world.damage(owner: number, target: Humanoid, amount: number)
		if not world.alive(owner) or target.Health <= 0 then return end
		local model = target.Parent
		if not model or not model:IsA("Model") or model == bodies[owner].character then return end
		if model:GetAttribute("TrainingTarget") then
			if policy and not policy.damageAllowed(owner, nil, target) then return end
			-- An inert target, not a bot. Reset before death so it remains usable.
			target.Health = if target.Health <= amount then target.MaxHealth else target.Health - amount
			return
		end
		local player = Players:GetPlayerFromCharacter(model)
		if policy and not policy.damageAllowed(owner, if player then player.UserId else nil, target) then return end
		if player and world.alive(player.UserId) and world.validate(player.UserId) then target:TakeDamage(amount) end
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
        local body = bodies[owner]
        body.root.CFrame = CFrame.lookAt(body.root.Position, body.root.Position + flat.Unit)
        body.trusted = body.root.CFrame
        return true
    end
	function world.position(owner: number): Vector3?
		local b = bodies[owner]
		return if b and world.alive(owner) then b.trusted.Position else nil
	end
	function world.place(owner: number, base: CFrame, frozen: boolean): boolean
		local b = bodies[owner]
		if not b or not world.alive(owner) then return false end
		local height = if b.humanoid.RigType == Enum.HumanoidRigType.R6 then 3 else b.humanoid.HipHeight + b.root.Size.Y / 2
		b.root.Anchored = frozen
		b.root.CFrame = base + Vector3.new(0, height + 0.2, 0)
		b.root.AssemblyLinearVelocity, b.root.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
		b.trusted, b.at, b.budget, b.vertical = b.root.CFrame, os.clock(), 8, 10
		b.humanoid.Health = b.humanoid.MaxHealth
        b.slow, b.humanoid.WalkSpeed = 1, b.baseSpeed
		return true
	end
	function world.freeze(owner: number, frozen: boolean)
		local b = bodies[owner]
		if b then b.root.Anchored = frozen; b.root.AssemblyLinearVelocity = Vector3.zero end
	end
	function world.step()
		for owner in bodies do world.validate(owner) end
	end
	local area = AreaWorld.new(world, policy)
	world.placement, world.areaTargets = area.placement, area.targets
	return world
end
return CombatWorld
