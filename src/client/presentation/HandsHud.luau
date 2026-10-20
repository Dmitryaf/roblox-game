--!strict
local AbilityHudCard = require(script.Parent.AbilityHudCard)
local HandsHud = {}
function HandsHud.new(playerGui: PlayerGui)
	return AbilityHudCard.new(playerGui, {
		name = "HandsHud", classId = "warlock", key = "Q", title = "ДЕМОНИЧЕСКИЕ РУКИ", slot = 2, count = 2,
		ink = Color3.fromRGB(222, 239, 229), background = Color3.fromRGB(22, 18, 31),
		hint = "Область под курсором", defaultNotes = { "Замедление и постепенный урон в области" },
	})
end
return HandsHud
