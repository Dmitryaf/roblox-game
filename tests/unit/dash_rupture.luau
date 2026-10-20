--!strict
local fs, luau, rb = require("@lune/fs"), require("@lune/luau"), require("@lune/roblox")
local Vector3, CFrame, Color3 = rb.Vector3, rb.CFrame, rb.Color3
local source = fs.readFile("src/client/presentation/DashRupture.luau")
local total = 0
local function test(name, run) run(); total += 1; print("PASS", name) end
local function fixture(quiet)
	local f = { time = 100, created = {}, queries = {} }
	local function instance(className)
		local values, children = { ClassName = className, Parent = nil, Transparency = 0 }, {}
		local object
		object = setmetatable({}, {
			__index = function(_, key)
				if key == "Destroy" then return function()
					for _, child in children do if child.Parent == object then child:Destroy() end end
					values.Parent, values.destroyed = nil, true
				end end
				if key == "IsA" then return function(_, name) return name == className or (name == "BasePart" and className == "Part") end end
				if key == "Emit" then return function(_, count) values.emitted = (values.emitted or 0) + count end end
				if key == "Play" then return function() values.played = true end end
				if key == "add" then return function(_, child) table.insert(children, child) end end
				if key == "FindFirstAncestorOfClass" then return function(_, name)
					local ancestor = values.Parent
					while ancestor do if ancestor.ClassName == name then return ancestor end; ancestor = ancestor.Parent end
					return nil
				end end
				if key == "FindFirstChildOfClass" then return function(_, name)
					for _, child in children do if child.Parent == object and child.ClassName == name then return child end end
					return nil
				end end
				return values[key]
			end,
			__newindex = function(_, key, value)
				values[key] = value
				if key == "Parent" and value then value:add(object) end
			end,
		})
		table.insert(f.created, object)
		return object
	end
	f.instance = instance
	f.parent = instance("Folder")
	f.character = instance("Model")
	f.root = { Position = Vector3.new(0, 3, 0) }
	local surface = instance("Part"); surface.Color = Color3.fromRGB(108, 79, 45)
	local world = {}; function world:GetServerTimeNow() return f.time end
	function world:Raycast(origin, delta, params)
		assert(params.FilterType == "Exclude" and params.FilterDescendantsInstances[1] == f.character and params.FilterDescendantsInstances[2] == f.parent)
		assert(params.RespectCanCollide and delta.Y < -5)
		table.insert(f.queries, origin)
		if f.blocker and not table.find(params.FilterDescendantsInstances, f.blocker.Parent) then
			return { Position = Vector3.new(origin.X, 3, origin.Z), Normal = Vector3.yAxis, Material = "Skin", Instance = f.blocker }
		end
		if f.staticWall then return { Position = Vector3.new(origin.X, 1, origin.Z), Normal = Vector3.xAxis, Material = "Concrete", Instance = surface } end
		return if f.noGround then nil else { Position = Vector3.new(origin.X, 0, origin.Z), Normal = Vector3.yAxis, Material = "Concrete", Instance = surface }
	end
	local module = luau.load(source, { environment = { workspace = world, Instance = { new = instance }, Vector3 = Vector3,
		Vector2 = rb.Vector2, CFrame = CFrame, Color3 = Color3, ColorSequence = rb.ColorSequence,
		NumberSequence = rb.NumberSequence, NumberSequenceKeypoint = rb.NumberSequenceKeypoint, NumberRange = rb.NumberRange,
		RaycastParams = { new = function() return {} end }, Enum = { RaycastFilterType = { Exclude = "Exclude" }, Material = { Slate = "Slate", Neon = "Neon" } },
	} })()
	f.effect = module.new(f.parent, f.character, f.root, Vector3.xAxis, 8, quiet)
	function f.named(name, live)
		local found = {}
		for _, object in f.created do if object.Name == name and (not live or object.Parent) then table.insert(found, object) end end
		return found
	end
	function f.step(delta, emitting) f.time += delta; return f.effect.step(f.time, emitting ~= false) end
	return f
end
test("ground colors materials and both staggered rock waves come from the real rendered surface", function()
	local f = fixture(false); local stones = f.named("DashGroundShard")
	assert(#stones == 4 and #f.named("DashGroundDust") == 2)
	for _, stone in stones do
		assert(stone.Color == Color3.fromRGB(108, 79, 45) and stone.Material == "Concrete")
		assert(stone.Anchored and stone.Massless and not stone.CanCollide and not stone.CanQuery and not stone.CanTouch)
	end
	f.step(0.03); assert(stones[1].Transparency < 1 and stones[3].Transparency == 1)
	f.step(0.04); assert(stones[3].Transparency < 1)
	assert(stones[1].CFrame.Position.Z * stones[2].CFrame.Position.Z < 0, "Ground must erupt on both sides")
	f.effect.destroy()
end)
test("only actual root movement emits path clusters and allocations stay bounded even under repeated long updates", function()
	local f = fixture(false); local before = #f.created
	for _ = 1, 10 do f.step(0.001) end
	assert(#f.created == before, "An unmoving character must not paint a fictitious dash")
	for _ = 1, 12 do f.root.Position += Vector3.new(20, 0, 0); f.step(0.01) end
	f.effect.finish(f.time)
	assert(#f.named("DashGroundShard") <= 40 and #f.named("DashGroundCrack") <= 40 and #f.named("DashDustAnchor") <= 20)
	for _, object in f.created do
		if object:IsA("Part") and object.Name and object.Name:find("Dash") then
			assert(object.Anchored and object.Massless and not object.CanCollide and not object.CanQuery and not object.CanTouch)
		end
	end
	f.effect.destroy()
end)
test("a teleport-sized correction never draws a ground fracture across the correction path", function()
	local f = fixture(true); f.root.Position = Vector3.new(100, 3, 0); f.step(0.1)
	assert(#f.named("DashGroundShard") == 0 and #f.queries == 0)
	f.root.Position += Vector3.new(2, 0, 0); f.step(0.02)
	assert(#f.named("DashGroundShard") == 4 and f.queries[1].X > 100)
	f.effect.destroy()
end)
test("natural completion emits its brake once and all cosmetic resources expire within the finite tail", function()
	local f = fixture(false); f.root.Position = Vector3.new(10, 3, 0); f.step(0.15)
	f.effect.finish(f.time); local count = #f.created
	f.effect.finish(f.time + 0.1); assert(#f.created == count and #f.named("WarriorDashBrake") == 1)
	assert(f.step(0.7, false))
	assert(not f.step(0.03, false) and #f.named("DashGroundShard", true) == 0 and #f.named("DashGroundDust", true) == 0)
	for _, object in f.created do if object.Name and object.Name:find("Dash") then assert(not object.Parent) end end
end)
test("missing ground produces no fabricated earth and destroy cancels immediately without later allocations", function()
	local f = fixture(true); f.noGround = true
	f.root.Position = Vector3.new(10, 3, 0); f.step(0.1)
	assert(#f.named("DashGroundShard") == 0 and #f.named("DashGroundDust") == 0)
	f.effect.destroy(); local count = #f.created
	f.effect.finish(f.time); assert(not f.step(0.1) and #f.created == count)
end)
test("quiet restoration never replays launch or brake sound and an abandoned effect has a hard deadline", function()
	local f = fixture(true); assert(#f.named("DashGroundShard") == 0 and #f.named("WarriorDashBrake") == 0)
	f.root.Position = Vector3.new(2, 3, 0); f.step(0.05)
	f.effect.finish(f.time); assert(#f.named("WarriorDashBrake") == 0)
	f.effect.destroy()
	local abandoned = fixture(false); assert(not abandoned.step(1.21) and #abandoned.named("DashGroundShard", true) == 0)
end)
test("enemy heads never supply ground color or height and ignoring a character never tunnels through a static wall", function()
	for _, wall in { false, true } do
		local f = fixture(true)
		local enemy = f.instance("Model")
		local humanoid = f.instance("Humanoid"); humanoid.Parent = enemy
		local head = f.instance("Part"); head.Color, head.Parent = Color3.fromRGB(255, 30, 10), enemy
		f.blocker, f.staticWall = head, wall
		f.root.Position = Vector3.new(2, 3, 0); f.step(0.02)
		assert(#f.queries == 2, "The real query must retry once after excluding the humanoid model")
		local stones = f.named("DashGroundShard")
		if wall then assert(#stones == 0, "A static wall must stop the surface query")
		else
			assert(#stones == 4)
			for _, stone in stones do assert(stone.Color == Color3.fromRGB(108, 79, 45) and stone.Material == "Concrete") end
		end
		f.effect.destroy()
	end
end)
print(string.format("%d DashRupture presentation lifecycle tests passed", total))
