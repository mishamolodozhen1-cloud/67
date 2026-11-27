-- Проверка этапа 1 DUMMY COMBAT на настоящем сервере Roblox (Open Cloud, безголовый сервер):
--   python3 tools/cloud.py test
-- Проверяет структуру плейса, конфиги, общие модули, запуск сервисов, сеть (создание remotes,
-- проверку аргументов, лимиты, нарушения), сбор ошибок, сессии игроков и логику клиентских
-- контроллеров. Живого клиента здесь нет: то, что требует настоящего игрока, отмечено в отчёте.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local StarterPlayer = game:GetService("StarterPlayer")
local StarterGui = game:GetService("StarterGui")
local ServerStorage = game:GetService("ServerStorage")
local Lighting = game:GetService("Lighting")

local results, notes = {}, {}
local function note(s)
	table.insert(notes, s)
end
local function test(name, fn)
	local ok, err = pcall(fn)
	table.insert(results, { Name = name, Ok = ok, Err = err })
end
local function expect(cond, msg)
	if not cond then
		error(msg or "условие не выполнено", 2)
	end
end
local function eq(actual, expected, msg)
	if actual ~= expected then
		error(string.format("%s: ждали %s, получили %s", msg or "", tostring(expected), tostring(actual)), 2)
	end
end

note("скрипты плейса уже запустили сервер до теста: " .. tostring(ServerScriptService:GetAttribute("DC_BootState")))

---------------------------------------------------------------------------- структура
test("структура плейса", function()
	local function at(root, path, class)
		local cur = root
		for part in string.gmatch(path, "[^%.]+") do
			cur = cur:FindFirstChild(part)
			expect(cur, "нет " .. root.Name .. "." .. path)
		end
		eq(cur.ClassName, class, path)
		return cur
	end
	at(ReplicatedStorage, "Shared", "Folder")
	for _, m in ipairs({ "Logger", "Signal", "Maid", "Validate", "RateLimiter", "ModuleLoader" }) do
		at(ReplicatedStorage, "Shared." .. m, "ModuleScript")
	end
	at(ReplicatedStorage, "Remotes", "Folder")
	at(ReplicatedStorage, "Assets", "Folder")
	for _, m in ipairs({ "GameConfig", "RemoteDefinitions", "BuildInfo" }) do
		at(ReplicatedStorage, "Configs." .. m, "ModuleScript")
	end
	at(ServerScriptService, "Server.Main", "Script")
	at(ServerScriptService, "Server.Bootstrap", "ModuleScript")
	for _, m in ipairs({ "ErrorService", "NetService", "PlayerService" }) do
		at(ServerScriptService, "Services." .. m, "ModuleScript")
	end
	at(ServerScriptService, "Systems", "Folder")
	at(StarterPlayer, "StarterPlayerScripts.Client.Main", "LocalScript")
	at(StarterPlayer, "StarterPlayerScripts.Client.Controllers.ClientNet", "ModuleScript")
	at(StarterPlayer, "StarterPlayerScripts.Client.Controllers.ErrorReporter", "ModuleScript")
	at(StarterPlayer, "StarterCharacterScripts", "StarterCharacterScripts")
	for _, g in ipairs({ "MainUI", "HUD", "Menus" }) do
		local gui = at(StarterGui, g, "ScreenGui")
		eq(gui.ResetOnSpawn, false, g .. ".ResetOnSpawn")
		eq(gui.IgnoreGuiInset, true, g .. ".IgnoreGuiInset")
	end
	for _, f in ipairs({ "Weapons", "Maps", "CharacterAssets" }) do
		at(ServerStorage, f, "Folder")
	end
	for _, f in ipairs({ "Lobby", "ActiveMap", "SpawnLocations" }) do
		at(workspace, f, "Folder")
	end
	local spawn = at(workspace, "SpawnLocations.BootstrapSpawn", "SpawnLocation")
	expect(spawn.Anchored and spawn.Neutral, "точка появления должна быть закреплена и общей")
	eq(spawn.Size, Vector3.new(12, 1, 12), "размер точки появления")
	eq(workspace.StreamingEnabled, false, "StreamingEnabled")
	-- Lighting.Technology в облачной среде читать нельзя (нет прав RobloxScript) — проверяем, если можно
	local okTech, tech = pcall(function()
		return Lighting.Technology
	end)
	if okTech then
		eq(tech, Enum.Technology.Future, "Lighting.Technology")
	else
		note("Lighting.Technology не читается в облачной среде (нет прав); Future записан сборщиком")
	end
end)

---------------------------------------------------------------------------- конфиги
local Configs = ReplicatedStorage.Configs
local GameConfig = require(Configs.GameConfig)
local Definitions = require(Configs.RemoteDefinitions)
local BuildInfo = require(Configs.BuildInfo)

test("конфиги заморожены", function()
	expect(table.isfrozen(GameConfig), "GameConfig не заморожен")
	expect(table.isfrozen(GameConfig.Net), "GameConfig.Net не заморожен")
	expect(not pcall(function()
		GameConfig.GameName = "X"
	end), "GameConfig можно изменить")
	expect(table.isfrozen(Definitions) and table.isfrozen(Definitions.ClientError.Rate), "RemoteDefinitions не заморожены")
	eq(GameConfig.GameName, "DUMMY COMBAT", "название")
	eq(BuildInfo.Version, "0.1.0", "версия сборки")
	expect(type(BuildInfo.Commit) == "string" and #BuildInfo.Commit >= 7, "нет коммита в BuildInfo")
	note("сборка " .. BuildInfo.Version .. " " .. BuildInfo.Commit .. " " .. BuildInfo.BuiltAt)
end)

---------------------------------------------------------------------------- общие модули
local Shared = ReplicatedStorage.Shared
local Logger = require(Shared.Logger)
local Signal = require(Shared.Signal)
local Maid = require(Shared.Maid)
local Validate = require(Shared.Validate)
local RateLimiter = require(Shared.RateLimiter)
local ModuleLoader = require(Shared.ModuleLoader)

test("Logger: уровни, повторы, формат, приёмники", function()
	local before = Logger.GetLevel()
	Logger.Configure({ Level = "Debug" })
	local log = Logger.new("Test")
	local got = {}
	local remove = Logger.AddSink(function(e)
		table.insert(got, e)
	end)
	local e1 = log:Info("число %d и таблица %s", 42, { a = 1 })
	expect(e1 and e1.Message == "число 42 и таблица {a=1}", "формат: " .. tostring(e1 and e1.Message))
	local e2 = log:Info("неверный формат %d", "текст")
	expect(e2 and string.find(e2.Message, "неверный формат", 1, true), "запасной формат не сработал")
	local cyc = {}
	cyc.self = cyc
	local e3 = log:Debug("цикл %s", cyc)
	expect(e3 and string.find(e3.Message, "<цикл>", 1, true), "цикл в таблице: " .. tostring(e3 and e3.Message))
	-- повтор: второе такое же сообщение подряд не печатается
	local first = log:Warn("повтор-проверка")
	local second = log:Warn("повтор-проверка")
	expect(first and second == nil, "повтор не подавлен")
	-- уровень: Debug не проходит при Warn
	Logger.Configure({ Level = "Warn" })
	expect(log:Info("не должно пройти") == nil, "Info прошёл при уровне Warn")
	Logger.Configure({ Level = "Debug" })
	expect(#got >= 4, "приёмник получил " .. #got)
	remove()
	local n = #got
	log:Info("после отключения приёмника")
	eq(#got, n, "отключённый приёмник")
	local hist = Logger.GetHistory(3)
	eq(#hist, 3, "история")
	eq(hist[3].Message, "после отключения приёмника", "последняя запись истории")
	Logger.Configure({ Level = before })
end)

test("Signal: порядок, отключение, Once, Wait, ошибка в обработчике", function()
	local s = Signal.new()
	local order = {}
	local c1 = s:Connect(function(x)
		table.insert(order, "a" .. x)
	end)
	s:Connect(function()
		error("DC_TEST_SIGNAL_HANDLER")
	end)
	s:Connect(function(x)
		table.insert(order, "c" .. x)
	end)
	s:Fire(1)
	eq(table.concat(order, ","), "a1,c1", "порядок и изоляция ошибок")
	c1:Disconnect()
	expect(not c1.Connected, "Disconnect")
	s:Fire(2)
	eq(table.concat(order, ","), "a1,c1,c2", "после Disconnect")
	local once = 0
	s:Once(function()
		once = once + 1
	end)
	s:Fire(3)
	s:Fire(4)
	eq(once, 1, "Once")
	task.delay(0.05, function()
		s:Fire("x", 7)
	end)
	local a, b = s:Wait()
	expect(a == "x" and b == 7, "Wait вернул " .. tostring(a) .. "," .. tostring(b))
	s:DisconnectAll()
	eq(s:ConnectionCount(), 0, "DisconnectAll")
end)

test("Maid: уборка всего и в обратном порядке", function()
	local m = Maid.new()
	local order = {}
	local part = Instance.new("Part")
	part.Parent = workspace
	m:Give(part)
	local be = Instance.new("BindableEvent")
	local conn = m:Give(be.Event:Connect(function() end))
	local thread = m:Give(task.delay(10, function() end))
	local obj = m:Give({
		Destroy = function()
			table.insert(order, "obj")
		end,
	})
	expect(obj, "Give возвращает предмет")
	m:Give(function()
		table.insert(order, "fn")
	end)
	eq(m:Count(), 5, "Count")
	m:Cleanup()
	eq(part.Parent, nil, "деталь удалена")
	expect(not conn.Connected, "соединение отключено")
	eq(coroutine.status(thread), "dead", "поток отменён")
	eq(table.concat(order, ","), "fn,obj", "обратный порядок")
	eq(m:Count(), 0, "после уборки пусто")
	be:Destroy()
	expect(not pcall(function()
		m:Give(42)
	end), "число нельзя отдать на уборку")
end)

test("Validate: числа, строки, векторы, таблицы, аргументы", function()
	local num = Validate.Number({ Min = 0, Max = 10, Integer = true })
	expect(num(5), "5")
	expect(not num(0 / 0), "NaN")
	expect(not num(math.huge), "inf")
	expect(not num(11), "больше Max")
	expect(not num(2.5), "не целое")
	expect(not num("5"), "строка вместо числа")
	local str = Validate.String({ Max = 8 })
	expect(str("привет") == false, "12 байт > 8")
	expect(str("ok"), "ok")
	expect(not str("\255\254"), "битый UTF-8")
	expect(not str(nil), "nil")
	local vec = Validate.Vector3({ MaxMagnitude = 100 })
	expect(vec(Vector3.new(1, 2, 3)), "вектор")
	expect(not vec(Vector3.new(0 / 0, 0, 0)), "вектор с NaN")
	expect(not vec(Vector3.new(1000, 0, 0)), "вектор длиннее")
	expect(not vec({ X = 1, Y = 2, Z = 3 }), "таблица вместо вектора")
	local cf = Validate.CFrame()
	expect(cf(CFrame.new(1, 2, 3)) and not cf(CFrame.new(0 / 0, 0, 0)), "CFrame")
	expect(Validate.OneOf({ "A", "B" })("A") and not Validate.OneOf({ "A" })("C"), "OneOf")
	expect(Validate.Optional(num)(nil) and not Validate.Optional(num)(-1), "Optional")
	local arr = Validate.Array(num, { Max = 3 })
	expect(arr({ 1, 2, 3 }), "массив")
	expect(not arr({ 1, 2, 3, 4 }), "массив длиннее")
	expect(not arr({ 1, nil, 3 }), "массив с дырой")
	expect(not arr({ 1, x = 2 }), "массив с посторонним ключом")
	local shape = Validate.Shape({ Id = num, Name = Validate.Optional(str) })
	expect(shape({ Id = 1 }), "форма")
	expect(not shape({ Id = 1, Extra = true }), "лишнее поле")
	expect(not shape({ Name = "x" }), "нет обязательного поля")
	local ok1 = Validate.Args({ num, str }, 1, "a")
	local ok2, why2 = Validate.Args({ num, str }, 1, "a", "лишний")
	local ok3 = Validate.Args({ num, str }, 1)
	local ok4 = Validate.Args({}, nil)
	expect(ok1, "верные аргументы")
	expect(not ok2 and string.find(why2, "лишние", 1, true), "лишний аргумент")
	expect(not ok3, "не хватает аргумента")
	expect(not ok4, "лишний nil-аргумент тоже считается")
	expect(Validate.Instance("BasePart")(Instance.new("Part")) and not Validate.Instance("BasePart")(Instance.new("Folder")), "Instance")
end)

test("RateLimiter: всплеск и восполнение", function()
	local now = 0
	local rl = RateLimiter.new(3, 2, function()
		return now
	end)
	expect(rl:Allow("p") and rl:Allow("p") and rl:Allow("p"), "три сразу")
	expect(not rl:Allow("p"), "четвёртый сразу — нельзя")
	expect(rl:Allow("q"), "другой ключ — своё ведро")
	now = 0.5
	expect(rl:Allow("p"), "через 0.5 с восполнился один")
	expect(not rl:Allow("p"), "и только один")
	now = 100
	for _ = 1, 3 do
		expect(rl:Allow("p"), "после долгой паузы — снова всплеск")
	end
	expect(not rl:Allow("p"), "но не больше Burst")
	rl:Forget("p")
	expect(rl:Allow("p"), "Forget")
	expect(not pcall(RateLimiter.new, 0, 1), "Burst 0 запрещён")
end)

test("ModuleLoader: порядок, ошибки, критичные модули, неподключённые", function()
	local folder = Instance.new("Folder")
	folder.Name = "LoaderTest"
	local a = Shared.Signal:Clone()
	a.Name = "A"
	a.Parent = folder
	local b = Shared.RateLimiter:Clone()
	b.Name = "B"
	b.Parent = folder
	local extra = Shared.Maid:Clone()
	extra.Name = "Extra"
	extra.Parent = folder
	folder.Parent = ServerStorage
	-- модули-«пустышки»: берём копии, подменяем им Init/Start (require кэширует таблицу по объекту)
	local calls = {}
	local ma = require(a)
	ma.Init = function(ctx)
		table.insert(calls, "A.Init")
		expect(ctx.Get("B"), "Get из Init")
	end
	ma.Start = function()
		table.insert(calls, "A.Start")
	end
	local mb = require(b)
	mb.Init = function()
		table.insert(calls, "B.Init")
		error("DC_TEST_INIT_FAIL")
	end
	mb.Start = function()
		table.insert(calls, "B.Start")
	end
	local report = ModuleLoader.Run({ Name = "LoaderTest", Folder = folder, Order = { "A", "B", "Missing" }, Critical = { B = true }, WaitTimeout = 0.1 })
	eq(table.concat(calls, ","), "A.Init,B.Init,A.Start", "порядок вызовов (B после ошибки не стартует)")
	eq(report.Status.A, "Started", "A")
	eq(report.Status.B, "Failed:Init", "B")
	eq(report.Status.Missing, "Failed:Require", "Missing")
	eq(report.Failures, 2, "ошибок")
	expect(report.CriticalFailed, "критичный B упал")
	local warned = false
	for _, e in ipairs(Logger.GetHistory(30)) do
		if e.Scope == "LoaderTest" and string.find(e.Message, "Extra", 1, true) then
			warned = true
		end
	end
	expect(warned, "нет предупреждения о неподключённом модуле Extra")
	folder:Destroy()
end)

---------------------------------------------------------------------------- запуск сервера
local Bootstrap = require(ServerScriptService.Server.Bootstrap)
local report

test("Bootstrap: все сервисы запущены", function()
	report = Bootstrap.Start()
	eq(report.State, "Ready", "состояние")
	eq(report.Failures, 0, "ошибок запуска")
	for _, name in ipairs({ "ErrorService", "NetService", "PlayerService" }) do
		eq(report.Status[name], "Started", name)
	end
	eq(ServerScriptService:GetAttribute("DC_BootState"), "Ready", "атрибут DC_BootState")
	expect(Bootstrap.Start() == report, "повторный Start возвращает тот же отчёт")
	note(string.format("запуск сервисов: %.3f с", report.Seconds or -1))
end)

local Net = Bootstrap.Get("NetService")
local Errors = Bootstrap.Get("ErrorService")
local PlayerService = Bootstrap.Get("PlayerService")

local function fakePlayer(id)
	local p = { Name = "Fake" .. id, UserId = -id, Kicked = false }
	function p:Kick()
		self.Kicked = true
	end
	return p
end

test("NetService: remotes по списку, посторонние удаляются", function()
	local folder = ReplicatedStorage.Remotes
	eq(folder:GetAttribute("Ready"), true, "Remotes.Ready")
	local count = 0
	for name, def in pairs(Definitions) do
		count = count + 1
		local r = folder:FindFirstChild(name)
		expect(r, "нет remote " .. name)
		eq(r.ClassName, def.Kind == "Event" and "RemoteEvent" or "UnreliableRemoteEvent", name)
	end
	eq(#folder:GetChildren(), count, "лишние объекты в Remotes")
	local keep = folder.ClientReady
	local stray = Instance.new("RemoteEvent")
	stray.Name = "GiveMeMoney"
	stray.Parent = folder
	local wrong = Instance.new("RemoteFunction")
	wrong.Name = "ServerInfoX"
	wrong.Parent = folder
	Net.SyncRemotes()
	eq(stray.Parent, nil, "посторонний remote не удалён")
	eq(wrong.Parent, nil, "второй посторонний не удалён")
	expect(folder.ClientReady == keep, "существующий remote пересоздан (клиенты потеряли бы ссылку)")
	eq(#Net.CheckDefinitions(Definitions), 0, "ошибки в RemoteDefinitions")
	local bad = Net.CheckDefinitions({ A = { Kind = "Weird", Direction = "Up" }, B = { Kind = "Event", Direction = "ToServer", Args = { 5 } } })
	expect(#bad >= 4, "проверка списка нашла " .. #bad .. " проблем")
end)

test("NetService: проверка аргументов, лимит, ошибки обработчика, нарушения", function()
	local got = {}
	local handler = Net.BuildHandler("ClientError", function(player, message, trace, kind)
		table.insert(got, { player, message, trace, kind })
		if message == "boom" then
			error("DC_TEST_HANDLER_ERROR")
		end
	end)
	local p = fakePlayer(1)
	local violations = {}
	local vconn = Net.Violation:Connect(function(player, name, reason)
		table.insert(violations, name .. ":" .. reason)
	end)
	handler(p, "ok", "trace", "Error")
	eq(#got, 1, "верный вызов")
	expect(got[1][1] == p and got[1][2] == "ok" and got[1][4] == "Error", "аргументы дошли как есть")
	handler(p, 123, "trace", "Error")
	handler(p, "ok", "trace", "Hack")
	handler(p, "ok", "trace", "Error", "extra")
	handler(p, string.rep("x", GameConfig.ClientErrors.MaxMessage + 1), "", "Error")
	eq(#got, 1, "неверные вызовы не дошли до обработчика")
	eq(Net.ViolationCount(p), 4, "нарушений")
	-- обработчик упал: исключение не выходит наружу
	local p2 = fakePlayer(2)
	local okCall = pcall(handler, p2, "boom", "", "Error")
	expect(okCall, "ошибка обработчика вышла наружу")
	-- лимит частоты: Burst = 5 (один вызов уже был выше у p2)
	for _ = 1, 4 do
		handler(p2, "ok", "", "Error")
	end
	local before = #got
	handler(p2, "ok", "", "Error")
	eq(#got, before, "шестой подряд прошёл мимо лимита")
	expect(Net.ViolationCount(p2) == 1, "превышение лимита — нарушение")
	-- много нарушений — отключение
	local p3 = fakePlayer(3)
	for _ = 1, GameConfig.Net.ViolationLimit do
		handler(p3, 1, 2, 3)
	end
	expect(p3.Kicked, "игрок с " .. GameConfig.Net.ViolationLimit .. " нарушениями не отключён")
	task.wait(0.1)
	expect(#violations >= 4, "сигнал Violation")
	vconn:Disconnect()
	-- отправка: только ToClient/Both и только игроку
	expect(not Net.Fire(p, "ServerInfo", {}), "Fire не игроку")
	expect(not Net.Fire(nil, "ClientReady"), "Fire события ToServer")
	expect(not Net.FireAll("NoSuchEvent"), "FireAll неизвестного события")
	expect(Net.FireAll("ServerInfo", { Test = true }), "FireAll ServerInfo (игроков нет — просто уходит)")
	expect(not pcall(Net.Connect, "ClientError", function() end), "второй обработчик для ClientError")
	expect(not pcall(Net.Connect, "ServerInfo", function() end), "Connect события ToClient")
end)

test("ErrorService: ошибки сервера, журнала и клиентов", function()
	local before = Errors.Total()
	task.spawn(function()
		error("DC_TEST_SERVER_ERROR")
	end)
	Logger.new("Test"):Error("DC_TEST_LOG_ERROR")
	task.wait(0.2)
	local foundServer, foundLog = false, false
	for _, e in ipairs(Errors.GetRecent(50)) do
		if e.Source == "Server" and string.find(e.Message, "DC_TEST_SERVER_ERROR", 1, true) then
			foundServer = true
		end
		if e.Source == "Log" and string.find(e.Message, "DC_TEST_LOG_ERROR", 1, true) then
			foundLog = true
		end
	end
	expect(foundLog, "ошибка журнала не записана")
	if foundServer then
		note("ошибка серверного скрипта поймана через ScriptContext.Error")
	else
		note("ScriptContext.Error в среде Open Cloud не сработал на ошибку тестового потока — проверить в Studio")
	end
	-- ошибки клиента — через настоящий обработчик ClientError (с проверками NetService)
	local handler = Net.BuildHandler("ClientError", Errors.OnClientError)
	local p = fakePlayer(10)
	handler(p, "клиент упал: attempt to index nil", "Players.Fake.PlayerScripts.Client:10", "Error")
	local recent = Errors.GetRecent(1, "Client")
	expect(recent[1] and recent[1].UserId == -10 and recent[1].Kind == "Error", "ошибка клиента не записана")
	-- лимит ошибок за сессию проверяем на самом сервисе: через обработчик раньше сработал бы лимит частоты
	local p2 = fakePlayer(11)
	local accepted = 0
	for i = 1, GameConfig.ClientErrors.MaxPerSession + 5 do
		if Errors.OnClientError(p2, "ошибка " .. i, "", "Error") then
			accepted = accepted + 1
		end
	end
	eq(accepted, GameConfig.ClientErrors.MaxPerSession, "лимит ошибок клиента за сессию")
	expect(#Errors.GetRecent() <= GameConfig.ClientErrors.History, "история не ограничена")
	expect(Errors.Total() > before, "счётчик")
end)

test("PlayerService: данные сервера, защита от чужих объектов", function()
	local info = PlayerService.ServerInfo()
	eq(info.Game, "DUMMY COMBAT", "Game")
	eq(info.Version, BuildInfo.Version, "Version")
	eq(info.Build, BuildInfo.Commit, "Build")
	expect(type(info.PlaceVersion) == "number", "PlaceVersion")
	expect(math.abs(info.ServerTime - workspace:GetServerTimeNow()) < 1, "ServerTime")
	eq(PlayerService.MarkReady(fakePlayer(20)), nil, "не игрок не может стать «готовым»")
	eq(#PlayerService.ReadyPlayers(), 0, "готовых игроков нет (сервер без игроков)")
end)

---------------------------------------------------------------------------- клиентские контроллеры (логика)
local Controllers = StarterPlayer.StarterPlayerScripts.Client.Controllers

test("ErrorReporter: обрезка UTF-8, один раз за сессию, лимит", function()
	local ER = require(Controllers.ErrorReporter)
	local long = string.rep("ошибка ", 200)
	local clipped = ER.Clip(long, 100)
	expect(#clipped <= 100, "длина " .. #clipped)
	expect(utf8.len(clipped) ~= nil, "обрезка разрезала символ")
	expect(utf8.len(ER.Clip("a\255b", 10)) ~= nil, "битые байты не заменены")
	local strCheck = Definitions.ClientError.Args[1]
	expect(strCheck((ER.Prepare(long, ""))), "сервер не принял бы подготовленный текст")
	local traceCheck = Definitions.ClientError.Args[2]
	local _, tr = ER.Prepare("x", string.rep("стек\n", 1000))
	expect(traceCheck(tr), "сервер не принял бы подготовленный стек")
	expect(ER.Report("Error", "DC_TEST_CLIENT_A", "trace"), "первая ошибка")
	expect(not ER.Report("Error", "DC_TEST_CLIENT_A", "trace"), "та же ошибка второй раз")
	local n = 1
	for i = 1, GameConfig.ClientErrors.MaxPerSession + 3 do
		if ER.Report("Error", "DC_TEST_CLIENT_" .. i, "") then
			n = n + 1
		end
	end
	eq(n, GameConfig.ClientErrors.MaxPerSession, "лимит за сессию")
end)

test("ClientNet: честный клиент не превышает серверный лимит", function()
	local CN = require(Controllers.ClientNet)
	expect(not CN.IsReady(), "без Init сеть не готова")
	-- одинаковая случайная последовательность попыток: клиент отпускает — сервер обязан принять
	for name, def in pairs(Definitions) do
		if def.Rate then
			local now = 0
			local clock = function()
				return now
			end
			local client = CN.MakeLimiter(def, clock)
			local server = RateLimiter.new(def.Rate.Burst, def.Rate.PerSecond, clock)
			local rng = Random.new(7)
			local sent = 0
			for _ = 1, 2000 do
				now = now + rng:NextNumber(0, 2 / def.Rate.PerSecond)
				if client:Allow("me") then
					sent = sent + 1
					expect(server:Allow("me"), name .. ": сервер отклонил честный клиент на t=" .. string.format("%.2f", now))
				end
			end
			expect(sent > 0, name .. ": клиент ничего не отправил")
		end
	end
end)

---------------------------------------------------------------------------- итог
local passed, failed = 0, {}
for _, r in ipairs(results) do
	if r.Ok then
		passed = passed + 1
	else
		table.insert(failed, r.Name .. " → " .. tostring(r.Err))
	end
end
local tail = {}
for _, e in ipairs(Logger.GetHistory(12)) do
	table.insert(tail, "[" .. e.LevelName .. "][" .. e.Scope .. "] " .. e.Message)
end
return string.format("ПРОЙДЕНО %d из %d", passed, #results),
	"ПРОВАЛЫ: " .. (#failed == 0 and "нет" or table.concat(failed, " | ")),
	"ЗАМЕТКИ: " .. table.concat(notes, " | "),
	"ЖУРНАЛ: " .. table.concat(tail, " || ")
