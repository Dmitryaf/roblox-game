--!strict
local AbilityHudCard = require(script.Parent.AbilityHudCard)
local DashHud = {}
function DashHud.new(playerGui: PlayerGui)
	return AbilityHudCard.new(playerGui, {
		name = "DashHud", classId = "warrior", key = "E", title = "РЫВОК", slot = 3, count = 3,
		ink = Color3.fromRGB(224, 235, 240), background = Color3.fromRGB(30, 25, 23),
		hint = "По ходу движения / вперёд", defaultNotes = { "По направлению движения · стоя — вперёд" },
	})
end
return DashHud
