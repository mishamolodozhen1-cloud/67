-- StoreSystems: работа в магазине, кроме касс.
--   • переноска предметов (коробки, швабра, мешок мусора, поставка) — атрибут игрока Carry
--   • выкладка товара на пустые полки (restock)
--   • лужи и швабра (spill)
--   • проверка и ремонт холодильников (fridgecheck, fridgefix), температура в холодильной камере (coldtemp)
--   • мусор (trash), поставка у заднего выхода (delivery), журнал смены (shiftlog), запереть задний выход (lockback)
--   • посетить помещение (visit), поднять товар с пола (pickup)
--   • табельные часы, пульт видеонаблюдения, батарейки для фонарика, телефон в кабинете
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Util = require(Shared:WaitForChild("Util"))
local Products = require(Shared:WaitForChild("Products"))
local Texts = require(Shared:WaitForChild("Texts"))

local StoreSystems = {}

local map, S
local rng = Random.new()
local carrying = {} -- player -> { Kind, Category, Part }
local spills = {} -- puddle part -> { TaskId }
local floorItems = {}
local deliveryProp, deliveryPrompt
local phoneRinging = false
local cctvSeen = {} -- taskId -> { [index] = true }

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

-------------------------------------------------------------------------------
-- Где находится точка (для подсказок в списке заданий)
-------------------------------------------------------------------------------
function StoreSystems.RoomAt(pos)
	for _, r in ipairs(map.Rooms) do
		if pos.X >= r.Min.X and pos.X <= r.Max.X and pos.Z >= r.Min.Z and pos.Z <= r.Max.Z and pos.Y >= r.Min.Y and pos.Y <= r.Max.Y then
			return r.Name
		end
	end
	return nil
end

local AISLE_X = { -57.5, -42.5, -27.5, -12.5, 2.5, 17.5, 32 }
local function describe(pos)
	if pos.Z < -1 then
		return "у холодильников"
	elseif pos.Z > 21 then
		return "у касс"
	end
	local best, bestD = 1, math.huge
	for i, x in ipairs(AISLE_X) do
		local d = math.abs(pos.X - x)
		if d < bestD then
			best, bestD = i, d
		end
	end
	return "проход " .. best
end

-------------------------------------------------------------------------------
-- Переноска предметов
-------------------------------------------------------------------------------
local CARRY_NAMES = {
	Box = "Коробка",
	Mop = "Швабра",
	Trash = "Мешок с мусором",
	Delivery = "Поставка",
	Parcel = "Заказ",
}

local function makeCarryPart(kind, category)
	local part = Instance.new("Part")
	part.Name = "Carried" .. kind
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.CastShadow = true
	if kind == "Box" or kind == "Delivery" or kind == "Parcel" then
		part.Size = kind == "Box" and Vector3.new(1.8, 1.3, 1.3) or (kind == "Parcel" and Vector3.new(1.3, 0.8, 1.1) or Vector3.new(2.2, 1.6, 1.6))
		part.Material = Enum.Material.Cardboard
		part.Color = rgb(176, 136, 90)
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Front
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 40
		gui.MaxDistance = 40
		gui.Parent = part
		local t = Instance.new("TextLabel")
		t.Size = UDim2.fromScale(1, 1)
		t.BackgroundTransparency = 1
		t.TextScaled = true
		t.Font = Enum.Font.GothamBold
		t.TextColor3 = rgb(60, 40, 20)
		t.Text = kind == "Box" and Products.Categories[category].Name or (kind == "Parcel" and ("№" .. tostring(category)) or "ПОСТАВКА")
		t.Parent = gui
	elseif kind == "Mop" then
		part.Size = Vector3.new(0.18, 5.6, 0.18)
		part.Color = rgb(80, 120, 200)
		part.Material = Enum.Material.SmoothPlastic
		local head = Instance.new("Part")
		head.Name = "MopHead"
		head.Size = Vector3.new(1.4, 0.35, 0.6)
		head.Color = rgb(220, 220, 210)
		head.Material = Enum.Material.Fabric
		head.CanCollide = false
		head.CanQuery = false
		head.Massless = true
		head.CFrame = part.CFrame * CFrame.new(0, -2.9, 0)
		local w = Instance.new("WeldConstraint")
		w.Part0 = part
		w.Part1 = head
		w.Parent = head
		head.Parent = part
	else
		part.Shape = Enum.PartType.Ball
		part.Size = Vector3.new(1.7, 1.7, 1.7)
		part.Color = rgb(24, 24, 26)
		part.Material = Enum.Material.Plastic
	end
	return part
end

function StoreSystems.Carrying(player)
	return carrying[player]
end

local function returnItem(player, c)
	if c.Kind == "Parcel" and S.Security then
		-- коробка заказа возвращается в свою ячейку
		S.Security.ReturnParcel(tostring(c.Category))
	end
	if c.Kind == "Delivery" and deliveryProp then
		-- поставка возвращается к заднему выходу
		deliveryProp.Transparency = 0
		deliveryPrompt.Enabled = true
	end
end

-- Убрать предмет из рук. used = true, если предмет израсходован (выложен, выброшен…)
function StoreSystems.ClearCarry(player, used)
	local c = carrying[player]
	carrying[player] = nil
	if player.Parent then
		player:SetAttribute("Carry", "")
	end
	if c then
		if c.Part then
			c.Part:Destroy()
		end
		if not used then
			returnItem(player, c)
		end
	end
end

function StoreSystems.GiveCarry(player, kind, category)
	local char = player.Character
	local anchor = char and (char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso"))
	local hand = char and (char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm"))
	if not (anchor and hand) then
		return false
	end
	local previous = carrying[player]
	if previous then
		StoreSystems.ClearCarry(player, false)
	end
	local part = makeCarryPart(kind, category)
	if kind == "Mop" then
		part.CFrame = hand.CFrame * CFrame.new(0, 0.4, -0.2) * CFrame.Angles(math.rad(-15), 0, 0)
	elseif kind == "Trash" then
		part.CFrame = hand.CFrame * CFrame.new(0, -1.1, 0)
	else
		part.CFrame = anchor.CFrame * CFrame.new(0, -0.4, -1.4)
	end
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = (kind == "Mop" or kind == "Trash") and hand or anchor
	weld.Part1 = part
	weld.Parent = part
	part.Parent = char
	carrying[player] = { Kind = kind, Category = category, Part = part }
	player:SetAttribute("Carry", kind .. (category and (":" .. category) or ""))
	S.Net.Sound("BoxPick", anchor.Position, 0.6)
	return true
end

local function needCarry(player, kind, category, hint)
	local c = carrying[player]
	if c and c.Kind == kind and (category == nil or c.Category == category) then
		return true
	end
	S.Net.Notify(player, hint, "warn")
	return false
end

-------------------------------------------------------------------------------
-- Выкладка товара
-------------------------------------------------------------------------------
-- Показать или убрать товар с полки (пустая полка — задание «выложить товар»)
local function setFacingVisible(f, visible)
	for _, p in ipairs(f.Parts or {}) do
		p.Transparency = visible and 0 or 1
		p.CanCollide = visible
		p.CanQuery = visible
		for _, d in ipairs(p:GetChildren()) do
			if d:IsA("Decal") then
				d.Transparency = visible and 0 or 1
			end
		end
	end
	f.Empty = not visible
end

local function restockDetail(t)
	local parts = {}
	for _, f in ipairs(map.Facings) do
		if f.Empty and f.TaskId == t.Id then
			table.insert(parts, string.format("ряд %d — %s", f.Gondola, Products.Categories[f.Category].Name))
		end
	end
	S.Tasks.SetDetail(t, table.concat(parts, "; "))
end

local function emptyFacings(t)
	local candidates = {}
	for _, f in ipairs(map.Facings) do
		if not f.Empty then
			table.insert(candidates, f)
		end
	end
	Util.shuffle(candidates, rng)
	local n = math.min(t.Count, #candidates)
	t.Count = math.max(1, n)
	for i = 1, n do
		local f = candidates[i]
		setFacingVisible(f, false)
		f.TaskId = t.Id
		f.Prompt.ObjectText = f.Label
		f.Prompt.Enabled = true
	end
	restockDetail(t)
end

-------------------------------------------------------------------------------
-- Лужи
-------------------------------------------------------------------------------
local SPILL_TYPES = {
	{ "Пролитое молоко", rgb(236, 236, 228) },
	{ "Пролитая газировка", rgb(110, 60, 30) },
	{ "Лужа воды", rgb(150, 190, 210) },
	{ "Разбитый йогурт", rgb(236, 170, 190) },
}

local function wetFloorSign(pos)
	local m = Instance.new("Model")
	m.Name = "WetFloorSign"
	for k = -1, 1, 2 do
		local p = Instance.new("Part")
		p.Size = Vector3.new(1.6, 2.6, 0.1)
		p.Color = rgb(250, 210, 30)
		p.Anchored = true
		p.CanCollide = false
		p.CFrame = CFrame.new(pos + Vector3.new(0, 1.25, 0)) * CFrame.Angles(math.rad(12 * k), 0, 0) * CFrame.new(0, 0, 0.25 * k)
		p.Parent = m
		local gui = Instance.new("SurfaceGui")
		gui.Face = k < 0 and Enum.NormalId.Front or Enum.NormalId.Back
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 50
		gui.MaxDistance = 50
		gui.Parent = p
		local t = Instance.new("TextLabel")
		t.Size = UDim2.fromScale(1, 1)
		t.BackgroundTransparency = 1
		t.TextScaled = true
		t.Font = Enum.Font.GothamBlack
		t.TextColor3 = rgb(20, 20, 20)
		t.Text = "ОСТОРОЖНО!\nМОКРЫЙ ПОЛ"
		t.Parent = gui
	end
	m.Parent = map.Dynamic
	task.delay(40, function()
		m:Destroy()
	end)
end

local function spawnSpill(t, pos)
	local kind = SPILL_TYPES[rng:NextInteger(1, #SPILL_TYPES)]
	local main
	for k = 1, 3 do
		local d = rng:NextNumber(2.2, 4.4) / k + 1
		local p = Instance.new("Part")
		p.Name = k == 1 and "Spill" or "SpillEdge"
		p.Shape = Enum.PartType.Cylinder
		p.Size = Vector3.new(0.04, d, d * rng:NextNumber(0.9, 1.1))
		p.Anchored = true
		p.CanCollide = false
		p.CastShadow = false
		p.Material = Enum.Material.Glass
		p.Reflectance = 0.2
		p.Transparency = 0.15
		p.Color = kind[2]
		local off = k == 1 and Vector3.new(0, 0, 0) or Vector3.new(rng:NextNumber(-1.2, 1.2), 0, rng:NextNumber(-1.2, 1.2))
		p.CFrame = CFrame.new(pos + off + Vector3.new(0, 0.03 + k * 0.002, 0)) * CFrame.Angles(0, 0, math.rad(90))
		if main then
			p.Parent = main
		else
			main = p
		end
	end
	main.Parent = map.Dynamic
	local prompt = Util.prompt(main, "Вымыть пол", kind[1], 2.5, 7)
	spills[main] = { TaskId = t.Id, Name = kind[1] }
	prompt.Triggered:Connect(function(player)
		if not spills[main] then
			return
		end
		if not needCarry(player, "Mop", nil, "Нужна швабра — она в комнате персонала, у ведра") then
			return
		end
		local info = spills[main]
		spills[main] = nil
		S.Net.Sound("Mop", main.Position, 0.8)
		wetFloorSign(main.Position + Vector3.new(2.5, 0, 0))
		main:Destroy()
		S.Tasks.Progress(info.TaskId, 1)
	end)
	return main
end

local function spawnSpills(t)
	local spots = Util.shuffle(table.clone(map.SpillSpots), rng)
	local where = {}
	for i = 1, t.Count do
		local pos = spots[i]
		if pos then
			spawnSpill(t, pos)
			table.insert(where, describe(pos))
		end
	end
	S.Tasks.SetDetail(t, table.concat(where, "; "))
end

-------------------------------------------------------------------------------
-- Холодильники
-------------------------------------------------------------------------------
local function fridgeTemp(f)
	if f.Broken then
		return "+14 °C", rgb(255, 70, 50)
	end
	return string.format("+%d °C", f.Temp), rgb(80, 255, 120)
end

local function updateFridge(f)
	local text, color = fridgeTemp(f)
	f.ThermoLabel.Text = text
	f.ThermoLabel.TextColor3 = color
	f.Body:SetAttribute("Broken", f.Broken == true)
end

function StoreSystems.BreakFridge()
	local ok = {}
	for _, f in ipairs(map.Fridges) do
		if not f.Broken then
			table.insert(ok, f)
		end
	end
	local f = Util.pick(ok, rng)
	if not f then
		return nil
	end
	f.Broken = true
	updateFridge(f)
	S.Net.Sound("PowerDown", f.Body.Position + Vector3.new(0, 4, 2), 0.5)
	local t = S.Tasks.Add({
		Id = "fridgefix_" .. f.Index .. "_" .. math.floor(os.clock()),
		Kind = "fridgefix",
		Text = "Перезапустить холодильник №" .. f.Index,
		Room = "Торговый зал, у задней стены",
		Count = 1,
		Data = { Fridge = f.Index },
	})
	f.FixTask = t.Id
	f.FixPrompt.Enabled = true
	return f
end

-------------------------------------------------------------------------------
-- Поставка у заднего выхода
-------------------------------------------------------------------------------
local function spawnDelivery(t)
	if deliveryProp then
		deliveryProp:Destroy()
		deliveryProp, deliveryPrompt = nil, nil
	end
	local spot = map.Stations.DeliverySpot
	local box = Instance.new("Part")
	box.Name = "DeliveryBox"
	box.Size = Vector3.new(3, 2.4, 2.4)
	box.Material = Enum.Material.Cardboard
	box.Color = rgb(176, 136, 90)
	box.Anchored = true
	box.CFrame = spot * CFrame.new(0, 1.2, 0) * CFrame.Angles(0, math.rad(rng:NextNumber(-20, 20)), 0)
	box.Parent = map.Dynamic
	local tape = Instance.new("Part")
	tape.Size = Vector3.new(3.02, 2.42, 0.4)
	tape.Color = rgb(200, 170, 110)
	tape.Material = Enum.Material.SmoothPlastic
	tape.Anchored = true
	tape.CanCollide = false
	tape.CFrame = box.CFrame
	tape.Parent = box
	local prompt = Util.prompt(box, "Взять поставку", "Коробка без накладной", 0.5, 7)
	deliveryProp, deliveryPrompt = box, prompt
	box:SetAttribute("TaskId", t.Id)
	prompt.Triggered:Connect(function(player)
		if box.Transparency > 0.5 then
			return
		end
		if StoreSystems.GiveCarry(player, "Delivery") then
			box.Transparency = 1
			tape.Transparency = 1
			prompt.Enabled = false
			S.Net.Notify(player, "Отнесите поставку в зону приёмки на складе", "info")
			-- v10: пока несёт коробку через подсобку — там кто-то есть
			if S.Beast then
				S.Beast.OnDeliveryPicked(player, S.Events.Night())
			end
		end
	end)
	-- когда коробку возвращают (бросили), снова показываем её с лентой
	box:GetPropertyChangedSignal("Transparency"):Connect(function()
		tape.Transparency = box.Transparency
	end)
end

-------------------------------------------------------------------------------
-- Подсказки станций
-------------------------------------------------------------------------------
local prompts = {}

local function station(key, part, action, object, hold, dist)
	local p = Util.prompt(part, action, object, hold, dist)
	p.Name = key .. "Prompt"
	prompts[key] = p
	return p
end

function StoreSystems.Init(m, services)
	map, S = m, services

	-- Табельные часы: начать смену
	station("TimeClock", map.Stations.TimeClock, "Отметиться и начать смену", "Табельные часы", 0.5, 8).Triggered:Connect(function(player)
		S.Shift.RequestStart(player)
	end)
	-- Пульт видеонаблюдения
	station("Cameras", map.Stations.CamDesk, "Открыть камеры", "Видеонаблюдение", 0, 9).Triggered:Connect(function(player)
		S.Net.Effect(player, "OpenCameras")
	end)
	-- Монитор камер на посту охраны у входа
	if map.Stations.GuardDesk then
		station("GuardCams", map.Stations.GuardDesk, "Открыть камеры", "Пост охраны", 0, 9).Triggered:Connect(function(player)
			S.Net.Sound("Keys", map.Stations.GuardDesk.Position, 0.4)
			S.Net.Effect(player, "OpenCameras")
		end)
	end
	-- v15: инструкции охраны на стойке (первое задание после командной кат-сцены; читать можно всегда)
	if map.Stations.Instructions then
		station("Instructions", map.Stations.Instructions, "Прочитать инструкции", "Стойка охраны", 0, 8).Triggered:Connect(function(player)
			S.Net.Sound("BoxPick", map.Stations.Instructions.Position, 0.25)
			S.Net.Effect(player, "Read", { Title = Texts.TeamInstructionsTitle, Body = Texts.IntroNote })
			S.Tasks.ProgressKind("instructions", 1)
		end)
	end
	-- Мониторы камер в кабинете менеджера
	if map.Stations.OfficeCams then
		station("OfficeCams", map.Stations.OfficeCams, "Открыть камеры", "Мониторы", 0, 9).Triggered:Connect(function(player)
			S.Net.Effect(player, "OpenCameras")
		end)
	end
	-- Батарейки для фонарика
	station("Batteries", map.Stations.Batteries, "Взять батарейки", "Для фонарика", 0.3, 7).Triggered:Connect(function(player)
		S.Net.Effect(player, "Battery")
		S.Net.Sound("BoxPick", map.Stations.Batteries.Position, 0.4, player)
		S.Net.Notify(player, "Фонарик заряжен", "info")
	end)
	-- Швабра
	station("Mop", map.Stations.Mop, "Взять швабру", "Швабра", 0.3, 8).Triggered:Connect(function(player)
		StoreSystems.GiveCarry(player, "Mop")
	end)
	-- Коробки на складе
	for _, pile in ipairs(map.BoxPiles) do
		local p = Util.prompt(pile.Part, "Взять коробку", Products.Categories[pile.Category].Name, 0.4, 8)
		p.Triggered:Connect(function(player)
			StoreSystems.GiveCarry(player, "Box", pile.Category)
		end)
	end
	-- Пустые места на полках
	for _, f in ipairs(map.Facings) do
		f.Empty = false
		local p = Util.prompt(f.Front, "Выложить товар", f.Label, 1.2, 7)
		p.Enabled = false
		f.Prompt = p
		p.Triggered:Connect(function(player)
			StoreSystems.Restock(player, f)
		end)
	end
	-- Холодильники: проверка температуры и перезапуск
	for _, f in ipairs(map.Fridges) do
		f.Temp = rng:NextInteger(2, 5)
		f.Broken = false
		local check = Util.prompt(f.Thermo, "Проверить температуру", "Холодильник №" .. f.Index, 1, 7)
		check.Enabled = false
		f.CheckPrompt = check
		check.Triggered:Connect(function(player)
			local list = S.Tasks.Active("fridgecheck")
			local t = list[1]
			if not t then
				return
			end
			t.Data.Checked = t.Data.Checked or {}
			if t.Data.Checked[f.Index] then
				return
			end
			t.Data.Checked[f.Index] = true
			check.Enabled = false
			local text = fridgeTemp(f)
			S.Net.Notify(player, "Холодильник №" .. f.Index .. ": " .. text .. (f.Broken and " — неисправен!" or " — норма"), f.Broken and "warn" or "info")
			S.Tasks.Progress(t.Id, 1)
		end)
		local fix = Util.prompt(f.Thermo, "Перезапустить холодильник", "Холодильник №" .. f.Index, 3, 7)
		fix.Enabled = false
		fix.KeyboardKeyCode = Enum.KeyCode.R
		fix.GamepadKeyCode = Enum.KeyCode.ButtonY
		fix.Exclusivity = Enum.ProximityPromptExclusivity.AlwaysShow
		fix.UIOffset = Vector2.new(0, 60)
		f.FixPrompt = fix
		fix.Triggered:Connect(function()
			if not f.Broken then
				return
			end
			f.Broken = false
			f.Temp = rng:NextInteger(3, 6)
			updateFridge(f)
			fix.Enabled = false
			S.Net.Sound("PowerUp", f.Body.Position + Vector3.new(0, 4, 2), 0.4)
			if f.FixTask then
				S.Tasks.Progress(f.FixTask, 1)
				f.FixTask = nil
			end
		end)
		updateFridge(f)
	end
	-- Температура в холодильной камере
	station("ColdThermo", map.ColdThermo.Part, "Записать температуру", "Термометр", 1.5, 7).Triggered:Connect(function(player)
		local list = S.Tasks.Active("coldtemp")
		if not list[1] then
			return
		end
		local hour = math.floor((S.Net.Get("Minutes") or 0) / 60)
		local temp = hour >= 3 and "-31 °C" or "-18 °C"
		map.ColdThermo.Label.Text = temp
		S.Net.Notify(player, "Записано в журнал: " .. temp .. (hour >= 3 and ". Так холодно здесь не бывает…" or ""), "info")
		S.Tasks.Progress(list[1].Id, 1)
	end)
	prompts.ColdThermo.Enabled = false
	-- Мусор: взять мешок на складе и выбросить в контейнер во дворе
	station("TrashBin", map.Stations.TrashBin, "Взять мешок с мусором", "Мусорный бак", 0.5, 8).Triggered:Connect(function(player)
		StoreSystems.GiveCarry(player, "Trash")
	end)
	prompts.TrashBin.Enabled = false
	station("Dumpster", map.Stations.Dumpster, "Выбросить мусор", "Контейнер", 0.5, 9).Triggered:Connect(function(player)
		if not needCarry(player, "Trash", nil, "Сначала возьмите мешок с мусором на складе") then
			return
		end
		StoreSystems.ClearCarry(player, true)
		S.Net.Sound("BoxDrop", map.Stations.Dumpster.Position, 0.9)
		S.Tasks.ProgressKind("trash", 1)
	end)
	prompts.Dumpster.Enabled = false
	-- Зона приёмки
	station("Delivery", map.Stations.DeliveryDrop, "Оставить поставку", "Зона приёмки", 0.5, 9).Triggered:Connect(function(player)
		if not needCarry(player, "Delivery", nil, "Поставку нужно забрать у заднего выхода") then
			return
		end
		StoreSystems.ClearCarry(player, true)
		S.Net.Sound("BoxDrop", map.Stations.DeliveryDrop.Position, 0.9)
		if deliveryProp then
			deliveryProp:Destroy()
			deliveryProp, deliveryPrompt = nil, nil
		end
		S.Tasks.ProgressKind("delivery", 1)
		if S.Beast then
			task.spawn(S.Beast.OnDeliveryDropped, player, S.Events.Night())
		end
	end)
	prompts.Delivery.Enabled = false
	-- Журнал смены
	station("ShiftLog", map.Stations.ShiftLog, "Заполнить журнал смены", "Журнал", 4, 7).Triggered:Connect(function(player)
		if not S.Tasks.IsActive("shiftlog") then
			return
		end
		S.Net.Notify(player, "Журнал заполнен. Предыдущая запись в нём сделана… 14.11.2003", "anomaly")
		S.Tasks.ProgressKind("shiftlog", 1)
	end)
	prompts.ShiftLog.Enabled = false
	-- Запереть задний выход
	local backDoor = S.Doors.Get("BackExit")
	station("LockBack", backDoor.Parts[1], "Запереть", "Задний выход", 1.5, 7).Triggered:Connect(function(player)
		if not S.Tasks.IsActive("lockback") then
			return
		end
		S.Doors.Set("BackExit", false)
		S.Doors.SetLocked("BackExit", true)
		S.Net.Sound("Keys", backDoor.Parts[1].Position, 0.6)
		task.delay(0.4, function()
			S.Net.Sound("LockClick", backDoor.Parts[1].Position, 0.8)
		end)
		S.Tasks.ProgressKind("lockback", 1)
	end)
	prompts.LockBack.Enabled = false
	prompts.LockBack.KeyboardKeyCode = Enum.KeyCode.R
	prompts.LockBack.GamepadKeyCode = Enum.KeyCode.ButtonY
	prompts.LockBack.Exclusivity = Enum.ProximityPromptExclusivity.AlwaysShow
	prompts.LockBack.UIOffset = Vector2.new(0, 60)
	-- Телефон в кабинете
	station("Phone", map.Stations.Phone, "Ответить", "Телефон", 0.3, 8).Triggered:Connect(function(player)
		if not phoneRinging then
			return
		end
		phoneRinging = false
		prompts.Phone.Enabled = false
		S.Net.Sound("Static", nil, 0.5, player)
		S.Net.Subtitle(player, "Телефон", Texts.Whisper.PhoneCall, 6)
		S.Tasks.ProgressKind("phone", 1)
	end)
	prompts.Phone.Enabled = false

	-- Положить предмет / выход игрока / смерть персонажа
	Players.PlayerRemoving:Connect(function(player)
		StoreSystems.ClearCarry(player, false)
	end)
	Players.PlayerAdded:Connect(function(player)
		player:SetAttribute("Carry", "")
		player.CharacterRemoving:Connect(function()
			StoreSystems.ClearCarry(player, false)
		end)
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		player.CharacterRemoving:Connect(function()
			StoreSystems.ClearCarry(player, false)
		end)
	end

	-- Проверка заданий «посетить помещение»
	task.spawn(function()
		while true do
			task.wait(0.5)
			for _, t in ipairs(S.Tasks.Active("visit")) do
				for _, player in ipairs(Players:GetPlayers()) do
					local root = Util.rootOf(player)
					if root and StoreSystems.RoomAt(root.Position) == t.Data.Room then
						S.Tasks.Progress(t.Id, 1)
						if S.Events then
							S.Events.OnVisit(t, player)
						end
						break
					end
				end
			end
		end
	end)
end

-- Выложить товар из коробки на пустую полку f
function StoreSystems.Restock(player, f)
	if not f.Empty then
		return false
	end
	local catName = Products.Categories[f.Category].Name
	if not needCarry(player, "Box", f.Category, "Нужна коробка «" .. catName .. "» со склада") then
		return false
	end
	StoreSystems.ClearCarry(player, true)
	setFacingVisible(f, true)
	f.Prompt.Enabled = false
	S.Net.Sound("BoxDrop", f.Front.Position, 0.6)
	local id = f.TaskId
	f.TaskId = nil
	S.Tasks.Progress(id, 1)
	local t = S.Tasks.Get(id)
	if t and not t.Done then
		restockDetail(t)
	end
	return true
end

-- Игрок положил предмет (кнопка «Положить» / клавиша G)
function StoreSystems.Drop(player)
	local c = carrying[player]
	if not c then
		return
	end
	local root = Util.rootOf(player)
	if root then
		S.Net.Sound("BoxDrop", root.Position, 0.5)
	end
	StoreSystems.ClearCarry(player, false)
end

-- Клиент сообщает, что посмотрел камеру index (задание «проверить камеры»)
function StoreSystems.CameraViewed(player, index)
	if type(index) ~= "number" or index < 1 or index > #map.Cameras then
		return
	end
	for _, t in ipairs(S.Tasks.Active("cctv")) do
		cctvSeen[t.Id] = cctvSeen[t.Id] or {}
		local seen = cctvSeen[t.Id]
		if not seen[index] then
			seen[index] = true
			local n = 0
			for _ in pairs(seen) do
				n = n + 1
			end
			S.Tasks.SetProgress(t.Id, n)
		end
		break
	end
end

-- Телефон звонит (событие)
function StoreSystems.RingPhone(seconds)
	if phoneRinging then
		return
	end
	phoneRinging = true
	prompts.Phone.Enabled = true
	task.spawn(function()
		local untilT = os.clock() + (seconds or 30)
		while phoneRinging and os.clock() < untilT do
			S.Net.Sound("Phone", map.Stations.Phone.Position, 1)
			task.wait(0.5)
			S.Net.Sound("Phone", map.Stations.Phone.Position, 1)
			task.wait(2.6)
		end
		phoneRinging = false
		prompts.Phone.Enabled = false
	end)
end

-- Товар на полу (событие): банки выложены линией
function StoreSystems.ScatterItems(t)
	local x = AISLE_X[rng:NextInteger(2, 6)]
	local n = t.Count
	for i = 1, n do
		local p = Instance.new("Part")
		p.Name = "FloorCan"
		p.Shape = Enum.PartType.Cylinder
		p.Size = Vector3.new(0.75, 0.45, 0.45)
		p.Color = rgb(170, 170, 176)
		p.Material = Enum.Material.Metal
		p.Anchored = true
		p.CFrame = CFrame.new(x + math.sin(i) * 0.3, 0.38, 2 + i * 2.2) * CFrame.Angles(0, 0, math.rad(90))
		p.Parent = map.Dynamic
		table.insert(floorItems, p)
		local prompt = Util.prompt(p, "Поднять", "Банка тушёнки", 0.2, 6)
		prompt.Triggered:Connect(function()
			if p.Parent then
				p:Destroy()
				S.Tasks.Progress(t.Id, 1)
			end
		end)
	end
	S.Tasks.SetDetail(t, "проход " .. table.find(AISLE_X, x))
	S.Net.Sound("CansFall", Vector3.new(x, 2, 12), 1)
end

-------------------------------------------------------------------------------
-- Подготовка заданий
-------------------------------------------------------------------------------
function StoreSystems.SetupTask(t)
	local k = t.Kind
	if k == "restock" then
		emptyFacings(t)
	elseif k == "spill" then
		spawnSpills(t)
	elseif k == "fridgecheck" then
		t.Data.Checked = {}
		for _, f in ipairs(map.Fridges) do
			f.CheckPrompt.Enabled = true
		end
	elseif k == "coldtemp" then
		prompts.ColdThermo.Enabled = true
	elseif k == "trash" then
		prompts.TrashBin.Enabled = true
		prompts.Dumpster.Enabled = true
	elseif k == "delivery" then
		prompts.Delivery.Enabled = true
		spawnDelivery(t)
	elseif k == "shiftlog" then
		prompts.ShiftLog.Enabled = true
	elseif k == "lockback" then
		prompts.LockBack.Enabled = true
	elseif k == "cctv" then
		cctvSeen[t.Id] = {}
	elseif k == "pickup" then
		StoreSystems.ScatterItems(t)
	end
end

function StoreSystems.OnTaskDone(t)
	local k = t.Kind
	if k == "fridgecheck" then
		for _, f in ipairs(map.Fridges) do
			f.CheckPrompt.Enabled = false
		end
	elseif k == "coldtemp" and not S.Tasks.IsActive("coldtemp") then
		prompts.ColdThermo.Enabled = false
	elseif k == "trash" and not S.Tasks.IsActive("trash") then
		prompts.TrashBin.Enabled = false
		prompts.Dumpster.Enabled = false
	elseif k == "delivery" and not S.Tasks.IsActive("delivery") then
		prompts.Delivery.Enabled = false
	elseif k == "shiftlog" then
		prompts.ShiftLog.Enabled = false
	elseif k == "lockback" then
		prompts.LockBack.Enabled = false
	end
end

-- Табельные часы показывают время смены, подсказка доступна только в лобби
function StoreSystems.SetLobby(isLobby)
	prompts.TimeClock.Enabled = isLobby
end

-- Пятая ночь: товар исчезает со всех полок разом (смена сбросит магазин обратно)
function StoreSystems.EmptyAll()
	local n = 0
	for _, f in ipairs(map.Facings) do
		if not f.Empty then
			setFacingVisible(f, false)
			n = n + 1
		end
	end
	return n
end

function StoreSystems.SetClock(text)
	map.Stations.TimeClockLabel.Text = text
end

function StoreSystems.Reset()
	for _, player in ipairs(Players:GetPlayers()) do
		StoreSystems.ClearCarry(player, true)
	end
	for _, f in ipairs(map.Facings) do
		setFacingVisible(f, true)
		f.Prompt.Enabled = false
		f.TaskId = nil
	end
	for part in pairs(spills) do
		part:Destroy()
	end
	spills = {}
	for _, p in ipairs(floorItems) do
		p:Destroy()
	end
	floorItems = {}
	if deliveryProp then
		deliveryProp:Destroy()
		deliveryProp, deliveryPrompt = nil, nil
	end
	for _, f in ipairs(map.Fridges) do
		f.Broken = false
		f.FixTask = nil
		f.Temp = rng:NextInteger(2, 5)
		f.CheckPrompt.Enabled = false
		f.FixPrompt.Enabled = false
		updateFridge(f)
	end
	map.ColdThermo.Label.Text = "-18 °C"
	for _, key in ipairs({ "ColdThermo", "TrashBin", "Dumpster", "Delivery", "ShiftLog", "LockBack", "Phone" }) do
		prompts[key].Enabled = false
	end
	phoneRinging = false
	cctvSeen = {}
	for _, c in ipairs(map.Dynamic:GetChildren()) do
		if c.Name == "WetFloorSign" then
			c:Destroy()
		end
	end
end

return StoreSystems
