-- HumanoidUtil: общие действия с Humanoid.
local HumanoidUtil = {}

-- fn(humanoid) — ровно один раз, когда Humanoid погиб: по событию Died или как только Health стало ≤ 0
-- (Died приходит не всегда сразу — например, если состояние Humanoid сейчас не обновляется). Возвращает
-- функцию, которая отменяет ожидание.
function HumanoidUtil.OnDeath(humanoid, fn)
	local done = false
	local died, health
	local function cancel()
		done = true
		if died then
			died:Disconnect()
		end
		if health then
			health:Disconnect()
		end
	end
	local function fire()
		if done then
			return
		end
		cancel()
		fn(humanoid)
	end
	died = humanoid.Died:Connect(fire)
	health = humanoid.HealthChanged:Connect(function(value)
		if value <= 0 then
			fire()
		end
	end)
	if humanoid.Health <= 0 then
		task.defer(fire)
	end
	return cancel
end

return HumanoidUtil
