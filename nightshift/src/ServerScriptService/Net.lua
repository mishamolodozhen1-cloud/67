-- Net: создаёт RemoteEvent'ы в ReplicatedStorage.Remotes и папку GameState с общим состоянием смены.
-- Остальные серверные модули отправляют клиентам уведомления, звуки и эффекты только через Net.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Sounds = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Sounds"))

local Net = {}

local remotes, state

-- mode: "Game" (смена) или "Hub" (главное меню на публичном сервере)
function Net.Init(mode)
	remotes = Instance.new("Folder")
	remotes.Name = "Remotes"
	-- Сервер -> клиент
	for _, name in ipairs({ "Notify", "Phone", "Subtitle", "Sound", "Effect" }) do
		local e = Instance.new("RemoteEvent")
		e.Name = name
		e.Parent = remotes
	end
	-- Клиент -> сервер: действия игрока (начать смену, положить предмет, фонарик, камеры, настройки…)
	local action = Instance.new("RemoteEvent")
	action.Name = "Action"
	action.Parent = remotes
	local profile = Instance.new("RemoteFunction")
	profile.Name = "GetProfile"
	profile.Parent = remotes
	-- комнаты: создать, войти по коду, список, выйти в меню
	local rooms = Instance.new("RemoteFunction")
	rooms.Name = "Rooms"
	rooms.Parent = remotes
	remotes.Parent = ReplicatedStorage

	-- Общее состояние смены. Клиенты читают атрибуты: Phase, Minutes, Power, Countdown, Percent…
	state = Instance.new("Folder")
	state.Name = "GameState"
	state:SetAttribute("Mode", mode or "Game")
	state:SetAttribute("Phase", mode == "Hub" and "Hub" or "Lobby")
	state:SetAttribute("Minutes", 0)
	state:SetAttribute("Power", true)
	state:SetAttribute("Countdown", 0)
	state:SetAttribute("Percent", 0)
	state:SetAttribute("Night", 1)
	state:SetAttribute("NightMax", 1)
	state:SetAttribute("Clues", 0)
	state.Parent = ReplicatedStorage

	-- Список заданий: каждая задача — Folder с атрибутами Text, Count, Progress, Done, Room, Order
	local tasks = Instance.new("Folder")
	tasks.Name = "Tasks"
	tasks.Parent = ReplicatedStorage
end

function Net.Remote(name)
	return remotes:FindFirstChild(name)
end

function Net.State()
	return state
end

function Net.Set(key, value)
	state:SetAttribute(key, value)
end

function Net.Get(key)
	return state:GetAttribute(key)
end

-- Отправить событие одному игроку (player) или всем (player == nil)
local function send(name, player, ...)
	local e = remotes:FindFirstChild(name)
	if typeof(player) == "Instance" then
		if player:IsA("Player") and player.Parent then
			e:FireClient(player, ...)
		end
	elseif player == nil then
		e:FireAllClients(...)
	end
end

-- Всплывающее уведомление. style: "info", "task", "done", "warn", "anomaly"
function Net.Notify(player, text, style)
	send("Notify", player, text, style or "info")
end

-- Сообщение на телефон
function Net.Phone(player, sender, text)
	send("Phone", player, sender, text)
end

-- Субтитры (диктор, шёпот)
function Net.Subtitle(player, speaker, text, seconds)
	send("Subtitle", player, speaker, text, seconds or 5)
end

-- Звук у всех игроков: в точке position (Vector3) или «в голове» (nil).
-- pitch — скорость (ниже 1 — ниже и медленнее), fx = "Distort" — искажённый, как из сломанного динамика
function Net.Sound(name, position, volume, player, pitch, fx)
	send("Sound", player, name, position, volume, pitch, fx)
end

-- Рация охраны: щелчок, сообщение в телефоне от «Диспетчера» и субтитр
function Net.RadioCall(player, text)
	send("Sound", player, "RadioChirp", nil, 0.8)
	send("Phone", player, "Рация (диспетчер)", text)
end

-- Объявление по громкой связи: сигнал + голос + субтитры.
-- opts.Pitch / opts.Distort — замедленный искажённый голос (поздние ночи), opts.Text — свой субтитр
function Net.PA(line, opts)
	opts = opts or {}
	local fx = opts.Distort and "Distort" or nil
	send("Sound", nil, "PAChime", nil, nil, opts.Pitch and math.max(0.7, opts.Pitch) or nil, fx)
	task.delay(2.4 / (opts.Pitch or 1), function()
		send("Sound", nil, line, nil, nil, opts.Pitch, fx)
		send("Subtitle", nil, "Громкая связь", opts.Text or Sounds.Subtitles[line] or "", 7)
	end)
end

-- Объявление без голоса: сигнал, треск динамика и субтитр (диктор молчит, говорит кто-то другой)
function Net.PAText(text, distort)
	send("Sound", nil, "PAChime", nil, nil, distort and 0.78 or nil, distort and "Distort" or nil)
	task.delay(2.2, function()
		send("Sound", nil, "Static", nil, 0.35)
		send("Subtitle", nil, "Громкая связь", text, 6)
	end)
end

-- Визуальный эффект на клиенте (мигание ламп, поимка, концовка…)
function Net.Effect(player, name, data)
	send("Effect", player, name, data)
end

function Net.OnAction(handler)
	remotes:FindFirstChild("Action").OnServerEvent:Connect(handler)
end

function Net.ForEachPlayer(fn)
	for _, p in ipairs(Players:GetPlayers()) do
		fn(p)
	end
end

return Net
