-- HitCheck: геометрия проверки выстрелов на сервере (чистые функции — их проверяет tests/stage4).
--
-- Клиент сам ищет попадание (луч из камеры) и сообщает, в какую часть тела попал. Сервер не верит на слово:
--   • точка выстрела должна быть у головы стрелка (с запасом на его скорость и задержку сети);
--   • луч должен пройти через коробку этой части (с небольшим запасом) там, где цель была В МОМЕНТ ВЫСТРЕЛА
--     у стрелка на экране — положение цели «отматывается» назад по истории (компенсация задержки, не
--     дальше MaxRewind), а также проверяется и текущее положение;
--   • между стрелком и точкой попадания не должно быть стены.
local HitCheck = {}

-- Пересечение луча (origin, dir — единичный) с повёрнутой коробкой (box — CFrame центра, half — половины
-- размеров). Возвращает расстояние до входа (0, если начало внутри) или nil
function HitCheck.RayBox(origin, dir, box, half)
	local o = box:PointToObjectSpace(origin)
	local d = box:VectorToObjectSpace(dir)
	local tmin, tmax = -math.huge, math.huge
	for _, axis in ipairs({ "X", "Y", "Z" }) do
		local oa, da, h = o[axis], d[axis], half[axis]
		if math.abs(da) < 1e-9 then
			if oa < -h or oa > h then
				return nil
			end
		else
			local t1, t2 = (-h - oa) / da, (h - oa) / da
			if t1 > t2 then
				t1, t2 = t2, t1
			end
			tmin = math.max(tmin, t1)
			tmax = math.min(tmax, t2)
			if tmin > tmax then
				return nil
			end
		end
	end
	if tmax < 0 then
		return nil
	end
	return math.max(tmin, 0)
end

-- Где была часть тела, если корень персонажа был в rootThen (а сейчас в rootNow): поза тела относительно
-- корня за доли секунды почти не меняется, сдвигаем часть вместе с корнем
function HitCheck.Rewind(partCF, rootNow, rootThen)
	return rootThen * rootNow:ToObjectSpace(partCF)
end

-- Точка выстрела у головы? speed — скорость стрелка (studs/с), latency — задержка (с)
function HitCheck.OriginOk(origin, head, speed, latency, tolerance)
	return (origin - head).Magnitude <= tolerance + speed * math.clamp(latency, 0, 1)
end

-- Время, на которое отматывать цели: момент выстрела у клиента минус задержка показа чужих персонажей,
-- но не раньше now - maxRewind и не позже now
function HitCheck.RewindTime(clientTime, now, interpDelay, maxRewind)
	return math.clamp(clientTime - interpDelay, now - maxRewind, now)
end

-- Попадает ли луч в часть (коробка part.Size + запас tolerance) при положении части partCF.
-- Возвращает расстояние вдоль луча или nil
function HitCheck.RayHitsPart(origin, dir, partCF, size, tolerance)
	local half = size / 2 + Vector3.new(tolerance, tolerance, tolerance)
	return HitCheck.RayBox(origin, dir, partCF, half)
end

-- Точка попадания, которую прислал клиент, лежит на луче (не дальше slack от него) и не дальше range?
function HitCheck.PointOnRay(origin, dir, point, range, slack)
	local rel = point - origin
	local along = rel:Dot(dir)
	if along < -slack or along > range + slack then
		return false
	end
	local closest = origin + dir * along
	return (point - closest).Magnitude <= slack
end

return HitCheck
