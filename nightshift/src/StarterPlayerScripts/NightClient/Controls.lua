-- Controls: управление на ПК и телефоне.
--   ПК: WASD, мышь, E — действие (R — второе), F — фонарик, Shift (удерживать) — бег, G — положить,
--       P — телефон, M — меню, T — задания, Enter — начать смену
--   Телефон: стандартный джойстик и обзор свайпом, круглые кнопки «фонарик» и «бег» у кнопки прыжка
--            (бег включается касанием и выключается сам, когда вы остановились или устали)
-- Фонарик: 3D-модель в руке, горячее пятно + ореол с тенями + рассеянный свет, отражение от поверхности,
-- пыль в луче; луч чуть запаздывает за поворотом головы, как у настоящего фонаря в руке.
-- Батарейка садится: свет тускнеет, желтеет, при низком заряде мигает.
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
-- Модель с текстурами (ReplicatedStorage.Assets.Flashlight; пока не загрузилась — простая из блоков).
-- Свет как у настоящего фонаря: яркое горячее пятно в центре (узкий прожектор), широкий ореол с тенями,
-- слабый рассеянный свет вокруг, тёплое стекло светится; там, куда попал луч, свет отражается от
-- поверхности её цветом; в луче видна пыль. Садится батарейка — свет тускнеет, желтеет и мигает.
-- Фонарик поднимается в кадр при включении и опускается при выключении, качается при ходьбе.
-------------------------------------------------------------------------------
local HAND_LENGTH = 0.92
local OTHER_LENGTH = 0.85
local LIGHT_COLOR = Color3.fromRGB(255, 240, 216)
local LOW_COLOR = Color3.fromRGB(255, 190, 128)
local CORE, MAIN, SPILL = 2.2, 1.7, 0.4

local hand -- { Folder, Parts, Glow, Emitter, Dust }
local coreLight
local bouncePart
local raise, raiseV = 0, 0
local flashLevel, flashColor = 1, LIGHT_COLOR
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function localPart(name, size, color, material, parent)
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
	p.Parent = parent
	return p
end

local CYL_FORWARD = CFrame.Angles(0, math.rad(90), 0) -- ось цилиндра (X) — вперёд (-Z)

-- Модель фонарика длиной length: детали со смещениями от «рамки» (центр, LookVector — куда светит)
local function makeFlashModel(length, parent)
	local obj = { Parts = {} }
	local f = Instance.new("Folder")
	f.Name = "Flashlight"
	f.Parent = parent
	obj.Folder = f
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local tpl = assets and assets:FindFirstChild("Flashlight")
	local lensZ, radius
	if tpl then
		local m = tpl:Clone()
		local _, size0 = m:GetBoundingBox()
		m:ScaleTo(length / math.max(size0.X, size0.Y, size0.Z))
		local cf, size = m:GetBoundingBox()
		local glass
		for _, d in ipairs(m:GetDescendants()) do
			if d:IsA("BasePart") and string.find(string.lower(d.Name), "glass", 1, true) then
				glass = d
			end
		end
		-- ось фонарика — самая длинная сторона, перёд — там, где стекло
		local ax = (size.X >= size.Y and size.X >= size.Z) and Vector3.xAxis or ((size.Y >= size.Z) and Vector3.yAxis or Vector3.zAxis)
		local g = glass and cf:PointToObjectSpace(glass.Position) or -Vector3.zAxis
		local frontWorld = cf:VectorToWorldSpace(ax * ((g:Dot(ax) >= 0) and 1 or -1))
		local up = math.abs(frontWorld.Y) < 0.9 and Vector3.yAxis or Vector3.xAxis
		local frame = CFrame.lookAt(cf.Position, cf.Position + frontWorld, up)
		for _, d in ipairs(m:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
				d.CanQuery = false
				d.CanTouch = false
				d.CastShadow = false
				d.Parent = f
				table.insert(obj.Parts, { Part = d, Off = frame:ToObjectSpace(d.CFrame) })
			end
		end
		m:Destroy()
		lensZ = glass and frame:PointToObjectSpace(glass.Position).Z or -length / 2
		local longest = math.max(size.X, size.Y, size.Z)
		radius = (size.X + size.Y + size.Z - longest) / 4
		obj.Real = true
	else
		local body = localPart("Body", Vector3.new(length * 0.78, 0.17, 0.17), Color3.fromRGB(34, 35, 38), Enum.Material.Metal, f)
		body.Shape = Enum.PartType.Cylinder
		table.insert(obj.Parts, { Part = body, Off = CFrame.new(0, 0, length * 0.1) * CYL_FORWARD })
		local head = localPart("Head", Vector3.new(length * 0.22, 0.25, 0.25), Color3.fromRGB(46, 47, 50), Enum.Material.Metal, f)
		head.Shape = Enum.PartType.Cylinder
		table.insert(obj.Parts, { Part = head, Off = CFrame.new(0, 0, -length * 0.39) * CYL_FORWARD })
		local button = localPart("Button", Vector3.new(0.08, 0.05, 0.06), Color3.fromRGB(150, 30, 30), Enum.Material.SmoothPlastic, f)
		table.insert(obj.Parts, { Part = button, Off = CFrame.new(0, 0.1, 0) })
		lensZ = -length / 2
		radius = 0.115
	end
	-- светящееся стекло (видно только когда включён)
	local glow = localPart("Glow", Vector3.new(0.012, radius * 1.7, radius * 1.7), Color3.fromRGB(255, 246, 228), Enum.Material.Neon, f)
	glow.Shape = Enum.PartType.Cylinder
	glow.Transparency = 1
	table.insert(obj.Parts, { Part = glow, Off = CFrame.new(0, 0, lensZ - 0.004) * CYL_FORWARD })
	obj.Glow = glow
	-- точка, откуда идёт свет
	local emitter = localPart("Emitter", Vector3.new(0.05, 0.05, 0.05), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic, f)
	emitter.Transparency = 1
	table.insert(obj.Parts, { Part = emitter, Off = CFrame.new(0, 0, lensZ - 0.05) })
	obj.Emitter = emitter
	return obj
end

local function placeFlashModel(obj, cf, show)
	for _, p in ipairs(obj.Parts) do
		p.Part.CFrame = cf * p.Off
		if p.Part ~= obj.Emitter then
			p.Part.LocalTransparencyModifier = show and 0 or 1
		end
	end
end

local function spotLight(name, parent, angle, range, brightness, shadows)
	local l = Instance.new("SpotLight")
	l.Name = name
	l.Face = Enum.NormalId.Front
	l.Angle = angle
	l.Range = range
	l.Brightness = brightness
	l.Color = LIGHT_COLOR
	l.Shadows = shadows
	l.Enabled = false
	l.Parent = parent
	return l
end

-- Пыль в луче: крошечные частицы видны только там, куда падает свет
local function dust(parent, rate)
	local e = Instance.new("ParticleEmitter")
	e.Name = "Dust"
	e.Texture = "rbxasset://textures/particles/smoke_main.dds"
	e.EmissionDirection = Enum.NormalId.Front
	e.Rate = rate
	e.Lifetime = NumberRange.new(2.5, 4.5)
	e.Speed = NumberRange.new(1.5, 5)
	e.SpreadAngle = Vector2.new(16, 16)
	e.Drag = 1.4
	e.Acceleration = Vector3.new(0, -0.04, 0)
	e.RotSpeed = NumberRange.new(-20, 20)
	e.Size = NumberSequence.new(0.045)
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.2, 0.55),
		NumberSequenceKeypoint.new(0.8, 0.65),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.Color = ColorSequence.new(Color3.fromRGB(235, 228, 216))
	e.LightInfluence = 1
	e.LightEmission = 0
	e.Enabled = false
	e.Parent = parent
	return e
end

local function buildFlashlight()
	if hand and hand.Folder.Parent then
		hand.Folder.Parent:Destroy()
	end
	local root = Instance.new("Folder")
	root.Name = "LocalFlashlight"
	root.Parent = workspace
	hand = makeFlashModel(HAND_LENGTH, root)
	local e = hand.Emitter
	coreLight = spotLight("Core", e, 22, 72, CORE, false)
	mainLight = spotLight("Beam", e, 46, 58, MAIN, true)
	spillLight = spotLight("Spill", e, 110, 20, SPILL, false)
	hand.Dust = dust(e, 9)
	-- отражённый свет там, куда попал луч
	bouncePart = localPart("Bounce", Vector3.new(0.1, 0.1, 0.1), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic, root)
	bouncePart.Transparency = 1
	bounceLight = Instance.new("PointLight")
	bounceLight.Name = "Bounce"
	bounceLight.Range = 8
	bounceLight.Brightness = 0
	bounceLight.Shadows = false
	bounceLight.Enabled = false
	bounceLight.Parent = bouncePart
	lens = hand.Glow
	rig = root
end

local function spring(x, v, target, dt, k, damp)
	v = v + (k * (target - x) - damp * v) * dt
	return x + v * dt, v
end

local function placeFlashlight(dt, moving, sprinting)
	local cam = workspace.CurrentCamera
	if not (cam and hand) then
		return
	end
	local want = (flashlightOn and not ctx.CameraLocked) and 1 or 0
	raise, raiseV = spring(raise, raiseV, want, math.min(dt, 0.05), 150, 19)
	local camCF = cam.CFrame
	local rot = camCF - camCF.Position
	-- рука чуть запаздывает за поворотом головы
	swayRot = swayRot:Lerp(rot, math.min(1, dt * 13))
	local bob = CFrame.new()
	if moving and ctx.Settings.HeadBob ~= false then
		local k = sprinting and 1.6 or 1
		bob = CFrame.new(math.sin(bobTime) * 0.025 * k, math.abs(math.cos(bobTime)) * 0.03 * k, 0) * CFrame.Angles(0, 0, math.sin(bobTime) * 0.02 * k)
	end
	local drop = math.clamp(1 - raise, 0, 1.2)
	local base = CFrame.new(camCF.Position) * swayRot
		* CFrame.new(0.44, -0.42 - drop * 0.6, -0.95 + drop * 0.12) * bob
		* CFrame.Angles(math.rad(2 + drop * 38), math.rad(4 + drop * 8), 0)
	local show = raise > 0.03
	placeFlashModel(hand, base, show)
	-- отражённый свет: точка на поверхности, куда смотрит луч
	if mainLight.Enabled then
		local list = { rig }
		if ctx.Player.Character then
			table.insert(list, ctx.Player.Character)
		end
		rayParams.FilterDescendantsInstances = list
		local origin = hand.Emitter.Position
		local hit = workspace:Raycast(origin, hand.Emitter.CFrame.LookVector * 50, rayParams)
		if hit then
			local d = (hit.Position - origin).Magnitude
			local k = (1 - d / 50) ^ 1.4
			bouncePart.CFrame = CFrame.new(hit.Position + hit.Normal * math.clamp(d * 0.08, 0.6, 2.4))
			bounceLight.Enabled = true
			bounceLight.Brightness = 0.55 * k * flashLevel
			bounceLight.Range = 6 + d * 0.16
			bounceLight.Color = flashColor:Lerp(hit.Instance.Color, 0.4)
		else
			bounceLight.Enabled = false
		end
	else
		bounceLight.Enabled = false
	end
end

local function setLights(on)
	if not mainLight then
		return
	end
	local visible = on and not ctx.CameraLocked
	coreLight.Enabled = visible
	mainLight.Enabled = visible
	spillLight.Enabled = visible
	if not visible then
		bounceLight.Enabled = false
	end
	hand.Dust.Enabled = visible
	hand.Glow.Transparency = on and 0 or 1
end

-- Яркость и цвет (батарейка): level 0..1
local function setFlashLevel(level, color)
	flashLevel, flashColor = level, color
	coreLight.Brightness = CORE * level
	mainLight.Brightness = MAIN * level
	spillLight.Brightness = SPILL * level
	coreLight.Color, mainLight.Color, spillLight.Color = color, color, color
	hand.Glow.Color = Color3.fromRGB(255, 246, 228):Lerp(color, 0.6)
	hand.Glow.Transparency = 1 - math.clamp(level * 1.1, 0, 1)
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

-- Фонарики других игроков (создаются только у нас): модель в правой руке, рука поднята вперёд,
-- прожектор с тенями и видимый конус света в пыльном воздухе магазина
local otherRoot = nil
local GRIP = CFrame.new(0, -0.12, -0.03) * CFrame.Angles(math.rad(-90), 0, 0) -- луч вдоль пальцев

local function dropOther(p)
	local o = otherLights[p]
	if o then
		if o.Obj then
			o.Obj.Folder:Destroy()
		end
		otherLights[p] = nil
	end
end

local function updateOtherLights()
	if not otherRoot or not otherRoot.Parent then
		otherRoot = Instance.new("Folder")
		otherRoot.Name = "OtherFlashlights"
		otherRoot.Parent = workspace
	end
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= ctx.Player then
			local ch = p.Character
			local handPart = ch and (ch:FindFirstChild("RightHand") or ch:FindFirstChild("Right Arm"))
			local o = otherLights[p]
			if o and o.Character ~= ch then
				dropOther(p)
				o = nil
			end
			if handPart and not o then
				local obj = makeFlashModel(OTHER_LENGTH, otherRoot)
				local light = spotLight("Beam", obj.Emitter, 42, 46, 2.4, true)
				local a0 = Instance.new("Attachment")
				a0.Parent = obj.Emitter
				local a1 = Instance.new("Attachment")
				a1.Position = Vector3.new(0, 0, -18)
				a1.Parent = obj.Emitter
				local cone = Instance.new("Beam")
				cone.Attachment0, cone.Attachment1 = a0, a1
				cone.Width0, cone.Width1 = 0.3, 9
				cone.FaceCamera = true
				cone.LightEmission = 1
				cone.LightInfluence = 0
				cone.Segments = 10
				cone.Color = ColorSequence.new(LIGHT_COLOR)
				cone.Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0.82),
					NumberSequenceKeypoint.new(0.4, 0.93),
					NumberSequenceKeypoint.new(1, 1),
				})
				cone.Enabled = false
				cone.Parent = obj.Emitter
				o = { Obj = obj, Light = light, Cone = cone, Character = ch, Hand = handPart, Raise = 0, RaiseV = 0 }
				local hum = ch:FindFirstChildOfClass("Humanoid")
				if hum and hum.RigType == Enum.HumanoidRigType.R15 then
					local upper = ch:FindFirstChild("RightUpperArm")
					local lower = ch:FindFirstChild("RightLowerArm")
					o.Shoulder = upper and upper:FindFirstChild("RightShoulder")
					o.Elbow = lower and lower:FindFirstChild("RightElbow")
				end
				otherLights[p] = o
			end
			if o then
				o.On = ch:GetAttribute("Flashlight") == true
			end
		end
	end
	for p in pairs(otherLights) do
		if not p.Parent then
			dropOther(p)
		end
	end
end

-- Поднять руку с фонариком: поверх анимации ходьбы (до шага физики)
local SHOULDER_UP = CFrame.Angles(1.22, 0, 0)
local ELBOW_UP = CFrame.Angles(0.32, 0, 0)
local function poseOthers(dt)
	for _, o in pairs(otherLights) do
		o.Raise, o.RaiseV = spring(o.Raise, o.RaiseV, o.On and 1 or 0, math.min(dt, 0.05), 90, 15)
		local w = math.clamp(o.Raise, 0, 1)
		if w > 0.01 then
			if o.Shoulder and o.Shoulder.Parent then
				o.Shoulder.Transform = o.Shoulder.Transform:Lerp(SHOULDER_UP, w)
			end
			if o.Elbow and o.Elbow.Parent then
				o.Elbow.Transform = o.Elbow.Transform:Lerp(ELBOW_UP, w)
			end
		end
	end
end

-- Поставить фонарики в руки (после шага физики, когда руки уже на месте)
local function placeOthers()
	for _, o in pairs(otherLights) do
		local show = o.Raise > 0.05 and o.Hand.Parent ~= nil
		if show then
			placeFlashModel(o.Obj, o.Hand.CFrame * GRIP, true)
		else
			placeFlashModel(o.Obj, CFrame.new(0, -500, 0), false)
		end
		local lit = show and o.On
		o.Light.Enabled = lit
		o.Cone.Enabled = lit
		o.Obj.Glow.Transparency = lit and 0 or 1
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

	-- фонарики других игроков: поднять руку до шага физики, поставить модель после
	RunService.Stepped:Connect(function(_, dt)
		poseOthers(dt)
	end)
	RunService.Heartbeat:Connect(placeOthers)
	-- модель фонарика приходит с сервера чуть позже: тогда заменяем простую
	task.spawn(function()
		local assets = ReplicatedStorage:WaitForChild("Assets", 120)
		local tpl = assets and assets:WaitForChild("Flashlight", 120)
		if tpl and hand and not hand.Real then
			buildFlashlight()
			setLights(flashlightOn)
			for p in pairs(otherLights) do
				dropOther(p)
			end
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
			-- садится батарейка: последние 25% свет тускнеет и желтеет
			local charge = math.clamp(battery / 0.25, 0, 1)
			setLights(true)
			setFlashLevel(flick * (0.6 + 0.4 * charge), LOW_COLOR:Lerp(LIGHT_COLOR, charge))
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
