-- TaskManager: задания смены. Каждый игровой час добавляет свои задания (таблица SCHEDULE),
-- события добавляют срочные (свет, холодильник, касса №4…). Прогресс общий для всей команды.
-- Задания видны клиентам как папки в ReplicatedStorage.Tasks с атрибутами Text, Room, Detail, Count, Progress, Done, Order.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local TaskManager = {}

local S
local tasks = {} -- id -> task
local order = 0
local folder

-- Количество зависит от числа игроков n (1–4). Работа охранника:
--   patrol — обход контрольных точек, cctv — проверить камеры, help — помочь на кассах самообслуживания,
--   orders — выдать заказы, catch — задержать вора (добавляется, когда срабатывают ворота),
--   lockback — запереть задний выход, closelanes — отключить кассы, shiftlog — журнал смены
local SCHEDULE = {
	[0] = {
		{ Kind = "patrol", Text = "Обход: отметиться на всех контрольных точках", Room = "Весь магазин", Count = Config.PatrolPoints },
		{ Kind = "help", Text = "Помогать покупателям на кассах самообслуживания", Room = "Кассы самообслуживания", Count = function(n) return 1 + n end },
		{ Kind = "orders", Text = "Выдать заказы в пункте выдачи", Room = "У входа, стойка выдачи", Count = function(n) return 1 + math.floor(n / 2) end },
	},
	[1] = {
		{ Kind = "cctv", Text = "Проверить все камеры наблюдения", Room = "Пост охраны у входа или комната охраны", Count = Config.CameraCount },
		{ Kind = "help", Text = "Помогать покупателям на кассах самообслуживания", Room = "Кассы самообслуживания", Count = function(n) return 1 + n end },
		{ Kind = "orders", Text = "Выдать заказы в пункте выдачи", Room = "У входа, стойка выдачи", Count = function(n) return 1 + math.floor(n / 2) end },
	},
	[2] = {
		{ Kind = "patrol", Text = "Второй обход контрольных точек", Room = "Весь магазин", Count = Config.PatrolPoints },
		{ Kind = "help", Text = "Помогать покупателям на кассах самообслуживания", Room = "Кассы самообслуживания", Count = function(n) return 1 + math.floor(n / 2) end },
		{ Kind = "orders", Text = "Выдать заказы в пункте выдачи", Room = "У входа, стойка выдачи", Count = 1 },
	},
	[3] = {
		{ Kind = "cctv", Text = "Снова проверить все камеры", Room = "Пост охраны у входа или комната охраны", Count = Config.CameraCount },
		{ Kind = "help", Text = "Помогать покупателям на кассах самообслуживания", Room = "Кассы самообслуживания", Count = 1 },
	},
	[4] = {
		{ Kind = "patrol", Text = "Ночной обход контрольных точек", Room = "Весь магазин", Count = Config.PatrolPoints },
		{ Kind = "lockback", Text = "Запереть задний выход", Room = "Служебный коридор", Count = 1 },
	},
	[5] = {
		{ Kind = "closelanes", Text = "Отключить кассы самообслуживания 1–4", Room = "Кассы самообслуживания", Count = 4 },
		{ Kind = "shiftlog", Text = "Заполнить журнал смены", Room = "Кабинет менеджера", Count = 1 },
	},
}

local function playerCount()
	return math.clamp(#Players:GetPlayers(), 1, 4)
end

local function publishPercent()
	local done, total = 0, 0
	for _, t in pairs(tasks) do
		total = total + t.Count
		done = done + math.min(t.Progress, t.Count)
	end
	local pct = total > 0 and math.floor(done / total * 100 + 0.5) or 0
	S.Net.Set("Percent", pct)
	S.Net.Set("TasksDone", done)
	S.Net.Set("TasksTotal", total)
	return pct, done, total
end

local function sync(t)
	t.Folder:SetAttribute("Progress", math.min(t.Progress, t.Count))
	t.Folder:SetAttribute("Count", t.Count)
	t.Folder:SetAttribute("Done", t.Done)
	t.Folder:SetAttribute("Detail", t.Detail or "")
end

function TaskManager.Init(_, services)
	S = services
	folder = ReplicatedStorage:WaitForChild("Tasks")
end

-- Добавить задание. def = { Id, Kind, Text, Room, Count, Data }
function TaskManager.Add(def)
	order = order + 1
	local id = def.Id or (def.Kind .. "_" .. order)
	if tasks[id] then
		return tasks[id]
	end
	local t = {
		Id = id,
		Kind = def.Kind,
		Text = def.Text,
		Room = def.Room or "",
		Count = math.max(1, def.Count or 1),
		Progress = 0,
		Done = false,
		Order = order,
		Data = def.Data or {},
		Detail = "",
	}
	local f = Instance.new("Folder")
	f.Name = id
	f:SetAttribute("Text", t.Text)
	f:SetAttribute("Room", t.Room)
	f:SetAttribute("Kind", t.Kind)
	f:SetAttribute("Order", order)
	t.Folder = f
	sync(t)
	f.Parent = folder
	tasks[id] = t
	-- Подготовить задание в мире (пустые полки, лужи, подсказки…)
	if S.Store then
		S.Store.SetupTask(t)
	end
	if S.Checkout then
		S.Checkout.SetupTask(t)
	end
	if S.Security then
		S.Security.OnTaskAdded(t)
	end
	sync(t)
	publishPercent()
	S.Net.Notify(nil, "Новое задание: " .. t.Text, "task")
	return t
end

function TaskManager.Get(id)
	return tasks[id]
end

-- Активные (невыполненные) задания нужного типа, от старых к новым
function TaskManager.Active(kind)
	local list = {}
	for _, t in pairs(tasks) do
		if t.Kind == kind and not t.Done then
			table.insert(list, t)
		end
	end
	table.sort(list, function(a, b)
		return a.Order < b.Order
	end)
	return list
end

function TaskManager.IsActive(kind)
	return #TaskManager.Active(kind) > 0
end

function TaskManager.SetDetail(t, text)
	if t then
		t.Detail = text
		sync(t)
	end
end

local function complete(t)
	t.Done = true
	sync(t)
	S.Net.Notify(nil, "Выполнено: " .. t.Text, "done")
	if S.Store then
		S.Store.OnTaskDone(t)
	end
	if S.Checkout then
		S.Checkout.OnTaskDone(t)
	end
end

-- Прибавить прогресс заданию по id
function TaskManager.Progress(id, amount)
	local t = tasks[id]
	if not t or t.Done then
		return false
	end
	t.Progress = t.Progress + (amount or 1)
	if t.Progress >= t.Count then
		t.Progress = t.Count
		complete(t)
	else
		sync(t)
	end
	publishPercent()
	return true
end

-- Установить прогресс (например, сколько камер уже просмотрено)
function TaskManager.SetProgress(id, value)
	local t = tasks[id]
	if not t or t.Done then
		return
	end
	t.Progress = math.min(value, t.Count)
	if t.Progress >= t.Count then
		complete(t)
	else
		sync(t)
	end
	publishPercent()
end

-- Прибавить прогресс самому старому активному заданию этого типа
function TaskManager.ProgressKind(kind, amount)
	local list = TaskManager.Active(kind)
	if list[1] then
		return TaskManager.Progress(list[1].Id, amount)
	end
	return false
end

function TaskManager.OnHour(hour)
	local n = playerCount()
	for _, def in ipairs(SCHEDULE[hour] or {}) do
		local count = type(def.Count) == "function" and def.Count(n) or def.Count
		TaskManager.Add({ Id = def.Kind .. "_h" .. hour, Kind = def.Kind, Text = def.Text, Room = def.Room, Count = count })
	end
end

function TaskManager.Percent()
	return publishPercent()
end

-- Сколько заданий каждого типа выполнено (для итогов смены)
function TaskManager.Summary()
	local served = 0
	for _, t in pairs(tasks) do
		if t.Kind == "serve" then
			served = served + t.Progress
		end
	end
	return { Served = served }
end

function TaskManager.Reset()
	tasks = {}
	order = 0
	for _, c in ipairs(folder:GetChildren()) do
		c:Destroy()
	end
	publishPercent()
end

return TaskManager
