-- MapSystem: карты матчей. Каждая карта — модуль в ServerStorage.Maps (кроме MapKit) с полями Id,
-- DisplayName, Description, Lighting и функцией Build(folder) → { Spawns, TeamSpawns, Center }.
-- Load(id) строит карту в Workspace.ActiveMap (старая удаляется) и ставит её освещение;
-- Unload() убирает карту и возвращает освещение лобби.
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Logger = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Logger"))

local MapSystem = { Name = "MapSystem" }

local log = Logger.new("Map")
local maps = {} -- id → модуль
local order = {}
local current = nil
local lobbyLighting = nil

-- Освещение лобби (по умолчанию) — задаёт LobbySystem
function MapSystem.SetLobbyLighting(l)
	lobbyLighting = l
end

local function effect(className, name)
	local e = Lighting:FindFirstChild(name)
	if not e then
		e = Instance.new(className)
		e.Name = name
		e.Parent = Lighting
	end
	return e
end

function MapSystem.ApplyLighting(l)
	if not l then
		return
	end
	for _, key in ipairs({ "ClockTime", "Brightness", "Ambient", "OutdoorAmbient", "EnvironmentDiffuseScale", "EnvironmentSpecularScale", "ExposureCompensation", "GeographicLatitude", "ShadowSoftness" }) do
		if l[key] ~= nil then
			Lighting[key] = l[key]
		end
	end
	if l.Atmosphere then
		local a = effect("Atmosphere", "DC_Atmosphere")
		for k, v in pairs(l.Atmosphere) do
			a[k] = v
		end
	end
	if l.ColorCorrection then
		local c = effect("ColorCorrectionEffect", "DC_ColorCorrection")
		for k, v in pairs(l.ColorCorrection) do
			c[k] = v
		end
	end
	local bloom = effect("BloomEffect", "DC_Bloom")
	bloom.Intensity, bloom.Size, bloom.Threshold = 0.35, 24, 1.6
	local sun = effect("SunRaysEffect", "DC_SunRays")
	sun.Intensity, sun.Spread = l.SunRays or 0.04, 0.6
end

function MapSystem.List()
	local list = {}
	for _, id in ipairs(order) do
		local m = maps[id]
		table.insert(list, { Id = id, DisplayName = m.DisplayName, Description = m.Description })
	end
	return list
end

function MapSystem.Get(id)
	return maps[id]
end

function MapSystem.Current()
	return current
end

function MapSystem.Folder()
	local f = workspace:FindFirstChild("ActiveMap")
	if not f then
		f = Instance.new("Folder")
		f.Name = "ActiveMap"
		f.Parent = workspace
	end
	return f
end

function MapSystem.Unload()
	local folder = MapSystem.Folder()
	folder:ClearAllChildren()
	current = nil
	MapSystem.ApplyLighting(lobbyLighting)
end

-- Построить карту id. Возвращает описание: { Id, DisplayName, Spawns, TeamSpawns, Center, Model }
function MapSystem.Load(id)
	local m = maps[id]
	assert(m, "MapSystem.Load: нет карты " .. tostring(id))
	MapSystem.Unload()
	local folder = MapSystem.Folder()
	local model = Instance.new("Model")
	model.Name = m.Id
	local started = os.clock()
	local result = m.Build(model)
	model.Parent = folder
	MapSystem.ApplyLighting(m.Lighting)
	current = {
		Id = m.Id,
		DisplayName = m.DisplayName,
		Spawns = result.Spawns,
		TeamSpawns = result.TeamSpawns,
		Center = result.Center or Vector3.zero,
		Model = model,
		Parts = result.Parts,
	}
	log:Info("карта %s: %d деталей, %d точек появления, %.2f с", m.DisplayName, result.Parts or 0, #result.Spawns, os.clock() - started)
	return current
end

function MapSystem.Init()
	local folder = ServerStorage:WaitForChild("Maps")
	local preferred = { "IndustrialZone", "CityBlock", "MilitaryBase", "ConstructionSite", "TestChamber" }
	for _, ms in ipairs(folder:GetChildren()) do
		if ms:IsA("ModuleScript") and ms.Name ~= "MapKit" then
			local ok, m = pcall(require, ms)
			if ok and type(m) == "table" and m.Build then
				maps[m.Id or ms.Name] = m
			else
				log:Error("карта %s не загрузилась: %s", ms.Name, tostring(m))
			end
		end
	end
	for _, id in ipairs(preferred) do
		if maps[id] then
			table.insert(order, id)
		end
	end
	for id in pairs(maps) do
		if not table.find(order, id) then
			table.insert(order, id)
		end
	end
	log:Info("карт: %d (%s)", #order, table.concat(order, ", "))
end

return MapSystem
