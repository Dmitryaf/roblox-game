--!strict
-- Authored foot support yields smoothly to locomotion; no physical root writes.
local Locomotion = {}
Locomotion.joints = { "RightHip", "LeftHip", "RightKnee", "LeftKnee", "RightAnkle", "LeftAnkle" }
function Locomotion.weight(humanoid: Humanoid, root: BasePart?, previous: number, delta: number): number
    local target = 0
    if root and humanoid.FloorMaterial ~= Enum.Material.Air then
        local velocity = root.AssemblyLinearVelocity
        local horizontalSpeed = (velocity * Vector3.new(1, 0, 1)).Magnitude
        if humanoid.MoveDirection.Magnitude < 0.1 and math.abs(velocity.Y) < 2 then
            target = 1 - math.clamp((horizontalSpeed - 1) / 3, 0, 1)
        end
    end
    local weight = previous + (target - previous) * (1 - math.exp(-22 * math.clamp(delta, 0, 0.05)))
    -- A completed fade must leave the running joints exactly under Animator ownership.
    if target == 0 and weight < 0.001 then return 0 end
    return math.clamp(weight, 0, 1)
end
return Locomotion
