-- Security: работа охранника.
--   • Антикражные ворота у входа: если покупатель выносит неоплаченный товар — ворота пищат,
--     мигают красным, вор бежит к выходу. Охранник догоняет его и задерживает («Проверить чек»).
--     Вора можно вычислить и раньше: на камерах видно, как он оглядывается и прячет товар под куртку.
--     Проверить честного покупателя без причины — он обидится (это записывается в итоги смены).
--   • Обход: контрольные точки на стенах магазина, на каждой нужно отметиться (метка пищит).
--   • Пункт выдачи заказов: покупатель называет номер заказа, терминал показывает ячейку,
--     охранник берёт коробку с нужным номером со стеллажа и выдаёт её.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Util = require(Shared:WaitForChild("Util"))
local Models = require(Shared:WaitForChild("Models"))
local ModelKit = require(script.Parent:WaitForChild("ModelKit"))

local Security = {}

local map, S, NpcFactory
local rng = Random.new()
local stats = { Caught = 0, Escaped = 0, Orders = 0, FalseChecks = 0, Alarms = 0 }
local watched = {} -- npc -> последняя позиция Z (для ворот)
local alarmUntil = 0

-------------------------------------------------------------------------------
-- Ворота
-------------------------------------------------------------------------------
local function gateLamps(on)
	for _, l in ipairs(map.Gates.Lamps) do
		l.Part.Color = on and Color3.fromRGB(255, 40, 30) or Color3.fromRGB(90, 20, 20)
		l.Light.Brightness = on and 2.5 or 0
	end
end

local function soundAlarm(npc)
	stats.Alarms = stats.Alarms + 1
	alarmUntil = os.clock() + 4
	S.Net.Sound("GateAlarm", map.Gates.Center, 1)
	task.spawn(function()
		local on = true
		while os.clock() < alarmUntil do
			gateLamps(on)
			on = not on
			task.wait(0.25)
		end
		gateLamps(false)
	end)
	npc.Alarmed = true
	if npc.Stolen then
		S.Net.Notify(nil, "Сработали ворота! Покупатель выносит товар — задержите его", "warn")
		S.Net.RadioCall(nil, "Охрана, на выходе сработали ворота. Задержите покупателя!")
		S.Tasks.Add({ Id = "catch_" .. npc.Id, Kind = "catch", Text = "Задержать покупателя у выхода", Room = "Вход и парковка", Count = 1 })
	else
		S.Net.Notify(nil, "Сработали ворота. Проверьте чек у покупателя", "task")
	end
end

-- Ворота пищат сами, хотя рядом никого нет (поздние ночи). На камере над выходом в этот момент —
-- пустой проход. Возвращает позицию ворот, чтобы событие могло поставить там шаги
function Security.GhostAlarm()
	alarmUntil = os.clock() + 4
	S.Net.Sound("GateAlarm", map.Gates.Center, 1)
	task.spawn(function()
		local on = true
		while os.clock() < alarmUntil do
			gateLamps(on)
			on = not on
			task.wait(0.25)
		end
		gateLamps(false)
	end)
	return map.Gates.Center
end

-- Каждый кадр: кто пересёк линию ворот наружу
local function watchGates()
	local g = map.Gates
	for _, npc in ipairs(S.Customers.All()) do
		if npc.Alive and npc.Root then
			local p = npc.Root.Position
			local lastZ = watched[npc]
			watched[npc] = p.Z
			if lastZ and lastZ < g.Z and p.Z >= g.Z and p.X > g.X0 - 1 and p.X < g.X1 + 1 then
				if (npc.Stolen and not npc.Caught) or (not npc.Alarmed and rng:NextNumber() < Config.FalseAlarmChance and npc.Paid) then
					soundAlarm(npc)
				end
			end
			-- вор добежал до дальней парковки — скрылся
			if npc.Stolen and not npc.Caught and not npc.Escaped and p.Z > Config.ThiefEscapeZ then
				npc.Escaped = true
				stats.Escaped = stats.Escaped + 1
				S.Net.Notify(nil, "Вор скрылся с товаром", "warn")
				S.Shift.AddStat("Escaped")
			end
		end
	end
	for npc in pairs(watched) do
		if not npc.Alive then
			watched[npc] = nil
		end
	end
end

-------------------------------------------------------------------------------
-- Проверка покупателя (подсказка на каждом покупателе)
-------------------------------------------------------------------------------
local function check(npc, player)
	if not npc.Alive or npc.Checked then
		return
	end
	npc.Checked = true
	npc.CheckPrompt.Enabled = false
	if npc.Stolen and not npc.Caught then
		npc.Caught = true
		npc.Frozen = true
		npc.Humanoid:MoveTo(npc.Root.Position)
		NpcFactory.PlayAction(npc, "HandsUp")
		S.Net.Sound("ClothRustle", npc.Root.Position, 0.8)
		S.Customers.Say(npc, Util.pick({ "Ладно, ладно! Вот, забирайте…", "Я… я просто забыл заплатить.", "Только полицию не вызывайте!" }, rng))
		stats.Caught = stats.Caught + 1
		S.Shift.AddStat("Caught")
		S.Tasks.ProgressKind("catch", 1)
		if player then
			S.Net.Notify(player, "Вор задержан, товар возвращён", "done")
		end
		task.delay(3.2, function()
			if npc.Alive then
				npc.Stolen = false
				npc.Frozen = false
				npc.Humanoid.WalkSpeed = Config.CustomerWalkSpeed
				npc.Released = true
			end
		end)
	elseif npc.Alarmed then
		S.Customers.Say(npc, "Вот мой чек. Наверное, метку забыли снять.")
		S.Net.Sound("Receipt", npc.Root.Position, 0.5)
		if player then
			S.Net.Notify(player, "Чек в порядке — ложная тревога", "info")
		end
	else
		stats.FalseChecks = stats.FalseChecks + 1
		S.Shift.AddStat("FalseChecks")
		S.Customers.Say(npc, Util.pick({ "Вы что, меня подозреваете? Вот чек.", "Я всё оплатил. Ну и магазин.", "Мне за вами ещё и в магазине следить?" }, rng))
		if player then
			S.Net.Notify(player, "Покупатель всё оплатил и обиделся", "warn")
		end
	end
end

Security.Check = check

function Security.OnCustomer(npc)
	local p = Util.prompt(npc.Root, "Проверить чек", "Покупатель", 0.8, 7)
	p.RequiresLineOfSight = false
	p.UIOffset = Vector2.new(0, 40)
	npc.CheckPrompt = p
	p.Triggered:Connect(function(player)
		check(npc, player)
	end)
end

-- Вор прячет товар: видно на камерах (оглядывается, рука под куртку, шорох)
function Security.Conceal(npc)
	npc.Stolen = true
	NpcFactory.PlayAction(npc, "Look")
	task.wait(1.6)
	if npc.Alive then
		NpcFactory.PlayAction(npc, "Conceal")
		task.wait(2.4)
	end
end

-------------------------------------------------------------------------------
-- Обход
-------------------------------------------------------------------------------
local AMBER = Color3.fromRGB(255, 160, 40)
local GREEN = Color3.fromRGB(60, 230, 110)

local function resetPatrolLeds()
	for _, tag in ipairs(map.Patrol) do
		tag.Led.Color = AMBER
	end
end

local function patrolCheck(tag, player)
	local list = S.Tasks.Active("patrol")
	local t = list[1]
	if not t then
		S.Net.Sound("TagBeep", tag.Position, 0.5)
		if player then
			S.Net.Notify(player, "Обход сейчас не нужен", "info")
		end
		return
	end
	t.Data.Marked = t.Data.Marked or {}
	if t.Data.Marked[tag.Index] then
		if player then
			S.Net.Notify(player, "На этой точке вы уже отметились", "info")
		end
		return
	end
	t.Data.Marked[tag.Index] = true
	tag.Led.Color = GREEN
	S.Net.Sound("TagBeep", tag.Position, 0.8)
	S.Tasks.Progress(t.Id, 1)
	-- что ещё осталось
	local left = {}
	for _, other in ipairs(map.Patrol) do
		if not t.Data.Marked[other.Index] then
			table.insert(left, "№" .. other.Index)
		end
	end
	S.Tasks.SetDetail(t, #left > 0 and ("Осталось: " .. table.concat(left, ", ")) or "")
end

Security.PatrolCheck = patrolCheck

-------------------------------------------------------------------------------
-- Пункт выдачи заказов
-------------------------------------------------------------------------------
local parcels = {} -- номер -> { Number, Cell, Part, Prompt, Taken }
local waiting = {} -- номер -> npc

local function parcelLabel(part, number)
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Front
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 80
	sg.MaxDistance = 18
	sg.Parent = part
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 0.4)
	t.Position = UDim2.fromScale(0, 0.3)
	t.BackgroundColor3 = Color3.fromRGB(250, 250, 246)
	t.BorderSizePixel = 0
	t.TextColor3 = Color3.fromRGB(20, 20, 24)
	t.Font = Enum.Font.GothamBlack
	t.TextScaled = true
	t.Text = "№" .. number
	t.Parent = sg
end

local function placeParcel(number, cell)
	local scale = Models.Assets.Parcel.Scale * rng:NextNumber(0.85, 1.35)
	local part
	local model = ModelKit.MakeAsset("Parcel", map.Dynamic, CFrame.new(cell.Base) * CFrame.Angles(0, math.rad(rng:NextNumber(-8, 8)), 0), scale)
	if model then
		part = model:FindFirstChildWhichIsA("BasePart")
		model.Name = "Parcel"
	end
	if not part then
		part = Instance.new("Part")
		part.Name = "Parcel"
		part.Size = Vector3.new(1.0, 0.6, 1.3)
		part.Color = Color3.fromRGB(176, 136, 90)
		part.Material = Enum.Material.Cardboard
		part.Anchored = true
		part.CFrame = CFrame.new(cell.Base + Vector3.new(0, 0.3, 0))
		part.Parent = map.Dynamic
		model = part
	end
	-- наклейка с номером на торце, видна из прохода
	local tag = Instance.new("Part")
	tag.Name = "ParcelTag"
	tag.Size = Vector3.new(0.7, 0.35, 0.02)
	tag.Anchored = true
	tag.CanCollide = false
	tag.CanQuery = false
	tag.Transparency = 1
	local size = part.Size
	if model:IsA("Model") then
		local _, s2 = model:GetBoundingBox()
		size = s2
	end
	tag.CFrame = CFrame.lookAt(cell.Base + Vector3.new(0, math.max(0.25, size.Y * 0.5), -size.Z / 2 - 0.02), cell.Base + Vector3.new(0, math.max(0.25, size.Y * 0.5), -10))
	tag.Parent = model
	parcelLabel(tag, number)
	local prompt = Util.prompt(tag, "Взять заказ", "№" .. number .. " · ячейка " .. cell.Label, 0.4, 7)
	prompt.RequiresLineOfSight = false
	local entry = { Number = number, Cell = cell, Model = model, Tag = tag, Prompt = prompt, Taken = false }
	parcels[number] = entry
	cell.Number = number
	prompt.Triggered:Connect(function(player)
		Security.TakeParcel(player, entry)
	end)
	return entry
end

local function setParcelVisible(entry, visible)
	local list = entry.Model:IsA("Model") and entry.Model:GetDescendants() or { entry.Model }
	if not entry.Model:IsA("Model") then
		table.insert(list, entry.Model)
	end
	for _, d in ipairs(list) do
		if d:IsA("BasePart") and d.Name ~= "ParcelTag" then
			d.Transparency = visible and 0 or 1
		elseif d:IsA("SurfaceGui") then
			d.Enabled = visible
		end
	end
	entry.Prompt.Enabled = visible
end

local function freeCells()
	local list = {}
	for _, cell in pairs(map.Pickup.Cells) do
		if not cell.Number then
			table.insert(list, cell)
		end
	end
	return list
end

-- Пополнить стеллаж до count заказов (ночью курьеры привозят новые)
function Security.Restock(count)
	local n = 0
	for _ in pairs(parcels) do
		n = n + 1
	end
	while n < count do
		local cells = freeCells()
		if #cells == 0 then
			break
		end
		local number = tostring(rng:NextInteger(1000, 9899))
		if not parcels[number] then
			placeParcel(number, cells[rng:NextInteger(1, #cells)])
			n = n + 1
		end
	end
end

-- Заказ, за которым можно прийти (ещё не ждёт другой покупатель)
function Security.FreeOrder()
	local list = {}
	for number, e in pairs(parcels) do
		if not waiting[number] and not e.Taken then
			table.insert(list, number)
		end
	end
	return Util.pick(list, rng)
end

local function refreshTerminal()
	local lines = {}
	for number, npc in pairs(waiting) do
		local e = parcels[number]
		if e and npc.Alive then
			table.insert(lines, "№" .. number .. " → ячейка " .. e.Cell.Label)
		end
	end
	table.sort(lines)
	map.Pickup.StaffText.Text = #lines > 0 and ("ВЫДАЧА:\n" .. table.concat(lines, "\n")) or "ЗАКАЗОВ НЕТ"
	map.Pickup.CustomerText.Text = #lines > 0 and "ОЖИДАЙТЕ\nСОТРУДНИКА" or "ПУНКТ ВЫДАЧИ\nЗАКАЗОВ"
end

function Security.TakeParcel(player, entry)
	if entry.Taken then
		return
	end
	if not S.Store.GiveCarry(player, "Parcel", entry.Number) then
		return
	end
	entry.Taken = true
	entry.Carrier = player
	setParcelVisible(entry, false)
	S.Net.Sound("ParcelBox", entry.Cell.Base, 0.7)
end

-- Коробку положили обратно (её не взяли или игрок бросил)
function Security.ReturnParcel(number)
	local e = parcels[number]
	if e and e.Taken then
		e.Taken = false
		e.Carrier = nil
		setParcelVisible(e, true)
	end
end

local function removeParcel(number)
	local e = parcels[number]
	if e then
		e.Cell.Number = nil
		e.Model:Destroy()
		parcels[number] = nil
	end
end

-- Охранник отдаёт коробку, которую держит в руках, покупателю у стойки
function Security.GiveOrder(npc, player)
	local number = npc.OrderNumber
	local carry = player:GetAttribute("Carry") or ""
	local carried = string.match(carry, "^Parcel:(%d+)$")
	if not carried then
		S.Net.Notify(player, "Сначала возьмите коробку №" .. number .. " со стеллажа (ячейка " .. (parcels[number] and parcels[number].Cell.Label or "?") .. ")", "warn")
		return false
	end
	if carried ~= number then
		S.Customers.Say(npc, "Это не мой заказ. У меня №" .. number .. ".")
		S.Net.Sound("ScanError", npc.Root.Position, 0.5)
		S.Store.ClearCarry(player, false)
		return false
	end
	S.Store.ClearCarry(player, true)
	npc.OrderResult = true
	return true
end

function Security.Parcel(number)
	return parcels[number]
end

-- Покупатель пришёл за заказом: ждёт у стойки, пока охранник не выдаст. true — получил
function Security.WaitOrder(npc, number)
	waiting[number] = npc
	npc.OrderNumber = number
	refreshTerminal()
	S.Net.Sound("KioskHelp", map.Pickup.Terminal.Position, 0.6)
	S.Net.Notify(nil, "Пункт выдачи: пришли за заказом №" .. number, "task")
	local give = Util.prompt(npc.Root, "Выдать заказ", "№" .. number, 0.6, 8)
	give.RequiresLineOfSight = false
	give.UIOffset = Vector2.new(0, -40)
	npc.GivePrompt = give
	npc.OrderResult = nil
	give.Triggered:Connect(function(player)
		Security.GiveOrder(npc, player)
	end)
	local t0 = os.clock()
	local nagged = false
	local result = nil
	while npc.Alive and result == nil do
		result = npc.OrderResult
		task.wait(0.3)
		if not nagged and os.clock() - t0 > 40 then
			nagged = true
			S.Customers.Say(npc, Util.pick({ "Мне бы заказ забрать…", "Есть кто на выдаче?", "Номер " .. number .. ", я жду." }, rng))
		end
		if result == nil and os.clock() - t0 > Config.PickupPatience then
			result = false
		end
	end
	give:Destroy()
	waiting[number] = nil
	if result then
		NpcFactory.PlayAction(npc, "Take", nil, map.Pickup.CustomerSpot + Vector3.new(0, 3.4, 1.4))
		removeParcel(number)
		stats.Orders = stats.Orders + 1
		S.Shift.AddStat("Orders")
		S.Tasks.ProgressKind("orders", 1)
		S.Net.Notify(nil, "Заказ №" .. number .. " выдан", "done")
	else
		local e = parcels[number]
		if e and e.Taken and e.Carrier then
			-- охранник несёт коробку, а покупатель ушёл: коробка возвращается на полку
			S.Store.ClearCarry(e.Carrier, false)
		end
	end
	refreshTerminal()
	return result == true
end

-------------------------------------------------------------------------------
function Security.Init(m, services, npcFactory)
	map, S, NpcFactory = m, services, npcFactory
	for _, tag in ipairs(map.Patrol) do
		local p = Util.prompt(tag.Plate, "Отметиться", "Контрольная точка №" .. tag.Index, 0.6, 8)
		p.RequiresLineOfSight = false
		p.Triggered:Connect(function(player)
			patrolCheck(tag, player)
		end)
	end
	resetPatrolLeds()
	-- стойка выдачи: подсказка
	local hint = Util.prompt(map.Pickup.Terminal, "Список заказов", "Терминал выдачи", 0, 7)
	hint.Triggered:Connect(function(player)
		local lines = {}
		for number, npc in pairs(waiting) do
			if npc.Alive and parcels[number] then
				table.insert(lines, "№" .. number .. " — ячейка " .. parcels[number].Cell.Label)
			end
		end
		S.Net.Notify(player, #lines > 0 and ("Ждут заказы: " .. table.concat(lines, "; ")) or "Сейчас никто не ждёт заказ", "info")
	end)
	Security.Restock(7)
	refreshTerminal()
	RunService.Heartbeat:Connect(function()
		local ok, err = pcall(watchGates)
		if not ok then
			warn("[Охрана] " .. tostring(err))
		end
	end)
end

function Security.OnTaskAdded(t)
	if t.Kind == "patrol" then
		resetPatrolLeds()
		t.Data.Marked = {}
		S.Tasks.SetDetail(t, "Точки №1–" .. #map.Patrol .. ": вход, зал, склад, задний выход, коридор")
	end
end

function Security.Stats()
	return stats
end

function Security.Reset()
	stats = { Caught = 0, Escaped = 0, Orders = 0, FalseChecks = 0, Alarms = 0 }
	waiting = {}
	for number in pairs(parcels) do
		removeParcel(number)
	end
	parcels = {}
	for _, cell in pairs(map.Pickup.Cells) do
		cell.Number = nil
	end
	Security.Restock(7)
	refreshTerminal()
	resetPatrolLeds()
	gateLamps(false)
end

return Security
