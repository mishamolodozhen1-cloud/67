-- CustomerManager: покупатели.
-- Обычный: входит, ходит по рядам и берёт товар с полок (анимация), идёт на свободную кассу
--   самообслуживания, сам сканирует и платит картой, уходит через проход между кассами.
-- Вор: берёт товар, оглядывается и прячет под куртку, идёт мимо касс к выходу — сработают ворота.
-- За заказом: идёт к стойке выдачи, называет номер и ждёт, пока охранник принесёт коробку.
-- Странные (появляются по событиям ночи): «Наблюдатель» стоит и смотрит на игрока,
-- «У стены» смотрит в стену, «Задом наперёд» ходит спиной вперёд, «Постоянный» каждую ночь берёт одно и то же,
-- «Без лица» (ночи 4–5) идёт за игроком по пятам и исчезает, если подойти.
-- По событиям все покупатели разом поворачиваются к игроку (TurnHeads) или исчезают (VanishAll).
-- v10: у каждого покупателя свой голос (мужской M1/M2 или женский F1, своя высота тона) — реплики озвучены.
-- Когда гаснет свет, покупатели пугаются (Panic): замирают, оглядываются, включают фонарик телефона,
-- кто-то бросает корзину и уходит. Свет вернулся — успокаиваются (Calm).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Products = require(Shared:WaitForChild("Products"))
local Util = require(Shared:WaitForChild("Util"))
local VoiceLines = require(Shared:WaitForChild("VoiceLines"))

local CustomerManager = {}

local map, S, NpcFactory, Navigation
local customers = {}
local rng = Random.new()
local lastSpawn = 0
local nextId = 0
local closed = false -- после VanishAll покупатели не приходят до конца смены

-- реплики — ключи VoiceLines (текст и голос берутся оттуда)
local GREET = { "Greet1", "Greet2", "Greet3", "Greet4" }
local THANKS = { "Thanks1", "Thanks2", "Thanks3", "Thanks4" }
local ANGRY = { "Angry1", "Angry2", "Angry3" }
local EMPTY = { "Empty1", "Empty2" }
local SHOP = { "Shop1", "Shop2", "Shop3", "Shop4" }
local DARK = { "Dark1", "Dark2", "Dark3", "Dark4", "Dark5", "Dark6", "Dark7", "Dark8", "Dark9", "Dark10" }
local LIGHT = { "Light1", "Light2", "Light3" }
local BEAST_SEEN = { "Beast1", "Beast2", "Beast3" }

function CustomerManager.All()
	return customers
end

-- Голос покупателя: мужчины — M1 или M2, женщины — F1; у каждого своя высота тона
local function voiceOf(npc)
	if not npc.Voice then
		if npc.Male == false then
			npc.Voice = "F1"
			npc.VoicePitch = rng:NextNumber(0.96, 1.1)
		else
			npc.Voice = rng:NextNumber() < 0.5 and "M1" or "M2"
			npc.VoicePitch = rng:NextNumber(0.9, 1.08)
		end
	end
	local pitch = npc.VoicePitch
	if npc.Weird then
		pitch = pitch * 0.86 -- странные говорят ниже и медленнее
	end
	return npc.Voice, pitch
end

-- Сказать реплику. what — ключ VoiceLines («Greet1»), список ключей (берётся случайный)
-- или просто текст (тогда без голоса, только надпись). suffix дописывается к надписи (номер заказа)
function CustomerManager.Say(npc, what, suffix)
	if not (npc and npc.Alive) then
		return
	end
	local key = type(what) == "table" and Util.pick(what, rng) or what
	local voice, pitch = voiceOf(npc)
	local clip = VoiceLines.Clips[voice .. "_" .. tostring(key)]
	if clip then
		NpcFactory.Say(npc, clip.Text .. (suffix or ""), 3.5)
		local head = npc.Model and npc.Model:FindFirstChild("Head")
		S.Net.Sound(voice .. "_" .. key, head or npc.Root.Position, 1, nil, pitch)
	else
		NpcFactory.Say(npc, tostring(key) .. (suffix or ""), 3.5)
	end
end

local function say(npc, list)
	CustomerManager.Say(npc, list)
end

local function remove(npc)
	for i, c in ipairs(customers) do
		if c == npc then
			table.remove(customers, i)
			break
		end
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

local function leave(npc, via)
	if not npc.Alive then
		return
	end
	for _, p in ipairs(via or {}) do
		NpcFactory.WalkTo(npc, p, 10)
	end
	goTo(npc, map.Points.EntranceInside)
	NpcFactory.WalkTo(npc, map.Points.EntranceOutside, 10)
	NpcFactory.WalkTo(npc, npc.Home, 25)
	remove(npc)
end

-- Ближайший к покупателю товар на этой выкладке, до которого он дотянется
local function shelfItem(npc, f)
	local root = npc.Root.Position
	local best, bestD = nil, math.huge
	for _, p in ipairs(f.Parts or {}) do
		if p.Parent and p.Transparency < 0.5 and p.Position.Y > 0.6 and p.Position.Y < 6.2 then
			local d = (p.Position - root).Magnitude
			if d < bestD then
				best, bestD = p, d
			end
		end
	end
	return best
end

-- Взять товар: копия товара с полки — в правую руку (на полке он пропадает), потом в корзину в левой руке.
-- part — товар на полке (или nil — тогда товар создаётся из описания product, как из холодильника)
local function takeItem(npc, product, part)
	npc.ItemParts = npc.ItemParts or {}
	table.insert(npc.Items, product)
	local index = #npc.Items
	local length = NpcFactory.PlayAction(npc, "Reach", function(mark)
		if not npc.Alive then
			return
		end
		if mark == "Grab" then
			local item
			if part and part.Parent and part.Transparency < 0.5 then
				item = part:Clone()
				item.Name = "Item"
				part.Transparency = 1
				for _, d in ipairs(part:GetChildren()) do
					if d:IsA("Decal") then
						d.Transparency = 1
					end
				end
			else
				local hand = npc.Model:FindFirstChild("RightHand")
				item = S.Checkout.MakeItem(product, hand and hand.CFrame or npc.Root.CFrame)
			end
			if item then
				item.Parent = map.Dynamic
				NpcFactory.HoldItem(npc, item)
				npc.ItemParts[index] = item
			end
		elseif mark == "Drop" then
			local item = npc.ItemParts[index]
			if item and npc.Basket then
				NpcFactory.PutInBasket(npc, item)
			end
		end
	end)
	task.wait(length)
end

-- Походить по рядам и набрать товар
local function shop(npc, stops)
	for _ = 1, stops do
		if not npc.Alive or npc.Flee then
			return
		end
		local f = map.Facings[rng:NextInteger(1, #map.Facings)]
		local z = math.clamp(f.ZCenter + rng:NextNumber(-3, 3), 1.5, 18.5)
		goTo(npc, Vector3.new(f.Aisle, 0, z))
		if not npc.Alive or npc.Flee then
			return
		end
		NpcFactory.Face(npc, Vector3.new(f.Front.Position.X, 0, z))
		if rng:NextNumber() < 0.2 then
			say(npc, SHOP)
		end
		task.wait(rng:NextNumber(0.8, 2.2))
		if f.Empty then
			say(npc, EMPTY)
		else
			for _ = 1, rng:NextInteger(1, 2) do
				-- берёт настоящий товар с полки: рука — к полке, товар — в руку, потом в корзину
				local part = shelfItem(npc, f)
				if part then
					NpcFactory.Face(npc, Vector3.new(part.Position.X, 0, part.Position.Z))
				end
				takeItem(npc, Products.Random(f.Category, rng), part)
			end
		end
	end
	if npc.Alive and not npc.Flee and rng:NextNumber() < 0.45 then
		local fr = map.Fridges[rng:NextInteger(1, #map.Fridges)]
		goTo(npc, fr.Front)
		NpcFactory.Face(npc, fr.Front + Vector3.new(0, 0, -5))
		task.wait(rng:NextNumber(1, 2.5))
		takeItem(npc, Products.Random("Chilled", rng), nil)
	end
	if #npc.Items == 0 and not npc.Flee then
		takeItem(npc, Products.Random(nil, rng), nil)
	end
end

-- Касса самообслуживания: ждёт свободную, сканирует и платит сам. Возвращает касс у и true, если оплатил
local function selfCheckout(npc)
	local k = S.Checkout.Free()
	local t0 = os.clock()
	while npc.Alive and not k and not npc.Flee do
		-- все кассы заняты: стоит перед ними и ждёт
		if not npc.WaitingSpot then
			npc.WaitingSpot = Vector3.new(rng:NextNumber(-22, 20), 0, 27.5)
			goTo(npc, npc.WaitingSpot)
			NpcFactory.Face(npc, npc.WaitingSpot + Vector3.new(0, 0, 5))
		end
		task.wait(1)
		k = S.Checkout.Free()
		if os.clock() - t0 > Config.CustomerPatience then
			say(npc, ANGRY)
			return nil, false
		end
	end
	if not npc.Alive or npc.Flee or not k then
		return nil, false
	end
	k.State = "Reserved"
	goTo(npc, k.CustomerSpot)
	local paid = S.Checkout.Use(k, npc)
	return k, paid
end

local function finish(npc, k, paid)
	if paid then
		CustomerManager.Say(npc, npc.Weird and "Weird1" or THANKS)
		S.Shift.AddServed()
	else
		say(npc, ANGRY)
	end
	task.wait(0.8)
	-- к выходу через проход между кассами
	local via = {}
	if k then
		table.insert(via, k.ExitGap)
		table.insert(via, Vector3.new(k.ExitGap.X, 0, 41))
	end
	leave(npc, via)
end

-------------------------------------------------------------------------------
-- Поведение
-------------------------------------------------------------------------------
local BEHAVIOUR = {}

function BEHAVIOUR.Normal(npc)
	NpcFactory.HoldBasket(npc)
	enter(npc)
	if rng:NextNumber() < 0.4 then
		say(npc, GREET)
	end
	shop(npc, rng:NextInteger(1, 3))
	if npc.Flee then
		return CustomerManager.FleeOut(npc)
	end
	local k, paid = selfCheckout(npc)
	if npc.Flee and not paid then
		return CustomerManager.FleeOut(npc)
	end
	finish(npc, k, paid)
end

-- Вор: набирает товар, прячет его под куртку и идёт к выходу мимо касс
function BEHAVIOUR.Thief(npc)
	enter(npc)
	shop(npc, rng:NextInteger(1, 2))
	if not npc.Alive then
		return
	end
	-- оглядывается и прячет (видно на камерах)
	S.Security.Conceal(npc)
	task.wait(rng:NextNumber(1, 3))
	-- к выходу
	goTo(npc, map.Points.EntranceInside)
	if not npc.Alive then
		return
	end
	NpcFactory.WalkTo(npc, map.Points.EntranceOutside, 10)
	if npc.Stolen and npc.Alarmed and not npc.Caught then
		-- ворота пищат — бежит
		npc.Humanoid.WalkSpeed = 15.5
		CustomerManager.Say(npc, "…")
	end
	NpcFactory.WalkTo(npc, npc.Home, 30)
	remove(npc)
end

-- За заказом: стойка выдачи, ждёт коробку
function BEHAVIOUR.Pickup(npc)
	local number = S.Security.FreeOrder()
	if not number then
		return BEHAVIOUR.Normal(npc)
	end
	enter(npc)
	goTo(npc, map.Pickup.CustomerSpot)
	if not npc.Alive then
		return
	end
	NpcFactory.Face(npc, map.Pickup.CustomerSpot + Vector3.new(0, 0, 5))
	CustomerManager.Say(npc, { "Order1", "Order2" }, " Номер " .. number .. ".")
	local got = S.Security.WaitOrder(npc, number)
	if got then
		CustomerManager.Say(npc, { "Thanks1", "Thanks6", "Thanks2" })
	else
		CustomerManager.Say(npc, { "Order6", "Order7" })
	end
	task.wait(1.2)
	leave(npc, { Vector3.new(-46, 0, 42.5) })
end

-- Ходит спиной вперёд, но покупает как обычно
function BEHAVIOUR.Backwards(npc)
	npc.Backwards = true
	enter(npc)
	shop(npc, 2)
	npc.Backwards = false
	npc.Humanoid.AutoRotate = true
	local k, paid = selfCheckout(npc)
	finish(npc, k, paid)
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
	local k, paid = selfCheckout(npc)
	finish(npc, k, paid)
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

-- Без лица: заходит, встаёт в нескольких шагах от игрока и смотрит. Если отойти — идёт следом.
-- Если подойти вплотную — помехи, и его больше нет
function BEHAVIOUR.Faceless(npc)
	npc.Weird = true
	enter(npc)
	npc.Humanoid.WalkSpeed = 6.5
	local untilT = os.clock() + 75
	while npc.Alive and os.clock() < untilT do
		local root, d = nearestPlayer(npc.Root.Position, 90)
		if not root then
			task.wait(0.5)
		elseif d < 5 then
			S.Net.Sound("Static", npc.Root.Position, 0.6)
			S.Net.Sound("Whisper", npc.Root.Position, 0.7)
			task.wait(0.15)
			remove(npc)
			return
		elseif d > 16 and S.Store.RoomAt(root.Position) then
			-- идёт следом, но останавливается в нескольких шагах
			local target = root.Position + (npc.Root.Position - root.Position).Unit * 9
			NpcFactory.WalkTo(npc, Vector3.new(target.X, 0, target.Z), 4)
		else
			NpcFactory.Face(npc, root.Position)
			task.wait(0.35)
		end
	end
	if npc.Alive then
		leave(npc, nil)
	end
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
			CustomerManager.Say(npc, "Weird2")
			task.wait(3)
			break
		end
		task.wait(0.4)
	end
	npc.Humanoid.WalkSpeed = 13
	leave(npc, nil)
end

-- Для автопроверок: покупатель берёт товар с выкладки f (возвращает деталь товара на полке)
function CustomerManager.TestTake(npc, f)
	local part = shelfItem(npc, f)
	takeItem(npc, Products.Random(f.Category, rng), part)
	return part
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
	local npc = NpcFactory.Customer(map.Dynamic, home, kind == "Faceless" and NpcFactory.FacelessLook() or nil)
	if not npc then
		return nil
	end
	nextId = nextId + 1
	npc.Id = tostring(nextId)
	npc.Home = home
	npc.Items = {}
	npc.Behaviour = kind
	S.Security.OnCustomer(npc)
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
			if S.Net.Get("Phase") == "Shift" and not closed then
				local hour = math.floor((S.Net.Get("Minutes") or 0) / 60)
				local untilHour = Config.Night(S.Net.Get("Night")).CustomersUntil or 4
				local interval = hour < untilHour and Config.CustomerInterval[hour] or nil
				if interval and #customers < Config.MaxCustomers and os.clock() - lastSpawn >= interval then
					lastSpawn = os.clock()
					local roll = rng:NextNumber()
					local thief = Config.ThiefChance[hour] or 0
					local pickup = Config.PickupChance[hour] or 0
					if roll < thief then
						CustomerManager.Spawn("Thief")
					elseif roll < thief + pickup then
						CustomerManager.Spawn("Pickup")
					else
						CustomerManager.Spawn("Normal")
					end
				end
			end
		end
	end)
end

function CustomerManager.Reset()
	for i = #customers, 1, -1 do
		local npc = customers[i]
		NpcFactory.Destroy(npc)
	end
	customers = {}
	closed = false
end

-- Все покупатели разом замирают и поворачиваются к ближайшему игроку, потом идут дальше как ни в чём не бывало
function CustomerManager.TurnHeads(seconds)
	local list = {}
	for _, npc in ipairs(customers) do
		if npc.Alive and not npc.Caught then
			table.insert(list, npc)
		end
	end
	for _, npc in ipairs(list) do
		npc.Frozen = true
		NpcFactory.StopActions(npc)
	end
	local untilT = os.clock() + (seconds or 6)
	task.spawn(function()
		while os.clock() < untilT do
			for _, npc in ipairs(list) do
				if npc.Alive then
					local root = nearestPlayer(npc.Root.Position, 120)
					if root then
						NpcFactory.Face(npc, root.Position)
					end
				end
			end
			task.wait(0.25)
		end
		for _, npc in ipairs(list) do
			if npc.Alive and not npc.Caught then
				npc.Frozen = false
			end
		end
	end)
	return #list
end

-------------------------------------------------------------------------------
-- Свет погас (v10)
-------------------------------------------------------------------------------
-- Бросить корзину и уйти из магазина (быстро)
function CustomerManager.FleeOut(npc)
	if not npc.Alive or npc.Fleeing then
		return
	end
	npc.Fleeing = true
	npc.Frozen = false
	if npc.Basket then
		local p = npc.Root.Position
		NpcFactory.PlaceBasket(npc, Vector3.new(p.X + rng:NextNumber(-1, 1), 0.55, p.Z + rng:NextNumber(-1, 1)), math.rad(rng:NextNumber(0, 360)), map.Dynamic)
	end
	npc.Humanoid.WalkSpeed = Config.CustomerWalkSpeed + 6
	leave(npc, nil)
end

-- Свет погас: все замирают, кто-то вскрикивает, оглядываются, включают фонарики телефонов;
-- примерно каждый третий через несколько секунд бросает корзину и уходит. Возвращает число покупателей
function CustomerManager.Panic(seconds)
	local n = 0
	for _, npc in ipairs(customers) do
		if npc.Alive and not npc.Caught and not npc.Weird and not npc.Scared then
			n = n + 1
			npc.Scared = true
			npc.Frozen = true
			NpcFactory.StopActions(npc)
			task.delay(rng:NextNumber(0.25, 1.6), function()
				if npc.Alive and npc.Scared then
					CustomerManager.Say(npc, DARK)
					NpcFactory.PlayAction(npc, "Look")
					NpcFactory.PhoneLight(npc, true)
				end
			end)
			if rng:NextNumber() < 0.35 then
				npc.Flee = true
			end
		end
	end
	if n >= 2 then
		S.Net.Sound("CrowdGasp", Vector3.new(-12, 4, 20), 0.8)
	end
	-- оцепенение проходит: кто решил уйти — уходит, остальные стоят и ждут свет
	task.delay(math.min(seconds or 8, rng:NextNumber(3, 5)), function()
		for _, npc in ipairs(customers) do
			if npc.Alive and npc.Scared and npc.Flee and not npc.Caught then
				npc.Frozen = false
				npc.Humanoid.WalkSpeed = Config.CustomerWalkSpeed + 6
			end
		end
	end)
	return n
end

-- Свет вернулся
function CustomerManager.Calm()
	local talkers = 0
	for _, npc in ipairs(customers) do
		if npc.Alive and npc.Scared then
			npc.Scared = false
			NpcFactory.PhoneLight(npc, false)
			if not npc.Caught then
				npc.Frozen = false
			end
			if not npc.Flee and talkers < 2 and rng:NextNumber() < 0.6 then
				talkers = talkers + 1
				task.delay(rng:NextNumber(0.4, 1.8), function()
					CustomerManager.Say(npc, LIGHT)
				end)
			end
		end
	end
end

-- Существо рядом (в темноте): покупатели в радиусе кричат и убегают
function CustomerManager.ReactBeast(pos, radius)
	local n = 0
	for _, npc in ipairs(customers) do
		if npc.Alive and not npc.Caught and not npc.Weird and (npc.Root.Position - pos).Magnitude < (radius or 22) then
			n = n + 1
			npc.Flee = true
			npc.Frozen = false
			npc.Humanoid.WalkSpeed = Config.CustomerWalkSpeed + 7
			task.delay(rng:NextNumber(0, 0.8), function()
				CustomerManager.Say(npc, BEAST_SEEN)
			end)
		end
	end
	if n > 0 then
		S.Net.Sound(rng:NextNumber() < 0.5 and "WomanScream" or "CrowdGasp", pos + Vector3.new(0, 4, 0), 0.9)
	end
	return n
end

-- В темноте пропадает один покупатель: крик, хруст — и только корзина на полу
function CustomerManager.Take()
	local list = {}
	for _, npc in ipairs(customers) do
		if npc.Alive and not npc.Caught and not npc.Weird then
			table.insert(list, npc)
		end
	end
	local npc = Util.pick(list, rng)
	if not npc then
		return false
	end
	local p = npc.Root.Position
	S.Net.Sound(npc.Male == false and "WomanScream" or "BeastGrowl", p + Vector3.new(0, 4, 0), 1)
	S.Net.Sound("BoneCrack", p + Vector3.new(0, 3, 0), 0.9)
	if npc.Basket then
		NpcFactory.PlaceBasket(npc, Vector3.new(p.X, 0.55, p.Z), math.rad(rng:NextNumber(0, 360)), map.Dynamic)
	end
	remove(npc)
	return true
end

-- Все покупатели исчезают (пятая ночь после 03:00), новые больше не приходят
function CustomerManager.VanishAll()
	closed = true
	for i = #customers, 1, -1 do
		local npc = customers[i]
		if npc.Alive then
			S.Net.Sound("Static", npc.Root.Position, 0.35)
		end
		remove(npc)
	end
end

return CustomerManager
