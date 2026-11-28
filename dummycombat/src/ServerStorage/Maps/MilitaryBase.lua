-- MILITARY BASE: военная база (этап 9). 240 × 200 studs, пол — y = 0.
--
--   северо-восток — ангар 60 × 50 с бронемашиной, ящиками и мостками вдоль стены;
--   северо-запад  — двухэтажный штаб (лестница внутри, окна на плац);
--   центр         — плац с вертолётной площадкой, габионы и ящики снабжения;
--   юго-запад     — две казармы с койками, между ними — двор с мешками с песком;
--   юго-восток    — автопарк: грузовики, топливные цистерны, контейнеры;
--   восток        — стрельбище с мишенями; по углам и в середине краёв — вышки (на две можно подняться).
-- Командные точки: красные — казармы (юго-запад), синие — ангар (северо-восток).
local MapKit = require(script.Parent:WaitForChild("MapKit"))

local M = Enum.Material

local Map = {
	Id = "MilitaryBase",
	DisplayName = "MILITARY BASE",
	Description = "Ангар, штаб, казармы, плац и автопарк",
	Size = Vector3.new(240, 0, 200),
	Lighting = {
		ClockTime = 17.1,
		Brightness = 2.3,
		Ambient = Color3.fromRGB(68, 64, 60),
		OutdoorAmbient = Color3.fromRGB(130, 120, 106),
		EnvironmentDiffuseScale = 0.6,
		EnvironmentSpecularScale = 0.35,
		Atmosphere = { Density = 0.33, Offset = 0.1, Haze = 2.2, Glare = 0.35, Color = Color3.fromRGB(214, 196, 168), Decay = Color3.fromRGB(122, 104, 84) },
		ColorCorrection = { Contrast = 0.07, Saturation = -0.08, Brightness = 0, TintColor = Color3.fromRGB(255, 244, 228) },
	},
}

local OLIVE = Color3.fromRGB(88, 96, 70)
local OLIVE_DARK = Color3.fromRGB(64, 70, 52)
local SAND = Color3.fromRGB(168, 152, 118)

function Map.Build(folder)
	local b = MapKit.new(folder)
	local C = MapKit.Colors

	-- габион (короб с землёй в сетке)
	local function hesco(cf)
		b:Box(Vector3.new(4, 4.6, 4), cf * CFrame.new(0, 2.3, 0), M.Fabric, SAND)
		b:Box(Vector3.new(4.1, 0.25, 4.1), cf * CFrame.new(0, 4.5, 0), M.Metal, C.SteelDark, { CastShadow = false })
		b:Box(Vector3.new(3.6, 0.3, 3.6), cf * CFrame.new(0, 4.7, 0), M.Ground, Color3.fromRGB(106, 88, 64))
	end
	-- вышка: площадка на высоте h, перила, навес; stairs = true — с лестницей (look — куда смотрит её низ)
	local function tower(pos, h, stairs, look)
		b:Group("Tower")
		for _, o in ipairs({ Vector3.new(-3.5, 0, -3.5), Vector3.new(3.5, 0, -3.5), Vector3.new(-3.5, 0, 3.5), Vector3.new(3.5, 0, 3.5) }) do
			b:Post(pos + o, h + 7, 0.7, C.WoodDark)
		end
		b:Box(Vector3.new(9, 0.8, 9), CFrame.new(pos + Vector3.new(0, h - 0.4, 0)), M.WoodPlanks, C.Wood)
		b:Box(Vector3.new(10, 0.5, 10), CFrame.new(pos + Vector3.new(0, h + 7.2, 0)), M.CorrodedMetal, C.SteelDark)
		for _, side in ipairs({ { 0, -4.4, 9, 0.4 }, { 0, 4.4, 9, 0.4 }, { -4.4, 0, 0.4, 9 }, { 4.4, 0, 0.4, 9 } }) do
			b:Box(Vector3.new(side[3], 2.6, side[4]), CFrame.new(pos + Vector3.new(side[1], h + 1.3, side[2])), M.WoodPlanks, C.WoodDark)
		end
		if stairs then
			local dir = look or Vector3.new(0, 0, 1)
			local base = pos + dir * (4.5 + h * 1.1)
			b:Stairs(CFrame.lookAt(base, base - dir), 3.2, h, h * 1.1, M.WoodPlanks, C.Wood)
		end
		b:EndGroup()
	end
	-- бронемашина: cf — центр на земле, длина вдоль −Z
	local function apc(cf)
		b:Group("APC")
		b:Box(Vector3.new(8.4, 4.2, 18), cf * CFrame.new(0, 3.6, 0), M.Metal, OLIVE)
		b:Wedge(Vector3.new(8.4, 2.6, 4), cf * CFrame.new(0, 4.4, -10.9) * CFrame.Angles(0, math.pi, 0), M.Metal, OLIVE)
		b:Box(Vector3.new(4.4, 1.8, 5), cf * CFrame.new(0, 6.6, 1), M.Metal, OLIVE_DARK)
		b:Box(Vector3.new(0.5, 0.5, 5), cf * CFrame.new(0, 6.8, -3.2), M.Metal, C.Black)
		for _, z in ipairs({ -6, -2, 2, 6 }) do
			for _, x in ipairs({ -4.4, 4.4 }) do
				local w = b:Box(Vector3.new(1.4, 3.4, 3.4), cf * CFrame.new(x, 1.7, z), M.SmoothPlastic, C.Black)
				w.Shape = Enum.PartType.Cylinder
			end
		end
		b:EndGroup()
	end

	---------------------------------------------------------------------------
	-- Земля, дороги, ограждение
	---------------------------------------------------------------------------
	b:Group("Ground")
	b:Box(Vector3.new(250, 2, 210), CFrame.new(0, -1, 0), M.Ground, Color3.fromRGB(112, 100, 76))
	b:Box(Vector3.new(240, 0.1, 14), CFrame.new(0, 0.05, 0), M.Pebble, Color3.fromRGB(128, 122, 110))
	b:Box(Vector3.new(14, 0.1, 200), CFrame.new(30, 0.05, 0), M.Pebble, Color3.fromRGB(128, 122, 110))
	b:Box(Vector3.new(44, 0.12, 44), CFrame.new(-28, 0.06, -12), M.Concrete, Color3.fromRGB(140, 138, 132))
	for i = 0, 5 do
		b:Box(Vector3.new(30, 0.1, 22), CFrame.new(-90 + i * 40, 0.04, 70 + (i % 2) * 6), M.Grass, Color3.fromRGB(96, 104, 68))
	end
	-- вертолётная площадка: круг и буква H
	b:Cylinder(0.14, 24, CFrame.new(-28, 0.13, -12), M.Concrete, C.ConcreteDark)
	b:Box(Vector3.new(1.4, 0.05, 10), CFrame.new(-31, 0.22, -12), M.SmoothPlastic, C.White, { CastShadow = false })
	b:Box(Vector3.new(1.4, 0.05, 10), CFrame.new(-25, 0.22, -12), M.SmoothPlastic, C.White, { CastShadow = false })
	b:Box(Vector3.new(6, 0.05, 1.4), CFrame.new(-28, 0.22, -12), M.SmoothPlastic, C.White, { CastShadow = false })
	b:EndGroup()

	b:Group("Perimeter")
	local wallH = 16
	b:Wall(Vector3.new(-120, 0, -100), Vector3.new(120, 0, -100), wallH, 1.6, M.Concrete, Color3.fromRGB(150, 144, 130))
	b:Wall(Vector3.new(-120, 0, 100), Vector3.new(120, 0, 100), wallH, 1.6, M.Concrete, Color3.fromRGB(150, 144, 130))
	b:Wall(Vector3.new(-120, 0, -100), Vector3.new(-120, 0, 100), wallH, 1.6, M.Concrete, Color3.fromRGB(150, 144, 130))
	b:Wall(Vector3.new(120, 0, -100), Vector3.new(120, 0, 100), wallH, 1.6, M.Concrete, Color3.fromRGB(150, 144, 130))
	-- колючая проволока поверху (кольца)
	for x = -116, 116, 8 do
		for _, z in ipairs({ -100, 100 }) do
			local ring = b:Box(Vector3.new(0.3, 2, 2), CFrame.new(x, wallH + 1, z), M.Metal, C.Steel, { CastShadow = false, CanQuery = false })
			ring.Shape = Enum.PartType.Cylinder
		end
	end
	tower(Vector3.new(-112, 0, -92), 14, false)
	tower(Vector3.new(112, 0, -92), 14, false)
	tower(Vector3.new(-112, 0, 92), 14, false)
	tower(Vector3.new(112, 0, 92), 14, false)
	tower(Vector3.new(-6, 0, 88), 12, true, Vector3.new(0, 0, -1))
	tower(Vector3.new(-6, 0, -88), 12, true, Vector3.new(0, 0, 1))
	b:EndGroup()
	b:Bounds(Vector3.new(0, 0, 0), Vector3.new(238, 0, 198), 80)

	---------------------------------------------------------------------------
	-- Ангар (северо-восток)
	---------------------------------------------------------------------------
	local hx, hz = 74, -66
	b:Building(CFrame.new(hx, 0, hz), Vector3.new(60, 22, 50), {
		{ Side = "S", Offset = -4, Width = 30, Height = 16 },
		{ Side = "W", Offset = 14, Width = 6, Height = 9 },
		{ Side = "E", Offset = -10, Width = 6, Height = 9 },
		{ Side = "N", Offset = -16, Width = 10, Height = 3, Sill = 14 },
		{ Side = "N", Offset = 16, Width = 10, Height = 3, Sill = 14 },
	}, { Name = "Hangar", Material = M.CorrodedMetal, Color = OLIVE_DARK, RoofColor = OLIVE_DARK })
	b:Group("HangarInside")
	apc(CFrame.new(hx - 8, 0, hz - 2) * CFrame.Angles(0, 0.15, 0))
	b:Crate(CFrame.new(hx + 16, 0, hz + 10), Vector3.new(5, 5, 5))
	b:Crate(CFrame.new(hx + 21, 0, hz + 12), Vector3.new(4, 4, 6))
	b:Crate(CFrame.new(hx + 17, 5, hz + 10), Vector3.new(3, 3, 3))
	b:Pallet(CFrame.new(hx + 20, 0, hz - 6), 3)
	b:Barrel(CFrame.new(hx - 24, 0, hz + 14), OLIVE)
	b:Barrel(CFrame.new(hx - 21.5, 0, hz + 15), OLIVE)
	b:Barrel(CFrame.new(hx - 23, 0, hz + 17.5), C.ContainerRed)
	-- мостки вдоль северной стены (высота 10) и лестница к ним
	b:Catwalk(Vector3.new(hx - 26, 10, hz - 21), Vector3.new(hx + 26, 10, hz - 21), 5, false)
	b:Rail(Vector3.new(hx - 26, 10, hz - 18.7), Vector3.new(hx + 21.5, 10, hz - 18.7))
	b:Stairs(CFrame.new(hx + 24, 0, hz - 6.5), 4, 10, 12, M.Metal, C.SteelDark)
	for x = -24, 24, 12 do
		b:Post(Vector3.new(hx + x, 0, hz - 18.6), 9.6, 0.6, C.SteelDark)
	end
	b:Lamp(Vector3.new(hx - 12, 21, hz), Color3.fromRGB(236, 240, 250), 1.6, 40)
	b:Lamp(Vector3.new(hx + 12, 21, hz), Color3.fromRGB(236, 240, 250), 1.6, 40)
	b:EndGroup()

	---------------------------------------------------------------------------
	-- Штаб (северо-запад): два этажа
	---------------------------------------------------------------------------
	local sx, sz = -84, -70
	b:Building(CFrame.new(sx, 0, sz), Vector3.new(40, 20, 34), {
		{ Side = "S", Offset = 0, Width = 6, Height = 8.5 },
		{ Side = "S", Offset = -12, Width = 6, Height = 4, Sill = 3 },
		{ Side = "S", Offset = 12, Width = 6, Height = 4, Sill = 3 },
		{ Side = "S", Offset = -12, Width = 6, Height = 4, Sill = 13 },
		{ Side = "S", Offset = 0, Width = 6, Height = 4, Sill = 13 },
		{ Side = "S", Offset = 12, Width = 6, Height = 4, Sill = 13 },
		{ Side = "E", Offset = -6, Width = 5, Height = 8.5 },
		{ Side = "E", Offset = 8, Width = 6, Height = 4, Sill = 13 },
		{ Side = "W", Offset = 0, Width = 6, Height = 4, Sill = 13 },
	}, { Name = "HQ", Material = M.Concrete, Color = Color3.fromRGB(176, 168, 146), RoofColor = OLIVE_DARK })
	b:Group("HQInside")
	local f2 = 10
	b:Slab(Vector3.new(sx - 5, 0, sz), Vector3.new(27.6, 1, 31.6), f2)
	b:Slab(Vector3.new(sx + 14, 0, sz - 6.9), Vector3.new(10.6, 1, 17.8), f2)
	b:Stairs(CFrame.new(sx + 14, 0, sz + 14), 6, 9.5, 12, M.Concrete, C.ConcreteDark)
	b:Rail(Vector3.new(sx + 8.6, f2, sz - 2), Vector3.new(sx + 8.6, f2, sz + 15))
	b:Box(Vector3.new(10, 3.2, 5), CFrame.new(sx - 6, 1.6, sz - 4), M.Wood, C.WoodDark)
	b:Box(Vector3.new(12, 0.3, 6), CFrame.new(sx - 6, f2 + 2.8, sz - 6), M.Wood, C.WoodDark)
	b:Box(Vector3.new(0.4, 2.8, 0.4), CFrame.new(sx - 11, f2 + 1.4, sz - 6), M.Wood, C.WoodDark)
	b:Box(Vector3.new(0.4, 2.8, 0.4), CFrame.new(sx - 1, f2 + 1.4, sz - 6), M.Wood, C.WoodDark)
	b:Box(Vector3.new(8, 6, 0.4), CFrame.new(sx - 6, f2 + 4, sz - 15.2), M.SmoothPlastic, Color3.fromRGB(64, 78, 62))
	b:Lamp(Vector3.new(sx, 9.5, sz), Color3.fromRGB(255, 226, 186), 1.2, 26)
	b:Lamp(Vector3.new(sx, 19.5, sz), Color3.fromRGB(255, 226, 186), 1.2, 26)
	b:EndGroup()
	-- флагшток и мешки у входа
	b:Post(Vector3.new(sx, 0, sz + 26), 22, 0.4, C.Steel)
	b:Box(Vector3.new(0.1, 3, 5), CFrame.new(sx, 20, sz + 28.6), M.Fabric, Color3.fromRGB(80, 92, 70), { CanQuery = false })
	b:Sandbags(Vector3.new(sx - 10, 0, sz + 21), Vector3.new(sx - 2, 0, sz + 21), 3)
	b:Sandbags(Vector3.new(sx + 2, 0, sz + 21), Vector3.new(sx + 10, 0, sz + 21), 3)

	---------------------------------------------------------------------------
	-- Плац: вертолётная площадка, габионы, ящики
	---------------------------------------------------------------------------
	b:Group("Yard")
	for _, p in ipairs({ { -52, -30, 0 }, { -52, -26, 0 }, { -4, 6, 0.2 }, { 0, 6, 0.2 }, { -46, 10, 0 }, { -8, -34, 0 } }) do
		hesco(CFrame.new(p[1], 0, p[2]) * CFrame.Angles(0, p[3], 0))
	end
	b:Crate(CFrame.new(-28, 0, 16), Vector3.new(6, 4, 4))
	b:Crate(CFrame.new(-36, 0, -40), Vector3.new(4, 4, 4))
	b:Crate(CFrame.new(-18, 0, -40) * CFrame.Angles(0, 0.4, 0), Vector3.new(5, 3, 5))
	b:Container(CFrame.new(-64, 0, 2) * CFrame.Angles(0, math.pi / 2, 0), C.ContainerGreen, true)
	b:Container(CFrame.new(8, 0, -30) * CFrame.Angles(0, 0.1, 0), OLIVE)
	b:EndGroup()

	---------------------------------------------------------------------------
	-- Казармы (юго-запад)
	---------------------------------------------------------------------------
	for i, z in ipairs({ 34, 74 }) do
		local cx = -80
		b:Building(CFrame.new(cx, 0, z), Vector3.new(60, 11, 18), {
			{ Side = "W", Offset = 0, Width = 5, Height = 8.5 },
			{ Side = "E", Offset = 0, Width = 5, Height = 8.5 },
			{ Side = i == 1 and "S" or "N", Offset = 0, Width = 5, Height = 8.5 },
			{ Side = "N", Offset = -18, Width = 5, Height = 3, Sill = 4 },
			{ Side = "N", Offset = 18, Width = 5, Height = 3, Sill = 4 },
			{ Side = "S", Offset = -18, Width = 5, Height = 3, Sill = 4 },
			{ Side = "S", Offset = 18, Width = 5, Height = 3, Sill = 4 },
		}, { Name = "Barracks" .. i, Material = M.WoodPlanks, Color = Color3.fromRGB(116, 104, 84), RoofColor = OLIVE_DARK })
		b:Group("Bunks" .. i)
		for k = -2, 2 do
			if k ~= 0 then
				for _, side in ipairs({ -1, 1 }) do
					local bx, bz = cx + k * 9, z + side * 5.5
					b:Box(Vector3.new(6.5, 0.6, 3), CFrame.new(bx, 1.6, bz), M.Fabric, OLIVE)
					b:Box(Vector3.new(6.5, 0.6, 3), CFrame.new(bx, 5.2, bz), M.Fabric, OLIVE)
					b:Box(Vector3.new(0.3, 6, 3), CFrame.new(bx - 3.2, 3, bz), M.Metal, C.SteelDark)
					b:Box(Vector3.new(0.3, 6, 3), CFrame.new(bx + 3.2, 3, bz), M.Metal, C.SteelDark)
				end
			end
		end
		b:Lamp(Vector3.new(cx - 12, 10.5, z), Color3.fromRGB(255, 220, 170), 1, 20)
		b:Lamp(Vector3.new(cx + 12, 10.5, z), Color3.fromRGB(255, 220, 170), 1, 20)
		b:EndGroup()
	end
	-- двор между казармами
	b:Sandbags(Vector3.new(-96, 0, 54), Vector3.new(-84, 0, 54), 3)
	b:Sandbags(Vector3.new(-70, 0, 56), Vector3.new(-60, 0, 52), 3)
	b:Crate(CFrame.new(-106, 0, 54), Vector3.new(4, 4, 4))
	b:Barrel(CFrame.new(-50, 0, 54))

	---------------------------------------------------------------------------
	-- Автопарк (юго-восток)
	---------------------------------------------------------------------------
	b:Group("MotorPool")
	b:Box(Vector3.new(70, 0.12, 60), CFrame.new(78, 0.06, 56), M.Concrete, Color3.fromRGB(132, 130, 124))
	b:Truck(CFrame.new(56, 0, 50) * CFrame.Angles(0, math.pi, 0), OLIVE)
	b:Truck(CFrame.new(74, 0, 46) * CFrame.Angles(0, math.pi + 0.08, 0), OLIVE_DARK)
	apc(CFrame.new(94, 0, 44) * CFrame.Angles(0, math.pi, 0))
	b:Tank(Vector3.new(104, 0, 80), 6, 12, C.White)
	b:Tank(Vector3.new(88, 0, 82), 5, 10, OLIVE)
	b:Container(CFrame.new(60, 0, 82), C.ContainerGrey, false)
	b:Container(CFrame.new(60, 8.1, 82) * CFrame.Angles(0, 0.04, 0), OLIVE, false)
	b:Barrel(CFrame.new(76, 0, 74), OLIVE)
	b:Barrel(CFrame.new(78.5, 0, 75), OLIVE)
	b:Barrel(CFrame.new(77, 0, 77.4), C.ContainerRed)
	for _, x in ipairs({ 50, 70, 90, 110 }) do
		b:Post(Vector3.new(x, 0, 28), 14, 0.5, C.SteelDark)
		b:Lamp(Vector3.new(x, 13.6, 29), Color3.fromRGB(255, 214, 160), 1.4, 36)
	end
	b:EndGroup()

	---------------------------------------------------------------------------
	-- Стрельбище (восток, середина)
	---------------------------------------------------------------------------
	b:Group("Range")
	for i = 0, 3 do
		local z = -18 + i * 10
		b:Sandbags(Vector3.new(76, 0, z - 3), Vector3.new(76, 0, z + 3), 2)
		b:Box(Vector3.new(0.4, 6, 0.4), CFrame.new(112, 3, z), M.Wood, C.WoodDark)
		b:Box(Vector3.new(0.3, 3.6, 2.4), CFrame.new(112, 6.6, z), M.Wood, C.White)
	end
	b:Box(Vector3.new(3, 8, 44), CFrame.new(116, 4, -3), M.Ground, Color3.fromRGB(104, 90, 66))
	b:EndGroup()

	---------------------------------------------------------------------------
	-- Точки появления
	---------------------------------------------------------------------------
	local E, W, N, S = Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 0, -1), Vector3.new(0, 0, 1)
	for _, p in ipairs({ Vector3.new(-104, 0, 34), Vector3.new(-56, 0, 34), Vector3.new(-104, 0, 74), Vector3.new(-56, 0, 74),
		Vector3.new(-112, 0, 54), Vector3.new(-40, 0, 64), Vector3.new(-80, 0, 92), Vector3.new(-30, 0, 90) }) do
		b:Spawn(p, N, "Red")
	end
	for _, p in ipairs({ Vector3.new(hx - 20, 0, hz + 8), Vector3.new(hx + 6, 0, hz + 16), Vector3.new(hx, 10, hz - 21), Vector3.new(110, 0, -40),
		Vector3.new(38, 0, -88), Vector3.new(100, 0, -30), Vector3.new(60, 0, -34), Vector3.new(110, 0, -76) }) do
		b:Spawn(p, S, "Blue")
	end
	for _, sp in ipairs({ { Vector3.new(sx - 14, f2, sz + 6), S }, { Vector3.new(sx - 16, 0, sz + 8), S }, { Vector3.new(-28, 0, -12), E },
		{ Vector3.new(100, 0, 62), W }, { Vector3.new(66, 0, 64), N }, { Vector3.new(-110, 0, -40), E }, { Vector3.new(20, 0, 60), N },
		{ Vector3.new(0, 0, -60), S } }) do
		b:Spawn(sp[1], sp[2])
	end
	return b:Result({ Center = Vector3.new(0, 0, 0) })
end

return Map
