-- CITY BLOCK: городской квартал (этап 9). 220 × 180 studs, пол — y = 0.
--
--   центр  — главная улица с запада на восток (две полосы, тротуары с бордюром), брошенный автобус, машины,
--            бетонные блоки и остановки;
--   восток — перекрёсток с поперечной улицей и сквер (деревья, клумбы, скамейки, киоск, фонтан);
--   север  — кафе, магазин (вход с улицы, чёрный ход во двор) и двухэтажный дом с окнами на улицу;
--            за ними — двор-переулок с мусорными баками и ящиками;
--   юг     — двухэтажный офис со стеклянным холлом и парковка с машинами и шлагбаумом.
-- Командные точки: красные — запад, синие — восток (сквер).
local MapKit = require(script.Parent:WaitForChild("MapKit"))

local M = Enum.Material

local Map = {
	Id = "CityBlock",
	DisplayName = "CITY BLOCK",
	Description = "Улица, магазины, офис, парковка и сквер",
	Size = Vector3.new(220, 0, 180),
	Lighting = {
		ClockTime = 10.6,
		Brightness = 2.1,
		Ambient = Color3.fromRGB(70, 72, 78),
		OutdoorAmbient = Color3.fromRGB(128, 130, 136),
		EnvironmentDiffuseScale = 0.7,
		EnvironmentSpecularScale = 0.5,
		Atmosphere = { Density = 0.3, Offset = 0.12, Haze = 2.0, Glare = 0.1, Color = Color3.fromRGB(188, 196, 206), Decay = Color3.fromRGB(104, 110, 120) },
		ColorCorrection = { Contrast = 0.06, Saturation = -0.1, Brightness = 0, TintColor = Color3.fromRGB(246, 249, 255) },
	},
}

local SIDEWALK = 0.5

function Map.Build(folder)
	local b = MapKit.new(folder)
	local C = MapKit.Colors
	local sidewalk = Color3.fromRGB(156, 154, 148)
	local curb = Color3.fromRGB(176, 174, 168)

	---------------------------------------------------------------------------
	-- Земля: улицы, тротуары, разметка
	---------------------------------------------------------------------------
	b:Group("Ground")
	b:Box(Vector3.new(230, 2, 190), CFrame.new(0, -1, 0), M.Asphalt, C.Asphalt)
	-- тротуары кварталов (приподняты на SIDEWALK): северо-запад, юго-запад, северо-восток, юго-восток
	local blocks = {
		{ -110, 44, 12, 90 },
		{ -110, 44, -90, -12 },
		{ 72, 110, 12, 90 },
		{ 72, 110, -90, -12 },
	}
	for _, r in ipairs(blocks) do
		local x0, x1, z0, z1 = r[1], r[2], r[3], r[4]
		b:Box(Vector3.new(x1 - x0, SIDEWALK, z1 - z0), CFrame.new((x0 + x1) / 2, SIDEWALK / 2, (z0 + z1) / 2), M.Concrete, sidewalk)
	end
	-- бордюры вдоль улиц
	b:Box(Vector3.new(154, SIDEWALK + 0.1, 0.6), CFrame.new(-33, (SIDEWALK + 0.1) / 2, 12.3), M.Concrete, curb)
	b:Box(Vector3.new(154, SIDEWALK + 0.1, 0.6), CFrame.new(-33, (SIDEWALK + 0.1) / 2, -12.3), M.Concrete, curb)
	b:Box(Vector3.new(38, SIDEWALK + 0.1, 0.6), CFrame.new(91, (SIDEWALK + 0.1) / 2, 12.3), M.Concrete, curb)
	b:Box(Vector3.new(38, SIDEWALK + 0.1, 0.6), CFrame.new(91, (SIDEWALK + 0.1) / 2, -12.3), M.Concrete, curb)
	for _, x in ipairs({ 43.7, 72.3 }) do
		b:Box(Vector3.new(0.6, SIDEWALK + 0.1, 78), CFrame.new(x, (SIDEWALK + 0.1) / 2, 51), M.Concrete, curb)
		b:Box(Vector3.new(0.6, SIDEWALK + 0.1, 78), CFrame.new(x, (SIDEWALK + 0.1) / 2, -51), M.Concrete, curb)
	end
	-- разметка: прерывистая осевая, стоп-линии, пешеходные переходы
	for x = -104, 40, 8 do
		b:Box(Vector3.new(4, 0.04, 0.35), CFrame.new(x, 0.02, 0), M.SmoothPlastic, C.White, { CastShadow = false })
	end
	for z = -84, 84, 8 do
		if math.abs(z) > 14 then
			b:Box(Vector3.new(0.35, 0.04, 4), CFrame.new(62, 0.02, z), M.SmoothPlastic, C.White, { CastShadow = false })
		end
	end
	for i = 0, 7 do
		b:Box(Vector3.new(1.6, 0.04, 6), CFrame.new(47 + i * 3, 0.02, 15.5), M.SmoothPlastic, C.White, { CastShadow = false })
		b:Box(Vector3.new(1.6, 0.04, 6), CFrame.new(47 + i * 3, 0.02, -15.5), M.SmoothPlastic, C.White, { CastShadow = false })
		b:Box(Vector3.new(6, 0.04, 1.6), CFrame.new(40.5, 0.02, -10.5 + i * 3), M.SmoothPlastic, C.White, { CastShadow = false })
	end
	b:EndGroup()

	-- граница: глухие стены по краю (как торцы соседних домов) и невидимая крыша
	b:Group("Perimeter")
	local wallH = 32
	b:Wall(Vector3.new(-110, 0, -90), Vector3.new(110, 0, -90), wallH, 2, M.Brick, Color3.fromRGB(118, 92, 80))
	b:Wall(Vector3.new(-110, 0, 90), Vector3.new(110, 0, 90), wallH, 2, M.Brick, Color3.fromRGB(118, 92, 80))
	b:Wall(Vector3.new(-110, 0, -90), Vector3.new(-110, 0, 90), wallH, 2, M.Brick, Color3.fromRGB(110, 86, 74))
	b:Wall(Vector3.new(110, 0, -90), Vector3.new(110, 0, 90), wallH, 2, M.Brick, Color3.fromRGB(110, 86, 74))
	-- концы улиц перекрыты: строительные заборы
	for _, z in ipairs({ -6, 0, 6 }) do
		b:Barrier(CFrame.new(-105, 0, z) * CFrame.Angles(0, math.pi / 2, 0), 6, C.White)
	end
	b:EndGroup()
	b:Bounds(Vector3.new(0, 0, 0), Vector3.new(218, 0, 178), 70)

	local y = SIDEWALK
	---------------------------------------------------------------------------
	-- Север: кафе, магазин, двухэтажный дом
	---------------------------------------------------------------------------
	-- кафе (x −100..−62): первый этаж открыт на улицу, верх — глухой фасад с окнами
	b:Building(CFrame.new(-81, y, 40), Vector3.new(38, 11, 40), {
		{ Side = "N", Offset = -8, Width = 7, Height = 8.5 },
		{ Side = "N", Offset = 6, Width = 14, Height = 6, Sill = 2.5 },
		{ Side = "S", Offset = 10, Width = 5, Height = 8.5 },
		{ Side = "E", Offset = -6, Width = 5, Height = 8.5 },
	}, { Name = "Cafe", Material = M.Brick, Color = Color3.fromRGB(140, 84, 62), RoofColor = C.ConcreteDark, RoofMaterial = M.Concrete })
	b:Glass(Vector3.new(14, 6, 0.3), CFrame.new(-75, y + 5.5, 20.6))
	b:Box(Vector3.new(38, 18, 40), CFrame.new(-81, y + 11.8 + 9, 40), M.Brick, Color3.fromRGB(140, 84, 62))
	b:Group("CafeInside")
	b:Box(Vector3.new(14, 3.6, 2.4), CFrame.new(-88, y + 1.8, 50), M.Wood, C.WoodDark)
	for i = 0, 2 do
		b:Box(Vector3.new(3, 0.3, 3), CFrame.new(-90 + i * 9, y + 2.9, 30), M.Wood, C.Wood)
		b:Box(Vector3.new(0.5, 2.9, 0.5), CFrame.new(-90 + i * 9, y + 1.45, 30), M.Metal, C.SteelDark)
	end
	b:Lamp(Vector3.new(-81, y + 10.4, 34), Color3.fromRGB(255, 220, 176), 1.2, 24)
	b:EndGroup()
	-- навесы над витринами (полосатые)
	b:Box(Vector3.new(24, 0.4, 4), CFrame.new(-78, y + 9.6, 18.4) * CFrame.Angles(0.25, 0, 0), M.Fabric, Color3.fromRGB(122, 48, 42))

	-- магазин (x −50..−12): витрина, полки, чёрный ход во двор
	b:Building(CFrame.new(-31, y, 42), Vector3.new(38, 11, 40), {
		{ Side = "N", Offset = 0, Width = 6, Height = 8.5 },
		{ Side = "N", Offset = -11, Width = 12, Height = 6, Sill = 2.5 },
		{ Side = "N", Offset = 11, Width = 12, Height = 6, Sill = 2.5 },
		{ Side = "S", Offset = -12, Width = 5, Height = 8.5 },
	}, { Name = "Store", Material = M.Concrete, Color = Color3.fromRGB(176, 170, 158), RoofColor = C.ConcreteDark, RoofMaterial = M.Concrete })
	b:Glass(Vector3.new(12, 6, 0.3), CFrame.new(-42, y + 5.5, 22.6))
	b:Glass(Vector3.new(12, 6, 0.3), CFrame.new(-20, y + 5.5, 22.6))
	b:Box(Vector3.new(38, 16, 40), CFrame.new(-31, y + 11.8 + 8, 42), M.Concrete, Color3.fromRGB(176, 170, 158))
	b:Box(Vector3.new(16, 2.4, 0.5), CFrame.new(-31, y + 13, 21.7), M.SmoothPlastic, Color3.fromRGB(44, 70, 96))
	b:Group("StoreInside")
	for i = 0, 2 do
		local x = -42 + i * 11
		b:Box(Vector3.new(2.2, 6, 14), CFrame.new(x, y + 3, 46), M.Metal, C.White)
		for k = 1, 3 do
			b:Box(Vector3.new(2.6, 0.2, 14), CFrame.new(x, y + k * 1.8, 46), M.Metal, C.Steel)
			b:Box(Vector3.new(1.8, 1.2, 13), CFrame.new(x, y + k * 1.8 + 0.7, 46), M.SmoothPlastic, Color3.fromRGB(150 + k * 20, 120, 90 + k * 15))
		end
	end
	b:Box(Vector3.new(8, 3.6, 2.4), CFrame.new(-20, y + 1.8, 30), M.Wood, C.White)
	b:Lamp(Vector3.new(-31, y + 10.4, 40), Color3.fromRGB(236, 244, 255), 1.3, 26)
	b:EndGroup()

	-- двухэтажный дом (x −6..40): вход с улицы, лестница, окна второго этажа на улицу и во двор
	local hx, hz = 17, 42
	b:Building(CFrame.new(hx, y, hz), Vector3.new(46, 21, 40), {
		{ Side = "N", Offset = -14, Width = 6, Height = 8.5 },
		{ Side = "N", Offset = 6, Width = 8, Height = 5, Sill = 3 },
		{ Side = "N", Offset = -12, Width = 6, Height = 4.5, Sill = 13.5 },
		{ Side = "N", Offset = 2, Width = 6, Height = 4.5, Sill = 13.5 },
		{ Side = "N", Offset = 14, Width = 6, Height = 4.5, Sill = 13.5 },
		{ Side = "S", Offset = 12, Width = 5, Height = 8.5 },
		{ Side = "S", Offset = -8, Width = 6, Height = 4.5, Sill = 13.5 },
		{ Side = "E", Offset = 0, Width = 6, Height = 4.5, Sill = 13.5 },
	}, { Name = "House", Material = M.Brick, Color = Color3.fromRGB(150, 98, 74), RoofColor = C.ConcreteDark, RoofMaterial = M.Concrete })
	b:Glass(Vector3.new(8, 5, 0.3), CFrame.new(hx + 6, y + 5.5, 22.6))
	b:Group("HouseInside")
	-- перекрытие второго этажа с проёмом под лестницу (x 26..36, z 46..58)
	local f2 = y + 10.5
	b:Slab(Vector3.new(10.5, 0, hz), Vector3.new(31, 1, 37.6), f2)
	b:Slab(Vector3.new(32.5, 0, 34.5), Vector3.new(13, 1, 23), f2)
	b:Slab(Vector3.new(32.5, 0, 59.8), Vector3.new(13, 1, 3.6), f2)
	b:Stairs(CFrame.new(31, y, 58) * CFrame.Angles(0, 0, 0), 6, 10, 12, M.Concrete, C.ConcreteDark)
	b:Rail(Vector3.new(25.7, f2, 46), Vector3.new(25.7, f2, 58))
	b:Box(Vector3.new(0.6, 9.8, 16), CFrame.new(10, y + 4.9, 50), M.Concrete, C.White)
	b:Box(Vector3.new(6, 3, 3), CFrame.new(0, f2 + 1.5, 30), M.Wood, C.WoodDark)
	b:Box(Vector3.new(3, 4, 6), CFrame.new(30, f2 + 2, 30), M.Wood, C.Wood)
	b:Lamp(Vector3.new(hx, y + 10, 40), Color3.fromRGB(255, 222, 180), 1.1, 22)
	b:Lamp(Vector3.new(hx, y + 20.4, 40), Color3.fromRGB(255, 222, 180), 1.1, 22)
	b:EndGroup()

	-- двор-переулок за домами (z 62..90): баки, ящики, поддоны, пожарная лестница
	b:Group("Alley")
	b:Dumpster(CFrame.new(-92, y, 70), C.ContainerGreen)
	b:Dumpster(CFrame.new(-60, y, 82), C.ContainerBlue)
	b:Dumpster(CFrame.new(-8, y, 72) * CFrame.Angles(0, 0.3, 0), C.ContainerGreen)
	b:Crate(CFrame.new(-40, y, 72), Vector3.new(4, 4, 4))
	b:Crate(CFrame.new(-36, y, 75), Vector3.new(3, 3, 3))
	b:Pallet(CFrame.new(-20, y, 82), 2)
	b:Pallet(CFrame.new(28, y, 78), 3)
	b:Barrel(CFrame.new(36, y, 70))
	b:Barrel(CFrame.new(38, y, 72.5), C.ContainerBlue)
	b:Crate(CFrame.new(-74, y, 84), Vector3.new(5, 3, 4))
	b:Lamp(Vector3.new(-50, y + 14, 66), Color3.fromRGB(255, 210, 150), 1.4, 30)
	b:Lamp(Vector3.new(10, y + 14, 66), Color3.fromRGB(255, 210, 150), 1.4, 30)
	b:EndGroup()

	---------------------------------------------------------------------------
	-- Юг: офис и парковка
	---------------------------------------------------------------------------
	local ox, oz = -66, -48
	b:Building(CFrame.new(ox, y, oz), Vector3.new(52, 21, 40), {
		{ Side = "S", Offset = -4, Width = 16, Height = 8.5 },
		{ Side = "S", Offset = -18, Width = 6, Height = 4.5, Sill = 13.5 },
		{ Side = "S", Offset = -4, Width = 8, Height = 4.5, Sill = 13.5 },
		{ Side = "S", Offset = 12, Width = 8, Height = 4.5, Sill = 13.5 },
		{ Side = "E", Offset = 8, Width = 6, Height = 8.5 },
		{ Side = "E", Offset = -8, Width = 8, Height = 4.5, Sill = 13.5 },
		{ Side = "W", Offset = 0, Width = 5, Height = 8.5 },
	}, { Name = "Office", Material = M.Concrete, Color = Color3.fromRGB(196, 194, 188), RoofColor = C.ConcreteDark, RoofMaterial = M.Concrete })
	b:Group("OfficeInside")
	local of2 = y + 10.5
	b:Slab(Vector3.new(ox + 4, 0, oz), Vector3.new(41.6, 1, 37.6), of2)
	b:Slab(Vector3.new(ox - 20.5, 0, oz - 7.4), Vector3.new(8.6, 1, 22.8), of2)
	b:Slab(Vector3.new(ox - 20.5, 0, oz + 17), Vector3.new(8.6, 1, 3.6), of2)
	b:Stairs(CFrame.new(ox - 20.5, y, oz + 15) * CFrame.Angles(0, 0, 0), 6, 10, 11, M.Concrete, C.ConcreteDark)
	b:Rail(Vector3.new(ox - 16.4, of2, oz + 4), Vector3.new(ox - 16.4, of2, oz + 15))
	-- холл: стойка, колонны, диваны; наверху — столы с перегородками
	b:Box(Vector3.new(10, 3.6, 2.4), CFrame.new(ox, y + 1.8, oz + 4), M.Wood, C.WoodDark)
	for _, x in ipairs({ -10, 10 }) do
		b:Column(Vector3.new(ox + x, 0, oz - 10), y, of2 - 1, 2, M.Concrete, C.White)
	end
	b:Box(Vector3.new(8, 2, 3), CFrame.new(ox + 14, y + 1, oz - 12), M.Fabric, Color3.fromRGB(70, 76, 84))
	for i = 0, 2 do
		for k = 0, 1 do
			local px, pz = ox - 8 + i * 12, oz - 10 + k * 14
			b:Box(Vector3.new(6, 0.3, 3), CFrame.new(px, of2 + 2.6, pz), M.Wood, C.White)
			b:Box(Vector3.new(6, 4.2, 0.3), CFrame.new(px, of2 + 2.1, pz + 1.8), M.Fabric, Color3.fromRGB(96, 104, 112))
		end
	end
	b:Lamp(Vector3.new(ox, y + 10, oz), Color3.fromRGB(236, 244, 255), 1.2, 28)
	b:Lamp(Vector3.new(ox, y + 20.4, oz), Color3.fromRGB(236, 244, 255), 1.2, 28)
	b:EndGroup()
	b:Glass(Vector3.new(10, 8.5, 0.3), CFrame.new(ox - 7, y + 4.25, oz + 20 - 0.6)) -- витрина холла, справа — вход

	b:Group("Parking")
	b:Box(Vector3.new(72, 0.06, 50), CFrame.new(4, y + 0.03, -54), M.Asphalt, Color3.fromRGB(66, 68, 70))
	for i = 0, 8 do
		b:Box(Vector3.new(0.3, 0.05, 12), CFrame.new(-28 + i * 8, y + 0.07, -76), M.SmoothPlastic, C.White, { CastShadow = false })
		b:Box(Vector3.new(0.3, 0.05, 12), CFrame.new(-28 + i * 8, y + 0.07, -34), M.SmoothPlastic, C.White, { CastShadow = false })
	end
	local cars = {
		{ -24, -76, Color3.fromRGB(150, 40, 36) }, { -8, -76, Color3.fromRGB(200, 200, 196) }, { 16, -76, Color3.fromRGB(40, 46, 56) },
		{ 32, -75, Color3.fromRGB(70, 90, 110) }, { -16, -34, Color3.fromRGB(88, 92, 96) }, { 8, -35, Color3.fromRGB(176, 160, 120) },
	}
	for i, c in ipairs(cars) do
		b:Car(CFrame.new(c[1], y, c[2]) * CFrame.Angles(0, (i % 2) * math.pi + (i == 3 and 0.12 or 0), 0), c[3])
	end
	-- будка охраны и шлагбаум
	b:Building(CFrame.new(36, y, -20 - 6), Vector3.new(6, 8, 6), {
		{ Side = "W", Offset = 0, Width = 3, Height = 7 },
		{ Side = "N", Offset = 0, Width = 4, Height = 2.5, Sill = 3.5 },
	}, { Name = "Booth", Material = M.Concrete, Color = C.White, Roof = true })
	b:Box(Vector3.new(14, 0.4, 0.4), CFrame.new(26, y + 3.2, -22), M.SmoothPlastic, Color3.fromRGB(210, 50, 40))
	b:Lamp(Vector3.new(-10, y + 16, -54), Color3.fromRGB(255, 214, 160), 1.4, 40)
	b:Lamp(Vector3.new(24, y + 16, -54), Color3.fromRGB(255, 214, 160), 1.4, 40)
	b:Post(Vector3.new(-10, y, -54), 16, 0.5, C.SteelDark)
	b:Post(Vector3.new(24, y, -54), 16, 0.5, C.SteelDark)
	b:EndGroup()

	---------------------------------------------------------------------------
	-- Улица: автобус, машины, блоки, остановки, светофоры
	---------------------------------------------------------------------------
	b:Group("Street")
	-- автобус поперёк полосы
	local bus = CFrame.new(-28, 0, -5) * CFrame.Angles(0, math.pi / 2 + 0.08, 0)
	b:Box(Vector3.new(8, 8.6, 34), bus * CFrame.new(0, 5.2, 0), M.SmoothPlastic, Color3.fromRGB(196, 186, 150))
	b:Box(Vector3.new(8.1, 2.6, 30), bus * CFrame.new(0, 6.6, 0.5), M.Glass, Color3.fromRGB(60, 72, 82), { Transparency = 0.15, CanQuery = true })
	b:Box(Vector3.new(8.2, 1.0, 34.2), bus * CFrame.new(0, 1.4, 0), M.SmoothPlastic, C.SteelDark)
	for _, z in ipairs({ -11, 10 }) do
		for _, x in ipairs({ -3.8, 3.8 }) do
			local w = b:Box(Vector3.new(1.2, 3.4, 3.4), bus * CFrame.new(x, 1.7, z), M.SmoothPlastic, C.Black)
			w.Shape = Enum.PartType.Cylinder
		end
	end
	-- машины на дороге
	b:Car(CFrame.new(10, 0, 6) * CFrame.Angles(0, math.pi / 2 - 0.2, 0), Color3.fromRGB(60, 64, 70))
	b:Car(CFrame.new(58, 0, -4) * CFrame.Angles(0, 0.6, 0), Color3.fromRGB(180, 176, 168))
	b:Car(CFrame.new(66, 0, 8) * CFrame.Angles(0, 2.3, 0), Color3.fromRGB(120, 34, 30))
	b:Car(CFrame.new(-70, 0, 6) * CFrame.Angles(0, -math.pi / 2, 0), Color3.fromRGB(46, 70, 52))
	b:Car(CFrame.new(64, 0, 44) * CFrame.Angles(0, 0.05, 0), Color3.fromRGB(150, 150, 146))
	b:Car(CFrame.new(58, 0, -52) * CFrame.Angles(0, math.pi + 0.1, 0), Color3.fromRGB(80, 60, 44))
	-- бетонные блоки (укрытия)
	b:Barrier(CFrame.new(-90, 0, -4), 8, C.White)
	b:Barrier(CFrame.new(-54, 0, 5) * CFrame.Angles(0, 0.3, 0), 8, C.White)
	b:Barrier(CFrame.new(-6, 0, -7), 8, C.White)
	b:Barrier(CFrame.new(28, 0, -2) * CFrame.Angles(0, -0.4, 0), 8, C.White)
	b:Barrier(CFrame.new(62, 0, 26) * CFrame.Angles(0, math.pi / 2, 0), 8, C.White)
	b:Barrier(CFrame.new(60, 0, -28) * CFrame.Angles(0, math.pi / 2 + 0.2, 0), 8, C.White)
	-- остановки
	for _, s in ipairs({ { -52, 16, 0 }, { 8, -16, math.pi } }) do
		local cf = CFrame.new(s[1], y, s[2]) * CFrame.Angles(0, s[3], 0)
		b:Box(Vector3.new(10, 0.4, 3.4), cf * CFrame.new(0, 8, 0.4), M.Metal, C.SteelDark)
		b:Glass(Vector3.new(10, 6.5, 0.2), cf * CFrame.new(0, 4.4, 2))
		b:Box(Vector3.new(0.3, 8, 0.3), cf * CFrame.new(-4.9, 4, 2), M.Metal, C.SteelDark)
		b:Box(Vector3.new(0.3, 8, 0.3), cf * CFrame.new(4.9, 4, 2), M.Metal, C.SteelDark)
		b:Bench(cf * CFrame.new(0, 0, 1))
	end
	-- светофоры на перекрёстке
	for _, p in ipairs({ Vector3.new(44, y, 13), Vector3.new(72, y, -13), Vector3.new(44, y, -13), Vector3.new(72, y, 13) }) do
		b:Post(p, 12, 0.5, C.SteelDark)
		b:Box(Vector3.new(1.2, 3.4, 1.2), CFrame.new(p + Vector3.new(0, 12.5, 0)), M.Metal, C.Black)
	end
	-- фонари вдоль улицы
	for x = -96, 36, 22 do
		for _, z in ipairs({ -18, 18 }) do
			local p = Vector3.new(x, y, z)
			b:Post(p, 15, 0.45, C.SteelDark)
			b:Box(Vector3.new(0.3, 0.3, 3), CFrame.new(p + Vector3.new(0, 15, -math.sign(z) * 1.4)), M.Metal, C.SteelDark)
			b:Lamp(p + Vector3.new(0, 14.7, -math.sign(z) * 2.8), Color3.fromRGB(255, 220, 170), 1.0, 34)
		end
	end
	b:EndGroup()

	---------------------------------------------------------------------------
	-- Восток: сквер
	---------------------------------------------------------------------------
	b:Group("Square")
	local grass = Color3.fromRGB(78, 104, 58)
	b:Box(Vector3.new(30, 0.2, 28), CFrame.new(92, y + 0.1, 50), M.Grass, grass)
	b:Box(Vector3.new(30, 0.2, 28), CFrame.new(92, y + 0.1, -50), M.Grass, grass)
	local trees = { Vector3.new(84, y, 40), Vector3.new(100, y, 58), Vector3.new(88, y, 74), Vector3.new(102, y, 30), Vector3.new(84, y, -40),
		Vector3.new(100, y, -60), Vector3.new(90, y, -76), Vector3.new(104, y, -34) }
	for i, p in ipairs(trees) do
		b:Tree(p, 18 + (i % 3) * 2, i)
	end
	b:Planter(CFrame.new(80, y, 22), Vector3.new(8, 0, 4))
	b:Planter(CFrame.new(100, y, -22), Vector3.new(8, 0, 4))
	b:Planter(CFrame.new(80, y, -24), Vector3.new(4, 0, 8))
	b:Bench(CFrame.new(94, y, 40))
	b:Bench(CFrame.new(92, y, -44) * CFrame.Angles(0, math.pi, 0))
	-- фонтан в центре восточной части дороги
	b:Cylinder(1.6, 16, CFrame.new(92, 0.8, 0), M.Concrete, C.Concrete)
	b:Cylinder(0.3, 13.6, CFrame.new(92, 1.65, 0), M.Glass, Color3.fromRGB(70, 104, 120), { Transparency = 0.3, CanCollide = false })
	b:Cylinder(4, 2.4, CFrame.new(92, 3.6, 0), M.Concrete, C.White)
	-- газетный киоск
	b:Building(CFrame.new(98, y, 76), Vector3.new(8, 8, 6), {
		{ Side = "W", Offset = 0, Width = 5, Height = 3, Sill = 3 },
	}, { Name = "Kiosk", Material = M.Metal, Color = Color3.fromRGB(60, 84, 70) })
	b:Lamp(Vector3.new(92, y + 14, 50), Color3.fromRGB(255, 220, 170), 1.0, 30)
	b:Post(Vector3.new(92, y, 50), 14, 0.45, C.SteelDark)
	b:Lamp(Vector3.new(92, y + 14, -50), Color3.fromRGB(255, 220, 170), 1.0, 30)
	b:Post(Vector3.new(92, y, -50), 14, 0.45, C.SteelDark)
	b:EndGroup()

	---------------------------------------------------------------------------
	-- Точки появления
	---------------------------------------------------------------------------
	local E, W, N, S = Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 0, -1), Vector3.new(0, 0, 1)
	for _, p in ipairs({ Vector3.new(-98, 0, -8), Vector3.new(-98, 0, 8), Vector3.new(-100, y, 70), Vector3.new(-86, y, 40),
		Vector3.new(-100, y, -30), Vector3.new(-76, y, -40), Vector3.new(-80, of2, -54), Vector3.new(-104, y, -80) }) do
		b:Spawn(p, E, "Red")
	end
	for _, p in ipairs({ Vector3.new(104, y, 46), Vector3.new(86, y, 60), Vector3.new(104, y, -46), Vector3.new(86, y, -66),
		Vector3.new(102, 0, 8), Vector3.new(102, 0, -8), Vector3.new(80, 0, 0), Vector3.new(104, y, 84) }) do
		b:Spawn(p, W, "Blue")
	end
	for _, sp in ipairs({ { Vector3.new(-30, y, 86), N }, { Vector3.new(20, f2, 40), S }, { Vector3.new(-31, y, 56), S },
		{ Vector3.new(0, y, -84), S }, { Vector3.new(40, y, -86), W }, { Vector3.new(-58, of2, -34), N }, { Vector3.new(62, 0, -84), N },
		{ Vector3.new(62, 0, 84), S } }) do
		b:Spawn(sp[1], sp[2])
	end
	return b:Result({ Center = Vector3.new(0, 0, 0) })
end

return Map
