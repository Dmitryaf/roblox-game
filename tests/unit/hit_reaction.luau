--!strict
local fs, luau, rb = require("@lune/fs"), require("@lune/luau"), require("@lune/roblox")
local Vector3, CFrame = rb.Vector3, rb.CFrame
local Motion = luau.load(fs.readFile("src/client/presentation/HitReactionMotion.luau"), { environment = { Vector3 = Vector3 } })()
local source = fs.readFile("src/client/presentation/HitReaction.luau")
local total = 0
local function test(name, run) run(); total += 1; print("PASS", name) end
local function difference(a, b) local _, angle = (a:Inverse() * b):ToAxisAngle(); return math.abs(angle) + (a.Position - b.Position).Magnitude end
local function fixture()
	local f = { time = 100, sounds = {}, bodies = {}, owners = {} }
	function f.body(life, training)
		local body = { life = life or 50, classId = "warrior", training = training == true, motors = {}, base = {} }
		body.model = { Parent = true, mockInstance = true }
		function body.model:IsA(kind) return kind == "Model" end
		function body.model:GetAttribute(name)
			return if name == "CombatLife" then body.life else if name == "CombatClass" then body.classId else if name == "TrainingTarget" then body.training else nil
		end
		local humanData = { Parent = body.model, Health = 100, WalkSpeed = 16, AutoRotate = true, MoveDirection = Vector3.new(0, 0, -1) }
		body.humanData = humanData
		body.human = setmetatable({}, { __index = humanData, __newindex = function(_, key) error("Reaction wrote Humanoid gameplay property: " .. key) end })
		local rootData = { Parent = body.model, Anchored = training == true, Position = Vector3.new(5, 3, 0), CFrame = CFrame.new(5, 3, 0),
			AssemblyLinearVelocity = Vector3.new(0, 6, -16), AssemblyAngularVelocity = Vector3.zero }
		body.rootData = rootData
		body.root = setmetatable({}, {
			__index = function(_, key) return if key == "IsA" then function(_, name) return name == "BasePart" end else rootData[key] end,
			__newindex = function(_, key) error("Reaction wrote root physics: " .. key) end,
		})
		function body.model:FindFirstChildOfClass() return body.human end
		function body.model:FindFirstChild(name) return if name == "HumanoidRootPart" then body.root else nil end
		local descendants = {}
		for index, name in { "Waist", "Neck", "RightShoulder", "LeftShoulder", "RightElbow", "LeftElbow", "RightWrist", "RightHip", "LeftHip" } do
			local motor = { Name = name, Parent = body.model, C0 = CFrame.Angles(0.1, 0.07, 0.04), Transform = CFrame.Angles(index * 0.02, 0.15, -0.04) }
			function motor:IsA(kind) return kind == "Motor6D" end
			body.motors[name], body.base[name] = motor, motor.Transform; table.insert(descendants, motor)
		end
		function body.model:GetDescendants() return descendants end
		body.player = { Character = body.model }
		if not training then f.owners[body.model] = body.player end
		table.insert(f.bodies, body); return body
	end
	local players = {}; function players:GetPlayerFromCharacter(model) return f.owners[model] end
	local game = {}; function game:GetService(name) assert(name == "Players"); return players end
	local world = {}; function world:GetServerTimeNow() return f.time end
	local instance = { new = function(kind)
		assert(kind == "Sound", "Reaction created physical/cosmetic geometry outside its sound owner")
		local sound = { destroyed = false, plays = 0 }
		function sound:Play() self.plays += 1 end
		function sound:Destroy() self.destroyed = true end
		table.insert(f.sounds, sound); return sound
	end }
	f.reaction = luau.load(source, { environment = { game = game, workspace = world, CFrame = CFrame, Vector3 = Vector3, Instance = instance,
		typeof = function(value) return if type(value) == "table" and value.mockInstance then "Instance" else typeof(value) end,
		script = { Parent = { HitReactionMotion = "Motion" } }, require = function(name) assert(name == "Motion"); return Motion end,
	} })().new()
	function f.event(body, kind, id)
		return { kind = if kind == "arrow" then "ended" else "contact", reason = if kind == "arrow" then "hit" else nil,
			style = if kind == "heavy" then "heavy" else nil, owner = 1, life = 2, swingId = id or 1, contactId = 1, castId = id or 1,
			targetModel = body.model, targetLife = body.life or 0, sourcePosition = body.root.Position + Vector3.new(0, 0, -10), contactAt = f.time }
	end
	function f.restored(body)
		for name, motor in body.motors do assert(difference(motor.Transform, body.base[name]) < 0.00001, "Native/action pose not restored: " .. name) end
	end
	function f.liveSounds() local n = 0; for _, sound in f.sounds do if not sound.destroyed then n += 1 end end; return n end
	return f
end
test("confirmed melee heavy and arrow contacts identify their exact target and deduplicate independently", function()
	local f = fixture(); local target, neighbour = f.body(50), f.body(51)
	for _, kind in { "melee", "heavy", "arrow" } do
		local event = f.event(target, kind, 1)
		assert(f.reaction.hit(event) and not f.reaction.hit(event), "Confirmed source identity was not deduplicated")
	end
	assert(#f.sounds == 3 and f.reaction.active(target.model) and not f.reaction.active(neighbour.model))
	f.time += 0.055; f.reaction.afterPose(f.time)
	assert(difference(target.motors.Waist.Transform, target.base.Waist) > 0.05)
	f.restored(neighbour); f.reaction.destroy(); f.restored(target); assert(f.liveSounds() == 0)
end)
test("the overlay composes after changing locomotion/attack bases and restores them without accumulating", function()
	local f = fixture(); local body = f.body(); assert(f.reaction.hit(f.event(body, "heavy")))
	for frame = 1, 16 do
		f.reaction.beforePose(); f.restored(body)
		for name, motor in body.motors do body.base[name] = CFrame.Angles(frame * 0.013, 0.2, -0.05); motor.Transform = body.base[name] end
		f.time += 0.016; f.reaction.afterPose(f.time, 0.016)
		assert(difference(body.motors.Waist.Transform, body.base.Waist) > 0.001)
		for _, name in { "RightElbow", "LeftElbow", "RightWrist", "RightHip", "LeftHip" } do assert(body.motors[name].Transform == body.base[name]) end
	end
	f.reaction.beforePose(); f.restored(body)
	assert(body.root.AssemblyLinearVelocity == Vector3.new(0, 6, -16) and body.human.WalkSpeed == 16 and body.human.AutoRotate)
	f.reaction.destroy(); f.restored(body)
end)
test("late confirmed contact receives a complete short local recoil but stale/wall/teleport/snapshot messages never invent a target", function()
	local f = fixture(); local body = f.body(); local event = f.event(body, "heavy")
	event.contactAt = 99.5; assert(f.reaction.hit(event))
	f.time = 100.1; f.reaction.afterPose(f.time); assert(f.reaction.active(body.model))
	for _, change in {
		{ contactAt = 98 }, { kind = "snapshot" }, { reason = "teleported", kind = "ended" }, { kind = "ended", reason = "hit", targetModel = false },
		{ targetLife = 49 }, { sourcePosition = Vector3.new(math.huge, 0, 0) }, { contactAt = 101 },
	} do
		local bad = f.event(body, "arrow", 2); for key, value in change do bad[key] = value end
		assert(not f.reaction.hit(bad), "Unconfirmed/mismatched target became a reaction")
	end
	f.time = 100.39; f.reaction.afterPose(f.time); assert(not f.reaction.active(body.model)); f.restored(body)
	f.time = 100.91; f.reaction.step(f.time); assert(f.liveSounds() == 0); f.reaction.destroy()
end)
test("death pause class life replacement removed model and destroy clear joints and contact sound immediately", function()
	for _, reason in { "dead", "paused", "class", "life", "replacement", "removed", "destroy" } do
		local f = fixture(); local body = f.body(); f.reaction.hit(f.event(body, "melee")); f.time += 0.055; f.reaction.afterPose(f.time)
		if reason == "dead" then body.humanData.Health = 0
		elseif reason == "paused" then body.rootData.Anchored = true
		elseif reason == "class" then body.classId = "warlock"
		elseif reason == "life" then body.life = 99
		elseif reason == "replacement" then body.player.Character = nil
		elseif reason == "removed" then body.model.Parent = nil
		else f.reaction.destroy() end
		f.reaction.afterPose(f.time); assert(not f.reaction.active(body.model) and f.liveSounds() == 0)
		f.restored(body); f.reaction.destroy()
	end
end)
test("an old-life cancel never erases the new life reaction on the same character model", function()
	local f = fixture(); local body = f.body(50); f.reaction.hit(f.event(body, "melee", 1))
	f.time += 0.03; f.reaction.afterPose(f.time)
	body.life = 51; assert(f.reaction.hit(f.event(body, "arrow", 2)))
	f.reaction.cancel(body.model, 50); assert(f.reaction.active(body.model))
	f.reaction.cancel(body.model, 51); assert(not f.reaction.active(body.model)); f.restored(body); f.reaction.destroy()
end)
test("simultaneous damage has bounded recoil and owned cues instead of escalating or creating body movement", function()
	local f = fixture(); local body = f.body()
	for name, motor in body.motors do motor.C0, motor.Transform, body.base[name] = CFrame.identity, CFrame.identity, CFrame.identity end
	for id = 1, 80 do assert(f.reaction.hit(f.event(body, "heavy", id))) end
	assert(f.liveSounds() == 4)
	f.time += 0.055; f.reaction.afterPose(f.time)
	local x, y, z = body.motors.Waist.Transform:ToOrientation()
	assert(math.abs(x) <= math.rad(18) + 0.00001 and math.abs(y) < 0.001 and math.abs(z) < 0.001)
	f.reaction.destroy(); f.restored(body); assert(f.liveSounds() == 0)
end)
test("target resource budget evicts an old target safely while keeping at most twelve current reactions", function()
	local f = fixture(); local first
	for index = 1, 13 do
		local body = f.body(index); first = first or body
		assert(f.reaction.hit(f.event(body, "melee", index))); f.time += 0.001
	end
	assert(not f.reaction.active(first.model) and f.liveSounds() == 12)
	local active = 0; for _, body in f.bodies do if f.reaction.active(body.model) then active += 1 end end
	assert(active == 12); f.reaction.destroy(); assert(f.liveSounds() == 0)
end)
test("a later external Animator write remains untouched on cleanup and an anchored training target is not treated as a paused player", function()
	local f = fixture(); local body = f.body(); f.reaction.hit(f.event(body, "melee")); f.time += 0.06; f.reaction.afterPose(f.time)
	local external = CFrame.Angles(0.5, 0.3, 0.1); body.motors.Waist.Transform = external; body.base.Waist = external
	f.reaction.cancel(body.model); f.restored(body)
	local dummy = f.body(0, true); dummy.classId = nil
	assert(f.reaction.hit(f.event(dummy, "arrow"))); f.time += 0.06; f.reaction.afterPose(f.time)
	assert(f.reaction.active(dummy.model) and dummy.root.Anchored)
	f.reaction.destroy(); f.restored(dummy)
end)
print(string.format("%d HitReaction lifecycle/composition tests passed", total))
