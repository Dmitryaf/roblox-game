--!strict
local fs, luau, rb = require("@lune/fs"), require("@lune/luau"), require("@lune/roblox")
local Vector3, CFrame = rb.Vector3, rb.CFrame
local function module(name, environment) return luau.load(fs.readFile("src/client/presentation/" .. name .. ".luau"), { environment = environment })() end
local Timeline = module("PreparationTimeline", {})
local motions = { MeleeMotion = module("MeleeMotion", { Vector3 = Vector3 }), HeavyMotion = module("HeavyMotion", { Vector3 = Vector3 }),
	DashPoseMotion = module("DashPoseMotion", { Vector3 = Vector3 }), PreparationTimeline = Timeline }
local total = 0
local function test(name, run) run(); total += 1; print("PASS", name) end
local function near(a, b) assert(math.abs(a - b) < 0.00001, tostring(a) .. " ~= " .. tostring(b)) end
local function angle(a, b) local _, value = (a:Inverse() * b):ToAxisAngle(); return math.abs(value) end
local function signal()
	local list, event = {}, {}
	function event:Connect(callback)
		local c = { Connected = true }; function c:Disconnect() self.Connected = false end
		table.insert(list, { c, callback }); return c
	end
	function event.fire(...) for _, value in list do if value[1].Connected then value[2](...) end end end
	return event
end
local function fixture()
	local f = { time = 100, life = 7, classId = "warrior", motors = {}, base = {}, faces = {}, objects = {} }
	local character = { Parent = true }; f.character = character
	function character:GetAttribute(name) return if name == "CombatLife" then f.life else f.classId end
	f.human = { Parent = character, Health = 100, MoveDirection = Vector3.zero, AutoRotate = true }
	f.rootData = { Parent = character, Anchored = false, Position = Vector3.new(10, 3, 0), CFrame = CFrame.new(10, 3, 0), AssemblyLinearVelocity = Vector3.new(0, 4, -16) }
	f.root = setmetatable({}, { __index = function(_, key) return if key == "IsA" then function(_, name) return name == "BasePart" end else f.rootData[key] end,
		__newindex = function(_, key) error("Preparation feedback wrote physical root: " .. key) end })
	function character:FindFirstChildOfClass() return f.human end
	function character:FindFirstChild(name) return if name == "HumanoidRootPart" then f.root else if name == "UpperTorso" then {} else nil end
	local descendants = {}
	for _, name in { "Waist", "Neck", "RightShoulder", "LeftShoulder", "RightElbow", "LeftElbow", "RightWrist", "LeftWrist", "RightHip", "LeftHip" } do
		local motor = { Parent = character, Name = name, Transform = CFrame.Angles(0.03, 0.05, 0.02), C0 = CFrame.identity }
		function motor:IsA(kind) return kind == "Motor6D" end
		f.motors[name], f.base[name] = motor, motor.Transform; table.insert(descendants, motor)
	end
	function character:GetDescendants() return descendants end
	f.player = { UserId = 10, Character = character }
	local players = { LocalPlayer = f.player }; function players:GetPlayerByUserId(owner) return if owner == 10 then f.player else nil end
	local facing = {}
	function facing.new()
		f.human.AutoRotate = false; local value = { destroyed = false, step = function() end }
		function value.destroy() value.destroyed = true; f.human.AutoRotate = true end
		table.insert(f.faces, value); return value
	end
	f.render, f.heartbeat = signal(), signal()
	local services = { Players = players, RunService = { RenderStepped = f.render, Heartbeat = f.heartbeat }, Debris = { AddItem = function() end } }
	f.game = {}; function f.game:GetService(name) return services[name] end
	f.world = {}; function f.world:GetServerTimeNow() return f.time end
	local dependencies = table.clone(motions); dependencies.MeleeFacing = facing
	local names = {}; for name in dependencies do names[name] = name end
	f.pose = module("MeleePose", { game = f.game, workspace = f.world, Vector3 = Vector3, CFrame = CFrame, script = { Parent = names },
		require = function(name) return assert(dependencies[name]) end }).new(true)
	f.cast = module("CastPose", { game = f.game, workspace = f.world, Vector3 = Vector3, CFrame = CFrame,
		script = { Parent = { PreparationTimeline = "Timeline" } }, require = function(name) assert(name == "Timeline"); return Timeline end }).new(function() return f.time end, true)
	function f.tick(at, effects)
		f.time = at; f.pose.beforePose(); f.cast.beforePose()
		f.pose.afterPose(f.time, 1 / 60); f.cast.afterPose(f.time)
		if effects then effects.step(f.time) end
	end
	function f.restored() for name, motor in f.motors do assert(angle(motor.Transform, f.base[name]) < 0.00001, "Not restored: " .. name) end end
	function f.effects(style)
		local impact = { new = function() return { hit = function() end, cancel = function() end, step = function() end, destroy = function() end } end }
		local instance = { new = function(class)
			local object = { ClassName = class, Play = function() end, Destroy = function(self) self.destroyed = true end }
			table.insert(f.objects, object); return object
		end }
		return module("MeleeEffects", { game = f.game, workspace = f.world, Vector3 = Vector3, CFrame = CFrame, Color3 = rb.Color3,
			ColorSequence = rb.ColorSequence, NumberSequence = rb.NumberSequence, Enum = { Material = { Neon = "Neon" } }, Instance = instance,
			script = { Parent = { MeleePose = "Pose", MeleeImpact = "Impact" } }, require = function(name) return if name == "Impact" then impact else {} end,
		}).new(f.pose, style)
	end
	function f.count(name) local n = 0; for _, object in f.objects do if object.Name == name then n += 1 end end; return n end
	return f
end
local forward = Vector3.new(0, 0, -1)
test("unconfirmed preparation gathers promptly but can never reach release regardless of missing server response", function()
	local timeline = Timeline.new(100)
	assert(timeline.progress(100.05) > 0.1 and timeline.progress(100.05) < 0.32)
	for _, age in { 0.1, 0.3, 0.7, 2, 1000 } do assert(timeline.progress(100 + age) <= 0.32) end
	assert(not timeline.confirmed())
end)
test("a matching acceptance preserves progress and duplicate confirmation cannot move the accepted release deadline", function()
	local timeline = Timeline.new(100); local before = timeline.progress(100.3)
	timeline.confirm(100.3, 100.65); near(timeline.progress(100.3), before)
	timeline.confirm(100.31, 100.32)
	local previous = before
	for index = 1, 34 do local progress = timeline.progress(100.3 + index / 100); assert(progress >= previous and progress < 1); previous = progress end
	near(timeline.progress(100.65), 1); assert(timeline.confirmed())
end)
test("melee and heavy input previews are immediate bounded gather poses, and an unrelated cancel cannot erase them", function()
	for _, kind in { "melee", "heavy" } do
		local f = fixture(); assert(not f.pose.preview(10, kind, 1, 6, forward))
		assert(f.pose.preview(10, kind, 1, 7, forward) and not f.pose.preview(10, kind, 2, 7, forward))
		f.tick(100.05); assert(angle(f.motors.RightShoulder.Transform, f.base.RightShoulder) > 0.05 and #f.faces == 1)
		f.tick(101); assert(f.pose.active(10))
		f.pose.cancelPreview(10, kind, 2); assert(f.pose.active(10))
		f.pose.cancelPreview(10, kind, 1); assert(not f.pose.active(10)); f.restored()
		assert(f.root.AssemblyLinearVelocity == Vector3.new(0, 4, -16)); f.pose.destroy(); f.cast.destroy()
	end
end)
test("real melee/heavy Effects adopt previews once and never produce a release burst before server hitAt", function()
	for _, kind in { "melee", "heavy" } do
		local f = fixture(); local effects = f.effects(if kind == "heavy" then "heavy" else nil)
		assert(effects.preview(21, 7, forward)); f.tick(100.3, effects)
		local shoulder = f.motors.RightShoulder.Transform
		local hitAt = if kind == "heavy" then 100.8 else 100.45
		local event = { kind = "preparing", owner = 10, life = 7, swingId = 1, requestId = 21, direction = forward,
			style = if kind == "heavy" then "heavy" else nil, startedAt = 100.15, hitAt = hitAt, expiresAt = hitAt + 0.6 }
		effects.event(event); assert(f.motors.RightShoulder.Transform == shoulder and #f.faces == 1)
		effects.event(table.clone(event)); effects.sync({ table.clone(event) }); assert(#f.faces == 1)
		local burstName = if kind == "heavy" then "WarriorHeavySwing" else "WarriorSwing"
		f.tick(hitAt - 0.001, effects); assert(f.count(burstName) == 0)
		f.tick(hitAt + 0.001, effects); assert(f.count(burstName) == 1)
		local struck = table.clone(event); struck.kind = "struck"; effects.event(struck); effects.event(struck)
		assert(f.count(burstName) == 1, "Authoritative acceptance/strike replayed a local start")
		effects.destroy(); f.pose.destroy(); f.cast.destroy(); f.restored()
	end
end)
test("denial and preview timeout cannot leave an animation or a late release on the old life", function()
	for _, kind in { "melee", "heavy" } do
		local f = fixture(); local effects = f.effects(if kind == "heavy" then "heavy" else nil)
		assert(effects.preview(1, 7, forward)); f.tick(100.1)
		effects.cancelPreview(1); f.restored(); f.tick(101, effects)
		assert(not f.pose.active(10) and f.count("WarriorSwing") == 0 and f.count("WarriorHeavySwing") == 0)
		assert(effects.preview(2, 7, forward)); f.tick(103.6, effects)
		assert(not f.pose.active(10)); f.restored()
		effects.destroy(); f.pose.destroy(); f.cast.destroy()
	end
end)
test("new life death and global pause cancel both sword and arrow preparations without writing gameplay movement", function()
	for _, which in { "melee", "arrow" } do
		for _, reason in { "life", "dead", "pause" } do
			local f = fixture()
			if which == "arrow" then f.classId = "warlock"; assert(f.cast.preview(10, 8, 7, forward))
			else assert(f.pose.preview(10, "melee", 8, 7, forward)) end
			f.tick(100.08)
			if reason == "life" then f.life = 8 elseif reason == "dead" then f.human.Health = 0 else f.rootData.Anchored = true end
			f.tick(100.1); assert(not f.cast.active(10) and not f.pose.active(10)); f.restored()
			assert(f.root.AssemblyLinearVelocity == Vector3.new(0, 4, -16)); f.pose.destroy(); f.cast.destroy()
		end
	end
end)
test("missing or invalid cast root restores the pose and does not abort later coordinator layers", function()
	for _, kind in { "missing", "wrong_type" } do
		local f = fixture(); f.classId = "warlock"
		assert(f.cast.preview(10, 31, 7, forward)); f.tick(100.08)
		assert(angle(f.motors.RightShoulder.Transform, f.base.RightShoulder) > 0.1)
		function f.character:FindFirstChild(name)
			if name == "UpperTorso" then return {} end
			if name == "HumanoidRootPart" and kind == "wrong_type" then return { IsA = function() return false end } end
			return nil
		end
		local run = f.game:GetService("RunService")
		run.PreAnimation, run.PreSimulation = signal(), signal()
		local Layers = module("PoseLayers", { game = f.game, workspace = f.world })
		local visited = 0
		local layers = Layers.new({ f.pose, f.cast, { beforePose = function() end, afterPose = function() visited += 1 end } })
		run.PreSimulation.fire(1 / 60)
		assert(visited == 1 and not f.cast.active(10), "Invalid root aborted the shared pose coordinator")
		f.restored(); layers.destroy(); f.pose.destroy(); f.cast.destroy()
	end
end)

test("arrow preview confirms with the same request without lowering the hands or restarting its gathering phase", function()
	local f = fixture(); f.classId = "warlock"
	assert(f.cast.preview(10, 31, 7, forward)); f.tick(100.05)
	assert(angle(f.motors.RightShoulder.Transform, f.base.RightShoulder) > 0.1)
	f.tick(100.3); local before = f.motors.RightShoulder.Transform
	f.cast.begin(10, 100.85, forward, 100.15, 31)
	assert(f.motors.RightShoulder.Transform == before)
	f.tick(100.3); assert(angle(f.motors.RightShoulder.Transform, before) < 0.00001)
	f.cast.cancelPreview(10, 31); assert(f.cast.active(10), "A late rejection erased an accepted arrow")
	f.tick(100.849); local gather = f.motors.RightShoulder.Transform
	f.tick(100.9); assert(angle(gather, f.motors.RightShoulder.Transform) > 0.1)
	f.pose.destroy(); f.cast.destroy(); f.restored()
end)
print(string.format("%d preparation feedback boundary tests passed", total))
