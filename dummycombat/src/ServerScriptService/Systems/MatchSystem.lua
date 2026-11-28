-- MatchSystem: матчи (этапы 7 и 9). Один сервер — один матч за раз, по кругу:
--   Intermission (в лобби, голосование за карту и режим) → Starting (карта построена, отсчёт, урона нет) →
--   Running (бой до лимита очков или времени) → Results (итоги, награды) → снова Intermission.
--
-- Участники — игроки, нажавшие PLAY, и боты-манекены (BotSystem добирает матч до FillTo). Игрок может
-- войти в идущий матч в любой момент; в лобби оружия нет и урона нет.
-- Режимы (MatchConfig.Modes): FFA — каждый сам за себя; TDM — красные против синих (урон по своим не
-- проходит, команда — по цвету манекена); GunGame — каждое KillsPerWeapon убийств — следующее оружие,
-- победа — убийство с последним; Chaos — FFA под обстрелом: каждые Strike.Every секунд взрывы
-- (за Warning секунд — метка на земле).
--
-- Что видят клиенты: ReplicatedStorage.Match — атрибуты Phase, Mode, ModeName, Map, MapName, EndsAt,
-- ScoreLimit, RedScore, BlueScore, варианты голосования (OptionNMap/Mode/Votes); Match.Participants —
-- по Configuration на участника (Name, UserId, IsBot, Team, Kills, Deaths, Assists, Score, GunLevel, InMatch).
-- События MatchEvent: Countdown, Start, End (итоги), Strike (Chaos), GunLevel.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Configs = ReplicatedStorage:WaitForChild("Configs")
local Logger = require(Shared:WaitForChild("Logger"))
local Signal = require(Shared:WaitForChild("Signal"))
local MatchConfig = require(Configs:WaitForChild("MatchConfig"))
local WeaponConfig = require(Configs:WaitForChild("WeaponConfig"))
local DummyRig = require(Configs:WaitForChild("DummyRig"))

local MatchSystem = { Name = "MatchSystem" }

MatchSystem.MatchStarted = Signal.new() -- (info)
MatchSystem.MatchEnded = Signal.new() -- (results)
MatchSystem.ParticipantEntered = Signal.new() -- (p)
MatchSystem.Kill = Signal.new() -- (kill, killerP, victimP)

local log = Logger.new("Match")
local net, maps, characters, weapons, combat, ragdoll, bots, lobby, progression = nil, nil, nil, nil, nil, nil, nil, nil, nil

local state = {
	Phase = "Idle",
	ModeId = nil,
	Mode = nil,
	Map = nil,
	EndsAt = 0,
	StartedAt = 0,
	Scores = { Red = 0, Blue = 0 },
	Options = {},
	Votes = {},
	Token = 0,
}
local participants = {} -- ключ (Player или таблица бота) → участник
local byModel = setmetatable({}, { __mode = "k" }) -- модель бота → участник
local folder, partsFolder = nil, nil
local rng = Random.new()
MatchSystem.Paused = false -- для тестов: цикл фаз не запускать

local function now()
	return workspace:GetServerTimeNow()
end

local function isPlayer(k)
	return typeof(k) == "Instance" and k:IsA("Player")
end

-------------------------------------------------------------------------------
-- Участники
-------------------------------------------------------------------------------
local function publish(p)
	local f = p.Folder
	if not f then
		f = Instance.new("Configuration")
		f.Name = tostring(p.UserId)
		f.Parent = partsFolder
		p.Folder = f
	end
	for _, k in ipairs({ "Name", "UserId", "IsBot", "Team", "Kills", "Deaths", "Assists", "Score", "GunLevel", "InMatch", "Queued" }) do
		if f:GetAttribute(k) ~= p[k] then
			f:SetAttribute(k, p[k])
		end
	end
end

local function newParticipant(key, name, userId, isBot)
	local p = {
		Key = key,
		Name = name,
		UserId = userId,
		IsBot = isBot,
		Team = "",
		Kills = 0,
		Deaths = 0,
		Assists = 0,
		Score = 0,
		GunLevel = 1,
		GunKills = 0,
		InMatch = false,
		Queued = false,
	}
	participants[key] = p
	publish(p)
	return p
end

local function resetStats(p)
	p.Kills, p.Deaths, p.Assists, p.Score, p.GunLevel, p.GunKills = 0, 0, 0, 0, 1, 0
end

function MatchSystem.Participant(key)
	return participants[key]
end

function MatchSystem.Participants()
	local list = {}
	for _, p in pairs(participants) do
		table.insert(list, p)
	end
	return list
end

function MatchSystem.InMatch()
	local list = {}
	for _, p in pairs(participants) do
		if p.InMatch then
			table.insert(list, p)
		end
	end
	return list
end

-- Участник по модели персонажа (игрока или бота)
function MatchSystem.ParticipantOfModel(model)
	if not model then
		return nil
	end
	local player = Players:GetPlayerFromCharacter(model)
	if player then
		return participants[player]
	end
	return byModel[model]
end

function MatchSystem.SetBotModel(p, model)
	byModel[model] = p
	p.Model = model
end

local function characterOf(p)
	if isPlayer(p.Key) then
		return p.Key.Character
	end
	return p.Model
end
MatchSystem.CharacterOf = characterOf

local function teamCounts()
	local red, blue = 0, 0
	for _, p in pairs(participants) do
		if p.InMatch then
			if p.Team == "Red" then
				red = red + 1
			elseif p.Team == "Blue" then
				blue = blue + 1
			end
		end
	end
	return red, blue
end

local function assignTeam(p)
	if state.Mode and state.Mode.Teams then
		local red, blue = teamCounts()
		p.Team = red <= blue and "Red" or "Blue"
	else
		p.Team = ""
	end
end

-------------------------------------------------------------------------------
-- Появление: где и с каким оружием
-------------------------------------------------------------------------------
local ROOT_Y = DummyRig.HipHeight + DummyRig.RootSize.Y / 2 + 0.05

-- Точка появления: дальше всех от живых противников (из трёх лучших — случайно)
function MatchSystem.ChooseSpawn(p)
	local map = state.Map
	if not map then
		return nil
	end
	local list = map.Spawns
	if state.Mode and state.Mode.Teams and p.Team ~= "" and #map.TeamSpawns[p.Team] > 0 then
		list = map.TeamSpawns[p.Team]
	end
	local enemies = {}
	for _, q in pairs(participants) do
		if q ~= p and q.InMatch and (not state.Mode.Teams or q.Team ~= p.Team) then
			local c = characterOf(q)
			local root = c and c:FindFirstChild("HumanoidRootPart")
			local hum = c and c:FindFirstChildOfClass("Humanoid")
			if root and hum and hum.Health > 0 then
				table.insert(enemies, root.Position)
			end
		end
	end
	local scored = {}
	for _, cf in ipairs(list) do
		local d = math.huge
		for _, e in ipairs(enemies) do
			d = math.min(d, (e - cf.Position).Magnitude)
		end
		table.insert(scored, { CF = cf, D = d + rng:NextNumber(0, 6) })
	end
	table.sort(scored, function(a, b)
		return a.D > b.D
	end)
	local pick = scored[rng:NextInteger(1, math.min(3, #scored))]
	return pick and pick.CF
end

-- Где появиться персонажу игрока (CharacterSystem спрашивает): в матче — точка карты, иначе — лобби
local function spawnResolver(player)
	local p = participants[player]
	if p and p.InMatch and state.Map then
		local cf = MatchSystem.ChooseSpawn(p)
		return cf and cf * CFrame.new(0, ROOT_Y, 0)
	end
	if lobby then
		return lobby.SpawnPoint(player)
	end
	return nil
end

-- Какое оружие выдать (WeaponSystem спрашивает): в матче — по режиму / снаряжению, в лобби — никакого
function MatchSystem.WeaponFor(key)
	local p = participants[key]
	if not (p and p.InMatch) then
		return nil
	end
	if state.ModeId == "GunGame" then
		local list = state.Mode.Weapons
		return list[math.clamp(p.GunLevel, 1, #list)]
	end
	if not p.IsBot and progression then
		local w = progression.PrimaryWeapon(p.Key)
		if w and WeaponConfig.Weapons[w] then
			return w
		end
	end
	return p.Weapon or WeaponConfig.Default
end

-- Можно ли наносить урон: только в бою, только участникам матча, не своим в командном режиме
local function canDamage(attacker, victimModel)
	if state.Phase ~= "Running" then
		return false
	end
	local a = participants[attacker]
	local v = MatchSystem.ParticipantOfModel(victimModel)
	if not v then
		-- манекены стенда в Studio — можно
		return victimModel.Parent ~= nil and victimModel.Parent.Name == "DevDummies"
	end
	if not (a and a.InMatch and v.InMatch) then
		return false
	end
	if state.Mode.Teams and a.Team ~= "" and a.Team == v.Team then
		return false
	end
	return true
end
MatchSystem.CanDamage = canDamage

-------------------------------------------------------------------------------
-- Вход и выход
-------------------------------------------------------------------------------
local function setInMatch(p, on)
	p.InMatch = on
	p.Queued = false
	publish(p)
	if isPlayer(p.Key) then
		p.Key:SetAttribute("InMatch", on)
	end
end

-- Ввести участника в идущую игру: команда, статистика, появление на карте
function MatchSystem.Enter(p)
	resetStats(p)
	assignTeam(p)
	setInMatch(p, true)
	if isPlayer(p.Key) then
		p.Key:SetAttribute("Team", p.Team)
		characters.Spawn(p.Key)
	elseif bots then
		bots.SpawnBot(p)
	end
	MatchSystem.ParticipantEntered:Fire(p)
end

-- Игрок нажал PLAY
function MatchSystem.Join(player)
	local p = participants[player] or newParticipant(player, player.DisplayName ~= "" and player.DisplayName or player.Name, player.UserId, false)
	if p.InMatch then
		return "InMatch"
	end
	if state.Phase == "Running" or state.Phase == "Starting" then
		MatchSystem.Enter(p)
		if bots then
			bots.Balance()
		end
		return "Entered"
	end
	p.Queued = true
	publish(p)
	return "Queued"
end

-- Игрок вышел в лобби
function MatchSystem.Leave(player)
	local p = participants[player]
	if not p then
		return
	end
	local was = p.InMatch
	setInMatch(p, false)
	p.Team = ""
	player:SetAttribute("Team", "")
	publish(p)
	if was then
		characters.Spawn(player)
		if bots then
			bots.Balance()
		end
	end
end

function MatchSystem.AddBot(identity)
	local p = newParticipant(identity, identity.Name, identity.UserId, true)
	p.Weapon = identity.Weapon
	return p
end

function MatchSystem.RemoveBot(identity)
	local p = participants[identity]
	if p then
		if p.Folder then
			p.Folder:Destroy()
		end
		if p.Model then
			byModel[p.Model] = nil
		end
		participants[identity] = nil
	end
end

-------------------------------------------------------------------------------
-- Счёт
-------------------------------------------------------------------------------
local function publishState()
	folder:SetAttribute("Phase", state.Phase)
	folder:SetAttribute("Mode", state.ModeId or "")
	folder:SetAttribute("ModeName", state.Mode and state.Mode.DisplayName or "")
	folder:SetAttribute("Map", state.Map and state.Map.Id or "")
	folder:SetAttribute("MapName", state.Map and state.Map.DisplayName or "")
	folder:SetAttribute("EndsAt", state.EndsAt)
	folder:SetAttribute("ScoreLimit", state.Mode and (state.Mode.ScoreLimit or 0) or 0)
	folder:SetAttribute("RedScore", state.Scores.Red)
	folder:SetAttribute("BlueScore", state.Scores.Blue)
	folder:SetAttribute("Teams", state.Mode ~= nil and state.Mode.Teams == true)
	if state.ModeId == "GunGame" then
		folder:SetAttribute("GunWeapons", table.concat(state.Mode.Weapons, ","))
		folder:SetAttribute("KillsPerWeapon", state.Mode.KillsPerWeapon)
	end
end

local function leader()
	local best = nil
	for _, p in pairs(participants) do
		if p.InMatch and (not best or p.Score > best.Score or (p.Score == best.Score and p.Deaths < best.Deaths)) then
			best = p
		end
	end
	return best
end

local finish -- объявлено ниже

local function checkWin()
	if state.Phase ~= "Running" then
		return
	end
	local m = state.Mode
	if m.Teams then
		for _, t in ipairs({ "Red", "Blue" }) do
			if state.Scores[t] >= m.ScoreLimit then
				finish("Score")
				return
			end
		end
	elseif m.ScoreLimit then
		local l = leader()
		if l and l.Score >= m.ScoreLimit then
			finish("Score")
		end
	end
end

local function onKill(kill)
	if state.Phase ~= "Running" then
		return
	end
	local victim = MatchSystem.ParticipantOfModel(kill.Victim)
	local killer = kill.Killer and participants[kill.Killer] or nil
	if victim and victim.InMatch then
		victim.Deaths = victim.Deaths + 1
		publish(victim)
	end
	for _, a in ipairs(kill.Assists or {}) do
		local ap = participants[a]
		if ap and ap.InMatch then
			ap.Assists = ap.Assists + 1
			publish(ap)
		end
	end
	if killer and killer.InMatch and killer ~= victim then
		killer.Kills = killer.Kills + 1
		if state.ModeId == "GunGame" then
			killer.GunKills = killer.GunKills + 1
			local list = state.Mode.Weapons
			if killer.GunLevel >= #list then
				killer.Score = killer.Score + 1
				publish(killer)
				MatchSystem.Kill:Fire(kill, killer, victim)
				finish("GunGame")
				return
			end
			if killer.GunKills >= state.Mode.KillsPerWeapon then
				killer.GunKills = 0
				killer.GunLevel = killer.GunLevel + 1
				local c = characterOf(killer)
				local hum = c and c:FindFirstChildOfClass("Humanoid")
				if c and hum and hum.Health > 0 then
					weapons.Equip(killer.Key, c, list[killer.GunLevel])
				end
				if isPlayer(killer.Key) and net then
					net.Fire(killer.Key, "MatchEvent", { Type = "GunLevel", Level = killer.GunLevel, Weapon = list[killer.GunLevel] })
				end
			end
			killer.Score = killer.GunLevel - 1
		else
			killer.Score = killer.Score + 1
		end
		if state.Mode.Teams and killer.Team ~= "" then
			state.Scores[killer.Team] = state.Scores[killer.Team] + 1
		end
		publish(killer)
	end
	publishState()
	MatchSystem.Kill:Fire(kill, killer, victim)
	checkWin()
end

-------------------------------------------------------------------------------
-- Фазы
-------------------------------------------------------------------------------
local function pickOptions()
	local pool = {}
	for _, r in ipairs(MatchConfig.Rotation) do
		if maps.Get(r.Map) and MatchConfig.Modes[r.Mode] then
			table.insert(pool, r)
		end
	end
	local options = {}
	while #pool > 0 and #options < MatchConfig.VoteOptions do
		local i = rng:NextInteger(1, #pool)
		local r = table.remove(pool, i)
		local dup = false
		for _, o in ipairs(options) do
			if o.Map == r.Map then
				dup = true
			end
		end
		if not dup or #pool == 0 then
			table.insert(options, { Map = r.Map, Mode = r.Mode })
		end
	end
	return options
end

local function publishVotes()
	local counts = {}
	for _, idx in pairs(state.Votes) do
		counts[idx] = (counts[idx] or 0) + 1
	end
	for i = 1, MatchConfig.VoteOptions do
		local o = state.Options[i]
		folder:SetAttribute("Option" .. i .. "Map", o and o.Map or "")
		folder:SetAttribute("Option" .. i .. "MapName", o and maps.Get(o.Map).DisplayName or "")
		folder:SetAttribute("Option" .. i .. "Mode", o and o.Mode or "")
		folder:SetAttribute("Option" .. i .. "ModeName", o and MatchConfig.Modes[o.Mode].DisplayName or "")
		folder:SetAttribute("Option" .. i .. "Votes", counts[i] or 0)
	end
end

function MatchSystem.Vote(player, index)
	if state.Phase ~= "Intermission" or not state.Options[index] then
		return false
	end
	state.Votes[player] = index
	publishVotes()
	return true
end

local function winningOption()
	local counts = {}
	for _, idx in pairs(state.Votes) do
		counts[idx] = (counts[idx] or 0) + 1
	end
	local best, bestCount = nil, -1
	for i, _ in ipairs(state.Options) do
		local c = (counts[i] or 0) + rng:NextNumber(0, 0.5)
		if c > bestCount then
			best, bestCount = i, c
		end
	end
	return state.Options[best or 1]
end

local function setPhase(phase, duration)
	state.Phase = phase
	state.EndsAt = duration and (now() + duration) or 0
	publishState()
end

-- Итоги матча: таблица для клиентов и наград
function MatchSystem.Results(reason)
	local list = {}
	for _, p in pairs(participants) do
		if p.InMatch then
			table.insert(list, { Name = p.Name, UserId = p.UserId, IsBot = p.IsBot, Team = p.Team, Kills = p.Kills, Deaths = p.Deaths, Assists = p.Assists, Score = p.Score })
		end
	end
	table.sort(list, function(a, b)
		if a.Score ~= b.Score then
			return a.Score > b.Score
		end
		if a.Kills ~= b.Kills then
			return a.Kills > b.Kills
		end
		return a.Deaths < b.Deaths
	end)
	local winnerTeam, winner = nil, nil
	if state.Mode and state.Mode.Teams then
		if state.Scores.Red ~= state.Scores.Blue then
			winnerTeam = state.Scores.Red > state.Scores.Blue and "Red" or "Blue"
		end
	else
		winner = list[1]
	end
	return {
		Mode = state.ModeId,
		ModeName = state.Mode and state.Mode.DisplayName or "",
		Map = state.Map and state.Map.Id or "",
		MapName = state.Map and state.Map.DisplayName or "",
		Reason = reason,
		WinnerTeam = winnerTeam,
		Winner = winner and winner.Name or nil,
		WinnerUserId = winner and winner.UserId or nil,
		RedScore = state.Scores.Red,
		BlueScore = state.Scores.Blue,
		Players = list,
		Duration = now() - state.StartedAt,
	}
end

finish = function(reason)
	if state.Phase ~= "Running" then
		return
	end
	local results = MatchSystem.Results(reason)
	setPhase("Results", MatchConfig.Results)
	state.Results = results
	log:Info("матч окончен (%s): %s, победитель %s", reason, results.ModeName, tostring(results.WinnerTeam or results.Winner))
	MatchSystem.MatchEnded:Fire(results)
	if net then
		net.FireAll("MatchEvent", { Type = "End", Results = results })
	end
end
MatchSystem.Finish = finish

-- Начать матч на карте mapId в режиме modeId (сразу, без голосования) — и для тестов
function MatchSystem.StartMatch(mapId, modeId)
	state.ModeId = modeId
	state.Mode = MatchConfig.Modes[modeId]
	state.Scores = { Red = 0, Blue = 0 }
	state.Map = maps.Load(mapId)
	state.Votes = {}
	setPhase("Starting", MatchConfig.Starting)
	-- все, кто ждал или был в прошлом матче, — в бой
	local entering = {}
	for _, p in pairs(participants) do
		if p.Queued or p.InMatch then
			table.insert(entering, p)
		end
	end
	for _, p in ipairs(entering) do
		p.InMatch = false
		p.Team = ""
	end
	for _, p in ipairs(entering) do
		MatchSystem.Enter(p)
	end
	if bots then
		bots.Balance()
	end
	MatchSystem.MatchStarted:Fire({ Map = state.Map, Mode = modeId })
	if net then
		net.FireAll("MatchEvent", { Type = "Countdown", Seconds = MatchConfig.Starting, ModeName = state.Mode.DisplayName, MapName = state.Map.DisplayName })
	end
end

function MatchSystem.BeginFight()
	state.StartedAt = now()
	setPhase("Running", state.Mode.TimeLimit)
	if net then
		net.FireAll("MatchEvent", { Type = "Start", ModeName = state.Mode.DisplayName })
	end
end

-- Вернуть всех в лобби и убрать карту
function MatchSystem.ReturnToLobby()
	for _, p in pairs(participants) do
		if p.InMatch then
			p.InMatch = false
			p.Queued = not p.IsBot -- игроки остаются в очереди на следующий матч
			p.Team = ""
			publish(p)
			if isPlayer(p.Key) then
				p.Key:SetAttribute("InMatch", false)
				p.Key:SetAttribute("Team", "")
				characters.Spawn(p.Key)
			end
		end
	end
	if bots then
		bots.Clear()
	end
	maps.Unload()
	state.Map = nil
	state.Mode = nil
	state.ModeId = nil
end

function MatchSystem.Phase()
	return state.Phase
end

function MatchSystem.State()
	return state
end

-- Chaos: удары с неба. Каждые Every секунд — Count взрывов, ближе к участникам; за Warning секунд — метка
local function chaosStrike()
	local cfg = state.Mode.Strike
	local targets = {}
	for _, p in pairs(participants) do
		local c = p.InMatch and characterOf(p)
		local root = c and c:FindFirstChild("HumanoidRootPart")
		if root then
			table.insert(targets, root.Position)
		end
	end
	if #targets == 0 then
		return
	end
	for _ = 1, cfg.Count do
		local base = targets[rng:NextInteger(1, #targets)]
		local at = base + Vector3.new(rng:NextNumber(-10, 10), 0, rng:NextNumber(-10, 10))
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = { workspace:FindFirstChild("ActiveMap") }
		local hit = workspace:Raycast(at + Vector3.new(0, 40, 0), Vector3.new(0, -80, 0), params)
		local ground = hit and hit.Position or at
		if net then
			net.FireAll("MatchEvent", { Type = "Strike", Position = ground, Radius = cfg.Radius, Delay = cfg.Warning })
		end
		task.delay(cfg.Warning, function()
			if state.Phase ~= "Running" then
				return
			end
			MatchSystem.Explode(ground, cfg.Radius, cfg.Damage)
		end)
	end
end

-- Взрыв: урон со спадом к краю, живых роняет, тела отбрасывает
function MatchSystem.Explode(center, radius, damage, attacker)
	local victims = {}
	for _, p in pairs(participants) do
		local c = p.InMatch and characterOf(p)
		local root = c and c:FindFirstChild("HumanoidRootPart")
		if root then
			local d = (root.Position - center).Magnitude
			if d < radius then
				table.insert(victims, { Model = c, D = d })
			end
		end
	end
	for _, v in ipairs(victims) do
		local k = 1 - v.D / radius
		combat.Damage(v.Model, damage * k * k, { Attacker = attacker, Cause = "Explosion", Origin = center, Position = center })
	end
	if ragdoll then
		ragdoll.Explode(center, radius, 70, { LethalRadius = 0 })
	end
end

local function runCycle()
	-- голосование
	state.Options = pickOptions()
	state.Votes = {}
	publishVotes()
	setPhase("Intermission", MatchConfig.Intermission)
	task.wait(MatchConfig.Intermission)
	if MatchSystem.Paused then
		return
	end
	local option = winningOption()
	local ok, err = pcall(MatchSystem.StartMatch, option.Map, option.Mode)
	if not ok then
		log:Error("матч не начался (%s / %s): %s", tostring(option.Map), tostring(option.Mode), tostring(err))
		pcall(MatchSystem.ReturnToLobby)
		task.wait(3)
		return
	end
	task.wait(MatchConfig.Starting)
	MatchSystem.BeginFight()
	local nextStrike = now() + (state.Mode.Strike and state.Mode.Strike.Every or math.huge)
	while state.Phase == "Running" do
		task.wait(0.25)
		if now() >= state.EndsAt then
			finish("Time")
		elseif state.Mode.Strike and now() >= nextStrike then
			nextStrike = now() + state.Mode.Strike.Every
			local okStrike, why = pcall(chaosStrike)
			if not okStrike then
				log:Warn("удар не прошёл: %s", tostring(why))
			end
		end
	end
	task.wait(MatchConfig.Results)
	local okBack, why = pcall(MatchSystem.ReturnToLobby)
	if not okBack then
		log:Error("возврат в лобби: %s", tostring(why))
	end
end

local function loop()
	while true do
		if MatchSystem.Paused then
			task.wait(0.5)
		else
			runCycle()
		end
	end
end

-------------------------------------------------------------------------------
function MatchSystem.Init(context)
	net = context.Get("NetService")
	maps = context.Get("MapSystem")
	characters = context.Get("CharacterSystem")
	weapons = context.Get("WeaponSystem")
	combat = context.Get("CombatSystem")
	ragdoll = context.Get("RagdollSystem")
	folder = ReplicatedStorage:FindFirstChild("Match")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Match"
		folder.Parent = ReplicatedStorage
	end
	partsFolder = folder:FindFirstChild("Participants") or Instance.new("Folder")
	partsFolder.Name = "Participants"
	partsFolder.Parent = folder
end

function MatchSystem.Start(context)
	bots = context.Get("BotSystem")
	lobby = context.Get("LobbySystem")
	progression = context.Get("ProgressionSystem")
	characters.SetSpawnResolver(spawnResolver)
	weapons.SetLoadoutResolver(MatchSystem.WeaponFor)
	combat.SetRules({ CanDamage = canDamage })
	combat.Killed:Connect(onKill)
	net.Connect("Play", function(player)
		MatchSystem.Join(player)
	end)
	net.Connect("LeaveMatch", function(player)
		MatchSystem.Leave(player)
	end)
	net.Connect("Vote", function(player, index)
		MatchSystem.Vote(player, index)
	end)
	Players.PlayerRemoving:Connect(function(player)
		local p = participants[player]
		if p then
			if p.Folder then
				p.Folder:Destroy()
			end
			participants[player] = nil
			state.Votes[player] = nil
			if bots then
				task.defer(bots.Balance)
			end
		end
	end)
	-- новый игрок — в списке участников (в лобби), чтобы его видели в таблице
	local function added(player)
		if not participants[player] then
			newParticipant(player, player.DisplayName ~= "" and player.DisplayName or player.Name, player.UserId, false)
		end
		player:SetAttribute("InMatch", false)
	end
	Players.PlayerAdded:Connect(added)
	for _, player in ipairs(Players:GetPlayers()) do
		added(player)
	end
	task.spawn(loop)
end

return MatchSystem
