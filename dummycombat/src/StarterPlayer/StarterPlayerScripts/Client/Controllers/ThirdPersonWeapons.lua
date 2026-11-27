-- ThirdPersonWeapons: как держат оружие другие игроки (на экране этого клиента).
--
-- Сервер даёт каждому персонажу оружие у плеча (Motor6D «RifleHold» от UpperTorso) и атрибуты: Weapon,
-- AimPitch (куда смотрит вверх-вниз), Aiming, Sprinting, Reloading (время начала по часам сервера),
-- ReloadKind. Здесь каждый кадр — после анимаций и до физики (RunService.PreSimulation), поверх
-- шагов и бега из Animate:
--   • корпус развёрнут в «боевую стойку» (Twist) и наклонён за взглядом; голова смотрит вперёд;
--   • оружие — в позе Ready / Aim / Sprint / Reload (Configs/WeaponPoses.ThirdPerson), плавно;
--   • руки по ИК (Shared/ArmIK) держат рукоять и цевьё; при перезарядке левая рука уносит и приносит
--     магазин, при пустом — правая передёргивает затвор (те же ключи, что у вида от первого лица).
-- Всё это — Motor6D.Transform: ничего не уходит на сервер и не мешает регдоллу (он выключает суставы).
-- Дальше ThirdPersonRange — без ИК (персонаж далеко, разница не видна).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Configs = ReplicatedStorage:WaitForChild("Configs")
local ArmIK = require(Shared:WaitForChild("ArmIK"))
local WeaponAnim = require(Shared:WaitForChild("WeaponAnim"))
local WeaponPoses = require(Configs:WaitForChild("WeaponPoses"))
local WeaponConfig = require(Configs:WaitForChild("WeaponConfig"))

local ThirdPersonWeapons = { Name = "ThirdPersonWeapons" }

local cameraCtl = nil
local cache = setmetatable({}, { __mode = "k" })
local range = WeaponConfig.Effects.ThirdPersonRange

local function motor(character, partName, name)
	local part = character:FindFirstChild(partName)
	local m = part and part:FindFirstChild(name)
	return (m and m:IsA("Motor6D")) and m or nil
end

local function collect(character)
	local gun = character:FindFirstChild("Weapon")
	local body = gun and gun.PrimaryPart
	local hold = body and body:FindFirstChild("RifleHold")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not (hold and humanoid) then
		return nil
	end
	local data = {
		Gun = gun,
		Hold = hold,
		Humanoid = humanoid,
		Root = character:FindFirstChild("HumanoidRootPart"),
		Waist = motor(character, "UpperTorso", "Waist"),
		Neck = motor(character, "Head", "Neck"),
		Mag = gun:FindFirstChild("Magazine") and gun.Magazine:FindFirstChild("MagJoint"),
		Bolt = gun:FindFirstChild("ChargingHandle") and gun.ChargingHandle:FindFirstChild("BoltJoint"),
		Arms = {},
		Aim = 0,
		Sprint = 0,
		Base = {},
		Last = {},
	}
	for _, side in ipairs({ "Right", "Left" }) do
		local arm = {
			Shoulder = motor(character, side .. "UpperArm", side .. "Shoulder"),
			Elbow = motor(character, side .. "LowerArm", side .. "Elbow"),
			Wrist = motor(character, side .. "Hand", side .. "Wrist"),
		}
		if not (arm.Shoulder and arm.Elbow and arm.Wrist) then
			return nil
		end
		data.Arms[side] = arm
	end
	return data
end

ThirdPersonWeapons.Collect = function(character)
	return collect(character)
end

-- Добавить поворот extra поверх позы анимации. Если в этом кадре аниматор сустав не перезаписал (там
-- осталось наше прошлое значение), берём прошлую позу анимации — иначе поворот копился бы каждый кадр
local function overlay(data, key, m, extra)
	local current = m.Transform
	local base = current
	if data.Last[key] ~= nil and current == data.Last[key] then
		base = data.Base[key]
	end
	local out = base * extra
	data.Base[key], data.Last[key] = base, out
	m.Transform = out
end

local function approach(value, target, rate, dt)
	if value < target then
		return math.min(target, value + rate * dt)
	end
	return math.max(target, value - rate * dt)
end

-- Поставить оружие и руки персонажа (data — из collect). Возвращает true, если поставлено
function ThirdPersonWeapons.Pose(character, data, dt, serverTime, withArms)
	local name = character:GetAttribute("Weapon")
	local poses = WeaponPoses[name]
	if not poses then
		return false
	end
	local tp = poses.ThirdPerson
	data.Aim = approach(data.Aim, character:GetAttribute("Aiming") == true and 1 or 0, 1 / 0.18, dt)
	data.Sprint = approach(data.Sprint, character:GetAttribute("Sprinting") == true and 1 or 0, 1 / 0.22, dt)
	local rl = nil
	local started = character:GetAttribute("Reloading")
	local kind = character:GetAttribute("ReloadKind")
	if type(started) == "number" and started > 0 and poses.Reloads[kind] then
		local t = serverTime - started
		if t >= 0 and t < WeaponAnim.Length(poses, kind) then
			rl = WeaponAnim.Reload(poses, kind, t)
		end
	end
	-- корпус: стойка и наклон за взглядом (на бегу — почти без наклона)
	local pitch = math.rad(math.clamp(character:GetAttribute("AimPitch") or 0, -80, 80))
	local bend = pitch * (1 - 0.8 * data.Sprint)
	if data.Waist then
		overlay(data, "Waist", data.Waist, CFrame.Angles(bend * 0.85, 0, 0) * CFrame.Angles(0, tp.Twist, 0))
	end
	if data.Neck then
		overlay(data, "Neck", data.Neck, CFrame.Angles(0, -tp.Twist, 0) * CFrame.Angles(bend * 0.15, 0, 0))
	end
	-- оружие
	local P = tp.Poses
	local hold = P.Ready:Lerp(P.Aim, WeaponAnim.Smooth(data.Aim))
	if data.Sprint > 0 then
		hold = hold:Lerp(P.Sprint, WeaponAnim.Smooth(data.Sprint))
	end
	if rl then
		hold = hold:Lerp(P.Reload, rl.Gun)
	end
	data.Hold.Transform = data.Hold.C0:Inverse() * hold
	local hands = poses.Hands
	local rightT = hold * (rl and rl.Right or hands.Right)
	local leftT = hold * (rl and rl.Left or hands.Left)
	if data.Mag then
		if rl and rl.MagInHand then
			local magT = hold:Inverse() * leftT * WeaponAnim.MagOffsetInHand(poses)
			data.Mag.Transform = data.Mag.C0:Inverse() * magT
		else
			data.Mag.Transform = CFrame.identity
		end
	end
	if data.Bolt then
		data.Bolt.Transform = CFrame.new(0, 0, poses.ChargeTravel * (rl and rl.Charge or 0))
	end
	if withArms then
		for side, arm in pairs(data.Arms) do
			local upper, lower, hand = ArmIK.Solve(side, ArmIK.Dims[side].ShoulderTorso, side == "Right" and rightT or leftT, tp.Poles[side])
			arm.Shoulder.Transform, arm.Elbow.Transform, arm.Wrist.Transform = ArmIK.MotorTransforms(arm, upper, lower, hand)
		end
	end
	return true
end

local function step(dt)
	local camera = workspace.CurrentCamera
	local camPos = camera.CFrame.Position
	local serverTime = workspace:GetServerTimeNow()
	local localPlayer = Players.LocalPlayer
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		if character and character.Parent and (character:GetAttribute("Weapon") or "") ~= "" then
			local skip = character:GetAttribute("Ragdolled") == true
			if player == localPlayer and cameraCtl.IsFirstPerson() then
				skip = true -- своё оружие от первого лица рисует Viewmodel
			end
			if not skip then
				local data = cache[character]
				if not data or data.Gun.Parent ~= character then
					data = collect(character)
					cache[character] = data
				end
				if data and data.Humanoid.Health > 0 and data.Root then
					local near = (data.Root.Position - camPos).Magnitude <= range
					ThirdPersonWeapons.Pose(character, data, dt, serverTime, near)
				end
			end
		end
	end
end

function ThirdPersonWeapons.Init(context)
	cameraCtl = context.Get("CameraController")
end

function ThirdPersonWeapons.Start()
	RunService.PreSimulation:Connect(step)
end

return ThirdPersonWeapons
