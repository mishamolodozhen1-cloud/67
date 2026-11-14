-- Городская инфраструктура для РП: тротуары с бордюрами, разметка, зебры, стоп-линии, светофоры,
-- таблички улиц (рус/тат), остановки, скамейки, урны, фонари, фонтаны, вывески заведений и адреса.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Settings = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Settings"))
local Data = require(script.Parent:WaitForChild("CityData"):WaitForChild("Infra"))

local Infrastructure = {}

local SMOOTH = Enum.SurfaceType.Smooth
local CYL_UP = CFrame.Angles(0, 0, math.rad(90))
local UP = Vector3.new(0, 1, 0)
local WHITE = Color3.fromRGB(240, 240, 236)
local IRON = Color3.fromRGB(44, 46, 50)
local MARK_Y = 0.33

local count = 0
local function tick()
	count = count + 1
	if count % 300 == 0 then
		task.wait()
	end
end

local function part(parent, size, cf, color, material, props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = SMOOTH
	p.BottomSurface = SMOOTH
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	if props then
		for k, v in pairs(props) do
			p[k] = v
		end
	end
	p.Parent = parent
	tick()
	return p
end

local function each(chunks, fn)
	for _, chunk in ipairs(chunks or {}) do
		for rec in string.gmatch(chunk, "[^;]+") do
			fn(string.split(rec, ","))
		end
	end
end

local function folder(name, parent)
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

local function v2(x, z)
	return Vector3.new(tonumber(x), 0, tonumber(z))
end

-- Рамка, у которой локальная X идёт вдоль dir (горизонтально), а лицевая сторона (-Z) смотрит наружу.
local function alongFrame(pos, dir)
	return CFrame.fromMatrix(pos, dir, UP)
end

local function facing(pos, dir)
	return CFrame.lookAt(pos, pos + dir)
end

-- Надпись на грани детали
local function surfaceText(p, face, lines, textColor, ppS, maxDist)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = ppS or 40
	gui.LightInfluence = 0.4
	gui.MaxDistance = maxDist or 260
	gui.Parent = p
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Vertical
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.Parent = gui
	for i, line in ipairs(lines) do
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Size = UDim2.fromScale(1, line[2])
		l.Text = line[1]
		l.TextScaled = true
		l.Font = (i == 1) and Enum.Font.GothamBlack or Enum.Font.GothamBold
		l.TextColor3 = textColor or WHITE
		l.LayoutOrder = i
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0.04, 0)
		pad.PaddingRight = UDim.new(0.04, 0)
		pad.Parent = l
		l.Parent = gui
	end
	return gui
end

-------------------------------------------------------------------------------
-- Тротуары, бордюры, разметка, переходы
-------------------------------------------------------------------------------
local function buildStreetsurface(root)
	local walks = folder("Sidewalks", root)
	each(Data.Sidewalks, function(f)
		local a, b = v2(f[1], f[2]), v2(f[3], f[4])
		local w = tonumber(f[5])
		local len = (b - a).Magnitude
		if len < 0.2 then
			return
		end
		part(walks, Vector3.new(w, 1, len + 1.5), CFrame.lookAt((a + b) / 2, b) + Vector3.new(0, 0.4, 0),
			Color3.fromRGB(192, 188, 180), Enum.Material.Pavement, { CastShadow = false })
	end)
	each(Data.Curbs, function(f)
		local a, b = v2(f[1], f[2]), v2(f[3], f[4])
		local len = (b - a).Magnitude
		if len < 0.2 then
			return
		end
		part(walks, Vector3.new(tonumber(f[5]), 1.15, len + 0.6), CFrame.lookAt((a + b) / 2, b) + Vector3.new(0, 0.42, 0),
			Color3.fromRGB(214, 212, 206), Enum.Material.Concrete, { CastShadow = false })
	end)

	local marks = folder("RoadMarkings", root)
	local function stripe(a, b, width, offset)
		local len = (b - a).Magnitude
		local cf = CFrame.lookAt((a + b) / 2, b)
		part(marks, Vector3.new(width, 0.05, len), cf * CFrame.new(offset or 0, MARK_Y, 0), WHITE, Enum.Material.SmoothPlastic,
			{ CanCollide = false, CastShadow = false, CanQuery = false })
	end
	each(Data.Markings, function(f)
		local a, b = v2(f[1], f[2]), v2(f[3], f[4])
		local len = (b - a).Magnitude
		if len < 1 then
			return
		end
		if f[5] == "s" then
			stripe(a, b, 0.4, -0.55)
			stripe(a, b, 0.4, 0.55)
		else
			local dir = (b - a).Unit
			local dash, period = 9, 27
			local t = 2
			while t + dash <= len do
				stripe(a + dir * t, a + dir * (t + dash), 0.5)
				t = t + period
			end
		end
	end)
	each(Data.StopLines, function(f)
		local a, b = v2(f[1], f[2]), v2(f[3], f[4])
		local len = (b - a).Magnitude
		if len > 0.5 then
			part(marks, Vector3.new(1.4, 0.05, len), CFrame.lookAt((a + b) / 2, b) + Vector3.new(0, MARK_Y, 0), WHITE,
				Enum.Material.SmoothPlastic, { CanCollide = false, CastShadow = false, CanQuery = false })
		end
	end)
	each(Data.Crossings, function(f)
		local c = v2(f[1], f[2])
		local u = Vector3.new(tonumber(f[3]), 0, tonumber(f[4]))
		local w = tonumber(f[5])
		-- Прозрачная пластина с текстурой полос «зебры» (полосы вдоль дороги, повторяются поперёк)
		local p = part(marks, Vector3.new(w - 2, 0.05, 10), CFrame.lookAt(c, c + u) + Vector3.new(0, MARK_Y + 0.01, 0), WHITE,
			Enum.Material.SmoothPlastic, { Transparency = 1, CanCollide = false, CastShadow = false, CanQuery = false })
		local tex = Instance.new("Texture")
		tex.Texture = Settings.Textures.Zebra
		tex.Face = Enum.NormalId.Top
		tex.StudsPerTileU = 4.4
		tex.StudsPerTileV = 10
		tex.Parent = p
	end)
end

-------------------------------------------------------------------------------
-- Светофоры (лампы переключает клиент синхронно по серверному времени)
-------------------------------------------------------------------------------
local function buildTrafficLights(root)
	local f0 = folder("TrafficLights", root)
	each(Data.Lights, function(f)
		local pos = v2(f[1], f[2])
		local dir = Vector3.new(tonumber(f[3]), 0, tonumber(f[4]))
		local model = Instance.new("Model")
		model.Name = "TrafficLight"
		model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
		model:SetAttribute("Axis", tonumber(f[5]))
		model:SetAttribute("Group", tonumber(f[6]))
		local pole = part(model, Vector3.new(15, 0.7, 0.7), CFrame.new(pos + Vector3.new(0, 7.5, 0)) * CYL_UP, IRON, Enum.Material.Metal)
		pole.Shape = Enum.PartType.Cylinder
		local headPos = pos + Vector3.new(0, 13, 0) + dir * 0.6
		local head = part(model, Vector3.new(1.6, 4.8, 1.3), facing(headPos, dir), Color3.fromRGB(28, 30, 32), Enum.Material.Metal)
		head.Name = "Head"
		for i, name in ipairs({ "Red", "Yellow", "Green" }) do
			local lamp = part(model, Vector3.new(1.1, 1.1, 1.1), head.CFrame * CFrame.new(0, 1.5 - (i - 1) * 1.5, -0.62), Color3.fromRGB(40, 40, 40),
				Enum.Material.SmoothPlastic, { Shape = Enum.PartType.Ball, CastShadow = false })
			lamp.Name = name
		end
		-- козырёк
		part(model, Vector3.new(1.8, 0.2, 1.4), head.CFrame * CFrame.new(0, 2.5, -0.4), Color3.fromRGB(28, 30, 32), Enum.Material.Metal)
		model.Parent = f0
		CollectionService:AddTag(model, "TrafficLight")
	end)
end

-------------------------------------------------------------------------------
-- Таблички с названиями улиц на перекрёстках
-------------------------------------------------------------------------------
local function blade(parent, polePos, y, dirX, dirZ, label)
	local dir = Vector3.new(tonumber(dirX), 0, tonumber(dirZ))
	local parts = string.split(label, "|")
	local ru, tt = parts[1], parts[2]
	local len = math.clamp(#ru * 0.42, 9, 20)
	local pos = polePos + Vector3.new(0, y, 0) + dir * (len / 2 + 0.3)
	local b = part(parent, Vector3.new(len, tt and 3 or 2.2, 0.2), alongFrame(pos, dir), Color3.fromRGB(0, 72, 150), Enum.Material.SmoothPlastic)
	local lines = tt and { { ru, 0.56 }, { tt, 0.38 } } or { { ru, 0.9 } }
	surfaceText(b, Enum.NormalId.Front, lines, WHITE, 36, 220)
	surfaceText(b, Enum.NormalId.Back, lines, WHITE, 36, 220)
end

local function buildStreetSigns(root)
	local f0 = folder("StreetSigns", root)
	each(Data.StreetSigns, function(f)
		local pos = v2(f[1], f[2])
		local pole = part(f0, Vector3.new(14, 0.4, 0.4), CFrame.new(pos + Vector3.new(0, 7, 0)) * CYL_UP, Color3.fromRGB(110, 114, 120), Enum.Material.Metal)
		pole.Shape = Enum.PartType.Cylinder
		blade(f0, pos, 13, f[4], f[5], f[3])
		blade(f0, pos, 9.8, f[7], f[8], f[6])
	end)
end

-------------------------------------------------------------------------------
-- Остановки общественного транспорта
-------------------------------------------------------------------------------
local function buildStops(root)
	local f0 = folder("BusStops", root)
	each(Data.Stops, function(f)
		local pos = v2(f[1], f[2]) + Vector3.new(0, 0.9, 0)
		local dir = Vector3.new(tonumber(f[3]), 0, tonumber(f[4]))
		local name = f[5]
		local base = facing(pos, dir)
		local glass = Color3.fromRGB(170, 200, 220)
		part(f0, Vector3.new(17, 0.3, 7.5), base * CFrame.new(0, 0.15, 0), Color3.fromRGB(150, 150, 146), Enum.Material.Concrete)
		part(f0, Vector3.new(16, 7.6, 0.25), base * CFrame.new(0, 4, 3.2), glass, Enum.Material.Glass, { Transparency = 0.55 })
		for _, sx in ipairs({ -1, 1 }) do
			part(f0, Vector3.new(0.25, 7.6, 5.6), base * CFrame.new(sx * 8, 4, 0.5), glass, Enum.Material.Glass, { Transparency = 0.55 })
			part(f0, Vector3.new(0.4, 8, 0.4), base * CFrame.new(sx * 8, 4.1, 3.2), IRON, Enum.Material.Metal)
			part(f0, Vector3.new(0.4, 8, 0.4), base * CFrame.new(sx * 8, 4.1, -2.4), IRON, Enum.Material.Metal)
		end
		part(f0, Vector3.new(17.5, 0.5, 7.8), base * CFrame.new(0, 8.3, 0.4), Color3.fromRGB(40, 70, 110), Enum.Material.Metal)
		local plate = part(f0, Vector3.new(17, 1.6, 0.2), base * CFrame.new(0, 7.4, -3.4), Color3.fromRGB(0, 72, 150), Enum.Material.SmoothPlastic,
			{ CanCollide = false })
		surfaceText(plate, Enum.NormalId.Front, { { "ОСТАНОВКА · " .. name, 1 } }, WHITE, 30, 200)
		part(f0, Vector3.new(12, 0.35, 1.8), base * CFrame.new(0, 2.1, 2.2), Color3.fromRGB(128, 86, 52), Enum.Material.Wood)
		part(f0, Vector3.new(12, 1.8, 0.3), base * CFrame.new(0, 1.0, 2.9), IRON, Enum.Material.Metal)
		-- знак «А» на столбе
		local pole = part(f0, Vector3.new(11, 0.35, 0.35), base * CFrame.new(10.5, 5.5, -1.5) * CYL_UP, Color3.fromRGB(110, 114, 120), Enum.Material.Metal)
		pole.Shape = Enum.PartType.Cylinder
		local sign = part(f0, Vector3.new(2.6, 2.6, 0.15), base * CFrame.new(10.5, 10, -1.5) * CFrame.Angles(0, math.rad(90), 0),
			Color3.fromRGB(0, 90, 170), Enum.Material.SmoothPlastic)
		surfaceText(sign, Enum.NormalId.Front, { { "А", 1 } }, WHITE, 40, 220)
		surfaceText(sign, Enum.NormalId.Back, { { "А", 1 } }, WHITE, 40, 220)
	end)
end

-------------------------------------------------------------------------------
-- Скамейки, урны, фонари, фонтаны
-------------------------------------------------------------------------------
local function streetLamp(parent, pos, dir)
	local pole = part(parent, Vector3.new(24, 0.7, 0.7), CFrame.new(pos + Vector3.new(0, 12, 0)) * CYL_UP, IRON, Enum.Material.Metal, { CastShadow = false })
	pole.Shape = Enum.PartType.Cylinder
	local head = pos + Vector3.new(0, 24, 0) + dir * 2.5
	part(parent, Vector3.new(1.2, 0.5, 5), CFrame.lookAt(pos + Vector3.new(0, 24.2, 0) + dir * 1.5, head + dir), IRON, Enum.Material.Metal, { CastShadow = false })
	local bulb = part(parent, Vector3.new(1.1, 0.3, 2), CFrame.lookAt(head - Vector3.new(0, 0.3, 0), head + dir - Vector3.new(0, 0.3, 0)),
		Color3.fromRGB(255, 236, 200), Enum.Material.Neon, { CastShadow = false })
	local light = Instance.new("SpotLight")
	light.Face = Enum.NormalId.Bottom
	light.Angle = 120
	light.Range = 42
	light.Brightness = 1.5
	light.Color = Color3.fromRGB(255, 220, 170)
	light.Shadows = false
	light.Parent = bulb
end

local function fountain(parent, pos, radius)
	local r = math.clamp(radius, 6, 60)
	local basin = part(parent, Vector3.new(2.4, r * 2, r * 2), CFrame.new(pos + Vector3.new(0, 1.2, 0)) * CYL_UP,
		Color3.fromRGB(176, 170, 160), Enum.Material.Granite, { Shape = Enum.PartType.Cylinder })
	basin.Name = "FountainBasin"
	part(parent, Vector3.new(0.4, r * 2 - 2, r * 2 - 2), CFrame.new(pos + Vector3.new(0, 2.2, 0)) * CYL_UP,
		Color3.fromRGB(80, 140, 170), Enum.Material.Glass, { Shape = Enum.PartType.Cylinder, Transparency = 0.3, CanCollide = false, Reflectance = 0.2 })
	local jet = part(parent, Vector3.new(1.5, 1.5, 1.5), CFrame.new(pos + Vector3.new(0, 2.6, 0)), Color3.fromRGB(176, 170, 160), Enum.Material.Granite)
	local water = Instance.new("ParticleEmitter")
	water.Texture = "rbxasset://textures/particles/smoke_main.dds"
	water.Color = ColorSequence.new(Color3.fromRGB(200, 230, 250))
	water.Rate = 60
	water.Lifetime = NumberRange.new(1, 1.4)
	water.Speed = NumberRange.new(math.min(r, 24), math.min(r, 24) + 4)
	water.SpreadAngle = Vector2.new(8, 8)
	water.Acceleration = Vector3.new(0, -40, 0)
	water.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1.6) })
	water.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
	water.EmissionDirection = Enum.NormalId.Top
	water.Parent = jet
end

local function buildProps(root)
	local f0 = folder("StreetFurniture", root)
	each(Data.Props, function(f)
		local kind = f[1]
		local pos = v2(f[2], f[3])
		local dir = Vector3.new(tonumber(f[4]), 0, tonumber(f[5]))
		if kind == "b" then
			local base = facing(pos, dir)
			local wood = Color3.fromRGB(132, 88, 54)
			part(f0, Vector3.new(6, 0.35, 1.8), base * CFrame.new(0, 1.7, 0), wood, Enum.Material.Wood)
			part(f0, Vector3.new(6, 1.5, 0.3), base * CFrame.new(0, 2.7, 0.85), wood, Enum.Material.Wood)
			part(f0, Vector3.new(0.3, 1.7, 1.8), base * CFrame.new(-2.6, 0.85, 0), IRON, Enum.Material.Metal)
			part(f0, Vector3.new(0.3, 1.7, 1.8), base * CFrame.new(2.6, 0.85, 0), IRON, Enum.Material.Metal)
		elseif kind == "t" then
			local bin = part(f0, Vector3.new(2.8, 1.6, 1.6), CFrame.new(pos + Vector3.new(0, 1.4, 0)) * CYL_UP, Color3.fromRGB(46, 78, 58), Enum.Material.Metal)
			bin.Shape = Enum.PartType.Cylinder
			bin.Name = "TrashBin"
		elseif kind == "l" then
			streetLamp(f0, pos, dir)
		elseif kind == "f" then
			fountain(f0, pos, 8)
		elseif kind == "F" then
			fountain(f0, pos, tonumber(f[4]))
		end
	end)
end

-------------------------------------------------------------------------------
-- Вывески заведений, витрины, отдельные указатели, адресные таблички
-------------------------------------------------------------------------------
local CAT_TITLES = {
	police = "ПОЛИЦИЯ", medical = "МЕДИЦИНА", pharmacy = "АПТЕКА", fire = "ПОЖАРНАЯ ЧАСТЬ", bank = "БАНК",
	food_shop = "ПРОДУКТЫ", shop = "МАГАЗИН", food = "КАФЕ", hotel = "ОТЕЛЬ", post = "ПОЧТА",
	culture = "КУЛЬТУРА", education = "УЧЁБА", gov = "ГОСУЧРЕЖДЕНИЕ", fuel = "АЗС",
}

local function buildSigns(root)
	local f0 = folder("Signs", root)
	each(Data.ShopSigns, function(f)
		local cat, color, name = f[1], Color3.fromHex(f[2]), f[3]
		local pos = v2(f[4], f[5])
		local n = Vector3.new(tonumber(f[6]), 0, tonumber(f[7]))
		local width = tonumber(f[8])
		local store = f[9] == "1"
		local board = part(f0, Vector3.new(width, 3.4, 0.5), facing(pos + Vector3.new(0, 13.6, 0) + n * 0.25, n), color, Enum.Material.SmoothPlastic)
		board.Name = "Sign_" .. cat
		board:SetAttribute("Category", cat)
		board:SetAttribute("PlaceName", name)
		surfaceText(board, Enum.NormalId.Front, { { name, 0.95 } }, WHITE, 32, 280)
		if store then
			local sw = math.min(width + 4, 30)
			local shop = part(f0, Vector3.new(sw, 10, 0.3), facing(pos + Vector3.new(0, 5.1, 0) + n * 0.15, n), Color3.fromRGB(44, 46, 50),
				Enum.Material.SmoothPlastic, { CanCollide = false })
			local tex = Instance.new("Texture")
			tex.Texture = Settings.Textures.Storefront
			tex.Face = Enum.NormalId.Front
			tex.StudsPerTileU = sw
			tex.StudsPerTileV = 10
			tex.Parent = shop
		end
	end)
	each(Data.FreeSigns, function(f)
		local cat, color, name = f[1], Color3.fromHex(f[2]), f[3]
		local pos = v2(f[4], f[5])
		local n = Vector3.new(tonumber(f[6]), 0, tonumber(f[7]))
		local pole = part(f0, Vector3.new(9, 0.5, 0.5), CFrame.new(pos + Vector3.new(0, 4.5, 0)) * CYL_UP, IRON, Enum.Material.Metal)
		pole.Shape = Enum.PartType.Cylinder
		local board = part(f0, Vector3.new(9, 4, 0.4), facing(pos + Vector3.new(0, 10.5, 0), n), color, Enum.Material.SmoothPlastic)
		board:SetAttribute("Category", cat)
		board:SetAttribute("PlaceName", name)
		local lines = { { CAT_TITLES[cat] or "", 0.42 }, { name, 0.5 } }
		surfaceText(board, Enum.NormalId.Front, lines, WHITE, 32, 260)
		surfaceText(board, Enum.NormalId.Back, lines, WHITE, 32, 260)
	end)
	local plates = folder("Addresses", root)
	each(Data.Addresses, function(f)
		local pos = v2(f[1], f[2])
		local n = Vector3.new(tonumber(f[3]), 0, tonumber(f[4]))
		local parts = string.split(f[5], "|")
		local plate = part(plates, Vector3.new(6.5, 2.6, 0.15), facing(pos + Vector3.new(0, 11.5, 0) + n * 0.1, n), Color3.fromRGB(0, 66, 140),
			Enum.Material.SmoothPlastic, { CanCollide = false, CastShadow = false })
		surfaceText(plate, Enum.NormalId.Front, { { parts[2] or "", 0.55 }, { parts[1], 0.4 } }, WHITE, 40, 160)
	end)
end

function Infrastructure.Build(root)
	local infra = folder("Infrastructure", root)
	buildStreetsurface(infra)
	buildTrafficLights(infra)
	buildStreetSigns(infra)
	buildStops(infra)
	buildProps(infra)
	buildSigns(infra)
end

return Infrastructure
