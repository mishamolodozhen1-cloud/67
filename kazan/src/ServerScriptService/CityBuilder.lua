-- Строит центр Казани из данных OpenStreetMap (CityData/*): рельеф с Казанкой и парками,
-- улицы, дома с окнами и крышами, стены Кремля, деревья и фонари.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Settings = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Settings"))
local DataFolder = script.Parent:WaitForChild("CityData")
local Meta = require(DataFolder:WaitForChild("Meta"))

local CityBuilder = {}

local SMOOTH = Enum.SurfaceType.Smooth
local CYL_UP = CFrame.Angles(0, 0, math.rad(90))
local TEX = Settings.Textures
-- Стиль окон: c — классика, m — современное остекление, p — панельный дом
local WINDOW_STYLES = {
	c = { TEX.WindowClassic, 10.5, 11 },
	m = { TEX.WindowModern, 12, 12 },
	p = { TEX.WindowPanel, 10, 9.4 },
}

local created = 0
local function tick()
	created = created + 1
	if created % 300 == 0 then
		task.wait()
	end
end

local function newPart(className, parent, size, cf, color, material)
	local p = Instance.new(className)
	p.Anchored = true
	p.TopSurface = SMOOTH
	p.BottomSurface = SMOOTH
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material
	p.Parent = parent
	tick()
	return p
end

-- Перебор записей вида "a,b,c;a,b,c;..." в нескольких строковых кусках.
local function each(chunks, fn)
	for _, chunk in ipairs(chunks) do
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

-------------------------------------------------------------------------------
-- Рельеф: мощёная основа, Казанка и Булак (вода), парки (трава)
-------------------------------------------------------------------------------
function CityBuilder.BuildTerrain()
	local T = workspace.Terrain
	local W = Meta.nx * Meta.cell
	local H = Meta.nz * Meta.cell
	local cx = Meta.xMin + W / 2
	local cz = Meta.zMin + H / 2
	T:FillBlock(CFrame.new(cx, -6, cz), Vector3.new(W + 64, 12, H + 64), Enum.Material.Pavement)
	T:FillBlock(CFrame.new(cx, -18, cz), Vector3.new(W + 64, 12, H + 64), Enum.Material.Ground)

	local spans = require(DataFolder:WaitForChild("Terrain")).Spans
	local n = 0
	each(spans, function(f)
		local code = f[1]
		local row, c0, len = tonumber(f[2]), tonumber(f[3]), tonumber(f[4])
		-- Границы выравниваем по сетке вокселей (4 стада), чтобы соседние полосы не «съедали» друг друга.
		local function snap(v)
			return math.floor(v / 4 + 0.5) * 4
		end
		local x0, x1 = snap(Meta.xMin + c0 * Meta.cell), snap(Meta.xMin + (c0 + len) * Meta.cell)
		local z0, z1 = snap(Meta.zMin + row * Meta.cell), snap(Meta.zMin + (row + 1) * Meta.cell)
		local x, z = (x0 + x1) / 2, (z0 + z1) / 2
		local size = x1 - x0
		local depth = z1 - z0
		if code == "w" then
			-- Вода не вытесняет грунт: сначала вырезаем русло целиком, потом наливаем воду.
			T:FillBlock(CFrame.new(x, -10, z), Vector3.new(size, 20, depth), Enum.Material.Air)
			T:FillBlock(CFrame.new(x, -12, z), Vector3.new(size, 16, depth), Enum.Material.Water)
		elseif code == "g" then
			T:FillBlock(CFrame.new(x, -2, z), Vector3.new(size, 4, depth), Enum.Material.Grass)
		elseif code == "f" then
			T:FillBlock(CFrame.new(x, -2, z), Vector3.new(size, 4, depth), Enum.Material.LeafyGrass)
		elseif code == "k" then
			T:FillBlock(CFrame.new(x, -2, z), Vector3.new(size, 4, depth), Enum.Material.Asphalt)
		end
		n = n + 1
		if n % 150 == 0 then
			task.wait()
		end
	end)
	-- Облака над городом
	if not T:FindFirstChildOfClass("Clouds") then
		local clouds = Instance.new("Clouds")
		clouds.Cover = 0.55
		clouds.Density = 0.6
		clouds.Color = Color3.fromRGB(245, 245, 250)
		clouds.Parent = T
	end
end

-------------------------------------------------------------------------------
-- Улицы
-------------------------------------------------------------------------------
local ROAD = {
	a = { Color3.fromRGB(56, 56, 60), Enum.Material.Asphalt, 0.26 },
	r = { Color3.fromRGB(64, 64, 68), Enum.Material.Asphalt, 0.22 },
	s = { Color3.fromRGB(78, 78, 80), Enum.Material.Asphalt, 0.18 },
	p = { Color3.fromRGB(178, 168, 154), Enum.Material.Pavement, 0.16 },
	f = { Color3.fromRGB(150, 142, 132), Enum.Material.Pavement, 0.12 },
}

local function streetLamp(parent, pos, facing)
	local pole = newPart("Part", parent, Vector3.new(26, 0.8, 0.8), CFrame.new(pos + Vector3.new(0, 13, 0)) * CYL_UP,
		Color3.fromRGB(46, 48, 52), Enum.Material.Metal)
	pole.Shape = Enum.PartType.Cylinder
	pole.CastShadow = false
	local headPos = pos + Vector3.new(0, 26, 0) + facing * 2.5
	newPart("Part", parent, Vector3.new(1.4, 0.6, 5.5), CFrame.lookAt(pos + Vector3.new(0, 26.2, 0) + facing * 1.6, headPos + facing + Vector3.new(0, 0.2, 0)),
		Color3.fromRGB(46, 48, 52), Enum.Material.Metal).CastShadow = false
	local bulb = newPart("Part", parent, Vector3.new(1.2, 0.3, 2.2), CFrame.lookAt(headPos + Vector3.new(0, -0.35, 0), headPos + facing + Vector3.new(0, -0.35, 0)),
		Color3.fromRGB(255, 236, 200), Enum.Material.Neon)
	bulb.CastShadow = false
	local light = Instance.new("SpotLight")
	light.Face = Enum.NormalId.Bottom
	light.Angle = 120
	light.Range = 45
	light.Brightness = 1.6
	light.Color = Color3.fromRGB(255, 220, 170)
	light.Shadows = false
	light.Parent = bulb
end

function CityBuilder.BuildRoads(root)
	local roads = folder("Streets", root)
	local markings = folder("Markings", root)
	local lamps = folder("StreetLamps", root)
	local segs = require(DataFolder:WaitForChild("Roads")).Segments
	local i = 0
	local lampAcc = 0
	each(segs, function(f)
		i = i + 1
		local x1, z1, x2, z2, w = tonumber(f[1]), tonumber(f[2]), tonumber(f[3]), tonumber(f[4]), tonumber(f[5])
		local kind, bridge = f[6], f[7] == "1"
		local spec = ROAD[kind] or ROAD.r
		local a = Vector3.new(x1, 0, z1)
		local b = Vector3.new(x2, 0, z2)
		local len = (b - a).Magnitude
		local ext = (kind == "f") and 0.6 or w * 0.5
		local top = spec[3] + (i % 3) * 0.012
		local thick = bridge and 5 or 1
		local cf = CFrame.lookAt((a + b) / 2, b)
		local p = newPart("Part", roads, Vector3.new(w, thick, len + ext), cf + Vector3.new(0, top - thick / 2, 0), spec[1], spec[2])
		p.CastShadow = false
		if bridge then
			for _, side in ipairs({ -1, 1 }) do
				local rail = newPart("Part", roads, Vector3.new(0.6, 3.2, len), cf * CFrame.new(side * (w / 2 - 0.3), top + 1.6, 0),
					Color3.fromRGB(70, 74, 80), Enum.Material.Metal)
				rail.CastShadow = false
			end
		end
		if kind == "a" and w >= 30 then
			local line = newPart("Part", markings, Vector3.new(0.5, 0.06, len), cf + Vector3.new(0, top + 0.03, 0),
				Color3.fromRGB(235, 235, 230), Enum.Material.SmoothPlastic)
			line.CastShadow = false
			line.CanCollide = false
		end
		if kind == "a" or kind == "p" then
			lampAcc = lampAcc + len
			if lampAcc > 220 and not bridge then
				lampAcc = 0
				local side = (i % 2 == 0) and 1 or -1
				local right = cf.RightVector * side
				streetLamp(lamps, (a + b) / 2 + right * (w / 2 + 3), -right)
			end
		end
	end)
end

-------------------------------------------------------------------------------
-- Здания
-------------------------------------------------------------------------------
local MATERIALS = {
	p = Enum.Material.Plaster,
	b = Enum.Material.Brick,
	c = Enum.Material.Concrete,
	g = Enum.Material.Glass,
}
local FACES = { Enum.NormalId.Front, Enum.NormalId.Back, Enum.NormalId.Left, Enum.NormalId.Right }

local function addWindows(part, w, d, style)
	local spec = WINDOW_STYLES[style] or WINDOW_STYLES.c
	for _, face in ipairs(FACES) do
		local faceWidth = (face == Enum.NormalId.Left or face == Enum.NormalId.Right) and d or w
		if faceWidth >= 8 then
			local tex = Instance.new("Texture")
			tex.Texture = spec[1]
			tex.Face = face
			tex.StudsPerTileU = spec[2]
			tex.StudsPerTileV = spec[3]
			tex.Parent = part
		end
	end
end

local function gableRoof(parent, base, w, d, y, color)
	local rot = CFrame.new()
	local rw, rd = w, d
	if d > w then
		rot = CFrame.Angles(0, math.pi / 2, 0)
		rw, rd = d, w
	end
	local rh = math.min(rd * 0.32, 26)
	local top = base * rot * CFrame.new(0, y, 0)
	newPart("WedgePart", parent, Vector3.new(rw + 1, rh, rd / 2 + 0.6), top * CFrame.new(0, rh / 2, -rd / 4 - 0.3), color, Enum.Material.Metal)
	newPart("WedgePart", parent, Vector3.new(rw + 1, rh, rd / 2 + 0.6), top * CFrame.new(0, rh / 2, rd / 4 + 0.3) * CFrame.Angles(0, math.pi, 0), color, Enum.Material.Metal)
end

function CityBuilder.BuildBuildings(root)
	local data = require(DataFolder:WaitForChild("Buildings"))
	local houses = folder("Buildings", root)
	each(data.Boxes, function(f)
		local x, z, w, d, phi, y0, h = tonumber(f[1]), tonumber(f[2]), tonumber(f[3]), tonumber(f[4]), tonumber(f[5]), tonumber(f[6]), tonumber(f[7])
		local wall, roof, mat, flags = f[8], f[9], f[10], tonumber(f[11]) or 0
		local base = CFrame.new(x, 0, z) * CFrame.Angles(0, phi, 0)
		local body = newPart("Part", houses, Vector3.new(w, h, d), base * CFrame.new(0, y0 + h / 2, 0), Color3.fromHex(wall), MATERIALS[mat] or Enum.Material.Plaster)
		if mat == "g" then
			body.Reflectance = 0.12
		end
		if flags % 2 == 1 then
			addWindows(body, w, d, (mat == "g") and "m" or f[12])
		end
		if flags >= 2 then
			gableRoof(houses, base, w, d, y0 + h, Color3.fromHex(roof))
		else
			local slab = newPart("Part", houses, Vector3.new(w + 0.8, 0.8, d + 0.8), base * CFrame.new(0, y0 + h + 0.4, 0), Color3.fromHex(roof), Enum.Material.Metal)
			slab.CastShadow = false
		end
	end)
	each(data.Wedges, function(f)
		local x, z = tonumber(f[1]), tonumber(f[2])
		local u = Vector3.new(tonumber(f[3]), 0, tonumber(f[4]))
		local v = Vector3.new(tonumber(f[5]), 0, tonumber(f[6]))
		local a, b, y0, h = tonumber(f[7]), tonumber(f[8]), tonumber(f[9]), tonumber(f[10])
		local Y = u
		local Z = -v
		local X = Y:Cross(Z)
		newPart("WedgePart", houses, Vector3.new(h, a, b), CFrame.fromMatrix(Vector3.new(x, y0 + h / 2, z), X, Y, Z), Color3.fromHex(f[11]), Enum.Material.Plaster)
	end)
end

-------------------------------------------------------------------------------
-- Стены Кремля, прочие стены, деревья
-------------------------------------------------------------------------------
function CityBuilder.BuildMisc(root)
	local data = require(DataFolder:WaitForChild("Misc"))
	local walls = folder("Walls", root)
	each(data.Walls, function(f)
		local a = Vector3.new(tonumber(f[1]), 0, tonumber(f[2]))
		local b = Vector3.new(tonumber(f[3]), 0, tonumber(f[4]))
		local len = (b - a).Magnitude
		local cf = CFrame.lookAt((a + b) / 2, b)
		if f[5] == "k" then
			-- Белокаменная стена Кремля с зубцами
			newPart("Part", walls, Vector3.new(9, 26, len + 9), cf + Vector3.new(0, 13, 0), Color3.fromRGB(242, 239, 230), Enum.Material.Plaster)
			newPart("Part", walls, Vector3.new(10.5, 1.4, len + 10), cf + Vector3.new(0, 26.7, 0), Color3.fromRGB(205, 200, 188), Enum.Material.Limestone)
			local n = math.floor(len / 7)
			for k = 0, n - 1 do
				local off = -len / 2 + (k + 0.5) * (len / math.max(n, 1))
				newPart("Part", walls, Vector3.new(1.6, 3.2, 3.6), cf * CFrame.new(-4, 29, off), Color3.fromRGB(242, 239, 230), Enum.Material.Plaster)
			end
		else
			newPart("Part", walls, Vector3.new(1.6, 7, len + 1.6), cf + Vector3.new(0, 3.5, 0), Color3.fromRGB(196, 184, 168), Enum.Material.Brick)
		end
	end)

	local trees = folder("Trees", root)
	local greens = {
		Color3.fromRGB(74, 116, 52), Color3.fromRGB(88, 128, 60), Color3.fromRGB(62, 104, 50), Color3.fromRGB(96, 132, 66),
	}
	local idx = 0
	each(data.Trees, function(f)
		idx = idx + 1
		local x, z, s = tonumber(f[1]), tonumber(f[2]), tonumber(f[3])
		local th = 14 * s
		local trunk = newPart("Part", trees, Vector3.new(th, 1.6 * s, 1.6 * s), CFrame.new(x, th / 2, z) * CYL_UP, Color3.fromRGB(92, 70, 52), Enum.Material.Wood)
		trunk.Shape = Enum.PartType.Cylinder
		local crown = newPart("Part", trees, Vector3.new(19 * s, 17 * s, 19 * s), CFrame.new(x, th + 5 * s, z) * CFrame.Angles(0, idx, 0),
			greens[idx % #greens + 1], Enum.Material.Grass)
		crown.Shape = Enum.PartType.Ball
	end)
	return data.Landmarks
end

return CityBuilder
