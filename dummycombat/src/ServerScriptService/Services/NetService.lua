-- NetService: все сетевые события сервера идут через этот модуль.
--
--   Net.Connect("ClientError", function(player, message, trace, kind) ... end)
--   Net.Fire(player, "ServerInfo", info) / Net.FireAll(...) / Net.FireExcept(player, ...)
--
-- Что он делает:
--   • при запуске создаёт объекты в ReplicatedStorage.Remotes строго по Configs/RemoteDefinitions
--     (лишние и не того класса — удаляет: у них нет схемы проверки) и ставит папке атрибут Ready;
--   • каждое сообщение от клиента сначала проходит лимит частоты (RateLimiter на игрока), потом
--     проверку аргументов (Validate.Args), и только потом попадает в обработчик;
--   • ошибка обработчика не роняет сервер и не уходит клиенту — пишется в журнал;
--   • нарушения (слишком часто, неверные аргументы) считаются на игрока; если их больше
--     ViolationLimit за ViolationWindow секунд — игрока отключают (KickOnViolations);
--   • отправить клиенту можно только событие с Direction ToClient/Both, принять — только ToServer/Both.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Configs = ReplicatedStorage:WaitForChild("Configs")
local Logger = require(Shared:WaitForChild("Logger"))
local Validate = require(Shared:WaitForChild("Validate"))
local RateLimiter = require(Shared:WaitForChild("RateLimiter"))
local Signal = require(Shared:WaitForChild("Signal"))
local GameConfig = require(Configs:WaitForChild("GameConfig"))
local Definitions = require(Configs:WaitForChild("RemoteDefinitions"))

local NetService = { Name = "NetService" }

-- Нарушение от игрока: (player, имя события, причина)
NetService.Violation = Signal.new()

local log = Logger.new("Net")
local cfg = GameConfig.Net

local CLASS_OF_KIND = { Event = "RemoteEvent", UnreliableEvent = "UnreliableRemoteEvent" }
local DIRECTIONS = { ToServer = true, ToClient = true, Both = true }

local folder = nil
local remotes = {}
local limiters = {}
local connected = {}
local violations = {}

local function fromClient(def)
	return def.Direction == "ToServer" or def.Direction == "Both"
end

local function toClient(def)
	return def.Direction == "ToClient" or def.Direction == "Both"
end

-- Проверка списка событий: ошибка в конфиге должна ловиться при запуске, а не в разгар матча
function NetService.CheckDefinitions(defs)
	local problems = {}
	for name, def in pairs(defs) do
		if type(name) ~= "string" or name == "" then
			table.insert(problems, "имя события должно быть строкой")
		elseif type(def) ~= "table" then
			table.insert(problems, name .. ": описание должно быть таблицей")
		else
			if not CLASS_OF_KIND[def.Kind] then
				table.insert(problems, name .. ": неизвестный Kind " .. tostring(def.Kind))
			end
			if not DIRECTIONS[def.Direction] then
				table.insert(problems, name .. ": неизвестный Direction " .. tostring(def.Direction))
			end
			if fromClient(def) then
				if type(def.Args) ~= "table" then
					table.insert(problems, name .. ": нет схемы аргументов Args")
				else
					for i, check in ipairs(def.Args) do
						if type(check) ~= "function" then
							table.insert(problems, name .. ": Args[" .. i .. "] — не валидатор")
						end
					end
				end
				local rate = def.Rate
				if type(rate) ~= "table" or type(rate.Burst) ~= "number" or rate.Burst < 1 or type(rate.PerSecond) ~= "number" or rate.PerSecond <= 0 then
					table.insert(problems, name .. ": нужен Rate { Burst ≥ 1, PerSecond > 0 }")
				end
			end
		end
	end
	table.sort(problems)
	return problems
end

-- Привести ReplicatedStorage.Remotes в соответствие со списком событий (можно вызывать повторно)
function NetService.SyncRemotes()
	folder = ReplicatedStorage:FindFirstChild(cfg.RemotesFolder)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = cfg.RemotesFolder
		folder.Parent = ReplicatedStorage
	end
	for _, child in ipairs(folder:GetChildren()) do
		local def = Definitions[child.Name]
		if not def or child.ClassName ~= CLASS_OF_KIND[def.Kind] then
			log:Warn("удалён посторонний объект Remotes.%s (%s): его нет в RemoteDefinitions", child.Name, child.ClassName)
			child:Destroy()
		end
	end
	local count = 0
	for name, def in pairs(Definitions) do
		local remote = folder:FindFirstChild(name)
		if not remote then
			remote = Instance.new(CLASS_OF_KIND[def.Kind])
			remote.Name = name
			remote.Parent = folder
		end
		remotes[name] = remote
		count = count + 1
	end
	folder:SetAttribute("Count", count)
	folder:SetAttribute("Ready", true)
	return remotes
end

function NetService.GetRemote(name)
	return remotes[name]
end

local function violation(player, name, reason)
	local now = os.clock()
	local v = violations[player]
	if not v or now - v.Start > cfg.ViolationWindow then
		v = { Count = 0, Start = now, Kicked = false }
		violations[player] = v
	end
	v.Count = v.Count + 1
	log:Warn("нарушение: %s (%s) → %s: %s [%d за %d с]", tostring(player.Name), tostring(player.UserId), name, reason, v.Count, cfg.ViolationWindow)
	NetService.Violation:Fire(player, name, reason)
	if cfg.KickOnViolations and v.Count >= cfg.ViolationLimit and not v.Kicked then
		v.Kicked = true
		log:Warn("игрок %s (%s) отключён: слишком много неверных запросов", tostring(player.Name), tostring(player.UserId))
		pcall(function()
			player:Kick("Соединение закрыто: слишком много неверных запросов к серверу.")
		end)
	end
end

function NetService.ViolationCount(player)
	local v = violations[player]
	if not v or os.clock() - v.Start > cfg.ViolationWindow then
		return 0
	end
	return v.Count
end

-- Обёртка обработчика: лимит → проверка аргументов → вызов в pcall. Её же вешает Connect на OnServerEvent
function NetService.BuildHandler(name, handler)
	local def = Definitions[name]
	assert(def and fromClient(def), "NetService.BuildHandler: событие " .. tostring(name) .. " не принимается от клиента")
	local limiter = limiters[name]
	assert(limiter, "NetService.BuildHandler: сервис не инициализирован")
	return function(player, ...)
		if not limiter:Allow(player) then
			violation(player, name, "слишком часто")
			return
		end
		local ok, reason = Validate.Args(def.Args, ...)
		if not ok then
			violation(player, name, reason)
			return
		end
		local okCall, err = pcall(handler, player, ...)
		if not okCall then
			log:Error("обработчик %s упал (игрок %s): %s", name, tostring(player.Name), tostring(err))
		end
	end
end

-- Принять событие от клиентов. У события один обработчик (так проще найти, кто за что отвечает)
function NetService.Connect(name, handler)
	local def = Definitions[name]
	assert(def, "NetService.Connect: нет события " .. tostring(name) .. " в RemoteDefinitions")
	assert(fromClient(def), "NetService.Connect: событие " .. name .. " не принимается от клиента")
	assert(type(handler) == "function", "NetService.Connect: нужна функция")
	assert(not connected[name], "NetService.Connect: у события " .. name .. " уже есть обработчик")
	local remote = remotes[name]
	assert(remote, "NetService.Connect: remotes ещё не созданы (Connect — только после Init)")
	connected[name] = remote.OnServerEvent:Connect(NetService.BuildHandler(name, handler))
	return connected[name]
end

local function checkOutgoing(name)
	local def = Definitions[name]
	if not def then
		log:Error("отправка неизвестного события %s", tostring(name))
		return nil
	end
	if not toClient(def) then
		log:Error("событие %s не отправляется клиентам (Direction = %s)", name, def.Direction)
		return nil
	end
	return remotes[name]
end

local function isPlayer(p)
	return typeof(p) == "Instance" and p:IsA("Player")
end

-- Отправить одному игроку. Возвращает true, если ушло
function NetService.Fire(player, name, ...)
	local remote = checkOutgoing(name)
	if not remote then
		return false
	end
	if not isPlayer(player) then
		log:Error("Fire %s: получатель не игрок (%s)", name, typeof(player))
		return false
	end
	local ok, err = pcall(remote.FireClient, remote, player, ...)
	if not ok then
		log:Warn("Fire %s → %s не ушло: %s", name, player.Name, tostring(err))
	end
	return ok
end

function NetService.FireAll(name, ...)
	local remote = checkOutgoing(name)
	if not remote then
		return false
	end
	local ok, err = pcall(remote.FireAllClients, remote, ...)
	if not ok then
		log:Warn("FireAll %s не ушло: %s", name, tostring(err))
	end
	return ok
end

function NetService.FireExcept(except, name, ...)
	local remote = checkOutgoing(name)
	if not remote then
		return false
	end
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= except then
			pcall(remote.FireClient, remote, p, ...)
		end
	end
	return true
end

function NetService.Init()
	local problems = NetService.CheckDefinitions(Definitions)
	if #problems > 0 then
		error("ошибки в RemoteDefinitions:\n  " .. table.concat(problems, "\n  "), 0)
	end
	for name, def in pairs(Definitions) do
		if fromClient(def) then
			limiters[name] = RateLimiter.new(def.Rate.Burst, def.Rate.PerSecond)
		end
	end
	NetService.SyncRemotes()
	Players.PlayerRemoving:Connect(function(player)
		violations[player] = nil
		for _, limiter in pairs(limiters) do
			limiter:Forget(player)
		end
	end)
	log:Debug("remotes готовы: %d", folder:GetAttribute("Count"))
end

return NetService
