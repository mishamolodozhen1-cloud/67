-- ClientNet: сетевые события на клиенте (пара к серверному NetService).
--
--   ClientNet.Fire("ClientReady")                 -- клиент → сервер
--   ClientNet.On("ServerInfo", function(info) end) -- сервер → клиент
--
-- • Ждёт, пока сервер подготовит ReplicatedStorage.Remotes (атрибут Ready), не дольше Net.ReadyTimeout.
-- • Отправлять можно только события с Direction ToServer/Both, слушать — ToClient/Both.
-- • Перед отправкой — свой лимит частоты, чуть строже серверного (ClientRateFactor): честный клиент
--   не получает нарушений, а лишнее просто не уходит (пишется в журнал на уровне Debug).
-- • Ошибка в обработчике события не ломает соединение — пишется в журнал (и уходит на сервер как ошибка).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Configs = ReplicatedStorage:WaitForChild("Configs")
local Logger = require(Shared:WaitForChild("Logger"))
local RateLimiter = require(Shared:WaitForChild("RateLimiter"))
local Signal = require(Shared:WaitForChild("Signal"))
local GameConfig = require(Configs:WaitForChild("GameConfig"))
local Definitions = require(Configs:WaitForChild("RemoteDefinitions"))

local ClientNet = { Name = "ClientNet" }

ClientNet.ServerInfo = nil -- что сервер сообщил о себе (после ClientReady)
ClientNet.ServerInfoChanged = Signal.new()

local log = Logger.new("Net")
local cfg = GameConfig.Net
local remotes = {}
local limiters = {}

local function fromClient(def)
	return def.Direction == "ToServer" or def.Direction == "Both"
end

local function toClient(def)
	return def.Direction == "ToClient" or def.Direction == "Both"
end

-- Лимит клиента по серверному описанию: запас по всплеску на 1 меньше, темп — ClientRateFactor
function ClientNet.MakeLimiter(def, clock)
	local burst = math.max(1, def.Rate.Burst - 1)
	return RateLimiter.new(burst, def.Rate.PerSecond * cfg.ClientRateFactor, clock)
end

function ClientNet.IsReady()
	return next(remotes) ~= nil
end

function ClientNet.Fire(name, ...)
	local def = Definitions[name]
	if not def or not fromClient(def) then
		log:Error("нельзя отправить событие %s на сервер", tostring(name))
		return false
	end
	local remote = remotes[name]
	if not remote then
		log:Warn("событие %s ещё не готово", name)
		return false
	end
	if not limiters[name]:Allow(name) then
		log:Debug("%s: слишком часто, не отправлено", name)
		return false
	end
	remote:FireServer(...)
	return true
end

-- Слушать событие от сервера. Возвращает соединение
function ClientNet.On(name, fn)
	local def = Definitions[name]
	assert(def and toClient(def), "ClientNet.On: событие " .. tostring(name) .. " не приходит с сервера")
	assert(type(fn) == "function", "ClientNet.On: нужна функция")
	local remote = remotes[name]
	assert(remote, "ClientNet.On: remotes ещё не готовы (On — после Init)")
	return remote.OnClientEvent:Connect(function(...)
		local ok, err = pcall(fn, ...)
		if not ok then
			log:Error("обработчик %s упал: %s", name, tostring(err))
		end
	end)
end

function ClientNet.Init()
	local folder = ReplicatedStorage:WaitForChild(cfg.RemotesFolder, cfg.ReadyTimeout)
	if not folder then
		error("нет ReplicatedStorage." .. cfg.RemotesFolder .. " — сервер не запустился", 0)
	end
	local started = os.clock()
	while not folder:GetAttribute("Ready") do
		if os.clock() - started > cfg.ReadyTimeout then
			error(string.format("сервер не подготовил remotes за %d с", cfg.ReadyTimeout), 0)
		end
		task.wait(0.1)
	end
	for name, def in pairs(Definitions) do
		local left = math.max(1, cfg.ReadyTimeout - (os.clock() - started))
		local remote = folder:WaitForChild(name, left)
		if not remote then
			error("нет события " .. name .. " в Remotes", 0)
		end
		remotes[name] = remote
		if fromClient(def) then
			limiters[name] = ClientNet.MakeLimiter(def)
		end
	end
	log:Debug("remotes получены за %.2f с", os.clock() - started)
end

function ClientNet.Start()
	ClientNet.On("ServerInfo", function(info)
		if type(info) ~= "table" then
			return
		end
		ClientNet.ServerInfo = info
		ClientNet.ServerInfoChanged:Fire(info)
		log:Info("сервер: %s %s (сборка %s), версия плейса %s", tostring(info.Game), tostring(info.Version), tostring(info.Build), tostring(info.PlaceVersion))
	end)
	ClientNet.Fire("ClientReady")
end

return ClientNet
