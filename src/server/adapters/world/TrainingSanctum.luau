--!strict
local Stone = require(script.Parent.ShrineStonework)
local Sanctum = {}
function Sanctum.create(parent: Folder)
	local c = Stone.colors
	local decor = Instance.new("Folder")
	decor.Name, decor.Parent = "TrainingSanctum", parent
	-- Ground is visual only. The shared training floor still has its exact upper face at y = 0.
	for x = 0, 7 do
		for z = 0, 15 do
			Stone.block(decor, "CourtyardPaver", Vector3.new(8.45, 0.025, 8.45), CFrame.new(200 + x * 8.5, 0.018, -65 + z * 8.5),
				if (x + z) % 3 == 0 then c.light else c.stone)
		end
	end
	-- Warm transverse bands lead from the first spawn toward the target, without covering the aim.
	for _, z in {-59, -24, 18, 53} do
		Stone.block(decor, "MosaicCrossBand", Vector3.new(66, 0.025, 0.36), CFrame.new(230, 0.05, z), c.edge)
	end
	Stone.ring(decor, "PracticeSeal", Vector3.new(230, 0.06, -38), 8, 0.25, c.edge, 32)
	Stone.ring(decor, "PracticeInnerSeal", Vector3.new(230, 0.065, -38), 6.4, 0.12, c.violet, 24, Enum.Material.Neon)
	-- Effigy ornament is outside its Humanoid model and cannot become an accidental damage target.
	Stone.block(decor, "EffigyBreastplate", Vector3.new(2.5, 2.6, 0.16), CFrame.new(230, 3.1, -36.92), c.ink, Enum.Material.Metal)
	Stone.block(decor, "EffigyHeartRune", Vector3.new(0.18, 1.4, 0.12), CFrame.new(230, 3.1, -36.77) * CFrame.Angles(0, 0, 0.3), c.emerald, Enum.Material.Neon)
	for _, sign in {-1, 1} do
		Stone.block(decor, "EffigyEye", Vector3.new(0.36, 0.12, 0.08), CFrame.new(230 + sign * 0.44, 6.25, -36.96), c.emerald, Enum.Material.Neon)
	end
	for _, sign in {-1, 1} do
		local x = if sign == -1 then 197 else 263
		for index, z in {-55, -12, 33, 66} do
			Stone.pillar(decor, Vector3.new(x, 0, z), if index == 3 then 21 else 26, 3.4, index == 3)
			Stone.growth(decor, Vector3.new(x + sign * 0.2, 0, z - 4.8), 0.7, index * sign)
		end
		for index = 0, 6 do
			Stone.block(decor, "SanctumWallPanel", Vector3.new(0.25, 21, 15.8), CFrame.new(x + sign * 2.2, 13, -56 + index * 19), c.shadow)
			Stone.block(decor, "InsetWarmLintel", Vector3.new(0.45, 0.65, 15.9), CFrame.new(x + sign * 2.1, 24, -56 + index * 19), c.edge)
			Stone.block(decor, "MasonryFootCourse", Vector3.new(0.5, 1, 15.9), CFrame.new(x + sign * 2.05, 1.2, -56 + index * 19), c.edge)
		end
	end
	-- This broad broken sanctuary façade is the player's first view behind the practice target.
	Stone.arch(decor, Vector3.new(230, 0, -67), 19, 16, 3.5, 0)
	Stone.block(decor, "SanctumApse", Vector3.new(29, 26, 0.4), CFrame.new(230, 15, -70.8), c.ink)
	Stone.ring(decor, "ApseSeal", Vector3.new(230, 0.07, -59), 10.5, 0.22, c.edge, 32)
	for index = 1, 5 do
		local angle = index * math.pi / 3
		Stone.block(decor, "ApseVerticalRune", Vector3.new(0.45, 4.4, 0.3),
			CFrame.new(230 + math.sin(angle) * 5, 18 + math.cos(angle) * 5, -70.3) * CFrame.Angles(0, 0, angle), c.emerald, Enum.Material.Neon)
	end
	Stone.block(decor, "ApseLintel", Vector3.new(25, 1.7, 1.4), CFrame.new(230, 7, -69.5), c.edge)
	Stone.flame(decor, Vector3.new(211, 1.8, -52), c.emerald)
	Stone.flame(decor, Vector3.new(249, 1.8, -52), c.violet)
	Stone.pillar(decor, Vector3.new(211, 0, -52), 2, 3, true)
	Stone.pillar(decor, Vector3.new(249, 0, -52), 2, 3, true)
	-- A near-camera ruined pier gives the entrance a readable human scale.
	Stone.pillar(decor, Vector3.new(197, 0, 51), 15, 4, true)
	Stone.block(decor, "EntranceBrokenLintel", Vector3.new(6, 2.2, 4.5), CFrame.new(198, 17, 51) * CFrame.Angles(0, 0.12, -0.12), c.edge)
	Stone.growth(decor, Vector3.new(199, 0, 46), 1.15, 17)
	Stone.growth(decor, Vector3.new(260, 0, -65), 1.4, 9)
	Stone.growth(decor, Vector3.new(200, 0, -65), 1.6, 14)
	-- Receding towers are seen above the rear wall; the training space stays completely traversable.
	for _, x in {207, 230, 254} do
		Stone.pillar(decor, Vector3.new(x, 28, -88), if x == 230 then 34 else 23, 5, x ~= 230)
	end
	return decor
end
return Sanctum
