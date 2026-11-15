-- Effects: визуальные эффекты на клиенте.
--   • свет: без электричества гаснут лампы, фонари и вывеска, выключаются табло касс и мониторы;
--     сломанные лампы мигают сами
--   • мигание ламп по событию (иногда в мигающем свете кто-то стоит), погасший участок зала
--   • цвет картинки по месту, где камера: улица — холодная сине-серая, торговый зал — бледный белый
--     с зеленоватым оттенком ламп, подсобка — серая, комнаты — чуть теплее; без света всё бесцветнее
--   • виньетка по краям экрана, сильнее, когда рядом Покупатель или нет света
--   • вывеска MART 24 иногда мерцает; часы в кабинете менеджера показывают время смены
--   • «Покупатель»: сообщаем серверу, видим ли его (он не двигается, пока на него смотрят),
--     поворачиваем ему голову к камере, звук сердцебиения рядом
--   • видения (их видит только этот игрок), поимка, сцены концовок
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
-- кадр отрисовки (в серверном тесте его нет — там Heartbeat)
local RENDER = RunService:IsClient() and RunService.RenderStepped or RunService.Heartbeat

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Texts = require(Shared:WaitForChild("Texts"))

local Effects = {}

local ctx
local lamps = {}
local fridgeBodies = {}
local screens = {}
local emergency = {}
local forcedOff = false
local flickering = {}
local outLamps = {}
local savedLighting = {}
local cinematic = false
local signs = {} -- { Gui, Base, Glow, GlowBase }
local signDim = 1
local OFF_COLOR = Color3.fromRGB(70, 70, 72)
local grade, vignette
local gradeKey = nil
local gradeTime = 1.2
local threatLevel = 0
local vignetteBoost = 0
local wallHands = {}
local deskClockLabel
local clockOverride = nil
Effects.Ready = false

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

-------------------------------------------------------------------------------
-- Свет
-------------------------------------------------------------------------------
local function powerOn()
	return ctx.State:GetAttribute("Power") ~= false and not forcedOff
end

local function lampShouldBeOn(l)
	if not powerOn() or outLamps[l] then
		return false
	end
	if l.Unit and fridgeBodies[l.Unit] and fridgeBodies[l.Unit]:GetAttribute("Broken") == true then
		return false
	end
	return true
end

local function setLamp(l, on)
	if l.Light then
		l.Light.Enabled = on
	end
	l.Part.Material = on and Enum.Material.Neon or Enum.Material.SmoothPlastic
	l.Part.Color = on and l.Color or OFF_COLOR
end

local function setSigns(k)
	for _, s in ipairs(signs) do
		s.Gui.Enabled = k > 0
		s.Gui.Brightness = s.Base * math.max(k, 0.05)
		if s.Glow then
			s.Glow.Enabled = k > 0
			s.Glow.Brightness = s.GlowBase * k
		end
	end
end

function Effects.ApplyLights()
	local on = powerOn()
	for _, l in ipairs(lamps) do
		if not flickering[l] then
			setLamp(l, lampShouldBeOn(l))
		end
	end
	for _, gui in ipairs(screens) do
		gui.Enabled = on
	end
	for _, e in ipairs(emergency) do
		e.Brightness = on and 0.8 or 1.6
	end
	setSigns(on and signDim or 0)
end

local function collect()
	for _, part in ipairs(CollectionService:GetTagged("StoreLight")) do
		local zone = part:GetAttribute("Zone") or ""
		table.insert(lamps, {
			Part = part,
			Light = part:FindFirstChildWhichIsA("Light"),
			Color = part:GetAttribute("LampColor") or part.Color,
			Zone = zone,
			Unit = tonumber(string.match(zone, "^Fridge(%d+)$")),
			Broken = part:GetAttribute("Broken") == true,
		})
	end
	for _, body in ipairs(CollectionService:GetTagged("AmbFridge")) do
		local unit = body:GetAttribute("Unit")
		if unit then
			fridgeBodies[unit] = body
			body:GetAttributeChangedSignal("Broken"):Connect(Effects.ApplyLights)
		end
	end
	for _, sign in ipairs(CollectionService:GetTagged("EmergencyLight")) do
		local l = sign:FindFirstChildWhichIsA("PointLight")
		if l then
			table.insert(emergency, l)
		end
	end
	for _, part in ipairs(CollectionService:GetTagged("StoreSign")) do
		local g = part:FindFirstChildWhichIsA("SurfaceGui")
		if g then
			local glow = part:FindFirstChild("SignGlow")
			table.insert(signs, { Gui = g, Base = g.Brightness, Glow = glow, GlowBase = glow and glow.Brightness or 0 })
		end
	end
	local store = workspace:FindFirstChild("Store")
	if store then
		-- светящиеся экраны (у них LightInfluence = 0): табло касс, холодильников, мониторы
		local holders = {}
		local rooms = store:FindFirstChild("Rooms")
		for _, f in ipairs({
			store:FindFirstChild("Checkouts") or false,
			store:FindFirstChild("Fridges") or false,
			rooms and rooms:FindFirstChild("Security") or false,
			rooms and rooms:FindFirstChild("Office") or false,
		}) do
			if f then
				table.insert(holders, f)
			end
		end
		for _, f in ipairs(holders) do
			for _, d in ipairs(f:GetDescendants()) do
				if d:IsA("SurfaceGui") and d.LightInfluence == 0 then
					table.insert(screens, d)
				end
			end
		end
		local office = rooms and rooms:FindFirstChild("Office")
		local dclock = office and office:FindFirstChild("DeskClock")
		local cg = dclock and dclock:FindFirstChild("ClockGui")
		deskClockLabel = cg and cg:FindFirstChildWhichIsA("TextLabel")
	end
	-- стрелки настенных часов
	for _, face in ipairs(CollectionService:GetTagged("WallClock")) do
		local center = face:GetAttribute("Center") or face.Position
		for _, p in ipairs(face.Parent:GetChildren()) do
			local kind = p:IsA("BasePart") and p:GetAttribute("ClockHand")
			if kind then
				local off = p.Position - center
				table.insert(wallHands, { Part = p, Kind = kind, Pivot = center + Vector3.new(0, 0, off.Z), Arm = off.Y })
			end
		end
	end
end

-- Мигание: лампы в радиусе Radius от Center (или зоны Zone) Duration секунд.
-- Figure = true — пока свет мигает, впереди стоит тёмная фигура (видит только этот игрок)
local function setModelVisible(model, on)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.LocalTransparencyModifier = on and 0 or 1
		end
	end
end

local function figureSpot()
	local cam = workspace.CurrentCamera
	local cf = cam.CFrame
	local look = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
	if look.Magnitude < 0.1 then
		return nil
	end
	look = look.Unit
	local right = Vector3.new(-look.Z, 0, look.X)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { ctx.Player.Character, workspace:FindFirstChild("Dynamic") }
	for _ = 1, 12 do
		local p = cf.Position + look * math.random(14, 26) + right * ((math.random() - 0.5) * 6)
		local down = workspace:Raycast(Vector3.new(p.X, cf.Position.Y + 1, p.Z), Vector3.new(0, -14, 0), params)
		if down and down.Normal.Y > 0.7 and down.Position.Y < 0.6 then
			local foot = down.Position
			local head = foot + Vector3.new(0, 5, 0)
			local clear = not workspace:Raycast(cf.Position, (head - cf.Position) * 0.97, params)
				and not workspace:Raycast(cf.Position, (foot + Vector3.new(0, 1, 0) - cf.Position) * 0.97, params)
			if clear then
				return CFrame.lookAt(foot, Vector3.new(cf.Position.X, foot.Y, cf.Position.Z))
			end
		end
	end
	return nil
end

-- Тёмный силуэт без лица (локальная модель). cf — точка на полу и направление взгляда
function Effects.Silhouette(cf, parent)
	local tpl = ReplicatedStorage:FindFirstChild("MonsterTemplate")
	if not tpl then
		return nil
	end
	local m = tpl:Clone()
	m.Name = "Silhouette"
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Color = Color3.fromRGB(6, 6, 8)
			d.Material = Enum.Material.SmoothPlastic
			d.Reflectance = 0
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			if d:IsA("MeshPart") then
				pcall(function()
					d.TextureID = ""
				end)
			end
		elseif d:IsA("Decal") or d:IsA("Clothing") or d:IsA("ShirtGraphic") or d:IsA("BaseScript") then
			d:Destroy()
		elseif d:IsA("SpecialMesh") then
			d.TextureId = ""
		end
	end
	local hum = m:FindFirstChildOfClass("Humanoid")
	local root = m:FindFirstChild("HumanoidRootPart")
	if hum then
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
	local h = (hum and root) and (hum.HipHeight + root.Size.Y / 2) or 3
	local pos = cf.Position
	local at = Vector3.new(pos.X, pos.Y + h, pos.Z)
	local look = cf.LookVector
	m:PivotTo(CFrame.lookAt(at, at + Vector3.new(look.X, 0, look.Z)))
	if root then
		root.Anchored = true
	end
	m.Parent = parent or workspace
	return m
end

function Effects.Flicker(data)
	local list = {}
	for _, l in ipairs(lamps) do
		local near = data.Center and (l.Part.Position - Vector3.new(data.Center.X, l.Part.Position.Y, data.Center.Z)).Magnitude <= (data.Radius or 40)
		if near or (not data.Center and l.Zone == data.Zone) then
			table.insert(list, l)
		end
	end
	for _, l in ipairs(list) do
		flickering[l] = true
	end
	local figure
	if data.Figure and not cinematic and not ctx.CameraLocked then
		local spot = figureSpot()
		figure = spot and Effects.Silhouette(spot)
	end
	task.spawn(function()
		local untilT = os.clock() + (data.Duration or 3)
		while os.clock() < untilT do
			local dark = math.random() < 0.55
			for _, l in ipairs(list) do
				setLamp(l, lampShouldBeOn(l) and (not dark or math.random() < 0.2))
			end
			if figure then
				setModelVisible(figure, math.random() < 0.8)
			end
			task.wait(math.random(4, 16) / 100)
		end
		if figure then
			figure:Destroy()
		end
		for _, l in ipairs(list) do
			flickering[l] = nil
		end
		Effects.ApplyLights()
	end)
end

-- Погасший участок зала: лампы в радиусе Radius от Center мигают и гаснут на Duration секунд
function Effects.LampsOut(data)
	local center = data.Center
	if not center then
		return
	end
	local list = {}
	for _, l in ipairs(lamps) do
		local d = (l.Part.Position - Vector3.new(center.X, l.Part.Position.Y, center.Z)).Magnitude
		if l.Zone ~= "Outside" and d <= (data.Radius or 16) then
			table.insert(list, l)
		end
	end
	local function flick(seconds, chance)
		for _, l in ipairs(list) do
			flickering[l] = true
		end
		local t = os.clock() + seconds
		while os.clock() < t do
			for _, l in ipairs(list) do
				setLamp(l, lampShouldBeOn(l) and math.random() < chance)
			end
			task.wait(math.random(4, 12) / 100)
		end
		for _, l in ipairs(list) do
			flickering[l] = nil
		end
	end
	task.spawn(function()
		flick(1.2, 0.4)
		for _, l in ipairs(list) do
			outLamps[l] = true
		end
		Effects.ApplyLights()
		task.wait(data.Duration or 90)
		for _, l in ipairs(list) do
			outLamps[l] = nil
		end
		flick(1.5, 0.6)
		Effects.ApplyLights()
	end)
end

-------------------------------------------------------------------------------
-- Цвет картинки, виньетка, вывеска, часы
-------------------------------------------------------------------------------
local GRADES = {
	Outside = { Tint = Color3.fromRGB(198, 214, 242), Saturation = -0.28, Contrast = 0.14, Brightness = -0.02 },
	Sales = { Tint = Color3.fromRGB(238, 248, 236), Saturation = -0.1, Contrast = 0.06, Brightness = 0 },
	Corridor = { Tint = Color3.fromRGB(226, 234, 232), Saturation = -0.2, Contrast = 0.1, Brightness = -0.02 },
	Room = { Tint = Color3.fromRGB(246, 238, 226), Saturation = -0.08, Contrast = 0.06, Brightness = 0 },
}

local function updateGrade()
	local cam = workspace.CurrentCamera
	if not (cam and grade) then
		return
	end
	local zone = ctx.Audio.ZoneOf(cam.CFrame.Position)
	local power = powerOn()
	local key = zone .. (power and "" or "Dark")
	if key == gradeKey then
		return
	end
	gradeKey = key
	local g = GRADES[zone] or GRADES.Sales
	TweenService:Create(grade, TweenInfo.new(gradeTime, Enum.EasingStyle.Sine), {
		TintColor = g.Tint,
		Saturation = g.Saturation - (power and 0 or 0.25),
		Contrast = g.Contrast,
		Brightness = g.Brightness - (power and 0 or 0.03),
	}):Play()
end

-- Скорость смены цвета (кат-сцена делает переход с улицы в магазин медленнее)
function Effects.SetGradeTime(seconds)
	gradeTime = seconds or 1.2
end

-- Дополнительная виньетка (0..1), например в кат-сцене
function Effects.SetVignetteBoost(v)
	vignetteBoost = v or 0
end

-- Часы в кабинете: minutes от полуночи (−1 = 23:59), nil — время смены
function Effects.SetClock(minutes)
	clockOverride = minutes
	Effects.UpdateClocks()
end

function Effects.UpdateClocks()
	local phase = ctx.State:GetAttribute("Phase")
	local minutes = ctx.State:GetAttribute("Minutes") or 0
	if phase ~= "Shift" and phase ~= "Ending" then
		minutes = -2 -- до начала смены часы показывают 23:58
	end
	if clockOverride then
		minutes = clockOverride
	end
	local total = minutes % (24 * 60)
	local h = math.floor(total / 60)
	local m = total % 60
	if deskClockLabel then
		deskClockLabel.Text = string.format("%02d:%02d", h, m)
	end
	for _, hand in ipairs(wallHands) do
		local frac = (hand.Kind == "Hour") and (((h % 12) + m / 60) / 12) or (m / 60)
		hand.Part.CFrame = CFrame.new(hand.Pivot) * CFrame.Angles(0, 0, frac * 2 * math.pi) * CFrame.new(0, hand.Arm, 0)
	end
end

-- Вывеска иногда слегка мерцает (неисправный пускатель)
local function signFlickerLoop()
	while true do
		task.wait(math.random(40, 110) / 10)
		if powerOn() and #signs > 0 then
			for _ = 1, math.random(2, 5) do
				signDim = 0.2 + math.random() * 0.3
				setSigns(powerOn() and signDim or 0)
				task.wait(math.random(3, 9) / 100)
				signDim = 1
				setSigns(powerOn() and 1 or 0)
				task.wait(math.random(5, 22) / 100)
			end
		end
	end
end

-------------------------------------------------------------------------------
-- Видимость
-------------------------------------------------------------------------------
local function clearLine(a, b, ignore)
	local list = { ctx.Player.Character, workspace.CurrentCamera }
	local dyn = workspace:FindFirstChild("Dynamic")
	if dyn then
		table.insert(list, dyn)
	end
	for _, x in ipairs(ignore or {}) do
		table.insert(list, x)
	end
	rayParams.FilterDescendantsInstances = list
	local origin = a
	for _ = 1, 5 do
		local dir = b - origin
		if dir.Magnitude < 0.1 then
			return true
		end
		local hit = workspace:Raycast(origin, dir, rayParams)
		if not hit then
			return true
		end
		if hit.Instance.Transparency > 0.4 or hit.Instance.Material == Enum.Material.Glass then
			origin = hit.Position + dir.Unit * 0.05
		else
			return false
		end
	end
	return false
end

-- Видит ли камера игрока модель (голова или грудь на экране и ничто не загораживает)
local function canSee(model)
	local cam = workspace.CurrentCamera
	if not cam then
		return false
	end
	for _, name in ipairs({ "Head", "UpperTorso" }) do
		local part = model:FindFirstChild(name)
		if part then
			local p, onScreen = cam:WorldToViewportPoint(part.Position)
			local dist = (part.Position - cam.CFrame.Position).Magnitude
			if onScreen and p.Z > 0 and dist < 130 and clearLine(cam.CFrame.Position, part.Position, { model }) then
				return true
			end
		end
	end
	return false
end

-------------------------------------------------------------------------------
-- Видения (только у этого игрока)
-------------------------------------------------------------------------------
local function spawnLocalFigure(cf)
	local tpl = ReplicatedStorage:FindFirstChild("MonsterTemplate")
	if not tpl then
		return nil
	end
	local m = tpl:Clone()
	m.Name = "Apparition"
	local hum = m:FindFirstChildOfClass("Humanoid")
	local root = m:FindFirstChild("HumanoidRootPart")
	local h = (hum and root) and (hum.HipHeight + root.Size.Y / 2) or 3
	local pos = cf.Position
	local at = Vector3.new(pos.X, pos.Y + h, pos.Z)
	local look = cf.LookVector
	m:PivotTo(CFrame.lookAt(at, at + Vector3.new(look.X, 0, look.Z)))
	if root then
		root.Anchored = true
	end
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end
	m.Parent = workspace
	return m
end

function Effects.Apparition(data)
	if cinematic or ctx.CameraLocked then
		return
	end
	local m = spawnLocalFigure(data.CFrame)
	if not m then
		return
	end
	task.spawn(function()
		local seenTime = 0
		local started = os.clock()
		while m.Parent and os.clock() - started < 14 do
			task.wait(0.1)
			if canSee(m) then
				seenTime = seenTime + 0.1
			elseif seenTime > 0.6 then
				break -- отвернулись — исчез
			end
			if seenTime > 4 then
				break
			end
		end
		m:Destroy()
		if seenTime > 0.6 then
			ctx.Audio.Play("Static", nil, 0.25)
		end
	end)
end

-------------------------------------------------------------------------------
-- «Покупатель»
-------------------------------------------------------------------------------
local lastSeen, lastSent = false, 0

local function watchMonster()
	local dyn = workspace:FindFirstChild("Dynamic")
	local model = dyn and dyn:FindFirstChild("TheCustomer")
	local present = model and model:GetAttribute("Present") == true
	local seen = present and canSee(model) or false
	local now = os.clock()
	if seen ~= lastSeen or (seen and now - lastSent > 0.5) then
		lastSeen = seen
		lastSent = now
		ctx.Remotes.Action:FireServer("MonsterSeen", seen)
	end
	local level = 0
	if present then
		local root = ctx.Player.Character and ctx.Player.Character:FindFirstChild("HumanoidRootPart")
		local head = model:FindFirstChild("Head")
		if root and head then
			local d = (head.Position - root.Position).Magnitude
			level = math.clamp(1 - (d - 6) / 34, 0, 1)
			-- поворачивает голову к вам
			local neck = head:FindFirstChild("Neck")
			local mroot = model:FindFirstChild("HumanoidRootPart")
			if neck and mroot and d < 50 then
				local rel = mroot.CFrame:PointToObjectSpace(workspace.CurrentCamera.CFrame.Position)
				local yaw = math.clamp(math.atan2(-rel.X, -rel.Z), -1.1, 1.1)
				pcall(function()
					neck.Transform = CFrame.Angles(0, yaw, 0)
				end)
			end
		end
	end
	threatLevel = level
	ctx.Audio.SetThreat(level)
end

-------------------------------------------------------------------------------
-- Поимка
-------------------------------------------------------------------------------
function Effects.Caught()
	if cinematic then
		return
	end
	cinematic = true
	ctx.CameraLocked = true
	local cam = workspace.CurrentCamera
	ctx.Controls.SetEnabled(false)
	ctx.Audio.Play("Stinger", nil, 1)
	local dyn = workspace:FindFirstChild("Dynamic")
	local model = dyn and dyn:FindFirstChild("TheCustomer")
	local head = model and model:FindFirstChild("Head")
	vignetteBoost = 0.6
	if head then
		cam.CameraType = Enum.CameraType.Scriptable
		local face = head.CFrame * CFrame.new(0, 0, -2.2)
		for i = 1, 12 do
			cam.CFrame = CFrame.lookAt(face.Position + Vector3.new(math.random() - 0.5, math.random() - 0.5, 0) * 0.08 * i, head.Position)
			task.wait(0.03)
		end
	end
	ctx.HUD.Fade(0, 0.2)
	task.wait(2.6)
	cam.CameraType = Enum.CameraType.Custom
	local hum = ctx.Player.Character and ctx.Player.Character:FindFirstChildOfClass("Humanoid")
	if hum then
		cam.CameraSubject = hum
	end
	vignetteBoost = 0
	ctx.HUD.Fade(1, 1.5)
	ctx.HUD.Subtitle("", "…вы приходите в себя в комнате персонала", 4)
	ctx.Controls.SetEnabled(true)
	ctx.CameraLocked = false
	cinematic = false
end

-------------------------------------------------------------------------------
-- Концовки
-------------------------------------------------------------------------------
local function saveLighting()
	savedLighting = {
		ClockTime = Lighting.ClockTime,
		Brightness = Lighting.Brightness,
		Ambient = Lighting.Ambient,
		OutdoorAmbient = Lighting.OutdoorAmbient,
	}
end

local function restoreLighting()
	for k, v in pairs(savedLighting) do
		Lighting[k] = v
	end
end

function Effects.Ending(stats)
	local kind = stats.Kind
	cinematic = true
	ctx.CameraLocked = true
	if ctx.Cameras.IsOpen() then
		ctx.Cameras.Close()
	end
	ctx.HUD.CloseModals()
	ctx.Controls.SetEnabled(false)
	local cam = workspace.CurrentCamera
	task.spawn(function()
		if kind == "Good" then
			-- рассвет: магазин снаружи, тёмный и заброшенный
			ctx.HUD.Fade(0, 1.2, Color3.fromRGB(230, 230, 236))
			task.wait(1.4)
			Lighting.ClockTime = 6.4
			Lighting.Brightness = 1.6
			Lighting.OutdoorAmbient = Color3.fromRGB(110, 106, 122)
			forcedOff = true
			Effects.ApplyLights()
			cam.CameraType = Enum.CameraType.Scriptable
			local from = CFrame.lookAt(Vector3.new(-30, 7, 104), Vector3.new(-30, 8, 50))
			local to = CFrame.lookAt(Vector3.new(-30, 6.5, 74), Vector3.new(-30, 8, 50))
			cam.CFrame = from
			ctx.HUD.Fade(1, 2.5)
			local t0 = os.clock()
			while os.clock() - t0 < 9 and cinematic do
				cam.CFrame = from:Lerp(to, (os.clock() - t0) / 9)
				RENDER:Wait()
			end
			ctx.HUD.ShowEnding(stats)
		elseif kind == "Bad" then
			forcedOff = true
			Effects.ApplyLights()
			ctx.Audio.Play("PowerDown", nil, 1)
			task.wait(1.6)
			local look = cam.CFrame.LookVector
			local spot = cam.CFrame.Position + Vector3.new(look.X, 0, look.Z).Unit * 3.2
			-- пол магазина на высоте 0
			local fig = spawnLocalFigure(CFrame.lookAt(Vector3.new(spot.X, 0, spot.Z), Vector3.new(cam.CFrame.Position.X, 0, cam.CFrame.Position.Z)))
			ctx.HUD.Subtitle("Шёпот", Texts.Whisper.YourTurn, 4)
			task.wait(1.8)
			ctx.Audio.Play("DarkHit", nil, 1)
			ctx.HUD.Fade(0, 0.25)
			task.wait(1.5)
			if fig then
				fig:Destroy()
			end
			ctx.HUD.ShowEnding(stats)
		else
			-- секретная: тёплый рассвет над пустой кассой №0
			ctx.HUD.Fade(0, 2, Color3.fromRGB(255, 240, 220))
			task.wait(2.2)
			Lighting.ClockTime = 6.6
			Lighting.Brightness = 1.4
			Lighting.Ambient = Color3.fromRGB(90, 80, 70)
			cam.CameraType = Enum.CameraType.Scriptable
			cam.CFrame = CFrame.lookAt(Vector3.new(-58, 6, -50), Vector3.new(-58, 3, -62))
			ctx.HUD.Fade(1, 3)
			task.wait(5)
			ctx.HUD.ShowEnding(stats)
		end
	end)
end

-- Новая смена: вернуть свет, камеру и управление
function Effects.ResetCinematic()
	cinematic = false
	forcedOff = false
	ctx.CameraLocked = false
	vignetteBoost = 0
	restoreLighting()
	local cam = workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Custom
	local hum = ctx.Player.Character and ctx.Player.Character:FindFirstChildOfClass("Humanoid")
	if hum then
		cam.CameraSubject = hum
	end
	ctx.HUD.Fade(1, 1)
	ctx.Controls.SetEnabled(true)
	ctx.Controls.ApplySettings()
	Effects.ApplyLights()
end

-- Кат-сцена: не показывать видения и поимку
function Effects.SetCinematic(on)
	cinematic = on
end

function Effects.Init(c)
	ctx = c
	saveLighting()

	-- цвет картинки и виньетка
	grade = Instance.new("ColorCorrectionEffect")
	grade.Name = "NS_ZoneGrade"
	grade.Parent = Lighting
	local vg = Instance.new("ScreenGui")
	vg.Name = "NightVignette"
	vg.ResetOnSpawn = false
	vg.IgnoreGuiInset = true
	vg.DisplayOrder = 0
	vg.Parent = ctx.Player:WaitForChild("PlayerGui")
	vignette = Instance.new("ImageLabel")
	vignette.Name = "Vignette"
	vignette.Size = UDim2.fromScale(1, 1)
	vignette.BackgroundTransparency = 1
	vignette.Image = Config.Images.Vignette
	vignette.ImageTransparency = 0.5
	vignette.Parent = vg

	if not workspace:GetAttribute("StoreReady") then
		workspace:GetAttributeChangedSignal("StoreReady"):Wait()
	end
	collect()
	ctx.State:GetAttributeChangedSignal("Power"):Connect(Effects.ApplyLights)
	ctx.State:GetAttributeChangedSignal("Phase"):Connect(function()
		local phase = ctx.State:GetAttribute("Phase")
		if phase == "Lobby" then
			outLamps = {}
			if cinematic then
				Effects.ResetCinematic()
			else
				Effects.ApplyLights()
			end
		end
		Effects.UpdateClocks()
	end)
	ctx.State:GetAttributeChangedSignal("Minutes"):Connect(Effects.UpdateClocks)
	Effects.ApplyLights()
	Effects.UpdateClocks()
	Effects.Ready = true

	-- сломанные лампы мигают сами
	task.spawn(function()
		while true do
			task.wait(math.random(5, 30) / 100)
			for _, l in ipairs(lamps) do
				if l.Broken and not flickering[l] and lampShouldBeOn(l) then
					setLamp(l, math.random() < 0.82)
				end
			end
		end
	end)
	task.spawn(signFlickerLoop)

	-- следим за Покупателем 10 раз в секунду, цвет — 5 раз в секунду
	local acc, gacc = 0, 0
	RunService.Heartbeat:Connect(function(dt)
		acc = acc + dt
		gacc = gacc + dt
		if acc >= 0.1 then
			acc = 0
			local ok, err = pcall(watchMonster)
			if not ok then
				warn(err)
			end
		end
		if gacc >= 0.2 then
			gacc = 0
			updateGrade()
		end
	end)
	RENDER:Connect(function(dt)
		local target = 0.55 - threatLevel * 0.45 - (powerOn() and 0 or 0.15) - vignetteBoost
		target = math.clamp(target, 0, 1)
		vignette.ImageTransparency = vignette.ImageTransparency + (target - vignette.ImageTransparency) * math.min(1, dt * 3)
	end)
end

return Effects
