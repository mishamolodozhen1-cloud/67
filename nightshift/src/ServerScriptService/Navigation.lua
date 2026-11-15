-- Navigation: граф точек торгового зала для покупателей (проходы, ряды у касс, вход).
-- Путь ищется алгоритмом Дейкстры по графу из MapBuilder (map.Nav). Это надёжнее и дешевле,
-- чем PathfindingService: планировка магазина заранее известна.
local Navigation = {}

local nodes, neighbors = {}, {}

function Navigation.Init(map)
	nodes = map.Nav.Nodes
	neighbors = {}
	for key in pairs(nodes) do
		neighbors[key] = {}
	end
	for _, e in ipairs(map.Nav.Edges) do
		table.insert(neighbors[e[1]], e[2])
		table.insert(neighbors[e[2]], e[1])
	end
end

function Navigation.Node(key)
	return nodes[key]
end

-- Ближайший узел к точке
function Navigation.Nearest(pos)
	local best, bestD = nil, math.huge
	for key, p in pairs(nodes) do
		local dx, dz = p.X - pos.X, p.Z - pos.Z
		local d = dx * dx + dz * dz
		if d < bestD then
			best, bestD = key, d
		end
	end
	return best
end

-- Список позиций от узла a до узла b (включая оба)
function Navigation.PathKeys(a, b)
	local dist, prev, done = { [a] = 0 }, {}, {}
	while true do
		local cur, curD = nil, math.huge
		for key, d in pairs(dist) do
			if not done[key] and d < curD then
				cur, curD = key, d
			end
		end
		if not cur or cur == b then
			break
		end
		done[cur] = true
		for _, nb in ipairs(neighbors[cur]) do
			local nd = curD + (nodes[cur] - nodes[nb]).Magnitude
			if dist[nb] == nil or nd < dist[nb] then
				dist[nb] = nd
				prev[nb] = cur
			end
		end
	end
	if dist[b] == nil then
		return { b }
	end
	local path, k = {}, b
	while k do
		table.insert(path, 1, k)
		k = prev[k]
	end
	return path
end

-- Маршрут из позиции from в позицию to: через ближайшие узлы графа
function Navigation.Route(from, to)
	local a, b = Navigation.Nearest(from), Navigation.Nearest(to)
	local points = {}
	for _, key in ipairs(Navigation.PathKeys(a, b)) do
		table.insert(points, nodes[key])
	end
	-- Первый узел пропускаем, если мы уже ближе ко второму
	if #points >= 2 then
		local d1 = (points[1] - from).Magnitude
		local d12 = (points[2] - points[1]).Magnitude
		if (points[2] - from).Magnitude < d12 and d1 < d12 then
			table.remove(points, 1)
		end
	end
	table.insert(points, to)
	return points
end

return Navigation
