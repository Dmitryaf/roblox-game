--!strict
local AbilityHudCard = require(script.Parent.AbilityHudCard)
local ArrowHud = {}
function ArrowHud.new(playerGui: PlayerGui)
	return AbilityHudCard.new(playerGui, {
		name = "ArrowHud", classId = "warlock", key = "ЛКМ", title = "СТРЕЛА", slot = 1, count = 2,
		ink = Color3.fromRGB(242, 232, 255), background = Color3.fromRGB(22, 18, 31),
		hint = "E — телепорт · F — перенос рук", defaultNotes = { "WASD — движение · Мышь — прицел · E — телепортация · Q → ЛКМ → F — перенос рук" },
	})
end
return ArrowHud
