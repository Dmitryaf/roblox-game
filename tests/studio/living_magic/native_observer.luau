--!strict
-- Observe the production path after isolated sampler tests have finished.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Observer = {}
type ActorStats = { frames: number, samplers: number, maxHandDisplacement: number }
type Actor = { character: Model, key: string, firstHand: Vector3 }
local function rigs(): { Model }
    local result = {}
    for _, child in workspace:GetChildren() do
        if child:IsA("Model") and child.Name == "LocalNativePoseSampler" then table.insert(result, child) end
    end
    return result
end
local function handPosition(character: Model): Vector3?
    local root, hand = character:FindFirstChild("HumanoidRootPart"), character:FindFirstChild("RightHand")
    if root and root:IsA("BasePart") and hand and hand:IsA("BasePart") then
        return root.CFrame:PointToObjectSpace(hand.Position)
    end
    return nil
end
function Observer.new()
    local nativeFrames, nativeSamples, maxConcurrent = 0, 0, 0
    local geometryViolations, replicationViolations, actorMatchFailures = 0, 0, 0
    local failure: string? = nil
    local nativeIds: { [string]: boolean } = {}
    local actors: { [string]: ActorStats } = {}
    local active: { [Model]: Actor } = {}
    local seen: { [Model]: boolean } = {}
    local stopped = false
    local function fail(message: string)
        if not failure then failure = message end
    end
    local function associate(rig: Model): Actor?
        local sourceRoot = rig:FindFirstChild("HumanoidRootPart")
        if not sourceRoot or not sourceRoot:IsA("BasePart") then return nil end
        local nearest, distance = nil :: Player?, 4
        for _, player in Players:GetPlayers() do
            local character = player.Character
            local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
            if root and root:IsA("BasePart") then
                local gap = (root.Position - sourceRoot.Position).Magnitude
                if gap < distance then nearest, distance = player, gap end
            end
        end
        local character = if nearest then nearest.Character else nil
        local firstHand = if character then handPosition(character) else nil
        if not nearest or not character or not firstHand then return nil end
        local key = tostring(nearest.UserId)
        if not actors[key] then actors[key] = { frames = 0, samplers = 0, maxHandDisplacement = 0 } end
        actors[key].samplers += 1
        return { character = character, key = key, firstHand = firstHand }
    end
    local function observe()
        local live = rigs()
        maxConcurrent = math.max(maxConcurrent, #live)
        if #live > 0 then nativeFrames += 1 end
        local present: { [Model]: boolean } = {}
        for _, rig in live do
            present[rig] = true
            nativeSamples += 1
            if not seen[rig] then
                seen[rig] = true
                local actor = associate(rig)
                if actor then active[rig] = actor end
                if not actor then actorMatchFailures += 1; fail("Production sampler has no nearby actor") end
            end
            for _, item in rig:GetDescendants() do
                if item:IsA("BasePart") and (item.CanQuery or item.CanTouch or item.CanCollide or item.Transparency ~= 1) then
                    geometryViolations += 1
                    fail("Production sampler geometry became visible or interactive")
                elseif item:IsA("Animator") then
                    for _, track in item:GetPlayingAnimationTracks() do
                        local animation = track.Animation
                        if animation then nativeIds[animation.AnimationId] = true end
                    end
                end
            end
            local actor = active[rig]
            if actor then
                local position = handPosition(actor.character)
                if position then
                    local stats = actors[actor.key]
                    stats.frames += 1
                    stats.maxHandDisplacement = math.max(stats.maxHandDisplacement, (position - actor.firstHand).Magnitude)
                end
            end
        end
        for rig in seen do if not present[rig] then active[rig], seen[rig] = nil, nil end end
        for _, player in Players:GetPlayers() do
            local character = player.Character
            local animator = if character then character:FindFirstChildWhichIsA("Animator", true) else nil
            if animator and animator:IsA("Animator") then
                for _, track in animator:GetPlayingAnimationTracks() do
                    local animation = track.Animation
                    if animation and nativeIds[animation.AnimationId] then
                        replicationViolations += 1
                        fail("Native sampler animation appeared on a real character Animator")
                    end
                end
            end
        end
    end
    local connection = RunService.RenderStepped:Connect(function()
        if stopped then return end
        local ok, problem = pcall(function(): any observe(); return true end)
        if not ok then fail("Native observer failed: " .. tostring(problem)) end
    end)
    local observer = {}
    function observer.inspect()
        local actorSnapshot: { [string]: ActorStats } = {}
        for key, value in actors do actorSnapshot[key] = table.clone(value) end
        local ids = {}
        for id in nativeIds do table.insert(ids, id) end
        table.sort(ids)
        return { nativeFrames = nativeFrames, nativeSamples = nativeSamples, maxConcurrent = maxConcurrent,
            live = #rigs(), geometryViolations = geometryViolations, replicationViolations = replicationViolations,
            actorMatchFailures = actorMatchFailures, actors = actorSnapshot, nativeIds = ids, failure = failure }
    end
    function observer.destroy()
        if stopped then return end
        stopped = true
        connection:Disconnect()
        table.clear(active)
        table.clear(seen)
    end
    return observer
end
return Observer
