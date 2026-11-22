-- Beast: существо из подсобки (v10). Высокая чёрная фигура с длинными руками (модель «New Breaking News Rig»).
-- Живёт там, где принимают поставку и носят её на склад: склад, служебный коридор, задний двор.
-- Иногда выходит в торговый зал — только когда гаснет свет. Никого не убивает: худшее, что бывает, — скример.
--
-- Как устроено:
--   • сервер ставит модель в мир и пишет в атрибуты, что она делает (Anim, AnimT0, Walk…);
--     клиент (NightClient/BeastClient) двигает кости по кадрам анимаций (Shared/BeastAnims)
--     и плавно ведёт модель по пути;
--   • клиент сообщает, что игрок увидел существо (действие BeastSeen) — по-настоящему, с учётом камеры;
--   • скример — эффект BeastScare у одного игрока: существо бросается в камеру.
-- Сценарии:
--   Cross  — проходит поперёк прохода вдали и скрывается за стеллажом;
--   Stare  — стоит и смотрит; заметили — мигает свет, и его нет;
--   Roar   — заметили — замахивается длинной рукой и ревёт, потом уходит в темноту;
--   Charge — заметили — бросается на игрока (скример, если тот не убежал);
--   Behind — гаснет свет над игроком, рычание за спиной; обернётся — скример.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local InsertService = game:GetService("InsertService")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Models = require(Shared:WaitForChild("Models"))
local Util = require(Shared:WaitForChild("Util"))

local Beast = {}

local map, S
local rng = Random.new()
local template
local active = {} -- model -> { Seen = {player = time}, OnSeen = fn, Kind = ... }
local folder
local lastScare = {} -- player -> os.clock()
local cooldownUntil = 0
local ROOMS_BACK = { ["Склад"] = true, ["Служебный коридор"] = true, ["Задний двор"] = true }

-- Места, где он может стоять (проверены по карте свободных клеток склада: между стеллажами,
-- у зоны приёмки, в коридоре, во дворе)
local SPOTS = {
	Vector3.new(-58, 0, -30),
	Vector3.new(-58, 0, -50),
	Vector3.new(-46, 0, -26),
	Vector3.new(-46, 0, -56),
	Vector3.new(-34, 0, -56),
	Vector3.new(-29, 0, -60),
	Vector3.new(-24, 0, -20),
	Vector3.new(-40, 0, -19),
	Vector3.new(-14, 0, -58),
	Vector3.new(-14, 0, -22),
	Vector3.new(-36, 0, -86),
	Vector3.new(-4, 0, -88),
	Vector3.new(-26, 0, -80),
}
-- Проходы, через которые он переходит (из точки в точку, скрываясь за стеллажами)
local CROSSINGS = {
	{ Vector3.new(-30, 0, -58.5), Vector3.new(-60, 0, -58.5) },
	{ Vector3.new(-60, 0, -20), Vector3.new(-26, 0, -20) },
	{ Vector3.new(-46, 0, -24), Vector3.new(-46, 0, -58) },
	{ Vector3.new(-58, 0, -24), Vector3.new(-58, 0, -58) },
	{ Vector3.new(-14, 0, -62), Vector3.new(-14, 0, -16) },
	{ Vector3.new(-40, 0, -88), Vector3.new(4, 0, -84) },
}

local function now()
	return workspace:GetServerTimeNow()
end

local function rootOf(player)
	return Util.rootOf(player)
end

-------------------------------------------------------------------------------
-- Модель
-------------------------------------------------------------------------------
local function loadTemplate()
	if template then
		return template
	end
	local ok, res = pcall(function()
		return InsertService:LoadAsset(Models.Beast.Id)
	end)
	if not ok or not res then
		warn("[Существо] модель не загрузилась: " .. tostring(res))
		return nil
	end
	local m = res:FindFirstChildWhichIsA("Model") or res
	local body = m:FindFirstChild("Body", true)
	if not (body and body:IsA("MeshPart")) then
		warn("[Существо] в модели нет сетки Body")
		return nil
	end
	m.Name = "Beast"
	m.Parent = nil
	local ip = m:FindFirstChild("InitialPoses")
	if ip then
		ip:Destroy()
	end
	body.Anchored = true
	body.CanCollide = false
	body.CanTouch = false
	body.CanQuery = true -- для проверок «видно ли его»
	body.CastShadow = true
	body.Material = Enum.Material.SmoothPlastic
	body.Color = Color3.fromRGB(10, 10, 12)
	-- точка опоры — между ступнями (низ модели)
	body.PivotOffset = CFrame.new(0, -body.Size.Y / 2, 0)
	m.PrimaryPart = body
	m:SetAttribute("Height", body.Size.Y)
	template = m
	-- копия для клиентов (скример они делают у себя)
	local copy = m:Clone()
	copy.Name = "BeastTemplate"
	copy.Parent = ReplicatedStorage
	res:Destroy()
	return template
end

function Beast.Ready()
	return template ~= nil
end

-- Поставить существо: cf — где стоит и куда смотрит (ступни). anim — idle/walk/roar/attack1/grab/stomp1
function Beast.Spawn(cf, anim)
	if not loadTemplate() then
		return nil
	end
	local m = template:Clone()
	m:PivotTo(cf)
	m:SetAttribute("Anim", anim or "idle")
	m:SetAttribute("AnimT0", now())
	m:SetAttribute("AnimSpeed", 1)
	m.Parent = folder
	CollectionService:AddTag(m, "NS_Beast")
	active[m] = { Seen = {}, Born = os.clock() }
	return m
end

function Beast.Play(m, anim, speed)
	if m and m.Parent then
		m:SetAttribute("Anim", anim)
		m:SetAttribute("AnimT0", now())
		m:SetAttribute("AnimSpeed", speed or 1)
	end
end

-- Идти из текущего места в точку to со скоростью speed (studs/с). Возвращает время в пути.
-- Ведёт клиент (плавно), сервер ставит модель в конечную точку, когда дошёл.
function Beast.Walk(m, to, speed, anim)
	if not (m and m.Parent) then
		return 0
	end
	local from = m:GetPivot().Position
	to = Vector3.new(to.X, from.Y, to.Z)
	local dist = (to - from).Magnitude
	local dur = dist / (speed or 5)
	m:SetAttribute("WalkFrom", from)
	m:SetAttribute("WalkTo", to)
	m:SetAttribute("WalkT0", now())
	m:SetAttribute("WalkDur", dur)
	-- естественная скорость шага в анимации ходьбы — около 6 studs/с
	Beast.Play(m, anim or "walk", math.clamp((speed or 5) / 6, 0.6, 2.4))
	local token = (m:GetAttribute("WalkToken") or 0) + 1
	m:SetAttribute("WalkToken", token)
	task.delay(dur, function()
		if m.Parent and m:GetAttribute("WalkToken") == token then
			if dist > 0.1 then
				m:PivotTo(CFrame.lookAt(to, to + (to - from).Unit))
			end
			m:SetAttribute("WalkT0", nil)
		end
	end)
	return dur
end

function Beast.Face(m, pos)
	if m and m.Parent then
		local p = m:GetPivot().Position
		local flat = Vector3.new(pos.X, p.Y, pos.Z)
		if (flat - p).Magnitude > 0.1 then
			m:PivotTo(CFrame.lookAt(p, flat))
		end
	end
end

-- Убрать: с миганием света вокруг (fx = true) или просто
function Beast.Remove(m, fx)
	if not (m and m.Parent) then
		return
	end
	if fx then
		local p = m:GetPivot().Position
		S.Net.Effect(nil, "Flicker", { Center = p, Radius = 26, Duration = 0.9 })
		S.Net.Sound("FluorFlicker", p + Vector3.new(0, 9, 0), 0.7)
		task.delay(0.35, function()
			if m.Parent then
				m:Destroy()
			end
		end)
	else
		m:Destroy()
	end
	active[m] = nil
end

function Beast.RemoveAll()
	for m in pairs(active) do
		if m.Parent then
			m:Destroy()
		end
	end
	active = {}
end

function Beast.Count()
	local n = 0
	for m in pairs(active) do
		if m.Parent then
			n = n + 1
		end
	end
	return n
end

-------------------------------------------------------------------------------
-- Кто его видит
-------------------------------------------------------------------------------
-- Клиент сообщил: игрок видит это существо (на экране и ничем не загорожено)
function Beast.ReportSeen(player, m)
	local a = typeof(m) == "Instance" and active[m]
	if not a then
		return
	end
	if not a.Seen[player] then
		a.Seen[player] = os.clock()
		if a.OnSeen then
			task.spawn(a.OnSeen, player)
		end
	end
end

local function seenBy(m)
	local a = active[m]
	if not a then
		return nil
	end
	for p in pairs(a.Seen) do
		return p
	end
	return nil
end

local function distTo(player, pos)
	local root = rootOf(player)
	if not root then
		return math.huge
	end
	return (Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(pos.X, 0, pos.Z)).Magnitude
end

-------------------------------------------------------------------------------
-- Скример
-------------------------------------------------------------------------------
function Beast.Scare(player, m)
	if not player or (lastScare[player] and os.clock() - lastScare[player] < 25) then
		return false
	end
	lastScare[player] = os.clock()
	S.Net.Effect(player, "BeastScare", {})
	-- остальные слышат рёв там, где это случилось
	local root = rootOf(player)
	if root then
		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= player then
				S.Net.Sound("BeastRoar", root.Position, 0.8, p)
			end
		end
	end
	if m then
		Beast.Remove(m, false)
	end
	S.Shift.AddStat("Scares")
	return true
end

-------------------------------------------------------------------------------
-- Сценарии
-------------------------------------------------------------------------------
-- Лучшее место: в 14–34 studs от игрока, на виду (клиент всё равно проверит «видно ли»)
local function spotFor(player, minD, maxD, wantVisible)
	local root = rootOf(player)
	if not root then
		return nil
	end
	local look = root.CFrame.LookVector
	local best, bestScore = nil, -math.huge
	for _, p in ipairs(SPOTS) do
		local d = distTo(player, p)
		if d >= minD and d <= maxD then
			local to = Vector3.new(p.X - root.Position.X, 0, p.Z - root.Position.Z).Unit
			local facing = to:Dot(Vector3.new(look.X, 0, look.Z).Unit)
			local score = (wantVisible and facing or -facing) + rng:NextNumber(0, 0.6)
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = { player.Character, folder }
			local hit = workspace:Raycast(root.Position + Vector3.new(0, 1.5, 0), Vector3.new(p.X, 5, p.Z) - (root.Position + Vector3.new(0, 1.5, 0)), params)
			if wantVisible and hit then
				score = score - 1.5
			end
			if score > bestScore then
				best, bestScore = p, score
			end
		end
	end
	return best
end

local function faceCF(pos, target)
	local flat = Vector3.new(target.X, pos.Y, target.Z)
	if (flat - pos).Magnitude < 0.1 then
		return CFrame.new(pos)
	end
	return CFrame.lookAt(pos, flat)
end

-- Игрок заметил — фраза (не каждый раз)
local function sawLine(player)
	if rng:NextNumber() < 0.75 then
		task.delay(rng:NextNumber(0.8, 1.6), function()
			S.Net.PlayerVoice(player, "Saw")
		end)
	end
end

-- Пройти поперёк прохода вдали
function Beast.Cross(player)
	local root = rootOf(player)
	if not root then
		return nil
	end
	local best, bestD = nil, math.huge
	for _, c in ipairs(CROSSINGS) do
		local mid = (c[1] + c[2]) / 2
		local d = distTo(player, mid)
		if d > 16 and d < 45 and d < bestD then
			best, bestD = c, d
		end
	end
	if not best then
		return nil
	end
	local a, b = best[1], best[2]
	if rng:NextNumber() < 0.5 then
		a, b = b, a
	end
	local m = Beast.Spawn(faceCF(a, b), "walk")
	if not m then
		return nil
	end
	active[m].OnSeen = function(p)
		sawLine(p)
	end
	local dur = Beast.Walk(m, b, 6.5)
	-- тяжёлые шаги слышны издалека
	task.spawn(function()
		local t0 = os.clock()
		while m.Parent and os.clock() - t0 < dur do
			S.Net.Sound("BeastStep", m:GetPivot().Position + Vector3.new(0, 1, 0), 0.5)
			task.wait(0.83)
		end
	end)
	task.delay(dur + 0.2, function()
		Beast.Remove(m, false)
	end)
	return m
end

-- Стоит и смотрит. mode: "Stare" (исчезает в мигании), "Roar" (ревёт и уходит), "Charge" (бросается)
function Beast.Watch(player, mode, spot)
	local root = rootOf(player)
	if not root then
		return nil
	end
	spot = spot or spotFor(player, 13, 34, true)
	if not spot then
		return nil
	end
	local m = Beast.Spawn(faceCF(spot, root.Position), "idle")
	if not m then
		return nil
	end
	S.Net.Sound("BeastGrowlLow", spot + Vector3.new(0, 6, 0), 0.7)
	local done = false
	local function finish(fx)
		if not done then
			done = true
			Beast.Remove(m, fx)
		end
	end
	active[m].OnSeen = function(p)
		if done then
			return
		end
		if mode == "Stare" then
			sawLine(p)
			task.wait(rng:NextNumber(1.0, 1.8))
			finish(true)
		elseif mode == "Roar" then
			Beast.Face(m, rootOf(p) and rootOf(p).Position or spot)
			task.wait(0.5)
			-- замах длинной рукой и рёв (анимация «roar» поднимает руки до 16 studs — в подсобке потолок 10,
			-- поэтому здесь замах attack1, он помещается)
			Beast.Play(m, "attack1", 0.8)
			S.Net.Sound("BeastRoar", m:GetPivot().Position + Vector3.new(0, 7, 0), 1)
			S.Net.Effect(nil, "Flicker", { Center = m:GetPivot().Position, Radius = 30, Duration = 2.2 })
			sawLine(p)
			task.wait(2.3)
			if not m.Parent then
				return
			end
			-- уходит прочь, вглубь
			local away = m:GetPivot().Position + (m:GetPivot().Position - (rootOf(p) and rootOf(p).Position or spot)).Unit * 10
			Beast.Walk(m, away, 5.5)
			task.wait(1.6)
			finish(true)
		elseif mode == "Charge" then
			Beast.Face(m, rootOf(p) and rootOf(p).Position or spot)
			Beast.Play(m, "stomp1")
			S.Net.Sound("BeastShriek", m:GetPivot().Position + Vector3.new(0, 7, 0), 1)
			task.wait(0.55)
			-- бежит прямо на игрока
			local t0 = os.clock()
			while m.Parent and os.clock() - t0 < 3.5 do
				local r = rootOf(p)
				if not r then
					break
				end
				local pos = m:GetPivot().Position
				local d = distTo(p, pos)
				if d < 4.5 then
					Beast.Scare(p, m)
					done = true
					return
				end
				local target = Vector3.new(r.Position.X, 0, r.Position.Z)
				local step = math.min(d - 3, 18 * 0.25)
				Beast.Walk(m, pos + (target - pos).Unit * step, 18, "walk")
				S.Net.Sound("BeastStomp", pos + Vector3.new(0, 1, 0), 0.8)
				task.wait(0.25)
			end
			finish(true)
		end
	end
	-- если подошёл вплотную — скример; если долго не замечают — исчезает
	task.spawn(function()
		local t0 = os.clock()
		while m.Parent and not done and os.clock() - t0 < 22 do
			for _, p in ipairs(Players:GetPlayers()) do
				if distTo(p, m:GetPivot().Position) < 6 and m.Parent and not done then
					done = true
					Beast.Scare(p, m)
					return
				end
			end
			task.wait(0.2)
		end
		finish(false)
	end)
	return m
end

-- За спиной: лампы над игроком гаснут, рычание сзади; обернётся — скример (клиент)
function Beast.Behind(player)
	S.Net.Effect(player, "BeastBehind", {})
end

-- В темноте (свет погас): стоит в ряду торгового зала среди покупателей. Покупатели рядом кричат и
-- убегают; подойти вплотную — скример. Исчезает, как только свет загорится
function Beast.InDark(player)
	local root = rootOf(player)
	if not root then
		return nil
	end
	local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z).Unit
	local best, bestScore = nil, -math.huge
	for _ = 1, 40 do
		local f = map.Facings[rng:NextInteger(1, #map.Facings)]
		local p = Vector3.new(f.Aisle, 0, rng:NextNumber(3, 17))
		local d = distTo(player, p)
		if d > 11 and d < 30 then
			local score = Vector3.new(p.X - root.Position.X, 0, p.Z - root.Position.Z).Unit:Dot(look) + rng:NextNumber(0, 0.5)
			if score > bestScore then
				best, bestScore = p, score
			end
		end
	end
	if not best then
		return nil
	end
	local m = Beast.Spawn(faceCF(best, root.Position), "idle")
	if not m then
		return nil
	end
	S.Net.Sound("BeastGrowlLow", best + Vector3.new(0, 6, 0), 0.9)
	S.Customers.ReactBeast(best, 22)
	active[m].OnSeen = function(p)
		sawLine(p)
	end
	task.spawn(function()
		local t0 = os.clock()
		while m.Parent and os.clock() - t0 < 40 do
			if S.Power.IsOn() then
				break
			end
			for _, p in ipairs(Players:GetPlayers()) do
				if m.Parent and distTo(p, m:GetPivot().Position) < 6 then
					Beast.Scare(p, m)
					return
				end
			end
			task.wait(0.2)
		end
		Beast.Remove(m, false)
	end)
	return m
end

-- Вспышка в темноте: на долю секунды что-то освещает его — в нескольких шагах прямо перед игроком
function Beast.Flash(player)
	local root = rootOf(player)
	if not root then
		return nil
	end
	local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z).Unit
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character, folder }
	local dist = 8
	local hit = workspace:Raycast(root.Position, look * 9, params)
	if hit then
		dist = math.max(3.5, hit.Distance - 2.5)
	end
	local pos = Vector3.new(root.Position.X, 0, root.Position.Z) + look * dist
	local m = Beast.Spawn(faceCF(pos, root.Position), "idle")
	if not m then
		return nil
	end
	S.Net.Effect(player, "BeastFlash", { Pos = pos + Vector3.new(0, 5, 0) })
	task.delay(1.4, function()
		Beast.Remove(m, false)
	end)
	return m
end

-- Случайная встреча в подсобке (зовёт EventDirector раз в минуту). night — номер ночи
function Beast.Lurk(night, force)
	if not force and os.clock() < cooldownUntil then
		return false
	end
	if Beast.Count() > 0 then
		return false
	end
	local list = {}
	for _, p in ipairs(Players:GetPlayers()) do
		local root = rootOf(p)
		if root and ROOMS_BACK[S.Store.RoomAt(root.Position) or ""] then
			table.insert(list, p)
		end
	end
	local player = Util.pick(list, rng)
	if not player then
		return false
	end
	cooldownUntil = os.clock() + (night >= 4 and 55 or 80)
	local roll = rng:NextNumber()
	if night <= 1 then
		return Beast.Cross(player) ~= nil
	elseif night == 2 then
		if roll < 0.5 then
			return Beast.Cross(player) ~= nil
		end
		return Beast.Watch(player, "Stare") ~= nil
	elseif night == 3 then
		if roll < 0.3 then
			return Beast.Cross(player) ~= nil
		elseif roll < 0.65 then
			return Beast.Watch(player, "Roar") ~= nil
		elseif roll < 0.85 then
			return Beast.Watch(player, "Stare") ~= nil
		end
		Beast.Behind(player)
		return true
	end
	if roll < 0.35 then
		return Beast.Watch(player, "Charge") ~= nil
	elseif roll < 0.6 then
		return Beast.Watch(player, "Roar") ~= nil
	elseif roll < 0.8 then
		Beast.Behind(player)
		return true
	end
	return Beast.Cross(player) ~= nil
end

-- Поставка: игрок взял коробку у заднего выхода. Пока несёт её на склад — что-то происходит
function Beast.OnDeliveryPicked(player, night)
	S.Net.PlayerVoice(player, "Delivery")
	local chance = ({ 0.75, 0.9, 1, 1, 1 })[night] or 1
	if rng:NextNumber() > chance then
		return
	end
	task.spawn(function()
		-- ждём, пока войдёт на склад (через боковую дверь из коридора)
		local t0 = os.clock()
		while os.clock() - t0 < 90 do
			local root = rootOf(player)
			if not root or player:GetAttribute("Carry") ~= "Delivery" then
				return
			end
			if S.Store.RoomAt(root.Position) == "Склад" then
				break
			end
			task.wait(0.3)
		end
		task.wait(0.6)
		if night <= 1 then
			Beast.Cross(player)
		elseif night == 2 then
			Beast.Watch(player, "Stare", Vector3.new(-46, 0, -56))
		elseif night == 3 then
			Beast.Watch(player, "Roar", Vector3.new(-34, 0, -56))
		end
		-- ночи 4–5: ждёт у зоны приёмки, см. OnDeliveryDropped
	end)
end

-- Поставку оставили в зоне приёмки (ночи 4–5): лампы склада гаснут, рычание, а когда свет вернётся —
-- оно прямо перед игроком
function Beast.OnDeliveryDropped(player, night)
	if night < 4 then
		return
	end
	local root = rootOf(player)
	if not root then
		return
	end
	S.Net.Effect(nil, "LampsOut", { Center = Vector3.new(-40, 0, -40), Radius = 40, Duration = 4 })
	S.Net.Sound("BeastGrowlLow", root.Position + root.CFrame.LookVector * 6 + Vector3.new(0, 5, 0), 1)
	task.wait(3.6)
	root = rootOf(player)
	if not root then
		return
	end
	local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z).Unit
	local pos = Vector3.new(root.Position.X, 0, root.Position.Z) + look * 5
	local m = Beast.Spawn(faceCF(pos, root.Position), "attack1")
	task.wait(0.45)
	Beast.Scare(player, m)
end

-- Игрок вошёл в подсобку: иногда он говорит сам с собой
local backLine = {} -- игрок -> когда последний раз говорил про склад
function Beast.OnRoomEnter(player, room)
	if room == "Склад" and rng:NextNumber() < 0.35 and os.clock() - (backLine[player] or -1e9) > 120 then
		backLine[player] = os.clock()
		S.Net.PlayerVoice(player, "Back")
	end
end

function Beast.Init(m, services)
	map, S = m, services
	folder = Instance.new("Folder")
	folder.Name = "Beasts"
	folder.Parent = workspace
	task.spawn(loadTemplate)
	-- клиент сообщает: игрок видит существо
	-- (подключается в GameServer: ACTIONS.BeastSeen)
	Players.PlayerRemoving:Connect(function(p)
		lastScare[p] = nil
		backLine[p] = nil
		for _, a in pairs(active) do
			a.Seen[p] = nil
		end
	end)
	-- кто в какой комнате (для реплик «не люблю этот склад»)
	local rooms = {}
	task.spawn(function()
		while true do
			task.wait(1)
			for _, p in ipairs(Players:GetPlayers()) do
				local root = rootOf(p)
				local room = root and S.Store.RoomAt(root.Position) or nil
				if room ~= rooms[p] then
					rooms[p] = room
					if room and S.Net.Get("Phase") == "Shift" then
						Beast.OnRoomEnter(p, room)
					end
				end
			end
		end
	end)
end

function Beast.Reset()
	Beast.RemoveAll()
	cooldownUntil = 0
	lastScare = {}
end

Beast.Spots = SPOTS
Beast.SeenBy = seenBy

return Beast
