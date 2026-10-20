--!strict
-- Only the owning client turns its live body. Never replay a server position.
local Facing = {}
function Facing.new(character: Model, direction: Vector3): { step: (number, number, number) -> (), destroy: () -> () }?
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local root = character:FindFirstChild("HumanoidRootPart")
    if not humanoid or not root or not root:IsA("BasePart") then return nil end
    local original = humanoid.AutoRotate
    local flat = direction * Vector3.new(1, 0, 1)
    if flat.Magnitude < 0.1 then return nil end
    local aim = flat.Unit
    local stopped = false
    humanoid.AutoRotate = false
    local facing = {}
    function facing.step(now: number, hitAt: number, delta: number)
        if stopped or not root.Parent or humanoid.Health <= 0 or root.Anchored then return end
        local desired = aim
        local moving = humanoid.MoveDirection * Vector3.new(1, 0, 1)
        if now > hitAt + 0.09 and moving.Magnitude > 0.1 then
            local recovery = math.clamp((now - hitAt - 0.09) / 0.22, 0, 1)
            local mixed = aim:Lerp(moving.Unit, recovery)
            if mixed.Magnitude > 0.1 then desired = mixed.Unit end
        end
        local look = root.CFrame.LookVector * Vector3.new(1, 0, 1)
        if look.Magnitude < 0.1 then return end
        look = look.Unit
        local error = math.atan2(look:Cross(desired).Y, look:Dot(desired))
        local dt = math.clamp(delta, 0, 0.05)
        local turn = math.clamp(error * (1 - math.exp(-18 * dt)), -9 * dt, 9 * dt)
        local rotation = CFrame.fromAxisAngle(Vector3.yAxis, turn)
        local nextDirection = rotation:VectorToWorldSpace(look)
        -- Read the current simulated position at the moment of the write; velocity is untouched.
        local position = root.Position
        root.CFrame = CFrame.lookAt(position, position + nextDirection)
    end
    function facing.destroy()
        if stopped then return end
        stopped = true
        if humanoid.Parent and humanoid.AutoRotate == false then humanoid.AutoRotate = original end
    end
    return facing
end
return Facing
