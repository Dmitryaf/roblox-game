--!strict
return table.freeze({
	color = Color3.fromRGB(128, 63, 179),
	core = Color3.fromRGB(208, 255, 151),
	flame = Color3.fromRGB(91, 196, 66),
	shadow = Color3.fromRGB(29, 13, 40),
	textures = {
		flame = "rbxasset://textures/warlock-art-v1/flame.png",
		smoke = "rbxasset://textures/warlock-art-v1/smoke.png",
	},
	-- Studio-only local assets: scripts/install_studio_art.ps1. Published audio needs authorized import.
	sounds = {
		preparing = "rbxasset://sounds/warlock-art-v2/charge.wav",
		launched = "rbxasset://sounds/warlock-art-v1/launch.wav",
		hit = "rbxasset://sounds/warlock-art-v2/impact.wav",
		teleported = "rbxasset://sounds/warlock-art-v1/teleport.wav",
	},
})
