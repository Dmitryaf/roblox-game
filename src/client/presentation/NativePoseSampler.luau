--!strict
-- Studio-only native evaluation, isolated from the replicated character Animator.
local Sampler = {}
type Joint = Motor6D | AnimationConstraint
type Pair = { source: Joint, copy: Joint, neutral: CFrame?, delta: CFrame?, support: boolean? }
type Handle = { prepare: (number) -> (), capture: () -> (), sample: (Joint) -> CFrame?, support: (Joint) -> CFrame?, destroy: () -> () }
local registered: { [AnimationClip]: string } = {}
local bodyParts: { [string]: boolean } = {
    HumanoidRootPart = true, Head = true, UpperTorso = true, LowerTorso = true,
    LeftUpperArm = true, LeftLowerArm = true, LeftHand = true,
    RightUpperArm = true, RightLowerArm = true, RightHand = true,
    LeftUpperLeg = true, LeftLowerLeg = true, LeftFoot = true,
    RightUpperLeg = true, RightLowerLeg = true, RightFoot = true,
}
local sampledBody: { [string]: boolean } = {
    Waist = true, Neck = true, LeftShoulder = true, RightShoulder = true,
    LeftElbow = true, RightElbow = true, LeftWrist = true, RightWrist = true,
    LeftHip = true, RightHip = true, LeftKnee = true, RightKnee = true,
    LeftAnkle = true, RightAnkle = true,
}
local function jointName(joint: Joint): string
    if joint:IsA("AnimationConstraint") and joint.Attachment0 then
        return (string.gsub(joint.Attachment0.Name, "RigAttachment$", ""))
    end
    return joint.Name
end
local function reset(joint: Joint)
    if joint:IsA("Motor6D") then joint.Transform = CFrame.identity
    else (joint :: AnimationConstraint).Transform = CFrame.identity end
end
function Sampler.new(character: Model, clip: AnimationClip): Handle?
    local RunService = game:GetService("RunService")
    if not RunService:IsStudio() or not RunService:IsClient() or not character.Parent then return nil end
    local Provider = game:GetService("AnimationClipProvider")
    local root = character:FindFirstChild("HumanoidRootPart")
    if not root or not root:IsA("BasePart") or not character:FindFirstChild("UpperTorso") then return nil end
    local rig = Instance.new("Model")
    rig.Name = "LocalNativePoseSampler"
    local track: AnimationTrack? = nil
    local animation = Instance.new("Animation")
    local pairs: { [Joint]: Pair } = {}
    local animator: Animator? = nil
    local ok, problem = pcall(function()
        local copies: { [Instance]: Instance } = {}
        -- Only body parts are cloned; nothing is parented into Workspace until sanitized.
        for _, source in character:GetChildren() do
            if not source:IsA("BasePart") or not bodyParts[source.Name] then continue end
            local copy = source:Clone()
            assert(copy, "Body part is not archivable")
            copy.Parent = rig
            copies[source] = copy
            for _, child in copy:GetChildren() do child:Destroy() end
            for _, original in source:GetChildren() do
                if original:IsA("Attachment") or original:IsA("Motor6D") or original:IsA("AnimationConstraint") then
                    local child = original:Clone()
                    assert(child, "Joint or attachment is not archivable")
                    copies[original] = child
                    -- Attachments/joints have no presentation descendants in the sampler.
                    for _, nested in child:GetChildren() do nested:Destroy() end
                    (child :: Instance).Parent = copy
                end
            end
            copy.Transparency, copy.CastShadow = 1, false
            if copy:IsA("MeshPart") then copy.TextureID = "" end
            copy.CanCollide, copy.CanTouch, copy.CanQuery = false, false, false
            copy.Anchored, copy.Massless = source == root, true
            copy.AssemblyLinearVelocity, copy.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
        end
        assert(copies[root], "Missing sampler root")
        for original, copy in copies do
            if copy:IsA("Motor6D") and original:IsA("Motor6D") then
                local part0, part1 = original.Part0, original.Part1
                assert(part0 and part1, "Missing joint parts")
                local copy0, copy1 = copies[part0], copies[part1]
                assert(copy0 and copy0:IsA("BasePart") and copy1 and copy1:IsA("BasePart"), "Joint leaves sampler skeleton")
                copy.Part0, copy.Part1 = copy0, copy1
                reset(copy)
                local name = jointName(original)
                local support = name == "Root" or name == "RootJoint"
                if sampledBody[name] or support then pairs[original] = { source = original, copy = copy, support = support } end
            elseif copy:IsA("AnimationConstraint") and original:IsA("AnimationConstraint") then
                local attachment0, attachment1 = original.Attachment0, original.Attachment1
                assert(attachment0 and attachment1, "Missing constraint attachments")
                local copy0, copy1 = copies[attachment0], copies[attachment1]
                assert(copy0 and copy0:IsA("Attachment") and copy1 and copy1:IsA("Attachment"), "Constraint leaves sampler skeleton")
                copy.Attachment0, copy.Attachment1 = copy0, copy1
                reset(copy)
                local name = jointName(original)
                local support = name == "Root" or name == "RootJoint"
                if sampledBody[name] or support then pairs[original] = { source = original, copy = copy, support = support } end
            end
        end
        assert(next(pairs), "No sampled body joints")
        local controller = Instance.new("AnimationController")
        controller.Parent = rig
        local nativeAnimator = Instance.new("Animator")
        nativeAnimator.PreferLodEnabled = false
        nativeAnimator.Parent = controller
        animator = nativeAnimator
        rig.Parent = workspace
        local id = registered[clip]
        if not id then id = Provider:RegisterAnimationClip(clip); registered[clip] = id end
        animation.AnimationId = id
        local nativeTrack = nativeAnimator:LoadAnimation(animation)
        track = nativeTrack
        nativeTrack.Looped = false
        nativeTrack:Play(0, 1, 0)
    end)
    if not ok then
        if track then track:Destroy() end
        animation:Destroy(); rig:Destroy()
        warn("Native pose sampler unavailable: " .. tostring(problem))
        return nil
    end
    local stopped, neutralReady, prepared = false, false, false
    local sampler = {}
    function sampler.prepare(time: number)
        prepared = false
        local current = track
        if stopped or not current or not current.IsPlaying or current.Length <= 0 then return end
        -- The first evaluated frame establishes the engine's neutral/retargeting basis.
        current.TimePosition = if neutralReady then math.clamp(time, 0, math.max(0, current.Length - 0.0001)) else 0
        prepared = true
    end
    function sampler.capture()
        if stopped or not prepared or not animator or animator.EvaluationThrottled then return end
        prepared = false
        for _, pair in pairs do
            local value = pair.copy.Transform
            if not neutralReady then pair.neutral, pair.delta = value, CFrame.identity
            elseif pair.neutral then pair.delta = value * pair.neutral:Inverse() end
        end
        neutralReady = true
    end
    function sampler.sample(joint: Joint): CFrame?
        if stopped or not neutralReady then return nil end
        local pair = pairs[joint]
        return if pair and not pair.support then pair.delta else nil
    end
    function sampler.support(joint: Joint): CFrame?
        if stopped or not neutralReady then return nil end
        local pair = pairs[joint]
        if not pair or not pair.support or not pair.delta then return nil end
        -- The visual LowerTorso may settle with authored bent knees. This is
        -- bounded translation on the rig joint, never physical HRP root motion.
        local position = pair.delta.Position
        for _, value in {position.X, position.Y, position.Z} do
            if value ~= value or math.abs(value) == math.huge then return nil end
        end
        return CFrame.new(math.clamp(position.X, -0.15, 0.15), math.clamp(position.Y, -0.5, 0.1), math.clamp(position.Z, -0.15, 0.15))
    end
    function sampler.destroy()
        if stopped then return end
        stopped = true
        if track then track:Stop(0); track:Destroy(); track = nil end
        animation:Destroy(); rig:Destroy()
        table.clear(pairs)
    end
    return sampler
end
return Sampler
