--!strict
local Stone = require(script.Parent.ShrineStonework)
local Courtyard = {}
function Courtyard.create(parent: Folder)
	local c = Stone.colors
	local decor = Instance.new("Folder")
	decor.Name, decor.Parent = "SanctuaryStonework", parent
	-- Only these four cores are new physical cover. Their art has no independent hitboxes.
	for index, position in {Vector3.new(-44, 0, -50), Vector3.new(44, 0, -50), Vector3.new(-44, 0, 50), Vector3.new(44, 0, 50)} do
		local core = Stone.block(parent, "MainCover" .. tostring(index), Vector3.new(10, 14, 10),
			CFrame.new(position + Vector3.new(0, 7, 0)), c.shadow, Enum.Material.Slate, true)
		core:SetAttribute("MainCover", true)
		Stone.pillar(decor, position, 14, 10.1, index == 2 or index == 3)
		Stone.block(decor, "CoverCarvedLintel", Vector3.new(8.3, 1.6, 0.25), CFrame.new(position + Vector3.new(0, 11, -5.15)), c.ink)
		for rune = 1, index do
			Stone.block(decor, "CoverIdentityRune", Vector3.new(0.3, 0.8, 0.15),
				CFrame.new(position + Vector3.new((rune - (index + 1) / 2) * 1.1, 11, -5.31)) * CFrame.Angles(0, 0, 0.5), c.emerald, Enum.Material.Neon)
		end
		if index == 1 then
			Stone.round(decor, "CrownSeal", position + Vector3.new(0, 16.1, 0), 6, 0.25, c.ink)
			Stone.flame(decor, position + Vector3.new(0, 16.4, 0), c.emerald)
		elseif index == 2 then
			Stone.block(decor, "BrokenCrown", Vector3.new(6, 2.1, 9), CFrame.new(position + Vector3.new(1, 15.3, 0)) * CFrame.Angles(0.1, 0.2, -0.22), c.edge)
		elseif index == 3 then
			Stone.growth(decor, position + Vector3.new(-1, 14, 0), 1.4, 3)
		else
			Stone.block(decor, "DarkCrystalFinial", Vector3.new(2.5, 4, 2.5), CFrame.new(position + Vector3.new(0, 17.5, 0)) * CFrame.Angles(0, 0.7, 0), c.ink, Enum.Material.Glass)
			Stone.block(decor, "CrystalSeam", Vector3.new(0.12, 3, 0.12), CFrame.new(position + Vector3.new(0, 17.5, -1.3)), c.violet, Enum.Material.Neon)
		end
		Stone.growth(decor, position + Vector3.new(7, 0, 5), 0.8, index)
	end
	-- Open, legible objective: shallow inscriptions, no collidable platform or central cover.
	Stone.round(decor, "RitualStone", Vector3.new(0, 0.015, 0), 33, 0.025, c.shadow)
	Stone.ring(decor, "OuterRitualInlay", Vector3.new(0, 0.047, 0), 15.7, 0.23, c.edge, 48)
	Stone.ring(decor, "InnerRitualInlay", Vector3.new(0, 0.05, 0), 12.7, 0.12, c.emerald, 40, Enum.Material.Neon)
	for index = 1, 8 do
		local angle = index * math.pi / 4
		local frame = CFrame.new(math.sin(angle) * 9, 0.064, math.cos(angle) * 9) * CFrame.Angles(0, angle, 0)
		Stone.block(decor, "RuneStem", Vector3.new(0.18, 0.025, 2.7), frame, c.edge)
		Stone.block(decor, "RuneCleft", Vector3.new(1.3, 0.025, 0.18), frame * CFrame.new(0.45, 0, -0.5) * CFrame.Angles(0, 0.65, 0), c.edge)
	end
	for _, x in {-66, -22, 22, 66} do
		for _, z in {-124, -88, -48, 0, 48, 88, 124} do
			if math.abs(x) > 22 or math.abs(z) > 20 then
				Stone.block(decor, "WeatheredPaving", Vector3.new(20, 0.025, 24), CFrame.new(x, 0.018, z),
					if (x + z) % 3 == 0 then c.stone else c.shadow)
			end
		end
	end
	for _, sign in {-1, 1} do
		for _, z in {-125, -84, -28, 28, 84, 125} do
			Stone.pillar(decor, Vector3.new(sign * 91, 0, z), if z % 2 == 0 then 24 else 30, 5, z == -28 or z == 84)
			Stone.growth(decor, Vector3.new(sign * 89, 0, z + 8), 1.6, z)
		end
		for _, z in {-80, 80} do
			Stone.block(decor, "ScreenCoping", Vector3.new(43, 0.8, 4.4), CFrame.new(0, 12.5, z), c.edge)
		end
		for index = -4, 4 do
			Stone.block(decor, "WallRecess", Vector3.new(0.15, 17, 17), CFrame.new(sign * 95.8, 13.5, index * 29), c.shadow)
			Stone.block(decor, "WallWarmCornice", Vector3.new(1.1, 0.6, 24), CFrame.new(sign * 95.4, 24, index * 29), c.edge)
		end
		Stone.arch(decor, Vector3.new(0, 0, sign * 140), 21, 17, 4, 0)
		Stone.block(decor, "DistantTerrace", Vector3.new(165, 9, 30), CFrame.new(0, 38, sign * 174), c.shadow)
		for index = -2, 2 do
			Stone.pillar(decor, Vector3.new(index * 30, 42, sign * 175), 21 + (index % 2) * 8, 7, index % 2 == 0)
		end
	end
	-- Skyline stays beyond physical bounds, so it cannot hide an opponent on the objective.
	for index = 1, 7 do
		local x = -185 + index * 48
		Stone.block(decor, "FarSanctuaryButtress", Vector3.new(22, 47 + index % 3 * 13, 35),
			CFrame.new(x, 40, -230 - index % 2 * 22) * CFrame.Angles(0, index * 0.13, 0), c.shadow)
	end
	return decor
end
return Courtyard
