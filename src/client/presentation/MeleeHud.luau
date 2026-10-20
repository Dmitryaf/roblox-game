--!strict
local AbilityHudCard = require(script.Parent.AbilityHudCard)
local MeleeHud = {}
function MeleeHud.new(playerGui: PlayerGui)
	return AbilityHudCard.new(playerGui, {
		name = "MeleeHud", classId = "warrior", key = "ЛКМ", title = "МЕЧ", slot = 1, count = 3,
		ink = Color3.fromRGB(246, 233, 214), background = Color3.fromRGB(30, 25, 23),
		hint = "Взмах к курсору", defaultNotes = { "WASD — движение · ЛКМ — взмах · E — рывок · Q — тяжёлый удар" },
	})
end
return MeleeHud
