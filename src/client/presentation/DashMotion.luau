--!strict
-- Clip the server-created mover against its approved endpoint and the live local geometry.
-- This never starts a dash, creates physics, or replays a delayed server position.
local RunService = game:GetService("RunService")
local DashMotion = {}
type Motion = { mover: LinearVelocity, direction: Vector3, endpoint: Vector3, speed: number, stopped: boolean }

local function finite(value: any): boolean
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end
local function vector(value: any): boolean
	return typeof(value) == "Vector3" and finite(value.X) and finite(value.Y) and finite(value.Z)
end

function DashMotion.new(player: Player)
	local character: Model? = nil
	local root: BasePart? = nil
	local humanoid: Humanoid? = nil
	local motion: Motion? = nil
	local characterConnections: { RBXScriptConnection } = {}
	local bodyConnections: { RBXScriptConnection } = {}
	local stopped = false
	local function disconnect(connections: { RBXScriptConnection })
		for _, connection in connections do connection:Disconnect() end
		table.clear(connections)
	end
	local function running(): boolean
		return character ~= nil and player.Character == character and character.Parent ~= nil
			and root ~= nil and root.Parent == character and not root.Anchored
			and humanoid ~= nil and humanoid.Parent ~= nil and humanoid.Health > 0
	end
	local function normalVelocity()
		if not running() or not root or not humanoid then return end
		local walk = humanoid.MoveDirection * humanoid.WalkSpeed
		root.AssemblyLinearVelocity = Vector3.new(walk.X, root.AssemblyLinearVelocity.Y, walk.Z)
	end
	local function finish(restore: boolean)
		local current = motion
		motion = nil
		if not current then return end
		if current.mover.Parent then current.mover.Enabled = false end
		if restore then normalVelocity() end
	end
	local function adopt(child: Instance)
		if stopped or not character or character:GetAttribute("CombatClass") ~= "warrior"
			or not running() or not child:IsA("LinearVelocity") or child.Name ~= "WarriorDashVelocity"
			or child.Parent ~= root or not child.Enabled then return end
		local direction, origin = child:GetAttribute("DashDirection"), child:GetAttribute("DashOrigin")
		local distance, speed = child:GetAttribute("DashDistance"), child:GetAttribute("DashSpeed")
		if not vector(direction) or not vector(origin) or not finite(distance) or distance <= 0
			or not finite(speed) or speed <= 0 then return end
		local flat = (direction :: Vector3) * Vector3.new(1, 0, 1)
		if flat.Magnitude < 0.1 then return end
		finish(false)
		local endpoint = (origin :: Vector3) + flat.Unit * (distance :: number)
		local limit = child:GetAttribute("DashLimit")
		if vector(limit) and root then
			-- Start from the current simulated body, while staying inside the corridor
			-- already checked by the server. A delayed origin must not eat the dash.
			local allowed = math.min(distance :: number, ((limit :: Vector3) - root.Position):Dot(flat.Unit))
			endpoint = root.Position + flat.Unit * allowed
		end
		motion = { mover = child, direction = flat.Unit, endpoint = endpoint,
			speed = speed :: number, stopped = false }
	end
	local function bindBody()
		if not character then return end
		local nextRoot = character:FindFirstChild("HumanoidRootPart")
		local nextHumanoid = character:FindFirstChildOfClass("Humanoid")
		if nextRoot == root and nextHumanoid == humanoid then return end
		finish(false); disconnect(bodyConnections)
		root = if nextRoot and nextRoot:IsA("BasePart") then nextRoot else nil
		humanoid = nextHumanoid
		if not root or not humanoid then return end
		table.insert(bodyConnections, root.ChildAdded:Connect(adopt))
		table.insert(bodyConnections, root.ChildRemoved:Connect(function(child)
			if motion and child == motion.mover then finish(true) end
		end))
		table.insert(bodyConnections, humanoid.Died:Connect(function() finish(false) end))
		for _, child in root:GetChildren() do adopt(child) end
	end
	local function clearCharacter()
		finish(false); disconnect(bodyConnections); disconnect(characterConnections)
		character, root, humanoid = nil, nil, nil
	end
	local function bindCharacter(value: Model)
		clearCharacter()
		if stopped then return end
		character = value
		table.insert(characterConnections, value.ChildAdded:Connect(bindBody))
		table.insert(characterConnections, value.ChildRemoved:Connect(bindBody))
		for _, name in { "CombatLife", "CombatClass" } do
			table.insert(characterConnections, value:GetAttributeChangedSignal(name):Connect(function() finish(true) end))
		end
		bindBody()
	end
	local added = player.CharacterAdded:Connect(bindCharacter)
	local removing = player.CharacterRemoving:Connect(function(value)
		if value == character then clearCharacter() end
	end)
	if player.Character then bindCharacter(player.Character) end
	local simulation = RunService.PreSimulation:Connect(function(delta: number)
		local current = motion
		if not current or current.stopped then return end
		if not running() or not root or not character or not humanoid then finish(false); return end
		if current.mover.Parent ~= root then finish(true); return end
		if not current.mover.Enabled then finish(true); return end
		if not finite(delta) or delta <= 0 then return end
		local remaining = (current.endpoint - root.Position):Dot(current.direction)
		local clearance = remaining - 0.05
		if remaining > 0.08 then
			local params = RaycastParams.new()
			params.FilterType, params.FilterDescendantsInstances = Enum.RaycastFilterType.Exclude, { character }
			params.RespectCanCollide = true
			local hit = workspace:Blockcast(CFrame.new(root.Position), Vector3.new(3, 3.5, 3), current.direction * remaining, params)
			if hit then clearance = math.min(clearance, math.max(0, hit.Distance - 0.35)) end
		end
		if remaining <= 0.08 or clearance <= 0.08 then
			current.stopped = true
			current.mover.Enabled = false
			normalVelocity()
			return
		end
		local speed = math.min(current.speed, math.max(0, clearance / delta))
		local height = if humanoid.RigType == Enum.HumanoidRigType.R6 then 3 else humanoid.HipHeight + root.Size.Y / 2
		local front = root.Position + current.direction * (speed * delta + 1.5)
		local groundParams = RaycastParams.new()
		groundParams.FilterType, groundParams.FilterDescendantsInstances = Enum.RaycastFilterType.Exclude, { character }
		groundParams.RespectCanCollide = true
		local ground = workspace:Raycast(front + Vector3.new(0, 0.5, 0), Vector3.new(0, -height - 1.5, 0), groundParams)
		if not ground or ground.Normal.Y < 0.85 then
			current.stopped = true
			current.mover.Enabled = false
			normalVelocity()
			return
		end
		current.mover.PlaneVelocity = Vector2.new(current.direction.X, current.direction.Z) * speed
	end)
	return {
		destroy = function()
			if stopped then return end
			stopped = true
			finish(true); clearCharacter()
			added:Disconnect(); removing:Disconnect(); simulation:Disconnect()
		end,
	}
end
return DashMotion
