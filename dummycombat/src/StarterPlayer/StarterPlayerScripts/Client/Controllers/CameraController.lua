-- CameraController: камера от первого лица.
--
-- Камеру ведёт стандартный модуль Roblox в режиме LockFirstPerson (мышь, геймпад и сенсорный экран
-- работают как привычно, чувствительность — из настроек Roblox у игрока). Поверх него:
--   • точка камеры — на уровне глаз манекена и чуть впереди головы (Humanoid.CameraOffset);
--   • в приседе камера опускается вместе с персонажем (плавно: присед меняет HipHeight постепенно);
--   • лёгкое покачивание в такт шагам (сильнее на бегу, слабее в приседе, в воздухе нет);
--   • просадка камеры при приземлении с высоты;
--   • поле зрения на бегу чуть шире;
--   • свой манекен: голова, грудь и руки скрыты (не мешают обзору; руки с оружием — этап 4), а таз и
--     ноги видно, если посмотреть вниз.
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
	if not (humanoid and root and humanoid.Health > 0) then
		return
	end
	local st = characters.GetState()
	-- покачивание
	local vel = root.AssemblyLinearVelocity
	local speed = Vector3.new(vel.X, 0, vel.Z).Magnitude
	local grounded = humanoid.FloorMaterial ~= Enum.Material.Air
	local scale = st.Sprint and cfg.SprintBobScale or (st.Stance == "Crouch" and cfg.CrouchBobScale or 1)
	local want = (cfg.HeadBob and grounded) and math.clamp(speed / move.WalkSpeed, 0, 1.6) * scale or 0
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
	camera.FieldOfView = fov
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
		end
	end
end

function CameraController.Init(context)
	characters = context.Get("CharacterController")
end

function CameraController.Start()
	Players.LocalPlayer.CameraMode = Enum.CameraMode.LockFirstPerson
	workspace.CurrentCamera.FieldOfView = cfg.FieldOfView
	RunService:BindToRenderStep("DC_CameraOffset", Enum.RenderPriority.Camera.Value - 1, preCamera)
	RunService:BindToRenderStep("DC_BodyVisibility", Enum.RenderPriority.Camera.Value + 1, postCamera)
	characters.CharacterChanged:Connect(function()
		bob.Amount, dip.Offset, dip.Speed, fallSpeed = 0, 0, 0, 0
	end)
end

return CameraController
