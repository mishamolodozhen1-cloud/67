-- Audio: звук на клиенте.
--   • Play(name, position, volume) — короткий звук из «спрайта» (в точке мира или в голове)
--   • фон: гул холодильников, вентиляция, лампы (3D у объектов с тегами AmbFridge/AmbVent/AmbFluor)
--   • музыка магазина (тише в подсобке, пропадает в 03:00, искажается после 04:00), ночная улица
--   • сердцебиение и низкий гул, когда рядом Покупатель; помехи при просмотре камер
local SoundService = game:GetService("SoundService")
local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Sounds = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Sounds"))

local Audio = {}

local ctx
local groups = {}
local loops = {} -- { Sound, Part, Kind, Base }
local music, outside, drone, heart, static
local threat = 0
local staticOn = false

local FILE_GROUP = { Ambience = "Ambience", Sfx = "Sfx", Voice = "Voice", Music = "Music" }

local function makeGroup(name)
	local g = Instance.new("SoundGroup")
	g.Name = "NS_" .. name
	g.Volume = 1
	g.Parent = SoundService
	groups[name] = g
	return g
end

local function newSound(name, volume)
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

-- Короткий звук. position = nil — звук «в голове» (без направления)
function Audio.Play(name, position, volume)
	local s, def = newSound(name, volume)
	if not s then
		return nil
	end
	local holder = s
	if typeof(position) == "Vector3" then
		holder = Instance.new("Attachment")
		holder.Name = "SoundAt"
		holder.Position = position
		holder.Parent = workspace.Terrain
		s.RollOffMode = Enum.RollOffMode.InverseTapered
		s.RollOffMinDistance = 10
		s.RollOffMaxDistance = 110
		s.Parent = holder
	else
		s.Parent = SoundService
	end
	s:Play()
	Debris:AddItem(holder, (def.Stop - def.Start) + 1.5)
	return s
end

local function loopOn(parent, name, minD, maxD)
	local s, def = newSound(name, 1)
	if not s then
		return nil
	end
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = minD
	s.RollOffMaxDistance = maxD
	s.Parent = parent
	s:Play()
	-- случайная фаза, чтобы одинаковые гулы не звучали в унисон
	s.TimePosition = def.Start + math.random() * math.max(0, def.Stop - def.Start - 0.5)
	return s
end

local function loop2D(name)
	local s = newSound(name, 1)
	if not s then
		return nil
	end
	s.Volume = 0
	s.Parent = SoundService
	s:Play()
	return s
end

-- Где игрок: зал, подсобка или улица (по координатам плана магазина)
local function zoneOf(pos)
	if pos.Z > 50 or pos.Z < -64 then
		return "Outside"
	end
	if pos.X >= -66 and pos.X <= 40 and pos.Z >= -12 then
		return "Sales"
	end
	return "Back"
end

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

function Audio.Init(c)
	ctx = c
	for name in pairs({ Ambience = true, Sfx = true, Voice = true, Music = true }) do
		makeGroup(name)
	end
	-- Фоновые источники у объектов магазина
	local function addTagged(tag, name, minD, maxD)
		for _, part in ipairs(CollectionService:GetTagged(tag)) do
			local s = loopOn(part, name, minD, maxD)
			if s then
				table.insert(loops, { Sound = s, Part = part, Kind = tag, Base = s.Volume })
				s.Volume = 0
			end
		end
	end
	addTagged("AmbFridge", "Fridge", 5, 34)
	addTagged("AmbVent", "Vent", 4, 26)
	addTagged("AmbFluor", "Fluorescent", 3, 20)

	music = loop2D("StoreMusic")
	outside = loop2D("NightOutside")
	drone = loop2D("Drone")
	heart = loop2D("Heartbeat")
	static = loop2D("Static")

	task.spawn(function()
		local player = ctx.Player
		while true do
			task.wait(0.25)
			local state = ctx.State
			local power = state:GetAttribute("Power") ~= false
			local phase = state:GetAttribute("Phase")
			local musicMode = state:GetAttribute("Music") or "Normal"
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			local zone = root and zoneOf(root.Position) or "Back"

			-- Гул оборудования: молчит без электричества, у сломанного холодильника тоже
			for _, l in ipairs(loops) do
				local on = power and l.Part.Parent ~= nil
				if on and l.Kind == "AmbFridge" and l.Part:GetAttribute("Broken") == true then
					on = false
				end
				approach(l.Sound, on and l.Base or 0, 0.35)
			end

			-- Музыка из потолочных динамиков
			local m = 0
			if power and phase ~= "Ending" and musicMode ~= "Off" then
				m = (zone == "Sales") and 1 or (zone == "Back" and 0.3 or 0.12)
				if musicMode == "Slow" then
					m = m * 0.75
				end
			end
			if music then
				approach(music, m * 0.32, 0.2)
				music.PlaybackSpeed = (musicMode == "Slow") and 0.8 or 1
			end
			-- Ночная улица
			approach(outside, zone == "Outside" and 0.6 or 0.06, 0.2)
			-- Близость Покупателя и темнота
			local dark = (not power) and 0.12 or 0
			approach(drone, math.max(dark, threat * 0.7), 0.25)
			approach(heart, threat > 0.15 and (0.25 + threat * 0.75) or 0, 0.3)
			if heart then
				heart.PlaybackSpeed = 0.85 + threat * 0.6
			end
			approach(static, staticOn and 0.35 or 0, 0.5)
		end
	end)
end

return Audio
