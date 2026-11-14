-- Детализированная древняя стрела: древко, оперение, золотые кольца, наконечник с гравировкой и камнем.
-- Собирается вдоль оси X: остриё смотрит в +X, хвостовик в -X. Опорная точка модели (Core) в центре.
local ArrowBuilder = {}

local rad = math.rad
local METAL = Enum.Material.Metal
local NEON = Enum.Material.Neon

local WOOD = Color3.fromRGB(104, 72, 46)
local DARK_WOOD = Color3.fromRGB(46, 32, 24)
local GOLD = Color3.fromRGB(214, 172, 62)
local OLD_GOLD = Color3.fromRGB(226, 192, 96)
local DGOLD = Color3.fromRGB(142, 104, 34)
local CRIMSON = Color3.fromRGB(122, 16, 30)
local IVORY = Color3.fromRGB(232, 226, 210)
local GEM = Color3.fromRGB(150, 15, 50)
local GEM_GLOW = Color3.fromRGB(255, 40, 90)
local FILIGREE = Color3.fromRGB(255, 222, 140)

local function part(model, className, size, cf, color, material, shape)
	local p = Instance.new(className)
	p.Name = "ArrowPart"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material
	if shape then
		p.Shape = shape
	end
	if material == NEON then
		p.CastShadow = false
	end
	p.Parent = model
	return p
end

-- Треугольная пластина в плоскости, натянутой на ось стрелы (X) и радиальное направление.
-- base: расстояние основания от оси, h: высота треугольника,
-- fullAtFront: полная высота у x1 (ближе к острию), иначе у x0.
local function tri(model, radial, x0, x1, base, h, fullAtFront, thick, color, material)
	local X = Vector3.new(1, 0, 0)
	local up = radial
	local back = fullAtFront and X or -X
	local right = up:Cross(back)
	local center = X * ((x0 + x1) / 2) + radial * (base + h / 2)
	local cf = CFrame.fromMatrix(center, right, up, back)
	return part(model, "WedgePart", Vector3.new(thick, h, math.abs(x1 - x0)), cf, color, material)
end

local function cyl(model, x, length, diameter, color, material)
	return part(model, "Part", Vector3.new(length, diameter, diameter), CFrame.new(x, 0, 0), color, material, Enum.PartType.Cylinder)
end

function ArrowBuilder.Build()
	local model = Instance.new("Model")
	model.Name = "Arrow"

	local core = part(model, "Part", Vector3.new(0.2, 0.2, 0.2), CFrame.new(), WOOD, Enum.Material.SmoothPlastic)
	core.Name = "Core"
	core.Transparency = 1
	model.PrimaryPart = core

	-- Древко
	cyl(model, -0.525, 3.75, 0.14, WOOD, Enum.Material.Wood)

	-- Хвостовик с прорезью под тетиву
	cyl(model, -2.48, 0.18, 0.17, DARK_WOOD, Enum.Material.Wood)
	part(model, "Part", Vector3.new(0.14, 0.17, 0.05), CFrame.new(-2.6, 0, 0.055), DARK_WOOD, Enum.Material.Wood)
	part(model, "Part", Vector3.new(0.14, 0.17, 0.05), CFrame.new(-2.6, 0, -0.055), DARK_WOOD, Enum.Material.Wood)

	-- Обмотка нитью у оперения
	cyl(model, -2.3, 0.14, 0.165, CRIMSON, Enum.Material.Fabric)
	cyl(model, -1.22, 0.14, 0.165, CRIMSON, Enum.Material.Fabric)

	-- Три пера через 120 градусов, одно красное «ведущее»
	for i = 0, 2 do
		local theta = rad(90 + i * 120)
		local radial = Vector3.new(0, math.cos(theta), math.sin(theta))
		local color = (i == 0) and CRIMSON or IVORY
		tri(model, radial, -2.25, -1.3, 0.07, 0.34, false, 0.025, color, Enum.Material.Fabric)
		tri(model, radial, -2.36, -2.25, 0.07, 0.34, true, 0.025, color, Enum.Material.Fabric)
		-- стержень пера
		part(model, "Part", Vector3.new(1.08, 0.022, 0.022), CFrame.new(Vector3.new(-1.8, 0, 0) + radial * 0.08), DARK_WOOD, Enum.Material.Wood)
	end

	-- Золотые кольца и гравировка на древке
	for _, x in ipairs({ -0.95, -0.35, 0.25, 0.85 }) do
		cyl(model, x, 0.06, 0.175, GOLD, METAL)
	end
	for _, x in ipairs({ -0.65, 0.55 }) do
		cyl(model, x, 0.025, 0.16, DGOLD, METAL)
	end
	-- Светящиеся руны между кольцами
	for _, x in ipairs({ -0.05 }) do
		cyl(model, x, 0.03, 0.152, FILIGREE, NEON)
	end

	-- Втулка наконечника с ожерельем из бусин
	cyl(model, 1.5, 0.36, 0.2, GOLD, METAL)
	cyl(model, 1.34, 0.05, 0.24, DGOLD, METAL)
	cyl(model, 1.66, 0.05, 0.24, DGOLD, METAL)
	for i = 0, 7 do
		local a = (i / 8) * math.pi * 2
		part(model, "Part", Vector3.new(0.06, 0.06, 0.06), CFrame.new(1.5, math.cos(a) * 0.105, math.sin(a) * 0.105), OLD_GOLD, METAL, Enum.PartType.Ball)
	end

	-- Листовидный обоюдоострый наконечник
	local UP = Vector3.new(0, 1, 0)
	local DOWN = Vector3.new(0, -1, 0)
	for _, r in ipairs({ UP, DOWN }) do
		tri(model, r, 1.66, 2.02, 0, 0.3, true, 0.035, OLD_GOLD, METAL)   -- расширение
		tri(model, r, 2.02, 2.8, 0, 0.3, false, 0.035, OLD_GOLD, METAL)   -- сужение к острию
		tri(model, r, 1.6, 2.02, 0.18, 0.2, true, 0.045, DGOLD, METAL)    -- зазубрины-крылья
		-- гравировка-филигрань
		part(model, "Part", Vector3.new(0.42, 0.018, 0.045), CFrame.new(Vector3.new(2.12, 0, 0) + r * 0.12), FILIGREE, NEON)
	end
	part(model, "Part", Vector3.new(1.05, 0.05, 0.07), CFrame.new(2.2, 0, 0), DGOLD, METAL) -- центральное ребро

	-- Камень в основании клинка
	part(model, "Part", Vector3.new(0.17, 0.17, 0.17), CFrame.new(2.0, 0, 0), GEM, Enum.Material.Glass, Enum.PartType.Ball)
	part(model, "Part", Vector3.new(0.09, 0.09, 0.09), CFrame.new(2.0, 0, 0), GEM_GLOW, NEON, Enum.PartType.Ball)

	local glow = Instance.new("PointLight")
	glow.Color = GEM_GLOW
	glow.Range = 7
	glow.Brightness = 1.4
	glow.Shadows = false
	glow.Parent = core

	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Name = "Sparkles"
	sparkles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparkles.Rate = 10
	sparkles.Lifetime = NumberRange.new(1.2, 2)
	sparkles.Speed = NumberRange.new(0.2, 0.6)
	sparkles.SpreadAngle = Vector2.new(180, 180)
	sparkles.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.18), NumberSequenceKeypoint.new(1, 0) })
	sparkles.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	sparkles.Color = ColorSequence.new(OLD_GOLD, GEM_GLOW)
	sparkles.LightEmission = 1
	sparkles.Parent = core

	return model
end

return ArrowBuilder
