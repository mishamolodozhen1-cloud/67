-- Logger: единый журнал DUMMY COMBAT для сервера и клиента.
--
--   local log = Logger.new("Weapons")
--   log:Info("игрок %s выстрелил", player.Name)
--   log:Warn(...) / log:Error(...) / log:Debug(...)
--
-- Уровни: Debug < Info < Warn < Error. Что ниже текущего уровня — не печатается и не хранится.
-- Строка в Output: [DC S][WARN][Weapons] текст (S — сервер, C — клиент).
-- Одинаковые сообщения чаще, чем раз в DuplicateWindow секунд, не засоряют Output: они считаются,
-- и при следующей печати добавляется «(ещё N раз)».
-- Последние записи хранятся в памяти (GetHistory) — для диагностики и отчётов об ошибках.
-- Приёмники (AddSink) получают каждую напечатанную запись: так ErrorService собирает ошибки.
local RunService = game:GetService("RunService")

local Logger = {}

Logger.Levels = { Debug = 1, Info = 2, Warn = 3, Error = 4, None = 5 }
local LEVEL_TAGS = { "DEBUG", "INFO", "WARN", "ERROR" }

local state = {
	Level = Logger.Levels.Info,
	HistorySize = 200,
	DuplicateWindow = 10,
	History = {},
	Head = 0,
	Stored = 0,
	Sinks = {},
	Seen = {},
	SeenCount = 0,
	InSink = false,
	Side = RunService:IsServer() and "S" or "C",
}

local function levelValue(level)
	if type(level) == "number" then
		return math.clamp(math.floor(level), 1, 5)
	end
	return Logger.Levels[level] or Logger.Levels.Info
end

-- Настроить журнал: { Level = "Info", HistorySize = 200, DuplicateWindow = 10 }
function Logger.Configure(options)
	options = options or {}
	if options.Level ~= nil then
		state.Level = levelValue(options.Level)
	end
	if type(options.HistorySize) == "number" and options.HistorySize >= 1 then
		state.HistorySize = math.floor(options.HistorySize)
		state.History, state.Head, state.Stored = {}, 0, 0
	end
	if type(options.DuplicateWindow) == "number" and options.DuplicateWindow >= 0 then
		state.DuplicateWindow = options.DuplicateWindow
	end
end

function Logger.GetLevel()
	return state.Level
end

-- Короткое описание значения для журнала: таблицы — не глубже двух уровней и не больше 12 полей
local function describe(value, depth, seen)
	local t = typeof(value)
	if t == "string" then
		return value
	elseif t ~= "table" then
		return tostring(value)
	end
	if seen[value] then
		return "<цикл>"
	end
	if depth >= 2 then
		return "{…}"
	end
	seen[value] = true
	local parts, n = {}, 0
	for k, v in pairs(value) do
		n = n + 1
		if n > 12 then
			table.insert(parts, "…")
			break
		end
		table.insert(parts, tostring(k) .. "=" .. describe(v, depth + 1, seen))
	end
	seen[value] = nil
	return "{" .. table.concat(parts, ", ") .. "}"
end
Logger.Describe = function(value)
	return describe(value, 0, {})
end

-- Текст сообщения: string.format(fmt, ...), а если аргументы не подходят к формату — всё через пробел
local function render(fmt, ...)
	local count = select("#", ...)
	if count == 0 then
		return describe(fmt, 0, {})
	end
	local args = table.pack(...)
	for i = 1, count do
		local v = args[i]
		if type(v) ~= "number" then
			args[i] = describe(v, 0, {})
		end
	end
	local ok, text = pcall(string.format, tostring(fmt), table.unpack(args, 1, count))
	if ok then
		return text
	end
	local parts = { tostring(fmt) }
	for i = 1, count do
		table.insert(parts, tostring(args[i]))
	end
	return table.concat(parts, " ")
end

local function remember(entry)
	state.Head = state.Head % state.HistorySize + 1
	state.History[state.Head] = entry
	state.Stored = math.min(state.Stored + 1, state.HistorySize)
end

-- Повтор того же сообщения: не печатать, а посчитать. Возвращает nil (пропустить) или приписку
local function duplicateSuffix(key, now)
	local seen = state.Seen[key]
	if seen and now - seen.At < state.DuplicateWindow then
		seen.Suppressed = seen.Suppressed + 1
		return nil
	end
	local suffix = ""
	if seen and seen.Suppressed > 0 then
		suffix = string.format(" (ещё %d раз за %.0f с)", seen.Suppressed, now - seen.At)
	end
	if not seen then
		state.SeenCount = state.SeenCount + 1
		if state.SeenCount > 512 then
			-- таблица повторов не растёт бесконечно: старые записи выбрасываем
			for k, v in pairs(state.Seen) do
				if now - v.At >= state.DuplicateWindow then
					state.Seen[k] = nil
					state.SeenCount = state.SeenCount - 1
				end
			end
		end
	end
	state.Seen[key] = { At = now, Suppressed = 0 }
	return suffix
end

local function write(level, scope, fmt, ...)
	if level < state.Level then
		return nil
	end
	local message = render(fmt, ...)
	local now = os.clock()
	local suffix = duplicateSuffix(scope .. "\0" .. message, now)
	if suffix == nil then
		return nil
	end
	local entry = table.freeze({
		Level = level,
		LevelName = LEVEL_TAGS[level],
		Scope = scope,
		Message = message .. suffix,
		Side = state.Side,
		Time = os.time(),
		Clock = now,
	})
	remember(entry)
	local line = string.format("[DC %s][%s][%s] %s", state.Side, entry.LevelName, scope, entry.Message)
	if level >= Logger.Levels.Warn then
		warn(line)
	else
		print(line)
	end
	-- приёмники; если приёмник сам что-то пишет в журнал — дальше по приёмникам это не идёт (без петель)
	if not state.InSink and #state.Sinks > 0 then
		state.InSink = true
		for _, sink in ipairs(table.clone(state.Sinks)) do
			local ok, err = pcall(sink, entry)
			if not ok then
				warn("[DC " .. state.Side .. "][ERROR][Logger] приёмник журнала упал: " .. tostring(err))
			end
		end
		state.InSink = false
	end
	return entry
end

local LoggerObject = {}
LoggerObject.__index = LoggerObject

function LoggerObject:Debug(fmt, ...)
	return write(Logger.Levels.Debug, self.Scope, fmt, ...)
end

function LoggerObject:Info(fmt, ...)
	return write(Logger.Levels.Info, self.Scope, fmt, ...)
end

function LoggerObject:Warn(fmt, ...)
	return write(Logger.Levels.Warn, self.Scope, fmt, ...)
end

function LoggerObject:Error(fmt, ...)
	return write(Logger.Levels.Error, self.Scope, fmt, ...)
end

-- Журнал раздела: Logger.new("Net")
function Logger.new(scope)
	assert(type(scope) == "string" and scope ~= "", "Logger.new: нужно имя раздела")
	return setmetatable({ Scope = scope }, LoggerObject)
end

-- Приёмник записей: fn(entry). Возвращает функцию, которая его отключает
function Logger.AddSink(fn)
	assert(type(fn) == "function", "Logger.AddSink: нужна функция")
	table.insert(state.Sinks, fn)
	return function()
		local i = table.find(state.Sinks, fn)
		if i then
			table.remove(state.Sinks, i)
		end
	end
end

-- Последние записи (от старых к новым); limit — сколько последних вернуть
function Logger.GetHistory(limit)
	local out = {}
	local n = state.Stored
	local first = state.Head - n + 1
	for i = 0, n - 1 do
		local idx = (first + i - 1) % state.HistorySize + 1
		table.insert(out, state.History[idx])
	end
	if limit and limit < #out then
		return { table.unpack(out, #out - limit + 1, #out) }
	end
	return out
end

return Logger
