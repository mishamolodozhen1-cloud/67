-- Checkout: кассы. Покупатель выкладывает товары на ленту, игрок пробивает каждый товар
-- (подсказка «Пробить» на товаре), затем принимает оплату на терминале.
-- Здесь же задания «Закрыть кассы» и аномалия «касса №4 включилась сама».
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Products = require(Shared:WaitForChild("Products"))
local Util = require(Shared:WaitForChild("Util"))

local Checkout = {}

local map, S
local rng = Random.new()
local lanes
local lane4Active = false
local revenue = 0

local CYLINDER_SHAPES = { Bottle = true, Can = true, Jar = true, Cup = true }
local GREEN = Color3.fromRGB(40, 200, 90)
local GREY = Color3.fromRGB(70, 70, 72)
local RED = Color3.fromRGB(220, 30, 30)

-------------------------------------------------------------------------------
-- Табло кассы
-------------------------------------------------------------------------------
-- Обрезать строку до n символов (кириллица занимает 2 байта, поэтому через utf8)
local function short(text, n)
	local len = utf8.len(text) or #text
	if len <= n then
		return text
	end
	return string.sub(text, 1, utf8.offset(text, n) - 1) .. "…"
end

local function refreshScreens(lane)
	if lane.Closed then
		lane.CashierLabel.Text = "КАССА " .. lane.Index .. "\nЗАКРЫТА"
		lane.CustomerLabel.Text = "Касса закрыта"
		lane.TerminalLabel.Text = ""
		return
	end
	if not lane.Open then
		return
	end
	local lines = { "КАССА " .. lane.Index }
	if lane.Customer then
		local first = math.max(1, #lane.Scanned - 4)
		for i = first, #lane.Scanned do
			local item = lane.Scanned[i]
			table.insert(lines, short(item.Name, 16) .. "  " .. item.Price .. " ₽")
		end
		table.insert(lines, string.format("ИТОГО: %d ₽", lane.Total))
		local last = lane.Scanned[#lane.Scanned]
		lane.CustomerLabel.Text = last and (last.Name .. "\n" .. last.Price .. " ₽\nИтого: " .. lane.Total .. " ₽") or "Добро пожаловать!"
	else
		table.insert(lines, "Свободна")
		lane.CustomerLabel.Text = "Добро пожаловать!"
	end
	lane.CashierLabel.Text = table.concat(lines, "\n")
end

local function setNumberSign(lane, color)
	lane.NumberSign.Color = color
end

-------------------------------------------------------------------------------
-- Товар на ленте
-------------------------------------------------------------------------------
local function makeItem(lane, product, index)
	local size = Products.ShapeSize[product.Shape] or Vector3.new(0.8, 0.8, 0.8)
	local z = lane.ItemZ[math.min(index, #lane.ItemZ)]
	local base = Vector3.new(lane.X + rng:NextNumber(-0.35, 0.35), 3.12, z)
	local part = Instance.new("Part")
	part.Name = "Item"
	part.Anchored = true
	part.CanCollide = false
	part.Color = product.Color
	part.Material = (product.Shape == "Bag") and Enum.Material.Foil or Enum.Material.SmoothPlastic
	if CYLINDER_SHAPES[product.Shape] then
		part.Shape = Enum.PartType.Cylinder
		part.Size = Vector3.new(size.Y, size.X, size.Z)
		part.CFrame = CFrame.new(base + Vector3.new(0, size.Y / 2, 0)) * CFrame.Angles(0, 0, math.rad(90))
	else
		part.Size = size
		part.CFrame = CFrame.new(base + Vector3.new(0, size.Y / 2, 0)) * CFrame.Angles(0, math.rad(rng:NextNumber(-15, 15)), 0)
	end
	-- полоска-этикетка другого цвета
	local label = Instance.new("Part")
	label.Name = "Label"
	label.Anchored = true
	label.CanCollide = false
	label.CanQuery = false
	label.Color = product.Accent
	label.Material = Enum.Material.SmoothPlastic
	if CYLINDER_SHAPES[product.Shape] then
		label.Shape = Enum.PartType.Cylinder
		label.Size = Vector3.new(size.Y * 0.35, size.X + 0.02, size.Z + 0.02)
		label.CFrame = part.CFrame
	else
		label.Size = Vector3.new(size.X + 0.02, size.Y * 0.3, size.Z + 0.02)
		label.CFrame = part.CFrame
	end
	label.Parent = part
	if product.Shape == "Bottle" then
		local cap = Instance.new("Part")
		cap.Name = "Cap"
		cap.Anchored = true
		cap.CanCollide = false
		cap.Shape = Enum.PartType.Cylinder
		cap.Size = Vector3.new(0.18, 0.24, 0.24)
		cap.Color = product.Accent
		cap.CFrame = CFrame.new(base + Vector3.new(0, size.Y + 0.09, 0)) * CFrame.Angles(0, 0, math.rad(90))
		cap.Parent = part
	elseif product.Shape == "Fruit" then
		part.Material = Enum.Material.Plastic
		part.Transparency = 0.35
		part.Color = Color3.fromRGB(240, 240, 235)
		for k = 1, 3 do
			local apple = Instance.new("Part")
			apple.Name = "Apple"
			apple.Anchored = true
			apple.CanCollide = false
			apple.Shape = Enum.PartType.Ball
			apple.Size = Vector3.new(0.38, 0.38, 0.38)
			apple.Color = product.Color
			apple.CFrame = part.CFrame * CFrame.new((k - 2) * 0.28, -0.15, 0)
			apple.Parent = part
		end
	end
	part.Parent = map.Dynamic
	return part
end

-- Сдвинуть товар (вместе с деталями-детьми) в новую точку
local function slide(part, target, seconds)
	local start = part.CFrame
	local offsets = {}
	for _, c in ipairs(part:GetChildren()) do
		if c:IsA("BasePart") then
			offsets[c] = start:ToObjectSpace(c.CFrame)
		end
	end
	local steps = math.max(1, math.floor(seconds / 0.03))
	for i = 1, steps do
		if not part.Parent then
			return
		end
		local cf = start:Lerp(target, i / steps)
		part.CFrame = cf
		for c, off in pairs(offsets) do
			if c.Parent then
				c.CFrame = cf * off
			end
		end
		task.wait(0.03)
	end
end

local function clearItems(lane)
	for _, it in ipairs(lane.Items) do
		if it.Part and it.Part.Parent then
			it.Part:Destroy()
		end
	end
	lane.Items = {}
	lane.Scanned = {}
	lane.Total = 0
	lane.PayPrompt.Enabled = false
	lane.TerminalLabel.Text = ""
end

local function allScanned(lane)
	for _, it in ipairs(lane.Items) do
		if not it.Scanned then
			return false
		end
	end
	return #lane.Items > 0
end

local function scanItem(lane, it, player)
	if it.Scanned or lane.Customer ~= it.Customer then
		return
	end
	if not S.Power.IsOn() then
		S.Net.Sound("ScanError", lane.ScanSpot, 0.6)
		S.Net.Notify(player, "Касса не работает: нет электричества", "warn")
		return
	end
	if not it.Retried and rng:NextNumber() < Config.ScanErrorChance then
		it.Retried = true
		S.Net.Sound("ScanError", lane.ScanSpot, 0.7)
		it.Prompt.ActionText = "Пробить ещё раз"
		S.Net.Notify(player, "Штрихкод не считался — пробейте ещё раз", "warn")
		return
	end
	it.Scanned = true
	it.Prompt:Destroy()
	S.Net.Sound("Scan", lane.ScanSpot, 0.7)
	table.insert(lane.Scanned, it.Product)
	lane.Total = lane.Total + it.Product.Price
	refreshScreens(lane)
	local part = it.Part
	task.spawn(function()
		local over = CFrame.new(lane.ScanSpot + Vector3.new(0, 0.2, 0)) * (part.CFrame - part.CFrame.Position)
		slide(part, over, 0.25)
		local bag = lane.BagSpot + Vector3.new(rng:NextNumber(-0.6, 0.6), part.Size.Y / 2 + 0.05, rng:NextNumber(-0.8, 0.8))
		slide(part, CFrame.new(bag) * (part.CFrame - part.CFrame.Position), 0.3)
	end)
	if allScanned(lane) then
		lane.TerminalLabel.Text = "К ОПЛАТЕ\n" .. lane.Total .. " ₽"
		lane.PayPrompt.ObjectText = "К оплате " .. lane.Total .. " ₽"
		lane.PayPrompt.Enabled = true
		if lane.Customer and lane.Customer.Alive then
			S.Customers.Say(lane.Customer, rng:NextNumber() < 0.5 and "Картой, пожалуйста." or "Пакет не нужен, спасибо.")
		end
	end
end

-- Принять оплату на терминале
function Checkout.Pay(lane, player)
	local c = lane.Customer
	if not (c and allScanned(lane)) or c.Paid then
		return false
	end
	if not S.Power.IsOn() then
		S.Net.Notify(player, "Терминал не работает: нет электричества", "warn")
		return false
	end
	c.Paid = true
	lane.PayPrompt.Enabled = false
	revenue = revenue + lane.Total
	S.Net.Sound("Payment", lane.Terminal.Position, 0.7)
	lane.TerminalLabel.Text = "ОПЛАЧЕНО ✓"
	lane.CustomerLabel.Text = c.Weird and "СПАСИБО, ЧТО ОСТАЛИСЬ" or "Спасибо за покупку!"
	if player then
		S.Net.Notify(player, "Покупатель обслужен: " .. lane.Total .. " ₽", "info")
	end
	return true
end

-- Пробить товар (вызывается подсказкой «Пробить» на товаре)
Checkout.Scan = scanItem

-------------------------------------------------------------------------------
function Checkout.Init(m, services)
	map, S = m, services
	lanes = map.Lanes
	for _, lane in ipairs(lanes) do
		lane.Queue = {}
		lane.Items = {}
		lane.Scanned = {}
		lane.Total = 0
		lane.Closed = false
		local pay = Util.prompt(lane.Terminal, "Принять оплату", "Терминал", 0.3, 8)
		pay.Enabled = false
		lane.PayPrompt = pay
		pay.Triggered:Connect(function(player)
			Checkout.Pay(lane, player)
		end)
		local close = Util.prompt(lane.Monitor, "Закрыть кассу", "Касса №" .. lane.Index, 1.5, 8)
		close.Enabled = false
		lane.ClosePrompt = close
		close.Triggered:Connect(function()
			if lane.Closed or not S.Tasks.IsActive("closelanes") then
				return
			end
			if lane.Customer then
				S.Net.Notify(nil, "Сначала обслужите покупателя на кассе №" .. lane.Index, "warn")
				return
			end
			lane.Closed = true
			close.Enabled = false
			setNumberSign(lane, GREY)
			refreshScreens(lane)
			S.Net.Sound("PowerDown", lane.Monitor.Position, 0.3)
			S.Tasks.ProgressKind("closelanes", 1)
		end)
		if lane.Index == 4 then
			local off = Util.prompt(lane.Monitor, "Выключить кассу", "Касса №4", 2, 8)
			off.Enabled = false
			lane.OffPrompt = off
			off.Triggered:Connect(function()
				Checkout.Lane4(false)
				S.Tasks.ProgressKind("register4", 1)
			end)
		end
	end
end

-- Сколько игроков стоит за кассой (в зоне кассира)
local function staffed(lane)
	local z = lane.CashierZone
	for _, p in ipairs(Players:GetPlayers()) do
		local root = Util.rootOf(p)
		if root then
			local pos = root.Position
			if pos.X >= z[1] and pos.X <= z[2] and pos.Z >= z[3] and pos.Z <= z[4] then
				return true
			end
		end
	end
	return false
end

-- Выбрать кассу: сначала те, где стоит кассир, потом касса №1; при равенстве — короче очередь
function Checkout.ChooseLane()
	local best, bestScore = nil, math.huge
	for _, lane in ipairs(lanes) do
		if lane.Open and not lane.Closed then
			local score = #lane.Queue * 10
			if staffed(lane) then
				score = score - 100
			elseif lane.Index ~= 1 then
				score = score + 25
			end
			if score < bestScore then
				best, bestScore = lane, score
			end
		end
	end
	return best
end

function Checkout.Join(lane, customer)
	table.insert(lane.Queue, customer)
	customer.Lane = lane
end

function Checkout.Position(customer)
	local lane = customer.Lane
	if not lane then
		return nil
	end
	return table.find(lane.Queue, customer)
end

function Checkout.Leave(customer)
	local lane = customer.Lane
	if not lane then
		return
	end
	local i = table.find(lane.Queue, customer)
	if i then
		table.remove(lane.Queue, i)
	end
	if lane.Customer == customer then
		local items = lane.Items
		lane.Customer = nil
		lane.PayPrompt.Enabled = false
		lane.Items = {}
		lane.Scanned = {}
		lane.Total = 0
		-- оплаченные товары покупатель забирает, неоплаченные остаются и исчезают
		task.delay(customer.Paid and 0.6 or 2, function()
			for _, it in ipairs(items) do
				if it.Part and it.Part.Parent then
					it.Part:Destroy()
				end
			end
			if not lane.Customer then
				lane.TerminalLabel.Text = ""
				refreshScreens(lane)
			end
		end)
	end
	customer.Lane = nil
end

-- Покупатель подошёл к кассе: товары на ленту
function Checkout.BeginService(lane, customer)
	clearItems(lane)
	lane.Customer = customer
	customer.Paid = false
	for i, product in ipairs(customer.Items) do
		local part = makeItem(lane, product, i)
		local it = { Part = part, Product = product, Customer = customer }
		local prompt = Util.prompt(part, "Пробить", product.Name .. " · " .. product.Price .. " ₽", 0, 8)
		it.Prompt = prompt
		prompt.Triggered:Connect(function(player)
			scanItem(lane, it, player)
		end)
		table.insert(lane.Items, it)
	end
	lane.TerminalLabel.Text = "Ожидание…"
	refreshScreens(lane)
end

-------------------------------------------------------------------------------
-- Аномалия: касса №4 включилась сама
-------------------------------------------------------------------------------
function Checkout.Lane4(active)
	local lane = lanes[4]
	lane4Active = active
	lane.OffPrompt.Enabled = active
	for _, gui in ipairs(lane.NumberSign:GetChildren()) do
		local label = gui:IsA("SurfaceGui") and gui:FindFirstChild("Text")
		if label then
			label.Text = active and "0" or "4"
		end
	end
	if active then
		setNumberSign(lane, RED)
		lane.CashierLabel.Text = "КАССА 0\nОЖИДАНИЕ ПОКУПАТЕЛЯ…"
		lane.CashierLabel.TextColor3 = Color3.fromRGB(255, 80, 70)
		lane.CustomerLabel.Text = "ПОДОЙДИТЕ К КАССЕ"
		task.spawn(function()
			while lane4Active do
				S.Net.Sound("Scan", lane.ScanSpot, 0.8)
				task.wait(rng:NextNumber(1.5, 4))
			end
		end)
	else
		setNumberSign(lane, GREY)
		lane.CashierLabel.Text = "КАССА НЕ РАБОТАЕТ"
		lane.CashierLabel.TextColor3 = Color3.fromRGB(120, 220, 255)
		lane.CustomerLabel.Text = ""
	end
end

function Checkout.IsLane4Active()
	return lane4Active
end

-------------------------------------------------------------------------------
function Checkout.SetupTask(t)
	if t.Kind == "closelanes" then
		for _, lane in ipairs(lanes) do
			if lane.Open and not lane.Closed then
				lane.ClosePrompt.Enabled = true
			end
		end
	end
end

function Checkout.OnTaskDone(t)
	if t.Kind == "closelanes" then
		for _, lane in ipairs(lanes) do
			lane.ClosePrompt.Enabled = false
		end
	end
end

function Checkout.Revenue()
	return revenue
end

function Checkout.Reset()
	revenue = 0
	for _, lane in ipairs(lanes) do
		clearItems(lane)
		lane.Queue = {}
		lane.Customer = nil
		lane.Closed = false
		lane.ClosePrompt.Enabled = false
		if lane.Open then
			setNumberSign(lane, GREEN)
		end
		refreshScreens(lane)
	end
	Checkout.Lane4(false)
end

return Checkout
