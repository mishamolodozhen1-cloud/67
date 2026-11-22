-- GameServer: запуск всей серверной части NIGHT SHIFT (ModuleScript в ServerScriptService).
-- Порядок: удалённые события -> освещение -> постройка магазина -> системы -> запуск смены.
-- Все системы получают общую таблицу S и обращаются друг к другу через неё (S.Tasks, S.Store, …).
-- Вызывается из Main (Script). Вынесено в модуль, чтобы сервер можно было запустить и в тестах.
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local StarterPlayer = game:GetService("StarterPlayer")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local function mod(name)
	return require(ServerScriptService:WaitForChild(name))
end

local Net = mod("Net")
local MapBuilder = mod("MapBuilder")
local Navigation = mod("Navigation")
local NpcFactory = mod("NpcFactory")
local DataService = mod("DataService")
local TaskManager = mod("TaskManager")
local Doors = mod("Doors")
local Power = mod("Power")
local StoreSystems = mod("StoreSystems")
local Checkout = mod("Checkout")
local CustomerManager = mod("CustomerManager")
local MonsterAI = mod("MonsterAI")
local Secrets = mod("Secrets")
local EventDirector = mod("EventDirector")
local ShiftManager = mod("ShiftManager")
local Rooms = mod("Rooms")
local Security = mod("Security")
local Beast = mod("Beast")

local GameServer = {}

-- Ночное освещение (технология Future задана в файле плейса)
local function setupLighting()
	Lighting.ClockTime = 0.4
	Lighting.GeographicLatitude = 55
	Lighting.Brightness = 0.35
	Lighting.Ambient = Color3.fromRGB(22, 22, 26) -- v9: мягкая подсветка теней
	Lighting.OutdoorAmbient = Color3.fromRGB(34, 40, 54)
	-- v9: мягкий свет — рассеянное освещение сильнее, блики слабее, тени с мягкими краями
	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 0.55
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.45
	Lighting.ExposureCompensation = 0
	for _, c in ipairs(Lighting:GetChildren()) do
		if c:IsA("PostEffect") or c:IsA("Atmosphere") or c:IsA("Sky") then
			c:Destroy()
		end
	end
	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Density = 0.42
	atmosphere.Offset = 0.1
	atmosphere.Color = Color3.fromRGB(52, 60, 76)
	atmosphere.Decay = Color3.fromRGB(22, 26, 34)
	atmosphere.Glare = 0
	atmosphere.Haze = 2.2
	atmosphere.Parent = Lighting
	-- лёгкое свечение только у самых ярких источников (лампы, вывеска, фары), без «неона» на максимальной графике
	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.28
	bloom.Size = 26
	bloom.Threshold = 1.7
	bloom.Parent = Lighting
	local dof = Instance.new("DepthOfFieldEffect")
	dof.Name = "DepthOfField"
	dof.FarIntensity = 0.08
	dof.FocusDistance = 45
	dof.InFocusRadius = 40
	dof.NearIntensity = 0
	dof.Parent = Lighting
	-- пасмурное ночное небо
	local oldClouds = workspace.Terrain:FindFirstChildOfClass("Clouds")
	if oldClouds then
		oldClouds:Destroy()
	end
	local clouds = Instance.new("Clouds")
	clouds.Cover = 0.88
	clouds.Density = 0.55
	clouds.Color = Color3.fromRGB(30, 34, 44)
	clouds.Parent = workspace.Terrain
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "Grade"
	cc.Saturation = -0.08
	cc.Contrast = 0.06
	cc.Brightness = 0.01
	cc.TintColor = Color3.fromRGB(234, 241, 250)
	cc.Parent = Lighting
end

-- Холл (публичный сервер): главное меню. Магазин строится только как фон, смены нет, персонажей нет.
function GameServer.StartHub()
	Net.Init("Hub")
	setupLighting()
	Players.CharacterAutoLoads = false
	local started = os.clock()
	local map = MapBuilder.Build()
	DataService.Init()
	Net.Remote("GetProfile").OnServerInvoke = function(player)
		for _ = 1, 20 do
			if DataService.Get(player) then
				break
			end
			task.wait(0.25)
		end
		return DataService.Get(player)
	end
	Net.OnAction(function(player, action, settings)
		if action == "SaveSettings" then
			pcall(DataService.SaveSettings, player, settings)
		end
	end)
	Rooms.InitHub(Net.Remote("Rooms"))
	workspace:SetAttribute("StoreReady", true)
	print(string.format("[NIGHT SHIFT] главное меню готово за %.1f с", os.clock() - started))
	return { Net = Net, Map = map, Rooms = Rooms }
end

function GameServer.Start()
	Net.Init("Game")
	setupLighting()

	-------------------------------------------------------------------------------
	-- Магазин и системы
	-------------------------------------------------------------------------------
	local started = os.clock()
	local map = MapBuilder.Build()
	Navigation.Init(map)
	NpcFactory.Init()

	local S = {
		Net = Net,
		Map = map,
		Data = DataService,
		Tasks = TaskManager,
		Doors = Doors,
		Power = Power,
		Store = StoreSystems,
		Checkout = Checkout,
		Security = Security,
		Customers = CustomerManager,
		Monster = MonsterAI,
		Secrets = Secrets,
		Events = EventDirector,
		Shift = ShiftManager,
		Beast = Beast,
	}

	DataService.Init()
	TaskManager.Init(map, S)
	Doors.Init(map, S)
	Power.Init(map, S)
	StoreSystems.Init(map, S)
	-- звуки действий покупателей (сканирование, пакет, карта…) слышат все
	NpcFactory.SoundHook = function(name, position, volume)
		Net.Sound(name, position, volume)
	end
	Checkout.Init(map, S, NpcFactory)
	Security.Init(map, S, NpcFactory)
	CustomerManager.Init(map, S, NpcFactory, Navigation)
	MonsterAI.Init(map, S, NpcFactory)
	Secrets.Init(map, S)
	EventDirector.Init(map, S)
	Beast.Init(map, S)
	ShiftManager.Init(map, S)

	-------------------------------------------------------------------------------
	-- Игроки: вид от первого лица, скорость, фонарик
	-------------------------------------------------------------------------------
	StarterPlayer.CameraMode = Enum.CameraMode.LockFirstPerson
	StarterPlayer.EnableMouseLockOption = false
	StarterPlayer.CharacterWalkSpeed = Config.WalkSpeed
	StarterPlayer.CharacterUseJumpPower = false
	StarterPlayer.CharacterJumpHeight = 4
	Players.RespawnTime = 2

	local function onCharacter(player, character)
		NpcFactory.SetPlayerCollision(character)
		local hum = character:WaitForChild("Humanoid", 10)
		if hum then
			hum.WalkSpeed = Config.WalkSpeed
			hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
			hum.NameDisplayDistance = 30
		end
		character:SetAttribute("Flashlight", false)
		player:SetAttribute("Carry", "")
	end

	local function onPlayer(player)
		player.CameraMode = Enum.CameraMode.LockFirstPerson
		player.CameraMaxZoomDistance = 0.5
		player.CharacterAdded:Connect(function(ch)
			onCharacter(player, ch)
		end)
		if player.Character then
			task.spawn(onCharacter, player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, p in ipairs(Players:GetPlayers()) do
		onPlayer(p)
	end

	-------------------------------------------------------------------------------
	-- Действия клиентов
	-------------------------------------------------------------------------------
	local ACTIONS = {}
	function ACTIONS.StartShift(player)
		ShiftManager.RequestStart(player)
	end
	function ACTIONS.SelectNight(player, n)
		ShiftManager.SelectNight(player, n)
	end
	function ACTIONS.Drop(player)
		StoreSystems.Drop(player)
	end
	function ACTIONS.Flashlight(player, on)
		if player.Character and type(on) == "boolean" then
			player.Character:SetAttribute("Flashlight", on)
		end
	end
	function ACTIONS.CameraViewed(player, index)
		StoreSystems.CameraViewed(player, index)
	end
	function ACTIONS.CameraView(player, index)
		MonsterAI.ReportCamera(player, index)
	end
	function ACTIONS.MonsterSeen(player, seen)
		MonsterAI.ReportSeen(player, seen == true)
	end
	function ACTIONS.BeastSeen(player, model)
		Beast.ReportSeen(player, model)
	end
	function ACTIONS.IntroDone(player)
		ShiftManager.IntroDone(player)
	end
	function ACTIONS.SaveSettings(player, settings)
		DataService.SaveSettings(player, settings)
	end

	Net.OnAction(function(player, action, ...)
		local fn = type(action) == "string" and ACTIONS[action]
		if fn then
			local ok, err = pcall(fn, player, ...)
			if not ok then
				warn("[Действие " .. action .. "] " .. tostring(err))
			end
		end
	end)

	Net.Remote("GetProfile").OnServerInvoke = function(player)
		for _ = 1, 20 do
			if DataService.Get(player) then
				break
			end
			task.wait(0.25)
		end
		return DataService.Get(player)
	end

	-- комната: код для друзей, обновление списка комнат, выход в меню
	Rooms.InitGame(Net.State(), Net.Remote("Rooms"))
	S.Rooms = Rooms

	Doors.Start()
	CustomerManager.Start()
	MonsterAI.Start()
	ShiftManager.Start()
	workspace:SetAttribute("StoreReady", true)
	print(string.format("[NIGHT SHIFT] магазин MART 24 готов за %.1f с", os.clock() - started))
	return S
end

return GameServer
