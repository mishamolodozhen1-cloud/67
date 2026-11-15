-- Net: создаёт RemoteEvent'ы в ReplicatedStorage.Remotes и папку GameState с общим состоянием смены.
-- Остальные серверные модули отправляют клиентам уведомления, звуки и эффекты только через Net.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Sounds = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Sounds"))

local Net = {}

local remotes, state

function Net.Init()
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
	remotes.Parent = ReplicatedStorage

	-- Общее состояние смены. Клиенты читают атрибуты: Phase, Minutes, Power, Countdown, Percent…
	state = Instance.new("Folder")
	state.Name = "GameState"
	state:SetAttribute("Phase", "Lobby")
	state:SetAttribute("Minutes", 0)
	state:SetAttribute("Power", true)
	state:SetAttribute("Countdown", 0)
	state:SetAttribute("Percent", 0)
	state:SetAttribute("Night", 0)
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
	if player then
		e:FireClient(player, ...)
	else
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

-- Звук у всех игроков: в точке position (Vector3) или «в голове» (nil)
function Net.Sound(name, position, volume, player)
	send("Sound", player, name, position, volume)
end

-- Объявление по громкой связи: сигнал + голос + субтитры
function Net.PA(line)
	send("Sound", nil, "PAChime", nil, nil)
	task.delay(2.4, function()
		send("Sound", nil, line, nil, nil)
		send("Subtitle", nil, "Громкая связь", Sounds.Subtitles[line] or "", 7)
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
