-- CameraSystem: монитор видеонаблюдения в комнате охраны.
--   • 7 камер (детали с тегом CCTV в Workspace.Store.Cameras, атрибуты Index и Title)
--   • переключение кнопками ◀ ▶ и 1–7 (на ПК ещё стрелки/A/D и цифры), выход — кнопка или X
--   • чёрно-белая картинка с помехами, датой и значком REC
--   • после 02:00 на записях бывают странности: «НЕТ СИГНАЛА», дата 14.11.2003,
--     человек, которого на самом деле там нет, или вы сами
--   • видеокассета 14.11.03 (улика) проигрывается здесь же
local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Util = require(Shared:WaitForChild("Util"))

local CameraSystem = {}

local ctx, UI
local isOpen = false
local index = 1
local cams = {}
local gui, camLabel, timeLabel, recLabel, noise, lostLabel, buttonsBar
local cc, blur
local viewStart = 0
local reported = {}
local saved = {}
local props = {} -- локальные фигуры в кадре
local dateAnomaly = false
local tapeMode = false

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

-- Точка на полу перед камерой (без стен между)
local function floorPointInView(view)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { workspace:FindFirstChild("Dynamic"), ctx.Player.Character }
	local look = view.CFrame.LookVector
	for _ = 1, 8 do
		local d = math.random(12, 30)
		local side = (math.random() - 0.5) * 8
		local right = view.CFrame.RightVector
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

local function anomalies(view)
	clearProps()
	lostLabel.Visible = false
	dateAnomaly = false
	if not ctx.State:GetAttribute("CamAnomalies") then
		return
	end
	local r = math.random()
	if r < 0.16 then
		lostLabel.Visible = true
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
	end
	dateAnomaly = math.random() < 0.35
end

local function show(i)
	if #cams == 0 then
		return
	end
	index = ((i - 1) % #cams) + 1
	local view = cams[index]
	local cam = workspace.CurrentCamera
	cam.CFrame = view.CFrame
	cam.FieldOfView = 72
	camLabel.Text = string.format("КАМ %d · %s", index, view:GetAttribute("Title") or "")
	ctx.Audio.Play("CameraSwitch", nil, 0.7)
	viewStart = os.clock()
	ctx.Remotes.Action:FireServer("CameraView", index)
	anomalies(view)
end

local function bindKeys()
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
	local keys = { Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four, Enum.KeyCode.Five, Enum.KeyCode.Six, Enum.KeyCode.Seven }
	ContextActionService:BindAction("NS_CamNumber", function(_, state, input)
		if state == Enum.UserInputState.Begin then
			local n = table.find(keys, input.KeyCode)
			if n then
				show(n)
			end
		end
		return Enum.ContextActionResult.Sink
	end, false, table.unpack(keys))
	-- W/S тоже перехватываем, чтобы персонаж не ходил
	ContextActionService:BindAction("NS_CamBlock", function()
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.W, Enum.KeyCode.S, Enum.KeyCode.Space)
end

local function unbindKeys()
	for _, name in ipairs({ "NS_CamPrev", "NS_CamNext", "NS_CamExit", "NS_CamNumber", "NS_CamBlock" }) do
		ContextActionService:UnbindAction(name)
	end
end

local function enterView()
	local cam = workspace.CurrentCamera
	local player = ctx.Player
	saved.Mode = player.CameraMode
	saved.MaxZoom = player.CameraMaxZoomDistance
	player.CameraMode = Enum.CameraMode.Classic
	player.CameraMaxZoomDistance = 0.5
	cam.CameraType = Enum.CameraType.Scriptable
	ctx.CameraLocked = true
	ctx.Controls.SetEnabled(false)
	ctx.HUD.CloseModals()
	cc.Enabled = true
	blur.Enabled = true
	gui.Enabled = true
	ProximityPromptService.Enabled = false
	ctx.Audio.SetStatic(true)
end

local function exitView()
	local cam = workspace.CurrentCamera
	local player = ctx.Player
	clearProps()
	gui.Enabled = false
	cc.Enabled = false
	blur.Enabled = false
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
	ctx.Controls.ApplySettings()
end

function CameraSystem.IsOpen()
	return isOpen
end

function CameraSystem.Open()
	if isOpen or tapeMode then
		return
	end
	collectCams()
	if #cams == 0 then
		return
	end
	isOpen = true
	reported = {}
	enterView()
	buttonsBar.Visible = true
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

-- Видеокассета: запись 14.11.2003 с кассы №4, потом текст улики
function CameraSystem.PlayTape(data)
	if tapeMode then
		return
	end
	if isOpen then
		CameraSystem.Close()
	end
	tapeMode = true
	enterView()
	buttonsBar.Visible = false
	lostLabel.Visible = false
	local cam = workspace.CurrentCamera
	local camPos = Vector3.new(13, 12.5, 47)
	cam.CFrame = CFrame.lookAt(camPos, Vector3.new(23, 2.5, 34))
	cam.FieldOfView = 70
	camLabel.Text = "КАМ 1 · ЗАПИСЬ 14.11.2003"
	dateAnomaly = true
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
		task.wait(1.6)
		ctx.Audio.Play("Static", nil, 0.9)
		lostLabel.Visible = true
		task.wait(1.6)
		tapeMode = false
		exitView()
		ctx.HUD.ShowDocument(data)
	end)
end

function CameraSystem.Init(c)
	ctx = c
	UI = ctx.UI
	gui = UI.new("ScreenGui", { Name = "CCTV", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 25, Enabled = false }, ctx.Player:WaitForChild("PlayerGui"))
	noise = UI.new("ImageLabel", {
		Size = UDim2.new(1, 64, 1, 64),
		BackgroundTransparency = 1,
		Image = Config.Images.CctvNoise,
		ImageTransparency = 0.84,
		ScaleType = Enum.ScaleType.Tile,
		TileSize = UDim2.fromOffset(128, 128),
	}, gui)
	-- рамка и затемнение по краям
	UI.new("UIStroke", { Thickness = 18, Color = Color3.new(0, 0, 0), Transparency = 0.35 }, UI.new("Frame", {
		Size = UDim2.new(1, -36, 1, -36),
		Position = UDim2.fromOffset(18, 18),
		BackgroundTransparency = 1,
	}, gui))
	local top = UI.new("Frame", { Position = UDim2.fromOffset(40, 36), Size = UDim2.new(1, -80, 0, 40), BackgroundTransparency = 1 }, gui)
	UI.scaled(top)
	camLabel = UI.text("КАМ 1", { Size = UDim2.new(0.7, 0, 1, 0), TextSize = 26, Font = Enum.Font.Code, TextColor3 = Color3.fromRGB(220, 255, 220), TextStrokeTransparency = 0.5 }, top)
	recLabel = UI.text("● REC", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.new(0.3, 0, 1, 0), TextSize = 26, Font = Enum.Font.Code, TextColor3 = Color3.fromRGB(255, 60, 60), TextXAlignment = Enum.TextXAlignment.Right }, top)
	timeLabel = UI.text("", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 40, 1, -96), Size = UDim2.fromOffset(420, 30), TextSize = 22, Font = Enum.Font.Code, TextColor3 = Color3.fromRGB(220, 255, 220), TextStrokeTransparency = 0.5 }, gui)
	UI.scaled(timeLabel)
	lostLabel = UI.text("НЕТ СИГНАЛА", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromOffset(600, 80),
		TextSize = 54,
		Font = Enum.Font.Code,
		TextXAlignment = Enum.TextXAlignment.Center,
		BackgroundTransparency = 0.2,
		BackgroundColor3 = Color3.new(0, 0, 0),
		Visible = false,
	}, gui)
	UI.scaled(lostLabel)
	-- кнопки внизу
	buttonsBar = UI.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -22),
		Size = UDim2.fromOffset(720, 52),
		BackgroundTransparency = 1,
	}, gui)
	UI.scaled(buttonsBar)
	UI.list(buttonsBar, 6, true).HorizontalAlignment = Enum.HorizontalAlignment.Center
	-- Modal: пока открыт монитор, курсор мыши свободен
	UI.button("◀", { Size = UDim2.fromOffset(56, 50), TextSize = 22, LayoutOrder = 0, Modal = true }, buttonsBar, function()
		show(index - 1)
	end)
	for n = 1, Config.CameraCount do
		UI.button(tostring(n), { Size = UDim2.fromOffset(52, 50), TextSize = 20, LayoutOrder = n }, buttonsBar, function()
			show(n)
		end)
	end
	UI.button("▶", { Size = UDim2.fromOffset(56, 50), TextSize = 22, LayoutOrder = 20 }, buttonsBar, function()
		show(index + 1)
	end)
	UI.button("Выйти" .. (UI.IsTouch and "" or " [X]"), { Size = UDim2.fromOffset(120, 50), TextSize = 17, LayoutOrder = 21, BackgroundColor3 = UI.Colors.Accent }, buttonsBar, function()
		CameraSystem.Close()
	end)

	cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "NS_CCTV"
	cc.Saturation = -1
	cc.Contrast = 0.35
	cc.Brightness = 0.04
	cc.TintColor = Color3.fromRGB(205, 255, 215)
	cc.Enabled = false
	cc.Parent = Lighting
	blur = Instance.new("BlurEffect")
	blur.Name = "NS_CCTVBlur"
	blur.Size = 2
	blur.Enabled = false
	blur.Parent = Lighting

	RunService.RenderStepped:Connect(function()
		if not (isOpen or tapeMode) then
			return
		end
		noise.Position = UDim2.fromOffset(-math.random(0, 64), -math.random(0, 64))
		recLabel.TextTransparency = (os.clock() % 1 < 0.5) and 0 or 1
		local minutes = ctx.State:GetAttribute("Minutes") or 0
		local date = dateAnomaly and "14.11.2003" or os.date("%d.%m.%Y")
		local secs = math.floor(os.clock() * 7) % 60
		timeLabel.Text = string.format("%s  %s:%02d", date, tapeMode and "03:47" or Util.clock(minutes), secs)
		if isOpen then
			local view = cams[index]
			if view then
				workspace.CurrentCamera.CFrame = view.CFrame
			end
			if os.clock() - viewStart > 1.5 and not reported[index] then
				reported[index] = true
				ctx.Remotes.Action:FireServer("CameraViewed", index)
			end
		end
	end)
end

return CameraSystem
