-- TeamLines (v15): командная вступительная кат-сцена для 2–4 игроков — роли, реплики и расписание.
--
-- Роли раздаются по порядку входа на сервер: 1 — водитель, 2 — пассажир спереди, 3 — сзади слева
-- (за водителем), 4 — сзади справа. У каждой роли свой голос (звуки «<голос>_<ключ>» в Sounds.List,
-- озвучка — VoiceLines/Voice4; тексты и подача — TEAM в tools/voice_lines.py).
--
-- Сцена держится на «репликах-метках» (Cue): какая метка звучит, одинаково для любого состава, а кто её
-- говорит и какими словами — зависит от числа игроков (Scripts[2|3|4]). Расписание считается один раз
-- и одинаково у сервера и у всех клиентов: реплика начинается не раньше, чем закончилась предыдущая
-- (плюс пауза), поэтому реплики не накладываются, а действия сцены привязаны к началу нужной реплики.
local TeamLines = {}

TeamLines.Roles = { "Driver", "Passenger", "BackLeft", "BackRight" }
TeamLines.Voice = { Driver = "TD", Passenger = "TP", BackLeft = "TL", BackRight = "TR" }
TeamLines.RoleOfVoice = { TD = "Driver", TP = "Passenger", TL = "BackLeft", TR = "BackRight" }
TeamLines.RoleTitle = { Driver = "водитель", Passenger = "пассажир", BackLeft = "сзади слева", BackRight = "сзади справа" }

-- Метки по порядку. Gap — пауза перед репликой (после конца предыдущей); At — не раньше этого момента
-- сцены. Laugh — не реплика, а общий смешок (звук), Len — его длина.
TeamLines.Cues = {
	-- 1. ПОЕЗДКА
	{ Cue = "Ready", Scene = "Ride", At = 4.2 },
	{ Cue = "Calm", Gap = 0.35 },
	{ Cue = "Why", Gap = 0.55 },
	{ Cue = "Popular", Gap = 0.45 },
	{ Cue = "Laugh", Gap = 0.1, Laugh = "Chuckle", Len = 1.45 },
	{ Cue = "Relax", Gap = 0.25 },
	{ Cue = "Know", Gap = 1.7 },
	{ Cue = "Hope", Gap = 0.45 },
	-- 2. СТРАННОСТИ (радио теряет волну, силуэт у дороги)
	{ Cue = "Radio", Scene = "Strange", Gap = 2.4 },
	{ Cue = "Off", Gap = 0.3 },
	{ Cue = "Saw", Gap = 4.6 },
	{ Cue = "What", Gap = 0.3 },
	{ Cue = "Nothing", Gap = 1.9 },
	-- 3. ПРИБЫТИЕ
	{ Cue = "Arrived", Scene = "Arrive", Gap = 6.2 },
	{ Cue = "Store", Gap = 0.45 },
	{ Cue = "Peculiar", Gap = 0.55 },
	{ Cue = "LetsGo", Gap = 0.7 },
	-- 4. ВЫХОД ИЗ МАШИНЫ
	{ Cue = "Cold", Scene = "Exit", Gap = 6.4 },
	{ Cue = "Jacket", Gap = 0.3 },
	{ Cue = "Funny", Gap = 0.35 },
	{ Cue = "Laugh2", Gap = 0.05, Laugh = "Chuckle2", Len = 1.45 },
	-- 5. АВТОМАТИЧЕСКИЕ ДВЕРИ
	{ Cue = "Doors", Scene = "Doors", Gap = 5.6 },
	{ Cue = "Come", Gap = 0.45 },
	-- 6. ПОДОЗРЕНИЕ
	{ Cue = "Feel", Scene = "Inside", Gap = 5.2 },
	{ Cue = "Stop", Gap = 0.5 },
	{ Cue = "Instr", Gap = 4.4 },
}

-- Кто и что говорит (ключ звука) при 2, 3 и 4 игроках
TeamLines.Scripts = {
	[4] = {
		Ready = "TD_Ready", Calm = "TP_Calm", Why = "TL_Why4", Popular = "TR_Popular", Relax = "TD_Relax", Know = "TR_Know", Hope = "TP_Hope",
		Radio = "TD_Radio", Off = "TP_Off", Saw = "TL_Saw", What = "TD_What", Nothing = "TL_Nothing",
		Arrived = "TD_Arrived", Store = "TP_Store", Peculiar = "TL_Peculiar", LetsGo = "TR_LetsGo",
		Cold = "TR_Cold", Jacket = "TP_Jacket", Funny = "TR_Funny",
		Doors = "TD_Doors", Come = "TR_Come",
		Feel = "TL_Feel", Stop = "TD_Stop", Instr = "TP_Instr",
	},
	[3] = {
		Ready = "TD_Ready", Calm = "TP_Calm", Why = "TL_Why3", Popular = "TP_Popular", Relax = "TD_Relax", Know = "TL_Know", Hope = "TP_Hope",
		Radio = "TD_Radio", Off = "TP_Off", Saw = "TL_Saw", What = "TD_What", Nothing = "TL_Nothing",
		Arrived = "TD_Arrived", Store = "TP_Store", Peculiar = "TL_Peculiar", LetsGo = "TD_LetsGo",
		Cold = "TL_Cold", Jacket = "TP_Jacket", Funny = "TL_Funny",
		Doors = "TD_Doors", Come = "TP_Come",
		Feel = "TL_Feel", Stop = "TD_Stop", Instr = "TP_Instr",
	},
	[2] = {
		Ready = "TD_Ready2", Calm = "TP_Calm", Why = "TP_Why2", Popular = "TD_Popular", Relax = "TD_Relax2", Know = "TP_Know2", Hope = "TD_Hope",
		Radio = "TD_Radio", Off = "TP_Off", Saw = "TP_Saw2", What = "TD_What", Nothing = "TP_Nothing",
		Arrived = "TD_Arrived", Store = "TP_Store", Peculiar = "TD_Peculiar", LetsGo = "TP_LetsGo",
		Cold = "TP_Cold", Jacket = "TD_Jacket", Funny = "TP_Funny",
		Doors = "TD_Doors", Come = "TP_Come",
		Feel = "TP_Feel2", Stop = "TD_Stop", Instr = "TP_Instr2",
	},
}

-- После последней реплики: отъезд камеры и титр
TeamLines.Tail = 11.5
-- Сцена начинается у всех одновременно: сервер назначает момент старта с запасом на доставку сообщения
TeamLines.StartDelay = 2.5

-- Где команда стоит в магазине после сцены (там же сервер ставит игроков): у входа, лицом в зал (−Z);
-- справа — пост охраны со стойкой и инструкциями
TeamLines.EndSpots = {
	Driver = Vector3.new(-49.4, 0, 40.4),
	Passenger = Vector3.new(-52.9, 0, 41.0),
	BackLeft = Vector3.new(-46.3, 0, 41.8),
	BackRight = Vector3.new(-55.9, 0, 42.2),
}

local LINE_SPEED = 0.066 -- если звука нет: ~15 знаков в секунду

-- Длина реплики: по звуку (list = Sounds.List), иначе по тексту
function TeamLines.Length(key, list, text)
	local def = list and list[key]
	if def then
		return def.Stop - def.Start
	end
	text = text or ""
	return 0.6 + (utf8.len(text) or #text) * LINE_SPEED
end

-- Расписание для n игроков (2–4): список { Cue, Key, Role, At, Len, Laugh } и словарь меток.
-- texts — запасные тексты (VoiceLines.Clips[key].Text), если звука нет
function TeamLines.Schedule(n, list, texts)
	n = math.clamp(n or 2, 2, 4)
	local script = TeamLines.Scripts[n]
	local out, byCue = {}, {}
	local t = 0
	for _, c in ipairs(TeamLines.Cues) do
		local item = { Cue = c.Cue, Scene = c.Scene }
		if c.Laugh then
			item.Laugh = c.Laugh
			item.Len = c.Len
		else
			local key = script[c.Cue]
			local clip = texts and texts[key]
			item.Key = key
			item.Role = TeamLines.RoleOfVoice[string.sub(key, 1, 2)]
			item.Text = clip and clip.Text or ""
			item.Len = TeamLines.Length(key, list, item.Text)
		end
		local start = t + (c.Gap or 0)
		if c.At then
			start = math.max(start, c.At)
		end
		item.At = start
		t = start + item.Len
		table.insert(out, item)
		byCue[c.Cue] = item
	end
	return out, byCue, t + TeamLines.Tail
end

-- Длина всей сцены (секунды) — для сервера
function TeamLines.Duration(n, list, texts)
	local _, _, total = TeamLines.Schedule(n, list, texts)
	return total
end

return TeamLines
