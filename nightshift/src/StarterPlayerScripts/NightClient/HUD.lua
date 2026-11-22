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
local gui, overlay, main
local waitPanel
local hudMode = "Full"
local clockLabel, nightLabel, barFill, powerLabel, batteryLabel
local tasksPanel, tasksBody, planLabel, tasksCollapsed
local taskRows = {}
local notifyHolder
local subtitleLabel
local carryFrame, carryLabel
local staminaBack, staminaFill
local lobbyPanel, lobbyStats, lobbyCountdown, lobbyRoom
local lobbyNightTitle, lobbyNightInfo, lobbyNightDots, lobbyPrev, lobbyNext
local countdownLabel
local modals = {}
local settingsRows = {}
local settingsToggles = {}
local docTitle, docBody
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
-- Окна не должны вылезать за экран (телефон в горизонтальном положении — всего ~360 точек в высоту):
-- высота окна ограничивается экраном, а содержимое длинных окон прокручивается.
local fitList = {}
local function fitModals()
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	local v = cam.ViewportSize
	local s = UI.Scale()
	for _, f in ipairs(fitList) do
		local h = math.min(f.H, math.max(220, (v.Y - 24) / s))
		local w = math.min(f.W, math.max(260, (v.X - 24) / s))
		f.Holder.Size = UDim2.fromOffset(w, h)
	end
end

local function makeModal(name, size, paper, scroll)
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
	table.insert(fitList, { Holder = holder, W = size.X.Offset, H = size.Y.Offset })
	if scroll then
		local content = UI.new("ScrollingFrame", {
			Name = "Scroll",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollBarThickness = 5,
			ScrollingDirection = Enum.ScrollingDirection.Y,
			ZIndex = 22,
		}, panel)
		UI.new("UIPadding", { PaddingRight = UDim.new(0, 8) }, content)
		return holder, content
	end
	return holder, panel
end

function HUD.CloseModals(keepPhone)
	if not keepPhone and ctx.Phone then
		ctx.Phone.Close()
	end
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
		-- окно мягко «всплывает» снизу
		local panel = m:FindFirstChild("Panel")
		if panel then
			panel.Position = UDim2.fromOffset(0, 16)
			tween(panel, 0.28, { Position = UDim2.fromOffset(0, 0) })
		end
		if ctx.Audio then
			ctx.Audio.Play("UiOpen", nil, 0.35)
		end
	end
end

function HUD.AnyModalOpen()
	for _, m in pairs(modals) do
		if m.Visible then
			return true
		end
	end
	return ctx.Phone ~= nil and ctx.Phone.IsOpen()
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

-- Новое сообщение на телефон: оно попадает в мессенджер, а если телефон в кармане —
-- сверху появляется короткое уведомление; нажатие на него достаёт телефон сразу на этом чате
function HUD.Phone(sender, text)
	local time = Util.clock(ctx.State:GetAttribute("Minutes") or 0)
	if not ctx.Phone or ctx.Phone.Add(sender, text, time) then
		return
	end
	local card = UI.new("TextButton", {
		Name = "PhoneBanner",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Color3.fromRGB(22, 24, 30),
		BackgroundTransparency = 0.08,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = math.floor(os.clock() * 100),
	}, notifyHolder)
	UI.corner(card, 12)
	UI.padding(card, 10)
	local icon = UI.new("TextLabel", {
		Size = UDim2.fromOffset(34, 34),
		BackgroundColor3 = Color3.fromRGB(40, 170, 90),
		Text = "✉",
		TextColor3 = Color3.new(1, 1, 1),
		TextSize = 18,
		Font = Enum.Font.GothamBold,
	}, card)
	UI.corner(icon, 9)
	local body = UI.new("Frame", {
		Position = UDim2.fromOffset(44, 0),
		Size = UDim2.new(1, -44, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
	}, card)
	UI.list(body, 2)
	UI.text(sender .. "  ·  " .. time, { Size = UDim2.new(1, 0, 0, 16), TextSize = 13, Font = Enum.Font.GothamBold, TextColor3 = UI.Colors.Amber, LayoutOrder = 1 }, body)
	local preview = UI.text(text, {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextSize = 15,
		LayoutOrder = 2,
	}, body)
	UI.new("UISizeConstraint", { MaxSize = Vector2.new(math.huge, 40) }, preview)
	preview.TextTruncate = Enum.TextTruncate.AtEnd
	UI.text(UI.IsTouch and "нажмите, чтобы открыть телефон" or "открыть телефон — [P] или нажмите", { Size = UDim2.new(1, 0, 0, 14), TextSize = 12, TextColor3 = UI.Colors.Muted, LayoutOrder = 3 }, body)
	card.Activated:Connect(function()
		card:Destroy()
		ctx.Phone.Open(sender)
	end)
	task.delay(7, function()
		if card.Parent then
			tween(card, 0.5, { BackgroundTransparency = 1 })
			task.wait(0.5)
			card:Destroy()
		end
	end)
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
	local mark = UI.dot(top, 12, UI.Colors.Amber, false)
	mark.Position = UDim2.fromOffset(3, 4)
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
	UI.setDot(r.Mark, done and UI.Colors.Good or UI.Colors.Amber, done)
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

-- Пока открыт экран кассы, список заданий убирается (освобождает место справа)
local tasksHidden = false
function HUD.SetTasksHidden(on)
	tasksHidden = on
	if tasksPanel then
		tasksPanel.Visible = not on
	end
end

local tasksChevron
function HUD.ToggleTasks()
	tasksCollapsed = not tasksCollapsed
	tasksBody.Visible = not tasksCollapsed
	if tasksChevron then
		local parent = tasksChevron.Parent
		tasksChevron:Destroy()
		tasksChevron = UI.chevron(parent, tasksCollapsed and "Left" or "Down", 14, UI.Colors.Text, 3)
		if not UI.IsTouch then
			tasksChevron.Position = UDim2.new(0.5, -8, 0.5, 0)
		end
	end
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
	waitPanel.Visible = phase == "Intro" and not ctx.IntroPlaying
	clockLabel.Text = Util.clock(minutes)
	local code = s:GetAttribute("RoomCode") or ""
	local night = math.clamp(s:GetAttribute("Night") or 1, 1, Config.NightCount)
	local info = Texts.Nights[night]
	nightLabel.Text = string.format("НОЧЬ %d · %s", night, code ~= "" and ("КОМНАТА " .. code) or (info and info.Title or Texts.StoreName))
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
		-- выбор ночи: открытые ночи — по прогрессу игроков в комнате
		local max = math.clamp(s:GetAttribute("NightMax") or 1, 1, Config.NightCount)
		lobbyNightTitle.Text = string.format("НОЧЬ %d — «%s»", night, info and info.Title or "")
		lobbyNightInfo.Text = info and info.Lobby or ""
		lobbyPrev.Visible = night > 1
		lobbyNext.Visible = night < max
		for i, d in ipairs(lobbyNightDots) do
			local color = i == night and UI.Colors.Accent or (i <= max and UI.Colors.Text or UI.Colors.Muted)
			UI.setDot(d, color, i <= max)
		end
		-- комната: код для друзей и сколько сотрудников уже здесь
		local count = #Players:GetPlayers()
		if code ~= "" then
			lobbyRoom.Text = string.format("КОМНАТА %s  ·  сотрудников: %d из %d  ·  назовите код друзьям", code, count, s:GetAttribute("RoomMax") or 4)
			lobbyRoom.Visible = true
		elseif s:GetAttribute("RoomSolo") then
			lobbyRoom.Text = "ОДИНОЧНАЯ СМЕНА  ·  сюда никто не войдёт"
			lobbyRoom.Visible = true
		else
			lobbyRoom.Visible = false
		end
	end
end

function HUD.Refresh()
	updateClock()
end

-- Режим интерфейса: "Full" — всё; "Cameras" — только уведомления, телефон и субтитры;
-- "Hidden" — ничего (кат-сцена)
function HUD.SetMode(mode)
	hudMode = mode
	gui.Enabled = mode ~= "Hidden"
	main.Visible = mode == "Full"
end

function HUD.Mode()
	return hudMode
end

function HUD.SetProfile(profile)
	if not profile then
		return
	end
	local function mark(n)
		return (n or 0) > 0 and "есть" or "нет"
	end
	lobbyStats.Text = string.format(
		"Смен отработано: %d · заработано: %d руб. · лучший план: %d%%\nОткрыто ночей: %d из %d%s · концовки: хорошая %s · плохая %s · секретная %s",
		profile.Nights or 0,
		profile.Earnings or 0,
		profile.BestPercent or 0,
		math.clamp(profile.NightUnlocked or 1, 1, Config.NightCount),
		Config.NightCount,
		(profile.Completed or 0) > 0 and " (все пять ночей пройдены)" or "",
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
	local names = { Box = "Коробка", Mop = "Швабра", Trash = "Мешок с мусором", Delivery = "Поставка", Parcel = "Заказ" }
	local text = names[kind] or carry
	if kind == "Parcel" and category ~= "" then
		text = text .. " №" .. category .. " — отдайте покупателю у стойки выдачи"
	elseif category and category ~= "" and Products.Categories[category] then
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
	batteryLabel.Text = string.format("ФОНАРИК %d%%", math.floor(frac * 100 + 0.5))
	batteryLabel.TextColor3 = frac < 0.2 and UI.Colors.Warn or (on and UI.Colors.Amber or UI.Colors.Muted)
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
	local nightInfo = Texts.Nights[math.clamp(stats.Night or 1, 1, Config.NightCount)]
	if stats.Kind == "Good" and nightInfo and nightInfo.Good then
		e = nightInfo.Good
	end
	endingTitle.Text = e.Title
	endingTitle.TextColor3 = stats.Kind == "Good" and UI.Colors.Good or (stats.Kind == "Secret" and UI.Colors.Anomaly or UI.Colors.Accent)
	endingSubtitle.Text = e.Subtitle
	endingBody.Text = e.Body
	endingStats.Text = string.format(
		"План выполнен: %d%%\nПокупок на кассах самообслуживания: %d (выручка %d руб.)\nЗадержано воров: %d · скрылось: %d\nВыдано заказов: %d · ушли недовольными: %d\nЗарплата за смену: %d руб. · найдено улик: %d из 4",
		stats.Percent or 0,
		stats.Served or 0,
		stats.Revenue or 0,
		stats.Caught or 0,
		stats.Escaped or 0,
		stats.Orders or 0,
		(stats.LeftAngry or 0) + (stats.FalseChecks or 0),
		stats.Salary or 0,
		stats.Clues or 0
	)
	HUD.OpenModal("Ending")
	task.spawn(function()
		local left = Config.EndingSeconds - 8
		while modals.Ending.Visible and left > 0 do
			endingFooter.Text = string.format("%s через %d с", (stats.Kind == "Bad" or (stats.Night or 1) >= Config.NightCount) and "Новая смена" or "Следующая ночь", left)
			task.wait(1)
			left = left - 1
		end
		endingFooter.Text = (stats.Kind == "Bad") and "Ночь придётся повторить…" or "Следующая ночь…"
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
	for _, refresh in ipairs(settingsToggles) do
		refresh(false)
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
	}, main)
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
	batteryLabel = UI.text("ФОНАРИК 100%", { Position = UDim2.fromOffset(0, 74), Size = UDim2.new(0.5, 0, 0, 16), TextSize = 13, TextColor3 = UI.Colors.Muted }, panel)
	powerLabel = UI.text("НЕТ СВЕТА", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 74), Size = UDim2.new(0.5, 0, 0, 16), TextSize = 13, Font = Enum.Font.GothamBold, TextColor3 = UI.Colors.Warn, TextXAlignment = Enum.TextXAlignment.Right, Visible = false }, panel)

	buttonsRow = UI.new("Frame", {
		Name = "Buttons",
		Position = UDim2.fromOffset(14, 128),
		Size = UDim2.fromOffset(250, 40),
		BackgroundTransparency = 1,
	}, main)
	UI.scaled(buttonsRow)
	UI.list(buttonsRow, 8, true)
	UI.button("Телефон" .. keyHint("P"), { Size = UDim2.fromOffset(UI.IsTouch and 118 or 140, 38), TextSize = 14, LayoutOrder = 1 }, buttonsRow, function()
		if ctx.Phone then
			ctx.Phone.Toggle()
		end
	end)
	UI.button("Меню" .. keyHint("M"), { Size = UDim2.fromOffset(UI.IsTouch and 100 or 102, 38), TextSize = 14, LayoutOrder = 2 }, buttonsRow, function()
		HUD.OpenModal("Settings")
	end)
end

-- Состояние касс самообслуживания: 6 индикаторов, цвет как у лампы на стойке кассы
-- (зелёный — свободна, синий — идёт покупка, мигает оранжевым — зовёт сотрудника, серый — отключена)
local kioskDots = {}
local function buildKioskRow()
	local row = UI.panel({
		Name = "Kiosks",
		Position = UDim2.fromOffset(14, 176),
		Size = UDim2.fromOffset(250, 34),
		BackgroundTransparency = 0.35,
	}, main)
	UI.scaled(row)
	UI.text("КАССЫ", { Position = UDim2.fromOffset(10, 0), Size = UDim2.fromOffset(70, 34), TextSize = 12, Font = Enum.Font.GothamBold, TextColor3 = UI.Colors.Muted }, row)
	for i = 1, 6 do
		local holder = UI.new("Frame", { Position = UDim2.fromOffset(74 + (i - 1) * 28, 0), Size = UDim2.fromOffset(26, 34), BackgroundTransparency = 1 }, row)
		local dot = UI.dot(holder, 12, UI.Colors.Muted, true)
		dot.AnchorPoint = Vector2.new(0.5, 0)
		dot.Position = UDim2.new(0.5, 0, 0, 5)
		UI.text(tostring(i), { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 18), Size = UDim2.fromOffset(20, 14), TextSize = 11, TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = UI.Colors.Muted }, holder)
		kioskDots[i] = dot
	end
	task.spawn(function()
		while true do
			task.wait(0.25)
			local store = workspace:FindFirstChild("Store")
			local f = store and store:FindFirstChild("Checkouts")
			for i, dot in ipairs(kioskDots) do
				local k = f and f:FindFirstChild("Kiosk" .. i)
				local lamp = k and k:FindFirstChild("StatusLamp")
				if lamp then
					UI.setDot(dot, lamp.Color, true)
				end
			end
		end
	end)
end

local function buildTasks()
	tasksPanel = UI.panel({
		Name = "Tasks",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 10),
		Size = UDim2.fromOffset(340, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	}, main)
	UI.scaled(tasksPanel)
	UI.padding(tasksPanel, 12)
	UI.list(tasksPanel, 8)
	local header = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 22), BackgroundTransparency = 1, LayoutOrder = 1 }, tasksPanel)
	UI.text("ЗАДАНИЯ", { Size = UDim2.new(0.5, 0, 1, 0), TextSize = 15, Font = Enum.Font.GothamBlack }, header)
	-- свернуть/развернуть список (стрелка нарисована полосками, на ПК рядом клавиша T)
	local toggle = UI.button(UI.IsTouch and "" or "     T", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, -4),
		Size = UDim2.fromOffset(UI.IsTouch and 44 or 52, 30),
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Center,
	}, header, function()
		HUD.ToggleTasks()
	end)
	tasksChevron = UI.chevron(toggle, "Down", 14, UI.Colors.Text, 3)
	if not UI.IsTouch then
		tasksChevron.Position = UDim2.new(0.5, -8, 0.5, 0)
	end
	planLabel = UI.text("", { Size = UDim2.new(1, 0, 0, 16), TextSize = 13, TextColor3 = UI.Colors.Muted, LayoutOrder = 2 }, tasksPanel)
	-- список заданий не опускается ниже середины экрана (на телефоне там кнопки), лишнее прокручивается
	tasksBody = UI.new("ScrollingFrame", {
		Name = "Body",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollBarThickness = 4,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 3,
	}, tasksPanel)
	UI.list(tasksBody, 10)
	local limit = UI.new("UISizeConstraint", {}, tasksBody)
	local function fitTasks()
		local cam = workspace.CurrentCamera
		local vy = cam and cam.ViewportSize.Y or 720
		local frac = UI.IsTouch and 0.42 or 0.62
		limit.MaxSize = Vector2.new(math.huge, math.max(120, vy * frac / UI.Scale()))
	end
	fitTasks()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fitTasks)
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
	-- уведомления — в просвете между часами (слева) и заданиями (справа), чтобы ничего не перекрывать;
	-- если просвета не хватает (узкий экран) — под кнопками слева
	local function fitNotify()
		local cam = workspace.CurrentCamera
		local s = UI.Scale()
		local vx = cam and cam.ViewportSize.X or 1280
		local clock = main:FindFirstChild("Clock")
		local left = clock and (clock.AbsolutePosition.X + clock.AbsoluteSize.X) or (14 + 250 * s)
		local right = vx - 14
		if tasksPanel and tasksPanel.Visible and tasksPanel.AbsoluteSize.X > 0 then
			right = tasksPanel.AbsolutePosition.X
		end
		local gap = right - left - 24
		if gap >= 180 * s then
			local w = math.min(460 * s, gap)
			notifyHolder.AnchorPoint = Vector2.new(0.5, 0)
			notifyHolder.Position = UDim2.fromOffset(math.floor((left + right) / 2), 10)
			notifyHolder.Size = UDim2.fromOffset(math.floor(w / s), 0)
		else
			-- под самой нижней панелью слева (часы, кнопки, кассы)
			local top = 210 * s
			for _, name in ipairs({ "Clock", "Buttons", "Kiosks" }) do
				local o = main:FindFirstChild(name)
				if o and o.Visible and o.AbsoluteSize.Y > 0 then
					top = math.max(top, o.AbsolutePosition.Y + o.AbsoluteSize.Y - gui.AbsolutePosition.Y)
				end
			end
			notifyHolder.AnchorPoint = Vector2.new(0, 0)
			notifyHolder.Position = UDim2.fromOffset(14, math.floor(top + 8))
			notifyHolder.Size = UDim2.fromOffset(250, 0)
		end
	end
	HUD.FitNotify = fitNotify
	task.defer(fitNotify)
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		task.defer(fitNotify)
	end)
	if tasksPanel then
		tasksPanel:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitNotify)
		tasksPanel:GetPropertyChangedSignal("Visible"):Connect(fitNotify)
	end

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
	}, main)
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
	}, main)
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
	}, main)
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
	}, main)
	UI.scaled(lobbyPanel)
	UI.padding(lobbyPanel, 16)
	UI.list(lobbyPanel, 6)
	UI.text("NIGHT SHIFT", { Size = UDim2.new(1, 0, 0, 34), TextSize = 32, Font = Enum.Font.GothamBlack, TextColor3 = UI.Colors.Accent, LayoutOrder = 1 }, lobbyPanel)
	UI.text(Texts.StoreName .. " · ночная охрана с 00:00 до 06:00 · 1–4 охранника", { Size = UDim2.new(1, 0, 0, 18), TextSize = 15, TextColor3 = UI.Colors.Muted, LayoutOrder = 2 }, lobbyPanel)
	lobbyRoom = UI.text("", {
		Size = UDim2.new(1, 0, 0, 34),
		TextSize = 16,
		Font = Enum.Font.GothamBlack,
		TextColor3 = UI.Colors.Text,
		BackgroundColor3 = UI.Colors.PanelLight,
		BackgroundTransparency = 0.1,
		TextXAlignment = Enum.TextXAlignment.Center,
		Visible = false,
		LayoutOrder = 3,
	}, lobbyPanel)
	UI.corner(lobbyRoom, 8)
	-- выбор ночи: < НОЧЬ 3 — «Отключение» >, что ждёт на смене, пять отметок
	local nightRow = UI.new("Frame", {
		Name = "NightSelect",
		Size = UDim2.new(1, 0, 0, 92),
		BackgroundColor3 = UI.Colors.PanelLight,
		BackgroundTransparency = 0.1,
		LayoutOrder = 4,
	}, lobbyPanel)
	UI.corner(nightRow, 8)
	local function pickNight(dir)
		local cur = ctx.State:GetAttribute("Night") or 1
		ctx.Remotes.Action:FireServer("SelectNight", cur + dir)
	end
	lobbyPrev = UI.button("", { Position = UDim2.fromOffset(8, 22), Size = UDim2.fromOffset(46, 46) }, nightRow, function()
		pickNight(-1)
	end)
	UI.chevron(lobbyPrev, "Left", 16, UI.Colors.Text, 3)
	lobbyNext = UI.button("", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 22), Size = UDim2.fromOffset(46, 46) }, nightRow, function()
		pickNight(1)
	end)
	UI.chevron(lobbyNext, "Right", 16, UI.Colors.Text, 3)
	lobbyNightTitle = UI.text("НОЧЬ 1", {
		Position = UDim2.fromOffset(62, 8),
		Size = UDim2.new(1, -124, 0, 24),
		TextSize = 19,
		Font = Enum.Font.GothamBlack,
		TextXAlignment = Enum.TextXAlignment.Center,
	}, nightRow)
	lobbyNightInfo = UI.text("", {
		Position = UDim2.fromOffset(62, 33),
		Size = UDim2.new(1, -124, 0, 36),
		TextSize = 13,
		TextColor3 = UI.Colors.Muted,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Top,
	}, nightRow)
	local dots = UI.new("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -8), Size = UDim2.fromOffset(5 * 10 + 4 * 8, 10), BackgroundTransparency = 1 }, nightRow)
	UI.list(dots, 8, true)
	lobbyNightDots = {}
	for i = 1, Config.NightCount do
		local d = UI.dot(dots, 10, UI.Colors.Muted, false)
		d.LayoutOrder = i
		table.insert(lobbyNightDots, d)
	end
	lobbyStats = UI.text("Загрузка профиля…", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextSize = 14, LayoutOrder = 5 }, lobbyPanel)
	UI.text(Texts.LobbyHint .. (UI.IsTouch and "." or " — или нажмите Enter."), { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextSize = 14, TextColor3 = UI.Colors.Amber, LayoutOrder = 6 }, lobbyPanel)
	local row = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 44), BackgroundTransparency = 1, LayoutOrder = 7 }, lobbyPanel)
	UI.button("НАЧАТЬ СМЕНУ" .. keyHint("Enter"), {
		Size = UDim2.fromOffset(240, 42),
		BackgroundColor3 = UI.Colors.Accent,
		TextSize = 16,
	}, row, function()
		HUD.RequestStart()
	end)
	lobbyCountdown = UI.text("", { Position = UDim2.fromOffset(256, 0), Size = UDim2.new(1, -256, 1, 0), TextSize = 14, TextColor3 = UI.Colors.Muted }, row)
	-- авторы 3D-моделей (лицензия CC BY 4.0 требует их указывать)
	local Models = require(Shared:WaitForChild("Models"))
	UI.text("3D-модели: " .. table.concat(Models.Credits, " · "), { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextSize = 11, TextColor3 = UI.Colors.Muted, LayoutOrder = 8 }, lobbyPanel)
end

function HUD.RequestStart()
	if ctx.State:GetAttribute("Phase") == "Lobby" then
		ctx.Remotes.Action:FireServer("StartShift")
	end
end

local function buildModals()
	-- Настройки
	local _, sp = makeModal("Settings", UDim2.fromOffset(460, 570), false, true)
	UI.list(sp, 8)
	UI.text("НАСТРОЙКИ", { Size = UDim2.new(1, 0, 0, 26), TextSize = 22, Font = Enum.Font.GothamBlack, ZIndex = 22, LayoutOrder = 0 }, sp)
	for i, def in ipairs(SETTINGS) do
		local row = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 38), BackgroundTransparency = 1, LayoutOrder = i, ZIndex = 22 }, sp)
		UI.text(def.Name, { Size = UDim2.new(0.5, 0, 1, 0), TextSize = 16, ZIndex = 22 }, row)
		local value = UI.text("", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -50, 0, 0), Size = UDim2.fromOffset(90, 38), TextSize = 16, Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 22 }, row)
		if def.Kind == "Bool" then
			-- переключатель вместо кнопки: сразу видно, включено или нет
			local _, refresh = UI.toggle(row, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), ZIndex = 22 }, function()
				return ctx.Settings[def.Key] == true
			end, function()
				changeSetting(def, 1)
			end)
			table.insert(settingsToggles, refresh)
		else
			UI.button("-", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -144, 0, 0), Size = UDim2.fromOffset(44, 36), TextSize = 20, ZIndex = 22 }, row, function()
				changeSetting(def, -1)
			end)
			UI.button("+", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(44, 36), TextSize = 20, ZIndex = 22 }, row, function()
				changeSetting(def, 1)
			end)
		end
		value.Visible = def.Kind ~= "Bool"
		table.insert(settingsRows, { Def = def, Value = value })
	end
	local help = UI.IsTouch
			and "Управление: джойстик — ходьба, свайп — обзор. Круглые кнопки у прыжка: фонарик и бег (бег включается касанием и выключается, когда вы остановились). Нажимайте на подсказки рядом с предметами. На мониторе камер — номера камер на плане магазина."
		or "Управление: WASD — ходьба, мышь — обзор, E — действие (R — второе действие), F — фонарик, Shift — бег, G — положить предмет, P — телефон, M — меню, T — задания. На мониторе камер: 1–9 или номера на плане, ←/→, X — выйти."
	UI.text(help, { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextSize = 13, TextColor3 = UI.Colors.Muted, ZIndex = 22, LayoutOrder = 20 }, sp)
	UI.button("Закрыть", { Size = UDim2.new(1, 0, 0, 40), BackgroundColor3 = UI.Colors.Accent, ZIndex = 22, LayoutOrder = 21 }, sp, function()
		HUD.CloseModals()
	end)
	-- выход в главное меню: второе нажатие в течение 4 секунд подтверждает
	local leaveArmed = 0
	local leave
	leave = UI.button("Выйти в главное меню", { Size = UDim2.new(1, 0, 0, 40), BackgroundColor3 = UI.Colors.PanelLight, ZIndex = 22, LayoutOrder = 22 }, sp, function()
		if os.clock() - leaveArmed > 4 then
			leaveArmed = os.clock()
			leave.Text = "Нажмите ещё раз, чтобы выйти"
			leave.BackgroundColor3 = UI.Colors.Warn
			task.delay(4, function()
				if os.clock() - leaveArmed >= 4 then
					leave.Text = "Выйти в главное меню"
					leave.BackgroundColor3 = UI.Colors.PanelLight
				end
			end)
			return
		end
		HUD.SaveSettings()
		HUD.CloseModals()
		HUD.Fade(0, 0.8)
		HUD.Notify("Возвращаемся в главное меню…", "info")
		local rooms = ctx.Remotes:FindFirstChild("Rooms")
		local ok = rooms and pcall(function()
			return rooms:InvokeServer("Leave")
		end)
		task.delay(20, function()
			-- телепорт не случился: вернуть картинку
			HUD.Fade(1, 0.8)
			if not ok then
				HUD.Notify("Не удалось выйти в меню. Попробуйте ещё раз.", "warn")
			end
		end)
	end)

	-- Документ (улика)
	local _, dp = makeModal("Document", UDim2.fromOffset(500, 420), true)
	docTitle = UI.text("", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextSize = 20, Font = Enum.Font.Antique, TextColor3 = Color3.fromRGB(60, 40, 20), ZIndex = 22 }, dp)
	docBody = UI.text("", { Position = UDim2.fromOffset(0, 60), Size = UDim2.new(1, 0, 1, -110), TextSize = 17, Font = Enum.Font.SpecialElite, TextColor3 = Color3.fromRGB(40, 30, 20), TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 22 }, dp)
	UI.button("Закрыть", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(1, 0, 0, 40), BackgroundColor3 = Color3.fromRGB(80, 60, 40), ZIndex = 22 }, dp, function()
		HUD.CloseModals()
	end)

	-- Концовка
	local _, ep = makeModal("Ending", UDim2.fromOffset(560, 470), false, true)
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
	main = UI.new("Frame", { Name = "Main", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, gui)
	-- пока другие смотрят вступление (или вы зашли позже) — короткая надпись внизу
	waitPanel = UI.panel({
		Name = "IntroWait",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -40),
		Size = UDim2.fromOffset(520, 64),
		Visible = false,
		ZIndex = 5,
	}, overlay)
	UI.scaled(waitPanel)
	UI.text("Смена вот-вот начнётся…\nДругие сотрудники ещё досматривают вступление.", {
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextSize = 16,
		ZIndex = 6,
	}, waitPanel)
	HUD.Gui = gui
	HUD.Overlay = overlay

	buildTopLeft()
	buildKioskRow()
	buildTasks()
	buildCenter()
	buildLobby()
	buildModals()
	HUD.RefreshSettings()
	fitModals()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fitModals)

	-- Состояние смены
	local s = ctx.State
	for _, key in ipairs({ "Minutes", "Phase", "Power", "Countdown", "Night", "NightMax", "RoomCode", "RoomSolo" }) do
		s:GetAttributeChangedSignal(key):Connect(updateClock)
	end
	s:GetAttributeChangedSignal("Percent"):Connect(updatePlan)
	s:GetAttributeChangedSignal("Phase"):Connect(function()
		updatePlan()
		local phase = s:GetAttribute("Phase")
		if phase == "Lobby" then
			-- новая смена: очистить старые сообщения и окна концовки
			if ctx.Phone then
				ctx.Phone.Clear()
			end
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
	Players.PlayerAdded:Connect(updateClock)
	Players.PlayerRemoving:Connect(function()
		task.defer(updateClock)
	end)

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
