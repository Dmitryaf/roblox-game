--!strict
-- Owns only cosmetic ground displaced along the replicated body path.
local DashRupture = {}
local SILVER = Color3.fromRGB(207, 224, 234)
local SPACING, MAX_CLUSTERS, MAX_PIECES = 1.8, 8, 80
type Piece = { part: Part, origin: Vector3, velocity: Vector3, rotation: CFrame, spin: Vector3,
	started: number, duration: number, stone: boolean, opacity: number }

function DashRupture.new(parent: Instance, character: Model, root: BasePart, direction: Vector3, id: number, quiet: boolean?)
	local folder = Instance.new("Folder")
	folder.Name, folder.Parent = "DashRupture_" .. id, parent
	local pieces: { Piece } = {}
	local params = RaycastParams.new()
	params.FilterType, params.FilterDescendantsInstances = Enum.RaycastFilterType.Exclude, { character, parent }
	params.RespectCanCollide = true
	local flat = direction * Vector3.new(1, 0, 1)
	local forward = if flat.Magnitude > 0.1 then flat.Unit else Vector3.new(0, 0, -1)
	local right = Vector3.new(-forward.Z, 0, forward.X)
	local lastPosition, clusters, serial = root.Position, 0, 0
	local started = workspace:GetServerTimeNow()
	local deadline = started + 1.2
	local finished, destroyed = false, false
	local effect = {}
	local function part(name: string, size: Vector3, position: Vector3, color: Color3, material: Enum.Material): Part
		local p = Instance.new("Part")
		p.Name, p.Size, p.CFrame, p.Color, p.Material = name, size, CFrame.new(position), color, material
		p.Anchored, p.Massless, p.CanCollide, p.CanTouch, p.CanQuery, p.CastShadow = true, true, false, false, false, false
		p.Parent = folder
		return p
	end
	local function surface(position: Vector3): (Vector3?, Color3, Enum.Material)
		local ignored: { Instance } = { character, parent }
		for _ = 1, 6 do
			params.FilterDescendantsInstances = ignored
			local hit = workspace:Raycast(position + Vector3.new(0, 2, 0), Vector3.new(0, -12, 0), params)
			if not hit then break end
			local target = hit.Instance:FindFirstAncestorOfClass("Model")
			while target and not target:FindFirstChildOfClass("Humanoid") do target = target:FindFirstAncestorOfClass("Model") end
			if target then table.insert(ignored, target); continue end
			-- Only characters are transparent to this cosmetic query; static walls still stop it.
			if hit.Normal.Y < 0.6 then break end
			local color = if hit.Instance:IsA("BasePart") then hit.Instance.Color else Color3.fromRGB(90, 86, 80)
			return hit.Position, color, hit.Material
		end
		return nil, Color3.fromRGB(90, 86, 80), Enum.Material.Slate
	end
	local function dust(position: Vector3, color: Color3, scale: number)
		local anchor = part("DashDustAnchor", Vector3.one * 0.1, position, color, Enum.Material.Slate)
		anchor.Transparency = 1
		local emitter = Instance.new("ParticleEmitter")
		emitter.Name, emitter.Texture = "DashGroundDust", "rbxasset://textures/warlock-art-v1/smoke.png"
		emitter.Color, emitter.Rate = ColorSequence.new(color:Lerp(Color3.fromRGB(179, 173, 159), 0.24)), 0
		emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7 * scale), NumberSequenceKeypoint.new(1, 1.7 * scale) })
		emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.72), NumberSequenceKeypoint.new(0.4, 0.84), NumberSequenceKeypoint.new(1, 1) })
		emitter.Lifetime, emitter.Speed = NumberRange.new(0.24, 0.48), NumberRange.new(1.8, 4.2)
		emitter.SpreadAngle, emitter.Acceleration = Vector2.new(65, 65), Vector3.new(0, -2, 0)
		emitter.LightInfluence, emitter.LightEmission, emitter.Parent = 0.85, 0.04, anchor
		emitter:Emit(math.ceil(4 * scale))
	end
	local function piece(p: Part, origin: Vector3, velocity: Vector3, at: number, duration: number, stone: boolean, opacity: number)
		serial += 1
		local seed = id * 0.7 + serial * 2.39
		local rotation = if stone then CFrame.Angles(math.sin(seed), seed, math.cos(seed))
			else CFrame.lookAt(Vector3.zero, forward).Rotation * CFrame.Angles(0, math.sin(seed) * 0.4, 0)
		table.insert(pieces, { part = p, origin = origin, velocity = velocity, started = at, duration = duration,
			rotation = rotation, spin = if stone then Vector3.new(2.2, 3.4, 1.8) * math.sin(seed) else Vector3.zero, stone = stone, opacity = opacity })
	end
	local function burst(position: Vector3, time: number, emphasis: number)
		local ground, color, material = surface(position)
		if not ground then return end
		for wave = 0, 1 do
			for _, side in { -1, 1 } do
				if #pieces >= MAX_PIECES then return end
				local size = (0.58 + (serial % 3) * 0.14) * emphasis
				local origin = ground + right * side * (1.15 + wave * 0.72) + forward * (wave * 0.25)
				local rock = part("DashGroundShard", Vector3.new(size, size * 0.7, size * 1.25), origin, color, material)
				rock.Transparency = 1
				local velocity = right * side * (4.4 + wave * 1.8) * emphasis + forward * 1.5 + Vector3.new(0, (5.5 + wave * 1.2) * emphasis, 0)
				piece(rock, origin, velocity, time + wave * 0.055, 0.58, true, 0)
				local crackOrigin = ground + right * side * (0.6 + wave * 0.65) + Vector3.new(0, 0.035, 0)
				local crack = part("DashGroundCrack", Vector3.new(0.095 * emphasis, 0.035, 1.4 * emphasis), crackOrigin, SILVER, Enum.Material.Neon)
				crack.Transparency = 1
				piece(crack, crackOrigin, Vector3.zero, time + wave * 0.035, 0.36, false, 0.35)
			end
		end
		for _, side in { -1, 1 } do dust(ground + right * side * 1.6 + Vector3.new(0, 0.15, 0), color, emphasis) end
	end
	function effect.finish(now: number)
		if destroyed or finished then return end
		finished = true
		burst(root.Position, now, 1.25)
		if not quiet then
			local anchor = part("DashBrakeAnchor", Vector3.one * 0.1, root.Position, SILVER, Enum.Material.Slate)
			anchor.Transparency = 1
			local sound = Instance.new("Sound")
			sound.Name, sound.SoundId, sound.Volume, sound.PlaybackSpeed = "WarriorDashBrake", "rbxasset://sounds/warrior-v1/impact.wav", 0.22, 0.9
			sound.RollOffMinDistance, sound.RollOffMaxDistance, sound.Parent = 8, 55, anchor
			sound:Play()
		end
		deadline = math.min(deadline, now + 0.72)
	end
	function effect.step(now: number, emitting: boolean): boolean
		if destroyed then return false end
		if now >= deadline then effect.destroy(); return false end
		if not finished and emitting then
			local current = root.Position
			local delta = (current - lastPosition) * Vector3.new(1, 0, 1)
			local distance = delta.Magnitude
			if distance > 0.01 then
				-- A correction or teleport is not a physical dash path to decorate.
				if distance > 24 then lastPosition = current
				else
					local count = math.min(MAX_CLUSTERS - clusters, math.floor(distance / SPACING))
					for index = 1, count do
						clusters += 1
						burst(lastPosition + delta.Unit * SPACING * index, now, 1)
					end
					if count > 0 then lastPosition += delta.Unit * SPACING * count end
				end
			end
		elseif not finished then effect.finish(now) end
		for _, item in pieces do
			if not item.part.Parent then continue end
			local age = now - item.started
			if age < 0 then item.part.Transparency = 1; continue end
			if age >= item.duration then item.part:Destroy(); continue end
			local fade = math.clamp((age / item.duration - 0.5) * 2, 0, 1)
			local point = item.origin
			if item.stone then point += item.velocity * age + Vector3.new(0, -13 * age * age, 0) end
			item.part.CFrame = CFrame.new(point) * item.rotation * CFrame.Angles(item.spin.X * age, item.spin.Y * age, item.spin.Z * age)
			item.part.Transparency = item.opacity + (1 - item.opacity) * fade
		end
		return true
	end
	function effect.destroy()
		if destroyed then return end
		destroyed = true
		folder:Destroy(); table.clear(pieces)
	end
	if not quiet then burst(lastPosition, started, 1.2) end
	return effect
end
return DashRupture
