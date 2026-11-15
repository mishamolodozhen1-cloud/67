-- CameraSystem: система видеонаблюдения MART 24 (монитор в кабинете менеджера и в охране).
--   • 9 камер (детали с тегом CCTV в Workspace.Store.Cameras, атрибуты Index и Title)
--   • справа внизу — план магазина: на нём видно, где висит каждая камера и куда она смотрит;
--     нажмите на номер камеры, чтобы переключиться. ПК: 1–9, ←/→ (A/D), X — выйти. Геймпад: крестовина, B
--   • картинка как у настоящей ночной камеры: почти без цвета, зерно, строки развёртки, виньетка,
--     дата и время в углу; при переключении — короткие помехи; поворотные камеры медленно ходят влево-вправо
--   • без электричества камеры переходят на ИК-подсветку (чёрно-белая картинка, видно недалеко)
--   • после 02:00 на записях бывают странности: «НЕТ СИГНАЛА», дата 14.11.2003,
--     человек, которого на самом деле там нет, или вы сами
--   • видеокассета 14.11.03 (улика) проигрывается здесь же
--   • ShowFeed/Glitch/SignalLost — для вступительной кат-сцены
local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
-- кадр отрисовки (в серверном тесте его нет — там Heartbeat)
local RENDER = RunService:IsClient() and RunService.RenderStepped or RunService.Heartbeat

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Util = require(Shared:WaitForChild("Util"))

local CameraSystem = {}

local ctx, UI
local isOpen = false
local tapeMode = false
local feedMode = false
local index = 1
local cams = {}
local gui, grain, staticFlash, lostFrame, lostNoise
local camNumber, camTitle, recLabel, timeLabel, sysLabel
local planHolder, planFrame, controlsBar
local planButtons = {}
local planBuilt = 0
local tears = {}
local cc
local irPart, irLight
local irMode = nil
local viewStart = 0
local reported = {}
local saved = {}
local props = {} -- локальные фигуры в кадре
local dateAnomaly = false
local fixedClock = nil
local glitchUntil = 0
local minuteStamp, lastMinutes = os.clock(), -1

local FEED_TEXT = Color3.fromRGB(226, 240, 230)
local LINE = Color3.fromRGB(150, 196, 168)

-- Поворотные камеры: амплитуда поворота в градусах
local PAN = { [2] = 9, [4] = 7, [5] = 7, [6] = 6 }

-- План магазина (комнаты совпадают с map.Rooms в MapBuilder): название, x0, z0, x1, z1
local PLAN = {
	{ "Торговый зал", -66, -12, 40, 50 },
	{ "Склад", -66, -64, -18, -12 },
	{ "", -18, -64, -10, -12 },
	{ "", -10, -40, 40, -34 },
	{ "Охрана", -10, -34, 12, -12 },
	{ "Персонал", 12, -34, 40, -12 },
	{ "Холод", -10, -64, 12, -40 },
	{ "Кабинет", 12, -64, 40, -40 },
	{ "Двор", -40, -92, 10, -64 },
}
-- Где на плане стоит кнопка камеры (центр того, что она снимает)
local PLAN_SPOT = {
	{ -50, 42 },
	{ 0, 36 },
	{ -42, 10 },
	{ 14, 15 },
	{ 18, -6 },
	{ -44, -40 },
	{ -14, -42 },
	{ 1, -54 },
	{ -15, -80 },
}
local PLAN_MIN_X, PLAN_MAX_X = -70, 44
local PLAN_MIN_Z, PLAN_MAX_Z = -95, 56
local PLAN_W = 214
local PLAN_H = math.floor(PLAN_W * (PLAN_MAX_Z - PLAN_MIN_Z) / (PLAN_MAX_X - PLAN_MIN_X))

local function toPlan(x, z)
	return (x - PLAN_MIN_X) / (PLAN_MAX_X - PLAN_MIN_X) * PLAN_W, (z - PLAN_MIN_Z) / (PLAN_MAX_Z - PLAN_MIN_Z) * PLAN_H
end

local function collectCams()
	cams = CollectionService:GetTagged("CCTV")
	table.sort(cams, function(a, b)
		return (a:GetAttribute("Index") or 0) < (b:GetAttribute("Index") or 0)
	end)
end

local function clearProps()
	for _, m in ipairs(props) do
		m:Destroy()
	end
	props = {}
end

local function rootHeight(model)
	local hum = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	if hum and root then
		return hum.HipHeight + root.Size.Y / 2
	end
	return 3
end

-- Поставить локальную модель на пол в точке pos, лицом к точке lookAt
local function placeModel(model, pos, lookAt)
	local h = rootHeight(model)
	local at = Vector3.new(pos.X, pos.Y + h, pos.Z)
	model:PivotTo(CFrame.lookAt(at, Vector3.new(lookAt.X, at.Y, lookAt.Z)))
	local root = model:FindFirstChild("HumanoidRootPart")
	if root then
		root.Anchored = true
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BaseScript") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end
	model.Parent = workspace
	table.insert(props, model)
	return model
end
CameraSystem.PlaceModel = placeModel
CameraSystem.ClearProps = clearProps

-- Положение камеры с учётом поворота (поворотные камеры ходят вокруг вертикальной оси)
local function viewCFrame(view, i)
	local cf = view.CFrame
	local amp = PAN[i]
	if amp then
		local yaw = math.rad(amp) * math.sin(os.clock() * 2 * math.pi / 22 + i)
		local pos = cf.Position
		cf = CFrame.new(pos) * CFrame.Angles(0, yaw, 0) * (cf - pos)
	end
	return cf
end

-- Точка на полу перед камерой (без стен между)
local function floorPointInView(view)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { workspace:FindFirstChild("Dynamic"), ctx.Player.Character }
	local look = view.CFrame.LookVector
	local right = view.CFrame.RightVector
	for _ = 1, 8 do
		local d = math.random(12, 30)
		local side = (math.random() - 0.5) * 8
		local p = view.Position + Vector3.new(look.X, 0, look.Z).Unit * d + Vector3.new(right.X, 0, right.Z) * side
		local down = workspace:Raycast(Vector3.new(p.X, view.Position.Y, p.Z), Vector3.new(0, -40, 0), params)
		if down and down.Normal.Y > 0.7 then
			local floor = down.Position
			local toTop = floor + Vector3.new(0, 4.5, 0) - view.Position
			local block = workspace:Raycast(view.Position, toTop * 0.97, params)
			if not block then
				return floor
			end
		end
	end
	return nil
end

local function staticBurst(strength)
	staticFlash.ImageTransparency = 1 - (strength or 0.8)
	TweenService:Create(staticFlash, TweenInfo.new(0.32, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { ImageTransparency = 1 }):Play()
end

local function anomalies(view)
	clearProps()
	lostFrame.Visible = false
	dateAnomaly = false
	if not ctx.State:GetAttribute("CamAnomalies") then
		return
	end
	local r = math.random()
	if r < 0.16 then
		lostFrame.Visible = true
		ctx.Audio.Play("Static", nil, 0.6)
	elseif r < 0.38 then
		local tpl = ReplicatedStorage:FindFirstChild("MonsterTemplate")
		local pos = tpl and floorPointInView(view)
		if pos then
			placeModel(tpl:Clone(), pos, view.Position)
		end
	elseif r < 0.52 then
		-- вы сами стоите в кадре и смотрите в камеру
		local ch = ctx.Player.Character
		local pos = ch and floorPointInView(view)
		if pos then
			ch.Archivable = true
			local ok, clone = pcall(function()
				return ch:Clone()
			end)
			ch.Archivable = false
			if ok and clone then
				local hum = clone:FindFirstChildOfClass("Humanoid")
				if hum then
					hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
				end
				placeModel(clone, pos, view.Position)
			end
		end
	elseif r < 0.62 then
		-- короткий сбой картинки
		glitchUntil = os.clock() + 0.6
		ctx.Audio.Play("TvGlitch", nil, 0.5)
	end
	dateAnomaly = math.random() < 0.35
end

local function highlight()
	for i, pb in pairs(planButtons) do
		local on = i == index
		pb.Button.BackgroundColor3 = on and UI.Colors.Accent or UI.Colors.PanelLight
		pb.Line.BackgroundColor3 = on and UI.Colors.Accent or LINE
		pb.Line.BackgroundTransparency = on and 0.1 or 0.45
		pb.Dot.BackgroundColor3 = on and UI.Colors.Accent or LINE
	end
end

local function setLabels(i, view)
	camNumber.Text = string.format("КАМ %02d", i)
	camTitle.Text = view and (view:GetAttribute("Title") or "") or ""
end

local function show(i)
	if #cams == 0 then
		return
	end
	index = ((i - 1) % #cams) + 1
	local view = cams[index]
	local cam = workspace.CurrentCamera
	cam.CFrame = viewCFrame(view, index)
	cam.FieldOfView = 70
	setLabels(index, view)
	highlight()
	staticBurst(0.85)
	ctx.Audio.Play("CameraSwitch", nil, 0.7)
	viewStart = os.clock()
	ctx.Remotes.Action:FireServer("CameraView", index)
	anomalies(view)
end

-------------------------------------------------------------------------------
-- План магазина с кнопками камер
-------------------------------------------------------------------------------
local function refreshPlan()
	if planBuilt == #cams then
		return
	end
	for _, pb in pairs(planButtons) do
		pb.Button:Destroy()
		pb.Line:Destroy()
		pb.Dot:Destroy()
	end
	planButtons = {}
	for i, view in ipairs(cams) do
		local pos = view.Position
		local tx, tz
		local spot = PLAN_SPOT[i]
		if spot then
			tx, tz = spot[1], spot[2]
		else
			local look = view.CFrame.LookVector
			local t = look.Y < -0.05 and (pos.Y / -look.Y) or 20
			local hit = pos + look * math.min(t, 40)
			tx, tz = (pos.X + hit.X) / 2, (pos.Z + hit.Z) / 2
		end
		local ax, ay = toPlan(pos.X, pos.Z)
		local bx, by = toPlan(tx, tz)
		local dx, dy = bx - ax, by - ay
		local len = math.sqrt(dx * dx + dy * dy)
		local line = UI.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset((ax + bx) / 2, (ay + by) / 2),
			Size = UDim2.fromOffset(math.max(1, len), 2),
			Rotation = math.deg(math.atan2(dy, dx)),
			BackgroundColor3 = LINE,
			BackgroundTransparency = 0.45,
			ZIndex = 8,
		}, planFrame)
		local dot = UI.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(ax, ay),
			Size = UDim2.fromOffset(7, 7),
			BackgroundColor3 = LINE,
			ZIndex = 8,
		}, planFrame)
		UI.corner(dot, 4)
		local size = UI.IsTouch and 34 or 28
		local b = UI.button(tostring(i), {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(bx, by),
			Size = UDim2.fromOffset(size, size),
			TextSize = 15,
			Font = Enum.Font.Code,
			ZIndex = 9,
		}, planFrame, function()
			show(i)
		end)
		local corner = b:FindFirstChildOfClass("UICorner")
		if corner then
			corner.CornerRadius = UDim.new(0.5, 0)
		end
		UI.stroke(b, Color3.new(1, 1, 1), 1, 0.6)
		planButtons[i] = { Button = b, Line = line, Dot = dot }
	end
	planBuilt = #cams
	highlight()
end

-------------------------------------------------------------------------------
-- Клавиши
-------------------------------------------------------------------------------
local NUMBER_KEYS = {
	Enum.KeyCode.One,
	Enum.KeyCode.Two,
	Enum.KeyCode.Three,
	Enum.KeyCode.Four,
	Enum.KeyCode.Five,
	Enum.KeyCode.Six,
	Enum.KeyCode.Seven,
	Enum.KeyCode.Eight,
	Enum.KeyCode.Nine,
}

local function bindKeys()
	if not RunService:IsClient() then
		return -- ContextActionService есть только на клиенте (серверный тест)
	end
	ContextActionService:BindAction("NS_CamPrev", function(_, state)
		if state == Enum.UserInputState.Begin then
			show(index - 1)
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.Left, Enum.KeyCode.A, Enum.KeyCode.Q, Enum.KeyCode.DPadLeft)
	ContextActionService:BindAction("NS_CamNext", function(_, state)
		if state == Enum.UserInputState.Begin then
			show(index + 1)
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.Right, Enum.KeyCode.D, Enum.KeyCode.DPadRight)
	ContextActionService:BindAction("NS_CamExit", function(_, state)
		if state == Enum.UserInputState.Begin then
			CameraSystem.Close()
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.X, Enum.KeyCode.Backspace, Enum.KeyCode.ButtonB)
	ContextActionService:BindAction("NS_CamNumber", function(_, state, input)
		if state == Enum.UserInputState.Begin then
			local n = table.find(NUMBER_KEYS, input.KeyCode)
			if n and n <= #cams then
				show(n)
			end
		end
		return Enum.ContextActionResult.Sink
	end, false, table.unpack(NUMBER_KEYS))
	-- W/S/пробел тоже перехватываем, чтобы персонаж не ходил
	ContextActionService:BindAction("NS_CamBlock", function()
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.W, Enum.KeyCode.S, Enum.KeyCode.Space)
end

local function unbindKeys()
	if not RunService:IsClient() then
		return
	end
	for _, name in ipairs({ "NS_CamPrev", "NS_CamNext", "NS_CamExit", "NS_CamNumber", "NS_CamBlock" }) do
		ContextActionService:UnbindAction(name)
	end
end

-------------------------------------------------------------------------------
-- Режим просмотра
-------------------------------------------------------------------------------
local function applyGrade(ir)
	if irMode == ir then
		return
	end
	irMode = ir
	if ir then
		-- ИК-подсветка: чёрно-белая, контрастная картинка
		cc.Saturation = -1
		cc.Contrast = 0.45
		cc.Brightness = 0.12
		cc.TintColor = Color3.fromRGB(232, 245, 236)
	else
		cc.Saturation = -0.82
		cc.Contrast = 0.22
		cc.Brightness = 0.04
		cc.TintColor = Color3.fromRGB(214, 236, 224)
	end
end

local function enterView(interactive)
	local cam = workspace.CurrentCamera
	local player = ctx.Player
	saved.Mode = player.CameraMode
	saved.MaxZoom = player.CameraMaxZoomDistance
	player.CameraMode = Enum.CameraMode.Classic
	player.CameraMaxZoomDistance = 0.5
	cam.CameraType = Enum.CameraType.Scriptable
	ctx.CameraLocked = true
	ctx.Controls.SetEnabled(false)
	ctx.Controls.SetButtonsVisible(false)
	ctx.HUD.CloseModals()
	ctx.HUD.SetMode("Cameras")
	irMode = nil
	cc.Enabled = true
	gui.Enabled = true
	planHolder.Visible = interactive
	controlsBar.Visible = interactive
	ProximityPromptService.Enabled = false
	ctx.Audio.SetStatic(true)
end

local function exitView()
	local cam = workspace.CurrentCamera
	local player = ctx.Player
	clearProps()
	gui.Enabled = false
	cc.Enabled = false
	lostFrame.Visible = false
	irLight.Enabled = false
	ProximityPromptService.Enabled = true
	ctx.Audio.SetStatic(false)
	cam.CameraType = Enum.CameraType.Custom
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if hum then
		cam.CameraSubject = hum
	end
	player.CameraMode = saved.Mode or Enum.CameraMode.LockFirstPerson
	player.CameraMaxZoomDistance = saved.MaxZoom or 0.5
	ctx.CameraLocked = false
	ctx.Controls.SetEnabled(true)
	ctx.Controls.SetButtonsVisible(true)
	ctx.Controls.ApplySettings()
	ctx.HUD.SetMode("Full")
end

function CameraSystem.IsOpen()
	return isOpen
end

function CameraSystem.Open()
	if isOpen or tapeMode or feedMode then
		return
	end
	collectCams()
	if #cams == 0 then
		return
	end
	isOpen = true
	reported = {}
	enterView(true)
	refreshPlan()
	bindKeys()
	show(index)
end

function CameraSystem.Close()
	if not isOpen then
		return
	end
	isOpen = false
	unbindKeys()
	ctx.Remotes.Action:FireServer("CameraView", 0)
	exitView()
end

-------------------------------------------------------------------------------
-- Для кат-сцены: только картинка камеры, без кнопок и управления
-------------------------------------------------------------------------------
function CameraSystem.ShowFeed(i, clockText)
	collectCams()
	feedMode = true
	fixedClock = clockText
	local view = cams[i]
	setLabels(i, view)
	irMode = nil
	applyGrade(false)
	cc.Enabled = true
	planHolder.Visible = false
	controlsBar.Visible = false
	lostFrame.Visible = false
	gui.Enabled = true
	staticBurst(0.9)
	return view
end

function CameraSystem.HideFeed()
	feedMode = false
	fixedClock = nil
	glitchUntil = 0
	gui.Enabled = false
	cc.Enabled = false
	lostFrame.Visible = false
end

function CameraSystem.Glitch(seconds)
	glitchUntil = os.clock() + (seconds or 0.5)
end

function CameraSystem.SignalLost(on)
	lostFrame.Visible = on
end

function CameraSystem.Burst(strength)
	staticBurst(strength)
end

-- Видеокассета: запись 14.11.2003 с кассы №4, потом текст улики
function CameraSystem.PlayTape(data)
	if tapeMode or feedMode then
		return
	end
	if isOpen then
		CameraSystem.Close()
	end
	tapeMode = true
	enterView(false)
	lostFrame.Visible = false
	local cam = workspace.CurrentCamera
	local camPos = Vector3.new(13, 12.5, 47)
	cam.CFrame = CFrame.lookAt(camPos, Vector3.new(23, 2.5, 34))
	cam.FieldOfView = 70
	camNumber.Text = "КАМ 02 · ЗАПИСЬ"
	camTitle.Text = "КАССА №4 · 14.11.2003"
	dateAnomaly = true
	fixedClock = "03:47"
	local tpl = ReplicatedStorage:FindFirstChild("MonsterTemplate")
	local customer, cashier
	if tpl then
		customer = placeModel(tpl:Clone(), Vector3.new(20.6, 0, 35.6), Vector3.new(26, 0, 35.6))
		cashier = placeModel(tpl:Clone(), Vector3.new(27.6, 0, 35.2), Vector3.new(22, 0, 35.2))
		for _, p in ipairs(cashier:GetDescendants()) do
			if p:IsA("BasePart") then
				if p.Name == "UpperTorso" or string.find(p.Name, "Arm") then
					p.Color = Color3.fromRGB(170, 30, 34)
				elseif p.Name == "Head" or string.find(p.Name, "Hand") then
					p.Color = Color3.fromRGB(226, 186, 156)
				end
			end
		end
	end
	task.spawn(function()
		ctx.Audio.Play("Scan", Vector3.new(24, 3, 36), 0.5)
		task.wait(2)
		ctx.Audio.Play("Scan", Vector3.new(24, 3, 36), 0.5)
		task.wait(2.2)
		-- покупатель оборачивается к камере
		if customer and customer.Parent then
			local root = customer:FindFirstChild("HumanoidRootPart")
			if root then
				customer:PivotTo(CFrame.lookAt(root.Position, Vector3.new(camPos.X, root.Position.Y, camPos.Z)))
			end
		end
		task.wait(1.2)
		glitchUntil = os.clock() + 0.5
		ctx.Audio.Play("TvGlitch", nil, 0.7)
		task.wait(0.5)
		ctx.Audio.Play("Static", nil, 0.9)
		lostFrame.Visible = true
		task.wait(1.6)
		tapeMode = false
		fixedClock = nil
		exitView()
		ctx.HUD.ShowDocument(data)
	end)
end

-------------------------------------------------------------------------------
-- Время в углу: дата, часы смены и секунды
-------------------------------------------------------------------------------
local function stamp()
	local minutes = ctx.State:GetAttribute("Minutes") or 0
	if minutes ~= lastMinutes then
		lastMinutes = minutes
		minuteStamp = os.clock()
	end
	local perMinute = Config.SecondsPerHour / 60
	local secs = math.floor((os.clock() - minuteStamp) / perMinute * 60) % 60
	local date = dateAnomaly and "14.11.2003" or os.date("%d.%m.%Y")
	local clock = fixedClock or Util.clock(minutes)
	if fixedClock and #fixedClock <= 5 then
		secs = math.floor(os.clock() * 1) % 60
	end
	return string.format("%s  %s:%02d", date, clock, secs)
end

local function buildGui()
	gui = UI.new("ScreenGui", {
		Name = "CCTV",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 25,
		Enabled = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, ctx.Player:WaitForChild("PlayerGui"))
	-- зерно, строки развёртки, виньетка, помехи
	grain = UI.new("ImageLabel", {
		Name = "Grain",
		Size = UDim2.new(1, 128, 1, 128),
		BackgroundTransparency = 1,
		Image = Config.Images.CctvNoise,
		ImageTransparency = 0.88,
		ScaleType = Enum.ScaleType.Tile,
		TileSize = UDim2.fromOffset(128, 128),
		ZIndex = 1,
	}, gui)
	UI.new("ImageLabel", {
		Name = "Scanlines",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Image = Config.Images.Scanlines,
		ImageTransparency = 0.5,
		ScaleType = Enum.ScaleType.Tile,
		TileSize = UDim2.fromOffset(6, 96),
		ZIndex = 2,
	}, gui)
	UI.new("ImageLabel", {
		Name = "Vignette",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Image = Config.Images.Vignette,
		ImageTransparency = 0.05,
		ZIndex = 3,
	}, gui)
	staticFlash = UI.new("ImageLabel", {
		Name = "Static",
		Size = UDim2.new(1, 128, 1, 128),
		BackgroundTransparency = 1,
		Image = Config.Images.CctvNoise,
		ImageTransparency = 1,
		ScaleType = Enum.ScaleType.Tile,
		TileSize = UDim2.fromOffset(96, 96),
		ZIndex = 4,
	}, gui)
	for k = 1, 4 do
		tears[k] = UI.new("Frame", {
			Name = "Tear",
			Size = UDim2.new(1, 0, 0, 3),
			BackgroundColor3 = Color3.fromRGB(220, 232, 226),
			BackgroundTransparency = 0.6,
			Visible = false,
			ZIndex = 4,
		}, gui)
	end
	lostFrame = UI.new("Frame", { Name = "NoSignal", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(8, 10, 12), Visible = false, ZIndex = 5 }, gui)
	lostNoise = UI.new("ImageLabel", {
		Size = UDim2.new(1, 128, 1, 128),
		BackgroundTransparency = 1,
		Image = Config.Images.CctvNoise,
		ImageTransparency = 0.5,
		ScaleType = Enum.ScaleType.Tile,
		TileSize = UDim2.fromOffset(128, 128),
		ZIndex = 5,
	}, lostFrame)
	local lostText = UI.text("НЕТ СИГНАЛА", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(520, 64),
		TextSize = 44,
		Font = Enum.Font.Code,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = FEED_TEXT,
		BackgroundTransparency = 0.3,
		BackgroundColor3 = Color3.new(0, 0, 0),
		ZIndex = 6,
	}, lostFrame)
	UI.scaled(lostText)

	-- надписи камеры
	local tl = UI.new("Frame", { Name = "TopLeft", Position = UDim2.fromOffset(30, 24), Size = UDim2.fromOffset(440, 64), BackgroundTransparency = 1, ZIndex = 6 }, gui)
	UI.scaled(tl)
	camNumber = UI.text("КАМ 01", { Size = UDim2.new(1, 0, 0, 34), TextSize = 32, Font = Enum.Font.Code, TextColor3 = FEED_TEXT, TextStrokeTransparency = 0.6, ZIndex = 6 }, tl)
	camTitle = UI.text("", { Position = UDim2.fromOffset(0, 36), Size = UDim2.new(1, 0, 0, 22), TextSize = 20, Font = Enum.Font.Code, TextColor3 = FEED_TEXT, TextStrokeTransparency = 0.6, ZIndex = 6 }, tl)
	local tr = UI.new("Frame", { Name = "TopRight", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -30, 0, 24), Size = UDim2.fromOffset(380, 64), BackgroundTransparency = 1, ZIndex = 6 }, gui)
	UI.scaled(tr)
	recLabel = UI.text("● REC", { Size = UDim2.new(1, 0, 0, 34), TextSize = 30, Font = Enum.Font.Code, TextColor3 = Color3.fromRGB(255, 56, 56), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 6 }, tr)
	timeLabel = UI.text("", { Position = UDim2.fromOffset(0, 36), Size = UDim2.new(1, 0, 0, 22), TextSize = 20, Font = Enum.Font.Code, TextColor3 = FEED_TEXT, TextXAlignment = Enum.TextXAlignment.Right, TextStrokeTransparency = 0.6, ZIndex = 6 }, tr)
	sysLabel = UI.text("MART 24 · DVR-9 · CH 9", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 30, 1, -20), Size = UDim2.fromOffset(300, 18), TextSize = 14, Font = Enum.Font.Code, TextColor3 = FEED_TEXT, TextTransparency = 0.35, ZIndex = 6 }, gui)
	UI.scaled(sysLabel)

	-- план магазина
	planHolder = UI.new("Frame", {
		Name = "Plan",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -18, 1, -18),
		Size = UDim2.fromOffset(PLAN_W + 20, PLAN_H + 44),
		BackgroundColor3 = Color3.fromRGB(8, 10, 12),
		BackgroundTransparency = 0.25,
		ZIndex = 7,
	}, gui)
	UI.corner(planHolder, 10)
	UI.stroke(planHolder, Color3.fromRGB(200, 230, 210), 1, 0.7)
	UI.scaled(planHolder)
	UI.text("ПЛАН МАГАЗИНА", { Position = UDim2.fromOffset(10, 8), Size = UDim2.new(1, -20, 0, 18), TextSize = 14, Font = Enum.Font.Code, TextColor3 = FEED_TEXT, ZIndex = 7 }, planHolder)
	planFrame = UI.new("Frame", { Position = UDim2.fromOffset(10, 32), Size = UDim2.fromOffset(PLAN_W, PLAN_H), BackgroundTransparency = 1, ZIndex = 7 }, planHolder)
	for _, r in ipairs(PLAN) do
		local x0, y0 = toPlan(r[2], r[3])
		local x1, y1 = toPlan(r[4], r[5])
		local room = UI.new("Frame", {
			Position = UDim2.fromOffset(x0, y0),
			Size = UDim2.fromOffset(x1 - x0, y1 - y0),
			BackgroundColor3 = Color3.fromRGB(30, 38, 34),
			BackgroundTransparency = 0.15,
			ZIndex = 7,
		}, planFrame)
		UI.stroke(room, LINE, 1, 0.5)
		if r[1] ~= "" then
			UI.text(r[1], { Position = UDim2.fromOffset(3, 2), Size = UDim2.new(1, -6, 0, 12), TextSize = 10, Font = Enum.Font.Code, TextColor3 = LINE, TextTransparency = 0.25, ZIndex = 7 }, room)
		end
	end
	-- вход
	local ex0 = toPlan(-58, 0)
	local ex1 = toPlan(-46, 0)
	local _, ey = toPlan(0, 50)
	UI.new("Frame", { Position = UDim2.fromOffset(ex0, ey - 1), Size = UDim2.fromOffset(ex1 - ex0, 3), BackgroundColor3 = UI.Colors.Amber, ZIndex = 8 }, planFrame)
	UI.text("ВХОД", { Position = UDim2.fromOffset(ex0 - 4, ey + 3), Size = UDim2.fromOffset(50, 12), TextSize = 10, Font = Enum.Font.Code, TextColor3 = UI.Colors.Amber, ZIndex = 8 }, planFrame)

	-- кнопки ◀ ▶ «Выйти»
	controlsBar = UI.new("Frame", {
		Name = "Controls",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 24, 1, -46),
		Size = UDim2.fromOffset(330, 52),
		BackgroundTransparency = 1,
		ZIndex = 7,
	}, gui)
	UI.scaled(controlsBar)
	UI.list(controlsBar, 8, true)
	-- Modal: пока открыт монитор, курсор мыши свободен
	UI.button("◀", { Size = UDim2.fromOffset(64, 50), TextSize = 22, LayoutOrder = 1, Modal = true, ZIndex = 7 }, controlsBar, function()
		show(index - 1)
	end)
	UI.button("▶", { Size = UDim2.fromOffset(64, 50), TextSize = 22, LayoutOrder = 2, ZIndex = 7 }, controlsBar, function()
		show(index + 1)
	end)
	UI.button("Выйти" .. (UI.IsTouch and "" or " [X]"), { Size = UDim2.fromOffset(140, 50), TextSize = 17, LayoutOrder = 3, BackgroundColor3 = UI.Colors.Accent, ZIndex = 7 }, controlsBar, function()
		CameraSystem.Close()
	end)
end

function CameraSystem.Init(c)
	ctx = c
	UI = ctx.UI
	buildGui()

	cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "NS_CCTV"
	cc.Enabled = false
	cc.Parent = Lighting
	applyGrade(false)

	-- ИК-подсветка камеры (локальный свет у объектива)
	irPart = Instance.new("Part")
	irPart.Name = "CctvIR"
	irPart.Anchored = true
	irPart.CanCollide = false
	irPart.CanQuery = false
	irPart.CanTouch = false
	irPart.Transparency = 1
	irPart.Size = Vector3.new(0.2, 0.2, 0.2)
	irPart.CFrame = CFrame.new(0, -500, 0)
	irPart.Parent = workspace
	irLight = Instance.new("SpotLight")
	irLight.Face = Enum.NormalId.Front
	irLight.Angle = 90
	irLight.Range = 36
	irLight.Brightness = 1.6
	irLight.Color = Color3.fromRGB(235, 245, 240)
	irLight.Enabled = false
	irLight.Parent = irPart

	RENDER:Connect(function()
		if not gui.Enabled then
			return
		end
		grain.Position = UDim2.fromOffset(-math.random(0, 127), -math.random(0, 127))
		staticFlash.Position = UDim2.fromOffset(-math.random(0, 95), -math.random(0, 95))
		if lostFrame.Visible then
			lostNoise.Position = UDim2.fromOffset(-math.random(0, 127), -math.random(0, 127))
		end
		recLabel.TextTransparency = (os.clock() % 1.2 < 0.7) and 0 or 1
		timeLabel.Text = stamp()
		-- помехи: полосы и сильное зерно
		local glitching = os.clock() < glitchUntil
		for _, t in ipairs(tears) do
			if glitching and math.random() < 0.6 then
				t.Visible = true
				t.Position = UDim2.fromScale(0, math.random())
				t.Size = UDim2.new(1, 0, 0, math.random(2, 14))
				t.BackgroundTransparency = 0.35 + math.random() * 0.5
			elseif not glitching and math.random() < 0.004 then
				t.Visible = true
				t.Position = UDim2.fromScale(0, math.random())
				t.Size = UDim2.new(1, 0, 0, 2)
				t.BackgroundTransparency = 0.8
			else
				t.Visible = false
			end
		end
		grain.ImageTransparency = glitching and (0.5 + math.random() * 0.2) or 0.88
		local ir = (not feedMode) and ctx.State:GetAttribute("Power") == false
		applyGrade(ir)
		if isOpen then
			local view = cams[index]
			if view then
				local cf = viewCFrame(view, index)
				workspace.CurrentCamera.CFrame = cf
				irPart.CFrame = cf
				irLight.Enabled = ir
			end
			if os.clock() - viewStart > 1.5 and not reported[index] then
				reported[index] = true
				ctx.Remotes.Action:FireServer("CameraViewed", index)
			end
		else
			irLight.Enabled = false
		end
	end)
end

return CameraSystem
