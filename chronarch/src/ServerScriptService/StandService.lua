-- Серверная логика стенда: пробуждение стрелой, призыв, барраж, остановка времени.
-- Урон и заморозка считаются только на сервере; клиенты получают события для эффектов.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local StandBuilder = require(script.Parent:WaitForChild("StandBuilder"))

local StandService = {}

local actionRemote
local fxRemote
local standsFolder
local dummiesFolder

local states = {}
local timeStop = nil -- активная остановка времени: {owner, frozen, frozenSet, pending, active}

local function now()
	return workspace:GetServerTimeNow()
end

local function getState(player)
	local s = states[player]
	if not s then
		s = {
			hasStand = false,
			model = nil,
			barraging = false,
			busy = false,
			barrageReadyAt = 0,
			timeStopReadyAt = 0,
			lastSummon = 0,
		}
		states[player] = s
	end
	return s
end

-- Возвращает персонажа, Humanoid и HumanoidRootPart живого игрока.
local function getRoot(player)
	local char = player.Character
	if not char then
		return nil
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if hum and hrp and hum.Health > 0 then
		return char, hum, hrp
	end
	return nil
end

local function isFrozen(char)
	return char ~= nil and char:GetAttribute("Frozen") == true
end

local function knockback(hrp, velocity, duration)
	if hrp.Anchored then
		return
	end
	local att = Instance.new("Attachment")
	att.Name = "KnockbackAttachment"
	att.Parent = hrp
	local lv = Instance.new("LinearVelocity")
	lv.Name = "Knockback"
	lv.Attachment0 = att
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.MaxForce = 1e7
	lv.VectorVelocity = velocity
	lv.Parent = hrp
	Debris:AddItem(lv, duration)
	Debris:AddItem(att, duration)
end

-------------------------------------------------------------------------------
-- Призыв / отзыв стенда
-------------------------------------------------------------------------------
local function despawnStand(player)
	local s = getState(player)
	local model = s.model
	s.model = nil
	s.barraging = false
	player:SetAttribute("StandSummoned", false)
	if model then
		model:SetAttribute("State", "vanish")
		fxRemote:FireAllClients("Desummon", model)
		Debris:AddItem(model, 0.4)
	end
end

local function spawnStand(player)
	local s = getState(player)
	local char, _, hrp = getRoot(player)
	if not char then
		return
	end
	if s.model then
		s.model:Destroy()
		s.model = nil
	end

	local model, root = StandBuilder.Build()
	model.Name = "Stand_" .. player.UserId
	model:SetAttribute("Owner", player.UserId)
	model:SetAttribute("State", "idle")

	local offset = Config.StandOffsets.idle
	model:PivotTo(hrp.CFrame * offset)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = false
		end
	end
	local weld = Instance.new("Weld")
	weld.Name = "Anchor"
	weld.Part0 = hrp
	weld.Part1 = root
	weld.C0 = offset
	weld.Parent = root

	model.Parent = standsFolder
	s.model = model
	player:SetAttribute("StandSummoned", true)
	fxRemote:FireAllClients("Summon", model, hrp.Position)
end

-------------------------------------------------------------------------------
-- Попадания
-------------------------------------------------------------------------------
local function applyHit(hum, thrp, damage, dir, isFinisher)
	local tchar = hum.Parent
	if timeStop and timeStop.active and timeStop.frozenSet[tchar] then
		-- Цель застыла во времени: копим урон и импульс до возобновления.
		local p = timeStop.pending[hum]
		if not p then
			p = { damage = 0, dir = Vector3.zero, hrp = thrp }
			timeStop.pending[hum] = p
		end
		p.damage = p.damage + damage
		p.dir = p.dir + dir * (isFinisher and 3 or 0.25)
		return true
	end
	hum:TakeDamage(damage)
	if isFinisher then
		knockback(thrp, dir * Config.Barrage.FinisherKnockback + Vector3.new(0, 24, 0), 0.25)
	else
		knockback(thrp, dir * 7 + Vector3.new(0, 1.5, 0), 0.08)
	end
	return false
end

local function hitTargets(player, hrp, damage, isFinisher)
	local boxCF = hrp.CFrame * CFrame.new(0, 0.5, -Config.Barrage.BoxForward)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character, standsFolder }
	local parts = workspace:GetPartBoundsInBox(boxCF, Config.Barrage.BoxSize, params)

	local seen = {}
	local hits = {}
	local dir = hrp.CFrame.LookVector
	for _, part in ipairs(parts) do
		local model = part:FindFirstAncestorOfClass("Model")
		local hum = model and model:FindFirstChildOfClass("Humanoid")
		if hum and not seen[hum] and hum.Health > 0 then
			seen[hum] = true
			local thrp = model:FindFirstChild("HumanoidRootPart")
			if thrp then
				local delayed = applyHit(hum, thrp, damage, dir, isFinisher)
				local toAttacker = hrp.Position - thrp.Position
				local offset = Vector3.zero
				if toAttacker.Magnitude > 0.1 then
					offset = toAttacker.Unit * 0.9
				end
				local jitter = Vector3.new(math.random() - 0.5, math.random() * 1.6 - 0.4, math.random() - 0.5)
				table.insert(hits, { thrp.Position + offset + jitter, damage, delayed })
			end
		end
	end
	if #hits > 0 then
		fxRemote:FireAllClients("Hit", hits, isFinisher)
	end
end

-------------------------------------------------------------------------------
-- Барраж
-------------------------------------------------------------------------------
local function startBarrage(player)
	local s = getState(player)
	if s.barraging or s.busy or not s.model then
		return
	end
	if now() < s.barrageReadyAt then
		return
	end
	local char = getRoot(player)
	if not char or isFrozen(char) then
		return
	end

	s.barraging = true
	s.busy = true
	local model = s.model
	model:SetAttribute("State", "barrage")
	player:SetAttribute("Barraging", true)

	task.spawn(function()
		local started = os.clock()
		while s.barraging and s.model == model and os.clock() - started < Config.Barrage.MaxDuration do
			local c, _, r = getRoot(player)
			if not c or isFrozen(c) then
				break
			end
			hitTargets(player, r, Config.Barrage.Damage, false)
			task.wait(Config.Barrage.TickInterval)
		end
		s.barraging = false
		player:SetAttribute("Barraging", false)

		if s.model == model and model.Parent then
			-- Завершающий мощный удар
			model:SetAttribute("State", "finisher")
			fxRemote:FireAllClients("Finisher", model)
			task.wait(Config.Barrage.FinisherDelay)
			local c, _, r = getRoot(player)
			if c and not isFrozen(c) then
				hitTargets(player, r, Config.Barrage.FinisherDamage, true)
			end
			task.wait(0.35)
			if s.model == model and model:GetAttribute("State") == "finisher" then
				model:SetAttribute("State", "idle")
			end
		end

		s.barrageReadyAt = now() + Config.Barrage.Cooldown
		player:SetAttribute("BarrageReadyAt", s.barrageReadyAt)
		s.busy = false
	end)
end

-------------------------------------------------------------------------------
-- Остановка времени
-------------------------------------------------------------------------------
local function freezeCharacter(ts, char)
	if ts.frozenSet[char] then
		return
	end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end
	ts.frozenSet[char] = true
	table.insert(ts.frozen, { char = char, hrp = hrp, wasAnchored = hrp.Anchored })
	hrp.Anchored = true
	char:SetAttribute("Frozen", true)
end

local function resumeTime(ts)
	if timeStop ~= ts then
		return
	end
	timeStop = nil

	for _, f in ipairs(ts.frozen) do
		if f.hrp.Parent then
			f.hrp.Anchored = f.wasAnchored
			if not f.wasAnchored then
				local owner = Players:GetPlayerFromCharacter(f.char)
				pcall(function()
					f.hrp:SetNetworkOwner(owner)
				end)
			end
		end
		if f.char.Parent then
			f.char:SetAttribute("Frozen", nil)
		end
	end

	workspace:SetAttribute("TimeStopped", nil)
	workspace:SetAttribute("TimeStopper", nil)
	workspace:SetAttribute("TimeStopEndsAt", nil)

	-- Весь накопленный урон прилетает разом.
	local hits = {}
	for hum, p in pairs(ts.pending) do
		if hum.Parent and hum.Health > 0 then
			hum:TakeDamage(p.damage)
			if p.hrp.Parent then
				local dir = Vector3.zero
				if p.dir.Magnitude > 0.01 then
					dir = p.dir.Unit
				end
				local power = math.clamp(40 + p.damage * 1.2, 40, 140)
				knockback(p.hrp, dir * power + Vector3.new(0, 30, 0), 0.3)
				table.insert(hits, { p.hrp.Position, p.damage, false })
			end
		end
	end
	fxRemote:FireAllClients("TimeResume", hits)
end

local function startTimeStop(player)
	local s = getState(player)
	if timeStop or s.busy or not s.model then
		return
	end
	if now() < s.timeStopReadyAt then
		return
	end
	local char, _, hrp = getRoot(player)
	if not char or isFrozen(char) then
		return
	end

	s.busy = true
	local model = s.model
	model:SetAttribute("State", "timestop")
	local ts = { owner = player, frozen = {}, frozenSet = {}, pending = {}, active = false }
	timeStop = ts
	fxRemote:FireAllClients("TimeStopStart", player.UserId, hrp.Position, Config.TimeStop.Windup)

	task.delay(Config.TimeStop.Windup, function()
		local c2, _, r2 = getRoot(player)
		if timeStop ~= ts or not c2 then
			-- Владелец погиб во время замаха: отменяем.
			if timeStop == ts then
				timeStop = nil
			end
			s.busy = false
			fxRemote:FireAllClients("TimeResume", {})
			return
		end

		ts.active = true
		for _, other in ipairs(Players:GetPlayers()) do
			if other ~= player and other.Character then
				freezeCharacter(ts, other.Character)
			end
		end
		for _, dummy in ipairs(dummiesFolder:GetChildren()) do
			freezeCharacter(ts, dummy)
		end

		local endsAt = now() + Config.TimeStop.Duration
		workspace:SetAttribute("TimeStopper", player.UserId)
		workspace:SetAttribute("TimeStopEndsAt", endsAt)
		workspace:SetAttribute("TimeStopped", true)
		fxRemote:FireAllClients("TimeFrozen", player.UserId, r2.Position, Config.TimeStop.Duration)

		s.busy = false -- во время остановки можно бить барражем
		task.delay(0.7, function()
			if s.model == model and model:GetAttribute("State") == "timestop" then
				model:SetAttribute("State", "idle")
			end
		end)

		local deadline = os.clock() + Config.TimeStop.Duration
		while os.clock() < deadline and timeStop == ts do
			if player.Parent == nil or not getRoot(player) then
				break
			end
			task.wait(0.1)
		end
		resumeTime(ts)
		s.timeStopReadyAt = now() + Config.TimeStop.Cooldown
		player:SetAttribute("TimeStopReadyAt", s.timeStopReadyAt)
	end)
end

-------------------------------------------------------------------------------
-- Пробуждение стрелой
-------------------------------------------------------------------------------
local function onArrowTaken(player)
	local s = getState(player)
	if s.hasStand then
		return
	end
	local char = getRoot(player)
	if not char or isFrozen(char) then
		return
	end
	s.hasStand = true
	s.busy = true
	player:SetAttribute("HasStand", true)
	fxRemote:FireAllClients("Awaken", player.UserId)
	task.delay(1.6, function()
		s.busy = false
		if getRoot(player) and not s.model then
			spawnStand(player)
		end
	end)
end

local function onAction(player, action)
	if type(action) ~= "string" then
		return
	end
	local s = getState(player)
	if not s.hasStand then
		return
	end
	if action == "Summon" then
		if s.busy or s.barraging then
			return
		end
		local char = getRoot(player)
		if not char or isFrozen(char) then
			return
		end
		if os.clock() - s.lastSummon < 0.5 then
			return
		end
		s.lastSummon = os.clock()
		if s.model then
			despawnStand(player)
		else
			spawnStand(player)
		end
	elseif action == "BarrageStart" then
		if not s.model and not s.busy then
			spawnStand(player)
		end
		startBarrage(player)
	elseif action == "BarrageStop" then
		s.barraging = false
	elseif action == "TimeStop" then
		if not s.model and not s.busy then
			spawnStand(player)
		end
		startTimeStop(player)
	end
end

function StandService.Start(arrowPrompt, dummies)
	dummiesFolder = dummies
	standsFolder = workspace:WaitForChild("Stands")

	local remotes = Instance.new("Folder")
	remotes.Name = "Remotes"
	actionRemote = Instance.new("RemoteEvent")
	actionRemote.Name = "StandAction"
	actionRemote.Parent = remotes
	fxRemote = Instance.new("RemoteEvent")
	fxRemote.Name = "StandFX"
	fxRemote.Parent = remotes
	remotes.Parent = ReplicatedStorage

	actionRemote.OnServerEvent:Connect(onAction)
	arrowPrompt.Triggered:Connect(onArrowTaken)

	local function onPlayer(player)
		getState(player)
		player:SetAttribute("HasStand", false)
		player:SetAttribute("StandSummoned", false)
		player.CharacterRemoving:Connect(function()
			local s = getState(player)
			if s.model then
				s.model:Destroy()
				s.model = nil
			end
			s.barraging = false
			player:SetAttribute("StandSummoned", false)
		end)
		player.CharacterAdded:Connect(function(char)
			-- Персонаж, появившийся во время остановки времени, тоже застывает.
			if timeStop and timeStop.active and timeStop.owner ~= player then
				char:WaitForChild("HumanoidRootPart", 5)
				if timeStop and timeStop.active then
					freezeCharacter(timeStop, char)
				end
			end
		end)
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, p in ipairs(Players:GetPlayers()) do
		onPlayer(p)
	end
	Players.PlayerRemoving:Connect(function(player)
		local s = states[player]
		if s and s.model then
			s.model:Destroy()
		end
		states[player] = nil
	end)
end

return StandService
