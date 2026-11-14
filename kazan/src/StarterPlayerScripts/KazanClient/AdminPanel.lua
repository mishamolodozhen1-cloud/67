-- Админ-панель (видна только администраторам). Удобна и на телефоне, и на ПК.
-- Полёт и ноклип работают на клиенте, остальное выполняет сервер после проверки прав.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Places = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Places"))

local AdminPanel = {}

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local request

local ACCENT = Color3.fromRGB(46, 160, 100)
local DANGER = Color3.fromRGB(196, 62, 62)
local BG = Color3.fromRGB(22, 24, 32)
local CARD = Color3.fromRGB(34, 38, 50)
local BTN = Color3.fromRGB(48, 54, 70)
local TEXT = Color3.fromRGB(240, 242, 248)

local gui, panel, content, toastLabel, flyPad
local tabs = {}
local currentTab = "self"

local flying, noclip = false, false
local flySpeed = 120
local vertical = 0
local flyConn, flyLV, flyAO, flyAtt
local frozen = {}

-------------------------------------------------------------------------------
-- Вспомогательные элементы интерфейса
-------------------------------------------------------------------------------
local function make(className, props, parent)
	local inst = Instance.new(className)
	for k, v in pairs(props) do
		inst[k] = v
	end
	inst.Parent = parent
	return inst
end

local function corner(inst, px)
	make("UICorner", { CornerRadius = UDim.new(0, px or 10) }, inst)
end

local function toast(text)
	toastLabel.Text = text
	toastLabel.TextTransparency = 0
	toastLabel.BackgroundTransparency = 0.15
	toastLabel.Visible = true
	local stamp = os.clock()
	toastLabel:SetAttribute("Stamp", stamp)
	task.delay(2.6, function()
		if toastLabel:GetAttribute("Stamp") == stamp then
			toastLabel.Visible = false
		end
	end)
end

local function call(action, a, b)
	local ok, success, msg = pcall(function()
		return request:InvokeServer(action, a, b)
	end)
	if not ok then
		toast("Нет связи с сервером")
		return false
	end
	toast(msg or (success and "Готово" or "Ошибка"))
	return success
end

local function header(text)
	return make("TextLabel", {
		Size = UDim2.new(1, 0, 0, 22),
		BackgroundTransparency = 1,
		Text = text,
		TextColor3 = Color3.fromRGB(150, 210, 175),
		Font = Enum.Font.GothamBold,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, content)
end

local function button(parent, text, color, onClick, height)
	local b = make("TextButton", {
		Size = UDim2.new(1, 0, 0, height or 42),
		BackgroundColor3 = color or BTN,
		Text = text,
		TextColor3 = TEXT,
		Font = Enum.Font.GothamBold,
		TextSize = 16,
		AutoButtonColor = true,
		TextWrapped = true,
	}, parent)
	corner(b, 9)
	b.Activated:Connect(function()
		onClick(b)
	end)
	return b
end

local function grid(height, cellWidthScale)
	local frame = make("Frame", { Size = UDim2.new(1, 0, 0, height), BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.Y }, content)
	make("UIGridLayout", {
		CellSize = UDim2.new(cellWidthScale, -6, 0, 40),
		CellPadding = UDim2.new(0, 6, 0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, frame)
	return frame
end

local function toggle(text, getter, setter)
	local b
	local function refresh()
		local on = getter()
		b.Text = text .. (on and ":  ВКЛ" or ":  ВЫКЛ")
		b.BackgroundColor3 = on and ACCENT or BTN
	end
	b = button(content, text, BTN, function()
		setter(not getter())
		refresh()
	end)
	refresh()
	return b
end

-------------------------------------------------------------------------------
-- Полёт и ноклип
-------------------------------------------------------------------------------
local function stopFly()
	flying = false
	if flyConn then
		flyConn:Disconnect()
		flyConn = nil
	end
	for _, inst in ipairs({ flyLV, flyAO, flyAtt }) do
		if inst then
			inst:Destroy()
		end
	end
	flyLV, flyAO, flyAtt = nil, nil, nil
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.PlatformStand = false
	end
	if flyPad then
		flyPad.Visible = false
	end
end

local function startFly()
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hrp or not hum then
		return false
	end
	flying = true
	flyAtt = make("Attachment", { Name = "FlyAttachment" }, hrp)
	flyLV = make("LinearVelocity", {
		Attachment0 = flyAtt,
		MaxForce = math.huge,
		RelativeTo = Enum.ActuatorRelativeTo.World,
		VectorVelocity = Vector3.zero,
	}, hrp)
	flyAO = make("AlignOrientation", {
		Mode = Enum.OrientationAlignmentMode.OneAttachment,
		Attachment0 = flyAtt,
		RigidityEnabled = true,
	}, hrp)
	hum.PlatformStand = true
	flyPad.Visible = true
	flyConn = RunService.RenderStepped:Connect(function()
		if not hrp.Parent then
			stopFly()
			return
		end
		local look = camera.CFrame.LookVector
		local right = camera.CFrame.RightVector
		local flatLook = Vector3.new(look.X, 0, look.Z)
		local flatRight = Vector3.new(right.X, 0, right.Z)
		if flatLook.Magnitude < 0.01 then
			flatLook = Vector3.new(0, 0, -1)
		end
		flatLook = flatLook.Unit
		flatRight = flatRight.Magnitude > 0.01 and flatRight.Unit or Vector3.new(1, 0, 0)
		local md = hum.MoveDirection
		local dir = look * md:Dot(flatLook) + right * md:Dot(flatRight) + Vector3.new(0, vertical, 0)
		if dir.Magnitude > 1 then
			dir = dir.Unit
		end
		flyLV.VectorVelocity = dir * flySpeed
		flyAO.CFrame = CFrame.lookAt(Vector3.zero, flatLook)
	end)
	return true
end

RunService.Stepped:Connect(function()
	if noclip and player.Character then
		for _, d in ipairs(player.Character:GetDescendants()) do
			if d:IsA("BasePart") then
				d.CanCollide = false
			end
		end
	end
end)

-------------------------------------------------------------------------------
-- Вкладки
-------------------------------------------------------------------------------
local builders = {}

function builders.self()
	header("Передвижение")
	toggle("Полёт", function()
		return flying
	end, function(on)
		if on then
			startFly()
		else
			stopFly()
		end
	end)
	toggle("Сквозь стены", function()
		return noclip
	end, function(on)
		noclip = on
		if not on and player.Character then
			for _, d in ipairs(player.Character:GetDescendants()) do
				if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" then
					d.CanCollide = true
				end
			end
		end
	end)
	header("Скорость ходьбы")
	local g1 = grid(40, 0.2)
	for _, v in ipairs({ 16, 32, 60, 120, 250 }) do
		button(g1, tostring(v), BTN, function()
			call("Speed", v)
		end)
	end
	header("Скорость полёта")
	local g2 = grid(40, 0.25)
	for _, v in ipairs({ 60, 120, 300, 700 }) do
		button(g2, tostring(v), BTN, function()
			flySpeed = v
			toast("Скорость полёта: " .. v)
		end)
	end
	header("Сила прыжка")
	local g3 = grid(40, 0.25)
	for _, v in ipairs({ 50, 100, 200, 400 }) do
		button(g3, tostring(v), BTN, function()
			call("Jump", v)
		end)
	end
	header("Персонаж")
	local godOn, invisOn = player:GetAttribute("AdminGod") == true, player:GetAttribute("AdminInvisible") == true
	toggle("Бессмертие", function()
		return godOn
	end, function(on)
		godOn = on
		player:SetAttribute("AdminGod", on)
		call("God", on)
	end)
	toggle("Невидимость", function()
		return invisOn
	end, function(on)
		invisOn = on
		player:SetAttribute("AdminInvisible", on)
		call("Invisible", on)
	end)
	local g4 = grid(40, 0.5)
	button(g4, "Вылечить", BTN, function()
		call("Heal")
	end)
	button(g4, "Переродиться", BTN, function()
		stopFly()
		call("Respawn")
	end)
end

function builders.teleport()
	header("Достопримечательности Казани")
	for i, place in ipairs(Places.List) do
		button(content, place.name, BTN, function()
			call("Teleport", i)
		end)
	end
end

function builders.world()
	header("Время суток")
	local g = grid(40, 0.25)
	for _, t in ipairs({ { "Утро", 7.5 }, { "День", 13 }, { "Закат", 18.6 }, { "Ночь", 22.5 } }) do
		button(g, t[1], BTN, function()
			call("Time", t[2])
		end)
	end
	local fogOn = false
	toggle("Туман", function()
		return fogOn
	end, function(on)
		fogOn = on
		call("Fog", on)
	end)
	header("Гравитация")
	local g2 = grid(40, 1 / 3)
	for _, t in ipairs({ { "Обычная", 196.2 }, { "Лёгкая", 90 }, { "Луна", 32 } }) do
		button(g2, t[1], BTN, function()
			call("Gravity", t[2])
		end)
	end
	header("Объявление для всех")
	local box = make("TextBox", {
		Size = UDim2.new(1, 0, 0, 64),
		BackgroundColor3 = CARD,
		TextColor3 = TEXT,
		PlaceholderText = "Текст объявления…",
		PlaceholderColor3 = Color3.fromRGB(140, 146, 160),
		Text = "",
		ClearTextOnFocus = false,
		TextWrapped = true,
		MultiLine = true,
		Font = Enum.Font.Gotham,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
	}, content)
	corner(box, 9)
	make("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingTop = UDim.new(0, 6) }, box)
	button(content, "Отправить объявление", ACCENT, function()
		if call("Announce", box.Text) then
			box.Text = ""
		end
	end)
end

function builders.players()
	header("Игроки на сервере")
	for _, other in ipairs(Players:GetPlayers()) do
		local card = make("Frame", { Size = UDim2.new(1, 0, 0, 96), BackgroundColor3 = CARD }, content)
		corner(card, 10)
		make("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), PaddingTop = UDim.new(0, 6) }, card)
		make("TextLabel", {
			Size = UDim2.new(1, 0, 0, 24),
			BackgroundTransparency = 1,
			Text = other.DisplayName .. "  (@" .. other.Name .. ")" .. (other == player and "  — это ты" or ""),
			TextColor3 = TEXT,
			Font = Enum.Font.GothamBold,
			TextSize = 15,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}, card)
		local row = make("Frame", { Size = UDim2.new(1, 0, 0, 44), Position = UDim2.new(0, 0, 0, 30), BackgroundTransparency = 1 }, card)
		make("UIGridLayout", { CellSize = UDim2.new(0.25, -5, 0, 40), CellPadding = UDim2.new(0, 5, 0, 0) }, row)
		local uid = other.UserId
		button(row, "К нему", BTN, function()
			call("GotoPlayer", uid)
		end)
		button(row, "Ко мне", BTN, function()
			call("Bring", uid)
		end)
		button(row, frozen[uid] and "Разморозить" or "Заморозить", BTN, function(b)
			frozen[uid] = not frozen[uid]
			b.Text = frozen[uid] and "Разморозить" or "Заморозить"
			call("Freeze", uid, frozen[uid])
		end)
		local armed = false
		button(row, "Кик", DANGER, function(b)
			if other == player then
				toast("Себя кикнуть нельзя")
				return
			end
			if not armed then
				armed = true
				b.Text = "Точно?"
				task.delay(3, function()
					armed = false
					if b.Parent then
						b.Text = "Кик"
					end
				end)
				return
			end
			call("Kick", uid)
		end)
	end
end

local function showTab(name)
	currentTab = name
	for key, tb in pairs(tabs) do
		tb.BackgroundColor3 = (key == name) and ACCENT or BTN
	end
	for _, c in ipairs(content:GetChildren()) do
		if not c:IsA("UIListLayout") and not c:IsA("UIPadding") then
			c:Destroy()
		end
	end
	builders[name]()
	content.CanvasPosition = Vector2.zero
end

-------------------------------------------------------------------------------
-- Окно
-------------------------------------------------------------------------------
local function layoutPanel()
	local vp = camera.ViewportSize
	panel.Size = UDim2.fromOffset(math.min(440, vp.X - 24), math.min(520, vp.Y - 70))
end

local function makeDraggable(handle)
	local dragging, startPos, startInput
	handle.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			startInput = input.Position
			startPos = panel.Position
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
				end
			end)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local delta = input.Position - startInput
			panel.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
		end
	end)
end

function AdminPanel.Start()
	request = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("AdminRequest")

	gui = make("ScreenGui", { Name = "AdminPanel", ResetOnSpawn = false, DisplayOrder = 50, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, player:WaitForChild("PlayerGui"))

	local open = make("TextButton", {
		Name = "Open",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 10, 0.42, 0),
		Size = UDim2.fromOffset(58, 58),
		BackgroundColor3 = ACCENT,
		Text = "👑",
		TextSize = 28,
		Font = Enum.Font.GothamBold,
		TextColor3 = TEXT,
	}, gui)
	corner(open, 29)
	make("UIStroke", { Color = Color3.fromRGB(255, 255, 255), Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, open)

	panel = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundColor3 = BG,
		Visible = false,
	}, gui)
	corner(panel, 14)
	make("UIStroke", { Color = ACCENT, Thickness = 2 }, panel)
	layoutPanel()
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(layoutPanel)

	local top = make("Frame", { Size = UDim2.new(1, 0, 0, 44), BackgroundTransparency = 1 }, panel)
	make("TextLabel", {
		Size = UDim2.new(1, -60, 1, 0),
		Position = UDim2.fromOffset(14, 0),
		BackgroundTransparency = 1,
		Text = "👑  Админ-панель · Казань",
		TextColor3 = TEXT,
		Font = Enum.Font.GothamBlack,
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, top)
	local close = make("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, 0),
		Size = UDim2.fromOffset(36, 36),
		BackgroundColor3 = DANGER,
		Text = "✕",
		TextColor3 = TEXT,
		Font = Enum.Font.GothamBold,
		TextSize = 18,
	}, top)
	corner(close, 18)
	makeDraggable(top)

	local tabRow = make("Frame", { Size = UDim2.new(1, -16, 0, 40), Position = UDim2.fromOffset(8, 46), BackgroundTransparency = 1 }, panel)
	make("UIGridLayout", { CellSize = UDim2.new(0.25, -5, 1, 0), CellPadding = UDim2.new(0, 5, 0, 0), SortOrder = Enum.SortOrder.LayoutOrder }, tabRow)
	local order = { { "self", "Я" }, { "teleport", "Телепорт" }, { "world", "Мир" }, { "players", "Игроки" } }
	for i, t in ipairs(order) do
		local key = t[1]
		local b = make("TextButton", {
			LayoutOrder = i,
			BackgroundColor3 = BTN,
			Text = t[2],
			TextColor3 = TEXT,
			Font = Enum.Font.GothamBold,
			TextSize = 15,
		}, tabRow)
		corner(b, 8)
		b.Activated:Connect(function()
			showTab(key)
		end)
		tabs[key] = b
	end

	content = make("ScrollingFrame", {
		Position = UDim2.fromOffset(8, 94),
		Size = UDim2.new(1, -16, 1, -102),
		BackgroundTransparency = 1,
		ScrollBarThickness = 6,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
	}, panel)
	make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, content)
	make("UIPadding", { PaddingRight = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8) }, content)

	toastLabel = make("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.fromOffset(320, 36),
		BackgroundColor3 = Color3.fromRGB(16, 18, 24),
		TextColor3 = TEXT,
		Font = Enum.Font.GothamBold,
		TextSize = 15,
		Visible = false,
		ZIndex = 10,
	}, gui)
	corner(toastLabel, 10)

	-- Кнопки высоты для полёта (для телефона; на ПК — Пробел / Ctrl)
	flyPad = make("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.4, 0),
		Size = UDim2.fromOffset(70, 150),
		BackgroundTransparency = 1,
		Visible = false,
	}, gui)
	local function padButton(text, y, dirValue)
		local b = make("TextButton", {
			Position = UDim2.fromOffset(0, y),
			Size = UDim2.fromOffset(70, 70),
			BackgroundColor3 = ACCENT,
			BackgroundTransparency = 0.15,
			Text = text,
			TextColor3 = TEXT,
			Font = Enum.Font.GothamBlack,
			TextSize = 30,
		}, flyPad)
		corner(b, 35)
		b.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
				vertical = dirValue
			end
		end)
		b.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
				vertical = 0
			end
		end)
	end
	padButton("▲", 0, 1)
	padButton("▼", 80, -1)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not flying then
			return
		end
		if input.KeyCode == Enum.KeyCode.Space then
			vertical = 1
		elseif input.KeyCode == Enum.KeyCode.LeftControl or input.KeyCode == Enum.KeyCode.C then
			vertical = -1
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.LeftControl or input.KeyCode == Enum.KeyCode.C then
			vertical = 0
		end
	end)

	open.Activated:Connect(function()
		panel.Visible = not panel.Visible
		if panel.Visible then
			layoutPanel()
			showTab(currentTab)
		end
	end)
	close.Activated:Connect(function()
		panel.Visible = false
	end)

	Players.PlayerAdded:Connect(function()
		if panel.Visible and currentTab == "players" then
			showTab("players")
		end
	end)
	Players.PlayerRemoving:Connect(function()
		if panel.Visible and currentTab == "players" then
			task.defer(showTab, "players")
		end
	end)
	player.CharacterAdded:Connect(function()
		stopFly()
	end)
	showTab("self")
end

return AdminPanel
