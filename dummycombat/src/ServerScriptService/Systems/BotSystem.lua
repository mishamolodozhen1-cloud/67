-- BotSystem: боты-манекены (чтобы в матче всегда было с кем драться, даже одному).
--
-- MatchSystem добирает матч ботами до MatchConfig.FillTo участников (не больше MaxBots), а когда заходят
-- живые игроки — лишних убирает (Balance). Бот — тот же манекен, что у игроков, с тем же оружием и теми же
-- правилами урона; управляет им сервер:
--   • видит: противник в 220 studs и прямая видимость (луч от головы до головы);
--   • реагирует с задержкой 0.35–0.65 с, стреляет очередями, целится с ошибкой (растёт с расстоянием,
--     падает, пока держит цель), иногда в голову; при стрельбе отходит вбок;
--   • без цели — бежит по маршруту (PathfindingService) к последнему месту, где видел противника, или к
--     случайной точке карты; застрял — прыгает и выбирает новую точку;
--   • перезаряжается (те же атрибуты, что у игроков — клиенты показывают перезарядку);
--   • анимации — те же, что у игроков (проигрывает сервер), оружие и руки рисует ThirdPersonWeapons.
local CollectionService = game:GetService("CollectionService")
local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Configs = ReplicatedStorage:WaitForChild("Configs")
local Logger = require(Shared:WaitForChild("Logger"))
local HumanoidUtil = require(Shared:WaitForChild("HumanoidUtil"))
local MatchConfig = require(Configs:WaitForChild("MatchConfig"))
local GameConfig = require(Configs:WaitForChild("GameConfig"))
local WeaponConfig = require(Configs:WaitForChild("WeaponConfig"))
local WeaponPoses = require(Configs:WaitForChild("WeaponPoses"))
local DummyAssets = require(Configs:WaitForChild("DummyAssets"))
local DummyRig = require(Configs:WaitForChild("DummyRig"))

local BotSystem = { Name = "BotSystem" }

BotSystem.SightRange = 220
BotSystem.Names = {
	"Rivet", "Torque", "Piston", "Gasket", "Sprocket", "Ratchet", "Flange", "Crank",
	"Bolt", "Washer", "Socket", "Spanner", "Hinge", "Bearing", "Lever", "Valve",
}

local log = Logger.new("Bots")
local match, characters, weapons, combat, ragdoll, progression = nil, nil, nil, nil, nil, nil
local bots = {} -- identity → состояние бота
local folder = nil
local counter = 0
local rng = Random.new()
local ROOT_Y = DummyRig.HipHeight + DummyRig.RootSize.Y / 2 + 0.05

local function now()
	return workspace:GetServerTimeNow()
end

function BotSystem.Folder()
	if not folder or not folder.Parent then
		folder = workspace:FindFirstChild("Bots") or Instance.new("Folder")
		folder.Name = "Bots"
		folder.Parent = workspace
	end
	return folder
end

function BotSystem.Count()
	local n = 0
	for _ in pairs(bots) do
		n = n + 1
	end
	return n
end

function BotSystem.List()
	local list = {}
	for id, b in pairs(bots) do
		table.insert(list, { Identity = id, Bot = b })
	end
	return list
end

local function freeName()
	local used = {}
	for id in pairs(bots) do
		used[id.Name] = true
	end
	for _ = 1, 40 do
		local n = BotSystem.Names[rng:NextInteger(1, #BotSystem.Names)]
		if not used["BOT " .. n] then
			return "BOT " .. n
		end
	end
	counter = counter + 1
	return "BOT " .. counter
end

-------------------------------------------------------------------------------
-- Модель и анимации
-------------------------------------------------------------------------------
local function loadAnimations(humanoid)
	local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator")
	animator.Parent = humanoid
	local tracks = {}
	for _, name in ipairs({ "Idle", "WalkF", "RunF", "Fall" }) do
		local def = DummyAssets.Animations[name]
		if def then
			local a = Instance.new("Animation")
			a.AnimationId = def.Id
			local ok, track = pcall(animator.LoadAnimation, animator, a)
			if ok and track then
				track.Looped = def.Loop
				track.Priority = Enum.AnimationPriority.Core
				track:Play(0.1, 0.001, 1)
				tracks[name] = { Track = track, Natural = def.Natural, Weight = 0 }
			end
		end
	end
	return tracks
end

local function animate(b, dt)
	local tracks = b.Tracks
	if not tracks then
		return
	end
	local root = b.Root
	local v = root.AssemblyLinearVelocity
	local speed = Vector3.new(v.X, 0, v.Z).Magnitude
	local airborne = b.Humanoid.FloorMaterial == Enum.Material.Air
	local want = { Idle = 0, WalkF = 0, RunF = 0, Fall = 0 }
	if airborne then
		want.Fall = 1
	elseif speed < 0.8 then
		want.Idle = 1
	elseif speed < 15 then
		want.WalkF = 1
	else
		want.RunF = 1
	end
	for name, t in pairs(tracks) do
		t.Weight = t.Weight + ((want[name] or 0) - t.Weight) * math.min(1, dt * 10)
		t.Track:AdjustWeight(math.max(0.001, t.Weight), 0.05)
		if t.Natural and t.Natural > 0 and speed > 0.5 then
			t.Track:AdjustSpeed(math.clamp(speed / t.Natural, 0.3, 2))
		end
	end
end

local function cleanup(b)
	if b.Path then
		b.Path = nil
	end
	if b.Model and b.Model.Parent and not b.Dead then
		b.Model:Destroy()
	end
end

-- Появиться в матче (MatchSystem.Enter для бота)
function BotSystem.SpawnBot(p)
	local identity = p.Key
	local b = bots[identity]
	if not b then
		return
	end
	if b.Model and b.Model.Parent and not b.Dead then
		b.Model:Destroy()
	end
	local template = characters.Template()
	if not template then
		return
	end
	local model = template:Clone()
	model.Name = identity.Name
	model:SetAttribute("Bot", true)
	model:SetAttribute("Stance", "Stand")
	model:SetAttribute("Sprinting", false)
	model:SetAttribute("Aiming", false)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.MaxHealth = GameConfig.Combat.MaxHealth
	humanoid.Health = humanoid.MaxHealth
	humanoid.AutoRotate = false
	local spawnCF = match.ChooseSpawn(p) or CFrame.new(0, 0, 0)
	model:PivotTo(spawnCF * CFrame.new(0, ROOT_Y, 0))
	-- поворот плавно (AlignOrientation) — сервер задаёт только направление
	local att = Instance.new("Attachment")
	att.Name = "BotAlign"
	att.Parent = root
	local align = Instance.new("AlignOrientation")
	align.Name = "BotAlign"
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = att
	align.Responsiveness = 28
	align.MaxTorque = 1e6
	align.CFrame = spawnCF.Rotation
	align.Parent = root
	model.Parent = BotSystem.Folder()
	pcall(root.SetNetworkOwner, root, nil)
	CollectionService:AddTag(model, weapons.TargetTag)
	ragdoll.Track(model)
	ragdoll.OnSpawn(model)
	combat.TrackRegen(model)
	combat.Protect(model, GameConfig.Combat.SpawnProtection)
	identity.Model = model
	identity.Active = true
	match.SetBotModel(p, model)
	progression.ApplySkin(model, progression.SkinFor(identity))
	local weaponName = match.WeaponFor(identity) or identity.Weapon
	weapons.Equip(identity, model, weaponName)
	b.Model, b.Humanoid, b.Root, b.Align = model, humanoid, root, align
	b.Weapon = weaponName
	b.Def = WeaponConfig.Weapons[weaponName]
	b.Ammo = b.Def.Magazine
	b.Dead = false
	b.Target, b.SeenAt, b.Reaction = nil, 0, 0
	b.NextShot, b.BurstLeft, b.PauseUntil = 0, 0, 0
	b.Goal, b.Path, b.Waypoint, b.PathAt = nil, nil, nil, 0
	b.LastPos, b.StuckFor = root.Position, 0
	b.StrafeUntil, b.StrafeDir = 0, 1
	b.Tracks = loadAnimations(humanoid)
	HumanoidUtil.OnDeath(humanoid, function()
		b.Dead = true
		b.Tracks = nil
		local token = b.Model
		task.delay(MatchConfig.RespawnDelay, function()
			if token and token.Parent then
				ragdoll.DetachCorpse(nil, token)
			end
			if bots[identity] == b and b.Model == token and p.InMatch then
				BotSystem.SpawnBot(p)
			end
		end)
	end)
end

-- Новый бот в матч
function BotSystem.AddBot()
	counter = counter + 1
	local identity = { Name = freeName(), UserId = -(1000 + counter), IsBot = true, Active = true }
	local options = { "AK47", "AK47", "SMG" }
	local w = options[rng:NextInteger(1, #options)]
	identity.Weapon = WeaponConfig.Weapons[w] and w or WeaponConfig.Default
	local skins = { "Classic", "Graphite", "Arctic", "Olive", "Crimson", "Cobalt" }
	identity.Skin = skins[rng:NextInteger(1, #skins)]
	bots[identity] = { Identity = identity }
	local p = match.AddBot(identity)
	match.Enter(p)
	return identity
end

function BotSystem.RemoveBot(identity)
	local b = bots[identity]
	if not b then
		return
	end
	identity.Active = false
	bots[identity] = nil
	cleanup(b)
	match.RemoveBot(identity)
end

function BotSystem.Clear()
	for identity in pairs(bots) do
		BotSystem.RemoveBot(identity)
	end
end

-- Сколько ботов нужно: до FillTo участников вместе с игроками в матче (в командах — поровну)
function BotSystem.Balance()
	local phase = match.Phase()
	if phase ~= "Starting" and phase ~= "Running" then
		return
	end
	local humans = 0
	for _, p in ipairs(match.InMatch()) do
		if not p.IsBot then
			humans = humans + 1
		end
	end
	local want = math.clamp(MatchConfig.FillTo - humans, 0, MatchConfig.MaxBots)
	if humans == 0 then
		want = 0 -- без игроков ботам драться не для кого
	end
	while BotSystem.Count() < want do
		BotSystem.AddBot()
	end
	while BotSystem.Count() > want do
		local victim = next(bots)
		BotSystem.RemoveBot(victim)
	end
end

-------------------------------------------------------------------------------
-- Мозг
-------------------------------------------------------------------------------
local function enemiesOf(identity)
	local p = match.Participant(identity)
	local list = {}
	if not p then
		return list
	end
	local teams = match.State().Mode and match.State().Mode.Teams
	for _, q in ipairs(match.InMatch()) do
		if q ~= p and (not teams or q.Team ~= p.Team) then
			local c = match.CharacterOf(q)
			local hum = c and c:FindFirstChildOfClass("Humanoid")
			local head = c and c:FindFirstChild("Head")
			if hum and hum.Health > 0 and head and c:GetAttribute("Ragdolled") ~= true then
				table.insert(list, { Model = c, Head = head, Humanoid = hum })
			end
		end
	end
	return list
end

local function visible(b, target)
	local origin = b.Model.Head.Position
	local to = target.Head.Position - origin
	if to.Magnitude > BotSystem.SightRange then
		return false
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { b.Model, workspace:FindFirstChild("Corpses") }
	local r = workspace:Raycast(origin, to, params)
	return r == nil or r.Instance:IsDescendantOf(target.Model)
end

local function lookAt(b, pos)
	local root = b.Root
	local flat = Vector3.new(pos.X - root.Position.X, 0, pos.Z - root.Position.Z)
	if flat.Magnitude > 0.1 then
		b.Align.CFrame = CFrame.lookAt(Vector3.zero, flat.Unit)
	end
end

local function pickGoal(b)
	local map = match.State().Map
	if b.LastSeen and now() - b.LastSeenAt < 8 then
		return b.LastSeen
	end
	local enemies = enemiesOf(b.Identity)
	if #enemies > 0 and rng:NextNumber() < 0.6 then
		return enemies[rng:NextInteger(1, #enemies)].Model.HumanoidRootPart.Position
	end
	if map and #map.Spawns > 0 then
		return map.Spawns[rng:NextInteger(1, #map.Spawns)].Position
	end
	return b.Root.Position
end

local function computePath(b, goal)
	b.PathAt = now()
	b.Computing = true
	task.spawn(function()
		local path = PathfindingService:CreatePath({ AgentRadius = 1.6, AgentHeight = 6, AgentCanJump = true, WaypointSpacing = 6 })
		local ok = pcall(path.ComputeAsync, path, b.Root.Position, goal)
		b.Computing = false
		if ok and path.Status == Enum.PathStatus.Success then
			b.Path = path:GetWaypoints()
			b.Waypoint = 2
		else
			b.Path = nil
			b.Goal = nil
		end
	end)
end

local function setMove(b, sprint, aiming)
	local speed = sprint and GameConfig.Movement.SprintSpeed or GameConfig.Movement.WalkSpeed
	if aiming then
		speed = GameConfig.Movement.WalkSpeed * GameConfig.Movement.AimSpeedFactor
	end
	b.Humanoid.WalkSpeed = speed
	if b.Model:GetAttribute("Sprinting") ~= sprint then
		b.Model:SetAttribute("Sprinting", sprint)
	end
	if b.Model:GetAttribute("Aiming") ~= aiming then
		b.Model:SetAttribute("Aiming", aiming)
	end
end

local function startReload(b)
	if b.ReloadEnd then
		return
	end
	local kind = b.Ammo == 0 and "Empty" or "Tactical"
	local length = WeaponPoses[b.Weapon].Reloads[kind].Length
	b.ReloadEnd = now() + length
	b.Model:SetAttribute("Reloading", now())
	b.Model:SetAttribute("ReloadKind", kind)
end

local function shoot(b, target, dist)
	local def = b.Def
	local head = b.Model.Head
	local aimPart = (rng:NextNumber() < 0.14) and target.Head or (target.Model:FindFirstChild("UpperTorso") or target.Head)
	local held = now() - b.SeenAt
	local err = math.rad(math.clamp(1.4 + dist / 45 - held * 0.8, 0.5, 5))
	local origin = head.Position + Vector3.new(0, 0.2, 0)
	local dir = (aimPart.Position - origin).Unit
	local theta = rng:NextNumber(0, math.pi * 2)
	local r = err * math.sqrt(rng:NextNumber())
	dir = (CFrame.lookAt(Vector3.zero, dir) * CFrame.Angles(0, 0, theta) * CFrame.Angles(r, 0, 0)).LookVector
	weapons.ServerShot(b.Identity, b.Model, origin, dir, def.Pellets, def.Spread and def.Spread.Pellet)
	b.Ammo = b.Ammo - 1
	b.NextShot = now() + 60 / def.Rpm * (def.Modes[1] == "Semi" and rng:NextNumber(1.6, 2.6) or 1)
	b.BurstLeft = b.BurstLeft - 1
	if b.BurstLeft <= 0 then
		b.PauseUntil = now() + rng:NextNumber(0.2, 0.55)
		b.BurstLeft = rng:NextInteger(3, 7)
	end
	if b.Ammo <= 0 then
		startReload(b)
	end
end

local function think(b, dt)
	if b.Dead or not (b.Model and b.Model.Parent) or not b.Root then
		return
	end
	if b.Model:GetAttribute("Ragdolled") == true then
		return
	end
	animate(b, dt)
	local t = now()
	-- оружие сменилось (GUN GAME: новый уровень) — свежий магазин нового оружия
	local held = b.Model:GetAttribute("Weapon")
	if held and held ~= "" and held ~= b.Weapon and WeaponConfig.Weapons[held] then
		b.Weapon, b.Def = held, WeaponConfig.Weapons[held]
		b.Ammo, b.ReloadEnd = b.Def.Magazine, nil
		b.Model:SetAttribute("Reloading", 0)
	end
	if b.ReloadEnd and t >= b.ReloadEnd then
		b.ReloadEnd = nil
		b.Ammo = b.Def.Magazine
		b.Model:SetAttribute("Reloading", 0)
		b.Model:SetAttribute("ReloadKind", "")
	end
	if match.Phase() ~= "Running" and match.Phase() ~= "Starting" then
		b.Humanoid:Move(Vector3.zero)
		return
	end
	-- цель: ближайший видимый противник
	local best, bestDist = nil, math.huge
	for _, e in ipairs(enemiesOf(b.Identity)) do
		local d = (e.Head.Position - b.Root.Position).Magnitude
		if d < bestDist and visible(b, e) then
			best, bestDist = e, d
		end
	end
	if best then
		if not b.Target or b.Target.Model ~= best.Model then
			b.Target = best
			b.SeenAt = t
			b.Reaction = t + rng:NextNumber(0.35, 0.65)
			b.BurstLeft = rng:NextInteger(3, 7)
		end
		b.LastSeen, b.LastSeenAt = best.Model.HumanoidRootPart.Position, t
		lookAt(b, best.Head.Position)
		local d = best.Head.Position - b.Model.Head.Position
		b.Model:SetAttribute("AimPitch", math.floor(math.deg(math.asin(math.clamp(d.Unit.Y, -1, 1))) * 2 + 0.5) / 2)
		setMove(b, false, bestDist > 45)
		-- шаг вбок, иногда — ближе или дальше
		if t > b.StrafeUntil then
			b.StrafeUntil = t + rng:NextNumber(0.6, 1.4)
			b.StrafeDir = rng:NextNumber() < 0.5 and -1 or 1
			if rng:NextNumber() < 0.25 then
				b.StrafeDir = 0
			end
		end
		local right = b.Root.CFrame.RightVector
		local fwd = Vector3.new(d.X, 0, d.Z).Unit
		local move = right * b.StrafeDir
		if bestDist > 90 then
			move = move + fwd
		elseif bestDist < 12 then
			move = move - fwd
		end
		b.Humanoid:Move(move.Magnitude > 0.01 and move.Unit or Vector3.zero, false)
		b.Path = nil
		if match.Phase() == "Running" and t >= b.Reaction and t >= b.NextShot and t >= b.PauseUntil and not b.ReloadEnd and b.Ammo > 0 then
			shoot(b, best, bestDist)
		end
		return
	end
	b.Target = nil
	setMove(b, true, false)
	if b.Ammo < b.Def.Magazine * 0.5 and not b.ReloadEnd then
		startReload(b)
	end
	-- маршрут
	if not b.Computing and (not b.Path or t - b.PathAt > 4) then
		b.Goal = pickGoal(b)
		computePath(b, b.Goal)
	end
	local wp = b.Path and b.Path[b.Waypoint]
	if wp then
		local to = wp.Position - b.Root.Position
		if Vector3.new(to.X, 0, to.Z).Magnitude < 3 then
			b.Waypoint = b.Waypoint + 1
			if b.Waypoint > #b.Path then
				b.Path = nil
			end
		else
			b.Humanoid:MoveTo(wp.Position)
			lookAt(b, wp.Position)
			if wp.Action == Enum.PathWaypointAction.Jump then
				b.Humanoid.Jump = true
			end
		end
	end
	-- застрял: прыжок и новая цель
	local moved = (b.Root.Position - b.LastPos).Magnitude
	b.LastPos = b.Root.Position
	if moved < 0.15 * dt * 60 and b.Path then
		b.StuckFor = b.StuckFor + dt
		if b.StuckFor > 1.2 then
			b.Humanoid.Jump = true
			b.Path = nil
			b.StuckFor = 0
		end
	else
		b.StuckFor = 0
	end
end

function BotSystem.Init(context)
	match = context.Get("MatchSystem")
	characters = context.Get("CharacterSystem")
	weapons = context.Get("WeaponSystem")
	combat = context.Get("CombatSystem")
	ragdoll = context.Get("RagdollSystem")
	progression = context.Get("ProgressionSystem")
	BotSystem.Folder()
end

function BotSystem.Start()
	local accum = 0
	RunService.Heartbeat:Connect(function(dt)
		accum = accum + dt
		if accum < 0.1 then
			return
		end
		local step = accum
		accum = 0
		for _, b in pairs(bots) do
			local ok, err = pcall(think, b, step)
			if not ok then
				log:Warn("бот %s: %s", tostring(b.Identity.Name), tostring(err))
			end
		end
	end)
end

return BotSystem
