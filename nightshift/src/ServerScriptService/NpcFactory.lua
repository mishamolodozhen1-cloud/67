-- NpcFactory: создаёт людей-NPC (покупателей и «Покупателя»), проигрывает им анимации,
-- водит по точкам и показывает реплики над головой.
-- Модели делает Players:CreateHumanoidModelFromDescription (стандартный R15 Roblox), одежду задаём цветом частей тела.
local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local Debris = game:GetService("Debris")

local NpcFactory = {}

local ANIM_WALK = "rbxassetid://507777826" -- стандартная R15-анимация ходьбы Roblox
local ANIM_IDLE = "rbxassetid://507766388" -- стандартная R15-анимация ожидания

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

-- Собрать модель человека. look = { Skin, Top, Bottom, Shoes, Hair, Beanie, Height, Width, NoFace }
local function buildRig(look)
	local d = Instance.new("HumanoidDescription")
	d.HeightScale = look.Height or 1
	d.WidthScale = look.Width or 1
	d.DepthScale = look.Width or 1
	d.HeadScale = 1
	d.BodyTypeScale = 0
	d.ProportionScale = 0
	local model = Players:CreateHumanoidModelFromDescription(d, Enum.HumanoidRigType.R15)
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

local function randomLook()
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

-- Облик «Покупателя»: обычный человек в сером пальто. Вблизи видно, что у него нет лица.
NpcFactory.MonsterLook = {
	Skin = rgb(214, 206, 200),
	Top = rgb(74, 74, 78),
	Bottom = rgb(30, 30, 34),
	Shoes = rgb(16, 16, 16),
	Hair = rgb(24, 22, 20),
	Height = 1.09,
	Width = 0.92,
	NoFace = true,
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

-- Анимации ходьбы и ожидания (проигрываются на сервере и видны всем)
function NpcFactory.Animate(npc)
	local hum = npc.Humanoid
	local animator = hum:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = hum
	end
	local walk = Instance.new("Animation")
	walk.AnimationId = ANIM_WALK
	local idle = Instance.new("Animation")
	idle.AnimationId = ANIM_IDLE
	local okW, walkTrack = pcall(function()
		return animator:LoadAnimation(walk)
	end)
	local okI, idleTrack = pcall(function()
		return animator:LoadAnimation(idle)
	end)
	if okI then
		idleTrack.Looped = true
		idleTrack.Priority = Enum.AnimationPriority.Idle
		idleTrack:Play()
	end
	if okW then
		walkTrack.Looped = true
		walkTrack.Priority = Enum.AnimationPriority.Movement
		hum.Running:Connect(function(speed)
			if speed > 0.6 then
				if not walkTrack.IsPlaying then
					walkTrack:Play(0.2)
				end
				walkTrack:AdjustSpeed(math.clamp(speed / 10, 0.4, 1.4))
			elseif walkTrack.IsPlaying then
				walkTrack:Stop(0.25)
			end
		end)
	end
	npc.Tracks = { Walk = okW and walkTrack or nil, Idle = okI and idleTrack or nil }
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
