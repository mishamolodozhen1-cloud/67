-- CameraController: камера от первого лица.
--
-- Камеру ведёт стандартный модуль Roblox в режиме LockFirstPerson (мышь, геймпад и сенсорный экран
-- работают как привычно, чувствительность — из настроек Roblox у игрока). Поверх него:
--   • точка камеры — на уровне глаз манекена и чуть впереди головы (Humanoid.CameraOffset);
--   • в приседе камера опускается вместе с персонажем (плавно: присед меняет HipHeight постепенно);
--   • лёгкое покачивание в такт шагам (сильнее на бегу, слабее в приседе, в воздухе нет);
--   • просадка камеры при приземлении с высоты;
--   • поле зрения на бегу чуть шире;
--   • свой манекен: голова, грудь и руки скрыты (не мешают обзору; руки с оружием рисует Viewmodel), а таз
--     и ноги видно, если посмотреть вниз; своё оружие у плеча (его видят другие) тоже скрыто;
--   • оружие (этап 4): прицел сужает поле зрения (SetAim), отдача поворачивает взгляд вверх и вбок и после
--     очереди частично возвращается (AddRecoil); палец на кнопке огня тоже поворачивает обзор (AddLook).
--     Поворот вносится в камеру до модуля камеры Roblox — тот берёт направление взгляда из камеры, поэтому
--     отдача остаётся, а не «отпрыгивает» назад;
--   • упал (регдолл) — камера держится за голову; погиб — камера от третьего лица смотрит на тело.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("GameConfig"))

local CameraController = { Name = "CameraController" }

local cfg = GameConfig.Camera
local move = GameConfig.Movement

-- Части, скрытые от своей камеры (остальные видны)
CameraController.HiddenParts = {
	Head = true,
	UpperTorso = true,
	LeftUpperArm = true,
	LeftLowerArm = true,
	LeftHand = true,
	RightUpperArm = true,
	RightLowerArm = true,
	RightHand = true,
}

local characters = nil
local bob = { Phase = 0, Amount = 0 }
local dip = { Offset = 0, Speed = 0 }
local fallSpeed = 0
local fov = cfg.FieldOfView
local aim = { Alpha = 0, Fov = cfg.FieldOfView }
local recoil = { Pitch = 0, Yaw = 0, KickTime = 0.06, Return = 0, ReturnFraction = 0.5, ReturnSpeed = 12, LastAdd = -math.huge }
local look = { Yaw = 0, Pitch = 0 }
local MAX_PITCH = math.rad(80)

-- Прицел: alpha 0..1 (насколько оружие у глаза), fov — поле зрения при полном прицеле
function CameraController.SetAim(alpha, aimFov)
	aim.Alpha = math.clamp(alpha, 0, 1)
	aim.Fov = aimFov or aim.Fov
end

-- Отдача выстрела: pitch вверх и yaw вправо (градусы) — камера доходит до них за kickTime секунд;
-- returnFraction отдачи по вертикали после очереди возвращается со скоростью returnSpeed (град/с)
function CameraController.AddRecoil(pitch, yaw, kickTime, returnFraction, returnSpeed)
	recoil.Pitch = recoil.Pitch + pitch
	recoil.Yaw = recoil.Yaw + yaw
	recoil.KickTime = kickTime or recoil.KickTime
	recoil.ReturnFraction = returnFraction or recoil.ReturnFraction
	recoil.ReturnSpeed = returnSpeed or recoil.ReturnSpeed
	recoil.LastAdd = os.clock()
end

function CameraController.ResetRecoil()
	recoil.Pitch, recoil.Yaw, recoil.Return = 0, 0, 0
	look.Yaw, look.Pitch = 0, 0
end

-- Повернуть обзор (радианы): вправо yaw, вверх pitch (например, пальцем на кнопке огня)
function CameraController.AddLook(yaw, pitch)
	look.Yaw = look.Yaw + yaw
	look.Pitch = look.Pitch + pitch
end

-- Камера сейчас от первого лица (у головы своего манекена)
function CameraController.IsFirstPerson()
	local character = characters and characters.GetCharacter()
	local head = character and character:FindFirstChild("Head")
	return head ~= nil and (workspace.CurrentCamera.CFrame.Position - head.Position).Magnitude < 2.5
end

-- Повернуть камеру на dPitch / dYaw (радианы), не дальше ±80° по вертикали
local function rotateCamera(camera, dPitch, dYaw)
	local cf = camera.CFrame
	local lv = cf.LookVector
	local yaw = math.atan2(-lv.X, -lv.Z)
	local pitch = math.asin(math.clamp(lv.Y, -1, 1))
	pitch = math.clamp(pitch + dPitch, -MAX_PITCH, MAX_PITCH)
	camera.CFrame = CFrame.new(cf.Position) * CFrame.fromEulerAnglesYXZ(pitch, yaw - dYaw, 0)
end

-- Отдача и поворот пальцем: часть накопленного за кадр — в камеру
local function applyRotation(camera, dt)
	local dp, dy = 0, 0
	if recoil.Pitch ~= 0 or recoil.Yaw ~= 0 then
		local k = math.min(1, dt / math.max(recoil.KickTime, 1e-3))
		local p, y = recoil.Pitch * k, recoil.Yaw * k
		recoil.Pitch, recoil.Yaw = recoil.Pitch - p, recoil.Yaw - y
		if math.abs(recoil.Pitch) < 1e-3 then
			recoil.Pitch = 0
		end
		if math.abs(recoil.Yaw) < 1e-3 then
			recoil.Yaw = 0
		end
		dp, dy = dp + p, dy + y
		recoil.Return = recoil.Return + p * recoil.ReturnFraction
	end
	if recoil.Return > 0 and os.clock() - recoil.LastAdd > 0.12 then
		local r = math.min(recoil.Return, recoil.ReturnSpeed * dt)
		recoil.Return = recoil.Return - r
		dp = dp - r
	end
	local rp, ry = math.rad(dp) + look.Pitch, math.rad(dy) + look.Yaw
	look.Yaw, look.Pitch = 0, 0
	if rp ~= 0 or ry ~= 0 then
		rotateCamera(camera, rp, ry)
	end
end

-- Длина шага при ходьбе: за один шаг покачивание проходит полцикла
local STEP_LENGTH = 4.0

-- Смещение камеры при скорости speed (studs/с) и стойке: (вбок, вверх)
function CameraController.BobOffset(phase, amount)
	local y = cfg.BobVertical * amount * (math.cos(phase * 2) - 1) * 0.5
	local x = cfg.BobSide * amount * math.sin(phase)
	return x, y
end

local function preCamera(dt)
	local _, humanoid, root = characters.GetCharacter()
	local camera = workspace.CurrentCamera
	if not (humanoid and root and humanoid.Health > 0) or characters.IsRagdolled() then
		return
	end
	local st = characters.GetState()
	applyRotation(camera, dt)
	-- покачивание
	local vel = root.AssemblyLinearVelocity
	local speed = Vector3.new(vel.X, 0, vel.Z).Magnitude
	local grounded = humanoid.FloorMaterial ~= Enum.Material.Air
	local scale = st.Sprint and cfg.SprintBobScale or (st.Stance == "Crouch" and cfg.CrouchBobScale or 1)
	local want = (cfg.HeadBob and grounded) and math.clamp(speed / move.WalkSpeed, 0, 1.6) * scale * (1 - 0.8 * aim.Alpha) or 0
	bob.Amount = bob.Amount + (want - bob.Amount) * math.min(1, dt * 8)
	bob.Phase = bob.Phase + dt * speed / STEP_LENGTH * math.pi
	local bx, by = CameraController.BobOffset(bob.Phase, bob.Amount)
	-- просадка при приземлении: пружина
	if not grounded then
		fallSpeed = math.min(fallSpeed, vel.Y)
	elseif fallSpeed < -1 then
		local impact = math.clamp((-fallSpeed - 18) / 50, 0, 1)
		dip.Speed = dip.Speed - impact * cfg.LandDip * 14
		fallSpeed = 0
	end
	local force = -170 * dip.Offset - 18 * dip.Speed
	dip.Speed = dip.Speed + force * dt
	dip.Offset = math.clamp(dip.Offset + dip.Speed * dt, -cfg.LandDip, cfg.LandDip)
	humanoid.CameraOffset = Vector3.new(bx, cfg.EyeHeight + by + dip.Offset, -cfg.EyeForward)
	-- поле зрения
	local target = st.Sprint and speed > move.WalkSpeed and cfg.SprintFieldOfView or cfg.FieldOfView
	fov = fov + (target - fov) * math.min(1, dt * 6)
	-- прицел сужает поле зрения (плавность — у самого прицела: alpha меняется за Aim.Time)
	camera.FieldOfView = fov + (aim.Fov - fov) * aim.Alpha
end

-- После камеры Roblox (она прячет весь персонаж вблизи): показываем таз и ноги, прячем остальное
local function postCamera()
	local character, humanoid = characters.GetCharacter()
	if not (character and humanoid) then
		return
	end
	local head = character:FindFirstChild("Head")
	local camera = workspace.CurrentCamera
	local firstPerson = head and (camera.CFrame.Position - head.Position).Magnitude < 2
	for _, d in ipairs(character:GetChildren()) do
		if d:IsA("BasePart") then
			if firstPerson then
				d.LocalTransparencyModifier = CameraController.HiddenParts[d.Name] and 1 or 0
			end
		elseif d:IsA("Accessory") and firstPerson then
			local handle = d:FindFirstChild("Handle")
			if handle then
				handle.LocalTransparencyModifier = 1
			end
		elseif d:IsA("Model") and d.Name == "Weapon" then
			-- своё оружие у плеча: от первого лица видно оружие в руках (Viewmodel), это — скрыто
			for _, p in ipairs(d:GetChildren()) do
				if p:IsA("BasePart") then
					p.LocalTransparencyModifier = firstPerson and 1 or 0
				end
			end
		end
	end
end

function CameraController.Init(context)
	characters = context.Get("CharacterController")
end

-- Первое лицо (обычная игра)
local function firstPersonMode(humanoid)
	local player = Players.LocalPlayer
	player.CameraMinZoomDistance = 0.5
	player.CameraMaxZoomDistance = 0.5
	player.CameraMode = Enum.CameraMode.LockFirstPerson
	if humanoid then
		workspace.CurrentCamera.CameraSubject = humanoid
	end
end

-- После смерти — камера от третьего лица смотрит на тело (видно, как оно падает), до возрождения
local function deathMode(character)
	local player = Players.LocalPlayer
	player.CameraMode = Enum.CameraMode.Classic
	player.CameraMaxZoomDistance = cfg.DeathCameraDistance
	player.CameraMinZoomDistance = cfg.DeathCameraDistance * 0.6
	local head = character:FindFirstChild("Head")
	if head then
		workspace.CurrentCamera.CameraSubject = head
	end
end

-- Живой упал (регдолл): камера держится за голову — тело кувыркается, а взгляд игрок ведёт сам
local function watchRagdoll(character, humanoid)
	character:GetAttributeChangedSignal("Ragdolled"):Connect(function()
		if humanoid.Health <= 0 then
			return
		end
		local head = character:FindFirstChild("Head")
		if character:GetAttribute("Ragdolled") == true and head then
			workspace.CurrentCamera.CameraSubject = head
		else
			workspace.CurrentCamera.CameraSubject = humanoid
		end
	end)
	humanoid.Died:Connect(function()
		deathMode(character)
	end)
end

function CameraController.Start()
	firstPersonMode(nil)
	workspace.CurrentCamera.FieldOfView = cfg.FieldOfView
	RunService:BindToRenderStep("DC_CameraOffset", Enum.RenderPriority.Camera.Value - 1, preCamera)
	RunService:BindToRenderStep("DC_BodyVisibility", Enum.RenderPriority.Camera.Value + 1, postCamera)
	characters.CharacterChanged:Connect(function(character, humanoid)
		bob.Amount, dip.Offset, dip.Speed, fallSpeed = 0, 0, 0, 0
		aim.Alpha = 0
		CameraController.ResetRecoil()
		firstPersonMode(humanoid)
		watchRagdoll(character, humanoid)
	end)
	local character, humanoid = characters.GetCharacter()
	if character and humanoid then
		watchRagdoll(character, humanoid)
	end
end

return CameraController
