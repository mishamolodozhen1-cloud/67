-- INDUSTRIAL ZONE: промзона (этап 6). 260 × 200 studs, пол — y = 0.
--
--   запад      — склад 64 × 80: стеллажи, антресоль со стороны севера (лестница), большие ворота на восток;
--   юго-запад  — двор с поддонами и ящиками, домик-контора с окнами;
--   центр      — двор контейнеров: пять рядов с проходами, часть в два яруса, часть открыта насквозь;
--   северо-восток — заводская этажерка: открытый второй этаж (лестница с юга), станки внизу;
--   восток     — резервуары и эстакада с трубами, бочки;
--   юг         — погрузочная рампа (высота 4.2) с пандусом и лестницами, у рампы два грузовика.
-- По краю — бетонный забор, выше — невидимая граница. Командные точки: красные — запад, синие — восток.
local MapKit = require(script.Parent:WaitForChild("MapKit"))

local M = Enum.Material

local Map = {
	Id = "IndustrialZone",
	DisplayName = "INDUSTRIAL ZONE",
	Description = "Склад, контейнеры, заводская этажерка и погрузочная рампа",
	Size = Vector3.new(260, 0, 200),
	Lighting = {
		ClockTime = 16.4,
		Brightness = 2.4,
		Ambient = Color3.fromRGB(62, 62, 68),
		OutdoorAmbient = Color3.fromRGB(122, 118, 112),
		EnvironmentDiffuseScale = 0.6,
		EnvironmentSpecularScale = 0.4,
		Atmosphere = { Density = 0.34, Offset = 0.1, Haze = 1.8, Glare = 0.2, Color = Color3.fromRGB(204, 194, 178), Decay = Color3.fromRGB(110, 104, 96) },
		ColorCorrection = { Contrast = 0.08, Saturation = -0.12, Brightness = 0, TintColor = Color3.fromRGB(255, 247, 238) },
	},
}

function Map.Build(folder)
	local b = MapKit.new(folder)
	local C = MapKit.Colors

	-- земля: асфальт, бетонные площадки, разметка
	b:Group("Ground")
	b:Box(Vector3.new(270, 2, 210), CFrame.new(0, -1, 0), M.Asphalt, C.Asphalt)
	b:Box(Vector3.new(104, 0.1, 120), CFrame.new(12, 0.05, -12), M.Concrete, Color3.fromRGB(132, 130, 124))
	b:Box(Vector3.new(50, 0.1, 50), CFrame.new(99, 0.05, -70), M.Concrete, C.ConcreteDark)
	for _, x in ipairs({ -48, -30, -12, 6, 24, 42, 60 }) do
		b:Box(Vector3.new(0.4, 0.06, 10), CFrame.new(x, 0.11, 60), M.SmoothPlastic, C.Yellow, { CastShadow = false })
	end
	b:Box(Vector3.new(120, 0.06, 0.5), CFrame.new(12, 0.11, 52), M.SmoothPlastic, C.Yellow, { CastShadow = false })
	b:EndGroup()

	-- забор по периметру и граница
	b:Group("Perimeter")
	local wallH = 18
	b:Wall(Vector3.new(-130, 0, -100), Vector3.new(130, 0, -100), wallH)
	b:Wall(Vector3.new(-130, 0, 100), Vector3.new(130, 0, 100), wallH)
	b:Wall(Vector3.new(-130, 0, -100), Vector3.new(-130, 0, 100), wallH)
	b:Wall(Vector3.new(130, 0, -100), Vector3.new(130, 0, 100), wallH)
	for x = -120, 120, 20 do
		b:Box(Vector3.new(2, wallH + 1, 2), CFrame.new(x, (wallH + 1) / 2, -100), M.Concrete, C.ConcreteDark)
		b:Box(Vector3.new(2, wallH + 1, 2), CFrame.new(x, (wallH + 1) / 2, 100), M.Concrete, C.ConcreteDark)
	end
	b:EndGroup()
	b:Bounds(Vector3.new(0, 0, 0), Vector3.new(258, 0, 198), 90)

	---------------------------------------------------------------------------
	-- Склад (запад)
	---------------------------------------------------------------------------
	local wh = CFrame.new(-88, 0, -20)
	b:Building(wh, Vector3.new(64, 24, 80), {
		{ Side = "E", Offset = -18, Width = 14, Height = 14 },
		{ Side = "E", Offset = 20, Width = 14, Height = 14 },
		{ Side = "S", Offset = -10, Width = 10, Height = 11 },
		{ Side = "N", Offset = 14, Width = 6, Height = 9 },
		{ Side = "S", Offset = 16, Width = 8, Height = 4, Sill = 8 },
		{ Side = "N", Offset = -12, Width = 10, Height = 4, Sill = 13 },
	}, { Name = "Warehouse", Material = M.Brick, Color = C.Brick, RoofColor = C.SteelDark })
	b:Group("WarehouseInside")
	-- антресоль у северной стены: x −118..−94, z −58..−38, высота пола 10
	b:Box(Vector3.new(24, 1, 20), CFrame.new(-106, 9.5, -48), M.DiamondPlate, C.Steel)
	for _, p in ipairs({ Vector3.new(-95, 0, -39), Vector3.new(-106, 0, -39), Vector3.new(-117, 0, -39) }) do
		b:Post(p, 9, 0.9)
	end
	b:Rail(Vector3.new(-118, 10, -38.4), Vector3.new(-100, 10, -38.4))
	b:Rail(Vector3.new(-94.4, 10, -58), Vector3.new(-94.4, 10, -38.4))
	b:Stairs(CFrame.new(-97, 0, -24), 5, 10, 14, M.Metal, C.SteelDark)
	b:Crate(CFrame.new(-112, 10, -52), Vector3.new(4, 4, 4))
	b:Crate(CFrame.new(-104, 10, -55), Vector3.new(5, 3, 4))
	-- стеллажи: два ряда вдоль Z, с ящиками на полках
	for _, x in ipairs({ -110, -80 }) do
		b:Group("Rack")
		for z = -12, 12, 12 do
			for _, sx in ipairs({ -1.8, 1.8 }) do
				for _, sz in ipairs({ -5.8, 5.8 }) do
					b:Post(Vector3.new(x + sx, 0, z + sz), 12, 0.45, C.ContainerOrange)
				end
			end
			for _, y in ipairs({ 0.3, 4.3, 8.3, 12 }) do
				b:Box(Vector3.new(4.2, 0.3, 12), CFrame.new(x, y, z), M.Metal, C.ContainerBlue)
			end
			b:Crate(CFrame.new(x, 0.45, z - 3), Vector3.new(3.2, 3.2, 3.6))
			b:Crate(CFrame.new(x, 4.45, z + 2.5), Vector3.new(3.2, 3.2, 4.5))
			b:Crate(CFrame.new(x, 8.45, z - 2), Vector3.new(3.2, 2.6, 4))
		end
		b:EndGroup()
	end
	b:Pallet(CFrame.new(-66, 0, -46), 2.4)
	b:Pallet(CFrame.new(-66, 0, -41), 1.6)
	b:Crate(CFrame.new(-72, 0, 4) * CFrame.Angles(0, 0.3, 0), Vector3.new(5, 5, 5))
	b:Crate(CFrame.new(-95, 0, 6), Vector3.new(4, 3, 6))
	b:Barrel(CFrame.new(-118, 0, 14), C.ContainerRed)
	b:Barrel(CFrame.new(-115.5, 0, 15), C.ContainerRed)
	b:Barrel(CFrame.new(-117, 0, 11.5), C.ContainerBlue)
	for _, z in ipairs({ -44, -16, 12 }) do
		for _, x in ipairs({ -104, -72 }) do
			b:Lamp(Vector3.new(x, 22.5, z), Color3.fromRGB(255, 232, 196), 2.2, 40)
		end
	end
	b:EndGroup()

	---------------------------------------------------------------------------
	-- Юго-запад: двор и контора
	---------------------------------------------------------------------------
	b:Building(CFrame.new(-100, 0, 62), Vector3.new(22, 11, 16), {
		{ Side = "N", Offset = -4, Width = 5, Height = 8 },
		{ Side = "E", Offset = 0, Width = 6, Height = 3, Sill = 3.5 },
		{ Side = "N", Offset = 5, Width = 6, Height = 3, Sill = 3.5 },
		{ Side = "W", Offset = 0, Width = 6, Height = 3, Sill = 3.5 },
	}, { Name = "Office", Material = M.Concrete, Color = C.White, RoofColor = C.SteelDark })
	b:Group("OfficeInside")
	b:Box(Vector3.new(6, 2.6, 2.4), CFrame.new(-104, 1.3, 64), M.Wood, C.WoodDark)
	b:Box(Vector3.new(1.5, 4.5, 6), CFrame.new(-90.5, 2.25, 64), M.Metal, C.Steel)
	b:EndGroup()
	b:Group("YardSW")
	b:Pallet(CFrame.new(-78, 0, 40), 3)
	b:Pallet(CFrame.new(-74, 0, 41) * CFrame.Angles(0, 0.4, 0), 1.2)
	b:Crate(CFrame.new(-84, 0, 80), Vector3.new(6, 5, 5))
	b:Crate(CFrame.new(-77, 0, 82) * CFrame.Angles(0, -0.3, 0), Vector3.new(4, 4, 4))
	b:Barrier(CFrame.new(-66, 0, 66) * CFrame.Angles(0, math.pi / 2, 0), 10)
	b:Barrier(CFrame.new(-112, 0, 34), 10)
	b:Container(CFrame.new(-70, 0, 88) * CFrame.Angles(0, 0.08, 0), C.ContainerGrey, false)
	b:EndGroup()

	---------------------------------------------------------------------------
	-- Двор контейнеров (центр)
	---------------------------------------------------------------------------
	b:Group("Containers")
	local colors = { C.ContainerRed, C.ContainerBlue, C.ContainerGreen, C.ContainerOrange, C.ContainerGrey }
	local rows = {
		{ Z = -62, Items = { { -30, true }, { -6 }, { 22, false, true }, { 48 } } },
		{ Z = -38, Items = { { -34 }, { -10, true }, { 16 }, { 44, false, true } } },
		{ Z = -14, Items = { { -26 }, { 2, false, true }, { 32 }, { 58, true } } },
		{ Z = 10, Items = { { -32 }, { -6 }, { 22, true }, { 50 } } },
		{ Z = 34, Items = { { -22, false, true }, { 8 }, { 38, true } } },
	}
	local k = 0
	for _, row in ipairs(rows) do
		for _, item in ipairs(row.Items) do
			k = k + 1
			local x, open, stacked = item[1], item[2], item[3]
			local yaw = ((k % 3) - 1) * 0.02
			local flip = (k % 2 == 0) and math.pi or 0
			local cf = CFrame.new(x, 0, row.Z) * CFrame.Angles(0, flip + yaw, 0)
			b:Container(cf, colors[(k % #colors) + 1], open)
			if stacked then
				b:Container(CFrame.new(x + 0.4, 8.1, row.Z) * CFrame.Angles(0, flip - yaw, 0), colors[((k + 2) % #colors) + 1], false)
			end
		end
	end
	-- укрытия в проходах
	b:Barrier(CFrame.new(5, 0, -50), 8)
	b:Barrier(CFrame.new(-18, 0, -26) * CFrame.Angles(0, math.pi / 2, 0), 8)
	b:Barrier(CFrame.new(30, 0, -2), 8)
	b:Barrier(CFrame.new(-16, 0, 22) * CFrame.Angles(0, 0.2, 0), 8)
	b:Crate(CFrame.new(18, 0, -26), Vector3.new(4, 4, 4))
	b:Crate(CFrame.new(20.5, 0, -22.5), Vector3.new(3, 3, 3))
	b:Pallet(CFrame.new(-40, 0, -2), 2)
	b:Pallet(CFrame.new(64, 0, 24), 2.6)
	b:Barrel(CFrame.new(46, 0, -50))
	b:Barrel(CFrame.new(48.2, 0, -49), C.ContainerRed)
	b:EndGroup()

	---------------------------------------------------------------------------
	-- Заводская этажерка (северо-восток): x 80..116, z −86..−58, второй этаж — 12
	---------------------------------------------------------------------------
	b:Group("Factory")
	local fx, fz = 98, -72
	b:Box(Vector3.new(36, 1, 28), CFrame.new(fx, 11.5, fz), M.Concrete, C.ConcreteDark)
	b:Box(Vector3.new(38, 0.8, 30), CFrame.new(fx, 24.4, fz), M.CorrodedMetal, C.SteelDark)
	for _, x in ipairs({ fx - 17.5, fx - 6, fx + 6, fx + 17.5 }) do
		for _, z in ipairs({ fz - 13.5, fz + 13.5 }) do
			b:Box(Vector3.new(1.2, 24, 1.2), CFrame.new(x, 12, z), M.Metal, C.Yellow)
		end
	end
	-- перила второго этажа (кроме выхода лестницы у x = 88)
	b:Rail(Vector3.new(fx - 18, 12, fz + 14), Vector3.new(85, 12, fz + 14))
	b:Rail(Vector3.new(91, 12, fz + 14), Vector3.new(fx + 18, 12, fz + 14))
	b:Rail(Vector3.new(fx - 18, 12, fz - 14), Vector3.new(fx + 18, 12, fz - 14))
	b:Rail(Vector3.new(fx - 18, 12, fz - 14), Vector3.new(fx - 18, 12, fz + 14))
	b:Rail(Vector3.new(fx + 18, 12, fz - 14), Vector3.new(fx + 18, 12, fz + 14))
	b:Stairs(CFrame.new(88, 0, -42), 6, 12, 16, M.Metal, C.SteelDark)
	b:Box(Vector3.new(0.4, 6, 16), CFrame.new(84.8, 9, -50), M.Metal, C.Yellow, { CastShadow = false })
	-- станки внизу (укрытия) и ящики наверху
	b:Box(Vector3.new(8, 5, 5), CFrame.new(fx - 8, 2.5, fz - 4), M.Metal, C.ContainerGreen)
	b:Box(Vector3.new(4, 7, 4), CFrame.new(fx - 8, 3.5, fz - 4 + 4.5), M.Metal, C.SteelDark)
	b:Box(Vector3.new(6, 4, 9), CFrame.new(fx + 9, 2, fz + 4), M.Metal, C.ContainerBlue)
	b:Box(Vector3.new(10, 3, 3), CFrame.new(fx + 4, 1.5, fz - 9), M.Metal, C.Steel)
	b:Crate(CFrame.new(fx - 10, 12, fz - 6), Vector3.new(4, 4, 4))
	b:Crate(CFrame.new(fx + 8, 12, fz + 6), Vector3.new(6, 3.5, 3))
	b:Box(Vector3.new(10, 3.2, 1), CFrame.new(fx + 2, 13.6, fz - 2), M.Concrete, C.Concrete)
	b:Lamp(Vector3.new(fx - 6, 23.6, fz), nil, 2, 34)
	b:Lamp(Vector3.new(fx + 8, 23.6, fz), nil, 2, 34)
	b:Lamp(Vector3.new(fx, 10.6, fz + 6), nil, 1.6, 26)
	b:EndGroup()

	---------------------------------------------------------------------------
	-- Резервуары и эстакада с трубами (восток)
	---------------------------------------------------------------------------
	b:Group("Tanks")
	b:Tank(Vector3.new(100, 0, -25), 7, 18, C.White)
	b:Tank(Vector3.new(118, 0, -8), 6, 14, Color3.fromRGB(196, 190, 176))
	b:Box(Vector3.new(4, 3, 6), CFrame.new(88, 1.5, -18), M.Metal, C.Steel)
	for x = 78, 122, 11 do
		b:Post(Vector3.new(x, 0, 5), 9, 0.8, C.SteelDark)
		b:Box(Vector3.new(0.8, 0.8, 7), CFrame.new(x, 9, 5), M.Metal, C.SteelDark)
	end
	b:Pipe(Vector3.new(76, 9.9, 3), Vector3.new(124, 9.9, 3), 1.6, C.Steel)
	b:Pipe(Vector3.new(76, 9.9, 7), Vector3.new(124, 9.9, 7), 1.2, C.Rust)
	b:Pipe(Vector3.new(100, 1.2, -17.5), Vector3.new(100, 9.9, 3), 1.2, C.Steel)
	for i, p in ipairs({ Vector3.new(84, 0, 12), Vector3.new(86.2, 0, 12.8), Vector3.new(85, 0, 14.9), Vector3.new(108, 0, 14), Vector3.new(110.3, 0, 14.5) }) do
		b:Barrel(CFrame.new(p), i % 2 == 0 and C.Yellow or C.ContainerBlue)
	end
	b:Barrier(CFrame.new(112, 0, 28), 8)
	b:Crate(CFrame.new(92, 0, 30), Vector3.new(5, 4, 5))
	b:EndGroup()

	---------------------------------------------------------------------------
	-- Погрузочная рампа (юг): x −45..70, z 72..96, высота 4.2
	---------------------------------------------------------------------------
	b:Group("Dock")
	local dockY = 4.2
	b:Box(Vector3.new(115, dockY, 24), CFrame.new(12.5, dockY / 2, 84), M.Concrete, C.Concrete)
	b:Box(Vector3.new(115, 0.6, 1), CFrame.new(12.5, dockY - 0.3, 71.6), M.Metal, C.Yellow)
	-- пандус с запада
	b:Wedge(Vector3.new(24, dockY, 16), CFrame.new(-53, dockY / 2, 84) * CFrame.Angles(0, math.pi / 2, 0), M.Concrete, C.ConcreteDark)
	-- лестницы
	b:Stairs(CFrame.new(64, 0, 67) * CFrame.Angles(0, math.pi, 0), 6, dockY, 5, M.Concrete, C.ConcreteDark)
	b:Stairs(CFrame.new(12, 0, 67) * CFrame.Angles(0, math.pi, 0), 6, dockY, 5, M.Concrete, C.ConcreteDark)
	-- навес над рампой
	b:Box(Vector3.new(115, 0.6, 14), CFrame.new(12.5, 17, 90), M.CorrodedMetal, C.SteelDark)
	for x = -40, 65, 15 do
		b:Box(Vector3.new(0.8, 13, 0.8), CFrame.new(x, dockY + 6.5, 96), M.Metal, C.SteelDark)
		b:Lamp(Vector3.new(x + 7, 16.4, 88), Color3.fromRGB(255, 224, 176), 1.8, 26)
	end
	-- груз на рампе
	b:Crate(CFrame.new(-30, dockY, 86), Vector3.new(5, 5, 5))
	b:Crate(CFrame.new(-24, dockY, 88), Vector3.new(4, 3, 4))
	b:Pallet(CFrame.new(5, dockY, 80), 3)
	b:Pallet(CFrame.new(28, dockY, 86), 2)
	b:Crate(CFrame.new(46, dockY, 82) * CFrame.Angles(0, 0.2, 0), Vector3.new(6, 4, 4))
	b:Barrier(CFrame.new(58, dockY, 88), 8)
	-- грузовики задом к рампе
	b:Truck(CFrame.new(-10, 0, 58), C.White)
	b:Truck(CFrame.new(35, 0, 58), Color3.fromRGB(176, 48, 40))
	b:EndGroup()

	---------------------------------------------------------------------------
	-- Фонари на столбах
	---------------------------------------------------------------------------
	b:Group("LightPoles")
	for _, p in ipairs({ Vector3.new(-46, 0, -82), Vector3.new(14, 0, -82), Vector3.new(66, 0, -40), Vector3.new(-46, 0, 48), Vector3.new(66, 0, 40), Vector3.new(120, 0, 44) }) do
		b:Post(p, 20, 0.6, C.SteelDark)
		b:Box(Vector3.new(0.4, 0.4, 3), CFrame.new(p + Vector3.new(0, 20, 1.4)), M.Metal, C.SteelDark)
		b:Lamp(p + Vector3.new(0, 19.6, 2.8), Color3.fromRGB(255, 214, 160), 1.6, 44, 110)
	end
	b:EndGroup()

	---------------------------------------------------------------------------
	-- Точки появления (FFA — все; команды: красные запад, синие восток)
	---------------------------------------------------------------------------
	local E, W, N, S = Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 0, -1), Vector3.new(0, 0, 1)
	-- красные: склад и юго-запад
	for _, p in ipairs({ Vector3.new(-110, 0, -30), Vector3.new(-66, 0, -30), Vector3.new(-66, 0, 10), Vector3.new(-92, 0, 14), Vector3.new(-115, 0, 46), Vector3.new(-80, 0, 30), Vector3.new(-100, 10, -46), Vector3.new(-120, 0, 88) }) do
		b:Spawn(p, E, "Red")
	end
	-- синие: этажерка, резервуары, восток
	for _, p in ipairs({ Vector3.new(98, 0, -92), Vector3.new(84, 0, -64), Vector3.new(108, 12, -78), Vector3.new(120, 0, -30), Vector3.new(92, 0, 20), Vector3.new(120, 0, 20), Vector3.new(118, 0, 60), Vector3.new(96, 0, 46) }) do
		b:Spawn(p, W, "Blue")
	end
	-- только FFA: середина краёв
	for _, sp in ipairs({ { Vector3.new(-40, 0, -88), S }, { Vector3.new(30, 0, -90), S }, { Vector3.new(66, 0, -88), S }, { Vector3.new(-14, dockY, 90), N }, { Vector3.new(50, dockY, 92), N }, { Vector3.new(-40, 0, 64), N }, { Vector3.new(70, 0, 50), N }, { Vector3.new(-4, 0, -26), E } }) do
		b:Spawn(sp[1], sp[2])
	end

	return b:Result({ Center = Vector3.new(0, 0, 0) })
end

return Map
