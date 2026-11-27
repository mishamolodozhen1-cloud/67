-- ArmIK: руки манекена по двухзвенной ИК (плечо — локоть — кисть). Тот же расчёт, что в
-- tools/weapons/viewmodel.py (превью поз), — поэтому в игре руки стоят так же, как на картинках.
--
-- Solve(side, shoulder, handCF, pole) → CFrame-ы UpperArm, LowerArm, Hand (центры частей) в тех же осях, что
-- и входные данные (оси камеры для вида от первого лица, оси UpperTorso — от третьего лица):
--   shoulder — точка сустава плеча; handCF — где должна быть кисть (центр части и поворот);
--   pole — куда смотрит локоть (вниз-наружу).
-- Если кисть дальше, чем достаёт рука, рука вытягивается к ней до предела.
-- MotorTransforms переводит результат в Motor6D.Transform суставов плеча, локтя и запястья.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DummyRig = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("DummyRig"))

local ArmIK = {}

local function attachment(part, name)
	for _, item in ipairs(DummyRig.Attachments[part]) do
		if item[1] == name then
			return item[2]
		end
	end
	error("ArmIK: в DummyRig нет точки " .. part .. "." .. name)
end

-- Точки суставов руки в осях её частей (из скелета манекена)
local DIMS = {}
for _, side in ipairs({ "Right", "Left" }) do
	local d = {
		ShoulderUp = attachment(side .. "UpperArm", side .. "ShoulderRigAttachment"),
		ElbowUp = attachment(side .. "UpperArm", side .. "ElbowRigAttachment"),
		ElbowLo = attachment(side .. "LowerArm", side .. "ElbowRigAttachment"),
		WristLo = attachment(side .. "LowerArm", side .. "WristRigAttachment"),
		WristHand = attachment(side .. "Hand", side .. "WristRigAttachment"),
		ShoulderTorso = attachment("UpperTorso", side .. "ShoulderRigAttachment"),
	}
	d.Upper = (d.ElbowUp - d.ShoulderUp).Magnitude
	d.Lower = (d.WristLo - d.ElbowLo).Magnitude
	DIMS[side] = table.freeze(d)
end
ArmIK.Dims = table.freeze(DIMS)

local X_AXIS = Vector3.new(1, 0, 0)

-- Поворот, который переводит направление кости localDir в worldDir, а боковую ось localSide — как можно
-- ближе к worldSide (ось сгиба локтя)
local function align(localDir, localSide, worldDir, worldSide)
	local e1 = localDir.Unit
	local e2 = (localSide - e1 * localSide:Dot(e1)).Unit
	local e3 = e1:Cross(e2)
	local t1 = worldDir.Unit
	local t2 = (worldSide - t1 * worldSide:Dot(t1)).Unit
	local t3 = t1:Cross(t2)
	local E = CFrame.fromMatrix(Vector3.zero, e1, e2, e3)
	local T = CFrame.fromMatrix(Vector3.zero, t1, t2, t3)
	return T * E:Inverse()
end
ArmIK.Align = align

function ArmIK.Solve(side, shoulder, handCF, pole)
	local d = DIMS[side]
	local l1, l2 = d.Upper, d.Lower
	local handRot = handCF.Rotation
	local wrist = handCF:PointToWorldSpace(d.WristHand)
	local to = wrist - shoulder
	local dist = to.Magnitude
	local u = dist > 1e-6 and to / dist or Vector3.new(0, -1, 0)
	dist = math.clamp(dist, math.abs(l1 - l2) + 1e-3, l1 + l2 - 1e-3)
	local a = (l1 * l1 - l2 * l2 + dist * dist) / (2 * dist)
	local h = math.sqrt(math.max(0, l1 * l1 - a * a))
	local v = pole - u * pole:Dot(u)
	if v.Magnitude > 1e-6 then
		v = v.Unit
	else
		v = u:Cross(X_AXIS).Unit
	end
	local elbow = shoulder + u * a + v * h
	wrist = shoulder + u * dist -- не достаёт: кисть у предела вытянутой руки
	local hinge = (elbow - shoulder):Cross(wrist - elbow)
	if hinge.Magnitude < 1e-6 then
		hinge = u:Cross(v)
	end
	hinge = hinge.Unit
	local rUp = align(d.ElbowUp - d.ShoulderUp, X_AXIS, elbow - shoulder, hinge)
	local upper = CFrame.new(shoulder - rUp:VectorToWorldSpace(d.ShoulderUp)) * rUp
	local rLo = align(d.WristLo - d.ElbowLo, X_AXIS, wrist - elbow, hinge)
	local lower = CFrame.new(elbow - rLo:VectorToWorldSpace(d.ElbowLo)) * rLo
	local hand = CFrame.new(wrist - handRot:VectorToWorldSpace(d.WristHand)) * handRot
	return upper, lower, hand
end

-- Motor6D.Transform суставов руки, если части стоят upper/lower/hand (в осях UpperTorso).
-- motors = { Shoulder = Motor6D, Elbow = Motor6D, Wrist = Motor6D } (у Motor6D: Part1 = Part0 * C0 * Transform * C1⁻¹)
function ArmIK.MotorTransforms(motors, upper, lower, hand)
	local shoulder = motors.Shoulder.C0:Inverse() * upper * motors.Shoulder.C1
	local elbow = motors.Elbow.C0:Inverse() * upper:Inverse() * lower * motors.Elbow.C1
	local wrist = motors.Wrist.C0:Inverse() * lower:Inverse() * hand * motors.Wrist.C1
	return shoulder, elbow, wrist
end

return ArmIK
