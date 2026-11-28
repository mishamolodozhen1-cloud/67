-- Pellets: направления дробин дробовика. Одинаковые у клиента и сервера: строятся по номеру выстрела
-- (зерно Random), поэтому сервер проверяет ровно те лучи, что клиент нарисовал и посчитал.
--
-- Directions(dir, count, spread, seed): первая дробина — по центру (dir — уже с разбросом прицела), остальные —
-- два кольца (внешнее и внутреннее через одну) с поворотом и небольшим случайным сдвигом от seed.
-- spread — угол внешнего кольца от центра (градусы).
local Pellets = {}

function Pellets.Directions(dir, count, spread, seed)
	local out = { dir }
	if count <= 1 then
		return out
	end
	local frame = CFrame.lookAt(Vector3.zero, dir)
	local rng = Random.new(seed)
	local spin = rng:NextNumber(0, math.pi * 2)
	local ring = count - 1
	for i = 1, ring do
		local theta = spin + (i - 1) / ring * math.pi * 2 + rng:NextNumber(-0.22, 0.22)
		local r = math.rad(spread) * (i % 2 == 0 and 0.55 or 1.0) * rng:NextNumber(0.82, 1.0)
		table.insert(out, (frame * CFrame.Angles(0, 0, theta) * CFrame.Angles(r, 0, 0)).LookVector)
	end
	return out
end

return Pellets
