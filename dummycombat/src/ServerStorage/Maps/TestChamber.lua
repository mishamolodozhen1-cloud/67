-- TEST CHAMBER: испытательный зал краш-тестов (этап 9). Закрытое помещение 140 × 120, высота 30.
--
--   центр — испытательный путь с запада на восток: рельсы, тележка-сани с креслом, бетонный отбойник
--           в чёрно-жёлтую полосу; вокруг — модульные укрытия, стенды-мишени, ящики с оборудованием;
--   север — пультовая на высоте 10 со стеклом на зал, две лестницы;
--   юг    — мостки на высоте 8 вдоль стены (лестницы с двух концов);
--   запад и восток — подготовительные комнаты за стенами с тремя проходами (шкафчики, скамейки):
--           там появляются команды (красные — запад, синие — восток).
local MapKit = require(script.Parent:WaitForChild("MapKit"))

local M = Enum.Material

local Map = {
	Id = "TestChamber",
	DisplayName = "TEST CHAMBER",
	Description = "Зал краш-тестов: путь с отбойником, пультовая, мостки",
	Size = Vector3.new(140, 0, 120),
	Lighting = {
		ClockTime = 12,
		Brightness = 1,
		Ambient = Color3.fromRGB(118, 120, 126),
		OutdoorAmbient = Color3.fromRGB(118, 120, 126),
		EnvironmentDiffuseScale = 0.4,
		EnvironmentSpecularScale = 0.5,
		Atmosphere = { Density = 0.12, Offset = 0, Haze = 0.6, Glare = 0, Color = Color3.fromRGB(214, 218, 224), Decay = Color3.fromRGB(180, 184, 190) },
		ColorCorrection = { Contrast = 0.1, Saturation = -0.12, Brightness = 0.02, TintColor = Color3.fromRGB(246, 250, 255) },
	},
}

local H = 30
local PANEL = Color3.fromRGB(214, 216, 218)
local FLOOR = Color3.fromRGB(150, 152, 156)
local HAZ_Y = Color3.fromRGB(222, 178, 42)
local HAZ_K = Color3.fromRGB(30, 30, 32)

function Map.Build(folder)
	local b = MapKit.new(folder)
	local C = MapKit.Colors

	-- полоса «чёрный — жёлтый» по верху блока: cf — центр верхней грани, length — вдоль X
	local function stripes(cf, length, depth)
		local n = math.max(2, math.floor(length / 1.6))
		local w = length / n
		for i = 0, n - 1 do
			b:Box(Vector3.new(w, 0.12, depth), cf * CFrame.new(-length / 2 + w * (i + 0.5), 0.06, 0), M.SmoothPlastic, i % 2 == 0 and HAZ_Y or HAZ_K, { CastShadow = false })
		end
	end
	-- модульное укрытие: белый блок с полосой
	local function block(cf, size)
		b:Box(size, cf * CFrame.new(0, size.Y / 2, 0), M.SmoothPlastic, PANEL)
		stripes(cf * CFrame.new(0, size.Y, 0), size.X, size.Z)
	end
	-- стенд-мишень: стойка и круглый щит с кругами
	local function target(cf)
		b:Group("Target")
		b:Box(Vector3.new(2.4, 0.4, 2.4), cf * CFrame.new(0, 0.2, 0), M.Metal, C.SteelDark)
		b:Box(Vector3.new(0.4, 4.6, 0.4), cf * CFrame.new(0, 2.5, 0), M.Metal, C.Steel)
		for i, r in ipairs({ 3.4, 2.4, 1.4 }) do
			b:Cylinder(0.12 + i * 0.02, r, cf * CFrame.new(0, 5.6, -0.06 * i) * CFrame.Angles(math.pi / 2, 0, 0), M.SmoothPlastic, i % 2 == 1 and HAZ_Y or HAZ_K)
		end
		b:EndGroup()
	end

	---------------------------------------------------------------------------
	-- Оболочка: пол, стены, потолок, свет
	---------------------------------------------------------------------------
	b:Group("Shell")
	b:Box(Vector3.new(144, 2, 124), CFrame.new(0, -1, 0), M.SmoothPlastic, FLOOR)
	for x = -66, 66, 6 do
		b:Box(Vector3.new(0.12, 0.03, 120), CFrame.new(x, 0.015, 0), M.SmoothPlastic, Color3.fromRGB(132, 134, 138), { CastShadow = false })
	end
	for z = -54, 54, 6 do
		b:Box(Vector3.new(140, 0.03, 0.12), CFrame.new(0, 0.015, z), M.SmoothPlastic, Color3.fromRGB(132, 134, 138), { CastShadow = false })
	end
	b:Box(Vector3.new(144, 1, 124), CFrame.new(0, H + 0.5, 0), M.SmoothPlastic, Color3.fromRGB(190, 192, 196))
	b:Box(Vector3.new(2, H, 124), CFrame.new(-71, H / 2, 0), M.SmoothPlastic, PANEL)
	b:Box(Vector3.new(2, H, 124), CFrame.new(71, H / 2, 0), M.SmoothPlastic, PANEL)
	b:Box(Vector3.new(144, H, 2), CFrame.new(0, H / 2, -61), M.SmoothPlastic, PANEL)
	b:Box(Vector3.new(144, H, 2), CFrame.new(0, H / 2, 61), M.SmoothPlastic, PANEL)
	-- полосы по низу стен и тёмные швы панелей
	for _, side in ipairs({ { 0, -59.9, 140, 0.2 }, { 0, 59.9, 140, 0.2 } }) do
		b:Box(Vector3.new(side[3], 1.2, side[4]), CFrame.new(side[1], 0.6, side[2]), M.SmoothPlastic, HAZ_K, { CastShadow = false })
	end
	for x = -60, 60, 10 do
		b:Box(Vector3.new(0.2, H, 0.15), CFrame.new(x, H / 2, -59.95), M.SmoothPlastic, Color3.fromRGB(170, 172, 176), { CastShadow = false })
		b:Box(Vector3.new(0.2, H, 0.15), CFrame.new(x, H / 2, 59.95), M.SmoothPlastic, Color3.fromRGB(170, 172, 176), { CastShadow = false })
	end
	-- светильники под потолком: ряды панелей
	for x = -48, 48, 24 do
		for z = -36, 36, 24 do
			b:Box(Vector3.new(10, 0.3, 2.4), CFrame.new(x, H - 0.15, z), M.SmoothPlastic, Color3.fromRGB(246, 248, 250), { CastShadow = false })
			b:Lamp(Vector3.new(x, H - 0.6, z), Color3.fromRGB(240, 244, 255), 1.3, 40, 120)
		end
	end
	b:EndGroup()
	b:Bounds(Vector3.new(0, 0, 0), Vector3.new(140, 0, 120), H)

	---------------------------------------------------------------------------
	-- Подготовительные комнаты (запад и восток) за стенами с тремя проходами
	---------------------------------------------------------------------------
	b:Group("PrepRooms")
	for _, sx in ipairs({ -1, 1 }) do
		local wx = sx * 55
		local doors = { -36, 0, 36 }
		local z0 = -60
		for _, dz in ipairs(doors) do
			local a, c = dz - 4, dz + 4
			b:Box(Vector3.new(1.2, 12, a - z0), CFrame.new(wx, 6, (z0 + a) / 2), M.SmoothPlastic, PANEL)
			b:Box(Vector3.new(1.2, 4, 8), CFrame.new(wx, 10, dz), M.SmoothPlastic, PANEL)
			b:Box(Vector3.new(1.3, 0.6, 8.2), CFrame.new(wx, 8.2, dz), M.SmoothPlastic, HAZ_Y, { CastShadow = false })
			z0 = c
		end
		b:Box(Vector3.new(1.2, 12, 60 - z0), CFrame.new(wx, 6, (z0 + 60) / 2), M.SmoothPlastic, PANEL)
		b:Box(Vector3.new(1.2, H - 12, 120), CFrame.new(wx, 12 + (H - 12) / 2, 0), M.SmoothPlastic, Color3.fromRGB(200, 202, 206))
		b:Box(Vector3.new(15, 0.6, 120), CFrame.new(sx * 62.5, 12.3, 0), M.SmoothPlastic, Color3.fromRGB(190, 192, 196))
		-- шкафчики вдоль внешней стены и скамейки
		for z = -52, 52, 8 do
			if math.abs(z) > 6 then
				b:Box(Vector3.new(2.4, 7, 7.6), CFrame.new(sx * 68.6, 3.5, z), M.Metal, sx < 0 and Color3.fromRGB(140, 70, 62) or Color3.fromRGB(62, 86, 130))
			end
		end
		for _, z in ipairs({ -20, 20 }) do
			b:Bench(CFrame.new(sx * 62, 0, z) * CFrame.Angles(0, math.pi / 2, 0))
		end
		b:Lamp(Vector3.new(sx * 62, 11.6, -30), Color3.fromRGB(240, 244, 255), 1.0, 24)
		b:Lamp(Vector3.new(sx * 62, 11.6, 30), Color3.fromRGB(240, 244, 255), 1.0, 24)
	end
	b:EndGroup()

	---------------------------------------------------------------------------
	-- Испытательный путь: рельсы, сани, отбойник
	---------------------------------------------------------------------------
	b:Group("Track")
	b:Box(Vector3.new(92, 0.06, 8), CFrame.new(-2, 0.03, 0), M.Concrete, Color3.fromRGB(116, 118, 122))
	for _, z in ipairs({ -2.2, 2.2 }) do
		b:Box(Vector3.new(92, 0.5, 0.5), CFrame.new(-2, 0.25, z), M.Metal, C.Steel)
	end
	-- отбойник
	b:Box(Vector3.new(6, 9, 18), CFrame.new(47, 4.5, 0), M.Concrete, C.Concrete)
	for i = 0, 5 do
		b:Box(Vector3.new(0.2, 9, 3), CFrame.new(43.9, 4.5, -7.5 + i * 3), M.SmoothPlastic, i % 2 == 0 and HAZ_Y or HAZ_K, { CastShadow = false })
	end
	-- сани с креслом и закреплённым «пассажиром»-манекеном (силуэт)
	local sled = CFrame.new(-12, 0, 0)
	b:Box(Vector3.new(8, 1.2, 6), sled * CFrame.new(0, 1.1, 0), M.Metal, C.SteelDark)
	b:Box(Vector3.new(2.6, 0.5, 3), sled * CFrame.new(0.6, 2.0, 0), M.Fabric, HAZ_K)
	b:Box(Vector3.new(0.5, 3.4, 3), sled * CFrame.new(2.1, 3.6, 0), M.Fabric, HAZ_K)
	b:Box(Vector3.new(1.2, 2.4, 2), sled * CFrame.new(1.3, 3.5, 0), M.SmoothPlastic, Color3.fromRGB(200, 170, 96))
	local head = b:Box(Vector3.new(1.3, 1.3, 1.3), sled * CFrame.new(1.3, 5.3, 0), M.SmoothPlastic, Color3.fromRGB(200, 170, 96))
	head.Shape = Enum.PartType.Ball
	-- запускающая лебёдка в начале пути
	b:Box(Vector3.new(6, 5, 10), CFrame.new(-50, 2.5, 0), M.Metal, C.SteelDark)
	stripes(CFrame.new(-50, 5, 0), 6, 10)
	b:EndGroup()

	---------------------------------------------------------------------------
	-- Укрытия, мишени, оборудование
	---------------------------------------------------------------------------
	b:Group("Cover")
	for _, c in ipairs({
		{ -36, -14, 0, Vector3.new(8, 4.2, 2.4) }, { -36, 14, 0, Vector3.new(8, 4.2, 2.4) },
		{ -20, -24, 0.3, Vector3.new(6, 6, 6) }, { -18, 22, -0.2, Vector3.new(10, 4.2, 2.4) },
		{ 0, -12, 0, Vector3.new(2.4, 4.2, 10) }, { 2, 14, 0, Vector3.new(6, 6, 6) },
		{ 18, -26, 0, Vector3.new(10, 4.2, 2.4) }, { 22, 22, 0.25, Vector3.new(8, 4.2, 2.4) },
		{ 34, -12, 0, Vector3.new(6, 6, 6) }, { 30, 10, 0, Vector3.new(2.4, 4.2, 8) },
		{ -44, -34, 0, Vector3.new(2.4, 7, 10) }, { 44, 34, 0, Vector3.new(2.4, 7, 10) },
		{ -6, -38, 0, Vector3.new(12, 4.2, 2.4) }, { 8, 38, 0, Vector3.new(12, 4.2, 2.4) },
	}) do
		block(CFrame.new(c[1], 0, c[2]) * CFrame.Angles(0, c[3], 0), c[4])
	end
	for _, p in ipairs({ { -28, -4, 0 }, { 20, 5, math.pi }, { -40, 30, 0.4 }, { 40, -30, -0.4 } }) do
		target(CFrame.new(p[1], 0, p[2]) * CFrame.Angles(0, p[3], 0))
	end
	b:Crate(CFrame.new(-26, 0, 36), Vector3.new(4, 4, 4))
	b:Crate(CFrame.new(-22, 0, 37), Vector3.new(3, 3, 3))
	b:Crate(CFrame.new(26, 0, -38), Vector3.new(5, 4, 4))
	b:Barrel(CFrame.new(-48, 0, 18), HAZ_Y)
	b:Barrel(CFrame.new(48, 0, -18), HAZ_Y)
	b:EndGroup()

	---------------------------------------------------------------------------
	-- Пультовая (север, высота 10)
	---------------------------------------------------------------------------
	b:Group("ControlRoom")
	local cy = 10
	b:Box(Vector3.new(36, 1, 14), CFrame.new(0, cy - 0.5, -53), M.SmoothPlastic, Color3.fromRGB(176, 178, 182))
	b:Box(Vector3.new(36, H - cy - 9, 14), CFrame.new(0, cy + 9 + (H - cy - 9) / 2, -53), M.SmoothPlastic, PANEL)
	b:Box(Vector3.new(36, 1.6, 0.6), CFrame.new(0, cy + 0.8, -46.3), M.SmoothPlastic, PANEL)
	b:Glass(Vector3.new(36, 7.4, 0.3), CFrame.new(0, cy + 5.3, -46.3))
	b:Box(Vector3.new(36, 0.6, 0.6), CFrame.new(0, cy + 9.3, -46.3), M.SmoothPlastic, HAZ_K)
	for _, x in ipairs({ -17.7, 17.7 }) do
		b:Box(Vector3.new(0.6, 9, 4), CFrame.new(x, cy + 4.5, -58), M.SmoothPlastic, PANEL)
	end
	for _, x in ipairs({ -9, 0, 9 }) do
		b:Box(Vector3.new(7, 2.8, 2.6), CFrame.new(x, cy + 1.4, -49.2), M.SmoothPlastic, Color3.fromRGB(72, 76, 82))
		b:Box(Vector3.new(2.6, 1.6, 0.2), CFrame.new(x - 1.8, cy + 3.7, -49.8) * CFrame.Angles(-0.2, 0, 0), M.Glass, Color3.fromRGB(40, 60, 70), { CanQuery = true })
		b:Box(Vector3.new(2.6, 1.6, 0.2), CFrame.new(x + 1.8, cy + 3.7, -49.8) * CFrame.Angles(-0.2, 0, 0), M.Glass, Color3.fromRGB(40, 60, 70), { CanQuery = true })
	end
	-- опоры и лестницы с двух сторон (вдоль стены вверх к краям пультовой)
	for _, x in ipairs({ -16, 16 }) do
		b:Column(Vector3.new(x, 0, -47), 0, cy - 1, 1.2, M.Metal, C.SteelDark)
	end
	b:Stairs(CFrame.new(-31, 0, -53) * CFrame.Angles(0, -math.pi / 2, 0), 5, cy, 13, M.Metal, C.SteelDark)
	b:Stairs(CFrame.new(31, 0, -53) * CFrame.Angles(0, math.pi / 2, 0), 5, cy, 13, M.Metal, C.SteelDark)
	b:Lamp(Vector3.new(0, cy + 8.6, -53), Color3.fromRGB(240, 244, 255), 1.0, 20)
	b:EndGroup()

	---------------------------------------------------------------------------
	-- Мостки вдоль южной стены (высота 8)
	---------------------------------------------------------------------------
	b:Group("Gantry")
	local gy = 8
	b:Catwalk(Vector3.new(-38, gy, 55), Vector3.new(38, gy, 55), 6, false)
	b:Rail(Vector3.new(-38, gy, 52.2), Vector3.new(38, gy, 52.2), HAZ_Y)
	for x = -36, 36, 12 do
		b:Column(Vector3.new(x, 0, 52.6), 0, gy - 0.5, 0.8, M.Metal, C.SteelDark)
	end
	b:Stairs(CFrame.new(-51, 0, 55) * CFrame.Angles(0, -math.pi / 2, 0), 5, gy, 13, M.Metal, C.SteelDark)
	b:Stairs(CFrame.new(51, 0, 55) * CFrame.Angles(0, math.pi / 2, 0), 5, gy, 13, M.Metal, C.SteelDark)
	b:EndGroup()

	---------------------------------------------------------------------------
	-- Точки появления
	---------------------------------------------------------------------------
	local E, W, N, S = Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 0, -1), Vector3.new(0, 0, 1)
	for _, z in ipairs({ -50, -38, -28, -8, 8, 28, 38, 50 }) do
		b:Spawn(Vector3.new(-62, 0, z), E, "Red")
		b:Spawn(Vector3.new(62, 0, z), W, "Blue")
	end
	for _, sp in ipairs({ { Vector3.new(0, cy, -53), S }, { Vector3.new(-20, gy, 55), N }, { Vector3.new(20, gy, 55), N },
		{ Vector3.new(-48, 0, -50), E }, { Vector3.new(48, 0, 50), W }, { Vector3.new(0, 0, 28), N }, { Vector3.new(0, 0, -28), S },
		{ Vector3.new(-30, 0, 46), E } }) do
		b:Spawn(sp[1], sp[2])
	end
	return b:Result({ Center = Vector3.new(0, 0, 0) })
end

return Map
