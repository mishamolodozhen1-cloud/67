-- WeaponSystem: оружие на сервере — выдача, патроны, перезарядка, режим огня, проверка выстрелов и попаданий.
--
-- Модель: AK-47 (WeaponAssets.Models.AK47) загружается один раз при запуске и собирается в шаблон
-- ReplicatedStorage.Assets.Weapons.AK47 (детали Body, Magazine, ChargingHandle; суставы магазина и затвора;
-- точки Muzzle, Eject, прицел, хваты). Клиенты берут оттуда же оружие для вида от первого лица и гильзы.
-- Если модель не загрузилась — оружие из простых деталей тех же размеров (и ошибка в журнал): играть можно.
--
-- Выдача: каждому появившемуся персонажу — AK-47 у плеча: Motor6D «RifleHold» от UpperTorso к Body.
-- Как держать (поза, руки по ИК, наклон корпуса за взглядом, перезарядка) — считают клиенты
-- (Controllers/ThirdPersonWeapons) по атрибутам персонажа: Weapon, AimPitch, Aiming, Reloading, ReloadKind.
-- Погиб — оружие падает рядом с телом.
--
-- Патроны и перезарядка — только здесь: клиент показывает сразу (предсказание), но решает сервер; при
-- расхождении сервер присылает WeaponState, и клиент поправляется.
--
-- Выстрел (событие Fire): сервер проверяет темп, патроны, перезарядку, точку выстрела (у головы стрелка) и,
-- если клиент сообщил о попадании, — геометрию попадания с компенсацией задержки (HitCheck, History).
-- Принятый выстрел: −1 патрон, остальным игрокам — ShotFired (эффекты), стрелку при попадании —
-- HitConfirmed; сигналы ShotFired / HitConfirmed — для урона (этап 5) и статистики.
local CollectionService = game:GetService("CollectionService")
local InsertService = game:GetService("InsertService")
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Configs = ReplicatedStorage:WaitForChild("Configs")
local Logger = require(Shared:WaitForChild("Logger"))
local Signal = require(Shared:WaitForChild("Signal"))
local WeaponAnim = require(Shared:WaitForChild("WeaponAnim"))
local WeaponConfig = require(Configs:WaitForChild("WeaponConfig"))
local WeaponModels = require(Configs:WaitForChild("WeaponModels"))
local WeaponAssets = require(Configs:WaitForChild("WeaponAssets"))
local WeaponPoses = require(Configs:WaitForChild("WeaponPoses"))
local RagdollConfig = require(Configs:WaitForChild("RagdollConfig"))

local HitCheck = require(script:WaitForChild("HitCheck"))
local History = require(script:WaitForChild("History"))

local WeaponSystem = { Name = "WeaponSystem" }

WeaponSystem.ShotFired = Signal.new() -- (player, shot) shot = { Weapon, Origin, Direction, End, Hit }
WeaponSystem.HitConfirmed = Signal.new() -- (player, hit) hit = { Weapon, Target, Humanoid, Part, Position, Direction, Distance, Headshot }

-- Тег целей: персонажи игроков и манекены стенда. Их положения пишутся в историю
WeaponSystem.TargetTag = "DC_Target"
-- Группа столкновений гильз и упавшего оружия: мир — да, персонажи и тела — нет
WeaponSystem.DebrisGroup = "DC_Debris"

local log = Logger.new("Weapon")
local cfg = WeaponConfig.Server

local net = nil
local ragdoll = nil
local states = {} -- player -> состояние оружия
local history = History.new(cfg.HistoryWindow)
local templates = {} -- имя оружия -> Model
local usedFallback = false
local recordAccum = 0

local function now()
	return workspace:GetServerTimeNow()
end

local function weaponDef(name)
	return WeaponConfig.Weapons[name]
end

-------------------------------------------------------------------------------
-- Модель оружия
-------------------------------------------------------------------------------
local LOAD_ATTEMPTS = 3

local function loadMeshes(assetId)
	local ok, asset
	for attempt = 1, LOAD_ATTEMPTS do
		ok, asset = pcall(InsertService.LoadAsset, InsertService, assetId)
		if ok then
			break
		end
		log:Warn("модель оружия %d: попытка %d из %d не удалась: %s", assetId, attempt, LOAD_ATTEMPTS, tostring(asset))
		if attempt < LOAD_ATTEMPTS then
			task.wait(2 * attempt)
		end
	end
	if not ok then
		log:Error("модель оружия %d не загрузилась: %s", assetId, tostring(asset))
		return nil
	end
	local meshes = {}
	for _, d in ipairs(asset:GetDescendants()) do
		if d:IsA("MeshPart") then
			meshes[d.Name] = d
		end
	end
	return meshes, asset
end

local function setupPart(p)
	p.Anchored = false
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false -- лучи выстрелов сквозь оружие (попадания — по телу)
	p.Massless = true
	p.CastShadow = true
	p.Material = Enum.Material.SmoothPlastic
	p.Reflectance = 0
end

-- Собрать шаблон оружия name из деталей meshes (имя -> MeshPart) или, если их нет, из простых деталей.
-- Возвращает Model (PrimaryPart — Body) и деталь гильзы
function WeaponSystem.BuildTemplate(name, meshes)
	local geo = WeaponModels[name]
	local model = Instance.new("Model")
	model.Name = name
	local parts = {}
	for partName, spec in pairs(geo.Parts) do
		local p
		if meshes and meshes[partName] then
			p = meshes[partName]:Clone()
		else
			p = Instance.new("Part")
			p.Color = partName == "Body" and Color3.fromRGB(58, 46, 36) or Color3.fromRGB(32, 32, 34)
		end
		p.Name = partName
		p.Size = spec.Size
		p.CFrame = CFrame.new(spec.Offset)
		setupPart(p)
		parts[partName] = p
	end
	local casing = parts.Casing
	parts.Casing = nil
	for _, p in pairs(parts) do
		p.Parent = model
	end
	local body = parts.Body
	model.PrimaryPart = body
	-- магазин и рукоять затвора — на суставах: клиенты двигают их при перезарядке
	for jointName, partName in pairs({ MagJoint = "Magazine", BoltJoint = "ChargingHandle" }) do
		local m = Instance.new("Motor6D")
		m.Name = jointName
		m.Part0 = body
		m.Part1 = parts[partName]
		m.C0 = CFrame.new(geo.Parts[partName].Offset)
		m.C1 = CFrame.identity
		m.Parent = parts[partName]
	end
	for pointName, pos in pairs(geo.Points) do
		local a = Instance.new("Attachment")
		a.Name = pointName
		a.Position = pos
		a.Parent = body
	end
	model:SetAttribute("Weapon", name)
	casing.Name = name .. "Casing"
	casing.Massless = false
	return model, casing
end

local function assetsFolder()
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if not assets then
		assets = Instance.new("Folder")
		assets.Name = "Assets"
		assets.Parent = ReplicatedStorage
	end
	local folder = assets:FindFirstChild("Weapons")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Weapons"
		folder.Parent = assets
	end
	return folder
end

function WeaponSystem.Template(name)
	return templates[name or WeaponConfig.Default]
end

function WeaponSystem.UsedFallback()
	return usedFallback
end

-------------------------------------------------------------------------------
-- Состояние игрока
-------------------------------------------------------------------------------
local function snapshot(st, reason)
	return {
		Weapon = st.Weapon,
		Ammo = st.Ammo,
		Reserve = st.Reserve,
		Mode = st.Mode,
		Reloading = st.Reload ~= nil,
		ReloadKind = st.Reload and st.Reload.Kind or nil,
		ReloadEnd = st.Reload and st.Reload.End or nil,
		Reason = reason,
	}
end

function WeaponSystem.GetState(player)
	local st = states[player]
	return st and snapshot(st) or nil
end

local function isPlayer(player)
	return typeof(player) == "Instance" and player:IsA("Player")
end

local function sendState(player, reason)
	local st = states[player]
	if st and net and isPlayer(player) then
		net.Fire(player, "WeaponState", snapshot(st, reason))
	end
end

local function aliveParts(character)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (humanoid and humanoid.Health > 0) then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	local head = character:FindFirstChild("Head")
	if not (root and head) then
		return nil
	end
	return humanoid, root, head
end

-- Выдать оружие появившемуся персонажу: полный магазин и запас, оружие у плеча
function WeaponSystem.Equip(player, character, weaponName)
	weaponName = weaponName or WeaponConfig.Default
	local def = weaponDef(weaponName)
	local template = templates[weaponName]
	local torso = character:FindFirstChild("UpperTorso")
	if not (def and template and torso) then
		log:Error("не удалось выдать %s игроку %s", tostring(weaponName), player.Name)
		return nil
	end
	local old = character:FindFirstChild("Weapon")
	if old then
		old:Destroy()
	end
	local gun = template:Clone()
	gun.Name = "Weapon"
	local hold = Instance.new("Motor6D")
	hold.Name = "RifleHold"
	hold.Part0 = torso
	hold.Part1 = gun.PrimaryPart
	hold.C0 = WeaponPoses[weaponName].ThirdPerson.Poses.Ready
	hold.C1 = CFrame.identity
	gun:PivotTo(torso.CFrame * hold.C0)
	hold.Parent = gun.PrimaryPart
	gun.Parent = character
	character:SetAttribute("Weapon", weaponName)
	character:SetAttribute("AimPitch", 0)
	character:SetAttribute("Reloading", 0)
	character:SetAttribute("ReloadKind", "")
	CollectionService:AddTag(character, WeaponSystem.TargetTag)
	states[player] = {
		Weapon = weaponName,
		Def = def,
		Ammo = def.Magazine,
		Reserve = def.Reserve,
		Mode = def.DefaultMode,
		Character = character,
		Reload = nil,
		NextShot = 0,
		LastShotId = -1,
		ReadyAt = now() + def.EquipTime,
		Shots = 0,
		Hits = 0,
	}
	sendState(player, "Equip")
	return gun
end

-- Какое оружие давать появившемуся: функция(player) → имя оружия или nil (без оружия: лобби).
-- Задаёт MatchSystem; без неё — оружие по умолчанию
local loadoutResolver = nil
function WeaponSystem.SetLoadoutResolver(fn)
	loadoutResolver = fn
end

-- Без оружия (лобби)
function WeaponSystem.Unequip(player, character)
	local old = character:FindFirstChild("Weapon")
	if old then
		old:Destroy()
	end
	character:SetAttribute("Weapon", "")
	states[player] = nil
end

-- Погиб: оружие выпадает из рук и падает рядом с телом (лежит вместе с ним)
function WeaponSystem.Drop(character)
	local gun = character:FindFirstChild("Weapon")
	if not gun or not gun.PrimaryPart then
		return
	end
	local hold = gun.PrimaryPart:FindFirstChild("RifleHold")
	if hold then
		hold:Destroy()
	end
	for _, p in ipairs(gun:GetDescendants()) do
		if p:IsA("BasePart") then
			p.Massless = false
			p.CanCollide = p.Name == "Body" or p.Name == "Magazine"
			p.CollisionGroup = WeaponSystem.DebrisGroup
		end
	end
	local body = gun.PrimaryPart
	if body:IsDescendantOf(workspace) then
		pcall(body.SetNetworkOwner, body, nil)
		body:ApplyImpulse(body.CFrame.LookVector * body.AssemblyMass * 4 + Vector3.new(0, body.AssemblyMass * 6, 0))
	end
	character:SetAttribute("Weapon", "")
end

-------------------------------------------------------------------------------
-- Перезарядка и режим огня
-------------------------------------------------------------------------------
local function finishReload(player, token)
	local st = states[player]
	if not (st and st.Reload and st.Reload.Token == token) then
		return
	end
	local take = math.min(st.Def.Magazine - st.Ammo, st.Reserve)
	st.Ammo = st.Ammo + take
	st.Reserve = st.Reserve - take
	st.Reload = nil
	if st.Character and st.Character.Parent then
		st.Character:SetAttribute("Reloading", 0)
		st.Character:SetAttribute("ReloadKind", "")
	end
	sendState(player, "Reloaded")
end

-- Начать перезарядку. Возвращает true, если началась
function WeaponSystem.StartReload(player)
	local st = states[player]
	if not st or not aliveParts(player.Character) or player.Character ~= st.Character then
		return false
	end
	if st.Reload or st.Ammo >= st.Def.Magazine or st.Reserve <= 0 then
		sendState(player, "NoReload")
		return false
	end
	local kind = st.Ammo == 0 and "Empty" or "Tactical"
	local length = WeaponAnim.Length(WeaponPoses[st.Weapon], kind)
	local t = now()
	local token = {}
	st.Reload = { Kind = kind, Start = t, End = t + length, Token = token }
	st.Character:SetAttribute("Reloading", t)
	st.Character:SetAttribute("ReloadKind", kind)
	sendState(player, "Reload")
	task.delay(length, finishReload, player, token)
	return true
end

-- Для тестов: закончить идущую перезарядку сейчас
function WeaponSystem.FinishReloadNow(player)
	local st = states[player]
	if st and st.Reload then
		finishReload(player, st.Reload.Token)
	end
end

function WeaponSystem.SetMode(player, mode)
	local st = states[player]
	if not st then
		return false
	end
	if table.find(st.Def.Modes, mode) then
		st.Mode = mode
	end
	sendState(player, "Mode")
	return st.Mode == mode
end

-------------------------------------------------------------------------------
-- Выстрел
-------------------------------------------------------------------------------
-- Все, сквозь кого летит «мировой» луч сервера: персонажи, манекены, тела (по ним — отдельная проверка)
local function worldParams()
	local list = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	for _, name in ipairs({ "DevDummies", "Corpses" }) do
		local f = workspace:FindFirstChild(name)
		if f then
			table.insert(list, f)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = list
	params.IgnoreWater = true
	return params
end

-- Цель, в чью часть тела попали: живой персонаж или манекен с тегом цели (не сам стрелок)
local function targetOf(part, shooterCharacter)
	local model = part.Parent
	if not (model and model:IsA("Model")) or model == shooterCharacter then
		return nil
	end
	if not CollectionService:HasTag(model, WeaponSystem.TargetTag) then
		return nil
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	if not (humanoid and root and humanoid.Health > 0) then
		return nil
	end
	return model, humanoid, root
end

-- Проверить попадание, о котором сообщил клиент. Возвращает таблицу попадания или nil и причину
function WeaponSystem.CheckHit(shooterCharacter, origin, dir, clientTime, serverTime, part, point, wallDist, range)
	if not (part and part:IsDescendantOf(workspace)) then
		return nil, "часть не в мире"
	end
	local model, humanoid, root = targetOf(part, shooterCharacter)
	if not model then
		return nil, "не цель"
	end
	local t = HitCheck.RewindTime(clientTime, serverTime, cfg.InterpDelay, cfg.MaxRewind)
	local rootThen = history:At(model, t) or root.CFrame
	-- где была часть у стрелка на экране (отмотано назад) и где она сейчас: подходит любое
	local positions = { HitCheck.Rewind(part.CFrame, root.CFrame, rootThen), part.CFrame }
	local dist = nil
	for _, cf in ipairs(positions) do
		local d = HitCheck.RayHitsPart(origin, dir, cf, part.Size, cfg.HitTolerance)
		if d and d <= range and d <= wallDist + cfg.WallTolerance then
			dist = d
			break
		end
	end
	if not dist then
		return nil, "луч не проходит через цель"
	end
	local position = origin + dir * dist
	if point and HitCheck.PointOnRay(origin, dir, point, range, 1.5) and (point - origin).Magnitude <= wallDist + cfg.WallTolerance then
		position = point
	end
	return {
		Target = model,
		Humanoid = humanoid,
		Part = part,
		Position = position,
		Direction = dir,
		Distance = (position - origin).Magnitude,
		Headshot = part.Name == "Head",
		Rewind = serverTime - t,
	}
end

-- Обработать выстрел. Возвращает true и результат { Hit, End, Normal, Material, Kind } или false и причину
function WeaponSystem.HandleFire(player, shotId, origin, direction, clientTime, hitPart, hitPos)
	local st = states[player]
	local character = player.Character
	if not st or character ~= st.Character then
		return false, "нет оружия"
	end
	local humanoid, root, head = aliveParts(character)
	if not humanoid then
		return false, "не жив"
	end
	if character:GetAttribute("Ragdolled") == true then
		return false, "лежит"
	end
	local t = now()
	if st.Reload then
		sendState(player, "Reloading")
		return false, "перезарядка"
	end
	if t < st.ReadyAt - cfg.RateJitter then
		return false, "достаёт оружие"
	end
	if st.Ammo <= 0 then
		sendState(player, "Empty")
		return false, "нет патронов"
	end
	if shotId <= st.LastShotId then
		return false, "повтор выстрела"
	end
	local interval = 60 / st.Def.Rpm
	if t + cfg.RateJitter < st.NextShot then
		sendState(player, "Rate")
		return false, "слишком часто"
	end
	if direction.Magnitude < 0.98 then
		return false, "направление"
	end
	direction = direction.Unit
	local okPing, ping = pcall(player.GetNetworkPing, player)
	local latency = (okPing and type(ping) == "number" and ping or 0.1) + 0.1
	if not HitCheck.OriginOk(origin, head.Position, root.AssemblyLinearVelocity.Magnitude, latency, cfg.OriginTolerance) then
		sendState(player, "Origin")
		return false, "точка выстрела далеко от стрелка"
	end
	-- выстрел принят
	st.NextShot = math.max(st.NextShot, t - cfg.RateJitter) + interval
	st.LastShotId = shotId
	st.Ammo = st.Ammo - 1
	st.Shots = st.Shots + 1
	local range = math.min(st.Def.Range, cfg.Range)
	local result = workspace:Raycast(origin, direction * range, worldParams())
	local wallDist = result and (result.Position - origin).Magnitude or range
	local hit, why = nil, nil
	if hitPart then
		hit, why = WeaponSystem.CheckHit(character, origin, direction, clientTime, t, hitPart, hitPos, wallDist, range)
		if not hit then
			log:Debug("%s: попадание не засчитано (%s)", player.Name, tostring(why))
		end
	end
	local out = { Hit = hit }
	if hit then
		out.End, out.Normal, out.Material, out.Kind = hit.Position, nil, "Body", "Body"
	elseif result then
		out.End, out.Normal, out.Material, out.Kind = result.Position, result.Normal, result.Material.Name, "World"
	else
		out.End, out.Kind = origin + direction * range, "None"
	end
	if net then
		net.FireExcept(player, "ShotFired", player, origin, out.End, out.Normal, out.Material, out.Kind)
	end
	WeaponSystem.ShotFired:Fire(player, { Weapon = st.Weapon, Origin = origin, Direction = direction, End = out.End, Hit = hit })
	if hit then
		st.Hits = st.Hits + 1
		hit.Weapon = st.Weapon
		if ragdoll then
			ragdoll.RecordHit(hit.Target, hit.Part.Name, direction, 1, hit.Position)
		end
		WeaponSystem.HitConfirmed:Fire(player, hit)
		if net and isPlayer(player) then
			-- урон и убийство посчитал CombatSystem (обработчик сигнала выше выполняется сразу)
			net.Fire(player, "HitConfirmed", {
				Part = hit.Part.Name,
				Headshot = hit.Headshot,
				Position = hit.Position,
				Damage = hit.Damage and math.floor(hit.Damage + 0.5) or 0,
				Kill = hit.Killed == true,
			})
		end
	end
	return true, out
end

-- Выстрел, который считает сам сервер (боты): луч с учётом персонажей, без компенсации задержки.
-- shooterKey — ключ состояния (таблица бота), model — его модель. Патроны ведёт вызывающий (BotSystem).
-- pellets/spread — для дробовика: несколько дробин с разбросом (градусы). Возвращает список попаданий
function WeaponSystem.ServerShot(shooterKey, model, origin, direction, pellets, spread)
	local st = states[shooterKey]
	if not st or not model then
		return {}
	end
	local range = math.min(st.Def.Range, cfg.Range)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude = { model }
	local corpses = workspace:FindFirstChild("Corpses")
	if corpses then
		table.insert(exclude, corpses)
	end
	params.FilterDescendantsInstances = exclude
	params.IgnoreWater = true
	local hits = {}
	local first = nil
	for i = 1, pellets or 1 do
		local dir = direction
		if spread and spread > 0 and i > 1 then
			local r = math.rad(spread) * math.sqrt(math.random())
			local theta = math.random() * math.pi * 2
			dir = (CFrame.lookAt(Vector3.zero, direction) * CFrame.Angles(0, 0, theta) * CFrame.Angles(r, 0, 0)).LookVector
		end
		local result = workspace:Raycast(origin, dir * range, params)
		local out = { End = origin + dir * range, Kind = "None" }
		if result then
			out.End, out.Normal, out.Material, out.Kind = result.Position, result.Normal, result.Material.Name, "World"
			local target = result.Instance.Parent
			local humanoid = target and target:FindFirstChildOfClass("Humanoid")
			if target and CollectionService:HasTag(target, WeaponSystem.TargetTag) and humanoid and humanoid.Health > 0 then
				local hit = {
					Target = target,
					Humanoid = humanoid,
					Part = result.Instance,
					Position = result.Position,
					Direction = dir,
					Distance = (result.Position - origin).Magnitude,
					Headshot = result.Instance.Name == "Head",
					Weapon = st.Weapon,
				}
				out.Kind, out.Material = "Body", "Body"
				table.insert(hits, hit)
				if ragdoll then
					ragdoll.RecordHit(target, hit.Part.Name, dir, 1, hit.Position)
				end
				WeaponSystem.HitConfirmed:Fire(shooterKey, hit)
			end
		end
		first = first or out
		if net and (i == 1 or i % 3 == 0) then
			net.FireAll("ShotFired", model, origin, out.End, out.Normal, out.Material, out.Kind)
		end
	end
	WeaponSystem.ShotFired:Fire(shooterKey, { Weapon = st.Weapon, Origin = origin, Direction = direction, End = first and first.End, Hit = hits[1] })
	return hits
end

-------------------------------------------------------------------------------
-- История положений целей
-------------------------------------------------------------------------------
function WeaponSystem.History()
	return history
end

function WeaponSystem.RecordTargets()
	local t = now()
	for _, model in ipairs(CollectionService:GetTagged(WeaponSystem.TargetTag)) do
		local root = model:FindFirstChild("HumanoidRootPart")
		if root and model:IsDescendantOf(workspace) then
			history:Record(model, t, root.CFrame)
		end
	end
end

-------------------------------------------------------------------------------
function WeaponSystem.Init(context)
	ragdoll = context.Get("RagdollSystem")
	-- гильзы и упавшее оружие: сталкиваются с миром, но не с персонажами и телами
	local group = WeaponSystem.DebrisGroup
	if not PhysicsService:IsCollisionGroupRegistered(group) then
		PhysicsService:RegisterCollisionGroup(group)
	end
	PhysicsService:CollisionGroupSetCollidable(group, "Default", true)
	PhysicsService:CollisionGroupSetCollidable(group, group, false)
	for _, other in pairs(RagdollConfig.CollisionGroups) do
		if PhysicsService:IsCollisionGroupRegistered(other) then
			PhysicsService:CollisionGroupSetCollidable(group, other, false)
		end
	end
	local folder = assetsFolder()
	for name in pairs(WeaponConfig.Weapons) do
		local meshes, asset = loadMeshes(WeaponAssets.Models[name])
		if not meshes then
			usedFallback = true
		end
		local model, casing = WeaponSystem.BuildTemplate(name, meshes)
		if asset then
			asset:Destroy()
		end
		for _, oldName in ipairs({ name, name .. "Casing" }) do
			local old = folder:FindFirstChild(oldName)
			if old then
				old:Destroy()
			end
		end
		model.Parent = folder
		casing.Parent = folder
		templates[name] = model
	end
	log:Info("оружие готово: %s%s", WeaponConfig.Default, usedFallback and " (запасная модель из деталей)" or "")
	if usedFallback then
		log:Error("модель оружия не загрузилась — оружие из простых деталей")
	end
end

function WeaponSystem.Start(context)
	net = context.Get("NetService")
	local characters = context.Get("CharacterSystem")
	characters.CharacterSpawned:Connect(function(player, character)
		if loadoutResolver then
			local weapon = loadoutResolver(player)
			if weapon then
				WeaponSystem.Equip(player, character, weapon)
			else
				WeaponSystem.Unequip(player, character)
			end
		else
			WeaponSystem.Equip(player, character)
		end
	end)
	characters.CharacterDied:Connect(function(player, character)
		local st = states[player]
		if st and st.Character == character then
			st.Reload = nil
		end
		CollectionService:RemoveTag(character, WeaponSystem.TargetTag)
		history:Forget(character)
		WeaponSystem.Drop(character)
	end)
	Players.PlayerRemoving:Connect(function(player)
		local st = states[player]
		if st and st.Character then
			history:Forget(st.Character)
		end
		states[player] = nil
	end)
	CollectionService:GetInstanceRemovedSignal(WeaponSystem.TargetTag):Connect(function(model)
		history:Forget(model)
	end)
	net.Connect("Fire", function(player, shotId, origin, direction, clientTime, hitPart, hitPos)
		local ok, why = WeaponSystem.HandleFire(player, shotId, origin, direction, clientTime, hitPart, hitPos)
		if not ok then
			log:Debug("%s: выстрел отклонён (%s)", player.Name, tostring(why))
		end
	end)
	net.Connect("Reload", function(player)
		WeaponSystem.StartReload(player)
	end)
	net.Connect("FireMode", function(player, mode)
		WeaponSystem.SetMode(player, mode)
	end)
	net.Connect("AimPitch", function(player, pitch)
		local character = player.Character
		local st = states[player]
		if character and st and st.Character == character then
			local value = math.floor(pitch * 2 + 0.5) / 2
			if character:GetAttribute("AimPitch") ~= value then
				character:SetAttribute("AimPitch", value)
			end
		end
	end)
	-- история положений целей: HistoryRate раз в секунду
	local step = 1 / cfg.HistoryRate
	RunService.Heartbeat:Connect(function(dt)
		recordAccum = recordAccum + dt
		if recordAccum >= step then
			recordAccum = recordAccum % step
			WeaponSystem.RecordTargets()
		end
	end)
	-- персонажи, появившиеся до запуска системы
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character and not states[player] then
			WeaponSystem.Equip(player, player.Character)
		end
	end
end

return WeaponSystem
