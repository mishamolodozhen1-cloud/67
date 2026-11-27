-- ShiftManager: ход смены.
--   Lobby     — игроки в комнате персонала; выбирают ночь (1–5, открытые по прогрессу) и начинают
--               смену отметкой на табельных часах (или кнопкой), либо она начнётся сама через
--               Config.LobbyAutoStart секунд
-- Ночи: хорошая (или секретная) концовка открывает следующую ночь, плохая — ночь повторяется.
--   Countdown — короткий отсчёт
--   Shift     — часы идут от 00:00 до 06:00, каждый час добавляет задания и события
--   Ending    — концовка (хорошая, плохая или секретная), потом магазин сбрасывается и снова лобби
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Util = require(Shared:WaitForChild("Util"))
local Texts = require(Shared:WaitForChild("Texts"))
local TeamLines = require(Shared:WaitForChild("TeamLines"))
local Sounds = require(Shared:WaitForChild("Sounds"))
local VoiceLines = require(Shared:WaitForChild("VoiceLines"))

local ShiftManager = {}

local map, S
local phase = "Lobby"
local minutes = 0
local served = 0
local night = 1
local selected = 1 -- ночь, выбранная в лобби
local userPicked = false -- игроки выбрали ночь сами (иначе — самая дальняя открытая)
local startRequested = false
local finishKind = nil
local introPlayers, introDone = {}, {}
local introSpots = {} -- v15: UserId -> где игрок стоит после командной сцены
local teamIntro = false -- v15: смену открыла командная кат-сцена (2–4 игрока) — первое задание у стойки охраны
-- v15: порядок входа на сервер — по нему раздаются роли в командной кат-сцене (первый — за рулём)
local joinOrder, joinCounter = {}, 0
local function noteJoin(p)
	if not joinOrder[p] then
		joinCounter = joinCounter + 1
		joinOrder[p] = joinCounter
	end
end
for _, p in ipairs(Players:GetPlayers()) do
	noteJoin(p)
end
Players.PlayerAdded:Connect(noteJoin)
Players.PlayerRemoving:Connect(function(p)
	joinOrder[p] = nil
end)

-- Состав командной кат-сцены: до четырёх игроков по порядку входа, у каждого своя роль
local function teamRoster()
	local list = Players:GetPlayers()
	for _, p in ipairs(list) do
		noteJoin(p)
	end
	table.sort(list, function(a, b)
		return (joinOrder[a] or 0) < (joinOrder[b] or 0)
	end)
	local roster = {}
	for i, p in ipairs(list) do
		if i > #TeamLines.Roles then
			break
		end
		table.insert(roster, { UserId = p.UserId, Name = p.DisplayName, Role = TeamLines.Roles[i] })
	end
	return roster
end

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

local testMax = nil -- проверка на сервере без игроков (TestUnlock)

-- Самая дальняя ночь, открытая хотя бы у одного игрока на сервере
local function unlockedMax()
	local best = testMax or 1
	for _, p in ipairs(Players:GetPlayers()) do
		local profile = S.Data.Get(p)
		if profile then
			best = math.max(best, tonumber(profile.NightUnlocked) or 1)
		end
	end
	return math.clamp(best, 1, Config.NightCount)
end

local function refreshNights()
	local max = unlockedMax()
	S.Net.Set("NightMax", max)
	if not userPicked then
		selected = max
	end
	selected = math.clamp(selected, 1, max)
	if phase == "Lobby" or phase == "Countdown" then
		S.Net.Set("Night", selected)
	end
end

function ShiftManager.Night()
	return night
end

-- Только для проверки на сервере без игроков: считать открытыми ночи до n (из игры не вызывается)
function ShiftManager.TestUnlock(n)
	testMax = n
end

-- Игрок выбрал ночь в лобби
function ShiftManager.SelectNight(player, n)
	if phase ~= "Lobby" or startRequested then
		return
	end
	n = math.floor(tonumber(n) or 0)
	if n < 1 or n > unlockedMax() then
		return
	end
	userPicked = true
	if n ~= selected then
		selected = n
		S.Net.Set("Night", n)
		local info = Texts.Nights[n]
		S.Net.Notify(nil, string.format("%s выбрал(а) ночь %d — «%s»", player.DisplayName, n, info and info.Title or ""), "info")
	end
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
	if phase ~= "Intro" or introDone[player] then
		return
	end
	introDone[player] = true
	local done, total = 0, 0
	for p in pairs(introPlayers) do
		if p.Parent then
			total = total + 1
			if introDone[p] then
				done = done + 1
			end
		end
	end
	S.Net.Set("IntroDone", done)
	S.Net.Set("IntroTotal", total)
	-- v15: кто пропустил командную сцену, сразу встаёт на общую точку старта у входа (управление — когда
	-- досмотрят все: до этого фаза остаётся "Intro")
	local spot = teamIntro and introSpots[player.UserId]
	local ch = player.Character
	if spot and ch then
		ch:PivotTo(CFrame.lookAt(spot + Vector3.new(0, 3, 0), spot + Vector3.new(0, 3, -10)))
	end
end

-- Счётчики для итогов смены: Caught, Escaped, Orders, FalseChecks, LeftAngry
local extra = {}
function ShiftManager.AddStat(key, n)
	extra[key] = (extra[key] or 0) + (n or 1)
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
	refreshNights()
	night = selected
	minutes = 0
	served = 0
	finishKind = nil
	S.Net.Set("Night", night)
	S.Net.Set("Ending", "")
	publishClock()
	S.Store.SetLobby(false)
	setPhase("Shift")
	S.Events.Plan(night)
	S.Events.OnHour(0)
	S.Tasks.OnHour(0)
	S.Customers.OnShiftStart()
	-- охранник говорит сам с собой в начале смены (v10)
	task.delay(6, function()
		if phase == "Shift" then
			S.Net.PlayerVoice(nil, night >= 2 and "Start3" or (math.random() < 0.5 and "Start1" or "Start2"))
		end
	end)
	local info = Texts.Nights[night]
	S.Net.Notify(nil, string.format("Ночь %d — «%s». Смена до 06:00", night, info and info.Title or ""), "info")
	S.Events.OnMinute(0)
	-- v15: после командной кат-сцены первое задание — прочитать инструкции на стойке охраны
	if teamIntro then
		S.Tasks.Add({ Id = "instructions", Kind = "instructions", Text = Texts.TeamFirstTask, Room = "Пост охраны у входа", Count = 1 })
	end
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
		Caught = extra.Caught or 0,
		Escaped = extra.Escaped or 0,
		Orders = extra.Orders or 0,
		FalseChecks = extra.FalseChecks or 0,
		LeftAngry = extra.LeftAngry or 0,
	}
	for _, p in ipairs(Players:GetPlayers()) do
		S.Data.RecordShift(p, kind, stats)
	end
	S.Customers.Reset()
	if S.Beast then
		S.Beast.Reset()
	end
	S.Net.Effect(nil, "Ending", stats)
	if kind == "Good" then
		S.Net.PA("ShiftOver")
		local info = Texts.Nights[night]
		local after = info and info.GoodPhone or { Texts.Unknown, Texts.Endings.Good.Phone }
		task.delay(9, function()
			S.Net.Phone(nil, after[1], after[2])
		end)
	end
	-- следующая ночь: после хорошей или секретной концовки — дальше, после плохой — та же ночь
	if kind == "Bad" then
		selected = night
		userPicked = true
	else
		userPicked = false
	end
	print(string.format("[Смена] ночь %d, концовка %s, выполнено %d%%", night, kind, pct))
end

local function resetAll()
	S.Tasks.Reset()
	S.Store.Reset()
	S.Checkout.Reset()
	S.Security.Reset()
	extra = {}
	S.Customers.Reset()
	S.Power.Reset()
	S.Doors.Reset()
	S.Monster.Reset()
	S.Secrets.Reset()
	S.Events.Reset()
	if S.Beast then
		S.Beast.Reset()
	end
	minutes = 0
	publishClock()
	S.Net.Set("Ending", "")
	S.Net.Set("Countdown", 0)
	startRequested = false
	setPhase("Lobby")
	refreshNights()
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
			refreshNights()
			while not startRequested and left > 0 do
				task.wait(1)
				refreshNights() -- профили игроков могли загрузиться только что
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
			-- полная кат-сцена — перед первой ночью, перед остальными — короткий титр «НОЧЬ N»
			refreshNights()
			local short = selected > 1
			-- v15: 2–4 игрока перед первой ночью — командная кат-сцена (едут вместе в одной машине).
			-- Старт у всех в один момент серверного времени; роли — по порядку входа
			local roster = (not short and Config.TeamIntro) and teamRoster() or {}
			teamIntro = #roster >= 2
			setPhase("Intro")
			local introLimit = short and 18 or Config.IntroSeconds + 8
			introSpots = {}
			S.Net.Set("IntroDone", 0)
			S.Net.Set("IntroTotal", #Players:GetPlayers())
			if teamIntro then
				for _, r in ipairs(roster) do
					introSpots[r.UserId] = TeamLines.EndSpots[r.Role]
				end
				local seconds = TeamLines.Duration(#roster, Sounds.List, VoiceLines.Clips)
				S.Net.Effect(nil, "Intro", {
					Team = true,
					Roster = roster,
					StartAt = workspace:GetServerTimeNow() + TeamLines.StartDelay,
					Seconds = seconds,
					Night = selected,
					Short = false,
				})
				introLimit = seconds + TeamLines.StartDelay + 10
			else
				S.Net.Effect(nil, "Intro", { Seconds = Config.IntroSeconds, Night = selected, Short = short })
			end
			local introStart = os.clock()
			while os.clock() - introStart < introLimit do
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
			-- (v15: после командной сцены — у входа в магазин, там, где команда стоит в конце сцены)
			local spots = introSpots
			for i, p in ipairs(Players:GetPlayers()) do
				local ch = p.Character
				if ch then
					local spot = spots[p.UserId]
					if spot then
						ch:PivotTo(CFrame.lookAt(spot + Vector3.new(0, 3, 0), spot + Vector3.new(0, 3, -10)))
					elseif teamIntro then
						-- пятый и дальше (в машине мест нет): рядом с командой
						local x = -50.5 + (i - 5) * 2.4
						ch:PivotTo(CFrame.lookAt(Vector3.new(x, 3, 37.6), Vector3.new(x, 3, 27)))
					else
						ch:PivotTo(map.Points.IntroEnd * CFrame.new((i - 2.5) * 2.4, 0, 0))
					end
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
