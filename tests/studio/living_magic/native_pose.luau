--!strict
-- Runs in each real client before the duel; never changes the production character.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Tests = {}
type Joint = Motor6D | AnimationConstraint
local function nameOf(joint: Joint): string
    if joint:IsA("AnimationConstraint") and joint.Attachment0 then
        return (string.gsub(joint.Attachment0.Name, "RigAttachment$", ""))
    end
    return joint.Name
end
local function angle(value: CFrame): number
    local _, radians = value:ToAxisAngle()
    return math.abs(radians)
end
local function samplers(): {[Instance]: boolean}
    local result = {}
    for _, child in workspace:GetChildren() do
        if child.Name == "LocalNativePoseSampler" then result[child] = true end
    end
    return result
end
function Tests.run()
    assert(RunService:IsClient() and RunService:IsStudio())
    local player = Players.LocalPlayer
    local character = player.Character or player.CharacterAdded:Wait()
    local root = character:WaitForChild("HumanoidRootPart", 10) :: BasePart
    local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid
    local sourceAnimator = humanoid:WaitForChild("Animator", 10) :: Animator
    local gameScripts = player:WaitForChild("PlayerScripts"):WaitForChild("Game")
    local loadModule = require :: any
    local Native = loadModule(gameScripts:WaitForChild("presentation"):WaitForChild("NativePoseSampler"))
    local clips = RS:WaitForChild("NativeCombatClips", 10)
    assert(clips, "Native clips were not included in the experiment")
    local joints: {[string]: Joint} = {}
    local rest: {[Joint]: CFrame} = {}
    for _, item in character:GetDescendants() do
        if item:IsA("Motor6D") or item:IsA("AnimationConstraint") then
            joints[nameOf(item)] = item
            rest[item] = if item:IsA("Motor6D") then item.C0 else (item.Attachment0 :: Attachment).CFrame
        end
    end
    local shoulder = joints.RightShoulder
    assert(shoulder and joints.LeftHip and joints.RightHip, "Native test requires an actual R15 rig")
    local sourceArchivable, sourceAnchored = character.Archivable, root.Anchored
    local sourceTracks: {[string]: boolean} = {}
    local trackEvent = sourceAnimator.AnimationPlayed:Connect(function(track)
        local animation = track.Animation
        if animation then sourceTracks[animation.AnimationId] = true end
    end)
    local baseline = samplers()
    local active: any = nil
    local preparing: RBXScriptConnection? = nil
    local capturing: RBXScriptConnection? = nil
    local function unchangedImmediately(action: () -> ())
        local rootBefore, jointBefore = root.CFrame, {}
        for _, joint in joints do jointBefore[joint] = joint.Transform end
        action()
        assert(root.CFrame == rootBefore, "Sampler wrote the authoritative character root")
        for joint, value in jointBefore do assert(joint.Transform == value, "Sampler wrote a live character joint") end
    end
    local ok, problem = xpcall(function()
        for _, spec in {
            {name = "WarriorStrike", windup = 0.27, contact = 0.458333343},
            {name = "WarlockCast", windup = 0.541666687, contact = 0.708333313},
        } do
            local clip = clips:FindFirstChild(spec.name)
            assert(clip and clip:IsA("AnimationClip"), "Missing native clip " .. spec.name)
            unchangedImmediately(function() active = Native.new(character, clip) end)
            assert(active, "Native sampler initialization failed for " .. spec.name)
            local clone: Model? = nil
            for rig in samplers() do
                if not baseline[rig] then
                    assert(clone == nil and rig:IsA("Model"), "Unexpected duplicate sampler rigs")
                    clone = rig :: Model
                end
            end
            assert(clone, "Native sampler rig absent")
            local parts = 0
            for _, item in clone:GetDescendants() do
                assert(not item:IsA("LuaSourceContainer") and not item:IsA("Humanoid"), "Sampler copied live behavior")
                if item:IsA("BasePart") then
                    parts += 1
                    assert(not item.CanQuery and not item.CanCollide and not item.CanTouch and item.Transparency == 1,
                        "Sampler geometry entered physics or presentation")
                end
            end
            assert(parts == 16, "Sampler must contain only the R15 body and root")
            local samplerAnimator = clone:FindFirstChildWhichIsA("Animator", true) :: Animator
            local desired, frames = 0, 0
            local frameError: string? = nil
            preparing = RunService.PreAnimation:Connect(function()
                local frameOK, failure = pcall(function() unchangedImmediately(function() active.prepare(desired) end) end)
                if not frameOK then frameError = tostring(failure) end
            end)
            capturing = RunService.PreSimulation:Connect(function()
                local frameOK, failure = pcall(function() unchangedImmediately(active.capture) end)
                if not frameOK then frameError = tostring(failure) end
                frames += 1
            end)
            local function seek(time: number): CFrame
                desired = time
                local target, deadline = frames + 5, os.clock() + 5
                repeat task.wait() until frameError or (frames >= target and active.sample(shoulder) ~= nil) or os.clock() >= deadline
                assert(not frameError, frameError)
                local value = active.sample(shoulder)
                assert(frames >= target and value, "Native Animator did not evaluate " .. spec.name)
                return value
            end
            assert(angle(seek(0)) < 0.01, "Native neutral sample is not neutral")
            local windup = seek(spec.windup)
            local contact = seek(spec.contact)
            assert(math.max(angle(windup), angle(contact)) > math.rad(15), "Native clip produced no meaningful arm movement")
            assert(angle(windup:ToObjectSpace(contact)) > math.rad(5), "Paused native track ignored seek across contact")
            local held = seek(spec.contact)
            assert(angle(held:ToObjectSpace(contact)) < 0.01, "Paused native clip continued advancing")
            assert(angle(seek(0)) < 0.01, "Backward seek failed to return to neutral")
            for _, name in {"LeftHip", "RightHip", "LeftKnee", "RightKnee", "LeftAnkle", "RightAnkle", "Root", "RootJoint"} do
                local joint = joints[name]
                if joint then assert(active.sample(joint) == nil, "Sampler exposed root or leg motion: " .. name) end
            end
            local tracks = samplerAnimator:GetPlayingAnimationTracks()
            assert(#tracks == 1, "Sampler did not use exactly one native track")
            local animation = tracks[1].Animation
            assert(animation and not sourceTracks[animation.AnimationId], "Native clip played on the replicated character Animator")
            for _, track in sourceAnimator:GetPlayingAnimationTracks() do
                assert(not track.Animation or track.Animation.AnimationId ~= animation.AnimationId, "Native playback escaped sampler")
            end
            if preparing then preparing:Disconnect(); preparing = nil end
            if capturing then capturing:Disconnect(); capturing = nil end
            unchangedImmediately(active.destroy)
            assert(clone.Parent == nil and active.sample(shoulder) == nil, "Destroyed sampler retained resources or samples")
            active.destroy(); active = nil
            for rig in samplers() do assert(baseline[rig], "Native sampler leaked after cleanup") end
            print("LIVING_NATIVE_CLIP_PASS", player.UserId, spec.name, "arm windup/contact radians", angle(windup), angle(contact))
        end
        assert(character.Archivable == sourceArchivable and root.Anchored == sourceAnchored, "Sampler changed live rig properties")
        for joint, value in rest do
            local current = if joint:IsA("Motor6D") then joint.C0 else (joint.Attachment0 :: Attachment).CFrame
            assert(current == value, "Sampler changed source rig rest frames")
        end
    end, debug.traceback)
    if preparing then preparing:Disconnect() end
    if capturing then capturing:Disconnect() end
    if active then active.destroy() end
    trackEvent:Disconnect()
    assert(ok, problem)
end
return Tests
