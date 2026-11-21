-- Animate (LocalScript в StarterPlayer.StarterCharacterScripts): собственные анимации персонажа игрока.
-- Скрипт с именем «Animate» заменяет стандартный скрипт анимаций Roblox.
-- Ходьба, бег и ожидание сделаны для NIGHT SHIFT (tools/make_anims.py, ID — в Shared/Models.Anim).
-- Темп шага подстраивается под скорость, чтобы ноги не скользили. Анимации, запущенные игроком
-- для своего персонажа, Roblox сам показывает остальным игрокам.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Models = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Models"))
local ANIM = Models.Anim

local character = script.Parent
local humanoid = character:WaitForChild("Humanoid")
local root = character:WaitForChild("HumanoidRootPart")
local animator = humanoid:FindFirstChildOfClass("Animator") or humanoid:WaitForChild("Animator", 5)
if not animator then
	animator = Instance.new("Animator")
	animator.Parent = humanoid
end

local function load(id, priority)
	local a = Instance.new("Animation")
	a.AnimationId = id
	local ok, track = pcall(function()
		return animator:LoadAnimation(a)
	end)
	if ok and track then
		track.Looped = true
		track.Priority = priority
		return track
	end
	return nil
end

local idle = load(ANIM.Idle, Enum.AnimationPriority.Idle)
local walk = load(ANIM.Walk, Enum.AnimationPriority.Movement)
local run = load(ANIM.Run, Enum.AnimationPriority.Movement)
if idle then
	idle:Play(0.2)
end

local function heightScale()
	local v = humanoid:FindFirstChild("BodyHeightScale")
	return (v and v:IsA("NumberValue") and v.Value > 0) and v.Value or 1
end

local current = nil
local AIR = {
	[Enum.HumanoidStateType.Freefall] = true,
	[Enum.HumanoidStateType.Jumping] = true,
	[Enum.HumanoidStateType.FallingDown] = true,
}

RunService.Heartbeat:Connect(function()
	if humanoid.Health <= 0 then
		return
	end
	local v = root.AssemblyLinearVelocity
	local speed = Vector3.new(v.X, 0, v.Z).Magnitude
	local moving = speed > 0.8 and humanoid.MoveDirection.Magnitude > 0.05 and not AIR[humanoid:GetState()]
	local want, rate = nil, 1
	if moving then
		local hs = heightScale()
		if speed >= ANIM.RunFrom and run then
			want, rate = run, math.clamp(speed / (ANIM.RunNatural * hs), 0.7, 1.5)
		else
			want, rate = walk, math.clamp(speed / (ANIM.WalkNatural * hs), 0.45, 1.6)
		end
	end
	if want ~= current then
		if current then
			current:Stop(0.25)
		end
		if want then
			want:Play(0.25)
		end
		current = want
	end
	if want then
		want:AdjustSpeed(rate)
	end
end)
