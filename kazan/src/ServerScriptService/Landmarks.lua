-- Достопримечательности Казани, собранные вручную на реальных местах (координаты и размеры из OSM):
-- мечеть Кул Шариф, падающая башня Сююмбике, Благовещенский собор, Спасская и другие башни Кремля,
-- Дворец земледельцев, колокольня Богоявленского собора, Петропавловский собор, Центр семьи «Казан».
local Landmarks = {}

local rad = math.rad
local SMOOTH = Enum.SurfaceType.Smooth
local CYL_UP = CFrame.Angles(0, 0, rad(90))

local WHITE = Color3.fromRGB(242, 240, 234)
local CREAM = Color3.fromRGB(232, 226, 212)
local GOLD = Color3.fromRGB(214, 176, 72)
local TURQ = Color3.fromRGB(42, 150, 186)
local BLUE = Color3.fromRGB(38, 96, 170)
local ROYAL = Color3.fromRGB(34, 70, 150)
local GREEN = Color3.fromRGB(38, 104, 72)
local BRICK = Color3.fromRGB(168, 70, 54)
local DARK = Color3.fromRGB(34, 32, 36)

local MARBLE = Enum.Material.Marble
local PLASTER = Enum.Material.Plaster
local METAL = Enum.Material.Metal
local GLASS = Enum.Material.Glass

local function P(parent, size, cf, color, material, shape)
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = SMOOTH
	p.BottomSurface = SMOOTH
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or PLASTER
	if shape then
		p.Shape = shape
	end
	p.Parent = parent
	return p
end

-- Блок с низом на высоте y
local function box(m, base, x, y, z, w, h, d, color, material)
	return P(m, Vector3.new(w, h, d), base * CFrame.new(x, y + h / 2, z), color, material)
end

-- Вертикальный цилиндр с низом на высоте y
local function cyl(m, base, x, y, z, h, dia, color, material)
	return P(m, Vector3.new(h, dia, dia), base * CFrame.new(x, y + h / 2, z) * CYL_UP, color, material, Enum.PartType.Cylinder)
end

local function ball(m, base, x, y, z, dia, color, material)
	return P(m, Vector3.new(dia, dia, dia), base * CFrame.new(x, y, z), color, material, Enum.PartType.Ball)
end

-- Ступенчатый «шатёр» из цилиндров
local function tent(m, base, x, y, z, d0, height, steps, color, material)
	local sh = height / steps
	for i = 0, steps - 1 do
		local t = i / steps
		cyl(m, base, x, y + i * sh, z, sh, math.max(d0 * (1 - t) * (1 - t * 0.15), 0.8), color, material or METAL)
	end
	return y + height
end

-- Ступенчатая пирамида из блоков
local function pyramid(m, base, x, y, z, w, d, height, steps, color)
	local sh = height / steps
	for i = 0, steps - 1 do
		local k = 1 - i / steps
		box(m, base, x, y + i * sh, z, math.max(w * k, 0.8), sh, math.max(d * k, 0.8), color, METAL)
	end
	return y + height
end

local function crescent(m, base, x, y, z, size)
	for i = 0, 6 do
		local a = rad(-70 + i * 23.3)
		ball(m, base, x + math.sin(a) * size, y + math.cos(a) * size, z, size * 0.32, GOLD, METAL)
	end
end

local function cross(m, base, x, y, z, size)
	box(m, base, x, y, z, size * 0.14, size, size * 0.14, GOLD, METAL)
	box(m, base, x, y + size * 0.62, z, size * 0.6, size * 0.12, size * 0.14, GOLD, METAL)
end

local function spire(m, base, x, y, z, height, topper)
	cyl(m, base, x, y, z, height, 0.7, GOLD, METAL)
	ball(m, base, x, y + height * 0.35, z, 1.8, GOLD, METAL)
	if topper == "crescent" then
		crescent(m, base, x, y + height + 2.2, z, 2.2)
	elseif topper == "cross" then
		cross(m, base, x, y + height, z, 4)
	else
		ball(m, base, x, y + height, z, 1.6, GOLD, METAL)
	end
end

-- Тёмные «арочные» окна по четырём сторонам блока
local function windowsAround(m, base, x, y, z, w, d, count, ww, wh, color)
	for face = 0, 3 do
		local along = (face % 2 == 0) and w or d
		local across = (face % 2 == 0) and d or w
		local rot = CFrame.Angles(0, face * math.pi / 2, 0)
		for i = 1, count do
			local off = -along / 2 + along * i / (count + 1)
			P(m, Vector3.new(ww, wh, 0.6), base * CFrame.new(x, 0, z) * rot * CFrame.new(off, y + wh / 2, -across / 2 - 0.2), color or DARK, GLASS)
		end
	end
end

local function modelFor(parent, name, persistent)
	local m = Instance.new("Model")
	m.Name = name
	if persistent then
		m.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	end
	m.Parent = parent
	return m
end

-------------------------------------------------------------------------------
-- Мечеть Кул Шариф: белый мрамор, бирюзовый купол-«шапка», четыре минарета по 58 м
-------------------------------------------------------------------------------
function Landmarks.KulSharif(m, base, w, d)
	local S = math.min(w, d)
	box(m, base, 0, 0, 0, S + 18, 3, S + 18, Color3.fromRGB(206, 202, 192), Enum.Material.Granite)
	local hall = S * 0.62
	box(m, base, 0, 3, 0, hall, 44, hall, WHITE, MARBLE)
	box(m, base, 0, 45, 0, hall + 1.5, 2, hall + 1.5, BLUE, METAL)
	windowsAround(m, base, 0, 10, 0, hall, hall, 3, 9, 26, Color3.fromRGB(40, 110, 170))
	-- угловые пилоны с бирюзовыми шатрами
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			local px, pz = sx * hall / 2, sz * hall / 2
			box(m, base, px, 3, pz, 12, 50, 12, WHITE, MARBLE)
			tent(m, base, px, 53, pz, 12, 10, 4, TURQ)
		end
	end
	-- второй ярус и барабан
	box(m, base, 0, 47, 0, hall * 0.78, 12, hall * 0.78, WHITE, MARBLE)
	windowsAround(m, base, 0, 49, 0, hall * 0.78, hall * 0.78, 4, 5, 8, Color3.fromRGB(40, 110, 170))
	cyl(m, base, 0, 59, 0, 14, hall * 0.68, WHITE, MARBLE)
	cyl(m, base, 0, 72, 0, 1.5, hall * 0.7, BLUE, METAL)
	-- купол в форме «казанской шапки»
	local dome = hall * 0.68
	ball(m, base, 0, 74, 0, dome, TURQ, GLASS).Reflectance = 0.1
	local topY = tent(m, base, 0, 74 + dome * 0.38, 0, dome * 0.55, 22, 6, TURQ, GLASS)
	spire(m, base, 0, topY, 0, 12, "crescent")
	-- четыре минарета
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			local px, pz = sx * (S / 2 + 2), sz * (S / 2 + 2)
			cyl(m, base, px, 0, pz, 8, 13, WHITE, MARBLE)
			cyl(m, base, px, 8, pz, 112, 8.5, WHITE, MARBLE)
			cyl(m, base, px, 70, pz, 2.4, 13, WHITE, MARBLE)
			cyl(m, base, px, 72.4, pz, 0.8, 13.4, BLUE, METAL)
			cyl(m, base, px, 120, pz, 2.4, 14, WHITE, MARBLE)
			cyl(m, base, px, 122.4, pz, 0.8, 14.4, BLUE, METAL)
			cyl(m, base, px, 123, pz, 27, 6.4, WHITE, MARBLE)
			cyl(m, base, px, 150, pz, 1.2, 7.6, BLUE, METAL)
			local t = tent(m, base, px, 151, pz, 7.2, 26, 6, TURQ, GLASS)
			spire(m, base, px, t, pz, 9, "crescent")
		end
	end
end

-------------------------------------------------------------------------------
-- Башня Сююмбике: семь ярусов красного кирпича с наклоном, зелёный шатёр
-------------------------------------------------------------------------------
function Landmarks.Syuyumbike(m, base)
	local lean = base * CFrame.Angles(rad(1.6), 0, rad(-0.9))
	local y = 0
	local tiers = {
		{ "sq", 40, 33 }, { "sq", 34, 28 }, { "sq", 28, 24 },
		{ "oct", 24, 18 }, { "oct", 20, 16 }, { "oct", 16, 14 }, { "oct", 12, 12 },
	}
	for i, t in ipairs(tiers) do
		local kind, size, h = t[1], t[2], t[3]
		if kind == "sq" then
			box(m, lean, 0, y, 0, size, h, size, BRICK, Enum.Material.Brick)
			box(m, lean, 0, y + h - 1.4, 0, size + 1.6, 1.4, size + 1.6, WHITE, PLASTER)
			if i == 1 then
				-- арка проезда
				box(m, lean, 0, y, 0, 10, 17, size + 0.6, DARK, Enum.Material.Slate)
			else
				windowsAround(m, lean, 0, y + h * 0.3, 0, size, size, 2, 3, h * 0.38)
			end
		else
			cyl(m, lean, 0, y, 0, h, size, BRICK, Enum.Material.Brick)
			cyl(m, lean, 0, y + h - 1.2, 0, 1.2, size + 1.4, WHITE, PLASTER)
			windowsAround(m, lean, 0, y + h * 0.3, 0, size * 0.72, size * 0.72, 1, 2.6, h * 0.42)
		end
		y = y + h
	end
	local t = tent(m, lean, 0, y, 0, 12, 40, 8, GREEN)
	spire(m, lean, 0, t, 0, 8, "crescent")
end

-------------------------------------------------------------------------------
-- Благовещенский собор: белый храм с синими куполами и колокольней
-------------------------------------------------------------------------------
function Landmarks.Annunciation(m, base, w, d)
	local mx = w / 2 - 48
	box(m, base, mx, 0, 0, 78, 52, math.min(d, 74), WHITE, PLASTER)
	box(m, base, mx, 52, 0, 80, 1.6, math.min(d, 74) + 2, Color3.fromRGB(70, 110, 90), METAL)
	windowsAround(m, base, mx, 16, 0, 78, math.min(d, 74), 4, 4, 12)
	for _, z in ipairs({ -22, 0, 22 }) do
		cyl(m, base, mx + 39, 0, z, 34, 22, WHITE, PLASTER)
		ball(m, base, mx + 39, 34, z, 22, Color3.fromRGB(70, 110, 90), METAL)
	end
	-- пять глав
	cyl(m, base, mx, 53, 0, 26, 22, WHITE, PLASTER)
	ball(m, base, mx, 84, 0, 26, ROYAL, METAL)
	spire(m, base, mx, 96, 0, 6, "cross")
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			cyl(m, base, mx + sx * 25, 53, sz * 25, 16, 12, WHITE, PLASTER)
			ball(m, base, mx + sx * 25, 72, sz * 25, 14, ROYAL, METAL)
			spire(m, base, mx + sx * 25, 79, sz * 25, 4, "cross")
		end
	end
	-- трапезная и колокольня
	box(m, base, mx - 80, 0, 0, 82, 30, math.min(d, 74) * 0.8, WHITE, PLASTER)
	box(m, base, mx - 80, 30, 0, 84, 1.4, math.min(d, 74) * 0.8 + 2, Color3.fromRGB(70, 110, 90), METAL)
	local bx = -w / 2 + 16
	box(m, base, bx, 0, 0, 26, 58, 26, WHITE, PLASTER)
	box(m, base, bx, 58, 0, 20, 22, 20, WHITE, PLASTER)
	windowsAround(m, base, bx, 62, 0, 20, 20, 1, 5, 12)
	local t = pyramid(m, base, bx, 80, 0, 20, 20, 24, 6, ROYAL)
	spire(m, base, bx, t, 0, 6, "cross")
end

-------------------------------------------------------------------------------
-- Спасская башня: главный въезд в Кремль
-------------------------------------------------------------------------------
function Landmarks.Spasskaya(m, base)
	box(m, base, 0, 0, 0, 52, 58, 52, WHITE, PLASTER)
	box(m, base, 0, 0, 0, 18, 30, 53, DARK, Enum.Material.Slate) -- арка ворот
	box(m, base, 0, 56, 0, 54, 2, 54, Color3.fromRGB(210, 206, 196), Enum.Material.Limestone)
	box(m, base, 0, 58, 0, 42, 28, 42, WHITE, PLASTER)
	windowsAround(m, base, 0, 64, 0, 42, 42, 2, 5, 12)
	-- часы на фасаде
	for face = 0, 3 do
		local rot = CFrame.Angles(0, face * math.pi / 2, 0)
		P(m, Vector3.new(0.6, 12, 12), base * rot * CFrame.new(0, 46, -26.4) * CFrame.Angles(0, rad(90), 0),
			Color3.fromRGB(250, 246, 236), MARBLE, Enum.PartType.Cylinder)
	end
	cyl(m, base, 0, 86, 0, 18, 34, WHITE, PLASTER)
	cyl(m, base, 0, 104, 0, 14, 26, WHITE, PLASTER)
	windowsAround(m, base, 0, 106, 0, 19, 19, 1, 4, 9)
	local t = tent(m, base, 0, 118, 0, 25, 30, 8, GREEN)
	spire(m, base, 0, t, 0, 9, nil)
	ball(m, base, 0, t + 11, 0, 3.6, GOLD, METAL)
end

-- Остальные башни Кремля: круглые угловые и квадратные проездные
function Landmarks.CastleTower(m, base, w, d, h, round)
	local size = math.min(w, d) * 0.9
	local body = h * 0.62
	if round then
		cyl(m, base, 0, 0, 0, body, size, WHITE, PLASTER)
		cyl(m, base, 0, body - 2, 0, 2, size + 2, Color3.fromRGB(210, 206, 196), Enum.Material.Limestone)
		windowsAround(m, base, 0, body * 0.55, 0, size * 0.72, size * 0.72, 1, 2, 5)
		local t = tent(m, base, 0, body, 0, size + 1, h - body, 7, GREEN)
		spire(m, base, 0, t, 0, 5, nil)
	else
		box(m, base, 0, 0, 0, size, body, size, WHITE, PLASTER)
		box(m, base, 0, body - 2, 0, size + 2, 2, size + 2, Color3.fromRGB(210, 206, 196), Enum.Material.Limestone)
		windowsAround(m, base, 0, body * 0.55, 0, size, size, 2, 2.5, 6)
		local t = pyramid(m, base, 0, body, 0, size + 1, size + 1, h - body, 7, GREEN)
		spire(m, base, 0, t, 0, 5, nil)
	end
end

-------------------------------------------------------------------------------
-- Дворец земледельцев: крылья с колоннадами, арка с бронзовым деревом, зелёный купол
-------------------------------------------------------------------------------
function Landmarks.FarmersPalace(m, base, w, d)
	local depth = math.min(d * 0.85, 130)
	local wingW = (w - 110) / 2
	for _, sx in ipairs({ -1, 1 }) do
		local x = sx * (55 + wingW / 2)
		box(m, base, x, 0, 0, wingW, 92, depth, CREAM, PLASTER)
		box(m, base, x, 92, 0, wingW + 2, 3, depth + 2, Color3.fromRGB(116, 132, 120), METAL)
		windowsAround(m, base, x, 14, 0, wingW, depth, 8, 5, 16)
		windowsAround(m, base, x, 52, 0, wingW, depth, 8, 5, 16)
		for _, sz in ipairs({ -1, 1 }) do
			for k = 0, 7 do
				local cx = x - wingW / 2 + 10 + k * (wingW - 20) / 7
				cyl(m, base, cx, 6, sz * (depth / 2 + 5), 70, 5, WHITE, MARBLE)
			end
			box(m, base, x, 76, sz * (depth / 2 + 5), wingW, 6, 10, CREAM, PLASTER)
			box(m, base, x, 0, sz * (depth / 2 + 5), wingW, 6, 12, Color3.fromRGB(200, 196, 186), Enum.Material.Granite)
		end
	end
	-- центральный корпус с аркой
	box(m, base, 0, 0, 0, 110, 120, depth + 6, CREAM, PLASTER)
	for _, sz in ipairs({ -1, 1 }) do
		box(m, base, 0, 0, sz * (depth / 2 + 3), 64, 90, 4, Color3.fromRGB(60, 56, 54), Enum.Material.Slate)
	end
	-- бронзовое дерево в арке
	local bronze = Color3.fromRGB(122, 92, 54)
	cyl(m, base, 0, 0, -(depth / 2 + 6), 62, 6, bronze, METAL)
	for k = 0, 5 do
		local a = rad(k * 60)
		P(m, Vector3.new(2.4, 26, 2.4), base * CFrame.new(math.cos(a) * 9, 66, -(depth / 2 + 6) + math.sin(a) * 4) * CFrame.Angles(0, 0, rad(k % 2 == 0 and 35 or -35)), bronze, METAL)
	end
	for k = 0, 8 do
		local a = rad(k * 40)
		ball(m, base, math.cos(a) * 16, 76 + (k % 3) * 4, -(depth / 2 + 6) + math.sin(a) * 5, 12, Color3.fromRGB(96, 110, 60), METAL)
	end
	-- купол
	cyl(m, base, 0, 120, 0, 12, 54, CREAM, PLASTER)
	ball(m, base, 0, 132, 0, 56, Color3.fromRGB(80, 160, 120), GLASS).Reflectance = 0.15
	spire(m, base, 0, 160, 0, 8, nil)
end

-------------------------------------------------------------------------------
-- Колокольня Богоявленского собора на улице Баумана (74 м)
-------------------------------------------------------------------------------
function Landmarks.BellTower(m, base)
	local tiers = { { 34, 75 }, { 28, 55 }, { 24, 42 } }
	local y = 0
	for _, t in ipairs(tiers) do
		local s, h = t[1], t[2]
		box(m, base, 0, y, 0, s, h, s, BRICK, Enum.Material.Brick)
		for _, sx in ipairs({ -1, 1 }) do
			for _, sz in ipairs({ -1, 1 }) do
				box(m, base, sx * (s / 2 - 1), y, sz * (s / 2 - 1), 2.6, h, 2.6, WHITE, PLASTER)
			end
		end
		box(m, base, 0, y + h - 2, 0, s + 2, 2, s + 2, WHITE, PLASTER)
		windowsAround(m, base, 0, y + h * 0.35, 0, s, s, 1, s * 0.22, h * 0.4)
		y = y + h
	end
	cyl(m, base, 0, y, 0, 30, 20, BRICK, Enum.Material.Brick)
	windowsAround(m, base, 0, y + 9, 0, 14, 14, 1, 3, 12)
	y = y + 30
	cyl(m, base, 0, y, 0, 20, 14, BRICK, Enum.Material.Brick)
	y = y + 20
	cyl(m, base, 0, y, 0, 8, 9, WHITE, PLASTER)
	y = y + 8
	ball(m, base, 0, y + 5, 0, 12, GOLD, METAL)
	ball(m, base, 0, y + 11, 0, 5, GOLD, METAL)
	spire(m, base, 0, y + 12, 0, 4, "cross")
end

-------------------------------------------------------------------------------
-- Петропавловский собор: барочный храм с зелёными главами и колокольней
-------------------------------------------------------------------------------
function Landmarks.PeterPaul(m, base, w, d)
	local walls = Color3.fromRGB(240, 218, 204)
	local mx = w / 2 - 40
	box(m, base, mx, 0, 0, 70, 58, math.min(d, 70), walls, PLASTER)
	windowsAround(m, base, mx, 12, 0, 70, math.min(d, 70), 4, 5, 14)
	windowsAround(m, base, mx, 36, 0, 70, math.min(d, 70), 4, 5, 12)
	cyl(m, base, mx, 58, 0, 24, 26, walls, PLASTER)
	ball(m, base, mx, 86, 0, 30, GREEN, METAL)
	cyl(m, base, mx, 98, 0, 8, 6, walls, PLASTER)
	ball(m, base, mx, 108, 0, 7, GOLD, METAL)
	spire(m, base, mx, 111, 0, 5, "cross")
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			cyl(m, base, mx + sx * 26, 58, sz * 26, 12, 10, walls, PLASTER)
			ball(m, base, mx + sx * 26, 72, sz * 26, 11, GREEN, METAL)
			spire(m, base, mx + sx * 26, 77, sz * 26, 3, "cross")
		end
	end
	local bx = -w / 2 + 16
	box(m, base, bx, 0, 0, 26, 52, 26, walls, PLASTER)
	box(m, base, bx, 52, 0, 20, 30, 20, walls, PLASTER)
	windowsAround(m, base, bx, 58, 0, 20, 20, 1, 5, 14)
	cyl(m, base, bx, 82, 0, 22, 14, walls, PLASTER)
	local t = tent(m, base, bx, 104, 0, 14, 40, 8, GREEN)
	spire(m, base, bx, t, 0, 6, "cross")
end

-------------------------------------------------------------------------------
-- Центр семьи «Казан» — здание-чаша на берегу Казанки
-------------------------------------------------------------------------------
function Landmarks.FamilyCenter(m, base)
	cyl(m, base, 0, 0, 0, 20, 136, Color3.fromRGB(226, 222, 214), MARBLE)
	cyl(m, base, 0, 20, 0, 56, 52, Color3.fromRGB(120, 156, 180), GLASS).Reflectance = 0.2
	local bronze = Color3.fromRGB(204, 162, 80)
	local dias = { 60, 80, 96, 110, 121, 130, 136 }
	local y = 76
	for i, dia in ipairs(dias) do
		cyl(m, base, 0, y, 0, 8.6, dia, (i == 4) and Color3.fromRGB(150, 110, 50) or bronze, METAL)
		y = y + 8.6
	end
	cyl(m, base, 0, y, 0, 3, 141, GOLD, METAL)
	cyl(m, base, 0, y + 2.5, 0, 1, 128, Color3.fromRGB(70, 66, 64), Enum.Material.Slate)
end

-------------------------------------------------------------------------------
local BUILDERS = {
	KulSharif = { Landmarks.KulSharif, true },
	Syuyumbike = { Landmarks.Syuyumbike, true },
	Annunciation = { Landmarks.Annunciation, true },
	Spasskaya = { Landmarks.Spasskaya, true },
	FarmersPalace = { Landmarks.FarmersPalace, true },
	BellTower = { Landmarks.BellTower, true },
	PeterPaul = { Landmarks.PeterPaul, true },
	FamilyCenter = { Landmarks.FamilyCenter, true },
}
local ROUND_TOWERS = { SouthWest = true, SouthEast = true, Nameless = true }

function Landmarks.BuildAll(parent, chunks)
	local root = Instance.new("Folder")
	root.Name = "Landmarks"
	root.Parent = parent
	for _, chunk in ipairs(chunks) do
		for rec in string.gmatch(chunk, "[^;]+") do
			local f = string.split(rec, ",")
			local name = f[1]
			local x, z, w, d, phi, h = tonumber(f[2]), tonumber(f[3]), tonumber(f[4]), tonumber(f[5]), tonumber(f[6]), tonumber(f[7])
			local base = CFrame.new(x, 0, z) * CFrame.Angles(0, phi, 0)
			local spec = BUILDERS[name]
			local m = modelFor(root, name, true)
			local ok, err = pcall(function()
				if spec then
					spec[1](m, base, w, d, h)
				else
					Landmarks.CastleTower(m, base, w, d, h, ROUND_TOWERS[name] == true)
				end
			end)
			if not ok then
				warn("Landmark", name, err)
			end
			task.wait()
		end
	end
end

return Landmarks
