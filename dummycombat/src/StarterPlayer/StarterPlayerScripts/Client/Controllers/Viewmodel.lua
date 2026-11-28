-- Viewmodel: оружие и руки в виде от первого лица (видит только этот игрок).
--
-- Модель — копия оружия из ReplicatedStorage.Assets.Weapons и предплечья с кистями своего манекена; всё
-- закреплено (Anchored), не сталкивается, лучи сквозь неё проходят, теней не отбрасывает. Каждый кадр после
-- камеры детали ставятся одним вызовом BulkMoveTo:
--   • поза оружия — смесь поз из Configs/WeaponPoses: от бедра (Hip), у глаза (Aim), бег (Sprint), достать
--     (Equip), перезарядка (Reload — по ключам Shared/WeaponAnim: магазин уходит в левую руку и обратно,
--     при пустом магазине правая рука передёргивает затвор);
--   • сверху — покачивание при ходьбе, инерция при повороте взгляда (оружие чуть отстаёт), дыхание,
--     отдача (толчок назад и вверх, пружиной), рукоять затвора ходит при каждом выстреле;
--   • руки — по ИК (Shared/ArmIK) от «плеч» у камеры к кистям на оружии.
-- Состояние (прицел, бег, перезарядка…) задаёт WeaponController через SetInput.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Configs = ReplicatedStorage:WaitForChild("Configs")
local Logger = require(Shared:WaitForChild("Logger"))
local ArmIK = require(Shared:WaitForChild("ArmIK"))
local WeaponAnim = require(Shared:WaitForChild("WeaponAnim"))
local WeaponPoses = require(Configs:WaitForChild("WeaponPoses"))
local WeaponModels = require(Configs:WaitForChild("WeaponModels"))
local WeaponConfig = require(Configs:WaitForChild("WeaponConfig"))

local Viewmodel = { Name = "Viewmodel" }

local log = Logger.new("Viewmodel")
local effects = nil
local vm = nil
local ARM_PARTS = { "RightLowerArm", "RightHand", "LeftLowerArm", "LeftHand" }

local input = { Aim = 0, Sprint = 0, Equip = 1, Reload = nil, Speed = 0, Grounded = true, Visible = false }
local recoil = { Back = 0, BackVel = 0, Rot = 0, RotVel = 0, Up = 0, UpVel = 0, Roll = 0, RollVel = 0 }
local sway = { X = 0, Y = 0, VX = 0, VY = 0, LastYaw = nil, LastPitch = nil }
local bob = { Phase = 0, Amount = 0 }
local boltCycle = 0
local breath = 0

function Viewmodel.SetInput(t)
	for k, v in pairs(t) do
		input[k] = v
	end
end

function Viewmodel.Muzzle()
	return vm and vm.Muzzle
end

function Viewmodel.Eject()
	return vm and vm.Eject
end

function Viewmodel.Exists()
	return vm ~= nil
end

-- Отдача одного выстрела (в руках): толчок назад, подброс, поворот вверх; затвор отходит и возвращается
function Viewmodel.Kick(def, aimAlpha)
	local r = def.Recoil
	local k = 1 - 0.45 * aimAlpha
	recoil.BackVel = recoil.BackVel + r.KickBack * 38 * k
	recoil.UpVel = recoil.UpVel + r.KickUp * 30 * k
	recoil.RotVel = recoil.RotVel + math.rad(r.KickRotate) * 30 * k
	recoil.RollVel = recoil.RollVel + (math.random() - 0.5) * 0.6 * k
	if not def.BoltAction then
		boltCycle = 1 -- затвор (у пистолета — кожух) отходит и возвращается; у снайперской — рукой (поза Cycle)
	end
end

function Viewmodel.Destroy()
	if vm then
		vm.Model:Destroy()
		vm = nil
	end
end

-- Собрать модель из оружия weaponName и рук персонажа character
function Viewmodel.Build(character, weaponName)
	Viewmodel.Destroy()
	weaponName = weaponName or WeaponConfig.Default
	local assets = ReplicatedStorage:WaitForChild("Assets", 10)
	local folder = assets and assets:WaitForChild("Weapons", 20)
	local template = folder and folder:WaitForChild(weaponName, 20)
	if not template then
		log:Error("нет модели оружия %s — вид от первого лица без оружия", tostring(weaponName))
		return false
	end
	local model = Instance.new("Model")
	model.Name = "Viewmodel"
	local gun = template:Clone()
	gun.Name = "Weapon"
	for _, d in ipairs(gun:GetDescendants()) do
		if d:IsA("Motor6D") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.CastShadow = false
		end
	end
	gun.Parent = model
	local arms = {}
	for _, name in ipairs(ARM_PARTS) do
		local src = character:FindFirstChild(name)
		if src and src:IsA("BasePart") then
			local p = src:Clone()
			p:ClearAllChildren()
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.CastShadow = false
			p.Massless = true
			p.LocalTransparencyModifier = 0
			p.Transparency = 0
			p.Parent = model
			arms[name] = p
		end
	end
	local body = gun.PrimaryPart
	vm = {
		Model = model,
		Weapon = weaponName,
		Poses = WeaponPoses[weaponName],
		Geo = WeaponModels[weaponName],
		Body = body,
		Mag = gun:FindFirstChild("Magazine"),
		Bolt = gun:FindFirstChild("ChargingHandle"),
		Muzzle = body:FindFirstChild("Muzzle"),
		Eject = body:FindFirstChild("Eject"),
		Arms = arms,
	}
	vm.MagInHand = WeaponAnim.MagOffsetInHand(vm.Poses)
	effects.Rig(gun, 0.8)
	model.Parent = nil
	return true
end

-- Пружина: x'' = k(цель − x) − d·x' (несколько маленьких шагов — устойчиво и при низком FPS)
local function spring(pos, vel, target, k, d, dt)
	local steps = math.max(1, math.ceil(dt / (1 / 120)))
	local h = dt / steps
	for _ = 1, steps do
		vel = vel + (k * (target - pos) - d * vel) * h
		pos = pos + vel * h
	end
	return pos, vel
end

local function ease(t)
	return WeaponAnim.Smooth(t)
end

local function angles(look)
	return math.atan2(-look.X, -look.Z), math.asin(math.clamp(look.Y, -1, 1))
end

local function wrap(a)
	return (a + math.pi) % (2 * math.pi) - math.pi
end

local function update(dt)
	if not vm then
		return
	end
	local camera = workspace.CurrentCamera
	local visible = input.Visible
	if not visible then
		if vm.Model.Parent then
			vm.Model.Parent = nil
		end
		sway.LastYaw = nil
		return
	end
	if vm.Model.Parent ~= camera then
		vm.Model.Parent = camera
	end
	dt = math.min(dt, 0.1)
	local P = vm.Poses.Viewmodel.Poses
	local aim = ease(input.Aim)
	-- поза
	local pose = P.Hip:Lerp(P.Aim, aim)
	if input.Sprint > 0 then
		pose = pose:Lerp(P.Sprint, ease(input.Sprint))
	end
	local rl = nil
	-- при смене оружия модель пересобирается не сразу: ключи чужого оружия не применяем
	if input.Reload and vm.Poses.Reloads[input.Reload.Kind] then
		rl = WeaponAnim.Reload(vm.Poses, input.Reload.Kind, input.Reload.T)
		pose = pose:Lerp(P.Reload, rl.Gun)
	end
	if input.Equip < 1 then
		pose = P.Equip:Lerp(pose, ease(input.Equip))
	end
	-- инерция взгляда: оружие отстаёт от поворота камеры
	local yaw, pitch = angles(camera.CFrame.LookVector)
	local dYaw, dPitch = 0, 0
	if sway.LastYaw then
		dYaw, dPitch = wrap(yaw - sway.LastYaw), pitch - sway.LastPitch
	end
	sway.LastYaw, sway.LastPitch = yaw, pitch
	local swayScale = 1 - 0.75 * aim
	local tx = math.clamp(-dPitch / math.max(dt, 1e-3) * 0.012, -0.07, 0.07) * swayScale
	local ty = math.clamp(-dYaw / math.max(dt, 1e-3) * 0.014, -0.09, 0.09) * swayScale
	sway.X, sway.VX = spring(sway.X, sway.VX, tx, 140, 18, dt)
	sway.Y, sway.VY = spring(sway.Y, sway.VY, ty, 140, 18, dt)
	-- покачивание шагов и дыхание
	local moving = input.Grounded and input.Speed > 1
	local want = moving and math.clamp(input.Speed / 12, 0, 1.6) or 0
	bob.Amount = bob.Amount + (want - bob.Amount) * math.min(1, dt * 8)
	bob.Phase = bob.Phase + dt * input.Speed / 4 * math.pi
	breath = breath + dt
	local bobScale = bob.Amount * (1 - 0.85 * aim)
	local breathScale = 1 - 0.7 * aim
	local bobCF = CFrame.new(
		math.sin(bob.Phase) * 0.03 * bobScale,
		-math.abs(math.cos(bob.Phase)) * 0.025 * bobScale + math.sin(breath * 1.6) * 0.006 * breathScale,
		0
	) * CFrame.Angles(0, 0, math.sin(bob.Phase) * 0.02 * bobScale)
	-- отдача: пружины к нулю
	recoil.Back, recoil.BackVel = spring(recoil.Back, recoil.BackVel, 0, 420, 30, dt)
	recoil.Up, recoil.UpVel = spring(recoil.Up, recoil.UpVel, 0, 300, 24, dt)
	recoil.Rot, recoil.RotVel = spring(recoil.Rot, recoil.RotVel, 0, 260, 22, dt)
	recoil.Roll, recoil.RollVel = spring(recoil.Roll, recoil.RollVel, 0, 200, 20, dt)
	local grip = vm.Geo.Points.GripRight
	local recoilCF = CFrame.new(0, recoil.Up, recoil.Back) * CFrame.new(grip) * CFrame.Angles(recoil.Rot, 0, recoil.Roll) * CFrame.new(-grip)
	boltCycle = math.max(0, boltCycle - dt / 0.07)

	local cam = camera.CFrame
	local gunCF = cam * bobCF * CFrame.Angles(sway.X, sway.Y, sway.Y * 0.5) * pose * recoilCF
	local parts, frames = { vm.Body }, { gunCF }
	-- магазин: в оружии или в левой руке
	local hands = vm.Poses.Hands
	local rightCF = gunCF * (rl and rl.Right or hands.Right)
	local leftCF = gunCF * (rl and rl.Left or hands.Left)
	if vm.Mag then
		table.insert(parts, vm.Mag)
		table.insert(frames, (rl and rl.MagInHand) and leftCF * vm.MagInHand or gunCF * CFrame.new(vm.Poses.Magazine))
	end
	if vm.Bolt then
		local travel = vm.Poses.ChargeTravel * math.max(rl and rl.Charge or 0, math.sin(boltCycle * math.pi) * 0.9)
		table.insert(parts, vm.Bolt)
		table.insert(frames, gunCF * CFrame.new(vm.Geo.Parts.ChargingHandle.Offset + Vector3.new(0, 0, travel)))
	end
	-- руки
	local vmPoses = vm.Poses.Viewmodel
	for _, side in ipairs({ "Right", "Left" }) do
		local lower, hand = vm.Arms[side .. "LowerArm"], vm.Arms[side .. "Hand"]
		if lower and hand then
			local shoulder = cam:PointToWorldSpace(vmPoses.Shoulders[side])
			local pole = cam:VectorToWorldSpace(vmPoses.Poles[side])
			local _, lowerCF, handCF = ArmIK.Solve(side, shoulder, side == "Right" and rightCF or leftCF, pole)
			table.insert(parts, lower)
			table.insert(frames, lowerCF)
			table.insert(parts, hand)
			table.insert(frames, handCF)
		end
	end
	workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
end

-- Для проверки без клиента (tests/stage4): один кадр
Viewmodel.Step = update

-- Детали модели (для проверки): Body, Mag, Bolt, Arms
function Viewmodel.Parts()
	return vm
end

function Viewmodel.Init(context)
	effects = context.Get("WeaponEffects")
end

function Viewmodel.Start()
	-- после камеры Roblox и после CameraController (он на Camera ± 1)
	RunService:BindToRenderStep("DC_Viewmodel", Enum.RenderPriority.Camera.Value + 2, update)
	Players.LocalPlayer.CharacterRemoving:Connect(function()
		Viewmodel.Destroy()
	end)
end

return Viewmodel
