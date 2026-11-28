-- MapKit: строительные блоки карт DUMMY COMBAT. Карты собираются кодом при начале матча
-- (MapSystem): так у каждой карты одна точка правды, её легко менять и проверять.
--
-- local b = MapKit.new(folder)      — всё создаётся в folder (Model), закреплено (Anchored)
-- b:Group("Имя") / b:EndGroup()     — вложенная модель для порядка
-- b:Box(размер, CFrame, материал, цвет, свойства)  — деталь
-- готовые вещи: Container, Crate, Barrel, Pallet, Barrier, Stairs, Catwalk, Rail, Lamp, Pipe, Tank, Truck,
-- Building (коробка со стенами, проёмами, крышей), Wall; Ramp, Glass, Tree, Car, Sandbags, Bench, Planter,
-- Dumpster, Slab, Column; Spawn — точка появления (на полу, лицом по look).
-- Координаты: Y вверх, пол карты — y = 0 (Floor), 1 stud ≈ 0,3 м (манекен — 5,6).
local MapKit = {}
MapKit.__index = MapKit

local M = Enum.Material

MapKit.Colors = table.freeze({
	Concrete = Color3.fromRGB(150, 148, 142),
	ConcreteDark = Color3.fromRGB(104, 104, 100),
	Asphalt = Color3.fromRGB(58, 60, 62),
	Steel = Color3.fromRGB(96, 100, 104),
	SteelDark = Color3.fromRGB(58, 61, 64),
	Rust = Color3.fromRGB(122, 74, 46),
	Yellow = Color3.fromRGB(214, 172, 52),
	Wood = Color3.fromRGB(150, 112, 70),
	WoodDark = Color3.fromRGB(102, 74, 46),
	Brick = Color3.fromRGB(128, 68, 52),
	White = Color3.fromRGB(214, 214, 208),
	Black = Color3.fromRGB(28, 29, 31),
	ContainerRed = Color3.fromRGB(150, 52, 40),
	ContainerBlue = Color3.fromRGB(44, 82, 130),
	ContainerGreen = Color3.fromRGB(58, 102, 70),
	ContainerOrange = Color3.fromRGB(196, 104, 40),
	ContainerGrey = Color3.fromRGB(120, 124, 128),
})
local C = MapKit.Colors

function MapKit.new(folder)
	local self = setmetatable({}, MapKit)
	self.Root = folder
	self.Parent = folder
	self.Stack = {}
	self.Spawns = {}
	self.TeamSpawns = { Red = {}, Blue = {} }
	self.Parts = 0
	return self
end

function MapKit:Group(name)
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = self.Parent
	table.insert(self.Stack, self.Parent)
	self.Parent = m
	return m
end

function MapKit:EndGroup()
	self.Parent = table.remove(self.Stack) or self.Root
end

function MapKit:Box(size, cf, material, color, props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Material = material or M.Concrete
	p.Color = color or C.Concrete
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanTouch = false
	if props then
		for k, v in pairs(props) do
			p[k] = v
		end
	end
	p.Parent = self.Parent
	self.Parts = self.Parts + 1
	return p
end

function MapKit:Wedge(size, cf, material, color)
	local p = Instance.new("WedgePart")
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Material = material or M.Concrete
	p.Color = color or C.Concrete
	p.CanTouch = false
	p.Parent = self.Parent
	self.Parts = self.Parts + 1
	return p
end

function MapKit:Cylinder(length, diameter, cf, material, color, props)
	-- ось цилиндра Roblox — X: поворачиваем, чтобы длина шла вдоль Y у cf
	local p = self:Box(Vector3.new(length, diameter, diameter), cf * CFrame.Angles(0, 0, math.pi / 2), material, color, props)
	p.Shape = Enum.PartType.Cylinder
	return p
end

-- Невидимая стена (граница карты): не видна, лучи проходят, персонажи упираются
function MapKit:Invisible(size, cf)
	return self:Box(size, cf, M.SmoothPlastic, C.White, { Transparency = 1, CanQuery = false, CastShadow = false, Name = "Boundary" })
end

-- Точка появления: pos — на полу, look — куда смотреть; team — "Red" / "Blue" (для командных режимов)
function MapKit:Spawn(pos, look, team)
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 1e-3 then
		flat = Vector3.new(0, 0, -1)
	end
	local cf = CFrame.lookAt(pos, pos + flat.Unit)
	table.insert(self.Spawns, cf)
	if team then
		table.insert(self.TeamSpawns[team], cf)
	end
	return cf
end

-------------------------------------------------------------------------------
-- Вещи
-------------------------------------------------------------------------------
-- 20-футовый морской контейнер (19 × 8.1 × 7.6), стоит на полу в cf (низ — в cf.Y), длина вдоль X.
-- open = true — торец (+X) открыт, внутри можно пройти
function MapKit:Container(cf, color, open)
	local L, H, W = 19, 8.1, 7.6
	self:Group("Container")
	local base = cf * CFrame.new(0, H / 2, 0)
	local t = 0.25
	local metal = M.CorrodedMetal
	-- стенки и крыша
	self:Box(Vector3.new(L, t, W), base * CFrame.new(0, H / 2 - t / 2, 0), metal, color)
	self:Box(Vector3.new(L, 0.4, W), base * CFrame.new(0, -H / 2 + 0.2, 0), M.Metal, C.SteelDark)
	for _, s in ipairs({ -1, 1 }) do
		self:Box(Vector3.new(L, H - 0.6, t), base * CFrame.new(0, 0.1, s * (W / 2 - t / 2)), metal, color)
		-- гофра: вертикальные рёбра снаружи
		for i = 0, 12 do
			local x = -L / 2 + 0.9 + i * ((L - 1.8) / 12)
			self:Box(Vector3.new(0.35, H - 1.2, 0.18), base * CFrame.new(x, 0.05, s * (W / 2 + 0.05)), metal, color, { CastShadow = false })
		end
	end
	-- угловые стойки и рамы
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			self:Box(Vector3.new(0.5, H, 0.5), base * CFrame.new(sx * (L / 2 - 0.25), 0, sz * (W / 2 - 0.25)), M.Metal, C.SteelDark)
		end
	end
	-- задний торец (−X) глухой, с дверями
	self:Box(Vector3.new(t, H - 0.6, W - 0.6), base * CFrame.new(-L / 2 + t / 2, 0.1, 0), metal, color)
	self:Box(Vector3.new(0.12, H - 1.4, 0.12), base * CFrame.new(-L / 2 - 0.05, 0, 0), M.Metal, C.SteelDark)
	if not open then
		self:Box(Vector3.new(t, H - 0.6, W - 0.6), base * CFrame.new(L / 2 - t / 2, 0.1, 0), metal, color)
		for _, z in ipairs({ -1.2, 1.2 }) do
			self:Box(Vector3.new(0.12, H - 1.4, 0.1), base * CFrame.new(L / 2 + 0.05, 0, z), M.Metal, C.SteelDark)
		end
	else
		-- открытые створки, развернутые к стенам
		for _, sz in ipairs({ -1, 1 }) do
			self:Box(Vector3.new(0.2, H - 0.8, W / 2 - 0.3), base * CFrame.new(L / 2 + W / 4, 0.1, sz * (W / 2 + 0.15)) * CFrame.Angles(0, math.pi / 2, 0), metal, color)
		end
	end
	self:EndGroup()
end

-- Деревянный ящик size (обвязка из досок по рёбрам)
function MapKit:Crate(cf, size)
	size = size or Vector3.new(4, 4, 4)
	self:Group("Crate")
	local base = cf * CFrame.new(0, size.Y / 2, 0)
	self:Box(size - Vector3.new(0.2, 0.2, 0.2), base, M.WoodPlanks, C.Wood)
	local e = 0.35
	for _, sy in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			self:Box(Vector3.new(size.X, e, e), base * CFrame.new(0, sy * (size.Y / 2 - e / 2), sz * (size.Z / 2 - e / 2)), M.Wood, C.WoodDark)
		end
		for _, sx in ipairs({ -1, 1 }) do
			self:Box(Vector3.new(e, e, size.Z), base * CFrame.new(sx * (size.X / 2 - e / 2), sy * (size.Y / 2 - e / 2), 0), M.Wood, C.WoodDark)
		end
	end
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			self:Box(Vector3.new(e, size.Y, e), base * CFrame.new(sx * (size.X / 2 - e / 2), 0, sz * (size.Z / 2 - e / 2)), M.Wood, C.WoodDark)
		end
	end
	self:EndGroup()
end

-- Бочка 200 л (высота 2.9, диаметр 1.9) с обручами
function MapKit:Barrel(cf, color)
	self:Group("Barrel")
	local base = cf * CFrame.new(0, 1.45, 0)
	self:Cylinder(2.9, 1.9, base, M.Metal, color or C.ContainerBlue)
	for _, y in ipairs({ -0.95, 0, 0.95 }) do
		self:Cylinder(0.12, 1.98, base * CFrame.new(0, y, 0), M.Metal, C.SteelDark, { CastShadow = false })
	end
	self:Cylinder(0.05, 1.7, base * CFrame.new(0, 1.46, 0), M.Metal, C.SteelDark, { CastShadow = false })
	self:EndGroup()
end

function MapKit:Pallet(cf, load)
	self:Group("Pallet")
	local base = cf * CFrame.new(0, 0.2, 0)
	for _, z in ipairs({ -1.4, 0, 1.4 }) do
		self:Box(Vector3.new(3.8, 0.4, 0.4), base * CFrame.new(0, 0, z), M.Wood, C.Wood)
	end
	for i = -2, 2 do
		self:Box(Vector3.new(0.6, 0.12, 3.6), base * CFrame.new(i * 0.8, 0.26, 0), M.Wood, C.Wood)
	end
	if load then
		self:Box(Vector3.new(3.4, load, 3.2), base * CFrame.new(0, 0.32 + load / 2, 0), M.Fabric, Color3.fromRGB(176, 166, 140))
	end
	self:EndGroup()
end

-- Бетонный блок «нью-джерси» длиной length (вдоль X), высота 2.7
function MapKit:Barrier(cf, length, color)
	length = length or 8
	color = color or C.Concrete
	self:Group("Barrier")
	local base = cf * CFrame.new(0, 0, 0)
	self:Box(Vector3.new(length, 0.9, 2.2), base * CFrame.new(0, 0.45, 0), M.Concrete, color)
	self:Box(Vector3.new(length, 1.8, 0.8), base * CFrame.new(0, 1.8, 0), M.Concrete, color)
	-- скосы: вертикальная грань клина — к середине, наклонная — наружу
	for _, s in ipairs({ -1, 1 }) do
		self:Wedge(Vector3.new(length, 1.0, 0.7), base * CFrame.new(0, 1.4, s * 0.75) * CFrame.Angles(0, s > 0 and math.pi or 0, 0), M.Concrete, color)
	end
	self:EndGroup()
end

-- Лестница: низ — в cf (центр нижней ступени на полу), поднимается вдоль −Z cf на height за depth
function MapKit:Stairs(cf, width, height, depth, material, color)
	local steps = math.max(2, math.ceil(height / 0.75))
	local rise, run = height / steps, depth / steps
	self:Group("Stairs")
	for i = 1, steps do
		local h = rise * i
		self:Box(Vector3.new(width, h, run), cf * CFrame.new(0, h / 2, -run * (i - 0.5)), material or M.Concrete, color or C.ConcreteDark)
	end
	self:EndGroup()
end

-- Перила между точками a и b (на высоте пола y): стойки и поручень
function MapKit:Rail(a, b, color)
	local d = b - a
	local len = d.Magnitude
	if len < 0.5 then
		return
	end
	local mid = (a + b) / 2
	local cf = CFrame.lookAt(mid, b)
	self:Box(Vector3.new(0.2, 0.2, len), cf * CFrame.new(0, 3.4, 0), M.Metal, color or C.Yellow, { CastShadow = false })
	self:Box(Vector3.new(0.14, 0.14, len), cf * CFrame.new(0, 1.8, 0), M.Metal, color or C.Yellow, { CastShadow = false })
	local n = math.max(1, math.floor(len / 5))
	for i = 0, n do
		local p = a + d * (i / n)
		self:Box(Vector3.new(0.2, 3.5, 0.2), CFrame.new(p + Vector3.new(0, 1.75, 0)), M.Metal, color or C.Yellow, { CastShadow = false })
	end
end

-- Мостки (рифлёный металл) от a до b на высоте a.Y, шириной width, с перилами с двух сторон
function MapKit:Catwalk(a, b, width, rails)
	local d = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
	local len = d.Magnitude
	local mid = (a + b) / 2
	local cf = CFrame.lookAt(mid, mid + d.Unit)
	self:Group("Catwalk")
	self:Box(Vector3.new(width, 0.5, len), cf * CFrame.new(0, -0.25, 0), M.DiamondPlate, C.Steel)
	self:Box(Vector3.new(0.4, 0.8, len), cf * CFrame.new(-width / 2 + 0.2, -0.65, 0), M.Metal, C.SteelDark)
	self:Box(Vector3.new(0.4, 0.8, len), cf * CFrame.new(width / 2 - 0.2, -0.65, 0), M.Metal, C.SteelDark)
	if rails ~= false then
		local r = cf.RightVector * (width / 2 - 0.1)
		self:Rail(a + r, b + r)
		self:Rail(a - r, b - r)
	end
	self:EndGroup()
end

-- Опора (стойка) от пола до высоты h
function MapKit:Post(pos, h, size, color)
	size = size or 0.8
	return self:Box(Vector3.new(size, h, size), CFrame.new(pos + Vector3.new(0, h / 2, 0)), M.Metal, color or C.SteelDark)
end

-- Светильник: плафон и свет вниз (SpotLight), тёплый или холодный
function MapKit:Lamp(pos, color, brightness, range, angle)
	self:Group("Lamp")
	local housing = self:Box(Vector3.new(2.2, 0.5, 1.2), CFrame.new(pos), M.Metal, C.SteelDark, { CastShadow = false })
	local glow = self:Box(Vector3.new(1.9, 0.08, 0.9), CFrame.new(pos - Vector3.new(0, 0.28, 0)), M.SmoothPlastic, Color3.fromRGB(255, 244, 220), { CastShadow = false })
	glow.Transparency = 0.1
	local light = Instance.new("SpotLight")
	light.Face = Enum.NormalId.Bottom
	light.Color = color or Color3.fromRGB(255, 226, 180)
	light.Brightness = brightness or 2.2
	light.Range = range or 36
	light.Angle = angle or 100
	light.Shadows = true
	light.Parent = housing
	self:EndGroup()
	return housing
end

-- Труба от a до b, диаметр d
function MapKit:Pipe(a, b, d, color)
	local len = (b - a).Magnitude
	local cf = CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(math.pi / 2, 0, 0)
	local p = self:Cylinder(len, d, cf, M.Metal, color or C.Steel)
	return p
end

-- Резервуар (цилиндр с лестницей-кольцами), низ в pos
function MapKit:Tank(pos, radius, height, color)
	self:Group("Tank")
	local base = CFrame.new(pos + Vector3.new(0, height / 2, 0))
	self:Cylinder(height, radius * 2, base, M.Metal, color or C.White)
	self:Cylinder(0.6, radius * 2 + 0.3, base * CFrame.new(0, height / 2 - 0.3, 0), M.Metal, C.SteelDark)
	self:Cylinder(0.8, radius * 2 + 0.4, CFrame.new(pos + Vector3.new(0, 0.4, 0)), M.Concrete, C.ConcreteDark)
	for i = 1, 3 do
		self:Cylinder(0.25, radius * 2 + 0.15, base * CFrame.new(0, -height / 2 + i * height / 4, 0), M.Metal, C.Steel, { CastShadow = false })
	end
	self:EndGroup()
end

-- Грузовик с фургоном: cf — центр на полу, длина вдоль −Z (кабина спереди)
function MapKit:Truck(cf, color)
	self:Group("Truck")
	local body = color or C.White
	-- рама и колёса
	self:Box(Vector3.new(6.6, 1.2, 26), cf * CFrame.new(0, 2.2, 0), M.Metal, C.Black)
	for _, z in ipairs({ -9.5, 5, 8.6 }) do
		for _, x in ipairs({ -3.1, 3.1 }) do
			self:Cylinder(1.4, 3.4, cf * CFrame.new(x, 1.7, z) * CFrame.Angles(0, 0, math.pi / 2), M.Rubber, C.Black)
		end
	end
	-- кабина
	self:Box(Vector3.new(7.4, 6.2, 6.4), cf * CFrame.new(0, 5.7, -9.6), M.Metal, body)
	self:Box(Vector3.new(7.0, 2.3, 0.2), cf * CFrame.new(0, 7.0, -12.85), M.Glass, Color3.fromRGB(60, 72, 80), { Transparency = 0.25 })
	self:Box(Vector3.new(7.6, 1.0, 0.6), cf * CFrame.new(0, 3.2, -12.9), M.Metal, C.SteelDark)
	-- фургон
	self:Box(Vector3.new(7.8, 8.6, 18.4), cf * CFrame.new(0, 7.5, 3.6), M.Metal, body)
	self:Box(Vector3.new(7.9, 0.3, 18.5), cf * CFrame.new(0, 3.3, 3.6), M.Metal, C.SteelDark)
	self:EndGroup()
end

-- Здание-коробка: cf — центр пола, size (X ширина, Y высота, Z глубина); стены толщиной t; openings —
-- проёмы { Side = "N"|"S"|"E"|"W", Offset = вдоль стены, Width, Height, Sill (низ проёма) };
-- roof = true — крыша (с фермами); mat/color — стены
function MapKit:Building(cf, size, openings, opts)
	opts = opts or {}
	local t = opts.Thickness or 1.2
	local mat = opts.Material or M.Concrete
	local color = opts.Color or C.Concrete
	self:Group(opts.Name or "Building")
	local W, H, D = size.X, size.Y, size.Z
	-- стороны: N (−Z), S (+Z), W (−X), E (+X); у каждой — локальная ось вдоль стены
	local sides = {
		N = { Center = CFrame.new(0, 0, -D / 2 + t / 2), Len = W, Axis = 1 },
		S = { Center = CFrame.new(0, 0, D / 2 - t / 2), Len = W, Axis = 1 },
		W = { Center = CFrame.new(-W / 2 + t / 2, 0, 0), Len = D - 2 * t, Axis = 3 },
		E = { Center = CFrame.new(W / 2 - t / 2, 0, 0), Len = D - 2 * t, Axis = 3 },
	}
	for name, side in pairs(sides) do
		local holes = {}
		for _, o in ipairs(openings or {}) do
			if o.Side == name then
				table.insert(holes, o)
			end
		end
		table.sort(holes, function(a, b)
			return a.Offset < b.Offset
		end)
		-- стена кусками между проёмами + перемычки над/под проёмами
		local function piece(u0, u1, y0, y1)
			if u1 - u0 < 0.05 or y1 - y0 < 0.05 then
				return
			end
			local u = (u0 + u1) / 2
			local sz, off
			if side.Axis == 1 then
				sz, off = Vector3.new(u1 - u0, y1 - y0, t), Vector3.new(u, (y0 + y1) / 2, 0)
			else
				sz, off = Vector3.new(t, y1 - y0, u1 - u0), Vector3.new(0, (y0 + y1) / 2, u)
			end
			self:Box(sz, cf * side.Center * CFrame.new(off), mat, color)
		end
		local u = -side.Len / 2
		for _, o in ipairs(holes) do
			local a, b = o.Offset - o.Width / 2, o.Offset + o.Width / 2
			piece(u, a, 0, H)
			piece(a, b, o.Height + (o.Sill or 0), H)
			piece(a, b, 0, o.Sill or 0)
			u = b
		end
		piece(u, side.Len / 2, 0, H)
	end
	if opts.Floor ~= false then
		self:Box(Vector3.new(W, 0.4, D), cf * CFrame.new(0, 0.2, 0), opts.FloorMaterial or M.Concrete, opts.FloorColor or C.ConcreteDark)
	end
	if opts.Roof ~= false then
		self:Box(Vector3.new(W + 1, 0.8, D + 1), cf * CFrame.new(0, H + 0.4, 0), opts.RoofMaterial or M.CorrodedMetal, opts.RoofColor or C.Steel)
		-- фермы под крышей
		local n = math.floor(W / 12)
		for i = 1, n do
			local x = -W / 2 + i * (W / (n + 1))
			self:Box(Vector3.new(0.6, 1.4, D - 2 * t), cf * CFrame.new(x, H - 0.7, 0), M.Metal, C.SteelDark, { CastShadow = false })
		end
	end
	self:EndGroup()
end

-- Забор из бетонных плит от a до b, высотой h
function MapKit:Wall(a, b, h, t, mat, color)
	local d = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
	local mid = Vector3.new((a.X + b.X) / 2, a.Y + h / 2, (a.Z + b.Z) / 2)
	return self:Box(Vector3.new(t or 1.5, h, d.Magnitude), CFrame.lookAt(mid, mid + d), mat or M.Concrete, color or C.Concrete)
end

-- Граница: невидимые стены по прямоугольнику (центр, размер), высотой h
function MapKit:Bounds(center, size, h)
	h = h or 80
	local hx, hz = size.X / 2, size.Z / 2
	self:Group("Bounds")
	self:Invisible(Vector3.new(size.X + 4, h, 2), CFrame.new(center + Vector3.new(0, h / 2, -hz - 1)))
	self:Invisible(Vector3.new(size.X + 4, h, 2), CFrame.new(center + Vector3.new(0, h / 2, hz + 1)))
	self:Invisible(Vector3.new(2, h, size.Z + 4), CFrame.new(center + Vector3.new(-hx - 1, h / 2, 0)))
	self:Invisible(Vector3.new(2, h, size.Z + 4), CFrame.new(center + Vector3.new(hx + 1, h / 2, 0)))
	self:Invisible(Vector3.new(size.X + 4, 2, size.Z + 4), CFrame.new(center + Vector3.new(0, h + 1, 0)))
	self:EndGroup()
end

-- Пандус от a (низ, центр нижнего края на полу a.Y) до b (верх, центр верхнего края на высоте b.Y), шириной width
function MapKit:Ramp(a, b, width, material, color)
	local d = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
	local h = b.Y - a.Y
	local mid = Vector3.new((a.X + b.X) / 2, a.Y + h / 2, (a.Z + b.Z) / 2)
	-- у WedgePart высокая сторона — локальная +Z: разворачиваем её к b
	return self:Wedge(Vector3.new(width, h, d.Magnitude), CFrame.lookAt(mid, mid - d), material, color)
end

-- Стекло окна: прозрачное, пули пролетают (CanQuery = false), персонажи упираются
function MapKit:Glass(size, cf)
	return self:Box(size, cf, M.Glass, Color3.fromRGB(150, 172, 184), { Transparency = 0.62, CanQuery = false, CastShadow = false, Reflectance = 0.08 })
end

-- Дерево: ствол и крона из нескольких шаров листвы, pos — на земле, h — высота
function MapKit:Tree(pos, h, seed)
	local rng = Random.new(seed or 1)
	self:Group("Tree")
	local trunkH = h * 0.55
	self:Cylinder(trunkH, 0.9, CFrame.new(pos + Vector3.new(0, trunkH / 2, 0)), M.Wood, C.WoodDark)
	local leaf = Color3.fromRGB(70 + rng:NextInteger(-8, 8), 94 + rng:NextInteger(-10, 10), 52)
	for i = 1, 5 do
		local r = h * rng:NextNumber(0.2, 0.28)
		local off = Vector3.new(rng:NextNumber(-1, 1) * h * 0.16, trunkH + rng:NextNumber(0.05, 0.35) * h, rng:NextNumber(-1, 1) * h * 0.16)
		local ball = self:Box(Vector3.new(r * 2, r * 1.7, r * 2), CFrame.new(pos + off), M.Grass, leaf, { CanQuery = i > 2 })
		ball.Shape = Enum.PartType.Ball
	end
	self:EndGroup()
end

-- Легковая машина: cf — центр на земле, длина вдоль −Z
function MapKit:Car(cf, color)
	self:Group("Car")
	self:Box(Vector3.new(6.2, 2.2, 14), cf * CFrame.new(0, 2.0, 0), M.SmoothPlastic, color, { Reflectance = 0.05 })
	self:Box(Vector3.new(5.6, 2.0, 7), cf * CFrame.new(0, 4.0, 0.8), M.SmoothPlastic, color)
	self:Glass(Vector3.new(5.7, 1.6, 0.2), cf * CFrame.new(0, 4.0, -2.75) * CFrame.Angles(-0.35, 0, 0))
	self:Glass(Vector3.new(5.7, 1.5, 0.2), cf * CFrame.new(0, 4.0, 4.35) * CFrame.Angles(0.3, 0, 0))
	self:Glass(Vector3.new(5.7, 1.3, 5.8), cf * CFrame.new(0, 4.1, 0.8))
	self:Box(Vector3.new(6.3, 0.6, 1.0), cf * CFrame.new(0, 1.3, -7.1), M.SmoothPlastic, C.Black)
	self:Box(Vector3.new(6.3, 0.6, 1.0), cf * CFrame.new(0, 1.3, 7.1), M.SmoothPlastic, C.Black)
	for _, w in ipairs({ { -2.9, -4.5 }, { 2.9, -4.5 }, { -2.9, 4.5 }, { 2.9, 4.5 } }) do
		local wheel = self:Box(Vector3.new(0.9, 2.4, 2.4), cf * CFrame.new(w[1], 1.2, w[2]), M.SmoothPlastic, C.Black)
		wheel.Shape = Enum.PartType.Cylinder
	end
	self:Box(Vector3.new(1.2, 0.4, 0.2), cf * CFrame.new(-2.2, 2.4, -7.05), M.Glass, Color3.fromRGB(236, 232, 214), { CastShadow = false })
	self:Box(Vector3.new(1.2, 0.4, 0.2), cf * CFrame.new(2.2, 2.4, -7.05), M.Glass, Color3.fromRGB(236, 232, 214), { CastShadow = false })
	self:Box(Vector3.new(1.0, 0.35, 0.2), cf * CFrame.new(-2.3, 2.4, 7.05), M.SmoothPlastic, Color3.fromRGB(120, 24, 20), { CastShadow = false })
	self:Box(Vector3.new(1.0, 0.35, 0.2), cf * CFrame.new(2.3, 2.4, 7.05), M.SmoothPlastic, Color3.fromRGB(120, 24, 20), { CastShadow = false })
	self:EndGroup()
end

-- Стенка из мешков с песком от a до b, рядов rows (ряд — 0.9 высотой), мешки вразбежку
function MapKit:Sandbags(a, b, rows)
	local d = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
	local len = d.Magnitude
	local cf = CFrame.lookAt(Vector3.new(a.X, a.Y, a.Z), Vector3.new(b.X, a.Y, b.Z))
	local color = Color3.fromRGB(150, 136, 104)
	self:Group("Sandbags")
	for r = 0, (rows or 3) - 1 do
		local n = math.max(1, math.floor(len / 2.1))
		local shift = (r % 2) * 1.05
		for i = 0, n - 1 do
			local z = -(shift + i * 2.1 + 1.05)
			if -z <= len then
				local bag = self:Box(Vector3.new(1.6, 0.95, 2.15), cf * CFrame.new(0, 0.48 + r * 0.9, z) * CFrame.Angles(0, (i % 3 - 1) * 0.04, 0), M.Fabric, color)
				bag.Shape = Enum.PartType.Block
			end
		end
	end
	self:EndGroup()
end

-- Скамейка: cf — центр на земле, длина вдоль X
function MapKit:Bench(cf)
	self:Group("Bench")
	self:Box(Vector3.new(6, 0.3, 1.6), cf * CFrame.new(0, 1.6, 0), M.Wood, C.Wood)
	self:Box(Vector3.new(6, 1.2, 0.25), cf * CFrame.new(0, 2.5, 0.75) * CFrame.Angles(-0.2, 0, 0), M.Wood, C.Wood)
	for _, x in ipairs({ -2.5, 2.5 }) do
		self:Box(Vector3.new(0.3, 1.6, 1.4), cf * CFrame.new(x, 0.8, 0), M.Metal, C.SteelDark)
	end
	self:EndGroup()
end

-- Клумба из бетона с землёй и кустом
function MapKit:Planter(cf, size)
	self:Group("Planter")
	self:Box(Vector3.new(size.X, 2.2, size.Z), cf * CFrame.new(0, 1.1, 0), M.Concrete, C.Concrete)
	self:Box(Vector3.new(size.X - 0.8, 0.2, size.Z - 0.8), cf * CFrame.new(0, 2.25, 0), M.Ground, Color3.fromRGB(84, 64, 44))
	local bush = self:Box(Vector3.new(size.X - 1.2, 2.4, size.Z - 1.2), cf * CFrame.new(0, 3.2, 0), M.Grass, Color3.fromRGB(74, 100, 56))
	bush.Shape = Enum.PartType.Ball
	self:EndGroup()
end

-- Мусорный контейнер: cf — центр на земле, длина вдоль X
function MapKit:Dumpster(cf, color)
	self:Group("Dumpster")
	self:Box(Vector3.new(7, 4.4, 4), cf * CFrame.new(0, 2.6, 0), M.Metal, color or C.ContainerGreen)
	self:Box(Vector3.new(7.2, 0.3, 4.3), cf * CFrame.new(0, 4.95, 0.1) * CFrame.Angles(0.08, 0, 0), M.Plastic, C.Black)
	for _, x in ipairs({ -3, 3 }) do
		for _, z in ipairs({ -1.5, 1.5 }) do
			self:Box(Vector3.new(0.5, 0.5, 0.5), cf * CFrame.new(x, 0.25, z), M.Metal, C.Black)
		end
	end
	self:EndGroup()
end

-- Плита перекрытия: верх — на высоте top, центр (x, z), размер size (X, толщина, Z)
function MapKit:Slab(center, size, top, material, color)
	return self:Box(size, CFrame.new(center.X, top - size.Y / 2, center.Z), material or M.Concrete, color or C.Concrete)
end

-- Колонна от y0 до y1 сечением w
function MapKit:Column(pos, y0, y1, w, material, color)
	return self:Box(Vector3.new(w, y1 - y0, w), CFrame.new(pos.X, (y0 + y1) / 2, pos.Z), material or M.Concrete, color or C.Concrete)
end

function MapKit:Result(extra)
	local r = { Spawns = self.Spawns, TeamSpawns = self.TeamSpawns, Parts = self.Parts }
	for k, v in pairs(extra or {}) do
		r[k] = v
	end
	return r
end

return MapKit
