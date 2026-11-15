-- HUD: интерфейс игрока.
--   слева сверху — часы смены, ночь, полоса прогресса 00:00–06:00, свет и фонарик; кнопки «Телефон» и «Меню»
--   справа сверху — список заданий и выполнение плана
--   по центру сверху — уведомления; слева — сообщения на телефон; снизу — субтитры, предмет в руках, выносливость
--   окна: лобби, настройки, история сообщений, документы (улики), экран концовки
-- Окна с кнопкой Modal освобождают курсор мыши в режиме от первого лица.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Products = require(Shared:WaitForChild("Products"))
local Util = require(Shared:WaitForChild("Util"))
local Texts = require(Shared:WaitForChild("Texts"))

local HUD = {}

local ctx, UI
local gui, overlay
local clockLabel, nightLabel, barFill, powerLabel, batteryLabel
local tasksPanel, tasksBody, planLabel, tasksCollapsed
local taskRows = {}
local notifyHolder
local phoneCard, phoneSender, phoneText
local messages = {}
local subtitleLabel
local carryFrame, carryLabel
local staminaBack, staminaFill
local lobbyPanel, lobbyStats, lobbyCountdown
local countdownLabel
local modals = {}
local settingsRows = {}
local docTitle, docBody
local phoneList
local endingTitle, endingSubtitle, endingBody, endingStats, endingFooter
local fadeFrame
local buttonsRow

local function tween(obj, t, props)
	TweenService:Create(obj, TweenInfo.new(t, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props):Play()
end

local function keyHint(key)
	return UI.IsTouch and "" or ("  [" .. key .. "]")
end

-------------------------------------------------------------------------------
-- Окна
-------------------------------------------------------------------------------
local function makeModal(name, size, paper)
	local holder = UI.new("Frame", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = size,
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 20,
	}, overlay)
	UI.scaled(holder)
	-- невидимая модальная кнопка: пока окно открыто, курсор мыши свободен
	UI.new("TextButton", {
		Name = "ModalCatcher",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		Modal = true,
		AutoButtonColor = false,
		ZIndex = 20,
	}, holder)
	local panel = UI.panel({
		Name = "Panel",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = paper and 0 or 0.08,
		BackgroundColor3 = paper and Color3.fromRGB(238, 230, 210) or UI.Colors.Panel,
		ZIndex = 21,
	}, holder)
	UI.padding(panel, 18)
	modals[name] = holder
	return holder, panel
end

function HUD.CloseModals()
	for name, m in pairs(modals) do
		if m.Visible then
			m.Visible = false
			if name == "Settings" then
				HUD.SaveSettings()
			end
		end
	end
end

function HUD.OpenModal(name)
	local m = modals[name]
	if not m then
		return
	end
	local wasOpen = m.Visible
	HUD.CloseModals()
	if not wasOpen then
		m.Visible = true
	end
end

function HUD.AnyModalOpen()
	for _, m in pairs(modals) do
		if m.Visible then
			return true
		end
	end
	return false
end

-------------------------------------------------------------------------------
-- Уведомления, телефон, субтитры
-------------------------------------------------------------------------------
local STYLE_COLOR = {
	info = Color3.fromRGB(240, 240, 236),
	task = Color3.fromRGB(255, 196, 70),
	done = Color3.fromRGB(90, 220, 130),
	warn = Color3.fromRGB(255, 120, 70),
	anomaly = Color3.fromRGB(190, 120, 255),
}

function HUD.Notify(text, style)
	local color = STYLE_COLOR[style] or STYLE_COLOR.info
	local card = UI.panel({
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 0.2,
		LayoutOrder = math.floor(os.clock() * 100),
	}, notifyHolder)
	UI.padding(card, 10)
	local bar = UI.new("Frame", { Size = UDim2.new(0, 4, 1, 0), BackgroundColor3 = color }, card)
	UI.corner(bar, 2)
	local label = UI.text(text, {
		Size = UDim2.new(1, -14, 0, 0),
		Position = UDim2.fromOffset(14, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextColor3 = color,
		TextSize = 17,
		Font = Enum.Font.GothamMedium,
	}, card)
	-- не больше 3 уведомлений сразу
	local cards = {}
	for _, c in ipairs(notifyHolder:GetChildren()) do
		if c:IsA("Frame") then
			table.insert(cards, c)
		end
	end
	if #cards > 3 then
		table.sort(cards, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		cards[1]:Destroy()
	end
	task.delay(5, function()
		if card.Parent then
			tween(card, 0.6, { BackgroundTransparency = 1 })
			tween(label, 0.6, { TextTransparency = 1 })
			tween(bar, 0.6, { BackgroundTransparency = 1 })
			task.wait(0.7)
			card:Destroy()
		end
	end)
end

function HUD.Phone(sender, text)
	table.insert(messages, { Sender = sender, Text = text, Time = Util.clock(ctx.State:GetAttribute("Minutes") or 0) })
	phoneSender.Text = "📱 " .. sender
	phoneText.Text = text
	phoneCard.Visible = true
	local stamp = os.clock()
	phoneCard:SetAttribute("Stamp", stamp)
	task.delay(9, function()
		if phoneCard:GetAttribute("Stamp") == stamp then
			phoneCard.Visible = false
		end
	end)
	HUD.RefreshPhoneList()
end

function HUD.RefreshPhoneList()
	if not phoneList then
		return
	end
	for _, c in ipairs(phoneList:GetChildren()) do
		if c:IsA("Frame") then
			c:Destroy()
		end
	end
	for i = #messages, 1, -1 do
		local m = messages[i]
		local item = UI.new("Frame", {
			Size = UDim2.new(1, -8, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundColor3 = UI.Colors.PanelLight,
			BackgroundTransparency = 0.1,
			LayoutOrder = #messages - i,
			ZIndex = 22,
		}, phoneList)
		UI.corner(item, 8)
		UI.padding(item, 10)
		UI.list(item, 4)
		UI.text(m.Time .. " · " .. m.Sender, { Size = UDim2.new(1, 0, 0, 16), TextSize = 13, TextColor3 = UI.Colors.Amber, ZIndex = 22, LayoutOrder = 1 }, item)
		UI.text(m.Text, { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextSize = 16, ZIndex = 22, LayoutOrder = 2 }, item)
	end
end

function HUD.Subtitle(speaker, text, seconds)
	if ctx.Settings.Subtitles == false then
		return
	end
	subtitleLabel.Text = (speaker ~= "" and (speaker .. ": ") or "") .. text
	subtitleLabel.Visible = true
	local stamp = os.clock()
	subtitleLabel:SetAttribute("Stamp", stamp)
	task.delay(seconds or 5, function()
		if subtitleLabel:GetAttribute("Stamp") == stamp then
			subtitleLabel.Visible = false
		end
	end)
end

-------------------------------------------------------------------------------
-- Задания
-------------------------------------------------------------------------------
local function rowFor(folder)
	local existing = taskRows[folder]
	if existing then
		return existing
	end
	local row = UI.new("Frame", {
		Name = folder.Name,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
	}, tasksBody)
	UI.list(row, 2)
	local top = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 1 }, row)
	local mark = UI.text("○", { Size = UDim2.fromOffset(18, 20), TextSize = 16, TextColor3 = UI.Colors.Amber, TextXAlignment = Enum.TextXAlignment.Center }, top)
	local title = UI.text("", { Position = UDim2.fromOffset(22, 0), Size = UDim2.new(1, -72, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextSize = 16 }, top)
	local count = UI.text("", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(46, 20), TextSize = 15, Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = UI.Colors.Amber }, top)
	local detail = UI.text("", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextSize = 13, TextColor3 = UI.Colors.Muted, LayoutOrder = 2 }, row)
	UI.new("UIPadding", { PaddingLeft = UDim.new(0, 22) }, detail)
	local r = { Frame = row, Mark = mark, Title = title, Count = count, Detail = detail }
	taskRows[folder] = r
	return r
end

local function updateRow(folder)
	local r = rowFor(folder)
	local done = folder:GetAttribute("Done") == true
	local progress = folder:GetAttribute("Progress") or 0
	local count = folder:GetAttribute("Count") or 1
	r.Title.Text = folder:GetAttribute("Text") or folder.Name
	r.Count.Text = count > 1 and (progress .. "/" .. count) or ""
	local detail = folder:GetAttribute("Detail") or ""
	local room = folder:GetAttribute("Room") or ""
	r.Detail.Text = detail ~= "" and detail or room
	r.Detail.Visible = r.Detail.Text ~= ""
	r.Mark.Text = done and "✓" or "○"
	r.Mark.TextColor3 = done and UI.Colors.Good or UI.Colors.Amber
	r.Title.TextColor3 = done and UI.Colors.Muted or UI.Colors.Text
	r.Count.TextColor3 = done and UI.Colors.Good or UI.Colors.Amber
	r.Frame.LayoutOrder = (done and 100000 or 0) + (folder:GetAttribute("Order") or 0)
	-- выполненные задания исчезают из списка через несколько секунд
	if done and not r.Removing then
		r.Removing = true
		task.delay(6, function()
			if r.Frame.Parent then
				r.Frame:Destroy()
			end
			taskRows[folder] = nil
		end)
	end
end

local function watchTask(folder)
	updateRow(folder)
	folder.AttributeChanged:Connect(function()
		if taskRows[folder] or not folder:GetAttribute("Done") then
			updateRow(folder)
		end
	end)
end

function HUD.ToggleTasks()
	tasksCollapsed = not tasksCollapsed
	tasksBody.Visible = not tasksCollapsed
end

local function updatePlan()
	local pct = ctx.State:GetAttribute("Percent") or 0
	local phase = ctx.State:GetAttribute("Phase")
	if phase == "Shift" or phase == "Ending" then
		planLabel.Text = string.format("План: %d%% · нужно %d%%", pct, Config.GoodEndingPercent)
		planLabel.TextColor3 = pct >= Config.GoodEndingPercent and UI.Colors.Good or UI.Colors.Muted
	else
		planLabel.Text = "Смена ещё не началась"
		planLabel.TextColor3 = UI.Colors.Muted
	end
end

-------------------------------------------------------------------------------
-- Часы и лобби
-------------------------------------------------------------------------------
local function updateClock()
	local s = ctx.State
	local minutes = s:GetAttribute("Minutes") or 0
	local phase = s:GetAttribute("Phase")
	clockLabel.Text = Util.clock(minutes)
	nightLabel.Text = string.format("НОЧЬ %d · %s", math.max(1, s:GetAttribute("Night") or 1), Texts.StoreName)
	barFill.Size = UDim2.new(math.clamp(minutes / (Config.ShiftHours * 60), 0, 1), 0, 1, 0)
	local power = s:GetAttribute("Power") ~= false
	powerLabel.Visible = not power and phase == "Shift"
	lobbyPanel.Visible = phase == "Lobby"
	countdownLabel.Visible = phase == "Countdown"
	if phase == "Countdown" then
		countdownLabel.Text = tostring(s:GetAttribute("Countdown") or "")
	end
	if phase == "Lobby" then
		local left = s:GetAttribute("Countdown") or 0
		lobbyCountdown.Text = string.format("Смена начнётся сама через %d с", left)
	end
end

function HUD.SetProfile(profile)
	if not profile then
		return
	end
	local function mark(n)
		return (n or 0) > 0 and "✓" or "—"
	end
	lobbyStats.Text = string.format(
		"Смен отработано: %d · заработано: %d ₽ · лучший план: %d%%\nКонцовки: хорошая %s · плохая %s · секретная %s",
		profile.Nights or 0,
		profile.Earnings or 0,
		profile.BestPercent or 0,
		mark(profile.Good),
		mark(profile.Bad),
		mark(profile.Secret)
	)
end

-------------------------------------------------------------------------------
-- Предмет в руках, выносливость, фонарик
-------------------------------------------------------------------------------
local function updateCarry()
	local carry = ctx.Player:GetAttribute("Carry") or ""
	if carry == "" then
		carryFrame.Visible = false
		return
	end
	local kind, category = string.match(carry, "^(%w+):?(%w*)$")
	local names = { Box = "Коробка", Mop = "Швабра", Trash = "Мешок с мусором", Delivery = "Поставка" }
	local text = names[kind] or carry
	if category and category ~= "" and Products.Categories[category] then
		text = text .. " «" .. Products.Categories[category].Name .. "»"
	end
	carryLabel.Text = "В руках: " .. text
	carryFrame.Visible = true
end

function HUD.SetStamina(frac)
	staminaBack.Visible = frac < 0.99
	staminaFill.Size = UDim2.fromScale(math.clamp(frac, 0, 1), 1)
	staminaFill.BackgroundColor3 = frac < 0.25 and UI.Colors.Warn or UI.Colors.Text
end

function HUD.SetBattery(frac, on)
	batteryLabel.Text = string.format("🔦 %d%%%s", math.floor(frac * 100 + 0.5), on and " · вкл" or "")
	batteryLabel.TextColor3 = frac < 0.2 and UI.Colors.Warn or UI.Colors.Muted
end

-------------------------------------------------------------------------------
-- Документы, концовка, затемнение
-------------------------------------------------------------------------------
function HUD.ShowDocument(data)
	docTitle.Text = data.Title or ""
	docBody.Text = data.Body or ""
	HUD.OpenModal("Document")
end

function HUD.Fade(transparency, seconds, color)
	fadeFrame.BackgroundColor3 = color or Color3.new(0, 0, 0)
	tween(fadeFrame, seconds or 0.5, { BackgroundTransparency = transparency })
end

function HUD.ShowEnding(stats)
	local e = Texts.Endings[stats.Kind] or Texts.Endings.Bad
	endingTitle.Text = e.Title
	endingTitle.TextColor3 = stats.Kind == "Good" and UI.Colors.Good or (stats.Kind == "Secret" and UI.Colors.Anomaly or UI.Colors.Accent)
	endingSubtitle.Text = e.Subtitle
	endingBody.Text = e.Body
	endingStats.Text = string.format(
		"План выполнен: %d%%\nОбслужено покупателей: %d\nВыручка: %d ₽\nЗарплата за смену: %d ₽\nНайдено улик: %d из 4",
		stats.Percent or 0,
		stats.Served or 0,
		stats.Revenue or 0,
		stats.Salary or 0,
		stats.Clues or 0
	)
	HUD.OpenModal("Ending")
	task.spawn(function()
		local left = Config.EndingSeconds - 8
		while modals.Ending.Visible and left > 0 do
			endingFooter.Text = string.format("Новая смена через %d с", left)
			task.wait(1)
			left = left - 1
		end
		endingFooter.Text = "Новая смена…"
	end)
end

-------------------------------------------------------------------------------
-- Настройки
-------------------------------------------------------------------------------
local SETTINGS = {
	{ Key = "Music", Name = "Музыка", Kind = "Percent", Step = 0.1, Min = 0, Max = 1 },
	{ Key = "Sfx", Name = "Звуки", Kind = "Percent", Step = 0.1, Min = 0, Max = 1 },
	{ Key = "Brightness", Name = "Яркость", Kind = "Signed", Step = 0.05, Min = -0.3, Max = 0.5 },
	{ Key = "Fov", Name = "Поле зрения", Kind = "Number", Step = 5, Min = 60, Max = 100 },
	{ Key = "HeadBob", Name = "Покачивание камеры", Kind = "Bool" },
	{ Key = "Subtitles", Name = "Субтитры", Kind = "Bool" },
}

local function formatSetting(def, v)
	if def.Kind == "Percent" then
		return math.floor(v * 100 + 0.5) .. "%"
	elseif def.Kind == "Signed" then
		local n = math.floor(v * 100 + 0.5)
		return (n > 0 and "+" or "") .. n .. "%"
	elseif def.Kind == "Number" then
		return tostring(math.floor(v + 0.5)) .. "°"
	end
	return v and "Вкл" or "Выкл"
end

function HUD.RefreshSettings()
	for _, row in ipairs(settingsRows) do
		row.Value.Text = formatSetting(row.Def, ctx.Settings[row.Def.Key])
	end
end

function HUD.SaveSettings()
	ctx.Remotes.Action:FireServer("SaveSettings", ctx.Settings)
end

local function changeSetting(def, dir)
	local v = ctx.Settings[def.Key]
	if def.Kind == "Bool" then
		v = not v
	else
		v = math.clamp(v + dir * def.Step, def.Min, def.Max)
		v = math.floor(v / def.Step + 0.5) * def.Step
	end
	ctx.Settings[def.Key] = v
	ctx.ApplySettings()
	HUD.RefreshSettings()
end

-------------------------------------------------------------------------------
-- Построение интерфейса
-------------------------------------------------------------------------------
local function buildTopLeft()
	local panel = UI.panel({
		Name = "Clock",
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.fromOffset(14, 10),
		Size = UDim2.fromOffset(250, 112),
	}, gui)
	UI.scaled(panel)
	UI.padding(panel, 12)
	clockLabel = UI.text("00:00", { Size = UDim2.new(1, 0, 0, 40), TextSize = 40, Font = Enum.Font.GothamBlack }, panel)
	nightLabel = UI.text("НОЧЬ 1", { Position = UDim2.fromOffset(0, 42), Size = UDim2.new(1, 0, 0, 16), TextSize = 13, TextColor3 = UI.Colors.Muted, Font = Enum.Font.GothamBold }, panel)
	local bar = UI.new("Frame", { Position = UDim2.fromOffset(0, 64), Size = UDim2.new(1, 0, 0, 6), BackgroundColor3 = UI.Colors.PanelLight }, panel)
	UI.corner(bar, 3)
	barFill = UI.new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = UI.Colors.Accent }, bar)
	UI.corner(barFill, 3)
	for h = 1, Config.ShiftHours - 1 do
		UI.new("Frame", { Position = UDim2.new(h / Config.ShiftHours, -1, 0, -2), Size = UDim2.new(0, 2, 1, 4), BackgroundColor3 = UI.Colors.Muted, BackgroundTransparency = 0.4 }, bar)
	end
	batteryLabel = UI.text("🔦 100%", { Position = UDim2.fromOffset(0, 74), Size = UDim2.new(0.5, 0, 0, 16), TextSize = 13, TextColor3 = UI.Colors.Muted }, panel)
	powerLabel = UI.text("⚡ НЕТ СВЕТА", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 74), Size = UDim2.new(0.5, 0, 0, 16), TextSize = 13, Font = Enum.Font.GothamBold, TextColor3 = UI.Colors.Warn, TextXAlignment = Enum.TextXAlignment.Right, Visible = false }, panel)

	buttonsRow = UI.new("Frame", {
		Name = "Buttons",
		Position = UDim2.fromOffset(14, 128),
		Size = UDim2.fromOffset(250, 40),
		BackgroundTransparency = 1,
	}, gui)
	UI.scaled(buttonsRow)
	UI.list(buttonsRow, 8, true)
	UI.button("📱 Телефон" .. keyHint("P"), { Size = UDim2.fromOffset(UI.IsTouch and 118 or 140, 38), TextSize = 14, LayoutOrder = 1 }, buttonsRow, function()
		HUD.OpenModal("Phone")
	end)
	UI.button("⚙ Меню" .. keyHint("M"), { Size = UDim2.fromOffset(UI.IsTouch and 100 or 102, 38), TextSize = 14, LayoutOrder = 2 }, buttonsRow, function()
		HUD.OpenModal("Settings")
	end)
end

local function buildTasks()
	tasksPanel = UI.panel({
		Name = "Tasks",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 10),
		Size = UDim2.fromOffset(340, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	}, gui)
	UI.scaled(tasksPanel)
	UI.padding(tasksPanel, 12)
	UI.list(tasksPanel, 8)
	local header = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 22), BackgroundTransparency = 1, LayoutOrder = 1 }, tasksPanel)
	UI.text("ЗАДАНИЯ", { Size = UDim2.new(0.5, 0, 1, 0), TextSize = 15, Font = Enum.Font.GothamBlack }, header)
	UI.button(UI.IsTouch and "▾" or "▾ T", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, -2),
		Size = UDim2.fromOffset(UI.IsTouch and 40 or 46, 26),
		TextSize = 14,
	}, header, function()
		HUD.ToggleTasks()
	end)
	planLabel = UI.text("", { Size = UDim2.new(1, 0, 0, 16), TextSize = 13, TextColor3 = UI.Colors.Muted, LayoutOrder = 2 }, tasksPanel)
	tasksBody = UI.new("Frame", { Name = "Body", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 3 }, tasksPanel)
	UI.list(tasksBody, 10)
	tasksCollapsed = false
end

local function buildCenter()
	notifyHolder = UI.new("Frame", {
		Name = "Notifications",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 10),
		Size = UDim2.fromOffset(460, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
	}, gui)
	UI.scaled(notifyHolder)
	UI.list(notifyHolder, 6)

	phoneCard = UI.panel({
		Name = "PhoneCard",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 14, 0.46, 0),
		Size = UDim2.fromOffset(320, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 0.1,
		Visible = false,
	}, gui)
	UI.scaled(phoneCard)
	UI.padding(phoneCard, 12)
	UI.list(phoneCard, 6)
	phoneSender = UI.text("", { Size = UDim2.new(1, 0, 0, 18), TextSize = 14, Font = Enum.Font.GothamBold, TextColor3 = UI.Colors.Amber, LayoutOrder = 1 }, phoneCard)
	phoneText = UI.text("", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextSize = 16, LayoutOrder = 2 }, phoneCard)

	subtitleLabel = UI.text("", {
		Name = "Subtitle",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -150),
		Size = UDim2.fromOffset(760, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 0.35,
		BackgroundColor3 = Color3.new(0, 0, 0),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextSize = 19,
		Font = Enum.Font.GothamMedium,
		Visible = false,
	}, gui)
	UI.scaled(subtitleLabel)
	UI.padding(subtitleLabel, 8)
	UI.corner(subtitleLabel, 8)

	carryFrame = UI.panel({
		Name = "Carry",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -96),
		Size = UDim2.fromOffset(420, 44),
		Visible = false,
	}, gui)
	UI.scaled(carryFrame)
	carryLabel = UI.text("", { Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -150, 1, 0), TextSize = 15 }, carryFrame)
	UI.button("Положить" .. keyHint("G"), {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -6, 0.5, 0),
		Size = UDim2.fromOffset(130, 34),
		TextSize = 14,
	}, carryFrame, function()
		ctx.Remotes.Action:FireServer("Drop")
	end)

	staminaBack = UI.new("Frame", {
		Name = "Stamina",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -82),
		Size = UDim2.fromOffset(200, 5),
		BackgroundColor3 = UI.Colors.PanelLight,
		BackgroundTransparency = 0.3,
		Visible = false,
	}, gui)
	UI.scaled(staminaBack)
	UI.corner(staminaBack, 3)
	staminaFill = UI.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = UI.Colors.Text }, staminaBack)
	UI.corner(staminaFill, 3)

	countdownLabel = UI.text("", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.4),
		Size = UDim2.fromOffset(200, 120),
		TextSize = 110,
		Font = Enum.Font.GothamBlack,
		TextXAlignment = Enum.TextXAlignment.Center,
		Visible = false,
	}, gui)
	UI.scaled(countdownLabel)
end

local function buildLobby()
	lobbyPanel = UI.panel({
		Name = "Lobby",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -20),
		Size = UDim2.fromOffset(600, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 0.15,
		Visible = false,
	}, gui)
	UI.scaled(lobbyPanel)
	UI.padding(lobbyPanel, 16)
	UI.list(lobbyPanel, 6)
	UI.text("NIGHT SHIFT", { Size = UDim2.new(1, 0, 0, 34), TextSize = 32, Font = Enum.Font.GothamBlack, TextColor3 = UI.Colors.Accent, LayoutOrder = 1 }, lobbyPanel)
	UI.text("МАРТ 24 · ночная смена с 00:00 до 06:00 · 1–4 сотрудника", { Size = UDim2.new(1, 0, 0, 18), TextSize = 15, TextColor3 = UI.Colors.Muted, LayoutOrder = 2 }, lobbyPanel)
	lobbyStats = UI.text("Загрузка профиля…", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextSize = 14, LayoutOrder = 3 }, lobbyPanel)
	UI.text(Texts.LobbyHint .. (UI.IsTouch and "." or " — или нажмите Enter."), { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextSize = 14, TextColor3 = UI.Colors.Amber, LayoutOrder = 4 }, lobbyPanel)
	local row = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 44), BackgroundTransparency = 1, LayoutOrder = 5 }, lobbyPanel)
	UI.button("НАЧАТЬ СМЕНУ" .. keyHint("Enter"), {
		Size = UDim2.fromOffset(240, 42),
		BackgroundColor3 = UI.Colors.Accent,
		TextSize = 16,
	}, row, function()
		HUD.RequestStart()
	end)
	lobbyCountdown = UI.text("", { Position = UDim2.fromOffset(256, 0), Size = UDim2.new(1, -256, 1, 0), TextSize = 14, TextColor3 = UI.Colors.Muted }, row)
end

function HUD.RequestStart()
	if ctx.State:GetAttribute("Phase") == "Lobby" then
		ctx.Remotes.Action:FireServer("StartShift")
	end
end

local function buildModals()
	-- Настройки
	local _, sp = makeModal("Settings", UDim2.fromOffset(460, 520), false)
	UI.list(sp, 8)
	UI.text("НАСТРОЙКИ", { Size = UDim2.new(1, 0, 0, 26), TextSize = 22, Font = Enum.Font.GothamBlack, ZIndex = 22, LayoutOrder = 0 }, sp)
	for i, def in ipairs(SETTINGS) do
		local row = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 38), BackgroundTransparency = 1, LayoutOrder = i, ZIndex = 22 }, sp)
		UI.text(def.Name, { Size = UDim2.new(0.5, 0, 1, 0), TextSize = 16, ZIndex = 22 }, row)
		local value = UI.text("", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -50, 0, 0), Size = UDim2.fromOffset(90, 38), TextSize = 16, Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 22 }, row)
		if def.Kind == "Bool" then
			UI.button("⇄", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(44, 36), ZIndex = 22 }, row, function()
				changeSetting(def, 1)
			end)
		else
			UI.button("−", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -144, 0, 0), Size = UDim2.fromOffset(44, 36), TextSize = 20, ZIndex = 22 }, row, function()
				changeSetting(def, -1)
			end)
			UI.button("+", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(44, 36), TextSize = 20, ZIndex = 22 }, row, function()
				changeSetting(def, 1)
			end)
		end
		table.insert(settingsRows, { Def = def, Value = value })
	end
	local help = UI.IsTouch
			and "Управление: джойстик — ходьба, свайп — обзор. 🔦 — фонарик, 🏃 — бег, ✋ — положить предмет. Нажимайте на подсказки рядом с предметами."
		or "Управление: WASD — ходьба, мышь — обзор, E — действие (R — второе действие), F — фонарик, Shift — бег, G — положить предмет, P — телефон, M — меню, T — задания. На мониторе охраны: 1–7, ←/→, X — выйти."
	UI.text(help, { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextSize = 13, TextColor3 = UI.Colors.Muted, ZIndex = 22, LayoutOrder = 20 }, sp)
	UI.button("Закрыть", { Size = UDim2.new(1, 0, 0, 40), BackgroundColor3 = UI.Colors.Accent, ZIndex = 22, LayoutOrder = 21 }, sp, function()
		HUD.CloseModals()
	end)

	-- История сообщений
	local _, pp = makeModal("Phone", UDim2.fromOffset(440, 500), false)
	UI.text("📱 СООБЩЕНИЯ", { Size = UDim2.new(1, 0, 0, 26), TextSize = 20, Font = Enum.Font.GothamBlack, ZIndex = 22 }, pp)
	phoneList = UI.new("ScrollingFrame", {
		Position = UDim2.fromOffset(0, 34),
		Size = UDim2.new(1, 0, 1, -86),
		BackgroundTransparency = 1,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		ZIndex = 22,
	}, pp)
	UI.list(phoneList, 8)
	UI.button("Закрыть", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(1, 0, 0, 40), BackgroundColor3 = UI.Colors.Accent, ZIndex = 22 }, pp, function()
		HUD.CloseModals()
	end)

	-- Документ (улика)
	local _, dp = makeModal("Document", UDim2.fromOffset(500, 420), true)
	docTitle = UI.text("", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextSize = 20, Font = Enum.Font.Antique, TextColor3 = Color3.fromRGB(60, 40, 20), ZIndex = 22 }, dp)
	docBody = UI.text("", { Position = UDim2.fromOffset(0, 60), Size = UDim2.new(1, 0, 1, -110), TextSize = 17, Font = Enum.Font.SpecialElite, TextColor3 = Color3.fromRGB(40, 30, 20), TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 22 }, dp)
	UI.button("Закрыть", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(1, 0, 0, 40), BackgroundColor3 = Color3.fromRGB(80, 60, 40), ZIndex = 22 }, dp, function()
		HUD.CloseModals()
	end)

	-- Концовка
	local _, ep = makeModal("Ending", UDim2.fromOffset(560, 470), false)
	UI.list(ep, 10)
	endingTitle = UI.text("", { Size = UDim2.new(1, 0, 0, 36), TextSize = 30, Font = Enum.Font.GothamBlack, ZIndex = 22, LayoutOrder = 1 }, ep)
	endingSubtitle = UI.text("", { Size = UDim2.new(1, 0, 0, 20), TextSize = 17, TextColor3 = UI.Colors.Muted, ZIndex = 22, LayoutOrder = 2 }, ep)
	endingBody = UI.text("", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextSize = 17, ZIndex = 22, LayoutOrder = 3 }, ep)
	endingStats = UI.text("", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextSize = 15, TextColor3 = UI.Colors.Amber, ZIndex = 22, LayoutOrder = 4 }, ep)
	endingFooter = UI.text("", { Size = UDim2.new(1, 0, 0, 18), TextSize = 14, TextColor3 = UI.Colors.Muted, ZIndex = 22, LayoutOrder = 5 }, ep)
	UI.button("Закрыть", { Size = UDim2.new(1, 0, 0, 40), BackgroundColor3 = UI.Colors.Accent, ZIndex = 22, LayoutOrder = 6 }, ep, function()
		HUD.CloseModals()
	end)
end

function HUD.Init(c)
	ctx = c
	UI = ctx.UI
	local playerGui = ctx.Player:WaitForChild("PlayerGui")
	gui = UI.new("ScreenGui", { Name = "NightHUD", ResetOnSpawn = false, IgnoreGuiInset = false, DisplayOrder = 5, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, playerGui)
	overlay = UI.new("ScreenGui", { Name = "NightOverlay", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 30, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, playerGui)
	fadeFrame = UI.new("Frame", { Name = "Fade", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1, ZIndex = 1 }, overlay)
	HUD.Gui = gui
	HUD.Overlay = overlay

	buildTopLeft()
	buildTasks()
	buildCenter()
	buildLobby()
	buildModals()
	HUD.RefreshSettings()

	-- Состояние смены
	local s = ctx.State
	for _, key in ipairs({ "Minutes", "Phase", "Power", "Countdown", "Night" }) do
		s:GetAttributeChangedSignal(key):Connect(updateClock)
	end
	s:GetAttributeChangedSignal("Percent"):Connect(updatePlan)
	s:GetAttributeChangedSignal("Phase"):Connect(function()
		updatePlan()
		local phase = s:GetAttribute("Phase")
		if phase == "Lobby" then
			-- новая смена: очистить старые сообщения и окна концовки
			messages = {}
			HUD.RefreshPhoneList()
			HUD.CloseModals()
			task.spawn(function()
				local ok, profile = pcall(function()
					return ctx.Remotes.GetProfile:InvokeServer()
				end)
				if ok then
					HUD.SetProfile(profile)
				end
			end)
		end
	end)
	updateClock()
	updatePlan()

	-- Задания
	local tasksFolder = ReplicatedStorage:WaitForChild("Tasks")
	for _, f in ipairs(tasksFolder:GetChildren()) do
		watchTask(f)
	end
	tasksFolder.ChildAdded:Connect(watchTask)
	tasksFolder.ChildRemoved:Connect(function(f)
		local r = taskRows[f]
		if r then
			r.Frame:Destroy()
			taskRows[f] = nil
		end
	end)

	-- Предмет в руках
	ctx.Player:GetAttributeChangedSignal("Carry"):Connect(updateCarry)
	updateCarry()
end

return HUD
