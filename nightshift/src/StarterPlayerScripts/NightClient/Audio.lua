-- Audio: звук на клиенте.
--   • Play(name, position, volume) — короткий звук (в точке мира или «в голове»)
--   • фон у объектов: холодильники, вентиляция, лампы, компьютер, вывеска (3D, по тегам)
--   • общий фон по месту, где сейчас камера: дождь и ветер на улице (внутри дождь глухой),
--     ночной город, гул ламп зала, низкий фон подсобки, тревожный гул ближе к утру
--   • эхо помещения (SoundService.AmbientReverb): зал, коридоры, комнаты, улица
--   • шаги всех людей (игроки и покупатели) по плитке и мокрому асфальту — точно в момент касания
--     пяткой: в анимациях ходьбы и бега стоят метки «Step» (L/R), звук идёт из той ступни
--   • сердцебиение, когда рядом Покупатель; помехи при просмотре камер
local SoundService = game:GetService("SoundService")
local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Sounds = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Sounds"))
local Models = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Models"))

local Audio = {}

local ctx
local groups = {}
local emitters = {} -- { Sound, Part, Kind, Base }
local beds = {} -- имя -> Sound (2D петли)
local rainEq
local threat = 0
local staticOn = false
local cinematic = false
local stepState = setmetatable({}, { __mode = "k" })

local FILE_GROUP = { Ambience = "Ambience", Sfx = "Sfx", Sfx2 = "Sfx", Sfx3 = "Sfx", Sfx4 = "Sfx", Voice = "Voice", Music = "Music" }

local function makeGroup(name)
	local g = Instance.new("SoundGroup")
	g.Name = "NS_" .. name
	g.Volume = 1
	g.Parent = SoundService
	groups[name] = g
	return g
end

-- Звук из «спрайта» (короткие звуки)
local function spriteSound(name, volume)
	local def = Sounds.List[name]
	if not def then
		return nil
	end
	local s = Instance.new("Sound")
	s.Name = name
	s.SoundId = Sounds.Files[def.File]
	s.PlaybackRegionsEnabled = true
	s.PlaybackRegion = NumberRange.new(def.Start, def.Stop)
	if def.Loop then
		s.Looped = true
		s.LoopRegion = NumberRange.new(def.Start, def.Stop)
	end
	s.Volume = def.Volume * (volume or 1)
	s.SoundGroup = groups[FILE_GROUP[def.File]]
	return s, def
end

-- Петля из отдельного файла (Sounds.Loops)
local function loopSound(name)
	local def = Sounds.Loops[name]
	if not def then
		return nil
	end
	local s = Instance.new("Sound")
	s.Name = name
	s.SoundId = def.Id
	s.Looped = true
	s.Volume = 0
	s.SoundGroup = groups.Ambience
	return s, def
end

-- Короткий звук. position = nil — звук «в голове» (без направления)
function Audio.Play(name, position, volume, pitch)
	local s, def = spriteSound(name, volume)
	if not s then
		return nil
	end
	if pitch then
		s.PlaybackSpeed = pitch
	end
	local holder = s
	if typeof(position) == "Vector3" then
		holder = Instance.new("Attachment")
		holder.Name = "SoundAt"
		holder.Position = position
		holder.Parent = workspace.Terrain
		s.RollOffMode = Enum.RollOffMode.InverseTapered
		s.RollOffMinDistance = 9
		s.RollOffMaxDistance = 110
		s.Parent = holder
	elseif typeof(position) == "Instance" then
		s.RollOffMode = Enum.RollOffMode.InverseTapered
		s.RollOffMinDistance = 9
		s.RollOffMaxDistance = 110
		s.Parent = position
		holder = s
	else
		s.Parent = SoundService
	end
	s:Play()
	Debris:AddItem(holder, (def.Stop - def.Start) / (pitch or 1) + 1.5)
	return s
end

-- Петля, привязанная к детали (3D) или общая (parent = nil)
function Audio.Loop(name, parent, minD, maxD)
	local s, def = loopSound(name)
	if not s then
		s, def = spriteSound(name, 1)
		if not s then
			return nil
		end
		s.Looped = true
	end
	if parent then
		s.RollOffMode = Enum.RollOffMode.InverseTapered
		s.RollOffMinDistance = minD or 4
		s.RollOffMaxDistance = maxD or 30
		s.Parent = parent
	else
		s.Parent = SoundService
	end
	s:Play()
	return s, (def.Volume or 0.5)
end

-- Где камера: улица, торговый зал, коридоры/склад или небольшая комната
local function zoneOf(pos)
	if pos.Z > 50 or pos.Z < -64 or pos.X < -66 or pos.X > 40 then
		return "Outside"
	end
	if pos.Z >= -12 then
		return "Sales"
	end
	if pos.X <= -10 or (pos.Z <= -34 and pos.Z >= -40) then
		return "Corridor"
	end
	return "Room"
end
Audio.ZoneOf = zoneOf

local REVERB = {
	Outside = Enum.ReverbType.City,
	Sales = Enum.ReverbType.Hallway,
	Corridor = Enum.ReverbType.StoneCorridor,
	Room = Enum.ReverbType.Room,
}

local function approach(sound, target, rate)
	if sound then
		sound.Volume = sound.Volume + (target - sound.Volume) * rate
	end
end

function Audio.SetVolumes(musicVolume, sfxVolume)
	groups.Music.Volume = musicVolume
	groups.Sfx.Volume = sfxVolume
	groups.Ambience.Volume = sfxVolume
	groups.Voice.Volume = math.max(0.3, sfxVolume)
end

-- 0..1: насколько близко Покупатель
function Audio.SetThreat(level)
	threat = math.clamp(level, 0, 1)
end

function Audio.SetStatic(on)
	staticOn = on
end

-- Кат-сцена сама управляет музыкой
function Audio.SetCinematic(on)
	cinematic = on
end

function Audio.Bed(name)
	return beds[name]
end

-------------------------------------------------------------------------------
-- Шаги
-------------------------------------------------------------------------------
local WET = {
	[Enum.Material.Asphalt] = true,
	[Enum.Material.Glass] = true,
	[Enum.Material.Pavement] = true,
	[Enum.Material.Grass] = true,
}
local SOFT = {
	[Enum.Material.Carpet] = true,
	[Enum.Material.Fabric] = true,
}

local function muteDefaultSteps(character)
	local root = character:FindFirstChild("HumanoidRootPart")
	local running = root and root:FindFirstChild("Running")
	if running and running:IsA("Sound") then
		running.Volume = 0
	end
end

-- Шаг персонажа: звук на его корневой детали (у своего игрока — тише и ближе)
function Audio.Step(root, material, outside, isLocal, sprint)
	local list = (outside or WET[material]) and Sounds.Steps.Wet or Sounds.Steps.Tile
	local name = list[math.random(1, #list)]
	local vol = (isLocal and 0.75 or 1) * (SOFT[material] and 0.45 or 1) * (sprint and 1.25 or 1)
	local s = Audio.Play(name, root, vol, 0.92 + math.random() * 0.16)
	if s and SOFT[material] then
		local eq = Instance.new("EqualizerSoundEffect")
		eq.HighGain = -12
		eq.MidGain = -4
		eq.LowGain = 0
		eq.Parent = s
	end
end

-- Шаги по меткам анимации: для каждого Animator — один обработчик на каждую дорожку ходьбы/бега
local STEP_IDS = { [Models.Anim.Walk] = "Walk", [Models.Anim.Run] = "Run" }
local hookedTracks = setmetatable({}, { __mode = "k" })
local hookedHumanoids = setmetatable({}, { __mode = "k" })
local stepRay = RaycastParams.new()
stepRay.FilterType = Enum.RaycastFilterType.Exclude

local function hookTrack(model, track)
	if hookedTracks[track] then
		return
	end
	local kind = track.Animation and STEP_IDS[track.Animation.AnimationId]
	if not kind then
		return
	end
	hookedTracks[track] = true
	track:GetMarkerReachedSignal("Step"):Connect(function(side)
		local foot = model:FindFirstChild(side == "L" and "LeftFoot" or "RightFoot") or model:FindFirstChild("HumanoidRootPart")
		local cam = workspace.CurrentCamera
		if not (foot and cam) or (foot.Position - cam.CFrame.Position).Magnitude > 60 then
			return
		end
		stepRay.FilterDescendantsInstances = { model }
		local hit = workspace:Raycast(foot.Position + Vector3.new(0, 1, 0), Vector3.new(0, -4, 0), stepRay)
		local material = hit and hit.Material or Enum.Material.Concrete
		local st = stepState[model]
		if not st then
			st = { Dist = 0 }
			stepState[model] = st
		end
		st.Marker = os.clock()
		local isLocal = ctx and model == ctx.Player.Character
		Audio.Step(foot, material, zoneOf(foot.Position) == "Outside", isLocal, kind == "Run")
	end)
end

-- Идут ли шаги этого персонажа по меткам анимации (тогда шаги «по расстоянию» не нужны)
function Audio.MarkerSteps(model)
	local st = model and stepState[model]
	return st ~= nil and st.Marker ~= nil and os.clock() - st.Marker < 1.5
end

function Audio.HookHumanoid(hum)
	if hookedHumanoids[hum] then
		return
	end
	hookedHumanoids[hum] = true
	task.spawn(function()
		local animator = hum:FindFirstChildOfClass("Animator") or hum:WaitForChild("Animator", 10)
		local model = hum.Parent
		if not (animator and model) then
			return
		end
		animator.AnimationPlayed:Connect(function(track)
			hookTrack(model, track)
		end)
		for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
			hookTrack(model, track)
		end
	end)
end

local function updateSteps(dt)
	local camPos = workspace.CurrentCamera and workspace.CurrentCamera.CFrame.Position or Vector3.new()
	for _, p in ipairs(Players:GetPlayers()) do
		local ch = p.Character
		local hum = ch and ch:FindFirstChildOfClass("Humanoid")
		local root = ch and ch:FindFirstChild("HumanoidRootPart")
		if hum and root and (root.Position - camPos).Magnitude < 70 then
			local st = stepState[ch]
			if not st then
				st = { Last = root.Position, Dist = 0 }
				stepState[ch] = st
				muteDefaultSteps(ch)
			end
			local moved = Vector3.new(root.Position.X - (st.Last or root.Position).X, 0, root.Position.Z - (st.Last or root.Position).Z).Magnitude
			st.Last = root.Position
			local markersWork = st.Marker and os.clock() - st.Marker < 1.5
			if not markersWork and hum.FloorMaterial ~= Enum.Material.Air and moved < 3 and hum.MoveDirection.Magnitude > 0.05 then
				st.Dist = st.Dist + moved
				local sprint = hum.WalkSpeed > 15
				if st.Dist >= (sprint and 5.4 or 4.3) then
					st.Dist = 0
					Audio.Step(root, hum.FloorMaterial, zoneOf(root.Position) == "Outside", p == ctx.Player, sprint)
				end
			else
				st.Dist = math.min(st.Dist, 2)
			end
		end
	end
end

-------------------------------------------------------------------------------
function Audio.Init(c)
	ctx = c
	for _, name in ipairs({ "Ambience", "Sfx", "Voice", "Music" }) do
		makeGroup(name)
	end
	-- шаги по меткам анимации: все люди в мире (игроки, покупатели, герой кат-сцены)
	for _, d in ipairs(workspace:GetDescendants()) do
		if d:IsA("Humanoid") then
			Audio.HookHumanoid(d)
		end
	end
	workspace.DescendantAdded:Connect(function(d)
		if d:IsA("Humanoid") then
			Audio.HookHumanoid(d)
		end
	end)
	-- Фоновые источники у объектов магазина
	local function addTagged(tag, name, minD, maxD)
		for _, part in ipairs(CollectionService:GetTagged(tag)) do
			local s, base = Audio.Loop(name, part, minD, maxD)
			if s then
				s.Volume = 0
				pcall(function()
					s.TimePosition = math.random() * 5
				end)
				table.insert(emitters, { Sound = s, Part = part, Kind = tag, Base = base })
			end
		end
	end
	addTagged("AmbFridge", "Fridge", 5, 34)
	addTagged("AmbVent", "Vent", 4, 26)
	addTagged("AmbFluor", "FluorHum", 3, 22)
	addTagged("AmbComputer", "Computer", 3, 18)
	addTagged("AmbSign", "SignHum", 6, 60)

	-- Общие фоновые петли
	for _, name in ipairs({ "RainOutside", "Wind", "Traffic", "StoreRoom", "LowRoom", "TensionDrone", "CctvStatic" }) do
		local s = Audio.Loop(name, nil)
		if s then
			s.Volume = 0
			beds[name] = s
		end
	end
	beds.Heartbeat = (Audio.Loop("Heartbeat", nil))
	beds.Music = (Audio.Loop("StoreMusic", nil))
	if beds.Music then
		beds.Music.SoundGroup = groups.Music
	end
	for _, s in pairs(beds) do
		s.Volume = 0
	end
	-- дождь внутри здания слышен глухо (как сквозь крышу и витрину)
	if beds.RainOutside then
		rainEq = Instance.new("EqualizerSoundEffect")
		rainEq.HighGain = 0
		rainEq.MidGain = 0
		rainEq.LowGain = 0
		rainEq.Parent = beds.RainOutside
	end

	RunService.Heartbeat:Connect(function(dt)
		updateSteps(dt)
	end)

	task.spawn(function()
		while true do
			task.wait(0.2)
			local state = ctx.State
			local power = state:GetAttribute("Power") ~= false
			local phase = state:GetAttribute("Phase")
			local hour = math.floor((state:GetAttribute("Minutes") or 0) / 60)
			local musicMode = state:GetAttribute("Music") or "Normal"
			local cam = workspace.CurrentCamera
			local zone = zoneOf(cam and cam.CFrame.Position or Vector3.new(0, 0, 0))
			local inside = zone ~= "Outside"
			pcall(function()
				SoundService.AmbientReverb = REVERB[zone]
			end)

			-- Гул оборудования: молчит без электричества, у сломанного холодильника тоже
			for _, e in ipairs(emitters) do
				local on = power and e.Part.Parent ~= nil
				if on and e.Kind == "AmbFridge" and e.Part:GetAttribute("Broken") == true then
					on = false
				end
				if e.Kind == "AmbSign" then
					on = e.Part.Parent ~= nil
				end
				approach(e.Sound, on and e.Base or 0, 0.35)
			end

			-- Улица: дождь, ветер, город. Внутри — глухо
			approach(beds.RainOutside, inside and 0.32 or 0.75, 0.25)
			if rainEq then
				rainEq.HighGain = inside and -26 or 0
				rainEq.MidGain = inside and -10 or 0
			end
			approach(beds.Wind, inside and 0.03 or 0.32, 0.25)
			approach(beds.Traffic, inside and 0.04 or 0.28, 0.25)
			-- Помещение: гул ламп зала, низкий фон подсобки
			approach(beds.StoreRoom, (zone == "Sales" and power) and 0.36 or 0, 0.25)
			local late = math.clamp((hour - 1) / 4, 0, 1)
			approach(beds.LowRoom, (zone == "Corridor" or zone == "Room") and (0.25 + late * 0.3) or (inside and late * 0.2 or 0), 0.2)
			-- Музыка из динамиков: тише в подсобке, пропадает в 03:00, искажается после 04:00
			if not cinematic then
				local m = 0
				if power and (phase == "Shift" or phase == "Lobby" or phase == "Countdown") and musicMode ~= "Off" then
					m = (zone == "Sales") and 1 or (zone == "Outside" and 0.1 or 0.3)
					if musicMode == "Slow" then
						m = m * 0.7
					end
				end
				approach(beds.Music, m * 0.22, 0.2)
				if beds.Music then
					beds.Music.PlaybackSpeed = (musicMode == "Slow") and 0.8 or 1
				end
				-- Тревожный гул: ближе к утру, в темноте и рядом с Покупателем
				local dread = 0
				if phase == "Shift" then
					dread = math.max((hour >= 2) and 0.12 + (hour - 2) * 0.08 or 0, (not power) and 0.3 or 0, threat * 0.8)
				end
				approach(beds.TensionDrone, dread, 0.2)
			end
			approach(beds.Heartbeat, threat > 0.15 and (0.25 + threat * 0.75) or 0, 0.3)
			if beds.Heartbeat then
				beds.Heartbeat.PlaybackSpeed = 0.85 + threat * 0.6
			end
			approach(beds.CctvStatic, staticOn and 0.3 or 0, 0.5)
		end
	end)
end

return Audio
