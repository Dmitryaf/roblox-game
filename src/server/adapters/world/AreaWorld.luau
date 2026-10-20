--!strict
-- Ground projection and real occupant queries; gameplay timing stays in HandsService.
local Players = game:GetService("Players")
local AreaWorld = {}
function AreaWorld.new(world: any, policy: any)
    local function characters(extra: Instance?): { Instance }
        local ignore: { Instance } = {}
        for _, player in Players:GetPlayers() do if player.Character then table.insert(ignore, player.Character) end end
        if extra then table.insert(ignore, extra) end
        return ignore
    end
    local function rayParams(extra: Instance?): RaycastParams
        local p = RaycastParams.new()
        p.FilterType, p.FilterDescendantsInstances = Enum.RaycastFilterType.Exclude, characters(extra)
        p.RespectCanCollide = true
        return p
    end
    local function visible(a: Vector3, b: Vector3, extra: Instance?): boolean
        return workspace:Raycast(a, b - a, rayParams(extra)) == nil
    end
    local function bounded(owner: number, position: Vector3): boolean
        return if policy then policy.contains(owner, position) and policy.allowed(owner, position)
            else math.abs(position.X) < 77 and math.abs(position.Z) < 77 and position.Y > 1 and position.Y < 24
    end
    return {
        placement = function(owner: number, requested: Vector3, range: number, radius: number): (Vector3?, string?)
            local origin = world.origin(owner)
            if not origin then return nil, "invalid_position" end
            local p = rayParams(nil)
            local ground = workspace:Raycast(requested + Vector3.yAxis * 3, -Vector3.yAxis * 8, p)
            if not ground or ground.Normal.Y < 0.85 or ground.Instance:FindFirstAncestorOfClass("Model") then return nil, "invalid_target" end
            local center = ground.Position
            if (center + Vector3.yAxis - origin).Magnitude > range then return nil, "out_of_range" end
            if math.abs(center.Y - (origin.Y - 4)) > 4 then return nil, "invalid_target" end
            if not bounded(owner, center + Vector3.yAxis * 3) or not visible(origin, center + Vector3.yAxis, nil) then return nil, "invalid_target" end
            if policy and policy.barrier(owner, origin, center + Vector3.yAxis - origin) then return nil, "invalid_target" end
            -- Require the whole footprint to stay supported and outside protected pads/walls.
            for i = 1, 8 do
                local angle = i * math.pi / 4
                local edge = center + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
                if not bounded(owner, edge + Vector3.yAxis * 3) then return nil, "invalid_target" end
                if policy and policy.barrier(owner, center + Vector3.yAxis, edge - center) then return nil, "invalid_target" end
                local support = workspace:Raycast(edge + Vector3.yAxis * 2, -Vector3.yAxis * 4, p)
                if not support or support.Normal.Y < 0.85 or math.abs(support.Position.Y - center.Y) > 1 then return nil, "invalid_target" end
            end
            return center, nil
        end,
        targets = function(owner: number, center: Vector3, radius: number): { Humanoid }
            if not world.alive(owner) then return {} end
            local result: { Humanoid } = {}
            local seen: { [Humanoid]: boolean } = {}
            local nearby = workspace:GetPartBoundsInRadius(center + Vector3.yAxis * 2, radius + 3)
            for _, part in nearby do
                local model = part:FindFirstAncestorOfClass("Model")
                local humanoid = if model then model:FindFirstChildOfClass("Humanoid") else nil
                local root = if model then model:FindFirstChild("HumanoidRootPart") else nil
                if not model or not humanoid or seen[humanoid] or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then continue end
                seen[humanoid] = true
                local player = Players:GetPlayerFromCharacter(model)
                if player and (player.UserId == owner or not world.alive(player.UserId) or not world.validate(player.UserId)) then continue end
                if not player and model:GetAttribute("TrainingTarget") ~= true then continue end
                if policy and not policy.damageAllowed(owner, if player then player.UserId else nil, humanoid) then continue end
                local delta = root.Position - center
                if Vector3.new(delta.X, 0, delta.Z).Magnitude > radius or math.abs(delta.Y) > 6 then continue end
                if not visible(center + Vector3.yAxis * 2, root.Position, model) then continue end
                table.insert(result, humanoid)
            end
            return result
        end,
    }
end
return AreaWorld
