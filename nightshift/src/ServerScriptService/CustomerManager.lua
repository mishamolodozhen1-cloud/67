-- CustomerManager: обычные и «странные» покупатели.
-- Обычный покупатель: входит, ходит по рядам и берёт товар, встаёт в очередь на кассу, ждёт, платит и уходит.
-- Странные (появляются после 01:00 по событиям): «Наблюдатель» стоит и смотрит на игрока,
-- «У стены» смотрит в стену, «Задом наперёд» ходит спиной вперёд, «Постоянный» каждую ночь берёт одно и то же.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Products = require(Shared:WaitForChild("Products"))
local Util = require(Shared:WaitForChild("Util"))

local CustomerManager = {}

local map, S, NpcFactory, Navigation
local customers = {}
local rng = Random.new()
local lastSpawn = 0

local GREET = { "Добрый вечер.", "Здравствуйте.", "Ночь сегодня тихая…", "О, открыто. Отлично." }
local IMPATIENT = { "Есть кто на кассе?", "Долго ещё?", "Кассир, ау?", "Мне бы оплатить…" }
local THANKS = { "Спасибо!", "Спасибо, хорошей смены.", "Благодарю.", "До свидания." }
local ANGRY = { "Ну и обслуживание…", "Ладно, пойду в другой магазин.", "Безобразие." }
local EMPTY = { "Хм, пусто…", "А где товар?" }

function CustomerManager.All()
	return customers
end

function CustomerManager.Say(npc, text)
	NpcFactory.Say(npc, text, 3.5)
end

local function say(npc, list)
	NpcFactory.Say(npc, Util.pick(list, rng), 3.5)
end

local function remove(npc)
	for i, c in ipairs(customers) do
		if c == npc then
			table.remove(customers, i)
			break
		end
	end
	if npc.Lane then
		S.Checkout.Leave(npc)
	end
	NpcFactory.Destroy(npc)
end

local function goTo(npc, target)
	if not npc.Alive then
		return false
	end
	if npc.Backwards then
		npc.Humanoid.AutoRotate = false
		for _, p in ipairs(Navigation.Route(npc.Root.Position, target)) do
			local pos = npc.Root.Position
			NpcFactory.Face(npc, pos + (pos - Vector3.new(p.X, pos.Y, p.Z)))
			NpcFactory.WalkTo(npc, p, 16)
		end
		return npc.Alive
	end
	return NpcFactory.Follow(npc, Navigation.Route(npc.Root.Position, target))
end

local function nearestPlayer(pos, maxDist)
	local best, bestD = nil, maxDist or math.huge
	for _, p in ipairs(Players:GetPlayers()) do
		local root = Util.rootOf(p)
		if root then
			local d = (root.Position - pos).Magnitude
			if d < bestD then
				best, bestD = root, d
			end
		end
	end
	return best, bestD
end

local function enter(npc)
	return NpcFactory.Follow(npc, { map.Points.EntranceOutside, map.Points.EntranceInside })
end

local function leave(npc, lane)
	if not npc.Alive then
		return
	end
	if lane then
		NpcFactory.WalkTo(npc, lane.ExitSpot, 10)
	end
	goTo(npc, map.Points.EntranceInside)
	NpcFactory.WalkTo(npc, map.Points.EntranceOutside, 10)
	NpcFactory.WalkTo(npc, npc.Home, 25)
	remove(npc)
end

-- Походить по рядам и набрать товар
local function shop(npc, stops)
	for _ = 1, stops do
		if not npc.Alive then
			return
		end
		local f = map.Facings[rng:NextInteger(1, #map.Facings)]
		local z = math.clamp(f.ZCenter + rng:NextNumber(-3, 3), 1.5, 18.5)
		goTo(npc, Vector3.new(f.Aisle, 0, z))
		if not npc.Alive then
			return
		end
		NpcFactory.Face(npc, Vector3.new(f.Front.Position.X, 0, z))
		task.wait(rng:NextNumber(2, 4.5))
		if f.Empty then
			say(npc, EMPTY)
		else
			for _ = 1, rng:NextInteger(1, 2) do
				table.insert(npc.Items, Products.Random(f.Category, rng))
			end
		end
	end
	if npc.Alive and rng:NextNumber() < 0.45 then
		local fr = map.Fridges[rng:NextInteger(1, #map.Fridges)]
		goTo(npc, fr.Front)
		NpcFactory.Face(npc, fr.Front + Vector3.new(0, 0, -5))
		task.wait(rng:NextNumber(2, 4))
		table.insert(npc.Items, Products.Random("Chilled", rng))
	end
	if #npc.Items == 0 then
		table.insert(npc.Items, Products.Random(nil, rng))
	end
	while #npc.Items > 6 do
		table.remove(npc.Items)
	end
end

-- Очередь и оплата. Возвращает true, если покупатель оплатил
local function queueAndPay(npc)
	local lane = S.Checkout.ChooseLane()
	if not lane then
		return false
	end
	S.Checkout.Join(lane, npc)
	goTo(npc, lane.QueueSpots[5])
	local at = 5
	local started = os.clock()
	while npc.Alive do
		local idx = S.Checkout.Position(npc)
		if not idx then
			return false
		end
		idx = math.min(idx, 5)
		if idx < at then
			at = at - 1
			NpcFactory.WalkTo(npc, lane.QueueSpots[at], 8)
		elseif idx == 1 and at == 1 then
			break
		else
			NpcFactory.Face(npc, npc.Root.Position + Vector3.new(0, 0, 5))
			task.wait(0.5)
		end
		if os.clock() - started > Config.CustomerPatience * 1.6 then
			say(npc, ANGRY)
			return false
		end
	end
	if not npc.Alive then
		return false
	end
	NpcFactory.Face(npc, Vector3.new(lane.X, 0, npc.Root.Position.Z))
	S.Checkout.BeginService(lane, npc)
	if npc.Weird then
		CustomerManager.Say(npc, "Я каждую ночь беру одно и то же.")
	end
	local t0, nagged = os.clock(), false
	while npc.Alive and not npc.Paid do
		task.wait(0.5)
		if not nagged and os.clock() - t0 > 45 then
			nagged = true
			say(npc, IMPATIENT)
		end
		if os.clock() - t0 > Config.CustomerPatience then
			break
		end
	end
	return npc.Paid == true
end

local function finish(npc)
	local lane = npc.Lane
	local paid = npc.Paid == true
	S.Checkout.Leave(npc)
	if paid then
		CustomerManager.Say(npc, npc.Weird and "До завтра. Вернее… до сегодня." or Util.pick(THANKS, rng))
		S.Tasks.ProgressKind("serve", 1)
		S.Shift.AddServed()
	else
		say(npc, ANGRY)
	end
	task.wait(0.8)
	leave(npc, lane)
end

-------------------------------------------------------------------------------
-- Поведение
-------------------------------------------------------------------------------
local BEHAVIOUR = {}

function BEHAVIOUR.Normal(npc)
	enter(npc)
	if rng:NextNumber() < 0.4 then
		say(npc, GREET)
	end
	shop(npc, rng:NextInteger(1, 3))
	queueAndPay(npc)
	finish(npc)
end

-- Ходит спиной вперёд, но покупает как обычно
function BEHAVIOUR.Backwards(npc)
	npc.Backwards = true
	enter(npc)
	shop(npc, 2)
	npc.Backwards = false
	npc.Humanoid.AutoRotate = true
	queueAndPay(npc)
	finish(npc)
end

-- Постоянный покупатель: шесть пакетов одного молока
function BEHAVIOUR.Repeater(npc)
	npc.Weird = true
	enter(npc)
	local fr = map.Fridges[1]
	goTo(npc, fr.Front)
	NpcFactory.Face(npc, fr.Front + Vector3.new(0, 0, -5))
	task.wait(7)
	npc.Items = {}
	for _ = 1, 6 do
		table.insert(npc.Items, Products.Get("milk"))
	end
	queueAndPay(npc)
	finish(npc)
end

-- Стоит посреди ряда и смотрит на ближайшего игрока
function BEHAVIOUR.Watcher(npc)
	enter(npc)
	local i = rng:NextInteger(2, 6)
	goTo(npc, Navigation.Node("M" .. i))
	npc.Humanoid.AutoRotate = false
	local untilT = os.clock() + 28
	while npc.Alive and os.clock() < untilT do
		local root, d = nearestPlayer(npc.Root.Position, 80)
		if root then
			NpcFactory.Face(npc, root.Position)
			if d < 6 then
				CustomerManager.Say(npc, "…")
				task.wait(1.5)
				break
			end
		end
		task.wait(0.3)
	end
	npc.Humanoid.AutoRotate = true
	npc.Humanoid.WalkSpeed = 12
	leave(npc, nil)
end

-- Стоит лицом к хлебному стеллажу, пока к нему не подойдут
function BEHAVIOUR.WallFacer(npc)
	enter(npc)
	local spot = Vector3.new(-61, 0, rng:NextNumber(2, 20))
	goTo(npc, spot)
	NpcFactory.Face(npc, npc.Root.Position + Vector3.new(-5, 0, 0))
	local untilT = os.clock() + 70
	while npc.Alive and os.clock() < untilT do
		local root, d = nearestPlayer(npc.Root.Position, 9)
		if root then
			NpcFactory.Face(npc, root.Position)
			CustomerManager.Say(npc, "Вы тоже здесь работаете?.. Давно?")
			task.wait(3)
			break
		end
		task.wait(0.4)
	end
	npc.Humanoid.WalkSpeed = 13
	leave(npc, nil)
end

-------------------------------------------------------------------------------
function CustomerManager.Init(m, services, npcFactory, navigation)
	map, S, NpcFactory, Navigation = m, services, npcFactory, navigation
end

function CustomerManager.Spawn(kind)
	if #customers >= Config.MaxCustomers + 2 then
		return nil
	end
	local home = Util.pick(map.Points.CustomerSpawns, rng)
	local npc = NpcFactory.Customer(map.Dynamic, home)
	if not npc then
		return nil
	end
	npc.Home = home
	npc.Items = {}
	npc.Behaviour = kind
	npc.Humanoid.WalkSpeed = Config.CustomerWalkSpeed + rng:NextNumber(-1, 1)
	table.insert(customers, npc)
	task.spawn(function()
		local ok, err = pcall(BEHAVIOUR[kind] or BEHAVIOUR.Normal, npc)
		if not ok then
			warn("[Покупатель] " .. tostring(err))
		end
		if npc.Alive then
			remove(npc)
		end
	end)
	return npc
end

-- Первый покупатель придёт через несколько секунд после начала смены
function CustomerManager.OnShiftStart()
	lastSpawn = os.clock() - (Config.CustomerInterval[0] or 20) + 6
end

function CustomerManager.Start()
	task.spawn(function()
		while true do
			task.wait(1)
			if S.Net.Get("Phase") == "Shift" then
				local hour = math.floor((S.Net.Get("Minutes") or 0) / 60)
				local interval = Config.CustomerInterval[hour]
				if interval and #customers < Config.MaxCustomers and os.clock() - lastSpawn >= interval then
					lastSpawn = os.clock()
					CustomerManager.Spawn("Normal")
				end
			end
		end
	end)
end

function CustomerManager.Reset()
	for i = #customers, 1, -1 do
		local npc = customers[i]
		npc.Lane = nil
		NpcFactory.Destroy(npc)
	end
	customers = {}
end

return CustomerManager
