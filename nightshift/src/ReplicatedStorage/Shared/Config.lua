-- Config: все настройки NIGHT SHIFT в одном месте.
-- Хотите длиннее смену, больше покупателей или другой порог хорошей концовки — меняйте числа здесь.
local Config = {}

-- Время смены ---------------------------------------------------------------
Config.SecondsPerHour = 160 -- реальных секунд в одном игровом часе (вся смена 00:00–06:00 ≈ 16 минут)
Config.ShiftHours = 6 -- смена длится с 00:00 до 06:00
Config.LobbyAutoStart = 90 -- через столько секунд смена начнётся сама, если никто не отметился на табельных часах
Config.StartCountdown = 3 -- обратный отсчёт перед началом смены
Config.EndingSeconds = 40 -- сколько длится финал, потом магазин сбрасывается и начинается новая смена

-- Цель смены ----------------------------------------------------------------
Config.GoodEndingPercent = 70 -- столько процентов заданий нужно выполнить для хорошей концовки

-- Игрок ---------------------------------------------------------------------
Config.WalkSpeed = 12
Config.SprintSpeed = 19
Config.StaminaSeconds = 6 -- сколько секунд можно бежать без отдыха
Config.FlashlightBatterySeconds = 300 -- заряд фонарика в секундах работы

-- Покупатели ----------------------------------------------------------------
Config.MaxCustomers = 5 -- одновременно в магазине
Config.CustomerWalkSpeed = 8
Config.CustomerPatience = 110 -- столько секунд покупатель ждёт на кассе, потом уходит
-- секунд между приходом покупателей в каждый час смены; после 04:00 обычные покупатели не приходят
Config.CustomerInterval = { [0] = 24, [1] = 32, [2] = 40, [3] = 60 }
Config.ScanErrorChance = 0.12 -- (старые кассы с кассиром, не используется)

-- Охрана ---------------------------------------------------------------------
Config.KioskHelpChance = 0.35 -- шанс, что касса самообслуживания позовёт сотрудника во время покупки
Config.CardDeclineChance = 0.1 -- шанс, что карта не пройдёт и тоже понадобится сотрудник
Config.HelpPatience = 55 -- столько секунд покупатель ждёт сотрудника у кассы, потом уходит
Config.ThiefChance = { [0] = 0.08, [1] = 0.16, [2] = 0.2, [3] = 0.22 } -- доля воров среди покупателей по часам
Config.PickupChance = { [0] = 0.3, [1] = 0.28, [2] = 0.25, [3] = 0.2 } -- доля тех, кто пришёл за заказом
Config.PickupPatience = 100 -- столько секунд покупатель ждёт заказ у стойки выдачи
Config.ThiefEscapeZ = 74 -- вор, убежавший дальше этой линии парковки, скрылся
Config.FalseAlarmChance = 0.05 -- ворота иногда пищат на честного покупателя (забыли снять метку)
Config.PatrolPoints = 6

-- Пять ночей ------------------------------------------------------------------
-- Первая ночь — обычная работа. С каждой следующей ночью Покупатель приходит раньше,
-- света меньше, а странностей больше. Хорошая концовка открывает следующую ночь,
-- плохая — ночь придётся повторить. Часы ниже — игровые часы смены (0 = 00:00).
--   Apparition — с этого часа Покупатель является «видениями»
--   Stalk      — с этого часа он в магазине и переставляется ближе, пока на него не смотрят
--   Hunt       — с этого часа охотится (подкрадывается за спину)
--   DarkHunt   — после этого часа охотится и тогда, когда нет света
--   Pace       — во сколько раз быстрее он переставляется
--   BrokenLamps — сколько ламп мигает всю ночь; Dark — насколько темнее и бесцветнее картинка (0..1)
--   CustomersUntil — до какого часа приходят обычные покупатели
--   JumpScare  — показывать лицо Покупателя на весь экран, когда он поймал
Config.NightCount = 5
Config.Nights = {
	[1] = { Pace = 1, BrokenLamps = 0, Dark = 0, CustomersUntil = 4, JumpScare = false },
	[2] = { Apparition = 3, Pace = 1, BrokenLamps = 3, Dark = 0.12, CustomersUntil = 4, JumpScare = false },
	[3] = { Apparition = 2, Stalk = 4, Hunt = 5, DarkHunt = 4, Pace = 1, BrokenLamps = 7, Dark = 0.25, CustomersUntil = 4, JumpScare = true },
	[4] = { Apparition = 1, Stalk = 3, Hunt = 5, DarkHunt = 3, Pace = 1.25, BrokenLamps = 12, Dark = 0.4, CustomersUntil = 3, JumpScare = true },
	[5] = { Apparition = 1, Stalk = 2, Hunt = 4, DarkHunt = 2, Pace = 1.5, BrokenLamps = 18, Dark = 0.55, CustomersUntil = 3, JumpScare = true },
}

function Config.Night(n)
	return Config.Nights[math.clamp(math.floor(tonumber(n) or 1), 1, Config.NightCount)]
end

-- Монстр «Покупатель» -------------------------------------------------------
Config.CaughtPenaltyMinutes = 10 -- на столько игровых минут сдвигаются часы, если Покупатель поймал игрока
Config.CatchDistance = 4.5

-- Зарплата за смену (сохраняется в профиле) ---------------------------------
Config.SalaryBase = 2400
Config.SalaryPerPercent = 30

-- Картинки (загружены через Open Cloud) -------------------------------------
Config.Images = {
	-- старые ряды товаров (остались для торцов витрин и ларей)
	Grocery = "rbxassetid://83836111641998",
	Drinks = "rbxassetid://110507854021190",
	Snacks = "rbxassetid://118531572248218",
	Cans = "rbxassetid://87194565857360",
	Chilled = "rbxassetid://95680666274277",
	Household = "rbxassetid://84149092547214",
	Bread = "rbxassetid://87998717470651",
	ProduceTop = "rbxassetid://77506074059788",
	FrozenTop = "rbxassetid://128979819244355",
	CctvNoise = "rbxassetid://125782225307871",
	-- текстуры поверхностей (набор NIGHT_SHIFT_MART24_TEXTURES)
	FloorTile = "rbxassetid://74296570713927",
	PaintedWall = "rbxassetid://84891728643042",
	CeilingPanels = "rbxassetid://90690072446047",
	ConcreteWall = "rbxassetid://127833902419080",
	BrushedMetal = "rbxassetid://123908805648197",
	StainlessSteel = "rbxassetid://96392735117413",
	DarkPlastic = "rbxassetid://87456451994167",
	RubberMat = "rbxassetid://101405801984514",
	Cardboard = "rbxassetid://137540960037592",
	WoodCounter = "rbxassetid://109926347152153",
	-- этикетки товаров
	LabelCanned = "rbxassetid://91283338775160",
	LabelCereal = "rbxassetid://122876531882957",
	LabelChips = "rbxassetid://86830321046304",
	LabelCoffee = "rbxassetid://136906214330237",
	LabelFrozen = "rbxassetid://80887092072390",
	LabelMilk = "rbxassetid://139729338565115",
	LabelSoda = "rbxassetid://77235555671982",
	LabelWater = "rbxassetid://92889266951620",
	LabelHousehold = "rbxassetid://116293978072091",
	-- эффекты и интерфейс
	RainStreak = "rbxassetid://73426808753707",
	IconFlashlight = "rbxassetid://74745876125161",
	IconRun = "rbxassetid://127992880148136",
	PaperNote = "rbxassetid://96018777830216",
	Vignette = "rbxassetid://75529053513298",
	Scanlines = "rbxassetid://126973411646885",
}

-- Вступительная кат-сцена ----------------------------------------------------
Config.IntroSeconds = 166 -- длина кат-сцены перед началом смены (v12: поездка, реплики героя, двери с датчиком)
-- v15 (в работе): командная кат-сцена для 2–4 игроков (TeamCinematic). Пока выключена: клиент её ещё не
-- запускает (init.client.lua не подключён), сцена не проверена. Включать после проверки.
Config.TeamIntro = false
Config.IntroAlways = true -- показывать каждую смену (её можно пропустить кнопкой)

-- Камеры видеонаблюдения: порядок на мониторе охраны
Config.CameraCount = 9

return Config
