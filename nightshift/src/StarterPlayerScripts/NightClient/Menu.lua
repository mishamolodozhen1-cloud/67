-- Menu: главное меню (публичный сервер — «холл»).
--   Фон — ночной MART 24 под дождём: камера непрерывно плывёт по замкнутой траектории (через дорогу,
--   между машинами, к вывеске, подъём над парковкой), с лёгкой «ручной» дрожью и глубиной резкости.
--   Слева — название (буквы появляются по очереди) и крупные кнопки:
--     ИГРАТЬ ОДНОМУ · СОЗДАТЬ КОМНАТУ · ВОЙТИ ПО КОДУ · ОТКРЫТЫЕ КОМНАТЫ · КАК ИГРАТЬ
--   Справа выезжает панель выбранного пункта. На телефоне панель занимает место кнопок.
-- Кнопки: наведение — подсветка и сдвиг, нажатие — «вдавливание», результат — переход или сообщение.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Texts = require(Shared:WaitForChild("Texts"))
local Models = require(Shared:WaitForChild("Models"))

local Menu = {}

local ctx, UI
local gui, shade, left, panel, busyFrame, busyLabel, busyBar, toastLabel, profileLabel
local scaleObj
local grid, credits, menuTitles = nil, nil, {}
local pages = {}
local current = nil
local compact = false
local busy = false
local joinDigits = ""
local joinDisplay = {}
local roomsList, roomsEmpty
local createOpen, createMax = true, 4
local segButtons = {}
local music

local ACCENT = Color3.fromRGB(226, 52, 52)
local INK = Color3.fromRGB(240, 240, 236)
local MUTED = Color3.fromRGB(150, 156, 166)
local CARD = Color3.fromRGB(16, 18, 23)
local CARD_HOVER = Color3.fromRGB(30, 33, 41)

local function tween(obj, t, props, style, dir)
	local tw = TweenService:Create(obj, TweenInfo.new(t, style or Enum.EasingStyle.Quint, dir or Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end

local function sound(name, volume)
	if ctx and ctx.Audio then
		ctx.Audio.Play(name, nil, volume)
	end
end

-------------------------------------------------------------------------------
-- Камера фона: замкнутая плавная траектория
-------------------------------------------------------------------------------
local CAM = {
	-- через дорогу, деревья на переднем плане
	{ Vector3.new(-8, 5.4, 139), Vector3.new(-42, 9.5, 50) },
	-- край дороги, низко
	{ Vector3.new(-30, 3.6, 120), Vector3.new(-50, 8, 50) },
	-- между машинами на парковке
	{ Vector3.new(-58, 3.1, 89), Vector3.new(-44, 4.6, 64) },
	-- у витрины, вывеска крупно
	{ Vector3.new(-74, 6.2, 70), Vector3.new(-50, 11, 50) },
	-- подъём над парковкой
	{ Vector3.new(-46, 16, 101), Vector3.new(-50, 7, 52) },
	-- отлёт к дороге
	{ Vector3.new(-14, 10, 126), Vector3.new(-36, 8, 52) },
}
local LOOP_SECONDS = 96

local function catmull(p0, p1, p2, p3, t)
	local t2, t3 = t * t, t * t * t
	return 0.5 * ((2 * p1) + (p2 - p0) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (3 * p1 - p0 - 3 * p2 + p3) * t3)
end

local function loopAt(index, u)
	local n = #CAM
	local x = (u % 1) * n
	local i = math.floor(x)
	local t = x - i
	local function p(k)
		return CAM[(k % n) + 1][index]
	end
	-- сглаживание внутри каждого участка: камера не дёргается на опорных точках
	return catmull(p(i - 1), p(i), p(i + 1), p(i + 2), t)
end

local camConn
local dof
local function startCamera()
	local cam = workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Scriptable
	cam.FieldOfView = 52
	dof = Lighting:FindFirstChild("DepthOfField")
	local t0 = os.clock()
	local function frame()
		local t = os.clock() - t0
		local u = t / LOOP_SECONDS
		local pos = loopAt(1, u)
		local look = loopAt(2, u)
		-- «ручная» камера: медленные небольшие покачивания
		local nx = math.noise(t * 0.21, 1.7) * 0.012
		local ny = math.noise(t * 0.17, 8.3) * 0.016
		local nz = math.noise(t * 0.13, 4.1) * 0.01
		-- в широком режиме магазин смещён вправо, чтобы слева читались кнопки
		local yaw = compact and 0 or math.rad(9)
		local cf = CFrame.lookAt(pos, look) * CFrame.Angles(nx, yaw + ny, nz)
		cam.CFrame = cf
		cam.FieldOfView = 50 + math.sin(t * 0.11) * 2.5
		if dof then
			local d = (look - pos).Magnitude
			dof.FocusDistance = d
			dof.InFocusRadius = math.max(12, d * 0.45)
			dof.FarIntensity = 0.28
			dof.NearIntensity = 0.45
		end
	end
	if RunService:IsClient() then
		RunService:BindToRenderStep("NS_MenuCamera", Enum.RenderPriority.Camera.Value + 1, frame)
		camConn = true
	else
		camConn = RunService.Heartbeat:Connect(frame)
	end
end

-------------------------------------------------------------------------------
-- Элементы
-------------------------------------------------------------------------------
-- Кнопка меню: полоска слева, крупная надпись, подпись мелко. Наведение — сдвиг и подсветка,
-- нажатие — «вдавливание» (UIScale), звук.
local function menuButton(parent, order, title, subtitle, primary, onClick)
	local b = UI.new("TextButton", {
		Name = title,
		Size = UDim2.new(1, 0, 0, primary and 60 or 56),
		BackgroundColor3 = primary and ACCENT or CARD,
		BackgroundTransparency = primary and 0.05 or 0.18,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = order,
	}, parent)
	UI.corner(b, 10)
	local stroke = UI.stroke(b, Color3.new(1, 1, 1), 1, primary and 0.7 or 0.88)
	local sc = UI.new("UIScale", { Scale = 1 }, b)
	local bar = UI.new("Frame", {
		Position = UDim2.new(0, 0, 0.2, 0),
		Size = UDim2.new(0, 3, 0.6, 0),
		BackgroundColor3 = primary and INK or ACCENT,
		BackgroundTransparency = primary and 0.3 or 0,
	}, b)
	UI.corner(bar, 2)
	local inner = UI.new("Frame", { Position = UDim2.fromOffset(18, 0), Size = UDim2.new(1, -30, 1, 0), BackgroundTransparency = 1 }, b)
	local titleLabel = UI.text(title, {
		Position = UDim2.new(0, 0, 0.5, subtitle and -19 or -11),
		Size = UDim2.new(1, 0, 0, 22),
		TextSize = 19,
		Font = Enum.Font.GothamBlack,
		TextColor3 = INK,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, inner)
	table.insert(menuTitles, titleLabel)
	if subtitle then
		UI.text(subtitle, {
			Position = UDim2.new(0, 0, 0.5, 3),
			Size = UDim2.new(1, 0, 0, 16),
			TextSize = 13,
			TextColor3 = primary and Color3.fromRGB(255, 220, 220) or MUTED,
			TextWrapped = false,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}, inner)
	end
	local base = b.BackgroundColor3
	local hover = primary and Color3.fromRGB(240, 70, 70) or CARD_HOVER
	b.MouseEnter:Connect(function()
		tween(b, 0.18, { BackgroundColor3 = hover })
		tween(inner, 0.22, { Position = UDim2.fromOffset(24, 0) })
		tween(bar, 0.22, { Size = UDim2.new(0, 5, 0.7, 0), Position = UDim2.new(0, 0, 0.15, 0) })
		tween(stroke, 0.18, { Transparency = 0.6 })
		sound("UiHover", 0.25)
	end)
	b.MouseLeave:Connect(function()
		tween(b, 0.25, { BackgroundColor3 = base })
		tween(inner, 0.3, { Position = UDim2.fromOffset(18, 0) })
		tween(bar, 0.3, { Size = UDim2.new(0, 3, 0.6, 0), Position = UDim2.new(0, 0, 0.2, 0) })
		tween(stroke, 0.25, { Transparency = primary and 0.7 or 0.88 })
		tween(sc, 0.2, { Scale = 1 })
	end)
	b.MouseButton1Down:Connect(function()
		tween(sc, 0.08, { Scale = 0.965 }, Enum.EasingStyle.Quad)
	end)
	b.MouseButton1Up:Connect(function()
		tween(sc, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
	end)
	b.Activated:Connect(function()
		if busy then
			return
		end
		tween(sc, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
		sound("UiClick", 0.5)
		onClick()
	end)
	return b
end

-- Обычная кнопка панели (с теми же состояниями)
local function panelButton(parent, text, props, onClick)
	local b = UI.button(text, props, parent)
	b.AutoButtonColor = false
	local base = b.BackgroundColor3
	local sc = UI.new("UIScale", { Scale = 1 }, b)
	b.MouseEnter:Connect(function()
		tween(b, 0.15, { BackgroundColor3 = base:Lerp(Color3.new(1, 1, 1), 0.12) })
	end)
	b.MouseLeave:Connect(function()
		tween(b, 0.2, { BackgroundColor3 = base })
		tween(sc, 0.2, { Scale = 1 })
	end)
	b.MouseButton1Down:Connect(function()
		tween(sc, 0.07, { Scale = 0.94 }, Enum.EasingStyle.Quad)
	end)
	b.MouseButton1Up:Connect(function()
		tween(sc, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
	end)
	b.Activated:Connect(function()
		if busy then
			return
		end
		tween(sc, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
		sound("UiClick", 0.45)
		onClick(b)
	end)
	return b
end

function Menu.Toast(text, style)
	if not toastLabel then
		return
	end
	toastLabel.Text = text
	toastLabel.TextColor3 = (style == "warn") and Color3.fromRGB(255, 150, 110) or INK
	toastLabel.Visible = true
	toastLabel.TextTransparency = 1
	toastLabel.BackgroundTransparency = 1
	tween(toastLabel, 0.25, { TextTransparency = 0, BackgroundTransparency = 0.2 })
	local stamp = os.clock()
	toastLabel:SetAttribute("Stamp", stamp)
	task.delay(4, function()
		if toastLabel:GetAttribute("Stamp") == stamp then
			tween(toastLabel, 0.4, { TextTransparency = 1, BackgroundTransparency = 1 })
		end
	end)
	if style == "warn" then
		sound("ScanError", 0.35)
	end
end

-------------------------------------------------------------------------------
-- Ожидание перехода на сервер
-------------------------------------------------------------------------------
local busyToken = 0
local function setBusy(text)
	busyToken = busyToken + 1
	local token = busyToken
	if not text then
		busy = false
		tween(busyFrame, 0.35, { BackgroundTransparency = 1 })
		tween(busyLabel, 0.25, { TextTransparency = 1 })
		task.delay(0.36, function()
			if busyToken == token then
				busyFrame.Visible = false
			end
		end)
		return
	end
	busy = true
	busyFrame.Visible = true
	busyLabel.Text = text
	tween(busyFrame, 0.6, { BackgroundTransparency = 0.05 })
	tween(busyLabel, 0.4, { TextTransparency = 0 })
	-- бегущая полоска
	task.spawn(function()
		while busyToken == token and busy do
			busyBar.Position = UDim2.new(-0.35, 0, 0, 0)
			local tw = tween(busyBar, 1.1, { Position = UDim2.new(1, 0, 0, 0) }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
			tw.Completed:Wait()
		end
	end)
end

-- Запрос на сервер: пока идёт — экран ожидания; если телепорт не случился за 25 с — сообщение
local function request(action, arg, waitText, goText)
	setBusy(waitText)
	local ok, result = pcall(function()
		return ctx.Remotes.Rooms:InvokeServer(action, arg)
	end)
	if not ok or type(result) ~= "table" or not result.Ok then
		setBusy(nil)
		Menu.Toast((type(result) == "table" and result.Error) or "Сервер не ответил. Попробуйте ещё раз.", "warn")
		return nil
	end
	busyLabel.Text = goText and goText(result) or "Переходим на сервер…"
	sound("PowerUp", 0.25)
	if music then
		tween(music, 2.5, { Volume = 0 })
	end
	local token = busyToken
	task.delay(25, function()
		if busyToken == token and busy then
			setBusy(nil)
			Menu.Toast("Не получилось перейти на сервер. Попробуйте ещё раз.", "warn")
			if music then
				tween(music, 2, { Volume = music:GetAttribute("Base") or 0.4 })
			end
		end
	end)
	return result
end

-------------------------------------------------------------------------------
-- Панели
-------------------------------------------------------------------------------
local function showPage(name)
	if busy then
		return
	end
	if current == name then
		name = nil
	end
	for n, p in pairs(pages) do
		p.Visible = (n == name)
	end
	current = name
	if name then
		panel.Visible = true
		-- панель выезжает справа (на телефоне — вместо кнопок)
		local target = compact and UDim2.new(0.5, 0, 0.5, 0) or UDim2.new(1, -56, 0.5, 0)
		panel.AnchorPoint = compact and Vector2.new(0.5, 0.5) or Vector2.new(1, 0.5)
		panel.Position = target + UDim2.fromOffset(60, 0)
		panel.GroupTransparency = 1
		tween(panel, 0.4, { Position = target, GroupTransparency = 0 })
		if compact then
			-- на телефоне кнопки уходят влево и перестают нажиматься, пока открыта панель
			tween(left, 0.3, { GroupTransparency = 1, Position = UDim2.new(0, -40, 0.5, 0) }).Completed:Connect(function()
				if current then
					left.Visible = false
				end
			end)
		end
		if name == "Rooms" then
			Menu.RefreshRooms()
		end
	else
		tween(panel, 0.25, { GroupTransparency = 1 })
		task.delay(0.26, function()
			if not current then
				panel.Visible = false
			end
		end)
		left.Visible = true
		tween(left, 0.35, { GroupTransparency = 0, Position = UDim2.new(0, compact and 24 or 56, 0.5, 0) })
	end
end

local function pageFrame(name, title)
	local p = UI.new("Frame", { Name = name, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false }, panel)
	UI.text(title, { Size = UDim2.new(1, -110, 0, 30), TextSize = 22, Font = Enum.Font.GothamBlack }, p)
	panelButton(p, "Назад", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, -2),
		Size = UDim2.fromOffset(96, 34),
		TextSize = 15,
		BackgroundColor3 = Color3.fromRGB(40, 44, 54),
	}, function()
		showPage(nil)
	end)
	local body = UI.new("Frame", { Name = "Body", Position = UDim2.fromOffset(0, 44), Size = UDim2.new(1, 0, 1, -44), BackgroundTransparency = 1 }, p)
	pages[name] = p
	return body
end

-- Переключатель из нескольких вариантов
local function segmented(parent, y, label, options, get, set)
	UI.text(label, { Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, 0, 0, 18), TextSize = 14, TextColor3 = MUTED }, parent)
	local row = UI.new("Frame", { Position = UDim2.fromOffset(0, y + 24), Size = UDim2.new(1, 0, 0, 46), BackgroundTransparency = 1 }, parent)
	UI.list(row, 8, true)
	local list = {}
	local function refresh()
		for _, it in ipairs(list) do
			local on = get() == it.Value
			tween(it.Button, 0.18, { BackgroundColor3 = on and ACCENT or Color3.fromRGB(34, 37, 46) })
			it.Button.TextColor3 = on and INK or Color3.fromRGB(200, 204, 212)
		end
	end
	local w = 1 / #options
	for i, opt in ipairs(options) do
		local b = panelButton(row, opt.Text, {
			Size = UDim2.new(w, -8 * (#options - 1) / #options, 1, 0),
			TextSize = 15,
			LayoutOrder = i,
			BackgroundColor3 = Color3.fromRGB(34, 37, 46),
		}, function()
			set(opt.Value)
			refresh()
		end)
		table.insert(list, { Button = b, Value = opt.Value })
	end
	table.insert(segButtons, refresh)
	refresh()
end

local function buildCreate()
	local body = pageFrame("Create", "НОВАЯ КОМНАТА")
	segmented(body, 0, "Кто может войти", {
		{ Text = "Все (в списке)", Value = true },
		{ Text = "Только по коду", Value = false },
	}, function()
		return createOpen
	end, function(v)
		createOpen = v
	end)
	segmented(body, 84, "Сколько сотрудников", {
		{ Text = "2", Value = 2 },
		{ Text = "3", Value = 3 },
		{ Text = "4", Value = 4 },
	}, function()
		return createMax
	end, function(v)
		createMax = v
	end)
	UI.text("Вы получите код из 4 цифр — назовите его друзьям. Код виден в игре, пока смена не началась.", {
		Position = UDim2.fromOffset(0, 172),
		Size = UDim2.new(1, 0, 0, 40),
		TextSize = 14,
		TextColor3 = MUTED,
	}, body)
	panelButton(body, "СОЗДАТЬ И ВОЙТИ", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, 52),
		TextSize = 18,
		Font = Enum.Font.GothamBlack,
		BackgroundColor3 = ACCENT,
	}, function()
		request("Create", { Open = createOpen, Max = createMax }, "Создаём комнату…", function(r)
			return "Комната " .. tostring(r.Code) .. "\nПереходим на сервер…"
		end)
	end)
end

local function updateJoinDisplay()
	for i, box in ipairs(joinDisplay) do
		local ch = string.sub(joinDigits, i, i)
		box.Label.Text = ch
		local active = i == #joinDigits + 1
		tween(box.Stroke, 0.15, { Transparency = active and 0.2 or 0.8, Color = active and ACCENT or Color3.new(1, 1, 1) })
	end
end

local function typeDigit(d)
	if #joinDigits < 4 then
		joinDigits = joinDigits .. d
		updateJoinDisplay()
		local box = joinDisplay[#joinDigits]
		if box then
			box.Scale.Scale = 1.15
			tween(box.Scale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
		end
	end
end

local function eraseDigit()
	joinDigits = string.sub(joinDigits, 1, -2)
	updateJoinDisplay()
end

local function submitJoin()
	if #joinDigits ~= 4 then
		Menu.Toast("Введите 4 цифры кода комнаты", "warn")
		return
	end
	request("Join", joinDigits, "Ищем комнату " .. joinDigits .. "…", function(r)
		return "Комната " .. tostring(r.Code) .. "\nПереходим на сервер…"
	end)
end

local function buildJoin()
	local body = pageFrame("Join", "ВХОД ПО КОДУ")
	local row = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 64), BackgroundTransparency = 1 }, body)
	UI.list(row, 10, true).HorizontalAlignment = Enum.HorizontalAlignment.Center
	for i = 1, 4 do
		local box = UI.new("Frame", { Size = UDim2.fromOffset(62, 64), BackgroundColor3 = Color3.fromRGB(24, 27, 34), LayoutOrder = i }, row)
		UI.corner(box, 10)
		local st = UI.stroke(box, Color3.new(1, 1, 1), 2, 0.8)
		local sc = UI.new("UIScale", { Scale = 1 }, box)
		local label = UI.text("", { Size = UDim2.fromScale(1, 1), TextSize = 34, Font = Enum.Font.GothamBlack, TextXAlignment = Enum.TextXAlignment.Center }, box)
		joinDisplay[i] = { Label = label, Stroke = st, Scale = sc }
	end
	local pad = UI.new("Frame", { Position = UDim2.fromOffset(0, 76), Size = UDim2.new(1, 0, 1, -76), BackgroundTransparency = 1 }, body)
	local grid = UI.new("UIGridLayout", {
		CellSize = UDim2.new(1 / 3, -6, 0.25, -6),
		CellPadding = UDim2.fromOffset(9, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, pad)
	grid.FillDirectionMaxCells = 3
	local keys = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "Стереть", "0", "Войти" }
	for i, k in ipairs(keys) do
		local isDigit = string.match(k, "^%d$") ~= nil
		panelButton(pad, k, {
			LayoutOrder = i,
			TextSize = isDigit and 24 or 16,
			Font = isDigit and Enum.Font.GothamBold or Enum.Font.GothamBlack,
			BackgroundColor3 = (k == "Войти") and ACCENT or Color3.fromRGB(34, 37, 46),
		}, function()
			if isDigit then
				typeDigit(k)
			elseif k == "Стереть" then
				eraseDigit()
			else
				submitJoin()
			end
		end)
	end
	updateJoinDisplay()
end

local PHASE_TEXT = { Lobby = "ждут сотрудников", Intro = "начинается смена", Shift = "идёт смена", Ending = "смена заканчивается" }

function Menu.RefreshRooms()
	if not roomsList then
		return
	end
	roomsEmpty.Text = "Загрузка…"
	roomsEmpty.Visible = true
	task.spawn(function()
		local ok, result = pcall(function()
			return ctx.Remotes.Rooms:InvokeServer("List")
		end)
		for _, c in ipairs(roomsList:GetChildren()) do
			if c:IsA("Frame") then
				c:Destroy()
			end
		end
		if not ok or type(result) ~= "table" or not result.Ok then
			roomsEmpty.Text = "Не удалось загрузить список. Нажмите «Обновить»."
			return
		end
		local rooms = result.Rooms or {}
		roomsEmpty.Visible = #rooms == 0
		roomsEmpty.Text = "Открытых комнат пока нет.\nСоздайте свою — друзья войдут по коду."
		for i, r in ipairs(rooms) do
			local card = UI.new("Frame", { Size = UDim2.new(1, -8, 0, 62), BackgroundColor3 = Color3.fromRGB(24, 27, 34), LayoutOrder = i }, roomsList)
			UI.corner(card, 10)
			UI.text("Комната " .. r.Code, { Position = UDim2.fromOffset(14, 8), Size = UDim2.new(1, -140, 0, 22), TextSize = 17, Font = Enum.Font.GothamBlack, TextWrapped = false }, card)
			UI.text(string.format("%s · %d из %d · %s", r.Host, r.Players, r.Max, PHASE_TEXT[r.Phase] or ""), {
				Position = UDim2.fromOffset(14, 33),
				Size = UDim2.new(1, -140, 0, 18),
				TextSize = 13,
				TextColor3 = MUTED,
				TextWrapped = false,
				TextTruncate = Enum.TextTruncate.AtEnd,
			}, card)
			panelButton(card, "Войти", {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -10, 0.5, 0),
				Size = UDim2.fromOffset(110, 42),
				TextSize = 16,
				BackgroundColor3 = ACCENT,
			}, function()
				request("Join", r.Code, "Входим в комнату " .. r.Code .. "…", function()
					return "Комната " .. r.Code .. "\nПереходим на сервер…"
				end)
			end)
			card.BackgroundTransparency = 1
			tween(card, 0.3 + i * 0.05, { BackgroundTransparency = 0 })
		end
	end)
end

local function buildRooms()
	local body = pageFrame("Rooms", "ОТКРЫТЫЕ КОМНАТЫ")
	roomsList = UI.new("ScrollingFrame", {
		Size = UDim2.new(1, 0, 1, -58),
		BackgroundTransparency = 1,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 5,
		ScrollingDirection = Enum.ScrollingDirection.Y,
	}, body)
	UI.list(roomsList, 8)
	roomsEmpty = UI.text("", { Size = UDim2.new(1, 0, 0, 60), TextSize = 15, TextColor3 = MUTED, TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 0 }, roomsList)
	panelButton(body, "Обновить", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, 46),
		TextSize = 16,
		BackgroundColor3 = Color3.fromRGB(40, 44, 54),
	}, function()
		Menu.RefreshRooms()
	end)
end

local function buildHelp()
	local body = pageFrame("Help", "КАК ИГРАТЬ")
	local scroll = UI.new("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 5,
	}, body)
	UI.text(table.concat({
		"Вы — ночной сотрудник круглосуточного супермаркета " .. Texts.StoreName .. ". Смена — с 00:00 до 06:00.",
		"",
		"Обслуживайте покупателей на кассе, выкладывайте товар со склада, мойте полы, проверяйте холодильники и камеры наблюдения, чините свет в щитке.",
		"",
		"Выполните план смены — и утро наступит спокойно. Но среди покупателей есть один, который просто стоит и смотрит. Он не двигается, пока на него смотрят.",
		"",
		UI.IsTouch and "Управление: джойстик — ходьба, свайп — обзор, кнопки справа — фонарик и бег. Нажимайте на подсказки у предметов."
			or "Управление: WASD — ходьба, мышь — обзор, E — действие, F — фонарик, Shift — бег, G — положить, P — телефон, M — меню, T — задания.",
		"",
		"Три концовки: хорошая, плохая и секретная.",
		"",
		"3D-модели: " .. table.concat(Models.Credits, " · "),
	}, "\n"), { Size = UDim2.new(1, -10, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextSize = 15, TextColor3 = Color3.fromRGB(214, 216, 222), TextYAlignment = Enum.TextYAlignment.Top }, scroll)
end

-------------------------------------------------------------------------------
-- Название: буквы появляются по очереди, неон иногда мигает
-------------------------------------------------------------------------------
local function buildTitle(parent)
	local holder = UI.new("Frame", { Name = "Title", Size = UDim2.new(1, 0, 0, 62), BackgroundTransparency = 1, LayoutOrder = 1 }, parent)
	local layout = UI.list(holder, 0, true)
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	local letters = {}
	local word = "NIGHT SHIFT"
	for i = 1, #word do
		local ch = string.sub(word, i, i)
		local l = UI.new("TextLabel", {
			BackgroundTransparency = 1,
			Text = ch,
			Font = Enum.Font.GothamBlack,
			TextSize = 58,
			TextColor3 = ACCENT,
			TextTransparency = 1,
			Size = UDim2.fromOffset(ch == " " and 16 or 0, 62),
			AutomaticSize = Enum.AutomaticSize.X,
			LayoutOrder = i,
		}, holder)
		local pad = UI.new("UIPadding", { PaddingTop = UDim.new(0, 18) }, l)
		table.insert(letters, { Label = l, Pad = pad })
	end
	-- появление: каждая буква поднимается и проявляется с небольшой задержкой
	task.delay(0.4, function()
		for i, it in ipairs(letters) do
			task.delay((i - 1) * 0.055, function()
				tween(it.Label, 0.5, { TextTransparency = 0 })
				tween(it.Pad, 0.6, { PaddingTop = UDim.new(0, 0) }, Enum.EasingStyle.Back)
			end)
		end
	end)
	-- мигание неона: одна-две буквы гаснут на долю секунды
	task.spawn(function()
		task.wait(3)
		while gui and gui.Parent do
			task.wait(math.random(30, 90) / 10)
			local it = letters[math.random(1, #letters)]
			if it.Label.Text ~= " " then
				for _ = 1, math.random(1, 3) do
					it.Label.TextTransparency = 0.75
					task.wait(math.random(4, 9) / 100)
					it.Label.TextTransparency = 0
					task.wait(math.random(3, 12) / 100)
				end
			end
		end
	end)
	return holder
end

-------------------------------------------------------------------------------
-- Раскладка под экран
-------------------------------------------------------------------------------
local function layout()
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	local v = cam.ViewportSize
	-- телефон: панели по очереди; ПК и планшет — кнопки слева, панель справа
	compact = v.X < 980 or (UI.IsTouch and v.Y < 560)
	-- на телефоне: кнопки сеткой 2×2 под главной, авторы моделей — в «Как играть»
	if compact then
		grid.CellSize = UDim2.new(0.5, -4, 0, 64)
		grid.FillDirectionMaxCells = 2
		left.Size = UDim2.fromOffset(440, 0)
	else
		grid.CellSize = UDim2.new(1, 0, 0, 56)
		grid.FillDirectionMaxCells = 1
		left.Size = UDim2.fromOffset(400, 0)
	end
	for _, l in ipairs(menuTitles) do
		l.TextSize = compact and 17 or 19
	end
	credits.Visible = not compact
	-- масштаб: всё должно помещаться по высоте (сверху — кнопки Roblox, снизу — отступ)
	local designH = compact and 330 or 520
	local s = math.min((v.Y - 64) / designH, (v.X - 48) / (compact and 440 or 1000))
	s = math.clamp(s, 0.55, compact and 1.25 or 1.5)
	scaleObj.Scale = s
	local ps = math.clamp(math.min((v.Y - 24) / 430, (v.X - 24) / 440, compact and 1.25 or s), 0.55, 1.5)
	panel:FindFirstChildOfClass("UIScale").Scale = ps
	if not current then
		left.Position = UDim2.new(0, compact and 24 or 56, 0.5, 0)
	end
end

-------------------------------------------------------------------------------
function Menu.Init(c)
	ctx = c
	UI = ctx.UI
	gui = UI.new("ScreenGui", {
		Name = "NightMenu",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 40,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, ctx.Player:WaitForChild("PlayerGui"))

	-- затемнение слева, чтобы текст читался на фоне
	shade = UI.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0 }, gui)
	UI.new("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.12),
			NumberSequenceKeypoint.new(0.42, 0.55),
			NumberSequenceKeypoint.new(0.75, 0.92),
			NumberSequenceKeypoint.new(1, 0.85),
		}),
	}, shade)

	left = UI.new("CanvasGroup", {
		Name = "Left",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 56, 0.5, 0),
		Size = UDim2.fromOffset(400, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		GroupTransparency = 1,
	}, gui)
	scaleObj = UI.new("UIScale", { Scale = 1 }, left)
	UI.list(left, 8)
	buildTitle(left)
	UI.text(Texts.StoreName .. " · ночная смена 00:00–06:00 · 1–4 игрока", {
		Size = UDim2.new(1, 0, 0, 18),
		TextSize = 14,
		TextColor3 = MUTED,
		TextWrapped = false,
		LayoutOrder = 2,
	}, left)
	profileLabel = UI.text("", { Size = UDim2.new(1, 0, 0, 18), TextSize = 13, TextColor3 = Color3.fromRGB(255, 196, 70), TextWrapped = false, LayoutOrder = 3 }, left)
	UI.new("Frame", { Size = UDim2.new(1, 0, 0, 6), BackgroundTransparency = 1, LayoutOrder = 4 }, left)
	local buttons = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 5 }, left)
	UI.list(buttons, 8)
	local secondary = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 2 }, buttons)
	grid = UI.new("UIGridLayout", { CellPadding = UDim2.fromOffset(8, 8), CellSize = UDim2.new(1, 0, 0, 56), SortOrder = Enum.SortOrder.LayoutOrder }, secondary)
	menuButton(buttons, 1, "ИГРАТЬ ОДНОМУ", "Только вы и ночь", true, function()
		request("Solo", nil, "Готовим вашу смену…", function()
			return "Одиночная смена\nПереходим на сервер…"
		end)
	end)
	menuButton(secondary, 2, "СОЗДАТЬ КОМНАТУ", "Код для друзей, до 4 сотрудников", false, function()
		showPage("Create")
	end)
	menuButton(secondary, 3, "ВОЙТИ ПО КОДУ", "Код из 4 цифр от друга", false, function()
		joinDigits = ""
		updateJoinDisplay()
		showPage("Join")
	end)
	menuButton(secondary, 4, "ОТКРЫТЫЕ КОМНАТЫ", "Присоединиться к другим", false, function()
		showPage("Rooms")
	end)
	menuButton(secondary, 5, "КАК ИГРАТЬ", "Правила и управление", false, function()
		showPage("Help")
	end)
	credits = UI.text("3D-модели: " .. table.concat(Models.Credits, " · "), {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextSize = 10,
		TextColor3 = Color3.fromRGB(120, 124, 134),
		LayoutOrder = 9,
	}, left)

	panel = UI.new("CanvasGroup", {
		Name = "Panel",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -56, 0.5, 0),
		Size = UDim2.fromOffset(440, 430),
		BackgroundColor3 = Color3.fromRGB(12, 14, 18),
		BackgroundTransparency = 0.12,
		GroupTransparency = 1,
		Visible = false,
	}, gui)
	UI.new("UIScale", { Scale = 1 }, panel)
	UI.corner(panel, 14)
	UI.stroke(panel, Color3.new(1, 1, 1), 1, 0.88)
	UI.padding(panel, 20)
	buildCreate()
	buildJoin()
	buildRooms()
	buildHelp()

	toastLabel = UI.text("", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 18),
		Size = UDim2.fromOffset(0, 40),
		AutomaticSize = Enum.AutomaticSize.X,
		TextSize = 16,
		Font = Enum.Font.GothamBold,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = false,
		BackgroundColor3 = Color3.fromRGB(10, 10, 12),
		BackgroundTransparency = 1,
		TextTransparency = 1,
		Visible = false,
		ZIndex = 50,
	}, gui)
	UI.corner(toastLabel, 10)
	UI.new("UIPadding", { PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16) }, toastLabel)

	busyFrame = UI.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1, Visible = false, ZIndex = 60 }, gui)
	UI.new("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, ZIndex = 60 }, busyFrame)
	busyLabel = UI.text("", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.47),
		Size = UDim2.fromOffset(520, 70),
		TextSize = 22,
		Font = Enum.Font.GothamBold,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTransparency = 1,
		ZIndex = 61,
	}, busyFrame)
	local track = UI.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.47, 46),
		Size = UDim2.fromOffset(220, 3),
		BackgroundColor3 = Color3.fromRGB(60, 60, 66),
		ClipsDescendants = true,
		ZIndex = 61,
	}, busyFrame)
	busyBar = UI.new("Frame", { Size = UDim2.new(0.35, 0, 1, 0), BackgroundColor3 = ACCENT, ZIndex = 62 }, track)

	layout()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(layout)

	-- клавиатура: цифры и Backspace на странице кода, Esc — назад
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or busy or input.UserInputType ~= Enum.UserInputType.Keyboard then
			return
		end
		local k = input.KeyCode
		if k == Enum.KeyCode.Escape then
			if current then
				showPage(nil)
			end
		elseif current == "Join" then
			local digit = k.Value - Enum.KeyCode.Zero.Value
			local kp = k.Value - Enum.KeyCode.KeypadZero.Value
			if digit >= 0 and digit <= 9 then
				typeDigit(tostring(digit))
			elseif kp >= 0 and kp <= 9 then
				typeDigit(tostring(kp))
			elseif k == Enum.KeyCode.Backspace then
				eraseDigit()
			elseif k == Enum.KeyCode.Return or k == Enum.KeyCode.KeypadEnter then
				submitJoin()
			end
		end
	end)

	-- открытие: из черноты проявляется ночная улица, потом кнопки
	startCamera()
	tween(shade, 2.5, { BackgroundTransparency = 0 })
	local intro = UI.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), ZIndex = 70 }, gui)
	tween(intro, 2.6, { BackgroundTransparency = 1 }, Enum.EasingStyle.Sine)
	task.delay(2.7, function()
		intro:Destroy()
	end)
	task.delay(0.9, function()
		tween(left, 1.1, { GroupTransparency = 0 })
	end)

	-- музыка меню (если её нет — тревожный гул)
	music = ctx.Audio.Loop("MenuMusic", nil) or ctx.Audio.Loop("TensionDrone", nil)
	if music then
		local base = music.Volume > 0 and math.min(music.Volume, 0.5) or 0.4
		local group = game:GetService("SoundService"):FindFirstChild("NS_Music")
		if group then
			music.SoundGroup = group
		end
		music:SetAttribute("Base", base)
		music.Volume = 0
		music:Play()
		tween(music, 4, { Volume = base }, Enum.EasingStyle.Sine)
	end
end

function Menu.SetProfile(profile)
	if profileLabel and type(profile) == "table" and (profile.Nights or 0) > 0 then
		profileLabel.Text = string.format("Смен отработано: %d · лучший план: %d%%", profile.Nights or 0, profile.BestPercent or 0)
	end
end

-- Для тестов: состояние меню
function Menu.Debug()
	return { Page = current, Compact = compact, Busy = busy, Digits = joinDigits, Camera = camConn ~= nil }
end
Menu.ShowPage = showPage
Menu.TypeDigit = typeDigit

return Menu
