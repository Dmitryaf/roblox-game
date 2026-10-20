--!strict
-- Authored upper-body keys; the Animator keeps ownership of the running legs.
local Motion = {}
local times = { 0, 0.12, 0.22, 0.30, 0.37, 0.53, 0.75 }
local function angles(x: number, y: number, z: number): Vector3
    return Vector3.new(math.rad(x), math.rad(y), math.rad(z))
end
Motion.channels = {
    { names = { "Waist", "RootJoint" }, body = true, keys = {
        angles(0, 0, 0), angles(-6, -24, 5), angles(-12, -50, 8), angles(-2, 5, -4),
        angles(9, 43, -10), angles(-3, 13, -2), angles(0, 0, 0),
    } },
    { names = { "Neck" }, body = true, keys = {
        angles(0, 0, 0), angles(0, 8, -2), angles(2, 13, -3), angles(-2, -3, 2),
        angles(-1, -12, 3), angles(1, -3, 0), angles(0, 0, 0),
    } },
    { names = { "RightShoulder", "Right Shoulder" }, body = false, keys = {
        angles(-8, -4, 10), angles(26, -42, 35), angles(58, -84, 56), angles(0, 7, -29),
        angles(-22, 88, -43), angles(-10, 35, -18), angles(-8, -4, 10),
    } },
    { names = { "RightElbow" }, body = false, keys = {
        angles(23, 0, 0), angles(70, 0, 0), angles(104, 0, 0), angles(17, 0, 0),
        angles(20, 0, 0), angles(52, 0, 0), angles(23, 0, 0),
    } },
    { names = { "RightWrist" }, body = false, keys = {
        angles(-5, 0, 4), angles(-17, -12, 10), angles(-24, -19, 14), angles(0, -7, -11),
        angles(21, 14, -17), angles(5, 7, -3), angles(-5, 0, 4),
    } },
    { names = { "LeftShoulder", "Left Shoulder" }, body = false, keys = {
        angles(8, 0, -8), angles(27, 13, -25), angles(39, 19, -34), angles(35, -9, -19),
        angles(24, -22, 12), angles(13, -6, -5), angles(8, 0, -8),
    } },
    { names = { "LeftElbow" }, body = false, keys = {
        angles(20, 0, 0), angles(61, 0, 0), angles(79, 0, 0), angles(55, 0, 0),
        angles(37, 0, 0), angles(31, 0, 0), angles(20, 0, 0),
    } },
}
local function smooth(value: number): number
    value = math.clamp(value, 0, 1)
    return value * value * (3 - 2 * value)
end
function Motion.time(now: number, started: number, hitAt: number, expires: number): number
    return if now <= hitAt then math.clamp((now - started) / math.max(0.05, hitAt - started), 0, 1) * 0.3
        else 0.3 + math.clamp((now - hitAt) / math.max(0.05, expires - hitAt), 0, 1) * 0.45
end
function Motion.sample(keys: { Vector3 }, time: number): Vector3
    for index = 2, #times do
        if time <= times[index] then
            local span = times[index] - times[index - 1]
            local t = math.clamp((time - times[index - 1]) / span, 0, 1)
            local before = if index == 2 then Vector3.zero else (keys[index] - keys[index - 2]) / (times[index] - times[index - 2])
            local after = if index == #times then Vector3.zero else (keys[index + 1] - keys[index - 1]) / (times[index + 1] - times[index - 1])
            -- Continuous velocity through contact: the sword passes through, rather than stopping on each key.
            return keys[index - 1] * (2 * t^3 - 3 * t^2 + 1) + before * span * (t^3 - 2 * t^2 + t)
                + keys[index] * (-2 * t^3 + 3 * t^2) + after * span * (t^3 - t^2)
        end
    end
    return keys[#keys]
end
function Motion.weight(time: number, receivedAge: number): number
    -- Delayed confirmation blends in instead of popping straight to the middle key.
    return smooth(time / 0.085) * smooth(receivedAge / 0.07) * (1 - smooth((time - 0.53) / 0.22))
end
return Motion
