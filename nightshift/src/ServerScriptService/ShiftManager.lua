-- ShiftManager: ход смены.
--   Lobby     — игроки в комнате персонала; смену начинает отметка на табельных часах
--               (или кнопка «Начать смену»), либо она начнётся сама через Config.LobbyAutoStart секунд
--   Countdown — короткий отсчёт
--   Shift     — часы идут от 00:00 до 06:00, каждый час добавляет задания и события
--   Ending    — концовка (хорошая, плохая или секретная), потом магазин сбрасывается и снова лобби
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Util = require(Shared:WaitForChild("Util"))
local Texts = require(Shared:WaitForChild("Texts"))

local ShiftManager = {}

local map, S
local phase = "Lobby"
local minutes = 0
local served = 0
local night = 0
local startRequested = false
local finishKind = nil
local introPlayers, introDone = {}, {}

local function setPhase(p)
	phase = p
	S.Net.Set("Phase", p)
end

local function publishClock()
	S.Net.Set("Minutes", minutes)
	S.Store.SetClock(Util.clock(minutes))
end

function ShiftManager.Phase()
	return phase
end

function ShiftManager.RequestStart(player)
	if phase ~= "Lobby" or startRequested then
		return
	end
	startRequested = true
	S.Net.Notify(nil, player.DisplayName .. " отметился на табельных часах. Смена начинается!", "info")
end

-- Клиент досмотрел (или пропустил) вступительную кат-сцену
function ShiftManager.IntroDone(player)
	introDone[player] = true
end

function ShiftManager.AddServed()
	served = served + 1
end

-- Сдвинуть часы вперёд (штраф, если Покупатель поймал игрока)
function ShiftManager.AddMinutes(n)
	if phase ~= "Shift" then
		return
	end
	local target = math.min(Config.ShiftHours * 60 - 1, minutes + n)
	while minutes < target do
		minutes = minutes + 1
		if minutes % 60 == 0 then
			local hour = math.floor(minutes / 60)
			S.Tasks.OnHour(hour)
			S.Events.OnHour(hour)
		end
		S.Events.OnMinute(minutes)
	end
	publishClock()
end

-- Закончить смену досрочно (секретная концовка)
function ShiftManager.Finish(kind)
	if phase == "Shift" then
		finishKind = kind
	end
end

local function startShift()
	night = night + 1
	minutes = 0
	served = 0
	finishKind = nil
	S.Net.Set("Night", night)
	S.Net.Set("Ending", "")
	publishClock()
	S.Store.SetLobby(false)
	setPhase("Shift")
	S.Events.Plan()
	S.Events.OnHour(0)
	S.Tasks.OnHour(0)
	S.Customers.OnShiftStart()
	S.Net.Notify(nil, "Смена началась. Магазин работает до 06:00", "info")
	S.Events.OnMinute(0)
end

local function endShift(kind)
	local pct = S.Tasks.Percent()
	if not kind then
		kind = pct >= Config.GoodEndingPercent and "Good" or "Bad"
	end
	setPhase("Ending")
	S.Net.Set("Ending", kind)
	local salary = Config.SalaryBase + pct * Config.SalaryPerPercent
	if kind == "Bad" then
		salary = math.floor(salary / 2)
	end
	local stats = {
		Kind = kind,
		Percent = pct,
		Served = served,
		Revenue = S.Checkout.Revenue(),
		Salary = salary,
		Clues = S.Secrets.Count(),
		Night = night,
	}
	for _, p in ipairs(Players:GetPlayers()) do
		S.Data.RecordShift(p, kind, stats)
	end
	S.Customers.Reset()
	S.Net.Effect(nil, "Ending", stats)
	if kind == "Good" then
		S.Net.PA("ShiftOver")
		task.delay(9, function()
			S.Net.Phone(nil, Texts.Unknown, Texts.Endings.Good.Phone)
		end)
	end
	print(string.format("[Смена] ночь %d, концовка %s, выполнено %d%%", night, kind, pct))
end

local function resetAll()
	S.Tasks.Reset()
	S.Store.Reset()
	S.Checkout.Reset()
	S.Customers.Reset()
	S.Power.Reset()
	S.Doors.Reset()
	S.Monster.Reset()
	S.Secrets.Reset()
	S.Events.Reset()
	minutes = 0
	publishClock()
	S.Net.Set("Ending", "")
	S.Net.Set("Countdown", 0)
	startRequested = false
	for _, p in ipairs(Players:GetPlayers()) do
		pcall(function()
			p:LoadCharacter()
		end)
	end
end

function ShiftManager.Init(m, services)
	map, S = m, services
end

function ShiftManager.Start()
	S.Store.SetLobby(true)
	setPhase("Lobby")
	publishClock()
	task.spawn(function()
		while true do
			-- ЛОББИ
			S.Store.SetLobby(true)
			setPhase("Lobby")
			local left = Config.LobbyAutoStart
			S.Net.Set("Countdown", left)
			while not startRequested and left > 0 do
				task.wait(1)
				if #Players:GetPlayers() > 0 then
					left = left - 1
					S.Net.Set("Countdown", left)
				end
			end
			-- ОТСЧЁТ
			setPhase("Countdown")
			for i = Config.StartCountdown, 1, -1 do
				S.Net.Set("Countdown", i)
				task.wait(1)
			end
			S.Net.Set("Countdown", 0)
			-- ВСТУПИТЕЛЬНАЯ КАТ-СЦЕНА (у каждого игрока своя, ждём всех или ~100 секунд)
			introPlayers, introDone = {}, {}
			for _, p in ipairs(Players:GetPlayers()) do
				introPlayers[p] = true
			end
			setPhase("Intro")
			S.Net.Effect(nil, "Intro", { Seconds = Config.IntroSeconds })
			local introStart = os.clock()
			while os.clock() - introStart < Config.IntroSeconds + 8 do
				task.wait(0.5)
				local waiting = false
				for p in pairs(introPlayers) do
					if p.Parent and not introDone[p] then
						waiting = true
					end
				end
				if not waiting then
					break
				end
			end
			-- все стоят в кабинете менеджера, смена начинается в 00:00
			for i, p in ipairs(Players:GetPlayers()) do
				local ch = p.Character
				if ch then
					ch:PivotTo(map.Points.IntroEnd * CFrame.new((i - 2.5) * 2.4, 0, 0))
				end
			end
			-- СМЕНА
			startShift()
			local perMinute = Config.SecondsPerHour / 60
			local acc = 0
			local last = os.clock()
			while phase == "Shift" do
				task.wait(0.2)
				local now = os.clock()
				acc = acc + (now - last)
				last = now
				if finishKind then
					break
				end
				while acc >= perMinute and minutes < Config.ShiftHours * 60 do
					acc = acc - perMinute
					minutes = minutes + 1
					publishClock()
					if minutes % 60 == 0 and minutes < Config.ShiftHours * 60 then
						local hour = math.floor(minutes / 60)
						S.Tasks.OnHour(hour)
						S.Events.OnHour(hour)
					end
					S.Events.OnMinute(minutes)
				end
				if minutes >= Config.ShiftHours * 60 then
					break
				end
			end
			-- КОНЦОВКА
			endShift(finishKind)
			task.wait(Config.EndingSeconds)
			resetAll()
		end
	end)
end

return ShiftManager
