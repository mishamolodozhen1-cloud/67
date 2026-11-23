-- ModelKit: 3D-модели магазина (полки, холодильники, кассы, стеллажи склада, коробки, продукты).
-- ID мешей и размеры — в Shared/Models. При запуске сервера загружаем по одному образцу каждой модели
-- (AssetService:CreateMeshPartAsync, параллельно), дальше только копируем их.
-- Продукты получают PBR-материал (цвет, нормали, шероховатость): его берём у двух загруженных
-- моделей-«носителей» с текстурами набора и копируем SurfaceAppearance на каждый продукт.
-- Если что-то не загрузилось, ModelKit.Has(name) вернёт false, и MapBuilder построит простую замену.
--
-- Важно про оси: Roblox при импорте разворачивает модели на 180° вокруг вертикали, поэтому
-- лицевая сторона продуктов (этикетка) смотрит в LookVector детали, а перёд полок и холодильников — в -X.
local AssetService = game:GetService("AssetService")
local InsertService = game:GetService("InsertService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Models = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Models"))

local ModelKit = {}
ModelKit.Ready = false

local templates = {}
local appearance = {}
local assets = {}
local loaded = false

-- Целая модель с текстурами (касса, машина, фонарик): все детали в одну модель, опора — центр низа
local function loadAsset(name, def)
	local ok, m = pcall(function()
		return InsertService:LoadAsset(def.Id)
	end)
	if not ok then
		warn("[Модели] " .. name .. " не загрузилась: " .. tostring(m))
		return
	end
	local tpl = Instance.new("Model")
	tpl.Name = name
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanTouch = false
			d.Parent = tpl
		end
	end
	m:Destroy()
	if #tpl:GetChildren() == 0 then
		return
	end
	local cf, size = tpl:GetBoundingBox()
	-- опора: центр низа (по умолчанию), центр верха или центр модели
	local offset = -size.Y / 2
	if def.Pivot == "Top" then
		offset = size.Y / 2
	elseif def.Pivot == "Center" then
		offset = 0
	end
	tpl.WorldPivot = CFrame.new(cf.Position + Vector3.new(0, offset, 0))
	tpl:SetAttribute("SourceSize", size)
	assets[name] = tpl
end

local function loadCarrier(atlas, assetId)
	local ok, model = pcall(function()
		return InsertService:LoadAsset(assetId)
	end)
	if not ok then
		warn("[Модели] материал " .. atlas .. " не загрузился: " .. tostring(model))
		return
	end
	local sa = model:FindFirstChildWhichIsA("SurfaceAppearance", true)
	if sa then
		appearance[atlas] = sa:Clone()
	end
	model:Destroy()
end

local function loadMesh(name, def)
	local ok, part = pcall(function()
		return AssetService:CreateMeshPartAsync(def.Mesh, {
			-- полки и холодильники: точная форма (между полками можно заглянуть), остальное — коробка
			CollisionFidelity = def.Precise and Enum.CollisionFidelity.PreciseConvexDecomposition or Enum.CollisionFidelity.Box,
			RenderFidelity = Enum.RenderFidelity.Automatic,
		})
	end)
	if not ok then
		warn("[Модели] " .. name .. " не загрузилась: " .. tostring(part))
		return
	end
	part.Name = name
	part.Anchored = true
	part.CanTouch = false
	part.Material = def.Material or Enum.Material.SmoothPlastic
	part.Color = def.Color or Color3.new(1, 1, 1)
	part.CastShadow = def.Shadow ~= false
	if def.Atlas == "Palette" then
		part.TextureID = Models.Palette
	elseif appearance[def.Atlas] then
		appearance[def.Atlas]:Clone().Parent = part
	end
	templates[name] = part
end

-- Загрузить все модели (ждёт до timeout секунд). Повторный вызов ничего не делает.
function ModelKit.Load(timeout)
	if loaded then
		return ModelKit.Ready
	end
	loaded = true
	local started = os.clock()
	-- 1) материалы продуктов
	local pending = 0
	for atlas, id in pairs(Models.Carriers) do
		pending = pending + 1
		task.spawn(function()
			loadCarrier(atlas, id)
			pending = pending - 1
		end)
	end
	while pending > 0 and os.clock() - started < (timeout or 30) do
		task.wait(0.05)
	end
	-- 2) меши
	for name, def in pairs(Models.Meshes) do
		pending = pending + 1
		task.spawn(function()
			loadMesh(name, def)
			pending = pending - 1
		end)
	end
	while pending > 0 and os.clock() - started < (timeout or 30) do
		task.wait(0.05)
	end
	-- 3) целые модели (касса, машины, фонарик)
	for name, def in pairs(Models.Assets or {}) do
		pending = pending + 1
		task.spawn(function()
			loadAsset(name, def)
			pending = pending - 1
		end)
	end
	while pending > 0 and os.clock() - started < (timeout or 30) do
		task.wait(0.05)
	end
	-- фонарик нужен клиенту (модель в руке): кладём копию в ReplicatedStorage.Assets
	local shared = ReplicatedStorage:FindFirstChild("Assets") or Instance.new("Folder")
	shared.Name = "Assets"
	shared.Parent = ReplicatedStorage
	if assets.Flashlight and not shared:FindFirstChild("Flashlight") then
		assets.Flashlight:Clone().Parent = shared
	end
	local count = 0
	for _ in pairs(templates) do
		count = count + 1
	end
	for _ in pairs(assets) do
		count = count + 1
	end
	ModelKit.Count = count
	ModelKit.Ready = count > 0
	print(string.format("[Модели] загружено %d моделей за %.1f с", count, os.clock() - started))
	return ModelKit.Ready
end

function ModelKit.Has(name)
	return templates[name] ~= nil
end

-- Образец целой модели (чтобы один раз поправить его перед копированием)
function ModelKit.Template(name)
	return assets[name]
end

function ModelKit.HasAsset(name)
	return assets[name] ~= nil
end

-- Размер целой модели в studs до масштабирования
function ModelKit.AssetSize(name)
	return assets[name] and assets[name]:GetAttribute("SourceSize") or nil
end

-- Копия целой модели: cf — где стоит центр её низа (и куда повёрнута), scale — во сколько раз увеличить
function ModelKit.MakeAsset(name, parent, cf, scale)
	local tpl = assets[name]
	if not tpl then
		return nil
	end
	local m = tpl:Clone()
	if scale and scale ~= 1 then
		m:ScaleTo(scale)
	end
	m:PivotTo(cf)
	m.Parent = parent
	return m
end

-- Копия целой модели заданной высоты (в studs). Учитывает Yaw из Models.Assets, чтобы перёд модели
-- смотрел в LookVector cf. Возвращает модель и итоговую высоту (или nil, если модель не загрузилась)
function ModelKit.MakeAssetFit(name, parent, cf, height)
	local tpl = assets[name]
	local def = Models.Assets[name]
	if not (tpl and def) then
		return nil
	end
	local size = tpl:GetAttribute("SourceSize")
	local m = tpl:Clone()
	m:ScaleTo(height / size.Y)
	m:PivotTo(cf * CFrame.Angles(0, math.rad(def.Yaw or 0), 0))
	m.Parent = parent
	m:SetAttribute("FitHeight", height)
	return m, height
end

-- Где у поставленной модели экран: CFrame середины экрана (LookVector — наружу от экрана) и размер в studs
function ModelKit.ScreenOf(name, m)
	local def = Models.Assets[name]
	local sc = def and def.Screen
	local h = m and m:GetAttribute("FitHeight")
	if not (sc and h) then
		return nil
	end
	local pivot = m:GetPivot()
	local pos = pivot:PointToWorldSpace(sc.Center * h)
	local normal = pivot:VectorToWorldSpace(sc.Normal)
	return CFrame.lookAt(pos, pos + normal), sc.Size * h
end

-- Все ли модели из списка загружены
function ModelKit.HasAll(list)
	for _, name in ipairs(list) do
		if not templates[name] then
			return false
		end
	end
	return true
end

-- Размер модели в studs при масштабе scale (studs на метр)
function ModelKit.Size(name, scale)
	local def = Models.Meshes[name]
	return def and def.Size * (scale or 1) or nil
end

-- Новая деталь-копия модели. size — размер в studs (Vector3, по локальным осям модели)
function ModelKit.Make(name, parent, cf, size, props)
	local tpl = templates[name]
	if not tpl then
		return nil
	end
	local p = tpl:Clone()
	p.Size = size
	p.CFrame = cf
	if props then
		for k, v in pairs(props) do
			p[k] = v
		end
	end
	p.Parent = parent
	return p
end

return ModelKit
