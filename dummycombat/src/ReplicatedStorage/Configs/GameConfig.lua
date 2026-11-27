-- GameConfig: общие настройки DUMMY COMBAT. Их читают и сервер, и клиент.
-- Таблица заморожена: во время игры её не изменить (ни случайно, ни эксплойтом на клиенте —
-- на сервере у клиента всё равно своей копии нет). Менять значения — только здесь.
-- Настройки отдельных систем (оружие, карты, режимы) будут лежать рядом, в своих модулях Configs.
local function deepFreeze(t)
	for _, v in pairs(t) do
		if type(v) == "table" and not table.isfrozen(v) then
			deepFreeze(v)
		end
	end
	return table.freeze(t)
end

return deepFreeze({
	GameName = "DUMMY COMBAT",

	-- Журнал (Shared/Logger): уровни Debug < Info < Warn < Error
	Logging = {
		ServerLevel = "Info", -- опубликованная игра, сервер
		ClientLevel = "Warn", -- опубликованная игра, клиент (в Output игрока — только важное)
		StudioLevel = "Debug", -- Roblox Studio: подробно
		HistorySize = 200, -- сколько последних записей держать в памяти
		DuplicateWindow = 10, -- одинаковое сообщение чаще этого (секунды) не печатается, а считается
	},

	-- Ошибки на клиентах (клиент сообщает, ErrorService собирает)
	ClientErrors = {
		MaxMessage = 400, -- байт в тексте ошибки
		MaxTrace = 1200, -- байт в стеке вызовов
		MaxPerSession = 25, -- больше этого от одного клиента за сессию не принимаем (дальше — шум)
		History = 100, -- сколько последних ошибок (сервера и клиентов) держит ErrorService
	},

	-- Персонаж (Systems/CharacterSystem): манекен, появление и возрождение
	Character = {
		RespawnDelay = 3, -- через сколько секунд после смерти появиться снова (бой и смерть — этап 5)
		ReadySpawnTimeout = 15, -- если клиент не сообщил о готовности, всё равно дать персонажа
		BodyColor = Color3.fromRGB(201, 170, 98), -- цвет запасного (блочного) манекена, если модель не загрузилась
	},

	-- Передвижение (Systems/MovementSystem, Controllers/CharacterController): studs/с, studs
	Movement = {
		WalkSpeed = 12,
		SprintSpeed = 19,
		CrouchSpeed = 6.5,
		AimSpeedFactor = 0.62, -- с оружием у глаза (прицел) — медленнее: шаг ×0.62, в приседе тоже
		JumpHeight = 4.6,
		JumpCooldown = 0.3, -- пауза между прыжками (против «кроличьих» прыжков)
		StanceTime = 0.18, -- за сколько персонаж приседает / встаёт (с)
		SprintForwardDot = 0.6, -- бег — только если движение в пределах ~53° от взгляда
		StandClearance = 0.15, -- запас над головой, чтобы встать из приседа
	},

	-- Камера от первого лица (Controllers/CameraController)
	Camera = {
		FieldOfView = 72,
		SprintFieldOfView = 78,
		EyeHeight = 0.2, -- над стандартной точкой камеры Roblox (HumanoidRootPart + 2): на уровне глаз манекена
		EyeForward = 0.3, -- камера чуть впереди центра головы: видно свои ноги, не видно шею изнутри
		HeadBob = true,
		BobVertical = 0.07, -- покачивание при ходьбе (studs)
		BobSide = 0.045,
		SprintBobScale = 1.6,
		CrouchBobScale = 0.6,
		LandDip = 0.35, -- просадка камеры при приземлении с высоты (studs, максимум)
		DeathCameraDistance = 14, -- после смерти камера от третьего лица на таком расстоянии от тела
	},

	-- Сеть (Services/NetService, Controllers/ClientNet)
	Net = {
		RemotesFolder = "Remotes", -- ReplicatedStorage.Remotes
		ReadyTimeout = 30, -- сколько клиент ждёт, пока сервер подготовит remotes (с)
		ViolationWindow = 60, -- окно подсчёта нарушений (с)
		ViolationLimit = 30, -- нарушений за окно: игрока отключают с сервера
		KickOnViolations = true,
		-- клиент шлёт чуть реже, чем разрешает сервер: честный клиент никогда не упирается в лимит
		ClientRateFactor = 0.8,
	},
})
