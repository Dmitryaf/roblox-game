--!strict
local Timing = require("../../build/test-source/client/presentation/NativePoseTiming")
local Timeline = require("../../build/test-source/client/presentation/PreparationTimeline")
local function near(a, b) assert(math.abs(a - b) < 0.00001, tostring(a) .. " ~= " .. tostring(b)) end
for _, clip in {{0.3, 0.45, 0.458333343, 1}, {0.7, 0.45, 0.708333313, 1.20833337}} do
    local windup, recovery, contact, finish = table.unpack(clip)
    near(Timing.time(10, 10, 10 + windup, 10 + windup + recovery, contact, finish), 0)
    near(Timing.time(10 + windup, 10, 10 + windup, 10 + windup + recovery, contact, finish), contact)
    near(Timing.time(20, 10, 10 + windup, 10 + windup + recovery, contact, finish), finish)
    local timeline = Timeline.new(10)
    local held = Timing.time(12, 10, math.huge, 12.5, contact, finish, timeline)
    assert(held < contact * 0.33)
    timeline.confirm(12, 12.12)
    near(Timing.time(12, 10, 12.12, 12.57, contact, finish, timeline), held)
    near(Timing.time(12.12, 10, 12.12, 12.57, contact, finish, timeline), contact)
end
print("PASS native clip contact follows server deadlines; preview holds and adopts without restart")
