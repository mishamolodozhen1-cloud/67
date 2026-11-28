-- WeaponController: стрельба своим оружием — управление, предсказание, отдача, разброс, прицел, перезарядка.
--
-- Управление:
--   ПК       ЛКМ — огонь, ПКМ (держать) — прицел, R — перезарядка, B — режим огня (авто / одиночный)
--   Геймпад  R2 — огонь, L2 (держать) — прицел, X — перезарядка, крестовина вверх — режим огня
--   Телефон  кнопки FIRE (держать; можно вести пальцем — поворот обзора), AIM, R, режим (Controllers/TouchControls)
--
-- Выстрел считается у себя сразу (без ожидания сервера): луч из камеры с разбросом, вспышка, звук, трассер,
-- след, гильза, отдача камеры и оружия в руках; серверу уходит событие Fire (точка, направление, время и,
-- если попали в персонажа, — часть тела). Сервер решает, засчитать ли (WeaponSystem), и подтверждает
-- попадание (HitConfirmed). Патроны и перезарядку ведёт сервер: клиент показывает их заранее, а если
-- сервер прислал другое (WeaponState) — поправляется.
--
-- Правила: на бегу не стреляют и не целятся (нажатие огня или прицела останавливает бег, оружие поднимается
-- SprintToFire секунд); при перезарядке, в регдолле и пока оружие достают — не стреляют; пустой магазин —
-- щелчок и перезарядка сама. Разброс: база (от бедра / с прицелом) + движение + прыжок + раскачка очередью;
-- в приседе меньше. Отдача: вверх и немного вбок (первые выстрелы сильнее), после очереди часть отдачи
-- камера возвращает сама.
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Configs = ReplicatedStorage:WaitForChild("Configs")
local Logger = require(Shared:WaitForChild("Logger"))
local Signal = require(Shared:WaitForChild("Signal"))
local WeaponAnim = require(Shared:WaitForChild("WeaponAnim"))
local Pellets = require(Shared:WaitForChild("Pellets"))
local GameConfig = require(Configs:WaitForChild("GameConfig"))
local WeaponConfig = require(Configs:WaitForChild("WeaponConfig"))
local WeaponPoses = require(Configs:WaitForChild("WeaponPoses"))

local WeaponController = { Name = "WeaponController" }

WeaponController.StateChanged = Signal.new() -- () — патроны, режим, перезарядка изменились
WeaponController.Fired = Signal.new() -- (shot) — свой выстрел { Origin, Direction, End, Hit }
WeaponController.HitConfirmed = Signal.new() -- (info) — сервер засчитал попадание { Part, Headshot, Position }

local log = Logger.new("Weapon")
local rng = Random.new()

local net, characters, cameraCtl, viewmodel, effects, profileCtl = nil, nil, nil, nil, nil, nil
local weaponName = WeaponConfig.Default
local def = WeaponConfig.Weapons[weaponName]
local poses = WeaponPoses[weaponName]

local st = {
	Ammo = def.Magazine,
	Reserve = def.Reserve,
	Mode = def.DefaultMode,
	Known = false, -- пришло ли состояние с сервера
	EquipStart = -math.huge,
	Reload = nil, -- { Kind, Start, Length, Confirmed, Played }
	Trigger = false,
	SemiFired = false,
	DryClicked = false,
	AimWanted = false,
	AimToggle = false, -- прицел кнопкой на телефоне (вкл/выкл)
	AimAlpha = 0,
	SprintAlpha = 0,
	SprintEndedAt = -math.huge,
	NextShot = 0,
	ShotId = 0,
	Bloom = 0,
	Burst = 0,
	LastShot = -math.huge,
	PitchSentAt = 0,
	PitchSent = 0,
}

-------------------------------------------------------------------------------
-- Состояние для интерфейса и других контроллеров
-------------------------------------------------------------------------------
function WeaponController.GetState()
	local progress = nil
	if st.Reload then
		progress = math.clamp((os.clock() - st.Reload.Start) / st.Reload.Length, 0, 1)
	end
	return {
		Weapon = weaponName,
		DisplayName = def.DisplayName,
		Ammo = st.Ammo,
		Reserve = st.Reserve,
		Magazine = def.Magazine,
		Mode = st.Mode,
		Reloading = st.Reload ~= nil,
		ReloadProgress = progress,
		AimAlpha = st.AimAlpha,
		Aiming = st.AimWanted or st.AimToggle,
		Spread = WeaponController.CurrentSpread(),
		Equipped = WeaponController.HasWeapon(),
		Known = st.Known,
	}
end

function WeaponController.Definition()
	return def
end

function WeaponController.HasWeapon()
	local character = characters and characters.GetCharacter()
	return character ~= nil and character:GetAttribute("Weapon") == weaponName
end

local function alive()
	local _, humanoid, root = characters.GetCharacter()
	return humanoid ~= nil and humanoid.Health > 0 and root ~= nil and root.Parent ~= nil
end

local function horizontalSpeed()
	local _, _, root = characters.GetCharacter()
	if not root then
		return 0
	end
	local v = root.AssemblyLinearVelocity
	return Vector3.new(v.X, 0, v.Z).Magnitude
end

local function grounded()
	local _, humanoid = characters.GetCharacter()
	return humanoid ~= nil and humanoid.FloorMaterial ~= Enum.Material.Air
end

-- Текущий разброс (градусы, наибольшее отклонение пули от центра)
function WeaponController.CurrentSpread()
	local sp = def.Spread
	local aim = st.AimAlpha
	local base = sp.Hip + (sp.Aim - sp.Hip) * aim
	local move = math.clamp(horizontalSpeed() / GameConfig.Movement.WalkSpeed, 0, 1.6) * sp.Move * (1 - 0.6 * aim)
	local air = grounded() and 0 or sp.Air
	local crouch = (characters and characters.GetState().Stance == "Crouch") and sp.CrouchFactor or 1
	local bloom = st.Bloom * (1 - (1 - sp.AimBloomFactor) * aim)
	return (base + move + air) * crouch + bloom
end

-- Направление внутри конуса с отклонением до spread градусов (равномерно по кругу)
function WeaponController.ConeDirection(cf, spread, random)
	random = random or rng
	local r = math.rad(spread) * math.sqrt(random:NextNumber())
	local theta = random:NextNumber(0, math.pi * 2)
	return (cf.Rotation * CFrame.Angles(0, 0, theta) * CFrame.Angles(r, 0, 0)).LookVector
end

-------------------------------------------------------------------------------
-- Действия
-------------------------------------------------------------------------------
local function changed()
	WeaponController.StateChanged:Fire()
end

function WeaponController.SetTrigger(down)
	down = down == true
	if st.Trigger == down then
		return
	end
	st.Trigger = down
	if not down then
		st.SemiFired = false
		st.DryClicked = false
	end
end

function WeaponController.SetAim(on)
	st.AimWanted = on == true
end

function WeaponController.ToggleAim()
	st.AimToggle = not st.AimToggle
	changed()
end

function WeaponController.RequestReload()
	if st.Reload or not alive() or characters.IsRagdolled() or not WeaponController.HasWeapon() then
		return false
	end
	if st.Ammo >= def.Magazine or st.Reserve <= 0 then
		return false
	end
	if not net.Fire("Reload") then
		return false
	end
	local kind = st.Ammo == 0 and "Empty" or "Tactical"
	st.Reload = { Kind = kind, Start = os.clock(), Length = WeaponAnim.Length(poses, kind), Confirmed = false, Played = {} }
	st.Bloom, st.Burst = 0, 0
	changed()
	return true
end

function WeaponController.ToggleMode()
	if not WeaponController.HasWeapon() then
		return
	end
	local modes = def.Modes
	local i = table.find(modes, st.Mode) or 1
	local mode = modes[i % #modes + 1]
	if mode ~= st.Mode and net.Fire("FireMode", mode) then
		st.Mode = mode
		effects.PlaySound("Select", nil, { Volume = 0.45, Pitch = 0.02 })
		changed()
	end
end

-------------------------------------------------------------------------------
-- Выстрел
-------------------------------------------------------------------------------
local function rayParams(character)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character, workspace.CurrentCamera, effects.Folder() }
	params.IgnoreWater = true
	return params
end

local function canFire(now)
	if not (alive() and WeaponController.HasWeapon()) or characters.IsRagdolled() then
		return false
	end
	if st.Reload or now - st.EquipStart < def.EquipTime then
		return false
	end
	if st.SprintAlpha > 0.35 or now - st.SprintEndedAt < def.SprintToFire then
		return false
	end
	return true
end

local function fireOne(now)
	local character, _, root = characters.GetCharacter()
	local camera = workspace.CurrentCamera
	local cf = camera.CFrame
	local origin = cf.Position
	local spread = WeaponController.CurrentSpread()
	local dir = WeaponController.ConeDirection(cf, spread)
	local range = def.Range
	local id = st.ShotId + 1
	-- лучи: один или дробь (направления дробин — по номеру выстрела, как на сервере)
	local params = rayParams(character)
	local dirs = Pellets.Directions(dir, def.Pellets or 1, def.Spread.Pellet or 0, id)
	local shots = {}
	local counts, best = {}, nil
	local hitPart, hitPos = nil, nil
	for i, d in ipairs(dirs) do
		local result = workspace:Raycast(origin, d * range, params)
		shots[i] = { End = result and result.Position or origin + d * range, Result = result }
		if result then
			local model = result.Instance.Parent
			if model and model ~= character and model:FindFirstChildOfClass("Humanoid") then
				-- у дроби о попадании сообщаем по той части, в которую попало больше всего дробин
				counts[result.Instance] = (counts[result.Instance] or 0) + 1
				if not best or counts[result.Instance] > counts[best] then
					best = result.Instance
					hitPos = result.Position
				end
			end
		end
	end
	hitPart = best
	local result = shots[1].Result
	if not net.Fire("Fire", id, origin, dir, workspace:GetServerTimeNow(), hitPart, hitPos) then
		return false -- лимит отправки: выстрел в следующем кадре
	end
	st.ShotId = id
	st.Ammo = st.Ammo - 1
	st.LastShot = now
	st.Burst = st.Burst + 1
	st.Bloom = math.min(def.Spread.MaxBloom, st.Bloom + def.Spread.PerShot)
	-- отдача камеры
	local r = def.Recoil
	local crouch = characters.GetState().Stance == "Crouch"
	local k = (1 - (1 - r.AimFactor) * st.AimAlpha) * (crouch and r.CrouchFactor or 1)
	local mult = r.Pattern[st.Burst] or 1
	local vertical = r.Vertical * mult * k
	local horizontal = (rng:NextNumber(-1, 1) * r.Horizontal + r.Drift) * k
	cameraCtl.AddRecoil(vertical, horizontal, r.KickTime, r.ReturnFraction, r.ReturnSpeed)
	viewmodel.Kick(def, st.AimAlpha)
	local endPos = shots[1].End
	effects.LocalShot(viewmodel.Muzzle(), viewmodel.Eject(), shots, root and root.AssemblyLinearVelocity, weaponName, not def.BoltAction)
	if def.BoltAction and st.Ammo > 0 then
		-- затвор передёргивают после выстрела (гильза вылетает при этом)
		st.Cycle = { Start = now, Played = {}, Ejected = false }
	end
	WeaponController.Fired:Fire({ Origin = origin, Direction = dir, End = endPos, Hit = hitPart, Pellets = #dirs })
	return true
end

local function tryFire(now)
	if not canFire(now) then
		return
	end
	if st.Ammo <= 0 then
		if not st.DryClicked then
			st.DryClicked = true
			effects.PlaySound("Dry", nil, { Volume = 0.5, Pitch = 0.02 })
			WeaponController.RequestReload()
		end
		return
	end
	if st.Mode == "Semi" and st.SemiFired then
		return
	end
	local interval = 60 / def.Rpm
	-- после паузы отсчёт темпа начинается с этого кадра; в очереди — ровно через interval (при низком FPS
	-- кадр может догнать не больше одного пропущенного выстрела)
	if st.NextShot < now - interval then
		st.NextShot = now
	end
	local fired = 0
	while now >= st.NextShot and fired < 2 and st.Ammo > 0 do
		if not fireOne(now) then
			break
		end
		st.NextShot = st.NextShot + interval
		fired = fired + 1
		if st.Mode == "Semi" then
			st.SemiFired = true
			break
		end
	end
	if fired > 0 then
		changed()
	end
end

-------------------------------------------------------------------------------
-- Кадр
-------------------------------------------------------------------------------
local function approach(value, target, rate, dt)
	if value < target then
		return math.min(target, value + rate * dt)
	end
	return math.max(target, value - rate * dt)
end

local function updateReload(now)
	local r = st.Reload
	if not r then
		return nil
	end
	local t = now - r.Start
	for i, ev in ipairs(WeaponAnim.Sounds(poses, r.Kind)) do
		if t >= ev[1] and not r.Played[i] then
			r.Played[i] = true
			effects.PlaySound(ev[2], nil, { Volume = 0.45, Pitch = 0.03 })
		end
	end
	if t >= r.Length then
		-- анимация закончилась: ждём подтверждения сервера (он начал позже — на задержку сети), но не вечно
		if r.Confirmed or t > r.Length + 1.5 then
			if not r.Confirmed then
				local take = math.min(def.Magazine - st.Ammo, st.Reserve)
				st.Ammo, st.Reserve = st.Ammo + take, st.Reserve - take
			end
			st.Reload = nil
			changed()
			return nil
		end
	end
	return { Kind = r.Kind, T = math.min(t, r.Length) }
end

-- Передёргивание затвора снайперской после выстрела: звуки и гильза по ключам Cycle
local function updateCycle(now)
	local c = st.Cycle
	if not c or not poses.Reloads.Cycle then
		return nil
	end
	local t = now - c.Start
	for i, ev in ipairs(WeaponAnim.Sounds(poses, "Cycle")) do
		if t >= ev[1] and not c.Played[i] then
			c.Played[i] = true
			effects.PlaySound(ev[2], nil, { Volume = 0.45, Pitch = 0.03 })
		end
	end
	local charge = poses.Reloads.Cycle.Charge
	if not c.Ejected and charge and t >= charge[2] then
		c.Ejected = true
		local _, _, root = characters.GetCharacter()
		effects.Casing(viewmodel.Eject(), root and root.AssemblyLinearVelocity, weaponName)
	end
	if t >= WeaponAnim.Length(poses, "Cycle") or st.Reload then
		st.Cycle = nil
		return nil
	end
	return { Kind = "Cycle", T = t }
end

function WeaponController.IsCycling()
	return st.Cycle ~= nil
end

-- Смотрит в оптический прицел (снайперская): оружия в руках не видно, на экране — сетка прицела
function WeaponController.IsScoped()
	return def.Scope == true and st.AimAlpha > 0.9
end

local function sendPitch(now)
	if now - st.PitchSentAt < 0.1 then
		return
	end
	local look = workspace.CurrentCamera.CFrame.LookVector
	local pitch = math.deg(math.asin(math.clamp(look.Y, -1, 1)))
	if math.abs(pitch - st.PitchSent) >= 0.75 and net.Fire("AimPitch", math.clamp(pitch, -89, 89)) then
		st.PitchSent = pitch
		st.PitchSentAt = now
	end
end

local function update(dt)
	local now = os.clock()
	local isAlive = alive()
	local ragdolled = characters.IsRagdolled()
	local hasWeapon = isAlive and WeaponController.HasWeapon()
	local moveState = characters.GetState()
	-- бег: пока он идёт и чуть после — оружие опущено
	if moveState.Sprint then
		st.SprintEndedAt = now
	end
	st.SprintAlpha = approach(st.SprintAlpha, moveState.Sprint and 1 or 0, 1 / 0.2, dt)
	local reloadView = updateReload(now)
	local cycleView = updateCycle(now)
	local equip = math.clamp((now - st.EquipStart) / def.EquipTime, 0, 1)
	-- прицел (у снайперской на время передёргивания затвора оружие отходит от глаза)
	local wantAim = (st.AimWanted or st.AimToggle) and hasWeapon and not ragdolled
	local canAim = wantAim and not st.Reload and equip >= 1 and not moveState.Sprint and not cycleView
	st.AimAlpha = approach(st.AimAlpha, canAim and 1 or 0, 1 / def.Aim.Time, dt)
	characters.SetSprintBlocked("Aim", wantAim)
	characters.SetSprintBlocked("Fire", st.Trigger and hasWeapon and st.Ammo > 0 and not st.Reload)
	characters.SetAim(canAim)
	cameraCtl.SetAim(st.AimAlpha, poses.Viewmodel.AimFov)
	local settings = profileCtl and profileCtl.Settings()
	local base = settings and settings.Sensitivity or 1
	local aimFactor = settings and settings.AimSensitivity or def.Aim.SensitivityFactor
	UserInputService.MouseDeltaSensitivity = base * (1 + (aimFactor - 1) * st.AimAlpha)
	-- раскачка очередью затухает
	if now - st.LastShot > 60 / def.Rpm * 1.6 then
		st.Bloom = math.max(0, st.Bloom - def.Spread.Recovery * dt)
		st.Burst = 0
	end
	if st.Trigger and hasWeapon then
		tryFire(now)
	end
	if hasWeapon and not ragdolled then
		sendPitch(now)
	end
	viewmodel.SetInput({
		Aim = st.AimAlpha,
		Sprint = st.SprintAlpha,
		Equip = equip,
		Reload = reloadView or cycleView,
		Speed = horizontalSpeed(),
		Grounded = grounded(),
		Visible = hasWeapon and not ragdolled and cameraCtl.IsFirstPerson() and not WeaponController.IsScoped(),
	})
end

-------------------------------------------------------------------------------
-- Сервер
-------------------------------------------------------------------------------
local setWeapon -- объявлена ниже (смена оружия)

local function onServerState(s)
	if type(s) ~= "table" or type(s.Ammo) ~= "number" or type(s.Reserve) ~= "number" then
		return
	end
	st.Known = true
	local reason = s.Reason
	if reason == "Equip" then
		local character = characters.GetCharacter()
		if s.Weapon ~= weaponName and character and WeaponConfig.Weapons[s.Weapon] then
			setWeapon(character, s.Weapon)
		end
		st.Ammo, st.Reserve, st.Mode = s.Ammo, s.Reserve, s.Mode or st.Mode
		st.Reload = nil
	elseif reason == "Reloaded" then
		st.Ammo, st.Reserve = s.Ammo, s.Reserve
		if st.Reload then
			st.Reload.Confirmed = true
		end
	elseif reason == "Reload" then
		-- сервер начал перезарядку (мы её уже показываем)
		if not st.Reload and s.ReloadKind then
			st.Reload = { Kind = s.ReloadKind, Start = os.clock(), Length = WeaponAnim.Length(poses, s.ReloadKind), Confirmed = false, Played = {} }
		end
	elseif reason == "NoReload" then
		st.Ammo, st.Reserve = s.Ammo, s.Reserve
		st.Reload = nil
	else
		-- сервер не принял выстрел или сменил режим: его данные — правильные
		st.Ammo, st.Reserve, st.Mode = s.Ammo, s.Reserve, s.Mode or st.Mode
		if s.Reloading and not st.Reload and s.ReloadKind then
			local left = math.max(0, (s.ReloadEnd or 0) - workspace:GetServerTimeNow())
			local length = WeaponAnim.Length(poses, s.ReloadKind)
			st.Reload = { Kind = s.ReloadKind, Start = os.clock() - (length - left), Length = length, Confirmed = false, Played = {} }
		end
	end
	changed()
end

-------------------------------------------------------------------------------
-- Ввод
-------------------------------------------------------------------------------
local function onFire(_, inputState)
	if inputState == Enum.UserInputState.Begin then
		WeaponController.SetTrigger(true)
	elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
		WeaponController.SetTrigger(false)
	end
	return Enum.ContextActionResult.Pass
end

local function onAim(_, inputState)
	if inputState == Enum.UserInputState.Begin then
		WeaponController.SetAim(true)
	elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
		WeaponController.SetAim(false)
	end
	return Enum.ContextActionResult.Pass
end

local function onReload(_, inputState)
	if inputState == Enum.UserInputState.Begin then
		WeaponController.RequestReload()
	end
	return Enum.ContextActionResult.Sink
end

local function onMode(_, inputState)
	if inputState == Enum.UserInputState.Begin then
		WeaponController.ToggleMode()
	end
	return Enum.ContextActionResult.Sink
end

-- Сменить оружие в руках (выдал сервер: атрибут Weapon персонажа — при появлении и в GUN GAME)
setWeapon = function(character, name)
	if not (name and WeaponConfig.Weapons[name] and WeaponPoses[name]) then
		return false
	end
	weaponName, def, poses = name, WeaponConfig.Weapons[name], WeaponPoses[name]
	st.Reload = nil
	st.EquipStart = os.clock()
	st.Ammo, st.Reserve, st.Mode = def.Magazine, def.Reserve, def.DefaultMode -- до ответа сервера — полный комплект
	st.Bloom, st.Burst, st.NextShot = 0, 0, 0
	st.Cycle = nil
	task.spawn(function()
		if not viewmodel.Build(character, name) then
			log:Error("вид от первого лица без оружия %s", name)
		end
	end)
	changed()
	return true
end

local weaponConn = nil
local function onCharacter(character)
	st.Reload = nil
	st.Trigger, st.SemiFired, st.DryClicked = false, false, false
	st.AimWanted, st.AimToggle, st.AimAlpha, st.SprintAlpha = false, false, 0, 0
	st.Bloom, st.Burst = 0, 0
	st.EquipStart = os.clock()
	cameraCtl.ResetRecoil()
	if weaponConn then
		weaponConn:Disconnect()
	end
	weaponConn = character:GetAttributeChangedSignal("Weapon"):Connect(function()
		local name = character:GetAttribute("Weapon")
		if name ~= weaponName or not viewmodel.Exists() then
			setWeapon(character, name)
		end
	end)
	if not setWeapon(character, character:GetAttribute("Weapon")) then
		viewmodel.Destroy() -- без оружия (лобби); модель соберётся, когда сервер выдаст оружие
	end
	changed()
end

-- Для проверки без клиента (tests/stage4): один кадр, ответ сервера, новый персонаж
WeaponController.Step = update
WeaponController.ServerState = onServerState
WeaponController.OnCharacter = onCharacter

function WeaponController.Init(context)
	net = context.Get("ClientNet")
	characters = context.Get("CharacterController")
	cameraCtl = context.Get("CameraController")
	viewmodel = context.Get("Viewmodel")
	effects = context.Get("WeaponEffects")
	local ok, p = pcall(context.Get, "ProfileController")
	profileCtl = ok and p or nil
end

function WeaponController.Start()
	net.On("WeaponState", onServerState)
	net.On("HitConfirmed", function(info)
		if type(info) == "table" then
			WeaponController.HitConfirmed:Fire(info)
		end
	end)
	ContextActionService:BindAction("DC_Fire", onFire, false, Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonR2)
	ContextActionService:BindAction("DC_Aim", onAim, false, Enum.UserInputType.MouseButton2, Enum.KeyCode.ButtonL2)
	ContextActionService:BindAction("DC_Reload", onReload, false, Enum.KeyCode.R, Enum.KeyCode.ButtonX)
	ContextActionService:BindAction("DC_FireMode", onMode, false, Enum.KeyCode.B, Enum.KeyCode.DPadUp)
	characters.CharacterChanged:Connect(function(character, humanoid)
		onCharacter(character)
		humanoid.Died:Connect(function()
			WeaponController.SetTrigger(false)
			st.Reload = nil
			changed()
		end)
	end)
	local character = characters.GetCharacter()
	if character then
		onCharacter(character)
	end
	-- после камеры (CameraController и камера Roblox), до вида от первого лица (Viewmodel, Camera + 2)
	RunService:BindToRenderStep("DC_Weapon", Enum.RenderPriority.Camera.Value + 1, update)
	Players.LocalPlayer.CharacterRemoving:Connect(function()
		WeaponController.SetTrigger(false)
	end)
end

return WeaponController
