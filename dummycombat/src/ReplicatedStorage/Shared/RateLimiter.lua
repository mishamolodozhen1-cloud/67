-- RateLimiter: «ведро с жетонами» — не чаще заданного темпа, с запасом на короткие всплески.
--
--   local limiter = RateLimiter.new(5, 2)   -- 5 сразу, дальше 2 в секунду
--   if limiter:Allow(player) then ... end
--   limiter:Forget(player)                  -- игрок ушёл: его ведро больше не нужно
--
-- Ключ — что угодно (игрок, UserId, строка). clock — своя функция времени (для проверок), по умолчанию os.clock.
local RateLimiter = {}
RateLimiter.__index = RateLimiter

function RateLimiter.new(burst, perSecond, clock)
	assert(type(burst) == "number" and burst >= 1, "RateLimiter.new: Burst должен быть ≥ 1")
	assert(type(perSecond) == "number" and perSecond > 0, "RateLimiter.new: PerSecond должен быть > 0")
	return setmetatable({
		Burst = burst,
		PerSecond = perSecond,
		Clock = clock or os.clock,
		_buckets = {},
	}, RateLimiter)
end

-- Можно ли сейчас (и сразу «тратит» жетон, если можно)
function RateLimiter:Allow(key)
	local now = self.Clock()
	local b = self._buckets[key]
	if not b then
		b = { Tokens = self.Burst, At = now }
		self._buckets[key] = b
	end
	b.Tokens = math.min(self.Burst, b.Tokens + math.max(0, now - b.At) * self.PerSecond)
	b.At = now
	if b.Tokens >= 1 then
		b.Tokens = b.Tokens - 1
		return true
	end
	return false
end

function RateLimiter:Forget(key)
	self._buckets[key] = nil
end

return RateLimiter
