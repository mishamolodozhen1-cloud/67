-- Validate: проверка данных, которые пришли от клиента. Клиенту не доверяем: через RemoteEvent может
-- прийти что угодно — не тот тип, NaN, бесконечность, огромная строка, лишние поля и аргументы.
--
-- Валидатор — функция value -> ok, причина. Из них собираются схемы аргументов remotes:
--   Args = { Validate.Vector3({ MaxMagnitude = 2000 }), Validate.Number({ Min = 0, Max = 1, }) }
--   local ok, reason = Validate.Args(def.Args, ...)
--
-- Числа: только конечные (не NaN, не ±inf). Строки: длина в байтах и правильный UTF-8.
-- Таблицы (Shape/Array): только перечисленные поля, без лишних; массивы — без дыр и посторонних ключей.
local Validate = {}

local function isFinite(n)
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end
Validate.IsFinite = isFinite

-- Число. opts: Min, Max, Integer
function Validate.Number(opts)
	opts = opts or {}
	return function(v)
		if type(v) ~= "number" then
			return false, "ожидалось число, пришло " .. typeof(v)
		end
		if not isFinite(v) then
			return false, "число не конечное"
		end
		if opts.Integer and v % 1 ~= 0 then
			return false, "ожидалось целое число"
		end
		if opts.Min and v < opts.Min then
			return false, "число меньше " .. tostring(opts.Min)
		end
		if opts.Max and v > opts.Max then
			return false, "число больше " .. tostring(opts.Max)
		end
		return true
	end
end

-- Строка. opts: Max (байт, обязательно), Min, Pattern (Lua-шаблон, которому строка должна соответствовать)
function Validate.String(opts)
	assert(opts and type(opts.Max) == "number", "Validate.String: нужен Max")
	return function(v)
		if type(v) ~= "string" then
			return false, "ожидалась строка, пришло " .. typeof(v)
		end
		if #v > opts.Max then
			return false, "строка длиннее " .. opts.Max .. " байт"
		end
		if opts.Min and #v < opts.Min then
			return false, "строка короче " .. opts.Min .. " байт"
		end
		if utf8.len(v) == nil then
			return false, "строка не в UTF-8"
		end
		if opts.Pattern and not string.find(v, opts.Pattern) then
			return false, "строка не подходит под формат"
		end
		return true
	end
end

function Validate.Boolean()
	return function(v)
		if type(v) ~= "boolean" then
			return false, "ожидалось true/false, пришло " .. typeof(v)
		end
		return true
	end
end

-- Одно из значений списка (строки или числа)
function Validate.OneOf(list)
	local set = {}
	for _, item in ipairs(list) do
		set[item] = true
	end
	return function(v)
		if (type(v) == "string" or type(v) == "number") and set[v] then
			return true
		end
		return false, "значение не из списка"
	end
end

-- Vector3 с конечными координатами. opts: MaxMagnitude
function Validate.Vector3(opts)
	opts = opts or {}
	return function(v)
		if typeof(v) ~= "Vector3" then
			return false, "ожидался Vector3, пришло " .. typeof(v)
		end
		if not (isFinite(v.X) and isFinite(v.Y) and isFinite(v.Z)) then
			return false, "Vector3 с нечисловыми координатами"
		end
		if opts.MaxMagnitude and v.Magnitude > opts.MaxMagnitude then
			return false, "Vector3 длиннее " .. tostring(opts.MaxMagnitude)
		end
		return true
	end
end

-- CFrame с конечными компонентами
function Validate.CFrame()
	return function(v)
		if typeof(v) ~= "CFrame" then
			return false, "ожидался CFrame, пришло " .. typeof(v)
		end
		for _, c in ipairs({ v:GetComponents() }) do
			if not isFinite(c) then
				return false, "CFrame с нечисловыми компонентами"
			end
		end
		return true
	end
end

-- Объект Roblox нужного класса (IsA)
function Validate.Instance(className)
	return function(v)
		if typeof(v) ~= "Instance" then
			return false, "ожидался объект, пришло " .. typeof(v)
		end
		if className and not v:IsA(className) then
			return false, "объект не " .. className
		end
		return true
	end
end

-- nil или значение, которое проходит inner
function Validate.Optional(inner)
	return function(v)
		if v == nil then
			return true
		end
		return inner(v)
	end
end

-- Массив: только ключи 1..n без дыр, не длиннее opts.Max, каждый элемент проходит item
function Validate.Array(item, opts)
	assert(opts and type(opts.Max) == "number", "Validate.Array: нужен Max")
	return function(v)
		if type(v) ~= "table" then
			return false, "ожидался массив, пришло " .. typeof(v)
		end
		local count = 0
		for k in pairs(v) do
			count = count + 1
			if type(k) ~= "number" or k % 1 ~= 0 or k < 1 then
				return false, "в массиве посторонний ключ"
			end
			if count > opts.Max then
				return false, "в массиве больше " .. opts.Max .. " элементов"
			end
		end
		if count ~= #v then
			return false, "в массиве дыры"
		end
		for i = 1, count do
			local ok, reason = item(v[i])
			if not ok then
				return false, "элемент " .. i .. ": " .. tostring(reason)
			end
		end
		return true
	end
end

-- Таблица с известными полями: fields = { Поле = валидатор }. Лишние поля — ошибка;
-- отсутствующее поле получает nil (если оно необязательное — оберните в Validate.Optional)
function Validate.Shape(fields)
	return function(v)
		if type(v) ~= "table" then
			return false, "ожидалась таблица, пришло " .. typeof(v)
		end
		for k in pairs(v) do
			if type(k) ~= "string" or fields[k] == nil then
				return false, "лишнее поле " .. tostring(k)
			end
		end
		for name, check in pairs(fields) do
			local ok, reason = check(v[name])
			if not ok then
				return false, name .. ": " .. tostring(reason)
			end
		end
		return true
	end
end

-- Проверить аргументы remote по списку валидаторов: лишние аргументы — ошибка
function Validate.Args(validators, ...)
	local count = select("#", ...)
	if count > #validators then
		return false, string.format("лишние аргументы (%d вместо %d)", count, #validators)
	end
	for i, check in ipairs(validators) do
		local ok, reason = check((select(i, ...)))
		if not ok then
			return false, string.format("аргумент %d: %s", i, tostring(reason))
		end
	end
	return true
end

return Validate
