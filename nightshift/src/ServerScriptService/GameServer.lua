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

local GameServer = {}

function GameServer.Start()
	Net.Init()

	-------------------------------------------------------------------------------
	-- Ночное освещение (технология Future задана в файле плейса)
	-------------------------------------------------------------------------------
	Lighting.ClockTime = 0.4
	Lighting.GeographicLatitude = 55
	Lighting.Brightness = 0.6
	Lighting.Ambient = Color3.fromRGB(14, 14, 18)
	Lighting.OutdoorAmbient = Color3.fromRGB(26, 28, 36)
	Lighting.EnvironmentDiffuseScale = 0.25
	Lighting.EnvironmentSpecularScale = 1
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.25
	Lighting.ExposureCompensation = 0.1
	for _, c in ipairs(Lighting:GetChildren()) do
		if c:IsA("PostEffect") or c:IsA("Atmosphere") or c:IsA("Sky") then
			c:Destroy()
		end
	end
	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Density = 0.36
	atmosphere.Offset = 0
	atmosphere.Color = Color3.fromRGB(58, 62, 78)
	atmosphere.Decay = Color3.fromRGB(28, 28, 38)
	atmosphere.Glare = 0
	atmosphere.Haze = 1.6
	atmosphere.Parent = Lighting
	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.55
	bloom.Size = 26
	bloom.Threshold = 1.5
	bloom.Parent = Lighting
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "Grade"
	cc.Saturation = -0.1
	cc.Contrast = 0.08
	cc.TintColor = Color3.fromRGB(236, 242, 255)
	cc.Parent = Lighting

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
		Customers = CustomerManager,
		Monster = MonsterAI,
		Secrets = Secrets,
		Events = EventDirector,
		Shift = ShiftManager,
	}

	DataService.Init()
	TaskManager.Init(map, S)
	Doors.Init(map, S)
	Power.Init(map, S)
	StoreSystems.Init(map, S)
	Checkout.Init(map, S)
	CustomerManager.Init(map, S, NpcFactory, Navigation)
	MonsterAI.Init(map, S, NpcFactory)
	Secrets.Init(map, S)
	EventDirector.Init(map, S)
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

	Doors.Start()
	CustomerManager.Start()
	MonsterAI.Start()
	ShiftManager.Start()
	workspace:SetAttribute("StoreReady", true)
	print(string.format("[NIGHT SHIFT] магазин МАРТ 24 готов за %.1f с", os.clock() - started))
	return S
end

return GameServer
