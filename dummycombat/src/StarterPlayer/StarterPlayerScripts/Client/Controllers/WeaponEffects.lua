-- WeaponEffects: эффекты и звуки выстрелов у этого клиента — своих и чужих.
--
--   • вспышка у дула (две текстуры: спереди и сбоку) и короткий свет;
--   • трассер — тонкий светлый штрих, летящий от дула к точке попадания;
--   • попадание: след от пули на поверхности (исчезает через HoleLifetime, не больше MaxHoles), облачко
--     пыли/щепок/искр по материалу и звук по материалу (бетон, металл, дерево, тело);
--   • гильза вылетает из окна выброса, падает с физикой (группа DC_Debris — не задевает персонажей) и звенит;
--   • звуки — из одного файла-спрайта (WeaponAssets.Sfx): каждый звук — отрезок файла (PlaybackRegion);
--     свой выстрел звучит «в голове» (без позиции), чужие — в точке выстрела, издалека — дальний раскат.
-- Чужие выстрелы приходят с сервера (ShotFired): эффекты — у оружия стрелка.
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ContentProvider = game:GetService("ContentProvider")

local Configs = ReplicatedStorage:WaitForChild("Configs")
local Logger = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Logger"))
local WeaponAssets = require(Configs:WaitForChild("WeaponAssets"))
local WeaponConfig = require(Configs:WaitForChild("WeaponConfig"))

local WeaponEffects = { Name = "WeaponEffects" }

local log = Logger.new("Effects")
local fx = WeaponConfig.Effects
local groups = WeaponAssets.Sfx.Groups

local folder = nil -- workspace.Effects (только у этого клиента)
local holes = {}
local casings = {}
local tracers = {}
local rng = Random.new()

-- Какую группу звуков и какой цвет частиц дать материалу поверхности
local METAL = { Metal = true, DiamondPlate = true, CorrodedMetal = true, Foil = true }
local WOOD = { Wood = true, WoodPlanks = true }
local SOFT = { Grass = true, LeafyGrass = true, Ground = true, Sand = true, Mud = true, Snow = true, Fabric = true }

function WeaponEffects.SurfaceKind(materialName)
	if materialName == "Body" then
		return "Body"
	elseif METAL[materialName] then
		return "Metal"
	elseif WOOD[materialName] then
		return "Wood"
	elseif SOFT[materialName] then
		return "Soft"
	end
	return "Concrete"
end

local DUST = {
	Concrete = { Color = Color3.fromRGB(168, 164, 156), Count = 7, Speed = 9 },
	Soft = { Color = Color3.fromRGB(110, 96, 74), Count = 8, Speed = 8 },
	Wood = { Color = Color3.fromRGB(150, 112, 70), Count = 6, Speed = 10 },
	Metal = { Color = Color3.fromRGB(255, 196, 120), Count = 9, Speed = 22, Sparks = true },
	Body = { Color = Color3.fromRGB(201, 170, 98), Count = 5, Speed = 7 },
}

-------------------------------------------------------------------------------
-- Звуки
-------------------------------------------------------------------------------
local SoundService = game:GetService("SoundService")
local function sfxGroup()
	local g = SoundService:FindFirstChild("DC_SFX")
	if not g then
		g = Instance.new("SoundGroup")
		g.Name = "DC_SFX"
		g.Parent = SoundService
	end
	return g
end
-- Сыграть звук из группы (случайный вариант). at: Vector3 (звук в мире) или nil (без позиции, «в голове»).
-- opts: Volume, Pitch (разброс ±), MaxDistance
function WeaponEffects.PlaySound(group, at, opts)
	local list = groups[group]
	if not list then
		log:Warn("нет звука %s", tostring(group))
		return nil
	end
	opts = opts or {}
	local region = list[rng:NextInteger(1, #list)]
	local s = Instance.new("Sound")
	s.SoundId = WeaponAssets.Sfx.Id
	s.PlaybackRegionsEnabled = true
	s.PlaybackRegion = NumberRange.new(region.Start, region.Stop)
	s.Volume = opts.Volume or 0.6
	local pitch = opts.Pitch or 0.04
	s.PlaybackSpeed = 1 + rng:NextNumber(-pitch, pitch)
	s.SoundGroup = sfxGroup()
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = opts.MinDistance or 8
	s.RollOffMaxDistance = opts.MaxDistance or 220
	local holder = nil
	if at then
		holder = Instance.new("Attachment")
		holder.WorldPosition = at
		holder.Parent = workspace.Terrain
		s.Parent = holder
	else
		s.Parent = folder or workspace
	end
	s:Play()
	local life = (region.Stop - region.Start) / s.PlaybackSpeed + 0.2
	Debris:AddItem(holder or s, life)
	return s
end

-------------------------------------------------------------------------------
-- Вспышка, трассер, попадание, гильза
-------------------------------------------------------------------------------
local function emitterTemplate(texture, size, lifetime)
	local e = Instance.new("ParticleEmitter")
	e.Texture = texture
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Brightness = 2.2
	e.Rate = 0
	e.Speed = NumberRange.new(0)
	e.Lifetime = NumberRange.new(lifetime)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(1, size * 0.55) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.05), NumberSequenceKeypoint.new(1, 1) })
	e.Rotation = NumberRange.new(0, 360)
	e.LockedToPart = true
	e.ZOffset = 0.5
	return e
end

-- Подготовить к оружию (модель с точкой Muzzle) вспышку и свет. Повторный вызов ничего не делает.
-- Вспышка: «звезда» спереди (частица, всегда лицом к камере) + язык пламени сбоку (Beam от дула вперёд:
-- текстура вытянута вдоль ствола, яркое основание — у дула) + короткий свет
function WeaponEffects.Rig(weaponModel, scale)
	local body = weaponModel and weaponModel.PrimaryPart
	local muzzle = body and body:FindFirstChild("Muzzle")
	if not muzzle or muzzle:FindFirstChild("Flash") then
		return muzzle
	end
	scale = scale or 1
	local front = emitterTemplate(WeaponAssets.Images.MuzzleFlash, 0.7 * scale, 0.05)
	front.Name = "Flash"
	front.Parent = muzzle
	local tip = Instance.new("Attachment")
	tip.Name = "FlashEnd"
	tip.Position = muzzle.Position + Vector3.new(0, 0, -1.0 * scale)
	tip.Parent = body
	local beam = Instance.new("Beam")
	beam.Name = "FlashSide"
	beam.Attachment0 = muzzle
	beam.Attachment1 = tip
	beam.Texture = WeaponAssets.Images.MuzzleFlashSide
	beam.TextureMode = Enum.TextureMode.Stretch
	beam.TextureLength = 1
	beam.Width0 = 0.42 * scale
	beam.Width1 = 0.42 * scale
	beam.FaceCamera = true
	beam.Segments = 1
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.Brightness = 2
	beam.Transparency = NumberSequence.new(1)
	beam.Parent = body
	local light = Instance.new("PointLight")
	light.Name = "FlashLight"
	light.Color = Color3.fromRGB(255, 196, 130)
	light.Range = 12
	light.Brightness = 0
	light.Shadows = false
	light.Parent = muzzle
	muzzle:SetAttribute("FlashLength", 1.0 * scale)
	return muzzle
end

function WeaponEffects.Flash(muzzle)
	if not muzzle then
		return
	end
	local body = muzzle.Parent
	local front, light = muzzle:FindFirstChild("Flash"), muzzle:FindFirstChild("FlashLight")
	local beam, tip = body:FindFirstChild("FlashSide"), body:FindFirstChild("FlashEnd")
	if front then
		front:Emit(1)
	end
	if beam and tip then
		local length = (muzzle:GetAttribute("FlashLength") or 1) * rng:NextNumber(0.75, 1.2)
		tip.Position = muzzle.Position + Vector3.new(0, 0, -length)
		beam.Transparency = NumberSequence.new(0)
		task.delay(0.04, function()
			beam.Transparency = NumberSequence.new(1)
		end)
	end
	if light then
		light.Brightness = 2.4
		task.delay(0.045, function()
			light.Brightness = 0
		end)
	end
end

function WeaponEffects.Tracer(from, to)
	local dist = (to - from).Magnitude
	if dist < 3 then
		return
	end
	local p = Instance.new("Part")
	p.Name = "Tracer"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	p.Color = Color3.fromRGB(255, 226, 170)
	p.Transparency = 0.35
	local length = math.min(fx.TracerLength, dist)
	p.Size = Vector3.new(0.035, 0.035, length)
	p.Parent = folder
	table.insert(tracers, { Part = p, From = from, Dir = (to - from).Unit, Dist = dist, Length = length, Travel = 0 })
end

local function stepTracers(dt)
	for i = #tracers, 1, -1 do
		local t = tracers[i]
		t.Travel = t.Travel + fx.TracerSpeed * dt
		if t.Travel >= t.Dist then
			t.Part:Destroy()
			table.remove(tracers, i)
		else
			local head = math.min(t.Travel, t.Dist)
			local tail = math.max(0, head - t.Length)
			local mid = t.From + t.Dir * ((head + tail) / 2)
			t.Part.Size = Vector3.new(0.035, 0.035, math.max(0.05, head - tail))
			t.Part.CFrame = CFrame.lookAt(mid, mid + t.Dir)
		end
	end
end

local function puff(position, normal, kind)
	local d = DUST[kind] or DUST.Concrete
	local a = Instance.new("Attachment")
	a.WorldCFrame = CFrame.lookAt(position, position + normal) * CFrame.Angles(-math.pi / 2, 0, 0)
	a.Parent = workspace.Terrain
	local e = Instance.new("ParticleEmitter")
	e.Rate = 0
	e.Color = ColorSequence.new(d.Color)
	e.LightEmission = d.Sparks and 1 or 0
	e.LightInfluence = d.Sparks and 0 or 1
	e.Speed = NumberRange.new(d.Speed * 0.5, d.Speed)
	e.SpreadAngle = Vector2.new(38, 38)
	e.Acceleration = Vector3.new(0, d.Sparks and -40 or -12, 0)
	e.Drag = d.Sparks and 1 or 4
	e.Lifetime = NumberRange.new(d.Sparks and 0.12 or 0.35, d.Sparks and 0.3 or 0.7)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, d.Sparks and 0.05 or 0.18), NumberSequenceKeypoint.new(1, d.Sparks and 0.01 or 0.45) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, d.Sparks and 0 or 0.35), NumberSequenceKeypoint.new(1, 1) })
	e.EmissionDirection = Enum.NormalId.Top
	e.Parent = a
	e:Emit(d.Count)
	Debris:AddItem(a, 1.2)
end

local function hole(position, normal, instance)
	if not (instance and instance:IsA("BasePart")) then
		return
	end
	local p = Instance.new("Part")
	p.Name = "BulletHole"
	p.Size = Vector3.new(0.32, 0.32, 0.02)
	p.Transparency = 1
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.CFrame = CFrame.lookAt(position + normal * 0.012, position + normal * 2) * CFrame.Angles(0, 0, rng:NextNumber(0, math.pi * 2))
	local decal = Instance.new("Decal")
	decal.Texture = WeaponAssets.Images.BulletHole
	decal.Face = Enum.NormalId.Front
	decal.Parent = p
	p.Parent = folder
	table.insert(holes, { Part = p, Born = os.clock() })
	while #holes > fx.MaxHoles do
		local old = table.remove(holes, 1)
		old.Part:Destroy()
	end
end

-- Попадание: kind — "Body" (персонаж) или имя материала Enum.Material; instance — во что попали (для следа)
function WeaponEffects.Impact(position, normal, materialName, instance, loud)
	normal = (normal and normal.Magnitude > 0.5) and normal.Unit or Vector3.new(0, 1, 0)
	local kind = WeaponEffects.SurfaceKind(materialName)
	puff(position, normal, kind)
	if kind ~= "Body" then
		hole(position, normal, instance)
	end
	local group = (kind == "Soft") and "Concrete" or kind
	WeaponEffects.PlaySound(group, position, { Volume = loud and 0.55 or 0.4, MaxDistance = 160 })
end

function WeaponEffects.Casing(eject, inherit)
	if not eject then
		return
	end
	local template = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Weapons")
	template = template and template:FindFirstChild("AK47Casing")
	if not template then
		return
	end
	local c = template:Clone()
	c.Anchored = false
	c.CanCollide = true
	c.CanQuery = false
	c.CanTouch = false
	c.CastShadow = false
	c.Massless = false
	c.CollisionGroup = "DC_Debris"
	local cf = eject.WorldCFrame
	c.CFrame = cf * CFrame.Angles(0, math.pi / 2, 0)
	c.Parent = folder
	local right, up, back = cf.RightVector, cf.UpVector, -cf.LookVector
	c.AssemblyLinearVelocity = (inherit or Vector3.zero) + right * rng:NextNumber(9, 13) + up * rng:NextNumber(5, 8) + back * rng:NextNumber(0.5, 2)
	c.AssemblyAngularVelocity = Vector3.new(rng:NextNumber(-25, 25), rng:NextNumber(-25, 25), rng:NextNumber(-25, 25))
	table.insert(casings, { Part = c, Born = os.clock() })
	while #casings > fx.MaxCasings do
		local old = table.remove(casings, 1)
		old.Part:Destroy()
	end
	task.delay(rng:NextNumber(0.35, 0.55), function()
		if c.Parent then
			WeaponEffects.PlaySound("Casing", c.Position, { Volume = 0.22, MaxDistance = 40, MinDistance = 4 })
		end
	end)
end

-------------------------------------------------------------------------------
-- Выстрелы
-------------------------------------------------------------------------------
-- Свой выстрел: muzzle и eject — точки на оружии в руках (вид от первого лица), result — луч клиента
function WeaponEffects.LocalShot(muzzle, eject, endPos, result, inherit)
	WeaponEffects.Flash(muzzle)
	WeaponEffects.PlaySound("Shot", nil, { Volume = 0.55, Pitch = 0.035 })
	if muzzle then
		WeaponEffects.Tracer(muzzle.WorldPosition, endPos)
	end
	if result then
		local model = result.Instance.Parent
		local isBody = model and model:FindFirstChildOfClass("Humanoid") ~= nil
		WeaponEffects.Impact(result.Position, result.Normal, isBody and "Body" or result.Material.Name, result.Instance, true)
	end
	WeaponEffects.Casing(eject, inherit)
end

local function remoteWeapon(shooter)
	-- стрелок — игрок или модель бота
	local character = nil
	if typeof(shooter) == "Instance" then
		character = shooter:IsA("Player") and shooter.Character or (shooter:IsA("Model") and shooter or nil)
	end
	local gun = character and character:FindFirstChild("Weapon")
	return gun, character
end

-- Чужой выстрел (с сервера)
function WeaponEffects.RemoteShot(shooter, origin, endPos, normal, material, kind)
	if typeof(origin) ~= "Vector3" or typeof(endPos) ~= "Vector3" then
		return
	end
	local camera = workspace.CurrentCamera
	local distance = (camera.CFrame.Position - origin).Magnitude
	if distance > fx.ShotHearing then
		return
	end
	local gun = remoteWeapon(shooter)
	local muzzle = gun and WeaponEffects.Rig(gun)
	local from = muzzle and muzzle.WorldPosition or origin
	if distance < fx.DistantFrom then
		WeaponEffects.PlaySound("Shot", from, { Volume = 0.7, MaxDistance = fx.DistantFrom * 1.6, MinDistance = 10 })
	else
		WeaponEffects.PlaySound("Distant", from, { Volume = 0.6, MaxDistance = fx.ShotHearing, MinDistance = fx.DistantFrom })
	end
	if distance > fx.RemoteRange then
		return
	end
	WeaponEffects.Flash(muzzle)
	WeaponEffects.Tracer(from, endPos)
	if kind == "World" or kind == "Body" then
		-- что именно задето, ищем коротким лучом у точки попадания (для следа на поверхности)
		local instance = nil
		if kind == "World" and normal then
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = { folder }
			local r = workspace:Raycast(endPos + normal * 0.2, -normal * 0.5, params)
			instance = r and r.Instance
		end
		WeaponEffects.Impact(endPos, normal, kind == "Body" and "Body" or (material or "Concrete"), instance, false)
	end
	local eject = gun and gun.PrimaryPart and gun.PrimaryPart:FindFirstChild("Eject")
	if eject and distance < 80 then
		WeaponEffects.Casing(eject)
	end
end

function WeaponEffects.Folder()
	return folder
end

function WeaponEffects.Init(context)
	local net = context.Get("ClientNet")
	folder = workspace:FindFirstChild("Effects")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Effects"
		folder.Parent = workspace
	end
	net.On("ShotFired", function(shooter, origin, endPos, normal, material, kind)
		if shooter == Players.LocalPlayer then
			return
		end
		WeaponEffects.RemoteShot(shooter, origin, endPos, normal, material, kind)
	end)
end

function WeaponEffects.Start()
	RunService.RenderStepped:Connect(function(dt)
		stepTracers(dt)
		local t = os.clock()
		for i = #holes, 1, -1 do
			if t - holes[i].Born > fx.HoleLifetime then
				holes[i].Part:Destroy()
				table.remove(holes, i)
			end
		end
		for i = #casings, 1, -1 do
			if t - casings[i].Born > fx.CasingLifetime then
				casings[i].Part:Destroy()
				table.remove(casings, i)
			end
		end
	end)
	-- звук заранее: первый выстрел не должен молчать, пока файл грузится
	task.spawn(function()
		local s = Instance.new("Sound")
		s.SoundId = WeaponAssets.Sfx.Id
		local ok, err = pcall(ContentProvider.PreloadAsync, ContentProvider, { s })
		if not ok then
			log:Warn("звуки оружия не загрузились заранее: %s", tostring(err))
		end
		s:Destroy()
	end)
end

return WeaponEffects
