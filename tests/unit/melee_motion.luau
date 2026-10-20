--!strict
local fs, luau, roblox = require("@lune/fs"), require("@lune/luau"), require("@lune/roblox")
local Vector3, CFrame = roblox.Vector3, roblox.CFrame
-- Compile unchanged presentation modules; supply Roblox value types, not rewritten motion rules.
local Motion = luau.load(fs.readFile("src/client/presentation/MeleeMotion.luau"), { environment = { Vector3 = Vector3 } })()
local Facing = luau.load(fs.readFile("src/client/presentation/MeleeFacing.luau"), { environment = { Vector3 = Vector3, CFrame = CFrame } })()
local total = 0
local function test(name, run) run(); total += 1; print("PASS", name) end
local function near(actual, expected, tolerance) assert(math.abs(actual - expected) <= (tolerance or 0.000001), tostring(actual) .. " ~= " .. tostring(expected)) end
local function vectorNear(actual, expected, tolerance) assert((actual - expected).Magnitude <= (tolerance or 0.000001)) end
local function finite(value)
	for _, n in { value.X, value.Y, value.Z } do assert(n == n and math.abs(n) < 1000, "Motion produced a nonfinite/unbounded vector") end
end
local function angle(a, b) return math.acos(math.clamp(a:Dot(b), -1, 1)) end
local function fixture(originalAutoRotate)
	local f = { writes = {}, velocityWrites = 0 }
	local initialPosition = Vector3.new(0, 3, 0)
	local data = { CFrame = CFrame.new(initialPosition), AssemblyLinearVelocity = Vector3.new(2, 0, -1), Parent = true, Anchored = false }
	local humanoid = { Parent = true, AutoRotate = if originalAutoRotate == nil then true else originalAutoRotate,
		Health = 100, MoveDirection = Vector3.new(0, 0, 0) }
	local root = setmetatable({}, {
		__index = function(_, key)
			if key == "Position" then return data.CFrame.Position end
			if key == "IsA" then return function(_, class) return class == "BasePart" end end
			return data[key]
		end,
		__newindex = function(_, key, value)
			if key == "Position" then error("Facing directly wrote a position") end
			if key == "AssemblyLinearVelocity" then f.velocityWrites += 1 end
			if key == "CFrame" then table.insert(f.writes, { before = data.CFrame.Position, after = value.Position, velocity = data.AssemblyLinearVelocity }) end
			data[key] = value
		end,
	})
	local character = {}
	function character:FindFirstChildOfClass() return humanoid end
	function character:FindFirstChild() return if data.Parent then root else nil end
	function f.move(position, velocity)
		-- Emulate an independent simulation step between presentation callbacks.
		data.CFrame = CFrame.new(position) * data.CFrame.Rotation
		data.AssemblyLinearVelocity = velocity
	end
	f.root, f.humanoid, f.character, f.data = root, humanoid, character, data
	return f
end

test("Facing preserves live moving positions and velocities on every bounded turn", function()
	local f = fixture()
	local facing = Facing.new(f.character, Vector3.new(1, 0.6, 0)); assert(facing and not f.humanoid.AutoRotate)
	assert(#f.writes == 0)
	for index, delta in { 1 / 60, 0.02, 0.1, 0.006, 0.034, 0 } do
		local position, velocity = Vector3.new(index * 0.37, 3 + index * 0.04, -index * 0.2), Vector3.new(index, 0.5, -index * 2)
		f.move(position, velocity)
		local before = f.root.CFrame.LookVector
		facing.step(index * 0.02, 1, delta)
		local after = f.root.CFrame.LookVector
		vectorNear(f.root.Position, position); vectorNear(f.root.AssemblyLinearVelocity, velocity)
		assert(f.velocityWrites == 0 and after.X >= before.X - 0.000001 and after.X > 0, "Facing turned away from rightward aim")
		assert(angle(before, after) <= 9 * math.clamp(delta, 0, 0.05) + 0.0005, "Facing exceeded its per-frame angular limit")
		near(after.Y, 0)
	end
	for _, write in f.writes do vectorNear(write.before, write.after) end
	facing.destroy(); assert(f.humanoid.AutoRotate)
end)
test("Facing turns with the correct sign on either side without snapping to aim", function()
	for _, side in { -1, 1 } do
		local f = fixture(); local facing = Facing.new(f.character, Vector3.new(side, 0, 0)); assert(facing)
		facing.step(0, 0.3, 1 / 60)
		local look = f.root.CFrame.LookVector
		assert(look.X * side > 0 and math.abs(look.X) < 0.2 and look.Z < -0.9)
		local previousError = angle(look, Vector3.new(side, 0, 0))
		for frame = 1, 20 do
			facing.step(frame / 60, 10, 1 / 60)
			local error = angle(f.root.CFrame.LookVector, Vector3.new(side, 0, 0))
			assert(error <= previousError + 0.0005); previousError = error
		end
		assert(previousError < 0.03); facing.destroy()
	end
end)
test("Facing holds attack direction through contact then recovers toward actual movement", function()
	local f = fixture(); f.data.CFrame = CFrame.lookAt(f.root.Position, f.root.Position + Vector3.new(1, 0, 0))
	f.humanoid.MoveDirection = Vector3.new(0, 0, -1)
	local facing = Facing.new(f.character, Vector3.new(1, 0, 0)); assert(facing)
	facing.step(1.05, 1, 0.05); vectorNear(f.root.CFrame.LookVector, Vector3.new(1, 0, 0))
	facing.step(1.4, 1, 0.05)
	assert(f.root.CFrame.LookVector.Z < -0.1 and f.root.CFrame.LookVector.X > 0)
	facing.destroy()
end)
test("Anchored, dead, removed and stopped roots receive no position/rotation/velocity writes", function()
	for _, condition in { "anchored", "dead", "removed", "stopped" } do
		local f = fixture(); local facing = Facing.new(f.character, Vector3.new(1, 0, 0)); assert(facing)
		if condition == "anchored" then f.data.Anchored = true
		elseif condition == "dead" then f.humanoid.Health = 0
		elseif condition == "removed" then f.data.Parent = nil
		else facing.destroy() end
		local before, velocity = f.root.CFrame, f.root.AssemblyLinearVelocity
		facing.step(0.2, 0.3, 0.05)
		assert(#f.writes == 0 and f.root.CFrame == before and f.root.AssemblyLinearVelocity == velocity and f.velocityWrites == 0)
		facing.destroy(); assert(f.humanoid.AutoRotate)
	end
end)
test("Facing restores the original AutoRotate false and rejects partial/vertical input without ownership", function()
	local f = fixture(false); local facing = Facing.new(f.character, Vector3.new(1, 0, 0)); assert(facing)
	facing.destroy(); facing.destroy(); assert(not f.humanoid.AutoRotate)
	for _, direction in { Vector3.new(0, 1, 0), Vector3.new(0.05, -1, 0), Vector3.new(0, 0, 0) } do
		local invalid = fixture(); assert(Facing.new(invalid.character, direction) == nil)
		assert(invalid.humanoid.AutoRotate and #invalid.writes == 0)
	end
	local partial = fixture(); partial.data.Parent = nil
	assert(Facing.new(partial.character, Vector3.new(1, 0, 0)) == nil and partial.humanoid.AutoRotate)
end)
test("Motion follows authoritative hit/expiry times and clamps outside the action", function()
	near(Motion.time(9, 10, 10.3, 10.75), 0)
	near(Motion.time(10, 10, 10.3, 10.75), 0)
	near(Motion.time(10.15, 10, 10.3, 10.75), 0.15)
	near(Motion.time(10.3, 10, 10.3, 10.75), 0.3)
	near(Motion.time(10.525, 10, 10.3, 10.75), 0.525)
	near(Motion.time(10.75, 10, 10.3, 10.75), 0.75)
	near(Motion.time(100, 10, 10.3, 10.75), 0.75)
	near(Motion.time(20.6, 20, 20.6, 21.5), 0.3)
	near(Motion.time(21.5, 20, 20.6, 21.5), 0.75)
end)
test("Every authored channel remains finite and position/velocity continuous across keys", function()
	assert(#Motion.channels == 7)
	for _, channel in Motion.channels do
		assert(#channel.keys == 7)
		for index = 0, 750 do finite(Motion.sample(channel.keys, index / 1000)) end
		for _, at in { 0.12, 0.22, 0.3, 0.37, 0.53 } do
			local center = Motion.sample(channel.keys, at)
			local function derivatives(step)
				return (center - Motion.sample(channel.keys, at - step)) / step, (Motion.sample(channel.keys, at + step) - center) / step
			end
			local left, right = derivatives(0.0002)
			local coarseLeft, coarseRight = derivatives(0.001)
			finite(left); finite(right)
			assert((Motion.sample(channel.keys, at - 0.0002) - Motion.sample(channel.keys, at + 0.0002)).Magnitude < 0.03,
				"Authored channel has a position discontinuity at " .. tostring(at))
			assert((right - left).Magnitude < (coarseRight - coarseLeft).Magnitude * 0.3 + 0.015,
				"Left/right velocities do not converge at " .. tostring(at) .. ": " .. channel.names[1])
		end
	end
end)
test("Sword shoulder passes through authoritative contact with nonzero continuous speed", function()
	local shoulder = nil
	for _, channel in Motion.channels do if table.find(channel.names, "RightShoulder") then shoulder = channel end end
	assert(shoulder)
	local dt = 0.0002
	local before = Motion.sample(shoulder.keys, Motion.time(10.3 - dt, 10, 10.3, 10.75))
	local contact = Motion.sample(shoulder.keys, Motion.time(10.3, 10, 10.3, 10.75))
	local after = Motion.sample(shoulder.keys, Motion.time(10.3 + dt, 10, 10.3, 10.75))
	local entering, leaving = (contact - before) / dt, (after - contact) / dt
	assert(entering.Magnitude > 5 and leaving.Magnitude > 5 and entering:Dot(leaving) > 0)
	assert(before.Y < contact.Y and contact.Y < after.Y, "Contact became a stopped/reversed shoulder key")
	assert((leaving - entering).Magnitude < 0.2)
end)
test("Motion fades in/out with zero weight and late confirmations blend rather than pop", function()
	near(Motion.weight(0, 1), 0); near(Motion.weight(0.75, 1), 0); near(Motion.weight(-1, 1), 0); near(Motion.weight(1, 1), 0)
	near(Motion.weight(0.3, 0), 0)
	local previous = 0
	for index = 0, 70 do
		local value = Motion.weight(0.3, index / 1000)
		assert(value >= previous - 0.000001 and value >= 0 and value <= 1)
		previous = value
	end
	near(previous, 1)
	assert(Motion.weight(0.3, 0.001) < 0.001)
	for _, channel in Motion.channels do
		local late = Motion.sample(channel.keys, 0.38) * Motion.weight(0.38, 0)
		local nextFrame = Motion.sample(channel.keys, 0.381) * Motion.weight(0.381, 0.001)
		vectorNear(late, Vector3.zero); assert(nextFrame.Magnitude < 0.003)
		local startSlope = (Motion.sample(channel.keys, 0.0002) * Motion.weight(0.0002, 1)).Magnitude / 0.0002
		local endSlope = (Motion.sample(channel.keys, 0.7498) * Motion.weight(0.7498, 1)).Magnitude / 0.0002
		assert(startSlope < 0.1 and endSlope < 0.1, "Motion envelope starts/stops with an impulse")
	end
end)
print(string.format("%d MeleeMotion/Facing engine-boundary tests passed", total))
