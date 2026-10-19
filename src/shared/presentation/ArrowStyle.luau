--!strict
return table.freeze({
	color = Color3.fromRGB(185, 92, 255),
	core = Color3.fromRGB(245, 206, 255),
	-- Studio-only local assets: scripts/install_studio_audio.ps1. Published audio needs authorized import.
	sounds = {
		preparing = "rbxasset://sounds/warlock-slice-v1/charge.wav",
		launched = "rbxasset://sounds/warlock-slice-v1/launch.wav",
		hit = "rbxasset://sounds/warlock-slice-v1/impact.wav",
		teleported = "rbxasset://sounds/warlock-slice-v1/teleport.wav",
	},
})
