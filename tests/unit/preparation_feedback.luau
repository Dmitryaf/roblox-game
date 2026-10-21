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
local function fixture(nativeMode)
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
	f.native = { handles = {}, destroyed = 0 }
	dependencies.NativePoseTiming = module("NativePoseTiming", {})
	dependencies.NativePoseSampler = { new = function(source, clip)
		assert(source == character)
		local handle = { clip = clip.Name, destroyed = false, time = 0, prepared = false }
		function handle.prepare(time)
			assert(not handle.destroyed); handle.time, handle.prepared = time, true
		end
		function handle.capture() assert(not handle.destroyed and handle.prepared); handle.prepared = false end
		function handle.sample(joint)
			assert(not handle.destroyed and joint.Name ~= "RightHip" and joint.Name ~= "LeftHip", "Native pose touched running legs")
			return CFrame.Angles(handle.time, 0, 0)
		end
		function handle.destroy()
			assert(not handle.destroyed, "Native pose released its sampler twice")
			handle.destroyed = true; f.native.destroyed += 1
		end
		table.insert(f.native.handles, handle)
		return handle
	end }
	local clips = if nativeMode then { FindFirstChild = function(_, name)
		return { Name = name, IsA = function(_, kind) return kind == "AnimationClip" end }
	end } else nil
	local names = {}; for name in dependencies do names[name] = name end
	f.pose = module("MeleePose", { game = f.game, workspace = f.world, Vector3 = Vector3, CFrame = CFrame, script = { Parent = names },
		require = function(name) return assert(dependencies[name]) end }).new(true, clips)
	f.cast = module("CastPose", { game = f.game, workspace = f.world, Vector3 = Vector3, CFrame = CFrame,
		script = { Parent = names }, require = function(name) return assert(dependencies[name]) end }).new(function() return f.time end, true, clips)
	function f.tick(at, effects)
		f.time = at; f.pose.beforePose(); f.cast.beforePose()
		f.pose.preparePose(f.time); f.cast.preparePose(f.time)
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
local function nativeAction(which)
	local f = fixture(true)
	f.classId = if which == "arrow" then "warlock" else "warrior"
	f.human.MoveDirection = forward
	local action = if which == "arrow" then f.cast else f.pose
	local function preview(id)
		return if which == "arrow" then action.preview(10, id, 7, forward) else action.preview(10, "melee", id, 7, forward)
	end
	local function confirm(id)
		if which == "arrow" then action.begin(10, 100.7, forward, 100.1, id)
		else action.begin(10, 100.7, 100.1, 101.15, forward, 91, id) end
	end
	local function cancel(id)
		if which == "arrow" then action.cancelPreview(10, id) else action.cancelPreview(10, "melee", id) end
	end
	return f, action, preview, confirm, cancel
end

test("native sword and arrow adopt one preview sampler, keep its pose, and reach contact only at the accepted deadline", function()
	for _, which in { "melee", "arrow" } do
		local f, action, preview, confirm, cancel = nativeAction(which)
		assert(preview(41)); f.tick(100.1)
		assert(#f.native.handles == 1 and f.native.destroyed == 0)
		local handle = f.native.handles[1]
		local clipContact = if which == "arrow" then 0.708333313 else 0.458333343
		local beforeTime, beforePose = handle.time, f.motors.RightShoulder.Transform
		assert(beforeTime > 0 and beforeTime < clipContact * 0.32 and angle(beforePose, f.base.RightShoulder) > 0.01)
		confirm(41); f.tick(100.1)
		assert(#f.native.handles == 1 and f.native.destroyed == 0 and action.active(10))
		near(handle.time, beforeTime); assert(angle(beforePose, f.motors.RightShoulder.Transform) < 0.00001)
		cancel(41); assert(action.active(10) and not handle.destroyed, "Late rejection erased an accepted native pose")
		f.tick(100.699); assert(handle.time < clipContact)
		f.tick(100.7); near(handle.time, clipContact)
		assert(f.motors.LeftHip.Transform == f.base.LeftHip and f.motors.RightHip.Transform == f.base.RightHip)
		assert(f.root.AssemblyLinearVelocity == Vector3.new(0, 4, -16))
		f.tick(101.151); assert(not action.active(10) and handle.destroyed and f.native.destroyed == 1); f.restored()
		f.pose.destroy(); f.cast.destroy(); assert(f.native.destroyed == 1)
	end
end)

test("native preparation denial is request-scoped and releases its overlay and sampler once", function()
	for _, which in { "melee", "arrow" } do
		local f, action, preview, _, cancel = nativeAction(which)
		assert(preview(41)); f.tick(100.15)
		cancel(42); assert(action.active(10) and f.native.destroyed == 0)
		cancel(41); assert(not action.active(10) and f.native.destroyed == 1); f.restored()
		f.tick(100.9); assert(not action.active(10) and #f.native.handles == 1)
		f.pose.destroy(); f.cast.destroy(); assert(f.native.destroyed == 1)
	end
end)

test("native preview timeout and accepted or pending life death pause destroy paths release all resources", function()
	for _, which in { "melee", "arrow" } do
		for _, phase in { "pending", "accepted" } do
			for _, reason in { "timeout", "life", "death", "pause", "destroy" } do
				local f, action, preview, confirm = nativeAction(which)
				assert(preview(41)); if phase == "accepted" then confirm(41) end
				f.tick(100.15)
				assert(f.motors.LeftHip.Transform == f.base.LeftHip and f.motors.RightHip.Transform == f.base.RightHip)
				if reason == "life" then f.life = 8
				elseif reason == "death" then f.human.Health = 0
				elseif reason == "pause" then f.rootData.Anchored = true
				elseif reason == "destroy" then action.destroy() end
				f.tick(if reason == "timeout" then 103 else 100.2)
				assert(not action.active(10) and #f.native.handles == 1 and f.native.destroyed == 1,
					which .. " " .. phase .. " " .. reason .. " retained a native pose")
				f.restored(); assert(f.root.AssemblyLinearVelocity == Vector3.new(0, 4, -16))
				f.pose.destroy(); f.cast.destroy(); assert(f.native.destroyed == 1)
			end
		end
	end
end)

test("native sword Effects deduplicate authoritative events without replacing the adopted sampler", function()
	local f = fixture(true); local effects = f.effects()
	assert(effects.preview(41, 7, forward)); f.tick(100.1, effects)
	local event = { kind = "preparing", owner = 10, life = 7, swingId = 91, requestId = 41,
		direction = forward, startedAt = 100.1, hitAt = 100.7, expiresAt = 101.15 }
	effects.event(event); effects.event(table.clone(event)); effects.sync({table.clone(event)})
	assert(#f.native.handles == 1 and f.native.destroyed == 0)
	f.tick(100.699, effects); assert(f.count("WarriorSwing") == 0)
	f.tick(100.701, effects); assert(f.count("WarriorSwing") == 1)
	effects.destroy(); f.pose.destroy(); f.cast.destroy(); f.restored()
	assert(f.native.destroyed == 1)
end)
test("native cast preserves directional head focus and release-hand aim without rotating the root or legs", function()
	local straight, aimed = fixture(true), fixture(true)
	for _, f in {straight, aimed} do f.classId = "warlock" end
	straight.cast.begin(10, 100.7, forward, 100)
	aimed.cast.begin(10, 100.7, Vector3.new(0.5, 0.4, -1).Unit, 100)
	straight.tick(100.64); aimed.tick(100.64)
	assert(angle(straight.motors.Neck.Transform, aimed.motors.Neck.Transform) > 0.1)
	assert(angle(straight.motors.RightShoulder.Transform, aimed.motors.RightShoulder.Transform) < 0.00001)
	straight.tick(100.75); aimed.tick(100.75)
	assert(angle(straight.motors.RightShoulder.Transform, aimed.motors.RightShoulder.Transform) > 0.1)
	for _, f in {straight, aimed} do
		assert(f.motors.LeftHip.Transform == f.base.LeftHip and f.motors.RightHip.Transform == f.base.RightHip)
		f.tick(101.16); f.restored(); f.cast.destroy(); f.pose.destroy()
	end
end)
print(string.format("%d preparation feedback boundary tests passed", total))
