-- Signal: события внутри одной стороны (сервер или клиент) без BindableEvent.
--
--   local Died = Signal.new()
--   local conn = Died:Connect(function(player) ... end)
--   Died:Fire(player)
--   conn:Disconnect()
--
-- Каждый обработчик вызывается в своём потоке (task.spawn): ошибка в одном не мешает остальным
-- и попадает в Output/ErrorService как обычная ошибка скрипта. Порядок вызова — порядок подключения.
local Signal = {}
Signal.__index = Signal

local Connection = {}
Connection.__index = Connection

function Connection:Disconnect()
	if not self.Connected then
		return
	end
	self.Connected = false
	local list = self._signal._list
	local i = table.find(list, self)
	if i then
		table.remove(list, i)
	end
end

function Signal.new()
	return setmetatable({ _list = {} }, Signal)
end

function Signal:Connect(fn)
	assert(type(fn) == "function", "Signal:Connect: нужна функция")
	local c = setmetatable({ Connected = true, _signal = self, _fn = fn }, Connection)
	table.insert(self._list, c)
	return c
end

-- Один раз: после первого вызова отключается сам
function Signal:Once(fn)
	assert(type(fn) == "function", "Signal:Once: нужна функция")
	local c
	c = self:Connect(function(...)
		c:Disconnect()
		fn(...)
	end)
	return c
end

function Signal:Fire(...)
	-- копия списка: обработчик может отключить себя или другого прямо во время вызова
	for _, c in ipairs(table.clone(self._list)) do
		if c.Connected then
			task.spawn(c._fn, ...)
		end
	end
end

-- Ждать следующего Fire и вернуть его аргументы
function Signal:Wait()
	local thread = coroutine.running()
	self:Once(function(...)
		task.spawn(thread, ...)
	end)
	return coroutine.yield()
end

function Signal:DisconnectAll()
	for _, c in ipairs(self._list) do
		c.Connected = false
	end
	table.clear(self._list)
end

function Signal:ConnectionCount()
	return #self._list
end

Signal.Destroy = Signal.DisconnectAll

return Signal
