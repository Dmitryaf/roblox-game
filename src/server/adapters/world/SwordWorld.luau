--!strict
local SwordWorld = {}
function SwordWorld.new(world: any)
    return {
        impact = function(target: Humanoid): Vector3?
            local model = target.Parent
            local root = if model then model:FindFirstChild("HumanoidRootPart") else nil
            return if root and root:IsA("BasePart") then root.Position + Vector3.yAxis * 0.6 else nil
        end,
        targets = function(owner: number, direction: Vector3, range: number, arcDegrees: number): { Humanoid }
            local origin = world.origin(owner)
            if not origin then return {} end
            local center = origin - Vector3.yAxis
            local threshold = math.cos(math.rad(arcDegrees / 2))
            local result = {}
            for _, target in world.areaTargets(owner, center, range) do
                local model = target.Parent
                local root = if model then model:FindFirstChild("HumanoidRootPart") else nil
                if not root or not root:IsA("BasePart") then continue end
                local delta = root.Position - center
                local flat = delta * Vector3.new(1, 0, 1)
                if math.abs(delta.Y) <= 4 and flat.Magnitude <= range
                    and (flat.Magnitude < 0.01 or flat.Unit:Dot(direction) >= threshold) then
                    table.insert(result, target)
                end
            end
            return result
        end,
    }
end
return SwordWorld
