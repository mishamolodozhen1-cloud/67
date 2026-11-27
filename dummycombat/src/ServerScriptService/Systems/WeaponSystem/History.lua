-- History: где были цели в недавнем прошлом (для компенсации задержки сети при проверке попаданий).
-- Хранит положения корня (HumanoidRootPart) каждой цели с отметкой времени сервера за последние window
-- секунд; At(model, t) — положение в момент t (между записями — плавно).
local History = {}
History.__index = History

function History.new(window)
	return setmetatable({ Window = window, Samples = {} }, History)
end

function History:Record(model, t, cf)
	local list = self.Samples[model]
	if not list then
		list = {}
		self.Samples[model] = list
	end
	table.insert(list, { T = t, CF = cf })
	local cut = t - self.Window
	while #list > 2 and list[2].T < cut do
		table.remove(list, 1)
	end
end

function History:Forget(model)
	self.Samples[model] = nil
end

function History:Count(model)
	local list = self.Samples[model]
	return list and #list or 0
end

-- Положение в момент t: до первой записи — первая, после последней — последняя
function History:At(model, t)
	local list = self.Samples[model]
	if not list or #list == 0 then
		return nil
	end
	if t <= list[1].T then
		return list[1].CF
	end
	local last = list[#list]
	if t >= last.T then
		return last.CF
	end
	for i = #list - 1, 1, -1 do
		local a = list[i]
		if a.T <= t then
			local b = list[i + 1]
			local k = (t - a.T) / math.max(b.T - a.T, 1e-6)
			return a.CF:Lerp(b.CF, k)
		end
	end
	return list[1].CF
end

return History
