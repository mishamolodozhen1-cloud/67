-- Sounds: звуки NIGHT SHIFT.
--   Loops — длинные фоновые петли, каждая отдельным аудиофайлом (дождь, ветер, город, гул ламп…).
--   List  — короткие звуки. Несколько звуков склеены в один файл («спрайт»), а здесь записано,
--           с какой по какую секунду звучит каждый (Sound.PlaybackRegion).
-- Источники: Soundza (soundza.com, реальные записи), голос диктора — ElevenLabs.
-- Сгенерированы ИИ: PAChime, Stinger, StoreMusic, Cart, Mop, MenuMusic.
local Sounds = {}

Sounds.Files = {
	Ambience = "rbxassetid://99536408963814",
	Sfx = "rbxassetid://131689605885313",
	Voice = "rbxassetid://95082023556735",
	Music = "rbxassetid://124959931909471",
	Sfx2 = "rbxassetid://99267307944697",
	Sfx3 = "rbxassetid://89980517795896", -- интерфейс, касса, фонарик
}

-- Короткие звуки: файл, начало, конец, зациклен ли, громкость
Sounds.List = {
	Fridge = { File = "Ambience", Start = 0.02, Stop = 15.98, Loop = true, Volume = 0.5 },
	Vent = { File = "Ambience", Start = 16.62, Stop = 29.68, Loop = true, Volume = 0.4 },
	Fluorescent = { File = "Ambience", Start = 30.32, Stop = 41.08, Loop = true, Volume = 0.2 },
	NightOutside = { File = "Ambience", Start = 41.72, Stop = 61.18, Loop = true, Volume = 0.5 },
	Drone = { File = "Ambience", Start = 61.82, Stop = 90.98, Loop = true, Volume = 0.6 },
	Heartbeat = { File = "Ambience", Start = 91.62, Stop = 92.286, Loop = true, Volume = 0.9 },
	Static = { File = "Ambience", Start = 92.926, Stop = 96.786, Loop = true, Volume = 0.45 },
	Scan = { File = "Sfx", Start = 0.02, Stop = 0.111, Loop = false, Volume = 0.55 },
	ScanError = { File = "Sfx", Start = 0.751, Stop = 1.021, Loop = false, Volume = 0.55 },
	Payment = { File = "Sfx", Start = 1.661, Stop = 3.943, Loop = false, Volume = 0.55 },
	DoorChime = { File = "Sfx", Start = 4.583, Stop = 6.043, Loop = false, Volume = 0.45 },
	AutoDoor = { File = "Sfx", Start = 6.683, Stop = 8.66, Loop = false, Volume = 0.6 },
	Knock = { File = "Sfx", Start = 9.3, Stop = 9.936, Loop = false, Volume = 1.0 },
	KnockHard = { File = "Sfx", Start = 10.576, Stop = 11.914, Loop = false, Volume = 1.0 },
	PowerDown = { File = "Sfx", Start = 12.554, Stop = 16.383, Loop = false, Volume = 0.9 },
	PowerUp = { File = "Sfx", Start = 17.023, Stop = 22.483, Loop = false, Volume = 0.7 },
	Flicker = { File = "Sfx", Start = 23.123, Stop = 28.725, Loop = false, Volume = 0.6 },
	CansFall = { File = "Sfx", Start = 29.365, Stop = 30.575, Loop = false, Volume = 0.9 },
	DoorSlam = { File = "Sfx", Start = 31.215, Stop = 32.52, Loop = false, Volume = 1.0 },
	FreezerDoor = { File = "Sfx", Start = 33.16, Stop = 34.623, Loop = false, Volume = 0.8 },
	DoorOpen = { File = "Sfx", Start = 35.263, Stop = 37.012, Loop = false, Volume = 0.7 },
	StepsFar = { File = "Sfx", Start = 37.652, Stop = 44.076, Loop = false, Volume = 0.6 },
	Steps = { File = "Sfx", Start = 44.716, Stop = 51.083, Loop = false, Volume = 0.8 },
	Stinger = { File = "Sfx", Start = 51.723, Stop = 56.193, Loop = false, Volume = 0.6 },
	BoxPick = { File = "Sfx", Start = 56.833, Stop = 57.72, Loop = false, Volume = 0.6 },
	BoxDrop = { File = "Sfx", Start = 58.36, Stop = 59.72, Loop = false, Volume = 0.75 },
	Phone = { File = "Sfx", Start = 60.36, Stop = 60.765, Loop = false, Volume = 0.7 },
	Cart = { File = "Sfx", Start = 61.405, Stop = 65.798, Loop = false, Volume = 0.7 },
	Mop = { File = "Sfx", Start = 66.438, Stop = 68.51, Loop = false, Volume = 0.7 },
	CameraSwitch = { File = "Sfx", Start = 69.15, Stop = 70.01, Loop = false, Volume = 0.55 },
	PAChime = { File = "Sfx", Start = 70.65, Stop = 73.21, Loop = false, Volume = 0.65 },
	Welcome = { File = "Voice", Start = 0.02, Stop = 7.27, Loop = false, Volume = 0.8 },
	CallRegister = { File = "Voice", Start = 8.11, Stop = 11.82, Loop = false, Volume = 0.8 },
	Discount = { File = "Voice", Start = 12.66, Stop = 19.32, Loop = false, Volume = 0.8 },
	NeverCloses = { File = "Voice", Start = 20.16, Stop = 27.59, Loop = false, Volume = 0.8 },
	ColdRoom = { File = "Voice", Start = 28.43, Stop = 32.97, Loop = false, Volume = 0.8 },
	RegisterZero = { File = "Voice", Start = 33.81, Stop = 36.45, Loop = false, Volume = 0.8 },
	DontTurn = { File = "Voice", Start = 37.29, Stop = 40.12, Loop = false, Volume = 0.8 },
	ShiftOver = { File = "Voice", Start = 40.96, Stop = 43.89, Loop = false, Volume = 0.8 },
	StoreMusic = { File = "Music", Start = 0.02, Stop = 74.026, Loop = true, Volume = 0.22 },
	CarArrive = { File = "Sfx2", Start = 0.02, Stop = 14.555, Loop = false, Volume = 0.9 },
	CarDoorOpen = { File = "Sfx2", Start = 15.155, Stop = 16.653, Loop = false, Volume = 0.8 },
	CarDoorClose = { File = "Sfx2", Start = 17.253, Stop = 17.748, Loop = false, Volume = 0.9 },
	FluorFlicker = { File = "Sfx2", Start = 18.348, Stop = 23.99, Loop = false, Volume = 0.7 },
	FluorOn = { File = "Sfx2", Start = 24.59, Stop = 33.59, Loop = false, Volume = 0.7 },
	ClockBeep = { File = "Sfx2", Start = 34.19, Stop = 34.433, Loop = false, Volume = 0.5 },
	TvGlitch = { File = "Sfx2", Start = 35.033, Stop = 37.633, Loop = false, Volume = 0.45 },
	DarkHit = { File = "Sfx2", Start = 38.233, Stop = 42.16, Loop = false, Volume = 0.8 },
	Riser = { File = "Sfx2", Start = 42.76, Stop = 51.539, Loop = false, Volume = 0.5 },
	StepTile1 = { File = "Sfx2", Start = 52.139, Stop = 52.459, Loop = false, Volume = 0.5 },
	StepTile2 = { File = "Sfx2", Start = 53.059, Stop = 53.379, Loop = false, Volume = 0.5 },
	StepTile3 = { File = "Sfx2", Start = 53.979, Stop = 54.299, Loop = false, Volume = 0.5 },
	StepTile4 = { File = "Sfx2", Start = 54.899, Stop = 55.219, Loop = false, Volume = 0.5 },
	StepTile5 = { File = "Sfx2", Start = 55.819, Stop = 56.139, Loop = false, Volume = 0.5 },
	StepWet1 = { File = "Sfx2", Start = 56.739, Stop = 57.059, Loop = false, Volume = 0.5 },
	StepWet2 = { File = "Sfx2", Start = 57.659, Stop = 57.979, Loop = false, Volume = 0.5 },
	StepWet3 = { File = "Sfx2", Start = 58.579, Stop = 58.899, Loop = false, Volume = 0.5 },
	StepWet4 = { File = "Sfx2", Start = 59.499, Stop = 59.819, Loop = false, Volume = 0.5 },
	StepWet5 = { File = "Sfx2", Start = 60.419, Stop = 60.739, Loop = false, Volume = 0.5 },
	-- интерфейс
	UiClick = { File = "Sfx3", Start = 0.02, Stop = 0.09, Loop = false, Volume = 0.35 },
	UiHover = { File = "Sfx3", Start = 0.69, Stop = 0.737, Loop = false, Volume = 0.18 },
	UiOpen = { File = "Sfx3", Start = 1.337, Stop = 1.647, Loop = false, Volume = 0.3 },
	-- касса: ящик с чеком, ящик закрылся, карта к терминалу, сигнал «оплачено», сдача монетами
	CashDrawer = { File = "Sfx3", Start = 2.247, Stop = 4.513, Loop = false, Volume = 0.6 },
	CashClose = { File = "Sfx3", Start = 5.113, Stop = 6.998, Loop = false, Volume = 0.55 },
	CardTap = { File = "Sfx3", Start = 8.342, Stop = 8.452, Loop = false, Volume = 0.5 },
	CardBeep = { File = "Sfx3", Start = 9.052, Stop = 9.213, Loop = false, Volume = 0.35 },
	Coins = { File = "Sfx3", Start = 9.813, Stop = 10.17, Loop = false, Volume = 0.5 },
	-- щелчок кнопки фонарика
	FlashClick = { File = "Sfx3", Start = 7.598, Stop = 7.742, Loop = false, Volume = 0.6 },
}

-- Фоновые петли: отдельный файл, громкость
Sounds.Loops = {
	RainOutside = { Id = "rbxassetid://72757943747907", Volume = 0.7 },
	Wind = { Id = "rbxassetid://110706365888451", Volume = 0.35 },
	Traffic = { Id = "rbxassetid://74825841820970", Volume = 0.3 },
	StoreRoom = { Id = "rbxassetid://96033090026477", Volume = 0.35 },
	FluorHum = { Id = "rbxassetid://117053962793792", Volume = 0.35 },
	SignHum = { Id = "rbxassetid://121606027666716", Volume = 0.35 },
	Computer = { Id = "rbxassetid://128092595250800", Volume = 0.3 },
	CctvStatic = { Id = "rbxassetid://107209527430817", Volume = 0.35 },
	TensionDrone = { Id = "rbxassetid://125613290392026", Volume = 0.6 },
	LowRoom = { Id = "rbxassetid://105916043267847", Volume = 0.5 },
	-- музыка главного меню (петля)
	MenuMusic = { Id = "rbxassetid://111386435897248", Volume = 0.45 },
}

-- Шаги по типу пола
Sounds.Steps = {
	Tile = { "StepTile1", "StepTile2", "StepTile3", "StepTile4", "StepTile5" },
	Wet = { "StepWet1", "StepWet2", "StepWet3", "StepWet4", "StepWet5" },
}

-- Реплики диктора (громкая связь) и субтитры к ним
Sounds.Subtitles = {
	Welcome = "Уважаемые покупатели! Добро пожаловать в магазин «Март двадцать четыре». Мы работаем для вас круглосуточно.",
	CallRegister = "Сотрудника торгового зала просим подойти к кассе номер два.",
	Discount = "С полуночи до шести утра в нашем магазине действует ночная скидка.",
	NeverCloses = "Магазин закрывается. Магазин… никогда не закрывается.",
	ColdRoom = "Сотрудника ночной смены просят пройти в холодильную камеру. Вас там ждут.",
	RegisterZero = "Покупатель ожидает на кассе номер ноль.",
	DontTurn = "Не оборачивайтесь. Приятных покупок.",
	ShiftOver = "Смена окончена. Спасибо за вашу работу.",
}

function Sounds.Get(name)
	return Sounds.List[name]
end

return Sounds
