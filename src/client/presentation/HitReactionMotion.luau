--!strict
-- Short visual recoil only: no recovery lock, root movement or gameplay timing.
local Motion = {}
local profiles = {
	melee = { duration = 0.26, body = 9, shoulders = 7 },
	heavy = { duration = 0.38, body = 15, shoulders = 11 },
	arrow = { duration = 0.32, body = 12, shoulders = 9 },
}
local function smooth(value: number): number
	value = math.clamp(value, 0, 1)
	return value * value * (3 - 2 * value)
end
function Motion.duration(kind: string): number
	return (profiles :: any)[kind].duration
end
function Motion.sample(kind: string, role: string, age: number, away: Vector3): Vector3
	local profile = (profiles :: any)[kind]
	local weight = if age < 0 then 0 else smooth(age / 0.035) * (1 - smooth((age - 0.055) / (profile.duration - 0.055)))
	local pitch = away.Z * math.rad(profile.body)
	local roll = -away.X * math.rad(profile.body * 0.8)
	local angles: Vector3
	if role == "torso" then angles = Vector3.new(pitch, away.X * math.rad(3), roll)
	elseif role == "neck" then angles = Vector3.new(-pitch * 0.32, -away.X * math.rad(2), -roll * 0.22)
	else
		local side = if role == "right" then 1 else -1
		angles = Vector3.new(pitch * 0.45 - math.rad(3), side * away.X * math.rad(2), side * math.rad(profile.shoulders))
	end
	return angles * weight
end
return Motion
