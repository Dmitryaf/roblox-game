--!strict
-- Client-only contracts for production presentation modules; require has no side effects.
local Players = game:GetService("Players")
local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WarlockArtTests = {}

local function untilTrue(predicate: () -> boolean, seconds: number, reason: string)
	local deadline = os.clock() + seconds
	repeat
		if predicate() then return end
		task.wait(0.04)
	until os.clock() >= deadline
	error(reason)
end

local function visualParts(parent: Instance, requireMassless: boolean): number
	local count = 0
	for _, item in parent:GetDescendants() do
		if item:IsA("BasePart") then
			-- Presence owns short-lived footprints in the costume folder as well.
			if not (requireMassless and item.Name == "BriefFelFootprint") then count += 1 end
			assert(item.Anchored and not item.CanCollide and not item.CanQuery and not item.CanTouch,
				"Presentation participates in physics/query: " .. item:GetFullName())
			if requireMassless then assert(item.Massless, "Costume part is not massless: " .. item.Name) end
		end
	end
	return count
end

local function queryInvisible(folder: Instance, at: CFrame)
	local overlap = OverlapParams.new()
	overlap.FilterType, overlap.FilterDescendantsInstances = Enum.RaycastFilterType.Include, { folder }
	overlap.RespectCanCollide = false
	assert(#workspace:GetPartBoundsInBox(at, Vector3.one * 50, overlap) == 0,
		"Presentation entered a real overlap query")
	local ray = RaycastParams.new()
	ray.FilterType, ray.FilterDescendantsInstances = Enum.RaycastFilterType.Include, { folder }
	ray.RespectCanCollide = false
	assert(workspace:Raycast(at.Position + Vector3.yAxis * 20, -Vector3.yAxis * 40, ray) == nil,
		"Presentation entered a real raycast query")
end

function WarlockArtTests.run(): any
	local player = Players.LocalPlayer
	assert(player, "Warlock art suite must run on a Studio client")
	local presentation = player:WaitForChild("PlayerScripts"):WaitForChild("Game"):WaitForChild("presentation")
	-- PlayerScripts is a runtime clone; the analyzer cannot map its ModuleScripts statically.
	local loadModule = require :: any
	local Costume: any = loadModule(presentation:WaitForChild("WarlockCostume") :: ModuleScript)
	local Presence: any = loadModule(presentation:WaitForChild("WarlockPresence") :: ModuleScript)
	local Arrow: any = loadModule(presentation:WaitForChild("ChaosArrow") :: ModuleScript)
	local Impact: any = loadModule(presentation:WaitForChild("ChaosImpact") :: ModuleScript)
	local CastPose: any = loadModule(presentation:WaitForChild("CastPose") :: ModuleScript)
	local Style: any = loadModule(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("presentation"):WaitForChild("ArrowStyle") :: ModuleScript)
	local owned = Instance.new("Folder")
	owned.Name, owned.Parent = "WarlockArtContractFixture", workspace
	local costume: any = nil
	local presence: any = nil
	local poseFixture: any = nil
	local poseObservation: RBXScriptConnection? = nil
	local poseTick: RBXScriptConnection? = nil
	local result: any = nil
	local ok, failure = xpcall(function()
		untilTrue(function()
			local character = player.Character
			return character ~= nil and character:FindFirstChild("HumanoidRootPart") ~= nil
				and character:FindFirstChild("WarlockCostume") ~= nil
		end, 40, "Production character/costume did not appear")
		local character = player.Character :: Model
		local originalRoot = character:FindFirstChild("HumanoidRootPart") :: BasePart
		local liveCostume = character:FindFirstChild("WarlockCostume") :: Folder
		assert(visualParts(liveCostume, true) == 43, "Production costume did not contain the full 43-part silhouette")
		queryInvisible(liveCostume, originalRoot.CFrame)
		assert(type(CastPose.new) == "function", "Production CastPose API absent")
		local motorCount = 0
		local poseJoint: (Motor6D | AnimationConstraint)? = nil
		for _, item in character:GetDescendants() do
			if item:IsA("Motor6D") or item:IsA("AnimationConstraint") then
				motorCount += 1
				local attachment = if item:IsA("AnimationConstraint") then item.Attachment0 else nil
				if item.Name == "RightShoulder" or item.Name == "Right Shoulder"
					or (attachment and attachment.Name == "RightShoulderRigAttachment") then poseJoint = item end
			end
		end
		assert(motorCount > 0, "Production character has no animation joints")
		assert(poseJoint, "Production character has no right shoulder animation joint")
		local observedJoint = poseJoint :: Motor6D | AnimationConstraint
		local controlledTime = workspace:GetServerTimeNow()
		poseFixture = CastPose.new(function(): number return controlledTime end)
		local started = controlledTime
		poseFixture.begin(player.UserId, started + 0.7, originalRoot.CFrame.LookVector, started)
		controlledTime = started + 0.4
		local sawSimulation = false
		poseTick = game:GetService("RunService").PreSimulation:Connect(function() sawSimulation = true end)
		local observed: any = nil
		poseObservation = game:GetService("RunService").PostSimulation:Connect(function()
			if observed or not sawSimulation then return end
			local checked, problem = pcall(function()
				local applied = observedJoint.Transform
				local atRoot = originalRoot.CFrame
				-- Stop and inspect synchronously within this callback: Animator cannot replace
				-- the baseline between these reads, as it could across task.wait()/frames.
				poseFixture.stop(player.UserId)
				local restored = observedJoint.Transform
				assert(restored ~= applied, string.format("Procedural preparation did not modify live Transform: joint=%s/%s clock=%.6f applied=%s restored=%s",
					observedJoint.ClassName, observedJoint.Name, controlledTime, tostring(applied), tostring(restored)))
				poseFixture.stop(player.UserId)
				assert(observedJoint.Transform == restored, "Repeated pose stop changed the restored Animator pose")
				assert(originalRoot.CFrame == atRoot, "Procedural pose stop changed the authoritative root")
			end)
			observed = { ok = checked, failure = problem }
		end)
		-- Six background Studio clients may not simulate even one frame in three seconds.
		-- The pose clock remains fixed above; this waits for the same assertion, not a later phase.
		untilTrue(function() return observed ~= nil end, 15, "Procedural preparation did not reach PostSimulation")
		if poseObservation then poseObservation:Disconnect(); poseObservation = nil end
		if poseTick then poseTick:Disconnect(); poseTick = nil end
		poseFixture.destroy(); poseFixture = nil
		assert(observed.ok, tostring(observed.failure))

		-- Clone only for destructive lifecycle checks. Never recreate/destroy the live appearance.
		local archivable = character.Archivable
		character.Archivable = true
		local copied, clone = pcall(function() return character:Clone() end)
		character.Archivable = archivable
		assert(copied, "Could not clone production rig")
		local rig = clone :: Model
		rig.Name = "IsolatedWarlockRig"
		for _, item in rig:GetDescendants() do
			if item:IsA("LuaSourceContainer") or item:IsA("Animation") or item:IsA("Animator")
				or item.Name == "WarlockCostume" or item.Name == "WarlockAura" then item:Destroy() end
		end
		local parts: { [BasePart]: number } = {}
		local cameraModifiers: { [BasePart]: number } = {}
		local decals: { [Decal]: number } = {}
		for _, item in rig:GetDescendants() do
			if item:IsA("BasePart") then
				item.Anchored, item.CanCollide, item.CanQuery, item.CanTouch = true, false, false, false
				item.LocalTransparencyModifier = 0.23
				item.Transparency = 0.17
				parts[item] = item.Transparency
				cameraModifiers[item] = item.LocalTransparencyModifier
			elseif item:IsA("Decal") then item.Transparency = 0.31; decals[item] = item.Transparency end
		end
		rig:PivotTo(character:GetPivot() + Vector3.new(0, 500, 0))
		rig.Parent = owned
		local root = rig:FindFirstChild("HumanoidRootPart") :: BasePart
		local initialRoot = root.CFrame
		local fixtureHumanoid = rig:FindFirstChildOfClass("Humanoid") :: Humanoid
		local lateNames: { string } = if fixtureHumanoid.RigType == Enum.HumanoidRigType.R15 then
			{ "LowerTorso", "RightHand", "LeftUpperArm", "RightFoot" } else { "Right Arm", "Left Leg" }
		for _, missingName in lateNames do
			local missing = rig:FindFirstChild(missingName) :: BasePart
			assert(missing, "Partial-rig fixture lacks expected body part: " .. missingName)
			missing.Parent = nil
			costume = Costume.new(rig)
			missing.Parent = rig
			assert(costume == nil, "Partial rig created a costume before " .. missingName .. " replicated")
			assert(rig:FindFirstChild("WarlockCostume") == nil, "Partial rig created a presentation folder")
			for part, original in parts do
				assert(part.Transparency == original, "Partial rig hid a body before it was ready")
				assert(part.LocalTransparencyModifier == cameraModifiers[part], "Partial rig changed camera visibility")
			end
			for decal, original in decals do assert(decal.Transparency == original, "Partial rig hid a decal") end
		end
		costume = Costume.new(rig)
		assert(costume and visualParts(costume.folder, true) == 43, "Cloned full-rig costume creation failed")
		for part in parts do
			assert(part.Transparency == 1, "Costume did not hide underlying body")
			assert(part.LocalTransparencyModifier == cameraModifiers[part], "Costume changed camera-owned visibility")
		end
		for decal in decals do assert(decal.Transparency == 1, "Costume did not hide underlying decal") end
		for _, at in { 10, 10.1, 10.2 } do costume.step(at, 1) end
		assert(root.CFrame == initialRoot, "Costume moved the authoritative root")
		queryInvisible(costume.folder, root.CFrame)
		local laterPart = Instance.new("Part")
		laterPart.Anchored, laterPart.CanCollide, laterPart.CanQuery, laterPart.CanTouch = true, false, false, false
		laterPart.LocalTransparencyModifier = 0.41
		laterPart.Transparency = 0.29
		local laterVisibility = laterPart.Transparency
		local laterCameraModifier = laterPart.LocalTransparencyModifier
		laterPart.Parent = rig
		untilTrue(function() return laterPart.Transparency == 1 end, 1, "Late accessory was not hidden")
		assert(laterPart.LocalTransparencyModifier == laterCameraModifier, "Costume changed late accessory camera modifier")
		presence = Presence.new(rig, costume.folder)
		assert(presence and root:FindFirstChild("WarlockAura"), "Production aura was not created")
		local auraRoot = root:FindFirstChild("WarlockAura") :: Attachment
		local outsideSources = 0
		for _, source in auraRoot:GetChildren() do
			if source:IsA("Attachment") and (source.WorldPosition - root.Position).Magnitude >= 0.8 then
				outsideSources += 1
			end
		end
		assert(outsideSources >= 2, "Veil emitters remained buried inside the torso")
		presence.step(10, 0); presence.step(10.2, 1)
		presence.destroy(); presence = nil
		assert(root:FindFirstChild("WarlockAura") == nil, "Aura attachment leaked after destroy")
		costume.destroy(); costume = nil
		assert(rig:FindFirstChild("WarlockCostume") == nil, "Costume folder leaked after destroy")
		for part, original in parts do
			assert(part.Transparency == original, "Body visibility was not restored")
			assert(part.LocalTransparencyModifier == cameraModifiers[part], "Costume cleanup changed camera-owned visibility")
		end
		for decal, original in decals do assert(decal.Transparency == original, "Decal visibility was not restored") end
		assert(laterPart.Transparency == laterVisibility, "Late accessory visibility was not restored")
		assert(laterPart.LocalTransparencyModifier == laterCameraModifier, "Late accessory camera modifier was not retained")
		assert(root.CFrame == initialRoot, "Appearance cleanup moved the authoritative root")

		local effects = Instance.new("Folder")
		effects.Name, effects.Parent = "OwnedEffects", owned
		local now = workspace:GetServerTimeNow()
		local point = originalRoot.Position + Vector3.new(12, 2, 0)
		local event = { owner = player.UserId, castId = 91234, position = point, direction = Vector3.xAxis,
			speed = 58, sampledAt = now, startedAt = now, launchAt = now + 0.7, expiresAt = now + 2.9 }
		local flying = Arrow.new(effects, event, true)
		flying.step(now); flying.step(now + 0.25)
		assert(flying.root:IsA("BasePart") and flying.root.Name == "DemonicArrow", "Production arrow root absent")
		assert((flying.root.Position - (point + Vector3.xAxis * 14.5)).Magnitude < 0.001, "Arrow presentation extrapolation changed")
		assert(visualParts(effects, false) > 1, "Arrow presentation has no layered body")
		queryInvisible(effects, flying.root.CFrame)
		flying.destroy()
		assert(#effects:GetChildren() == 0, "Flying arrow leaked after destroy")
		local charge = Arrow.new(effects, event, false)
		charge.step(now + 0.2)
		assert(charge.root.Name == "ArrowCharge" and visualParts(effects, false) > 1, "Production charge visual absent")
		charge.destroy()
		assert(#effects:GetChildren() == 0, "Charge leaked after destroy")
		for _, teleport in { false, true } do
			local impact = Impact.new(effects, point, teleport, 1234, now)
			assert(impact.step(now + 0.15) and impact.step(now + 1.7), "Aftermath disappeared before its lifetime")
			assert(visualParts(effects, false) > 1, "Aftermath has no layered presentation")
			queryInvisible(effects, CFrame.new(point))
			assert(not impact.step(now + 2), "Aftermath did not expire")
			assert(#effects:GetChildren() == 0, "Expired aftermath leaked descendants")
		end
		local early = Impact.new(effects, point, false, 5678, now)
		early.destroy()
		assert(#effects:GetChildren() == 0, "Cancelled aftermath leaked descendants")

		local ids: { string } = {}
		for _, id in (Style.textures :: { [string]: string }) do table.insert(ids, id) end
		local sounds: { Sound } = {}
		for _, id in (Style.sounds :: { [string]: string }) do
			table.insert(ids, id)
			local sound = Instance.new("Sound")
			sound.SoundId, sound.Parent = id, owned
			table.insert(sounds, sound)
		end
		assert(#ids == 6 and #sounds == 4, "Art manifest does not contain two textures/four sounds")
		ContentProvider:PreloadAsync(ids)
		ContentProvider:PreloadAsync(sounds)
		for _, id in ids do
			assert(string.find(id, "rbxasset://", 1, true) == 1, "Art suite expects installed local assets")
			assert(ContentProvider:GetAssetFetchStatus(id) == Enum.AssetFetchStatus.Success, "Local art asset failed loading: " .. id)
		end
		for _, sound in sounds do assert(sound.IsLoaded and sound.TimeLength > 0, "Local audio contains no decoded frames") end
		assert(liveCostume.Parent == character and visualParts(liveCostume, true) == 43, "Fixture disturbed the live costume")
		result = { ok = true, costumeParts = 43, liveJoints = motorCount, loadedAssets = #ids,
			queryIsolation = true, visibilityRestored = true, partialRigWait = true, livePoseTransform = true, effectCleanup = true }
	end, debug.traceback)
	if presence then pcall(presence.destroy) end
	if poseObservation then poseObservation:Disconnect() end
	if poseTick then poseTick:Disconnect() end
	if poseFixture then pcall(poseFixture.destroy) end
	if costume then pcall(costume.destroy) end
	owned:Destroy()
	assert(owned.Parent == nil, "Art fixture root leaked")
	if not ok then error(tostring(failure), 0) end
	return result
end

return WarlockArtTests
