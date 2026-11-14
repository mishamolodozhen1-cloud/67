-- Управление: крупные круглые кнопки под большой палец на телефоне,
-- клавиши на ПК (Q — стенд, E — барраж (держать), R — остановка времени) и геймпад.
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local Controls = {}

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local remote

local gui
local buttons = {}
local hint
local awakenTitle
local awakenSub
local tips

local GOLD = Config.Colors.Gold
local ACCENT = Config.Colors.Accent

local function isTouchOnly()
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

local function corner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = radius
	c.Parent = parent
	return c
end

local function label(parent, props)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.TextScaled = true
	l.Font = Enum.Font.GothamBlack
	l.TextColor3 = Color3.fromRGB(255, 240, 210)
	for k, v in pairs(props) do
		l[k] = v
	end
	l.Parent = parent
	return l
end

local function makeButton(name, icon, text, key)
	local b = Instance.new("TextButton")
	b.Name = name
	b.Text = ""
	b.AutoButtonColor = false
	b.AnchorPoint = Vector2.new(0.5, 0.5)
	b.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	b.BackgroundTransparency = 0.08
	b.Parent = gui
	corner(b, UDim.new(1, 0))

	local grad = Instance.new("UIGradient")
	grad.Rotation = 90
	grad.Color = ColorSequence.new(Color3.fromRGB(74, 60, 96), Color3.fromRGB(16, 12, 22))
	grad.Parent = b

	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = GOLD
	stroke.Thickness = 2.5
	stroke.Parent = b

	local scale = Instance.new("UIScale")
	scale.Parent = b

	local iconLabel = label(b, {
		Size = UDim2.fromScale(0.62, 0.42),
		Position = UDim2.fromScale(0.19, 0.14),
		Text = icon,
		Font = Enum.Font.GothamBold,
	})
	local textLabel = label(b, {
		Size = UDim2.fromScale(0.84, 0.2),
		Position = UDim2.fromScale(0.08, 0.6),
		Text = text,
		TextColor3 = Color3.fromRGB(255, 226, 150),
	})

	local cd = Instance.new("Frame")
	cd.Name = "Cooldown"
	cd.AnchorPoint = Vector2.new(0, 1)
	cd.Position = UDim2.fromScale(0, 1)
	cd.Size = UDim2.fromScale(1, 0)
	cd.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	cd.BackgroundTransparency = 0.35
	cd.BorderSizePixel = 0
	cd.ZIndex = 3
	cd.Visible = false
	cd.Parent = b
	corner(cd, UDim.new(1, 0))
	local cdText = label(b, {
		Size = UDim2.fromScale(0.5, 0.36),
		Position = UDim2.fromScale(0.25, 0.32),
		Text = "",
		ZIndex = 4,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextStrokeTransparency = 0.2,
	})

	local keyBadge = label(b, {
		Size = UDim2.fromOffset(24, 24),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 4, 0, -4),
		Text = key,
		BackgroundTransparency = 0,
		BackgroundColor3 = GOLD,
		TextColor3 = Color3.fromRGB(30, 22, 10),
		ZIndex = 5,
	})
	corner(keyBadge, UDim.new(0, 6))

	return {
		button = b,
		stroke = stroke,
		scale = scale,
		icon = iconLabel,
		text = textLabel,
		cd = cd,
		cdText = cdText,
		key = keyBadge,
	}
end

local function layout()
	local vp = camera.ViewportSize
	if isTouchOnly() then
		-- Кнопки дугой вокруг стандартной кнопки прыжка в правом нижнем углу.
		local small = math.min(vp.X, vp.Y) <= 500
		local spec
		if small then
			spec = { barrage = { 84, 145, 62 }, timestop = { 70, 125, 150 }, summon = { 60, 52, 135 } }
		else
			spec = { barrage = { 110, 245, 115 }, timestop = { 92, 225, 235 }, summon = { 78, 110, 262 } }
		end
		for name, sp in pairs(spec) do
			local b = buttons[name].button
			b.Size = UDim2.fromOffset(sp[1], sp[1])
			b.Position = UDim2.new(1, -sp[2], 1, -sp[3])
			buttons[name].key.Visible = false
		end
	else
		local row = { summon = { 80, -112, 72 }, barrage = { 96, 0, 80 }, timestop = { 80, 112, 72 } }
		for name, sp in pairs(row) do
			local b = buttons[name].button
			b.Size = UDim2.fromOffset(sp[1], sp[1])
			b.Position = UDim2.new(0.5, sp[2], 1, -sp[3])
			buttons[name].key.Visible = true
		end
	end
end

local function pressFx(entry)
	entry.scale.Scale = 0.88
	TweenService:Create(entry.scale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

-------------------------------------------------------------------------------
-- Действия
-------------------------------------------------------------------------------
local barrageHeld = false
local holdInput = nil

local function send(action)
	remote:FireServer(action)
end

local function barrageStart()
	if barrageHeld then
		return
	end
	barrageHeld = true
	buttons.barrage.stroke.Color = ACCENT
	send("BarrageStart")
end

local function barrageStop()
	if not barrageHeld then
		return
	end
	barrageHeld = false
	holdInput = nil
	buttons.barrage.stroke.Color = GOLD
	send("BarrageStop")
end

local function isPointer(input)
	return input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1
end

local function bindTap(entry, fn)
	entry.button.InputBegan:Connect(function(input)
		if isPointer(input) then
			pressFx(entry)
			fn()
		end
	end)
end

local function bindHold(entry)
	entry.button.InputBegan:Connect(function(input)
		if isPointer(input) then
			pressFx(entry)
			holdInput = input
			barrageStart()
			local conn
			conn = input:GetPropertyChangedSignal("UserInputState"):Connect(function()
				local st = input.UserInputState
				if st == Enum.UserInputState.End or st == Enum.UserInputState.Cancel then
					conn:Disconnect()
					if holdInput == input then
						barrageStop()
					end
				end
			end)
		end
	end)
end

-------------------------------------------------------------------------------
-- Подсказки и баннеры
-------------------------------------------------------------------------------
local function setVisibleForStand()
	local has = player:GetAttribute("HasStand") == true
	for _, entry in pairs(buttons) do
		entry.button.Visible = has
	end
	hint.Visible = not has
	-- Подсказку у стрелы скрываем локально, когда стенд уже есть.
	local altar = workspace:FindFirstChild("ArrowAltar")
	local top = altar and altar:FindFirstChild("TopSlab")
	local prompt = top and top:FindFirstChild("TakeArrow")
	if prompt then
		prompt.Enabled = not has
	end
end

function Controls.OnAwaken()
	awakenTitle.Visible = true
	awakenSub.Visible = true
	awakenTitle.TextTransparency = 1
	awakenSub.TextTransparency = 1
	awakenTitle.Text = "СТЕНД ПРОБУЖДЁН"
	awakenSub.Text = Config.StandName .. "  ·  " .. Config.StandTitle
	local info = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(awakenTitle, info, { TextTransparency = 0, TextStrokeTransparency = 0.2 }):Play()
	TweenService:Create(awakenSub, info, { TextTransparency = 0, TextStrokeTransparency = 0.3 }):Play()
	task.delay(3.2, function()
		local out = TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(awakenTitle, out, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		TweenService:Create(awakenSub, out, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	end)
	if isTouchOnly() then
		tips.Text = "Держи «Барраж» — шквал ударов. «Стоп» — остановка времени на 5 секунд."
	else
		tips.Text = "Q — стенд   ·   E (держать) — барраж   ·   R — остановка времени"
	end
	tips.Visible = true
	tips.TextTransparency = 0
	task.delay(9, function()
		TweenService:Create(tips, TweenInfo.new(1), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	end)
end

local function updateCooldown(entry, readyAt, total)
	local left = (readyAt or 0) - workspace:GetServerTimeNow()
	if left > 0 then
		entry.cd.Visible = true
		entry.cd.Size = UDim2.fromScale(1, math.clamp(left / total, 0, 1))
		entry.cdText.Text = tostring(math.ceil(left))
	else
		entry.cd.Visible = false
		entry.cdText.Text = ""
	end
end

function Controls.Start(actionRemote)
	remote = actionRemote

	gui = Instance.new("ScreenGui")
	gui.Name = "StandHUD"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 10
	gui.Parent = player:WaitForChild("PlayerGui")

	buttons.summon = makeButton("Summon", "👤", "СТЕНД", "Q")
	buttons.barrage = makeButton("Barrage", "👊", "БАРРАЖ", "E")
	buttons.timestop = makeButton("TimeStop", "⏱", "СТОП", "R")

	bindTap(buttons.summon, function()
		send("Summon")
	end)
	bindHold(buttons.barrage)
	bindTap(buttons.timestop, function()
		send("TimeStop")
	end)

	hint = label(gui, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 14),
		Size = UDim2.new(0.86, 0, 0, 30),
		Text = "Подойди к алтарю и возьми Стрелу Судьбы",
		TextColor3 = Color3.fromRGB(255, 230, 170),
		TextStrokeTransparency = 0.35,
	})
	local hc = Instance.new("UITextSizeConstraint")
	hc.MaxTextSize = 26
	hc.Parent = hint

	awakenTitle = label(gui, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.36),
		Size = UDim2.new(0.8, 0, 0, 56),
		TextColor3 = Color3.fromRGB(255, 214, 110),
		TextStrokeColor3 = Color3.fromRGB(60, 30, 0),
		TextTransparency = 1,
		TextStrokeTransparency = 1,
		Visible = false,
	})
	awakenSub = label(gui, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.36, 46),
		Size = UDim2.new(0.7, 0, 0, 30),
		Font = Enum.Font.GothamBold,
		TextColor3 = Color3.fromRGB(190, 240, 255),
		TextStrokeColor3 = Color3.fromRGB(0, 30, 50),
		TextTransparency = 1,
		TextStrokeTransparency = 1,
		Visible = false,
	})
	tips = label(gui, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 14),
		Size = UDim2.new(0.9, 0, 0, 24),
		Font = Enum.Font.GothamBold,
		TextColor3 = Color3.fromRGB(240, 236, 255),
		TextStrokeTransparency = 0.3,
		Visible = false,
	})
	local tc = Instance.new("UITextSizeConstraint")
	tc.MaxTextSize = 22
	tc.Parent = tips

	layout()
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(layout)
	UserInputService.LastInputTypeChanged:Connect(layout)

	setVisibleForStand()
	player:GetAttributeChangedSignal("HasStand"):Connect(setVisibleForStand)
	task.spawn(function()
		workspace:WaitForChild("ArrowAltar", 15)
		setVisibleForStand()
	end)

	-- Клавиатура и геймпад
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or player:GetAttribute("HasStand") ~= true then
			return
		end
		local k = input.KeyCode
		if k == Enum.KeyCode.Q or k == Enum.KeyCode.ButtonX then
			pressFx(buttons.summon)
			send("Summon")
		elseif k == Enum.KeyCode.E or k == Enum.KeyCode.ButtonR2 then
			pressFx(buttons.barrage)
			barrageStart()
		elseif k == Enum.KeyCode.R or k == Enum.KeyCode.ButtonY then
			pressFx(buttons.timestop)
			send("TimeStop")
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		local k = input.KeyCode
		if k == Enum.KeyCode.E or k == Enum.KeyCode.ButtonR2 then
			barrageStop()
		elseif holdInput and (input == holdInput or (input.UserInputType == Enum.UserInputType.MouseButton1 and holdInput.UserInputType == Enum.UserInputType.MouseButton1)) then
			barrageStop()
		end
	end)

	-- Перезарядки и подписи
	RunService.RenderStepped:Connect(function()
		updateCooldown(buttons.barrage, player:GetAttribute("BarrageReadyAt"), Config.Barrage.Cooldown)
		updateCooldown(buttons.timestop, player:GetAttribute("TimeStopReadyAt"), Config.TimeStop.Cooldown)
		local summoned = player:GetAttribute("StandSummoned") == true
		buttons.summon.text.Text = summoned and "УБРАТЬ" or "СТЕНД"
		buttons.summon.stroke.Color = summoned and ACCENT or GOLD
		local stopped = workspace:GetAttribute("TimeStopped") == true
		buttons.timestop.stroke.Color = stopped and Color3.fromRGB(170, 140, 255) or GOLD
		if barrageHeld and player:GetAttribute("Barraging") == false and not summoned then
			barrageStop()
		end
	end)

	player.CharacterAdded:Connect(function()
		barrageStop()
	end)
end

return Controls
