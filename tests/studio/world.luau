--!strict
-- run-in-roblox --place build/WarlockSlice.rbxlx --script tests/studio/world.luau
-- Actual engine geometry tests, not a substitute for two-client playtesting.
local modules = game:GetService("ServerScriptService"):WaitForChild("Game")
local Arena = require(modules.adapters.world.TestArena)
local World = require(modules.adapters.world.CombatWorld)
local arena = Arena.create()
local world = World.new()
local character = Instance.new("Model")
character.Name = "GeometryTestRig"
local root = Instance.new("Part")
root.Name, root.Size = "HumanoidRootPart", Vector3.new(2, 2, 1)
root.Anchored = true
root.Position = Vector3.new(0, 3, 0)
root.Parent = character
local humanoid = Instance.new("Humanoid")
humanoid.RequiresNeck = false
humanoid.HipHeight = 2
humanoid.Parent = character
character.Parent = workspace
world.register(101, character, root, humanoid)
local passed = 0
local function check(name: string, run: () -> ())
	run(); passed += 1; print("PASS Studio: " .. name)
end
local ok, err = xpcall(function()
	check("transient zero-position root receives authoritative spawn", function()
		local spawnWorld = World.new({ CFrame.new(0, 1, 40) })
		root.CFrame = CFrame.identity
		spawnWorld.register(202, character, root, humanoid)
		assert(root.Position.Z == 40 and root.Position.Y > 3 and spawnWorld.validate(202))
		spawnWorld.remove(202)
		root.CFrame = CFrame.new(0, 3, 0)
		world.register(101, character, root, humanoid)
	end)
	check("supported empty landing", function()
		local destination = world.landing(101, Vector3.new(20, 4, 0), Vector3.xAxis)
		assert(destination and math.abs(destination.X - 17) < 0.01)
		world.move(101, destination)
		assert((root.Position - destination).Magnitude < 0.01 and world.validate(101))
	end)
	check("wall blocks swept projectile", function()
		local position, target = world.sweep(101, Vector3.new(-23, 5, 0), Vector3.new(0, 0, -30), 0.8)
		assert(position and not target)
	end)
	check("target takes damage through same sweep path", function()
		local position, target = world.sweep(101, Vector3.new(0, 4, 0), Vector3.new(0, 0, -50), 0.8)
		assert(position and target)
		world.damage(101, target, 25)
		assert(target.Health == 75)
	end)
	check("destination behind wall rejected", function()
		assert(world.landing(101, Vector3.new(-23, 4, -22), -Vector3.zAxis) == nil)
	end)
	check("outside arena and missing support rejected", function()
		assert(world.landing(101, Vector3.new(90, 4, 0), Vector3.xAxis) == nil)
		assert(world.landing(101, Vector3.new(20, 30, 0), Vector3.xAxis) == nil)
	end)
	check("untrusted position jump corrected", function()
		local before = root.CFrame
		root.CFrame = CFrame.new(70, 3, 70)
		assert(not world.validate(101))
		assert((root.Position - before.Position).Magnitude < 0.01)
	end)
	check("removed life cannot cast or land", function()
		world.remove(101)
		assert(not world.alive(101) and world.origin(101) == nil)
		assert(world.landing(101, Vector3.new(20, 4, 0), Vector3.xAxis) == nil)
	end)
end, debug.traceback)
world.remove(101)
character:Destroy()
arena:Destroy()
assert(ok, err)
print(string.format("%d Studio geometry tests passed", passed))
return true
