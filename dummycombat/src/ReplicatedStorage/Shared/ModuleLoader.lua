-- ModuleLoader: запуск сервисов (сервер) и контроллеров (клиент) в два прохода.
--
--   1. require всех модулей по списку Order;
--   2. Init(context) у всех — подготовка: создать объекты, подключиться к событиям; здесь модули ещё
--      не должны рассчитывать, что другие уже работают (но могут взять их через context.Get);
--   3. Start(context) у всех — запуск: с этого момента можно пользоваться другими модулями.
--
-- Модуль — таблица с полями Name, Init, Start (оба необязательны). Ошибка в одном модуле не роняет
-- остальные: она пишется в журнал и в итоговый отчёт. Если упал модуль из списка Critical —
-- отчёт помечается CriticalFailed (сервер тогда объявляет загрузку неудачной).
-- Модули в папке, которых нет в Order, не запускаются — о них пишется предупреждение
-- (обычно это значит, что новый модуль забыли подключить).
local Logger = require(script.Parent.Logger)

local ModuleLoader = {}

local PHASES = { "Init", "Start" }

-- options: { Name, Folder, Order = { ... }, Critical = { Имя = true }, WaitTimeout = 5 }
-- или несколько папок с общим контекстом: { Name, Groups = { { Folder = ..., Order = { ... } }, ... }, Critical }
-- (сервер: сначала Services, потом Systems — системы берут сервисы через context.Get)
function ModuleLoader.Run(options)
	local log = Logger.new(options.Name or "Loader")
	local groups = options.Groups or { { Folder = options.Folder, Order = options.Order or {} } }
	local critical = options.Critical or {}
	local started = os.clock()
	local order = {}
	for _, group in ipairs(groups) do
		for _, name in ipairs(group.Order) do
			table.insert(order, name)
		end
	end
	local report = { Modules = {}, Status = {}, Failures = 0, CriticalFailed = false, Order = order }

	local context = {}
	function context.Get(name)
		local m = report.Modules[name]
		if not m then
			error(string.format("модуль «%s» не загружен", tostring(name)), 2)
		end
		return m
	end
	report.Context = context

	local function fail(name, phase, err)
		report.Status[name] = "Failed:" .. phase
		report.Failures = report.Failures + 1
		if critical[name] then
			report.CriticalFailed = true
		end
		log:Error("%s — ошибка на этапе %s: %s", name, phase, tostring(err))
	end

	-- 1. require (по группам, в порядке списков)
	for _, group in ipairs(groups) do
		local folder = group.Folder
		local listed = {}
		for _, name in ipairs(group.Order) do
			listed[name] = true
			local ms = folder:FindFirstChild(name) or folder:WaitForChild(name, options.WaitTimeout or 5)
			if not (ms and ms:IsA("ModuleScript")) then
				fail(name, "Require", "модуль не найден в " .. folder:GetFullName())
			else
				local ok, result = pcall(require, ms)
				if not ok then
					fail(name, "Require", result)
				elseif type(result) ~= "table" then
					fail(name, "Require", "модуль вернул не таблицу")
				else
					report.Modules[name] = result
					report.Status[name] = "Loaded"
				end
			end
		end
		for _, child in ipairs(folder:GetChildren()) do
			if child:IsA("ModuleScript") and not listed[child.Name] then
				log:Warn("модуль %s лежит в %s, но не подключён (нет в списке запуска)", child.Name, folder.Name)
			end
		end
	end

	-- 2–3. Init, затем Start
	for _, phase in ipairs(PHASES) do
		for _, name in ipairs(order) do
			local m = report.Modules[name]
			if m and string.sub(report.Status[name], 1, 6) ~= "Failed" then
				local fn = m[phase]
				if type(fn) == "function" then
					local ok, err = xpcall(fn, debug.traceback, context)
					if ok then
						report.Status[name] = phase == "Init" and "Initialized" or "Started"
					else
						fail(name, phase, err)
					end
				else
					report.Status[name] = phase == "Init" and "Initialized" or "Started"
				end
			end
		end
	end

	report.Seconds = os.clock() - started
	local names = {}
	for _, name in ipairs(order) do
		table.insert(names, name .. "=" .. tostring(report.Status[name]))
	end
	if report.Failures == 0 then
		log:Info("запущено за %.2f с: %s", report.Seconds, table.concat(names, ", "))
	else
		log:Error("запуск с ошибками (%d) за %.2f с: %s", report.Failures, report.Seconds, table.concat(names, ", "))
	end
	return report
end

return ModuleLoader
