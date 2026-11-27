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
	-- стойка и бег своего персонажа: { Stance = "Stand" | "Crouch", Sprint = true/false }
	-- (сервер ставит скорость и атрибуты персонажа, которые видят все клиенты)
	MoveState = {
		Kind = "Event",
		Direction = "ToServer",
		Args = {
			Validate.Shape({
				Stance = Validate.OneOf({ "Stand", "Crouch" }),
				Sprint = Validate.Boolean(),
			}),
		},
		Rate = { Burst = 8, PerSecond = 6 },
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
