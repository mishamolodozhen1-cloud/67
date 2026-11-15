-- Sounds: звуковые «спрайты». Несколько звуков склеены в один аудиофайл, а здесь записано,
-- с какой по какую секунду звучит каждый (Sound.PlaybackRegion). Так нужно всего 4 аудиоассета.
-- Источники: Soundza (soundza.com), диктор — ElevenLabs. Сгенерированы ИИ: PAChime, Stinger, StoreMusic, Cart, Mop.
local Sounds = {}

Sounds.Files = {
	Ambience = "rbxassetid://99536408963814",
	Sfx = "rbxassetid://131689605885313",
	Voice = "rbxassetid://95082023556735",
	Music = "rbxassetid://124959931909471",
}

-- Имя звука -> файл, начало, конец, зациклен ли, громкость, группа громкости
Sounds.List = {
	Fridge = { File = "Ambience", Start = 0.02, Stop = 15.98, Loop = true, Volume = 0.55 },
	Vent = { File = "Ambience", Start = 16.62, Stop = 29.68, Loop = true, Volume = 0.45 },
	Fluorescent = { File = "Ambience", Start = 30.32, Stop = 41.08, Loop = true, Volume = 0.25 },
	NightOutside = { File = "Ambience", Start = 41.72, Stop = 61.18, Loop = true, Volume = 0.6 },
	Drone = { File = "Ambience", Start = 61.82, Stop = 90.98, Loop = true, Volume = 0.7 },
	Heartbeat = { File = "Ambience", Start = 91.62, Stop = 92.286, Loop = true, Volume = 0.9 },
	Static = { File = "Ambience", Start = 92.926, Stop = 96.786, Loop = true, Volume = 0.5 },
	Scan = { File = "Sfx", Start = 0.02, Stop = 0.111, Loop = false, Volume = 0.6 },
	ScanError = { File = "Sfx", Start = 0.751, Stop = 1.021, Loop = false, Volume = 0.6 },
	Payment = { File = "Sfx", Start = 1.661, Stop = 3.943, Loop = false, Volume = 0.6 },
	DoorChime = { File = "Sfx", Start = 4.583, Stop = 6.043, Loop = false, Volume = 0.5 },
	AutoDoor = { File = "Sfx", Start = 6.683, Stop = 8.66, Loop = false, Volume = 0.6 },
	Knock = { File = "Sfx", Start = 9.3, Stop = 9.936, Loop = false, Volume = 1.0 },
	KnockHard = { File = "Sfx", Start = 10.576, Stop = 11.914, Loop = false, Volume = 1.0 },
	PowerDown = { File = "Sfx", Start = 12.554, Stop = 16.383, Loop = false, Volume = 0.9 },
	PowerUp = { File = "Sfx", Start = 17.023, Stop = 22.483, Loop = false, Volume = 0.8 },
	Flicker = { File = "Sfx", Start = 23.123, Stop = 28.725, Loop = false, Volume = 0.7 },
	CansFall = { File = "Sfx", Start = 29.365, Stop = 30.575, Loop = false, Volume = 0.9 },
	DoorSlam = { File = "Sfx", Start = 31.215, Stop = 32.52, Loop = false, Volume = 1.0 },
	FreezerDoor = { File = "Sfx", Start = 33.16, Stop = 34.623, Loop = false, Volume = 0.8 },
	DoorOpen = { File = "Sfx", Start = 35.263, Stop = 37.012, Loop = false, Volume = 0.7 },
	StepsFar = { File = "Sfx", Start = 37.652, Stop = 44.076, Loop = false, Volume = 0.6 },
	Steps = { File = "Sfx", Start = 44.716, Stop = 51.083, Loop = false, Volume = 0.8 },
	Stinger = { File = "Sfx", Start = 51.723, Stop = 56.193, Loop = false, Volume = 0.8 },
	BoxPick = { File = "Sfx", Start = 56.833, Stop = 57.72, Loop = false, Volume = 0.7 },
	BoxDrop = { File = "Sfx", Start = 58.36, Stop = 59.72, Loop = false, Volume = 0.8 },
	Phone = { File = "Sfx", Start = 60.36, Stop = 60.765, Loop = false, Volume = 0.7 },
	Cart = { File = "Sfx", Start = 61.405, Stop = 65.798, Loop = false, Volume = 0.7 },
	Mop = { File = "Sfx", Start = 66.438, Stop = 68.51, Loop = false, Volume = 0.7 },
	CameraSwitch = { File = "Sfx", Start = 69.15, Stop = 70.01, Loop = false, Volume = 0.6 },
	PAChime = { File = "Sfx", Start = 70.65, Stop = 73.21, Loop = false, Volume = 0.7 },
	Welcome = { File = "Voice", Start = 0.02, Stop = 7.27, Loop = false, Volume = 0.8 },
	CallRegister = { File = "Voice", Start = 8.11, Stop = 11.82, Loop = false, Volume = 0.8 },
	Discount = { File = "Voice", Start = 12.66, Stop = 19.32, Loop = false, Volume = 0.8 },
	NeverCloses = { File = "Voice", Start = 20.16, Stop = 27.59, Loop = false, Volume = 0.8 },
	ColdRoom = { File = "Voice", Start = 28.43, Stop = 32.97, Loop = false, Volume = 0.8 },
	RegisterZero = { File = "Voice", Start = 33.81, Stop = 36.45, Loop = false, Volume = 0.8 },
	DontTurn = { File = "Voice", Start = 37.29, Stop = 40.12, Loop = false, Volume = 0.8 },
	ShiftOver = { File = "Voice", Start = 40.96, Stop = 43.89, Loop = false, Volume = 0.8 },
	StoreMusic = { File = "Music", Start = 0.02, Stop = 74.026, Loop = true, Volume = 0.32 },
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
