-- RagdollConfig: физика тряпичной куклы DUMMY COMBAT (Systems/RagdollSystem).
--
-- Суставы. Ball — шаровой (BallSocketConstraint): угол между осями двух точек крепления не больше Cone,
-- поворот вокруг оси — от TwistLower до TwistUpper (градусы). Hinge — шарнир (HingeConstraint): сгиб вокруг
-- оси Hinge от Lower до Upper. Friction — трение в суставе (гасит болтание; торможение суставом).
--
-- Оси (Axis) — в осях частей в позе покоя (персонаж смотрит в −Z, правая сторона +X). У шаровых суставов
-- ось родительской части (Axis) может быть наклонена относительно направления кости (Bone): так диапазон
-- становится несимметричным, как у человека — бедро сгибается вперёд далеко, назад — мало.
-- Пределы проверяет тест этапа 3: ни один кадр анимаций не выходит за них (иначе при переходе в регдолл
-- сустав рывком «выстрелил» бы к пределу).
local function unit(x, y, z)
	return Vector3.new(x, y, z).Unit
end

local DOWN = Vector3.new(0, -1, 0)
local UP = Vector3.new(0, 1, 0)
local FORWARD = Vector3.new(0, 0, -1)
local RIGHT = Vector3.new(1, 0, 0)

local function deepFreeze(t)
	for _, v in pairs(t) do
		if type(v) == "table" and not table.isfrozen(v) then
			deepFreeze(v)
		end
	end
	return table.freeze(t)
end

return deepFreeze({
	Joints = {
		Waist = { Type = "Ball", Bone = UP, Axis = UP, Cone = 32, TwistLower = -64, TwistUpper = 64, Friction = 4 },
		Neck = { Type = "Ball", Bone = UP, Axis = unit(0, 1, -0.12), Cone = 42, TwistLower = -60, TwistUpper = 60, Friction = 1.2 },
		LeftShoulder = { Type = "Ball", Bone = DOWN, Axis = unit(-0.45, -0.72, -0.53), Cone = 118, TwistLower = -75, TwistUpper = 75, Friction = 1.5 },
		RightShoulder = { Type = "Ball", Bone = DOWN, Axis = unit(0.45, -0.72, -0.53), Cone = 118, TwistLower = -75, TwistUpper = 75, Friction = 1.5 },
		LeftElbow = { Type = "Hinge", Hinge = RIGHT, Bone = DOWN, Lower = -6, Upper = 150, Friction = 0.8 },
		RightElbow = { Type = "Hinge", Hinge = RIGHT, Bone = DOWN, Lower = -6, Upper = 150, Friction = 0.8 },
		LeftWrist = { Type = "Ball", Bone = DOWN, Axis = DOWN, Cone = 55, TwistLower = -40, TwistUpper = 40, Friction = 0.3 },
		RightWrist = { Type = "Ball", Bone = DOWN, Axis = DOWN, Cone = 55, TwistLower = -40, TwistUpper = 40, Friction = 0.3 },
		LeftHip = { Type = "Ball", Bone = DOWN, Axis = unit(0, -0.9, -0.42), Cone = 80, TwistLower = -35, TwistUpper = 35, Friction = 3 },
		RightHip = { Type = "Ball", Bone = DOWN, Axis = unit(0, -0.9, -0.42), Cone = 80, TwistLower = -35, TwistUpper = 35, Friction = 3 },
		LeftKnee = { Type = "Hinge", Hinge = RIGHT, Bone = DOWN, Lower = -150, Upper = 6, Friction = 1.5 },
		RightKnee = { Type = "Hinge", Hinge = RIGHT, Bone = DOWN, Lower = -150, Upper = 6, Friction = 1.5 },
		-- лодыжка: ось — вдоль стопы; ось голени наклонена к носку вверх (тыльное сгибание больше подошвенного)
		LeftAnkle = { Type = "Ball", Bone = FORWARD, Axis = unit(0, 0.3, -1), Cone = 42, TwistLower = -14, TwistUpper = 14, Friction = 0.6 },
		RightAnkle = { Type = "Ball", Bone = FORWARD, Axis = unit(0, 0.3, -1), Cone = 42, TwistLower = -14, TwistUpper = 14, Friction = 0.6 },
	},

	-- Импульсы — как изменение скорости (studs/с), умножается на массу части: лёгкая кисть и тяжёлый корпус
	-- получают одинаковый «толчок» по скорости
	Hit = {
		PartSpeed = 26, -- попавшая часть при смертельном попадании (полная сила)
		BodySpeed = 7, -- остальное тело (корпус) — доля толчка
		HeadTwist = 6, -- вращение головы от попадания в голову (рад/с)
		Window = 0.35, -- попадание считается причиной смерти, если было не раньше этого (с)
	},
	Explosion = {
		MaxSpeed = 62, -- скорость частей у центра взрыва (studs/с)
		Lift = 0.45, -- доля подброса вверх
		Spin = 4, -- случайное вращение частей (рад/с)
		Falloff = 1.6, -- (1 − расстояние/радиус)^Falloff
	},

	-- Падение без смерти (взрыв рядом, сильный толчок): сколько лежать и как вставать
	Knockdown = {
		MinTime = 1.2,
		MaxTime = 3.0,
		SettleSpeed = 3, -- встаёт, только когда тело почти не движется (studs/с)
		GetUpTimeout = 2.5, -- но не позже этого после MaxTime
	},

	-- Тела погибших: сколько лежат, сколько их одновременно, когда «засыпают» (замораживаются — без нагрузки
	-- на физику сервера)
	Corpses = {
		Lifetime = 14,
		FadeTime = 1.2,
		Max = 12,
		SleepSpeed = 0.6, -- быстрее этого (studs/с) — тело ещё движется
		SleepAfter = 1.5, -- столько секунд подряд тело почти неподвижно — замораживаем
		CheckEvery = 0.25,
	},

	CollisionGroups = {
		Characters = "DC_Characters", -- живые персонажи
		Ragdoll = "DC_Ragdoll", -- регдоллы и тела (не толкают живых, чтобы не было рывков у игроков)
	},
})
