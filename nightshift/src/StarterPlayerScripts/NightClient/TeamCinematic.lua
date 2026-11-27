-- TeamCinematic (v15): командная вступительная кат-сцена для 2–4 игроков. «MARKET 24 — TEAM EDITION».
--
-- 02:37, ливень и туман. Друзья едут на первую совместную смену в старой «семёрке»: за рулём первый вошедший
-- на сервер, рядом второй, сзади третий и четвёртый. Сцена подстраивается под состав (Shared/TeamLines):
-- кто сидит в машине, кто какие реплики говорит, какие планы снимаются.
--
--   1. ПОЕЗДКА      чёрный экран — дождь по крыше, дворники, мотор, тихое радио; планы в салоне: сквозь лобовое
--                   (дворники в кадре), задний ряд, над плечами задних, крупно водитель, сбоку сквозь окно
--   2. СТРАННОСТИ   радио хрипит — «Да что за радио…» — водитель выключает его; тишина, только дождь;
--                   у обочины под мигающим фонарём стоит тёмная фигура; «Эй… Вы это видели?» — «Что?» —
--                   в заднем стекле пусто — «Да ничего. Забей.»
--   3. ПРИБЫТИЕ     вывеска выплывает из тумана, машина сворачивает на мокрую парковку, медленно встаёт,
--                   ручник, мотор глохнет; реплики в салоне
--   4. ВЫХОД        двери открываются по очереди, все выходят, двери хлопают, машина покачивается; пар изо рта;
--                   «Ну и холодина…»; у каждого игрока — короткий план его собственного персонажа
--   5. ДВЕРИ        первый подходит ко входу: датчик зеленеет и пищит, створки разъезжаются; «О, хоть двери
--                   нормальные.» — «Пойдём уже.»; изнутри видно, как двери закрываются за последним
--   6. ПОДОЗРЕНИЕ   гул холодильников и ламп; «Ребят… А вам не кажется…»; в конце тёмного ряда — силуэт;
--                   снова ряд — никого; «Ладно, давайте сначала найдём инструкции.»
--   7. ФИНАЛ        камера поднимается над командой; титр MARKET 24 / NIGHT SHIFT · TEAM EDITION / 02:37 AM
--
-- Синхронизация: сервер шлёт момент старта в серверном времени (StartAt); у каждого клиента время сцены —
-- workspace:GetServerTimeNow() − StartAt, поэтому все видят одно и то же в одно время (кто загрузился позже,
-- догоняет: прошедшие реплики пропускаются). Реплики — по общему расписанию (TeamLines.Schedule): одна за
-- другой, без наложений; голос звучит из головы того, кто говорит, субтитры — с его именем.
-- «Пропустить» — у каждого своё: этот игрок встаёт на общую точку старта и ждёт, пока досмотрят остальные
-- (смена начинается, только когда досмотрели все). Ушёл игрок — его персонаж исчезает, реплики — тоже.
-- Персонажи в сцене — копии настоящих аватаров (рост приведён к салону), руки и голова — свой IK, как в
-- одиночной сцене (v14). Всё, что двигается, — локальные копии; настоящие объекты на время прячутся.
local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Models = require(Shared:WaitForChild("Models"))
local Sounds = require(Shared:WaitForChild("Sounds"))
local VoiceLines = require(Shared:WaitForChild("VoiceLines"))
local TeamLines = require(Shared:WaitForChild("TeamLines"))

local TeamCinematic = {}

local ctx, UI
local SKIP = "NS_TEAM_SKIP"
local S = { Playing = false } -- состояние сцены (сбрасывается в reset)
local G = {} -- интерфейс

local ROLE_COLOR = {
	Driver = "#E8C47A",
	Passenger = "#96C4E8",
	BackLeft = "#A8DCA0",
	BackRight = "#E2A0A0",
}

-------------------------------------------------------------------------------
-- Время и кривые
-------------------------------------------------------------------------------
local function now()
	return workspace:GetServerTimeNow() - S.StartAt
end

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

local function track(eyes, targets, fovFrom, fovTo)
	return function(u)
		local a = easeSine(u)
		return CFrame.lookAt(spline(eyes, a), spline(targets, a)), fovFrom + (fovTo - fovFrom) * a
	end
end

local function lerpAngle(a, b, k)
	local d = (b - a + math.pi) % (2 * math.pi) - math.pi
	return a + d * k
end

-- Ждать момента t сцены. Если он уже прошёл (клиент догоняет) — сразу дальше
local function at(t)
	while now() < t do
		if S.Cancelled then
			error(SKIP, 0)
		end
		RunService.Heartbeat:Wait()
	end
	if S.Cancelled then
		error(SKIP, 0)
	end
end

-- Пауза побочной задачи; false — сцену пропустили или она кончилась
local function sleep(seconds)
	local token = S.Token
	local t = now() + seconds
	while now() < t do
		if S.Cancelled or token ~= S.Token then
			return false
		end
		RunService.Heartbeat:Wait()
	end
	return not S.Cancelled and token == S.Token
end

local function after(seconds, fn)
	task.spawn(function()
		if sleep(seconds) then
			fn()
		end
	end)
end

-- still = true: камера в салоне едет вместе с машиной (её движение не размывает кадр)
local function setShot(duration, eval, still)
	S.Shot = { Start = now(), Dur = duration, Eval = eval, Still = still == true }
end

local function setRig(shake, freq)
	S.Rig.Shake = shake or 0
	S.Rig.Freq = freq or 0.4
end

-------------------------------------------------------------------------------
-- Спрятать настоящие объекты у этого игрока
-------------------------------------------------------------------------------
local function hideModel(model)
	local list = model:GetDescendants()
	table.insert(list, model)
	for _, d in ipairs(list) do
		if d:IsA("BasePart") or d:IsA("Decal") or d:IsA("SurfaceGui") then
			if d:IsA("SurfaceGui") then
				if d.Enabled then
					d.Enabled = false
					S.Hidden[d] = "Gui"
				end
			else
				d.LocalTransparencyModifier = 1
				S.Hidden[d] = true
			end
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
	for _, ch in ipairs(S.ExtraChars or {}) do
		if ch.Parent then
			for _, d in ipairs(ch:GetDescendants()) do
				if d:IsA("BasePart") or d:IsA("Decal") then
					d.LocalTransparencyModifier = on and 1 or 0
				end
			end
		end
	end
end

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude

local function updateGroundFilter()
	local list = { S.Folder }
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	for _, ch in ipairs(S.ExtraChars or {}) do
		table.insert(list, ch)
	end
	if S.Car and S.Car.Real then
		table.insert(list, S.Car.Real)
	end
	groundParams.FilterDescendantsInstances = list
end

local function groundAt(pos)
	local hit = workspace:Raycast(Vector3.new(pos.X, pos.Y + 6, pos.Z), Vector3.new(0, -12, 0), groundParams)
	if hit then
		return hit.Position.Y, hit.Material
	end
	return 0, Enum.Material.Concrete
end

local function invisiblePart(name, size)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size or Vector3.new(0.1, 0.1, 0.1)
	p.Transparency = 1
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = S.Folder
	return p
end

local function solid(name, size, color, material, parent)
	local p = invisiblePart(name, size)
	p.Transparency = 0
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.CastShadow = true
	if parent then
		p.Parent = parent
	end
	return p
end

-------------------------------------------------------------------------------
-- Машина команды: копия Store.Front.TeamCar. Координаты салона — в осях модели (studs): перёд +Z,
-- водитель (левый руль) +X, опора — центр низа. Двери, колёса и руль двигаются; дворники и сиденья —
-- свои детали; свет фар, приборов, магнитолы и проплывающих фонарей.
-------------------------------------------------------------------------------
local CAR = {
	Seats = {
		Driver = { Pos = Vector3.new(1.31, 0, 0.78), Cushion = 2.45, Door = "FL", Side = 1, Out = Vector3.new(5.6, 0, 1.2) },
		Passenger = { Pos = Vector3.new(-1.31, 0, 0.78), Cushion = 2.45, Door = "FR", Side = -1, Out = Vector3.new(-5.6, 0, 1.2) },
		BackLeft = { Pos = Vector3.new(1.45, 0, -2.4), Cushion = 2.35, Door = "RL", Side = 1, Out = Vector3.new(5.6, 0, -2.9) },
		BackRight = { Pos = Vector3.new(-1.45, 0, -2.4), Cushion = 2.35, Door = "RR", Side = -1, Out = Vector3.new(-5.6, 0, -2.9) },
	},
	Roof = 5.95, -- потолок салона
	-- петли дверей (передняя кромка двери, у наружной обшивки); знак X — сторона
	Hinge = { FL = Vector3.new(3.5, 2.6, 3.87), FR = Vector3.new(-3.5, 2.6, 3.87), RL = Vector3.new(3.5, 2.6, -0.19), RR = Vector3.new(-3.5, 2.6, -0.19) },
	SteerC = Vector3.new(1.369, 3.315, 2.718), -- центр руля
	SteerR = 0.62,
	Radio = Vector3.new(0.05, 3.55, 3.05), -- магнитола на центральной консоли
	Mirror = Vector3.new(0.25, 5.55, 2.95), -- салонное зеркало
	Road = Vector3.new(1.3, 4.6, 40), -- взгляд водителя на дорогу
	Ahead = Vector3.new(0, 4.6, 40),
	-- лобовое стекло: низ и направление вверх по стеклу (для дворников)
	GlassBottom = Vector3.new(0, 3.9, 4.42),
	GlassUp = Vector3.new(0, 0.811, -0.586),
	GlassN = Vector3.new(0, 0.586, 0.811),
	Spot = Vector3.new(-28.5, 0, 70), -- место на парковке (как у настоящей машины)
	RoadZ = 123.5,
}
CAR.SteerN = Vector3.new(0, math.sin(math.rad(25)), -math.cos(math.rad(25))) -- ось руля (к водителю)
CAR.SteerU = Vector3.new(1, 0, 0):Cross(CAR.SteerN).Unit -- «верх» руля в его плоскости

local DOOR_OF_ROLE = { Driver = "FL", Passenger = "FR", BackLeft = "RL", BackRight = "RR" }
local HEAD_ON = Color3.fromRGB(255, 246, 226)

local function lightHolder(name)
	local h = invisiblePart(name, Vector3.new(0.2, 0.2, 0.2))
	return h
end

-- Видимый конус света фары в дожде
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

local function carAttach(c, part, off)
	table.insert(c.Parts, { Part = part, Off = off })
end

-- Сиденья: подушка и спинка (обивка — тёмная ткань)
local function buildSeats(c)
	local fabric = Color3.fromRGB(46, 40, 37)
	for role, s in pairs(CAR.Seats) do
		local front = role == "Driver" or role == "Passenger"
		local width = front and 2.15 or 2.6
		local depth = front and 2.0 or 1.9
		local cushion = solid("SeatCushion", Vector3.new(width, 0.5, depth), fabric, Enum.Material.Fabric)
		carAttach(c, cushion, CFrame.new(s.Pos.X, s.Cushion - 0.25, s.Pos.Z + depth / 2 - 0.55))
		local back = solid("SeatBack", Vector3.new(width, 2.7, 0.45), fabric, Enum.Material.Fabric)
		carAttach(c, back, CFrame.new(s.Pos.X, s.Cushion + 1.25, s.Pos.Z - 0.85) * CFrame.Angles(math.rad(-12), 0, 0))
		if front then
			local rest = solid("Headrest", Vector3.new(1.1, 0.75, 0.4), fabric, Enum.Material.Fabric)
			carAttach(c, rest, CFrame.new(s.Pos.X, s.Cushion + 2.95, s.Pos.Z - 1.15) * CFrame.Angles(math.rad(-12), 0, 0))
		end
	end
	-- коврик пола (под ногами темно, днища кузова не видно)
	local floor = solid("CarFloor", Vector3.new(5.6, 0.1, 9.6), Color3.fromRGB(22, 22, 24), Enum.Material.Fabric)
	carAttach(c, floor, CFrame.new(0, 1.33, -0.4))
end

-- Дворники: два рычага на стекле, качаются вместе
local function buildWipers(c)
	c.Wipers = {}
	for _, x in ipairs({ -2.1, 0.7 }) do
		local blade = solid("Wiper", Vector3.new(0.09, 0.09, 2.45), Color3.fromRGB(14, 14, 16), Enum.Material.SmoothPlastic)
		blade.CastShadow = false
		local pivot = Vector3.new(x, CAR.GlassBottom.Y, CAR.GlassBottom.Z) + CAR.GlassN * 0.1
		table.insert(c.Wipers, { Part = blade, Pivot = pivot })
	end
	c.WiperAngle = 0
	c.WipersOn = false
	c.WiperPhase = 0
end

local function wiperOffset(w, angle)
	local d = Vector3.new(1, 0, 0) * math.cos(angle) + CAR.GlassUp * math.sin(angle)
	local mid = w.Pivot + d * 1.2
	return CFrame.lookAt(mid, mid + d, CAR.GlassN)
end

-- Свет: фары с конусами в дожде, задние фонари, приборы, магнитола, «проплывающий» фонарь улицы
local function buildLights(c)
	c.Lights = {}
	for _, side in ipairs({ -1, 1 }) do
		local holder = lightHolder("HeadBeam")
		local s = Instance.new("SpotLight")
		s.Face = Enum.NormalId.Front
		s.Angle = 60
		s.Range = 60
		s.Brightness = 5
		s.Color = HEAD_ON
		s.Shadows = true
		s.Parent = holder
		local cone = lightCone(holder, 26, 11, Color3.fromRGB(255, 236, 205), 0.9)
		local p = Vector3.new(side * 2.4, 3.0, 8.9)
		carAttach(c, holder, CFrame.lookAt(p, p + Vector3.new(0, -0.09, 1)))
		table.insert(c.Lights, { Light = s, Beam = cone })
	end
	local tail = lightHolder("TailGlow")
	local glow = Instance.new("PointLight")
	glow.Range = 7
	glow.Brightness = 1.1
	glow.Color = Color3.fromRGB(255, 30, 20)
	glow.Parent = tail
	carAttach(c, tail, CFrame.new(0, 3.0, -9.6))
	table.insert(c.Lights, { Light = glow, Tail = true })
	-- приборы: холодный свет снизу на лицах передних; магнитола — тёплое пятно
	local function glowAt(name, pos, color, range, brightness)
		local h = lightHolder(name)
		local l = Instance.new("PointLight")
		l.Color = color
		l.Range = range
		l.Brightness = brightness
		l.Shadows = false
		l.Parent = h
		carAttach(c, h, CFrame.new(pos))
		return l
	end
	c.Dash = glowAt("DashGlow", Vector3.new(0.7, 4.35, 2.85), Color3.fromRGB(125, 170, 255), 6, 0.5)
	c.RadioGlow = glowAt("RadioGlow", CAR.Radio + Vector3.new(0, 0.15, -0.3), Color3.fromRGB(255, 168, 90), 2.4, 0.55)
	-- фонарь улицы проплывает над машиной (на ходу — каждые ~48 studs)
	c.Sweep = glowAt("LampSweep", Vector3.new(0, 7.5, 0), Color3.fromRGB(255, 176, 92), 15, 0)
	c.SweepHolder = c.Sweep.Parent
	c.SweepZ = 20
end

local function setCarLights(on, brake)
	local c = S.Car
	if not c then
		return
	end
	for _, l in ipairs(c.Lights) do
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

local function makeCar()
	local store = workspace:FindFirstChild("Store")
	local front = store and store:FindFirstChild("Front")
	local real = front and front:FindFirstChild("TeamCar")
	if not real then
		return nil
	end
	real.Archivable = true
	local m = real:Clone()
	m.Name = "TeamIntroCar"
	m.Parent = S.Folder
	hideModel(real)
	local base = real:GetPivot()
	local scale = real:GetAttribute("Scale") or 3.5
	local c = {
		Model = m,
		Real = real,
		Scale = scale,
		Parts = {},
		Wheels = {},
		Doors = { FL = { Parts = {}, Angle = 0 }, FR = { Parts = {}, Angle = 0 }, RL = { Parts = {}, Angle = 0 }, RR = { Parts = {}, Angle = 0 } },
		Pitch = 0, PitchV = 0, Roll = 0, RollV = 0, Heave = 0, HeaveV = 0,
		Spin = 0, Steer = 0, Speed = 0, Accel = 0, S = 0,
	}
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.LocalTransparencyModifier = 0
			local off = base:ToObjectSpace(d.CFrame)
			local name = d.Name
			if name == "Collision" then
				d:Destroy()
			elseif string.find(name, "Glass", 1, true) then
				-- стёкла копии светлее: сквозь них снимают салон
				d.Transparency = 0.82
				d.Reflectance = 0.08
				carAttach(c, d, off)
			end
			if d.Parent then
				local door = string.match(name, "^Door(%u%u)_")
				local wheel = string.match(name, "^Wheel_(%u%u)$")
				if door and c.Doors[door] then
					table.insert(c.Doors[door].Parts, { Part = d, Off = off })
				elseif wheel then
					table.insert(c.Wheels, { Part = d, Pos = off.Position, Rot = off - off.Position, Front = string.sub(wheel, 1, 1) == "F", R = math.max(d.Size.Y, d.Size.Z) / 2 })
				elseif name == "Steer" then
					c.SteerPart = { Part = d, Off = off }
				elseif not string.find(name, "Glass", 1, true) then
					carAttach(c, d, off)
				end
			end
		end
	end
	buildSeats(c)
	buildWipers(c)
	buildLights(c)
	c.Pts, c.Lens = nil, nil
	return c
end

local function spring(x, v, target, dt, k, damp)
	local a = k * (target - x) - damp * v
	v = v + a * dt
	return x + v * dt, v
end

local function carBump(h, r)
	local c = S.Car
	if c then
		c.HeaveV = c.HeaveV + h
		c.RollV = c.RollV + (r or 0)
	end
end

-- Где точка салона (координаты машины) в мире
local function carPoint(p)
	local c = S.Car
	return (c and c.BodyCF) and c.BodyCF:PointToWorldSpace(p) or p
end

-- Точка хвата на ободе руля (угол от верха; руль повёрнут на steerAngle)
local function steerGrip(angle)
	local c = S.Car
	local a = angle + (c and c.SteerWheel or 0)
	return CAR.SteerC + (Vector3.new(1, 0, 0) * math.sin(a) + CAR.SteerU * math.cos(a)) * CAR.SteerR
end

-- Поставить кузов: pos, направление dir; ds — путь за кадр (колёса, подвеска), turn — поворот впереди
local function poseCar(pos, dir, ds, dt)
	local c = S.Car
	local speed = dt > 0 and ds / dt or 0
	local accel = dt > 0 and (speed - c.Speed) / dt or 0
	c.Speed = speed
	c.Accel = c.Accel + (accel - c.Accel) * math.min(1, dt * 6)
	local base = CFrame.lookAt(pos, pos + dir) * CFrame.Angles(0, math.pi, 0)
	if dt > 0 then
		local pitchTarget = math.clamp(-c.Accel * 0.0045, -0.035, 0.035)
		local rollTarget = math.clamp(c.Steer * speed * 0.004, -0.03, 0.03)
		if speed > 4 then
			local bump = math.min(1, speed / 25)
			c.HeaveV = c.HeaveV + math.noise(c.Spin * 0.2, 0.5) * 2.2 * bump * dt
			c.RollV = c.RollV + math.noise(c.Spin * 0.15, 7.5) * 0.25 * bump * dt
		end
		c.Pitch, c.PitchV = spring(c.Pitch, c.PitchV, pitchTarget, dt, 70, 8)
		c.Roll, c.RollV = spring(c.Roll, c.RollV, rollTarget, dt, 80, 7)
		c.Heave, c.HeaveV = spring(c.Heave, c.HeaveV, 0, dt, 90, 7)
		c.Spin = c.Spin + ds
	end
	local body = base * CFrame.new(0, c.Heave, 0) * CFrame.Angles(c.Pitch, 0, c.Roll)
	c.Base, c.BodyCF, c.Pos, c.Dir = base, body, pos, dir
	for _, p in ipairs(c.Parts) do
		p.Part.CFrame = body * p.Off
	end
	-- двери: поворот вокруг петли (наружу)
	for key, door in pairs(c.Doors) do
		local hinge = CAR.Hinge[key]
		local side = hinge.X > 0 and -1 or 1
		local rot = CFrame.new(hinge) * CFrame.Angles(0, side * math.rad(door.Angle), 0) * CFrame.new(-hinge)
		for _, p in ipairs(door.Parts) do
			p.Part.CFrame = body * rot * p.Off
		end
	end
	for _, w in ipairs(c.Wheels) do
		local steer = w.Front and CFrame.Angles(0, c.Steer, 0) or CFrame.identity
		w.Part.CFrame = base * CFrame.new(w.Pos + Vector3.new(0, c.Heave * 0.15, 0)) * steer * CFrame.Angles(c.Spin / math.max(0.3, w.R), 0, 0) * w.Rot
	end
	-- руль крутится вместе с поворотом колёс
	c.SteerWheel = (c.SteerWheel or 0) + ((-c.Steer * 3.2) - (c.SteerWheel or 0)) * math.min(1, dt * 8)
	if c.SteerPart then
		local rot = CFrame.new(CAR.SteerC) * CFrame.fromAxisAngle(CAR.SteerN, c.SteerWheel) * CFrame.new(-CAR.SteerC)
		c.SteerPart.Part.CFrame = body * rot * c.SteerPart.Off
	end
	-- дворники
	for _, w in ipairs(c.Wipers) do
		w.Part.CFrame = body * wiperOffset(w, c.WiperAngle)
	end
	-- фонарь улицы проплывает от капота к багажнику
	if c.SweepHolder then
		c.SweepHolder.CFrame = body * CFrame.new(0, 7.5, c.SweepZ)
	end
end

-- Путь с дороги на место парковки
local function buildCurve(path)
	local pts, lens = {}, { 0 }
	for i = 0, 240 do
		pts[i + 1] = spline(path, i / 240)
	end
	for i = 2, #pts do
		lens[i] = lens[i - 1] + (pts[i] - pts[i - 1]).Magnitude
	end
	return pts, lens
end

local function curveAt(pts, lens, s)
	s = math.clamp(s, 0, lens[#lens])
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
	local dir = pts[hi] - pts[lo]
	if dir.Magnitude < 1e-4 then
		dir = Vector3.new(0, 0, -1)
	end
	return pts[lo]:Lerp(pts[hi], k), Vector3.new(dir.X, 0, dir.Z).Unit
end

local function parkingPath()
	local x, z = CAR.Spot.X, CAR.Spot.Z
	return {
		Vector3.new(95, 0, CAR.RoadZ),
		Vector3.new(40, 0, CAR.RoadZ),
		Vector3.new(-4, 0, CAR.RoadZ - 0.3),
		Vector3.new(x + 14.5, 0, 115),
		Vector3.new(x + 2.1, 0, z + 31),
		Vector3.new(x, 0, z + 14),
		Vector3.new(x, 0, z),
	}
end

-- Прямая улица на запад: машина в момент tAt проезжает x = xAt (скорость speed)
local function driveThrough(xAt, tAt, speed)
	local c = S.Car
	if not c then
		return
	end
	c.Drive = nil
	c.Line = { X0 = xAt + speed * (tAt - now()), Speed = speed, Start = now() }
	c.LineX = c.Line.X0
	c.Speed = speed
	c.Accel = 0
	poseCar(Vector3.new(c.Line.X0, 0, CAR.RoadZ), Vector3.new(-1, 0, 0), 0, 0)
end

-- Въезд на парковку: start — момент начала, dur — до остановки
local function driveToSpot(start, dur)
	local c = S.Car
	if not c then
		return
	end
	c.Pts, c.Lens = buildCurve(parkingPath())
	c.Length = c.Lens[#c.Lens]
	c.Line = nil
	c.Drive = { Start = start, Dur = dur, P = 2.2 }
	c.S = 0
end

local function updateCar(dt)
	local c = S.Car
	if not c then
		return
	end
	-- дворники: ход вверх-вниз за 1.8 с
	if c.WipersOn then
		c.WiperPhase = c.WiperPhase + dt / 1.8
	elseif c.WiperAngle > 0.01 then
		c.WiperPhase = c.WiperPhase + dt / 1.8
		if (c.WiperPhase % 1) < 0.05 then
			c.WiperPhase = 0
		end
	end
	c.WiperAngle = 1.75 * (0.5 - 0.5 * math.cos(2 * math.pi * c.WiperPhase))
	local pos, dir, ds = c.Pos, c.Dir, 0
	if c.Line then
		local l = c.Line
		local x = l.X0 - l.Speed * (now() - l.Start)
		ds = c.LineX - x
		c.LineX = x
		pos, dir = Vector3.new(x, 0, CAR.RoadZ), Vector3.new(-1, 0, 0)
		c.Steer = c.Steer + (0 - c.Steer) * math.min(1, dt * 4)
		-- фонари вдоль улицы: каждые ~48 studs свет проходит по салону
		c.SweepZ = c.SweepZ - ds
		if c.SweepZ < -16 then
			c.SweepZ = c.SweepZ + 48
		end
		local k = math.clamp(1 - math.abs(c.SweepZ) / 13, 0, 1)
		c.Sweep.Brightness = 1.4 * k * k
	elseif c.Drive and c.Pts then
		local d = c.Drive
		local u = clamp01((now() - d.Start) / d.Dur)
		local s = c.Length * (1 - (1 - u) ^ d.P)
		ds = s - c.S
		c.S = s
		pos, dir = curveAt(c.Pts, c.Lens, s)
		local _, ahead = curveAt(c.Pts, c.Lens, s + 6)
		local la = CFrame.lookAt(Vector3.zero, dir):VectorToObjectSpace(ahead)
		c.Steer = c.Steer + (math.clamp(math.atan2(-la.X, -la.Z) * 1.7, -0.5, 0.5) - c.Steer) * math.min(1, dt * 6)
		c.Sweep.Brightness = 0
		if u >= 1 then
			c.Drive = nil
		end
	end
	if pos then
		poseCar(pos, dir, ds, dt)
	end
end

local function swingDoor(key, to, seconds)
	local door = S.Car and S.Car.Doors[key]
	if not door then
		return
	end
	local from = door.Angle
	task.spawn(function()
		local t = 0
		while t < seconds and S.Car do
			t = t + RunService.Heartbeat:Wait()
			door.Angle = from + (to - from) * easeSine(t / seconds)
		end
		door.Angle = to
	end)
end

-------------------------------------------------------------------------------
-- Актёры: копии аватаров игроков (R15 — с IK рук и головы, как в одиночной сцене v14)
-------------------------------------------------------------------------------
local function motorOf(m, partName, jointName)
	local p = m:FindFirstChild(partName)
	local j = p and p:FindFirstChild(jointName)
	return (j and j:IsA("Motor6D")) and j or nil
end

local function frameOf(x, y)
	return CFrame.fromMatrix(Vector3.zero, x, y, x:Cross(y))
end

local FWD = Vector3.new(0, 0, -1)

local function makeIK(a)
	local m = a.Model
	local ut = m:FindFirstChild("UpperTorso")
	if not (ut and a.R15) then
		return
	end
	a.UT = ut
	a.IK = {}
	local function arm(key, side)
		local sh = motorOf(m, side .. "UpperArm", side .. "Shoulder")
		local el = motorOf(m, side .. "LowerArm", side .. "Elbow")
		local wr = motorOf(m, side .. "Hand", side .. "Wrist")
		if not (sh and el and wr) then
			return
		end
		local ua0 = sh.C0 * sh.C1:Inverse()
		local e0 = ua0 * el.C0.Position
		local la0 = ua0 * el.C0 * el.C1:Inverse()
		local w0 = la0 * wr.C0.Position
		local s0 = sh.C0.Position
		local u0 = (e0 - s0).Unit
		local f0 = (w0 - e0).Unit
		local h0 = u0:Cross(FWD).Unit
		local h0f = (h0 - f0 * h0:Dot(f0)).Unit
		local hand = m:FindFirstChild(side .. "Hand")
		local grip = hand and hand:FindFirstChild(side .. "GripAttachment")
		local gripLen = grip and (grip.Position - wr.C1.Position).Magnitude or 0.3
		a.IK[key] = {
			Kind = "Arm", Sh = sh, El = el, S = s0, UA0 = ua0, LA0 = la0, E0 = e0,
			L1 = (e0 - s0).Magnitude, L2 = (w0 - e0).Magnitude, Grip = gripLen,
			F0u = frameOf(u0, h0), F0f = frameOf(f0, h0f),
			Cur = Vector3.zero, Goal = Vector3.zero, InCar = false, Rate = 5, BaseRate = 5, Fresh = true,
			W = 0, WGoal = 0, WSpeed = 2,
		}
	end
	arm("L", "Left")
	arm("R", "Right")
	local neck = motorOf(m, "Head", "Neck")
	if neck then
		a.IK.Look = { Kind = "Look", Neck = neck, Cur = Vector3.zero, Goal = Vector3.zero, InCar = false, Rate = 3.2, BaseRate = 3.2, Fresh = true, W = 0, WGoal = 0, WSpeed = 2 }
	end
end

-- Цель IK актёра a. key: "Look", "L", "R"; point — в координатах машины (inCar) или мира
local function ik(a, key, point, inCar, weight, seconds, rate)
	local k = a and a.IK and a.IK[key]
	if not k then
		return
	end
	inCar = inCar == true
	local cf = S.Car and S.Car.BodyCF
	if k.Fresh then
		k.Cur, k.InCar, k.Fresh = point, inCar, false
	elseif inCar ~= k.InCar then
		if cf then
			k.Cur = inCar and cf:PointToObjectSpace(k.Cur) or cf:PointToWorldSpace(k.Cur)
		else
			k.Cur = point
		end
		k.InCar = inCar
	end
	k.Goal = point
	k.Rate = rate or k.BaseRate
	if weight then
		k.WGoal = weight
		k.WSpeed = 1 / math.max(seconds or 0.5, 0.05)
	end
end

local function solveArm(k, T, P)
	local S0 = k.S
	local toT = T - S0
	local dir0 = toT.Magnitude > 1e-4 and toT.Unit or Vector3.new(0, -1, 0)
	local Wt = T - dir0 * k.Grip
	local E, fa, perp
	for _ = 1, 4 do
		local toW = Wt - S0
		local dist = toW.Magnitude
		local dir = dist > 1e-4 and toW / dist or dir0
		dist = math.clamp(dist, math.abs(k.L1 - k.L2) + 0.05, k.L1 + k.L2 - 0.01)
		local W = S0 + dir * dist
		local cosA = math.clamp((k.L1 * k.L1 + dist * dist - k.L2 * k.L2) / (2 * k.L1 * dist), -1, 1)
		local sinA = math.sqrt(1 - cosA * cosA)
		local toP = P - S0
		perp = toP - dir * toP:Dot(dir)
		if perp.Magnitude < 1e-3 then
			perp = Vector3.new(0, -1, 0) - dir * (-dir.Y)
		end
		perp = perp.Unit
		E = S0 + dir * (cosA * k.L1) + perp * (sinA * k.L1)
		fa = (W - E).Unit
		Wt = T - fa * k.Grip
	end
	local ua = (E - S0).Unit
	local h = ua:Cross(fa)
	if h.Magnitude < 1e-3 then
		h = ua:Cross(-perp)
	end
	h = h.Unit
	local UA = CFrame.new(S0) * (frameOf(ua, h) * k.F0u:Inverse()) * CFrame.new(-S0) * k.UA0
	local hf = (h - fa * h:Dot(fa)).Unit
	local LA = CFrame.new(E) * (frameOf(fa, hf) * k.F0f:Inverse()) * CFrame.new(-k.E0) * k.LA0
	return k.Sh.C0:Inverse() * UA * k.Sh.C1, k.El.C0:Inverse() * UA:Inverse() * LA * k.El.C1
end

local function solveLook(k, d)
	if d.Magnitude < 1e-3 then
		return CFrame.identity
	end
	d = d.Unit
	local yaw = math.clamp(math.atan2(-d.X, -d.Z), -1.1, 1.1)
	local pitch = math.clamp(math.asin(math.clamp(d.Y, -1, 1)), -0.75, 0.55)
	local r = k.Neck.C0.Rotation
	return r:Inverse() * CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0) * r
end

local function setJoint(motor, k, slot, pose, w)
	local base = motor.Transform
	if k[slot] and base == k[slot] then
		base = k[slot .. "Base"] or CFrame.identity
	else
		k[slot .. "Base"] = base
	end
	local out = w >= 0.999 and pose or base:Lerp(pose, w)
	motor.Transform = out
	k[slot] = out
end

-- После анимации (Stepped): позы IK всех актёров — в суставы
local function applyIK()
	for _, a in pairs(S.Actors) do
		if a.IK and a.UT and a.UT.Parent then
			local ut = a.UT.CFrame
			for _, k in pairs(a.IK) do
				if k.World and k.W > 0.001 then
					if k.Kind == "Arm" then
						local ts, te = solveArm(k, ut:PointToObjectSpace(k.World), ut:PointToObjectSpace(k.PoleWorld))
						setJoint(k.Sh, k, "LastS", ts, k.W)
						setJoint(k.El, k, "LastE", te, k.W)
					else
						local from = ut * k.Neck.C0.Position
						setJoint(k.Neck, k, "LastN", solveLook(k, ut:VectorToObjectSpace(k.World - from)), k.W)
					end
				elseif k.W <= 0.001 and k.LastS then
					k.LastS, k.LastE = nil, nil
					k.Sh.Transform = k.LastSBase or CFrame.identity
					k.El.Transform = k.LastEBase or CFrame.identity
				elseif k.W <= 0.001 and k.LastN then
					k.LastN = nil
					k.Neck.Transform = k.LastNBase or CFrame.identity
				end
			end
		end
	end
end

local function animId(ch, folderName, childName, fallback)
	local animate = ch:FindFirstChild("Animate")
	local f = animate and animate:FindFirstChild(folderName)
	local a = f and (f:FindFirstChild(childName) or f:FindFirstChildOfClass("Animation"))
	if a and a:IsA("Animation") and a.AnimationId ~= "" then
		return a.AnimationId
	end
	return fallback
end

local function characterOf(entry)
	local p = Players:GetPlayerByUserId(entry.UserId or 0)
	return (p and p.Character) or entry.Character
end

-- Копия аватара игрока entry ({ UserId, Name, Role }). Рост приводится к ~5.2 studs (иначе высокие
-- аватары упирались бы головой в крышу «семёрки», а маленькие терялись в кадре)
local function makeActor(entry)
	local ch = characterOf(entry)
	local hum0 = ch and ch:FindFirstChildOfClass("Humanoid")
	if not (ch and hum0) then
		return nil
	end
	local r15 = hum0.RigType == Enum.HumanoidRigType.R15
	local walkId = r15 and Models.Anim.Walk or animId(ch, "walk", "WalkAnim", "rbxassetid://180426354")
	local idleId = r15 and Models.Anim.Idle or animId(ch, "idle", "Animation1", "rbxassetid://180435571")
	local sitId = animId(ch, "sit", "SitAnim", r15 and "rbxassetid://2506281703" or "rbxassetid://178130996")
	ch.Archivable = true
	local ok, m = pcall(function()
		return ch:Clone()
	end)
	if not (ok and m) then
		return nil
	end
	m.Name = "TeamActor_" .. entry.Role
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BaseScript") or d:IsA("Sound") or d:IsA("ForceField") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = false
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
		return nil
	end
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	root.Anchored = true
	m.Parent = S.Folder
	-- рост: от низа ступней до макушки
	local okS = pcall(function()
		local _, size = m:GetBoundingBox()
		local h = size.Y
		local k = 1
		if h > 5.6 then
			k = 5.2 / h
		elseif h < 4.0 then
			k = 4.6 / h
		end
		if math.abs(k - 1) > 0.02 then
			m:ScaleTo(m:GetScale() * k)
		end
	end)
	if not okS then
		warn("[Командная сцена] рост не изменить")
	end
	local a = {
		Role = entry.Role,
		Name = entry.Name or entry.Role,
		UserId = entry.UserId,
		Model = m,
		Root = root,
		Hum = hum,
		R15 = r15,
		Pos = Vector3.zero,
		Yaw = 0,
		Forward = Vector3.new(0, 0, -1),
		Path = {},
		Speed = 4.6,
		Moving = false,
		StepDist = 0,
		Lean = 0,
		LeanCur = 0,
		Laugh = 0,
		Lift = 0,
	}
	if r15 then
		a.Height = hum.HipHeight + root.Size.Y / 2
		local hs = hum:FindFirstChild("BodyHeightScale")
		a.AnimScale = 1 / (Models.Anim.WalkNatural * ((hs and hs:IsA("NumberValue") and hs.Value > 0) and hs.Value or 1) * m:GetScale())
	else
		a.Height = 3 * m:GetScale()
		a.AnimScale = 1 / 14.5
	end
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
	a.Sit = load(sitId, Enum.AnimationPriority.Action)
	local head = m:FindFirstChild("Head")
	a.HeadPart = head
	a.HeadOff = head and (head.Position.Y - root.Position.Y) or 1.5
	a.HipBelow = r15 and 0.45 or 1
	local lt = m:FindFirstChild("LowerTorso")
	local leg = m:FindFirstChild("RightUpperLeg")
	local hip = leg and leg:FindFirstChild("RightHip")
	if lt and hip and hip:IsA("Motor6D") then
		a.HipBelow = math.clamp(root.Position.Y - (lt.CFrame * hip.C0).Position.Y, 0, 1.5)
	end
	makeIK(a)
	-- пар изо рта на холоде (снаружи)
	if head then
		local att = Instance.new("Attachment")
		att.Name = "Breath"
		att.Position = Vector3.new(0, -0.15, -0.55)
		att.Parent = head
		local pe = Instance.new("ParticleEmitter")
		pe.Texture = "rbxasset://textures/particles/smoke_main.dds"
		pe.Color = ColorSequence.new(Color3.fromRGB(220, 224, 230))
		pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.82), NumberSequenceKeypoint.new(1, 1) })
		pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.12), NumberSequenceKeypoint.new(1, 0.7) })
		pe.Lifetime = NumberRange.new(0.7, 1.1)
		pe.Speed = NumberRange.new(0.6, 1.0)
		pe.SpreadAngle = Vector2.new(12, 12)
		pe.Acceleration = Vector3.new(0, 0.6, 0)
		pe.LightInfluence = 1
		pe.Rate = 0
		pe.EmissionDirection = Enum.NormalId.Front
		pe.Parent = att
		a.Breath = pe
	end
	return a
end

local function removeActor(role)
	local a = S.Actors[role]
	if a and a.Model then
		a.Model:Destroy()
	end
	S.Actors[role] = nil
end

-- Посадить актёра в машину (поза «сидя»; руки водителя — на руле)
local function seatActor(a)
	local seat = CAR.Seats[a.Role]
	local rootY = seat.Cushion + 0.4 + a.HipBelow
	rootY = math.min(rootY, CAR.Roof - 0.55 - a.HeadOff - 0.6)
	a.SeatCF = CFrame.new(seat.Pos.X, rootY, seat.Pos.Z) * CFrame.Angles(0, math.pi, 0)
	a.InCar = true
	if a.Idle then
		a.Idle:Stop(0)
	end
	if a.Sit then
		a.Sit:Play(0)
	end
	ik(a, "Look", CAR.Ahead + Vector3.new(seat.Pos.X, 0, 0), true, 0.85, 0.1)
	if a.Role == "Driver" then
		ik(a, "L", steerGrip(math.rad(62)), true, 1, 0.1)
		ik(a, "R", steerGrip(math.rad(-62)), true, 1, 0.1)
	end
end

local function actorGo(a, points, speed)
	if a then
		a.Path = points
		a.Speed = speed or a.Speed
		a.Face = nil
	end
end

-- Кто сейчас говорит (роль) и момент начала реплики
local function speakerNow()
	return S.Speaking
end

-- Взгляд по умолчанию: слушают того, кто говорит; водитель на ходу смотрит на дорогу и лишь бросает
-- короткий взгляд; кто говорит — смотрит на собеседников. Сцена может задать свой взгляд (a.LookAt)
local function lookPolicy(a, t)
	if a.LookAt and (not a.LookUntil or t < a.LookUntil) then
		return a.LookAt, a.LookInCar
	end
	local sp = speakerNow()
	local driving = a.InCar and a.Role == "Driver" and S.Car and (S.Car.Line or S.Car.Drive)
	if a.InCar then
		local seat = CAR.Seats[a.Role]
		local ahead = Vector3.new(seat.Pos.X * 0.6, 4.7, 40)
		if sp and sp.Role ~= a.Role and S.Actors[sp.Role] then
			local other = S.Actors[sp.Role]
			local p = other.HeadPart and S.Car.BodyCF:PointToObjectSpace(other.HeadPart.Position) or ahead
			if driving then
				-- водитель: короткий взгляд на говорящего (через зеркало, если тот сзади), потом снова дорога
				if t - sp.At < 0.9 then
					return (CAR.Seats[sp.Role].Pos.Z < 0) and CAR.Mirror or p, true
				end
				return CAR.Road, true
			end
			return p, true
		elseif sp and sp.Role == a.Role and not driving then
			-- говорит сам: к остальным (вперёд-в-центр салона)
			return Vector3.new(-seat.Pos.X * 0.5, 4.6, seat.Pos.Z < 0 and 2 or -1.5), true
		end
		if driving then
			return CAR.Road, true
		end
		-- в окно, в своей стороне
		return Vector3.new(seat.Side * 14, 4.4, seat.Pos.Z + 12), true
	end
	-- снаружи: смотрим на говорящего
	if sp and sp.Role ~= a.Role and S.Actors[sp.Role] and S.Actors[sp.Role].HeadPart then
		return S.Actors[sp.Role].HeadPart.Position, false
	end
	return (a.Root and a.Root.CFrame or CFrame.identity) * Vector3.new(0, 1.4, -20), false
end

local function updateIK(a, dt, t)
	if not (a.Model and a.Root) then
		return
	end
	local rootCF = a.Root.CFrame
	if a.IK then
		local look, inCar = lookPolicy(a, t)
		local lk = a.IK.Look
		if lk then
			ik(a, "Look", look, inCar)
			if lk.WGoal < 0.05 then
				lk.WGoal, lk.WSpeed = 0.85, 2
			end
		end
		-- водитель держит руль (руль крутится — руки вместе с ним), пока не занят чем-то ещё
		if a.Role == "Driver" and a.InCar and not a.HandsBusy then
			ik(a, "L", steerGrip(math.rad(62)), true, 1, 0.4)
			ik(a, "R", steerGrip(math.rad(-62)), true, 1, 0.4)
		end
		local cf = S.Car and S.Car.BodyCF
		local talking = S.Speaking and S.Speaking.Role == a.Role
		for key, k in pairs(a.IK) do
			if not k.Fresh then
				k.Cur = k.Cur:Lerp(k.Goal, 1 - math.exp(-dt * k.Rate))
				local p = (k.InCar and cf) and cf:PointToWorldSpace(k.Cur) or k.Cur
				if key == "Look" then
					local d = math.max(1, (p - rootCF.Position).Magnitude) / 6
					local amount = talking and 1 or 0.3
					local up = amount * (math.noise(t * 1.5, 3.3 + a.Root.Position.X) * 0.5 + (talking and math.sin(t * 4.2) * 0.06 or 0)) + a.Laugh * math.sin(t * 17) * 0.12
					local side = amount * math.noise(t * 0.9, 8.8 + a.Root.Position.Z) * 0.6
					p = p + rootCF.UpVector * (up * d) + rootCF.RightVector * (side * d)
				else
					k.PoleWorld = rootCF * Vector3.new(key == "L" and -2.0 or 2.0, -0.8, 0.3)
				end
				k.World = p
				local step = k.WSpeed * dt
				k.W = k.W + math.clamp(k.WGoal - k.W, -step, step)
			end
		end
	end
end

local function updateActor(a, dt, t)
	if not a.Model or not a.Root then
		return
	end
	a.LeanCur = a.LeanCur + (a.Lean - a.LeanCur) * (1 - math.exp(-dt * 3))
	local lean = a.LeanCur + a.Laugh * math.sin(t * 15) * 0.05
	if a.InCar then
		local cf = S.Car and S.Car.BodyCF
		if cf then
			a.Root.CFrame = cf * a.SeatCF * CFrame.new(0, -0.7, 0) * CFrame.Angles(lean, 0, 0) * CFrame.new(0, 0.7, 0)
		end
		updateIK(a, dt, t)
		return
	end
	if a.Exit then
		-- выходит из машины: из кресла через проём двери наружу (координаты машины)
		local e = a.Exit
		local u = clamp01((t - e.Start) / e.Dur)
		local cf = S.Car.BodyCF
		local seat = CAR.Seats[a.Role]
		local k1 = easeSine(clamp01(u / 0.35)) -- разворот к двери
		local k2 = easeSine(clamp01((u - 0.25) / 0.75)) -- выход
		local from = Vector3.new(seat.Pos.X, 0, seat.Pos.Z)
		local p = from:Lerp(seat.Out, k2)
		local yaw = math.pi + (seat.Side > 0 and -1 or 1) * (math.pi / 2) * k1 * (1 - 0.35 * k2)
		local seatedY = a.SeatCF.Position.Y
		local standY = a.Height + 0.05
		local y = seatedY + (standY - seatedY) * easeSine(clamp01((u - 0.3) / 0.5))
		local world = cf * CFrame.new(p.X, y, p.Z) * CFrame.Angles(0, yaw, 0)
		a.Root.CFrame = world
		if u > 0.32 and not e.Stood then
			e.Stood = true
			if a.Sit then
				a.Sit:Stop(0.35)
			end
			if a.Walk then
				a.Walk:Play(0.3)
				a.Walk:AdjustSpeed(2.4 * a.AnimScale)
			end
		end
		if u >= 1 then
			a.Exit = nil
			local pos = world.Position
			a.Pos = Vector3.new(pos.X, 0, pos.Z)
			local look = world.LookVector
			a.Forward = Vector3.new(look.X, 0, look.Z).Unit
			a.Yaw = math.atan2(-a.Forward.X, -a.Forward.Z)
			a.Moving = true
		end
		updateIK(a, dt, t)
		return
	end
	local target = a.Path[1]
	local moving = false
	if target then
		local flat = Vector3.new(target.X - a.Pos.X, 0, target.Z - a.Pos.Z)
		local d = flat.Magnitude
		local stepLen = a.Speed * dt
		if d <= stepLen or d < 0.01 then
			a.Pos = Vector3.new(target.X, 0, target.Z)
			table.remove(a.Path, 1)
		else
			a.Pos = a.Pos + flat.Unit * stepLen
			moving = true
			a.Forward = a.Forward:Lerp(flat.Unit, math.min(1, dt * 4)).Unit
		end
		a.StepDist = a.StepDist + math.min(stepLen, d)
	elseif a.Face then
		local f = Vector3.new(a.Face.X - a.Pos.X, 0, a.Face.Z - a.Pos.Z)
		if f.Magnitude > 0.1 then
			a.Forward = a.Forward:Lerp(f.Unit, math.min(1, dt * 3)).Unit
		end
	end
	a.Yaw = lerpAngle(a.Yaw, math.atan2(-a.Forward.X, -a.Forward.Z), math.min(1, dt * 7))
	local gy, material = groundAt(a.Pos)
	a.Y = a.Y and (a.Y + (gy - a.Y) * math.min(1, dt * 10)) or gy
	local h = a.Height + a.Lift
	a.Root.CFrame = CFrame.new(a.Pos.X, a.Y + h, a.Pos.Z) * CFrame.Angles(0, a.Yaw, 0) * CFrame.new(0, -h, 0) * CFrame.Angles(lean, 0, 0) * CFrame.new(0, h, 0)
	if moving and a.StepDist >= 2.4 and not ctx.Audio.MarkerSteps(a.Model) then
		a.StepDist = 0
		ctx.Audio.Step(a.Root, material, ctx.Audio.ZoneOf(a.Pos) == "Outside", false, false)
	end
	if moving ~= a.Moving then
		a.Moving = moving
		if moving then
			if a.Walk then
				a.Walk:Play(0.25)
				a.Walk:AdjustSpeed(a.Speed * a.AnimScale)
			end
			if a.Idle then
				a.Idle:Stop(0.3)
			end
		else
			if a.Walk then
				a.Walk:Stop(0.35)
			end
			if a.Idle then
				a.Idle:Play(0.35)
			end
		end
	elseif moving and a.Walk then
		a.Walk:AdjustSpeed(a.Speed * a.AnimScale)
	end
	updateIK(a, dt, t)
end

-- Начать выход актёра из машины: дверь открывается, через 0.25 с он поворачивается и выходит, дверь хлопает
local function exitCar(a, delay)
	if not a then
		return
	end
	local key = DOOR_OF_ROLE[a.Role]
	after(delay, function()
		if not S.Car then
			return
		end
		local hinge = carPoint(CAR.Hinge[key])
		ctx.Audio.Play("CarDoorOpen", hinge, 0.75, 0.95 + math.random() * 0.1)
		swingDoor(key, 64, 0.75)
		carBump(0.25, (CAR.Seats[a.Role].Side) * 0.02)
	end)
	after(delay + 0.3, function()
		if S.Actors[a.Role] == a then
			a.InCar = false
			a.Exit = { Start = now(), Dur = 1.75 }
			if a.IK and a.IK.L then
				ik(a, "L", Vector3.zero, false, 0, 0.3)
				ik(a, "R", Vector3.zero, false, 0, 0.3)
			end
			carBump(0.6, -(CAR.Seats[a.Role].Side) * 0.05)
		end
	end)
	after(delay + 2.55, function()
		if not S.Car then
			return
		end
		swingDoor(key, 0, 0.32)
	end)
	after(delay + 2.85, function()
		if S.Car then
			ctx.Audio.Play("CarDoorClose", carPoint(CAR.Hinge[key]), 0.85, 0.92 + math.random() * 0.12)
			carBump(-0.9, (CAR.Seats[a.Role].Side) * 0.06)
		end
	end)
end

-------------------------------------------------------------------------------
-- Раздвижные двери входа и датчик над ними (локальные копии), силуэты
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
			c.Parent = S.Folder
			hideModel(p)
			if left then
				d.Left, d.LeftClosed, d.LeftOpen = c, closed, closed * CFrame.new(-5.6, 0, 0)
			else
				d.Right, d.RightClosed, d.RightOpen = c, closed, closed * CFrame.new(5.6, 0, 0)
			end
		end
	end
	if not (d.Left and d.Right) then
		return nil
	end
	return d
end

local function moveDoors(open, seconds)
	local d = S.Doors
	if not d then
		return
	end
	local info = TweenInfo.new(seconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	TweenService:Create(d.Left, info, { CFrame = open and d.LeftOpen or d.LeftClosed }):Play()
	TweenService:Create(d.Right, info, { CFrame = open and d.RightOpen or d.RightClosed }):Play()
	ctx.Audio.Play("AutoDoor", Vector3.new(-52, 8, 50), 0.6, open and 0.84 or 0.95)
end

local SENSOR_POS = Vector3.new(-52, 9.45, 50.83)
local function makeSensor()
	local box = solid("TeamDoorSensor", Vector3.new(1.4, 0.34, 0.45), Color3.fromRGB(24, 24, 28))
	box.CFrame = CFrame.new(SENSOR_POS)
	local led = solid("TeamSensorLed", Vector3.new(0.12, 0.12, 0.04), Color3.fromRGB(255, 40, 30), Enum.Material.Neon)
	led.CastShadow = false
	led.CFrame = CFrame.new(SENSOR_POS + Vector3.new(0.5, -0.03, 0.245))
	local light = Instance.new("PointLight")
	light.Range = 2.5
	light.Brightness = 1.2
	light.Color = led.Color
	light.Shadows = false
	light.Parent = led
	return { Led = led, Light = light }
end

local function sensorSees(on)
	local s = S.Sensor
	if not s then
		return
	end
	local c = on and Color3.fromRGB(70, 255, 120) or Color3.fromRGB(255, 40, 30)
	s.Led.Color = c
	s.Light.Color = c
	s.Light.Brightness = on and 2.4 or 1.2
end

-- Тёмная фигура: высокий узкий силуэт без деталей (не скример — просто кто-то стоит)
local function makeFigure(name, pos, faceTo)
	local m = Instance.new("Model")
	m.Name = name
	local dark = Color3.fromRGB(7, 7, 9)
	local function piece(size, off)
		local p = solid("Shape", size, dark, Enum.Material.SmoothPlastic, m)
		p.Reflectance = 0
		p.CastShadow = false
		table.insert(m:GetChildren(), p)
		return p, off
	end
	local base = CFrame.lookAt(pos, Vector3.new(faceTo.X, pos.Y, faceTo.Z))
	local parts = {
		{ piece(Vector3.new(1.5, 2.9, 0.8), CFrame.new(0, 4.6, 0)) }, -- плечи и корпус
		{ piece(Vector3.new(0.55, 3.2, 0.55), CFrame.new(-0.4, 1.6, 0)) }, -- ноги
		{ piece(Vector3.new(0.55, 3.2, 0.55), CFrame.new(0.4, 1.6, 0)) },
		{ piece(Vector3.new(0.38, 3.1, 0.38), CFrame.new(-0.98, 4.35, 0) * CFrame.Angles(0, 0, math.rad(4))) }, -- длинные руки
		{ piece(Vector3.new(0.38, 3.1, 0.38), CFrame.new(0.98, 4.35, 0) * CFrame.Angles(0, 0, math.rad(-4))) },
		{ piece(Vector3.new(0.95, 1.1, 0.9), CFrame.new(0, 6.6, 0.05) * CFrame.Angles(math.rad(8), 0, 0)) }, -- голова чуть наклонена
	}
	for _, e in ipairs(parts) do
		e[1].CFrame = base * e[2]
	end
	m.Parent = S.Folder
	return m
end

-- Одинокий фонарь у обочины (мигает): под ним и стоит фигура
local function makeRoadLamp(pos)
	local pole = solid("RoadLampPole", Vector3.new(0.5, 17, 0.5), Color3.fromRGB(56, 58, 62), Enum.Material.Metal)
	pole.CFrame = CFrame.new(pos + Vector3.new(0, 8.5, 0))
	local head = solid("RoadLampHead", Vector3.new(1.6, 0.4, 0.8), Color3.fromRGB(40, 40, 44), Enum.Material.Metal)
	head.CFrame = CFrame.new(pos + Vector3.new(0, 17, 0))
	local s = Instance.new("SpotLight")
	s.Face = Enum.NormalId.Bottom
	s.Angle = 100
	s.Range = 26
	s.Brightness = 2.2
	s.Color = Color3.fromRGB(255, 170, 86)
	s.Shadows = true
	s.Parent = head
	return { Pole = pole, Head = head, Light = s }
end

-- Затемнить свет в дальнем ряду (сцена 6) — только у этого игрока
local function dimAisle(on)
	if on then
		S.Dimmed = S.Dimmed or {}
		local store = workspace:FindFirstChild("Store")
		for _, l in ipairs(store and store:GetDescendants() or {}) do
			if l:IsA("Light") and l.Parent and l.Parent:IsA("BasePart") then
				local p = l.Parent.Position
				if p.X > -52 and p.X < -33 and p.Z > -10 and p.Z < 24 and not S.Dimmed[l] then
					S.Dimmed[l] = l.Brightness
					l.Brightness = l.Brightness * 0.22
				end
			end
		end
	else
		for l, b in pairs(S.Dimmed or {}) do
			if l.Parent then
				l.Brightness = b
			end
		end
		S.Dimmed = nil
	end
end

-------------------------------------------------------------------------------
-- Реплики: общее расписание, голос — из головы говорящего, субтитры с именем
-------------------------------------------------------------------------------
local function subtitle(item)
	if not G.SubText then
		return
	end
	if item then
		local name = item.Name or ""
		local color = ROLE_COLOR[item.Role] or "#FFFFFF"
		G.SubText.Text = string.format('<font color="%s">%s:</font> %s', color, name, item.Text or "")
		TweenService:Create(G.SubText, TweenInfo.new(0.15), { TextTransparency = 0, TextStrokeTransparency = 0.45 }):Play()
		TweenService:Create(G.SubBack, TweenInfo.new(0.15), { BackgroundTransparency = 0.55 }):Play()
	else
		TweenService:Create(G.SubText, TweenInfo.new(0.25), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		TweenService:Create(G.SubBack, TweenInfo.new(0.25), { BackgroundTransparency = 1 }):Play()
	end
end

local function updateSpeech(t)
	local lines = S.Lines
	while S.LineIdx <= #lines and t >= lines[S.LineIdx].At do
		local item = lines[S.LineIdx]
		S.LineIdx = S.LineIdx + 1
		local late = t - item.At
		if item.Laugh then
			if late < 0.5 then
				ctx.Audio.Play(item.Laugh, nil, 0.8)
				for _, a in pairs(S.Actors) do
					a.Laugh = 1
					local actor = a
					after(item.Len, function()
						actor.Laugh = 0
					end)
				end
			end
		elseif late < item.Len - 0.2 and not S.Gone[item.Role] then
			local a = S.Actors[item.Role]
			item.Name = a and a.Name or (S.Names[item.Role] or "")
			if late < 0.45 then
				-- голос из головы говорящего (в салоне — громко и рядом; снаружи — с расстоянием)
				local at3d = a and a.HeadPart or nil
				S.Voice = ctx.Audio.Play(item.Key, at3d, 1)
				if S.Voice and at3d then
					S.Voice.RollOffMinDistance = 14
					S.Voice.RollOffMaxDistance = 140
				end
			end
			S.Speaking = item
			subtitle(item)
		end
	end
	local sp = S.Speaking
	if sp and t >= sp.At + sp.Len then
		S.Speaking = nil
		subtitle(nil)
	end
end

-------------------------------------------------------------------------------
-- Звук, свет, «оператор»
-------------------------------------------------------------------------------
local function loopOn(name, key, volume, parent, minD, maxD)
	local s = ctx.Audio.Loop(name, parent, minD, maxD)
	if s then
		if S.Loops[key] then
			S.Loops[key]:Destroy()
		end
		s.Volume = volume
		S.Loops[key] = s
	end
	return s
end

local function loopOff(key, seconds)
	local s = S.Loops[key]
	if not s then
		return
	end
	S.Loops[key] = nil
	if seconds and seconds > 0 then
		TweenService:Create(s, TweenInfo.new(seconds, Enum.EasingStyle.Sine), { Volume = 0 }):Play()
		task.delay(seconds + 0.05, function()
			s:Destroy()
		end)
	else
		s:Destroy()
	end
end

local function radioOn(volume)
	local s = loopOn("StoreMusic", "Radio", volume)
	if s then
		local eq = Instance.new("EqualizerSoundEffect")
		eq.LowGain = -22
		eq.MidGain = 3
		eq.HighGain = -14
		eq.Parent = s
		local d = Instance.new("DistortionSoundEffect")
		d.Level = 0.12
		d.Parent = s
		pcall(function()
			s.TimePosition = 40
		end)
	end
end

local function bedTo(name, volume, seconds)
	local s = ctx.Audio.Bed(name)
	if s then
		TweenService:Create(s, TweenInfo.new(seconds or 1, Enum.EasingStyle.Sine), { Volume = volume }):Play()
	end
end

local function dof(focus, radius, far, near, seconds)
	local d = Lighting:FindFirstChildOfClass("DepthOfFieldEffect")
	if not d then
		return
	end
	if not S.SavedDof then
		S.SavedDof = { FocusDistance = d.FocusDistance, InFocusRadius = d.InFocusRadius, FarIntensity = d.FarIntensity, NearIntensity = d.NearIntensity }
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

local function lightning(close)
	local fx = S.Flash
	if not fx then
		return
	end
	task.spawn(function()
		local peak = close and 0.55 or 0.3
		fx.Brightness = peak
		task.wait(0.05)
		fx.Brightness = peak * 0.1
		task.wait(0.08)
		fx.Brightness = peak * 0.75
		TweenService:Create(fx, TweenInfo.new(close and 0.7 or 0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Brightness = 0 }):Play()
	end)
	task.delay(close and 0.2 or 1.3, function()
		ctx.Audio.Play(close and "ThunderClose" or "Thunder", nil, close and 0.8 or 0.6)
	end)
end

local function fade(transparency, seconds)
	TweenService:Create(G.Black, TweenInfo.new(seconds, Enum.EasingStyle.Sine), { BackgroundTransparency = transparency }):Play()
end

local function bars(on, seconds)
	local info = TweenInfo.new(seconds or 1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	TweenService:Create(G.BarTop, info, { Size = UDim2.new(1, 0, on and 0.1 or 0, 0) }):Play()
	TweenService:Create(G.BarBottom, info, { Size = UDim2.new(1, 0, on and 0.1 or 0, 0) }):Play()
end

-- Капли на объективе (только снаружи)
local function spawnDrop()
	local size = math.random(8, 24)
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
	f.Parent = G.Lens
	table.insert(S.Drops, { Frame = f, Stroke = st, Born = os.clock(), Life = 2.5 + math.random() * 4, Vy = 0, Run = math.random() < 0.3, Alpha = 0 })
end

local function updateDrops(dt)
	if S.LensOn and #S.Drops < 30 and math.random() < dt * 5 then
		spawnDrop()
	end
	for i = #S.Drops, 1, -1 do
		local d = S.Drops[i]
		local age = os.clock() - d.Born
		local want = (S.LensOn and age < d.Life) and 1 or 0
		d.Alpha = d.Alpha + (want - d.Alpha) * math.min(1, dt * (want > 0 and 6 or 2.5))
		d.Frame.BackgroundTransparency = 1 - d.Alpha * 0.2
		d.Stroke.Transparency = 1 - d.Alpha * 0.45
		if d.Run and age > 0.8 then
			d.Vy = math.min(0.35, d.Vy + dt * 0.25)
			d.Frame.Position = d.Frame.Position + UDim2.fromScale(0, d.Vy * dt)
		end
		if d.Alpha < 0.02 and want == 0 then
			d.Frame:Destroy()
			table.remove(S.Drops, i)
		end
	end
end

-- Где камера: в салоне (вместе с машиной) — eyes/targets в координатах машины
local function carShot(duration, eyes, targets, fovFrom, fovTo)
	setShot(duration, function(u)
		local cf = S.Car and S.Car.BodyCF
		if not cf then
			return nil
		end
		local a = easeSine(u)
		return cf * CFrame.lookAt(spline(eyes, a), spline(targets, a)), fovFrom + (fovTo - fovFrom) * a
	end, true)
end

-- План на голову актёра role: камера в координатах машины (eye), цель — его голова (живая)
local function carFaceShot(duration, role, eyes, fovFrom, fovTo, offset)
	setShot(duration, function(u)
		local cf = S.Car and S.Car.BodyCF
		local a = S.Actors[role]
		if not cf then
			return nil
		end
		local e = easeSine(u)
		local target = (a and a.HeadPart) and a.HeadPart.Position or cf * CAR.Seats[role].Pos + Vector3.new(0, 4.8, 0)
		return CFrame.lookAt(cf * spline(eyes, e), target + (offset or Vector3.zero)), fovFrom + (fovTo - fovFrom) * e
	end, true)
end

-- План на голову актёра снаружи: камера от его лица по направлению взгляда (dist, высота, сдвиг вбок)
local function faceShot(duration, role, dist, side, up, fovFrom, fovTo)
	setShot(duration, function(u)
		local a = S.Actors[role]
		if not (a and a.HeadPart) then
			return nil
		end
		local head = a.HeadPart.Position
		local f = Vector3.new(a.Forward.X, 0, a.Forward.Z)
		local r = f:Cross(Vector3.new(0, 1, 0))
		local e = easeSine(u)
		local eye = head + f * (dist - 0.4 * e) + r * side + Vector3.new(0, up, 0)
		return CFrame.lookAt(eye, head + Vector3.new(0, -0.1, 0)), fovFrom + (fovTo - fovFrom) * e
	end)
end

-------------------------------------------------------------------------------
-- Сценарий
-------------------------------------------------------------------------------
local function present(role)
	return S.Actors[role] ~= nil
end

-- Кто говорит реплику метки cue (роль) — по расписанию
local function roleOf(cue)
	local item = S.ByCue[cue]
	return item and item.Role
end

local function A(cue)
	return S.ByCue[cue].At
end

local function E(cue)
	local c = S.ByCue[cue]
	return c.At + c.Len
end

local function timeline()
	local n = S.Count
	local car = S.Car
	local cam = workspace.CurrentCamera

	---------------------------------------------------------------- 1. ПОЕЗДКА
	-- в темноте: дождь по крыше, дворники, мотор, тихое радио
	ctx.Audio.SetInCar(true)
	loopOn("CarRain", "Rain", 0.5)
	loopOn("CarEngine", "Engine", 0.4)
	loopOn("Wipers", "Wipers", 0.3)
	radioOn(0.1)
	if car then
		car.WipersOn = true
		setCarLights(true, false)
		driveThrough(470, 9.0, 30)
	end
	setRig(0.1, 0.35)
	dof(9, 4, 0.25, 0)
	-- план 1: сквозь лобовое стекло (дворники в кадре) — водитель и пассажир; медленный наезд
	carShot(7.4, { Vector3.new(0.25, 5.35, 8.9), Vector3.new(0.1, 5.25, 8.4) }, { Vector3.new(0.1, 4.75, 0.7), Vector3.new(0, 4.7, 0.6) }, 47, 42)
	at(1.6)
	fade(0, 0.01)
	at(2.4)
	fade(1, 2.0)
	bars(true, 2.0)

	-- план 2: задний ряд (при двоих — пассажир крупно сбоку)
	at(A("Why") - 0.55)
	if present("BackLeft") or present("BackRight") then
		carShot(5.6, { Vector3.new(0.1, 5.3, 1.95), Vector3.new(-0.1, 5.25, 1.75) }, { Vector3.new(0.2, 4.6, -2.6), Vector3.new(-0.1, 4.6, -2.6) }, 56, 52)
		dof(4.3, 2.5, 0.25, 0.1)
	else
		carFaceShot(5.6, "Passenger", { Vector3.new(-6.1, 5.1, 2.2), Vector3.new(-5.9, 5.05, 1.9) }, 40, 37)
		dof(5.6, 2.5, 0.3, 0)
	end

	-- план 3: над плечами задних — дорога сквозь лобовое, дворники; общий смешок
	at(A("Popular") - 0.3)
	if car then
		driveThrough(600, A("Popular") + 1.0, 30)
	end
	carShot(E("Laugh") - A("Popular") + 0.6, { Vector3.new(0, 5.6, -4.25), Vector3.new(0.15, 5.55, -3.95) }, { Vector3.new(0, 4.4, 9), Vector3.new(0.3, 4.4, 9) }, 62, 58)
	dof(12, 9, 0.2, 0.15)

	-- план 4: водитель крупно (от пассажирской стороны торпедо)
	at(A("Relax") - 0.25)
	carFaceShot(E("Relax") - A("Relax") + 1.2, "Driver", { Vector3.new(-0.85, 4.95, 3.75), Vector3.new(-0.7, 4.9, 3.6) }, 42, 39)
	dof(3.6, 2, 0.35, 0.1)
	after(E("Relax") - A("Relax") + 0.4, function()
		lightning(false)
	end)

	-- план 5: сбоку сквозь окно (кто спрашивает «Кстати…») — потом «Надеюсь, ничего интересного»
	at(A("Know") - 0.5)
	if car then
		driveThrough(560, A("Know") + 1.0, 30)
	end
	local know = roleOf("Know")
	local seatK = CAR.Seats[know]
	local sx = seatK.Side * 6.3
	carFaceShot(E("Hope") - A("Know") + 1.0, know, { Vector3.new(sx, 5.2, seatK.Pos.Z + 1.6), Vector3.new(sx * 0.97, 5.15, seatK.Pos.Z + 1.2) }, 44, 41)
	dof(6.1, 3, 0.35, 0)

	---------------------------------------------------------------- 2. СТРАННОСТИ
	-- радио теряет волну: магнитола крупно, помехи
	at(A("Radio") - 1.4)
	S.Loops.Static = ctx.Audio.Play("RadioStatic", nil, 0.9)
	loopOff("Radio", 0.35)
	if car then
		car.RadioGlow.Brightness = 0.9
	end
	carShot(E("Off") - A("Radio") + 2.2, { Vector3.new(-0.9, 5.0, 0.2), Vector3.new(-0.75, 4.9, 0.6) }, { Vector3.new(0.2, 3.7, 3.1), Vector3.new(0.35, 3.75, 3.0) }, 46, 40)
	dof(3.2, 1.5, 0.4, 0.2)
	-- водитель тянется к магнитоле на «Выключи его уже» и щёлкает кнопкой
	local driver = S.Actors.Driver
	at(A("Off") + 0.2)
	if driver then
		driver.HandsBusy = true
		ik(driver, "R", CAR.Radio + Vector3.new(0, 0.05, -0.12), true, 1, 0.2, 4.5)
	end
	at(E("Off") + 0.35)
	ctx.Audio.Play("RadioOff", nil, 0.9)
	if S.Loops.Static then
		pcall(function()
			S.Loops.Static:Stop()
		end)
		S.Loops.Static = nil
	end
	if car then
		car.RadioGlow.Brightness = 0
	end
	after(0.5, function()
		if driver then
			driver.HandsBusy = false
		end
	end)

	-- тишина, только дождь; у обочины под мигающим фонарём — фигура
	local seer = roleOf("Saw")
	local side = CAR.Seats[seer].Side -- +1: со стороны водителя (север), −1 — пассажира (юг)
	local figX = 238
	local figZ = CAR.RoadZ + side * 9.5
	local passT = A("Saw") - 1.6 -- машина проезжает фигуру
	local lamp = makeRoadLamp(Vector3.new(figX - 4, 0, CAR.RoadZ + side * 12))
	local figure = makeFigure("RoadFigure", Vector3.new(figX, groundAt(Vector3.new(figX, 0, figZ)), figZ), Vector3.new(figX, 0, CAR.RoadZ))
	task.spawn(function()
		-- фонарь мигает (плохой контакт)
		while S.Playing and lamp.Light.Parent do
			lamp.Light.Enabled = math.random() > 0.18
			task.wait(0.05 + math.random() * 0.25)
		end
	end)
	at(E("Off") + 1.0)
	if car then
		driveThrough(figX, passT, 26)
	end
	-- снаружи: камера у обочины за фигурой (фигура — тёмное пятно не в фокусе), машина проносится
	ctx.Audio.SetInCar(false)
	S.LensOn = true
	setRig(0.25, 0.5)
	local camAt = Vector3.new(figX + 7, 4.2, CAR.RoadZ + side * 16)
	setShot(A("Saw") - (E("Off") + 1.0) - 1.0, track({ camAt, camAt + Vector3.new(-2, 0.2, 0) }, { Vector3.new(figX - 10, 3, CAR.RoadZ), Vector3.new(figX - 22, 3, CAR.RoadZ) }, 52, 50))
	dof(22, 8, 0.6, 0.55)
	-- в салоне: тот, кто заметил, провожает фигуру взглядом в окно
	at(A("Saw") - 1.0)
	ctx.Audio.SetInCar(true)
	S.LensOn = false
	setRig(0.12, 0.35)
	local seerA = S.Actors[seer]
	if seerA then
		seerA.LookAt, seerA.LookInCar, seerA.LookUntil = nil, false, nil
		task.spawn(function()
			while seerA.Model and now() < E("Saw") do
				seerA.LookAt = figure.PrimaryPart and figure.PrimaryPart.Position or Vector3.new(figX, 5, figZ)
				seerA.LookInCar = false
				RunService.Heartbeat:Wait()
			end
			seerA.LookAt = nil
		end)
	end
	local seatS = CAR.Seats[seer]
	carFaceShot(E("Saw") - A("Saw") + 1.0, seer, { Vector3.new(-seatS.Side * 1.0, 5.25, seatS.Pos.Z + 1.7), Vector3.new(-seatS.Side * 0.8, 5.2, seatS.Pos.Z + 1.5) }, 50, 45, Vector3.new(seatS.Side * 0.6, 0, 0))
	dof(2.6, 2, 0.4, 0.3)
	-- «Что?» — водитель смотрит в зеркало
	at(A("What") - 0.25)
	carFaceShot(E("What") - A("What") + 0.9, "Driver", { Vector3.new(-0.6, 5.0, 3.6), Vector3.new(-0.5, 5.0, 3.5) }, 36, 35)
	dof(3.4, 1.6, 0.4, 0.1)
	if driver then
		driver.LookAt, driver.LookInCar, driver.LookUntil = CAR.Mirror, true, E("What") + 0.6
	end
	-- в заднем стекле: дорога и фонарь — фигуры уже нет
	at(E("What") + 0.65)
	if figure then
		figure:Destroy()
	end
	carShot(E("Nothing") - E("What") + 0.6, { Vector3.new(0, 5.15, -2.55), Vector3.new(0, 5.15, -2.75) }, { Vector3.new(0, 4.2, -40), Vector3.new(-0.5, 4.3, -40) }, 48, 44)
	dof(30, 20, 0.15, 0.4)

	---------------------------------------------------------------- 3. ПРИБЫТИЕ
	-- вывеска выплывает из тумана; машина сворачивает на парковку и медленно встаёт
	local arriveT = E("Nothing") + 0.6
	at(arriveT)
	if lamp then
		lamp.Pole:Destroy()
		lamp.Head:Destroy()
	end
	local stopT = A("Store") + 1.2
	driveToSpot(arriveT - 1.0, stopT - (arriveT - 1.0))
	loopOn("TurnSignal", "Signal", 0.35)
	ctx.Audio.SetInCar(false)
	S.LensOn = true
	setRig(0.3, 0.45)
	setShot(A("Arrived") - arriveT - 0.2, track(
		{ Vector3.new(-12, 6.5, 108), Vector3.new(-15, 6.2, 103) },
		{ Vector3.new(-40, 9.5, 54), Vector3.new(-36, 6, 66) },
		44, 40))
	dof(40, 30, 0.2, 0)
	bedTo("TensionDrone", 0.12, 4)
	-- в салоне сквозь лобовое: смотрят на магазин
	at(A("Arrived") - 0.2)
	ctx.Audio.SetInCar(true)
	S.LensOn = false
	setRig(0.1, 0.35)
	carShot(A("Peculiar") - A("Arrived") + 0.2, { Vector3.new(0.2, 5.3, 8.8), Vector3.new(0.05, 5.25, 8.3) }, { Vector3.new(0, 4.8, 0.4), Vector3.new(0, 4.75, 0) }, 50, 46)
	dof(8.5, 5, 0.25, 0)
	local sign = Vector3.new(-48, 12.5, 51.8)
	for _, a in pairs(S.Actors) do
		if a.Role ~= "Driver" then
			a.LookAt, a.LookInCar, a.LookUntil = sign, false, A("Peculiar")
		end
	end
	-- пассажир наклоняется к стеклу: «Это и есть наш магазин?»
	if S.Actors.Passenger then
		S.Actors.Passenger.Lean = -0.12
		after(A("Peculiar") - now(), function()
			if S.Actors.Passenger then
				S.Actors.Passenger.Lean = 0
			end
		end)
	end
	at(stopT - 0.4)
	loopOff("Signal")
	at(stopT + 0.3)
	ctx.Audio.Play("Handbrake", nil, 0.7)
	if car then
		car.WipersOn = false
	end
	after(0.9, function()
		loopOff("Engine", 0.6)
		loopOff("Wipers", 0.4)
		setCarLights(false, false)
		if car then
			car.Dash.Brightness = 0.12
		end
		carBump(-0.4, 0)
	end)
	-- сзади: магазин за лобовым стеклом
	at(A("Peculiar") - 0.2)
	carShot(E("LetsGo") - A("Peculiar") + 0.6, { Vector3.new(0, 5.6, -4.2), Vector3.new(0.1, 5.5, -3.9) }, { Vector3.new(0, 4.6, 9), Vector3.new(0, 5.2, 9) }, 58, 52)
	dof(14, 10, 0.2, 0.2)
	for _, a in pairs(S.Actors) do
		a.LookAt, a.LookInCar, a.LookUntil = sign, false, E("LetsGo")
	end

	---------------------------------------------------------------- 4. ВЫХОД
	local exitT = E("LetsGo") + 0.5
	at(exitT)
	ctx.Audio.SetInCar(false)
	loopOff("Rain", 0.3)
	S.LensOn = true
	setRig(0.28, 0.5)
	-- снаружи со стороны водителя: двери открываются по очереди
	local spot = CAR.Spot
	setShot(A("Cold") - exitT - 0.4, track(
		{ Vector3.new(spot.X - 16, 4.4, spot.Z - 13), Vector3.new(spot.X - 14.5, 4.9, spot.Z - 12) },
		{ Vector3.new(spot.X - 1, 3.6, spot.Z), Vector3.new(spot.X - 2, 3.9, spot.Z + 0.5) },
		46, 42))
	dof(19, 10, 0.35, 0.1)
	local order = { "Driver", "Passenger", "BackLeft", "BackRight" }
	local delays = { Driver = 0.2, Passenger = 0.55, BackLeft = 0.95, BackRight = 1.3 }
	for _, role in ipairs(order) do
		exitCar(S.Actors[role], delays[role])
	end
	-- у капота собираются вместе (кто вышел справа — обходит машину спереди)
	local gather = {
		Driver = Vector3.new(spot.X - 4.6, 0, spot.Z - 12.8),
		BackLeft = Vector3.new(spot.X - 7.4, 0, spot.Z - 11.6),
		Passenger = Vector3.new(spot.X - 1.6, 0, spot.Z - 13.4),
		BackRight = Vector3.new(spot.X + 1.2, 0, spot.Z - 12.2),
	}
	S.Gather = gather
	at(exitT + 3.6)
	for role, a in pairs(S.Actors) do
		if not a.InCar then
			local g = gather[role]
			if CAR.Seats[role].Side < 0 then
				actorGo(a, { Vector3.new(spot.X + 6.2, 0, spot.Z - 6.5), Vector3.new(spot.X + 3, 0, spot.Z - 11.6), g }, 4.6)
			else
				actorGo(a, { Vector3.new(spot.X - 6.2, 0, spot.Z - 6), g }, 4.2)
			end
			a.Face = Vector3.new(-52, 0, 50)
		end
	end
	-- пар изо рта у всех; «Ну и холодина…» — растирает ладони
	for _, a in pairs(S.Actors) do
		if a.Breath then
			a.Breath.Rate = 1.6
		end
	end
	local cold = roleOf("Cold")
	at(A("Cold") - 0.4)
	local coldA = S.Actors[cold]
	faceShot(E("Funny") - A("Cold") + 0.3, cold, 7.2, 1.6, 0.6, 38, 35)
	dof(7.2, 3, 0.45, 0.2)
	if coldA and coldA.IK and coldA.IK.L then
		task.spawn(function()
			local stopAt = E("Cold") + 0.8
			while coldA.Model and now() < stopAt do
				local cf = coldA.Root.CFrame
				local w = math.sin(now() * 14) * 0.18
				ik(coldA, "L", cf * Vector3.new(0.18 + w, 0.35, -0.95), false, 1, 0.3, 12)
				ik(coldA, "R", cf * Vector3.new(-0.18 + w, 0.32, -0.95), false, 1, 0.3, 12)
				RunService.Heartbeat:Wait()
			end
			ik(coldA, "L", Vector3.zero, false, 0, 0.4)
			ik(coldA, "R", Vector3.zero, false, 0, 0.4)
		end)
	end
	-- свой персонаж: у каждого игрока — короткий план его аватара (камеры у всех разные)
	at(E("Funny") + 0.05)
	local mine = S.Me and S.Actors[S.Me]
	if mine then
		faceShot(2.0, S.Me, 5.6, -1.4, 0.4, 40, 37)
		dof(5.6, 2.5, 0.45, 0.2)
	end
	-- отъезд: команда перед магазином, вывеска над входом
	at(E("Funny") + (mine and 1.9 or 0.1))
	setShot(E("Laugh2") - now() + 3.4, track(
		{ Vector3.new(spot.X - 2, 5.2, spot.Z - 22), Vector3.new(spot.X - 1, 9.5, spot.Z - 30) },
		{ Vector3.new(spot.X - 4, 4.2, spot.Z - 12), Vector3.new(-46, 7.5, 52) },
		50, 56))
	dof(18, 14, 0.25, 0)
	-- идут ко входу: первым — водитель (или кто есть), остальные следом
	at(E("Laugh2") + 0.3)
	local leaderRole = present("Driver") and "Driver" or (present("Passenger") and "Passenger" or nil)
	for _, a in pairs(S.Actors) do
		a.Path = {}
	end
	local queue = { Driver = { -52.2, 53.6 }, Passenger = { -49.6, 55.2 }, BackLeft = { -54.6, 55.6 }, BackRight = { -51.8, 57.4 } }
	for role, a in pairs(S.Actors) do
		local q = queue[role]
		local g = gather[role]
		actorGo(a, { Vector3.new(g.X - 7, 0, g.Z - 2.5), Vector3.new(q[1] + 4, 0, q[2] + 1.2), Vector3.new(q[1], 0, q[2]) }, role == leaderRole and 4.8 or 4.4)
		a.Face = Vector3.new(-52, 0, 40)
		if a.Breath then
			a.Breath.Rate = 0.9
		end
	end

	---------------------------------------------------------------- 5. ДВЕРИ
	-- изнутри сквозь стекло: подходят; датчик зеленеет, створки разъезжаются
	at(A("Doors") - 3.4)
	S.LensOn = false
	setShot(A("Doors") + 0.2 - now(), track({ Vector3.new(-52.6, 5.4, 41.5), Vector3.new(-52.4, 5.6, 42.4) }, { Vector3.new(-52, 5.2, 56), Vector3.new(-52, 5.6, 54) }, 50, 46))
	dof(10, 6, 0.3, 0.1)
	at(A("Doors") - 1.5)
	sensorSees(true)
	ctx.Audio.Play("DoorSensor", SENSOR_POS, 0.6)
	at(A("Doors") - 1.2)
	moveDoors(true, 1.6)
	local leader = leaderRole and S.Actors[leaderRole]
	if leader then
		leader.LookAt, leader.LookInCar, leader.LookUntil = SENSOR_POS, false, A("Doors") + 0.6
	end
	-- снаружи за спинами: первый кивает на двери; «Пойдём уже.»
	at(A("Doors") + 0.2)
	S.LensOn = true
	setShot(E("Come") - now() + 1.0, track({ Vector3.new(-50.2, 5.6, 63.5), Vector3.new(-50.8, 5.5, 61.8) }, { Vector3.new(-52, 4.8, 52), Vector3.new(-52, 4.9, 49) }, 48, 45))
	dof(10, 6, 0.3, 0.1)
	at(E("Come") + 0.1)
	-- все входят и встают у входа, лицом в зал
	local enterOrder = {}
	for _, role in ipairs({ "Driver", "Passenger", "BackLeft", "BackRight" }) do
		if S.Actors[role] then
			table.insert(enterOrder, role)
		end
	end
	for i, role in ipairs(enterOrder) do
		local a = S.Actors[role]
		local endSpot = TeamLines.EndSpots[role]
		after((i - 1) * 0.55, function()
			if a.Model then
				actorGo(a, { Vector3.new(-52, 0, 50.5), Vector3.new(-52 + (endSpot.X + 52) * 0.4, 0, 46), endSpot }, 4.4)
				a.Face = Vector3.new(endSpot.X, 0, 20)
				if a.Breath then
					a.Breath.Rate = 0
				end
			end
		end)
	end
	-- изнутри: последний вошёл — двери закрываются за спинами
	at(E("Come") + 0.6)
	S.LensOn = false
	ctx.Audio.SetInCar(false)
	setShot(A("Feel") - now() - 0.3, track({ Vector3.new(-56.5, 6.2, 31.5), Vector3.new(-55.4, 6.0, 33.0) }, { Vector3.new(-51, 4.6, 46), Vector3.new(-51, 4.8, 47.5) }, 50, 46))
	dof(14, 9, 0.25, 0.1)
	loopOn("Fridge", "Fridge", 0.22)
	loopOn("Fluorescent", "Fluor", 0.14)
	local closeT = E("Come") + 0.1 + (#enterOrder - 1) * 0.55 + 3.2
	at(math.min(closeT, A("Feel") - 1.0))
	moveDoors(false, 1.5)
	after(1.4, function()
		sensorSees(false)
	end)

	---------------------------------------------------------------- 6. ПОДОЗРЕНИЕ
	dimAisle(true)
	local aisle = Vector3.new(-42.5, 0, 1.5)
	local aisleFig = makeFigure("AisleFigure", Vector3.new(aisle.X, groundAt(aisle), aisle.Z), Vector3.new(-48, 0, 40))
	local feel = roleOf("Feel")
	at(A("Feel") - 0.3)
	local feelA = S.Actors[feel]
	if feelA then
		-- оглядывается
		feelA.LookAt, feelA.LookInCar, feelA.LookUntil = Vector3.new(-30, 8, 20), false, A("Feel") + 1.2
	end
	setShot(E("Feel") - now() + 0.2, function(u)
		local a = S.Actors[feel]
		local head = (a and a.HeadPart) and a.HeadPart.Position or Vector3.new(-48, 5, 41)
		local e = easeSine(u)
		local eye = Vector3.new(head.X - 1.2, 5.6, head.Z - 9.2 + 2.4 * e)
		return CFrame.lookAt(eye, head + Vector3.new(0, -0.15, 0)), 44 - 6 * e
	end)
	dof(8, 3, 0.4, 0.1, 3)
	bedTo("TensionDrone", 0.3, 3)
	-- «Да перестань. Мы только пришли.»
	at(A("Stop") - 0.2)
	local stopRole = roleOf("Stop")
	setShot(E("Stop") - now() + 0.3, function(u)
		local a = S.Actors[stopRole]
		local head = (a and a.HeadPart) and a.HeadPart.Position or Vector3.new(-49, 5, 40)
		local e = easeSine(u)
		return CFrame.lookAt(Vector3.new(head.X + 1.6, 5.5, head.Z - 7.4 + 0.6 * e), head), 40
	end)
	dof(7.4, 3, 0.4, 0.1)
	-- все поворачиваются к дальнему ряду: в конце — силуэт
	at(E("Stop") + 0.3)
	for _, a in pairs(S.Actors) do
		a.LookAt, a.LookInCar, a.LookUntil = Vector3.new(aisle.X, 5, aisle.Z), false, A("Instr") - 0.4
		a.Face = Vector3.new(aisle.X, 0, aisle.Z)
	end
	setRig(0.18, 0.4)
	setShot(2.1, track({ Vector3.new(-46.8, 5.3, 44.2), Vector3.new(-46.6, 5.3, 43.6) }, { Vector3.new(-42.6, 4.2, 2), Vector3.new(-42.6, 4.3, 2) }, 30, 26))
	dof(42, 8, 0.2, 0.6)
	ctx.Audio.Play("DarkHit", nil, 0.3, 0.8)
	-- снова лицо…
	at(E("Stop") + 2.4)
	setShot(1.3, function()
		local a = S.Actors[feel] or S.Actors[stopRole]
		local head = (a and a.HeadPart) and a.HeadPart.Position or Vector3.new(-48, 5, 41)
		local f = a and a.Forward or Vector3.new(0, 0, -1)
		return CFrame.lookAt(head + f * 4.8 + Vector3.new(0, 0.3, 0), head), 38
	end)
	dof(4.8, 2, 0.4, 0.1)
	-- …и ряд пуст
	at(E("Stop") + 3.7)
	if aisleFig then
		aisleFig:Destroy()
	end
	setShot(1.4, track({ Vector3.new(-46.6, 5.3, 43.6), Vector3.new(-46.5, 5.3, 43.2) }, { Vector3.new(-42.6, 4.3, 2), Vector3.new(-42.6, 4.3, 2) }, 26, 25))
	-- «Ладно, давайте сначала найдём инструкции.» — общий план команды
	at(A("Instr") - 0.3)
	for _, a in pairs(S.Actors) do
		a.Face = Vector3.new(a.Pos.X, 0, 20)
	end
	setRig(0.12, 0.35)
	setShot(E("Instr") - now() + 0.5, track({ Vector3.new(-50.8, 5.7, 30.5), Vector3.new(-50.8, 5.6, 31.8) }, { Vector3.new(-50.6, 4.5, 41.5), Vector3.new(-50.6, 4.5, 41.5) }, 54, 50))
	dof(10.5, 6, 0.25, 0)

	---------------------------------------------------------------- 7. ФИНАЛ
	at(E("Instr") + 0.4)
	bedTo("TensionDrone", 0.0, 4)
	ctx.Audio.Play("Riser", nil, 0.3)
	setShot(S.Total - now(), track(
		{ Vector3.new(-50.8, 5.6, 32), Vector3.new(-50.5, 10, 26), Vector3.new(-50, 17, 18) },
		{ Vector3.new(-50.6, 4.4, 41.5), Vector3.new(-50.5, 4, 40), Vector3.new(-50.5, 2.5, 38) },
		50, 58))
	dof(16, 18, 0.2, 0)
	at(E("Instr") + 1.6)
	TeamCinematic.TitleReveal()
	at(S.Total - 1.6)
	fade(0, 1.4)
	at(S.Total)
	local _ = n
	local _ = cam
end

-------------------------------------------------------------------------------
-- Титр: MARKET 24 зажигается по буквам, ниже — NIGHT SHIFT · TEAM EDITION и время
-------------------------------------------------------------------------------
function TeamCinematic.TitleReveal()
	local main = G.TitleMain
	local text = main.Text
	local n = utf8.len(text) or #text
	main.MaxVisibleGraphemes = 0
	main.TextTransparency = 0
	TweenService:Create(G.TitleScale, TweenInfo.new(4, Enum.EasingStyle.Sine), { Scale = 1 }):Play()
	task.spawn(function()
		for i = 1, n do
			main.MaxVisibleGraphemes = i
			if i % 2 == 1 then
				ctx.Audio.Play("NeonBuzz", nil, 0.3, 0.9 + math.random() * 0.25)
			end
			task.wait(0.07)
		end
		main.MaxVisibleGraphemes = -1
		for _ = 1, 2 do
			main.TextTransparency = 0.7
			task.wait(0.05)
			main.TextTransparency = 0
			task.wait(0.09)
		end
		ctx.Audio.Play("DarkHit", nil, 0.5)
		local info = TweenInfo.new(0.9, Enum.EasingStyle.Sine)
		TweenService:Create(G.TitleLine, info, { BackgroundTransparency = 0.2 }):Play()
		TweenService:Create(G.TitleSub, info, { TextTransparency = 0.1 }):Play()
		task.wait(0.8)
		ctx.Audio.Play("ClockBeep", nil, 0.4)
		TweenService:Create(G.TitleTime, info, { TextTransparency = 0.2 }):Play()
	end)
end

-------------------------------------------------------------------------------
-- Интерфейс
-------------------------------------------------------------------------------
local function buildGui()
	local gui = UI.new("ScreenGui", {
		Name = "TeamIntro",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 41,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Enabled = false,
	}, ctx.Player:WaitForChild("PlayerGui"))
	G.Gui = gui
	G.BarTop = UI.new("Frame", { Name = "BarTop", Size = UDim2.new(1, 0, 0, 0), BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, ZIndex = 5 }, gui)
	G.BarBottom = UI.new("Frame", { Name = "BarBottom", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 0), BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, ZIndex = 5 }, gui)
	G.Lens = UI.new("Frame", { Name = "Lens", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 4 }, gui)
	G.Grain = UI.new("ImageLabel", {
		Name = "Grain",
		Size = UDim2.new(1, 128, 1, 128),
		BackgroundTransparency = 1,
		Image = Config.Images.CctvNoise,
		ImageTransparency = 0.94,
		ScaleType = Enum.ScaleType.Tile,
		TileSize = UDim2.fromOffset(128, 128),
		ZIndex = 4,
	}, gui)
	-- титр
	local holder = UI.new("Frame", { Name = "Title", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.45), Size = UDim2.fromOffset(820, 220), BackgroundTransparency = 1, ZIndex = 6 }, gui)
	UI.scaled(holder)
	local inner = UI.new("Frame", { Name = "Inner", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 6 }, holder)
	G.TitleScale = UI.new("UIScale", { Scale = 1.03 }, inner)
	G.TitleMain = UI.text("MARKET 24", { Size = UDim2.new(1, 0, 0, 100), TextSize = 92, Font = Enum.Font.GothamBlack, TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = Color3.fromRGB(238, 238, 234), TextTransparency = 1, ZIndex = 6 }, inner)
	G.TitleLine = UI.new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 110), Size = UDim2.fromOffset(150, 3), BackgroundColor3 = UI.Colors.Accent, BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 6 }, inner)
	G.TitleSub = UI.text("NIGHT SHIFT · TEAM EDITION", { Position = UDim2.fromOffset(0, 126), Size = UDim2.new(1, 0, 0, 32), TextSize = 26, Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = Color3.fromRGB(206, 210, 216), TextTransparency = 1, ZIndex = 6 }, inner)
	G.TitleTime = UI.text("02:37 AM", { Position = UDim2.fromOffset(0, 168), Size = UDim2.new(1, 0, 0, 26), TextSize = 20, Font = Enum.Font.Code, TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = Color3.fromRGB(200, 70, 60), TextTransparency = 1, ZIndex = 6 }, inner)
	-- субтитры: имя говорящего его цветом и реплика; на телефоне переносятся в две строки
	local sub = UI.new("Frame", { Name = "Subtitles", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -18), Size = UDim2.fromOffset(880, 64), BackgroundTransparency = 1, ZIndex = 7 }, gui)
	UI.scaled(sub)
	G.SubBack = UI.new("Frame", { Name = "Back", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 7 }, sub)
	UI.corner(G.SubBack, 10)
	G.SubText = UI.text("", {
		Size = UDim2.new(1, -24, 1, 0),
		Position = UDim2.fromOffset(12, 0),
		TextSize = 24,
		RichText = true,
		Font = Enum.Font.GothamMedium,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
		TextColor3 = Color3.fromRGB(244, 242, 236),
		TextStrokeColor3 = Color3.new(0, 0, 0),
		TextStrokeTransparency = 1,
		TextTransparency = 1,
		ZIndex = 8,
	}, sub)
	-- «Пропустить»: крупная кнопка в углу (пальцем на телефоне попасть легко)
	G.Skip = UI.button("Пропустить", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -20, 0, 20),
		Size = UDim2.fromOffset(176, 46),
		TextSize = 16,
		BackgroundColor3 = Color3.fromRGB(12, 14, 18),
		BackgroundTransparency = 0.35,
		TextColor3 = Color3.fromRGB(220, 220, 220),
		Modal = true,
		ZIndex = 9,
		Visible = false,
	}, gui, function()
		S.Cancelled = true
	end)
	UI.scaled(G.Skip)
	G.Wait = UI.text("", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -40),
		Size = UDim2.fromOffset(640, 60),
		TextSize = 20,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = Color3.fromRGB(214, 214, 214),
		TextStrokeTransparency = 0.5,
		Visible = false,
		ZIndex = 11,
	}, gui)
	UI.scaled(G.Wait)
	G.Black = UI.new("Frame", { Name = "Black", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0, BorderSizePixel = 0, ZIndex = 10 }, gui)
end

-------------------------------------------------------------------------------
-- Запуск, уборка, ожидание остальных
-------------------------------------------------------------------------------
local function reset()
	S.Cancelled = false
	S.Token = (S.Token or 0) + 1
	S.Hidden = {}
	S.Actors = {}
	S.Loops = {}
	S.Drops = {}
	S.Gone = {}
	S.Names = {}
	S.Rig = { Shake = 0, Freq = 0.4 }
	S.Shot = nil
	S.PrevCam = nil
	S.Speaking = nil
	S.LineIdx = 1
	S.LensOn = false
	S.Car = nil
	S.Doors = nil
	S.Sensor = nil
	S.Dimmed = nil
	S.ExtraChars = {}
end

local function cleanup()
	pcall(function()
		RunService:UnbindFromRenderStep("NS_TeamCinematic")
	end)
	if S.FrameConn then
		S.FrameConn:Disconnect()
		S.FrameConn = nil
	end
	if S.StepConn then
		S.StepConn:Disconnect()
		S.StepConn = nil
	end
	if S.LeaveConn then
		S.LeaveConn:Disconnect()
		S.LeaveConn = nil
	end
	if S.Blur then
		S.Blur:Destroy()
		S.Blur = nil
	end
	if S.Flash then
		S.Flash:Destroy()
		S.Flash = nil
	end
	for _, d in ipairs(S.Drops or {}) do
		d.Frame:Destroy()
	end
	S.Drops = {}
	S.LensOn = false
	S.Shot = nil
	S.Token = (S.Token or 0) + 1
	for key in pairs(S.Loops or {}) do
		loopOff(key)
	end
	if S.Voice then
		pcall(function()
			S.Voice:Stop()
		end)
		S.Voice = nil
	end
	subtitle(nil)
	dimAisle(false)
	for role in pairs(S.Actors or {}) do
		removeActor(role)
	end
	S.Car = nil
	S.Doors = nil
	S.Sensor = nil
	for d, kind in pairs(S.Hidden or {}) do
		if d.Parent then
			if kind == "Gui" then
				d.Enabled = true
			else
				d.LocalTransparencyModifier = 0
			end
		end
	end
	S.Hidden = {}
	if S.Folder then
		S.Folder:Destroy()
		S.Folder = nil
	end
	hideCharacters(false)
	if S.SavedNames then
		local names = S.SavedNames
		pcall(function()
			ctx.Player.NameDisplayDistance = names.Name
			ctx.Player.HealthDisplayDistance = names.Health
		end)
		S.SavedNames = nil
	end
	local d = Lighting:FindFirstChildOfClass("DepthOfFieldEffect")
	if d and S.SavedDof then
		for k, v in pairs(S.SavedDof) do
			d[k] = v
		end
	end
	S.SavedDof = nil
	ctx.Effects.SetGradeTime(1.2)
	ctx.Effects.SetVignetteBoost(0)
	ctx.Effects.SetCinematic(false)
	ctx.Audio.SetCinematic(false)
	ctx.Audio.SetInCar(false)
	ProximityPromptService.Enabled = true
end

-- Игрок вышел из игры посреди сцены: его персонаж исчезает, его реплик больше нет
function TeamCinematic.PlayerLeft(userId)
	if not S.Playing then
		return
	end
	for role, a in pairs(S.Actors or {}) do
		if a.UserId == userId then
			S.Gone[role] = true
			removeActor(role)
			if S.Speaking and S.Speaking.Role == role then
				if S.Voice then
					pcall(function()
						S.Voice:Stop()
					end)
				end
				S.Speaking = nil
				subtitle(nil)
			end
		end
	end
end

function TeamCinematic.IsPlaying()
	return S.Playing
end

-- Ждём остальных: камера смотрит на зал у входа (там уже стоит этот игрок), счётчик досмотревших
local function waitOthers(cam)
	local t = os.clock()
	G.Wait.Visible = true
	cam.CameraType = Enum.CameraType.Scriptable
	local base = Vector3.new(-50.6, 4.6, 41)
	while ctx.State:GetAttribute("Phase") == "Intro" and os.clock() - t < 40 do
		local done = ctx.State:GetAttribute("IntroDone") or 0
		local total = ctx.State:GetAttribute("IntroTotal") or 0
		G.Wait.Text = total > 0 and string.format("Ждём остальных сотрудников… (%d из %d досмотрели)", done, total) or "Ждём остальных сотрудников…"
		local a = os.clock() * 0.12
		cam.CFrame = CFrame.lookAt(base + Vector3.new(math.sin(a) * 3, 2.2, -10.5 + math.cos(a) * 1.2), base)
		cam.FieldOfView = 55
		task.wait()
	end
	G.Wait.Visible = false
end

function TeamCinematic.Play(data)
	if S.Playing or type(data) ~= "table" then
		return
	end
	reset()
	S.Playing = true
	S.StartAt = tonumber(data.StartAt) or workspace:GetServerTimeNow()
	if type(data.From) == "number" and data.From > 0 then
		-- проверка на сервере: начать с середины
		S.StartAt = S.StartAt - data.From
	end
	-- состав: роли игроков, которые ещё в игре
	local roster = {}
	for _, e in ipairs(type(data.Roster) == "table" and data.Roster or {}) do
		if type(e) == "table" and CAR.Seats[e.Role] then
			table.insert(roster, e)
			S.Names[e.Role] = e.Name
			if e.Character then
				table.insert(S.ExtraChars, e.Character)
			end
			if e.UserId == ctx.Player.UserId then
				S.Me = e.Role
			end
		end
	end
	S.Count = math.clamp(#roster, 2, 4)
	local lines, byCue, total = TeamLines.Schedule(S.Count, Sounds.List, VoiceLines.Clips)
	S.Lines, S.ByCue, S.Total = lines, byCue, total
	task.spawn(function()
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
		ctx.Effects.SetVignetteBoost(0.14)
		ctx.Audio.SetCinematic(true)
		bedTo("Music", 0, 1.5)
		bedTo("TensionDrone", 0, 1.5)
		S.Blur = Instance.new("BlurEffect")
		S.Blur.Name = "NS_TeamBlur"
		S.Blur.Size = 0
		S.Blur.Parent = Lighting
		S.Flash = Instance.new("ColorCorrectionEffect")
		S.Flash.Name = "NS_TeamLightning"
		S.Flash.TintColor = Color3.fromRGB(214, 226, 255)
		S.Flash.Brightness = 0
		S.Flash.Parent = Lighting
		ProximityPromptService.Enabled = false
		pcall(function()
			S.SavedNames = { Name = ctx.Player.NameDisplayDistance, Health = ctx.Player.HealthDisplayDistance }
			ctx.Player.NameDisplayDistance = 0
			ctx.Player.HealthDisplayDistance = 0
		end)
		G.Black.BackgroundTransparency = 0
		G.TitleMain.TextTransparency = 1
		G.TitleMain.MaxVisibleGraphemes = -1
		G.TitleSub.TextTransparency = 1
		G.TitleTime.TextTransparency = 1
		G.TitleLine.BackgroundTransparency = 1
		G.TitleScale.Scale = 1.03
		G.Wait.Visible = false
		G.Skip.Visible = false
		G.BarTop.Size = UDim2.new(1, 0, 0, 0)
		G.BarBottom.Size = UDim2.new(1, 0, 0, 0)
		G.Gui.Enabled = true

		S.Folder = Instance.new("Folder")
		S.Folder.Name = "NS_TeamIntro"
		S.Folder.Parent = workspace
		local cam = workspace.CurrentCamera
		cam.CameraType = Enum.CameraType.Scriptable
		local okSetup, setupErr = pcall(function()
			S.Car = makeCar()
			if S.Car then
				driveThrough(470, 9.0, 30)
				setCarLights(false, false)
			end
			for _, e in ipairs(roster) do
				local a = makeActor(e)
				if a then
					S.Actors[e.Role] = a
					if S.Car then
						seatActor(a)
					end
				end
			end
			S.Doors = makeDoors()
			S.Sensor = makeSensor()
		end)
		if not okSetup then
			warn("[Командная сцена] " .. tostring(setupErr))
		end
		updateGroundFilter()
		-- ушедшие до начала: их место пустое
		for _, e in ipairs(roster) do
			local p = Players:GetPlayerByUserId(e.UserId or 0)
			if not p and not e.Character then
				S.Gone[e.Role] = true
				removeActor(e.Role)
			end
		end
		S.LeaveConn = Players.PlayerRemoving:Connect(function(p)
			TeamCinematic.PlayerLeft(p.UserId)
		end)

		local function onFrame(dt)
			local t = now()
			local okC, errC = pcall(updateCar, dt)
			if not okC then
				warn("[Командная сцена] машина: " .. tostring(errC))
				S.Car = nil
			end
			for role, a in pairs(S.Actors) do
				local okA, errA = pcall(updateActor, a, dt, t)
				if not okA then
					warn("[Командная сцена] " .. role .. ": " .. tostring(errA))
					removeActor(role)
				end
			end
			pcall(updateSpeech, t)
			local shot = S.Shot
			if shot then
				local st = t - shot.Start
				local ok, cf, fov = pcall(shot.Eval, clamp01(st / shot.Dur), st, dt)
				if ok and cf then
					if S.Rig.Shake > 0 then
						local a = math.rad(S.Rig.Shake)
						local tt = t * S.Rig.Freq
						cf = cf * CFrame.Angles(math.noise(tt, 1.3) * a, math.noise(tt, 7.1) * a, math.noise(tt, 13.7) * a * 0.5)
					end
					if S.Blur and dt > 0 then
						if S.PrevCam then
							local moved = shot.Still and 0 or (cf.Position - S.PrevCam.Position).Magnitude
							local ang = math.acos(math.clamp(S.PrevCam.LookVector:Dot(cf.LookVector), -1, 1)) / dt
							local want = math.clamp((ang - 0.3) * 5, 0, 7) + math.clamp((moved / dt - 16) * 0.12, 0, 3)
							if moved > 5 then
								want = 0
							end
							S.Blur.Size = S.Blur.Size + (want - S.Blur.Size) * math.min(1, dt * 10)
						end
						S.PrevCam = cf
					end
					cam.CFrame = cf
					if fov then
						cam.FieldOfView = fov
					end
				end
			end
			updateDrops(dt)
			if G.Grain then
				G.Grain.Position = UDim2.fromOffset(-math.random(0, 127), -math.random(0, 127))
			end
			hideCharacters(true)
		end
		S.StepConn = RunService.Stepped:Connect(function()
			local okI, errI = pcall(applyIK)
			if not okI then
				warn("[Командная сцена] IK: " .. tostring(errI))
			end
		end)
		if RunService:IsClient() then
			RunService:BindToRenderStep("NS_TeamCinematic", Enum.RenderPriority.Camera.Value + 1, onFrame)
		else
			S.FrameConn = RunService.Heartbeat:Connect(onFrame)
		end
		task.delay(1.5, function()
			if S.Playing and not S.Cancelled then
				G.Skip.Visible = true
			end
		end)
		local phaseConn = ctx.State:GetAttributeChangedSignal("Phase"):Connect(function()
			if ctx.State:GetAttribute("Phase") ~= "Intro" then
				S.Cancelled = true
			end
		end)
		local ok, err = pcall(timeline)
		if not ok and err ~= SKIP then
			warn("[Командная сцена] " .. tostring(err))
		end
		local skipped = S.Cancelled
		phaseConn:Disconnect()
		G.Skip.Visible = false
		if G.Black.BackgroundTransparency > 0.05 then
			fade(0, 0.45)
			task.wait(0.5)
		end
		G.Black.BackgroundTransparency = 0
		G.TitleMain.TextTransparency = 1
		G.TitleSub.TextTransparency = 1
		G.TitleTime.TextTransparency = 1
		G.TitleLine.BackgroundTransparency = 1
		bars(false, 0.01)
		cleanup()
		ctx.Remotes.Action:FireServer("IntroDone")
		-- остальные ещё смотрят: этот игрок уже стоит у входа (сервер поставил), ждём всех
		if ctx.State:GetAttribute("Phase") == "Intro" then
			task.wait(0.35)
			fade(0.35, 0.8)
			waitOthers(cam)
			fade(0, 0.3)
			task.wait(0.35)
		end
		local _ = skipped
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
		fade(1, 1.4)
		task.wait(1.5)
		G.Gui.Enabled = false
		S.Playing = false
	end)
end

function TeamCinematic.Init(c)
	ctx = c
	UI = ctx.UI
	buildGui()
end

return TeamCinematic
