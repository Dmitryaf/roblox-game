--!strict
-- A short upper-body brace, drive and brake; the Animator owns the running legs.
local Motion = {}
local times = { 0, 0.06, 0.14, 0.22, 0.28 }
local function angles(x: number, y: number, z: number): Vector3
	return Vector3.new(math.rad(x), math.rad(y), math.rad(z))
end
Motion.channels = {
	{ names = { "Waist", "RootJoint" }, body = true, keys = {
		angles(0, 0, 0), angles(-16, -4, 2), angles(-32, -5, 3), angles(-12, 3, -2), angles(0, 0, 0),
	} },
	{ names = { "Neck" }, body = true, keys = {
		angles(0, 0, 0), angles(7, 2, -1), angles(12, 3, -2), angles(-2, -1, 1), angles(0, 0, 0),
	} },
	{ names = { "RightShoulder", "Right Shoulder" }, body = false, keys = {
		angles(0, 0, 0), angles(32, -20, 24), angles(46, -26, 20), angles(22, 4, 10), angles(0, 0, 0),
	} },
	{ names = { "RightElbow" }, body = false, keys = {
		angles(0, 0, 0), angles(55, 0, 0), angles(72, 0, 0), angles(38, 0, 0), angles(0, 0, 0),
	} },
	{ names = { "LeftShoulder", "Left Shoulder" }, body = false, keys = {
		angles(0, 0, 0), angles(26, 14, -23), angles(40, 20, -28), angles(18, -4, -12), angles(0, 0, 0),
	} },
	{ names = { "LeftElbow" }, body = false, keys = {
		angles(0, 0, 0), angles(50, 0, 0), angles(75, 0, 0), angles(34, 0, 0), angles(0, 0, 0),
	} },
}
local function smooth(value: number): number
	value = math.clamp(value, 0, 1)
	return value * value * (3 - 2 * value)
end
function Motion.time(now: number, started: number, expires: number): number
	return math.clamp((now - started) / math.max(0.05, expires - started), 0, 1) * 0.28
end
function Motion.sample(keys: { Vector3 }, time: number): Vector3
	for index = 2, #times do
		if time <= times[index] then
			return keys[index - 1]:Lerp(keys[index], smooth((time - times[index - 1]) / (times[index] - times[index - 1])))
		end
	end
	return keys[#keys]
end
function Motion.weight(time: number): number
	return smooth(time / 0.035) * (1 - smooth((time - 0.22) / 0.06))
end
return Motion
