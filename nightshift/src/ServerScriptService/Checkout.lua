-- Checkout: кассы самообслуживания (ночью кассиров нет — покупатели платят сами).
-- Покупатель подходит к свободной кассе, выкладывает корзину на полку слева, проводит каждый товар
-- над сканером (анимация, писк, строка на экране) и кладёт в пакет справа, затем прикладывает карту.
-- Иногда касса просит помощи сотрудника: «неожиданный предмет в зоне упаковки», «проверка товара»,
-- «карта не прошла». Лампа на стойке мигает оранжевым, касса зовёт сигналом — охранник подходит и
-- подтверждает (подсказка «Помочь покупателю»). Если долго никто не подходит, покупатель уходит,
-- не заплатив.
-- Здесь же: задание «Отключить кассы» в конце смены и аномалия «касса №6 включилась сама».
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Products = require(Shared:WaitForChild("Products"))
local Util = require(Shared:WaitForChild("Util"))
local Models = require(Shared:WaitForChild("Models"))
local ModelKit = require(script.Parent:WaitForChild("ModelKit"))

local Checkout = {}

local map, S, NpcFactory
local rng = Random.new()
local kiosks
local revenue = 0
local hauntedActive = false
local HAUNTED = 6

local GREEN = Color3.fromRGB(40, 200, 90)
local BLUE = Color3.fromRGB(60, 140, 255)
local ORANGE = Color3.fromRGB(255, 150, 30)
local GREY = Color3.fromRGB(70, 70, 72)
local RED = Color3.fromRGB(230, 30, 30)

local HELP_REASONS = {
	{ Text = "Неожиданный предмет\nв зоне упаковки", Short = "неожиданный предмет в зоне упаковки" },
	{ Text = "Вес товара не совпадает.\nОжидайте сотрудника", Short = "вес не совпадает" },
	{ Text = "Товар требует проверки\nсотрудником", Short = "проверка товара" },
}
local CARD_REASON = { Text = "Карта не прошла.\nОбратитесь к сотруднику", Short = "карта не прошла" }

-------------------------------------------------------------------------------
-- Экран, лампа, терминал
-------------------------------------------------------------------------------
local function short(text, n)
	if utf8.len(text) and utf8.len(text) > n then
		local cut = utf8.offset(text, n)
		return string.sub(text, 1, cut - 1) .. "…"
	end
	return text
end

local function setLamp(k, color)
	k.LampColor = color
	k.Lamp.Color = color
	k.LampLight.Color = color
	k.LampLight.Brightness = (color == GREY) and 0 or 0.6
end

local function screen(k, head, body, total, foot, headColor)
	local g = k.Gui
	g.Head.Text = head or ("КАССА " .. k.Index)
	g.Head.BackgroundColor3 = headColor or Color3.fromRGB(30, 150, 80)
	g.Body.Text = body or ""
	g.Total.Text = total or ""
	g.Foot.Text = foot or ""
end

local function idleScreen(k)
	if k.Closed then
		screen(k, "КАССА " .. k.Index, "Касса закрыта.\nВоспользуйтесь соседней кассой", "", "", GREY)
		setLamp(k, GREY)
		k.ReaderLabel.Text = ""
		return
	end
	screen(k, "КАССА " .. k.Index, "Добро пожаловать!\n\nОтсканируйте\nпервый товар", "", "Оплата картой")
	setLamp(k, GREEN)
	k.ReaderLabel.Text = ""
end

local function itemsScreen(k)
	local lines = {}
	local first = math.max(1, #k.Scanned - 4)
	for i = first, #k.Scanned do
		local p = k.Scanned[i]
		table.insert(lines, short(p.Name, 18) .. "  " .. p.Price)
	end
	screen(k, "КАССА " .. k.Index, table.concat(lines, "\n"), "ИТОГО " .. k.Total .. " руб.", "Отсканируйте следующий товар")
end

-------------------------------------------------------------------------------
-- Товары на полке кассы (3D-модели продуктов или простые коробочки)
-------------------------------------------------------------------------------
-- Деталь-товар по описанию product: 3D-модель продукта (или простая коробочка), стоит на точке spot
local function makeProductPart(product, spot)
	local def = product.Model and Models.Meshes[product.Model]
	if def and ModelKit.Has(product.Model) then
		local size = def.Size * Models.ProductScale
		local h = def.Pose == "Upright" and size.Z or size.Y
		local cf = CFrame.new(spot + Vector3.new(0, h / 2, 0)) * CFrame.Angles(0, math.rad(rng:NextNumber(-30, 30)), 0)
		if def.Pose == "Upright" then
			cf = cf * CFrame.Angles(math.rad(-90), 0, 0)
		end
		local part = ModelKit.Make(product.Model, map.Dynamic, cf, size, { Name = "Item", CanCollide = false, CastShadow = true })
		if part then
			return part
		end
	end
	local part = Instance.new("Part")
	part.Name = "Item"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.Size = Vector3.new(0.5, 0.7, 0.35)
	part.Color = product.Color or Color3.fromRGB(200, 200, 200)
	part.Material = Enum.Material.SmoothPlastic
	part.CFrame = CFrame.new(spot + Vector3.new(0, 0.35, 0))
	part.Parent = map.Dynamic
	return part
end

-- Товар для покупателя (из холодильника или если на полке ничего не нашлось): возле cf
function Checkout.MakeItem(product, cf)
	return makeProductPart(product, cf.Position)
end

local function makeItem(k, product, index)
	local spot = k.BasketSpot + Vector3.new(((index - 1) % 3 - 1) * 0.42, 0.12, (math.floor((index - 1) / 3) - 0.5) * 0.5)
	return makeProductPart(product, spot)
end

-- Пакет на стойке: видно, пока покупатель его не забрал
local function setBagVisible(k, on)
	for _, part in ipairs(k.BagParts or { k.Bag }) do
		part.Transparency = on and (part:GetAttribute("BaseTransparency") or 0.1) or 1
	end
end

-- Нажатие кнопки на экране кассы: кнопка темнеет и «вдавливается»
local function pressButton(k, button)
	if not button then
		return
	end
	local base = button.BackgroundColor3
	button.BackgroundColor3 = base:Lerp(Color3.new(0, 0, 0), 0.25)
	button.Size = button.Size - UDim2.fromScale(0.01, 0.006)
	S.Net.Sound("UiClick", k.ScanSpot + Vector3.new(0, 1.3, 0.8), 0.8)
	task.delay(0.25, function()
		button.BackgroundColor3 = base
		button.Size = button.Size + UDim2.fromScale(0.01, 0.006)
	end)
end

local function slide(part, target, seconds)
	if not part.Parent then
		return
	end
	local start = part.CFrame
	local steps = math.max(1, math.floor(seconds / 0.03))
	for i = 1, steps do
		if not part.Parent then
			return
		end
		local u = i / steps
		u = u * u * (3 - 2 * u)
		part.CFrame = start:Lerp(target, u)
		task.wait(0.03)
	end
end

local function clearItems(k)
	for _, part in ipairs(k.ItemParts or {}) do
		if part.Parent then
			part:Destroy()
		end
	end
	k.ItemParts = {}
	k.Scanned = {}
	k.Total = 0
end

-------------------------------------------------------------------------------
-- Помощь сотрудника
-------------------------------------------------------------------------------
local function startHelp(k, reason)
	k.State = "Help"
	k.Help = reason
	k.HelpSince = os.clock()
	k.HelpDone = false
	screen(k, "ОЖИДАЙТЕ СОТРУДНИКА", reason.Text, k.Total > 0 and ("ИТОГО " .. k.Total .. " руб.") or "", "Помощь уже идёт", Color3.fromRGB(230, 120, 20))
	k.HelpPrompt.ObjectText = "Касса " .. k.Index .. ": " .. reason.Short
	k.HelpPrompt.Enabled = true
	S.Net.Sound("KioskHelp", k.ScanSpot, 0.9)
	S.Net.Notify(nil, "Касса самообслуживания №" .. k.Index .. " зовёт сотрудника: " .. reason.Short, "task")
	-- лампа мигает, касса зовёт сигналом каждые несколько секунд
	task.spawn(function()
		local on = false
		local lastChime = os.clock()
		while k.State == "Help" and not k.HelpDone do
			on = not on
			setLamp(k, on and ORANGE or GREY)
			if os.clock() - lastChime > 5 then
				lastChime = os.clock()
				S.Net.Sound("KioskHelp", k.ScanSpot, 0.8)
			end
			task.wait(0.45)
		end
	end)
end

-- Охранник подтвердил на кассе
function Checkout.Help(k, player)
	if k.State ~= "Help" or k.HelpDone then
		return false
	end
	k.HelpDone = true
	k.HelpPrompt.Enabled = false
	S.Net.Sound("CardBeep", k.ScanSpot, 0.7)
	screen(k, "КАССА " .. k.Index, "Сотрудник подтвердил.\nПродолжайте", k.Total > 0 and ("ИТОГО " .. k.Total .. " руб.") or "", "", BLUE)
	setLamp(k, BLUE)
	S.Tasks.ProgressKind("help", 1)
	if player then
		S.Net.Notify(player, "Вы помогли покупателю на кассе №" .. k.Index, "done")
	end
	if k.Customer and k.Customer.Alive then
		S.Customers.Say(k.Customer, { "Thanks1", "Thanks5", "Thanks3" })
	end
	return true
end

-- Ждать сотрудника; true — помогли, false — покупатель ушёл
local function waitHelp(k, npc)
	local nagged = false
	while npc.Alive and not k.HelpDone do
		task.wait(0.3)
		local waited = os.clock() - k.HelpSince
		if not nagged and waited > 18 then
			nagged = true
			S.Customers.Say(npc, { "Help1", "Help2", "Help3" })
			NpcFactory.PlayAction(npc, "Look")
		end
		if waited > Config.HelpPatience then
			return false
		end
	end
	if k.State == "Help" then
		k.State = "Busy"
	end
	return k.HelpDone
end

-------------------------------------------------------------------------------
-- Покупка: всё делает покупатель (вызывает CustomerManager). Возвращает true, если оплатил
-------------------------------------------------------------------------------
function Checkout.Free()
	local list = {}
	for _, k in ipairs(kiosks) do
		if k.State == "Idle" and not k.Closed and not (hauntedActive and k.Index == HAUNTED) then
			table.insert(list, k)
		end
	end
	return Util.pick(list, rng)
end

function Checkout.Use(k, npc)
	k.State = "Busy"
	k.Customer = npc
	clearItems(k)
	setLamp(k, BLUE)
	screen(k, "КАССА " .. k.Index, "Выложите товары\nи отсканируйте их", "", "Оплата картой", Color3.fromRGB(30, 150, 80))
	NpcFactory.WalkTo(npc, k.CustomerSpot, 12)
	if not npc.Alive then
		Checkout.Finish(k)
		return false
	end
	NpcFactory.Face(npc, Vector3.new(k.X, 0, k.CustomerSpot.Z + 5))
	-- корзину на полку, товары из неё
	S.Net.Sound("BoxPick", k.BasketSpot, 0.35)
	local basket = NpcFactory.PlaceBasket(npc, k.BasketSpot, math.rad(90), map.Dynamic)
	if basket then
		table.insert(k.ItemParts, basket)
	end
	-- товары — те, что покупатель сам положил в корзину (если какого-то нет — создаём в корзине)
	local items = {}
	for i, product in ipairs(npc.Items) do
		local part = npc.ItemParts and npc.ItemParts[i]
		if not (part and part.Parent) then
			part = makeItem(k, product, i)
		end
		items[i] = part
		table.insert(k.ItemParts, part)
	end
	npc.ItemParts = {}
	task.wait(0.6)
	-- в каком месте покупки (если вообще) касса попросит помощи
	local helpAt = rng:NextNumber() < Config.KioskHelpChance and rng:NextInteger(1, #npc.Items) or nil
	for i, product in ipairs(npc.Items) do
		if not npc.Alive then
			break
		end
		local part = items[i]
		local scanned = false
		NpcFactory.PlayAction(npc, "Scan", function(mark)
			if mark == "Pick" then
				-- взял товар из корзины в руку
				if part and part.Parent then
					NpcFactory.HoldItem(npc, part)
				end
			elseif mark == "Beep" then
				-- товар в руке над сканером: писк, вспышка лазера, строка на экране
				k.Laser.Color = Color3.fromRGB(255, 255, 255)
				task.delay(0.12, function()
					k.Laser.Color = Color3.fromRGB(255, 40, 40)
				end)
				table.insert(k.Scanned, product)
				k.Total = k.Total + product.Price
				itemsScreen(k)
				scanned = true
			elseif mark == "Bag" then
				-- положил в пакет
				if part and part.Parent then
					local bag = k.BagSpot + Vector3.new(rng:NextNumber(-0.3, 0.3), 0.3 + math.floor((i - 1) / 4) * 0.25, rng:NextNumber(-0.45, 0.45))
					local rot = (part.CFrame - part.CFrame.Position) * CFrame.Angles(0, math.rad(rng:NextNumber(-25, 25)), 0)
					NpcFactory.Release(npc, part, nil, map.Dynamic)
					task.spawn(slide, part, CFrame.new(bag) * rot, 0.18)
				end
			end
		end, k.ScanSpot)
		task.wait(1.75)
		if not scanned then
			-- метка не пришла (покупатель удалён) — пробиваем без анимации
			table.insert(k.Scanned, product)
			k.Total = k.Total + product.Price
			itemsScreen(k)
		end
		if helpAt == i and npc.Alive then
			startHelp(k, Util.pick(HELP_REASONS, rng))
			if not waitHelp(k, npc) then
				S.Customers.Say(npc, { "Angry5", "Angry6", "Angry4" })
				S.Shift.AddStat("LeftAngry")
				Checkout.Finish(k)
				return false
			end
			task.wait(0.8)
		end
	end
	if not npc.Alive then
		Checkout.Finish(k)
		return false
	end
	-- оплата картой
	screen(k, "К ОПЛАТЕ", "Приложите карту\nк терминалу", "ИТОГО " .. k.Total .. " руб.", "Оплата картой")
	k.ReaderLabel.Text = k.Total .. "\nруб."
	task.wait(0.4)
	if not S.Power.IsOn() then
		screen(k, "КАССА " .. k.Index, "Нет связи с банком.\nОжидайте…", "ИТОГО " .. k.Total .. " руб.", "", GREY)
		local t0 = os.clock()
		while npc.Alive and not S.Power.IsOn() and os.clock() - t0 < 45 do
			task.wait(0.5)
		end
		if not S.Power.IsOn() then
			S.Customers.Say(npc, "NoPower")
			S.Shift.AddStat("LeftAngry")
			Checkout.Finish(k)
			return false
		end
	end
	-- нажимает «Оплатить» на экране
	NpcFactory.Face(npc, Vector3.new(k.Screen.Position.X, 0, k.Screen.Position.Z))
	NpcFactory.PlayAction(npc, "Pay", function(mark)
		if mark == "Tap" then
			pressButton(k, k.Gui.Pay)
			screen(k, "ОПЛАТА", "Приложите карту\nк терминалу справа", "ИТОГО " .. k.Total .. " руб.", "Бесконтактная оплата")
		end
	end, k.Screen.Position)
	task.wait(1.3)
	-- достаёт карту и прикладывает к терминалу
	local card = Instance.new("Part")
	card.Name = "Card"
	card.Size = Vector3.new(0.48, 0.03, 0.3)
	card.Color = Util.pick({ Color3.fromRGB(30, 90, 170), Color3.fromRGB(40, 40, 46), Color3.fromRGB(190, 160, 60), Color3.fromRGB(40, 140, 90) }, rng)
	card.Material = Enum.Material.SmoothPlastic
	card.Parent = map.Dynamic
	NpcFactory.HoldItem(npc, card, "RightHand", CFrame.new(0, -0.3, -0.1) * CFrame.Angles(math.rad(90), 0, 0))
	if k.TerminalSpot then
		NpcFactory.Face(npc, Vector3.new(k.TerminalSpot.X, 0, k.TerminalSpot.Z))
	end
	NpcFactory.PlayAction(npc, "Pay", nil, k.Reader.Position)
	task.wait(0.65)
	if rng:NextNumber() < Config.CardDeclineChance then
		S.Net.Sound("ScanError", k.Reader.Position, 0.6)
		startHelp(k, CARD_REASON)
		if not waitHelp(k, npc) then
			S.Customers.Say(npc, "Angry7")
			S.Shift.AddStat("LeftAngry")
			Checkout.Finish(k)
			return false
		end
		NpcFactory.PlayAction(npc, "Pay", nil, k.Reader.Position)
		task.wait(0.65)
	end
	S.Net.Sound("CardBeep", k.Reader.Position, 0.7)
	k.ReaderLabel.Text = "ОДОБРЕНО"
	screen(k, "ОПЛАЧЕНО", "Спасибо за покупку!\nНе забудьте пакет и чек", "ИТОГО " .. k.Total .. " руб.", "", Color3.fromRGB(30, 150, 80))
	setLamp(k, GREEN)
	task.wait(0.3)
	S.Net.Sound("Receipt", k.ReaderSpot or k.ScanSpot, 0.7)
	revenue = revenue + k.Total
	npc.Paid = true
	task.wait(0.5)
	if card.Parent then
		card:Destroy()
	end
	-- чек выползает из терминала
	local receipt = Instance.new("Part")
	receipt.Name = "Receipt"
	receipt.Size = Vector3.new(0.22, 0.01, 0.05)
	receipt.Color = Color3.fromRGB(246, 244, 236)
	receipt.Material = Enum.Material.SmoothPlastic
	receipt.Anchored = true
	receipt.CanCollide = false
	local rp = k.TerminalSpot or k.ScanSpot
	receipt.CFrame = CFrame.new(rp + Vector3.new(0, 0.32, 0.2))
	receipt.Parent = map.Dynamic
	table.insert(k.ItemParts, receipt)
	task.spawn(slide, receipt, receipt.CFrame * CFrame.new(0, 0, 0.3) * CFrame.Angles(math.rad(-25), 0, 0), 0.8)
	task.wait(1.0)
	-- забирает пакет с покупками и уходит с ним
	NpcFactory.Face(npc, Vector3.new(k.BagSpot.X, 0, k.BagSpot.Z))
	NpcFactory.PlayAction(npc, "Take", nil, k.BagSpot)
	task.wait(0.6)
	S.Net.Sound("BagPick", k.BagSpot, 0.7)
	for _, part in ipairs(k.ItemParts) do
		if part.Parent and part ~= basket then
			part:Destroy()
		end
	end
	k.ItemParts = {}
	if basket then
		task.delay(5, function()
			basket:Destroy()
		end)
	end
	setBagVisible(k, false)
	local carry = Instance.new("Part")
	carry.Name = "ShoppingBag"
	carry.Size = Vector3.new(0.9, 1.1, 0.45)
	carry.Color = Color3.fromRGB(240, 240, 234)
	carry.Material = Enum.Material.SmoothPlastic
	carry.Transparency = 0.08
	carry.Parent = map.Dynamic
	NpcFactory.HoldItem(npc, carry, "RightHand", CFrame.new(0, -0.75, 0))
	task.delay(4, function()
		setBagVisible(k, true)
	end)
	Checkout.Finish(k)
	return true
end

-- Покупатель ушёл от кассы
function Checkout.Finish(k)
	if k.Customer and not k.Customer.Paid then
		-- неоплаченные товары остаются на полке и пропадают через несколько секунд
		local parts = k.ItemParts
		task.delay(6, function()
			for _, part in ipairs(parts or {}) do
				if part.Parent then
					part:Destroy()
				end
			end
		end)
		k.ItemParts = {}
	end
	k.Customer = nil
	k.HelpDone = true
	k.HelpPrompt.Enabled = false
	k.Scanned = {}
	k.Total = 0
	task.delay(2.5, function()
		if not k.Customer then
			k.State = "Idle"
			if not (hauntedActive and k.Index == HAUNTED) then
				idleScreen(k)
			end
		end
	end)
end

-------------------------------------------------------------------------------
function Checkout.Init(m, services, npcFactory)
	map, S, NpcFactory = m, services, npcFactory
	kiosks = map.Kiosks
	for _, k in ipairs(kiosks) do
		k.State = "Idle"
		k.ItemParts = {}
		k.Scanned = {}
		k.Total = 0
		k.Closed = false
		local help = Util.prompt(k.Screen, "Помочь покупателю", "Касса " .. k.Index, 1.2, 9)
		help.Enabled = false
		help.RequiresLineOfSight = false
		k.HelpPrompt = help
		help.Triggered:Connect(function(player)
			Checkout.Help(k, player)
		end)
		local close = Util.prompt(k.Screen, "Отключить кассу", "Касса " .. k.Index, 1.5, 8)
		close.Enabled = false
		k.ClosePrompt = close
		close.Triggered:Connect(function()
			if k.Closed or not S.Tasks.IsActive("closelanes") then
				return
			end
			if k.Customer then
				S.Net.Notify(nil, "На кассе №" .. k.Index .. " ещё покупатель", "warn")
				return
			end
			k.Closed = true
			close.Enabled = false
			idleScreen(k)
			S.Net.Sound("PowerDown", k.ScanSpot, 0.3)
			S.Tasks.ProgressKind("closelanes", 1)
		end)
		if k.Index == HAUNTED then
			local off = Util.prompt(k.Screen, "Выключить кассу", "Касса " .. k.Index, 2, 8)
			off.Enabled = false
			k.OffPrompt = off
			off.Triggered:Connect(function()
				Checkout.Lane4(false)
				S.Tasks.ProgressKind("register4", 1)
			end)
		end
		idleScreen(k)
	end
end

-------------------------------------------------------------------------------
-- Аномалия: касса самообслуживания №6 включилась сама и «пробивает» товары никому
-------------------------------------------------------------------------------
function Checkout.Lane4(active)
	local k = kiosks[HAUNTED]
	hauntedActive = active
	k.OffPrompt.Enabled = active
	if active then
		k.State = "Haunted"
		setLamp(k, RED)
		screen(k, "КАССА 0", "Покупатель\nожидает на кассе.\n\nОтсканируйте\nследующий товар", "ИТОГО 0 руб.", "14.11.2003  03:47", Color3.fromRGB(120, 10, 10))
		task.spawn(function()
			while hauntedActive do
				S.Net.Sound("Scan", k.ScanSpot, 0.8)
				k.Laser.Color = Color3.fromRGB(255, 255, 255)
				task.wait(0.1)
				k.Laser.Color = Color3.fromRGB(255, 40, 40)
				task.wait(rng:NextNumber(1.5, 4))
			end
		end)
	else
		k.State = "Idle"
		idleScreen(k)
	end
end

function Checkout.IsLane4Active()
	return hauntedActive
end

-- Поздние ночи: на всех свободных кассах на seconds секунд загорается красная надпись text
-- (у каждой кассы может быть своя, если text — список). Лампы краснеют, касса пищит.
local creepyToken = 0
function Checkout.Creepy(seconds, text)
	creepyToken = creepyToken + 1
	local token = creepyToken
	local shown = {}
	for _, k in ipairs(kiosks) do
		if k.State == "Idle" and not k.Customer then
			local line = type(text) == "table" and text[(k.Index - 1) % #text + 1] or text
			k.Creepy = true
			setLamp(k, RED)
			screen(k, "КАССА 0", line, "", "14.11.2003  03:47", Color3.fromRGB(120, 10, 10))
			table.insert(shown, k)
		end
	end
	if #shown > 0 then
		S.Net.Sound("ScanError", shown[1].ScanSpot, 0.6)
		S.Net.Sound("ScanError", shown[#shown].ScanSpot, 0.6)
	end
	task.delay(seconds or 8, function()
		if token ~= creepyToken then
			return
		end
		for _, k in ipairs(shown) do
			k.Creepy = nil
			if k.State == "Idle" and not k.Customer then
				idleScreen(k)
			end
		end
	end)
	return #shown
end

-------------------------------------------------------------------------------
function Checkout.SetupTask(t)
	if t.Kind == "closelanes" then
		for _, k in ipairs(kiosks) do
			if k.Index <= t.Count and not k.Closed then
				k.ClosePrompt.Enabled = true
			end
		end
	end
end

function Checkout.OnTaskDone(t)
	if t.Kind == "closelanes" then
		for _, k in ipairs(kiosks) do
			k.ClosePrompt.Enabled = false
		end
	end
end

function Checkout.Revenue()
	return revenue
end

function Checkout.Kiosks()
	return kiosks
end

function Checkout.Reset()
	revenue = 0
	creepyToken = creepyToken + 1
	for _, k in ipairs(kiosks) do
		clearItems(k)
		k.Customer = nil
		k.Closed = false
		k.State = "Idle"
		k.HelpDone = true
		k.HelpPrompt.Enabled = false
		k.ClosePrompt.Enabled = false
		setBagVisible(k, true)
		idleScreen(k)
	end
	Checkout.Lane4(false)
end

return Checkout
