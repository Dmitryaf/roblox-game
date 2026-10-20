--!strict
-- Contact feedback comes only from confirmed server damage, never an empty swing.
local Players = game:GetService("Players")
local MeleeImpact = {}
type Fragment = { part: Part, origin: Vector3, velocity: Vector3, rotation: CFrame }
type Burst = { folder: Folder, owner: number, life: number, swingId: number, at: number, parts: { Fragment } }
function MeleeImpact.new(parent: Instance)
    local bursts: { [string]: Burst } = {}
    local retired: { [string]: number } = {}
    local impact = {}
    local function remove(key: string)
        local burst = bursts[key]
        if not burst then return end
        burst.folder:Destroy(); bursts[key] = nil
    end
    function impact.hit(event: any)
        local now = workspace:GetServerTimeNow()
        if not event.position or not event.contactId or now - event.hitAt > 0.35 then return end
        local key = event.owner .. ":" .. event.life .. ":" .. event.swingId .. ":" .. event.contactId
        if retired[key] then return end
        retired[key] = now + 1
        local count, oldest, oldestAt = 0, nil, math.huge
        for id, burst in bursts do
            count += 1
            if burst.at < oldestAt then oldest, oldestAt = id, burst.at end
        end
        if count >= 12 and oldest then remove(oldest) end
        local folder = Instance.new("Folder")
        folder.Name, folder.Parent = "ConfirmedSwordImpact", parent
        local parts: { Fragment } = {}
        local direction = event.direction * Vector3.new(1, 0, 1)
        direction = if direction.Magnitude > 0.1 then direction.Unit else Vector3.new(0, 0, -1)
        local right = Vector3.new(-direction.Z, 0, direction.X)
        for index = 1, 12 do
            local angle = index * math.pi * 2 / 12
            local axis = right * math.cos(angle) + Vector3.yAxis * math.sin(angle)
            local shard = Instance.new("Part")
            shard.Name, shard.Size, shard.Material = "SwordContactSpark", Vector3.new(0.07, 0.07, 0.55 + index % 3 * 0.2), Enum.Material.Neon
            shard.Color = if index % 3 == 0 then Color3.fromRGB(166, 61, 39) else Color3.fromRGB(255, 220, 160)
            shard.Anchored, shard.Massless, shard.CanCollide, shard.CanTouch, shard.CanQuery, shard.CastShadow = true, true, false, false, false, false
            local origin = event.position - direction * 0.35
            shard.CFrame, shard.Parent = CFrame.lookAt(origin, origin + axis), folder
            table.insert(parts, { part = shard, origin = origin, velocity = axis * (6 + index % 4 * 2) - direction * 2,
                rotation = shard.CFrame.Rotation })
        end
        local core = Instance.new("Part")
        core.Name, core.Shape, core.Size = "SwordContactFlash", Enum.PartType.Ball, Vector3.new(1.2, 1.2, 1.2)
        core.Anchored, core.Massless, core.CanCollide, core.CanQuery, core.CanTouch, core.CastShadow = true, true, false, false, false, false
        core.Color, core.Material, core.Transparency = Color3.fromRGB(255, 226, 172), Enum.Material.Neon, 0.35
        core.CFrame, core.Parent = CFrame.new(event.position), folder
        table.insert(parts, { part = core, origin = event.position, velocity = Vector3.zero, rotation = CFrame.identity })
        local sound = Instance.new("Sound")
        sound.Name, sound.SoundId, sound.Volume = "SwordContactWeight", "rbxasset://sounds/warrior-v1/impact.wav", 0.5
        sound.RollOffMinDistance, sound.RollOffMaxDistance, sound.Parent = 8, 70, core
        sound:Play()
        bursts[key] = { folder = folder, owner = event.owner, life = event.life, swingId = event.swingId, at = now, parts = parts }
    end
    function impact.cancel(owner: number, swingId: number)
        for key, burst in bursts do if burst.owner == owner and burst.swingId == swingId then remove(key) end end
    end
    function impact.step(now: number)
        for key, untilAt in retired do if now >= untilAt then retired[key] = nil end end
        for key, burst in bursts do
            local owner = Players:GetPlayerByUserId(burst.owner)
            local character = if owner then owner.Character else nil
            local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
            local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
            local age = now - burst.at
            if age >= 0.42 or not character or character:GetAttribute("CombatLife") ~= burst.life
                or character:GetAttribute("CombatClass") ~= "warrior" or not humanoid or humanoid.Health <= 0
                or not root or not root:IsA("BasePart") or root.Anchored then remove(key); continue end
            for _, item in burst.parts do
                local flash = item.part.Name == "SwordContactFlash"
                local duration = if flash then 0.10 else 0.28
                local fade = math.clamp(age / duration, 0, 1)
                item.part.Transparency = if flash then 0.35 + fade * 0.65 else fade
                item.part.CFrame = CFrame.new(item.origin + item.velocity * age + (if flash then Vector3.zero else Vector3.new(0, -11 * age * age, 0))) * item.rotation
            end
        end
    end
    function impact.destroy()
        for key in bursts do remove(key) end
        table.clear(retired)
    end
    return impact
end
return MeleeImpact
