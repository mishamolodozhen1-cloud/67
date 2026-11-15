-- EventDirector: странные события ночи. Каждую смену план составляется заново,
-- поэтому время и порядок событий каждый раз другие. По часам:
--   00:00 обычная смена · 01:00 первые странности · 02:00 записи камер · 03:00 серьёзные аномалии
--   04:00 появляется Покупатель · 05:00 финальные задания · 06:00 конец смены
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Texts = require(Shared:WaitForChild("Texts"))
local Util = require(Shared:WaitForChild("Util"))

local EventDirector = {}

local map, S
local rng = Random.new()
local queue = {}

local function add(minute, name, fn)
	table.insert(queue, { At = minute, Name = name, Fn = fn })
end

local function r(a, b)
	return rng:NextInteger(a, b)
end

local function randomPlayer()
	local list = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if Util.rootOf(p) then
			table.insert(list, p)
		end
	end
	return Util.pick(list, rng)
end

-------------------------------------------------------------------------------
-- События
-------------------------------------------------------------------------------
local E = {}

function E.Flicker(zone, center, radius, seconds)
	S.Net.Effect(nil, "Flicker", { Zone = zone, Center = center, Radius = radius or 40, Duration = seconds or 3 })
	if center then
		S.Net.Sound("FluorFlicker", center + Vector3.new(0, 12, 0), 0.8)
	end
end

-- Тележка катится по заднему ряду сама
function E.CartRoll()
	local cart = Instance.new("Model")
	cart.Name = "GhostCart"
	local basket = Instance.new("Part")
	basket.Name = "Basket"
	basket.Size = Vector3.new(2.2, 1.8, 3.2)
	basket.Color = Color3.fromRGB(170, 30, 30)
	basket.Material = Enum.Material.Metal
	basket.Transparency = 0.25
	basket.Anchored = true
	basket.CanCollide = false
	basket.Parent = cart
	local frame = Instance.new("Part")
	frame.Name = "Frame"
	frame.Size = Vector3.new(2, 1.5, 0.2)
	frame.Color = Color3.fromRGB(190, 190, 194)
	frame.Material = Enum.Material.Metal
	frame.Anchored = true
	frame.CanCollide = false
	frame.Parent = cart
	cart.PrimaryPart = basket
	cart.Parent = map.Dynamic
	local x0, x1 = -55, 30
	if rng:NextNumber() < 0.5 then
		x0, x1 = x1, x0
	end
	local z = -4.5
	S.Net.Sound("Cart", Vector3.new((x0 + x1) / 2, 2, z), 1)
	task.spawn(function()
		for i = 0, 100 do
			local x = x0 + (x1 - x0) * (i / 100) ^ 0.8
			basket.CFrame = CFrame.new(x, 2.2, z) * CFrame.Angles(0, math.rad(90), 0)
			frame.CFrame = basket.CFrame * CFrame.new(0, 0, 1.7)
			task.wait(0.05)
		end
		task.delay(60, function()
			cart:Destroy()
		end)
	end)
end

-- Видение: Покупатель стоит там, где его видит только один игрок
function E.Apparition()
	local player = randomPlayer()
	local root = player and Util.rootOf(player)
	if not root then
		return
	end
	local options = {}
	for _, cf in ipairs(map.MonsterSpots) do
		local d = (cf.Position - root.Position).Magnitude
		if d > 18 and d < 70 then
			table.insert(options, cf)
		end
	end
	local cf = Util.pick(options, rng)
	if cf then
		S.Net.Effect(player, "Apparition", { CFrame = CFrame.lookAt(cf.Position, Vector3.new(root.Position.X, 0, root.Position.Z)) })
	end
end

function E.Knocks(position, hard, times)
	task.spawn(function()
		for _ = 1, times or 3 do
			S.Net.Sound(hard and "KnockHard" or "Knock", position, 1)
			task.wait(rng:NextNumber(1.2, 2.2))
		end
	end)
end

function E.Delivery()
	local door = S.Doors.Get("BackExit")
	E.Knocks(door.Parts[1].Position, false, 3)
	S.Tasks.Add({ Id = "delivery_1", Kind = "delivery", Text = "Принять поставку у заднего выхода", Room = "Служебный коридор → задний двор", Count = 1 })
end

function E.ItemsOnFloor()
	S.Tasks.Add({ Id = "pickup_1", Kind = "pickup", Text = "Убрать банки с пола", Room = "Торговый зал", Count = 6 })
end

function E.UnknownVisitor()
	S.Doors.GhostOpen(4)
	task.delay(1.5, function()
		S.Net.Sound("StepsFar", map.AutoDoor.Center + Vector3.new(0, 2, -8), 0.8)
	end)
end

function E.ColdRoomKnocks()
	S.Doors.Set("ColdRoom", false, true)
	E.Knocks(S.Doors.Get("ColdRoom").Parts[1].Position + Vector3.new(0, 0, -1), true, 4)
end

function E.ColdRoomCall()
	S.Net.PA("ColdRoom")
	task.delay(8, function()
		E.ColdRoomKnocks()
		S.Tasks.Add({ Id = "visit_cold", Kind = "visit", Text = "Проверить холодильную камеру", Room = "Холодильная камера", Count = 1, Data = { Room = "Холодильная камера" } })
	end)
end

function E.Register4()
	if S.Checkout.IsLane4Active() then
		return
	end
	S.Checkout.Lane4(true)
	S.Tasks.Add({ Id = "register4", Kind = "register4", Text = "Выключить кассу №4 (она не работает с 2003 года)", Room = "Кассы", Count = 1 })
end

function E.SlamOpenDoor()
	local open = {}
	for name, door in pairs(map.Doors) do
		if door.IsOpen then
			table.insert(open, name)
		end
	end
	local name = Util.pick(open, rng)
	if name then
		S.Doors.Slam(name)
	else
		S.Net.Sound("DoorSlam", S.Doors.Get("Office").Parts[1].Position, 1)
	end
end

function E.Whisper(text)
	local player = randomPlayer()
	if player then
		S.Net.Subtitle(player, "Шёпот", text, 5)
		S.Net.Sound("Static", nil, 0.25, player)
	end
end

function E.Strange(kind)
	S.Customers.Spawn(kind)
end

-- Товар падает с полки рядом с игроком (настоящая физика), потом возвращается на место
function E.ItemFalls()
	local player = randomPlayer()
	local root = player and Util.rootOf(player)
	if not root then
		return
	end
	local options = {}
	for _, f in ipairs(map.Facings) do
		if not f.Empty and f.Front and (f.Front.Position - root.Position).Magnitude < 28 then
			local simple = true
			for _, p in ipairs(f.Parts) do
				if p.Name ~= "Product" then
					simple = false
				end
			end
			if simple and #f.Parts > 0 then
				table.insert(options, f)
			end
		end
	end
	local f = Util.pick(options, rng)
	if not f then
		return
	end
	local part = f.Parts[rng:NextInteger(1, #f.Parts)]
	local home = part.CFrame
	part.Anchored = false
	part.AssemblyLinearVelocity = Vector3.new(f.Side * rng:NextNumber(6, 10), rng:NextNumber(2, 5), rng:NextNumber(-2, 2))
	part.AssemblyAngularVelocity = Vector3.new(rng:NextNumber(-6, 6), rng:NextNumber(-6, 6), rng:NextNumber(-6, 6))
	task.delay(0.45, function()
		S.Net.Sound(rng:NextNumber() < 0.5 and "BoxDrop" or "CansFall", part.Position, 0.7)
	end)
	task.delay(45, function()
		if part.Parent then
			part.Anchored = true
			part.AssemblyLinearVelocity = Vector3.new()
			part.CFrame = home
		end
	end)
end

-- Шаги где-то рядом, хотя там никого нет
function E.FootstepsNear()
	local player = randomPlayer()
	local root = player and Util.rootOf(player)
	if not root then
		return
	end
	local a = rng:NextNumber(0, math.pi * 2)
	local pos = root.Position + Vector3.new(math.cos(a), 0, math.sin(a)) * rng:NextNumber(14, 24)
	S.Net.Sound(rng:NextNumber() < 0.6 and "StepsFar" or "Steps", Vector3.new(pos.X, 2, pos.Z), 0.55)
end

-- Лампы над игроком гаснут на минуту-две
function E.LampsOut()
	local player = randomPlayer()
	local root = player and Util.rootOf(player)
	if not root then
		return
	end
	S.Net.Effect(nil, "LampsOut", { Center = root.Position, Radius = 16, Duration = rng:NextNumber(60, 120) })
	S.Net.Sound("FluorFlicker", root.Position + Vector3.new(0, 12, 0), 0.8)
end

-- Мигание света, в темноте между вспышками в конце прохода кто-то стоит (видно только одному)
function E.FlickerFigure()
	local player = randomPlayer()
	local root = player and Util.rootOf(player)
	if not root then
		return
	end
	S.Net.Effect(player, "Flicker", { Zone = "Floor", Center = root.Position, Radius = 45, Duration = 3.5, Figure = true })
	S.Net.Sound("FluorFlicker", root.Position + Vector3.new(0, 12, 0), 0.9, player)
end

-------------------------------------------------------------------------------
-- План смены
-------------------------------------------------------------------------------
function EventDirector.Plan()
	queue = {}
	-- Сообщения директора и неизвестного номера
	for _, msg in ipairs(Texts.PhoneSchedule) do
		local sender = msg[2] == "Director" and Texts.Director or Texts.Unknown
		add(msg[1], "Phone", function()
			S.Net.Phone(nil, sender, msg[3])
		end)
	end
	-- 00:00 — обычная ночь
	add(2, "PA Welcome", function()
		S.Net.PA("Welcome")
	end)
	add(r(28, 48), "PA Discount", function()
		S.Net.PA("Discount")
	end)
	-- 01:00 — первые странности
	add(r(63, 72), "Delivery", E.Delivery)
	add(r(75, 92), "Flicker aisle", function()
		E.Flicker("Floor", Vector3.new(rng:NextNumber(-50, 30), 0, rng:NextNumber(0, 20)), 22, 2.5)
	end)
	add(r(80, 110), "Strange 1", function()
		E.Strange(rng:NextNumber() < 0.5 and "Watcher" or "Backwards")
	end)
	add(r(85, 115), "Apparition 1", E.Apparition)
	add(r(96, 104), "PA CallRegister", function()
		S.Net.PA("CallRegister")
	end)
	add(r(108, 118), "PA NeverCloses", function()
		S.Net.PA("NeverCloses")
	end)
	if rng:NextNumber() < 0.6 then
		add(r(70, 115), "Cart", E.CartRoll)
	end
	-- 02:00 — записи камер
	add(120, "Cam anomalies", function()
		S.Net.Set("CamAnomalies", true)
	end)
	add(r(126, 170), "Items on floor", E.ItemsOnFloor)
	add(r(130, 172), "Unknown visitor", E.UnknownVisitor)
	add(r(138, 176), "Cold knocks", E.ColdRoomKnocks)
	add(r(128, 165), "Repeater", function()
		E.Strange("Repeater")
	end)
	add(r(150, 178), "Phone ring", function()
		S.Store.RingPhone(35)
	end)
	add(r(122, 178), "Apparition 2", E.Apparition)
	-- мелкие тревожные события, чем ближе к утру — тем чаще
	add(r(70, 118), "Item falls 1", E.ItemFalls)
	add(r(80, 118), "Steps near 1", E.FootstepsNear)
	add(r(124, 178), "Item falls 2", E.ItemFalls)
	add(r(126, 178), "Steps near 2", E.FootstepsNear)
	add(r(130, 178), "Lamps out 1", E.LampsOut)
	add(r(140, 178), "Flicker figure 1", E.FlickerFigure)
	add(r(182, 238), "Item falls 3", E.ItemFalls)
	add(r(182, 238), "Steps near 3", E.FootstepsNear)
	add(r(182, 238), "Flicker figure 2", E.FlickerFigure)
	add(r(200, 238), "Lamps out 2", E.LampsOut)
	add(r(242, 298), "Steps near 4", E.FootstepsNear)
	add(r(242, 298), "Item falls 4", E.ItemFalls)
	add(r(242, 298), "Lamps out 3", E.LampsOut)
	add(r(300, 356), "Steps near 5", E.FootstepsNear)
	add(r(300, 356), "Flicker figure 3", E.FlickerFigure)
	add(r(300, 356), "Item falls 5", E.ItemFalls)
	-- 03:00 — серьёзные аномалии
	add(r(184, 196), "Blackout 1", function()
		S.Power.Cut()
	end)
	add(r(204, 214), "Cold room call", E.ColdRoomCall)
	add(r(206, 226), "Register 4", E.Register4)
	add(r(214, 236), "Fridge breaks", function()
		S.Store.BreakFridge()
	end)
	add(r(190, 230), "Strange 2", function()
		E.Strange(rng:NextNumber() < 0.5 and "WallFacer" or "Watcher")
	end)
	add(r(222, 238), "Flicker floor", function()
		E.Flicker("Floor", Vector3.new(-12, 0, 18), 80, 4)
	end)
	add(r(196, 236), "Whisper 1", function()
		E.Whisper(Texts.Whisper.NotFinished)
	end)
	-- 04:00 — Покупатель
	add(240, "PA RegisterZero", function()
		S.Net.PA("RegisterZero")
	end)
	if rng:NextNumber() < 0.55 then
		add(r(256, 290), "Blackout 2", function()
			S.Power.Cut()
		end)
	end
	add(r(266, 298), "PA DontTurn", function()
		S.Net.PA("DontTurn")
	end)
	add(r(250, 298), "Door slam", E.SlamOpenDoor)
	add(r(262, 296), "Phone ring 2", function()
		S.Store.RingPhone(30)
	end)
	-- 05:00 — финал
	if rng:NextNumber() < 0.6 then
		add(r(312, 344), "Blackout 3", function()
			S.Power.Cut()
		end)
	end
	add(r(302, 350), "Whisper 2", function()
		E.Whisper(Texts.Whisper.DontTurn)
	end)
	add(r(322, 356), "Back knocks", function()
		E.Knocks(S.Doors.Get("BackExit").Parts[1].Position, true, 5)
	end)
	add(r(305, 355), "Flicker back", function()
		E.Flicker("Corridor", Vector3.new(-14, 0, -38), 30, 5)
	end)
	table.sort(queue, function(a, b)
		return a.At < b.At
	end)
end

-- Вызывается каждую игровую минуту
function EventDirector.OnMinute(minute)
	while queue[1] and queue[1].At <= minute do
		local ev = table.remove(queue, 1)
		local ok, err = pcall(ev.Fn)
		if not ok then
			warn("[Событие " .. ev.Name .. "] " .. tostring(err))
		end
	end
end

-- Музыка: обычная до 03:00, тишина в 03:00, искажённая после 04:00
function EventDirector.OnHour(hour)
	if hour <= 2 then
		S.Net.Set("Music", "Normal")
	elseif hour == 3 then
		S.Net.Set("Music", "Off")
	else
		S.Net.Set("Music", "Slow")
	end
end

-- Реакции на действия игроков
function EventDirector.OnDoor(name, isOpen)
	local hour = math.floor((S.Net.Get("Minutes") or 0) / 60)
	if S.Net.Get("Phase") ~= "Shift" then
		return
	end
	if name == "BackExit" and isOpen and hour >= 3 and rng:NextNumber() < 0.35 then
		task.delay(7, function()
			S.Doors.Slam("BackExit")
		end)
	end
end

function EventDirector.OnVisit(t, player)
	if t.Data.Room == "Холодильная камера" then
		task.delay(1.5, function()
			S.Doors.Slam("ColdRoom")
			E.Flicker("Cold", Vector3.new(1, 0, -52), 20, 2)
			S.Net.Subtitle(player, "Шёпот", "…здесь всегда холодно…", 4)
		end)
	end
end

function EventDirector.Init(m, services)
	map, S = m, services
	S.Net.Set("Music", "Normal")
	S.Net.Set("CamAnomalies", false)
end

function EventDirector.Reset()
	queue = {}
	S.Net.Set("Music", "Normal")
	S.Net.Set("CamAnomalies", false)
end

return EventDirector
