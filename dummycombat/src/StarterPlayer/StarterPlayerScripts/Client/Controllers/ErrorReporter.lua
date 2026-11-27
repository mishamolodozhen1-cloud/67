-- ErrorReporter: ошибки на клиенте → сервер (ErrorService).
--   • ошибки клиентских скриптов (ScriptContext.Error) и записи журнала уровня Error;
--   • одинаковая ошибка отправляется один раз за сессию, всего — не больше ClientErrors.MaxPerSession;
--   • текст и стек обрезаются до лимитов сервера по границе символа UTF-8 (иначе сервер их отклонит);
--   • пока сеть не готова, ошибки копятся в очереди (не больше 10) и уходят после запуска ClientNet.
-- Сам ErrorReporter пишет в журнал только на уровне Warn — так он не может отправить сам себя по кругу.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ScriptContext = game:GetService("ScriptContext")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Logger = require(Shared:WaitForChild("Logger"))
local GameConfig = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("GameConfig"))

local ErrorReporter = { Name = "ErrorReporter" }

local cfg = GameConfig.ClientErrors
local QUEUE_MAX = 10

local net = nil
local queue = {}
local sentKeys = {}
local sentCount = 0

-- Привести текст к правильному UTF-8 и обрезать до max байт, не разрезая символ
function ErrorReporter.Clip(text, max)
	text = tostring(text or "")
	if utf8.len(text) == nil then
		-- битые байты заменяем на «?», чтобы сервер принял строку
		text = string.gsub(text, "[\128-\255]", "?")
	end
	if #text <= max then
		return text
	end
	local cut = max - 3 -- место под «...»
	while cut > 0 and utf8.len(string.sub(text, 1, cut)) == nil do
		cut = cut - 1
	end
	return string.sub(text, 1, cut) .. "..."
end

-- Что именно отправим: текст, стек, ключ для «один раз за сессию»
function ErrorReporter.Prepare(message, trace)
	local msg = ErrorReporter.Clip(message, cfg.MaxMessage)
	if msg == "" then
		msg = "(пустая ошибка)"
	end
	local tr = ErrorReporter.Clip(trace, cfg.MaxTrace)
	local key = msg .. "\n" .. (string.match(tr, "^[^\n]*") or "")
	return msg, tr, key
end

local function deliver(item)
	local ok, err = pcall(net.Fire, item.Message, item.Trace, item.Kind)
	if not ok then
		warn("[DC C][WARN][Errors] не удалось отправить ошибку: " .. tostring(err))
	end
end

-- Сообщить об ошибке (kind: "Error" или "Log"). Возвращает true, если принята к отправке
function ErrorReporter.Report(kind, message, trace)
	local msg, tr, key = ErrorReporter.Prepare(message, trace)
	if sentKeys[key] or sentCount >= cfg.MaxPerSession then
		return false
	end
	sentKeys[key] = true
	sentCount = sentCount + 1
	local item = { Kind = kind, Message = msg, Trace = tr }
	if net then
		deliver(item)
	elseif #queue < QUEUE_MAX then
		table.insert(queue, item)
	end
	return true
end

function ErrorReporter.Init()
	ScriptContext.Error:Connect(function(message, trace)
		ErrorReporter.Report("Error", message, trace)
	end)
	Logger.AddSink(function(entry)
		if entry.Level >= Logger.Levels.Error then
			ErrorReporter.Report("Log", entry.Scope .. ": " .. entry.Message, "")
		end
	end)
end

function ErrorReporter.Start(context)
	local clientNet = context.Get("ClientNet")
	if not clientNet.IsReady() then
		warn("[DC C][WARN][Errors] сеть не готова — ошибки клиента на сервер не отправляются")
		return
	end
	net = {
		Fire = function(message, trace, kind)
			return clientNet.Fire("ClientError", message, trace, kind)
		end,
	}
	local pending = queue
	queue = {}
	for _, item in ipairs(pending) do
		deliver(item)
	end
end

return ErrorReporter
