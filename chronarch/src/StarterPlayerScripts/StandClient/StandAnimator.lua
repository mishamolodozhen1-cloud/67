-- Процедурная анимация всех стендов на этом клиенте.
-- Сервер выставляет атрибут State, а клиент плавно ведёт суставы (C0 у Motor6D),
-- двигает стенд относительно хозяина и рисует призрачные руки во время барража.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local StandAnimator = {}

local rad = math.rad
local TAU = math.pi * 2
local V = Vector3.new

local records = {}
local swishPlayer = nil -- функция из Effects, проигрывает свист кулака

-------------------------------------------------------------------------------
-- Позы. Углы в градусах (X, Y, Z) для каждого сустава.
-- +X поднимает руку вперёд, +Z отводит правую руку наружу, +Y поворачивает влево.
-------------------------------------------------------------------------------
local function poseIdle(t)
	local b = math.sin(t * 1.6)
	return {
		Hips = V(-4 + b * 1.2, math.sin(t * 0.4) * 4, 0),
		Spine = V(2 + b * 1.5, 0, 0),
		Neck = V(5 - b, math.sin(t * 0.5) * 6, 0),
		RShoulder = V(10 + b * 2, 0, 14),
		RElbow = V(28, 0, 0),
		RWrist = V(0, 0, 0),
		LShoulder = V(10 + b * 2, 0, -14),
		LElbow = V(28, 0, 0),
		LWrist = V(0, 0, 0),
		RHip = V(10, 0, 4),
		RKnee = V(-26, 0, 0),
		RAnkle = V(-22, 0, 0),
		LHip = V(3, 0, -4),
		LKnee = V(-14, 0, 0),
		LAnkle = V(-18, 0, 0),
	}
end

local function punch(phase)
	return (math.sin(phase * TAU) + 1) / 2
end

local function poseBarrage(t)
	local f = 9
	local eR = punch(t * f)
	local eL = punch(t * f + 0.5)
	local jR = math.noise(t * 7, 1.3) * 14
	local jL = math.noise(t * 7, 2.7) * 14
	return {
		Hips = V(-14, math.sin(t * f * TAU) * 6, 0),
		Spine = V(-6, 0, 0),
		Neck = V(12, 0, 0),
		RShoulder = V(45 + eR * 50 + jR * 0.4, 8 + jR * 0.5, 4),
		RElbow = V(105 - eR * 100, 0, 0),
		RWrist = V(0, 0, 0),
		LShoulder = V(45 + eL * 50 + jL * 0.4, -8 - jL * 0.5, -4),
		LElbow = V(105 - eL * 100, 0, 0),
		LWrist = V(0, 0, 0),
		RHip = V(-12, 0, 12),
		RKnee = V(-20, 0, 0),
		RAnkle = V(-10, 0, 0),
		LHip = V(28, 0, -8),
		LKnee = V(-38, 0, 0),
		LAnkle = V(-12, 0, 0),
	}
end

local function poseFinisher()
	return {
		Hips = V(-16, 28, 0),
		Spine = V(-4, 8, 0),
		Neck = V(8, -26, 0),
		RShoulder = V(96, 14, 0),
		RElbow = V(0, 0, 0),
		RWrist = V(0, 0, 0),
		LShoulder = V(-25, 0, -12),
		LElbow = V(95, 0, 0),
		LWrist = V(0, 0, 0),
		RHip = V(-18, 0, 10),
		RKnee = V(-12, 0, 0),
		RAnkle = V(-8, 0, 0),
		LHip = V(34, 0, -6),
		LKnee = V(-44, 0, 0),
		LAnkle = V(-10, 0, 0),
	}
end

local function poseTimeStop(t)
	local b = math.sin(t * 3) * 2
	return {
		Hips = V(8, 0, 0),
		Spine = V(10 + b, 0, 0),
		Neck = V(18, 0, 0),
		RShoulder = V(18, 0, 98 + b),
		RElbow = V(38, 0, 0),
		RWrist = V(0, 0, 18),
		LShoulder = V(18, 0, -98 - b),
		LElbow = V(38, 0, 0),
		LWrist = V(0, 0, -18),
		RHip = V(2, 0, 12),
		RKnee = V(-8, 0, 0),
		RAnkle = V(-24, 0, 0),
		LHip = V(2, 0, -12),
		LKnee = V(-8, 0, 0),
		LAnkle = V(-24, 0, 0),
	}
end

local POSES = {
	idle = poseIdle,
	barrage = poseBarrage,
	finisher = poseFinisher,
	timestop = poseTimeStop,
	vanish = poseIdle,
}

-------------------------------------------------------------------------------
-- Призрачные руки для барража (только локально, в Camera).
-------------------------------------------------------------------------------
local function ghostPart(size, transparency)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = Color3.fromRGB(230, 176, 70)
	p.Size = size
	p.Transparency = transparency
	p.Parent = workspace.CurrentCamera
	return p
end

local function makeGhosts(rec)
	rec.ghosts = {}
	for i = 1, 6 do
		local side = (i % 2 == 0) and 1 or -1
		table.insert(rec.ghosts, {
			arm = ghostPart(V(0.42, 0.42, 2), 0.7),
			fist = ghostPart(V(0.66, 0.66, 0.66), 0.6),
			ox = side * (0.5 + math.random() * 1.4),
			oy = 0.5 + math.random() * 1.9,
			phase = math.random(),
			speed = 7 + math.random() * 5,
		})
	end
end

local function clearGhosts(rec)
	if rec.ghosts then
		for _, g in ipairs(rec.ghosts) do
			g.arm:Destroy()
			g.fist:Destroy()
		end
		rec.ghosts = nil
	end
end

local function updateGhosts(rec, t)
	local torso = rec.torso
	if not torso or not rec.ghosts then
		return
	end
	local base = torso.CFrame
	local look = base.LookVector
	for _, g in ipairs(rec.ghosts) do
		local e = punch(t * g.speed + g.phase)
		local shoulder = base * V(g.ox, g.oy - 0.3, -0.2)
		local fistPos = shoulder + look * (0.6 + e * 3.4) - base.RightVector * (g.ox * 0.3 * e)
		local diff = fistPos - shoulder
		local len = math.max(diff.Magnitude, 0.2)
		g.arm.Size = V(0.42, 0.42, len)
		g.arm.CFrame = CFrame.lookAt(shoulder + diff / 2, fistPos)
		g.fist.CFrame = CFrame.lookAt(fistPos, fistPos + diff)
		g.arm.Transparency = 0.86 - e * 0.3
		g.fist.Transparency = 0.8 - e * 0.35
	end
end

-------------------------------------------------------------------------------
-- Учёт стендов
-------------------------------------------------------------------------------
local function setFade(rec, alpha)
	for _, p in ipairs(rec.parts) do
		p.LocalTransparencyModifier = 1 - alpha
	end
end

local function track(model)
	if records[model] then
		return
	end
	local root = model:WaitForChild("Root", 5)
	if not root then
		return
	end
	local rec = {
		model = model,
		root = root,
		torso = model:WaitForChild("Torso", 5),
		joints = {},
		parts = {},
		trails = {},
		t = 0,
		fade = 0,
		halo = 0,
		swishTimer = 0,
		owner = Players:GetPlayerByUserId(model:GetAttribute("Owner") or 0),
	}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Motor6D") then
			rec.joints[d.Name] = { motor = d, base = d.C0, cur = V(0, 0, 0) }
		elseif d:IsA("BasePart") and d.Transparency < 1 then
			table.insert(rec.parts, d)
		elseif d:IsA("Trail") then
			table.insert(rec.trails, d)
		end
	end
	rec.anchor = root:WaitForChild("Anchor", 5)
	setFade(rec, 0)
	records[model] = rec
	model.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			clearGhosts(rec)
			records[model] = nil
		end
	end)
end

local function ownerFrozen(rec)
	local owner = rec.owner
	local char = owner and owner.Character
	return char ~= nil and char:GetAttribute("Frozen") == true
end

local function step(dt)
	for model, rec in pairs(records) do
		if not model.Parent then
			clearGhosts(rec)
			records[model] = nil
		else
			local state = model:GetAttribute("State") or "idle"
			local frozen = ownerFrozen(rec)
			local ldt = frozen and 0 or dt
			rec.t = rec.t + ldt

			-- Появление и исчезновение
			local targetFade = (state == "vanish") and 0 or 1
			if rec.fade ~= targetFade then
				local speed = (targetFade > rec.fade) and 4 or 6
				if targetFade > rec.fade then
					rec.fade = math.min(targetFade, rec.fade + dt * speed)
				else
					rec.fade = math.max(targetFade, rec.fade - dt * speed)
				end
				setFade(rec, rec.fade)
			end

			-- Позы суставов
			local poseFn = POSES[state] or poseIdle
			local pose = poseFn(rec.t)
			local k = (state == "barrage") and 38 or ((state == "finisher") and 22 or 9)
			local alpha = 1 - math.exp(-k * ldt)
			for name, j in pairs(rec.joints) do
				if name ~= "HaloSpin" then
					local target = pose[name] or V(0, 0, 0)
					j.cur = j.cur:Lerp(target, alpha)
					j.motor.C0 = j.base * CFrame.Angles(rad(j.cur.X), rad(j.cur.Y), rad(j.cur.Z))
				end
			end

			-- Нимб вращается, при остановке времени — быстрее
			local haloSpeed = (state == "timestop") and 7 or 0.6
			rec.halo = rec.halo + ldt * haloSpeed
			local halo = rec.joints.HaloSpin
			if halo then
				halo.motor.C0 = halo.base * CFrame.Angles(0, 0, rec.halo)
			end

			-- Положение стенда относительно хозяина
			if rec.anchor then
				local target = Config.StandOffsets[state] or Config.StandOffsets.idle
				if state == "idle" or state == "vanish" then
					target = target * CFrame.new(0, math.sin(rec.t * 1.8) * 0.18, 0) * CFrame.Angles(0, rad(math.sin(rec.t * 0.7) * 3), 0)
				end
				local ak = (state == "barrage" or state == "finisher") and 16 or 8
				rec.anchor.C0 = rec.anchor.C0:Lerp(target, 1 - math.exp(-ak * ldt))
			end

			-- Барраж: призрачные руки, шлейфы, свист
			local punching = (state == "barrage")
			if punching and not rec.ghosts then
				makeGhosts(rec)
			elseif not punching and rec.ghosts then
				clearGhosts(rec)
			end
			local trailsOn = punching or state == "finisher"
			if rec.trailsOn ~= trailsOn then
				rec.trailsOn = trailsOn
				for _, tr in ipairs(rec.trails) do
					tr.Enabled = trailsOn
				end
			end
			if punching then
				updateGhosts(rec, rec.t)
				rec.swishTimer = rec.swishTimer - ldt
				if rec.swishTimer <= 0 and swishPlayer and rec.torso then
					rec.swishTimer = 0.07
					swishPlayer(rec.torso)
				end
			end
		end
	end
end

function StandAnimator.Start(onSwish)
	swishPlayer = onSwish
	local folder = workspace:WaitForChild("Stands")
	folder.ChildAdded:Connect(function(m)
		task.defer(track, m)
	end)
	for _, m in ipairs(folder:GetChildren()) do
		task.spawn(track, m)
	end
	RunService.RenderStepped:Connect(step)
end

-- Локальный стенд в барраже (для тряски камеры)
function StandAnimator.LocalState()
	local me = Players.LocalPlayer
	for model in pairs(records) do
		if model:GetAttribute("Owner") == me.UserId then
			return model:GetAttribute("State")
		end
	end
	return nil
end

return StandAnimator
