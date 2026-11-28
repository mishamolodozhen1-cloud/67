-- RagdollSystem: тряпичная кукла DUMMY COMBAT. Всё решает сервер; физику регдолла тоже считает сервер
-- (он становится владельцем частей), поэтому все игроки видят одно и то же падение.
--
--   Смерть      Humanoid.Died → регдолл. Последнее попадание (RecordHit: часть, направление, сила) задаёт
--               толчок: попавшая часть получает полный толчок, корпус — долю, голова при попадании в голову
--               ещё и запрокидывается. Поэтому выстрел в голову, в ногу и в корпус роняют тело по-разному.
--   Взрыв       Explode(центр, радиус, сила): каждая часть каждого тела в радиусе получает свой толчок (от
--               центра и вверх, слабее с расстоянием) — ближняя к взрыву рука отлетает сильнее дальней.
--               Живых взрыв роняет (Knockdown) — полежат и встанут; уже лежащих и тела — отбрасывает.
--   Подъём      Recover: суставы снова анимированные, персонаж ставится на ноги там, где лежал таз, лицом
--               туда, куда смотрела грудь; управление и физика возвращаются игроку.
--   Тела        перед возрождением тело отделяется от игрока (DetachCorpse) и лежит ещё Corpses.Lifetime
--               секунд; когда тело замирает, оно «засыпает» (части закрепляются — физика его больше не
--               считает); одновременно не больше Corpses.Max тел (старые исчезают); исчезают плавно.
-- Части регдолла и тела не сталкиваются с живыми игроками (группы столкновений) — нет рывков у бегущих.
local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Configs = ReplicatedStorage:WaitForChild("Configs")
local Logger = require(Shared:WaitForChild("Logger"))
local Signal = require(Shared:WaitForChild("Signal"))
local Maid = require(Shared:WaitForChild("Maid"))
local HumanoidUtil = require(Shared:WaitForChild("HumanoidUtil"))
local RagdollConfig = require(Configs:WaitForChild("RagdollConfig"))
local DummyRig = require(Configs:WaitForChild("DummyRig"))
local RagdollRig = require(script:WaitForChild("RagdollRig"))

local RagdollSystem = { Name = "RagdollSystem" }

RagdollSystem.Ragdolled = Signal.new() -- (character, reason: "Death" | "Knockdown")
RagdollSystem.Recovered = Signal.new() -- (character)
RagdollSystem.Rig = RagdollRig

local log = Logger.new("Ragdoll")
local groups = RagdollConfig.CollisionGroups
local hitCfg = RagdollConfig.Hit
local boomCfg = RagdollConfig.Explosion
local knockCfg = RagdollConfig.Knockdown
local corpseCfg = RagdollConfig.Corpses

local lastHits = setmetatable({}, { __mode = "k" }) -- персонаж -> последнее попадание
local knockdowns = setmetatable({}, { __mode = "k" }) -- персонаж -> { Token }
local corpses = {} -- { Model, Born, Still, Sleeping, Maid }
local corpseFolder = nil
local tracked = setmetatable({}, { __mode = "k" })

local function bodyParts(model)
	local list = {}
	for _, d in ipairs(model:GetChildren()) do
		if d:IsA("BasePart") then
			table.insert(list, d)
		end
	end
	return list
end

local function setOwner(model, owner)
	for _, p in ipairs(bodyParts(model)) do
		if not p.Anchored and p:IsDescendantOf(workspace) then
			local ok, can = pcall(p.CanSetNetworkOwnership, p)
			if ok and can then
				p:SetNetworkOwner(owner)
			end
		end
	end
end

-- Части тела получают изменение скорости (studs/с) — так тяжёлое и лёгкое двигаются одинаково по скорости
local function push(part, velocity, spin)
	if part and not part.Anchored then
		part.AssemblyLinearVelocity = part.AssemblyLinearVelocity + velocity
		if spin then
			part.AssemblyAngularVelocity = part.AssemblyAngularVelocity + spin
		end
	end
end

function RagdollSystem.BuildRig(model)
	return RagdollRig.Build(model)
end

function RagdollSystem.IsRagdolled(model)
	return model:GetAttribute("Ragdolled") == true
end

-- Запомнить попадание (его толчок получит тело, если персонаж умрёт в ближайшие Hit.Window секунд).
-- direction — куда летела пуля (мир), strength — 0..1 (доля полной силы), point — точка попадания
function RagdollSystem.RecordHit(model, partName, direction, strength, point)
	if typeof(direction) ~= "Vector3" or direction.Magnitude < 1e-3 then
		return
	end
	lastHits[model] = { Part = partName, Direction = direction.Unit, Strength = math.clamp(strength or 1, 0, 2), Point = point, At = os.clock() }
end

-- Толчок от попадания: попавшая часть — полный, корпус — доля; голова запрокидывается
function RagdollSystem.HitImpulses(model, hit)
	local list = {}
	local s = hit.Strength
	local part = model:FindFirstChild(hit.Part)
	if part then
		local spin = nil
		if hit.Part == "Head" then
			spin = hit.Direction:Cross(Vector3.new(0, 1, 0)) * hitCfg.HeadTwist * s
		end
		table.insert(list, { Part = part, Velocity = hit.Direction * hitCfg.PartSpeed * s, Spin = spin })
	end
	for _, name in ipairs({ "UpperTorso", "LowerTorso" }) do
		local p = model:FindFirstChild(name)
		if p and p ~= part then
			table.insert(list, { Part = p, Velocity = hit.Direction * hitCfg.BodySpeed * s })
		end
	end
	return list
end

-- Толчок от взрыва для каждой части: от центра и вверх, слабее с расстоянием; немного случайного вращения
function RagdollSystem.ExplosionImpulses(model, center, radius, strength, rng)
	rng = rng or Random.new()
	local list = {}
	for _, p in ipairs(bodyParts(model)) do
		if p.Name ~= "HumanoidRootPart" then
			local offset = p.Position - center
			local d = offset.Magnitude
			if d < radius then
				local k = (1 - d / radius) ^ boomCfg.Falloff * strength
				local dir = d > 1e-3 and offset / d or Vector3.new(0, 1, 0)
				dir = (dir + Vector3.new(0, boomCfg.Lift, 0)).Unit
				local spin = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1), rng:NextNumber(-1, 1)) * boomCfg.Spin * k
				table.insert(list, { Part = p, Velocity = dir * boomCfg.MaxSpeed * k, Spin = spin })
			end
		end
	end
	return list
end

-- Перевести в регдолл. reason: "Death" | "Knockdown"; impulses: { { Part, Velocity, Spin } }
function RagdollSystem.Ragdoll(model, reason, impulses)
	if not RagdollRig.IsBuilt(model) then
		log:Warn("у %s нет физических суставов — регдолл невозможен", model.Name)
		return false
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local already = RagdollSystem.IsRagdolled(model)
	if not already then
		RagdollRig.SetEnabled(model, true, groups.Ragdoll)
		if humanoid and humanoid.Health > 0 then
			-- живой: состояние Physics — Humanoid не пытается встать и не тянет тело сам
			humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, false)
			humanoid:ChangeState(Enum.HumanoidStateType.Physics)
		end
		setOwner(model, nil)
	end
	model:SetAttribute("RagdollReason", reason)
	for _, imp in ipairs(impulses or {}) do
		push(imp.Part, imp.Velocity, imp.Spin)
	end
	if not already then
		RagdollSystem.Ragdolled:Fire(model, reason)
	end
	return true
end

local function floorBelow(model, position)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore = { model }
	if corpseFolder then
		table.insert(ignore, corpseFolder)
	end
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(ignore, p.Character)
		end
	end
	params.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(position + Vector3.new(0, 3, 0), Vector3.new(0, -60, 0), params)
	return hit and hit.Position.Y or (position.Y - 1)
end

-- Поднять после падения (только живого): стоит там, где лежал таз, лицом туда, куда смотрела грудь
function RagdollSystem.Recover(model)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	if not (humanoid and root and humanoid.Health > 0 and RagdollSystem.IsRagdolled(model)) then
		return false
	end
	knockdowns[model] = nil
	local pelvis = model:FindFirstChild("LowerTorso") or root
	local chest = model:FindFirstChild("UpperTorso") or pelvis
	local look = chest.CFrame.LookVector
	look = Vector3.new(look.X, 0, look.Z)
	if look.Magnitude < 0.2 then
		-- лежит лицом вверх или вниз: «вперёд» — куда направлена голова от таза
		local head = model:FindFirstChild("Head") or chest
		local toHead = head.Position - pelvis.Position
		look = Vector3.new(toHead.X, 0, toHead.Z)
		if look.Magnitude < 0.2 then
			look = Vector3.new(0, 0, -1)
		end
	end
	local base = pelvis.Position
	local floorY = floorBelow(model, base)
	local height = DummyRig.HipHeight + DummyRig.RootSize.Y / 2
	RagdollRig.SetEnabled(model, false, groups.Characters)
	for _, p in ipairs(bodyParts(model)) do
		p.AssemblyLinearVelocity = Vector3.zero
		p.AssemblyAngularVelocity = Vector3.zero
	end
	local at = Vector3.new(base.X, floorY + height, base.Z)
	root.CFrame = CFrame.lookAt(at, at + look.Unit)
	model:SetAttribute("RagdollReason", nil)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, true)
	humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	local player = Players:GetPlayerFromCharacter(model)
	if player then
		pcall(root.SetNetworkOwner, root, player)
	else
		pcall(root.SetNetworkOwnershipAuto, root)
	end
	RagdollSystem.Recovered:Fire(model)
	return true
end

local function maxSpeed(model)
	local m = 0
	for _, p in ipairs(bodyParts(model)) do
		if not p.Anchored then
			m = math.max(m, p.AssemblyLinearVelocity.Magnitude)
		end
	end
	return m
end

-- Уронить живого на seconds секунд (не меньше MinTime), затем поднять, когда тело успокоится
function RagdollSystem.Knockdown(model, seconds, impulses)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not (humanoid and humanoid.Health > 0) then
		return false
	end
	if not RagdollSystem.Ragdoll(model, "Knockdown", impulses) then
		return false
	end
	local token = {}
	knockdowns[model] = token
	local minTime = math.clamp(seconds or knockCfg.MinTime, knockCfg.MinTime, knockCfg.MaxTime)
	task.spawn(function()
		local started = os.clock()
		while knockdowns[model] == token and model.Parent and humanoid.Health > 0 do
			local t = os.clock() - started
			if t >= minTime and (maxSpeed(model) < knockCfg.SettleSpeed or t >= knockCfg.MaxTime + knockCfg.GetUpTimeout) then
				RagdollSystem.Recover(model)
				break
			end
			task.wait(0.1)
		end
	end)
	return true
end

-- Смерть: регдолл с толчком от последнего попадания (если оно было недавно)
function RagdollSystem.OnDeath(model)
	local hit = lastHits[model]
	local impulses = nil
	if hit and os.clock() - hit.At <= hitCfg.Window then
		impulses = RagdollSystem.HitImpulses(model, hit)
	end
	knockdowns[model] = nil
	RagdollSystem.Ragdoll(model, "Death", impulses)
	-- скрипты персонажа (анимации) телу больше не нужны
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BaseScript") then
			d:Destroy()
		end
	end
end

-- Следить за смертью модели с Humanoid (игроки — через CharacterSystem, манекены и NPC — через Track)
function RagdollSystem.Track(model)
	if tracked[model] then
		return
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	tracked[model] = true
	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false
	HumanoidUtil.OnDeath(humanoid, function()
		RagdollSystem.OnDeath(model)
	end)
end

-- Все модели с Humanoid, которые может задеть взрыв: персонажи игроков, NPC и тела
local function targets()
	local list, seen = {}, {}
	local function add(m)
		if m and not seen[m] and m:FindFirstChildOfClass("Humanoid") and m:FindFirstChild("HumanoidRootPart") then
			seen[m] = true
			table.insert(list, m)
		end
	end
	for _, p in ipairs(Players:GetPlayers()) do
		add(p.Character)
	end
	for _, folderName in ipairs({ "Corpses", "DevDummies", "ActiveMap", "Bots" }) do
		local f = workspace:FindFirstChild(folderName)
		if f then
			for _, d in ipairs(f:GetDescendants()) do
				if d:IsA("Humanoid") then
					add(d.Parent)
				end
			end
		end
	end
	return list
end

-- Взрыв. strength — 0..1+ (1 — полная сила). opts.LethalRadius: ближе — смерть (до этапа 5 — для проверки).
-- Возвращает список { Model, Distance, Effect = "Killed" | "Knocked" | "Pushed" }
function RagdollSystem.Explode(center, radius, strength, opts)
	opts = opts or {}
	strength = strength or 1
	local rng = Random.new()
	local affected = {}
	for _, model in ipairs(targets()) do
		local closest = math.huge
		for _, p in ipairs(bodyParts(model)) do
			closest = math.min(closest, (p.Position - center).Magnitude)
		end
		if closest < radius then
			local humanoid = model:FindFirstChildOfClass("Humanoid")
			local k = (1 - closest / radius) ^ boomCfg.Falloff * strength
			local effect
			if humanoid.Health > 0 and opts.LethalRadius and closest <= opts.LethalRadius then
				lastHits[model] = nil
				-- смерть от взрыва: сначала регдолл (чтобы толчок достался частям), потом Health = 0
				RagdollSystem.Ragdoll(model, "Death", RagdollSystem.ExplosionImpulses(model, center, radius, strength, rng))
				humanoid.Health = 0
				effect = "Killed"
			elseif humanoid.Health > 0 and not RagdollSystem.IsRagdolled(model) then
				local seconds = knockCfg.MinTime + (knockCfg.MaxTime - knockCfg.MinTime) * math.clamp(k, 0, 1)
				RagdollSystem.Knockdown(model, seconds, RagdollSystem.ExplosionImpulses(model, center, radius, strength, rng))
				effect = "Knocked"
			else
				-- уже лежит (регдолл или тело): разбудить и отбросить
				for _, p in ipairs(bodyParts(model)) do
					if p.Anchored and model:GetAttribute("DC_Corpse") then
						p.Anchored = false
					end
				end
				for _, c in ipairs(corpses) do
					if c.Model == model then
						c.Sleeping, c.Still = false, 0
					end
				end
				if model:GetAttribute("DC_Corpse") then
					setOwner(model, nil)
				end
				for _, imp in ipairs(RagdollSystem.ExplosionImpulses(model, center, radius, strength, rng)) do
					push(imp.Part, imp.Velocity, imp.Spin)
				end
				effect = "Pushed"
			end
			table.insert(affected, { Model = model, Distance = closest, Effect = effect })
		end
	end
	return affected
end

-------------------------------------------------------------------------------
-- Тела погибших
-------------------------------------------------------------------------------
local function removeCorpse(entry, fade)
	local model = entry.Model
	entry.Removed = true
	local i = table.find(corpses, entry)
	if i then
		table.remove(corpses, i)
	end
	if not (fade and model.Parent) then
		entry.Maid:Cleanup()
		return
	end
	local info = TweenInfo.new(corpseCfg.FadeTime, Enum.EasingStyle.Sine)
	for _, p in ipairs(model:GetDescendants()) do
		if (p:IsA("BasePart") and p.Name ~= "HumanoidRootPart") or p:IsA("Decal") then
			TweenService:Create(p, info, { Transparency = 1 }):Play()
		end
	end
	task.delay(corpseCfg.FadeTime + 0.05, function()
		entry.Maid:Cleanup()
	end)
end

-- Отделить тело от игрока перед возрождением: оно остаётся лежать, а игрок получает нового персонажа
function RagdollSystem.DetachCorpse(player, model)
	if not (model and model.Parent and RagdollSystem.IsRagdolled(model)) then
		return nil
	end
	if player and player.Character == model then
		player.Character = nil
	end
	model.Name = "Corpse_" .. (player and player.Name or model.Name)
	model:SetAttribute("DC_Corpse", true)
	model.Parent = corpseFolder
	local entry = { Model = model, Born = os.clock(), Still = 0, Sleeping = false, Maid = Maid.new() }
	entry.Maid:Give(model)
	table.insert(corpses, entry)
	-- лимит: самые старые исчезают сразу
	while #corpses > corpseCfg.Max do
		removeCorpse(corpses[1], false)
	end
	return model
end

function RagdollSystem.Corpses()
	local list = {}
	for _, c in ipairs(corpses) do
		table.insert(list, { Model = c.Model, Sleeping = c.Sleeping, Age = os.clock() - c.Born })
	end
	return list
end

-- Шаг слежения за телами: засыпание неподвижных, исчезновение старых
function RagdollSystem.StepCorpses(dt)
	local now = os.clock()
	for i = #corpses, 1, -1 do
		local c = corpses[i]
		if not c.Model.Parent then
			table.remove(corpses, i)
		elseif now - c.Born >= corpseCfg.Lifetime then
			removeCorpse(c, true)
		elseif not c.Sleeping then
			if maxSpeed(c.Model) < corpseCfg.SleepSpeed then
				c.Still = c.Still + dt
				if c.Still >= corpseCfg.SleepAfter then
					c.Sleeping = true
					for _, p in ipairs(bodyParts(c.Model)) do
						p.Anchored = true
					end
				end
			else
				c.Still = 0
			end
		end
	end
end

local function registerGroups()
	for _, name in ipairs({ groups.Characters, groups.Ragdoll }) do
		if not PhysicsService:IsCollisionGroupRegistered(name) then
			PhysicsService:RegisterCollisionGroup(name)
		end
	end
	PhysicsService:CollisionGroupSetCollidable(groups.Ragdoll, groups.Characters, false)
	PhysicsService:CollisionGroupSetCollidable(groups.Ragdoll, groups.Ragdoll, true)
	PhysicsService:CollisionGroupSetCollidable(groups.Ragdoll, "Default", true)
	PhysicsService:CollisionGroupSetCollidable(groups.Characters, groups.Characters, true)
	PhysicsService:CollisionGroupSetCollidable(groups.Characters, "Default", true)
end

-- Новый персонаж: его части — в группе живых
function RagdollSystem.OnSpawn(model)
	for _, p in ipairs(bodyParts(model)) do
		p.CollisionGroup = groups.Characters
	end
end

function RagdollSystem.Init()
	registerGroups()
	corpseFolder = workspace:FindFirstChild("Corpses")
	if not corpseFolder then
		corpseFolder = Instance.new("Folder")
		corpseFolder.Name = "Corpses"
		corpseFolder.Parent = workspace
	end
end

function RagdollSystem.Start(context)
	local characters = context.Get("CharacterSystem")
	characters.CharacterSpawned:Connect(function(_, model)
		RagdollSystem.OnSpawn(model)
	end)
	characters.CharacterDied:Connect(function(_, model)
		RagdollSystem.OnDeath(model)
	end)
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc = acc + dt
		if acc >= corpseCfg.CheckEvery then
			RagdollSystem.StepCorpses(acc)
			acc = 0
		end
	end)
end

return RagdollSystem
