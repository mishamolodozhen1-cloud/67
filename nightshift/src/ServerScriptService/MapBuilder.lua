-- MapBuilder: строит супермаркет MART 24 при запуске сервера.
-- Все объекты лежат в Workspace.Store. Функция Build() возвращает таблицу map со ссылками
-- на важные детали (кассы, полки, холодильники, двери, камеры…), которой пользуются остальные системы.
--
-- План (координаты в стадах, пол на высоте 0):
--   Торговый зал        x -66..40,  z -12..50  (вход с парковки по z = 50)
--   Склад               x -66..-18, z -64..-12
--   Служебный коридор   x -18..-10, z -64..-12 (щиток, задний выход)
--   Коридор             x -10..40,  z -40..-34
--   Охрана              x -10..12,  z -34..-12
--   Комната персонала   x  12..40,  z -34..-12 (здесь появляются игроки)
--   Холодильная камера  x -10..12,  z -64..-40
--   Кабинет менеджера   x  12..40,  z -64..-40 (мониторы камер, записка, часы)
--   Задний двор         x -40..10,  z -92..-64
--   Улица: парковка z 58..120, дорога z 120..132, тротуар напротив и тёмные дома
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Products = require(Shared:WaitForChild("Products"))
local Texts = require(Shared:WaitForChild("Texts"))
local Models = require(Shared:WaitForChild("Models"))
local ModelKit = require(script.Parent:WaitForChild("ModelKit"))

local MapBuilder = {}

local M = Enum.Material
local N = Enum.NormalId
local SMOOTH = Enum.SurfaceType.Smooth
local I = Config.Images
local rng = Random.new(2003)

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

-- Палитра
local C = {
	Wall = rgb(226, 224, 216),
	WallBack = rgb(196, 194, 186),
	Kick = rgb(64, 68, 74),
	FloorTile = rgb(214, 216, 212),
	Ceiling = rgb(236, 236, 232),
	Metal = rgb(214, 216, 218),
	Dark = rgb(52, 54, 58),
	Black = rgb(22, 22, 24),
	Price = rgb(250, 214, 60),
	Red = rgb(200, 36, 40),
	Green = rgb(30, 140, 70),
	Wood = rgb(150, 110, 70),
	Cardboard = rgb(176, 136, 90),
	Concrete = rgb(140, 140, 136),
	-- старые люминесцентные лампы: бледный свет с лёгкой зеленью
	Lamp = rgb(232, 246, 236),
	LampWarm = rgb(255, 226, 180),
	LampCold = rgb(200, 226, 255),
	Sodium = rgb(255, 178, 100),
	Exit = rgb(40, 220, 90),
}

local created = 0
local function step()
	created = created + 1
	if created % 400 == 0 then
		task.wait()
	end
end

-- Деталь по центру и размеру
local function P(parent, name, size, cf, color, material, extra)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or M.SmoothPlastic
	p.TopSurface = SMOOTH
	p.BottomSurface = SMOOTH
	if extra then
		for k, v in pairs(extra) do
			p[k] = v
		end
	end
	p.Parent = parent
	step()
	return p
end

-- Деталь по двум углам (x0,y0,z0)-(x1,y1,z1)
local function B(parent, name, x0, y0, z0, x1, y1, z1, color, material, extra)
	local size = Vector3.new(math.abs(x1 - x0), math.abs(y1 - y0), math.abs(z1 - z0))
	return P(parent, name, size, CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), color, material, extra)
end

-- Цилиндр, стоящий вертикально
local function Cyl(parent, name, diameter, height, pos, color, material, extra)
	local p = P(parent, name, Vector3.new(height, diameter, diameter), CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90)), color, material, extra)
	p.Shape = Enum.PartType.Cylinder
	return p
end

local function folder(name, parent)
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

local function model(name, parent)
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

local function tag(inst, name)
	CollectionService:AddTag(inst, name)
end

-- Текстура, повторяющаяся по грани
local function tex(part, face, image, u, v, offU, color)
	local t = Instance.new("Texture")
	t.Texture = image
	t.Face = face
	t.StudsPerTileU = u
	t.StudsPerTileV = v
	t.OffsetStudsU = offU or 0
	if color then
		t.Color3 = color
	end
	t.Parent = part
	return t
end

-- Обтянуть грани детали текстурой материала (studs — размер одной плитки в стадах)
local function skin(part, image, studs, faces, color)
	for _, face in ipairs(faces) do
		tex(part, face, image, studs, studs, 0, color)
	end
	return part
end

-- Картинка на грани (растягивается на всю грань): этикетки товаров
local function decal(part, face, image)
	local d = Instance.new("Decal")
	d.Texture = image
	d.Face = face
	d.Parent = part
	return d
end

-- Надпись на грани детали
local function sign(part, face, text, o)
	o = o or {}
	local sg = Instance.new("SurfaceGui")
	sg.Name = o.name or "Sign"
	sg.Face = face
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = o.ppS or 40
	sg.LightInfluence = o.light or 1
	sg.Brightness = o.brightness or 1
	sg.MaxDistance = o.maxDistance or 90
	sg.Parent = part
	local t = Instance.new("TextLabel")
	t.Name = "Text"
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = o.bg and 0 or 1
	t.BackgroundColor3 = o.bg or Color3.new(0, 0, 0)
	t.BorderSizePixel = 0
	t.Text = text
	t.TextColor3 = o.color or Color3.new(0.1, 0.1, 0.1)
	t.Font = o.font or Enum.Font.GothamBold
	t.TextScaled = o.scaled ~= false
	t.TextSize = o.textSize or 24
	t.TextWrapped = true
	t.TextXAlignment = o.alignX or Enum.TextXAlignment.Center
	t.TextYAlignment = o.alignY or Enum.TextYAlignment.Center
	t.LineHeight = o.lineHeight or 1
	t.Parent = sg
	if o.padding then
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, o.padding)
		pad.PaddingRight = UDim.new(0, o.padding)
		pad.PaddingTop = UDim.new(0, o.padding)
		pad.PaddingBottom = UDim.new(0, o.padding)
		pad.Parent = t
	end
	if o.maxText then
		local c = Instance.new("UITextSizeConstraint")
		c.MaxTextSize = o.maxText
		c.Parent = t
	end
	return t, sg
end

-- Стена вдоль оси X (линия z = zc) с проёмами {x0, x1, высота проёма}.
-- look = { Image, Studs, Color } — текстура на обе стороны стены
local function wallX(parent, name, zc, x0, x1, y0, y1, openings, color, material, t, look)
	t = t or 1
	table.sort(openings, function(a, b)
		return a[1] < b[1]
	end)
	local parts = {}
	local cur = x0
	for _, o in ipairs(openings) do
		if o[1] > cur then
			table.insert(parts, B(parent, name, cur, y0, zc - t / 2, o[1], y1, zc + t / 2, color, material))
		end
		if o[3] < y1 then
			table.insert(parts, B(parent, name .. "Lintel", o[1], o[3], zc - t / 2, o[2], y1, zc + t / 2, color, material))
		end
		cur = o[2]
	end
	if cur < x1 then
		table.insert(parts, B(parent, name, cur, y0, zc - t / 2, x1, y1, zc + t / 2, color, material))
	end
	if look then
		for _, p in ipairs(parts) do
			skin(p, look[1], look[2], { N.Front, N.Back }, look[3])
		end
	end
	return parts
end

-- Стена вдоль оси Z (линия x = xc) с проёмами {z0, z1, высота проёма}
local function wallZ(parent, name, xc, z0, z1, y0, y1, openings, color, material, t, look)
	t = t or 1
	table.sort(openings, function(a, b)
		return a[1] < b[1]
	end)
	local parts = {}
	local cur = z0
	for _, o in ipairs(openings) do
		if o[1] > cur then
			table.insert(parts, B(parent, name, xc - t / 2, y0, cur, xc + t / 2, y1, o[1], color, material))
		end
		if o[3] < y1 then
			table.insert(parts, B(parent, name .. "Lintel", xc - t / 2, o[3], o[1], xc + t / 2, y1, o[2], color, material))
		end
		cur = o[2]
	end
	if cur < z1 then
		table.insert(parts, B(parent, name, xc - t / 2, y0, cur, xc + t / 2, y1, z1, color, material))
	end
	if look then
		for _, p in ipairs(parts) do
			skin(p, look[1], look[2], { N.Left, N.Right }, look[3])
		end
	end
	return parts
end

-- Потолочный светильник. Лампы отмечены тегом StoreLight: клиент выключает их при отключении электричества.
local function ceilingLight(parent, pos, length, alongX, zone, o)
	o = o or {}
	local color = o.color or C.Lamp
	local size = alongX and Vector3.new(length, 0.12, 1.1) or Vector3.new(1.1, 0.12, length)
	local hsize = alongX and Vector3.new(length + 0.3, 0.3, 1.5) or Vector3.new(1.5, 0.3, length + 0.3)
	P(parent, "LightHousing", hsize, CFrame.new(pos + Vector3.new(0, 0.2, 0)), C.Metal, M.Metal)
	local lamp = P(parent, "Lamp", size, CFrame.new(pos), color, M.Neon, { CastShadow = false })
	local sl = Instance.new("SurfaceLight")
	sl.Face = N.Bottom
	sl.Angle = o.angle or 120
	sl.Range = o.range or 20
	sl.Brightness = o.brightness or 1.05
	sl.Color = color
	sl.Shadows = o.shadows == true
	sl.Parent = lamp
	lamp:SetAttribute("Zone", zone)
	lamp:SetAttribute("LampColor", color)
	if o.broken then
		lamp:SetAttribute("Broken", true)
	end
	tag(lamp, "StoreLight")
	return lamp
end

-- Подвесной промышленный светильник (склад, двор, улица)
local function pendantLight(parent, pos, zone, o)
	o = o or {}
	local color = o.color or C.LampWarm
	Cyl(parent, "Cable", 0.08, o.cable or 3, pos + Vector3.new(0, (o.cable or 3) / 2 + 0.4, 0), C.Black, M.SmoothPlastic)
	P(parent, "Shade", Vector3.new(2.2, 0.8, 2.2), CFrame.new(pos + Vector3.new(0, 0.3, 0)), C.Dark, M.Metal)
	local lamp = P(parent, "Lamp", Vector3.new(1.4, 0.15, 1.4), CFrame.new(pos - Vector3.new(0, 0.12, 0)), color, M.Neon, { CastShadow = false })
	local sl = Instance.new("SpotLight")
	sl.Face = N.Bottom
	sl.Angle = o.angle or 110
	sl.Range = o.range or 26
	sl.Brightness = o.brightness or 1.6
	sl.Color = color
	sl.Shadows = o.shadows == true
	sl.Parent = lamp
	lamp:SetAttribute("Zone", zone)
	lamp:SetAttribute("LampColor", color)
	if o.broken then
		lamp:SetAttribute("Broken", true)
	end
	tag(lamp, "StoreLight")
	return lamp
end

-- Табличка «ВЫХОД» над дверью — горит всегда (аварийное питание)
local function exitSign(parent, pos, faceDir)
	local cf = CFrame.lookAt(pos, pos + faceDir)
	local box = P(parent, "ExitSign", Vector3.new(2.6, 0.9, 0.25), cf, C.Exit, M.Neon, { CastShadow = false })
	sign(box, N.Front, "ВЫХОД", { color = Color3.new(1, 1, 1), light = 0, brightness = 2, ppS = 30 })
	local l = Instance.new("PointLight")
	l.Color = C.Exit
	l.Range = 7
	l.Brightness = 0.8
	l.Parent = box
	tag(box, "EmergencyLight")
	return box
end

-- Распашная дверь: детали поворачиваются вокруг вертикальной оси через hinge на угол angle (градусы)
local function hingedDoor(name, parts, hinge, angle, kind, objectText)
	local hcf = CFrame.new(hinge)
	local closed, open = {}, {}
	for i, part in ipairs(parts) do
		closed[i] = part.CFrame
		open[i] = hcf * CFrame.Angles(0, math.rad(angle), 0) * hcf:Inverse() * part.CFrame
	end
	return {
		Name = name,
		Parts = parts,
		Closed = closed,
		Open = open,
		Kind = kind or "Swing",
		Label = objectText,
		IsOpen = false,
		Locked = false,
	}
end

-- Одна створка двери: полотно, ручка, (окошко)
local function doorLeaf(parent, x0, x1, z, h, color, material, handleSide, windowed)
	local leaf = B(parent, "DoorLeaf", x0 + 0.04, 0.02, z - 0.13, x1 - 0.04, h - 0.04, z + 0.13, color, material)
	local parts = { leaf }
	local hx = handleSide > 0 and (x1 - 0.45) or (x0 + 0.45)
	table.insert(parts, B(parent, "Handle", hx - 0.1, 3.4, z - 0.32, hx + 0.1, 3.6, z + 0.32, C.Metal, M.Metal))
	if windowed then
		local cx = (x0 + x1) / 2
		table.insert(parts, B(parent, "DoorWindow", cx - 0.6, 5.2, z - 0.15, cx + 0.6, 6.6, z + 0.15, rgb(160, 190, 200), M.Glass, { Transparency = 0.45 }))
	end
	return parts
end

-- Та же створка в стене вдоль Z
local function doorLeafZ(parent, z0, z1, x, h, color, material, handleSide)
	local leaf = B(parent, "DoorLeaf", x - 0.13, 0.02, z0 + 0.04, x + 0.13, h - 0.04, z1 - 0.04, color, material)
	local hz = handleSide > 0 and (z1 - 0.45) or (z0 + 0.45)
	local handle = B(parent, "Handle", x - 0.32, 3.4, hz - 0.1, x + 0.32, 3.6, hz + 0.1, C.Metal, M.Metal)
	return { leaf, handle }
end

-------------------------------------------------------------------------------
-- Объёмный товар: коробка, пакет, банка, бутылка, пакет молока, флакон.
-- cf — центр товара, передняя грань (с этикеткой) смотрит по cf.LookVector.
-------------------------------------------------------------------------------
local CYL_UP = CFrame.Angles(0, 0, math.rad(90)) -- ось цилиндра вертикально; передняя грань остаётся спереди

local function productPart(parent, style, cf)
	local s = style.Size
	local parts = {}
	if style.Shape == "Can" or style.Shape == "Bottle" then
		local body = P(parent, "Product", Vector3.new(s.Y, s.X, s.Z), cf * CYL_UP, Color3.new(1, 1, 1), M.SmoothPlastic, { CastShadow = false })
		body.Shape = Enum.PartType.Cylinder
		decal(body, N.Front, style.Label)
		table.insert(parts, body)
		if style.Shape == "Bottle" then
			local neck = P(parent, "ProductCap", Vector3.new(0.18, s.X * 0.42, s.X * 0.42), cf * CFrame.new(0, s.Y / 2 + 0.09, 0) * CYL_UP, rgb(40, 110, 196), M.SmoothPlastic, { CastShadow = false })
			neck.Shape = Enum.PartType.Cylinder
			table.insert(parts, neck)
		end
	elseif style.Shape == "Bag" then
		local bag = P(parent, "Product", s, cf, Color3.new(1, 1, 1), M.Foil, { CastShadow = false })
		decal(bag, N.Front, style.Label)
		table.insert(parts, bag)
	else -- Box и Flask
		local box = P(parent, "Product", s, cf, Color3.new(1, 1, 1), M.SmoothPlastic, { CastShadow = false })
		decal(box, N.Front, style.Label)
		table.insert(parts, box)
		if style.Shape == "Flask" then
			local cap = P(parent, "ProductCap", Vector3.new(s.X * 0.3, 0.24, s.Z * 0.5), cf * CFrame.new(0, s.Y / 2 + 0.12, 0), rgb(240, 240, 240), M.SmoothPlastic, { CastShadow = false })
			table.insert(parts, cap)
		end
	end
	return parts
end

-------------------------------------------------------------------------------
-- 3D-модели: продукты (Melon Polygons) и полки, холодильники, стеллажи (SimplePolygon)
-------------------------------------------------------------------------------
local SS = Models.ShelfScale -- studs на метр для полок и холодильников
local PS = Models.ProductScale -- studs на метр для продуктов

local function useModels(list)
	return ModelKit.Ready and ModelKit.HasAll(list)
end

-- Размер продукта на полке: ширина вдоль полки, глубина, высота (studs)
local function productFootprint(def)
	local s = def.Size * PS
	if def.Pose == "Upright" then
		return s.X, s.Y, s.Z
	end
	return s.X, s.Z, s.Y
end

-- Ряд продуктов-моделей. Лицевая сторона (этикетка) смотрит в проход.
-- Stand — в один ярус, Stack — в 2–3 яруса, Flat — стопкой этикеткой вверх, Upright — пакет на ребре.
local function modelProductLayer(parent, x0, x1, y, z0, z1, face, category, clearance)
	local list = Models.Shelf[category]
	local name = list[rng:NextInteger(1, #list)]
	local def = Models.Meshes[name]
	local w, d, h = productFootprint(def)
	local alongZ = (face == N.Left or face == N.Right)
	local outward = (face == N.Left or face == N.Front) and -1 or 1
	local a0, a1 = alongZ and z0 or x0, alongZ and z1 or x1
	local d0, d1 = alongZ and x0 or z0, alongZ and x1 or z1
	local frontPlane = outward < 0 and d0 or d1
	local look = alongZ and Vector3.new(outward, 0, 0) or Vector3.new(0, 0, outward)
	local gap = 0.04
	local count = math.max(1, math.floor((a1 - a0 + gap) / (w + gap)))
	local used = count * (w + gap) - gap
	local first = a0 + ((a1 - a0) - used) / 2 + w / 2
	-- тонкие коробки ставим в два ряда (иначе полка выглядит пустой), остальное — в один
	local rows = (d < 0.35) and 2 or 1
	rows = math.max(1, math.min(rows, math.floor((d1 - d0 + gap) / (d + gap))))
	local layers = 1
	if def.Pose == "Stack" then
		layers = math.clamp(math.floor((clearance or 1.8) * 0.8 / h), 1, 2)
	elseif def.Pose == "Flat" then
		layers = math.clamp(math.floor((clearance or 1.8) * 0.3 / h), 1, 3)
	end
	-- не больше ~40 деталей на полку (телефоны)
	while count * rows * layers > 40 and (rows > 1 or layers > 1) do
		if rows > 1 then
			rows = rows - 1
		else
			layers = layers - 1
		end
	end
	local size = def.Size * PS
	local parts = {}
	for r = 0, rows - 1 do
		local dc = frontPlane - outward * (0.06 + d / 2 + r * (d + gap))
		for i = 0, count - 1 do
			local a = first + i * (w + gap)
			local pile = layers
			if def.Pose == "Flat" then
				pile = rng:NextInteger(math.max(1, layers - 2), layers)
			end
			for k = 0, pile - 1 do
				local cy = y + h / 2 + k * (h + 0.004)
				local jitter = rng:NextNumber(-0.03, 0.03)
				local pos = alongZ and Vector3.new(dc + jitter, cy, a) or Vector3.new(a, cy, dc + jitter)
				local cf = CFrame.lookAt(pos, pos + look) * CFrame.Angles(0, math.rad(rng:NextNumber(-3, 3)), 0)
				if def.Pose == "Upright" then
					cf = cf * CFrame.Angles(math.rad(-90), 0, 0)
				end
				local p = ModelKit.Make(name, parent, cf, size, { Name = "Product", CanCollide = false, CastShadow = false })
				if p then
					table.insert(parts, p)
				end
			end
		end
	end
	return parts
end

-- Ряд товара на полке. Коробка (x0..x1, z0..z1) — место под товар, y — высота полки,
-- face — куда смотрит покупатель (Left = -X, Right = +X, Front = -Z, Back = +Z).
-- Если передан facings, ряд можно опустошать и пополнять (задание «выложить товар»).
local function productLayer(parent, x0, x1, y, z0, z1, face, category, facings, info, clearance)
	local holderTop = y + math.min(clearance or 1.35, 1.6)
	if Models.Shelf[category] and useModels(Models.Shelf[category]) then
		local parts = modelProductLayer(parent, x0, x1, y, z0, z1, face, category, clearance)
		local holder = B(parent, "Facing", x0, y, z0, x1, holderTop, z1, Color3.new(1, 1, 1), M.SmoothPlastic, {
			Transparency = 1,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			CastShadow = false,
		})
		if facings then
			info.Front = holder
			info.Parts = parts
			info.Category = category
			table.insert(facings, info)
		end
		return holder, parts
	end
	local styles = Products.ShelfStyles[category]
	if not styles then
		return nil
	end
	local style = styles[rng:NextInteger(1, #styles)]
	local s = style.Size
	local alongZ = (face == N.Left or face == N.Right)
	local outward = (face == N.Left or face == N.Front) and -1 or 1
	local a0, a1 = alongZ and z0 or x0, alongZ and z1 or x1
	local d0, d1 = alongZ and x0 or z0, alongZ and x1 or z1
	local frontPlane = outward < 0 and d0 or d1
	local gap = 0.05
	local count = math.max(1, math.floor((a1 - a0 + gap) / (s.X + gap)))
	local used = count * (s.X + gap) - gap
	local first = a0 + ((a1 - a0) - used) / 2 + s.X / 2
	local dCenter = frontPlane - outward * (s.Z / 2 + 0.06)
	local look = alongZ and Vector3.new(outward, 0, 0) or Vector3.new(0, 0, outward)
	local parts = {}
	for i = 0, count - 1 do
		local a = first + i * (s.X + gap)
		local jitter = rng:NextNumber(-0.04, 0.04)
		local pos = alongZ and Vector3.new(dCenter + jitter, y + s.Y / 2, a) or Vector3.new(a, y + s.Y / 2, dCenter + jitter)
		local cf = CFrame.lookAt(pos, pos + look) * CFrame.Angles(0, math.rad(rng:NextNumber(-4, 4)), 0)
		for _, p in ipairs(productPart(parent, style, cf)) do
			table.insert(parts, p)
		end
	end
	-- невидимая «полка-держатель» для подсказки «Выложить товар»
	local holder = B(parent, "Facing", x0, y, z0, x1, y + 1.35, z1, Color3.new(1, 1, 1), M.SmoothPlastic, {
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
	})
	if facings then
		info.Front = holder
		info.Parts = parts
		info.Category = category
		table.insert(facings, info)
	end
	return holder, parts
end

-- Ценник на кромке полки
local function priceTag(parent, pos, face, price)
	local cf = CFrame.new(pos)
	local size = (face == N.Left or face == N.Right) and Vector3.new(0.05, 0.3, 0.7) or Vector3.new(0.7, 0.3, 0.05)
	local p = P(parent, "PriceTag", size, cf, Color3.new(1, 1, 1), M.SmoothPlastic, { CanCollide = false, CastShadow = false })
	sign(p, face, price .. " ₽", { color = rgb(200, 30, 30), ppS = 80, maxDistance = 22, font = Enum.Font.GothamBlack })
	return p
end

-------------------------------------------------------------------------------
-- Помещения: пол, стены, потолки
-------------------------------------------------------------------------------
local PAINT = { I.PaintedWall, 12, rgb(236, 234, 226) }
local CONCRETE = { I.ConcreteWall, 10, rgb(205, 205, 200) }

local function buildShell(root, map)
	local f = folder("Building", root)
	-- Полы
	local sales = B(f, "FloorSales", -66, -1, -12, 40, 0, 50, C.FloorTile, M.SmoothPlastic, { Reflectance = 0.04 })
	skin(sales, I.FloorTile, 6, { N.Top })
	local wh = B(f, "FloorWarehouse", -66, -1, -64, -18, 0, -12, rgb(150, 150, 146), M.Concrete)
	skin(wh, I.ConcreteWall, 14, { N.Top }, rgb(170, 170, 166))
	local c1 = B(f, "FloorCorridor", -18, -1, -64, -10, 0, -12, rgb(150, 156, 148), M.SmoothPlastic, { Reflectance = 0.02 })
	skin(c1, I.FloorTile, 5, { N.Top }, rgb(170, 178, 168))
	local c2 = B(f, "FloorCorridor2", -10, -1, -40, 40, 0, -34, rgb(150, 156, 148), M.SmoothPlastic, { Reflectance = 0.02 })
	skin(c2, I.FloorTile, 5, { N.Top }, rgb(170, 178, 168))
	B(f, "FloorSecurity", -10, -1, -34, 12, 0, -12, rgb(84, 86, 92), M.Carpet)
	B(f, "FloorStaff", 12, -1, -34, 40, 0, -12, rgb(170, 150, 120), M.WoodPlanks)
	B(f, "FloorCold", -10, -1, -64, 12, 0, -40, rgb(176, 180, 186), M.DiamondPlate)
	B(f, "FloorOffice", 12, -1, -64, 40, 0, -40, rgb(64, 70, 88), M.Carpet)

	-- Наружные стены
	local ext = rgb(150, 150, 146)
	local extLook = { I.ConcreteWall, 12, rgb(150, 150, 150) }
	wallZ(f, "WallWest", -66.5, -65, 51, 0, 17, { { -38, -26, 10 } }, ext, M.Concrete, 1, extLook)
	wallZ(f, "WallEast", 40.5, -65, 51, 0, 17, {}, ext, M.Concrete, 1, extLook)
	wallX(f, "WallBack", -64.5, -67, 41, 0, 17, { { -16, -12, 8.5 } }, ext, M.Concrete, 1, extLook)
	-- Внутренняя отделка торгового зала (крашеная штукатурка и тёмный цоколь)
	skin(B(f, "SalesWallW", -66, 0, -12, -65.6, 16, 50, C.Wall, M.Plaster), PAINT[1], PAINT[2], { N.Right }, PAINT[3])
	skin(B(f, "SalesWallE", 39.6, 0, -12, 40, 16, 50, C.Wall, M.Plaster), PAINT[1], PAINT[2], { N.Left }, PAINT[3])
	B(f, "KickW", -65.7, 0, -12, -65.5, 0.8, 50, C.Kick, M.SmoothPlastic)
	B(f, "KickE", 39.5, 0, -12, 39.7, 0.8, 50, C.Kick, M.SmoothPlastic)
	-- Ворота склада для фур (закрыты)
	B(f, "LoadingDoor", -66.6, 0, -38, -66.2, 10, -26, rgb(120, 126, 132), M.DiamondPlate)
	B(f, "LoadingDoorStripe", -66.2, 0, -38, -66.0, 0.6, -26, C.Price, M.SmoothPlastic)

	-- Стена между залом и подсобкой (z = -12): двери склада и служебного помещения
	wallX(f, "WallBackSales", -12, -66, 40, 0, 16, { { -46, -38, 9 }, { -16, -12, 8.5 } }, C.Wall, M.Plaster, 1, PAINT)
	-- Подсобка: бетонные стены
	wallZ(f, "WallWarehouseE", -18, -64, -12, 0, 16, { { -42, -38, 8.5 } }, C.WallBack, M.Concrete, 0.6, CONCRETE)
	wallZ(f, "WallCorridorE", -10, -64, -12, 0, 16, { { -40, -34, 10 } }, C.WallBack, M.Plaster, 0.6, CONCRETE)
	wallX(f, "WallC2North", -34, -10, 40, 0, 16, { { -1, 3, 8.5 }, { 24, 28, 8.5 } }, C.WallBack, M.Plaster, 0.6, CONCRETE)
	wallX(f, "WallC2South", -40, -10, 40, 0, 16, { { -1.5, 3, 8.5 }, { 24, 28, 8.5 } }, C.WallBack, M.Plaster, 0.6, CONCRETE)
	wallZ(f, "WallSecStaff", 12, -34, -12, 0, 16, {}, C.WallBack, M.Plaster, 0.6, PAINT)
	wallZ(f, "WallColdOffice", 12, -64, -40, 0, 16, {}, C.WallBack, M.Plaster, 0.6, PAINT)

	-- Потолки: подвесные плиты в зале, простые плиты в подсобке
	local ceil = B(f, "CeilingSales", -66, 15, -12, 40, 15.4, 50, C.Ceiling, M.SmoothPlastic)
	skin(ceil, I.CeilingPanels, 16, { N.Bottom })
	for _, r in ipairs({ { -18, -10, -64, -12 }, { -10, 40, -40, -34 }, { -10, 12, -34, -12 }, { 12, 40, -34, -12 }, { -10, 12, -64, -40 }, { 12, 40, -64, -40 } }) do
		local c = B(f, "CeilingBack", r[1], 10, r[3], r[2], 10.4, r[4], rgb(214, 214, 208), M.SmoothPlastic)
		skin(c, I.CeilingPanels, 16, { N.Bottom }, rgb(200, 200, 194))
	end
	B(f, "Roof", -67, 17, -65, 41, 18, 51, rgb(60, 60, 62), M.Concrete)
	-- Перекрытие над складом с балками
	for z = -60, -16, 11 do
		B(f, "Beam", -66, 14.6, z - 0.4, -18, 15.4, z + 0.4, rgb(90, 96, 104), M.Metal)
	end

	-- Вентиляционные решётки (у клиента — шум вентиляции)
	for _, v in ipairs({ { -60, 9.9, -30 }, { -30, 9.9, -50 }, { -14, 9.9, -26 }, { 20, 9.9, -37 }, { 0, 9.9, -22 }, { 30, 9.9, -52 }, { 0, 14.9, 20 } }) do
		local grille = P(f, "Vent", Vector3.new(2.4, 0.1, 2.4), CFrame.new(v[1], v[2], v[3]), rgb(170, 172, 170), M.DiamondPlate)
		tag(grille, "AmbVent")
	end
	-- Динамики громкой связи
	for _, x in ipairs({ -50, -20, 10, 32 }) do
		for _, z in ipairs({ 4, 32 }) do
			Cyl(f, "Speaker", 1.4, 0.15, Vector3.new(x, 14.9, z), rgb(240, 240, 236), M.SmoothPlastic)
		end
	end

	-- Комнаты (для проверок «где игрок»)
	map.Rooms = {
		{ Name = "Торговый зал", Min = Vector3.new(-66, -2, -12), Max = Vector3.new(40, 20, 50) },
		{ Name = "Склад", Min = Vector3.new(-66, -2, -64), Max = Vector3.new(-18, 20, -12) },
		{ Name = "Служебный коридор", Min = Vector3.new(-18, -2, -64), Max = Vector3.new(-10, 20, -12) },
		{ Name = "Коридор", Min = Vector3.new(-10, -2, -40), Max = Vector3.new(40, 20, -34) },
		{ Name = "Охрана", Min = Vector3.new(-10, -2, -34), Max = Vector3.new(12, 20, -12) },
		{ Name = "Комната персонала", Min = Vector3.new(12, -2, -34), Max = Vector3.new(40, 20, -12) },
		{ Name = "Холодильная камера", Min = Vector3.new(-10, -2, -64), Max = Vector3.new(12, 20, -40) },
		{ Name = "Кабинет менеджера", Min = Vector3.new(12, -2, -64), Max = Vector3.new(40, 20, -40) },
		{ Name = "Задний двор", Min = Vector3.new(-40, -2, -92), Max = Vector3.new(10, 30, -64) },
		{ Name = "Парковка", Min = Vector3.new(-90, -2, 50), Max = Vector3.new(70, 30, 132) },
	}
end

-------------------------------------------------------------------------------
-- Витрина, автоматические двери, улица под дождём
-------------------------------------------------------------------------------
local function car(parent, x, z, color, rot, name)
	local m = model(name or "Car", parent)
	local cf = CFrame.new(x, 0, z) * CFrame.Angles(0, math.rad(rot), 0)
	local body = P(m, "Body", Vector3.new(6, 1.8, 13), cf * CFrame.new(0, 1.6, 0), color, M.SmoothPlastic, { Reflectance = 0.12 })
	P(m, "Hood", Vector3.new(5.8, 0.4, 4), cf * CFrame.new(0, 2.6, -4.3), color, M.SmoothPlastic, { Reflectance = 0.12 })
	P(m, "Trunk", Vector3.new(5.8, 0.4, 2.6), cf * CFrame.new(0, 2.6, 5.1), color, M.SmoothPlastic, { Reflectance = 0.12 })
	P(m, "Cabin", Vector3.new(5.4, 1.9, 6.2), cf * CFrame.new(0, 3.45, 0.6), rgb(22, 26, 32), M.Glass, { Transparency = 0.15, Reflectance = 0.2 })
	P(m, "Roof", Vector3.new(5.5, 0.2, 5.2), cf * CFrame.new(0, 4.45, 0.8), color, M.SmoothPlastic, { Reflectance = 0.12 })
	for _, w in ipairs({ { -2.85, -4.1 }, { 2.85, -4.1 }, { -2.85, 4.1 }, { 2.85, 4.1 } }) do
		local wheel = P(m, "Wheel", Vector3.new(0.9, 2.3, 2.3), cf * CFrame.new(w[1], 1.15, w[2]), rgb(16, 16, 16), M.Rubber)
		wheel.Shape = Enum.PartType.Cylinder
		local hub = P(m, "Hub", Vector3.new(0.95, 1.2, 1.2), cf * CFrame.new(w[1], 1.15, w[2]), rgb(150, 150, 154), M.Metal)
		hub.Shape = Enum.PartType.Cylinder
	end
	P(m, "HeadL", Vector3.new(1.3, 0.5, 0.12), cf * CFrame.new(-2.1, 2.1, -6.5), rgb(235, 235, 220), M.Glass)
	P(m, "HeadR", Vector3.new(1.3, 0.5, 0.12), cf * CFrame.new(2.1, 2.1, -6.5), rgb(235, 235, 220), M.Glass)
	P(m, "TailL", Vector3.new(1.3, 0.45, 0.12), cf * CFrame.new(-2.1, 2.1, 6.5), rgb(120, 10, 10), M.Glass)
	P(m, "TailR", Vector3.new(1.3, 0.45, 0.12), cf * CFrame.new(2.1, 2.1, 6.5), rgb(120, 10, 10), M.Glass)
	m.PrimaryPart = body
	return m
end

-- Детализированная машина (модель с текстурами). heading — куда смотрит перёд: 0 = к магазину (-Z).
-- Перёд модели определяем по фарам; поворот для этого сохраняем в атрибуте YawFix (нужен кат-сцене).
-- Детали помечены атрибутом Role: Headlight / Taillight / Window / Wheel / WheelFront — по ним кат-сцена
-- включает фары и стоп-сигналы и крутит колёса. Столкновения — один невидимый блок по размеру кузова.
local LIGHT_ROLES = {
	{ "Headlights", "Headlight" },
	{ "Taillights", "Taillight" },
	{ "Brakelights", "Taillight" },
	{ "Reverse", "Reverse" },
	{ "Blinkers", "Blinker" },
}
local function carRole(name)
	for _, r in ipairs(LIGHT_ROLES) do
		if string.find(name, r[1], 1, true) then
			return r[2]
		end
	end
	if string.find(name, "Wheel%a*_F[LR]") then
		return "WheelFront"
	elseif string.find(name, "Wheel%a*_R[LR]") then
		return "Wheel"
	end
	local low = string.lower(name)
	if string.find(low, "glass", 1, true) or string.find(low, "windshield", 1, true) then
		return "Window"
	end
	return nil
end

local function carModel(parent, assetName, x, z, heading, name)
	local def = Models.Assets[assetName]
	local m = ModelKit.MakeAsset(assetName, parent, CFrame.new(x, 0, z), def.Scale)
	if not m then
		return nil
	end
	m.Name = name or "Car"
	local pivot = m:GetPivot()
	local fwd = -1
	local body, bodyVolume = nil, 0
	for _, p in ipairs(m:GetDescendants()) do
		if p:IsA("BasePart") then
			p.CanCollide = false
			p.CanQuery = false
			local role = carRole(p.Name)
			if role then
				p:SetAttribute("Role", role)
			end
			if role == "Headlight" then
				-- перёд — в той стороне по оси X модели, где фары
				fwd = (pivot:PointToObjectSpace(p.Position).X > 0) and 1 or -1
			elseif role == "Window" then
				-- тонированное стекло: видно салон и отражения
				p.Material = Enum.Material.Glass
				p.Transparency = 0.42
				p.Reflectance = 0.14
				p.CastShadow = false
			end
			local v = p.Size.X * p.Size.Y * p.Size.Z
			if string.find(string.lower(p.Name), "body", 1, true) and not role and v > bodyVolume then
				body, bodyVolume = p, v
			end
		end
	end
	-- блок столкновений по размеру машины (без окон и колёс)
	local _, size = m:GetBoundingBox()
	local hit = Instance.new("Part")
	hit.Name = "Collision"
	hit.Size = Vector3.new(size.X * 0.96, size.Y * 0.62, size.Z * 0.94)
	hit.CFrame = pivot * CFrame.new(0, size.Y * 0.36, 0)
	hit.Transparency = 1
	hit.Anchored = true
	hit.CanTouch = false
	hit.CastShadow = false
	hit.Parent = m
	local yawFix = (fwd < 0) and math.rad(-90) or math.rad(90)
	m:SetAttribute("YawFix", yawFix)
	m:SetAttribute("Length", size.X)
	m:SetAttribute("Width", size.Z)
	local placed = CFrame.new(x, 0, z) * CFrame.Angles(0, math.rad(heading or 0), 0) * CFrame.Angles(0, yawFix, 0)
	m:PivotTo(placed)
	-- главная деталь — кузов; опора модели остаётся в центре низа
	if body then
		body.PivotOffset = body.CFrame:ToObjectSpace(placed)
		m.PrimaryPart = body
	end
	return m
end

local function building(parent, x0, z0, x1, z1, h, seed)
	local r = Random.new(seed)
	local m = model("Building", parent)
	local color = rgb(r:NextInteger(46, 62), r:NextInteger(46, 60), r:NextInteger(50, 66))
	local body = B(m, "Block", x0, 0, z0, x1, h, z1, color, M.Concrete)
	skin(body, I.ConcreteWall, 16, { N.Front, N.Back, N.Left, N.Right }, rgb(120, 120, 124))
	-- редкие светящиеся окна (кто-то не спит)
	local faces = { { N.Front, z0 - 0.05 }, { N.Back, z1 + 0.05 } }
	for _, fc in ipairs(faces) do
		for fl = 1, math.floor(h / 9) - 1 do
			for x = x0 + 5, x1 - 5, 7 do
				if r:NextNumber() < 0.12 then
					local warm = r:NextNumber() < 0.7
					B(m, "Window", x - 1.4, fl * 9, fc[2] - 0.05, x + 1.4, fl * 9 + 3.2, fc[2] + 0.05, warm and rgb(255, 214, 150) or rgb(170, 200, 255), M.Neon, { CastShadow = false })
				end
			end
		end
	end
	return m
end

local function buildFront(root, map)
	local f = folder("Front", root)
	local frame = rgb(70, 74, 80)
	-- Цоколь витрины (с разрывом под двери) и верхняя полоса фасада
	B(f, "FacadeBase", -66, 0, 49.6, -58.4, 0.8, 50.6, frame, M.Metal)
	B(f, "FacadeBase", -45.6, 0, 49.6, 40, 0.8, 50.6, frame, M.Metal)
	B(f, "Threshold", -58.4, -1, 49.6, -45.6, 0.15, 50.6, rgb(120, 120, 124), M.DiamondPlate)
	local top = B(f, "FacadeTop", -66, 11, 49.6, 40, 17, 50.6, rgb(236, 236, 232), M.Plaster)
	skin(top, I.PaintedWall, 10, { N.Back }, rgb(230, 230, 226))
	B(f, "FacadeStripe", -66, 11, 50.6, 40, 12, 50.8, C.Red, M.SmoothPlastic)
	-- Стёкла витрины с импостами (кроме проёма дверей x -58..-46)
	local function glassRun(x0, x1)
		B(f, "ShopWindow", x0, 0.8, 49.95, x1, 11, 50.25, rgb(170, 200, 210), M.Glass, { Transparency = 0.78, Reflectance = 0.18, CastShadow = false })
		for x = x0, x1, 6 do
			B(f, "Mullion", x - 0.2, 0.8, 49.8, x + 0.2, 11, 50.4, frame, M.Metal)
		end
	end
	glassRun(-66, -58)
	glassRun(-46, 40)
	-- Плакаты на стекле
	for i, x in ipairs({ -40, -16, 14 }) do
		local poster = P(f, "Poster", Vector3.new(3.4, 4.4, 0.05), CFrame.new(x, 6.5, 50.32), Color3.new(1, 1, 1), M.SmoothPlastic, { Transparency = 1 })
		local texts = { "НОЧНАЯ СКИДКА\n−20%\n00:00–06:00", "МОЛОКО «УТРО»\n89 ₽", "MART 24\nМы работаем\nдля вас\nкруглосуточно" }
		sign(poster, N.Back, texts[i], { color = Color3.new(1, 1, 1), ppS = 40, bg = (i == 1) and C.Red or rgb(30, 90, 170), padding = 10 })
	end
	-- Рама дверного проёма и датчик
	B(f, "DoorFrameL", -58.4, 0, 49.6, -58, 11, 50.6, frame, M.Metal)
	B(f, "DoorFrameR", -46, 0, 49.6, -45.6, 11, 50.6, frame, M.Metal)
	B(f, "DoorHeader", -58, 9, 49.6, -46, 11, 50.6, frame, M.Metal)
	P(f, "DoorSensor", Vector3.new(1.6, 0.4, 0.6), CFrame.new(-52, 8.7, 49.4), C.Black, M.SmoothPlastic)
	-- Раздвижные стеклянные створки
	local function slide(x0, x1)
		return B(f, "AutoDoor", x0, 0.05, 49.3, x1, 9, 49.6, rgb(170, 200, 210), M.Glass, { Transparency = 0.6, Reflectance = 0.15, CastShadow = false })
	end
	local left, right = slide(-58, -52), slide(-52, -46)
	map.AutoDoor = {
		Left = left,
		Right = right,
		LeftClosed = left.CFrame,
		RightClosed = right.CFrame,
		LeftOpen = left.CFrame * CFrame.new(-5.6, 0, 0),
		RightOpen = right.CFrame * CFrame.new(5.6, 0, 0),
		Center = Vector3.new(-52, 0, 50),
	}
	B(f, "EntranceMat", -58, 0, 44, -46, 0.06, 49.4, rgb(40, 40, 44), M.Fabric)
	-- Навес над входом
	B(f, "Canopy", -60, 11.6, 50.6, -44, 12.2, 56, rgb(200, 36, 40), M.SmoothPlastic)
	for _, x in ipairs({ -59.4, -44.6 }) do
		Cyl(f, "CanopyPole", 0.4, 11.6, Vector3.new(x, 5.8, 55.4), rgb(70, 74, 80), M.Metal)
	end
	local canopyLight = P(f, "CanopyLamp", Vector3.new(6, 0.12, 1.2), CFrame.new(-52, 11.5, 53.2), C.Lamp, M.Neon, { CastShadow = false })
	local cl = Instance.new("SurfaceLight")
	cl.Face = N.Bottom
	cl.Angle = 120
	cl.Range = 18
	cl.Brightness = 1.2
	cl.Color = C.Lamp
	cl.Parent = canopyLight
	canopyLight:SetAttribute("Zone", "Outside")
	canopyLight:SetAttribute("LampColor", C.Lamp)
	tag(canopyLight, "StoreLight")

	-- Вывеска MART 24 (светится и слегка мерцает — мерцание делает клиент)
	local signBox = B(f, "StoreSign", -66, 12.6, 50.8, -30, 17.6, 51.8, C.Red, M.SmoothPlastic)
	sign(signBox, N.Back, Texts.StoreName, { color = Color3.new(1, 1, 1), light = 0, brightness = 3, ppS = 20, font = Enum.Font.GothamBlack, maxDistance = 500 })
	local glow = Instance.new("SurfaceLight")
	glow.Name = "SignGlow"
	glow.Face = N.Back
	glow.Color = rgb(255, 80, 80)
	glow.Range = 24
	glow.Brightness = 1.4
	glow.Angle = 110
	glow.Parent = signBox
	tag(signBox, "StoreSign")
	tag(signBox, "AmbSign")
	local sub = B(f, "Sign24", -26, 13.2, 50.8, 6, 16.2, 51.4, rgb(30, 30, 34), M.SmoothPlastic)
	sign(sub, N.Back, "КРУГЛОСУТОЧНО · 24/7", { color = rgb(255, 214, 80), light = 0, brightness = 2.5, ppS = 20, maxDistance = 500 })
	tag(sub, "StoreSign")
	local hours = P(f, "Hours", Vector3.new(4, 2.6, 0.05), CFrame.new(-60, 6, 50.3), Color3.new(1, 1, 1), M.SmoothPlastic, { Transparency = 1 })
	sign(hours, N.Back, Texts.StoreName .. "\nПн–Вс 00:00–24:00\nМы никогда не закрываемся", { color = Color3.new(1, 1, 1), ppS = 50 })

	-- Тротуар, бордюр, парковка, дорога, тротуар напротив
	B(f, "Sidewalk", -160, -1, 50.6, 160, 0.3, 58, rgb(120, 120, 118), M.Concrete)
	B(f, "Curb", -160, -1, 58, 160, 0.35, 58.6, rgb(160, 160, 156), M.Concrete)
	B(f, "Parking", -160, -1.2, 58.6, 160, 0, 120, rgb(38, 38, 40), M.Asphalt)
	B(f, "Road", -260, -1.3, 120, 260, -0.05, 134, rgb(30, 30, 32), M.Asphalt)
	B(f, "FarCurb", -260, -1, 134, 260, 0.35, 134.6, rgb(160, 160, 156), M.Concrete)
	B(f, "FarSidewalk", -260, -1, 134.6, 260, 0.3, 146, rgb(116, 116, 114), M.Concrete)
	-- Мокрый асфальт: тонкий глянцевый слой ловит блики фонарей и вывески
	B(f, "WetSheen", -160, 0.01, 58.6, 160, 0.03, 120, rgb(20, 22, 26), M.Glass, { Transparency = 0.72, Reflectance = 0.25, CanCollide = false, CastShadow = false })
	B(f, "WetSheenRoad", -260, -0.04, 120, 260, -0.02, 134, rgb(20, 22, 26), M.Glass, { Transparency = 0.7, Reflectance = 0.28, CanCollide = false, CastShadow = false })
	for _, pd in ipairs({ { -44, 76, 7 }, { -20, 92, 5 }, { 6, 70, 6 }, { -60, 104, 8 }, { 30, 110, 6 }, { -80, 127, 9 }, { -30, 128, 7 }, { 40, 126, 8 } }) do
		local puddle = P(f, "Puddle", Vector3.new(0.05, pd[3], pd[3] * 1.5), CFrame.new(pd[1], 0.05, pd[2]) * CFrame.Angles(0, math.rad(rng:NextNumber(0, 180)), math.rad(90)), rgb(14, 16, 20), M.Glass, { Reflectance = 0.45, Transparency = 0.1, CanCollide = false })
		puddle.Shape = Enum.PartType.Cylinder
	end
	for x = -250, 250, 14 do
		B(f, "RoadLine", x, -0.04, 126.8, x + 7, -0.02, 127.2, rgb(220, 220, 210), M.SmoothPlastic)
	end
	local realCars = ModelKit.HasAsset(Models.StaffCar)
	for i = 0, 12 do
		local x = -78 + i * 11
		if realCars then
			-- места под настоящий размер машин (около 5 м)
			B(f, "ParkingLine", x - 0.15, 0, 60, x + 0.15, 0.04, 80, rgb(214, 214, 208), M.SmoothPlastic)
			B(f, "ParkingLine", x - 0.15, 0, 90, x + 0.15, 0.04, 110, rgb(214, 214, 208), M.SmoothPlastic)
		else
			B(f, "ParkingLine", x - 0.15, 0, 62, x + 0.15, 0.04, 74, rgb(214, 214, 208), M.SmoothPlastic)
			B(f, "ParkingLine", x - 0.15, 0, 92, x + 0.15, 0.04, 104, rgb(214, 214, 208), M.SmoothPlastic)
		end
	end
	-- Фонари парковки и вдоль дороги (натриевый свет)
	local function streetLamp(x, z, armDir, broken)
		Cyl(f, "LampPost", 0.6, 20, Vector3.new(x, 10, z), rgb(60, 62, 66), M.Metal)
		B(f, "LampArm", x - 0.3, 19.6, math.min(z, z + armDir * 3), x + 0.3, 20, math.max(z, z + armDir * 3), rgb(60, 62, 66), M.Metal)
		pendantLight(f, Vector3.new(x, 19.3, z + armDir * 3), "Outside", { color = C.Sodium, range = 48, angle = 120, brightness = 2.2, cable = 0.2, broken = broken, shadows = true })
	end
	streetLamp(-60, 84, 1, false)
	streetLamp(-10, 84, 1, false)
	streetLamp(40, 84, 1, true)
	for x = -200, 200, 50 do
		streetLamp(x, 136, -1, false)
	end
	-- Машины на парковке (большинство мест пустые) и машина сотрудника (на ней игрок приезжает в начале смены)
	if realCars then
		local parked = Models.ParkedCars
		carModel(f, parked[1], -72.5, 70, 0)
		carModel(f, parked[2], 15.5, 100, 180)
		carModel(f, parked[3], 48.5, 70, 0)
		carModel(f, parked[4], -6.5, 100, 180)
		map.StaffCar = carModel(f, Models.StaffCar, -39.5, 70, 0, "StaffCar")
		map.StaffCarSpot = Vector3.new(-39.5, 0, 70)
	else
		car(f, -78 + 5.5, 67, rgb(140, 30, 34), 0)
		car(f, 10 + 5.5, 98, rgb(54, 62, 80), 180)
		car(f, 48.5, 67, rgb(190, 190, 186), 0)
		map.StaffCar = car(f, -39.5, 68, rgb(72, 80, 66), 0, "StaffCar")
		map.StaffCarSpot = Vector3.new(-39.5, 0, 68)
	end
	local staff = map.StaffCar
	-- Тележки у входа
	for i = 0, 3 do
		local m = model("Cart", f)
		B(m, "Basket", -37.2 + i * 0.9, 1.6, 57.5 - 3, -35.6 + i * 0.9, 3.4, 60.5 - 3, rgb(170, 30, 30), M.Metal, { Transparency = 0.2 })
		P(m, "Frame", Vector3.new(0.2, 1.6, 3), CFrame.new(-36 + i * 0.9 - 0.8, 0.8, 56), rgb(180, 180, 184), M.Metal)
	end
	-- Тёмные дома вокруг (видны за магазином и по сторонам)
	local bf = folder("Buildings", f)
	building(bf, -150, -150, -90, -100, 60, 1)
	building(bf, -80, -170, -10, -110, 46, 2)
	building(bf, 0, -160, 70, -105, 72, 3)
	building(bf, 80, -140, 140, -80, 52, 4)
	building(bf, -170, -80, -110, -10, 40, 5)
	building(bf, 100, -60, 160, 20, 44, 6)
	building(bf, -200, 160, -120, 210, 50, 7)
	building(bf, -60, 160, 30, 200, 38, 8)
	building(bf, 60, 160, 150, 220, 64, 9)
	-- Деревья вдоль тротуара напротив
	for x = -180, 180, 36 do
		if math.abs(x + 18 + 52) > 14 then
		Cyl(f, "TreeTrunk", 0.8, 8, Vector3.new(x + 18, 4, 142), rgb(50, 40, 34), M.Wood)
		local crown = P(f, "TreeCrown", Vector3.new(9, 9, 9), CFrame.new(x + 18, 11, 142), rgb(28, 40, 30), M.Grass)
		crown.Shape = Enum.PartType.Ball
		end
	end
	-- Невидимые границы, чтобы не уйти в пустоту
	for _, w in ipairs({ { -91, -1, 50, -90, 40, 133 }, { 70, -1, 50, 71, 40, 133 }, { -91, -1, 132, 71, 40, 133 } }) do
		B(f, "Boundary", w[1], w[2], w[3], w[4], w[5], w[6], Color3.new(0, 0, 0), M.SmoothPlastic, { Transparency = 1 })
	end

	map.Points.CustomerSpawns = { Vector3.new(-70, 0, 100), Vector3.new(-30, 0, 110), Vector3.new(20, 0, 108), Vector3.new(-80, 0, 70) }
	map.Points.EntranceOutside = Vector3.new(-52, 0, 60)
	map.Points.EntranceInside = Vector3.new(-52, 0, 45)
end

-------------------------------------------------------------------------------
-- Стеллажи торгового зала
-------------------------------------------------------------------------------
local GONDOLA_X = { -50, -35, -20, -5, 10, 25 }
local GONDOLA_CATEGORY = { "Snacks", "Grocery", "Drinks", "Cans", "Household", "Grocery" }
local AISLE_X = { -57.5, -42.5, -27.5, -12.5, 2.5, 17.5, 32 }
local SHELF_Y = { 0.5, 2.0, 3.5, 5.0 }
local PRICES = { Snacks = { 99, 89, 79 }, Grocery = { 159, 349, 49 }, Drinks = { 75, 45, 119 }, Cans = { 89, 249 }, Household = { 139, 89, 199 } }

local function metalSkin(part, faces)
	skin(part, I.BrushedMetal, 4, faces, rgb(225, 228, 232))
end

-- Двусторонний стеллаж из моделей: 3 секции по 2 м, на торцах — пристенные стеллажи 1 м
local function gondolaModel(parent, index, cx, z0, z1, category, map)
	local m = model("Gondola" .. index, parent)
	local def = Models.Meshes.GondolaDouble2m
	local depth, height = def.Size.X * SS, def.Size.Y * SS
	local modules = 3
	local len = (z1 - z0) / modules
	for k = 0, modules - 1 do
		ModelKit.Make("GondolaDouble2m", m, CFrame.new(cx, height / 2, z0 + (k + 0.5) * len), Vector3.new(depth, height, len), { Name = "GondolaModule" })
	end
	local levels = Models.Levels.Gondola
	local prices = PRICES[category] or { 99 }
	for side = -1, 1, 2 do
		local face = side < 0 and N.Left or N.Right
		local inner, outer = cx + side * 0.2, cx + side * (depth / 2 - 0.05)
		local xa, xb = math.min(inner, outer), math.max(inner, outer)
		for level, ym in ipairs(levels) do
			local y = ym * SS + 0.02
			local top = levels[level + 1] and levels[level + 1] * SS or height
			for sec = 1, modules do
				local sz0 = z0 + (sec - 1) * len + 0.3
				local sz1 = z0 + sec * len - 0.3
				productLayer(m, xa, xb, y, sz0, sz1, face, category, map.Facings, {
					Gondola = index,
					Side = side,
					Level = level,
					Section = sec,
					Aisle = cx + side * 7.5,
					ZCenter = (sz0 + sz1) / 2,
					Label = string.format("Ряд %d, %s", index, Products.Categories[category].Name),
				}, top - y - 0.2)
				priceTag(m, Vector3.new(cx + side * (depth / 2 + 0.03), y - 0.14, (sz0 + sz1) / 2 + rng:NextNumber(-1.5, 1.5)), face, prices[rng:NextInteger(1, #prices)])
			end
		end
	end
	-- торцы: пристенный стеллаж 1 м лицом в поперечный проход (перед модели — локальная -X)
	local ed = Models.Meshes.WallShelf1m
	local eDepth, eHeight, eWidth = ed.Size.X * SS, ed.Size.Y * SS, ed.Size.Z * SS
	for _, e in ipairs({ { z0, -1, N.Front }, { z1, 1, N.Back } }) do
		local zc = e[1] + e[2] * eDepth / 2
		local rotY = e[2] < 0 and math.rad(-90) or math.rad(90)
		ModelKit.Make("WallShelf1m", m, CFrame.new(cx, eHeight / 2, zc) * CFrame.Angles(0, rotY, 0), Vector3.new(eDepth, eHeight, eWidth), { Name = "EndCap" })
		local front, back = e[1] + e[2] * (eDepth - 0.05), e[1] + e[2] * (eDepth * 0.16)
		for level, ym in ipairs(Models.Levels.WallShelf) do
			local y = ym * SS + 0.02
			local top = Models.Levels.WallShelf[level + 1] and Models.Levels.WallShelf[level + 1] * SS or eHeight
			productLayer(m, cx - eWidth / 2 + 0.2, cx + eWidth / 2 - 0.2, y, math.min(front, back), math.max(front, back), e[3], category, nil, nil, top - y - 0.2)
		end
		local za, zb = e[1] + e[2] * 0.25, e[1] + e[2] * 0.45
		local header = B(m, "PromoSign", cx - eWidth / 2, eHeight + 0.1, math.min(za, zb), cx + eWidth / 2, eHeight + 1.4, math.max(za, zb), C.Red, M.SmoothPlastic)
		sign(header, e[3], "АКЦИЯ −20%", { color = Color3.new(1, 1, 1), ppS = 30, font = Enum.Font.GothamBlack })
	end
end

local function gondola(parent, index, cx, z0, z1, category, map)
	if useModels({ "GondolaDouble2m", "WallShelf1m" }) then
		return gondolaModel(parent, index, cx, z0, z1, category, map)
	end
	local m = model("Gondola" .. index, parent)
	local len = z1 - z0
	B(m, "Base", cx - 2, 0, z0, cx + 2, 0.5, z1, C.Dark, M.SmoothPlastic)
	local back = B(m, "BackPanel", cx - 0.15, 0.5, z0, cx + 0.15, 7, z1, C.Metal, M.Metal)
	metalSkin(back, { N.Left, N.Right })
	B(m, "TopRail", cx - 0.5, 7, z0, cx + 0.5, 7.25, z1, C.Metal, M.Metal)
	for _, z in ipairs({ z0, z0 + len / 2, z1 }) do
		B(m, "Upright", cx - 0.35, 0.5, z - 0.15, cx + 0.35, 7, z + 0.15, C.Dark, M.Metal)
	end
	for side = -1, 1, 2 do
		local inner, outer = cx + side * 0.15, cx + side * 2
		local xa, xb = math.min(inner, outer), math.max(inner, outer)
		local face = side < 0 and N.Left or N.Right
		for level, y in ipairs(SHELF_Y) do
			if level > 1 then
				local shelf = B(m, "Shelf", xa, y - 0.12, z0 + 0.15, xb, y, z1 - 0.15, C.Metal, M.Metal)
				skin(shelf, I.StainlessSteel, 3, { N.Top })
			end
			-- кромка с ценниками
			local px = outer + side * 0.04
			B(m, "PriceStrip", px - 0.04, y - 0.34, z0 + 0.15, px + 0.04, y - 0.02, z1 - 0.15, C.Price, M.SmoothPlastic)
			for s = 1, 2 do
				local sz0 = z0 + (s - 1) * len / 2 + 0.3
				local sz1 = z0 + s * len / 2 - 0.3
				local fx0, fx1
				if side < 0 then
					fx0, fx1 = outer + 0.1, inner - 0.05
				else
					fx0, fx1 = inner + 0.05, outer - 0.1
				end
				productLayer(m, fx0, fx1, y, sz0, sz1, face, category, map.Facings, {
					Gondola = index,
					Side = side,
					Level = level,
					Section = s,
					Aisle = cx + side * 7.5,
					ZCenter = (sz0 + sz1) / 2,
					Label = string.format("Ряд %d, %s", index, Products.Categories[category].Name),
				})
				local prices = PRICES[category] or { 99 }
				priceTag(m, Vector3.new(px + side * 0.06, y - 0.18, (sz0 + sz1) / 2 + rng:NextNumber(-2, 2)), face, prices[rng:NextInteger(1, #prices)])
			end
		end
	end
	-- Торцевые стеллажи с акцией
	for _, e in ipairs({ { z0 - 1.6, z0, N.Front }, { z1, z1 + 1.6, N.Back } }) do
		B(m, "EndCap", cx - 2, 0, e[1], cx + 2, 0.5, e[2], C.Dark, M.SmoothPlastic)
		local endBack = B(m, "EndCapBack", cx - 2, 0.5, math.min(e[1], e[2]) + (e[3] == N.Front and 1.45 or 0), cx + 2, 6, math.min(e[1], e[2]) + (e[3] == N.Front and 1.6 or 0.15), C.Metal, M.Metal)
		metalSkin(endBack, { e[3] })
		for _, y in ipairs({ 0.5, 2.3, 4.1 }) do
			if y > 0.5 then
				B(m, "EndShelf", cx - 2, y - 0.1, e[1], cx + 2, y, e[2], C.Metal, M.Metal)
			end
			productLayer(m, cx - 1.9, cx + 1.9, y, e[1] + 0.15, e[2] - 0.15, e[3], category, nil, nil)
		end
		local header = B(m, "PromoSign", cx - 2, 6, e[1] + 0.6, cx + 2, 7.4, e[1] + 0.8, C.Red, M.SmoothPlastic)
		sign(header, e[3], "АКЦИЯ −20%", { color = Color3.new(1, 1, 1), ppS = 30, font = Enum.Font.GothamBlack })
	end
end

local function buildSalesFloor(root, map)
	local f = folder("SalesFloor", root)
	map.Facings = {}
	for i, x in ipairs(GONDOLA_X) do
		gondola(f, i, x, 0, 20, GONDOLA_CATEGORY[i], map)
	end
	-- Номера рядов над проходами
	local aisleNames = {
		"Хлеб · Снеки",
		"Снеки · Бакалея",
		"Бакалея · Напитки",
		"Напитки · Консервы",
		"Консервы · Хозтовары",
		"Хозтовары · Чай, кофе",
		"Чай, кофе · Напитки",
	}
	for i, x in ipairs(AISLE_X) do
		Cyl(f, "SignWire", 0.05, 2.4, Vector3.new(x - 2.5, 13.8, 10), C.Black, M.SmoothPlastic)
		Cyl(f, "SignWire", 0.05, 2.4, Vector3.new(x + 2.5, 13.8, 10), C.Black, M.SmoothPlastic)
		local board = B(f, "AisleSign", x - 3.2, 11, 9.9, x + 3.2, 12.6, 10.1, rgb(30, 110, 60), M.SmoothPlastic)
		local text = tostring(i) .. "  " .. aisleNames[i]
		sign(board, N.Front, text, { color = Color3.new(1, 1, 1), ppS = 30, padding = 6 })
		sign(board, N.Back, text, { color = Color3.new(1, 1, 1), ppS = 30, padding = 6 })
	end

	-- Хлеб: пристенный стеллаж слева, буханки и батоны
	local bread = model("BreadWall", f)
	-- Ряд батонов и буханок на полке (x от xa до xb, z от za до zb)
	local function loaves(xa, xb, y, za, zb)
		local z = za
		while z < zb - 1 do
			local long = rng:NextNumber() < 0.6
			local w = long and 1.5 or 1.1
			local loaf = P(bread, "Loaf", Vector3.new(long and 0.9 or 1.0, long and 0.55 or 0.75, w), CFrame.new((xa + xb) / 2 + rng:NextNumber(-0.2, 0.2), y + (long and 0.28 or 0.38), z + w / 2) * CFrame.Angles(0, math.rad(rng:NextNumber(-8, 8)), 0), long and rgb(206, 150, 82) or rgb(150, 98, 56), M.SmoothPlastic, { CastShadow = false })
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.Sphere
			mesh.Parent = loaf
			z = z + w + 0.12
		end
	end
	if useModels({ "WallShelf2m" }) then
		-- пристенные стеллажи 2 м (перед модели — локальная -X, разворачиваем лицом в зал)
		local def = Models.Meshes.WallShelf2m
		local d, h, w = def.Size.X * SS, def.Size.Y * SS, def.Size.Z * SS
		for k = 0, 3 do
			ModelKit.Make("WallShelf2m", bread, CFrame.new(-65.5 + d / 2, h / 2, -6 + w / 2 + k * w) * CFrame.Angles(0, math.pi, 0), Vector3.new(d, h, w), { Name = "BreadShelf" })
		end
		for _, ym in ipairs(Models.Levels.WallShelf) do
			loaves(-65.5 + d * 0.2, -65.5 + d - 0.1, ym * SS + 0.02, -5.6, -6 + 4 * w - 0.3)
		end
	else
		local back = B(bread, "Back", -65.5, 0, -6, -65.2, 8, 24, C.Metal, M.Metal)
		metalSkin(back, { N.Right })
		for level, y in ipairs({ 0.6, 2.4, 4.2, 6.0 }) do
			B(bread, "Shelf", -65.2, y - 0.12, -6, -62.6, y, 24, rgb(150, 110, 70), M.Wood)
			B(bread, "PriceStrip", -62.66, y - 0.34, -6, -62.56, y - 0.02, 24, C.Price, M.SmoothPlastic)
			if level == 1 then
				B(bread, "Base", -65.2, 0, -6, -62.6, 0.6, 24, C.Dark, M.SmoothPlastic)
			end
			local z = -5.4
			while z < 23 do
				local long = rng:NextNumber() < 0.6
				local w = long and 1.5 or 1.1
				local loaf = P(bread, "Loaf", Vector3.new(long and 0.9 or 1.0, long and 0.55 or 0.75, w), CFrame.new(-64.0 + rng:NextNumber(-0.2, 0.2), y + (long and 0.28 or 0.38), z + w / 2) * CFrame.Angles(0, math.rad(rng:NextNumber(-8, 8)), 0), long and rgb(206, 150, 82) or rgb(150, 98, 56), M.SmoothPlastic, { CastShadow = false })
				local mesh = Instance.new("SpecialMesh")
				mesh.MeshType = Enum.MeshType.Sphere
				mesh.Parent = loaf
				z = z + w + 0.12
			end
		end
	end
	local breadSign = B(bread, "Header", -65.4, 8.4, -2, -65.2, 10, 20, rgb(170, 110, 50), M.SmoothPlastic)
	sign(breadSign, N.Right, "ХЛЕБ И ВЫПЕЧКА", { color = Color3.new(1, 1, 1), ppS = 30 })

	-- Напитки: пристенный стеллаж справа
	local drinks = model("DrinksWall", f)
	if useModels({ "DrinkCooler2", "CoolerDoor2" }) then
		-- шкафы-холодильники со стеклянными дверями вдоль восточной стены (перед модели — локальная -X)
		local def = Models.Meshes.DrinkCooler2
		local d, h, w = 2.6, def.Size.Y * SS, def.Size.Z * SS
		local x1 = 39.5
		local n = math.floor(46 / w)
		local zStart = -6 + (46 - n * w) / 2
		local door = Models.Meshes.CoolerDoor2
		local dh, dw = door.Size.Y * SS, door.Size.Z * SS
		for k = 0, n - 1 do
			local zc = zStart + (k + 0.5) * w
			ModelKit.Make("DrinkCooler2", drinks, CFrame.new(x1 - d / 2, h / 2, zc), Vector3.new(d, h, w), { Name = "DrinkCooler" })
			local frontX = x1 - d
			ModelKit.Make("CoolerDoor2", drinks, CFrame.new(frontX - 0.12, 1.1 * SS, zc), Vector3.new(0.22, dh, dw), { Name = "CoolerDoorFrame", CanCollide = false })
			P(drinks, "CoolerGlass", Vector3.new(0.06, dh - 0.3, dw - 0.3), CFrame.new(frontX - 0.12, 1.1 * SS, zc), rgb(190, 215, 230), M.Glass, { Transparency = 0.72, Reflectance = 0.18, CastShadow = false })
			B(drinks, "CoolerHandle", frontX - 0.32, 2.6, zc - 0.15, frontX - 0.22, 5.4, zc + 0.15, rgb(180, 182, 186), M.Metal)
			-- холодная подсветка внутри
			local strip = B(drinks, "CoolerLamp", frontX + 0.3, 1.84 * SS - 0.25, zc - w / 2 + 0.4, frontX + 0.5, 1.84 * SS - 0.15, zc + w / 2 - 0.4, C.LampCold, M.Neon, { CastShadow = false })
			local sl = Instance.new("SurfaceLight")
			sl.Face = N.Bottom
			sl.Angle = 150
			sl.Range = 8
			sl.Brightness = 1.2
			sl.Color = C.LampCold
			sl.Parent = strip
			strip:SetAttribute("Zone", "Drinks")
			strip:SetAttribute("LampColor", C.LampCold)
			tag(strip, "StoreLight")
			local levels = Models.Levels.DrinkCooler
			for level, ym in ipairs(levels) do
				local y = ym * SS + 0.02
				local top = levels[level + 1] and levels[level + 1] * SS or 1.84 * SS
				productLayer(drinks, frontX + d * 0.22, x1 - 0.25, y, zc - w / 2 + 0.35, zc + w / 2 - 0.35, N.Left, "Drinks", nil, nil, top - y - 0.15)
			end
		end
	else
		local dback = B(drinks, "Back", 39.2, 0, -6, 39.5, 8, 40, C.Metal, M.Metal)
		metalSkin(dback, { N.Left })
		for level, y in ipairs({ 0.6, 2.4, 4.2, 6.0 }) do
			local shelf = B(drinks, "Shelf", 36.6, y - 0.12, -6, 39.2, y, 40, C.Metal, M.Metal)
			skin(shelf, I.StainlessSteel, 3, { N.Top })
			B(drinks, "PriceStrip", 36.56, y - 0.34, -6, 36.66, y - 0.02, 40, C.Price, M.SmoothPlastic)
			if level == 1 then
				B(drinks, "Base", 36.6, 0, -6, 39.2, 0.6, 40, C.Dark, M.SmoothPlastic)
			end
			for sec = 0, 4 do
				local z0 = -5.8 + sec * 9.1
				productLayer(drinks, 36.8, 39.1, y, z0, z0 + 8.9, N.Left, "Drinks", nil, nil)
			end
		end
	end
	local drinksSign = B(drinks, "Header", 39.2, 8.4, 4, 39.4, 10, 30, rgb(30, 90, 170), M.SmoothPlastic)
	sign(drinksSign, N.Left, "НАПИТКИ", { color = Color3.new(1, 1, 1), ppS = 30 })

	-- Овощи и фрукты: наклонные ящики у входа с яблоками и апельсинами
	local produce = model("Produce", f)
	local fruitColors = { rgb(196, 30, 40), rgb(240, 140, 20), rgb(214, 190, 110), rgb(70, 150, 40) }
	for i = 0, 3 do
		local z = 27 + i * 4
		local crate = P(produce, "Crate", Vector3.new(3.6, 1.2, 3.6), CFrame.new(-60.8, 2.2, z + 1.8) * CFrame.Angles(0, 0, math.rad(-18)), rgb(120, 86, 50), M.Wood)
		tex(crate, N.Top, I.ProduceTop, 3.6, 3.6, i * 1.8)
		for k = 1, 7 do
			local ball = P(produce, "Fruit", Vector3.new(0.55, 0.55, 0.55), crate.CFrame * CFrame.new(rng:NextNumber(-1.4, 1.4), 0.75, rng:NextNumber(-1.4, 1.4)), fruitColors[i + 1], M.SmoothPlastic, { CastShadow = false })
			ball.Shape = Enum.PartType.Ball
		end
		B(produce, "Stand", -63, 0, z, -58.6, 1.6, z + 3.6, rgb(90, 66, 40), M.Wood)
	end
	local prodSign = B(produce, "Header", -65.4, 8.4, 28, -65.2, 10, 42, rgb(60, 140, 50), M.SmoothPlastic)
	sign(prodSign, N.Right, "ОВОЩИ И ФРУКТЫ", { color = Color3.new(1, 1, 1), ppS = 30 })

	-- Морозильные лари у задней стены: коробки заморозки лежат под стеклом
	map.Freezers = {}
	for _, x0 in ipairs({ -62, -34 }) do
		local fz = model("ChestFreezer", f)
		local body = B(fz, "Body", x0, 0, -11.5, x0 + 12, 2.2, -8.3, rgb(236, 238, 240), M.SmoothPlastic)
		-- бортик ларя (рамка, внутри видны коробки)
		B(fz, "Rim", x0, 2.2, -11.5, x0 + 12, 3, -11.35, rgb(236, 238, 240), M.SmoothPlastic)
		B(fz, "Rim", x0, 2.2, -8.45, x0 + 12, 3, -8.3, rgb(236, 238, 240), M.SmoothPlastic)
		B(fz, "Rim", x0, 2.2, -11.35, x0 + 0.15, 3, -8.45, rgb(236, 238, 240), M.SmoothPlastic)
		B(fz, "Rim", x0 + 11.85, 2.2, -11.35, x0 + 12, 3, -8.45, rgb(236, 238, 240), M.SmoothPlastic)
		for gx = 0, 10 do
			for gz = 0, 2 do
				local box = P(fz, "Frozen", Vector3.new(0.92, 0.24, 0.92), CFrame.new(x0 + 0.6 + gx * 1.05, 2.35, -11.0 + gz * 1.0) * CFrame.Angles(0, math.rad(rng:NextNumber(-10, 10)), 0), Color3.new(1, 1, 1), M.SmoothPlastic, { CastShadow = false })
				decal(box, N.Top, I.LabelFrozen)
			end
		end
		B(fz, "Glass", x0 + 0.2, 3, -11.3, x0 + 11.8, 3.12, -8.5, rgb(190, 220, 235), M.Glass, { Transparency = 0.6, CastShadow = false })
		B(fz, "Bumper", x0, 0.2, -8.35, x0 + 12, 0.8, -8.2, rgb(60, 140, 200), M.SmoothPlastic)
		tag(body, "AmbFridge")
		table.insert(map.Freezers, body)
	end
	-- Таблички над служебными дверями
	local staffOnly = B(f, "StaffOnlySign", -45, 9.4, -11.4, -39, 10.6, -11.3, rgb(240, 240, 236), M.SmoothPlastic)
	sign(staffOnly, N.Back, "СКЛАД · ТОЛЬКО ДЛЯ ПЕРСОНАЛА", { color = C.Red, ppS = 40 })
	local serviceSign = B(f, "ServiceSign", -16.5, 8.8, -11.4, -11.5, 9.8, -11.3, rgb(240, 240, 236), M.SmoothPlastic)
	sign(serviceSign, N.Back, "СЛУЖЕБНОЕ ПОМЕЩЕНИЕ", { color = C.Red, ppS = 40 })

	-- Свет зала: линии светильников над проходами и ряды у касс
	map.SalesLights = {}
	for i, x in ipairs(AISLE_X) do
		for j, z in ipairs({ 3, 10, 17 }) do
			local lamp = ceilingLight(f, Vector3.new(x, 14.7, z), 6, false, "Floor", { shadows = (j == 2 and i % 2 == 1) })
			if j == 2 and (i == 2 or i == 6) then
				tag(lamp, "AmbFluor")
			end
			table.insert(map.SalesLights, lamp)
		end
	end
	for _, x in ipairs({ -55, -40, -25, -10, 5, 20, 33 }) do
		ceilingLight(f, Vector3.new(x, 14.7, -5), 6, true, "Floor", {})
		ceilingLight(f, Vector3.new(x, 14.7, 25), 6, true, "Floor", { shadows = (x == -25 or x == 20) })
		ceilingLight(f, Vector3.new(x, 14.7, 35), 6, true, "Floor", {})
		ceilingLight(f, Vector3.new(x, 14.7, 45), 6, true, "Floor", { shadows = (x == -55) })
	end
	exitSign(f, Vector3.new(-52, 10, 49.3), Vector3.new(0, 0, -1))
end

-------------------------------------------------------------------------------
-- Холодильники вдоль задней стены
-------------------------------------------------------------------------------
local function buildFridges(root, map)
	local f = folder("Fridges", root)
	map.Fridges = {}
	local steel = rgb(70, 74, 80)
	for i = 1, 5 do
		local x0 = -8 + (i - 1) * 9.2
		local x1 = x0 + 9.2
		local m = model("Fridge" .. i, f)
		if useModels({ "OpenChiller2m" }) then
			-- открытая холодильная горка (перед модели — локальная -X, поворачиваем лицом в зал)
			local def = Models.Meshes.OpenChiller2m
			local d, h = 2.6, def.Size.Y * SS
			local cx, zc = (x0 + x1) / 2, -12 + d / 2
			local frontZ = -12 + d
			ModelKit.Make("OpenChiller2m", m, CFrame.new(cx, h / 2, zc) * CFrame.Angles(0, math.rad(90), 0), Vector3.new(d, h, x1 - x0 - 0.1), { Name = "Chiller" })
			local body = B(m, "Base", x0 + 0.2, 0, -11.9, x1 - 0.2, 0.6, frontZ - 0.3, steel, M.Metal, { Transparency = 1, CanCollide = false, CanQuery = false })
			tag(body, "AmbFridge")
			body:SetAttribute("Unit", i)
			local back = B(m, "Interior", x0 + 0.4, 1.8, -11.95, x1 - 0.4, 7.2, -11.9, rgb(236, 240, 244), M.SmoothPlastic, { Transparency = 1, CanCollide = false, CanQuery = false })
			local strip = B(m, "FridgeLamp", x0 + 0.5, 2.07 * SS - 0.3, frontZ - 0.9, x1 - 0.5, 2.07 * SS - 0.2, frontZ - 0.6, C.LampCold, M.Neon, { CastShadow = false })
			local sl = Instance.new("SurfaceLight")
			sl.Face = N.Bottom
			sl.Angle = 140
			sl.Range = 9
			sl.Brightness = 1.4
			sl.Color = C.LampCold
			sl.Parent = strip
			strip:SetAttribute("Zone", "Fridge" .. i)
			strip:SetAttribute("LampColor", C.LampCold)
			tag(strip, "StoreLight")
			local levels = Models.Levels.OpenChiller
			for level, ym in ipairs(levels) do
				local y = ym * SS + 0.02
				local top = levels[level + 1] and levels[level + 1] * SS or 2.07 * SS
				local backZ = (level == 1) and (-12 + 0.35) or (-12 + d * 0.17)
				productLayer(m, x0 + 0.5, x1 - 0.5, y, backZ, frontZ - 0.1, N.Back, "Chilled", nil, nil, top - y - 0.2)
			end
			local header = B(m, "Header", x0, h - 0.05, frontZ - 0.2, x1, h + 0.75, frontZ, rgb(30, 90, 170), M.SmoothPlastic)
			sign(header, N.Back, i <= 2 and "МОЛОЧНЫЕ ПРОДУКТЫ" or (i <= 4 and "МЯСО · КОЛБАСЫ · ПЕЛЬМЕНИ" or "СЫРЫ · ДЕСЕРТЫ"), { color = Color3.new(1, 1, 1), ppS = 30, light = 0, brightness = 1.4 })
			local thermo = B(m, "Thermometer", x1 - 1.6, h - 0.75, frontZ, x1 - 0.4, h - 0.15, frontZ + 0.14, C.Black, M.SmoothPlastic)
			local label = sign(thermo, N.Back, "+3 °C", { color = rgb(80, 255, 120), light = 0, brightness = 2, ppS = 60, font = Enum.Font.Code })
			table.insert(map.Fridges, {
				Index = i,
				Body = body,
				Lights = { strip },
				Interior = back,
				Thermo = thermo,
				ThermoLabel = label,
				Front = Vector3.new((x0 + x1) / 2, 0, -6.5),
			})
		else
			local body = B(m, "Base", x0, 0, -12, x1, 0.6, -8.4, steel, M.Metal)
			skin(B(m, "SideL", x0, 0.6, -12, x0 + 0.2, 8.2, -8.4, steel, M.Metal), I.StainlessSteel, 3, { N.Left, N.Right })
			skin(B(m, "SideR", x1 - 0.2, 0.6, -12, x1, 8.2, -8.4, steel, M.Metal), I.StainlessSteel, 3, { N.Left, N.Right })
			B(m, "Top", x0, 8.2, -12, x1, 9, -8.6, steel, M.Metal)
			tag(body, "AmbFridge")
			body:SetAttribute("Unit", i)
			local back = B(m, "Interior", x0 + 0.3, 0.6, -11.9, x1 - 0.3, 8, -11.7, rgb(236, 240, 244), M.SmoothPlastic)
			local lights = {}
			local strip = B(m, "FridgeLamp", x0 + 0.4, 7.85, -11.6, x1 - 0.4, 7.95, -11.3, C.LampCold, M.Neon, { CastShadow = false })
			local sl = Instance.new("SurfaceLight")
			sl.Face = N.Bottom
			sl.Angle = 140
			sl.Range = 9
			sl.Brightness = 1.4
			sl.Color = C.LampCold
			sl.Parent = strip
			strip:SetAttribute("Zone", "Fridge" .. i)
			strip:SetAttribute("LampColor", C.LampCold)
			tag(strip, "StoreLight")
			table.insert(lights, strip)
			for level, y in ipairs({ 0.7, 2.2, 3.7, 5.2, 6.6 }) do
				if level > 1 then
					B(m, "Shelf", x0 + 0.3, y - 0.08, -11.7, x1 - 0.3, y, -9.0, rgb(200, 210, 220), M.Glass, { Transparency = 0.3 })
				end
				productLayer(m, x0 + 0.4, x1 - 0.4, y, -11.5, -9.2, N.Back, "Chilled", nil, nil)
			end
			-- Стеклянные двери (3 на секцию) с рамками и ручками
			for d = 0, 2 do
				local dx0 = x0 + 0.2 + d * 2.95
				local dx1 = dx0 + 2.9
				B(m, "GlassDoor", dx0, 0.6, -8.6, dx1, 8.2, -8.45, rgb(190, 215, 230), M.Glass, { Transparency = 0.66, Reflectance = 0.2, CastShadow = false })
				B(m, "DoorFrame", dx0, 0.6, -8.62, dx0 + 0.12, 8.2, -8.4, C.Black, M.Metal)
				B(m, "DoorHandle", dx1 - 0.35, 3, -8.42, dx1 - 0.22, 6, -8.3, rgb(180, 182, 186), M.Metal)
			end
			local header = B(m, "Header", x0, 8.2, -8.6, x1, 9, -8.4, rgb(30, 90, 170), M.SmoothPlastic)
			sign(header, N.Back, i <= 2 and "МОЛОЧНЫЕ ПРОДУКТЫ" or (i <= 4 and "МЯСО · КОЛБАСЫ · ПЕЛЬМЕНИ" or "СЫРЫ · ДЕСЕРТЫ"), { color = Color3.new(1, 1, 1), ppS = 30, light = 0, brightness = 1.4 })
			-- Термометр-табло
			local thermo = B(m, "Thermometer", x1 - 1.5, 7.2, -8.44, x1 - 0.3, 7.9, -8.3, C.Black, M.SmoothPlastic)
			local label = sign(thermo, N.Back, "+3 °C", { color = rgb(80, 255, 120), light = 0, brightness = 2, ppS = 60, font = Enum.Font.Code })
			table.insert(map.Fridges, {
				Index = i,
				Body = body,
				Lights = lights,
				Interior = back,
				Thermo = thermo,
				ThermoLabel = label,
				Front = Vector3.new((x0 + x1) / 2, 0, -6.5),
			})
		end
	end
end

-------------------------------------------------------------------------------
-- Кассы
-------------------------------------------------------------------------------
local LANE_X = { -24, -8, 8, 24 }

-- Касса из простых деталей (если модель кассового стола не загрузилась)
local function laneSimple(m, i, X)
	local open = i <= 3
	local counter = B(m, "Counter", X - 1.4, 0, 28, X + 1.4, 3, 40, rgb(226, 228, 228), M.SmoothPlastic)
	skin(counter, I.DarkPlastic, 4, { N.Left, N.Right }, rgb(150, 154, 160))
	B(m, "CounterKick", X - 1.45, 0, 28, X + 1.45, 0.6, 40, C.Dark, M.SmoothPlastic)
	B(m, "CounterTrim", X - 1.45, 2.9, 28, X + 1.45, 3.02, 40, rgb(200, 36, 40), M.SmoothPlastic)
	local belt = B(m, "Belt", X - 1.2, 3.02, 28.4, X + 1.2, 3.12, 35.2, rgb(26, 26, 28), M.Rubber)
	skin(belt, I.RubberMat, 2, { N.Top })
	B(m, "BeltEnd", X - 1.25, 3.0, 35.2, X + 1.25, 3.2, 35.45, C.Metal, M.Metal)
	local scanner = B(m, "Scanner", X - 0.9, 3.02, 35.6, X + 0.9, 3.08, 36.8, rgb(40, 50, 56), M.Glass, { Transparency = 0.15 })
	local laser = B(m, "Laser", X - 0.7, 3.085, 36.15, X + 0.7, 3.09, 36.25, rgb(255, 40, 40), M.Neon, { CastShadow = false })
	skin(B(m, "ScannerTower", X + 0.9, 3.0, 35.6, X + 1.35, 4.3, 36.8, C.Dark, M.SmoothPlastic), I.DarkPlastic, 2, { N.Left, N.Front, N.Back })
	skin(B(m, "BagArea", X - 1.2, 3.02, 37.2, X + 1.2, 3.07, 39.6, rgb(180, 182, 186), M.Metal), I.StainlessSteel, 2, { N.Top })
	B(m, "RailCustomer", X - 1.5, 3.0, 28, X - 1.4, 3.5, 40, C.Metal, M.Metal)
	-- Монитор кассира (+X) и табло покупателя (−X)
	Cyl(m, "MonitorPole", 0.2, 2.2, Vector3.new(X + 1.7, 4.1, 37.2), C.Dark, M.Metal)
	local screen = B(m, "Monitor", X + 1.15, 4.6, 36.4, X + 2.25, 5.7, 38.0, C.Black, M.SmoothPlastic)
	local cashierLabel = sign(screen, N.Right, open and "КАССА " .. i .. "\nСвободна" or "КАССА НЕ РАБОТАЕТ", {
		color = rgb(120, 220, 255),
		light = 0,
		brightness = 1.6,
		ppS = 70,
		font = Enum.Font.Code,
		alignY = Enum.TextYAlignment.Top,
		padding = 4,
		name = "CashierScreen",
	})
	local customerLabel = sign(screen, N.Left, open and "Добро пожаловать!" or "", {
		color = rgb(255, 230, 120),
		light = 0,
		brightness = 1.6,
		ppS = 70,
		font = Enum.Font.Code,
		padding = 4,
		name = "CustomerScreen",
	})
	-- Терминал оплаты
	Cyl(m, "TerminalPole", 0.15, 0.9, Vector3.new(X - 1.75, 3.45, 37.6), C.Dark, M.Metal)
	local terminal = B(m, "Terminal", X - 2.05, 3.9, 37.1, X - 1.45, 4.3, 38.1, rgb(36, 36, 40), M.SmoothPlastic)
	local terminalLabel = sign(terminal, N.Left, "", { color = rgb(120, 255, 160), light = 0, brightness = 1.5, ppS = 60, font = Enum.Font.Code, name = "TerminalScreen" })
	-- Номер кассы на стойке
	Cyl(m, "NumberPole", 0.22, 8.4, Vector3.new(X + 1.2, 4.2, 28.4), C.Dark, M.Metal)
	local numberBox = B(m, "NumberSign", X + 0.4, 8.4, 27.9, X + 2.0, 9.8, 28.9, open and rgb(40, 200, 90) or rgb(70, 70, 72), M.Neon, { CastShadow = false })
	sign(numberBox, N.Back, tostring(i), { color = Color3.new(1, 1, 1), light = 0, brightness = 2, ppS = 30, font = Enum.Font.GothamBlack })
	sign(numberBox, N.Front, tostring(i), { color = Color3.new(1, 1, 1), light = 0, brightness = 2, ppS = 30, font = Enum.Font.GothamBlack })
	-- коврик кассира
	skin(B(m, "Mat", X + 1.5, 0, 32, X + 5.5, 0.06, 39, rgb(36, 36, 38), M.Rubber), I.RubberMat, 2, { N.Top })
	-- Стойка с мелочами (жвачка, шоколад) между кассами
	if i < 4 then
		local rackPart = B(m, "ImpulseRack", X + 6.2, 0, 29, X + 7.2, 4.6, 38, C.Metal, M.Metal)
		metalSkin(rackPart, { N.Right })
		for _, y in ipairs({ 1.2, 2.6 }) do
			B(m, "ImpulseShelf", X + 7.2, y - 0.08, 29.2, X + 7.9, y, 37.8, C.Metal, M.Metal)
			productLayer(m, X + 7.25, X + 7.9, y, 29.3, 37.7, N.Right, "Snacks", nil, nil)
		end
	end
	if not open then
		local chain = B(m, "Chain", X - 5.6, 2.6, 27.9, X - 1.5, 2.75, 28.1, rgb(230, 190, 30), M.Metal)
		local closedSign = P(m, "ClosedSign", Vector3.new(2.4, 1, 0.08), CFrame.new(X - 3.5, 2.1, 28), Color3.new(1, 1, 1), M.SmoothPlastic)
		sign(closedSign, N.Back, "КАССА НЕ РАБОТАЕТ", { color = C.Red, ppS = 40 })
		sign(closedSign, N.Front, "КАССА НЕ РАБОТАЕТ", { color = C.Red, ppS = 40 })
		chain:SetAttribute("Lane", i)
	end
	local cx = X - 3.4
	local lane = {
		Index = i,
		X = X,
		Model = m,
		Open = open,
		Belt = belt,
		Scanner = scanner,
		Laser = laser,
		Monitor = screen,
		CashierLabel = cashierLabel,
		CustomerLabel = customerLabel,
		Terminal = terminal,
		TerminalLabel = terminalLabel,
		NumberSign = numberBox,
		QueueSpots = {
			Vector3.new(cx, 0, 35.8),
			Vector3.new(cx, 0, 31.4),
			Vector3.new(cx, 0, 27.2),
			Vector3.new(cx, 0, 23.4),
			Vector3.new(cx - 1.5, 0, 21.2),
		},
		ItemZ = { 34.6, 33.6, 32.6, 31.6, 30.6, 29.6, 28.8 },
		BagSpot = Vector3.new(X, 3.07, 38.4),
		ScanSpot = Vector3.new(X, 3.3, 36.2),
		CashierSpot = Vector3.new(X + 3.4, 0, 35),
		ExitSpot = Vector3.new(cx, 0, 44.5),
		CashierZone = { X + 1.4, X + 6.2, 30, 40 },
	}
	return lane
end

-- Касса из модели кассового стола «Cash register» (Dester): лента и денежный ящик со стороны кассира (-X),
-- кассовый аппарат с экраном у дальнего края, столешница для пакетов со стороны покупателя (+X).
-- Покупатели стоят в очереди справа от стола (+X), кассир — слева (-X). Кресел у касс нет: кассир стоит.
local function laneModel(m, i, X)
	local open = i <= 3
	local CK = Models.Checkout
	local k = Models.Assets.Checkout.Scale
	local zc = 36
	-- в игре: смещение по X = -z_файла * k, по Z = x_файла * k (поворот на 90° после разворота импорта)
	ModelKit.MakeAsset("Checkout", m, CFrame.new(X, 0, zc) * CFrame.Angles(0, math.rad(90), 0), k)
	local beltX = X - (CK.BeltDepth[1] + CK.BeltDepth[2]) / 2 * k
	local beltZ0, beltZ1 = zc + CK.BeltLength[1] * k, zc + CK.BeltLength[2] * k
	local beltY = CK.BeltTop * k
	local topY = CK.Top * k
	local belt = B(m, "Belt", beltX - 0.8, beltY - 0.1, beltZ0, beltX + 0.8, beltY, beltZ1, rgb(26, 26, 28), M.Rubber, { Transparency = 1, CanCollide = false, CanQuery = false })
	-- сканер в конце ленты: стойка с красным стеклом, луч лазера
	local scanZ = beltZ1 - 0.95
	local tower = B(m, "ScannerTower", beltX - 0.55, beltY, beltZ1 - 0.35, beltX + 0.55, beltY + 1.0, beltZ1 - 0.05, rgb(34, 36, 40), M.SmoothPlastic)
	local scanner = B(m, "Scanner", beltX - 0.45, beltY + 0.12, beltZ1 - 0.37, beltX + 0.45, beltY + 0.82, beltZ1 - 0.35, rgb(120, 20, 20), M.Glass, { Transparency = 0.25, CastShadow = false })
	local laser = B(m, "Laser", beltX - 0.4, beltY + 0.02, scanZ - 0.03, beltX + 0.4, beltY + 0.03, scanZ + 0.03, rgb(255, 40, 40), M.Neon, { CastShadow = false })
	-- дисплей на стойке: сторона кассира (-X) и сторона покупателя (+X)
	Cyl(m, "MonitorPole", 0.16, 1.4, Vector3.new(X + 0.3, topY + 0.7, zc + 3.45), C.Dark, M.Metal)
	local screen = B(m, "Monitor", X + 0.24, topY + 1.3, zc + 2.7, X + 0.36, topY + 2.3, zc + 4.2, C.Black, M.SmoothPlastic)
	local cashierLabel = sign(screen, N.Left, open and "КАССА " .. i .. "\nСвободна" or "КАССА НЕ РАБОТАЕТ", {
		color = rgb(120, 220, 255),
		light = 0,
		brightness = 1.6,
		ppS = 70,
		font = Enum.Font.Code,
		alignY = Enum.TextYAlignment.Top,
		padding = 4,
		name = "CashierScreen",
	})
	local customerLabel = sign(screen, N.Right, open and "Добро пожаловать!" or "", {
		color = rgb(255, 230, 120),
		light = 0,
		brightness = 1.6,
		ppS = 70,
		font = Enum.Font.Code,
		padding = 4,
		name = "CustomerScreen",
	})
	-- терминал для карт на краю стола со стороны покупателя
	Cyl(m, "TerminalPole", 0.12, 0.6, Vector3.new(X + 2.35, topY + 0.3, zc + 1.4), C.Dark, M.Metal)
	local terminal = B(m, "Terminal", X + 2.1, topY + 0.55, zc + 0.95, X + 2.6, topY + 0.95, zc + 1.85, rgb(36, 36, 40), M.SmoothPlastic)
	local terminalLabel = sign(terminal, N.Right, "", { color = rgb(120, 255, 160), light = 0, brightness = 1.5, ppS = 60, font = Enum.Font.Code, name = "TerminalScreen" })
	-- номер кассы над входом в очередь
	Cyl(m, "NumberPole", 0.22, 8.4, Vector3.new(X + 2.6, 4.2, beltZ0 - 0.4), C.Dark, M.Metal)
	local numberBox = B(m, "NumberSign", X + 1.8, 8.4, beltZ0 - 0.9, X + 3.4, 9.8, beltZ0 + 0.1, open and rgb(40, 200, 90) or rgb(70, 70, 72), M.Neon, { CastShadow = false })
	sign(numberBox, N.Back, tostring(i), { color = Color3.new(1, 1, 1), light = 0, brightness = 2, ppS = 30, font = Enum.Font.GothamBlack })
	sign(numberBox, N.Front, tostring(i), { color = Color3.new(1, 1, 1), light = 0, brightness = 2, ppS = 30, font = Enum.Font.GothamBlack })
	-- коврик кассира
	skin(B(m, "Mat", X - 5.4, 0, zc - 3, X - 2.2, 0.06, zc + 4, rgb(36, 36, 38), M.Rubber), I.RubberMat, 2, { N.Top })
	-- стойка с мелочами для очереди (между кассами, смотрит на покупателей этой кассы)
	if i < 4 then
		local rackPart = B(m, "ImpulseRack", X + 6.2, 0, 29, X + 7.0, 4.6, 38, C.Metal, M.Metal)
		metalSkin(rackPart, { N.Left })
		for _, y in ipairs({ 1.2, 2.6, 4.0 }) do
			B(m, "ImpulseShelf", X + 5.4, y - 0.08, 29.2, X + 6.2, y, 37.8, C.Metal, M.Metal)
			productLayer(m, X + 5.45, X + 6.15, y, 29.3, 37.7, N.Left, "Snacks", nil, nil, 1.2)
		end
	end
	if not open then
		local chain = B(m, "Chain", X + 2.2, 2.6, beltZ0 - 0.6, X + 5.8, 2.75, beltZ0 - 0.4, rgb(230, 190, 30), M.Metal)
		local closedSign = P(m, "ClosedSign", Vector3.new(2.4, 1, 0.08), CFrame.new(X + 4, 2.1, beltZ0 - 0.5), Color3.new(1, 1, 1), M.SmoothPlastic)
		sign(closedSign, N.Back, "КАССА НЕ РАБОТАЕТ", { color = C.Red, ppS = 40 })
		sign(closedSign, N.Front, "КАССА НЕ РАБОТАЕТ", { color = C.Red, ppS = 40 })
		chain:SetAttribute("Lane", i)
	end
	local cx = X + 3.4
	local spacing = math.min(0.62, (beltZ1 - 1.6 - beltZ0 - 0.2) / 6)
	local itemZ = {}
	for n = 0, 6 do
		table.insert(itemZ, beltZ1 - 1.6 - n * spacing)
	end
	return {
		Index = i,
		X = X,
		BeltX = beltX,
		BeltY = beltY + 0.02,
		Model = m,
		Open = open,
		Belt = belt,
		Scanner = scanner,
		Laser = laser,
		Tower = tower,
		Monitor = screen,
		CashierLabel = cashierLabel,
		CustomerLabel = customerLabel,
		Terminal = terminal,
		TerminalLabel = terminalLabel,
		NumberSign = numberBox,
		QueueSpots = {
			Vector3.new(cx - 0.1, 0, zc + 1.4),
			Vector3.new(cx, 0, zc - 2.4),
			Vector3.new(cx + 0.1, 0, zc - 6),
			Vector3.new(cx + 0.2, 0, zc - 9.4),
			Vector3.new(cx + 0.6, 0, 25),
		},
		ItemZ = itemZ,
		BagSpot = Vector3.new(X + 1.0, topY, zc - 1.6),
		ScanSpot = Vector3.new(beltX, beltY + 0.4, scanZ),
		CashierSpot = Vector3.new(X - 3.2, 0, zc + 1),
		ExitSpot = Vector3.new(cx, 0, 44.5),
		CashierZone = { X - 6.2, X - 1.9, zc - 5, zc + 5 },
		Side = -1, -- кассир с -X
	}
end

local function buildLanes(root, map)
	local f = folder("Checkouts", root)
	map.Lanes = {}
	for i, X in ipairs(LANE_X) do
		local m = model("Lane" .. i, f)
		local lane
		if ModelKit.HasAsset("Checkout") then
			lane = laneModel(m, i, X)
		else
			lane = laneSimple(m, i, X)
		end
		table.insert(map.Lanes, lane)
	end
	-- Корзины у входа
	for i = 0, 5 do
		B(f, "Basket", -63.5, i * 0.35, 45.2, -61.5, i * 0.35 + 0.9, 46.6, rgb(190, 30, 34), M.SmoothPlastic, { Transparency = 0.1 })
	end
end

-------------------------------------------------------------------------------
-- Склад
-------------------------------------------------------------------------------
local BOX_KINDS = { "BoxClosed", "BoxClosed", "BoxClosed", "BoxFlat", "BoxOpen", "BoxTray" }

-- Коробка-модель на полке склада (размер подбирается под высоту и глубину полки)
local function modelBox(parent, kind, cx, y, z, maxH, maxD)
	local s = Models.Meshes[kind].Size
	local k = rng:NextNumber(1.5, 2.1) * SS
	k = math.min(k, maxH / s.Y, maxD / s.X)
	local size = s * k
	local cf = CFrame.new(cx + rng:NextNumber(-0.15, 0.15), y + size.Y / 2, z + size.Z / 2) * CFrame.Angles(0, math.rad((rng:NextNumber() < 0.5 and 0 or 180) + rng:NextNumber(-4, 4)), 0)
	return ModelKit.Make(kind, parent, cf, size, { Name = "Box" }), size
end

local function rackModel(parent, x0, x1, z0, z1)
	local m = model("Rack", parent)
	local def = Models.Meshes.Rack2m
	local d, h = x1 - x0, def.Size.Y * SS
	local n = math.max(1, math.floor((z1 - z0) / (def.Size.Z * SS) + 0.5))
	local w = (z1 - z0) / n
	local cx = (x0 + x1) / 2
	for k = 0, n - 1 do
		ModelKit.Make("Rack2m", m, CFrame.new(cx, h / 2, z0 + (k + 0.5) * w), Vector3.new(d, h, w), { Name = "RackBay" })
	end
	local levels = Models.Levels.Rack
	for level, ym in ipairs(levels) do
		local y = ym * SS + 0.05
		local top = levels[level + 1] and levels[level + 1] * SS or h
		local z = z0 + 0.4
		while z < z1 - 1.2 do
			if rng:NextNumber() < 0.85 then
				local _, size = modelBox(m, BOX_KINDS[rng:NextInteger(1, #BOX_KINDS)], cx, y, z, top - y - 0.25, d - 0.4)
				z = z + size.Z + rng:NextNumber(0.15, 0.5)
				if z > z1 - 0.3 then
					break
				end
			else
				z = z + rng:NextNumber(1.2, 2.2)
			end
		end
	end
	return m
end

local function rack(parent, x0, x1, z0, z1)
	if useModels({ "Rack2m", "BoxClosed", "BoxFlat", "BoxOpen", "BoxTray" }) then
		return rackModel(parent, x0, x1, z0, z1)
	end
	local m = model("Rack", parent)
	local orange, blue = rgb(230, 110, 30), rgb(30, 70, 150)
	local bays = math.max(1, math.floor((z1 - z0) / 8 + 0.5))
	for b = 0, bays do
		local z = z0 + (z1 - z0) * b / bays
		for _, x in ipairs({ x0, x1 }) do
			B(m, "Upright", x - 0.2, 0, z - 0.2, x + 0.2, 12, z + 0.2, blue, M.Metal)
		end
	end
	for _, y in ipairs({ 0.4, 4.2, 8.2 }) do
		B(m, "Beam", x0 - 0.15, y + 0.2, z0, x0 + 0.15, y + 0.6, z1, orange, M.Metal)
		B(m, "Beam", x1 - 0.15, y + 0.2, z0, x1 + 0.15, y + 0.6, z1, orange, M.Metal)
		B(m, "Deck", x0, y + 0.6, z0, x1, y + 0.7, z1, rgb(120, 120, 116), M.DiamondPlate)
		local z = z0 + 0.4
		while z < z1 - 1.5 do
			local w = rng:NextNumber(1.6, 3.2)
			if z + w > z1 - 0.3 then
				break
			end
			local h = rng:NextNumber(1.2, 3.0)
			local d = (x1 - x0) - rng:NextNumber(0.3, 0.9)
			local cx = (x0 + x1) / 2
			if rng:NextNumber() < 0.85 then
				local tint = rng:NextNumber(0.85, 1.05)
				B(m, "Box", cx - d / 2, y + 0.7, z, cx + d / 2, y + 0.7 + h, z + w, Color3.new(C.Cardboard.R * tint, C.Cardboard.G * tint, C.Cardboard.B * tint), M.Cardboard)
			end
			z = z + w + rng:NextNumber(0.2, 0.6)
		end
	end
	return m
end

local function buildWarehouse(root, map)
	local f = folder("Warehouse", root)
	rack(f, -65.4, -61.6, -60, -16)
	rack(f, -54.4, -50.6, -58, -26)
	rack(f, -41.4, -37.6, -58, -34)
	-- Поддоны с коробками для выкладки (по отделам) у двери в зал
	map.BoxPiles = {}
	for i, cat in ipairs(Products.RestockCategories) do
		local x0 = -36.5 + (i - 1) * 3.4
		B(f, "Pallet", x0, 0, -17, x0 + 2.8, 0.45, -14, rgb(160, 120, 70), M.WoodPlanks)
		local h = 0.45
		for k = 1, 3 do
			if useModels({ "BoxClosed" }) then
				local size = Vector3.new(2.6, 1.15, 2.8)
				ModelKit.Make("BoxClosed", f, CFrame.new(x0 + 1.4, h + size.Y / 2, -15.5) * CFrame.Angles(0, math.rad(rng:NextNumber(-3, 3)), 0), size, { Name = "PalletBox" })
				h = h + size.Y
			else
				local bh = rng:NextNumber(1.0, 1.3)
				B(f, "PalletBox", x0 + 0.1, h, -16.9, x0 + 2.7, h + bh, -14.1, C.Cardboard, M.Cardboard)
				h = h + bh
			end
		end
		local top = B(f, "BoxPile", x0 + 0.2, h, -16.6, x0 + 2.6, h + 1.2, -14.4, C.Cardboard, M.Cardboard)
		skin(top, I.Cardboard, 3, { N.Top, N.Front, N.Back, N.Left, N.Right })
		local label = B(f, "PileSign", x0, 6.5, -12.7, x0 + 2.8, 7.6, -12.5, Color3.new(1, 1, 1), M.SmoothPlastic)
		sign(label, N.Front, Products.Categories[cat].Name, { color = rgb(30, 30, 30), ppS = 40 })
		sign(top, N.Front, Products.Categories[cat].Name, { color = rgb(60, 40, 20), ppS = 40 })
		table.insert(map.BoxPiles, { Category = cat, Part = top })
	end
	-- Зона приёмки
	local zone = B(f, "ReceivingZone", -32, 0, -52, -22, 0.03, -44, rgb(70, 70, 66), M.Concrete)
	for _, e in ipairs({ { -32, -52, -22, -51.7 }, { -32, -44.3, -22, -44 }, { -32, -52, -31.7, -44 }, { -22.3, -52, -22, -44 } }) do
		B(f, "ZoneLine", e[1], 0.03, e[2], e[3], 0.05, e[4], C.Price, M.SmoothPlastic)
	end
	local zoneSign = B(f, "ZoneSign", -27, 0.05, -48.5, -24, 0.06, -47, Color3.new(1, 1, 1), M.SmoothPlastic, { Transparency = 1 })
	sign(zoneSign, N.Top, "ПРИЁМКА", { color = C.Price, ppS = 40 })
	map.Stations = map.Stations or {}
	map.Stations.DeliveryDrop = zone
	-- Мусорный контейнер с мешками
	local bin = B(f, "TrashBin", -22, 0, -28, -19, 4, -24, rgb(70, 90, 70), M.SmoothPlastic)
	B(f, "TrashBinLid", -22.1, 4, -28.1, -18.9, 4.3, -23.9, rgb(50, 66, 50), M.SmoothPlastic)
	for k = 0, 2 do
		local bag = P(f, "TrashBag", Vector3.new(1.6, 1.6, 1.6), CFrame.new(-23.5, 0.8, -27 + k * 1.3), rgb(24, 24, 26), M.Plastic)
		bag.Shape = Enum.PartType.Ball
	end
	map.Stations.TrashBin = bin
	-- Тележка-рохля и пустые поддоны
	B(f, "PalletJack", -30, 0.2, -38, -28.6, 0.6, -33, rgb(200, 40, 40), M.Metal)
	Cyl(f, "JackHandle", 0.15, 4, Vector3.new(-29.3, 2, -38.3), C.Black, M.Metal)
	for k = 0, 5 do
		B(f, "EmptyPallet", -46, k * 0.45, -63.5, -42, k * 0.45 + 0.4, -60.5, rgb(150, 112, 66), M.WoodPlanks)
	end
	-- Касса №0: старый прилавок под брезентом в дальнем углу
	local r0 = model("Register0", f)
	local counter = B(r0, "OldCounter", -61, 0, -63.5, -55, 3, -61.5, rgb(120, 110, 96), M.WoodPlanks)
	local register = B(r0, "OldRegister", -59, 3, -63.2, -57, 4.2, -61.8, rgb(70, 66, 60), M.SmoothPlastic)
	local crt = B(r0, "OldScreen", -58.6, 4.2, -62.9, -57.4, 5.1, -62.2, rgb(30, 34, 30), M.Glass, { Transparency = 0 })
	local crtLabel = sign(crt, N.Back, "", { color = rgb(120, 255, 140), light = 0, brightness = 1.6, ppS = 80, font = Enum.Font.Code, name = "OldScreen" })
	local numberPlate = B(r0, "Plate", -61, 3, -61.6, -59.6, 3.8, -61.45, rgb(200, 190, 160), M.SmoothPlastic)
	sign(numberPlate, N.Back, "КАССА 0", { color = rgb(60, 50, 40), ppS = 60 })
	local tarp = B(r0, "Tarp", -61.6, 0, -64, -54.4, 5.6, -60.8, rgb(70, 86, 110), M.Fabric)
	local r0light = pendantLight(r0, Vector3.new(-58, 9, -60), "Register0", { color = rgb(255, 230, 190), range = 14, brightness = 0, cable = 5 })
	-- эта лампа загорается только когда касса №0 откроется (её включает Secrets, а не общий свет)
	CollectionService:RemoveTag(r0light, "StoreLight")
	r0light.Material = M.SmoothPlastic
	r0light.Color = rgb(90, 86, 80)
	map.Register0 = {
		Model = r0,
		Counter = counter,
		Register = register,
		Screen = crt,
		ScreenLabel = crtLabel,
		Tarp = tarp,
		TarpCFrame = tarp.CFrame,
		Lamp = r0light,
		CustomerSpot = CFrame.lookAt(Vector3.new(-58, 0, -58.6), Vector3.new(-58, 0, -64)),
		ItemSpot = Vector3.new(-56, 3.5, -62.4),
		PlayerSpot = Vector3.new(-58, 0, -57),
	}
	-- Свет склада
	for _, p in ipairs({ { -58, -24 }, { -58, -48 }, { -46, -22 }, { -46, -46 }, { -28, -22 }, { -28, -40 }, { -28, -56 } }) do
		pendantLight(f, Vector3.new(p[1], 12.6, p[2]), "Warehouse", { broken = (p[1] == -46 and p[2] == -46), shadows = (p[2] == -40) })
	end
end

-------------------------------------------------------------------------------
-- Служебный коридор, щиток, задний выход, коридор к комнатам
-------------------------------------------------------------------------------
local function buildCorridors(root, map)
	local f = folder("Corridors", root)
	-- Трубы под потолком
	Cyl(f, "Pipe", 0.6, 52, Vector3.new(-17.2, 9.2, -38), rgb(150, 150, 150), M.Metal).CFrame = CFrame.new(-17.2, 9.2, -38) * CFrame.Angles(0, math.rad(90), 0)
	Cyl(f, "Pipe", 0.4, 52, Vector3.new(-16.4, 9.4, -38), rgb(170, 80, 60), M.Metal).CFrame = CFrame.new(-16.4, 9.4, -38) * CFrame.Angles(0, math.rad(90), 0)
	-- Щиток (на восточной стене служебного коридора)
	local panelBox = B(f, "ElectricalPanel", -10.95, 3, -52, -10.3, 7, -48, rgb(120, 126, 120), M.Metal)
	local warn = B(f, "PanelWarning", -11.0, 7.2, -51, -10.96, 8.2, -49, C.Price, M.SmoothPlastic)
	sign(warn, N.Left, "⚡ ЩИТОК\nНе влезай — убьёт!", { color = C.Black, ppS = 50 })
	local breakers = {}
	for k = 1, 3 do
		local z = -51.3 + (k - 1) * 1.3
		local lever = B(f, "Breaker" .. k, -11.3, 4.6, z - 0.25, -10.95, 5.4, z + 0.25, C.Black, M.SmoothPlastic)
		local led = B(f, "BreakerLed" .. k, -11.0, 5.7, z - 0.12, -10.94, 5.94, z + 0.12, rgb(40, 220, 80), M.Neon, { CastShadow = false })
		table.insert(breakers, { Lever = lever, Led = led, UpCFrame = lever.CFrame, DownCFrame = lever.CFrame * CFrame.new(0, -0.5, 0) })
	end
	local panelLabelPart = B(f, "PanelLabel", -11.0, 3.2, -51.5, -10.96, 4.2, -48.5, C.Black, M.SmoothPlastic)
	local panelLabel = sign(panelLabelPart, N.Left, "СЕТЬ: НОРМА", { color = rgb(80, 255, 120), light = 0, brightness = 1.5, ppS = 60, font = Enum.Font.Code })
	map.Panel = { Box = panelBox, Breakers = breakers, Label = panelLabel }
	-- Огнетушитель и доска в коридоре
	Cyl(f, "Extinguisher", 0.7, 2, Vector3.new(10, 1, -34.6), C.Red, M.SmoothPlastic)
	B(f, "WaterCooler", 37, 0, -39.5, 39, 4, -37.6, rgb(220, 220, 224), M.SmoothPlastic)
	Cyl(f, "WaterBottle", 1.4, 1.8, Vector3.new(38, 4.9, -38.5), rgb(120, 180, 230), M.Glass, { Transparency = 0.35 })
	-- Таблички на дверях
	local plates = {
		{ 5.2, 5.8, -34.34, N.Front, "ОХРАНА" },
		{ 30.2, 5.8, -34.34, N.Front, "КОМНАТА ПЕРСОНАЛА" },
		{ 5.2, 5.8, -39.66, N.Back, "ХОЛОДИЛЬНАЯ КАМЕРА · −18 °C" },
		{ 30.2, 5.8, -39.66, N.Back, "ДИРЕКТОР" },
	}
	for _, pl in ipairs(plates) do
		local plate = P(f, "DoorPlate", Vector3.new(3.2, 0.9, 0.06), CFrame.new(pl[1], pl[2], pl[3]), rgb(240, 240, 236), M.SmoothPlastic)
		sign(plate, pl[4], pl[5], { color = C.Black, ppS = 50 })
	end
	-- Свет
	ceilingLight(f, Vector3.new(-14, 9.8, -20), 5, false, "Corridor", { brightness = 0.9, range = 14 })
	local broken = ceilingLight(f, Vector3.new(-14, 9.8, -37), 5, false, "Corridor", { brightness = 0.9, range = 14, broken = true })
	tag(broken, "AmbFluor")
	ceilingLight(f, Vector3.new(-14, 9.8, -54), 5, false, "Corridor", { brightness = 0.9, range = 14, shadows = true })
	ceilingLight(f, Vector3.new(0, 9.8, -37), 5, true, "Corridor", { brightness = 0.9, range = 14 })
	ceilingLight(f, Vector3.new(20, 9.8, -37), 5, true, "Corridor", { brightness = 0.9, range = 14 })
	ceilingLight(f, Vector3.new(34, 9.8, -37), 5, true, "Corridor", { brightness = 0.9, range = 14 })
	exitSign(f, Vector3.new(-14, 9.2, -63.6), Vector3.new(0, 0, 1))
	exitSign(f, Vector3.new(-14, 9.2, -12.75), Vector3.new(0, 0, -1))
end

-------------------------------------------------------------------------------
-- Охрана, комната персонала, холодильная камера, кабинет менеджера
-------------------------------------------------------------------------------
local function chair(parent, x, z, facing)
	local cf = CFrame.new(x, 0, z) * CFrame.Angles(0, math.rad(facing), 0)
	P(parent, "ChairSeat", Vector3.new(1.8, 0.25, 1.8), cf * CFrame.new(0, 1.9, 0), rgb(40, 40, 46), M.Fabric)
	P(parent, "ChairBack", Vector3.new(1.8, 2, 0.25), cf * CFrame.new(0, 3, 0.85), rgb(40, 40, 46), M.Fabric)
	P(parent, "ChairLeg", Vector3.new(0.25, 1.8, 0.25), cf * CFrame.new(0, 0.9, 0), C.Dark, M.Metal)
	P(parent, "ChairFoot", Vector3.new(1.6, 0.15, 1.6), cf * CFrame.new(0, 0.08, 0), C.Dark, M.Metal)
end

local function buildRooms(root, map)
	local f = folder("Rooms", root)
	map.Stations = map.Stations or {}
	map.Clues = {}

	-- ОХРАНА -----------------------------------------------------------------
	local sec = model("Security", f)
	B(sec, "Desk", -8, 0, -15.5, 8, 2.6, -12.6, rgb(90, 80, 70), M.WoodPlanks)
	local monitors = {}
	for k = -1, 1 do
		local x = k * 4.6
		local mon = B(sec, "Monitor", x - 2, 2.9, -14.6, x + 2, 5.6, -14.2, C.Black, M.SmoothPlastic)
		B(sec, "MonitorStand", x - 0.3, 2.6, -14.4, x + 0.3, 2.9, -13.8, C.Dark, M.Metal)
		local sg = Instance.new("SurfaceGui")
		sg.Face = N.Front
		sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		sg.PixelsPerStud = 60
		sg.LightInfluence = 0
		sg.Brightness = 1.3
		sg.MaxDistance = 60
		sg.Parent = mon
		local noise = Instance.new("ImageLabel")
		noise.Size = UDim2.fromScale(1, 1)
		noise.BackgroundColor3 = rgb(20, 30, 24)
		noise.Image = Config.Images.CctvNoise
		noise.ImageTransparency = 0.6
		noise.ScaleType = Enum.ScaleType.Tile
		noise.TileSize = UDim2.fromOffset(64, 64)
		noise.Parent = sg
		local txt = Instance.new("TextLabel")
		txt.BackgroundTransparency = 1
		txt.Size = UDim2.fromScale(1, 1)
		txt.Font = Enum.Font.Code
		txt.TextScaled = true
		txt.TextColor3 = rgb(150, 255, 170)
		txt.Text = k == 0 and "ВИДЕОНАБЛЮДЕНИЕ\nнажмите, чтобы открыть" or (k < 0 and "КАМ 1–3" or "КАМ 4–7")
		txt.Parent = noise
		table.insert(monitors, mon)
	end
	map.Stations.CamDesk = monitors[2]
	B(sec, "Keyboard", -1.2, 2.6, -16.2, 1.2, 2.7, -15.4, C.Black, M.SmoothPlastic)
	chair(sec, 0, -18.5, 0)
	-- Видеомагнитофон и кассета (улика)
	B(sec, "VCR", 5, 2.6, -15.3, 7.4, 3.0, -13.6, rgb(30, 30, 32), M.SmoothPlastic)
	local tape = B(sec, "Tape", 5.6, 3.0, -15.1, 6.9, 3.2, -14.3, rgb(20, 20, 22), M.SmoothPlastic)
	sign(tape, N.Top, "14.11.03", { color = Color3.new(1, 1, 1), ppS = 80 })
	map.Clues.Tape = tape
	-- Стеллаж с папками
	B(sec, "Shelf", -9.5, 0, -30, -8.2, 7, -22, rgb(120, 100, 80), M.Wood)
	for k = 0, 8 do
		B(sec, "Binder", -9.4, 4.2, -29.6 + k * 0.8, -8.4, 5.8, -29.0 + k * 0.8, k % 2 == 0 and rgb(40, 60, 140) or rgb(150, 40, 40), M.SmoothPlastic)
	end
	ceilingLight(sec, Vector3.new(0, 9.8, -20), 5, true, "Security", { brightness = 0.7, range = 13 })
	ceilingLight(sec, Vector3.new(0, 9.8, -29), 5, true, "Security", { brightness = 0.7, range = 13 })

	-- КОМНАТА ПЕРСОНАЛА ------------------------------------------------------
	local staff = model("StaffRoom", f)
	local lockers = {}
	for k = 0, 8 do
		local x0 = 14 + k * 2.1
		local body = B(staff, "Locker", x0, 0, -13.8, x0 + 2, 7.4, -12.4, rgb(110, 130, 150), M.Metal)
		B(staff, "LockerVent", x0 + 0.5, 6.2, -13.83, x0 + 1.5, 6.6, -13.8, C.Dark, M.Metal)
		B(staff, "LockerHandle", x0 + 1.5, 3.2, -13.9, x0 + 1.7, 4.2, -13.8, C.Metal, M.Metal)
		local number = (k == 8) and "0" or tostring(k + 1)
		local plate = B(staff, "LockerNumber", x0 + 0.6, 5.2, -13.84, x0 + 1.4, 5.8, -13.8, Color3.new(1, 1, 1), M.SmoothPlastic)
		sign(plate, N.Front, number, { color = (k == 8) and C.Red or C.Black, ppS = 60, font = (k == 8) and Enum.Font.SpecialElite or Enum.Font.GothamBold })
		table.insert(lockers, body)
	end
	map.Clues.Locker = lockers[9]
	-- Стол, стулья, кухня
	B(staff, "Table", 22, 2.6, -26, 30, 2.9, -22, rgb(200, 190, 170), M.Wood)
	for _, lx in ipairs({ 22.4, 29.6 }) do
		for _, lz in ipairs({ -25.6, -22.4 }) do
			B(staff, "TableLeg", lx - 0.15, 0, lz - 0.15, lx + 0.15, 2.6, lz + 0.15, C.Dark, M.Metal)
		end
	end
	chair(staff, 24, -27.6, 0)
	chair(staff, 28, -27.6, 0)
	chair(staff, 24, -20.4, 180)
	chair(staff, 28, -20.4, 180)
	B(staff, "Kitchen", 37, 0, -32, 39.6, 3, -22, rgb(230, 230, 226), M.SmoothPlastic)
	B(staff, "Microwave", 37.2, 3, -30, 39.4, 4.4, -27.4, rgb(220, 220, 220), M.SmoothPlastic)
	B(staff, "MicrowaveDoor", 37.15, 3.2, -29.6, 37.2, 4.2, -27.8, rgb(20, 20, 22), M.Glass, { Transparency = 0.1 })
	Cyl(staff, "Kettle", 0.9, 1.1, Vector3.new(38.2, 3.55, -24), rgb(240, 240, 240), M.SmoothPlastic)
	B(staff, "MiniFridge", 37.2, 0, -21.5, 39.6, 4.5, -19, Color3.new(1, 1, 1), M.SmoothPlastic)
	-- Табельные часы (начать смену)
	local clock = B(staff, "TimeClock", 12.3, 4, -31.5, 12.9, 5.8, -29.5, rgb(60, 60, 64), M.SmoothPlastic)
	local clockLabel = sign(clock, N.Right, "00:00", { color = rgb(255, 80, 60), light = 0, brightness = 2, ppS = 60, font = Enum.Font.Code })
	local clockTitle = B(staff, "TimeClockTitle", 12.3, 5.9, -31.5, 12.32, 6.6, -29.5, rgb(240, 240, 236), M.SmoothPlastic)
	sign(clockTitle, N.Right, "ТАБЕЛЬНЫЕ ЧАСЫ", { color = C.Black, ppS = 50 })
	map.Stations.TimeClock = clock
	map.Stations.TimeClockLabel = clockLabel
	-- Доска с правилами
	local board = B(staff, "RulesBoard", 12.3, 3.2, -26.5, 12.45, 7.8, -17.5, rgb(160, 120, 80), M.Wood)
	sign(board, N.Right, Texts.Rules, { color = rgb(30, 26, 20), ppS = 36, font = Enum.Font.Gotham, alignX = Enum.TextXAlignment.Left, alignY = Enum.TextYAlignment.Top, padding = 10, bg = rgb(244, 238, 222) })
	-- Швабра и ведро
	local bucket = Cyl(staff, "Bucket", 1.6, 1.4, Vector3.new(37.5, 0.7, -32.5), rgb(240, 200, 30), M.SmoothPlastic)
	local mop = P(staff, "Mop", Vector3.new(0.2, 6, 0.2), CFrame.new(38.6, 3, -32.8) * CFrame.Angles(math.rad(8), 0, math.rad(-6)), rgb(80, 120, 200), M.SmoothPlastic)
	map.Stations.Mop = mop
	map.Stations.MopBucket = bucket
	-- Коробка с батарейками на столе
	local batteries = B(staff, "Batteries", 25, 2.9, -24.6, 26.4, 3.4, -23.6, rgb(30, 30, 30), M.SmoothPlastic)
	sign(batteries, N.Top, "БАТАРЕЙКИ", { color = rgb(240, 190, 30), ppS = 60 })
	map.Stations.Batteries = batteries
	ceilingLight(staff, Vector3.new(20, 9.8, -23), 5, true, "Staff", { brightness = 0.9, range = 14, shadows = true })
	ceilingLight(staff, Vector3.new(32, 9.8, -23), 5, true, "Staff", { brightness = 0.9, range = 14 })

	-- ХОЛОДИЛЬНАЯ КАМЕРА ----------------------------------------------------
	local cold = model("ColdRoom", f)
	local metal = rgb(196, 202, 208)
	B(cold, "Lining", -9.7, 0, -63.7, 11.7, 10, -63.4, metal, M.Metal)
	B(cold, "Lining", -9.7, 0, -63.7, -9.4, 10, -40.4, metal, M.Metal)
	B(cold, "Lining", 11.4, 0, -63.7, 11.7, 10, -40.4, metal, M.Metal)
	for _, side in ipairs({ { -9.4, -6.8 }, { 8.8, 11.4 } }) do
		for _, y in ipairs({ 0.4, 2.6, 4.8, 7.0 }) do
			B(cold, "ColdShelf", side[1], y, -62, side[2], y + 0.12, -44, rgb(170, 176, 182), M.Metal)
			local z = -61.6
			while z < -45 do
				local w = rng:NextNumber(1.2, 2.4)
				local badgeSpot = side[1] > 0 and y == 2.6 and z < -59
				if rng:NextNumber() < 0.75 and not badgeSpot then
					B(cold, "ColdBox", side[1] + 0.2, y + 0.12, z, side[2] - 0.2, y + 0.12 + rng:NextNumber(0.8, 1.8), z + w, rgb(200, 180, 150), M.Cardboard)
				end
				z = z + w + 0.3
			end
		end
	end
	-- Полосовая завеса за дверью
	for k = 0, 7 do
		B(cold, "StripCurtain", -1.4 + k * 0.56, 0.3, -41.0, -0.9 + k * 0.56, 8.4, -40.9, rgb(200, 220, 230), M.Plastic, { Transparency = 0.55, CanCollide = false, CastShadow = false })
	end
	local thermo = B(cold, "ColdThermometer", -9.4, 4.4, -44.5, -9.25, 5.6, -42.5, C.Black, M.SmoothPlastic)
	local thermoLabel = sign(thermo, N.Right, "−18 °C", { color = rgb(120, 200, 255), light = 0, brightness = 2, ppS = 60, font = Enum.Font.Code })
	map.ColdThermo = { Part = thermo, Label = thermoLabel }
	local badge = B(cold, "Badge", 9.0, 2.72, -60.6, 9.8, 2.76, -60.0, Color3.new(1, 1, 1), M.SmoothPlastic)
	sign(badge, N.Top, "MART 24\nВЕТРОВ А.", { color = C.Red, ppS = 100 })
	map.Clues.Badge = badge
	local mist = B(cold, "ColdMist", -8, 0.2, -62, 10, 0.4, -44, Color3.new(1, 1, 1), M.SmoothPlastic, { Transparency = 1, CanCollide = false })
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = "rbxasset://textures/particles/smoke_main.dds"
	pe.Rate = 4
	pe.Lifetime = NumberRange.new(5, 8)
	pe.Speed = NumberRange.new(0.2, 0.6)
	pe.Size = NumberSequence.new(5)
	pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.4, 0.88), NumberSequenceKeypoint.new(1, 1) })
	pe.Color = ColorSequence.new(rgb(220, 235, 255))
	pe.LightInfluence = 1
	pe.Parent = mist
	tag(thermo, "AmbFridge")
	ceilingLight(cold, Vector3.new(1, 9.8, -47), 5, true, "Cold", { color = C.LampCold, brightness = 1.0, range = 14 })
	ceilingLight(cold, Vector3.new(1, 9.8, -58), 5, true, "Cold", { color = C.LampCold, brightness = 1.0, range = 14, shadows = true })


	-- КАБИНЕТ МЕНЕДЖЕРА -----------------------------------------------------
	-- Стол, старый компьютер, телефон, кружка кофе, бумаги, настольная лампа, часы на стене,
	-- электронные часы на столе, график смен, стена мониторов видеонаблюдения и записка для новичка.
	local office = model("Office", f)
	map.Office = {}
	local desk = B(office, "Desk", 20, 0, -58, 32, 2.8, -54, rgb(110, 70, 40), M.Wood)
	skin(desk, I.WoodCounter, 3, { N.Top, N.Front, N.Back, N.Left, N.Right })
	-- ящик стола со стороны менеджера (улика: газета)
	local drawer = B(office, "Drawer", 27.5, 1.4, -58.08, 30.5, 2.5, -58.0, rgb(96, 60, 34), M.Wood)
	B(office, "DrawerHandle", 28.6, 1.85, -58.2, 29.4, 2.05, -58.08, C.Metal, M.Metal)
	map.Clues.Newspaper = drawer
	-- старый компьютер: монитор-«ящик» и системный блок
	local crt = B(office, "OldMonitor", 20.6, 2.8, -56.8, 23.0, 4.9, -54.8, rgb(206, 198, 178), M.SmoothPlastic)
	local crtScreen = P(office, "OldMonitorScreen", Vector3.new(2.0, 1.6, 0.06), CFrame.lookAt(Vector3.new(21.8, 3.95, -56.84), Vector3.new(21.8, 3.95, -60)), rgb(20, 30, 26), M.Glass, { Transparency = 0 })
	sign(crtScreen, N.Front, "MART 24 · УЧЁТ\n\nСМЕНА: НОЧЬ\nКАССА 0: ???", { color = rgb(120, 220, 160), light = 0, brightness = 1.2, ppS = 80, font = Enum.Font.Code, alignX = Enum.TextXAlignment.Left, alignY = Enum.TextYAlignment.Top, padding = 8 })
	tag(crt, "AmbComputer")
	B(office, "PCTower", 17.2, 0, -58, 18.6, 3.2, -54.5, rgb(200, 192, 172), M.SmoothPlastic)
	B(office, "Keyboard", 21.0, 2.8, -57.8, 23.4, 2.92, -57.0, rgb(190, 184, 166), M.SmoothPlastic)
	-- журнал смены
	local logbook = B(office, "ShiftLog", 29.6, 2.8, -57.4, 31.2, 2.95, -56.2, rgb(30, 60, 120), M.SmoothPlastic)
	sign(logbook, N.Top, "ЖУРНАЛ СМЕНЫ", { color = Color3.new(1, 1, 1), ppS = 80 })
	map.Stations.ShiftLog = logbook
	-- телефон
	local phone = B(office, "Phone", 29.4, 2.8, -55.6, 30.6, 3.2, -54.6, rgb(150, 30, 30), M.SmoothPlastic)
	map.Stations.Phone = phone
	-- кружка кофе
	local mugPos = Vector3.new(28.2, 3.11, -55.1)
	Cyl(office, "Mug", 0.42, 0.62, mugPos, rgb(236, 236, 230), M.SmoothPlastic)
	Cyl(office, "Coffee", 0.36, 0.02, mugPos + Vector3.new(0, 0.29, 0), rgb(60, 36, 20), M.SmoothPlastic)
	B(office, "MugHandle", 28.43, 3.0, -55.16, 28.55, 3.3, -55.04, rgb(236, 236, 230), M.SmoothPlastic)
	-- стопки бумаг и папки
	for k = 0, 4 do
		B(office, "Paper", 23.6 + k * 0.02, 2.8 + k * 0.03, -57.6 + k * 0.03, 24.5 + k * 0.02, 2.83 + k * 0.03, -56.4 + k * 0.03, rgb(240, 238, 230), M.SmoothPlastic)
	end
	for k = 0, 5 do
		B(office, "Folder", 31.2, 2.8, -57.9 + k * 0.42, 31.8, 4.0, -57.55 + k * 0.42, k % 2 == 0 and rgb(40, 60, 140) or rgb(150, 40, 40), M.SmoothPlastic)
	end
	-- записка для новичка (лежит на столе, читается со стороны двери)
	local notePos = Vector3.new(26.0, 2.815, -55.4)
	local note = P(office, "Note", Vector3.new(0.78, 1.04, 0.02), CFrame.fromMatrix(notePos, Vector3.new(-1, 0, 0), Vector3.new(0, 0, -1), Vector3.new(0, -1, 0)) * CFrame.Angles(0, 0, math.rad(-6)), Color3.new(1, 1, 1), M.SmoothPlastic, { CastShadow = false })
	do
		local sg = Instance.new("SurfaceGui")
		sg.Name = "NoteGui"
		sg.Face = N.Front
		sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		sg.PixelsPerStud = 500
		sg.LightInfluence = 1
		sg.MaxDistance = 30
		sg.Parent = note
		local paper = Instance.new("ImageLabel")
		paper.Size = UDim2.fromScale(1, 1)
		paper.BackgroundTransparency = 1
		paper.Image = I.PaperNote
		paper.Parent = sg
		local text = Instance.new("TextLabel")
		text.BackgroundTransparency = 1
		text.Position = UDim2.fromScale(0.09, 0.07)
		text.Size = UDim2.fromScale(0.82, 0.86)
		text.Font = Enum.Font.GothamMedium
		text.TextColor3 = rgb(36, 40, 70)
		text.TextScaled = true
		text.TextWrapped = true
		text.TextXAlignment = Enum.TextXAlignment.Left
		text.TextYAlignment = Enum.TextYAlignment.Top
		text.Text = Texts.IntroNote
		text.Parent = paper
	end
	map.Office.Note = note
	-- электронные часы на столе (крупно в кат-сцене: 23:59 → 00:00)
	local clockPos = Vector3.new(24.6, 3.15, -54.5)
	local dclock = P(office, "DeskClock", Vector3.new(1.2, 0.7, 0.4), CFrame.lookAt(clockPos, clockPos + Vector3.new(0, 0, 1)), rgb(24, 24, 26), M.SmoothPlastic)
	local dclockLabel = sign(dclock, N.Front, "23:57", { color = rgb(255, 60, 40), light = 0, brightness = 2.4, ppS = 120, font = Enum.Font.Code, name = "ClockGui" })
	map.Office.DeskClock = dclock
	map.Office.DeskClockLabel = dclockLabel
	-- кресло
	chair(office, 26, -60, 180)
	-- шкафы, сейф, календарь, грамота, растение
	B(office, "FilingCabinet", 12.6, 0, -63.6, 15.6, 5, -61.4, rgb(130, 130, 136), M.Metal)
	B(office, "Safe", 33, 0, -63.6, 35.6, 3.5, -61, rgb(50, 54, 50), M.Metal)
	local calendar = B(office, "Calendar", 18, 4.5, -64, 21, 7.5, -63.9, Color3.new(1, 1, 1), M.SmoothPlastic)
	sign(calendar, N.Back, "НОЯБРЬ\n2003\n\n14", { color = C.Red, ppS = 50 })
	local diploma = B(office, "Diploma", 27, 5, -64, 30, 7, -63.9, rgb(240, 230, 200), M.SmoothPlastic)
	sign(diploma, N.Back, "Лучший магазин района\n2002", { color = rgb(120, 90, 30), ppS = 50, font = Enum.Font.Antique })
	Cyl(office, "PlantPot", 1.4, 1.4, Vector3.new(14, 0.7, -42), rgb(150, 80, 50), M.SmoothPlastic)
	local leaves = P(office, "Plant", Vector3.new(2.4, 2.4, 2.4), CFrame.new(14, 2.6, -42), rgb(50, 110, 50), M.Grass)
	leaves.Shape = Enum.PartType.Ball
	-- настольная лампа (тёплый свет)
	B(office, "DeskLamp", 31.0, 2.8, -55.0, 31.4, 4.2, -54.6, C.Dark, M.Metal)
	local bulb = B(office, "DeskLampBulb", 30.6, 4.1, -55.3, 31.4, 4.3, -54.5, C.LampWarm, M.Neon)
	local pl = Instance.new("PointLight")
	pl.Color = C.LampWarm
	pl.Range = 12
	pl.Brightness = 1.3
	pl.Shadows = true
	pl.Parent = bulb
	bulb:SetAttribute("Zone", "Office")
	bulb:SetAttribute("LampColor", C.LampWarm)
	tag(bulb, "StoreLight")
	-- настенные часы со стрелками (клиент поворачивает стрелки по времени смены)
	local wallClockPos = Vector3.new(17, 7.2, -40.42)
	local face = P(office, "WallClock", Vector3.new(0.12, 2.2, 2.2), CFrame.new(wallClockPos) * CFrame.Angles(0, math.rad(90), 0) * CFrame.Angles(0, 0, 0), Color3.new(1, 1, 1), M.SmoothPlastic)
	face.Shape = Enum.PartType.Cylinder
	local hourHand = P(office, "HourHand", Vector3.new(0.12, 0.6, 0.03), CFrame.new(wallClockPos + Vector3.new(0, 0.22, -0.09)), C.Black, M.SmoothPlastic, { CanCollide = false })
	local minuteHand = P(office, "MinuteHand", Vector3.new(0.08, 0.9, 0.03), CFrame.new(wallClockPos + Vector3.new(0, 0.38, -0.11)), C.Black, M.SmoothPlastic, { CanCollide = false })
	map.Office.WallClock = { Center = wallClockPos + Vector3.new(0, 0, -0.1), Hour = hourHand, Minute = minuteHand }
	tag(face, "WallClock")
	face:SetAttribute("Center", wallClockPos)
	hourHand:SetAttribute("ClockHand", "Hour")
	minuteHand:SetAttribute("ClockHand", "Minute")
	-- график смен на стене
	local schedule = B(office, "Schedule", 31, 3.6, -40.38, 38, 8.2, -40.3, rgb(250, 250, 246), M.SmoothPlastic)
	sign(schedule, N.Front, "ГРАФИК СМЕН · MART 24\n\nУтро 06:00–14:00 — Ирина К.\nДень 14:00–22:00 — Сергей П.\nВечер 18:00–00:00 — Олег Д.\nНОЧЬ 00:00–06:00 — НОВЫЙ СОТРУДНИК\n\nКасса №0 — —", { color = rgb(30, 30, 40), ppS = 40, font = Enum.Font.Gotham, alignX = Enum.TextXAlignment.Left, alignY = Enum.TextYAlignment.Top, padding = 12 })
	-- стена мониторов видеонаблюдения (на восточной стене, смотрит в комнату)
	B(office, "MonitorDesk", 37, 0, -57, 39.9, 2.6, -45, rgb(70, 66, 62), M.Wood)
	B(office, "MonitorShelf", 38.6, 2.6, -57, 39.9, 8.6, -45, C.Dark, M.Metal)
	local titles = { "1 ГЛАВНЫЙ ВХОД", "2 КАССЫ", "3 РЯД 1", "4 РЯД 2", "5 СКЛАД", "6 ХОЛОДИЛЬНЫЙ ОТДЕЛ" }
	map.Office.Screens = {}
	map.Office.ScreenCams = { 1, 2, 3, 4, 6, 5 }
	for k = 0, 5 do
		local col, row = k % 3, math.floor(k / 3)
		local pos = Vector3.new(38.5, 6.95 - row * 2.45, -55.0 + col * 3.6)
		local mon = P(office, "CctvMonitor", Vector3.new(3.3, 2.25, 0.5), CFrame.lookAt(pos, pos + Vector3.new(-1, 0, 0)), rgb(30, 30, 32), M.SmoothPlastic)
		local scr = P(office, "CctvScreen", Vector3.new(3.0, 1.95, 0.05), CFrame.lookAt(pos + Vector3.new(-0.27, 0, 0), pos + Vector3.new(-2, 0, 0)), rgb(12, 16, 14), M.Glass, { Transparency = 0 })
		local sg = Instance.new("SurfaceGui")
		sg.Name = "ScreenGui"
		sg.Face = N.Front
		sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		sg.PixelsPerStud = 90
		sg.LightInfluence = 0
		sg.Brightness = 1.2
		sg.MaxDistance = 80
		sg.Parent = scr
		local noise = Instance.new("ImageLabel")
		noise.Name = "Noise"
		noise.Size = UDim2.fromScale(1, 1)
		noise.BackgroundColor3 = rgb(16, 24, 20)
		noise.Image = I.CctvNoise
		noise.ImageTransparency = 0.75
		noise.ScaleType = Enum.ScaleType.Tile
		noise.TileSize = UDim2.fromOffset(64, 64)
		noise.ZIndex = 1
		noise.Parent = sg
		local label = Instance.new("TextLabel")
		label.Name = "Title"
		label.BackgroundTransparency = 1
		label.Size = UDim2.new(1, -12, 0, 26)
		label.Position = UDim2.fromOffset(8, 4)
		label.Font = Enum.Font.Code
		label.TextColor3 = rgb(200, 255, 210)
		label.TextScaled = true
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.Text = titles[k + 1]
		label.ZIndex = 3
		label.Parent = sg
		tag(scr, "OfficeScreen")
		scr:SetAttribute("Slot", k + 1)
		scr:SetAttribute("Camera", map.Office.ScreenCams[k + 1])
		table.insert(map.Office.Screens, scr)
		if k == 1 then
			map.Stations.OfficeCams = mon
		end
	end
	ceilingLight(office, Vector3.new(26, 9.8, -48), 5, true, "Office", { brightness = 0.55, range = 13 })
	-- точки для кат-сцены
	map.Office.Desk = Vector3.new(26, 2.8, -56)
	map.Office.WallCenter = Vector3.new(38.5, 5.7, -51.4)
	map.Points.IntroEnd = CFrame.lookAt(Vector3.new(26, 3, -49), Vector3.new(26, 3, -60))
end

-------------------------------------------------------------------------------
-- Задний двор
-------------------------------------------------------------------------------
local function buildAlley(root, map)
	local f = folder("Alley", root)
	B(f, "Ground", -40, -1, -92, 10, 0, -64.5, rgb(46, 46, 48), M.Asphalt)
	local brick = rgb(120, 70, 56)
	B(f, "WallS", -41, 0, -93, 11, 12, -92, brick, M.Brick)
	B(f, "WallW", -41, 0, -92, -40, 12, -64.5, brick, M.Brick)
	B(f, "WallE", 10, 0, -92, 11, 12, -64.5, brick, M.Brick)
	local dumpster = B(f, "Dumpster", -5, 0, -80, 3, 4.6, -76, rgb(40, 90, 50), M.Metal)
	B(f, "DumpsterLid", -5.1, 4.6, -80.1, 3.1, 4.9, -75.9, rgb(30, 70, 40), M.Metal)
	map.Stations.Dumpster = dumpster
	for k = 0, 3 do
		B(f, "Pallet", -36, k * 0.45, -90, -32, k * 0.45 + 0.4, -87, rgb(140, 104, 60), M.WoodPlanks)
	end
	for _, pd in ipairs({ { -24, -78, 5 }, { -10, -86, 4 }, { 0, -70, 3 } }) do
		local puddle = P(f, "Puddle", Vector3.new(0.05, pd[3], pd[3] * 1.4), CFrame.new(pd[1], 0.02, pd[2]) * CFrame.Angles(0, 0, math.rad(90)), rgb(20, 24, 30), M.Glass, { Reflectance = 0.35, Transparency = 0.2 })
		puddle.Shape = Enum.PartType.Cylinder
	end
	pendantLight(f, Vector3.new(-14, 9.6, -66), "Alley", { color = rgb(255, 190, 120), range = 30, broken = true, cable = 0.3, shadows = true })
	map.Stations.DeliverySpot = CFrame.new(-20, 0, -70)
end

-------------------------------------------------------------------------------
-- Двери
-------------------------------------------------------------------------------
local function buildDoors(root, map)
	local f = folder("Doors", root)
	local doorColor = rgb(170, 176, 180)
	map.Doors = {}
	-- Двустворчатая дверь склада (открывается в склад)
	local left = doorLeaf(f, -46, -42, -12, 9, doorColor, M.Metal, 1, true)
	local right = doorLeaf(f, -42, -38, -12, 9, doorColor, M.Metal, -1, true)
	map.Doors.WarehouseL = hingedDoor("WarehouseL", left, Vector3.new(-46, 4.5, -12), 95, "Swing", "Склад")
	map.Doors.WarehouseR = hingedDoor("WarehouseR", right, Vector3.new(-38, 4.5, -12), -95, "Swing", "Склад")
	map.Doors.WarehouseL.Pair = "WarehouseR"
	map.Doors.WarehouseR.Pair = "WarehouseL"
	map.Doors.Service = hingedDoor("Service", doorLeaf(f, -16, -12, -12, 8.5, doorColor, M.Metal, 1, false), Vector3.new(-16, 4, -12), 95, "Swing", "Служебное помещение")
	map.Doors.WarehouseSide = hingedDoor("WarehouseSide", doorLeafZ(f, -42, -38, -18, 8.5, doorColor, M.Metal, 1), Vector3.new(-18, 4, -42), 95, "Swing", "Склад")
	map.Doors.BackExit = hingedDoor("BackExit", doorLeaf(f, -16, -12, -64.5, 8.5, rgb(110, 116, 120), M.DiamondPlate, 1, false), Vector3.new(-16, 4, -64.5), 95, "Metal", "Задний выход")
	map.Doors.Security = hingedDoor("Security", doorLeaf(f, -1, 3, -34, 8.5, rgb(150, 120, 90), M.Wood, 1, false), Vector3.new(-1, 4, -34), -95, "Swing", "Охрана")
	map.Doors.Staff = hingedDoor("Staff", doorLeaf(f, 24, 28, -34, 8.5, rgb(150, 120, 90), M.Wood, 1, false), Vector3.new(24, 4, -34), -95, "Swing", "Комната персонала")
	map.Doors.ColdRoom = hingedDoor("ColdRoom", doorLeaf(f, -1.5, 3, -40, 8.5, rgb(210, 214, 218), M.Metal, -1, false), Vector3.new(3, 4, -40), -95, "Freezer", "Холодильная камера")
	map.Doors.Office = hingedDoor("Office", doorLeaf(f, 24, 28, -40, 8.5, rgb(120, 80, 50), M.Wood, 1, false), Vector3.new(24, 4, -40), 95, "Swing", "Кабинет менеджера")
end

-------------------------------------------------------------------------------
-- Камеры видеонаблюдения
-------------------------------------------------------------------------------
local CAMERAS = {
	{ "ГЛАВНЫЙ ВХОД", Vector3.new(-38, 12.5, 33), Vector3.new(-52, 4.5, 50) },
	{ "КАССЫ", Vector3.new(38, 13, 46), Vector3.new(-12, 2.5, 32) },
	{ "РЯДЫ 1–3", Vector3.new(-63, 13.5, -10), Vector3.new(-40, 2, 24) },
	{ "РЯДЫ 4–7", Vector3.new(37, 13.5, -10), Vector3.new(8, 2, 24) },
	{ "ХОЛОДИЛЬНЫЙ ОТДЕЛ", Vector3.new(-8, 13.5, 24), Vector3.new(22, 2, -8) },
	{ "СКЛАД", Vector3.new(-20, 12.5, -14), Vector3.new(-56, 1, -56) },
	{ "СЛУЖЕБНЫЙ КОРИДОР", Vector3.new(-12, 9, -13.5), Vector3.new(-14, 1, -64) },
	{ "ХОЛОДИЛЬНАЯ КАМЕРА", Vector3.new(10.5, 9, -41.5), Vector3.new(-6, 1, -62) },
	{ "ЗАДНИЙ ДВОР", Vector3.new(-17, 10.5, -65.5), Vector3.new(0, 0, -88) },
}

local function buildCameras(root, map)
	local f = folder("Cameras", root)
	map.Cameras = {}
	for i, c in ipairs(CAMERAS) do
		local cf = CFrame.lookAt(c[2], c[3])
		local m = model("Camera" .. i, f)
		P(m, "Body", Vector3.new(0.7, 0.7, 1.6), cf, rgb(230, 230, 228), M.SmoothPlastic)
		local lens = P(m, "Lens", Vector3.new(0.2, 0.5, 0.5), cf * CFrame.new(0, 0, -0.85) * CFrame.Angles(0, math.rad(90), 0), C.Black, M.Glass)
		lens.Shape = Enum.PartType.Cylinder
		P(m, "Led", Vector3.new(0.12, 0.12, 0.12), cf * CFrame.new(0.22, 0.38, -0.6), rgb(255, 30, 30), M.Neon, { CastShadow = false })
		P(m, "Mount", Vector3.new(0.25, 0.9, 0.25), cf * CFrame.new(0, 0.75, 0.4), C.Dark, M.Metal)
		local view = P(m, "View", Vector3.new(0.2, 0.2, 0.2), cf * CFrame.new(0, 0, -1.2), Color3.new(0, 0, 0), M.SmoothPlastic, {
			Transparency = 1,
			CanCollide = false,
			CanQuery = false,
			CastShadow = false,
		})
		view:SetAttribute("Index", i)
		view:SetAttribute("Title", c[1])
		tag(view, "CCTV")
		table.insert(map.Cameras, { Index = i, Title = c[1], View = view })
	end
end

-------------------------------------------------------------------------------
-- Точки для покупателей и монстра
-------------------------------------------------------------------------------
local function buildNavigation(map)
	local nodes, edges = {}, {}
	local function node(key, x, z)
		nodes[key] = Vector3.new(x, 0, z)
	end
	for i, x in ipairs(AISLE_X) do
		node("B" .. i, x, -4)
		node("M" .. i, x, 10)
		node("F" .. i, x, 24)
		table.insert(edges, { "B" .. i, "M" .. i })
		table.insert(edges, { "M" .. i, "F" .. i })
		if i > 1 then
			table.insert(edges, { "B" .. (i - 1), "B" .. i })
			table.insert(edges, { "F" .. (i - 1), "F" .. i })
		end
	end
	node("EntranceIn", -52, 45)
	node("EntranceOut", -52, 60)
	table.insert(edges, { "EntranceIn", "F1" })
	table.insert(edges, { "EntranceIn", "F2" })
	table.insert(edges, { "EntranceIn", "EntranceOut" })
	-- Выход за кассами
	-- проходы за кассами (сторона покупателей каждой кассы)
	local frontX = ModelKit.HasAsset("Checkout") and { -44, -20.6, -4.6, 11.4, 27.4 } or { -44, -27.4, -11.4, 4.6, 20.6 }
	for k, x in ipairs(frontX) do
		node("X" .. k, x, 45)
		if k == 1 then
			table.insert(edges, { "X1", "EntranceIn" })
		else
			table.insert(edges, { "X" .. (k - 1), "X" .. k })
		end
	end
	map.Nav = { Nodes = nodes, Edges = edges }

	-- Точки, где может стоять Покупатель (CFrame: позиция + направление взгляда)
	local function spot(x, z, lx, lz)
		return CFrame.lookAt(Vector3.new(x, 0, z), Vector3.new(lx, 0, lz))
	end
	map.MonsterSpots = {
		spot(-27.5, -5, -27.5, 30), -- конец ряда 3
		spot(20, -6.5, 20, 30), -- у холодильников
		spot(-50, -36, -50, 0), -- между стеллажами склада
		spot(-14, -60, -14, -10), -- служебный коридор у заднего выхода
		spot(-20, 64, -20, 40), -- на парковке, смотрит в витрину
		spot(4, -31, 0, -15), -- за креслом охранника
		spot(35, -15, 26, -25), -- в углу комнаты персонала
		spot(20.6, 35.8, 20.6, 40), -- в очереди на кассу №4, которая не работает
		spot(-6, -60, 0, -44), -- в холодильной камере
		spot(-14, -84, -14, -60), -- во дворе под фонарём
		spot(32, -60, 26, -45), -- в тёмном кабинете
		spot(-57.5, 18, -57.5, 30), -- у хлебного стеллажа
	}
	-- Узлы для перемещения монстра по всему магазину
	local mn = {}
	for _, v in pairs(nodes) do
		table.insert(mn, v)
	end
	for _, p in ipairs({
		{ -57.5, -20 }, { -57.5, -40 }, { -57.5, -56 }, { -45, -20 }, { -45, -40 }, { -45, -56 }, { -30, -20 }, { -28, -34 }, { -28, -50 }, { -24, -58 },
		{ -14, -18 }, { -14, -30 }, { -14, -44 }, { -14, -58 },
		{ -4, -37 }, { 10, -37 }, { 20, -37 }, { 34, -37 },
		{ -6, -20 }, { 8, -28 }, { 16, -28 }, { 36, -16 }, { 36, -30 },
		{ -6, -46 }, { 6, -56 }, { -6, -60 }, { 16, -46 }, { 36, -50 }, { 16, -60 },
		{ -30, -80 }, { 0, -86 }, { -14, -84 },
		{ -20, 64 }, { 10, 70 }, { -60, 66 },
		{ -60, 35 }, { -38, 35 }, { 34, 45 }, { 34, 26 }, { -62, -6 }, { 34, -6 },
	}) do
		table.insert(mn, Vector3.new(p[1], 0, p[2]))
	end
	map.MonsterNodes = mn

	-- Где может появиться пролитая жидкость
	map.SpillSpots = {}
	for _, x in ipairs(AISLE_X) do
		for _, z in ipairs({ 4, 13 }) do
			table.insert(map.SpillSpots, Vector3.new(x + rng:NextNumber(-2, 2), 0, z + rng:NextNumber(-2, 2)))
		end
	end
	for _, p in ipairs({ { -40, -4 }, { 0, -4 }, { 25, -4 }, { -50, 24 }, { 0, 24 }, { 30, 30 } }) do
		table.insert(map.SpillSpots, Vector3.new(p[1], 0, p[2]))
	end
end

-------------------------------------------------------------------------------
function MapBuilder.Build()
	local old = workspace:FindFirstChild("Store")
	if old then
		old:Destroy()
	end
	local root = Instance.new("Folder")
	root.Name = "Store"
	-- 3D-модели полок и продуктов (если не загрузятся — магазин соберётся из простых деталей)
	ModelKit.Load(25)
	local map = { Root = root, Points = {}, Stations = {}, Clues = {} }
	buildShell(root, map)
	buildFront(root, map)
	buildSalesFloor(root, map)
	buildFridges(root, map)
	buildLanes(root, map)
	buildWarehouse(root, map)
	buildCorridors(root, map)
	buildRooms(root, map)
	buildAlley(root, map)
	buildDoors(root, map)
	buildCameras(root, map)
	buildNavigation(map)
	map.Points.StaffSpawn = Vector3.new(33, 3, -18)
	map.Points.CaughtWake = Vector3.new(26, 3, -29)
	root.Parent = workspace
	-- Динамические объекты систем (покупатели, товары на ленте, лужи…) складываем сюда
	local dyn = Instance.new("Folder")
	dyn.Name = "Dynamic"
	dyn.Parent = workspace
	map.Dynamic = dyn
	return map
end

return MapBuilder
