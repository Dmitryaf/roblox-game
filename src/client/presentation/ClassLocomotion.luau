--!strict
-- Upper-body stance over the Animator. PoseLayers owns frame order and action priority.
local Players = game:GetService("Players")
local ClassLocomotion = {}
type Motor = Motor6D | AnimationConstraint
type Joint = { motor: Motor, rest: CFrame, channel: string, base: CFrame?, applied: CFrame?, filtered: CFrame? }
type Entry = { character: Model, humanoid: Humanoid, root: BasePart, classId: string, life: any,
    joints: { Joint }, weight: number, movement: number, refreshed: number, visible: boolean }
type Options = { isActing: (Model) -> boolean }
local names = {
    Waist = "waist", Neck = "neck", RightShoulder = "right", ["Right Shoulder"] = "right",
    LeftShoulder = "left", ["Left Shoulder"] = "left", RightElbow = "rightElbow", LeftElbow = "leftElbow",
    RightWrist = "rightWrist", LeftWrist = "leftWrist",
}
local function radians(x: number, y: number, z: number): Vector3
    return Vector3.new(math.rad(x), math.rad(y), math.rad(z))
end
local function transform(motor: Motor, value: CFrame)
    if motor:IsA("Motor6D") then motor.Transform = value else (motor :: AnimationConstraint).Transform = value end
end
local function restore(joint: Joint)
    if joint.motor.Parent and joint.base and joint.applied and joint.motor.Transform == joint.applied then
        transform(joint.motor, joint.base)
    end
    joint.applied = nil
end
local function clear(entry: Entry)
    for _, joint in entry.joints do restore(joint) end
    entry.visible = false
end
local function collect(entry: Entry)
    local previous: { [Instance]: Joint } = {}
    for _, joint in entry.joints do previous[joint.motor] = joint end
    local joints: { Joint } = {}
    for _, candidate in entry.character:GetDescendants() do
        if not candidate:IsA("Motor6D") and not candidate:IsA("AnimationConstraint") then continue end
        local attachment = if candidate:IsA("AnimationConstraint") then candidate.Attachment0 else nil
        local channel = names[candidate.Name]
        if not channel and attachment then channel = names[attachment.Name:gsub("RigAttachment$", "")] end
        if not channel then continue end
        local old = previous[candidate]
        if old then table.insert(joints, old); previous[candidate] = nil
        else
            local rest = if candidate:IsA("Motor6D") then candidate.C0.Rotation
                else if attachment then attachment.CFrame.Rotation else CFrame.identity
            table.insert(joints, { motor = candidate, rest = rest, channel = channel })
        end
    end
    for _, joint in previous do restore(joint) end
    entry.joints = joints
end
local function angles(classId: string, channel: string, movement: number, now: number): Vector3
    -- Breathing is slow and small: no root bobbing and no replacement walk cycle.
    local breath = math.sin(now * 1.9)
    if classId == "warrior" then
        if channel == "waist" then return radians(-2 - movement * 4 + breath * 0.6, -4, 1) end
        if channel == "neck" then return radians(1 + movement * 2 - breath * 0.3, 3, -1) end
        if channel == "right" then return radians(-9 - movement * 4 + breath * 0.7, -8, 9) end
        if channel == "left" then return radians(5 + movement * 3 - breath * 0.8, 4, -7) end
        if channel == "rightElbow" then return radians(23 + movement * 7, 0, 0) end
        if channel == "leftElbow" then return radians(14 + movement * 4, 0, 0) end
        if channel == "rightWrist" then return radians(-5, 0, 4) end
        return radians(0, 0, -2)
    end
    if channel == "waist" then return radians(-1 - movement * 3 + breath * 1.2, 2, breath * 0.6) end
    if channel == "neck" then return radians(-2 - breath * 0.5, -2, 0) end
    if channel == "right" then return radians(5 + breath * 2 - movement * 3, -6, 13 + breath) end
    if channel == "left" then return radians(10 - breath * 1.5 - movement * 3, 5, -16 + breath) end
    if channel == "rightElbow" then return radians(18 + breath * 2, 0, 0) end
    if channel == "leftElbow" then return radians(27 - breath * 2, 0, 0) end
    if channel == "rightWrist" then return radians(-8 - breath, -5, 5) end
    return radians(-11 + breath, 4, -5)
end
function ClassLocomotion.new(options: Options)
    local entries: { [number]: Entry } = {}
    local stopped = false
    local stance = {}
    function stance.beforePose()
        for _, entry in entries do for _, joint in entry.joints do restore(joint) end end
    end
    function stance.afterPose(now: number, delta: number?)
        if stopped then return end
        local dt = math.clamp(delta or 1 / 60, 0, 0.1)
        local fade, follow = 1 - math.exp(-dt / 0.18), 1 - math.exp(-dt / 0.1)
        local seen: { [number]: boolean } = {}
        for _, player in Players:GetPlayers() do
            local owner, character = player.UserId, player.Character
            seen[owner] = true
            local entry = entries[owner]
            local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
            local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
            local classId = if character then character:GetAttribute("CombatClass") else nil
            local life = if character then character:GetAttribute("CombatLife") else nil
            local valid = character ~= nil and character.Parent ~= nil and humanoid ~= nil and humanoid.Health > 0
                and root ~= nil and root:IsA("BasePart") and not root.Anchored
                and (classId == "warrior" or classId == "warlock")
            if entry and (not valid or character ~= entry.character or life ~= entry.life or classId ~= entry.classId) then
                clear(entry); entries[owner] = nil
                -- Never carry the old life's filtered arm/stance into a new life or class.
                continue
            end
            if not valid or not character or not humanoid or not root or not root:IsA("BasePart") then continue end
            if not entry then
                local created: Entry = { character = character, humanoid = humanoid, root = root, classId = classId :: string, life = life,
                    joints = {}, weight = 0, movement = 0, refreshed = now, visible = false }
                collect(created); entries[owner] = created; entry = created
            end
            if not entry then continue end
            if now - entry.refreshed >= 0.5 then collect(entry); entry.refreshed = now end
            if options.isActing(character) then
                clear(entry); entry.weight = 0
                for _, joint in entry.joints do joint.filtered = nil end
                continue
            end
            entry.weight += (1 - entry.weight) * fade
            entry.movement += (math.clamp(humanoid.MoveDirection.Magnitude, 0, 1) - entry.movement) * follow
            entry.visible = entry.weight > 0.001 and #entry.joints > 0
            for _, joint in entry.joints do
                if not joint.motor.Parent then continue end
                -- Also safe on throttled Animator frames or explicit repeated coordinator steps.
                restore(joint)
                local base = joint.motor.Transform
                local a = angles(entry.classId, joint.channel, entry.movement, now)
                local rotation = joint.rest:Inverse() * CFrame.Angles(a.X, a.Y, a.Z) * joint.rest
                local animated = base
                if joint.channel == "right" or joint.channel == "left" then
                    -- Inertial shoulders retain the native rig basis and running motion while
                    -- reducing the fast weapon wag; legs and the authoritative root stay native.
                    joint.filtered = if joint.filtered then joint.filtered:Lerp(base, follow) else base
                    local damping = (if entry.classId == "warrior" then 0.55 else 0.2) * entry.movement
                    animated = base:Lerp(joint.filtered :: CFrame, damping)
                end
                joint.base = base
                joint.applied = base:Lerp(rotation * animated, entry.weight)
                transform(joint.motor, joint.applied :: CFrame)
            end
        end
        for owner, entry in entries do
            if not seen[owner] then clear(entry); entries[owner] = nil end
        end
    end
    function stance.active(owner: number): boolean
        local entry = entries[owner]
        return not stopped and entry ~= nil and entry.visible
    end
    function stance.destroy()
        if stopped then return end
        stopped = true
        for owner, entry in entries do clear(entry); entries[owner] = nil end
    end
    return stance
end
return ClassLocomotion
