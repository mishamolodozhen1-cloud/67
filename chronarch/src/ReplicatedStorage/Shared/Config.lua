-- Общие настройки игры «Стрела Судьбы»: звуки, баланс, цвета.
local Config = {}

Config.GameName = "Стрела Судьбы"
Config.StandName = "ХРОНАРХ"
Config.StandTitle = "Повелитель Времени"

-- Звуки: эффекты из Soundza, голос из ElevenLabs. Загружены в Roblox через Open Cloud.
Config.Sounds = {
	Hit = "rbxassetid://97014258099807",
	Swish = "rbxassetid://130745731701092",
	Finisher = "rbxassetid://76255895372118",
	Tick = "rbxassetid://92809251990078",
	TimeStop = "rbxassetid://117873320618530",
	Resume = "rbxassetid://96146490617409",
	Summon = "rbxassetid://85162080585965",
	Awaken = "rbxassetid://99368205209529",
	Voice = "rbxassetid://113320858384880",
}

Config.Barrage = {
	MaxDuration = 4,          -- сколько секунд можно держать барраж
	TickInterval = 0.09,      -- как часто проверяется попадание
	Damage = 2.5,             -- урон за одно попадание
	BoxSize = Vector3.new(7, 7, 8),
	BoxForward = 5.5,         -- насколько вынесен хитбокс вперёд от игрока
	Cooldown = 2.5,
	FinisherDamage = 18,
	FinisherKnockback = 85,
	FinisherDelay = 0.22,
}

Config.TimeStop = {
	Windup = 1.25,            -- совпадает с ударом «бум» в звуке остановки
	Duration = 5,
	Cooldown = 20,
}

Config.Colors = {
	Gold = Color3.fromRGB(214, 172, 62),
	DarkGold = Color3.fromRGB(142, 104, 34),
	Suit = Color3.fromRGB(26, 24, 32),
	Accent = Color3.fromRGB(90, 232, 255),
	Cloth = Color3.fromRGB(112, 18, 32),
}

-- Смещения стенда относительно HumanoidRootPart владельца.
Config.StandOffsets = {
	idle = CFrame.new(2.4, 1.6, 2.8),
	barrage = CFrame.new(0, 0.9, -3.4),
	finisher = CFrame.new(0, 0.9, -4.1),
	timestop = CFrame.new(0, 2.1, 1.3),
}

return Config
