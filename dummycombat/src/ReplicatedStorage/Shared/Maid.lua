-- Maid: уборка всего, что создал объект или система, одной командой.
--
--   local maid = Maid.new()
--   maid:Give(part)                          -- Instance → :Destroy()
--   maid:Give(humanoid.Died:Connect(...))    -- RBXScriptConnection → :Disconnect()
--   maid:Give(function() ... end)            -- функция → вызвать
--   maid:Give(task.delay(5, ...))            -- поток → task.cancel
--   maid:Give(signal)                        -- таблица с :Destroy() или :Disconnect()
--   maid:Cleanup()                           -- всё сразу, в обратном порядке
--
-- Нужен, чтобы после матча, смерти или регдолла не оставалось лишних деталей, соединений и потоков.
-- Ошибка при уборке одного предмета не мешает убрать остальные.
local Maid = {}
Maid.__index = Maid

function Maid.new()
	return setmetatable({ _items = {}, _cleaning = false }, Maid)
end

local function supported(item)
	local t = typeof(item)
	if t == "function" or t == "thread" or t == "Instance" or t == "RBXScriptConnection" then
		return true
	end
	return t == "table" and (type(item.Destroy) == "function" or type(item.Disconnect) == "function")
end

-- Отдать предмет на уборку; возвращает его же (удобно: local p = maid:Give(Instance.new("Part")))
function Maid:Give(item)
	assert(supported(item), "Maid:Give: нельзя убрать " .. typeof(item))
	if self._cleaning then
		-- уборка уже идёт: убираем сразу
		self:_clean(item)
		return item
	end
	table.insert(self._items, item)
	return item
end

function Maid:_clean(item)
	local t = typeof(item)
	local ok, err = pcall(function()
		if t == "function" then
			item()
		elseif t == "thread" then
			if coroutine.status(item) ~= "dead" then
				task.cancel(item)
			end
		elseif t == "Instance" then
			item:Destroy()
		elseif t == "RBXScriptConnection" then
			item:Disconnect()
		elseif type(item.Destroy) == "function" then
			item:Destroy()
		else
			item:Disconnect()
		end
	end)
	if not ok then
		warn("[DC][Maid] не удалось убрать " .. t .. ": " .. tostring(err))
	end
end

function Maid:Cleanup()
	if self._cleaning then
		return
	end
	self._cleaning = true
	local items = self._items
	self._items = {}
	for i = #items, 1, -1 do
		self:_clean(items[i])
	end
	self._cleaning = false
end

function Maid:Count()
	return #self._items
end

Maid.Destroy = Maid.Cleanup

return Maid
