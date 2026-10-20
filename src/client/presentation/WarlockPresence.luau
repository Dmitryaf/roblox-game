--!strict
local WarlockPresence = {}
local SMOKE = "rbxasset://textures/warlock-art-v1/smoke.png"
local FLAME = "rbxasset://textures/warlock-art-v1/flame.png"
type Mark = { part: BasePart, at: number }

function WarlockPresence.new(character: Model, parent: Instance): any
	local root = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not root or not root:IsA("BasePart") or not humanoid then return nil end
	local attachment = Instance.new("Attachment")
	attachment.Name = "WarlockAura"
	attachment.Parent = root
	-- Emit outside the robe: a single low emitter was hidden inside its opaque silhouette.
	local veils: { ParticleEmitter } = {}
	for index, offset in { Vector3.new(-0.95, 0.6, 0), Vector3.new(0.95, 0.6, 0), Vector3.new(0, -0.5, 0.65) } do
		local source = Instance.new("Attachment")
		source.Name, source.Position, source.Parent = "VeilWisp", offset, attachment
		local aura = Instance.new("ParticleEmitter")
		aura.Name, aura.Texture = "DemonicVeil", SMOKE
		aura.Color = ColorSequence.new(Color3.fromRGB(153, 83, 191), Color3.fromRGB(64, 37, 91))
		aura.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.18, 0.38), NumberSequenceKeypoint.new(0.65, 0.58), NumberSequenceKeypoint.new(1, 1) })
		aura.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(0.5, 1.85), NumberSequenceKeypoint.new(1, 2.55) })
		aura.Rate, aura.Lifetime = 4, NumberRange.new(0.6, 0.95)
		aura.Speed, aura.Drag = NumberRange.new(0.3, 0.7), 1.2
		aura.SpreadAngle = Vector2.new(55, 55)
		aura.Rotation, aura.RotSpeed = NumberRange.new(0, 360), NumberRange.new(-45, 45)
		aura.Acceleration = Vector3.new(if index == 1 then -0.4 elseif index == 2 then 0.4 else 0, 1.2, 0)
		aura.LightEmission, aura.LightInfluence = 0.6, 0.15
		aura.Parent = source
		table.insert(veils, aura)
	end
	local marks: { Mark } = {}
	local lastMark, lastPosition, foot = 0, root.Position, -1
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local function mark(now: number)
		local point = root.Position + root.CFrame.RightVector * (foot * 0.3)
		local hit = workspace:Raycast(point, Vector3.new(0, -6, 0), params)
		if not hit or hit.Normal.Y < 0.65 then return end
		foot = -foot
		local p = Instance.new("Part")
		p.Name, p.Size = "BriefFelFootprint", Vector3.new(0.27, 0.018, 0.62)
		p.Anchored, p.Massless = true, true
		p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = false, false, false, false
		p.Color, p.Material, p.Transparency = Color3.fromRGB(29, 95, 51), Enum.Material.Neon, 0.62
		local forward = root.CFrame.LookVector * Vector3.new(1, 0, 1)
		p.CFrame = CFrame.lookAt(hit.Position + Vector3.new(0, 0.025, 0), hit.Position + forward + Vector3.new(0, 0.025, 0))
		p.Parent = parent
		local flame = Instance.new("ParticleEmitter")
		flame.Name, flame.Texture = "DyingFelFlame", FLAME
		flame.Color = ColorSequence.new(Color3.fromRGB(48, 135, 70), Color3.fromRGB(17, 50, 35))
		flame.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.42), NumberSequenceKeypoint.new(0.35, 0.52), NumberSequenceKeypoint.new(1, 1) })
		flame.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(0.45, 0.55), NumberSequenceKeypoint.new(1, 0) })
		flame.Rate, flame.Lifetime, flame.Speed = 0, NumberRange.new(0.22, 0.42), NumberRange.new(0.6, 1.2)
		flame.Acceleration, flame.SpreadAngle = Vector3.new(0, 2, 0), Vector2.new(18, 18)
		flame.LightEmission, flame.LightInfluence = 0.35, 0.4
		flame.Parent = p
		flame:Emit(3)
		table.insert(marks, { part = p :: BasePart, at = now })
	end
	return {
		step = function(now: number, castWeight: number)
			for _, aura in veils do aura.Rate = 4 + castWeight * 7 end
			for index = #marks, 1, -1 do
				local entry = marks[index]
				local age = now - entry.at
				if age >= 0.6 then entry.part:Destroy(); table.remove(marks, index)
				else entry.part.Transparency = 0.62 + age / 0.6 * 0.38 end
			end
			if (root.Position - lastPosition).Magnitude > 15 then lastPosition = root.Position end
			if humanoid.FloorMaterial ~= Enum.Material.Air and now - lastMark >= 0.18 and (root.Position - lastPosition).Magnitude >= 1.9 and #marks < 5 then
				lastMark, lastPosition = now, root.Position
				mark(now)
			end
		end,
		destroy = function()
			attachment:Destroy()
			for _, entry in marks do entry.part:Destroy() end
			table.clear(marks)
		end,
	}
end
return WarlockPresence
