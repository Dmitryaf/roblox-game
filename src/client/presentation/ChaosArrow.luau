--!strict
local Players = game:GetService("Players")
local Style = require(game:GetService("ReplicatedStorage").Shared.presentation.ArrowStyle)
local Matter = require(script.Parent.ChaosMatter)
local ChaosArrow = {}

function ChaosArrow.new(folder: Folder, event: any, flying: boolean)
	local root = Matter.part(folder, if flying then "DemonicArrow" else "ArrowCharge", Vector3.one * 0.2, Style.shadow)
	root.Transparency = 1
	root.Parent = nil -- A charge has no world location until its owner's hand has replicated.
	-- Cleanup must also progress when Studio or the client stops rendering this window.
	game:GetService("Debris"):AddItem(root, math.max(0.05, event.expiresAt - workspace:GetServerTimeNow()))
	local core = Matter.part(root, "UnstableCore", Vector3.new(0.6, 0.6, if flying then 3.4 else 0.6), Style.core)
	core.Shape = Enum.PartType.Ball
	local shell = Matter.part(root, "DarkMantle", Vector3.one, Style.shadow)
	shell.Shape, shell.Transparency = Enum.PartType.Ball, 0.3
	local light = Matter.light(root, Style.flame, 1.5, 13)
	if event.redirected then
		core.Color, light.Color = Color3.fromRGB(255, 218, 140), Color3.fromRGB(255, 185, 90)
	end
	local fire, smoke = Matter.particles(root, false), Matter.particles(root, true)
	fire.Rate, smoke.Rate = if flying then 42 else 18, if flying then 12 else 5
	fire.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(0.25, 2.4), NumberSequenceKeypoint.new(1, 0.1)})
	if flying then
		fire.EmissionDirection = Enum.NormalId.Back
		fire.Speed, fire.Drag = NumberRange.new(5, 10), 2
		Matter.trail(core, Style.flame, 2.5, 0.25)
		Matter.trail(shell, Style.color, 1.4, 0.32)
	end
	-- Small strands travel inward; the held nucleus stays readable between them.
	local strands = {}
	if not flying then
		for i = 1, 6 do
			local mote = Matter.part(root, "GatheringEmber", Vector3.one * 0.16, if i % 2 == 0 then Style.color else Style.flame)
			mote.Shape = Enum.PartType.Ball
			Matter.trail(mote, mote.Color, 0.14, 0.12)
			table.insert(strands, mote)
		end
	end
	local ribbons = {}
	for i = 1, 3 do
		local rib = Matter.part(root, "RaggedSpine", Vector3.new(0.12, 0.2, if flying then 2.4 else 0.65), if i == 2 then Style.color else Style.flame)
		rib.Transparency = 0.18
		table.insert(ribbons, rib)
	end
	local visual = { root = root }
	function visual.step(now: number)
		local cf: CFrame
		local weight = 1
		if flying then
			local p = event.position + event.direction * event.speed * math.max(0, now - (event.sampledAt or event.launchAt))
			cf = CFrame.lookAt(p, p + event.direction)
		else
			local player = Players:GetPlayerByUserId(event.owner)
			local character = if player then player.Character else nil
			local hand = if character then character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm") else nil
			if not hand or not hand:IsA("BasePart") then root.Parent = nil; return end
			local startedAt = event.startedAt or event.launchAt
			weight = math.clamp((now - startedAt) / math.max(0.06, event.launchAt - startedAt), 0, 1)
			local p = hand.Position + hand.CFrame.UpVector * -0.3
			local direction = event.direction or hand.CFrame.LookVector
			cf = CFrame.lookAt(p, p + direction)
		end
		root.CFrame = cf
		local pulse = 1 + (if flying then 0.08 else 0.035) * math.sin(now * (if flying then 49 else 16) + event.castId)
		local gather = math.clamp(weight / 0.6, 0, 1)
		local scale = if flying then 1 else 0.2 + gather * 0.95
		core.Size = (if flying then Vector3.new(1.05, 1.05, 5) else Vector3.new(0.9, 0.9, 1.1)) * scale * pulse
		core.CFrame = cf
		shell.Size = (if flying then Vector3.new(1.85, 1.45, 4.5) else Vector3.new(1.5, 1.3, 1.45)) * scale
		shell.CFrame = cf * CFrame.Angles(0, 0, now * 11)
		light.Brightness = (if flying then 3.2 else 0.4 + gather * 3.2) * pulse
		if not flying then fire.Rate, smoke.Rate = 12 + gather * 20, 4 + gather * 5 end
		for i, mote in strands do
			local cycle = ((now - (event.startedAt or now)) * 2.6 + i / 6) % 1
			local angle = i * math.pi / 3 + cycle * 2.4
			local radius = (1 - cycle) * (2.4 - gather * 0.5) + 0.2
			mote.CFrame = cf * CFrame.new(math.cos(angle) * radius, math.sin(angle) * radius * 0.7, 0.45 * (1 - cycle))
			mote.Transparency = math.clamp((0.12 - cycle) / 0.12, 0, 1) + math.clamp((cycle - 0.8) / 0.2, 0, 1)
			mote.Size = Vector3.one * (0.12 + gather * 0.1) * (1 - cycle * 0.55)
		end
		for i, rib in ribbons do
			local angle = now * (if flying then 18 else -12) + i * math.pi * 2 / 3
			local radius = (if flying then 1 else 0.68) * scale
			rib.CFrame = cf * CFrame.new(math.cos(angle) * radius, math.sin(angle) * radius, if flying then 0.5 else 0)
				* CFrame.Angles(math.sin(angle) * 0.3, math.cos(angle) * 0.3, angle)
			rib.Size = Vector3.new(0.17, 0.26, if flying then 3.8 else 0.85) * scale
		end
		root.Parent = folder
	end
	function visual.destroy() root:Destroy() end
	return visual
end
return ChaosArrow
