--!strict
-- Owns the common ability strip geometry; controllers still own action state.
local Players = game:GetService("Players")
local TextService = game:GetService("TextService")
local AbilityHudCard = {}
type Options = {
	name: string, classId: string, key: string, title: string, slot: number, count: number,
	ink: Color3, background: Color3, hint: string, defaultNotes: { string },
}

function AbilityHudCard.new(playerGui: PlayerGui, options: Options)
	local gui = Instance.new("ScreenGui")
	gui.Name, gui.ResetOnSpawn, gui.Enabled, gui.DisplayOrder = options.name, false, false, 8
	local panel = Instance.new("TextLabel")
	panel.Name, panel.AnchorPoint = "Ability", Vector2.new(0.5, 1)
	panel.BackgroundColor3, panel.BackgroundTransparency = options.background, 0.12
	panel.TextColor3, panel.Font = options.ink, Enum.Font.GothamMedium
	panel.TextWrapped, panel.TextScaled = true, true
	panel.TextSize, panel.LineHeight = 14, 1.1
	panel.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius, corner.Parent = UDim.new(0, 9), panel
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft, padding.PaddingRight = UDim.new(0, 9), UDim.new(0, 9)
	padding.PaddingTop, padding.PaddingBottom, padding.Parent = UDim.new(0, 5), UDim.new(0, 5), panel
	local fontLimit = Instance.new("UITextSizeConstraint")
	fontLimit.MinTextSize, fontLimit.MaxTextSize, fontLimit.Parent = 10, 14, panel
	local detail = Instance.new("TextLabel")
	detail.Name, detail.AnchorPoint, detail.Visible = "Detail", Vector2.new(0.5, 1), false
	detail.BackgroundColor3, detail.BackgroundTransparency = options.background, 0.05
	detail.TextColor3, detail.Font, detail.TextSize = options.ink, Enum.Font.GothamMedium, 13
	detail.TextWrapped, detail.ZIndex = true, 2
	detail.Parent = gui
	local detailCorner = Instance.new("UICorner")
	detailCorner.CornerRadius, detailCorner.Parent = UDim.new(0, 9), detail
	local detailPadding = Instance.new("UIPadding")
	detailPadding.PaddingLeft, detailPadding.PaddingRight = UDim.new(0, 12), UDim.new(0, 12)
	detailPadding.PaddingTop, detailPadding.PaddingBottom, detailPadding.Parent = UDim.new(0, 8), UDim.new(0, 8), detail
	local status, note, hovered, notice = "", "", false, false
	local compactStates: { [string]: string } = {
		["Ожидаем подтверждения…"] = "Подтверждение…",
		["Ожидаем возрождения…"] = "Возрождение…",
		["Возрождение через несколько секунд…"] = "Возрождение…",
		["Обновляем состояние…"] = "Синхронизация…",
		["Бой приостановлен"] = "Пауза",
		["Подготовка тяжёлого удара…"] = "Подготовка удара…",
		["Собираем демонические руки…"] = "Подготовка рук…",
		["Возвращаем меч в стойку…"] = "Завершение удара…",
	}
	local normalNotes: { [string]: boolean } = { [""] = true, ["Получаем состояние сервера…"] = true }
	for _, value in options.defaultNotes do normalNotes[value] = true end
	local function cardText(width: number)
		local compactStatus = compactStates[status] or status
		if string.find(status, options.key .. " —", 1, true) == 1 then compactStatus = "Готов" end
		if string.find(status, "E — телепортация", 1, true) == 1 then compactStatus = "Стрела летит · E / F" end
		panel.Text = options.key .. " · " .. options.title .. "\n" .. compactStatus
		if notice then panel.Text ..= "\nСм. сообщение ↑"
		elseif width >= 170 then panel.Text ..= "\n" .. options.hint end
	end
	local function layout()
		-- GUI canvas remains valid for background Studio clients whose camera is 1x1.
		local viewport = gui.AbsoluteSize
		local stripWidth = math.min(if options.count == 3 then 900 else 760, math.max(1, viewport.X - 24))
		local gap, height, bottom = if viewport.X < 700 then 6 else 8, 78, 12
		local width = math.max(1, (stripWidth - gap * (options.count - 1)) / options.count)
		local center = (options.slot - (options.count + 1) / 2) * (width + gap)
		panel.Position, panel.Size = UDim2.new(0.5, center, 1, -bottom), UDim2.fromOffset(width, height)
		cardText(width)
		local bounds = TextService:GetTextSize(detail.Text, detail.TextSize, detail.Font, Vector2.new(math.max(1, width - 24), 1000))
		detail.Size = UDim2.fromOffset(width, math.max(40, bounds.Y + 16))
		-- Each notice stays above its own slot, including simultaneous refusals.
		detail.Position = UDim2.new(0.5, center, 1, -bottom - height - 8)
	end
	local function details()
		detail.Visible = gui.Enabled and (notice or hovered)
		detail.Text = options.key .. " · " .. options.title .. " · " .. status .. "\n" .. note
		layout()
	end
	local sizeConnection = gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
	local enter = panel.MouseEnter:Connect(function() hovered = true; details() end)
	local leave = panel.MouseLeave:Connect(function() hovered = false; details() end)
	gui.Parent = playerGui
	layout()
	return {
		show = function(nextStatus: string, nextNote: string)
			local player = Players.LocalPlayer
			local character = if player then player.Character else nil
			gui.Enabled = if options.classId == "warrior" then character ~= nil and character:GetAttribute("CombatClass") == "warrior"
				else not character or character:GetAttribute("CombatClass") ~= "warrior"
			status, note, notice = nextStatus, nextNote, not normalNotes[nextNote]
			details()
		end,
		destroy = function()
			sizeConnection:Disconnect(); enter:Disconnect(); leave:Disconnect(); gui:Destroy()
		end,
	}
end
return AbilityHudCard
