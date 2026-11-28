-- WeaponConfig: оружие DUMMY COMBAT — характеристики и общие правила стрельбы. Читают сервер (WeaponSystem:
-- проверка выстрелов, патроны, перезарядка) и клиент (стрельба, отдача, разброс, эффекты).
-- Таблица заморожена. Углы — в градусах, расстояния — в studs, время — в секундах.
-- Модель, позы рук и звуки — в WeaponModels / WeaponPoses / WeaponAssets (создаются инструментами).
-- Урон: Damage по зонам тела (голова, корпус, руки, ноги) и спад с расстоянием Falloff — их применяет CombatSystem.
-- Звук выстрела — группа ShotSound (WeaponAssets.Sfx/Sfx2) с громкостью ShotVolume. Дробовик: Pellets дробин,
-- урон Damage — за каждую, Spread.Pellet — угол конуса дроби (Shared/Pellets). Снайперская: BoltAction — после
-- выстрела затвор передёргивают (поза Cycle), Scope — оптический прицел (сетка на экране вместо оружия).
local function deepFreeze(t)
	for _, v in pairs(t) do
		if type(v) == "table" and not table.isfrozen(v) then
			deepFreeze(v)
		end
	end
	return table.freeze(t)
end

return deepFreeze({
	Default = "AK47", -- что выдаётся при появлении (выбор оружия — этапы 7 и 10)

	-- Проверка выстрелов на сервере
	Server = {
		HistoryRate = 20, -- сколько раз в секунду запоминать положение целей (для компенсации задержки)
		HistoryWindow = 1.0, -- сколько секунд истории хранить
		MaxRewind = 0.5, -- дальше этого в прошлое попадания не «отматываются» (с)
		InterpDelay = 0.1, -- на сколько клиент показывает чужих персонажей позже (интерполяция Roblox)
		OriginTolerance = 4.5, -- насколько точка выстрела может отличаться от головы стрелка (studs)
		HitTolerance = 0.9, -- запас вокруг коробки части тела: луч должен пройти не дальше (studs)
		WallTolerance = 1.0, -- запас на стену перед целью (у клиента и сервера чуть разная геометрия)
		RateJitter = 0.12, -- выстрелы могут прийти пачкой из-за сети: столько секунд «в долг»
		Range = 1000, -- дальность луча
	},

	-- Эффекты на клиентах
	Effects = {
		MaxHoles = 60, -- следов от пуль одновременно (старые исчезают первыми)
		HoleLifetime = 20,
		MaxCasings = 24, -- гильз на земле одновременно
		CasingLifetime = 2.6,
		TracerSpeed = 950, -- studs/с
		TracerLength = 5,
		RemoteRange = 700, -- чужие выстрелы дальше этого — без эффектов попаданий (только звук)
		DistantFrom = 140, -- с этого расстояния чужой выстрел звучит «издалека»
		ShotHearing = 900, -- дальше не слышно
		ThirdPersonRange = 250, -- дальше руки других игроков не пересчитываются (видно, но без ИК)
	},

	Weapons = {
		AK47 = {
			DisplayName = "AK-47",
			Class = "Автомат",
			ShotSound = "Shot",
			ShotVolume = 1,
			Rpm = 600, -- темп стрельбы (выстрелов в минуту)
			Modes = { "Auto", "Semi" },
			DefaultMode = "Auto",
			Magazine = 30,
			Reserve = 90, -- запас патронов при появлении
			EquipTime = 0.5, -- достать оружие при появлении
			SprintToFire = 0.2, -- после бега: столько секунд оружие поднимается, стрелять нельзя
			Range = 1000,

			-- Урон за попадание по зонам тела (этап 5) и спад с расстоянием: до Start — полный, к End — Min от него
			Damage = { Head = 92, Torso = 34, Arm = 28, Leg = 26 },
			Falloff = { Start = 70, End = 240, Min = 0.72 },

			-- Разброс (градусы, полный угол конуса от центра): база + движение + воздух + «раскачка» очередью
			Spread = {
				Hip = 2.6,
				Aim = 0.2,
				Move = 2.0, -- на скорости ходьбы; на бегу стрелять нельзя
				Air = 5.0,
				CrouchFactor = 0.7, -- в приседе разброс меньше
				PerShot = 0.35, -- каждый выстрел очереди раскачивает
				MaxBloom = 3.4,
				Recovery = 8.0, -- градусов в секунду возвращается к базе
				AimBloomFactor = 0.35, -- при прицеливании раскачка меньше
			},

			-- Отдача: ствол уходит вверх и немного вбок; часть отдачи камера возвращает сама после очереди
			Recoil = {
				Vertical = 0.95, -- градусов вверх за выстрел (первые выстрелы — сильнее, см. Pattern)
				Horizontal = 0.38, -- случайный разброс вбок (±)
				Drift = 0.12, -- очередь тянет вправо
				Pattern = { 1.35, 1.25, 1.15, 1.05, 1.0 }, -- множители первых выстрелов очереди
				AimFactor = 0.7, -- при прицеливании отдача меньше
				CrouchFactor = 0.85,
				KickTime = 0.06, -- за сколько камера доходит до отдачи выстрела
				ReturnFraction = 0.55, -- какую часть набранной отдачи камера возвращает сама
				ReturnSpeed = 14, -- градусов в секунду (возврат)
				-- оружие в руках (вид от первого лица): толчок назад, подброс вверх
				KickBack = 0.11,
				KickUp = 0.035,
				KickRotate = 3.2, -- градусов
			},

			Aim = {
				Time = 0.18, -- за сколько поднять к глазу (скорость ходьбы с прицелом — GameConfig.Movement)
				SensitivityFactor = 0.72, -- чувствительность обзора при прицеливании
			},
		},

		SMG = {
			DisplayName = "VX-9",
			Class = "Пистолет-пулемёт",
			ShotSound = "ShotSMG",
			ShotVolume = 1.1,
			Rpm = 820,
			Modes = { "Auto", "Semi" },
			DefaultMode = "Auto",
			Magazine = 32,
			Reserve = 128,
			EquipTime = 0.4,
			SprintToFire = 0.15,
			Range = 700,
			Damage = { Head = 58, Torso = 24, Arm = 20, Leg = 19 },
			Falloff = { Start = 25, End = 110, Min = 0.62 },
			Spread = {
				Hip = 2.0,
				Aim = 0.35,
				Move = 1.2,
				Air = 4.0,
				CrouchFactor = 0.75,
				PerShot = 0.22,
				MaxBloom = 2.6,
				Recovery = 9.0,
				AimBloomFactor = 0.4,
			},
			Recoil = {
				Vertical = 0.55,
				Horizontal = 0.35,
				Drift = 0.08,
				Pattern = { 1.2, 1.1, 1.0 },
				AimFactor = 0.7,
				CrouchFactor = 0.85,
				KickTime = 0.045,
				ReturnFraction = 0.6,
				ReturnSpeed = 16,
				KickBack = 0.06,
				KickUp = 0.025,
				KickRotate = 2.2,
			},
			Aim = { Time = 0.15, SensitivityFactor = 0.75 },
		},

		Shotgun = {
			DisplayName = "BR-12",
			Class = "Дробовик",
			ShotSound = "ShotShotgun",
			ShotVolume = 1.35,
			Pellets = 8, -- урон Damage — за каждую дробину: вблизи все 8 в корпус — больше 100
			Rpm = 150,
			Modes = { "Semi" },
			DefaultMode = "Semi",
			Magazine = 8,
			Reserve = 32,
			EquipTime = 0.55,
			SprintToFire = 0.22,
			Range = 160,
			Damage = { Head = 24, Torso = 17, Arm = 13, Leg = 12 },
			Falloff = { Start = 12, End = 45, Min = 0.25 },
			Spread = {
				Hip = 2.2,
				Aim = 1.0,
				Move = 1.0,
				Air = 3.0,
				CrouchFactor = 0.85,
				PerShot = 0.6,
				MaxBloom = 1.5,
				Recovery = 6.0,
				AimBloomFactor = 0.6,
				Pellet = 4.2, -- угол конуса дроби
			},
			Recoil = {
				Vertical = 3.2,
				Horizontal = 0.8,
				Drift = 0,
				Pattern = { 1 },
				AimFactor = 0.8,
				CrouchFactor = 0.85,
				KickTime = 0.06,
				ReturnFraction = 0.7,
				ReturnSpeed = 12,
				KickBack = 0.2,
				KickUp = 0.07,
				KickRotate = 8,
			},
			Aim = { Time = 0.2, SensitivityFactor = 0.75 },
		},

		Sniper = {
			DisplayName = "LR-7",
			Class = "Снайперская винтовка",
			ShotSound = "ShotSniper",
			ShotVolume = 1.4,
			BoltAction = true,
			Scope = true,
			Impulse = 2, -- сила толчка попадания (регдолл)
			Rpm = 48,
			Modes = { "Semi" },
			DefaultMode = "Semi",
			Magazine = 5,
			Reserve = 25,
			EquipTime = 0.6,
			SprintToFire = 0.3,
			Range = 1000,
			Damage = { Head = 250, Torso = 110, Arm = 80, Leg = 75 },
			Falloff = { Start = 400, End = 1000, Min = 0.9 },
			Spread = {
				Hip = 6.0,
				Aim = 0.0,
				Move = 4.0,
				Air = 8.0,
				CrouchFactor = 0.7,
				PerShot = 0,
				MaxBloom = 0,
				Recovery = 10,
				AimBloomFactor = 1,
			},
			Recoil = {
				Vertical = 4.5,
				Horizontal = 0.6,
				Drift = 0,
				Pattern = { 1 },
				AimFactor = 0.6,
				CrouchFactor = 0.85,
				KickTime = 0.07,
				ReturnFraction = 0.75,
				ReturnSpeed = 10,
				KickBack = 0.25,
				KickUp = 0.08,
				KickRotate = 9,
			},
			Aim = { Time = 0.3, SensitivityFactor = 0.32 },
		},

		Pistol = {
			DisplayName = "P-17",
			Class = "Пистолет",
			ShotSound = "ShotPistol",
			ShotVolume = 1,
			Rpm = 400,
			Modes = { "Semi" },
			DefaultMode = "Semi",
			Magazine = 12,
			Reserve = 48,
			EquipTime = 0.35,
			SprintToFire = 0.12,
			Range = 600,
			Damage = { Head = 70, Torso = 30, Arm = 24, Leg = 22 },
			Falloff = { Start = 30, End = 120, Min = 0.6 },
			Spread = {
				Hip = 1.8,
				Aim = 0.35,
				Move = 1.6,
				Air = 4.0,
				CrouchFactor = 0.75,
				PerShot = 0.6,
				MaxBloom = 3.0,
				Recovery = 10,
				AimBloomFactor = 0.4,
			},
			Recoil = {
				Vertical = 1.6,
				Horizontal = 0.45,
				Drift = 0.05,
				Pattern = { 1 },
				AimFactor = 0.75,
				CrouchFactor = 0.85,
				KickTime = 0.05,
				ReturnFraction = 0.75,
				ReturnSpeed = 18,
				KickBack = 0.07,
				KickUp = 0.05,
				KickRotate = 6,
			},
			Aim = { Time = 0.14, SensitivityFactor = 0.8 },
		},
	},
})
