-- NpcFactory: создаёт людей-NPC (покупателей и «Покупателя»), проигрывает им анимации,
-- водит по точкам и показывает реплики над головой.
-- Модели делает Players:CreateHumanoidModelFromDescription: реалистичные тела и живые лица
-- из каталога Roblox (вещи Roblox: Oliver, Summer, City Life Woman, Man, Woman, Kenneth),
-- многослойная одежда, причёски и обувь. Если каталог недоступен — простая модель с цветной одеждой.
-- Анимации ходьбы, бега и ожидания — собственные (Shared/Models.Anim, их делает tools/make_anims.py).
local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Models = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Models"))

local NpcFactory = {}

local ANIM = Models.Anim

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local SKIN = { rgb(234, 192, 160), rgb(224, 172, 136), rgb(196, 142, 104), rgb(150, 100, 70), rgb(242, 210, 186), rgb(110, 74, 52) }
local TOPS = { rgb(34, 40, 58), rgb(70, 72, 76), rgb(24, 24, 26), rgb(84, 92, 60), rgb(110, 30, 36), rgb(150, 130, 100), rgb(40, 70, 110), rgb(120, 120, 124), rgb(60, 40, 30) }
local BOTTOMS = { rgb(30, 36, 60), rgb(24, 24, 26), rgb(60, 62, 66), rgb(70, 56, 40), rgb(40, 50, 80) }
local HAIR = { rgb(26, 20, 16), rgb(60, 40, 26), rgb(110, 80, 50), rgb(190, 160, 110), rgb(150, 150, 150), rgb(90, 30, 20) }
local HATS = { rgb(30, 30, 34), rgb(120, 24, 30), rgb(40, 60, 90), rgb(80, 80, 84) }

local PARTS_TOP = { "UpperTorso", "LeftUpperArm", "LeftLowerArm", "RightUpperArm", "RightLowerArm" }
local PARTS_BOTTOM = { "LowerTorso", "LeftUpperLeg", "LeftLowerLeg", "RightUpperLeg", "RightLowerLeg" }
local PARTS_SKIN = { "Head", "LeftHand", "RightHand" }
local PARTS_SHOES = { "LeftFoot", "RightFoot" }

local rng = Random.new()

function NpcFactory.Init()
	-- NPC не толкают игроков и друг друга (но стоят на полу)
	pcall(function()
		PhysicsService:RegisterCollisionGroup("NPC")
		PhysicsService:RegisterCollisionGroup("Players")
	end)
	PhysicsService:CollisionGroupSetCollidable("NPC", "NPC", false)
	PhysicsService:CollisionGroupSetCollidable("NPC", "Players", false)
end

-- Персонаж игрока в группе столкновений Players
function NpcFactory.SetPlayerCollision(character)
	local function apply(d)
		if d:IsA("BasePart") then
			d.CollisionGroup = "Players"
		end
	end
	for _, d in ipairs(character:GetDescendants()) do
		apply(d)
	end
	character.DescendantAdded:Connect(apply)
end

local function addHair(model, color, beanie)
	local head = model:FindFirstChild("Head")
	if not head then
		return
	end
	local hair = Instance.new("Part")
	hair.Name = beanie and "Beanie" or "Hair"
	hair.Size = head.Size
	hair.CanCollide = false
	hair.CanQuery = false
	hair.CanTouch = false
	hair.Massless = true
	hair.Color = color
	hair.Material = beanie and Enum.Material.Fabric or Enum.Material.SmoothPlastic
	hair.CollisionGroup = "NPC"
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Scale = beanie and Vector3.new(1.12, 0.72, 1.1) or Vector3.new(1.06, 0.6, 1.0)
	mesh.Parent = hair
	hair.CFrame = head.CFrame * (beanie and CFrame.new(0, 0.34, 0.12) or CFrame.new(0, 0.3, 0.2))
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = head
	weld.Part1 = hair
	weld.Parent = hair
	hair.Parent = model
end

-------------------------------------------------------------------------------
-- Реалистичная внешность из каталога Roblox
-------------------------------------------------------------------------------
-- Тела (части из наборов Roblox) и живые головы с мимикой
local BODIES = {
	{ Name = "Oliver", Male = true, Torso = 3963871432, LeftArm = 3963861732, RightArm = 3963867514, LeftLeg = 3963864909, RightLeg = 3963869770, Head = 12778883791, Mood = 79356521114937, Brows = 12778888565 },
	{ Name = "Kenneth", Male = true, Torso = 4637290950, LeftArm = 4637157175, RightArm = 4637286849, LeftLeg = 4637285693, RightLeg = 4637289137, Head = 15093144795, Mood = 15093151872, Brows = 15093184900 },
	{ Name = "Man", Male = true, Torso = 86500008, LeftArm = 86500054, RightArm = 86500036, LeftLeg = 86500064, RightLeg = 86500078, Head = 10725826963, Mood = 10725833199 },
	{ Name = "Summer", Male = false, Torso = 3963485362, LeftArm = 3963476651, RightArm = 3963481369, LeftLeg = 3963479563, RightLeg = 3963483107, Head = 12853000475, Mood = 12954144780, Brows = 12853002044, Lashes = 12853004141 },
	{ Name = "CityLife", Male = false, Torso = 2492674027, LeftArm = 2492667589, RightArm = 2492669375, LeftLeg = 2492671662, RightLeg = 2492670347, Head = 15093243863, Mood = 15093245263, Brows = 15093246364 },
	{ Name = "Woman", Male = false, Torso = 86499666, LeftArm = 86499716, RightArm = 86499698, LeftLeg = 86499753, RightLeg = 86499793, Head = 10725626210, Mood = 10725638029 },
}
local HAIR_M = { 3963874672, 4637431811, 62234425, 9244021842, 9244111257 }
local HAIR_F = { 3963490791, 2492675286, 7193442167, 9244095135, 7193448258, 6993754725 }
-- Многослойная одежда Roblox: { id, тип }
local TOPS_LAYERED = {
	{ 7192553841, "Jacket" }, -- толстовка на молнии, чёрная
	{ 9240757332, "Sweater" }, -- вязаный свитер, чёрный
	{ 9240758221, "Sweater" }, -- вязаный свитер, серый
	{ 6984769289, "Sweater" }, -- вязаный свитер, бежевый
	{ 7192549218, "Jacket" }, -- кожаная куртка
	{ 8516609675, "Jacket" }, -- джинсовая куртка
	{ 8516620262, "Jacket" }, -- куртка с капюшоном, серая
	{ 8648397446, "Jacket" }, -- парка, коричневая
	{ 9120031517, "TShirt" }, -- лонгслив
	{ 9119670803, "TShirt" }, -- футболка в полоску
	{ 9112474888, "TShirt" }, -- футболка, серая
}
local BOTTOMS_LAYERED = {
	{ 6984763785, "Pants" }, -- спортивные штаны, чёрные
	{ 7192664790, "Pants" }, -- спортивные штаны, серые
	{ 6984740059, "Pants" }, -- карго, коричневые
	{ 8721985925, "Pants" }, -- брюки, коричневые
}
local SHOES = {
	{ 9482987287, 9482991343 }, -- кеды белые
	{ 9481782649, 9481786623 }, -- полукеды белые
	{ 9483690316, 9483697460 }, -- полукеды серые
	{ 7193165925, 7193166879 }, -- кроссовки серые
}
local SKIN_TONES = { rgb(234, 192, 160), rgb(224, 172, 136), rgb(196, 142, 104), rgb(242, 210, 186), rgb(160, 110, 78), rgb(110, 74, 52) }

local function accessory(id, kind, order, layered)
	if layered then
		return { AssetId = id, AccessoryType = Enum.AccessoryType[kind], IsLayered = true, Order = order }
	end
	if kind == "Eyebrow" or kind == "Eyelash" then
		-- брови и ресницы ложатся на живую голову: им нужен порядок, но не слой
		return { AssetId = id, AccessoryType = Enum.AccessoryType[kind], Order = order or 5 }
	end
	-- причёска: без слоя и порядка
	return { AssetId = id, AccessoryType = Enum.AccessoryType[kind] }
end

-- Описание внешности: тело, голова, причёска, одежда, обувь, цвет кожи
local function realisticDescription(look)
	local body = look.Body
	local d = Instance.new("HumanoidDescription")
	d.Torso = body.Torso
	d.LeftArm = body.LeftArm
	d.RightArm = body.RightArm
	d.LeftLeg = body.LeftLeg
	d.RightLeg = body.RightLeg
	d.Head = look.NoFace and 0 or body.Head
	d.Face = 0
	if not look.NoFace and body.Mood then
		d.MoodAnimation = body.Mood
	end
	d.HeightScale = look.Height or 1
	d.WidthScale = look.Width or 1
	d.DepthScale = look.Width or 1
	d.HeadScale = 1
	d.BodyTypeScale = look.BodyType or 0.3
	d.ProportionScale = 1
	for _, k in ipairs({ "HeadColor", "TorsoColor", "LeftArmColor", "RightArmColor", "LeftLegColor", "RightLegColor" }) do
		d[k] = look.Skin
	end
	local list = {}
	if look.HairId then
		table.insert(list, accessory(look.HairId, "Hair", nil, false))
	end
	if not look.NoFace then
		if body.Brows then
			table.insert(list, accessory(body.Brows, "Eyebrow", nil, false))
		end
		if body.Lashes then
			table.insert(list, accessory(body.Lashes, "Eyelash", nil, false))
		end
	end
	if look.Bottom then
		table.insert(list, accessory(look.Bottom[1], look.Bottom[2], 1, true))
	end
	if look.Top then
		table.insert(list, accessory(look.Top[1], look.Top[2], look.Top[2] == "TShirt" and 2 or 3, true))
	end
	if look.Shoes then
		table.insert(list, accessory(look.Shoes[1], "LeftShoe", 4, true))
		table.insert(list, accessory(look.Shoes[2], "RightShoe", 4, true))
	end
	d:SetAccessories(list, true)
	return d
end

local function pick(list)
	return list[rng:NextInteger(1, #list)]
end

local function realisticLook()
	local body = pick(BODIES)
	return {
		Realistic = true,
		Body = body,
		HairId = rng:NextNumber() < 0.92 and pick(body.Male and HAIR_M or HAIR_F) or nil,
		Top = pick(TOPS_LAYERED),
		Bottom = pick(BOTTOMS_LAYERED),
		Shoes = pick(SHOES),
		Skin = pick(SKIN_TONES),
		Height = rng:NextNumber(0.95, 1.05),
		Width = rng:NextNumber(0.92, 1.04),
	}
end

-- Собрать модель человека.
-- Реалистичная: look = { Realistic = true, Body, HairId, Top, Bottom, Shoes, Skin, Height, Width, NoFace }
-- Простая (запасная): look = { Skin, Top, Bottom, Shoes, Hair, Beanie, Height, Width, NoFace }
local function buildRig(look)
	local model
	if look.Realistic then
		local ok, res = pcall(function()
			return Players:CreateHumanoidModelFromDescription(realisticDescription(look), Enum.HumanoidRigType.R15)
		end)
		if ok then
			model = res
		else
			warn("[NPC] реалистичная внешность не загрузилась, беру простую: " .. tostring(res))
			look = look.Fallback or {
				Skin = look.Skin,
				Top = rgb(60, 62, 66),
				Bottom = rgb(30, 34, 50),
				Height = look.Height,
				Width = look.Width,
				NoFace = look.NoFace,
			}
		end
	end
	if model then
		local animate = model:FindFirstChild("Animate")
		if animate then
			animate:Destroy()
		end
		if look.NoFace then
			local head = model:FindFirstChild("Head")
			if head then
				for _, d in ipairs(head:GetChildren()) do
					if d:IsA("Decal") then
						d:Destroy()
					end
				end
				if head:IsA("MeshPart") then
					pcall(function()
						head.TextureID = ""
					end)
				end
			end
		end
		local hum = model:FindFirstChildOfClass("Humanoid")
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		hum.BreakJointsOnDeath = false
		hum.RequiresNeck = false
		for _, st in ipairs({ Enum.HumanoidStateType.FallingDown, Enum.HumanoidStateType.Ragdoll, Enum.HumanoidStateType.Climbing, Enum.HumanoidStateType.Swimming }) do
			hum:SetStateEnabled(st, false)
		end
		for _, p in ipairs(model:GetDescendants()) do
			if p:IsA("BasePart") then
				p.CollisionGroup = "NPC"
			end
		end
		return model, hum
	end
	local d = Instance.new("HumanoidDescription")
	d.HeightScale = look.Height or 1
	d.WidthScale = look.Width or 1
	d.DepthScale = look.Width or 1
	d.HeadScale = 1
	d.BodyTypeScale = 0
	d.ProportionScale = 0
	model = Players:CreateHumanoidModelFromDescription(d, Enum.HumanoidRigType.R15)
	local bc = model:FindFirstChildOfClass("BodyColors")
	if bc then
		bc:Destroy()
	end
	local animate = model:FindFirstChild("Animate")
	if animate then
		animate:Destroy()
	end
	local function paint(names, color)
		for _, n in ipairs(names) do
			local p = model:FindFirstChild(n)
			if p then
				p.Color = color
			end
		end
	end
	paint(PARTS_SKIN, look.Skin)
	paint(PARTS_TOP, look.Top)
	paint(PARTS_BOTTOM, look.Bottom)
	paint(PARTS_SHOES, look.Shoes or rgb(20, 20, 22))
	if look.NoFace then
		local head = model:FindFirstChild("Head")
		if head and head:IsA("MeshPart") then
			pcall(function()
				head.TextureID = ""
			end)
		end
	end
	if look.Hair then
		addHair(model, look.Hair, look.Beanie)
	end
	local hum = model:FindFirstChildOfClass("Humanoid")
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	hum.BreakJointsOnDeath = false
	hum.RequiresNeck = false
	for _, st in ipairs({ Enum.HumanoidStateType.FallingDown, Enum.HumanoidStateType.Ragdoll, Enum.HumanoidStateType.Climbing, Enum.HumanoidStateType.Swimming }) do
		hum:SetStateEnabled(st, false)
	end
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then
			p.CollisionGroup = "NPC"
		end
	end
	return model, hum
end

local function simpleLook()
	local hat = rng:NextNumber() < 0.25
	return {
		Skin = SKIN[rng:NextInteger(1, #SKIN)],
		Top = TOPS[rng:NextInteger(1, #TOPS)],
		Bottom = BOTTOMS[rng:NextInteger(1, #BOTTOMS)],
		Hair = hat and HATS[rng:NextInteger(1, #HATS)] or (rng:NextNumber() < 0.85 and HAIR[rng:NextInteger(1, #HAIR)] or nil),
		Beanie = hat,
		Height = rng:NextNumber(0.94, 1.06),
		Width = rng:NextNumber(0.9, 1.05),
	}
end

local function randomLook()
	if Models.RealisticPeople then
		return realisticLook()
	end
	return simpleLook()
end

-- Облик «Покупателя»: обычный высокий человек в сером пальто. Вблизи видно, что у него нет лица.
NpcFactory.MonsterLook = {
	Realistic = true,
	Body = BODIES[3], -- «Man»: обычное тело, лицо убираем
	HairId = 9244021842, -- пробор, чёрные волосы
	Top = { 8516638468, "Jacket" }, -- деловое пальто, серое
	Bottom = { 6984763785, "Pants" },
	Shoes = SHOES[4],
	Skin = rgb(214, 206, 200),
	Height = 1.09,
	Width = 0.92,
	NoFace = true,
	Fallback = {
		Skin = rgb(214, 206, 200),
		Top = rgb(74, 74, 78),
		Bottom = rgb(30, 30, 34),
		Shoes = rgb(16, 16, 16),
		Hair = rgb(24, 22, 20),
		Height = 1.09,
		Width = 0.92,
		NoFace = true,
	},
}

local function wrap(model, hum, kind)
	local root = model:FindFirstChild("HumanoidRootPart")
	local npc = {
		Model = model,
		Humanoid = hum,
		Root = root,
		Kind = kind,
		Alive = true,
		RootHeight = hum.HipHeight + root.Size.Y / 2,
	}
	model:SetAttribute("NpcKind", kind)
	return npc
end

-- Собственные анимации ходьбы, бега и ожидания (проигрываются на сервере и видны всем).
-- Темп шага подстраивается под скорость, чтобы ноги не скользили по полу.
local function heightScale(hum)
	local v = hum:FindFirstChild("BodyHeightScale")
	return (v and v:IsA("NumberValue") and v.Value > 0) and v.Value or 1
end

function NpcFactory.Animate(npc)
	local hum = npc.Humanoid
	local animator = hum:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = hum
	end
	local function load(id, priority)
		local a = Instance.new("Animation")
		a.AnimationId = id
		local ok, track = pcall(function()
			return animator:LoadAnimation(a)
		end)
		if ok and track then
			track.Looped = true
			track.Priority = priority
			return track
		end
		return nil
	end
	local idleTrack = load(ANIM.Idle, Enum.AnimationPriority.Idle)
	local walkTrack = load(ANIM.Walk, Enum.AnimationPriority.Movement)
	local runTrack = load(ANIM.Run, Enum.AnimationPriority.Movement)
	if idleTrack then
		idleTrack:Play()
	end
	local hs = heightScale(hum)
	local current = nil
	hum.Running:Connect(function(speed)
		local want, rate = nil, 1
		if speed > 0.6 then
			if speed >= ANIM.RunFrom and runTrack then
				want, rate = runTrack, math.clamp(speed / (ANIM.RunNatural * hs), 0.7, 1.5)
			else
				want, rate = walkTrack, math.clamp(speed / (ANIM.WalkNatural * hs), 0.45, 1.6)
			end
		end
		if want ~= current then
			if current then
				current:Stop(0.25)
			end
			if want then
				want:Play(0.25)
			end
			current = want
		end
		if want then
			want:AdjustSpeed(rate)
		end
	end)
	npc.Tracks = { Walk = walkTrack, Run = runTrack, Idle = idleTrack }
end

-- Обычный покупатель (случайная внешность). Возвращает nil, если модель не создалась.
function NpcFactory.Customer(parent, position, look)
	local ok, model, hum = pcall(buildRig, look or randomLook())
	if not ok then
		warn("[NPC] не удалось создать покупателя: " .. tostring(model))
		return nil
	end
	model.Name = "Customer"
	local npc = wrap(model, hum, "Customer")
	hum.WalkSpeed = 8
	model:PivotTo(CFrame.new(position + Vector3.new(0, npc.RootHeight + 0.1, 0)))
	model.Parent = parent
	pcall(function()
		npc.Root:SetNetworkOwner(nil)
	end)
	NpcFactory.Animate(npc)
	return npc
end

-- «Покупатель»: закреплённая модель, которая не ходит, а появляется в новых местах
function NpcFactory.Monster(parent)
	local ok, model, hum = pcall(buildRig, NpcFactory.MonsterLook)
	if not ok then
		warn("[NPC] не удалось создать Покупателя: " .. tostring(model))
		return nil
	end
	model.Name = "TheCustomer"
	local npc = wrap(model, hum, "Monster")
	npc.Root.Anchored = true
	model:PivotTo(CFrame.new(0, -500, 0))
	model.Parent = parent
	return npc
end

function NpcFactory.Destroy(npc)
	if npc and npc.Alive then
		npc.Alive = false
		if npc.Model then
			npc.Model:Destroy()
		end
	end
end

-- Поставить NPC в точку пола cf (позиция на полу + направление взгляда)
function NpcFactory.PlaceAt(npc, cf)
	local pos = cf.Position
	local look = cf.LookVector
	local at = Vector3.new(pos.X, pos.Y + npc.RootHeight, pos.Z)
	npc.Model:PivotTo(CFrame.lookAt(at, at + Vector3.new(look.X, 0, look.Z)))
end

-- Повернуть NPC лицом к точке
function NpcFactory.Face(npc, target)
	if not (npc.Alive and npc.Root) then
		return
	end
	local p = npc.Root.Position
	local flat = Vector3.new(target.X, p.Y, target.Z)
	if (flat - p).Magnitude > 0.05 then
		npc.Model:PivotTo(CFrame.lookAt(p, flat))
	end
end

local function flat(a, b)
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

-- Дойти до точки. true — дошёл, false — не успел или NPC удалён
function NpcFactory.WalkTo(npc, target, timeout)
	if not npc.Alive then
		return false
	end
	local hum, root = npc.Humanoid, npc.Root
	timeout = timeout or 14
	local started = os.clock()
	local lastPos, lastMove = root.Position, os.clock()
	hum:MoveTo(target)
	while npc.Alive do
		task.wait(0.15)
		if not npc.Alive or not root.Parent then
			return false
		end
		if flat(root.Position, target) < 1.3 then
			return true
		end
		if os.clock() - started > timeout then
			return false
		end
		if (root.Position - lastPos).Magnitude > 0.4 then
			lastPos, lastMove = root.Position, os.clock()
		elseif os.clock() - lastMove > 2.5 then
			-- застрял: подвинем на шаг к цели
			local dir = Vector3.new(target.X - root.Position.X, 0, target.Z - root.Position.Z)
			if dir.Magnitude > 0.1 then
				root.CFrame = root.CFrame + dir.Unit * 1.5
			end
			lastMove = os.clock()
		end
		hum:MoveTo(target)
	end
	return false
end

-- Пройти по списку точек
function NpcFactory.Follow(npc, points, timeoutEach)
	for _, p in ipairs(points) do
		if not NpcFactory.WalkTo(npc, p, timeoutEach) and not npc.Alive then
			return false
		end
	end
	return npc.Alive
end

-- Реплика над головой
function NpcFactory.Say(npc, text, seconds)
	if not (npc and npc.Alive) then
		return
	end
	local head = npc.Model:FindFirstChild("Head")
	if not head then
		return
	end
	local old = head:FindFirstChild("Speech")
	if old then
		old:Destroy()
	end
	local bb = Instance.new("BillboardGui")
	bb.Name = "Speech"
	bb.Size = UDim2.fromOffset(240, 54)
	bb.StudsOffset = Vector3.new(0, 2.3, 0)
	bb.MaxDistance = 45
	bb.Adornee = head
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(250, 250, 248)
	label.BackgroundTransparency = 0.1
	label.TextColor3 = Color3.fromRGB(30, 30, 34)
	label.Font = Enum.Font.GothamMedium
	label.TextScaled = true
	label.TextWrapped = true
	label.Text = text
	label.Parent = bb
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = label
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.PaddingTop = UDim.new(0, 4)
	pad.PaddingBottom = UDim.new(0, 4)
	pad.Parent = label
	bb.Parent = head
	Debris:AddItem(bb, seconds or 3)
end

return NpcFactory
