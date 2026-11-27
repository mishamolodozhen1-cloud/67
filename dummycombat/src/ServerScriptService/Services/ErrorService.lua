-- ErrorService: сбор ошибок в одном месте.
--   • ошибки серверных скриптов (ScriptContext.Error);
--   • записи журнала уровня Error (Logger);
--   • ошибки на клиентах: клиент присылает их через событие ClientError (текст и стек проверяются
--     NetService, а здесь — ещё лимит на игрока за сессию).
-- Последние ошибки хранятся в памяти (GetRecent) — для диагностики, админ-панели и проверок.
-- Ошибки скриптов Roblox и так печатает в Output, поэтому здесь они только записываются;
-- ошибки клиентов печатаются (их иначе на сервере не видно).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ScriptContext = game:GetService("ScriptContext")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Logger = require(Shared:WaitForChild("Logger"))
local Signal = require(Shared:WaitForChild("Signal"))
local GameConfig = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("GameConfig"))

local ErrorService = { Name = "ErrorService" }

-- Новая запись: (entry)
ErrorService.Recorded = Signal.new()

local log = Logger.new("Errors")
local cfg = GameConfig.ClientErrors

local entries = {}
local total = 0
local perPlayer = {}

local function firstLine(text)
	return (string.match(text, "^[^\n]*") or text)
end

-- Записать ошибку. source: "Server" | "Log" | "Client"; info — доп. поля (UserId, Script, Kind…)
function ErrorService.Record(source, message, trace, info)
	total = total + 1
	local entry = {
		Id = total,
		Source = source,
		Message = tostring(message),
		Trace = tostring(trace or ""),
		Time = os.time(),
	}
	for k, v in pairs(info or {}) do
		entry[k] = v
	end
	table.freeze(entry)
	table.insert(entries, entry)
	if #entries > cfg.History then
		table.remove(entries, 1)
	end
	ErrorService.Recorded:Fire(entry)
	return entry
end

-- Последние ошибки (от старых к новым); source — только такого источника
function ErrorService.GetRecent(limit, source)
	local out = {}
	for _, e in ipairs(entries) do
		if not source or e.Source == source then
			table.insert(out, e)
		end
	end
	if limit and #out > limit then
		return { table.unpack(out, #out - limit + 1, #out) }
	end
	return out
end

function ErrorService.Total()
	return total
end

-- Обработчик ClientError (после проверок NetService)
function ErrorService.OnClientError(player, message, trace, kind)
	local count = (perPlayer[player] or 0) + 1
	perPlayer[player] = count
	if count > cfg.MaxPerSession then
		return nil
	end
	local entry = ErrorService.Record("Client", message, trace, { UserId = player.UserId, Player = player.Name, Kind = kind })
	log:Warn("ошибка у клиента %s (%d): %s", player.Name, player.UserId, firstLine(message))
	if count == cfg.MaxPerSession then
		log:Warn("от %s больше ошибок не принимаем до конца сессии (%d)", player.Name, count)
	end
	return entry
end

function ErrorService.Init()
	ScriptContext.Error:Connect(function(message, trace, scriptInstance)
		local where = nil
		if typeof(scriptInstance) == "Instance" then
			local ok, name = pcall(scriptInstance.GetFullName, scriptInstance)
			where = ok and name or nil
		end
		ErrorService.Record("Server", message, trace, { Script = where })
	end)
	Logger.AddSink(function(entry)
		if entry.Level >= Logger.Levels.Error then
			ErrorService.Record("Log", entry.Scope .. ": " .. entry.Message, "", { Scope = entry.Scope })
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		perPlayer[player] = nil
	end)
end

function ErrorService.Start(context)
	context.Get("NetService").Connect("ClientError", ErrorService.OnClientError)
end

return ErrorService
