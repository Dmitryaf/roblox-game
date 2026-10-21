--!strict
local AbilityHudCard = require(script.Parent.AbilityHudCard)
local HandsHud = {}
function HandsHud.new(playerGui: PlayerGui, experiment: boolean?)
	return AbilityHudCard.new(playerGui, {
		name = "HandsHud", classId = "warlock", key = "Q", title = if experiment then "РУКИ · КАМЕННАЯ ПЛИТА" else "ДЕМОНИЧЕСКИЕ РУКИ", slot = 2, count = 2,
		ink = Color3.fromRGB(222, 239, 229), background = Color3.fromRGB(22, 18, 31),
		hint = if experiment then "Зелёные отметки на арене" else "Область под курсором",
		defaultNotes = { if experiment then "Укрытие для обеих сторон" else "Замедление и постепенный урон в области" },
	})
end
return HandsHud
