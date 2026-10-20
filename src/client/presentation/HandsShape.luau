--!strict
-- One articulated, local-only demonic hand. Its area root owns every instance.
local Style = require(game:GetService("ReplicatedStorage").Shared.presentation.ArrowStyle)
local HandsShape = {}
type Fixed = { part: BasePart, offset: CFrame, opacity: number }
type Finger = { base: CFrame, first: BasePart, second: BasePart, claw: BasePart, a: number, b: number, thumb: boolean }

function HandsShape.new(parent: Instance, frame: CFrame, scale: number, index: number)
	local fixed: { Fixed } = {}
	local fingers: { Finger } = {}
	local stone = Style.shadow:Lerp(Style.color, 0.27)
	local function part(name: string, size: Vector3, glowing: boolean, wedge: boolean?): BasePart
		local p: BasePart = if wedge then Instance.new("WedgePart") else Instance.new("Part")
		p.Name, p.Size = name, size * scale
		p.Anchored, p.Massless, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, true, false, false, false, false
		p.Color, p.Material = if glowing then Style.flame else stone, if glowing then Enum.Material.Neon else Enum.Material.Slate
		p.Transparency, p.CFrame, p.Parent = 1, frame, parent
		return p
	end
	local function fixedPart(name: string, size: Vector3, offset: Vector3, glowing: boolean, rotation: CFrame?)
		local p = part(name, size, glowing)
		table.insert(fixed, {part = p, offset = CFrame.new(offset * scale) * (rotation or CFrame.identity), opacity = if glowing then 0.25 else 0.08})
	end
	fixedPart("DemonicForearm", Vector3.new(0.73, 1.35, 0.76), Vector3.new(0, 0.42, 0.12), false, CFrame.Angles(-0.15, 0, 0.08))
	fixedPart("CurseWrist", Vector3.new(0.84, 0.35, 0.69), Vector3.new(0, 1.15, 0), false)
	fixedPart("DemonicPalm", Vector3.new(1.43, 1.15, 0.58), Vector3.new(0, 1.85, 0), false)
	fixedPart("PalmFelSeam", Vector3.new(0.11, 1.12, 0.04), Vector3.new(-0.15, 1.86, -0.31), true, CFrame.Angles(0, 0, -0.3))
	fixedPart("WristFelSeam", Vector3.new(0.08, 0.94, 0.04), Vector3.new(0.13, 0.66, -0.28), true, CFrame.Angles(0, 0, 0.16))
	for digit = 1, 5 do
		local thumb = digit == 5
		local a = if thumb then 0.58 else if digit == 2 or digit == 3 then 0.78 else 0.63
		local b = if thumb then 0.47 else 0.62
		local base = if thumb then CFrame.new(-0.78 * scale, 1.7 * scale, 0) * CFrame.Angles(0, 0, 0.95)
			else CFrame.new((digit - 2.5) * 0.37 * scale, 2.38 * scale, 0) * CFrame.Angles(0, 0, (digit - 2.5) * -0.08)
		table.insert(fingers, {base = base, a = a * scale, b = b * scale, thumb = thumb,
			first = part("FingerProximal" .. digit, Vector3.new(0.29, a, 0.31), false),
			second = part("FingerDistal" .. digit, Vector3.new(0.25, b, 0.26), false),
			claw = part("FelClaw" .. digit, Vector3.new(0.19, 0.34, 0.2), true, true)})
	end
	local hand = {}
	function hand.step(now: number, rise: number, fade: number)
		local curl = 0.35 + math.sin(now * 2.7 + index * 1.7) * 0.12
		local base = frame * CFrame.new(0, -(1 - rise) * 4.2 * scale, 0)
			* CFrame.Angles(math.sin(now * 1.8 + index) * 0.045 * rise, 0, math.sin(now * 2.1 + index) * 0.06 * rise)
		for _, item in fixed do
			item.part.CFrame = base * item.offset
			item.part.Transparency = item.opacity + (1 - item.opacity) * fade
		end
		for _, finger in fingers do
			local knuckle = base * finger.base * CFrame.Angles(-curl * (if finger.thumb then 0.7 else 1), 0, 0)
			finger.first.CFrame = knuckle * CFrame.new(0, finger.a / 2, 0)
			local joint = knuckle * CFrame.new(0, finger.a, 0) * CFrame.Angles(-0.75 - curl * 0.45, 0, 0)
			finger.second.CFrame = joint * CFrame.new(0, finger.b / 2, 0)
			finger.claw.CFrame = joint * CFrame.new(0, finger.b + 0.1 * scale, 0) * CFrame.Angles(-0.35, 0, 0)
			finger.first.Transparency, finger.second.Transparency, finger.claw.Transparency = 0.08 + fade * 0.92, 0.08 + fade * 0.92, 0.2 + fade * 0.8
		end
	end
	return hand
end
return HandsShape
