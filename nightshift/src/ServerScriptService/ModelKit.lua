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
local loaded = false

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
	local count = 0
	for _ in pairs(templates) do
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
