-- Cinematic: вступительная кат-сцена NIGHT SHIFT (~100 секунд). Каждый игрок смотрит её у себя.
-- Сервер (ShiftManager) переводит смену в фазу "Intro" и шлёт Effect("Intro"); клиент проигрывает
-- сцену и отвечает Action("IntroDone"). Кнопка «Пропустить» отвечает сразу.
-- Всё, что двигается в сцене (машина, герой, раздвижные двери, силуэт), — локальные копии:
-- настоящие объекты карты на время сцены прячутся у этого игрока (LocalTransparencyModifier).
--
--   0–3     чёрный экран, дождь; удар молнии на миг освещает пустую улицу
--   3–10    вывеска MART 24 вплотную: капли на объективе, неон трещит и мигает
--   10–17   камера отъезжает через парковку и дорогу — магазин светится один во всей улице; дальняя молния
--   17–31   приезжает машина, фары на мокром асфальте; встаёт у входа, мотор глохнет — тишина
--   31–38   водитель выходит, закрывает дверь, стоит
--   38–46   идёт ко входу (камера сзади), двери медленно разъезжаются, камера входит следом:
--           холодный уличный свет сменяется бледным светом ламп
--   46–66   пустой магазин: кассы, ряды, холодильники, камеры под потолком
--   66–81   кабинет менеджера; записка на столе крупно
--   81–92   мониторы видеонаблюдения; вход крупно — за стеклом стоит силуэт; помехи — его нет
--   92–100  электронные часы 23:59 → 00:00, сигнал; название NIGHT SHIFT зажигается буква за буквой, как неон
--
-- «Оператор» (v8): лёгкая ручная тряска у каждого плана, размытие при быстром движении камеры, плавная
-- перефокусировка, вспышки молний с громом, капли дождя на объективе снаружи, плёночное зерно.
local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Texts = require(Shared:WaitForChild("Texts"))
local Models = require(Shared:WaitForChild("Models"))

local Cinematic = {}

local ctx, UI
local playing = false
local cancelled = false
local startClock = 0
local shot = nil
local folder = nil
local hidden = {}
local feeds = {}
local actor = nil
local car = nil
local doors = nil
local savedDof = nil
local savedNames = nil
local gui, black, barTop, barBottom, titleHolder, titleLabel, subLabel, titleLine, titleScale, skipButton, waitLabel
local lensLayer, grainLabel
local rig = { Shake = 0, Freq = 0.4 } -- ручная тряска: амплитуда (градусы) и частота
local prevCam = nil
local blurFx, flashFx = nil, nil
local lensOn = false
local drops = {}
local SKIP = "NS_INTRO_SKIP"
local frameConn = nil

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude

local function now()
	return os.clock() - startClock
end

-------------------------------------------------------------------------------
-- Плавные кривые
-------------------------------------------------------------------------------
local function clamp01(u)
	return math.clamp(u, 0, 1)
end

local function easeSine(u)
	return 0.5 - 0.5 * math.cos(math.pi * clamp01(u))
end

local function catmull(p0, p1, p2, p3, t)
	local t2 = t * t
	local t3 = t2 * t
	return 0.5 * ((2 * p1) + (p2 - p0) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (3 * p1 - p0 - 3 * p2 + p3) * t3)
end

-- Точка на сплайне Катмулла — Рома через точки list (a = 0..1)
local function spline(list, a)
	local n = #list
	if n == 1 then
		return list[1]
	end
	local x = clamp01(a) * (n - 1)
	local i = math.min(math.floor(x) + 1, n - 1)
	local u = x - (i - 1)
	return catmull(list[math.max(1, i - 1)], list[i], list[i + 1], list[math.min(n, i + 2)], u)
end

-- Проезд камеры: позиции и точки, куда она смотрит; плавный разгон и торможение
local function track(positions, targets, fovFrom, fovTo)
	return function(u)
		local a = easeSine(u)
		return CFrame.lookAt(spline(positions, a), spline(targets, a)), fovFrom + (fovTo - fovFrom) * a
	end
end

local function lerpAngle(a, b, k)
	local d = (b - a + math.pi) % (2 * math.pi) - math.pi
	return a + d * k
end

-- Ждать до момента t сцены (или выйти, если сцену пропустили)
local function at(t)
	while now() < t do
		if cancelled then
			error(SKIP, 0)
		end
		RunService.Heartbeat:Wait()
	end
	if cancelled then
		error(SKIP, 0)
	end
end

local function setShot(duration, eval)
	shot = { Start = now(), Dur = duration, Eval = eval }
end

-- Ручная камера: shake — амплитуда покачивания в градусах, freq — как быстро она «дышит»
local function setRig(shake, freq)
	rig.Shake = shake or 0
	rig.Freq = freq or 0.4
end

-------------------------------------------------------------------------------
-- Спрятать настоящие объекты у этого игрока
-------------------------------------------------------------------------------
local function hideModel(model)
	local list = model:GetDescendants()
	table.insert(list, model)
	for _, d in ipairs(list) do
		if d:IsA("BasePart") or d:IsA("Decal") then
			d.LocalTransparencyModifier = 1
			hidden[d] = true
		end
	end
end

local function unhideModel(model)
	local list = model:GetDescendants()
	table.insert(list, model)
	for _, d in ipairs(list) do
		if hidden[d] then
			d.LocalTransparencyModifier = 0
			hidden[d] = nil
		end
	end
end

local function hideCharacters(on)
	for _, p in ipairs(Players:GetPlayers()) do
		local ch = p.Character
		if ch then
			for _, d in ipairs(ch:GetDescendants()) do
				if d:IsA("BasePart") or d:IsA("Decal") then
					d.LocalTransparencyModifier = on and 1 or 0
				end
			end
		end
	end
end

local function groundAt(pos)
	local hit = workspace:Raycast(Vector3.new(pos.X, 5, pos.Z), Vector3.new(0, -10, 0), groundParams)
	if hit then
		return hit.Position.Y, hit.Material
	end
	return 0, Enum.Material.Concrete
end

local function updateGroundFilter()
	local list = { folder }
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	if car and car.Real then
		table.insert(list, car.Real)
	end
	groundParams.FilterDescendantsInstances = list
end

-------------------------------------------------------------------------------
-- Герой: копия персонажа игрока с анимациями ходьбы и ожидания
-------------------------------------------------------------------------------
local function animId(ch, folderName, childName, fallback)
	local animate = ch:FindFirstChild("Animate")
	local f = animate and animate:FindFirstChild(folderName)
	local a = f and (f:FindFirstChild(childName) or f:FindFirstChildOfClass("Animation"))
	if a and a:IsA("Animation") and a.AnimationId ~= "" then
		return a.AnimationId
	end
	return fallback
end

local function makeActor(pos, yaw)
	local a = {
		Pos = pos,
		Yaw = yaw,
		Forward = Vector3.new(-math.sin(yaw), 0, -math.cos(yaw)),
		Path = {},
		Speed = 5.5,
		Moving = false,
		StepDist = 0,
		Height = 3,
		AnimScale = 0.156,
		Lift = 0,
	}
	local ch = ctx.Player.Character
	local hum0 = ch and ch:FindFirstChildOfClass("Humanoid")
	if not (ch and hum0) then
		return a
	end
	local r15 = hum0.RigType == Enum.HumanoidRigType.R15
	-- собственные анимации игры (R15); у R6 — анимации из его скрипта Animate или стандартные
	local walkId = r15 and Models.Anim.Walk or animId(ch, "walk", "WalkAnim", "rbxassetid://180426354")
	local idleId = r15 and Models.Anim.Idle or animId(ch, "idle", "Animation1", "rbxassetid://180435571")
	ch.Archivable = true
	local ok, m = pcall(function()
		return ch:Clone()
	end)
	ch.Archivable = false
	if not (ok and m) then
		return a
	end
	m.Name = "IntroActor"
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BaseScript") or d:IsA("Sound") or d:IsA("ForceField") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.LocalTransparencyModifier = 0
		elseif d:IsA("Decal") then
			d.LocalTransparencyModifier = 0
		end
	end
	local hum = m:FindFirstChildOfClass("Humanoid")
	local root = m:FindFirstChild("HumanoidRootPart")
	if not (hum and root) then
		m:Destroy()
		return a
	end
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	root.Anchored = true
	if r15 then
		a.Height = hum.HipHeight + root.Size.Y / 2
		local hs = hum:FindFirstChild("BodyHeightScale")
		a.AnimScale = 1 / (Models.Anim.WalkNatural * ((hs and hs:IsA("NumberValue") and hs.Value > 0) and hs.Value or 1))
	else
		a.Height = 3
		a.AnimScale = 1 / 14.5
	end
	m.Parent = folder
	local animator = hum:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = hum
	end
	local function load(id, priority)
		local anim = Instance.new("Animation")
		anim.AnimationId = id
		local okL, tr = pcall(function()
			return animator:LoadAnimation(anim)
		end)
		if okL and tr then
			tr.Looped = true
			tr.Priority = priority
			return tr
		end
		return nil
	end
	a.Walk = load(walkId, Enum.AnimationPriority.Movement)
	a.Idle = load(idleId, Enum.AnimationPriority.Idle)
	if a.Idle then
		a.Idle:Play(0)
	end
	a.Model = m
	a.Root = root
	return a
end

-- Идти по точкам со скоростью speed (studs/с)
local function actorGo(points, speed)
	if actor then
		actor.Path = points
		actor.Speed = speed
		actor.Face = nil
	end
end

-- Плавно поднять/опустить героя (сидит в машине → встаёт)
local function actorLift(from, to, seconds)
	if not actor then
		return
	end
	actor.Lift = from
	task.spawn(function()
		local t = 0
		while t < seconds and actor do
			t = t + RunService.Heartbeat:Wait()
			if actor then
				actor.Lift = from + (to - from) * easeSine(t / seconds)
			end
		end
	end)
end

local function actorFace(point)
	if actor then
		actor.Face = point
	end
end

local function updateActor(dt)
	if not actor then
		return
	end
	local target = actor.Path[1]
	local moving = false
	if target then
		local flat = Vector3.new(target.X - actor.Pos.X, 0, target.Z - actor.Pos.Z)
		local d = flat.Magnitude
		local stepLen = actor.Speed * dt
		if d <= stepLen or d < 0.01 then
			actor.Pos = Vector3.new(target.X, 0, target.Z)
			table.remove(actor.Path, 1)
		else
			actor.Pos = actor.Pos + flat.Unit * stepLen
			moving = true
			actor.Forward = actor.Forward:Lerp(flat.Unit, math.min(1, dt * 4)).Unit
		end
		actor.StepDist = actor.StepDist + math.min(stepLen, d)
	elseif actor.Face then
		local f = Vector3.new(actor.Face.X - actor.Pos.X, 0, actor.Face.Z - actor.Pos.Z)
		if f.Magnitude > 0.1 then
			actor.Forward = actor.Forward:Lerp(f.Unit, math.min(1, dt * 3)).Unit
		end
	end
	actor.Yaw = lerpAngle(actor.Yaw, math.atan2(-actor.Forward.X, -actor.Forward.Z), math.min(1, dt * 7))
	local gy, material = groundAt(actor.Pos)
	actor.Y = actor.Y and (actor.Y + (gy - actor.Y) * math.min(1, dt * 10)) or gy
	if actor.Model then
		actor.Model:PivotTo(CFrame.new(actor.Pos.X, actor.Y + actor.Height + actor.Lift, actor.Pos.Z) * CFrame.Angles(0, actor.Yaw, 0))
		-- шаги
		if moving and actor.StepDist >= 2.4 and not ctx.Audio.MarkerSteps(actor.Model) then
			actor.StepDist = 0
			ctx.Audio.Step(actor.Root, material, ctx.Audio.ZoneOf(actor.Pos) == "Outside", false, false)
		end
		if moving ~= actor.Moving then
			actor.Moving = moving
			if moving then
				if actor.Walk then
					actor.Walk:Play(0.25)
					actor.Walk:AdjustSpeed(actor.Speed * actor.AnimScale)
				end
				if actor.Idle then
					actor.Idle:Stop(0.3)
				end
			else
				if actor.Walk then
					actor.Walk:Stop(0.35)
				end
				if actor.Idle then
					actor.Idle:Play(0.35)
				end
			end
		elseif moving and actor.Walk then
			actor.Walk:AdjustSpeed(actor.Speed * actor.AnimScale)
		end
	end
	actor.Moving = moving
end

-------------------------------------------------------------------------------
-- Машина сотрудника (копия StaffCar) и её путь с дороги на парковку.
-- Детализированная модель: кузов на «подвеске» (клюёт носом при торможении, кренится в повороте,
-- покачивается, когда водитель выходит и хлопает дверью), колёса крутятся, передние поворачивают,
-- фары и стоп-сигналы горят по-настоящему (свет на асфальте и видимые конусы в дожде).
-------------------------------------------------------------------------------
local function carPath(spot)
	local x, z = spot.X, spot.Z
	return {
		Vector3.new(95, 0, 123.5),
		Vector3.new(40, 0, 123.5),
		Vector3.new(-4, 0, 123.2),
		Vector3.new(x + 14.5, 0, 115),
		Vector3.new(x + 2.1, 0, z + 31),
		Vector3.new(x, 0, z + 14),
		Vector3.new(x, 0, z),
	}
end

local function buildCarCurve(path)
	local pts, lens = {}, { 0 }
	local n = 240
	for i = 0, n do
		pts[i + 1] = spline(path, i / n)
	end
	for i = 2, #pts do
		lens[i] = lens[i - 1] + (pts[i] - pts[i - 1]).Magnitude
	end
	return pts, lens
end

local function curveAt(pts, lens, s)
	local total = lens[#lens]
	s = math.clamp(s, 0, total)
	local lo, hi = 1, #lens
	while hi - lo > 1 do
		local mid = math.floor((lo + hi) / 2)
		if lens[mid] <= s then
			lo = mid
		else
			hi = mid
		end
	end
	local seg = lens[hi] - lens[lo]
	local k = seg > 0 and (s - lens[lo]) / seg or 0
	local pos = pts[lo]:Lerp(pts[hi], k)
	local dir = pts[hi] - pts[lo]
	if dir.Magnitude < 1e-4 then
		dir = Vector3.new(0, 0, -1)
	end
	return pos, Vector3.new(dir.X, 0, dir.Z).Unit
end

local HEAD_ON = Color3.fromRGB(255, 246, 226)
local TAIL_ON = Color3.fromRGB(150, 8, 6)
local BRAKE_ON = Color3.fromRGB(255, 28, 18)

local function setCarLights(on, brake)
	if not car then
		return
	end
	car.LightsOn, car.Brake = on, brake
	for _, l in ipairs(car.Lamps) do
		if on then
			l.Part.Material = Enum.Material.Neon
			l.Part.Color = l.Tail and (brake and BRAKE_ON or TAIL_ON) or HEAD_ON
			if l.Part:IsA("MeshPart") then
				l.Part.TextureID = ""
			end
		else
			l.Part.Material = l.Material
			l.Part.Color = l.Color
			if l.Part:IsA("MeshPart") then
				l.Part.TextureID = l.Texture
			end
		end
	end
	for _, l in ipairs(car.Lights) do
		l.Light.Enabled = on
		if l.Beam then
			l.Beam.Enabled = on
		end
		if l.Tail then
			l.Light.Brightness = brake and 3.2 or 1.1
			l.Light.Range = brake and 12 or 7
		end
	end
end

-- Невидимая деталь-держатель света (двигается вместе с кузовом)
local function lightHolder(name, c)
	local h = Instance.new("Part")
	if c and c.Holders then
		table.insert(c.Holders, h)
	end
	h.Name = name
	h.Size = Vector3.new(0.2, 0.2, 0.2)
	h.Transparency = 1
	h.Anchored = true
	h.CanCollide = false
	h.CanQuery = false
	h.CanTouch = false
	h.CastShadow = false
	h.Parent = folder
	return h
end

-- Видимый конус света фары в дожде (плоский луч, всегда повёрнут к камере)
local function lightCone(holder, length, width, color, alpha)
	local a0 = Instance.new("Attachment")
	a0.Parent = holder
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, 0, -length)
	a1.Parent = holder
	local beam = Instance.new("Beam")
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.Width0 = 0.5
	beam.Width1 = width
	beam.FaceCamera = true
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.Segments = 12
	beam.Color = ColorSequence.new(color)
	beam.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, alpha),
		NumberSequenceKeypoint.new(0.35, alpha + (1 - alpha) * 0.45),
		NumberSequenceKeypoint.new(1, 1),
	})
	beam.Parent = holder
	return beam
end

local function makeMeshCar(m, real, c)
	c.Mesh = true
	c.YawFix = real:GetAttribute("YawFix")
	c.Fwd = c.YawFix < 0 and -1 or 1 -- перёд машины по оси X её модели
	c.Parts, c.Wheels, c.Lamps, c.Holders = {}, {}, {}, {}
	c.Pitch, c.PitchV, c.Roll, c.RollV, c.Heave, c.HeaveV = 0, 0, 0, 0, 0, 0
	c.Spin, c.Steer, c.Speed = 0, 0, 0
	local base = m:GetPivot()
	local heads, tails = {}, {}
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			local off = base:ToObjectSpace(d.CFrame)
			local role = d:GetAttribute("Role")
			if role == "Wheel" or role == "WheelFront" then
				table.insert(c.Wheels, { Part = d, Pos = off.Position, Rot = off - off.Position, Front = role == "WheelFront", R = math.max(d.Size.X, d.Size.Y) / 2 })
			else
				table.insert(c.Parts, { Part = d, Off = off })
			end
			if role == "Headlight" or role == "Taillight" then
				table.insert(c.Lamps, { Part = d, Tail = role == "Taillight", Material = d.Material, Color = d.Color, Texture = d:IsA("MeshPart") and d.TextureID or "" })
				table.insert(role == "Headlight" and heads or tails, off.Position)
			end
		end
	end
	local function centre(list, fallback)
		if #list == 0 then
			return fallback
		end
		local sum = Vector3.zero
		for _, v in ipairs(list) do
			sum = sum + v
		end
		return sum / #list
	end
	local len = real:GetAttribute("Length") or 14
	local wid = real:GetAttribute("Width") or 7
	local head = centre(heads, Vector3.new(c.Fwd * len * 0.46, 2.2, 0))
	local tail = centre(tails, Vector3.new(-c.Fwd * len * 0.46, 2.6, 0))
	local fwd = Vector3.new(c.Fwd, 0, 0)
	-- две фары: прожектор с тенями + конус в дожде; держатели крепятся к кузову
	for _, side in ipairs({ -1, 1 }) do
		local p = head + Vector3.new(c.Fwd * 0.25, 0, side * wid * 0.34)
		local holder = lightHolder("HeadBeam", c)
		local s = Instance.new("SpotLight")
		s.Face = Enum.NormalId.Front
		s.Angle = 62
		s.Range = 60
		s.Brightness = 6
		s.Color = Color3.fromRGB(255, 240, 214)
		s.Shadows = true
		s.Parent = holder
		local cone = lightCone(holder, 26, 11, Color3.fromRGB(255, 236, 205), 0.9)
		table.insert(c.Parts, { Part = holder, Off = CFrame.lookAt(p, p + fwd + Vector3.new(0, -0.09, 0)) })
		table.insert(c.Lights, { Light = s, Beam = cone })
	end
	-- общий тёплый засвет перед машиной (мокрый асфальт отражает)
	local fillHolder = lightHolder("HeadFill", c)
	local fill = Instance.new("PointLight")
	fill.Range = 16
	fill.Brightness = 0.9
	fill.Color = Color3.fromRGB(255, 232, 200)
	fill.Parent = fillHolder
	table.insert(c.Parts, { Part = fillHolder, Off = CFrame.new(head + fwd * 3 + Vector3.new(0, -0.6, 0)) })
	table.insert(c.Lights, { Light = fill })
	-- задние фонари: красный отсвет
	local tailHolder = lightHolder("TailGlow", c)
	local glow = Instance.new("PointLight")
	glow.Range = 7
	glow.Brightness = 1.1
	glow.Color = Color3.fromRGB(255, 30, 20)
	glow.Parent = tailHolder
	table.insert(c.Parts, { Part = tailHolder, Off = CFrame.new(tail - fwd * 0.9) })
	table.insert(c.Lights, { Light = glow, Tail = true })
end

local function makeCar()
	local store = workspace:FindFirstChild("Store")
	local front = store and store:FindFirstChild("Front")
	local real = front and front:FindFirstChild("StaffCar")
	if not (real and real.PrimaryPart) then
		return nil
	end
	local m = real:Clone()
	m.Name = "IntroCar"
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.LocalTransparencyModifier = 0
		end
	end
	m.Parent = folder
	hideModel(real)
	local spot = real:GetPivot().Position
	local c = { Model = m, Real = real, Body = m.PrimaryPart, BodyY = real.PrimaryPart.Position.Y, Lights = {}, Lamps = {} }
	if real:GetAttribute("YawFix") then
		makeMeshCar(m, real, c)
	else
		-- простая машина из блоков (если модель не загрузилась)
		spot = Vector3.new(-39.5, 0, 68)
		for _, name in ipairs({ "HeadL", "HeadR" }) do
			local p = m:FindFirstChild(name)
			if p then
				local s = Instance.new("SpotLight")
				s.Face = Enum.NormalId.Front
				s.Angle = 55
				s.Range = 55
				s.Brightness = 5
				s.Color = Color3.fromRGB(255, 240, 214)
				s.Shadows = true
				s.Parent = p
				table.insert(c.Lights, { Light = s })
				table.insert(c.Lamps, { Part = p, Material = p.Material, Color = p.Color, Texture = "" })
			end
		end
		for _, name in ipairs({ "TailL", "TailR" }) do
			local p = m:FindFirstChild(name)
			if p then
				local s = Instance.new("PointLight")
				s.Range = 6
				s.Brightness = 1.2
				s.Color = Color3.fromRGB(255, 30, 20)
				s.Parent = p
				table.insert(c.Lights, { Light = s, Tail = true })
				table.insert(c.Lamps, { Part = p, Tail = true, Material = p.Material, Color = p.Color, Texture = "" })
			end
		end
	end
	c.Spot = Vector3.new(spot.X, 0, spot.Z)
	c.Pts, c.Lens = buildCarCurve(carPath(c.Spot))
	c.Length = c.Lens[#c.Lens]
	c.S = 0
	return c
end

-- Толчок подвески: h — вверх/вниз, r — крен (водитель вышел, хлопнула дверь)
local function carBump(h, r)
	if car and car.Mesh then
		car.HeaveV = car.HeaveV + h
		car.RollV = car.RollV + (r or 0)
	end
end

local function spring(x, v, target, dt, k, damp)
	local a = k * (target - x) - damp * v
	v = v + a * dt
	return x + v * dt, v
end

-- Поставить машину в точку s пути (studs от начала); dt — время кадра (для подвески и колёс)
local function placeCar(s, dt)
	if not car then
		return
	end
	dt = dt or 0
	local ds = s - car.S
	car.S = s
	local pos, dir = curveAt(car.Pts, car.Lens, s)
	if not car.Mesh then
		local at = Vector3.new(pos.X, car.BodyY, pos.Z)
		car.Model:PivotTo(CFrame.lookAt(at, at + dir))
		return
	end
	-- скорость, ускорение, поворот
	local speed = dt > 0 and ds / dt or 0
	local accel = dt > 0 and (speed - car.Speed) / dt or 0
	car.Speed = speed
	car.Accel = (car.Accel or 0) + (accel - (car.Accel or 0)) * math.min(1, dt * 6)
	accel = car.Accel
	local _, ahead = curveAt(car.Pts, car.Lens, s + 6)
	local turn = math.atan2(dir:Cross(ahead).Y, dir:Dot(ahead))
	car.Steer = car.Steer + (math.clamp(turn * 1.7, -0.5, 0.5) - car.Steer) * math.min(1, dt * 6)
	local yawRate = turn * speed / 6
	if dt > 0 then
		-- кузов: клюёт носом при торможении, кренится наружу в повороте, пружинит
		local pitchTarget = -car.Fwd * math.clamp(-accel * 0.0045, -0.035, 0.035)
		local rollTarget = car.Fwd * math.clamp(yawRate * speed * 0.0016, -0.03, 0.03)
		car.Pitch, car.PitchV = spring(car.Pitch, car.PitchV, pitchTarget, dt, 70, 8)
		car.Roll, car.RollV = spring(car.Roll, car.RollV, rollTarget, dt, 80, 7)
		car.Heave, car.HeaveV = spring(car.Heave, car.HeaveV, 0, dt, 90, 7)
		car.Spin = car.Spin + ds
	end
	local base = CFrame.lookAt(pos, pos + dir) * CFrame.Angles(0, car.YawFix, 0)
	local body = base * CFrame.new(0, car.Heave, 0) * CFrame.Angles(car.Roll, 0, car.Pitch)
	for _, p in ipairs(car.Parts) do
		p.Part.CFrame = body * p.Off
	end
	for _, w in ipairs(car.Wheels) do
		local spin = -car.Fwd * car.Spin / math.max(0.3, w.R)
		local steer = w.Front and CFrame.Angles(0, car.Steer, 0) or CFrame.identity
		w.Part.CFrame = base * CFrame.new(w.Pos + Vector3.new(0, car.Heave * 0.15, 0)) * steer * CFrame.Angles(0, 0, spin) * w.Rot
	end
end

-- Каждый кадр: машина едет по пути (car.Drive: начало и длительность, плавное торможение до места),
-- подвеска дорабатывает покачивание, даже когда машина уже стоит
local function updateCar(dt)
	if not car then
		return
	end
	local s = car.S
	if car.Drive then
		local u = clamp01((now() - car.Drive.Start) / car.Drive.Dur)
		s = car.Length * (1 - (1 - u) ^ 2.1)
		if u >= 1 then
			car.Drive = nil
		end
	end
	if car.Mesh or s ~= car.S then
		placeCar(s, dt)
	end
end

-- Водительская дверь простой машины: панель и стекло на левом боку, петля спереди
local function makeCarDoor()
	if not car or car.Mesh then
		return nil
	end
	local body = car.Body
	local bcf = body.CFrame
	local half = body.Size.X / 2
	local hinge = bcf * CFrame.new(-half - 0.06, -body.Size.Y / 2, -3.1 + 0.6)
	local function part(name, size, color, material, transparency)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.Color = color
		p.Material = material
		p.Transparency = transparency or 0
		p.Reflectance = material == Enum.Material.Glass and 0.2 or 0.12
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Parent = folder
		return p
	end
	local panel = part("DoorPanel", Vector3.new(0.12, 1.8, 3.1), body.Color, Enum.Material.SmoothPlastic)
	local glass = part("DoorGlass", Vector3.new(0.1, 1.7, 2.9), Color3.fromRGB(22, 26, 32), Enum.Material.Glass, 0.15)
	local door = { Hinge = hinge, Panel = panel, Glass = glass, Angle = 0 }
	function door.Set(angle)
		door.Angle = angle
		local h = door.Hinge * CFrame.Angles(0, -math.rad(angle), 0)
		panel.CFrame = h * CFrame.new(0, 0.9, 1.55)
		glass.CFrame = h * CFrame.new(0, 2.7, 1.5)
	end
	door.Set(0)
	return door
end

local function swingDoor(door, from, to, seconds)
	if not door then
		return
	end
	task.spawn(function()
		local t = 0
		while t < seconds do
			local dt = RunService.Heartbeat:Wait()
			t = t + dt
			door.Set(from + (to - from) * easeSine(t / seconds))
		end
		door.Set(to)
	end)
end

-------------------------------------------------------------------------------
-- Раздвижные двери входа (локальные копии)
-------------------------------------------------------------------------------
local function makeDoors()
	local store = workspace:FindFirstChild("Store")
	local front = store and store:FindFirstChild("Front")
	if not front then
		return nil
	end
	local d = {}
	for _, p in ipairs(front:GetChildren()) do
		if p.Name == "AutoDoor" and p:IsA("BasePart") then
			local c = p:Clone()
			c.Anchored = true
			c.CanCollide = false
			c.CanQuery = false
			c.LocalTransparencyModifier = 0
			local left = p.Position.X < -52 or (p.Position.X == -52 and not d.Left)
			local closed = CFrame.new(left and -55 or -49, p.Position.Y, p.Position.Z)
			c.CFrame = closed
			c.Parent = folder
			hideModel(p)
			if left then
				d.Left, d.LeftClosed, d.LeftOpen, d.RealLeft = c, closed, closed * CFrame.new(-5.6, 0, 0), p
			else
				d.Right, d.RightClosed, d.RightOpen, d.RealRight = c, closed, closed * CFrame.new(5.6, 0, 0), p
			end
		end
	end
	if not (d.Left and d.Right) then
		return nil
	end
	return d
end

local function moveDoors(open, seconds)
	if not doors then
		return
	end
	local info = TweenInfo.new(seconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	TweenService:Create(doors.Left, info, { CFrame = open and doors.LeftOpen or doors.LeftClosed }):Play()
	TweenService:Create(doors.Right, info, { CFrame = open and doors.RightOpen or doors.RightClosed }):Play()
	ctx.Audio.Play("AutoDoor", Vector3.new(-52, 8, 50), 0.55, open and 0.85 or 0.95)
end

-------------------------------------------------------------------------------
-- Мониторы в кабинете: шесть «живых» картинок с камер (ViewportFrame с копией того, что видит камера)
-------------------------------------------------------------------------------
local STRIP = { "Sound", "Light", "ParticleEmitter", "ProximityPrompt", "SurfaceGui", "BillboardGui", "BaseScript", "ClickDetector" }

local function stripClone(inst)
	for _, d in ipairs(inst:GetDescendants()) do
		for _, cls in ipairs(STRIP) do
			if d:IsA(cls) then
				d:Destroy()
				break
			end
		end
	end
	for _, tag in ipairs(CollectionService:GetTags(inst)) do
		CollectionService:RemoveTag(inst, tag)
	end
end

local function cameraView(index)
	for _, v in ipairs(CollectionService:GetTagged("CCTV")) do
		if v:GetAttribute("Index") == index then
			return v
		end
	end
	return nil
end

local function buildFeeds()
	local store = workspace:FindFirstChild("Store")
	if not store then
		return
	end
	local parts = {}
	for _, d in ipairs(store:GetDescendants()) do
		if d:IsA("BasePart") and d.Transparency < 0.95 and d.Archivable then
			table.insert(parts, d)
		end
	end
	local cap = UI.IsTouch and 340 or 760
	local tanV = math.tan(math.rad(35))
	local made = 0
	for _, scr in ipairs(CollectionService:GetTagged("OfficeScreen")) do
		if cancelled then
			return
		end
		local view = cameraView(scr:GetAttribute("Camera"))
		local sg = scr:FindFirstChild("ScreenGui")
		if view and sg then
			sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
			local layer = Instance.new("Frame")
			layer.Name = "FeedLayer"
			layer.Size = UDim2.fromScale(1, 1)
			layer.BackgroundTransparency = 1
			layer.ZIndex = 2
			layer.Visible = false
			local vf = Instance.new("ViewportFrame")
			vf.Name = "Feed"
			vf.Size = UDim2.fromScale(1, 1)
			vf.BackgroundColor3 = Color3.fromRGB(10, 14, 12)
			vf.BackgroundTransparency = 0
			vf.Ambient = Color3.fromRGB(150, 156, 152)
			vf.LightColor = Color3.fromRGB(210, 220, 214)
			vf.LightDirection = Vector3.new(-0.3, -1, 0.25)
			vf.ImageColor3 = Color3.fromRGB(206, 226, 214)
			vf.ZIndex = 1
			vf.Parent = layer
			local cam = Instance.new("Camera")
			cam.CFrame = view.CFrame
			cam.FieldOfView = 70
			cam.Parent = vf
			vf.CurrentCamera = cam
			local grain = Instance.new("ImageLabel")
			grain.Name = "Grain"
			grain.Size = UDim2.new(1, 64, 1, 64)
			grain.BackgroundTransparency = 1
			grain.Image = Config.Images.CctvNoise
			grain.ImageTransparency = 0.82
			grain.ScaleType = Enum.ScaleType.Tile
			grain.TileSize = UDim2.fromOffset(64, 64)
			grain.ZIndex = 2
			grain.Parent = layer
			local stampLabel = Instance.new("TextLabel")
			stampLabel.Name = "Stamp"
			stampLabel.BackgroundTransparency = 1
			stampLabel.AnchorPoint = Vector2.new(0, 1)
			stampLabel.Position = UDim2.new(0, 8, 1, -4)
			stampLabel.Size = UDim2.new(1, -16, 0, 20)
			stampLabel.Font = Enum.Font.Code
			stampLabel.TextScaled = true
			stampLabel.TextXAlignment = Enum.TextXAlignment.Left
			stampLabel.TextColor3 = Color3.fromRGB(210, 240, 220)
			stampLabel.Text = os.date("%d.%m.%Y") .. "  23:59"
			stampLabel.ZIndex = 3
			stampLabel.Parent = layer
			layer.Parent = sg
			local title = sg:FindFirstChild("Title")
			if title then
				title.ZIndex = 3
			end
			table.insert(feeds, layer)
			-- что видит камера: детали в пирамиде обзора, крупные и близкие — первыми
			local cf = view.CFrame
			local aspect = scr.Size.X / math.max(scr.Size.Y, 0.1)
			local tanH = tanV * aspect
			local list = {}
			for _, p in ipairs(parts) do
				local rel = cf:PointToObjectSpace(p.Position)
				local depth = -rel.Z
				local r = p.Size.Magnitude / 2
				if depth > -r and depth < 80 + r then
					local dz = math.max(depth, 0.1)
					if math.abs(rel.X) < dz * tanH + r and math.abs(rel.Y) < dz * tanV + r then
						table.insert(list, { P = p, K = r / math.max(depth, 1) })
					end
				end
			end
			table.sort(list, function(a, b)
				return a.K > b.K
			end)
			for i = 1, math.min(cap, #list) do
				local ok, c = pcall(function()
					return list[i].P:Clone()
				end)
				if ok and c then
					stripClone(c)
					c.Parent = vf
				end
				made = made + 1
				if made % 120 == 0 then
					RunService.Heartbeat:Wait()
					if cancelled then
						return
					end
				end
			end
		end
	end
end

local function showFeeds(on)
	for _, layer in ipairs(feeds) do
		if layer.Parent then
			layer.Visible = on
		end
	end
end

local function removeFeeds()
	for _, layer in ipairs(feeds) do
		layer:Destroy()
	end
	feeds = {}
end

-------------------------------------------------------------------------------
-- Звук и свет сцены
-------------------------------------------------------------------------------
local function bedTo(name, volume, seconds)
	local s = ctx.Audio.Bed(name)
	if s then
		TweenService:Create(s, TweenInfo.new(seconds or 1, Enum.EasingStyle.Sine), { Volume = volume }):Play()
	end
end

-- Глубина резкости. seconds — плавная перефокусировка (как фокус-пуллер), без него — сразу
local function dof(focus, radius, far, near, seconds)
	local d = Lighting:FindFirstChildOfClass("DepthOfFieldEffect")
	if not d then
		return
	end
	if not savedDof then
		savedDof = { FocusDistance = d.FocusDistance, InFocusRadius = d.InFocusRadius, FarIntensity = d.FarIntensity, NearIntensity = d.NearIntensity }
	end
	local goal = { FocusDistance = focus, InFocusRadius = radius, FarIntensity = far, NearIntensity = near or 0 }
	if seconds and seconds > 0 then
		TweenService:Create(d, TweenInfo.new(seconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), goal):Play()
	else
		for k, v in pairs(goal) do
			d[k] = v
		end
	end
end

-- Молния: вспышка (двойная, как у настоящей) и гром — близкий сразу, дальний с задержкой
local function lightning(close)
	if not flashFx then
		return
	end
	task.spawn(function()
		local peak = close and 0.6 or 0.32
		flashFx.Brightness = peak
		task.wait(0.05)
		flashFx.Brightness = peak * 0.1
		task.wait(0.08)
		flashFx.Brightness = peak * 0.75
		TweenService:Create(flashFx, TweenInfo.new(close and 0.7 or 0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Brightness = 0 }):Play()
	end)
	task.delay(close and 0.2 or 1.3, function()
		ctx.Audio.Play(close and "ThunderClose" or "Thunder", nil, close and 0.9 or 0.7)
	end)
end

-- Капли дождя на объективе (только пока камера снаружи)
local function spawnDrop()
	local size = math.random(8, 26)
	local f = Instance.new("Frame")
	f.Name = "Drop"
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale(math.random(), math.random() * 0.9)
	f.Size = UDim2.fromOffset(size, size * (1 + math.random() * 0.25))
	f.BackgroundColor3 = Color3.fromRGB(210, 222, 236)
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	f.ZIndex = 4
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0.5, 0)
	c.Parent = f
	local st = Instance.new("UIStroke")
	st.Color = Color3.fromRGB(235, 242, 255)
	st.Thickness = 1
	st.Transparency = 1
	st.Parent = f
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(0.6, 0.9), NumberSequenceKeypoint.new(1, 0.6) })
	g.Parent = f
	f.Parent = lensLayer
	local d = { Frame = f, Stroke = st, Born = os.clock(), Life = 2.5 + math.random() * 4, Vy = 0, Run = math.random() < 0.3, Alpha = 0 }
	table.insert(drops, d)
end

local function updateDrops(dt)
	if lensOn and #drops < 34 and math.random() < dt * 5 then
		spawnDrop()
	end
	for i = #drops, 1, -1 do
		local d = drops[i]
		local age = os.clock() - d.Born
		local want = (lensOn and age < d.Life) and 1 or 0
		d.Alpha = d.Alpha + (want - d.Alpha) * math.min(1, dt * (want > 0 and 6 or 2.5))
		d.Frame.BackgroundTransparency = 1 - d.Alpha * 0.2
		d.Stroke.Transparency = 1 - d.Alpha * 0.45
		if d.Run and age > 0.8 then
			-- тяжёлая капля срывается и стекает вниз
			d.Vy = math.min(0.35, d.Vy + dt * 0.25)
			d.Frame.Position = d.Frame.Position + UDim2.fromScale(0, d.Vy * dt)
		end
		if d.Alpha < 0.02 and want == 0 then
			d.Frame:Destroy()
			table.remove(drops, i)
		end
	end
end

local function setLensRain(on)
	lensOn = on
end

local function fade(transparency, seconds)
	TweenService:Create(black, TweenInfo.new(seconds, Enum.EasingStyle.Sine), { BackgroundTransparency = transparency }):Play()
end

local function bars(on, seconds)
	local info = TweenInfo.new(seconds or 1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	TweenService:Create(barTop, info, { Size = UDim2.new(1, 0, on and 0.11 or 0, 0) }):Play()
	TweenService:Create(barBottom, info, { Size = UDim2.new(1, 0, on and 0.11 or 0, 0) }):Play()
end

local function showTitle(on, seconds)
	local info = TweenInfo.new(seconds, Enum.EasingStyle.Sine)
	TweenService:Create(titleLabel, info, { TextTransparency = on and 0 or 1 }):Play()
	TweenService:Create(subLabel, info, { TextTransparency = on and 0.15 or 1 }):Play()
	TweenService:Create(titleLine, info, { BackgroundTransparency = on and 0.2 or 1 }):Play()
	TweenService:Create(titleScale, TweenInfo.new(seconds + 2.5, Enum.EasingStyle.Sine), { Scale = on and 1 or 1.02 }):Play()
end

-- Название зажигается как неоновая вывеска: буква за буквой, с треском и миганием, затем — удар
local function titleReveal()
	local text = titleLabel.Text
	local n = utf8.len(text) or #text
	titleLabel.MaxVisibleGraphemes = 0
	titleLabel.TextTransparency = 0
	TweenService:Create(titleScale, TweenInfo.new(3.6, Enum.EasingStyle.Sine), { Scale = 1 }):Play()
	task.spawn(function()
		for i = 1, n do
			titleLabel.MaxVisibleGraphemes = i
			if i % 3 == 1 then
				ctx.Audio.Play("NeonBuzz", nil, 0.35, 0.9 + math.random() * 0.25)
			end
			task.wait(0.055)
		end
		titleLabel.MaxVisibleGraphemes = -1
		-- пара «неоновых» морганий
		for _ = 1, 2 do
			titleLabel.TextTransparency = 0.7
			task.wait(0.05)
			titleLabel.TextTransparency = 0
			task.wait(0.09)
		end
		ctx.Audio.Play("DarkHit", nil, 0.55)
		local info = TweenInfo.new(0.9, Enum.EasingStyle.Sine)
		TweenService:Create(subLabel, info, { TextTransparency = 0.15 }):Play()
		TweenService:Create(titleLine, info, { BackgroundTransparency = 0.2 }):Play()
	end)
end

-------------------------------------------------------------------------------
-- Сцена
-------------------------------------------------------------------------------
local function timeline()
	local cam = workspace.CurrentCamera
	local store = workspace:FindFirstChild("Store")
	local rooms = store and store:FindFirstChild("Rooms")
	local office = rooms and rooms:FindFirstChild("Office")
	local note = office and office:FindFirstChild("Note")
	local notePos = note and note.Position or Vector3.new(26, 2.815, -55.4)
	local noteUp = note and note.CFrame.UpVector or Vector3.new(0, 0, -1)
	ctx.Effects.SetClock(-3) -- 23:57

	-- 1. ВЫВЕСКА И УЛИЦА -----------------------------------------------------
	-- чернота, дождь; удар молнии на долю секунды показывает пустую улицу
	setShot(3.2, track({ Vector3.new(-26, 9.5, 132), Vector3.new(-27, 9.3, 130) }, { Vector3.new(-48, 8, 50), Vector3.new(-48.5, 8, 50) }, 50, 49))
	at(1.5)
	lightning(true)
	black.BackgroundTransparency = 0.35
	task.delay(0.09, function()
		black.BackgroundTransparency = 0.9
	end)
	task.delay(0.2, function()
		black.BackgroundTransparency = 0
	end)
	-- вывеска вплотную: телевик, капли на объективе, неон трещит и мигает
	at(3.0)
	setLensRain(true)
	setRig(0.22, 0.5)
	dof(7.2, 2.2, 0.45, 0.7)
	setShot(7.2, track({
		Vector3.new(-40.8, 14.3, 58.6),
		Vector3.new(-42.6, 14.5, 58.2),
		Vector3.new(-44.4, 14.7, 57.9),
	}, {
		Vector3.new(-44.5, 15.0, 51.8),
		Vector3.new(-46.6, 15.1, 51.8),
		Vector3.new(-48.8, 15.2, 51.8),
	}, 34, 31))
	fade(1, 2.2)
	bars(true, 2.5)
	at(6.1)
	ctx.Effects.SignFlicker(5)
	ctx.Audio.Play("NeonBuzz", Vector3.new(-46, 15, 52.5), 1)
	at(7.4)
	ctx.Audio.Play("NeonBuzz", Vector3.new(-46, 15, 52.5), 0.6, 0.85)
	-- отъезд: через парковку и дорогу — магазин светится один во всей улице
	at(10.2)
	setRig(0.15, 0.35)
	dof(88, 60, 0.18, 0.15, 7.2) -- фокус едет вместе с камерой: вывеска остаётся резкой
	setShot(7.2, track({
		Vector3.new(-44.4, 14.7, 57.9),
		Vector3.new(-41, 12.6, 70),
		Vector3.new(-35, 9.2, 96),
		Vector3.new(-30.5, 6.4, 124),
		Vector3.new(-28, 5.6, 138),
	}, {
		Vector3.new(-48.8, 15.2, 51.8),
		Vector3.new(-48, 12.5, 50),
		Vector3.new(-48, 9.4, 50),
		Vector3.new(-50.5, 7.8, 50),
		Vector3.new(-51, 7.3, 50),
	}, 31, 46))
	at(14.6)
	lightning(false)

	-- 2. МАШИНА ПРИЕЗЖАЕТ -----------------------------------------------------
	at(16.2)
	if car then
		ctx.Audio.Play("CarArrive", car.Body, 0.75)
	end
	at(17)
	setRig(0.28, 0.45)
	dof(22, 18, 0.2, 0, 1.2)
	local carStart = 17.5
	local carDur = 12
	local lookSm = Vector3.new(60, 2, 123.5)
	local camFrom, camTo = Vector3.new(-19.5, 2.7, 99), Vector3.new(-23.8, 3.1, 93)
	setShot(14, function(u, _, dt)
		local p = camFrom:Lerp(camTo, easeSine(u))
		local target = (car and car.Body.Position or Vector3.new(-39.5, 1.6, 70)) + Vector3.new(0, 0.4, 0)
		lookSm = lookSm:Lerp(target, math.min(1, dt * 2.2))
		return CFrame.lookAt(p, lookSm), 50 - 4 * easeSine(u)
	end)
	if car then
		setCarLights(true, false)
		car.Drive = { Start = carStart, Dur = carDur }
		-- стоп-сигналы: водитель тормозит перед поворотом на парковку и до самой остановки
		task.spawn(function()
			while now() < carStart + carDur + 0.2 and not cancelled and car do
				local u = clamp01((now() - carStart) / carDur)
				local brake = u > 0.55 and u < 1
				if brake ~= car.Brake then
					setCarLights(true, brake)
				end
				RunService.Heartbeat:Wait()
			end
			if car then
				setCarLights(true, false)
			end
		end)
	end
	at(29.8)
	-- мотор заглох, фары гаснут, несколько секунд тишины
	if car then
		setCarLights(false, false)
	end
	at(30.4)
	lightning(false)

	-- 3. ВОДИТЕЛЬ ВЫХОДИТ -----------------------------------------------------
	at(31)
	setRig(0.32, 0.5)
	dof(14, 8, 0.3, 0.1)
	local carDoor = makeCarDoor()
	if car and car.Mesh then
		-- Детализированная машина: камера с пассажирской стороны, водитель выходит за кузовом
		-- (дверь не видно, слышно), машина покачивается, когда он выходит и хлопает дверью
		local sp = car.Spot
		local doorAt = Vector3.new(sp.X - 3.6, 2.6, sp.Z - 0.2)
		actor = makeActor(Vector3.new(sp.X - 4.6, 0, sp.Z + 0.3), math.rad(90))
		actor.Lift = -2.4 -- пригнулся в проёме двери
		updateGroundFilter()
		setShot(7.5, track(
			{ Vector3.new(sp.X + 11.2, 3.7, sp.Z + 12.4), Vector3.new(sp.X + 9.6, 4.1, sp.Z + 10.2), Vector3.new(sp.X + 8.4, 4.5, sp.Z + 8.6) },
			{ Vector3.new(sp.X - 3.4, 3.2, sp.Z - 0.4), Vector3.new(sp.X - 4.4, 3.7, sp.Z + 0.2), Vector3.new(sp.X - 5.6, 4.0, sp.Z + 1.2) },
			40, 37))
		at(31.6)
		ctx.Audio.Play("CarDoorOpen", doorAt, 0.9)
		carBump(-0.05, 0.05)
		at(32.1)
		actorLift(-2.4, 0, 1.4)
		carBump(0.12, -0.06) -- вес ушёл из машины
		at(32.3)
		actorGo({ Vector3.new(sp.X - 5.4, 0, sp.Z + 1.2), Vector3.new(sp.X - 6.4, 0, sp.Z + 2.9) }, 2.4)
		at(34.0)
		actorFace(Vector3.new(sp.X - 3.4, 0, sp.Z))
		at(35.1)
		ctx.Audio.Play("CarDoorClose", doorAt, 1)
		carBump(-0.1, 0.09)
		at(35.8)
		actorFace(Vector3.new(-52, 0, 50)) -- смотрит на магазин
	else
		actor = makeActor(Vector3.new(-41.3, 0, 67.4), math.rad(90))
		actor.Lift = -1.7 -- сидит за рулём
		updateGroundFilter()
		setShot(7.5, track({ Vector3.new(-50.8, 4.5, 80.6), Vector3.new(-49.6, 4.2, 77.6) }, { Vector3.new(-43.4, 3.1, 67.6), Vector3.new(-44.8, 3.5, 67.6) }, 42, 40))
		at(31.6)
		swingDoor(carDoor, 0, 68, 1.2)
		ctx.Audio.Play("CarDoorOpen", Vector3.new(-42.6, 2.5, 66.5), 0.9)
		at(32.1)
		actorLift(-1.7, 0, 1.3)
		at(32.3)
		actorGo({ Vector3.new(-43.9, 0, 67.9), Vector3.new(-45.2, 0, 70.1) }, 2.4)
		at(34.0)
		actorFace(Vector3.new(-42.6, 0, 67.2))
		at(34.6)
		swingDoor(carDoor, 68, 0, 0.55)
		at(35.1)
		ctx.Audio.Play("CarDoorClose", Vector3.new(-42.6, 2.5, 66.5), 1)
		at(35.8)
		actorFace(Vector3.new(-52, 0, 50)) -- смотрит на магазин
	end

	-- 4. К ВХОДУ И ВНУТРЬ (камера идёт сзади) ---------------------------------
	at(37.2)
	lightning(true)
	at(38.5)
	setRig(0.55, 0.9) -- оператор идёт следом — камера покачивается сильнее
	dof(8, 6, 0.25, 0, 1)
	actorGo({ Vector3.new(-47.2, 0, 64), Vector3.new(-50.6, 0, 57.8), Vector3.new(-52, 0, 53.6) }, 5.6)
	local followPos = nil
	setShot(8, function(_, _, dt)
		local root = actor and Vector3.new(actor.Pos.X, (actor.Y or 0) + 3, actor.Pos.Z) or Vector3.new(-52, 3, 55)
		local fwd = actor and actor.Forward or Vector3.new(0, 0, -1)
		local desired = root - fwd * 7.2 + Vector3.new(0, 2.2, 0)
		followPos = followPos and followPos:Lerp(desired, math.min(1, dt * 2.2)) or desired
		return CFrame.lookAt(followPos, root + fwd * 6 + Vector3.new(0, 0.5, 0)), 50
	end)
	at(40.4)
	moveDoors(true, 2.8)
	setLensRain(false) -- под козырьком капли на объективе высыхают
	ctx.Audio.Play("DoorChime", Vector3.new(-52, 8, 46), 0.4)
	at(42.6)
	actorGo({
		Vector3.new(-52, 0, 47),
		Vector3.new(-52.6, 0, 41),
		Vector3.new(-56, 0, 34),
		Vector3.new(-57.6, 0, 27),
		Vector3.new(-57.6, 0, 12),
		Vector3.new(-57.6, 0, -2),
	}, 5.4)
	ctx.Effects.SetGradeTime(3.2)

	-- 5. ПУСТОЙ МАГАЗИН -------------------------------------------------------
	at(46.2)
	setRig(0.18, 0.35)
	dof(26, 22, 0.15, 0, 1.5)
	local p0 = cam.CFrame.Position
	local l0 = p0 + cam.CFrame.LookVector * 10
	setShot(10.5, track({
		p0,
		Vector3.new(-46, 6.4, 44.4),
		Vector3.new(-38, 7.6, 44.7),
		Vector3.new(-29.5, 8.4, 45.2),
	}, {
		l0,
		Vector3.new(-42, 3.4, 33),
		Vector3.new(-24, 3.2, 26),
		Vector3.new(-5, 3.6, 16),
	}, 50, 56))
	at(48.5)
	moveDoors(false, 2.4)
	at(51.5)
	-- машина и двери снова настоящие (они стоят там же, где копии)
	if doors then
		unhideModel(doors.RealLeft)
		unhideModel(doors.RealRight)
		doors.Left:Destroy()
		doors.Right:Destroy()
		doors = nil
	end
	if car then
		unhideModel(car.Real)
		if carDoor then
			carDoor.Panel:Destroy()
			carDoor.Glass:Destroy()
		end
		car.Model:Destroy()
		for _, h in ipairs(car.Holders or {}) do
			h:Destroy()
		end
		car = nil
	end
	at(52.4)
	-- лампа над рядом коротко мигает
	ctx.Effects.Flicker({ Zone = "Floor", Center = Vector3.new(-24, 0, 24), Radius = 9, Duration = 1.1 })
	ctx.Audio.Play("FluorFlicker", Vector3.new(-24, 13, 24), 0.7)
	at(56.7)
	ctx.Effects.SetGradeTime(1.2)
	setRig(0.15, 0.3)
	dof(18, 14, 0.2, 0, 1)
	if actor and actor.Model then
		actor.Model:Destroy()
	end
	actor = nil
	-- вдоль холодильников; заодно готовим картинки для мониторов в кабинете
	setShot(9.3, track({ Vector3.new(-20, 5.0, -4.6), Vector3.new(-5, 5.1, -4.8), Vector3.new(10, 5.2, -5.0) }, { Vector3.new(-5, 3.6, -11), Vector3.new(10, 3.6, -11.2), Vector3.new(26, 3.6, -11.5) }, 55, 52))
	task.spawn(buildFeeds)

	-- 6. КАБИНЕТ МЕНЕДЖЕРА ----------------------------------------------------
	at(66)
	setRig(0.2, 0.35)
	ctx.Effects.SetClock(-2) -- 23:58
	bedTo("TensionDrone", 0.12, 4)
	dof(14, 10, 0.18, 0)
	setShot(4.8, track({ Vector3.new(18, 7.0, -62.2), Vector3.new(20, 6.5, -59.7) }, { Vector3.new(30.5, 4.6, -45), Vector3.new(29.5, 4.2, -46) }, 54, 50))
	at(70.8)
	-- записка крупно (камера над столом, текст читается); фокус «доезжает» до текста
	setRig(0.12, 0.3)
	dof(1.9, 0.9, 0.45, 0.1, 0.9)
	local noteFrom = notePos + Vector3.new(0, 2.6, 0) - noteUp * 0.46
	local noteTo = notePos + Vector3.new(0, 1.98, 0) - noteUp * 0.34
	setShot(10.2, function(u)
		local a = easeSine(u)
		local p = noteFrom:Lerp(noteTo, a)
		return CFrame.lookAt(p, notePos, noteUp), 40
	end)

	-- 7. МОНИТОРЫ ------------------------------------------------------------
	at(81)
	setRig(0.12, 0.3)
	ctx.Effects.SetClock(-1) -- 23:59
	showFeeds(true)
	bedTo("TensionDrone", 0.22, 3)
	dof(7.5, 3.5, 0.3, 0)
	setShot(4.2, track({ Vector3.new(31.0, 5.9, -51.6), Vector3.new(31.8, 5.9, -51.5) }, { Vector3.new(38.5, 5.75, -51.4), Vector3.new(38.5, 5.8, -51.4) }, 49, 47))
	at(85.2)
	-- наезд на экран 1 «ГЛАВНЫЙ ВХОД»
	setShot(1.4, track({ Vector3.new(31.8, 5.9, -51.5), Vector3.new(34.6, 6.6, -54.2), Vector3.new(36.25, 6.95, -55.0) }, { Vector3.new(38.5, 5.8, -51.4), Vector3.new(38.4, 6.6, -54.4), Vector3.new(38.23, 6.95, -55.0) }, 47, 40))
	at(86.6)
	-- камера 1 на весь экран: за стеклом входа стоит силуэт (камера наблюдения неподвижна)
	setRig(0, 0.3)
	local view = ctx.Cameras.ShowFeed(1, "23:59")
	bars(false, 0.15)
	dof(40, 40, 0, 0)
	ctx.Audio.SetStatic(true)
	local sil = ctx.Effects.Silhouette(CFrame.lookAt(Vector3.new(-51.4, 0.3, 54.6), Vector3.new(-51.4, 0.3, 30)), folder)
	local viewCF = view and view.CFrame or CFrame.lookAt(Vector3.new(-38, 12.5, 33), Vector3.new(-52, 4.5, 50))
	setShot(5.6, function(u)
		return viewCF, 70 - 5 * easeSine(u)
	end)
	ctx.Audio.Play("Riser", nil, 0.35)
	bedTo("TensionDrone", 0.38, 2.5)
	at(89.4)
	ctx.Cameras.Glitch(0.7)
	ctx.Audio.Play("TvGlitch", nil, 0.6)
	at(90.0)
	ctx.Cameras.SignalLost(true)
	ctx.Audio.Play("Static", nil, 0.7)
	at(90.9)
	if sil then
		sil:Destroy()
	end
	ctx.Cameras.SignalLost(false)
	ctx.Cameras.Burst(0.6)
	at(92.2)
	ctx.Cameras.HideFeed()
	bars(true, 0.3)
	ctx.Audio.SetStatic(false)
	bedTo("TensionDrone", 0.16, 3)

	-- 8. ЧАСЫ 23:59 → 00:00 И НАЗВАНИЕ ----------------------------------------
	setRig(0.08, 0.3)
	dof(1.85, 0.75, 0.5, 0.1)
	local clockPos = Vector3.new(24.6, 3.15, -54.5)
	setShot(3.1, track({ Vector3.new(24.75, 3.36, -52.55), Vector3.new(24.65, 3.3, -52.75) }, { clockPos, clockPos }, 32, 31))
	at(95.3)
	ctx.Effects.SetClock(0) -- 00:00
	ctx.Audio.Play("ClockBeep", Vector3.new(24.6, 3.2, -54.3), 1)
	at(95.6)
	dof(9, 7, 0.25, 0)
	setShot(4.4, track({ Vector3.new(24.65, 3.3, -52.75), Vector3.new(24.8, 4.4, -49.5), Vector3.new(25, 5.4, -46.2) }, { clockPos, Vector3.new(25, 3.3, -55), Vector3.new(25.5, 3.4, -56) }, 31, 50))
	at(96.4)
	titleReveal()
	bedTo("TensionDrone", 0, 3.5)
	at(98.6)
	showTitle(false, 1.1)
	at(99.2)
	fade(0, 0.9)
	at(100.2)
end

-------------------------------------------------------------------------------
-- Начало и конец
-------------------------------------------------------------------------------
local function buildGui()
	gui = UI.new("ScreenGui", {
		Name = "NightIntro",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 40,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Enabled = false,
	}, ctx.Player:WaitForChild("PlayerGui"))
	barTop = UI.new("Frame", { Name = "BarTop", Size = UDim2.new(1, 0, 0, 0), BackgroundColor3 = Color3.new(0, 0, 0), ZIndex = 5 }, gui)
	barBottom = UI.new("Frame", { Name = "BarBottom", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 0), BackgroundColor3 = Color3.new(0, 0, 0), ZIndex = 5 }, gui)
	-- капли на объективе и плёночное зерно (под полосами кадра)
	lensLayer = UI.new("Frame", { Name = "Lens", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 4 }, gui)
	grainLabel = UI.new("ImageLabel", {
		Name = "Grain",
		Size = UDim2.new(1, 128, 1, 128),
		BackgroundTransparency = 1,
		Image = Config.Images.CctvNoise,
		ImageTransparency = 0.94,
		ScaleType = Enum.ScaleType.Tile,
		TileSize = UDim2.fromOffset(128, 128),
		ZIndex = 4,
	}, gui)
	titleHolder = UI.new("Frame", {
		Name = "Title",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.47),
		Size = UDim2.fromOffset(760, 170),
		BackgroundTransparency = 1,
		ZIndex = 6,
	}, gui)
	UI.scaled(titleHolder)
	local inner = UI.new("Frame", { Name = "Inner", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 6 }, titleHolder)
	titleScale = UI.new("UIScale", { Scale = 1.02 }, inner)
	titleHolder = inner
	titleLabel = UI.text(Texts.IntroTitle, {
		Size = UDim2.new(1, 0, 0, 96),
		TextSize = 88,
		Font = Enum.Font.GothamBlack,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = Color3.fromRGB(240, 240, 236),
		TextTransparency = 1,
		ZIndex = 6,
	}, titleHolder)
	titleLine = UI.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 106),
		Size = UDim2.fromOffset(140, 3),
		BackgroundColor3 = UI.Colors.Accent,
		BackgroundTransparency = 1,
		ZIndex = 6,
	}, titleHolder)
	subLabel = UI.text(Texts.IntroSubtitle, {
		Position = UDim2.fromOffset(0, 122),
		Size = UDim2.new(1, 0, 0, 30),
		TextSize = 24,
		Font = Enum.Font.GothamMedium,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = Color3.fromRGB(200, 204, 210),
		TextTransparency = 1,
		ZIndex = 6,
	}, titleHolder)
	-- Modal: пока идёт сцена, курсор мыши свободен (можно нажать «Пропустить»)
	skipButton = UI.button("Пропустить", {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -24, 1, -20),
		Size = UDim2.fromOffset(170, 40),
		TextSize = 15,
		BackgroundColor3 = Color3.fromRGB(12, 14, 18),
		BackgroundTransparency = 0.35,
		TextColor3 = Color3.fromRGB(220, 220, 220),
		Modal = true,
		ZIndex = 8,
		Visible = false,
	}, gui, function()
		cancelled = true
	end)
	UI.scaled(skipButton)
	waitLabel = UI.text("Ждём остальных сотрудников…", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(600, 40),
		TextSize = 20,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = Color3.fromRGB(200, 200, 200),
		Visible = false,
		ZIndex = 11,
	}, gui)
	UI.scaled(waitLabel)
	black = UI.new("Frame", { Name = "Black", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0, ZIndex = 10 }, gui)
end

local function cleanup()
	pcall(function()
		RunService:UnbindFromRenderStep("NS_Cinematic")
	end)
	if blurFx then
		blurFx:Destroy()
		blurFx = nil
	end
	if flashFx then
		flashFx:Destroy()
		flashFx = nil
	end
	lensOn = false
	for _, d in ipairs(drops) do
		d.Frame:Destroy()
	end
	drops = {}
	prevCam = nil
	setRig(0, 0.4)
	if frameConn then
		frameConn:Disconnect()
		frameConn = nil
	end
	shot = nil
	if actor and actor.Model then
		actor.Model:Destroy()
	end
	actor = nil
	car = nil
	doors = nil
	for d in pairs(hidden) do
		if d.Parent then
			d.LocalTransparencyModifier = 0
		end
	end
	hidden = {}
	if folder then
		folder:Destroy()
		folder = nil
	end
	removeFeeds()
	hideCharacters(false)
	if savedNames then
		local names = savedNames
		pcall(function()
			ctx.Player.NameDisplayDistance = names.Name
			ctx.Player.HealthDisplayDistance = names.Health
		end)
		savedNames = nil
	end
	local d = Lighting:FindFirstChildOfClass("DepthOfFieldEffect")
	if d and savedDof then
		for k, v in pairs(savedDof) do
			d[k] = v
		end
	end
	savedDof = nil
	ctx.Cameras.HideFeed()
	ctx.Effects.SetClock(nil)
	ctx.Effects.SetGradeTime(1.2)
	ctx.Effects.SetVignetteBoost(0)
	ctx.Effects.SetCinematic(false)
	ctx.Audio.SetStatic(false)
	ctx.Audio.SetCinematic(false)
	ProximityPromptService.Enabled = true
end

-- Перед ночами 2–5: короткий титр на чёрном экране — «НОЧЬ N» и название ночи.
-- Чем дальше ночь, тем тяжелее звук; в ночи 4–5 надпись на миг сбивается в «КАССА 0»
local function nightCard(data)
	local n = math.clamp(data.Night or 2, 1, Config.NightCount)
	local info = Texts.Nights[n]
	titleLabel.Text = "НОЧЬ " .. n
	subLabel.Text = info and string.format("«%s»", info.Title) or ""
	if n >= 3 then
		ctx.Audio.Play("Riser", nil, 0.35 + n * 0.05)
	end
	at(0.6)
	ctx.Audio.Play(n >= 4 and "DarkHit" or "ClockBeep", nil, n >= 4 and 0.8 or 0.6)
	showTitle(true, 1.3)
	at(3.4)
	if n >= 4 then
		for _ = 1, 2 do
			titleLabel.Text = "КАССА 0"
			titleLabel.TextColor3 = UI.Colors.Accent
			ctx.Audio.Play("TvGlitch", nil, 0.5)
			task.wait(0.07)
			titleLabel.Text = "НОЧЬ " .. n
			titleLabel.TextColor3 = Color3.fromRGB(240, 240, 236)
			task.wait(0.16)
		end
	end
	at(5.6)
	showTitle(false, 1.1)
	at(6.9)
end

function Cinematic.IsPlaying()
	return playing
end

function Cinematic.Play(data)
	if playing then
		return
	end
	playing = true
	cancelled = false
	task.spawn(function()
		-- магазин и эффекты должны быть готовы
		local waitStart = os.clock()
		while not (workspace:GetAttribute("StoreReady") and ctx.Effects.Ready) and os.clock() - waitStart < 15 do
			task.wait(0.1)
		end
		ctx.IntroPlaying = true
		ctx.HUD.Refresh()
		ctx.HUD.CloseModals()
		if ctx.Cameras.IsOpen() then
			ctx.Cameras.Close()
		end
		ctx.HUD.SetMode("Hidden")
		ctx.Controls.SetEnabled(false)
		ctx.Controls.SetButtonsVisible(false)
		ctx.CameraLocked = true
		ctx.Effects.SetCinematic(true)
		ctx.Effects.SetVignetteBoost(0.12)
		ctx.Audio.SetCinematic(true)
		bedTo("Music", 0, 1.5)
		bedTo("TensionDrone", 0, 1.5)
		-- эффекты «оператора»: размытие движения и вспышки молний (только у этого игрока)
		blurFx = Instance.new("BlurEffect")
		blurFx.Name = "NS_CineBlur"
		blurFx.Size = 0
		blurFx.Parent = Lighting
		flashFx = Instance.new("ColorCorrectionEffect")
		flashFx.Name = "NS_Lightning"
		flashFx.TintColor = Color3.fromRGB(214, 226, 255)
		flashFx.Brightness = 0
		flashFx.Parent = Lighting
		prevCam = nil
		setRig(0, 0.4)
		grainLabel.Visible = not (type(data) == "table" and data.Short == true)
		ProximityPromptService.Enabled = false
		pcall(function()
			savedNames = { Name = ctx.Player.NameDisplayDistance, Health = ctx.Player.HealthDisplayDistance }
			ctx.Player.NameDisplayDistance = 0
			ctx.Player.HealthDisplayDistance = 0
		end)

		black.BackgroundTransparency = 0
		local short = type(data) == "table" and data.Short == true
		titleLabel.Text = Texts.IntroTitle
		titleLabel.MaxVisibleGraphemes = -1
		titleLabel.TextColor3 = Color3.fromRGB(240, 240, 236)
		subLabel.Text = Texts.IntroSubtitle .. " · НОЧЬ 1"
		titleLabel.TextTransparency = 1
		subLabel.TextTransparency = 1
		titleLine.BackgroundTransparency = 1
		waitLabel.Visible = false
		skipButton.Visible = false
		barTop.Size = UDim2.new(1, 0, 0, 0)
		barBottom.Size = UDim2.new(1, 0, 0, 0)
		gui.Enabled = true

		folder = Instance.new("Folder")
		folder.Name = "NS_Intro"
		folder.Parent = workspace
		local cam = workspace.CurrentCamera
		cam.CameraType = Enum.CameraType.Scriptable
		local okSetup, setupErr = pcall(function()
			if short then
				return -- короткий титр: машина и двери не нужны
			end
			car = makeCar()
			if car then
				placeCar(0)
				setCarLights(false, false)
			end
			doors = makeDoors()
		end)
		if not okSetup then
			warn("[Кат-сцена] " .. tostring(setupErr))
		end
		updateGroundFilter()

		startClock = os.clock()
		local function onFrame(dt)
			if shot then
				local t = now() - shot.Start
				local ok, cf, fov = pcall(shot.Eval, clamp01(t / shot.Dur), t, dt)
				if ok and cf then
					-- ручная камера: медленное «дыхание» оператора (шум Перлина по трём осям)
					if rig.Shake > 0 then
						local a = math.rad(rig.Shake)
						local tt = now() * rig.Freq
						cf = cf * CFrame.Angles(math.noise(tt, 1.3) * a, math.noise(tt, 7.1) * a, math.noise(tt, 13.7) * a * 0.5)
					end
					-- размытие движения: сильнее, когда камера быстро поворачивается или летит (на склейке — нет)
					if blurFx and dt > 0 then
						if prevCam then
							local moved = (cf.Position - prevCam.Position).Magnitude
							local ang = math.acos(math.clamp(prevCam.LookVector:Dot(cf.LookVector), -1, 1)) / dt
							local want = math.clamp((ang - 0.3) * 5, 0, 7) + math.clamp((moved / dt - 16) * 0.12, 0, 3)
							if moved > 5 then
								want = 0
							end
							blurFx.Size = blurFx.Size + (want - blurFx.Size) * math.min(1, dt * 10)
						end
						prevCam = cf
					end
					cam.CFrame = cf
					if fov then
						cam.FieldOfView = fov
					end
				end
			end
			updateDrops(dt)
			if grainLabel then
				grainLabel.Position = UDim2.fromOffset(-math.random(0, 127), -math.random(0, 127))
			end
			local okA, errA = pcall(updateActor, dt)
			if not okA then
				warn("[Кат-сцена] " .. tostring(errA))
				actor = nil
			end
			local okC, errC = pcall(updateCar, dt)
			if not okC then
				warn("[Кат-сцена] машина: " .. tostring(errC))
				car = nil
			end
			hideCharacters(true)
			for _, layer in ipairs(feeds) do
				local g = layer.Visible and layer:FindFirstChild("Grain")
				if g then
					g.Position = UDim2.fromOffset(-math.random(0, 63), -math.random(0, 63))
				end
			end
		end
		-- камера сцены ставится сразу после стандартной камеры Roblox (в тесте на сервере — Heartbeat)
		if RunService:IsClient() then
			RunService:BindToRenderStep("NS_Cinematic", Enum.RenderPriority.Camera.Value + 1, onFrame)
		else
			frameConn = RunService.Heartbeat:Connect(onFrame)
		end
		task.delay(1.2, function()
			if playing and not cancelled then
				skipButton.Visible = true
			end
		end)
		-- если сервер начал смену раньше (кто-то очень долго грузился) — сцена заканчивается
		local phaseConn = ctx.State:GetAttributeChangedSignal("Phase"):Connect(function()
			if ctx.State:GetAttribute("Phase") ~= "Intro" then
				cancelled = true
			end
		end)

		local ok, err = pcall(short and function()
			nightCard(data)
		end or timeline)
		if not ok and err ~= SKIP then
			warn("[Кат-сцена] " .. tostring(err))
		end
		phaseConn:Disconnect()
		skipButton.Visible = false

		-- затемнение, конец сцены
		if black.BackgroundTransparency > 0.05 then
			fade(0, 0.45)
			task.wait(0.5)
		end
		black.BackgroundTransparency = 0
		titleLabel.TextTransparency = 1
		subLabel.TextTransparency = 1
		titleLine.BackgroundTransparency = 1
		cleanup()
		ctx.Remotes.Action:FireServer("IntroDone")

		-- ждём, пока сервер поставит всех в кабинет и начнёт смену
		local t = os.clock()
		while ctx.State:GetAttribute("Phase") == "Intro" and os.clock() - t < 20 do
			if os.clock() - t > 0.6 then
				waitLabel.Visible = true
			end
			task.wait(0.1)
		end
		waitLabel.Visible = false
		task.wait(0.35)

		cam.CameraType = Enum.CameraType.Custom
		local hum = ctx.Player.Character and ctx.Player.Character:FindFirstChildOfClass("Humanoid")
		if hum then
			cam.CameraSubject = hum
		end
		ctx.CameraLocked = false
		ctx.Controls.SetEnabled(true)
		ctx.Controls.SetButtonsVisible(true)
		ctx.Controls.ApplySettings()
		ctx.HUD.SetMode("Full")
		ctx.IntroPlaying = false
		ctx.HUD.Refresh()
		bars(false, 1.2)
		fade(1, 1.4)
		task.wait(1.5)
		gui.Enabled = false
		playing = false
	end)
end

function Cinematic.Init(c)
	ctx = c
	UI = ctx.UI
	buildGui()
end

return Cinematic
