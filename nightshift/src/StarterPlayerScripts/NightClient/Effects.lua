-- Effects: визуальные эффекты на клиенте.
--   • свет: без электричества лампы гаснут, табло касс выключаются; сломанные лампы мигают сами
--   • мигание ламп по событию
--   • «Покупатель»: сообщаем серверу, видим ли его (он не двигается, пока на него смотрят),
--     поворачиваем ему голову к камере, звук сердцебиения рядом
--   • видения (их видит только этот игрок), поимка, сцены концовок
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Texts = require(Shared:WaitForChild("Texts"))

local Effects = {}

local ctx
local lamps = {}
local fridgeBodies = {}
local screens = {}
local emergency = {}
local forcedOff = false
local flickering = {}
local savedLighting = {}
local cinematic = false
local signGuis = {}
local OFF_COLOR = Color3.fromRGB(70, 70, 72)

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

-------------------------------------------------------------------------------
-- Свет
-------------------------------------------------------------------------------
local function powerOn()
	return ctx.State:GetAttribute("Power") ~= false and not forcedOff
end

local function lampShouldBeOn(l)
	if not powerOn() then
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
end

local function collectLamps()
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
	local store = workspace:FindFirstChild("Store")
	if store then
		for _, name in ipairs({ "Checkouts", "Fridges" }) do
			local f = store:FindFirstChild(name)
			if f then
				for _, d in ipairs(f:GetDescendants()) do
					if d:IsA("SurfaceGui") and d.LightInfluence == 0 then
						table.insert(screens, d)
					end
				end
			end
		end
		local sec = store:FindFirstChild("Rooms") and store.Rooms:FindFirstChild("Security")
		if sec then
			for _, d in ipairs(sec:GetDescendants()) do
				if d:IsA("SurfaceGui") then
					table.insert(screens, d)
				end
			end
		end
		local front = store:FindFirstChild("Front")
		if front then
			for _, name in ipairs({ "StoreSign", "Sign24" }) do
				local p = front:FindFirstChild(name)
				local g = p and p:FindFirstChildWhichIsA("SurfaceGui")
				if g then
					table.insert(signGuis, g)
				end
			end
		end
	end
end

-- Мигание: лампы в радиусе Radius от Center (или зоны Zone) Duration секунд
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
	task.spawn(function()
		local untilT = os.clock() + (data.Duration or 3)
		while os.clock() < untilT do
			for _, l in ipairs(list) do
				setLamp(l, lampShouldBeOn(l) and math.random() < 0.45)
			end
			task.wait(math.random(4, 16) / 100)
		end
		for _, l in ipairs(list) do
			flickering[l] = nil
		end
		Effects.ApplyLights()
	end)
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
			for _, g in ipairs(signGuis) do
				g.Enabled = false
			end
			cam.CameraType = Enum.CameraType.Scriptable
			local from = CFrame.lookAt(Vector3.new(-30, 7, 104), Vector3.new(-30, 8, 50))
			local to = CFrame.lookAt(Vector3.new(-30, 6.5, 74), Vector3.new(-30, 8, 50))
			cam.CFrame = from
			ctx.HUD.Fade(1, 2.5)
			local t0 = os.clock()
			while os.clock() - t0 < 9 and cinematic do
				cam.CFrame = from:Lerp(to, (os.clock() - t0) / 9)
				RunService.RenderStepped:Wait()
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
			ctx.Audio.Play("Stinger", nil, 1)
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
	restoreLighting()
	for _, g in ipairs(signGuis) do
		g.Enabled = true
	end
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

function Effects.Init(c)
	ctx = c
	saveLighting()
	if not workspace:GetAttribute("StoreReady") then
		workspace:GetAttributeChangedSignal("StoreReady"):Wait()
	end
	collectLamps()
	ctx.State:GetAttributeChangedSignal("Power"):Connect(Effects.ApplyLights)
	ctx.State:GetAttributeChangedSignal("Phase"):Connect(function()
		if ctx.State:GetAttribute("Phase") == "Lobby" and cinematic then
			Effects.ResetCinematic()
		end
	end)
	Effects.ApplyLights()

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
	-- следим за Покупателем 10 раз в секунду
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc = acc + dt
		if acc >= 0.1 then
			acc = 0
			local ok, err = pcall(watchMonster)
			if not ok then
				warn(err)
			end
		end
	end)
end

return Effects
