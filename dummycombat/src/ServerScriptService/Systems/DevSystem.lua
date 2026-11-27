-- DevSystem: стенд проверки регдолла и физики — работает ТОЛЬКО в Roblox Studio. В опубликованной игре
-- сервер команды не принимает (обработчик события DevCommand даже не подключается) и полигон не строит.
-- В Studio строит полигон (пол, лестница, стена, пандус, ящики — карт ещё нет, они с этапа 6).
--
-- Команды (клавиши — на клиенте, Controllers/DevController):
--   Knockdown     уронить себя (толчок назад), полежать и встать
--   KillHead      убить себя «выстрелом в голову» спереди
--   KillLegs      убить себя «выстрелом по ногам» сбоку
--   Explode       взрыв в точке прицела: ближе LethalRadius — смерть, дальше — падение, тела отбрасывает
--   SpawnDummies  поставить 5 манекенов перед собой (не больше MaxDummies) — мишени для стрельбы и стресс-тест
--   ClearDummies  убрать манекены
--   Stats         в Output сервера: регдоллы, тела, манекены, частота физики, время шага физики
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")

local Logger = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Logger"))
local DummyRig = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("DummyRig"))

local DevSystem = { Name = "DevSystem" }

DevSystem.MaxDummies = 30
DevSystem.ExplosionRadius = 20
DevSystem.LethalRadius = 6
DevSystem.MaxExplodeDistance = 400

local log = Logger.new("Dev")
local active = false
local ragdoll, characters = nil, nil
local dummyFolder = nil

function DevSystem.IsActive()
	return active
end

local function liveCharacter(player)
	local c = player.Character
	local h = c and c:FindFirstChildOfClass("Humanoid")
	local root = c and c:FindFirstChild("HumanoidRootPart")
	if h and root and h.Health > 0 then
		return c, h, root
	end
	return nil
end

local function dummies()
	local list = {}
	for _, d in ipairs(dummyFolder and dummyFolder:GetChildren() or {}) do
		if d:IsA("Model") then
			table.insert(list, d)
		end
	end
	return list
end

-- Поставить count манекенов перед игроком (ряд по 5)
function DevSystem.SpawnDummies(root, count)
	local template = characters.Template()
	local made = 0
	local have = #dummies()
	for i = 1, count do
		if have + made >= DevSystem.MaxDummies then
			break
		end
		local n = have + made
		local row, col = math.floor(n / 5), n % 5
		local at = (root.CFrame * CFrame.new((col - 2) * 4.5, 0, -(14 + row * 6))).Position
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { root.Parent, dummyFolder }
		local hit = workspace:Raycast(at + Vector3.new(0, 6, 0), Vector3.new(0, -60, 0), params)
		local groundY = hit and hit.Position.Y or (root.Position.Y - DummyRig.HipHeight - DummyRig.RootSize.Y / 2)
		local pos = Vector3.new(at.X, groundY + DummyRig.HipHeight + DummyRig.RootSize.Y / 2, at.Z)
		local d = template:Clone()
		d.Name = "Dummy" .. (n + 1)
		-- опора шаблона — HumanoidRootPart; манекен смотрит на игрока
		d:PivotTo(CFrame.lookAt(pos, Vector3.new(root.Position.X, pos.Y, root.Position.Z)))
		d.Parent = dummyFolder
		-- мишень для оружия: её положения пишутся в историю попаданий (WeaponSystem)
		CollectionService:AddTag(d, "DC_Target")
		ragdoll.Track(d)
		ragdoll.OnSpawn(d)
		made = made + 1
	end
	return made
end

function DevSystem.Stats()
	local ragdolled, live = 0, 0
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			live = live + 1
			if ragdoll.IsRagdolled(p.Character) then
				ragdolled = ragdolled + 1
			end
		end
	end
	local sleeping = 0
	local corpses = ragdoll.Corpses()
	for _, c in ipairs(corpses) do
		if c.Sleeping then
			sleeping = sleeping + 1
		end
	end
	local downDummies = 0
	for _, d in ipairs(dummies()) do
		if ragdoll.IsRagdolled(d) then
			downDummies = downDummies + 1
		end
	end
	local okStep, stepMs = pcall(function()
		return Stats.PhysicsStepTimeMs
	end)
	local okBeat, beatMs = pcall(function()
		return Stats.HeartbeatTimeMs
	end)
	local info = {
		Players = live,
		PlayersRagdolled = ragdolled,
		Corpses = #corpses,
		CorpsesSleeping = sleeping,
		Dummies = #dummies(),
		DummiesRagdolled = downDummies,
		PhysicsFps = workspace:GetRealPhysicsFPS(),
		PhysicsStepMs = okStep and stepMs or -1,
		HeartbeatMs = okBeat and beatMs or -1,
	}
	log:Info("игроков %d (в регдолле %d), тел %d (спят %d), манекенов %d (лежат %d); физика %.0f кадр/с, шаг %.2f мс, Heartbeat %.2f мс",
		info.Players, info.PlayersRagdolled, info.Corpses, info.CorpsesSleeping, info.Dummies, info.DummiesRagdolled,
		info.PhysicsFps, info.PhysicsStepMs, info.HeartbeatMs)
	return info
end

-- Выполнить команду стенда от игрока. Возвращает true, если выполнена
function DevSystem.Run(player, command, point)
	if not active then
		return false
	end
	if command == "ClearDummies" then
		for _, d in ipairs(dummies()) do
			d:Destroy()
		end
		return true
	elseif command == "Stats" then
		DevSystem.Stats()
		return true
	end
	local character, humanoid, root = liveCharacter(player)
	if command == "Explode" then
		if typeof(point) ~= "Vector3" then
			return false
		end
		if root and (point - root.Position).Magnitude > DevSystem.MaxExplodeDistance then
			log:Warn("взрыв дальше %d studs от игрока — пропущен", DevSystem.MaxExplodeDistance)
			return false
		end
		local boom = Instance.new("Explosion")
		boom.Position = point
		boom.BlastPressure = 0 -- только вид: толчок даёт RagdollSystem
		boom.BlastRadius = 0
		boom.DestroyJointRadiusPercent = 0
		boom.Parent = workspace
		local affected = ragdoll.Explode(point, DevSystem.ExplosionRadius, 1, { LethalRadius = DevSystem.LethalRadius })
		log:Info("взрыв: задето %d", #affected)
		return true
	end
	if not character then
		return false
	end
	if command == "SpawnDummies" then
		return DevSystem.SpawnDummies(root, 5) > 0
	elseif command == "Knockdown" then
		local back = -root.CFrame.LookVector * 18 + Vector3.new(0, 10, 0)
		local chest = character:FindFirstChild("UpperTorso")
		return ragdoll.Knockdown(character, 2.5, { { Part = chest, Velocity = back } })
	elseif command == "KillHead" then
		local head = character:FindFirstChild("Head")
		ragdoll.RecordHit(character, "Head", -root.CFrame.LookVector, 1, head and head.Position)
		humanoid.Health = 0
		return true
	elseif command == "KillLegs" then
		local leg = character:FindFirstChild("LeftLowerLeg")
		ragdoll.RecordHit(character, "LeftLowerLeg", root.CFrame.RightVector, 1, leg and leg.Position)
		humanoid.Health = 0
		return true
	end
	return false
end

-- Полигон для проверки (только Studio; настоящие карты — с этапа 6): пол, лестница, стена, пандус, ящики —
-- чтобы видеть, как тела падают на ступени, ударяются о стену и скатываются
function DevSystem.BuildArena()
	if workspace:FindFirstChild("DevArena") then
		return workspace.DevArena
	end
	local arena = Instance.new("Model")
	arena.Name = "DevArena"
	local function block(name, size, cf, color, material)
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.Size = size
		p.CFrame = cf
		p.Color = color
		p.Material = material or Enum.Material.Concrete
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = arena
		return p
	end
	local concrete = Color3.fromRGB(118, 120, 122)
	block("Floor", Vector3.new(200, 2, 200), CFrame.new(0, -1, 0), concrete)
	-- лестница: 8 ступеней по 1 stud
	for i = 0, 7 do
		block("Step" .. (i + 1), Vector3.new(14, (i + 1), 2.2), CFrame.new(-30, (i + 1) / 2, -20 - i * 2.2), Color3.fromRGB(104, 106, 108))
	end
	block("Wall", Vector3.new(30, 14, 2), CFrame.new(28, 7, -30), Color3.fromRGB(96, 98, 100))
	block("Ramp", Vector3.new(14, 1, 30), CFrame.new(0, 4, -55) * CFrame.Angles(math.rad(16), 0, 0), Color3.fromRGB(110, 112, 114))
	for i = 1, 4 do
		block("Crate" .. i, Vector3.new(4, 4, 4), CFrame.new(18 + i * 5, 2, -8) * CFrame.Angles(0, math.rad(i * 17), 0), Color3.fromRGB(120, 92, 62), Enum.Material.WoodPlanks)
	end
	arena.Parent = workspace
	return arena
end

function DevSystem.Start(context)
	ragdoll = context.Get("RagdollSystem")
	characters = context.Get("CharacterSystem")
	if not RunService:IsStudio() then
		return
	end
	active = true
	DevSystem.BuildArena()
	dummyFolder = workspace:FindFirstChild("DevDummies") or Instance.new("Folder")
	dummyFolder.Name = "DevDummies"
	dummyFolder.Parent = workspace
	context.Get("NetService").Connect("DevCommand", function(player, command, point)
		DevSystem.Run(player, command, point)
	end)
	log:Info("стенд проверки включён (Studio): J — упасть, K — выстрел в голову, L — по ногам, H — взрыв в прицел, N — манекены, M — убрать манекены, P — статистика")
end

return DevSystem
