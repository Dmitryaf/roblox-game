--!strict
-- Owns the physical mover and a finite directional allowance for delayed replication.
-- It never writes root.CFrame or grants unlimited high-speed movement.
local DashWorld = {}
type Body = { character: Model, root: BasePart, humanoid: Humanoid, trusted: CFrame }
type Lease = { direction: Vector3, remaining: number, untilAt: number, mover: LinearVelocity?, attachment: Attachment? }
function DashWorld.new(body: (number) -> Body?, permitted: (number, Vector3) -> boolean,
    barrier: (number, Vector3, Vector3) -> Vector3?)
    local leases: { [number]: Lease } = {}
    local dash = {}
    local function params(character: Model): RaycastParams
        local p = RaycastParams.new()
        p.FilterType, p.FilterDescendantsInstances = Enum.RaycastFilterType.Exclude, { character }
        p.RespectCanCollide = true
        return p
    end
    local function supported(b: Body, point: Vector3): boolean
        local height = if b.humanoid.RigType == Enum.HumanoidRigType.R6 then 3 else b.humanoid.HipHeight + b.root.Size.Y / 2
        local ground = workspace:Raycast(point + Vector3.new(0, 0.5, 0), Vector3.new(0, -height - 1.5, 0), params(b.character))
        return ground ~= nil and ground.Normal.Y >= 0.85
    end
    function dash.stop(owner: number, reason: string)
        local lease = leases[owner]
        if not lease then return end
        if lease.mover then lease.mover:Destroy(); lease.mover = nil end
        if lease.attachment then lease.attachment:Destroy(); lease.attachment = nil end
        -- Natural expiry still needs to admit already simulated packets in flight.
        if reason ~= "expired" then leases[owner] = nil end
    end
    function dash.start(owner: number, direction: Vector3, distance: number, duration: number, requestId: number?): (Vector3?, number?, string?)
        local b = body(owner)
        if not b or b.root.Anchored or b.humanoid.Health <= 0 then return nil, nil, "invalid_position" end
        if not supported(b, b.trusted.Position) or math.abs(b.root.AssemblyLinearVelocity.Y) > 8 then return nil, nil, "airborne" end
        local start = b.trusted.Position
        local size = Vector3.new(3, 3.5, 3)
        local p = params(b.character)
        local overlap = OverlapParams.new()
        overlap.FilterType, overlap.FilterDescendantsInstances = Enum.RaycastFilterType.Exclude, { b.character }
        for _, part in workspace:GetPartBoundsInBox(CFrame.new(start), size, overlap) do
            if part.CanCollide then return nil, nil, "blocked" end
        end
        -- The owner can keep walking while approval travels over the network.
        -- Reserve checked space for that ordinary movement, not more dash credit.
        local lookAhead = distance + 8
        local hit = workspace:Blockcast(CFrame.new(start), size, direction * lookAhead, p)
        local limit = if hit then math.max(0, hit.Distance - 0.35) else lookAhead
        local boundary = barrier(owner, start, direction * limit)
        if boundary then limit = math.min(limit, math.max(0, (boundary - start).Magnitude - 1.7)) end
        -- Sample the supported corridor; a dash is not a jump or a cliff escape.
        local reachable = 0
        local steps = math.max(1, math.ceil(limit / 0.5))
        for index = 1, steps do
            local along = limit * index / steps
            local point = start + direction * along
            local fits = permitted(owner, point) and supported(b, point + direction * 1.5)
            for _, x in { -1.5, 1.5 } do
                for _, z in { -1.5, 1.5 } do
                    if not permitted(owner, point + Vector3.new(x, 0, z)) then fits = false end
                end
            end
            if not fits then break end
            reachable = along
        end
        if reachable < 1 then return nil, nil, "blocked" end
        local travel = math.min(distance, reachable)
        dash.stop(owner, "replaced")
        local attachment = Instance.new("Attachment")
        attachment.Name, attachment.Parent = "WarriorDashAttachment", b.root
        local mover = Instance.new("LinearVelocity")
        mover.Name, mover.Attachment0 = "WarriorDashVelocity", attachment
        mover.RelativeTo = Enum.ActuatorRelativeTo.World
        mover.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
        mover.PrimaryTangentAxis, mover.SecondaryTangentAxis = Vector3.xAxis, Vector3.zAxis
        mover.PlaneVelocity = Vector2.new(direction.X, direction.Z) * (distance / duration)
        mover.ForceLimitsEnabled = false
        mover:SetAttribute("DashDirection", direction)
        mover:SetAttribute("DashOrigin", start)
        mover:SetAttribute("DashDistance", travel)
        mover:SetAttribute("DashLimit", start + direction * reachable)
        mover:SetAttribute("DashSpeed", distance / duration)
        leases[owner] = { direction = direction, remaining = travel,
            untilAt = os.clock() + duration * travel / distance + 0.8, mover = mover, attachment = attachment }
        mover:SetAttribute("DashRequestId", requestId)
        mover:SetAttribute("DashLife", b.character:GetAttribute("CombatLife"))
        mover.Parent = b.root
        return start, travel, nil
    end
    function dash.allowance(owner: number, delta: Vector3): Vector3
        local lease = leases[owner]
        if not lease then return Vector3.zero end
        if os.clock() > lease.untilAt then dash.stop(owner, "expired_lease"); return Vector3.zero end
        -- Normal walking pays for sideways/backwards movement; extra credit is directional.
        return lease.direction * math.min(lease.remaining, math.max(0, delta:Dot(lease.direction)))
    end
    function dash.consume(owner: number, amount: number)
        local lease = leases[owner]
        if lease then lease.remaining = math.max(0, lease.remaining - amount) end
    end
    return dash
end
return DashWorld
