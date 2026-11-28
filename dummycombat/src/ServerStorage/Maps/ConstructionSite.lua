-- CONSTRUCTION SITE: стройка (этап 9). 200 × 180 studs, пол — y = 0.
--
--   центр-север — недостроенный каркас: три уровня перекрытий на колоннах, лестницы в проёмах, строительные
--                 леса вдоль южного фасада, частично выложенные стены, арматура;
--   северо-восток — башенный кран над каркасом (груз висит над площадкой);
--   юго-запад   — котлован глубиной 6 с двумя пандусами и экскаватором;
--   северо-запад — кучи грунта, бетонные короба-коллекторы (через них можно пройти), бульдозер;
--   восток      — склад материалов: трубы, арматура, кирпич на поддонах, песок, бетономешалка, бытовки.
-- По краю — забор из щитов. Командные точки: красные — запад, синие — восток.
local MapKit = require(script.Parent:WaitForChild("MapKit"))

local M = Enum.Material

local Map = {
	Id = "ConstructionSite",
	DisplayName = "CONSTRUCTION SITE",
	Description = "Каркас здания, кран, котлован и склад материалов",
	Size = Vector3.new(200, 0, 180),
	Lighting = {
		ClockTime = 13.4,
		Brightness = 2.0,
		Ambient = Color3.fromRGB(72, 72, 74),
		OutdoorAmbient = Color3.fromRGB(132, 130, 126),
		EnvironmentDiffuseScale = 0.65,
		EnvironmentSpecularScale = 0.4,
		Atmosphere = { Density = 0.36, Offset = 0.08, Haze = 2.4, Glare = 0.05, Color = Color3.fromRGB(196, 192, 184), Decay = Color3.fromRGB(116, 112, 104) },
		ColorCorrection = { Contrast = 0.06, Saturation = -0.15, Brightness = 0, TintColor = Color3.fromRGB(252, 250, 246) },
	},
}

local DIRT = Color3.fromRGB(122, 100, 74)
local DIRT_DARK = Color3.fromRGB(96, 78, 58)

function Map.Build(folder)
	local b = MapKit.new(folder)
	local C = MapKit.Colors
	local orange = Color3.fromRGB(206, 120, 44)

	---------------------------------------------------------------------------
	-- Земля с котлованом (x −80..−30, z 20..70, дно y = −6)
	---------------------------------------------------------------------------
	b:Group("Ground")
	b:Box(Vector3.new(210, 2, 115), CFrame.new(0, -1, -37.5), M.Ground, DIRT)
	b:Box(Vector3.new(210, 2, 25), CFrame.new(0, -1, 82.5), M.Ground, DIRT)
	b:Box(Vector3.new(25, 2, 50), CFrame.new(-92.5, -1, 45), M.Ground, DIRT)
	b:Box(Vector3.new(135, 2, 50), CFrame.new(37.5, -1, 45), M.Ground, DIRT)
	b:Box(Vector3.new(50, 2, 50), CFrame.new(-55, -7, 45), M.Mud, DIRT_DARK)
	b:Box(Vector3.new(50, 6, 1), CFrame.new(-55, -3, 19.5), M.Ground, DIRT_DARK)
	b:Box(Vector3.new(50, 6, 1), CFrame.new(-55, -3, 70.5), M.Ground, DIRT_DARK)
	b:Box(Vector3.new(1, 6, 52), CFrame.new(-80.5, -3, 45), M.Ground, DIRT_DARK)
	b:Box(Vector3.new(1, 6, 52), CFrame.new(-29.5, -3, 45), M.Ground, DIRT_DARK)
	b:Ramp(Vector3.new(-52, -6, 45), Vector3.new(-30, 0, 45), 10, M.Ground, DIRT)
	b:Ramp(Vector3.new(-64, -6, 40), Vector3.new(-64, 0, 20), 8, M.Ground, DIRT)
	-- дорога из щебня через стройку
	b:Box(Vector3.new(14, 0.1, 170), CFrame.new(40, 0.05, 0), M.Pebble, Color3.fromRGB(130, 126, 116))
	b:Box(Vector3.new(120, 0.1, 12), CFrame.new(-10, 0.05, 6), M.Pebble, Color3.fromRGB(130, 126, 116))
	b:EndGroup()

	-- забор из щитов и граница
	b:Group("Hoarding")
	local fenceH, fenceC = 12, Color3.fromRGB(176, 164, 132)
	b:Wall(Vector3.new(-100, 0, -90), Vector3.new(100, 0, -90), fenceH, 1, M.WoodPlanks, fenceC)
	b:Wall(Vector3.new(-100, 0, 90), Vector3.new(100, 0, 90), fenceH, 1, M.WoodPlanks, fenceC)
	b:Wall(Vector3.new(-100, 0, -90), Vector3.new(-100, 0, 90), fenceH, 1, M.WoodPlanks, fenceC)
	b:Wall(Vector3.new(100, 0, -90), Vector3.new(100, 0, 90), fenceH, 1, M.WoodPlanks, fenceC)
	for x = -96, 96, 12 do
		b:Box(Vector3.new(0.8, fenceH + 0.6, 0.8), CFrame.new(x, (fenceH + 0.6) / 2, -89.2), M.Metal, C.SteelDark)
		b:Box(Vector3.new(0.8, fenceH + 0.6, 0.8), CFrame.new(x, (fenceH + 0.6) / 2, 89.2), M.Metal, C.SteelDark)
	end
	b:EndGroup()
	b:Bounds(Vector3.new(0, 0, 0), Vector3.new(198, 0, 178), 80)

	---------------------------------------------------------------------------
	-- Каркас: x −30..30, z −60..−10; перекрытия — верх на 0.6 / 10.6 / 20.6
	---------------------------------------------------------------------------
	b:Group("Frame")
	local L0, L1, L2 = 0.6, 10.6, 20.6
	local slabC = Color3.fromRGB(162, 160, 154)
	b:Slab(Vector3.new(0, 0, -35), Vector3.new(60, 0.6, 50), L0, M.Concrete, slabC)
	-- уровень 1: проём под лестницу x 20..26, z −33..−21
	b:Slab(Vector3.new(-5, 0, -35), Vector3.new(50, 1, 50), L1, M.Concrete, slabC)
	b:Slab(Vector3.new(28, 0, -35), Vector3.new(4, 1, 50), L1, M.Concrete, slabC)
	b:Slab(Vector3.new(23, 0, -46.5), Vector3.new(6, 1, 27), L1, M.Concrete, slabC)
	b:Slab(Vector3.new(23, 0, -15.5), Vector3.new(6, 1, 11), L1, M.Concrete, slabC)
	b:Stairs(CFrame.new(23, L0, -21), 5.6, L1 - L0, 12, M.Concrete, C.ConcreteDark)
	-- уровень 2: проём x −26..−20, z −46..−34
	b:Slab(Vector3.new(-28, 0, -35), Vector3.new(4, 1, 50), L2, M.Concrete, slabC)
	b:Slab(Vector3.new(5, 0, -35), Vector3.new(50, 1, 50), L2, M.Concrete, slabC)
	b:Slab(Vector3.new(-23, 0, -53), Vector3.new(6, 1, 14), L2, M.Concrete, slabC)
	b:Slab(Vector3.new(-23, 0, -22), Vector3.new(6, 1, 24), L2, M.Concrete, slabC)
	b:Stairs(CFrame.new(-23, L1, -34), 5.6, L2 - L1, 12, M.Concrete, C.ConcreteDark)
	-- колонны (на верхнем уровне — недолитые, с арматурой)
	for _, x in ipairs({ -28, -14, 0, 14, 28 }) do
		for _, z in ipairs({ -58, -46, -34, -22, -12 }) do
			b:Column(Vector3.new(x, 0, z), L0, L2 - 1, 1.6, M.Concrete, C.Concrete)
			if (x + z) % 3 ~= 0 then
				b:Column(Vector3.new(x, 0, z), L2, L2 + 4, 1.6, M.Concrete, C.Concrete)
			else
				for _, o in ipairs({ Vector3.new(-0.5, 0, -0.5), Vector3.new(0.5, 0, 0.5), Vector3.new(-0.5, 0, 0.5), Vector3.new(0.5, 0, -0.5) }) do
					b:Box(Vector3.new(0.15, 3.5, 0.15), CFrame.new(x + o.X, L2 + 1.75, z + o.Z), M.Metal, C.Rust, { CanQuery = false, CastShadow = false })
				end
			end
		end
	end
	-- кирпичные стены: первый уровень по западу и северу, второй — куски с проёмами
	local brick = Color3.fromRGB(150, 82, 62)
	b:Box(Vector3.new(1.2, 9.8, 34), CFrame.new(-29.4, L0 + 4.9, -43), M.Brick, brick)
	b:Box(Vector3.new(30, 9.8, 1.2), CFrame.new(-14, L0 + 4.9, -59.4), M.Brick, brick)
	b:Box(Vector3.new(20, 4, 1.2), CFrame.new(16, L0 + 2, -59.4), M.Brick, brick)
	b:Box(Vector3.new(1.2, 9, 14), CFrame.new(29.4, L1 + 4.5, -50), M.Brick, brick)
	b:Box(Vector3.new(16, 3.2, 1.2), CFrame.new(-8, L1 + 1.6, -59.4), M.Brick, brick)
	b:Box(Vector3.new(12, 9, 1.2), CFrame.new(-8, L1 + 4.5, -34), M.Brick, brick)
	b:Box(Vector3.new(1.2, 3.2, 20), CFrame.new(-29.4, L2 + 1.6, -40), M.Brick, brick)
	-- ограждения по краям перекрытий (местами)
	b:Rail(Vector3.new(-30, L1, -60.2), Vector3.new(-10, L1, -60.2), orange)
	b:Rail(Vector3.new(30.2, L2, -60), Vector3.new(30.2, L2, -30), orange)
	b:Rail(Vector3.new(19.8, L1, -33), Vector3.new(19.8, L1, -21), orange)
	b:Rail(Vector3.new(-19.8, L2, -46), Vector3.new(-19.8, L2, -34), orange)
	-- материалы на перекрытиях
	b:Pallet(CFrame.new(-10, L0, -24), 3)
	b:Pallet(CFrame.new(6, L1, -50), 2)
	b:Crate(CFrame.new(12, L1, -26), Vector3.new(4, 3, 4))
	b:Crate(CFrame.new(-4, L2, -50), Vector3.new(5, 4, 3))
	b:Pallet(CFrame.new(16, L2, -20), 3)
	b:Barrel(CFrame.new(-18, L0, -50), orange)
	b:Lamp(Vector3.new(0, L1 - 1.2, -35), Color3.fromRGB(255, 226, 180), 1.2, 28)
	b:Lamp(Vector3.new(0, L2 - 1.2, -35), Color3.fromRGB(255, 226, 180), 1.2, 28)
	-- леса вдоль южного фасада (z −10..−6): стойки, настилы на уровнях 1 и 2, лестница с земли
	for x = -30, 30, 6 do
		b:Box(Vector3.new(0.35, L2 + 4, 0.35), CFrame.new(x, (L2 + 4) / 2, -9.6), M.Metal, C.Steel, { CastShadow = false })
		b:Box(Vector3.new(0.35, L2 + 4, 0.35), CFrame.new(x, (L2 + 4) / 2, -6.2), M.Metal, C.Steel, { CastShadow = false })
	end
	for _, yy in ipairs({ L1, L2 }) do
		b:Box(Vector3.new(60, 0.4, 3.8), CFrame.new(0, yy - 0.2, -7.9), M.WoodPlanks, C.Wood)
		b:Rail(Vector3.new(-30, yy, -6.1), Vector3.new(30, yy, -6.1), orange)
	end
	b:Stairs(CFrame.new(-42, 0, -8) * CFrame.Angles(0, -math.pi / 2, 0), 3.6, L1, 12, M.WoodPlanks, C.WoodDark)
	b:EndGroup()

	---------------------------------------------------------------------------
	-- Башенный кран
	---------------------------------------------------------------------------
	b:Group("Crane")
	local cx, cz, ch = 58, -52, 62
	b:Box(Vector3.new(8, 2, 8), CFrame.new(cx, 1, cz), M.Concrete, C.ConcreteDark)
	for _, o in ipairs({ Vector3.new(-1.6, 0, -1.6), Vector3.new(1.6, 0, -1.6), Vector3.new(-1.6, 0, 1.6), Vector3.new(1.6, 0, 1.6) }) do
		b:Box(Vector3.new(0.5, ch, 0.5), CFrame.new(cx + o.X, ch / 2 + 2, cz + o.Z), M.Metal, C.Yellow)
	end
	for yy = 6, ch, 6 do
		b:Box(Vector3.new(3.7, 0.3, 0.3), CFrame.new(cx, yy, cz - 1.6), M.Metal, C.Yellow, { CastShadow = false })
		b:Box(Vector3.new(3.7, 0.3, 0.3), CFrame.new(cx, yy, cz + 1.6), M.Metal, C.Yellow, { CastShadow = false })
		b:Box(Vector3.new(0.3, 0.3, 3.7), CFrame.new(cx - 1.6, yy, cz), M.Metal, C.Yellow, { CastShadow = false })
		b:Box(Vector3.new(0.3, 0.3, 3.7), CFrame.new(cx + 1.6, yy, cz), M.Metal, C.Yellow, { CastShadow = false })
	end
	local jibY = ch + 2.5
	b:Box(Vector3.new(80, 2.2, 2.4), CFrame.new(cx - 26, jibY, cz), M.Metal, C.Yellow)
	b:Box(Vector3.new(4, 3, 4), CFrame.new(cx + 16, jibY - 0.4, cz), M.Concrete, C.ConcreteDark)
	b:Box(Vector3.new(4, 3.4, 3.6), CFrame.new(cx - 0.5, jibY - 2.8, cz + 2.8), M.Metal, C.White)
	-- груз на тросе над площадкой у каркаса
	b:Box(Vector3.new(0.15, 36, 0.15), CFrame.new(cx - 46, jibY - 19, cz), M.Metal, C.Black, { CanQuery = false, CanCollide = false, CastShadow = false })
	b:Pallet(CFrame.new(cx - 46, jibY - 38, cz), 3)
	b:EndGroup()

	---------------------------------------------------------------------------
	-- Котлован: экскаватор, трубы, лужа
	---------------------------------------------------------------------------
	b:Group("Pit")
	local ex = CFrame.new(-66, -6, 58) * CFrame.Angles(0, 0.6, 0)
	b:Box(Vector3.new(9, 2.2, 12), ex * CFrame.new(0, 1.1, 0), M.Metal, C.Black)
	b:Box(Vector3.new(8, 4, 8), ex * CFrame.new(0, 4.2, 0.5), M.Metal, orange)
	b:Box(Vector3.new(3.6, 3.6, 3.6), ex * CFrame.new(-2, 7.6, -1), M.Glass, Color3.fromRGB(120, 140, 150), { Transparency = 0.4 })
	b:Box(Vector3.new(1.4, 1.4, 12), ex * CFrame.new(2, 7, -7) * CFrame.Angles(0.5, 0, 0), M.Metal, orange)
	b:Box(Vector3.new(1.2, 1.2, 8), ex * CFrame.new(2, 6, -15) * CFrame.Angles(-0.8, 0, 0), M.Metal, orange)
	b:Box(Vector3.new(3.4, 2.6, 2.4), ex * CFrame.new(2, 2, -17.5), M.Metal, C.SteelDark)
	b:Pipe(Vector3.new(-76, -4.8, 24), Vector3.new(-76, -4.8, 40), 2.4, C.ConcreteDark)
	b:Pipe(Vector3.new(-72.8, -4.8, 26), Vector3.new(-72.8, -4.8, 38), 2.4, C.ConcreteDark)
	b:Box(Vector3.new(14, 0.1, 10), CFrame.new(-44, -5.95, 62), M.Glass, Color3.fromRGB(70, 74, 66), { Transparency = 0.25, CanCollide = false, CanQuery = false })
	b:Crate(CFrame.new(-40, -6, 30), Vector3.new(4, 4, 4))
	b:Barrier(CFrame.new(-55, 0, 18) , 10, orange)
	b:EndGroup()

	---------------------------------------------------------------------------
	-- Северо-запад: грунт, короба-коллекторы, бульдозер
	---------------------------------------------------------------------------
	b:Group("Earthworks")
	for i, m in ipairs({ { -80, -70, 16 }, { -60, -78, 12 }, { -88, -40, 12 } }) do
		local mound = b:Box(Vector3.new(m[3] * 1.8, m[3], m[3] * 1.5), CFrame.new(m[1], -m[3] * 0.18, m[2]) * CFrame.Angles(0, i, 0), M.Ground, DIRT_DARK)
		mound.Shape = Enum.PartType.Ball
	end
	-- коробчатые коллекторы: проходят насквозь (стены и свод)
	for _, p in ipairs({ { -62, -40, 0 }, { -52, -54, 1.2 }, { -72, -22, 0.3 } }) do
		local cf = CFrame.new(p[1], 0, p[2]) * CFrame.Angles(0, p[3], 0)
		b:Box(Vector3.new(1, 7, 9), cf * CFrame.new(-3.5, 3.5, 0), M.Concrete, C.Concrete)
		b:Box(Vector3.new(1, 7, 9), cf * CFrame.new(3.5, 3.5, 0), M.Concrete, C.Concrete)
		b:Box(Vector3.new(8, 1, 9), cf * CFrame.new(0, 7.5, 0), M.Concrete, C.Concrete)
	end
	local dz = CFrame.new(-36, 0, -76) * CFrame.Angles(0, -0.4, 0)
	b:Box(Vector3.new(7, 2, 11), dz * CFrame.new(0, 1, 0), M.Metal, C.Black)
	b:Box(Vector3.new(6, 3.4, 7), dz * CFrame.new(0, 3.7, 1), M.Metal, C.Yellow)
	b:Box(Vector3.new(4, 3, 3.6), dz * CFrame.new(0, 6.9, 2.6), M.Glass, Color3.fromRGB(120, 140, 150), { Transparency = 0.4 })
	b:Box(Vector3.new(9, 3.2, 1), dz * CFrame.new(0, 1.8, -7.5), M.Metal, C.Yellow)
	b:EndGroup()

	---------------------------------------------------------------------------
	-- Восток: склад материалов, бетономешалка, бытовки
	---------------------------------------------------------------------------
	b:Group("Yard")
	-- штабель труб
	for layer = 0, 2 do
		for k = 0, 3 - layer do
			local x = 60 + k * 2.4 + layer * 1.2
			local yy = 1.1 + layer * 2.05
			b:Pipe(Vector3.new(x, yy, 8), Vector3.new(x, yy, 26), 2.2, C.Steel)
		end
	end
	-- пачки арматуры
	for i = 0, 3 do
		b:Box(Vector3.new(1.4, 0.8, 22), CFrame.new(76 + i * 2, 0.4 + (i % 2) * 0.8, 18), M.Metal, C.Rust)
	end
	-- кирпич на поддонах
	for i = 0, 2 do
		for k = 0, 1 do
			b:Box(Vector3.new(4, 0.5, 4), CFrame.new(84 + i * 5, 0.25, 36 + k * 5), M.WoodPlanks, C.Wood)
			b:Box(Vector3.new(3.6, 3, 3.6), CFrame.new(84 + i * 5, 2, 36 + k * 5), M.Brick, brick)
		end
	end
	-- песок
	b:Ramp(Vector3.new(66, 0, 50), Vector3.new(66, 4.5, 56), 10, M.Sand, Color3.fromRGB(196, 176, 130))
	b:Ramp(Vector3.new(66, 0, 62), Vector3.new(66, 4.5, 56), 10, M.Sand, Color3.fromRGB(196, 176, 130))
	-- бетономешалка
	b:Truck(CFrame.new(54, 0, 66) * CFrame.Angles(0, math.pi + 0.1, 0), C.White)
	b:Cylinder(10, 6, CFrame.new(54, 7.6, 70) * CFrame.Angles(math.pi / 2 - 0.25, 0, 0), M.Metal, orange)
	-- бытовки: две внизу, одна наверху
	b:Container(CFrame.new(80, 0, 74), C.White, true)
	b:Container(CFrame.new(80, 0, 82.5), C.White, false)
	b:Container(CFrame.new(80, 8.1, 78) * CFrame.Angles(0, 0.02, 0), Color3.fromRGB(70, 100, 130), false)
	-- туалеты
	for i = 0, 2 do
		b:Box(Vector3.new(4, 7.5, 4), CFrame.new(94, 3.75, 40 + i * 4.4), M.Plastic, Color3.fromRGB(52, 92, 140))
	end
	-- фонари на мачтах
	for _, p in ipairs({ Vector3.new(46, 0, -80), Vector3.new(46, 0, 30), Vector3.new(-90, 0, 0), Vector3.new(0, 0, 80) }) do
		b:Post(p, 18, 0.5, C.SteelDark)
		b:Lamp(p + Vector3.new(0, 17.6, 1.6), Color3.fromRGB(255, 220, 170), 1.5, 44, 100)
	end
	b:Barrier(CFrame.new(20, 0, 28), 8, orange)
	b:Barrier(CFrame.new(-8, 0, 40) * CFrame.Angles(0, 0.5, 0), 8, orange)
	b:Barrier(CFrame.new(8, 0, 64) * CFrame.Angles(0, -0.3, 0), 8, C.White)
	b:Crate(CFrame.new(-14, 0, 60), Vector3.new(5, 4, 5))
	b:Pallet(CFrame.new(-2, 0, 76), 2)
	b:EndGroup()

	---------------------------------------------------------------------------
	-- Точки появления
	---------------------------------------------------------------------------
	local E, W, N, S = Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 0, -1), Vector3.new(0, 0, 1)
	for _, p in ipairs({ Vector3.new(-92, 0, 80), Vector3.new(-92, 0, 20), Vector3.new(-90, 0, -12), Vector3.new(-70, 0, 82),
		Vector3.new(-94, 0, -86), Vector3.new(-56, -6, 46), Vector3.new(-40, 0, 80), Vector3.new(-74, 0, -56) }) do
		b:Spawn(p, E, "Red")
	end
	for _, p in ipairs({ Vector3.new(92, 0, -80), Vector3.new(92, 0, -40), Vector3.new(92, 0, 0), Vector3.new(92, 0, 20),
		Vector3.new(70, 0, -20), Vector3.new(72, 0, 40), Vector3.new(92, 0, 60), Vector3.new(70, 0, -80) }) do
		b:Spawn(p, W, "Blue")
	end
	for _, sp in ipairs({ { Vector3.new(-6, L1, -40), S }, { Vector3.new(10, L2, -44), S }, { Vector3.new(0, L0, -28), S },
		{ Vector3.new(20, 0, 84), N }, { Vector3.new(-20, 0, 84), N }, { Vector3.new(0, 0, -82), S }, { Vector3.new(30, 0, 40), W },
		{ Vector3.new(-20, 0, 20), E } }) do
		b:Spawn(sp[1], sp[2])
	end
	return b:Result({ Center = Vector3.new(0, 0, 0) })
end

return Map
