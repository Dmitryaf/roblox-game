--!strict
local modules = game:GetService("ServerScriptService"):WaitForChild("Game")
local Arena = require(modules.adapters.world.MatchArena)
local World = require(modules.adapters.world.MatchWorld)
local arena = Arena.create()
local contexts: { [number]: any } = { [101] = { mode = "match", team = 1, matchId = 1, frozen = false },
	[102] = { mode = "training", matchId = 0, frozen = false } }
local world = World.new(arena, function(owner) return contexts[owner] end, function(owner) return not contexts[owner].frozen end)
local rigs: { Model } = {}
local roots: { [number]: BasePart } = {}
for _, owner in {101, 102} do
	local rig = Instance.new("Model")
	local root = Instance.new("Part")
	root.Name, root.Size, root.Anchored, root.Parent = "HumanoidRootPart", Vector3.new(2, 2, 1), true, rig
	local humanoid = Instance.new("Humanoid")
	humanoid.RequiresNeck, humanoid.HipHeight, humanoid.Parent = false, 2, rig
	rig.Parent = workspace
	table.insert(rigs, rig)
	roots[owner] = root
	world.register(owner, rig, root, humanoid, arena.spawn(contexts[owner].team, owner))
	world.resetContext(owner, contexts[owner].team, false)
end
local count = 0
local function test(name: string, run: () -> ()) run(); count += 1; print("PASS Match geometry: " .. name) end
local ok, err = xpcall(function()
	test("four physical covers stay outside the objective and stop projectiles", function()
		local covers = 0
		for _, item in arena.folder:GetChildren() do
			if item:IsA("BasePart") and item:GetAttribute("MainCover") then
				covers += 1
				assert(item.CanCollide and item.CanQuery, "Cover has no physical body")
				assert(math.abs(item.Position.X) - item.Size.X / 2 > 18
					and math.abs(item.Position.Z) - item.Size.Z / 2 > 18, "Safe cover overlaps the capture zone")
			end
		end
		assert(covers == 4, "Arena must have four main covers")
		local hit = world.sweep(101, Vector3.new(44, 4, 20), Vector3.new(0, 0, 70), 0.8)
		assert(hit and hit.Z > 43 and hit.Z < 46, "The visible main cover does not stop the arrow")
	end)
	test("sanctuary decoration stays outside physics and hit queries", function()
		for _, name in {"TrainingSanctum", "SanctuaryStonework"} do
			local decor = arena.folder:FindFirstChild(name)
			assert(decor, "Sanctuary art is absent")
			for _, item in decor:GetDescendants() do
				if item:IsA("BasePart") then
					assert(not item.CanCollide and not item.CanQuery and not item.CanTouch,
						"Decorative geometry participates in combat: " .. item:GetFullName())
				end
			end
		end
	end)
	test("training visitors receive distinct stable positions", function()
		local positions: { Vector3 } = {}
		for owner = 201, 250 do
			local base = arena.spawn(nil, owner)
			assert(arena.spawn(nil, owner) == base)
			assert(math.abs(base.Position.X - 230) < 33 and math.abs(base.Position.Z) < 69)
			for _, previous in positions do assert((previous - base.Position).Magnitude >= 9) end
			table.insert(positions, base.Position)
		end
		for owner = 201, 250 do arena.forget(owner) end
	end)
	test("spawn has support and blocks casting in either direction", function()
		assert(world.position(101) and world.origin(101) == nil)
		local hit = world.sweep(101, Vector3.new(0, 4, 98), Vector3.new(0, 0, 20), 0.8)
		assert(hit and hit.Z <= 102)
		local outward = world.sweep(101, Vector3.new(0, 4, 118), Vector3.new(0, 0, -30), 0.8)
		assert(outward and outward.Z == 118)
	end)
	test("leaving pad enables cast but return teleport is rejected", function()
		world.move(101, Vector3.new(0, 3.2, 98))
		assert(world.origin(101))
		assert(world.landing(101, Vector3.new(0, 4, 106), Vector3.zAxis) == nil)
		world.resetContext(101, 1, false)
		assert(world.position(101).Z == 118 and world.validate(101))
	end)
	test("enemy pad and path through protected pad reject landing", function()
		world.move(101, Vector3.new(0, 3.2, -98))
		assert(world.landing(101, Vector3.new(0, 4, -110), -Vector3.zAxis) == nil)
		assert(world.landing(101, Vector3.new(0, 4, -140), -Vector3.zAxis) == nil)
	end)
	test("safe arena landing still works", function()
		world.move(101, Vector3.new(45, 3.2, 0))
		local destination = world.landing(101, Vector3.new(60, 4, 0), Vector3.xAxis)
		assert(destination and math.abs(destination.X - 57) < 0.01)
	end)
	test("practice and match stay in separate bounds and cannot damage practice target across context", function()
		world.move(102, Vector3.new(230, 3.2, 0))
		assert(world.origin(102))
		assert(world.landing(102, Vector3.new(80, 4, 0), Vector3.xAxis) == nil)
		local _, target = world.sweep(102, Vector3.new(230, 4, 0), Vector3.new(0, 0, -50), 0.8)
		assert(target)
		world.damage(101, target, 25)
		assert(target.Health == 100)
		world.damage(102, target, 25)
		assert(target.Health == 75)
	end)
	test("frozen participant cannot cast and fresh life drops old pad restriction", function()
		contexts[101].frozen = true
		assert(world.origin(101) == nil)
		contexts[101].frozen = false
		world.remove(101)
		world.register(101, rigs[1], roots[101], rigs[1]:FindFirstChildOfClass("Humanoid"), arena.spawn(1, 101))
		assert(world.validate(101))
	end)
    test("hands require supported reachable ground, range and an unprotected footprint", function()
        world.move(102, Vector3.new(230, 3.2, -12))
        local ground = world.placement(102, Vector3.new(230, 0, -26), 30, 8)
        assert(ground and math.abs(ground.Y) < 0.01, "Supported hands ground was rejected")
        assert(world.placement(102, Vector3.new(230, 0, -60), 30, 8) == nil, "Hands exceeded range")
        assert(world.placement(102, Vector3.new(260, 0, -12), 50, 8) == nil, "Hands footprint crossed training bounds")
        world.move(101, Vector3.new(44, 3.2, 35))
        assert(world.placement(101, Vector3.new(44, 0, 64), 30, 8) == nil, "Hands were placed through a physical cover")
        world.move(101, Vector3.new(-30, 3.2, 118))
        assert(world.placement(101, Vector3.new(-15, 0, 100), 30, 8) == nil, "Hands crossed a protected pad")
    end)
    test("hands occupants share training and match damage isolation", function()
        local targets = world.areaTargets(102, Vector3.new(230, 0, -30), 8)
        assert(#targets == 1 and targets[1].Parent:GetAttribute("TrainingTarget"), "Hands could not find the real training target")
        assert(#world.areaTargets(101, Vector3.new(230, 0, -30), 8) == 0, "Match hands selected a training target")
    end)
    test("slow movement restores on context reset and body removal", function()
        local humanoid = rigs[2]:FindFirstChildOfClass("Humanoid") :: Humanoid
        local original = humanoid.WalkSpeed
        world.slow(humanoid, 0.65)
        assert(math.abs(humanoid.WalkSpeed - original * 0.65) < 0.001)
        world.resetContext(102, nil, false)
        assert(humanoid.WalkSpeed == original, "New context retained old slow")
        world.slow(humanoid, 0.65); world.remove(102)
        assert(humanoid.WalkSpeed == original, "Removed body retained old slow")
    end)

end, debug.traceback)
for _, owner in {101, 102} do world.remove(owner) end
for _, rig in rigs do rig:Destroy() end
arena.folder:Destroy()
assert(ok, err)
print(tostring(count) .. " match geometry tests passed")
return true
