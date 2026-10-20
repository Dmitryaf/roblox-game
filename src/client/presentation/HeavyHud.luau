--!strict
local AbilityHudCard = require(script.Parent.AbilityHudCard)
local HeavyHud = {}
function HeavyHud.new(playerGui: PlayerGui)
	return AbilityHudCard.new(playerGui, {
		name = "HeavyHud", classId = "warrior", key = "Q", title = "ТЯЖЁЛЫЙ УДАР", slot = 2, count = 3,
		ink = Color3.fromRGB(251, 212, 163), background = Color3.fromRGB(30, 25, 23),
		hint = "Замедление на 2 с", defaultNotes = { "Попадание замедляет на 2 с · Можно увернуться" },
	})
end
return HeavyHud
