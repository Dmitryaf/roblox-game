--!strict
-- Local procedural overlay; the base Roblox locomotion remains active.
local Players = game:GetService("Players")
local CastPose = {}
function CastPose.new()
	local poses: { [number]: { joint: Motor6D, base: CFrame, started: number, release: number } } = {}
	local pose = {}
	function pose.stop(owner: number)
		local current = poses[owner]
		if current and current.joint.Parent then current.joint.C0 = current.base end
		poses[owner] = nil
	end
	function pose.begin(owner: number, release: number)
		pose.stop(owner)
		local player = Players:GetPlayerByUserId(owner)
		local character = if player then player.Character else nil
		if not character then return end
		local joint = character:FindFirstChild("RightShoulder", true) or character:FindFirstChild("Right Shoulder", true)
		if joint and joint:IsA("Motor6D") then
			poses[owner] = { joint = joint, base = joint.C0, started = workspace:GetServerTimeNow(), release = release }
		end
	end
	function pose.step(now: number)
		for owner, current in poses do
			if not current.joint.Parent or now > current.release + 0.24 then pose.stop(owner); continue end
			local t = if now < current.release then math.clamp((now - current.started) / 0.2, 0, 1)
				else 1 - math.clamp((now - current.release) / 0.24, 0, 1)
			local weight = t * t * (3 - 2 * t)
			current.joint.C0 = current.base * CFrame.Angles(math.rad(-72) * weight, 0, math.rad(16) * weight)
		end
	end
	function pose.destroy()
		for owner in poses do pose.stop(owner) end
	end
	return pose
end
return CastPose
