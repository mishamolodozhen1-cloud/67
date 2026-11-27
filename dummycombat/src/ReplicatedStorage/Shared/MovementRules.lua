-- MovementRules: правила передвижения — одни и те же у сервера (MovementSystem) и клиента
-- (CharacterController, анимация), чтобы предсказание клиента совпадало с решением сервера.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Configs = ReplicatedStorage:WaitForChild("Configs")
local GameConfig = require(Configs:WaitForChild("GameConfig"))
local DummyRig = require(Configs:WaitForChild("DummyRig"))
local DummyAssets = require(Configs:WaitForChild("DummyAssets"))

local MovementRules = {}

local cfg = GameConfig.Movement

MovementRules.StandHipHeight = DummyRig.HipHeight
MovementRules.CrouchHipHeight = DummyRig.HipHeight - DummyAssets.CrouchDrop
MovementRules.CrouchDrop = DummyAssets.CrouchDrop
-- верх манекена над центром HumanoidRootPart (одинаков стоя и в приседе: в приседе ниже весь корпус)
MovementRules.TopAboveRoot = DummyRig.Height - (DummyRig.HipHeight + DummyRig.RootSize.Y / 2)

-- Бег возможен только стоя
function MovementRules.Resolve(stance, sprint)
	if stance ~= "Crouch" then
		stance = "Stand"
	end
	return stance, sprint == true and stance == "Stand"
end

-- Скорость: присед / бег / шаг; с прицелом (aim) — медленнее, бег с прицелом невозможен
function MovementRules.SpeedFor(stance, sprint, aim)
	stance, sprint = MovementRules.Resolve(stance, sprint and not aim)
	local speed
	if stance == "Crouch" then
		speed = cfg.CrouchSpeed
	else
		speed = sprint and cfg.SprintSpeed or cfg.WalkSpeed
	end
	if aim then
		speed = speed * cfg.AimSpeedFactor
	end
	return speed
end

function MovementRules.HipHeight(stance)
	return stance == "Crouch" and MovementRules.CrouchHipHeight or MovementRules.StandHipHeight
end

-- Движение достаточно «вперёд» для бега: moveDirection и look — в мире, сравниваются по горизонтали
function MovementRules.IsForward(moveDirection, look)
	local m = Vector3.new(moveDirection.X, 0, moveDirection.Z)
	local l = Vector3.new(look.X, 0, look.Z)
	if m.Magnitude < 0.1 or l.Magnitude < 0.1 then
		return false
	end
	return m.Unit:Dot(l.Unit) >= cfg.SprintForwardDot
end

-- В приседе ли персонаж (по текущему HipHeight — так видно и плавный переход)
function MovementRules.IsCrouchedHip(hipHeight)
	return hipHeight < MovementRules.StandHipHeight - MovementRules.CrouchDrop * 0.5
end

return MovementRules
