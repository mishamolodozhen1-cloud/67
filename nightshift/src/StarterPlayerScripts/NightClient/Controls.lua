-- Controls: управление на ПК и телефоне.
--   ПК: WASD, мышь, E — действие (R — второе), F — фонарик, Shift (удерживать) — бег, G — положить,
--       P — телефон, M — меню, T — задания, Enter — начать смену
--   Телефон: стандартный джойстик и обзор свайпом, круглые кнопки «фонарик» и «бег» у кнопки прыжка
--            (бег включается касанием и выключается сам, когда вы остановились или устали)
-- Фонарик: модель в руке, узкий тёплый луч с тенями + мягкий рассеянный свет; луч чуть запаздывает
-- за поворотом головы, как у настоящего фонаря в руке. Батарейка садится, при низком заряде свет мигает.
local ContextActionService = game:GetService("ContextActionService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- кадр отрисовки (в серверном тесте его нет — там Heartbeat)
local RENDER = RunService:IsClient() and RunService.RenderStepped or RunService.Heartbeat

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local Controls = {}

local ctx, UI
local BEGIN = Enum.UserInputState.Begin
local SINK = Enum.ContextActionResult.Sink
local PASS = Enum.ContextActionResult.Pass

local sprintHeld, sprintToggle = false, false
local stamina = Config.StaminaSeconds
local exhausted = false
local stillTime = 0
local flashlightOn = false
local battery = 1
local rig, lens, mainLight, spillLight, bounceLight
local swayRot = CFrame.new()
local bobTime = 0
local controlsEnabled = true
local otherLights = {}
local brightness
local buttons = {}

local function humanoid()
	local ch = ctx.Player.Character
	return ch and ch:FindFirstChildOfClass("Humanoid")
end

-- Включить/выключить движение персонажа (камеры видеонаблюдения, заставки)
function Controls.SetEnabled(on)
	controlsEnabled = on
	pcall(function()
		local playerModule = require(ctx.Player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule"))
		local controls = playerModule:GetControls()
		if on then
			controls:Enable()
		else
			controls:Disable()
		end
	end)
	if not on then
		sprintHeld = false
		sprintToggle = false
	end
end

-------------------------------------------------------------------------------
-- Фонарик в руке
-------------------------------------------------------------------------------
local function localPart(name, size, color, material)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	return p
end

local function buildFlashlight()
	rig = Instance.new("Model")
	rig.Name = "LocalFlashlight"
	local body = localPart("Body", Vector3.new(0.72, 0.17, 0.17), Color3.fromRGB(34, 35, 38), Enum.Material.Metal)
	body.Shape = Enum.PartType.Cylinder
	body.Parent = rig
	local head = localPart("Head", Vector3.new(0.2, 0.25, 0.25), Color3.fromRGB(46, 47, 50), Enum.Material.Metal)
	head.Shape = Enum.PartType.Cylinder
	head.Parent = rig
	lens = localPart("Lens", Vector3.new(0.03, 0.21, 0.21), Color3.fromRGB(120, 120, 120), Enum.Material.Glass)
	lens.Shape = Enum.PartType.Cylinder
	lens.Parent = rig
	local button = localPart("Button", Vector3.new(0.08, 0.05, 0.06), Color3.fromRGB(150, 30, 30), Enum.Material.SmoothPlastic)
	button.Parent = rig
	local emitter = localPart("Emitter", Vector3.new(0.1, 0.1, 0.1), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic)
	emitter.Transparency = 1
	emitter.Parent = rig
	mainLight = Instance.new("SpotLight")
	mainLight.Name = "Beam"
	mainLight.Face = Enum.NormalId.Front
	mainLight.Angle = 42
	mainLight.Range = 60
	mainLight.Brightness = 3.2
	mainLight.Color = Color3.fromRGB(255, 236, 208)
	mainLight.Shadows = true
	mainLight.Enabled = false
	mainLight.Parent = emitter
	spillLight = Instance.new("SpotLight")
	spillLight.Name = "Spill"
	spillLight.Face = Enum.NormalId.Front
	spillLight.Angle = 100
	spillLight.Range = 22
	spillLight.Brightness = 0.45
	spillLight.Color = Color3.fromRGB(255, 232, 200)
	spillLight.Enabled = false
	spillLight.Parent = emitter
	bounceLight = Instance.new("PointLight")
	bounceLight.Name = "Bounce"
	bounceLight.Range = 5
	bounceLight.Brightness = 0.3
	bounceLight.Color = Color3.fromRGB(255, 228, 196)
	bounceLight.Enabled = false
	bounceLight.Parent = emitter
	rig.Parent = workspace
end

local FORWARD = CFrame.Angles(0, math.rad(90), 0) -- ось цилиндра — вперёд

local function placeFlashlight(dt, moving, sprinting)
	local cam = workspace.CurrentCamera
	if not (cam and rig) then
		return
	end
	local hidden = ctx.CameraLocked or not flashlightOn
	local camCF = cam.CFrame
	local rot = camCF - camCF.Position
	-- рука чуть запаздывает за поворотом головы
	swayRot = swayRot:Lerp(rot, math.min(1, dt * 13))
	local bob = CFrame.new()
	if moving and ctx.Settings.HeadBob ~= false then
		local k = sprinting and 1.6 or 1
		bob = CFrame.new(math.sin(bobTime) * 0.025 * k, math.abs(math.cos(bobTime)) * 0.03 * k, 0)
	end
	local base = CFrame.new(camCF.Position) * swayRot * CFrame.new(0.44, -0.42, -0.95) * bob * CFrame.Angles(math.rad(2), math.rad(4), 0)
	local show = not hidden
	for _, p in ipairs(rig:GetChildren()) do
		if p:IsA("BasePart") and p.Name ~= "Emitter" then
			p.Transparency = show and 0 or 1
		end
	end
	rig.Body.CFrame = base * FORWARD
	rig.Head.CFrame = base * CFrame.new(0, 0, -0.42) * FORWARD
	lens.CFrame = base * CFrame.new(0, 0, -0.53) * FORWARD
	rig.Button.CFrame = base * CFrame.new(0, 0.1, -0.05)
	rig.Emitter.CFrame = base * CFrame.new(0, 0, -0.6)
end

local function setLights(on)
	if not mainLight then
		return
	end
	local visible = on and not ctx.CameraLocked
	mainLight.Enabled = visible
	spillLight.Enabled = visible
	bounceLight.Enabled = visible
	lens.Material = on and Enum.Material.Neon or Enum.Material.Glass
	lens.Color = on and Color3.fromRGB(255, 244, 220) or Color3.fromRGB(120, 120, 120)
end

local function refreshButtons()
	local f = buttons.Flashlight
	if f then
		f.BackgroundColor3 = flashlightOn and Color3.fromRGB(255, 196, 80) or Color3.fromRGB(12, 14, 18)
		f.BackgroundTransparency = flashlightOn and 0.15 or 0.35
	end
	local s = buttons.Sprint
	if s then
		local active = sprintHeld or sprintToggle
		s.BackgroundColor3 = active and Color3.fromRGB(226, 52, 52) or Color3.fromRGB(12, 14, 18)
		s.BackgroundTransparency = active and 0.15 or 0.35
	end
end

function Controls.SetFlashlight(on)
	if on and battery <= 0 then
		ctx.HUD.Notify("Батарейки сели. Новые — на столе в комнате персонала", "warn")
		on = false
	end
	flashlightOn = on
	setLights(on)
	ctx.Audio.Play("CameraSwitch", nil, 0.45, 1.3)
	ctx.Remotes.Action:FireServer("Flashlight", on)
	ctx.HUD.SetBattery(battery, flashlightOn)
	refreshButtons()
end

function Controls.ToggleFlashlight()
	Controls.SetFlashlight(not flashlightOn)
end

function Controls.RefillBattery()
	battery = 1
	ctx.HUD.SetBattery(battery, flashlightOn)
end

-- Фонарики других игроков: свет у них в голове (создаётся только у нас)
local function updateOtherLights()
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= ctx.Player then
			local ch = p.Character
			local head = ch and ch:FindFirstChild("Head")
			if head then
				local light = otherLights[p]
				if not (light and light.Parent == head) then
					light = Instance.new("SpotLight")
					light.Name = "NS_Flashlight"
					light.Face = Enum.NormalId.Front
					light.Range = 50
					light.Angle = 44
					light.Brightness = 2.6
					light.Color = Color3.fromRGB(255, 236, 208)
					light.Shadows = true
					light.Parent = head
					otherLights[p] = light
				end
				light.Enabled = ch:GetAttribute("Flashlight") == true
			end
		end
	end
	for p, light in pairs(otherLights) do
		if not p.Parent then
			light:Destroy()
			otherLights[p] = nil
		end
	end
end

-------------------------------------------------------------------------------
-- Кнопки «фонарик» и «бег»
-------------------------------------------------------------------------------
local function makeButton(gui, name, image, keyText)
	local b = Instance.new("ImageButton")
	b.Name = name
	b.AnchorPoint = Vector2.new(0.5, 0.5)
	b.BackgroundColor3 = Color3.fromRGB(12, 14, 18)
	b.BackgroundTransparency = 0.35
	b.AutoButtonColor = false
	b.Image = ""
	b.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = b
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(1, 1, 1)
	stroke.Thickness = 2
	stroke.Transparency = 0.6
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = b
	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.47)
	icon.Size = UDim2.fromScale(0.64, 0.64)
	icon.BackgroundTransparency = 1
	icon.Image = image
	icon.Parent = b
	if keyText then
		local key = Instance.new("TextLabel")
		key.Name = "Key"
		key.AnchorPoint = Vector2.new(0.5, 0)
		key.Position = UDim2.new(0.5, 0, 1, 4)
		key.Size = UDim2.fromOffset(70, 16)
		key.BackgroundTransparency = 1
		key.Font = Enum.Font.GothamBold
		key.TextSize = 13
		key.TextColor3 = Color3.fromRGB(220, 220, 220)
		key.TextStrokeTransparency = 0.5
		key.Text = keyText
		key.Parent = b
	end
	return b
end

local function layoutButtons()
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	local v = cam.ViewportSize
	if UI.IsTouch then
		-- те же размеры и место, что у стандартной кнопки прыжка Roblox
		local small = math.min(v.X, v.Y) <= 500
		local jump = small and 70 or 120
		local jx = v.X - (jump * 1.5 - 10) + jump / 2
		local jy = v.Y - (small and (jump + 20) or (jump * 1.75)) + jump / 2
		local size = small and 62 or 92
		local gap = small and 12 or 18
		buttons.Sprint.Size = UDim2.fromOffset(size, size)
		buttons.Sprint.Position = UDim2.fromOffset(jx, jy - jump / 2 - gap - size / 2)
		buttons.Flashlight.Size = UDim2.fromOffset(size, size)
		buttons.Flashlight.Position = UDim2.fromOffset(jx - jump / 2 - gap - size / 2, jy)
	else
		local size = 58
		buttons.Sprint.Size = UDim2.fromOffset(size, size)
		buttons.Sprint.Position = UDim2.new(1, -46, 1, -60)
		buttons.Flashlight.Size = UDim2.fromOffset(size, size)
		buttons.Flashlight.Position = UDim2.new(1, -118, 1, -60)
	end
end

local function buildButtons()
	local gui = Instance.new("ScreenGui")
	gui.Name = "NightButtons"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 6
	gui.Parent = ctx.Player:WaitForChild("PlayerGui")
	Controls.Gui = gui
	buttons.Flashlight = makeButton(gui, "Flashlight", Config.Images.IconFlashlight, (not UI.IsTouch) and "F" or nil)
	buttons.Sprint = makeButton(gui, "Sprint", Config.Images.IconRun, (not UI.IsTouch) and "Shift" or nil)
	buttons.Flashlight.Activated:Connect(function()
		Controls.ToggleFlashlight()
	end)
	buttons.Sprint.Activated:Connect(function()
		sprintToggle = not sprintToggle
		refreshButtons()
	end)
	layoutButtons()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(layoutButtons)
	refreshButtons()
end

function Controls.SetButtonsVisible(on)
	if Controls.Gui then
		Controls.Gui.Enabled = on
	end
end

-------------------------------------------------------------------------------
-- Настройки
-------------------------------------------------------------------------------
function Controls.ApplySettings()
	local cam = workspace.CurrentCamera
	if cam and not ctx.CameraLocked then
		cam.FieldOfView = ctx.Settings.Fov or 80
	end
	if not brightness then
		brightness = Instance.new("ColorCorrectionEffect")
		brightness.Name = "NS_Brightness"
		brightness.Parent = Lighting
	end
	brightness.Brightness = ctx.Settings.Brightness or 0
end

-------------------------------------------------------------------------------
local function bind(name, fn, ...)
	ContextActionService:BindAction(name, function(_, state)
		if state == BEGIN then
			fn()
			return SINK
		end
		return PASS
	end, false, ...)
end

function Controls.BindKeys()
	bind("NS_Flashlight", Controls.ToggleFlashlight, Enum.KeyCode.F, Enum.KeyCode.ButtonL1)
	ContextActionService:BindAction("NS_Sprint", function(_, state)
		sprintHeld = state == BEGIN
		refreshButtons()
		return SINK
	end, false, Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonL3)
	bind("NS_Drop", function()
		ctx.Remotes.Action:FireServer("Drop")
	end, Enum.KeyCode.G, Enum.KeyCode.ButtonB)
	bind("NS_Phone", function()
		if not ctx.CameraLocked then
			ctx.HUD.OpenModal("Phone")
		end
	end, Enum.KeyCode.P)
	bind("NS_Menu", function()
		if not ctx.CameraLocked then
			ctx.HUD.OpenModal("Settings")
		end
	end, Enum.KeyCode.M)
	bind("NS_Tasks", function()
		ctx.HUD.ToggleTasks()
	end, Enum.KeyCode.T)
	bind("NS_Start", function()
		ctx.HUD.RequestStart()
	end, Enum.KeyCode.Return)
end

function Controls.Init(c)
	ctx = c
	UI = ctx.UI
	buildFlashlight()
	buildButtons()
	ctx.HUD.SetBattery(battery, false)

	-- клавиши (ContextActionService есть только на клиенте; в серверном тесте пропускаем)
	if RunService:IsClient() then
		Controls.BindKeys()
	end

	-- Новый персонаж: сбросить бег, сообщить серверу о фонарике
	ctx.Player.CharacterAdded:Connect(function()
		stamina = Config.StaminaSeconds
		exhausted = false
		sprintToggle = false
		if flashlightOn then
			task.delay(0.5, function()
				ctx.Remotes.Action:FireServer("Flashlight", flashlightOn)
			end)
		end
	end)

	local otherTimer = 0
	RENDER:Connect(function(dt)
		local hum = humanoid()
		local moving = hum ~= nil and hum.MoveDirection.Magnitude > 0.1
		local sprinting = false
		if hum then
			if moving then
				stillTime = 0
			else
				stillTime = stillTime + dt
				if stillTime > 1 and sprintToggle then
					sprintToggle = false
					refreshButtons()
				end
			end
			sprinting = controlsEnabled and (sprintHeld or sprintToggle) and moving and not exhausted and stamina > 0
			if sprinting then
				stamina = math.max(0, stamina - dt)
				if stamina <= 0 then
					exhausted = true
					sprintToggle = false
					refreshButtons()
				end
			else
				stamina = math.min(Config.StaminaSeconds, stamina + dt * 0.7)
				if exhausted and stamina > Config.StaminaSeconds * 0.35 then
					exhausted = false
				end
			end
			hum.WalkSpeed = sprinting and Config.SprintSpeed or Config.WalkSpeed
			ctx.HUD.SetStamina(stamina / Config.StaminaSeconds)
			-- покачивание камеры при ходьбе
			local target = Vector3.new(0, 0, 0)
			if ctx.Settings.HeadBob ~= false and moving and hum.FloorMaterial ~= Enum.Material.Air then
				bobTime = bobTime + dt * (sprinting and 13 or 8.5)
				local amp = sprinting and 1.5 or 1
				target = Vector3.new(math.sin(bobTime) * 0.07 * amp, math.abs(math.cos(bobTime)) * 0.11 * amp, 0)
			end
			hum.CameraOffset = hum.CameraOffset:Lerp(target, math.min(1, dt * 10))
		end

		-- фонарик: положение в руке, заряд, мигание при слабой батарейке
		placeFlashlight(dt, moving, sprinting)
		if flashlightOn then
			battery = math.max(0, battery - dt / Config.FlashlightBatterySeconds)
			local flick = 1
			if battery < 0.05 then
				flick = (math.random() < 0.18) and 0.05 or 0.7
			elseif battery < 0.15 then
				flick = (math.random() < 0.06) and 0.3 or 0.9
			end
			mainLight.Brightness = 3.2 * flick
			spillLight.Brightness = 0.45 * flick
			setLights(true)
			if battery <= 0 then
				Controls.SetFlashlight(false)
			end
		elseif mainLight.Enabled then
			setLights(false)
		end

		otherTimer = otherTimer + dt
		if otherTimer > 0.3 then
			otherTimer = 0
			updateOtherLights()
			ctx.HUD.SetBattery(battery, flashlightOn)
		end
	end)
end

return Controls
