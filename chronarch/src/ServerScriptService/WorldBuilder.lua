-- Строит мир: освещение, рельеф, площадь, дома, часовую башню, фонари,
-- алтарь со стрелой прямо перед спавном и тренировочные манекены.
local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")

local ArrowBuilder = require(script.Parent:WaitForChild("ArrowBuilder"))

local WorldBuilder = {}

local rad = math.rad
local SMOOTH = Enum.SurfaceType.Smooth
local CYL_Y = CFrame.Angles(0, 0, rad(90))
local CYL_Z = CFrame.Angles(0, rad(90), 0)

local GOLD = Color3.fromRGB(214, 172, 62)
local RUNE = Color3.fromRGB(170, 120, 255)

local ALTAR_POS = Vector3.new(0, 0, -12)

local function make(className, props, parent)
	local inst = Instance.new(className)
	for k, v in pairs(props) do
		inst[k] = v
	end
	inst.Parent = parent
	return inst
end

local function part(parent, name, size, cf, color, material, shape)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.TopSurface = SMOOTH
	p.BottomSurface = SMOOTH
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material
	if shape then
		p.Shape = shape
	end
	if material == Enum.Material.Neon then
		p.CastShadow = false
	end
	p.Parent = parent
	return p
end

local function wedgePart(parent, name, size, cf, color, material)
	local p = Instance.new("WedgePart")
	p.Name = name
	p.Anchored = true
	p.TopSurface = SMOOTH
	p.BottomSurface = SMOOTH
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material
	p.Parent = parent
	return p
end

local function folder(name, parent)
	local f = parent:FindFirstChild(name)
	if not f then
		f = Instance.new("Folder")
		f.Name = name
		f.Parent = parent
	end
	return f
end

-------------------------------------------------------------------------------
-- Освещение: тёплый закат, атмосфера, пост-эффекты.
-------------------------------------------------------------------------------
local function setupLighting()
	Lighting.ClockTime = 17.35
	Lighting.GeographicLatitude = 28
	Lighting.Brightness = 2.6
	Lighting.Ambient = Color3.fromRGB(46, 42, 52)
	Lighting.OutdoorAmbient = Color3.fromRGB(118, 104, 98)
	Lighting.EnvironmentDiffuseScale = 1
	Lighting.EnvironmentSpecularScale = 1
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.15
	Lighting.ExposureCompensation = 0.15
	Lighting.ColorShift_Top = Color3.fromRGB(255, 214, 170)
	pcall(function()
		Lighting.Technology = Enum.Technology.Future
	end)
	for _, c in ipairs(Lighting:GetChildren()) do
		if c:IsA("PostEffect") or c:IsA("Atmosphere") then
			c:Destroy()
		end
	end
	make("Atmosphere", {
		Density = 0.3,
		Offset = 0.2,
		Color = Color3.fromRGB(206, 172, 140),
		Decay = Color3.fromRGB(110, 86, 108),
		Glare = 0.45,
		Haze = 1.6,
	}, Lighting)
	make("BloomEffect", { Name = "Bloom", Intensity = 0.55, Size = 30, Threshold = 1.7 }, Lighting)
	make("SunRaysEffect", { Name = "SunRays", Intensity = 0.07, Spread = 0.75 }, Lighting)
	make("ColorCorrectionEffect", {
		Name = "Grade",
		Saturation = 0.08,
		Contrast = 0.1,
		Brightness = 0.01,
		TintColor = Color3.fromRGB(255, 246, 236),
	}, Lighting)
	make("DepthOfFieldEffect", { Name = "DoF", FarIntensity = 0.12, FocusDistance = 70, InFocusRadius = 60, NearIntensity = 0 }, Lighting)
end

-------------------------------------------------------------------------------
-- Рельеф вокруг площади и холмы на горизонте.
-------------------------------------------------------------------------------
local function setupTerrain()
	local t = workspace.Terrain
	t:FillBlock(CFrame.new(0, -8, 0), Vector3.new(900, 12, 900), Enum.Material.Grass)
	for i = 1, 14 do
		local a = i / 14 * math.pi * 2
		local r = 270 + (i % 3) * 40
		t:FillBall(Vector3.new(math.cos(a) * r, -16, math.sin(a) * r), 40 + (i % 4) * 12, Enum.Material.Grass)
		t:FillBall(Vector3.new(math.cos(a + 0.2) * (r + 30), -6, math.sin(a + 0.2) * (r + 30)), 14 + (i % 3) * 6, Enum.Material.Rock)
	end
end

-------------------------------------------------------------------------------
-- Площадь: мощёный пол с узором-розой ветров.
-------------------------------------------------------------------------------
local function buildPlaza(map)
	local plaza = workspace:FindFirstChild("Plaza")
	if plaza then
		plaza.Material = Enum.Material.Cobblestone
		plaza.Color = Color3.fromRGB(128, 118, 104)
	end
	part(map, "Ring", Vector3.new(0.1, 84, 84), CFrame.new(0, 0.03, 0) * CYL_Y, Color3.fromRGB(78, 74, 72), Enum.Material.Slate, Enum.PartType.Cylinder)
	part(map, "Inner", Vector3.new(0.1, 80, 80), CFrame.new(0, 0.06, 0) * CYL_Y, Color3.fromRGB(150, 138, 120), Enum.Material.Cobblestone, Enum.PartType.Cylinder)
	part(map, "CenterRing", Vector3.new(0.1, 26, 26), CFrame.new(0, 0.08, 0) * CYL_Y, Color3.fromRGB(66, 62, 64), Enum.Material.Granite, Enum.PartType.Cylinder)
	part(map, "CenterDisc", Vector3.new(0.1, 24, 24), CFrame.new(0, 0.1, 0) * CYL_Y, Color3.fromRGB(214, 204, 188), Enum.Material.Marble, Enum.PartType.Cylinder)
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		local len = (i % 2 == 0) and 15 or 10
		local mid = 12 + len / 2
		part(map, "Ray", Vector3.new(1.2, 0.1, len),
			CFrame.new(math.sin(a) * mid, 0.09, math.cos(a) * mid) * CFrame.Angles(0, a, 0),
			Color3.fromRGB(205, 195, 178), Enum.Material.Marble)
	end
end

-------------------------------------------------------------------------------
-- Дома вокруг площади.
-------------------------------------------------------------------------------
local WALLS = {
	{ Color3.fromRGB(196, 160, 128), Enum.Material.Plaster },
	{ Color3.fromRGB(150, 84, 64), Enum.Material.Brick },
	{ Color3.fromRGB(214, 198, 168), Enum.Material.Plaster },
	{ Color3.fromRGB(120, 112, 104), Enum.Material.Concrete },
	{ Color3.fromRGB(170, 120, 96), Enum.Material.Brick },
}

local function building(map, cf, width, depth, floors, styleIndex, seed)
	local model = Instance.new("Model")
	model.Name = "House"
	local style = WALLS[(styleIndex - 1) % #WALLS + 1]
	local h = floors * 11 + 2
	local wallColor, wallMat = style[1], style[2]

	part(model, "Base", Vector3.new(width + 0.8, 2, depth + 0.8), cf * CFrame.new(0, 1, 0), Color3.fromRGB(92, 88, 86), Enum.Material.Granite)
	part(model, "Body", Vector3.new(width, h, depth), cf * CFrame.new(0, h / 2, 0), wallColor, wallMat)
	part(model, "Cornice", Vector3.new(width + 1.4, 1, depth + 1.4), cf * CFrame.new(0, h + 0.5, 0), Color3.fromRGB(226, 218, 204), Enum.Material.Limestone)
	for f = 1, floors - 1 do
		part(model, "Band", Vector3.new(width + 0.4, 0.5, depth + 0.4), cf * CFrame.new(0, 2 + f * 11, 0), Color3.fromRGB(218, 208, 190), Enum.Material.Limestone)
	end

	-- Двускатная черепичная крыша
	local roofH = 6
	local roofColor = Color3.fromRGB(150, 70, 52)
	wedgePart(model, "Roof", Vector3.new(width + 1, roofH, depth / 2 + 0.6), cf * CFrame.new(0, h + 1 + roofH / 2, -depth / 4 - 0.3), roofColor, Enum.Material.ClayRoofTiles)
	wedgePart(model, "Roof", Vector3.new(width + 1, roofH, depth / 2 + 0.6), cf * CFrame.new(0, h + 1 + roofH / 2, depth / 4 + 0.3) * CFrame.Angles(0, math.pi, 0), roofColor, Enum.Material.ClayRoofTiles)
	part(model, "Chimney", Vector3.new(2, 5, 2), cf * CFrame.new(width / 2 - 3, h + 4, depth / 4), Color3.fromRGB(120, 66, 52), Enum.Material.Brick)

	-- Окна на фасаде (фасад смотрит в -Z, то есть на центр площади)
	local front = -depth / 2
	local cols = math.max(2, math.floor(width / 6))
	local spacing = width / cols
	local rng = Random.new(seed)
	for f = 0, floors - 1 do
		for c = 0, cols - 1 do
			local x = -width / 2 + spacing * (c + 0.5)
			local y = 2 + f * 11 + 6
			if not (f == 0 and c == math.floor(cols / 2)) then
				local lit = rng:NextNumber() < 0.45
				local glass = part(model, "Window", Vector3.new(2.4, 4, 0.3), cf * CFrame.new(x, y, front - 0.1),
					lit and Color3.fromRGB(255, 186, 112) or Color3.fromRGB(38, 46, 58),
					lit and Enum.Material.Neon or Enum.Material.Glass)
				if lit then
					glass.Transparency = 0.25
				else
					glass.Reflectance = 0.25
				end
				part(model, "Sill", Vector3.new(3.2, 0.35, 0.8), cf * CFrame.new(x, y - 2.2, front - 0.3), Color3.fromRGB(226, 218, 204), Enum.Material.Limestone)
				part(model, "Lintel", Vector3.new(3.2, 0.6, 0.6), cf * CFrame.new(x, y + 2.3, front - 0.2), Color3.fromRGB(226, 218, 204), Enum.Material.Limestone)
				part(model, "Shutter", Vector3.new(0.9, 4, 0.2), cf * CFrame.new(x - 1.75, y, front - 0.2), Color3.fromRGB(58, 86, 70), Enum.Material.WoodPlanks)
				part(model, "Shutter", Vector3.new(0.9, 4, 0.2), cf * CFrame.new(x + 1.75, y, front - 0.2), Color3.fromRGB(58, 86, 70), Enum.Material.WoodPlanks)
			end
		end
	end

	-- Дверь и маркиза лавки
	local doorX = -width / 2 + spacing * (math.floor(cols / 2) + 0.5)
	part(model, "Door", Vector3.new(3.4, 6.5, 0.4), cf * CFrame.new(doorX, 2 + 3.25, front - 0.1), Color3.fromRGB(70, 44, 30), Enum.Material.WoodPlanks)
	part(model, "DoorFrame", Vector3.new(4.4, 0.7, 0.7), cf * CFrame.new(doorX, 2 + 6.8, front - 0.25), Color3.fromRGB(226, 218, 204), Enum.Material.Limestone)
	wedgePart(model, "Awning", Vector3.new(6, 1.4, 3), cf * CFrame.new(doorX, 2 + 8.2, front - 1.5),
		({ Color3.fromRGB(150, 30, 36), Color3.fromRGB(40, 80, 120), Color3.fromRGB(60, 110, 60) })[seed % 3 + 1], Enum.Material.Fabric)

	model.Parent = map
	return model
end

local function buildHouses(map)
	local houses = folder("Houses", map)
	local seed = 1
	local function row(positions, facing)
		for _, pos in ipairs(positions) do
			local cf = CFrame.lookAt(pos, pos + facing)
			building(houses, cf, 26, 18, 2 + (seed % 2), seed, seed * 7)
			seed = seed + 1
		end
	end
	-- Фасады смотрят на центр площади
	row({ Vector3.new(86, 0, -50), Vector3.new(86, 0, -20), Vector3.new(86, 0, 10), Vector3.new(86, 0, 40) }, Vector3.new(-1, 0, 0))
	row({ Vector3.new(-86, 0, -50), Vector3.new(-86, 0, -20), Vector3.new(-86, 0, 10), Vector3.new(-86, 0, 40) }, Vector3.new(1, 0, 0))
	row({ Vector3.new(-45, 0, 86), Vector3.new(-15, 0, 86), Vector3.new(15, 0, 86), Vector3.new(45, 0, 86) }, Vector3.new(0, 0, -1))
	row({ Vector3.new(-48, 0, -86), Vector3.new(48, 0, -86) }, Vector3.new(0, 0, 1))
end

-------------------------------------------------------------------------------
-- Часовая башня на севере. Стрелки крутит клиент, при остановке времени они замирают.
-------------------------------------------------------------------------------
local function buildClockTower(map)
	local tower = Instance.new("Model")
	tower.Name = "ClockTower"
	local z = -90
	local stone = Color3.fromRGB(196, 176, 140)
	local trim = Color3.fromRGB(226, 218, 204)

	part(tower, "Plinth", Vector3.new(22, 3, 22), CFrame.new(0, 1.5, z), Color3.fromRGB(86, 82, 82), Enum.Material.Granite)
	part(tower, "Shaft", Vector3.new(16, 54, 16), CFrame.new(0, 30, z), stone, Enum.Material.Sandstone)
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			part(tower, "Pilaster", Vector3.new(2.4, 54, 2.4), CFrame.new(8 * sx, 30, z + 8 * sz), trim, Enum.Material.Limestone)
		end
	end
	for i = 1, 3 do
		part(tower, "Band", Vector3.new(17.4, 1, 17.4), CFrame.new(0, 3 + i * 13, z), trim, Enum.Material.Limestone)
	end
	-- Узкие окна-бойницы
	for i = 0, 2 do
		part(tower, "Slit", Vector3.new(1.4, 5, 0.3), CFrame.new(0, 10 + i * 13, z + 8.1), Color3.fromRGB(30, 30, 36), Enum.Material.Glass)
	end

	-- Часовой ярус
	part(tower, "ClockHousing", Vector3.new(18, 16, 18), CFrame.new(0, 65, z), stone, Enum.Material.Sandstone)
	part(tower, "HousingCap", Vector3.new(19.5, 1.2, 19.5), CFrame.new(0, 73.6, z), trim, Enum.Material.Limestone)
	local faceZ = z + 9
	part(tower, "ClockRim", Vector3.new(0.5, 14.2, 14.2), CFrame.new(0, 65, faceZ + 0.25) * CYL_Z, GOLD, Enum.Material.Metal, Enum.PartType.Cylinder)
	part(tower, "ClockFace", Vector3.new(0.5, 13, 13), CFrame.new(0, 65, faceZ + 0.5) * CYL_Z, Color3.fromRGB(238, 232, 220), Enum.Material.Marble, Enum.PartType.Cylinder)
	for i = 0, 11 do
		local a = i / 12 * math.pi * 2
		local big = (i % 3 == 0)
		part(tower, "Mark", Vector3.new(big and 0.6 or 0.35, big and 1.6 or 1.1, 0.2),
			CFrame.new(math.sin(a) * 5.4, 65 + math.cos(a) * 5.4, faceZ + 0.8) * CFrame.Angles(0, 0, -a),
			Color3.fromRGB(28, 28, 32), Enum.Material.Metal)
	end
	local center = part(tower, "ClockCenter", Vector3.new(0.4, 0.4, 0.4), CFrame.new(0, 65, faceZ + 1.0), Color3.new(0, 0, 0), Enum.Material.SmoothPlastic)
	center.Transparency = 1
	center.CanCollide = false
	part(tower, "HourHand", Vector3.new(0.55, 3.8, 0.15), CFrame.new(0, 65 + 1.6, faceZ + 0.95), Color3.fromRGB(26, 26, 30), Enum.Material.Metal)
	part(tower, "MinuteHand", Vector3.new(0.38, 5.6, 0.15), CFrame.new(0, 65 + 2.5, faceZ + 1.1), Color3.fromRGB(26, 26, 30), Enum.Material.Metal)
	part(tower, "Cap", Vector3.new(0.3, 0.9, 0.9), CFrame.new(0, 65, faceZ + 1.25) * CYL_Z, GOLD, Enum.Material.Metal, Enum.PartType.Cylinder)
	local lamp = part(tower, "FaceLight", Vector3.new(0.4, 0.4, 0.4), CFrame.new(0, 65, faceZ + 9), Color3.new(0, 0, 0), Enum.Material.SmoothPlastic)
	lamp.Transparency = 1
	lamp.CanCollide = false
	make("PointLight", { Color = Color3.fromRGB(255, 214, 160), Range = 16, Brightness = 1.2, Shadows = false }, lamp)

	-- Колокольня и ступенчатый шпиль
	part(tower, "Belfry", Vector3.new(14, 10, 14), CFrame.new(0, 79.2, z), stone, Enum.Material.Sandstone)
	for _, d in ipairs({ Vector3.new(0, 0, 7.05), Vector3.new(0, 0, -7.05), Vector3.new(7.05, 0, 0), Vector3.new(-7.05, 0, 0) }) do
		local size = (d.X == 0) and Vector3.new(4, 6, 0.3) or Vector3.new(0.3, 6, 4)
		part(tower, "Arch", size, CFrame.new(Vector3.new(0, 79.2, z) + d), Color3.fromRGB(20, 18, 22), Enum.Material.Slate)
	end
	local roof = Color3.fromRGB(62, 56, 62)
	part(tower, "Spire1", Vector3.new(15, 1.5, 15), CFrame.new(0, 85, z), trim, Enum.Material.Limestone)
	part(tower, "Spire2", Vector3.new(12, 3, 12), CFrame.new(0, 87.2, z), roof, Enum.Material.RoofShingles)
	part(tower, "Spire3", Vector3.new(9, 3, 9), CFrame.new(0, 90.2, z), roof, Enum.Material.RoofShingles)
	part(tower, "Spire4", Vector3.new(6, 3, 6), CFrame.new(0, 93.2, z), roof, Enum.Material.RoofShingles)
	part(tower, "Spire5", Vector3.new(3, 4, 3), CFrame.new(0, 96.7, z), roof, Enum.Material.RoofShingles)
	part(tower, "Needle", Vector3.new(6, 0.35, 0.35), CFrame.new(0, 101.5, z) * CYL_Y, GOLD, Enum.Material.Metal, Enum.PartType.Cylinder)
	part(tower, "Orb", Vector3.new(1.2, 1.2, 1.2), CFrame.new(0, 99.2, z), GOLD, Enum.Material.Metal, Enum.PartType.Ball)

	tower.Parent = map
end

-------------------------------------------------------------------------------
-- Фонари и жаровни.
-------------------------------------------------------------------------------
local function streetLamp(parent, pos, shadows)
	local m = Instance.new("Model")
	m.Name = "Lamp"
	local iron = Color3.fromRGB(36, 36, 40)
	part(m, "Base", Vector3.new(1.6, 1, 1.6), CFrame.new(pos + Vector3.new(0, 0.5, 0)), iron, Enum.Material.Metal)
	part(m, "Pole", Vector3.new(11, 0.45, 0.45), CFrame.new(pos + Vector3.new(0, 6.5, 0)) * CYL_Y, iron, Enum.Material.Metal, Enum.PartType.Cylinder)
	part(m, "Collar", Vector3.new(0.4, 0.75, 0.75), CFrame.new(pos + Vector3.new(0, 11.8, 0)) * CYL_Y, GOLD, Enum.Material.Metal, Enum.PartType.Cylinder)
	local glass = part(m, "Lantern", Vector3.new(1.3, 1.7, 1.3), CFrame.new(pos + Vector3.new(0, 13, 0)), Color3.fromRGB(255, 224, 176), Enum.Material.Glass)
	glass.Transparency = 0.35
	glass.CastShadow = false
	part(m, "Cap", Vector3.new(1.7, 0.35, 1.7), CFrame.new(pos + Vector3.new(0, 14, 0)), iron, Enum.Material.Metal)
	part(m, "Finial", Vector3.new(0.4, 0.4, 0.4), CFrame.new(pos + Vector3.new(0, 14.4, 0)), iron, Enum.Material.Metal, Enum.PartType.Ball)
	local bulb = part(m, "Bulb", Vector3.new(0.6, 0.6, 0.6), CFrame.new(pos + Vector3.new(0, 13, 0)), Color3.fromRGB(255, 200, 130), Enum.Material.Neon, Enum.PartType.Ball)
	bulb.CanCollide = false
	make("PointLight", { Color = Color3.fromRGB(255, 196, 130), Range = 22, Brightness = 1.6, Shadows = shadows }, bulb)
	m.Parent = parent
end

local function brazier(parent, pos)
	local m = Instance.new("Model")
	m.Name = "Brazier"
	local iron = Color3.fromRGB(48, 44, 40)
	for i = 0, 2 do
		local a = i / 3 * math.pi * 2
		part(m, "Leg", Vector3.new(0.25, 3.2, 0.25), CFrame.new(pos + Vector3.new(math.cos(a) * 0.7, 1.5, math.sin(a) * 0.7)) * CFrame.Angles(math.sin(a) * 0.25, 0, -math.cos(a) * 0.25), iron, Enum.Material.Metal)
	end
	part(m, "Bowl", Vector3.new(0.7, 2.4, 2.4), CFrame.new(pos + Vector3.new(0, 3.2, 0)) * CYL_Y, iron, Enum.Material.Metal, Enum.PartType.Cylinder)
	part(m, "Rim", Vector3.new(0.15, 2.6, 2.6), CFrame.new(pos + Vector3.new(0, 3.55, 0)) * CYL_Y, GOLD, Enum.Material.Metal, Enum.PartType.Cylinder)
	local coals = part(m, "Coals", Vector3.new(0.2, 2, 2), CFrame.new(pos + Vector3.new(0, 3.6, 0)) * CYL_Y, Color3.fromRGB(255, 120, 40), Enum.Material.CrackedLava, Enum.PartType.Cylinder)
	local fire = make("ParticleEmitter", {
		Name = "Fire",
		Texture = "rbxasset://textures/particles/fire_main.dds",
		Rate = 45,
		Lifetime = NumberRange.new(0.5, 0.9),
		Speed = NumberRange.new(3, 5),
		SpreadAngle = Vector2.new(12, 12),
		Acceleration = Vector3.new(0, 3, 0),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.3), NumberSequenceKeypoint.new(1, 0.2) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) }),
		Color = ColorSequence.new(Color3.fromRGB(255, 190, 90), Color3.fromRGB(255, 70, 20)),
		LightEmission = 1,
		EmissionDirection = Enum.NormalId.Right, -- ось X цилиндра повёрнута вверх
	}, coals)
	fire.ZOffset = 1
	make("ParticleEmitter", {
		Name = "Smoke",
		Texture = "rbxasset://textures/particles/smoke_main.dds",
		Rate = 6,
		Lifetime = NumberRange.new(2, 3),
		Speed = NumberRange.new(2, 3),
		SpreadAngle = Vector2.new(15, 15),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 3) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.75), NumberSequenceKeypoint.new(1, 1) }),
		Color = ColorSequence.new(Color3.fromRGB(60, 56, 54)),
		EmissionDirection = Enum.NormalId.Right,
	}, coals)
	local light = make("PointLight", { Color = Color3.fromRGB(255, 140, 60), Range = 16, Brightness = 2, Shadows = true }, coals)
	light:SetAttribute("Flicker", 2)
	m.Parent = parent
end

-------------------------------------------------------------------------------
-- Алтарь со стрелой прямо перед точкой появления.
-------------------------------------------------------------------------------
local function buildAltar()
	local altar = Instance.new("Model")
	altar.Name = "ArrowAltar"
	local base = CFrame.new(ALTAR_POS)
	local granite = Color3.fromRGB(70, 68, 72)
	local marble = Color3.fromRGB(214, 206, 192)

	part(altar, "Step1", Vector3.new(12, 0.6, 12), base * CFrame.new(0, 0.3, 0), granite, Enum.Material.Granite)
	part(altar, "Step2", Vector3.new(9.6, 0.6, 9.6), base * CFrame.new(0, 0.9, 0), marble, Enum.Material.Marble)
	part(altar, "Step3", Vector3.new(7.2, 0.6, 7.2), base * CFrame.new(0, 1.5, 0), granite, Enum.Material.Granite)

	-- Главный блок
	local blockCF = base * CFrame.new(0, 3.4, 0)
	local block = part(altar, "Block", Vector3.new(3.4, 3.2, 3.4), blockCF, Color3.fromRGB(40, 38, 44), Enum.Material.Basalt)

	-- Золотые рёбра блока
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			part(altar, "Trim", Vector3.new(0.16, 3.3, 0.16), blockCF * CFrame.new(1.7 * sx, 0, 1.7 * sz), GOLD, Enum.Material.Metal)
		end
		for _, y in ipairs({ -1.6, 1.6 }) do
			part(altar, "Trim", Vector3.new(3.5, 0.16, 0.16), blockCF * CFrame.new(0, y, 1.7 * sx), GOLD, Enum.Material.Metal)
			part(altar, "Trim", Vector3.new(0.16, 0.16, 3.5), blockCF * CFrame.new(1.7 * sx, y, 0), GOLD, Enum.Material.Metal)
		end
	end

	-- Резные панели с рунами на трёх сторонах, табличка на лицевой (+Z, к спавну)
	local faces = {
		{ CFrame.new(0, 0, -1.72), 0 },
		{ CFrame.new(1.72, 0, 0) * CFrame.Angles(0, rad(-90), 0), 0 },
		{ CFrame.new(-1.72, 0, 0) * CFrame.Angles(0, rad(90), 0), 0 },
	}
	for _, f in ipairs(faces) do
		local fcf = blockCF * f[1]
		part(altar, "Panel", Vector3.new(2.6, 2.4, 0.08), fcf, Color3.fromRGB(28, 26, 32), Enum.Material.Slate)
		part(altar, "Rune", Vector3.new(0.07, 1.5, 0.05), fcf * CFrame.new(0, -0.1, -0.06), RUNE, Enum.Material.Neon)
		part(altar, "Rune", Vector3.new(0.07, 0.8, 0.05), fcf * CFrame.new(-0.22, -0.62, -0.06) * CFrame.Angles(0, 0, rad(-38)), RUNE, Enum.Material.Neon)
		part(altar, "Rune", Vector3.new(0.07, 0.8, 0.05), fcf * CFrame.new(0.22, -0.62, -0.06) * CFrame.Angles(0, 0, rad(38)), RUNE, Enum.Material.Neon)
		part(altar, "Rune", Vector3.new(0.9, 0.07, 0.05), fcf * CFrame.new(0, 0.55, -0.06), RUNE, Enum.Material.Neon)
	end
	local plaque = part(altar, "Plaque", Vector3.new(2.8, 1.0, 0.12), blockCF * CFrame.new(0, 0.6, 1.76), Color3.fromRGB(120, 90, 30), Enum.Material.Metal)
	local gui = make("SurfaceGui", { Face = Enum.NormalId.Back, SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud, PixelsPerStud = 60, LightInfluence = 0.6 }, plaque)
	make("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "СТРЕЛА СУДЬБЫ",
		TextColor3 = Color3.fromRGB(255, 226, 150),
		TextScaled = true,
		Font = Enum.Font.Garamond,
	}, gui)
	part(altar, "PlaqueRune", Vector3.new(0.9, 0.07, 0.05), blockCF * CFrame.new(0, -0.5, 1.75), RUNE, Enum.Material.Neon)

	-- Верхняя плита и золотые колонны
	local top = part(altar, "TopSlab", Vector3.new(3.9, 0.35, 3.9), base * CFrame.new(0, 5.175, 0), Color3.fromRGB(226, 220, 206), Enum.Material.Marble)
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			part(altar, "Pillar", Vector3.new(2.8, 0.22, 0.22), base * CFrame.new(1.6 * sx, 6.75, 1.6 * sz) * CYL_Y, GOLD, Enum.Material.Metal, Enum.PartType.Cylinder)
			part(altar, "PillarGem", Vector3.new(0.32, 0.32, 0.32), base * CFrame.new(1.6 * sx, 8.25, 1.6 * sz), RUNE, Enum.Material.Neon, Enum.PartType.Ball)
		end
	end

	-- Прожектор над стрелой
	local spot = part(altar, "SpotHolder", Vector3.new(0.4, 0.4, 0.4), base * CFrame.new(0, 16, 0), Color3.new(0, 0, 0), Enum.Material.SmoothPlastic)
	spot.Transparency = 1
	spot.CanCollide = false
	make("SpotLight", { Face = Enum.NormalId.Bottom, Angle = 32, Range = 20, Brightness = 3, Color = Color3.fromRGB(255, 236, 200), Shadows = true }, spot)

	-- Сама стрела: парит над алтарём остриём вниз
	local arrow = ArrowBuilder.Build()
	arrow:PivotTo(CFrame.new(ALTAR_POS + Vector3.new(0, 8.3, 0)) * CFrame.Angles(0, 0, rad(-70)))
	arrow.Parent = altar

	-- Подсказка «Взять стрелу»
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "TakeArrow"
	prompt.ActionText = "Взять стрелу"
	prompt.ObjectText = "Стрела Судьбы"
	prompt.HoldDuration = 0.5
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.F
	prompt.Parent = top

	-- Жаровни по бокам
	brazier(altar, ALTAR_POS + Vector3.new(-7.6, 0, 0))
	brazier(altar, ALTAR_POS + Vector3.new(7.6, 0, 0))

	altar.Parent = workspace
	return altar, prompt
end

-------------------------------------------------------------------------------
-- Манекены для отработки ударов.
-------------------------------------------------------------------------------
local DUMMY_SPOTS = {
	Vector3.new(-12, 0, -34),
	Vector3.new(0, 0, -38),
	Vector3.new(12, 0, -34),
}

local dummiesFolder

local function spawnDummy(index)
	local pos = DUMMY_SPOTS[index]
	local desc = Instance.new("HumanoidDescription")
	local skin = Color3.fromRGB(176, 160, 132)
	desc.HeadColor = skin
	desc.TorsoColor = Color3.fromRGB(120, 92, 64)
	desc.LeftArmColor = skin
	desc.RightArmColor = skin
	desc.LeftLegColor = Color3.fromRGB(92, 72, 52)
	desc.RightLegColor = Color3.fromRGB(92, 72, 52)
	local ok, model = pcall(function()
		return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	end)
	if not ok or not model then
		warn("Не удалось создать манекен:", model)
		return
	end
	model.Name = "Манекен"
	local hum = model:FindFirstChildOfClass("Humanoid")
	hum.DisplayName = "Манекен"
	hum.MaxHealth = 250
	hum.Health = 250
	hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOn
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
	hum.NameDisplayDistance = 70
	hum.HealthDisplayDistance = 70
	hum.BreakJointsOnDeath = false
	hum.WalkSpeed = 0
	hum.JumpPower = 0
	model:PivotTo(CFrame.lookAt(pos + Vector3.new(0, 3.6, 0), pos + Vector3.new(0, 3.6, 10)))
	model.Parent = dummiesFolder
	local hrp = model:FindFirstChild("HumanoidRootPart")
	if hrp then
		pcall(function()
			hrp:SetNetworkOwner(nil)
		end)
	end
	hum.Died:Connect(function()
		task.delay(3, function()
			model:Destroy()
			spawnDummy(index)
		end)
	end)
end

local function buildDummies(map)
	dummiesFolder = folder("Dummies", workspace)
	for i, pos in ipairs(DUMMY_SPOTS) do
		part(map, "DummyPad", Vector3.new(5, 0.3, 5), CFrame.new(pos + Vector3.new(0, 0.25, 0)), Color3.fromRGB(110, 78, 50), Enum.Material.WoodPlanks)
		task.spawn(spawnDummy, i)
	end
end

-------------------------------------------------------------------------------
-- Пылинки в воздухе: при остановке времени они замирают.
-------------------------------------------------------------------------------
local function buildAmbience(map)
	local field = part(map, "DustField", Vector3.new(150, 18, 150), CFrame.new(0, 10, 0), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic)
	field.Transparency = 1
	field.CanCollide = false
	field.CanQuery = false
	field.CanTouch = false
	make("ParticleEmitter", {
		Name = "Dust",
		Texture = "rbxasset://textures/particles/sparkles_main.dds",
		Rate = 30,
		Lifetime = NumberRange.new(8, 12),
		Speed = NumberRange.new(0.2, 0.6),
		SpreadAngle = Vector2.new(180, 180),
		Acceleration = Vector3.new(0.15, 0.05, 0.1),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.12), NumberSequenceKeypoint.new(0.5, 0.16), NumberSequenceKeypoint.new(1, 0) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.2, 0.45), NumberSequenceKeypoint.new(1, 1) }),
		Color = ColorSequence.new(Color3.fromRGB(255, 232, 196)),
		LightEmission = 0.6,
	}, field)
end

function WorldBuilder.Build()
	setupLighting()
	setupTerrain()

	local map = folder("Map", workspace)
	folder("Stands", workspace)

	buildPlaza(map)
	buildHouses(map)
	buildClockTower(map)
	for i = 0, 7 do
		local a = (i + 0.5) / 8 * math.pi * 2
		streetLamp(map, Vector3.new(math.sin(a) * 44, 0, math.cos(a) * 44), i % 2 == 0)
	end
	buildAmbience(map)
	local _, prompt = buildAltar()
	buildDummies(map)
	return prompt, dummiesFolder
end

return WorldBuilder
