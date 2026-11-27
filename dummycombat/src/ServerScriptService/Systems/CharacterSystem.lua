-- CharacterSystem: манекен DUMMY COMBAT — сборка персонажа, появление и возрождение.
--
-- Сборка (один раз при запуске сервера):
--   • 15 частей тела (MeshPart) берутся из загруженной модели DummyAssets.BodyModel и ставятся по скелету
--     Configs/DummyRig (центры и размеры частей, точки суставов);
--   • HumanoidRootPart — невидимая коробка 2×2×1: на ней физика персонажа; в лучи попаданий она не попадает
--     (CanQuery = false), попадания будут по частям тела;
--   • суставы (Motor6D) — между парами «<Сустав>RigAttachment», имена и точки как у стандартного R15,
--     поэтому работают анимации и (на этапе 3) регдолл;
--   • сталкиваются с миром корпус и голова; руки и ноги — нет (не цепляются за стены и не дёргают персонажа);
--   • готовый манекен — StarterPlayer.StarterCharacter (так Roblox создаёт его каждому игроку) и копия в
--     ServerStorage.CharacterAssets.Dummy.
-- Если модель не загрузилась, манекен собирается из простых деталей тех же размеров (и пишется ошибка):
-- играть можно, но выглядит он хуже.
--
-- Появление: персонажи не создаются сами (Players.CharacterAutoLoads = false). Игрок получает манекена,
-- когда клиент сообщил о готовности (PlayerService.PlayerReady) — или через ReadySpawnTimeout секунд.
-- После смерти — новый через RespawnDelay секунд (полная система смерти и возрождения — этап 5).
local InsertService = game:GetService("InsertService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Configs = ReplicatedStorage:WaitForChild("Configs")
local Logger = require(Shared:WaitForChild("Logger"))
local Signal = require(Shared:WaitForChild("Signal"))
local GameConfig = require(Configs:WaitForChild("GameConfig"))
local DummyRig = require(Configs:WaitForChild("DummyRig"))
local DummyAssets = require(Configs:WaitForChild("DummyAssets"))

local CharacterSystem = { Name = "CharacterSystem" }

CharacterSystem.CharacterSpawned = Signal.new() -- (player, character)
CharacterSystem.CharacterDied = Signal.new() -- (player, character)

local log = Logger.new("Character")
local cfg = GameConfig.Character
local move = GameConfig.Movement

local template = nil
local usedFallback = false
local spawning = {}

-- Детали тела из загруженной модели: имя -> MeshPart
local function loadMeshes()
	local ok, asset = pcall(InsertService.LoadAsset, InsertService, DummyAssets.BodyModel)
	if not ok then
		log:Error("модель манекена %d не загрузилась: %s", DummyAssets.BodyModel, tostring(asset))
		return nil
	end
	local meshes = {}
	for _, d in ipairs(asset:GetDescendants()) do
		if d:IsA("MeshPart") then
			meshes[d.Name] = d
		end
	end
	for _, spec in ipairs(DummyRig.Parts) do
		if not meshes[spec.Name] then
			log:Error("в модели манекена нет части %s", spec.Name)
			asset:Destroy()
			return nil
		end
	end
	return meshes, asset
end

local function setupPart(p, spec)
	p.Anchored = false
	p.CanCollide = spec.Collide
	p.CanTouch = false
	p.CanQuery = true
	p.CastShadow = true
	p.Material = Enum.Material.SmoothPlastic
	p.Reflectance = 0
	p.CustomPhysicalProperties = PhysicalProperties.new(1, 0.4, 0.2)
end

-- Собрать манекена. Возвращает Model (StarterCharacter) и true, если пришлось собрать запасной из деталей
function CharacterSystem.BuildDummy(meshes)
	local model = Instance.new("Model")
	model.Name = "StarterCharacter"
	local rootY = DummyRig.HipHeight + DummyRig.RootSize.Y / 2
	local rootCF = CFrame.new(0, rootY, 0)

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = DummyRig.RootSize
	root.CFrame = rootCF
	root.Transparency = 1
	root.CanCollide = true
	root.CanQuery = false
	root.CanTouch = true
	root.CastShadow = false
	root.Anchored = false
	root.Parent = model

	local fallback = meshes == nil
	local parts = { HumanoidRootPart = root }
	for _, spec in ipairs(DummyRig.Parts) do
		local p
		if meshes then
			p = meshes[spec.Name]:Clone()
		else
			p = Instance.new("Part")
			p.Color = cfg.BodyColor
		end
		p.Name = spec.Name
		p.Size = spec.Size
		p.CFrame = rootCF * CFrame.new(spec.Offset)
		setupPart(p, spec)
		p.Parent = model
		parts[spec.Name] = p
	end
	for partName, list in pairs(DummyRig.Attachments) do
		local part = parts[partName]
		for _, item in ipairs(list) do
			local a = Instance.new("Attachment")
			a.Name = item[1]
			a.Position = item[2]
			a.Parent = part
		end
	end

	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R15
	humanoid.HipHeight = DummyRig.HipHeight
	humanoid.AutomaticScalingEnabled = false
	humanoid.UseJumpPower = false
	humanoid.JumpHeight = move.JumpHeight
	humanoid.WalkSpeed = move.WalkSpeed
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.Parent = model
	local animator = Instance.new("Animator")
	animator.Parent = humanoid
	model.PrimaryPart = root
	-- суставы: Motor6D между парами «<Сустав>RigAttachment» (C0/C1 — эти точки), как у стандартного R15
	for _, j in ipairs(DummyRig.Joints) do
		local jointName, part0, part1 = j[1], parts[j[2]], parts[j[3]]
		local a0 = part0 and part0:FindFirstChild(jointName .. "RigAttachment")
		local a1 = part1 and part1:FindFirstChild(jointName .. "RigAttachment")
		if a0 and a1 then
			local motor = Instance.new("Motor6D")
			motor.Name = jointName
			motor.Part0 = part0
			motor.Part1 = part1
			motor.C0 = a0.CFrame
			motor.C1 = a1.CFrame
			motor.Parent = part1
		else
			log:Error("сустав %s: нет точек крепления", jointName)
		end
	end
	model:SetAttribute("DummyVersion", DummyAssets.BodyModel)
	return model, fallback
end

-- Проверка собранного манекена: все суставы на месте, ноги стоят на полу. Возвращает список проблем
function CharacterSystem.Inspect(model)
	local problems = {}
	local joints = 0
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Motor6D") then
			joints = joints + 1
			if not (d.Part0 and d.Part1) then
				table.insert(problems, "сустав " .. d.Name .. " не соединён")
			end
		end
	end
	if joints ~= 15 then
		table.insert(problems, "суставов " .. joints .. " вместо 15")
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	if not (humanoid and root and humanoid.RootPart == root) then
		table.insert(problems, "нет Humanoid или HumanoidRootPart")
	else
		-- низ стоп должен быть на высоте пола: корень − (HipHeight + половина корня)
		local floor = root.Position.Y - humanoid.HipHeight - root.Size.Y / 2
		local lowest = math.huge
		for _, name in ipairs({ "LeftFoot", "RightFoot" }) do
			local f = model:FindFirstChild(name)
			if f then
				lowest = math.min(lowest, f.Position.Y - f.Size.Y / 2)
			end
		end
		if math.abs(lowest - floor) > 0.05 then
			table.insert(problems, string.format("стопы на %.2f, а пол на %.2f", lowest, floor))
		end
	end
	return problems
end

function CharacterSystem.Template()
	return template
end

function CharacterSystem.UsedFallback()
	return usedFallback
end

-- Дать игроку манекена (если он ещё в игре и персонажа сейчас не создают)
function CharacterSystem.Spawn(player)
	if spawning[player] or player.Parent ~= Players then
		return false
	end
	spawning[player] = true
	local ok, err = pcall(player.LoadCharacter, player)
	spawning[player] = nil
	if not ok then
		log:Error("не удалось создать персонажа %s: %s", player.Name, tostring(err))
	end
	return ok
end

local function onCharacter(player, character)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid then
		log:Error("у персонажа %s нет Humanoid", player.Name)
		return
	end
	character:SetAttribute("Stance", "Stand")
	character:SetAttribute("Sprinting", false)
	CharacterSystem.CharacterSpawned:Fire(player, character)
	humanoid.Died:Connect(function()
		CharacterSystem.CharacterDied:Fire(player, character)
		task.delay(cfg.RespawnDelay, function()
			-- возрождаем, только если игрок ещё здесь и это всё ещё тот же (погибший) персонаж
			if player.Parent == Players and player.Character == character then
				CharacterSystem.Spawn(player)
			end
		end)
	end)
end

local function watchPlayer(player)
	player.CharacterAdded:Connect(function(character)
		onCharacter(player, character)
	end)
	if player.Character then
		task.spawn(onCharacter, player, player.Character)
	end
	-- клиент так и не сообщил о готовности — всё равно дать персонажа
	task.delay(cfg.ReadySpawnTimeout, function()
		if player.Parent == Players and not player.Character then
			log:Warn("%s не сообщил о готовности за %d с — персонаж создан без ожидания", player.Name, cfg.ReadySpawnTimeout)
			CharacterSystem.Spawn(player)
		end
	end)
end

function CharacterSystem.Init()
	Players.CharacterAutoLoads = false
	local meshes, asset = loadMeshes()
	local problems
	template, usedFallback = CharacterSystem.BuildDummy(meshes)
	if asset then
		asset:Destroy()
	end
	problems = CharacterSystem.Inspect(template)
	if #problems > 0 then
		error("манекен собран с ошибками: " .. table.concat(problems, "; "), 0)
	end
	if usedFallback then
		log:Error("манекен собран из простых деталей (модель не загрузилась)")
	end
	local old = StarterPlayer:FindFirstChild("StarterCharacter")
	if old then
		old:Destroy()
	end
	template:Clone().Parent = StarterPlayer
	local store = ServerStorage:FindFirstChild("CharacterAssets")
	if store then
		local prev = store:FindFirstChild("Dummy")
		if prev then
			prev:Destroy()
		end
		local copy = template:Clone()
		copy.Name = "Dummy"
		copy.Parent = store
	end
	log:Info("манекен готов: %d частей, рост %.2f, HipHeight %.2f%s", #DummyRig.Parts, DummyRig.Height, DummyRig.HipHeight, usedFallback and " (запасной)" or "")
end

function CharacterSystem.Start(context)
	local playerService = context.Get("PlayerService")
	playerService.PlayerReady:Connect(function(player)
		if not player.Character then
			CharacterSystem.Spawn(player)
		end
	end)
	Players.PlayerAdded:Connect(watchPlayer)
	Players.PlayerRemoving:Connect(function(player)
		spawning[player] = nil
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		watchPlayer(player)
		if playerService.IsReady(player) and not player.Character then
			task.spawn(CharacterSystem.Spawn, player)
		end
	end
end

return CharacterSystem
