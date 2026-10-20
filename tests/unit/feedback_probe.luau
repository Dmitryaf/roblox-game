--!strict
-- Executes the real read-only Studio observer against controlled joint histories.
local fs, luau, rb = require("@lune/fs"), require("@lune/luau"), require("@lune/roblox")
local CFrame, Vector3 = rb.CFrame, rb.Vector3
local inputTypes = { MouseButton1 = "MouseButton1", Keyboard = "Keyboard" }
local source = fs.readFile("tests/studio/client/FeedbackProbe.luau")
local total = 0
local function test(name, run) run(); total += 1; print("PASS", name) end
local function signal()
    local listeners, event = {}, {}
    function event:Connect(callback)
        local connection = { Connected = true }; function connection:Disconnect() self.Connected = false end
        table.insert(listeners, { connection, callback }); return connection
    end
    function event.fire(...) for _, item in listeners do if item[1].Connected then item[2](...) end end end
    function event.count() local count = 0; for _, item in listeners do if item[1].Connected then count += 1 end end; return count end
    return event
end
local function fixture()
    local f = { time = 0, life = 7, classId = "warrior", motors = {}, attrs = {} }
    f.character = { Parent = true, ChildAdded = signal(), DescendantAdded = signal() }
    f.root = { Parent = f.character, Position = Vector3.zero, AssemblyLinearVelocity = Vector3.zero, ChildAdded = signal(), ChildRemoved = signal() }
    function f.root:IsA(kind) return kind == "BasePart" end
    function f.root:GetChildren() return {} end
    f.humanoid = { Health = 100, WalkSpeed = 16 }
    for _, name in { "Neck", "RightShoulder" } do
        local motor = { Parent = f.character, Name = name, Transform = CFrame.identity }
        function motor:IsA(kind) return kind == "Motor6D" end
        f.motors[name] = motor
    end
    function f.character:GetAttribute(name)
        if name == "CombatLife" then return f.life elseif name == "CombatClass" then return f.classId else return 0 end
    end
    function f.character:GetAttributeChangedSignal(name) f.attrs[name] = f.attrs[name] or signal(); return f.attrs[name] end
    function f.character:FindFirstChild(name) return if name == "HumanoidRootPart" then f.root else nil end
    function f.character:FindFirstChildOfClass() return f.humanoid end
    function f.character:GetDescendants() return { f.motors.Neck, f.motors.RightShoulder } end
    f.player = { Character = f.character, CharacterAdded = signal(), CharacterRemoving = signal() }
    f.run = { PreSimulation = signal(), PostSimulation = signal(), RenderStepped = signal(), Heartbeat = signal() }
    f.input = { InputBegan = signal() }; function f.input:GetFocusedTextBox() return nil end
    f.remote = { OnClientEvent = signal() }; function f.remote:IsA(kind) return kind == "RemoteEvent" end
    local replication = {}; function replication:FindFirstChild(name) return if name == "HeavyRemote" then f.remote else nil end
    local game = {}; function game:GetService(name) return if name == "RunService" then f.run else if name == "UserInputService" then f.input else replication end
    local world = {}; function world:GetServerTimeNow() return 100 + f.time end
    f.probe = luau.load(source, { environment = { game = game, workspace = world, Vector3 = Vector3, CFrame = CFrame,
        Enum = { UserInputType = inputTypes },
        os = { clock = function() return f.time end }, typeof = function(value) return if type(value) == "userdata" then typeof(value) else type(value) end,
    } })().new(f.player)
    function f.frame(dt, neck, arm)
        f.time += dt
        if neck then f.motors.Neck.Transform = neck end
        if arm then f.motors.RightShoulder.Transform = arm end
        f.run.PreSimulation.fire(); f.run.PostSimulation.fire(); f.run.RenderStepped.fire(); f.run.Heartbeat.fire()
    end
    function f.idle(duration, dt)
        local count = math.ceil(duration / (dt or 1 / 60))
        for _ = 1, count do f.frame(dt or 1 / 60) end
    end
    function f.press()
        f.input.InputBegan.fire({ UserInputType = inputTypes.Keyboard, KeyCode = { Name = "Q" } }, false)
    end
    function f.window() local inputs = f.probe.inspect().inputs; return inputs[#inputs] end
    function f.envelope(name)
        for _, entry in f.window().jointEnvelopes do if entry.joint == name then return entry end end
        error("No envelope for " .. name)
    end
    return f
end
test("quiet calibration retains the original angular/translation margins and detects immediate preparation before any server event", function()
    local f = fixture(); f.idle(0.7); assert(f.probe.inspect().calibration.ready)
    f.press(); local input = f.window(); assert(input.calibrated and input.historyMinimumSpan >= 0.5 and input.historyMinimumSamples >= 10)
    local envelope = f.envelope("Neck"); assert(envelope.angleThreshold == 0.035 and envelope.translationThreshold == 0.025)
    f.frame(0.03, CFrame.Angles(0.02, 0, 0)); assert(f.window().firstJointChange == nil)
    f.frame(0.03, CFrame.Angles(0.1, 0, 0))
    assert(f.window().firstJointChange - input.at <= 0.061 and f.window().firstJointChangeSimulation - input.at <= 0.061)
    local candidate = f.window().firstJointChange
    f.frame(0.25); f.remote.OnClientEvent.fire({ kind = "preparing", owner = 1, life = 7 })
    assert(f.window().firstJointChange == candidate and candidate < 100 + f.time)
    f.probe.destroy()
end)
test("natural accumulated rotation that crosses a frame-step threshold stays below its pre-input excursion plus margin", function()
    local f = fixture()
    for index = 0, 40 do f.frame(0.015, CFrame.Angles(-0.08 * (1 - index / 40), 0, 0)) end
    f.press(); local before = f.window().at
    assert(f.envelope("Neck").angleEnvelope > 0.075 and f.envelope("Neck").angleThreshold > 0.11)
    for index = 1, 20 do f.frame(0.0175, CFrame.Angles(index / 20 * 0.09, 0, 0)) end
    assert(f.window().maxRelativeToBaseline > 0.08 and f.window().firstJointChange == nil and f.window().firstJointChangeSimulation == nil)
    local acceptedAt = 100 + f.time; f.remote.OnClientEvent.fire({ kind = "preparing", owner = 1, life = 7 })
    f.frame(0.016, CFrame.Angles(0.3, 0, 0))
    assert(f.window().firstJointChange >= acceptedAt and f.window().firstJointChange - before > 0.3)
    f.probe.destroy()
end)
test("translation uses its own observed history envelope and a true action still crosses that envelope", function()
    local f = fixture()
    for index = 0, 40 do f.frame(0.015, CFrame.new(-0.04 * (1 - index / 40), 0, 0)) end
    f.press(); assert(f.envelope("Neck").translationThreshold > 0.06)
    f.frame(0.2, CFrame.new(0.05, 0, 0)); assert(f.window().firstJointChange == nil)
    f.frame(0.016, CFrame.new(0.1, 0, 0)); assert(f.window().firstJointChange ~= nil)
    f.probe.destroy()
end)
test("one naturally animated joint cannot inflate another joint's preparation threshold", function()
    local f = fixture()
    for index = 0, 40 do f.frame(0.015, CFrame.identity, CFrame.Angles(-1 * (1 - index / 40), 0, 0)) end
    f.press(); assert(f.envelope("Neck").angleThreshold == 0.035 and f.envelope("RightShoulder").angleThreshold > 1)
    f.frame(0.016, CFrame.Angles(0.08, 0, 0))
    assert(f.window().firstJointChange ~= nil); f.probe.destroy()
end)
test("a prior input/action cannot silently calibrate the next measurement and warmup explicitly recovers", function()
    local f = fixture(); f.idle(0.7); f.press(); f.frame(0.1, CFrame.Angles(0.8, 0, 0))
    f.frame(0.1, CFrame.identity); f.idle(0.6)
    assert(not f.probe.inspect().calibration.ready)
    f.idle(1.5); assert(f.probe.inspect().calibration.ready)
    f.press(); assert(f.window().calibrated and f.envelope("Neck").angleEnvelope < 0.001)
    f.probe.destroy()
end)
test("life/class changes discard old motion history and high frame rates retain a bounded one-second calibration", function()
    local f = fixture(); f.idle(0.7); f.life += 1; f.attrs.CombatLife.fire()
    assert(not f.probe.inspect().calibration.ready); f.idle(0.65, 0.001)
    local history = f.probe.inspect().calibration
    assert(history.ready and history.minimumSamples <= 300 and history.minimumSpan >= 0.5 and history.historySeconds == 1)
    f.classId = "warlock"; f.attrs.CombatClass.fire(); assert(not f.probe.inspect().calibration.ready)
    f.idle(0.65); assert(f.probe.inspect().calibration.ready)
    f.probe.destroy(); f.probe.destroy()
    for _, event in f.run do assert(event.count() == 0) end
    assert(f.input.InputBegan.count() == 0 and f.remote.OnClientEvent.count() == 0)
end)
test("a one-second history calibrates 15 Hz background rendering while retaining ten actual samples and half-second coverage", function()
    local f = fixture(); f.idle(0.6, 1 / 15)
    assert(not f.probe.inspect().calibration.ready, "Nine background frames must not silently meet a ten-sample requirement")
    f.idle(0.45, 1 / 15)
    local history = f.probe.inspect().calibration
    assert(history.ready and history.minimumSamples >= 10 and history.minimumSpan >= 0.5 and history.minimumSpan <= 1.001)
    f.press(); assert(f.window().calibrated and f.window().baselineSource == "last_rendered")
    f.probe.destroy()
end)
test("temporary coordinator restore at input is not a new visible action and genuine unconfirmed preparation still is", function()
    local f = fixture()
    local stance = CFrame.Angles(0.4, 0, 0)
    for _ = 1, 45 do f.frame(1 / 60, stance) end
    -- beforePose restores the Animator base. No rendered frame has shown this
    -- raw value; InputBegan happens here before afterPose restores the stance.
    f.motors.Neck.Transform = CFrame.identity
    f.press(); local input = f.window()
    assert(input.baselineSource == "last_rendered" and input.rawToRenderedAngleMax > 0.39)
    assert(f.envelope("Neck").rawToRenderedAngle > 0.39 and f.envelope("Neck").baselineAge < 0.001)
    f.frame(0.02, stance)
    assert(f.window().firstJointChange == nil and f.window().firstJointChangeSimulation == nil,
        "Returning the already presented stance was falsely counted as preparation")
    -- No server event exists: a genuine new pose must still be observable early.
    f.frame(0.02, CFrame.Angles(0.6, 0, 0))
    assert(f.window().firstJointChange ~= nil and f.window().firstJointChangeSimulation ~= nil)
    assert(f.window().firstJointChange - input.at < 0.041)
    f.probe.destroy()
end)
print(string.format("%d feedback probe measurement controls passed (read-only observer; not Studio)", total))
