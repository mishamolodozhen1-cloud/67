-- MonsterAI: «Покупатель». Выглядит как обычный покупатель, но никогда не ходит у вас на глазах.
--   00:00–02:00  его нет (только мелкие странности)
--   02:00–04:00  «видения»: стоит в необычных местах и смотрит; исчезает, когда от него отворачиваются;
--                может появиться на камерах наблюдения
--   04:00–05:00  он в магазине: пока на него никто не смотрит, переставляется ближе к игроку
--   при отключении света и после 05:00 — охота: подкрадывается за спину; если догнал — игрок теряет
--   сознание, приходит в себя в комнате персонала, а часы смены уходят вперёд.
-- «Смотрит ли кто-то» сообщают клиенты: камера игрока видит голову монстра и её ничто не загораживает.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Util = require(Shared:WaitForChild("Util"))

local MonsterAI = {}

local map, S, NpcFactory
local npc
local rng = Random.new()
local present = false
local held = false -- управляется сценой кассы №0
local banished = false
local vanishPending = false
local seenBy = {} -- player -> os.clock() последнего «вижу»
local viewing = {} -- player -> номер камеры (0 — не смотрит)
local observedTime = 0
local lastObserved = 0
local nextAppear = 0
local nextMove = 0
local caughtCooldown = {}
local lastCatch = 0
local behindTarget -- игрок, за спиной которого стоит монстр

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function updateFilter()
	local list = { map.Dynamic }
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	rayParams.FilterDescendantsInstances = list
end

-- Прямая видимость между точками (стекло и прозрачные детали не мешают)
local function clearLine(a, b)
	local origin = a
	for _ = 1, 5 do
		local dir = b - origin
		if dir.Magnitude < 0.1 then
			return true
		end
		local hit = workspace:Raycast(origin, dir, rayParams)
		if not hit then
			return true
		end
		local inst = hit.Instance
		if inst.Transparency > 0.4 or inst.Material == Enum.Material.Glass then
			origin = hit.Position + dir.Unit * 0.05
		else
			return false
		end
	end
	return false
end

local function heads()
	local list = {}
	for _, p in ipairs(Players:GetPlayers()) do
		local ch = p.Character
		local head = ch and ch:FindFirstChild("Head")
		local root = ch and ch:FindFirstChild("HumanoidRootPart")
		if head and root then
			table.insert(list, { Player = p, Head = head, Root = root })
		end
	end
	return list
end

-- Может ли кто-то увидеть точку пола pos прямо сейчас (с учётом направления взгляда и камер)
local function canBeSeen(pos)
	local top = pos + Vector3.new(0, 4.6, 0)
	for _, h in ipairs(heads()) do
		local to = top - h.Head.Position
		if to.Magnitude < 120 then
			local look = h.Root.CFrame.LookVector
			local flatTo = Vector3.new(to.X, 0, to.Z)
			local inFov = flatTo.Magnitude < 3 or (flatTo.Unit:Dot(Vector3.new(look.X, 0, look.Z).Unit) > math.cos(math.rad(62)))
			if inFov and clearLine(h.Head.Position, top) then
				return true
			end
		end
		local cam = viewing[h.Player]
		if cam and cam > 0 and map.Cameras[cam] then
			local cpos = map.Cameras[cam].View.Position
			local dir = (top - cpos)
			local camLook = map.Cameras[cam].View.CFrame.LookVector
			if dir.Magnitude < 120 and dir.Unit:Dot(camLook) > math.cos(math.rad(42)) and clearLine(cpos, top) then
				return true
			end
		end
	end
	return false
end

local function observed()
	local now = os.clock()
	for p, t in pairs(seenBy) do
		if p.Parent and now - t < 1.2 then
			return true, p
		end
	end
	return false
end

local function inStore(pos)
	local room = S.Store.RoomAt(pos)
	return room ~= nil
end

-- Игроки, за которыми можно охотиться (смена идёт, игрок в здании или во дворе)
local function targets()
	local list = {}
	for _, h in ipairs(heads()) do
		if inStore(h.Root.Position) then
			table.insert(list, h)
		end
	end
	return list
end

local function place(cf)
	if not npc then
		return
	end
	NpcFactory.PlaceAt(npc, cf)
	present = true
	npc.Model:SetAttribute("Present", true)
	observedTime = 0
	vanishPending = false
end

local function hide()
	if not npc then
		return
	end
	npc.Model:PivotTo(CFrame.new(0, -500, 0))
	present = false
	behindTarget = nil
	npc.Model:SetAttribute("Present", false)
end

local function faceTo(cfPos, target)
	return CFrame.lookAt(cfPos, Vector3.new(target.X, cfPos.Y, target.Z))
end

local function monsterPos()
	return npc.Root.Position - Vector3.new(0, npc.RootHeight, 0)
end

-------------------------------------------------------------------------------
-- Выбор места
-------------------------------------------------------------------------------
-- Видение: необычное место, которое игрок не видит прямо сейчас, но увидит, если обернётся/зайдёт
local function apparitionSpot()
	local list = targets()
	if #list == 0 then
		return nil
	end
	local candidates = {}
	for _, cf in ipairs(map.MonsterSpots) do
		local pos = cf.Position
		local near = false
		for _, h in ipairs(list) do
			local d = (h.Root.Position - pos).Magnitude
			if d > 14 and d < 75 then
				near = true
			end
		end
		if near and not canBeSeen(pos) then
			table.insert(candidates, cf)
		end
	end
	local cf = Util.pick(candidates, rng)
	if not cf then
		return nil
	end
	-- смотрит на ближайшего игрока
	local best, bestD = nil, math.huge
	for _, h in ipairs(list) do
		local d = (h.Root.Position - cf.Position).Magnitude
		if d < bestD then
			best, bestD = h, d
		end
	end
	return faceTo(cf.Position, best.Root.Position)
end

-- Ближе к цели, но там, где сейчас никто не видит
local function approachSpot(target, minD, step)
	local tpos = target.Root.Position
	local cur = present and (monsterPos() - tpos).Magnitude or 60
	local want = math.max(minD, cur - step)
	local best, bestScore = nil, math.huge
	for _, node in ipairs(map.MonsterNodes) do
		local d = (node - tpos).Magnitude
		if d >= minD and d <= math.max(cur, 45) and S.Store.RoomAt(node) then
			local score = math.abs(d - want) + rng:NextNumber(0, 4)
			if score < bestScore and not canBeSeen(node) then
				best, bestScore = node, score
			end
		end
	end
	if best then
		return faceTo(best, tpos)
	end
	return nil
end

-- За спиной игрока (если там нет стены)
local function behindSpot(target, dist)
	local root = target.Root
	local back = root.CFrame * CFrame.new(0, 0, dist)
	local pos = Vector3.new(back.Position.X, 0, back.Position.Z)
	if clearLine(root.Position, pos + Vector3.new(0, 3, 0)) and S.Store.RoomAt(pos) then
		return faceTo(pos, root.Position)
	end
	return nil
end

-- Камера, которую сейчас смотрит игрок: поставить монстра в кадр (видно только на мониторе)
local function cameraSpot(index)
	local cam = map.Cameras[index]
	if not cam then
		return nil
	end
	local cpos = cam.View.Position
	local look = cam.View.CFrame.LookVector
	local candidates = {}
	local function try(pos)
		local top = pos + Vector3.new(0, 4.6, 0)
		local dir = top - cpos
		if dir.Magnitude > 12 and dir.Magnitude < 70 and dir.Unit:Dot(look) > math.cos(math.rad(25)) and clearLine(cpos, top) then
			-- игроки вживую его видеть не должны
			local seenLive = false
			for _, h in ipairs(heads()) do
				if clearLine(h.Head.Position, top) and (h.Head.Position - top).Magnitude < 120 then
					seenLive = true
				end
			end
			if not seenLive then
				table.insert(candidates, pos)
			end
		end
	end
	for _, node in ipairs(map.MonsterNodes) do
		try(node)
	end
	for _, cf in ipairs(map.MonsterSpots) do
		try(cf.Position)
	end
	local pos = Util.pick(candidates, rng)
	return pos and faceTo(pos, cpos) or nil
end

-------------------------------------------------------------------------------
-- Поимка
-------------------------------------------------------------------------------
local function catch(player)
	local now = os.clock()
	if (caughtCooldown[player] and now - caughtCooldown[player] < 40) or now - lastCatch < 12 then
		return
	end
	caughtCooldown[player] = now
	lastCatch = now
	S.Net.Effect(player, "Caught")
	S.Net.Sound("DarkHit", nil, 0.9, player)
	S.Store.ClearCarry(player, false)
	nextAppear = now + rng:NextNumber(25, 40)
	task.delay(1.4, function()
		hide()
		local ch = player.Character
		if ch then
			ch:PivotTo(CFrame.new(map.Points.CaughtWake + Vector3.new(rng:NextNumber(-2, 2), 0, 0)))
		end
		S.Shift.AddMinutes(Config.CaughtPenaltyMinutes)
		S.Net.Notify(nil, player.DisplayName .. " нашли без сознания в комнате персонала. Часы ушли на " .. Config.CaughtPenaltyMinutes .. " минут вперёд", "anomaly")
	end)
end

-------------------------------------------------------------------------------
local function mode()
	local minutes = S.Net.Get("Minutes") or 0
	local hour = math.floor(minutes / 60)
	if hour < 2 then
		return nil
	end
	if (hour >= 4 and not S.Power.IsOn()) or hour >= 5 then
		return "Hunt"
	elseif hour >= 4 then
		return "Stalk"
	end
	return "Apparition"
end

local function step(dt)
	if not npc or banished or held then
		return
	end
	if S.Net.Get("Phase") ~= "Shift" then
		if present then
			hide()
		end
		return
	end
	updateFilter()
	local m = mode()
	if not m then
		if present then
			hide()
		end
		return
	end
	local now = os.clock()
	local seen, watcher = observed()

	if present then
		if seen then
			lastObserved = now
			observedTime = observedTime + dt
			-- смотрит на того, кто смотрит на него
			local wroot = Util.rootOf(watcher)
			if wroot and not behindTarget then
				NpcFactory.PlaceAt(npc, faceTo(monsterPos(), wroot.Position))
			end
			if behindTarget then
				-- обернулись вовремя: исчезает, как только отвернутся
				behindTarget = nil
				vanishPending = true
			end
			local _, nearD = nil, math.huge
			for _, h in ipairs(heads()) do
				nearD = math.min(nearD, (h.Root.Position - monsterPos()).Magnitude)
			end
			if m == "Apparition" and (observedTime > 2.5 or nearD < 14) then
				vanishPending = true
			elseif m ~= "Apparition" and nearD < 7 then
				vanishPending = true
			end
		else
			if vanishPending then
				hide()
				vanishPending = false
				nextAppear = now + (m == "Apparition" and rng:NextNumber(25, 55) or rng:NextNumber(6, 14))
				return
			end
			if m ~= "Apparition" and now >= nextMove and now - lastObserved > 1.5 then
				local list = targets()
				-- охотится на того, кто дальше всех от остальных
				local target, bestIso = nil, -1
				for _, h in ipairs(list) do
					local iso = math.huge
					for _, o in ipairs(list) do
						if o ~= h then
							iso = math.min(iso, (o.Root.Position - h.Root.Position).Magnitude)
						end
					end
					if iso > bestIso then
						target, bestIso = h, iso
					end
				end
				if target then
					local d = (target.Root.Position - monsterPos()).Magnitude
					if m == "Hunt" and behindTarget == target.Player and d < 8 then
						catch(target.Player)
						return
					end
					local cf
					if m == "Hunt" and d < 16 then
						cf = behindSpot(target, 6)
						if cf then
							behindTarget = target.Player
						end
					end
					if not cf then
						cf = approachSpot(target, m == "Hunt" and 8 or 16, m == "Hunt" and 12 or 8)
					end
					if cf then
						place(cf)
						if (cf.Position - target.Root.Position).Magnitude < 24 then
							S.Net.Sound(rng:NextNumber() < 0.5 and "Steps" or "StepsFar", cf.Position + Vector3.new(0, 2, 0), 0.6)
						end
					end
				end
				nextMove = now + (m == "Hunt" and rng:NextNumber(3.2, 4.8) or rng:NextNumber(8, 13))
			end
		end
	else
		if now >= nextAppear then
			local cf
			if m == "Apparition" then
				cf = apparitionSpot()
			else
				local list = targets()
				local target = Util.pick(list, rng)
				cf = target and approachSpot(target, 20, 0)
			end
			if cf then
				place(cf)
				nextMove = now + rng:NextNumber(6, 10)
			else
				nextAppear = now + 4
			end
		end
	end
end

-------------------------------------------------------------------------------
function MonsterAI.Init(m, services, npcFactory)
	map, S, NpcFactory = m, services, npcFactory
	npc = NpcFactory.Monster(map.Dynamic)
	if npc then
		-- копия для клиентских «видений» (видит только один игрок)
		local template = npc.Model:Clone()
		template.Name = "MonsterTemplate"
		template:PivotTo(CFrame.new(0, -500, 0))
		template.Parent = ReplicatedStorage
	end
	Players.PlayerRemoving:Connect(function(p)
		seenBy[p] = nil
		viewing[p] = nil
		caughtCooldown[p] = nil
	end)
end

-- Клиент: «вижу монстра» / «не вижу»
function MonsterAI.ReportSeen(player, isSeen)
	if isSeen then
		seenBy[player] = os.clock()
	else
		seenBy[player] = nil
	end
end

-- Клиент открыл камеру index (0 — закрыл камеры)
function MonsterAI.ReportCamera(player, index)
	if type(index) ~= "number" then
		return
	end
	viewing[player] = index
	if index > 0 and not present and not held and not banished and mode() == "Apparition" and rng:NextNumber() < 0.3 then
		local cf = cameraSpot(index)
		if cf then
			place(cf)
			vanishPending = true -- исчезнет, как только камеру переключат
		end
	end
end

-- Сцена кассы №0: поставить и не трогать
function MonsterAI.Hold(cf)
	held = true
	if npc then
		place(cf)
	end
end

function MonsterAI.Release()
	held = false
	hide()
end

-- После секретной концовки он больше не появляется
function MonsterAI.Banish()
	banished = true
	held = false
	hide()
end

function MonsterAI.IsPresent()
	return present
end

function MonsterAI.Model()
	return npc and npc.Model
end

function MonsterAI.Start()
	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(0.25)
			local now = os.clock()
			local ok, err = pcall(step, now - last)
			if not ok then
				warn("[Покупатель] " .. tostring(err))
			end
			last = now
		end
	end)
end

function MonsterAI.Reset()
	held = false
	banished = false
	vanishPending = false
	behindTarget = nil
	seenBy = {}
	nextAppear = os.clock() + 10
	if npc then
		hide()
	end
end

return MonsterAI
