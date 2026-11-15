-- Secrets: правда о МАРТ 24 и секретная концовка.
-- Четыре улики: газета в ящике стола директора, кассета в охране, бейдж в холодильной камере,
-- шкафчик №0 в комнате персонала (открывается ключом с бейджа).
-- Когда найдены все четыре, на складе открывается касса №0. После 04:00 на ней можно
-- пробить последний чек Покупателя — это секретная концовка.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Texts = require(Shared:WaitForChild("Texts"))
local Util = require(Shared:WaitForChild("Util"))

local Secrets = {}

local map, S
local found, count = {}, 0
local revealed, sceneActive, finished = false, false, false
local registerPrompt, payPrompt
local lastItem

local ACTIONS = {
	Newspaper = { "Открыть ящик", "Стол директора" },
	Tape = { "Посмотреть кассету", "Видеокассета" },
	Badge = { "Поднять бейдж", "Бейдж" },
	Locker = { "Открыть шкафчик", "Шкафчик №0" },
}

local function reveal()
	revealed = true
	local r0 = map.Register0
	r0.Tarp.Transparency = 1
	r0.Tarp.CanCollide = false
	local light = r0.Lamp:FindFirstChildWhichIsA("Light")
	if light then
		light.Brightness = 1.4
	end
	r0.Lamp.Material = Enum.Material.Neon
	r0.Lamp.Color = Color3.fromRGB(255, 230, 190)
	r0.ScreenLabel.Text = "КАССА 0\nОТКРЫТА"
	registerPrompt.Enabled = true
	S.Net.Sound("Static", nil, 0.4)
	S.Net.Subtitle(nil, "Шёпот", Texts.Whisper.RegisterOpen, 5)
	S.Net.Notify(nil, "На складе, в дальнем углу, что-то изменилось…", "anomaly")
end

function Secrets.Inspect(player, key)
	if key == "Locker" and not found.Badge then
		S.Net.Sound("Knock", map.Clues.Locker.Position, 0.4)
		S.Net.Notify(player, Texts.LockerNeedsKey, "warn")
		return
	end
	local clue = Texts.Clues[key]
	if key == "Tape" then
		S.Net.Effect(player, "VhsTape", { Title = clue.Title, Body = clue.Body })
	else
		S.Net.Effect(player, "Read", { Title = clue.Title, Body = clue.Body })
	end
	if key == "Locker" then
		S.Net.Sound("DoorOpen", map.Clues.Locker.Position, 0.5)
	end
	if not found[key] then
		found[key] = true
		count = count + 1
		S.Net.Set("Clues", count)
		S.Net.Notify(nil, string.format("Улика %d из 4: %s", count, clue.Title), "anomaly")
		if count >= 4 and not revealed then
			task.delay(4, reveal)
		end
	end
end

local function complete(player)
	if finished then
		return
	end
	finished = true
	payPrompt.Enabled = false
	S.Net.Sound("Payment", map.Register0.Register.Position, 0.8)
	map.Register0.ScreenLabel.Text = "ОПЛАЧЕНО\nСМЕНА ЗАКРЫТА"
	S.Net.Subtitle(nil, "Шёпот", Texts.Whisper.GoHome, 6)
	S.Net.Notify(nil, player.DisplayName .. " пробил(а) последний чек на кассе №0", "anomaly")
	task.delay(4, function()
		S.Monster.Banish()
		if lastItem then
			lastItem:Destroy()
			lastItem = nil
		end
		S.Shift.Finish("Secret")
	end)
end

function Secrets.Init(m, services)
	map, S = m, services
	for key, part in pairs(map.Clues) do
		local a = ACTIONS[key]
		local prompt = Util.prompt(part, a[1], a[2], 0.8, 7)
		prompt.Name = "CluePrompt"
		prompt.Triggered:Connect(function(player)
			if S.Net.Get("Phase") ~= "Shift" then
				S.Net.Notify(player, "Сначала начните смену", "info")
				return
			end
			Secrets.Inspect(player, key)
		end)
	end
	local r0 = map.Register0
	registerPrompt = Util.prompt(r0.Register, "Включить кассу", "Касса №0", 1.5, 8)
	registerPrompt.Enabled = false
	registerPrompt.Triggered:Connect(function(player)
		if sceneActive or finished then
			return
		end
		local hour = math.floor((S.Net.Get("Minutes") or 0) / 60)
		if hour < 4 then
			S.Net.Notify(player, "Касса молчит. Похоже, ещё рано…", "info")
			return
		end
		sceneActive = true
		registerPrompt.Enabled = false
		r0.ScreenLabel.Text = "КАССА 0\nПОКУПАТЕЛЬ ОЖИДАЕТ"
		S.Monster.Hold(r0.CustomerSpot)
		S.Net.Sound("Drone", r0.Register.Position, 0.6)
		S.Net.Subtitle(nil, "Шёпот", Texts.Whisper.NotFinished, 6)
		-- его последняя покупка
		local item = Instance.new("Part")
		item.Name = "LastPurchase"
		item.Size = Vector3.new(0.7, 1.3, 0.7)
		item.Color = Color3.fromRGB(236, 232, 214)
		item.Anchored = true
		item.CanCollide = false
		item.CFrame = CFrame.new(r0.ItemSpot + Vector3.new(0, 0.15, 0))
		item.Parent = map.Dynamic
		lastItem = item
		local scan = Util.prompt(item, "Пробить последний чек", "Молоко «Утро», 2003 год", 1.5, 8)
		scan.Triggered:Connect(function()
			if scan.Enabled == false then
				return
			end
			scan.Enabled = false
			S.Net.Sound("Scan", r0.Register.Position, 0.8)
			r0.ScreenLabel.Text = "МОЛОКО «УТРО» 1 Л\n9 р. 90 к.\nИТОГО: 9,90"
			payPrompt.Enabled = true
		end)
	end)
	payPrompt = Util.prompt(r0.Register, "Принять оплату", "Касса №0", 1, 8)
	payPrompt.Enabled = false
	payPrompt.Triggered:Connect(complete)
end

function Secrets.Count()
	return count
end

function Secrets.Reset()
	found, count = {}, 0
	revealed, sceneActive, finished = false, false, false
	local r0 = map.Register0
	r0.Tarp.Transparency = 0
	r0.Tarp.CanCollide = true
	local light = r0.Lamp:FindFirstChildWhichIsA("Light")
	if light then
		light.Brightness = 0
	end
	r0.Lamp.Material = Enum.Material.SmoothPlastic
	r0.Lamp.Color = Color3.fromRGB(90, 86, 80)
	r0.ScreenLabel.Text = ""
	registerPrompt.Enabled = false
	payPrompt.Enabled = false
	if lastItem then
		lastItem:Destroy()
		lastItem = nil
	end
	S.Net.Set("Clues", 0)
end

return Secrets
