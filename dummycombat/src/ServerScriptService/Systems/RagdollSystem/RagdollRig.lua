-- RagdollRig: физические суставы манекена и переключение «анимация ↔ тряпичная кукла».
--
-- Build(model) — один раз, в шаблоне персонажа (CharacterSystem): для каждого Motor6D, кроме Root,
-- добавляет ограничение из RagdollConfig (BallSocketConstraint или HingeConstraint с пределами и трением),
-- выключенное, и NoCollisionConstraint между соседними частями (иначе они бы толкали друг друга в суставе).
-- Так у каждого появившегося игрока всё уже готово, и переход в регдолл — это переключение, а не создание
-- объектов посреди боя.
--
-- SetEnabled(model, true): Motor6D выключаются (кроме Root: HumanoidRootPart следует за тазом, но становится
-- невесомым и не сталкивается), ограничения включаются, все части тела сталкиваются с миром, группа
-- столкновений — «регдолл». SetEnabled(model, false) возвращает всё как было (исходные значения хранятся
-- в атрибутах частей, записанных при Build).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Configs = ReplicatedStorage:WaitForChild("Configs")
local RagdollConfig = require(Configs:WaitForChild("RagdollConfig"))

local RagdollRig = {}

local PREFIX = "Ragdoll_"
local FORWARD = Vector3.new(0, 0, -1)
local UP = Vector3.new(0, 1, 0)

-- Вторая ось точки крепления: перпендикулярна первой, «смотрит» вперёд (или вверх, если первая — вперёд)
function RagdollRig.Secondary(primary)
	local ref = math.abs(primary:Dot(FORWARD)) < 0.9 and FORWARD or UP
	return (ref - primary * ref:Dot(primary)).Unit
end

local function frame(position, primary, secondary)
	return CFrame.fromMatrix(position, primary, secondary)
end

-- Точки крепления сустава в осях частей (поза покоя: части не повёрнуты). Возвращает CFrame для Part0 и Part1
function RagdollRig.AttachmentFrames(def, c0Position, c1Position)
	if def.Type == "Hinge" then
		local x, y = def.Hinge, def.Bone
		return frame(c0Position, x, y), frame(c1Position, x, y)
	end
	local a0 = frame(c0Position, def.Axis, RagdollRig.Secondary(def.Axis))
	local a1 = frame(c1Position, def.Bone, RagdollRig.Secondary(def.Bone))
	return a0, a1
end

local function motorsOf(model)
	local list = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Motor6D") then
			list[d.Name] = d
		end
	end
	return list
end

function RagdollRig.Build(model)
	local motors = motorsOf(model)
	local built = 0
	for jointName, def in pairs(RagdollConfig.Joints) do
		local motor = motors[jointName]
		if not motor then
			error("нет сустава " .. jointName .. " для регдолла", 0)
		end
		local p0, p1 = motor.Part0, motor.Part1
		local f0, f1 = RagdollRig.AttachmentFrames(def, motor.C0.Position, motor.C1.Position)
		local a0 = Instance.new("Attachment")
		a0.Name = PREFIX .. jointName .. "0"
		a0.CFrame = f0
		a0.Parent = p0
		local a1 = Instance.new("Attachment")
		a1.Name = PREFIX .. jointName .. "1"
		a1.CFrame = f1
		a1.Parent = p1
		local c
		if def.Type == "Hinge" then
			c = Instance.new("HingeConstraint")
			c.LimitsEnabled = true
			c.LowerAngle = def.Lower
			c.UpperAngle = def.Upper
			-- «мотор» с нулевой скоростью и малым моментом — это трение в суставе
			c.ActuatorType = Enum.ActuatorType.Motor
			c.AngularVelocity = 0
			c.MotorMaxTorque = def.Friction
			c.MotorMaxAcceleration = math.huge
		else
			c = Instance.new("BallSocketConstraint")
			c.LimitsEnabled = true
			c.UpperAngle = def.Cone
			c.TwistLimitsEnabled = true
			c.TwistLowerAngle = def.TwistLower
			c.TwistUpperAngle = def.TwistUpper
			c.MaxFrictionTorque = def.Friction
		end
		c.Name = PREFIX .. jointName
		c.Restitution = 0
		c.Attachment0 = a0
		c.Attachment1 = a1
		c.Enabled = false
		c.Parent = p1
		local nc = Instance.new("NoCollisionConstraint")
		nc.Name = PREFIX .. jointName .. "NoCollide"
		nc.Part0 = p0
		nc.Part1 = p1
		nc.Parent = p1
		built = built + 1
	end
	-- исходные значения частей — чтобы вернуть их после регдолла
	for _, d in ipairs(model:GetChildren()) do
		if d:IsA("BasePart") then
			d:SetAttribute("DC_Collide", d.CanCollide)
			d:SetAttribute("DC_Massless", d.Massless)
		end
	end
	model:SetAttribute("DC_RagdollRig", built)
	return built
end

function RagdollRig.IsBuilt(model)
	return (model:GetAttribute("DC_RagdollRig") or 0) > 0
end

-- Включить / выключить регдолл. group — группа столкновений частей (живые / регдолл)
function RagdollRig.SetEnabled(model, on, group)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Motor6D") then
			-- только суставы тела (они лежат в частях тела — прямых детях модели); суставы оружия в руках
			-- (этап 4: крепление к корпусу, магазин, затвор) не трогаем
			if d.Name ~= "Root" and d.Parent and d.Parent.Parent == model then
				d.Enabled = not on
			end
		elseif d:IsA("BallSocketConstraint") or d:IsA("HingeConstraint") then
			if string.sub(d.Name, 1, #PREFIX) == PREFIX then
				d.Enabled = on
			end
		end
	end
	for _, d in ipairs(model:GetChildren()) do
		if d:IsA("BasePart") then
			if d.Name == "HumanoidRootPart" then
				d.CanCollide = not on and d:GetAttribute("DC_Collide") == true
				d.Massless = on or d:GetAttribute("DC_Massless") == true
			else
				d.CanCollide = on or d:GetAttribute("DC_Collide") == true
			end
			if group then
				d.CollisionGroup = group
			end
		end
	end
	model:SetAttribute("Ragdolled", on)
end

return RagdollRig
