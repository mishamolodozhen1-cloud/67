-- RemoteDefinitions: единственный список сетевых событий DUMMY COMBAT.
-- Сервер (NetService) создаёт по нему объекты в ReplicatedStorage.Remotes, клиент (ClientNet) берёт их
-- оттуда. Событие, которого здесь нет, нельзя ни отправить, ни принять, а лишние объекты в папке
-- Remotes сервер удаляет при запуске.
--
-- Поля:
--   Kind       "Event" (надёжная доставка) или "UnreliableEvent" (частые эффекты, потеря не страшна)
--   Direction  "ToServer" (клиент → сервер), "ToClient" (сервер → клиент) или "Both"
--   Args       для ToServer/Both: валидаторы аргументов по порядку (Shared/Validate); лишние аргументы
--              и неверные значения отбрасываются, игроку засчитывается нарушение
--   Rate       для ToServer/Both: { Burst = сколько можно сразу, PerSecond = сколько восполняется в секунду }
--
-- Новые события добавляют те этапы, которым они нужны (оружие, урон, матчи…), — вместе со схемой
-- аргументов и лимитом.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Validate = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Validate"))
local GameConfig = require(script.Parent:WaitForChild("GameConfig"))

local errors = GameConfig.ClientErrors

local definitions = {
	-- клиент загрузился и готов получать данные (один раз за сессию)
	ClientReady = {
		Kind = "Event",
		Direction = "ToServer",
		Args = {},
		Rate = { Burst = 2, PerSecond = 0.05 },
	},
	-- сервер в ответ сообщает о себе: игра, версия, время сервера
	ServerInfo = {
		Kind = "Event",
		Direction = "ToClient",
	},
	-- ошибка скрипта на клиенте: текст, стек вызовов, вид ("Error" — ошибка скрипта, "Log" — запись журнала)
	ClientError = {
		Kind = "Event",
		Direction = "ToServer",
		Args = {
			Validate.String({ Max = errors.MaxMessage, Min = 1 }),
			Validate.String({ Max = errors.MaxTrace }),
			Validate.OneOf({ "Error", "Log" }),
		},
		Rate = { Burst = 5, PerSecond = 0.25 },
	},
	-- стойка, бег и прицел своего персонажа: { Stance = "Stand" | "Crouch", Sprint = true/false, Aim = true/false }
	-- (сервер ставит скорость и атрибуты персонажа, которые видят все клиенты)
	MoveState = {
		Kind = "Event",
		Direction = "ToServer",
		Args = {
			Validate.Shape({
				Stance = Validate.OneOf({ "Stand", "Crouch" }),
				Sprint = Validate.Boolean(),
				Aim = Validate.Optional(Validate.Boolean()),
			}),
		},
		Rate = { Burst = 10, PerSecond = 8 },
	},
	-- выстрел: номер выстрела, точка (камера), направление (единичный вектор), время выстрела по часам сервера
	-- (workspace:GetServerTimeNow) и, если клиент попал в персонажа, — часть тела и точка попадания.
	-- Сервер проверяет всё сам (WeaponSystem): темп, патроны, точку выстрела, попадание с учётом задержки
	Fire = {
		Kind = "Event",
		Direction = "ToServer",
		Args = {
			Validate.Number({ Min = 0, Max = 2 ^ 31, Integer = true }),
			Validate.Vector3({ MaxMagnitude = 100000 }),
			Validate.Vector3({ MaxMagnitude = 1.01 }),
			Validate.Number({ Min = 0, Max = 1e11 }),
			Validate.Optional(Validate.Instance("BasePart")),
			Validate.Optional(Validate.Vector3({ MaxMagnitude = 100000 })),
		},
		-- 600 выстрелов в минуту = 10 в секунду; запас — на неровную сеть
		Rate = { Burst = 16, PerSecond = 14 },
	},
	-- перезарядить (сервер решает, можно ли)
	Reload = {
		Kind = "Event",
		Direction = "ToServer",
		Args = {},
		Rate = { Burst = 3, PerSecond = 1 },
	},
	-- режим огня
	FireMode = {
		Kind = "Event",
		Direction = "ToServer",
		Args = { Validate.OneOf({ "Auto", "Semi" }) },
		Rate = { Burst = 4, PerSecond = 2 },
	},
	-- наклон взгляда вверх-вниз (градусы): по нему все видят, куда персонаж целится (корпус и оружие)
	AimPitch = {
		Kind = "UnreliableEvent",
		Direction = "ToServer",
		Args = { Validate.Number({ Min = -90, Max = 90 }) },
		Rate = { Burst = 20, PerSecond = 16 },
	},
	-- сервер → владелец: состояние оружия { Weapon, Ammo, Reserve, Mode, Reloading, ReloadKind, ReloadEnd, Reason }
	WeaponState = {
		Kind = "Event",
		Direction = "ToClient",
	},
	-- сервер → остальные: чужой выстрел (стрелок, откуда, куда, нормаль поверхности, материал, что задето) — эффекты
	ShotFired = {
		Kind = "UnreliableEvent",
		Direction = "ToClient",
	},
	-- сервер → стрелок: попадание подтверждено { Part, Headshot, Position, Damage, Kill }
	HitConfirmed = {
		Kind = "Event",
		Direction = "ToClient",
	},
	-- сервер → раненый: { Amount, From (откуда стреляли), Health }
	Damaged = {
		Kind = "Event",
		Direction = "ToClient",
	},
	-- сервер → все: лента убийств { Killer, KillerId, Victim, VictimId, Weapon, Headshot }
	KillFeed = {
		Kind = "Event",
		Direction = "ToClient",
	},
	-- игрок нажал PLAY: войти в идущий матч или встать в очередь на следующий
	Play = {
		Kind = "Event",
		Direction = "ToServer",
		Args = {},
		Rate = { Burst = 3, PerSecond = 0.5 },
	},
	-- выйти из матча в лобби
	LeaveMatch = {
		Kind = "Event",
		Direction = "ToServer",
		Args = {},
		Rate = { Burst = 3, PerSecond = 0.5 },
	},
	-- голос за вариант карты и режима (номер)
	Vote = {
		Kind = "Event",
		Direction = "ToServer",
		Args = { Validate.Number({ Min = 1, Max = 5, Integer = true }) },
		Rate = { Burst = 4, PerSecond = 1 },
	},
	-- сервер → клиенты: события матча { Type = "Countdown" | "Start" | "End" | "Strike" | "GunLevel", ... }
	MatchEvent = {
		Kind = "Event",
		Direction = "ToClient",
	},
	-- профиль: сервер → владелец (уровень, опыт, монеты, купленное, снаряжение, настройки)
	Profile = {
		Kind = "Event",
		Direction = "ToClient",
	},
	-- награда за убийство / помощь { Xp, Coins, Reason, LevelUps }
	Reward = {
		Kind = "Event",
		Direction = "ToClient",
	},
	-- награды за матч { Lines, Xp, Coins, LevelUps, Won, Rank }
	Rewards = {
		Kind = "Event",
		Direction = "ToClient",
	},
	-- ответ магазина { Ok, Reason, Category, Id }
	ShopResult = {
		Kind = "Event",
		Direction = "ToClient",
	},
	-- купить: категория и предмет
	Buy = {
		Kind = "Event",
		Direction = "ToServer",
		Args = { Validate.OneOf({ "Weapon", "Skin" }), Validate.String({ Max = 32, Min = 1 }) },
		Rate = { Burst = 4, PerSecond = 1 },
	},
	-- выбрать в снаряжение: слот и предмет
	EquipItem = {
		Kind = "Event",
		Direction = "ToServer",
		Args = { Validate.OneOf({ "Primary", "Skin" }), Validate.String({ Max = 32, Min = 1 }) },
		Rate = { Burst = 6, PerSecond = 2 },
	},
	-- настройки (сохраняются в профиль)
	SaveSettings = {
		Kind = "Event",
		Direction = "ToServer",
		Args = {
			Validate.Shape({
				Sensitivity = Validate.Optional(Validate.Number({ Min = 0.1, Max = 4 })),
				AimSensitivity = Validate.Optional(Validate.Number({ Min = 0.1, Max = 2 })),
				Fov = Validate.Optional(Validate.Number({ Min = 60, Max = 100 })),
				Master = Validate.Optional(Validate.Number({ Min = 0, Max = 1 })),
				Music = Validate.Optional(Validate.Number({ Min = 0, Max = 1 })),
				Sfx = Validate.Optional(Validate.Number({ Min = 0, Max = 1 })),
				Crosshair = Validate.Optional(Validate.Number({ Min = 0, Max = 1 })),
			}),
		},
		Rate = { Burst = 3, PerSecond = 0.5 },
	},
	-- клиент просит профиль заново (например, интерфейс открылся раньше, чем пришли данные)
	RequestProfile = {
		Kind = "Event",
		Direction = "ToServer",
		Args = {},
		Rate = { Burst = 2, PerSecond = 0.2 },
	},
	-- сервер → участник убийства: { Role = "Killer" | "Assist" | "Victim", Name, Weapon, Headshot, Respawn, From }
	Eliminated = {
		Kind = "Event",
		Direction = "ToClient",
	},
	-- стенд проверки (только в Roblox Studio; в опубликованной игре сервер эти команды не принимает):
	-- команда и, для взрыва, точка
	DevCommand = {
		Kind = "Event",
		Direction = "ToServer",
		Args = {
			Validate.OneOf({ "Knockdown", "KillHead", "KillLegs", "Explode", "SpawnDummies", "ClearDummies", "Stats" }),
			Validate.Optional(Validate.Vector3({ MaxMagnitude = 100000 })),
		},
		Rate = { Burst = 6, PerSecond = 3 },
	},
}

for _, def in pairs(definitions) do
	table.freeze(def)
	if def.Rate then
		table.freeze(def.Rate)
	end
	if def.Args then
		table.freeze(def.Args)
	end
end

return table.freeze(definitions)
