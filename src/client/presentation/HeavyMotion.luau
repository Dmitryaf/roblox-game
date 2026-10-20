--!strict
-- A deliberate upper-body coil and committed cleave. Legs remain the Animator's.
local Motion = {}
local times = { 0, 0.16, 0.36, 0.52, 0.65, 0.75, 0.94, 1.25 }
local function angles(x: number, y: number, z: number): Vector3
	return Vector3.new(math.rad(x), math.rad(y), math.rad(z))
end
Motion.channels = {
	{ names = { "Waist", "RootJoint" }, body = true, keys = {
		angles(0, 0, 0), angles(-8, -18, 4), angles(-12, -43, 7), angles(-15, -62, 9),
		angles(-3, 4, -5), angles(11, 54, -11), angles(-2, 26, -3), angles(0, 0, 0),
	} },
	{ names = { "Neck" }, body = true, keys = {
		angles(0, 0, 0), angles(1, 6, -2), angles(3, 14, -3), angles(5, 21, -4),
		angles(-3, -4, 2), angles(-2, -17, 4), angles(1, -7, 1), angles(0, 0, 0),
	} },
	{ names = { "RightShoulder", "Right Shoulder" }, body = false, keys = {
		angles(-8, -4, 10), angles(24, -35, 32), angles(49, -74, 58), angles(68, -98, 72),
		angles(0, 7, -29), angles(-28, 102, -52), angles(-12, 48, -24), angles(-8, -4, 10),
	} },
	{ names = { "RightElbow" }, body = false, keys = {
		angles(23, 0, 0), angles(57, 0, 0), angles(91, 0, 0), angles(114, 0, 0),
		angles(17, 0, 0), angles(25, 0, 0), angles(63, 0, 0), angles(23, 0, 0),
	} },
	{ names = { "RightWrist" }, body = false, keys = {
		angles(-5, 0, 4), angles(-13, -8, 8), angles(-23, -16, 13), angles(-31, -24, 18),
		angles(0, -7, -11), angles(26, 19, -22), angles(8, 10, -5), angles(-5, 0, 4),
	} },
	{ names = { "LeftShoulder", "Left Shoulder" }, body = false, keys = {
		angles(8, 0, -8), angles(32, 12, -28), angles(51, 23, -40), angles(64, 31, -49),
		angles(48, -14, -26), angles(36, -32, 18), angles(20, -12, -2), angles(8, 0, -8),
	} },
	{ names = { "LeftElbow" }, body = false, keys = {
		angles(20, 0, 0), angles(53, 0, 0), angles(78, 0, 0), angles(99, 0, 0),
		angles(63, 0, 0), angles(42, 0, 0), angles(38, 0, 0), angles(20, 0, 0),
	} },
}
local function smooth(value: number): number
	value = math.clamp(value, 0, 1)
	return value * value * (3 - 2 * value)
end
function Motion.time(now: number, started: number, hitAt: number, expires: number): number
	return if now <= hitAt then math.clamp((now - started) / math.max(0.05, hitAt - started), 0, 1) * 0.65
		else 0.65 + math.clamp((now - hitAt) / math.max(0.05, expires - hitAt), 0, 1) * 0.6
end
function Motion.sample(keys: { Vector3 }, time: number): Vector3
	for index = 2, #times do
		if time <= times[index] then
			local span = times[index] - times[index - 1]
			local t = math.clamp((time - times[index - 1]) / span, 0, 1)
			local before = if index == 2 then Vector3.zero else (keys[index] - keys[index - 2]) / (times[index] - times[index - 2])
			local after = if index == #times then Vector3.zero else (keys[index + 1] - keys[index - 1]) / (times[index + 1] - times[index - 1])
			return keys[index - 1] * (2 * t^3 - 3 * t^2 + 1) + before * span * (t^3 - 2 * t^2 + t)
				+ keys[index] * (-2 * t^3 + 3 * t^2) + after * span * (t^3 - t^2)
		end
	end
	return keys[#keys]
end
function Motion.weight(time: number, receivedAge: number): number
	return smooth(time / 0.1) * smooth(receivedAge / 0.07) * (1 - smooth((time - 0.94) / 0.31))
end
return Motion
