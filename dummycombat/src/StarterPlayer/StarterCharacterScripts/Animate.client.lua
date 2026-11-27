-- Animate: анимации своего манекена (заменяет стандартный скрипт Roblox с тем же именем).
-- Анимации, которые клиент играет своему персонажу, Roblox сам передаёт остальным игрокам.
--
-- Все циклы походки играют одновременно, а видно то, у чего больше вес. Веса считаются каждый кадр по
-- настоящей скорости персонажа относительно его взгляда:
--   • вперёд/назад — WalkF (назад — та же анимация, проигранная в обратную сторону), бег — RunF;
--   • вбок — WalkL / WalkR, по диагонали — смесь;
--   • в приседе — CrouchF / CrouchL / CrouchR / CrouchIdle (присед узнаётся по HipHeight — значит, и
--     плавный переход виден);
--   • темп каждого цикла = скорость / «родная» скорость анимации: шаг совпадает с движением, ноги не скользят.
-- Прыжок, падение, приземление (сила — по скорости падения) и лазание — по состоянию Humanoid.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Configs = ReplicatedStorage:WaitForChild("Configs")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local DummyAssets = require(Configs:WaitForChild("DummyAssets"))
local GameConfig = require(Configs:WaitForChild("GameConfig"))
local MovementRules = require(Shared:WaitForChild("MovementRules"))

local character = script.Parent
local humanoid = character:WaitForChild("Humanoid")
local root = character:WaitForChild("HumanoidRootPart")
local animator = humanoid:WaitForChild("Animator")

local move = GameConfig.Movement
local LOOPS = { "Idle", "WalkF", "WalkL", "WalkR", "RunF", "CrouchIdle", "CrouchF", "CrouchL", "CrouchR", "Fall", "Climb" }
local SMOOTH = 12 -- как быстро веса догоняют цель (1/с)

local tracks, weights = {}, {}
for name, def in pairs(DummyAssets.Animations) do
	local anim = Instance.new("Animation")
	anim.Name = name
	anim.AnimationId = def.Id
	local ok, track = pcall(animator.LoadAnimation, animator, anim)
	if ok and track then
		track.Looped = def.Loop
		tracks[name] = track
	else
		warn("[DC C][WARN][Animate] не загрузилась анимация " .. name .. ": " .. tostring(track))
	end
end
for _, name in ipairs(LOOPS) do
	local t = tracks[name]
	if t then
		t:Play(0, 0.0001, 1)
		weights[name] = 0
	end
end

local airborne, climbing, dead = false, false, false
local fallSpeed = 0

local function playOnce(name, weight, fade)
	local t = tracks[name]
	if t then
		t:Play(fade or 0.06, math.clamp(weight or 1, 0.05, 1), 1)
	end
end

humanoid.StateChanged:Connect(function(_, new)
	local S = Enum.HumanoidStateType
	if new == S.Jumping then
		airborne = true
		playOnce("Jump", 1, 0.05)
	elseif new == S.Freefall then
		airborne = true
	elseif new == S.Landed or new == S.Running or new == S.RunningNoPhysics then
		if airborne then
			local impact = math.clamp((-fallSpeed - 8) / 40, 0, 1)
			if impact > 0 then
				playOnce("Land", 0.35 + 0.65 * impact, 0.04)
			end
		end
		airborne, fallSpeed = false, 0
	elseif new == S.Climbing then
		climbing = true
	elseif new == S.Dead then
		dead = true
	end
	if new ~= S.Climbing then
		climbing = false
	end
end)

-- Целевые веса и темп каждого цикла для текущего движения
local function targets()
	local want, speeds = {}, {}
	for _, name in ipairs(LOOPS) do
		want[name] = 0
		speeds[name] = 1
	end
	if dead then
		return want, speeds
	end
	local vel = root.AssemblyLinearVelocity
	if climbing then
		want.Climb = 1
		speeds.Climb = math.clamp(math.abs(vel.Y) / 8, 0.2, 1.6) * (vel.Y >= 0 and 1 or -1)
		return want, speeds
	end
	if airborne then
		fallSpeed = math.min(fallSpeed, vel.Y)
		want.Fall = 1
		return want, speeds
	end
	local crouched = MovementRules.IsCrouchedHip(humanoid.HipHeight)
	local flat = Vector3.new(vel.X, 0, vel.Z)
	local speed = flat.Magnitude
	local idle = crouched and "CrouchIdle" or "Idle"
	local k = math.clamp((speed - 0.4) / 1.6, 0, 1) -- 0 — стоит, 1 — идёт
	want[idle] = 1 - k
	if k <= 0 then
		return want, speeds
	end
	local loc = root.CFrame:VectorToObjectSpace(flat)
	local f, r = -loc.Z / speed, loc.X / speed
	local wf, wr = math.abs(f), math.abs(r)
	local sum = math.max(1e-3, wf + wr)
	wf, wr = wf / sum, wr / sum
	local set = crouched and { F = "CrouchF", L = "CrouchL", R = "CrouchR" } or { F = "WalkF", L = "WalkL", R = "WalkR" }
	local run = 0
	if not crouched and f > 0.5 then
		run = math.clamp((speed - move.WalkSpeed - 1) / math.max(1, move.SprintSpeed - move.WalkSpeed - 2), 0, 1)
	end
	local anims = DummyAssets.Animations
	want[set.F] = wf * k * (1 - run)
	speeds[set.F] = (f >= 0 and 1 or -1) * speed / anims[set.F].Natural
	want.RunF = wf * k * run
	speeds.RunF = speed / anims.RunF.Natural
	local side = r >= 0 and set.R or set.L
	want[side] = wr * k
	speeds[side] = speed / anims[side].Natural
	return want, speeds
end

RunService.Heartbeat:Connect(function(dt)
	if not character.Parent then
		return
	end
	local want, speeds = targets()
	local a = math.min(1, dt * SMOOTH)
	for _, name in ipairs(LOOPS) do
		local t = tracks[name]
		if t then
			local w = weights[name] + (want[name] - weights[name]) * a
			weights[name] = w
			t:AdjustWeight(math.max(w, 0.0001), 0)
			t:AdjustSpeed(speeds[name])
		end
	end
end)
