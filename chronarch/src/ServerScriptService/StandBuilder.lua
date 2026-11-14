-- Собирает модель стенда «Хронарх» из деталей: броня, шестерни, часы на груди, нимб.
-- Модель строится в собственных координатах: Root в начале координат, взгляд по -Z.
-- Каждый сегмент тела соединён Motor6D, анимацию на клиенте задаёт C0.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local GOLD = Config.Colors.Gold
local DGOLD = Config.Colors.DarkGold
local SUIT = Config.Colors.Suit
local ACCENT = Config.Colors.Accent
local CLOTH = Config.Colors.Cloth
local DARK = Color3.fromRGB(10, 10, 14)

local METAL = Enum.Material.Metal
local NEON = Enum.Material.Neon
local RUBBER = Enum.Material.Rubber
local FABRIC = Enum.Material.Fabric
local GLASS = Enum.Material.Glass

local rad = math.rad
local CYL_Z = CFrame.Angles(0, rad(90), 0) -- ось цилиндра (X) направлена вдоль Z
local CYL_Y = CFrame.Angles(0, 0, rad(90)) -- ось цилиндра направлена вдоль Y

local StandBuilder = {}

local function basePart(className, name, size, cf, color, material)
	local p = Instance.new(className)
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material
	if material == NEON then
		p.CastShadow = false
	end
	return p
end

-- Деталь, приваренная к сегменту; localCF задаётся относительно центра сегмента.
local function detail(seg, className, size, localCF, color, material, shape)
	local p = basePart(className, "Detail", size, seg.CFrame * localCF, color, material)
	if shape then
		p.Shape = shape
	end
	p.Parent = seg
	local w = Instance.new("WeldConstraint")
	w.Part0 = seg
	w.Part1 = p
	w.Parent = p
	return p
end

local function block(seg, size, x, y, z, color, material, rot)
	return detail(seg, "Part", size, CFrame.new(x, y, z) * (rot or CFrame.new()), color, material)
end

local function ball(seg, d, x, y, z, color, material)
	return detail(seg, "Part", Vector3.new(d, d, d), CFrame.new(x, y, z), color, material, Enum.PartType.Ball)
end

local function cylinder(seg, length, diameter, cf, color, material)
	return detail(seg, "Part", Vector3.new(length, diameter, diameter), cf, color, material, Enum.PartType.Cylinder)
end

local function wedge(seg, size, cf, color, material)
	return detail(seg, "WedgePart", size, cf, color, material)
end

-- Шестерня, смотрящая вперёд (-Z), с неоновым центром.
local function gear(seg, x, y, z, radius, teeth, thick, color)
	cylinder(seg, thick, radius * 2, CFrame.new(x, y, z) * CYL_Z, color, METAL)
	for i = 0, teeth - 1 do
		local a = (i / teeth) * math.pi * 2
		block(seg, Vector3.new(radius * 0.34, radius * 0.4, thick * 0.9),
			x + math.cos(a) * radius, y + math.sin(a) * radius, z, color, METAL, CFrame.Angles(0, 0, a))
	end
	ball(seg, radius * 0.55, x, y, z - thick * 0.45, ACCENT, NEON)
end

-- Циферблат на груди: обод, тёмное стекло, 12 рисок и стрелки на 10:10.
local function clockFace(seg, x, y, z, r)
	cylinder(seg, 0.08, r * 2, CFrame.new(x, y, z) * CYL_Z, GOLD, METAL)
	cylinder(seg, 0.05, r * 1.62, CFrame.new(x, y, z - 0.045) * CYL_Z, Color3.fromRGB(16, 16, 24), GLASS)
	for i = 0, 11 do
		local a = (i / 12) * math.pi * 2
		local len = (i % 3 == 0) and 0.1 or 0.06
		block(seg, Vector3.new(0.028, len, 0.03),
			x + math.sin(a) * r * 0.66, y + math.cos(a) * r * 0.66, z - 0.075, ACCENT, NEON, CFrame.Angles(0, 0, -a))
	end
	local function hand(angle, len, w)
		local dx, dy = math.sin(angle) * len / 2, math.cos(angle) * len / 2
		block(seg, Vector3.new(w, len, 0.02), x + dx, y + dy, z - 0.085, ACCENT, NEON, CFrame.Angles(0, 0, -angle))
	end
	hand(rad(-60), r * 0.42, 0.035)
	hand(rad(60), r * 0.58, 0.028)
	ball(seg, 0.06, x, y, z - 0.09, GOLD, METAL)
end

local function decorateTorso(torso)
	for _, sx in ipairs({ 1, -1 }) do
		-- грудные пластины
		block(torso, Vector3.new(0.95, 0.75, 0.2), 0.5 * sx, 0.42, -0.6, GOLD, METAL, CFrame.Angles(rad(6), rad(-12 * sx), 0))
		block(torso, Vector3.new(0.9, 0.07, 0.22), 0.5 * sx, 0.03, -0.62, DGOLD, METAL, CFrame.Angles(0, rad(-12 * sx), 0))
		-- пресс
		for row = 0, 2 do
			block(torso, Vector3.new(0.42, 0.22, 0.14), 0.24 * sx, -0.18 - row * 0.26, -0.57, GOLD, METAL)
		end
		-- трапеции и боковые пластины (V-силуэт)
		block(torso, Vector3.new(0.62, 0.26, 0.92), 0.6 * sx, 0.9, 0, DGOLD, METAL, CFrame.Angles(0, 0, rad(-14 * sx)))
		block(torso, Vector3.new(0.16, 1.3, 0.9), 1.0 * sx, 0.05, 0, GOLD, METAL, CFrame.Angles(0, 0, rad(-6 * sx)))
	end
	clockFace(torso, 0, 0.62, -0.72, 0.31)
	-- горжет и шея
	cylinder(torso, 0.3, 0.55, CFrame.new(0, 1.0, 0) * CYL_Y, SUIT, RUBBER)
	cylinder(torso, 0.16, 1.0, CFrame.new(0, 0.92, 0) * CYL_Y, GOLD, METAL)
	ball(torso, 0.14, 0, 0.88, -0.5, ACCENT, NEON)
	-- спина
	block(torso, Vector3.new(1.6, 1.3, 0.16), 0, 0.25, 0.6, GOLD, METAL)
	for i = 0, 3 do
		block(torso, Vector3.new(0.28, 0.2, 0.14), 0, 0.7 - i * 0.3, 0.72, DGOLD, METAL)
	end

	local light = Instance.new("PointLight")
	light.Color = GOLD
	light.Range = 9
	light.Brightness = 0.9
	light.Shadows = false
	light.Parent = torso

	local aura = Instance.new("ParticleEmitter")
	aura.Name = "Aura"
	aura.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	aura.Rate = 14
	aura.Lifetime = NumberRange.new(1, 1.8)
	aura.Speed = NumberRange.new(0.4, 1.4)
	aura.SpreadAngle = Vector2.new(180, 180)
	aura.Acceleration = Vector3.new(0, 1.5, 0)
	aura.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 0) })
	aura.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	aura.Color = ColorSequence.new(GOLD, ACCENT)
	aura.LightEmission = 1
	aura.Parent = torso
end

local function decorateWaist(waist)
	block(waist, Vector3.new(1.8, 0.28, 1.08), 0, 0.28, 0, DGOLD, METAL)
	for _, x in ipairs({ -0.79, -0.62, -0.45, 0.45, 0.62, 0.79 }) do
		ball(waist, 0.09, x, 0.28, -0.55, GOLD, METAL)
	end
	gear(waist, 0, 0.28, -0.6, 0.2, 8, 0.1, GOLD)
	-- набедренная ткань спереди и сзади
	for _, sz in ipairs({ -1, 1 }) do
		block(waist, Vector3.new(0.75, 0.95, 0.06), 0, -0.33, 0.53 * sz, CLOTH, FABRIC)
		block(waist, Vector3.new(0.77, 0.07, 0.08), 0, -0.78, 0.54 * sz, GOLD, METAL)
	end
	for _, sx in ipairs({ 1, -1 }) do
		block(waist, Vector3.new(0.12, 0.62, 0.82), 0.92 * sx, -0.12, 0, GOLD, METAL, CFrame.Angles(0, 0, rad(10 * sx)))
	end
end

local function decorateHead(head)
	block(head, Vector3.new(0.98, 0.5, 1.02), 0, 0.27, 0.02, GOLD, METAL) -- купол шлема
	block(head, Vector3.new(0.84, 0.56, 0.1), 0, -0.14, -0.49, GOLD, METAL) -- маска
	block(head, Vector3.new(0.88, 0.15, 0.08), 0, 0.06, -0.535, DARK, GLASS) -- прорезь визора
	for _, sx in ipairs({ 1, -1 }) do
		block(head, Vector3.new(0.2, 0.06, 0.04), 0.19 * sx, 0.06, -0.58, ACCENT, NEON, CFrame.Angles(0, 0, rad(-12 * sx))) -- глаза
		block(head, Vector3.new(0.08, 0.52, 0.6), 0.49 * sx, -0.12, -0.15, GOLD, METAL, CFrame.Angles(0, rad(-10 * sx), 0)) -- нащёчники
		cylinder(head, 0.08, 0.36, CFrame.new(0.5 * sx, 0.05, 0.08), DGOLD, METAL) -- диски-шестерни у ушей
		ball(head, 0.1, 0.55 * sx, 0.05, 0.08, ACCENT, NEON)
		wedge(head, Vector3.new(0.07, 0.3, 0.62), CFrame.new(0.32 * sx, 0.62, 0.22) * CFrame.Angles(0, 0, rad(-22 * sx)), GOLD, METAL)
	end
	block(head, Vector3.new(0.08, 0.16, 0.06), 0, -0.12, -0.555, GOLD, METAL) -- переносица
	for i = 0, 2 do
		block(head, Vector3.new(0.38, 0.03, 0.04), 0, -0.24 - i * 0.06, -0.555, DARK, METAL) -- решётка рта
	end
	block(head, Vector3.new(0.5, 0.12, 0.26), 0, -0.46, -0.38, GOLD, METAL) -- подбородок
	wedge(head, Vector3.new(0.08, 0.46, 0.92), CFrame.new(0, 0.74, 0.12), GOLD, METAL) -- гребень
	block(head, Vector3.new(0.9, 0.3, 0.1), 0, -0.26, 0.5, GOLD, METAL) -- назатыльник

	local glow = Instance.new("PointLight")
	glow.Color = ACCENT
	glow.Range = 5
	glow.Brightness = 2
	glow.Shadows = false
	glow.Parent = head
end

local function decorateUpperArm(ua, sx)
	block(ua, Vector3.new(0.98, 0.24, 0.98), 0.04 * sx, 0.58, 0, GOLD, METAL)
	block(ua, Vector3.new(0.92, 0.2, 0.92), 0.12 * sx, 0.38, 0, DGOLD, METAL, CFrame.Angles(0, 0, rad(-18 * sx)))
	block(ua, Vector3.new(0.84, 0.18, 0.88), 0.2 * sx, 0.2, 0, GOLD, METAL, CFrame.Angles(0, 0, rad(-30 * sx)))
	block(ua, Vector3.new(0.05, 0.05, 0.92), 0.52 * sx, 0.5, 0, ACCENT, NEON)
	wedge(ua, Vector3.new(0.08, 0.32, 0.55), CFrame.new(0.22 * sx, 0.84, 0.05), GOLD, METAL)
	block(ua, Vector3.new(0.76, 0.12, 0.76), 0, -0.22, 0, GOLD, METAL)
	block(ua, Vector3.new(0.76, 0.07, 0.76), 0, -0.4, 0, DGOLD, METAL)
end

local function decorateLowerArm(la, sx)
	block(la, Vector3.new(0.72, 0.86, 0.72), 0, -0.14, 0, GOLD, METAL)
	for i = 0, 2 do
		block(la, Vector3.new(0.75, 0.05, 0.75), 0, 0.18 - i * 0.3, 0, DGOLD, METAL)
	end
	ball(la, 0.5, 0, 0.55, 0.06, DGOLD, METAL) -- налокотник
	block(la, Vector3.new(0.14, 0.24, 0.05), 0, -0.14, -0.38, ACCENT, NEON)
	wedge(la, Vector3.new(0.06, 0.55, 0.32), CFrame.new(0.38 * sx, -0.1, 0.12), DGOLD, METAL)
end

local function decorateHand(hand, sx)
	block(hand, Vector3.new(0.66, 0.36, 0.66), 0, 0.14, 0, GOLD, METAL)
	for i = 0, 3 do
		local x = -0.21 + i * 0.14
		ball(hand, 0.16, x, -0.15, -0.3, GOLD, METAL) -- костяшки
		block(hand, Vector3.new(0.13, 0.2, 0.18), x, -0.26, -0.18, SUIT, RUBBER) -- пальцы
	end
	block(hand, Vector3.new(0.16, 0.3, 0.2), -0.33 * sx, -0.05, -0.12, GOLD, METAL) -- большой палец

	local a0 = Instance.new("Attachment")
	a0.Name = "TrailA"
	a0.Position = Vector3.new(0, 0.2, 0)
	a0.Parent = hand
	local a1 = Instance.new("Attachment")
	a1.Name = "TrailB"
	a1.Position = Vector3.new(0, -0.3, 0)
	a1.Parent = hand
	local trail = Instance.new("Trail")
	trail.Name = "PunchTrail"
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.14
	trail.LightEmission = 0.9
	trail.FaceCamera = true
	trail.Color = ColorSequence.new(GOLD, ACCENT)
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
	trail.Enabled = false
	trail.Parent = hand
end

local function decorateThigh(th, sx)
	block(th, Vector3.new(0.7, 1.0, 0.12), 0, 0.1, -0.42, GOLD, METAL)
	block(th, Vector3.new(0.1, 0.9, 0.62), 0.42 * sx, 0.05, 0, GOLD, METAL)
	block(th, Vector3.new(0.84, 0.12, 0.86), 0, 0.62, 0, DGOLD, METAL)
end

local function decorateShin(sh)
	block(sh, Vector3.new(0.72, 1.0, 0.74), 0, -0.14, 0, GOLD, METAL)
	block(sh, Vector3.new(0.1, 0.95, 0.1), 0, -0.14, -0.4, DGOLD, METAL)
	gear(sh, 0, 0.55, -0.4, 0.26, 8, 0.12, GOLD) -- наколенник-шестерня
end

local function decorateFoot(ft)
	block(ft, Vector3.new(0.66, 0.3, 0.72), 0, 0.06, 0.12, GOLD, METAL)
	wedge(ft, Vector3.new(0.62, 0.3, 0.36), CFrame.new(0, 0.06, -0.38), GOLD, METAL) -- носок
	block(ft, Vector3.new(0.16, 0.12, 0.16), 0, -0.08, 0.55, DGOLD, METAL) -- шпора
	block(ft, Vector3.new(0.7, 0.1, 0.7), 0, 0.2, 0.16, DGOLD, METAL)
end

-- Нимб-циферблат за спиной: кольца, риски и спицы.
local function decorateHalo(halo)
	local rOuter = 1.15
	local n = 20
	for i = 0, n - 1 do
		local a = (i / n) * math.pi * 2
		local len = 2 * math.pi * rOuter / n * 1.05
		block(halo, Vector3.new(len, 0.08, 0.08), math.cos(a) * rOuter, math.sin(a) * rOuter, 0, GOLD, METAL, CFrame.Angles(0, 0, a + math.pi / 2))
	end
	for i = 0, 11 do
		local a = (i / 12) * math.pi * 2
		block(halo, Vector3.new(0.05, 0.22, 0.05), math.cos(a) * 1.32, math.sin(a) * 1.32, 0, ACCENT, NEON, CFrame.Angles(0, 0, a - math.pi / 2))
	end
	local rInner = 0.82
	for i = 0, 11 do
		local a = (i / 12) * math.pi * 2
		local len = 2 * math.pi * rInner / 12 * 1.05
		block(halo, Vector3.new(len, 0.05, 0.05), math.cos(a) * rInner, math.sin(a) * rInner, 0, DGOLD, METAL, CFrame.Angles(0, 0, a + math.pi / 2))
	end
	for i = 0, 3 do
		local a = (i / 4) * math.pi * 2 + math.pi / 4
		block(halo, Vector3.new(0.62, 0.04, 0.04), math.cos(a) * 0.5, math.sin(a) * 0.5, 0, DGOLD, METAL, CFrame.Angles(0, 0, a))
	end
	cylinder(halo, 0.1, 0.4, CFrame.new() * CYL_Z, GOLD, METAL)
end

function StandBuilder.Build()
	local model = Instance.new("Model")
	model.Name = "Stand"

	local root = basePart("Part", "Root", Vector3.new(1, 1, 1), CFrame.new(), Color3.new(0, 0, 0), Enum.Material.SmoothPlastic)
	root.Transparency = 1
	root.Parent = model
	model.PrimaryPart = root

	local function seg(name, size, pos)
		local p = basePart("Part", name, size, CFrame.new(pos), SUIT, RUBBER)
		p.Parent = model
		return p
	end

	local function joint(name, p0, p1, pos)
		local m = Instance.new("Motor6D")
		m.Name = name
		m.Part0 = p0
		m.Part1 = p1
		m.C0 = p0.CFrame:Inverse() * CFrame.new(pos)
		m.C1 = p1.CFrame:Inverse() * CFrame.new(pos)
		m.Parent = p0
		return m
	end

	local waist = seg("Waist", Vector3.new(1.7, 0.9, 1.0), Vector3.new(0, 0, 0))
	local torso = seg("Torso", Vector3.new(2.1, 1.9, 1.1), Vector3.new(0, 1.45, 0))
	local head = seg("Head", Vector3.new(0.9, 1.0, 0.95), Vector3.new(0, 2.95, 0))
	joint("Hips", root, waist, Vector3.new(0, 0, 0))
	joint("Spine", waist, torso, Vector3.new(0, 0.5, 0))
	joint("Neck", torso, head, Vector3.new(0, 2.45, 0))
	decorateWaist(waist)
	decorateTorso(torso)
	decorateHead(head)

	for _, sx in ipairs({ 1, -1 }) do
		local s = (sx == 1) and "R" or "L"
		local ua = seg(s .. "UpperArm", Vector3.new(0.7, 1.3, 0.7), Vector3.new(1.5 * sx, 1.5, 0))
		local la = seg(s .. "LowerArm", Vector3.new(0.62, 1.2, 0.62), Vector3.new(1.5 * sx, 0.25, 0))
		local hand = seg(s .. "Hand", Vector3.new(0.6, 0.62, 0.6), Vector3.new(1.5 * sx, -0.66, 0))
		joint(s .. "Shoulder", torso, ua, Vector3.new(1.5 * sx, 2.1, 0))
		joint(s .. "Elbow", ua, la, Vector3.new(1.5 * sx, 0.85, 0))
		joint(s .. "Wrist", la, hand, Vector3.new(1.5 * sx, -0.35, 0))
		decorateUpperArm(ua, sx)
		decorateLowerArm(la, sx)
		decorateHand(hand, sx)

		local th = seg(s .. "Thigh", Vector3.new(0.78, 1.45, 0.8), Vector3.new(0.5 * sx, -1.1, 0))
		local sh = seg(s .. "Shin", Vector3.new(0.66, 1.4, 0.68), Vector3.new(0.5 * sx, -2.5, 0))
		local ft = seg(s .. "Foot", Vector3.new(0.62, 0.42, 1.05), Vector3.new(0.5 * sx, -3.38, -0.16))
		joint(s .. "Hip", waist, th, Vector3.new(0.5 * sx, -0.4, 0))
		joint(s .. "Knee", th, sh, Vector3.new(0.5 * sx, -1.8, 0))
		joint(s .. "Ankle", sh, ft, Vector3.new(0.5 * sx, -3.2, 0))
		decorateThigh(th, sx)
		decorateShin(sh)
		decorateFoot(ft)
	end

	local halo = seg("Halo", Vector3.new(0.2, 0.2, 0.2), Vector3.new(0, 1.95, 1.0))
	halo.Transparency = 1
	joint("HaloSpin", torso, halo, Vector3.new(0, 1.95, 1.0))
	decorateHalo(halo)

	return model, root
end

return StandBuilder
