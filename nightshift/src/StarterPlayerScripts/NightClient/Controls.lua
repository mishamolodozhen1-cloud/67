-- Controls: управление на ПК и телефоне.
--   ПК: WASD, мышь, E — действие, F — фонарик, Shift — бег, G — положить, P — телефон, M — меню, T — задания, Enter — начать смену
--   Телефон: стандартный джойстик и обзор свайпом + кнопки 🔦 (фонарик) и 🏃 (бег, удерживать)
-- Кнопки делает ContextActionService: одна привязка работает и с клавиатуры, и с сенсорной кнопки, и с геймпада.
local ContextActionService = game:GetService("ContextActionService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local Controls = {}

local ctx
local BEGIN = Enum.UserInputState.Begin
local SINK = Enum.ContextActionResult.Sink
local PASS = Enum.ContextActionResult.Pass

local sprintHeld = false
local stamina = Config.StaminaSeconds
local exhausted = false
local flashlightOn = false
local battery = 1
local flashPart, flashLight
local bobTime = 0
local controlsEnabled = true
local otherLights = {}
local brightness

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
	end
end

-------------------------------------------------------------------------------
-- Фонарик (свет виден и другим игрокам: сервер ставит атрибут Flashlight на персонажа)
-------------------------------------------------------------------------------
local function ensureFlash()
	if flashPart and flashPart.Parent then
		return
	end
	flashPart = Instance.new("Part")
	flashPart.Name = "LocalFlashlight"
	flashPart.Size = Vector3.new(0.2, 0.2, 0.2)
	flashPart.Transparency = 1
	flashPart.Anchored = true
	flashPart.CanCollide = false
	flashPart.CanQuery = false
	flashPart.CanTouch = false
	flashPart.CastShadow = false
	flashLight = Instance.new("SpotLight")
	flashLight.Face = Enum.NormalId.Front
	flashLight.Range = 50
	flashLight.Angle = 52
	flashLight.Brightness = 2.6
	flashLight.Color = Color3.fromRGB(255, 244, 226)
	flashLight.Shadows = true
	flashLight.Enabled = false
	flashLight.Parent = flashPart
	flashPart.Parent = workspace
end

function Controls.SetFlashlight(on)
	if on and battery <= 0 then
		ctx.HUD.Notify("Батарейки сели. Новые — на столе в комнате персонала", "warn")
		on = false
	end
	flashlightOn = on
	ensureFlash()
	flashLight.Enabled = on
	ctx.Audio.Play("CameraSwitch", nil, 0.5)
	ctx.Remotes.Action:FireServer("Flashlight", on)
	ctx.HUD.SetBattery(battery, flashlightOn)
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
					light.Range = 44
					light.Angle = 50
					light.Brightness = 2.2
					light.Color = Color3.fromRGB(255, 244, 226)
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
local function bind(name, fn, touch, title, ...)
	ContextActionService:BindAction(name, function(_, state)
		if state == BEGIN then
			fn()
			return SINK
		end
		return PASS
	end, touch, ...)
	if touch and title then
		ContextActionService:SetTitle(name, title)
	end
end

function Controls.Init(c)
	ctx = c
	ensureFlash()
	ctx.HUD.SetBattery(battery, false)

	bind("NS_Flashlight", Controls.ToggleFlashlight, true, "🔦", Enum.KeyCode.F, Enum.KeyCode.ButtonL1)
	ContextActionService:BindAction("NS_Sprint", function(_, state)
		sprintHeld = state == BEGIN
		return SINK
	end, true, Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonL3)
	ContextActionService:SetTitle("NS_Sprint", "🏃")
	bind("NS_Drop", function()
		ctx.Remotes.Action:FireServer("Drop")
	end, false, nil, Enum.KeyCode.G, Enum.KeyCode.ButtonB)
	bind("NS_Phone", function()
		if not ctx.CameraLocked then
			ctx.HUD.OpenModal("Phone")
		end
	end, false, nil, Enum.KeyCode.P)
	bind("NS_Menu", function()
		if not ctx.CameraLocked then
			ctx.HUD.OpenModal("Settings")
		end
	end, false, nil, Enum.KeyCode.M)
	bind("NS_Tasks", function()
		ctx.HUD.ToggleTasks()
	end, false, nil, Enum.KeyCode.T)
	bind("NS_Start", function()
		ctx.HUD.RequestStart()
	end, false, nil, Enum.KeyCode.Return)

	-- Новый персонаж: сбросить бег и фонарик
	ctx.Player.CharacterAdded:Connect(function()
		stamina = Config.StaminaSeconds
		exhausted = false
		if flashlightOn then
			task.delay(0.5, function()
				ctx.Remotes.Action:FireServer("Flashlight", flashlightOn)
			end)
		end
	end)

	local otherTimer = 0
	RunService.RenderStepped:Connect(function(dt)
		local cam = workspace.CurrentCamera
		-- фонарик следует за камерой
		if flashPart and cam then
			flashPart.CFrame = cam.CFrame * CFrame.new(0.35, -0.35, -0.6)
		end
		if flashlightOn then
			battery = math.max(0, battery - dt / Config.FlashlightBatterySeconds)
			if battery < 0.1 then
				flashLight.Brightness = (math.random() < 0.08) and 0.3 or 2.0
			else
				flashLight.Brightness = 2.6
			end
			if battery <= 0 then
				Controls.SetFlashlight(false)
			end
		end

		local hum = humanoid()
		if hum then
			local moving = hum.MoveDirection.Magnitude > 0.1
			local sprinting = controlsEnabled and sprintHeld and moving and not exhausted and stamina > 0
			if sprinting then
				stamina = math.max(0, stamina - dt)
				if stamina <= 0 then
					exhausted = true
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

		otherTimer = otherTimer + dt
		if otherTimer > 0.3 then
			otherTimer = 0
			updateOtherLights()
			ctx.HUD.SetBattery(battery, flashlightOn)
		end
	end)
end

return Controls
