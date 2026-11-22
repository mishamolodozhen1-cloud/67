-- EventDirector: странные события ночи. Каждую смену план составляется заново по номеру ночи,
-- поэтому время и порядок событий каждый раз другие. Ночи нарастают:
--   1 «Первая смена»          — обычная работа, пара едва заметных странностей под утро
--   2 «Постоянный покупатель» — странные покупатели, касса №6, видения после 03:00
--   3 «Отключение»            — отключения света, все покупатели разом смотрят на вас, лампы гаснут
--                               цепочкой, ворота пищат сами, Покупатель подкрадывается и охотится
--   4 «Он внутри»             — он с первого часа, лицо за витриной, дыхание за спиной, надписи на кассах,
--                               покупатель без лица, полка рушится, голос диктора искажён
--   5 «Касса ноль»            — в 03:00 исчезают все покупатели и товар, на всех кассах «КАССА 0»,
--                               охота с 04:00, свет гаснет снова и снова
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
EventDirector.E = E -- для проверки событий по одному

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
	S.Tasks.Add({ Id = "delivery_1", Kind = "delivery", Text = "Принять поставку у заднего выхода", Room = "Служебный коридор — задний двор", Count = 1 })
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
	S.Tasks.Add({ Id = "register4", Kind = "register4", Text = "Выключить кассу самообслуживания №6 (она включилась сама)", Room = "Кассы самообслуживания", Count = 1 })
end

-- Подозрительный покупатель: диспетчер по рации просит присмотреть, на камерах видно, как он прячет товар
function E.Thief(warn)
	S.Customers.Spawn("Thief")
	if warn then
		task.delay(6, function()
			S.Net.RadioCall(nil, "Охрана, в зал зашёл подозрительный покупатель. Посмотрите по камерам и проверьте его на выходе.")
		end)
	end
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
-- Новые страшные события (ночи 3–5)
-------------------------------------------------------------------------------
-- Все покупатели в зале разом замирают и поворачиваются к вам
function E.HeadsTurn()
	local n = S.Customers.TurnHeads(rng:NextNumber(6, 9))
	if n > 0 then
		S.Net.Sound("Static", nil, 0.16)
		S.Net.Sound("FluorFlicker", Vector3.new(-12, 11, 10), 0.6)
	end
	return n
end

-- Лампы гаснут одна за другой — темнота «идёт» к игроку, у него за спиной кто-то дышит
function E.LightsChase()
	local player = randomPlayer()
	local root = player and Util.rootOf(player)
	if not root or not S.Store.RoomAt(root.Position) then
		return
	end
	S.Net.Effect(nil, "LightsChase", { Target = root.Position, Victim = player.UserId, Duration = rng:NextNumber(3.5, 5) })
end

-- На экранах свободных касс самообслуживания — красные надписи
function E.KioskMessage(seconds)
	local list = {}
	for _, t in ipairs(Texts.KioskCreepy) do
		table.insert(list, t)
	end
	Util.shuffle(list, rng)
	S.Checkout.Creepy(seconds or 9, list)
end

-- Лицо за витриной: Покупатель стоит снаружи у стекла и смотрит на игрока в зале; стучит ногтями
function E.WindowFace()
	local options = {}
	for _, p in ipairs(Players:GetPlayers()) do
		local root = Util.rootOf(p)
		if root and root.Position.Z > -12 and root.Position.Z < 49 and root.Position.X > -66 and root.Position.X < 40 then
			table.insert(options, p)
		end
	end
	local player = Util.pick(options, rng)
	local cf = player and S.Monster.WindowSpot(player)
	if not cf then
		return false
	end
	local glass = cf.Position + Vector3.new(0, 5, -1.4)
	local shown = S.Monster.Show(cf, 22, function(watcher)
		S.Net.Sound("GlassKnock", glass, 1)
		S.Net.Subtitle(watcher, "Шёпот", Texts.Whisper.Window, 4)
	end)
	if shown then
		S.Net.Sound("GlassKnock", glass, 0.9)
	end
	return shown
end

-- Ворота на выходе пищат сами, хотя рядом никого
function E.GhostAlarm()
	local pos = S.Security.GhostAlarm()
	task.delay(1.2, function()
		S.Net.Sound("StepsFar", pos + Vector3.new(0, 1, 6), 0.7)
	end)
	task.delay(5, function()
		S.Net.RadioCall(nil, "Охрана, сработали ворота на выходе. На камере… на камере никого.")
	end)
end

-- Вся выкладка на полке рядом с игроком с грохотом сыплется на пол
function E.ShelfCollapse()
	local player = randomPlayer()
	local root = player and Util.rootOf(player)
	if not root then
		return
	end
	local options = {}
	for _, f in ipairs(map.Facings) do
		if not f.Empty and f.Front and #f.Parts > 2 then
			local d = (f.Front.Position - root.Position).Magnitude
			if d > 6 and d < 30 then
				table.insert(options, f)
			end
		end
	end
	local f = Util.pick(options, rng)
	if not f then
		return
	end
	local homes = {}
	for _, part in ipairs(f.Parts) do
		if part.Name == "Product" then
			homes[part] = part.CFrame
			part.Anchored = false
			part.AssemblyLinearVelocity = Vector3.new(f.Side * rng:NextNumber(7, 14), rng:NextNumber(1, 6), rng:NextNumber(-3, 3))
			part.AssemblyAngularVelocity = Vector3.new(rng:NextNumber(-8, 8), rng:NextNumber(-8, 8), rng:NextNumber(-8, 8))
		end
	end
	S.Net.Sound("ShelfCrash", f.Front.Position, 1)
	task.delay(75, function()
		for part, home in pairs(homes) do
			if part.Parent then
				part.Anchored = true
				part.AssemblyLinearVelocity = Vector3.new()
				part.CFrame = home
			end
		end
	end)
end

-- Тяжёлое дыхание прямо за спиной. jump = true: если обернуться — лицо Покупателя на весь экран
function E.Breath(jump)
	local player = randomPlayer()
	if player then
		S.Net.Effect(player, "BehindYou", { Jump = jump == true })
	end
end

-- Далёкий нечеловеческий крик со двора
function E.Scream()
	S.Net.Sound("Scream", Vector3.new(-14, 4, -84), 1)
end

-- Кто-то дёргает ручку закрытой двери
function E.DoorHandle(name)
	local door = S.Doors.Get(name)
	local part = door and door.Parts and door.Parts[1]
	if part then
		S.Net.Sound("DoorHandle", part.Position, 1)
		task.delay(rng:NextNumber(1.4, 2.2), function()
			S.Net.Sound("DoorHandle", part.Position, 1)
		end)
	end
end

-- Пятая ночь, 03:00: свет мигает — и в магазине больше никого и ничего
function E.Vanish()
	E.Flicker("Floor", Vector3.new(-12, 0, 18), 90, 4)
	S.Net.Sound("PowerDown", Vector3.new(-12, 10, 18), 0.6)
	task.delay(1.4, function()
		S.Customers.VanishAll()
		S.Store.EmptyAll()
		S.Checkout.Creepy(100000, "КАССА 0\n\nПокупатель\nожидает")
		S.Tasks.Drop("help", "Покупатели исчезли. Помогать на кассах больше некому")
		S.Tasks.Drop("orders")
		S.Tasks.Drop("catch")
		S.Net.Set("Music", "Off")
	end)
	task.delay(7, function()
		S.Net.PAText("Уважаемые покупатели… магазин закрыт. В торговом зале остался один сотрудник.", true)
	end)
end

-- Объявления: обычные, замедленные и искажённые
local function pa(line, distort)
	if distort then
		S.Net.PA(line, { Pitch = rng:NextNumber(0.72, 0.84), Distort = true })
	else
		S.Net.PA(line)
	end
end

-------------------------------------------------------------------------------
-- План смены
-------------------------------------------------------------------------------
local curNight = 1

-- Музыка из динамиков по часам: Normal, Slow (замедлена), Warped (плывёт и хрипит), Off
local MUSIC = {
	[1] = { [0] = "Normal" },
	[2] = { [0] = "Normal", [4] = "Slow" },
	[3] = { [0] = "Normal", [2] = "Off", [3] = "Slow" },
	[4] = { [0] = "Normal", [1] = "Slow", [3] = "Warped" },
	[5] = { [0] = "Warped", [3] = "Off" },
}

-- Обычная работа охранника — во все ночи
local function work(night)
	for _, msg in ipairs(Texts.Nights[night].Phone) do
		local sender = msg[2] == "Director" and Texts.Director or Texts.Unknown
		add(msg[1], "Phone", function()
			S.Net.Phone(nil, sender, msg[3])
		end)
	end
	add(2, "PA Welcome", function()
		pa("Welcome", night >= 5)
	end)
	add(r(18, 30), "Radio check", function()
		S.Net.RadioCall(nil, "Пост охраны, проверка связи. Начните обход и держите кассы самообслуживания под контролем.")
	end)
	add(r(40, 55), "Thief 1", function()
		E.Thief(true)
	end)
	if night <= 4 then
		add(r(130, 165), "Thief 2", function()
			E.Thief(night <= 2)
		end)
	end
	if night == 2 or night == 3 then
		add(r(200, 235), "Thief 3", function()
			E.Thief(false)
		end)
	end
	if night <= 3 then
		add(r(63, 72), "Delivery", E.Delivery)
	end
	if night <= 4 then
		add(r(28, 48), "PA Discount", function()
			pa("Discount", night == 4)
		end)
		add(r(126, 170), "Items on floor", E.ItemsOnFloor)
	end
	if night >= 2 then
		add(r(214, 236), "Fridge breaks", function()
			S.Store.BreakFridge()
		end)
	end
end

local PLANS = {}

-- Ночь 1: обычная смена. Почти ничего не происходит — только пара мелочей под утро
PLANS[1] = function()
	add(r(96, 104), "PA CallRegister", function()
		pa("CallRegister")
	end)
	add(r(200, 230), "Fridge breaks", function()
		S.Store.BreakFridge()
	end)
	add(r(150, 175), "Flicker aisle", function()
		E.Flicker("Floor", Vector3.new(rng:NextNumber(-50, 30), 0, rng:NextNumber(0, 20)), 14, 1.6)
	end)
	add(r(205, 240), "Item falls", E.ItemFalls)
	add(r(300, 330), "Steps near", E.FootstepsNear)
	add(r(336, 350), "Back knocks", function()
		E.Knocks(S.Doors.Get("BackExit").Parts[1].Position, false, 2)
	end)
end

-- Ночь 2: постоянный покупатель
PLANS[2] = function()
	add(r(96, 104), "PA CallRegister", function()
		pa("CallRegister")
	end)
	add(r(70, 90), "Repeater", function()
		E.Strange("Repeater")
	end)
	add(r(100, 125), "Watcher 1", function()
		E.Strange("Watcher")
	end)
	add(r(150, 170), "Backwards", function()
		E.Strange("Backwards")
	end)
	add(r(220, 238), "Watcher 2", function()
		E.Strange("Watcher")
	end)
	add(r(250, 275), "WallFacer", function()
		E.Strange("WallFacer")
	end)
	add(r(120, 150), "Cart", E.CartRoll)
	add(r(140, 170), "Unknown visitor", E.UnknownVisitor)
	add(180, "Cam anomalies", function()
		S.Net.Set("CamAnomalies", true)
	end)
	add(r(200, 212), "Register 6", E.Register4)
	add(r(230, 262), "Apparition", E.Apparition)
	add(r(110, 140), "Item falls 1", E.ItemFalls)
	add(r(250, 285), "Item falls 2", E.ItemFalls)
	add(r(170, 200), "Steps near 1", E.FootstepsNear)
	add(r(290, 325), "Steps near 2", E.FootstepsNear)
	add(r(240, 270), "Lamps out", E.LampsOut)
	add(r(300, 335), "Flicker figure", E.FlickerFigure)
	add(r(250, 262), "PA NeverCloses", function()
		pa("NeverCloses")
	end)
	add(r(270, 292), "Phone ring", function()
		S.Store.RingPhone(35)
	end)
	add(r(290, 312), "Cold knocks", E.ColdRoomKnocks)
	add(r(320, 345), "Whisper", function()
		E.Whisper(Texts.Whisper.NotFinished)
	end)
end

-- Ночь 3: отключения света, он ходит в темноте
PLANS[3] = function()
	add(120, "Cam anomalies", function()
		S.Net.Set("CamAnomalies", true)
	end)
	add(r(80, 100), "Watcher", function()
		E.Strange("Watcher")
	end)
	add(r(110, 125), "Repeater", function()
		E.Strange("Repeater")
	end)
	add(r(190, 210), "WallFacer", function()
		E.Strange("WallFacer")
	end)
	add(r(108, 118), "PA NeverCloses", function()
		pa("NeverCloses")
	end)
	add(r(130, 150), "Heads turn 1", E.HeadsTurn)
	add(r(200, 215), "Heads turn 2", E.HeadsTurn)
	add(r(150, 160), "Blackout 1", function()
		S.Power.Cut()
	end)
	add(r(160, 176), "Ghost alarm 1", E.GhostAlarm)
	add(r(178, 192), "Lights chase 1", E.LightsChase)
	add(r(204, 213), "Cold room call", E.ColdRoomCall)
	add(r(216, 226), "Blackout 2", function()
		S.Power.Cut()
	end)
	add(r(226, 236), "Register 6", E.Register4)
	add(240, "PA RegisterZero", function()
		pa("RegisterZero")
	end)
	add(r(250, 298), "Door slam", E.SlamOpenDoor)
	add(r(262, 280), "Ghost alarm 2", E.GhostAlarm)
	add(r(266, 298), "PA DontTurn", function()
		pa("DontTurn")
	end)
	add(r(280, 300), "Breath", function()
		E.Breath(false)
	end)
	add(r(286, 300), "Blackout 3", function()
		S.Power.Cut()
	end)
	add(r(302, 322), "Lights chase 2", E.LightsChase)
	if rng:NextNumber() < 0.6 then
		add(r(330, 345), "Blackout 4", function()
			S.Power.Cut()
		end)
	end
	add(r(322, 356), "Back knocks", function()
		E.Knocks(S.Doors.Get("BackExit").Parts[1].Position, true, 5)
	end)
	add(r(150, 178), "Phone ring 1", function()
		S.Store.RingPhone(35)
	end)
	add(r(262, 296), "Phone ring 2", function()
		S.Store.RingPhone(30)
	end)
	add(r(122, 178), "Apparition 1", E.Apparition)
	add(r(196, 236), "Whisper 1", function()
		E.Whisper(Texts.Whisper.NotFinished)
	end)
	add(r(302, 350), "Whisper 2", function()
		E.Whisper(Texts.Whisper.DontTurn)
	end)
	add(r(70, 118), "Item falls 1", E.ItemFalls)
	add(r(182, 238), "Item falls 2", E.ItemFalls)
	add(r(242, 298), "Item falls 3", E.ItemFalls)
	add(r(80, 118), "Steps near 1", E.FootstepsNear)
	add(r(182, 238), "Steps near 2", E.FootstepsNear)
	add(r(242, 298), "Steps near 3", E.FootstepsNear)
	add(r(300, 356), "Steps near 4", E.FootstepsNear)
	add(r(130, 178), "Lamps out 1", E.LampsOut)
	add(r(242, 298), "Lamps out 2", E.LampsOut)
	add(r(140, 178), "Flicker figure 1", E.FlickerFigure)
	add(r(182, 238), "Flicker figure 2", E.FlickerFigure)
	add(r(300, 356), "Flicker figure 3", E.FlickerFigure)
	add(r(305, 355), "Flicker back", function()
		E.Flicker("Corridor", Vector3.new(-14, 0, -38), 30, 5)
	end)
end

-- Ночь 4: он внутри
PLANS[4] = function()
	add(60, "Cam anomalies", function()
		S.Net.Set("CamAnomalies", true)
	end)
	add(r(64, 70), "Back knocks 1", function()
		E.Knocks(S.Doors.Get("BackExit").Parts[1].Position, true, 4)
	end)
	add(r(72, 90), "Window face 1", E.WindowFace)
	add(r(90, 110), "Heads turn", E.HeadsTurn)
	add(r(98, 106), "PA CallRegister", function()
		pa("CallRegister")
	end)
	add(r(100, 116), "Door handle 1", function()
		E.DoorHandle("Office")
	end)
	add(r(110, 128), "Faceless 1", function()
		E.Strange("Faceless")
	end)
	add(r(120, 130), "Register 6", E.Register4)
	add(r(130, 150), "Breath 1", function()
		E.Breath(true)
	end)
	add(r(140, 152), "Ghost alarm", E.GhostAlarm)
	add(r(150, 158), "PA ColdRoom", function()
		pa("ColdRoom", true)
		task.delay(10, E.ColdRoomKnocks)
	end)
	add(r(160, 170), "Kiosk message 1", function()
		E.KioskMessage(10)
	end)
	add(r(176, 194), "Shelf collapse 1", E.ShelfCollapse)
	add(r(186, 196), "Blackout 1", function()
		S.Power.Cut()
	end)
	add(r(192, 212), "Window face 2", E.WindowFace)
	add(r(200, 220), "Faceless 2", function()
		E.Strange("Faceless")
	end)
	add(r(200, 208), "PA RegisterZero", function()
		pa("RegisterZero", true)
	end)
	add(r(215, 230), "Lights chase 1", E.LightsChase)
	add(r(230, 240), "Scream", E.Scream)
	add(r(240, 250), "Kiosk message 2", function()
		E.KioskMessage(12)
	end)
	add(r(250, 270), "Breath 2", function()
		E.Breath(true)
	end)
	add(r(258, 266), "PA DontTurn", function()
		pa("DontTurn", true)
	end)
	add(r(270, 282), "Blackout 2", function()
		S.Power.Cut()
	end)
	add(r(280, 292), "Door handle 2", function()
		E.DoorHandle("Office")
	end)
	add(r(290, 312), "Window face 3", E.WindowFace)
	add(r(300, 320), "Shelf collapse 2", E.ShelfCollapse)
	add(r(318, 326), "PA NeverCloses", function()
		pa("NeverCloses", true)
	end)
	add(r(322, 336), "Blackout 3", function()
		S.Power.Cut()
	end)
	add(r(330, 346), "Lights chase 2", E.LightsChase)
	add(r(340, 356), "Back knocks 2", function()
		E.Knocks(S.Doors.Get("BackExit").Parts[1].Position, true, 6)
	end)
	add(r(110, 150), "Phone ring 1", function()
		S.Store.RingPhone(30)
	end)
	add(r(262, 296), "Phone ring 2", function()
		S.Store.RingPhone(30)
	end)
	add(r(80, 120), "Apparition 1", E.Apparition)
	add(r(180, 230), "Apparition 2", E.Apparition)
	add(r(150, 200), "Whisper 1", function()
		E.Whisper(Texts.Whisper.Behind)
	end)
	add(r(300, 350), "Whisper 2", function()
		E.Whisper(Texts.Whisper.Breath)
	end)
	add(r(70, 118), "Item falls 1", E.ItemFalls)
	add(r(242, 298), "Item falls 2", E.ItemFalls)
	for i, span in ipairs({ { 62, 118 }, { 150, 200 }, { 220, 270 }, { 300, 356 } }) do
		add(r(span[1], span[2]), "Steps near " .. i, E.FootstepsNear)
	end
	for i, span in ipairs({ { 100, 150 }, { 200, 250 }, { 280, 340 } }) do
		add(r(span[1], span[2]), "Lamps out " .. i, E.LampsOut)
		add(r(span[1], span[2]), "Flicker figure " .. i, E.FlickerFigure)
	end
end

-- Ночь 5: касса ноль
PLANS[5] = function()
	add(0, "Cam anomalies", function()
		S.Net.Set("CamAnomalies", true)
	end)
	add(r(50, 70), "Window face 1", E.WindowFace)
	add(r(60, 80), "Faceless 1", function()
		E.Strange("Faceless")
	end)
	add(r(80, 100), "Watcher", function()
		E.Strange("Watcher")
	end)
	add(r(95, 110), "Heads turn 1", E.HeadsTurn)
	add(r(100, 112), "Kiosk message", function()
		E.KioskMessage(14)
	end)
	add(r(115, 135), "Faceless 2", function()
		E.Strange("Faceless")
	end)
	add(r(120, 140), "Shelf collapse", E.ShelfCollapse)
	add(r(140, 158), "Window face 2", E.WindowFace)
	add(r(150, 165), "Heads turn 2", E.HeadsTurn)
	add(r(150, 160), "Radio static", function()
		S.Net.RadioCall(nil, "Пост охраны… (помехи) …сколько вас там? На камерах в магазине… (помехи) …один человек.")
	end)
	add(r(160, 172), "Breath 1", function()
		E.Breath(true)
	end)
	-- 03:00 — все исчезают
	add(180, "Vanish", E.Vanish)
	add(r(185, 190), "Whisper alone", function()
		E.Whisper(Texts.Whisper.Alone)
	end)
	add(r(194, 200), "Register 6", E.Register4)
	add(r(200, 210), "Blackout 1", function()
		S.Power.Cut()
	end)
	add(r(214, 224), "Breath 2", function()
		E.Breath(true)
	end)
	add(r(225, 236), "Lights chase 1", E.LightsChase)
	add(r(230, 238), "Scream", E.Scream)
	add(240, "PA RegisterZero", function()
		pa("RegisterZero", true)
	end)
	add(r(242, 252), "Window face 3", E.WindowFace)
	add(r(250, 260), "Blackout 2", function()
		S.Power.Cut()
	end)
	add(r(260, 270), "Ghost alarm", E.GhostAlarm)
	add(r(268, 278), "Phone ring", function()
		S.Store.RingPhone(30)
	end)
	add(r(275, 286), "Breath 3", function()
		E.Breath(true)
	end)
	add(r(286, 296), "Lights chase 2", E.LightsChase)
	add(r(290, 300), "Back knocks", function()
		E.Knocks(S.Doors.Get("BackExit").Parts[1].Position, true, 6)
	end)
	add(r(300, 306), "PA DontTurn", function()
		pa("DontTurn", true)
	end)
	add(r(302, 312), "Blackout 3", function()
		S.Power.Cut()
	end)
	add(r(318, 326), "Door handle", function()
		E.DoorHandle("Office")
	end)
	add(r(326, 336), "Whisper finish", function()
		E.Whisper(Texts.Whisper.Finish)
	end)
	add(r(330, 340), "Breath 4", function()
		E.Breath(true)
	end)
	add(r(340, 350), "Blackout 4", function()
		S.Power.Cut()
	end)
	add(r(348, 354), "PA NeverCloses", function()
		pa("NeverCloses", true)
	end)
	add(r(40, 90), "Apparition 1", E.Apparition)
	add(r(120, 175), "Apparition 2", E.Apparition)
	for i, span in ipairs({ { 30, 80 }, { 100, 170 }, { 190, 240 }, { 250, 300 }, { 310, 356 } }) do
		add(r(span[1], span[2]), "Steps near " .. i, E.FootstepsNear)
	end
	for i, span in ipairs({ { 60, 120 }, { 140, 178 }, { 210, 260 }, { 280, 340 } }) do
		add(r(span[1], span[2]), "Flicker figure " .. i, E.FlickerFigure)
	end
	for i, span in ipairs({ { 80, 140 }, { 190, 240 }, { 300, 350 } }) do
		add(r(span[1], span[2]), "Lamps out " .. i, E.LampsOut)
	end
end

function EventDirector.Plan(night)
	queue = {}
	curNight = math.clamp(math.floor(tonumber(night) or 1), 1, #PLANS)
	work(curNight)
	PLANS[curNight]()
	table.sort(queue, function(a, b)
		return a.At < b.At
	end)
end

function EventDirector.Night()
	return curNight
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

-- Музыка из динамиков по расписанию ночи (MUSIC)
function EventDirector.OnHour(hour)
	local sched = MUSIC[curNight] or MUSIC[1]
	local mode = nil
	for h = 0, hour do
		mode = sched[h] or mode
	end
	if mode then
		S.Net.Set("Music", mode)
	end
end

-- Список событий плана (для проверки)
function EventDirector.Queue()
	local list = {}
	for _, ev in ipairs(queue) do
		table.insert(list, { At = ev.At, Name = ev.Name })
	end
	return list
end

-- Реакции на действия игроков
function EventDirector.OnDoor(name, isOpen)
	local hour = math.floor((S.Net.Get("Minutes") or 0) / 60)
	if S.Net.Get("Phase") ~= "Shift" then
		return
	end
	if name == "BackExit" and isOpen and curNight >= 2 and hour >= 6 - curNight and rng:NextNumber() < 0.35 then
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
	curNight = 1
	S.Net.Set("Music", "Normal")
	S.Net.Set("CamAnomalies", false)
end

return EventDirector
