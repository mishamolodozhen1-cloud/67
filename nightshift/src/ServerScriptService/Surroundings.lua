-- Surroundings (v14): окружение магазина — окраина небольшого города ночью.
--   • земля — Terrain: трава, грунт у дороги, лесная подстилка;
--   • за магазином и по сторонам — хвойный лес (ели, пихты) с берёзами;
--   • через дорогу — частный сектор: дома за деревянными заборами, сараи, берёзы во дворах,
--     фонари над калитками; дальше за ними — лес и пятиэтажки с редкими горящими окнами;
--   • вдоль дороги — деревянные столбы с проводами, остановка; дорога уходит за город в лес.
-- Всё это — декорация: игрок туда не доходит (границы парковки), поэтому детали без столкновений
-- и без запросов (CanCollide / CanQuery / CanTouch = false), у деревьев нет теней (дешевле).
-- Модели — Models.Assets.Env*, у хвои и листвы прозрачная текстура ставится в TextureID (Models.Leaves).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Models = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Models"))
local ModelKit = require(script.Parent:WaitForChild("ModelKit"))

local Surroundings = {}

local M = Enum.Material
local SPS = 3.6 -- studs на метр (как у машин и магазина)

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

-- Подготовить образец модели один раз: декорация без столкновений; листва — с прозрачностью
local prepared = {}
local function prepare(name, shadows)
	if prepared[name] ~= nil then
		return prepared[name]
	end
	local tpl = ModelKit.Template(name)
	if not tpl then
		prepared[name] = false
		return false
	end
	local leaves = Models.Leaves[name]
	for _, d in ipairs(tpl:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.CastShadow = shadows == true
			if leaves and d:IsA("MeshPart") then
				for prefix, image in pairs(leaves) do
					if string.sub(d.Name, 1, #prefix) == prefix then
						local sa = d:FindFirstChildOfClass("SurfaceAppearance")
						if sa then
							sa:Destroy()
						end
						pcall(function()
							d.TextureID = image
						end)
						d.Color = Color3.new(1, 1, 1)
					end
				end
			end
		end
	end
	prepared[name] = true
	return true
end

local function place(name, parent, cf, scale, shadows)
	if not prepare(name, shadows) then
		return nil
	end
	return ModelKit.MakeAsset(name, parent, cf, scale)
end

local function part(parent, name, size, cf, color, material, props)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props or {}) do
		p[k] = v
	end
	p.Parent = parent
	return p
end

-- Размер модели по осям мира (GetBoundingBox отдаёт размер в осях самой модели)
local function worldExtent(m)
	local cf, size = m:GetBoundingBox()
	local h = size / 2
	local ex = math.abs(cf.RightVector.X) * h.X + math.abs(cf.UpVector.X) * h.Y + math.abs(cf.LookVector.X) * h.Z
	local ez = math.abs(cf.RightVector.Z) * h.X + math.abs(cf.UpVector.Z) * h.Y + math.abs(cf.LookVector.Z) * h.Z
	return cf, size, ex, ez
end

-------------------------------------------------------------------------------
-- Земля
-------------------------------------------------------------------------------
local function buildGround()
	local T = workspace.Terrain
	-- Воксели Terrain — по 4 studs, у каждого один материал. Поэтому грунт — в слоях ниже −4, а верхний
	-- слой (−4…−0.25) целиком травяной; верх чуть ниже асфальта — под дорогой и магазином земли не видно
	local TOP_Y, TOP_H = -2.125, 3.75
	T:FillBlock(CFrame.new(0, -8, 0), Vector3.new(1400, 8, 1400), M.Ground)
	T:FillBlock(CFrame.new(0, TOP_Y, 0), Vector3.new(1400, TOP_H, 1400), M.Grass)
	-- лесная подстилка за магазином и за частным сектором
	T:FillBlock(CFrame.new(0, TOP_Y, -430), Vector3.new(1400, TOP_H, 620), M.LeafyGrass)
	T:FillBlock(CFrame.new(0, TOP_Y, 470), Vector3.new(1400, TOP_H, 460), M.LeafyGrass)
	-- грунтовые обочины вдоль дороги
	T:FillBlock(CFrame.new(0, TOP_Y, 116), Vector3.new(1400, TOP_H, 8), M.Ground)
	T:FillBlock(CFrame.new(0, TOP_Y, 150), Vector3.new(1400, TOP_H, 8), M.Ground)
	-- раскисшая земля по краям парковки и у заборов
	for _, p in ipairs({ { -190, 40, 24 }, { 185, 60, 30 }, { -120, 166, 18 }, { 60, 166, 16 }, { 230, 30, 20 } }) do
		T:FillBlock(CFrame.new(p[1], TOP_Y, p[2]) * CFrame.Angles(0, math.rad(p[3] * 7), 0), Vector3.new(p[3], TOP_H, p[3] * 0.6), M.Mud)
	end
end

-- Дорога уходит за город: продолжение асфальта, разметки и обочин в обе стороны
local function buildRoad(f)
	for _, side in ipairs({ -1, 1 }) do
		local x0, x1 = 260 * side, 640 * side
		local lo, hi = math.min(x0, x1), math.max(x0, x1)
		part(f, "RoadOut", Vector3.new(hi - lo, 1.25, 14), CFrame.new((lo + hi) / 2, -0.675, 127), rgb(30, 30, 32), M.Asphalt)
		part(f, "WetSheenOut", Vector3.new(hi - lo, 0.02, 14), CFrame.new((lo + hi) / 2, -0.03, 127), rgb(20, 22, 26), M.Glass, { Transparency = 0.7, Reflectance = 0.28, CastShadow = false })
		for x = lo + 4, hi - 10, 14 do
			part(f, "RoadLineOut", Vector3.new(7, 0.02, 0.4), CFrame.new(x + 3.5, -0.03, 127), rgb(220, 220, 210), M.SmoothPlastic, { CastShadow = false })
		end
	end
end

-------------------------------------------------------------------------------
-- Лес: случайная расстановка с минимальным расстоянием и запретными зонами
-------------------------------------------------------------------------------
local TREES = {
	-- имя, высота от, высота до (studs), высота модели в файле, радиус кроны (studs на 1 stud высоты)
	Pine = { "EnvPine", 54, 80, 75, 0.17 },
	Spruce = { "EnvSpruce", 66, 95, 10.52, 0.12 },
	Fir = { "EnvFir", 42, 60, 4.39, 0.2 },
	Birch = { "EnvBirch", 46, 64, 8.16, 0.2 },
}

local rng = Random.new(2411)
local occupied = {} -- {x, z, r}
local blocked = {} -- прямоугольники {x0, z0, x1, z1}

local function isFree(x, z, r)
	for _, b in ipairs(blocked) do
		if x > b[1] - r and x < b[3] + r and z > b[2] - r and z < b[4] + r then
			return false
		end
	end
	for _, o in ipairs(occupied) do
		local dx, dz = x - o[1], z - o[2]
		local rr = r + o[3]
		if dx * dx + dz * dz < rr * rr then
			return false
		end
	end
	return true
end

local function block(x0, z0, x1, z1)
	table.insert(blocked, { math.min(x0, x1), math.min(z0, z1), math.max(x0, x1), math.max(z0, z1) })
end

local count = { trees = 0 }

local function tree(parent, kind, x, z)
	local def = TREES[kind]
	local h = rng:NextNumber(def[2], def[3])
	local cf = CFrame.new(x, -0.7, z) * CFrame.Angles(math.rad(rng:NextNumber(-2.5, 2.5)), rng:NextNumber(0, math.pi * 2), math.rad(rng:NextNumber(-2.5, 2.5)))
	local m = place(def[1], parent, cf, h / def[4], false)
	if m then
		count.trees = count.trees + 1
	end
	return m
end

-- n деревьев в прямоугольнике; mix — веса пород; spacing — минимальное расстояние между стволами;
-- bias > 1 — гуще у стороны z0
local function forest(parent, n, x0, z0, x1, z1, mix, spacing, bias)
	local total = 0
	for _, w in pairs(mix) do
		total = total + w
	end
	local made, tries = 0, 0
	while made < n and tries < n * 30 do
		tries = tries + 1
		local u = rng:NextNumber()
		if bias then
			u = u ^ bias
		end
		local x = x0 + (x1 - x0) * rng:NextNumber()
		local z = z0 + (z1 - z0) * u
		local r = spacing * rng:NextNumber(0.8, 1.25)
		if isFree(x, z, r) then
			local pick = rng:NextNumber() * total
			local kind = "Pine"
			for k, w in pairs(mix) do
				pick = pick - w
				if pick <= 0 then
					kind = k
					break
				end
			end
			if tree(parent, kind, x, z) then
				table.insert(occupied, { x, z, r })
				made = made + 1
			end
		end
	end
	return made
end

-------------------------------------------------------------------------------
-- Частный сектор через дорогу
-------------------------------------------------------------------------------
-- модель, масштаб, поворот к дороге (рад; nil — как получится), ширина участка, занятая домом
local HOUSES = {
	{ "EnvHouseVodum", SPS, math.rad(-90) }, -- вход со ступеньками — к дороге
	{ "EnvHouseAki", 1.6 * SPS, nil },
	{ "EnvHouseSmall", 0.8 * SPS, nil },
	{ "EnvHouseBrick", 1.7 * SPS, nil },
	{ "EnvHouseLong", 0.9 * SPS, 0 },
}

local FENCE_LEN = 10.2 -- длина секции забора, studs
local FENCE_SCALE = FENCE_LEN / 284.5

local function gateLamp(parent, x, z)
	part(parent, "GateLampPost", Vector3.new(0.35, 9, 0.35), CFrame.new(x, 4.5, z), rgb(52, 48, 44), M.Wood)
	part(parent, "GateLampArm", Vector3.new(0.25, 0.25, 1.6), CFrame.new(x, 8.8, z - 0.7), rgb(52, 48, 44), M.Wood)
	local bulb = part(parent, "GateLamp", Vector3.new(0.5, 0.5, 0.5), CFrame.new(x, 8.45, z - 1.4), rgb(255, 196, 120), M.Neon, { CastShadow = false })
	local l = Instance.new("PointLight")
	l.Color = rgb(255, 186, 112)
	l.Range = 18
	l.Brightness = 0.9
	l.Shadows = false
	l.Parent = bulb
end

local function buildPrivateSector(f)
	local plotW = 41
	local fenceZ = 152.5
	local plots = 12
	for i = 0, plots - 1 do
		local cx = -225.5 + plotW * i
		local x0 = cx - plotW / 2
		local plot = Instance.new("Model")
		plot.Name = "Plot" .. (i + 1)
		plot.Parent = f
		local kind = (i == 4) and "empty" or ((i == 9) and "shack" or "house")
		-- забор вдоль улицы с калиткой
		local gate = x0 + rng:NextNumber(6, 12)
		local x = x0
		while x < x0 + plotW - 1 do
			local len = math.min(FENCE_LEN, x0 + plotW - x)
			if not (gate >= x and gate < x + len) and len > FENCE_LEN * 0.6 and kind ~= "empty" then
				place("EnvFence", plot, CFrame.new(x + FENCE_LEN / 2, -0.3, fenceZ) * CFrame.Angles(0, math.rad(90), 0), FENCE_SCALE, true)
			end
			x = x + FENCE_LEN
		end
		if kind == "house" then
			local h = HOUSES[(i % #HOUSES) + 1]
			if i == 7 then
				h = HOUSES[1]
			end
			local yaw = h[3] or (rng:NextNumber() < 0.5 and 0 or math.pi)
			yaw = yaw + math.rad(rng:NextNumber(-6, 6))
			local m = place(h[1], plot, CFrame.new(cx + rng:NextNumber(-3, 3), -0.4, 180 + rng:NextNumber(-4, 4)) * CFrame.Angles(0, yaw, 0), h[2], true)
			if m then
				local cf, _, ex, ez = worldExtent(m)
				block(cf.Position.X - ex - 4, cf.Position.Z - ez - 4, cf.Position.X + ex + 4, cf.Position.Z + ez + 4)
			end
			-- сарай в глубине двора
			if i % 3 == 1 then
				place("EnvShed", plot, CFrame.new(cx + rng:NextNumber(-10, 10), -0.3, 206) * CFrame.Angles(0, math.rad(rng:NextNumber(-10, 10)), 0), 0.01 * SPS, true)
				block(cx - 14, 196, cx + 14, 216)
			end
			if i % 4 == 2 then
				gateLamp(plot, gate + 1.5, fenceZ - 1)
			end
		elseif kind == "shack" then
			-- заброшенный участок: покосившаяся лачуга и бурьян из берёз
			place("EnvShack", plot, CFrame.new(cx, -0.4, 182) * CFrame.Angles(math.rad(1.5), math.rad(rng:NextNumber(0, 360)), 0), 0.7 * SPS, true)
			block(cx - 16, 166, cx + 16, 198)
		end
		-- берёзы и ели во дворе (у пустого участка — целая роща)
		local n = kind == "empty" and 4 or 2
		forest(plot, n, x0 + 3, 158, x0 + plotW - 3, 214, kind == "empty" and { Birch = 3, Pine = 1 } or { Birch = 1, Pine = 1.4 }, 7)
	end
	gateLamp(f, -246, fenceZ - 1) -- у крайнего участка
end

-------------------------------------------------------------------------------
-- Пятиэтажки вдалеке (за частным сектором), редкие горящие окна на стороне к магазину
-------------------------------------------------------------------------------
local function litWindows(parent, m, seed)
	local cf, size = m:GetBoundingBox()
	local r = Random.new(seed)
	-- фасад, который смотрит к магазину (на юг, −Z мира)
	local best, normal, half, tangent, width = nil, nil, 0, nil, 0
	for _, ax in ipairs({ { cf.RightVector, size.X, cf.LookVector, size.Z }, { -cf.RightVector, size.X, cf.LookVector, size.Z }, { cf.LookVector, size.Z, cf.RightVector, size.X }, { -cf.LookVector, size.Z, cf.RightVector, size.X } }) do
		local n = ax[1]
		if not best or n.Z < best then
			best, normal, half, tangent, width = n.Z, n, ax[2] / 2, ax[3], ax[4]
		end
	end
	local floors = 5
	local cols = math.max(2, math.floor(width / 9))
	local bottom = cf.Position.Y - size.Y / 2
	for _ = 1, 9 do
		local col = r:NextInteger(1, cols)
		local fl = r:NextInteger(0, floors - 1)
		local along = -width / 2 + (col - 0.5) * (width / cols)
		local y = bottom + size.Y * 0.1 + fl * (size.Y * 0.76 / floors) + 3
		local pos = Vector3.new(cf.Position.X, y, cf.Position.Z) + normal * (half + 0.25) + tangent * along
		local warm = r:NextNumber() < 0.75
		part(parent, "LitWindow", Vector3.new(4.2, 4.6, 0.2), CFrame.lookAt(pos, pos + normal), warm and rgb(255, 208, 140) or rgb(170, 200, 255), M.Neon, { CastShadow = false, Transparency = 0.15 })
	end
end

local function buildBlocks(f)
	local list = {
		{ "EnvPanel5", Vector3.new(-160, -0.5, 300), 0, SPS },
		{ "EnvKhrush", Vector3.new(110, -0.5, 330), math.rad(-90), 8.3 },
		{ "EnvPanel5", Vector3.new(330, -0.5, 285), math.rad(4), SPS },
	}
	for i, b in ipairs(list) do
		local m = place(b[1], f, CFrame.new(b[2]) * CFrame.Angles(0, b[3], 0), b[4], false)
		if m then
			local cf, _, ex, ez = worldExtent(m)
			block(cf.Position.X - ex - 8, cf.Position.Z - ez - 8, cf.Position.X + ex + 8, cf.Position.Z + ez + 8)
			litWindows(f, m, 30 + i)
		end
	end
end

-------------------------------------------------------------------------------
-- Столбы с проводами вдоль дороги (по стороне частного сектора) и остановка
-------------------------------------------------------------------------------
local function wire(holder, a, b)
	-- провод — тонкий луч, провисает посередине (кривая Безье: концы уходят вниз)
	local a0 = Instance.new("Attachment")
	a0.Parent = holder
	a0.WorldCFrame = CFrame.fromMatrix(a, Vector3.new(0, -1, 0), (b - a).Unit:Cross(Vector3.new(0, -1, 0)).Unit)
	local a1 = Instance.new("Attachment")
	a1.Parent = holder
	a1.WorldCFrame = CFrame.fromMatrix(b, Vector3.new(0, 1, 0), (b - a).Unit:Cross(Vector3.new(0, 1, 0)).Unit)
	local beam = Instance.new("Beam")
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	local sag = (b - a).Magnitude * 0.035
	beam.CurveSize0 = sag * 1.33
	beam.CurveSize1 = sag * 1.33
	beam.Width0 = 0.09
	beam.Width1 = 0.09
	beam.FaceCamera = true
	beam.Segments = 12
	beam.Color = ColorSequence.new(rgb(18, 18, 20))
	beam.LightInfluence = 1
	beam.Transparency = NumberSequence.new(0.05)
	beam.Parent = holder
end

-- Деревянный столб на бетонном «пасынке» (как вдоль сельских дорог): опора, траверса, четыре изолятора.
-- Собран из деталей (модель столба была слишком тяжёлой: 7 300 треугольников на каждый)
local function pole(parent, x, z, lean)
	local m = Instance.new("Model")
	m.Name = "Pole"
	local base = CFrame.new(x, -0.6, z) * CFrame.Angles(math.rad(lean.X), 0, math.rad(lean.Z))
	part(m, "Stub", Vector3.new(1.0, 9.5, 1.0), base * CFrame.new(0, 4.75, 0), rgb(120, 120, 116), M.Concrete, { CastShadow = false })
	part(m, "PoleWood", Vector3.new(30, 1.05, 1.05), base * CFrame.new(-1.0, 16.5, 0) * CFrame.Angles(0, 0, math.rad(90)), rgb(66, 54, 44), M.Wood, { CastShadow = false, Shape = Enum.PartType.Cylinder })
	for _, y in ipairs({ 2.6, 7.6 }) do
		part(m, "Band", Vector3.new(2.25, 0.25, 1.25), base * CFrame.new(-0.5, y, 0), rgb(40, 40, 42), M.Metal, { CastShadow = false })
	end
	part(m, "Traverse", Vector3.new(0.45, 0.45, 7.6), base * CFrame.new(-1.0, 29.4, 0), rgb(58, 58, 60), M.Metal, { CastShadow = false })
	local tops = {}
	for i, dz in ipairs({ -3.3, -1.2, 1.2, 3.3 }) do
		local c = base * CFrame.new(-1.0, 30.1, dz)
		part(m, "Insulator", Vector3.new(0.9, 0.5, 0.5), c * CFrame.Angles(0, 0, math.rad(90)), rgb(190, 200, 205), M.Glass, { CastShadow = false, Shape = Enum.PartType.Cylinder })
		tops[i] = (c * CFrame.new(0, 0.45, 0)).Position
	end
	m.Parent = parent
	return tops
end

local function buildPowerLine(f)
	local holder = part(f, "Wires", Vector3.new(0.2, 0.2, 0.2), CFrame.new(0, 20, 149), rgb(0, 0, 0), M.SmoothPlastic, { Transparency = 1, CastShadow = false })
	local prev = nil
	local poles = 0
	for x = -495, 495, 55 do
		local tops = pole(f, x, 149.2, Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1.4, 1.4)))
		poles = poles + 1
		if prev then
			for i = 1, 4 do
				wire(holder, prev[i], tops[i])
			end
		end
		prev = tops
	end
	return poles
end

local function buildBusStop(f)
	-- открытой стороной к дороге, вдоль тротуара напротив магазина
	local m = place("EnvBusStop", f, CFrame.new(84, 0.25, 141.2) * CFrame.Angles(0, math.rad(-90), 0), 0.0583, true)
	if m then
		local sign = part(f, "BusSignPost", Vector3.new(0.3, 9, 0.3), CFrame.new(72, 4.6, 137), rgb(70, 72, 76), M.Metal)
		local plate = part(f, "BusSign", Vector3.new(0.12, 2.2, 2.2), CFrame.new(72, 8.4, 137), rgb(30, 90, 170), M.SmoothPlastic)
		local sg = Instance.new("SurfaceGui")
		sg.Face = Enum.NormalId.Front
		sg.PixelsPerStud = 50
		sg.Parent = plate
		local t = Instance.new("TextLabel")
		t.Size = UDim2.fromScale(1, 1)
		t.BackgroundTransparency = 1
		t.Text = "A"
		t.TextScaled = true
		t.Font = Enum.Font.GothamBlack
		t.TextColor3 = Color3.new(1, 1, 1)
		t.Parent = sg
		plate.CFrame = CFrame.lookAt(plate.Position, plate.Position + Vector3.new(1, 0, 0))
		sign.CastShadow = false
	end
end

-------------------------------------------------------------------------------
function Surroundings.Build()
	local old = workspace:FindFirstChild("Environment")
	if old then
		old:Destroy()
	end
	local f = Instance.new("Folder")
	f.Name = "Environment"
	local started = os.clock()
	buildGround()
	buildRoad(f)
	-- запретные зоны: магазин с двором, парковка, дорога с обочинами
	block(-84, -114, 58, 58)
	block(-172, 48, 172, 121)
	block(-700, 111, 700, 153)
	local village = Instance.new("Folder")
	village.Name = "Village"
	village.Parent = f
	buildPrivateSector(village)
	block(-252, 150, 252, 217) -- участки: дальше в них деревья не сажаем
	buildBlocks(f)
	local poles = buildPowerLine(f)
	buildBusStop(f)
	local woods = Instance.new("Folder")
	woods.Name = "Forest"
	woods.Parent = f
	-- лес за магазином: гуще у его задней стены
	forest(woods, 84, -440, -116, 440, -470, { Pine = 10, Spruce = 0.7, Fir = 0.8, Birch = 0.25 }, 11, 1.7)
	-- по сторонам от парковки
	forest(woods, 22, -460, -116, -176, 112, { Pine = 7, Birch = 1, Spruce = 0.6, Fir = 0.6 }, 12)
	forest(woods, 22, 176, -116, 460, 112, { Pine = 7, Birch = 1, Spruce = 0.6, Fir = 0.6 }, 12)
	-- поляны по бокам от магазина: редкие ели и берёзы, ближе к лесу гуще
	forest(woods, 9, -172, -114, -88, 46, { Birch = 1.5, Pine = 2, Fir = 1 }, 14)
	forest(woods, 9, 62, -114, 172, 46, { Birch = 1.5, Pine = 2, Fir = 1 }, 14)
	-- за частным сектором и вдоль дороги за городом
	forest(woods, 36, -480, 219, 480, 470, { Pine = 9, Birch = 0.6, Spruce = 0.5 }, 12, 1.4)
	forest(woods, 10, -660, 154, -258, 220, { Pine = 6, Birch = 0.6, Fir = 0.5 }, 11)
	forest(woods, 10, 258, 154, 660, 220, { Pine = 6, Birch = 0.6, Fir = 0.5 }, 11)
	forest(woods, 8, -660, 40, -470, 110, { Pine = 5, Spruce = 0.6 }, 12)
	forest(woods, 8, 470, 40, 660, 110, { Pine = 5, Spruce = 0.6 }, 12)
	-- заброшенная лачуга на опушке слева от парковки
	place("EnvShack", f, CFrame.new(-214, -0.5, 36) * CFrame.Angles(math.rad(-1.5), math.rad(28), math.rad(2)), 0.7 * SPS, true)
	f.Parent = workspace
	local parts = 0
	for _, d in ipairs(f:GetDescendants()) do
		if d:IsA("BasePart") then
			parts = parts + 1
		end
	end
	f:SetAttribute("Trees", count.trees)
	f:SetAttribute("Parts", parts)
	f:SetAttribute("Poles", poles)
	print(string.format("[Окружение] деревьев %d, деталей %d, столбов %d — за %.1f с", count.trees, parts, poles, os.clock() - started))
	return f
end

return Surroundings
