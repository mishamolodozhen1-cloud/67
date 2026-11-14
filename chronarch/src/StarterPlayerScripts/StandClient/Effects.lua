-- Визуальные и звуковые эффекты: удары, призыв, пробуждение стрелой, остановка времени,
-- а также «живой» мир (часы на башне, парящая стрела, огонь), который замирает во время остановки.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local Lighting = game:GetService("Lighting")
local Debris = game:GetService("Debris")
local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local S = Config.Sounds

local Effects = {}

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local fxGui
local flashFrame
local banner
local bannerTimer
local frozenNote
local fxAttachment
local sparkEmitter
local tickSound
local timeCC
local frozenEmitters = {}
local frozenTracks = {}
local shakeUntil = 0
local shakePower = 0
local lastHitSound = 0
local timeStopEndsAt = 0

-------------------------------------------------------------------------------
-- Звук
-------------------------------------------------------------------------------
local function newSound(id, parent, volume, speed)
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume or 1
	s.PlaybackSpeed = speed or 1
	s.RollOffMinDistance = 12
	s.RollOffMaxDistance = 160
	s.Parent = parent
	return s
end

local function play2D(id, volume, speed)
	local s = newSound(id, SoundService, volume, speed)
	s:Play()
	s.Ended:Connect(function()
		s:Destroy()
	end)
	Debris:AddItem(s, 12)
	return s
end

local function playAt(id, position, volume, speed)
	local att = Instance.new("Attachment")
	att.WorldPosition = position
	att.Parent = workspace.Terrain
	local s = newSound(id, att, volume, speed)
	s:Play()
	Debris:AddItem(att, 8)
	return s
end

function Effects.PlaySwish(torso)
	local s = newSound(S.Swish, torso, 0.55, 0.85 + math.random() * 0.45)
	s:Play()
	Debris:AddItem(s, 1)
end

-------------------------------------------------------------------------------
-- Камера
-------------------------------------------------------------------------------
function Effects.Shake(power, duration)
	shakePower = math.max(shakePower, power)
	shakeUntil = math.max(shakeUntil, os.clock() + duration)
end

local function cameraStep()
	local t = os.clock()
	local p = 0
	if t < shakeUntil then
		p = shakePower
	else
		shakePower = 0
	end
	local Animator = Effects.Animator
	if Animator and Animator.LocalState() == "barrage" then
		p = math.max(p, 0.12)
	end
	if p > 0 then
		local rx = (math.noise(t * 25, 0.1) * 2) * p
		local ry = (math.noise(t * 25, 5.3) * 2) * p
		camera.CFrame = camera.CFrame * CFrame.Angles(math.rad(rx), math.rad(ry), 0)
	end
end

local function fovKick(amount, upTime, downTime)
	local base = 70
	local up = TweenService:Create(camera, TweenInfo.new(upTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { FieldOfView = base + amount })
	up:Play()
	up.Completed:Connect(function()
		TweenService:Create(camera, TweenInfo.new(downTime, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), { FieldOfView = base }):Play()
	end)
end

local function flash(color, from, duration)
	flashFrame.BackgroundColor3 = color
	flashFrame.BackgroundTransparency = from
	TweenService:Create(flashFrame, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 }):Play()
end

-------------------------------------------------------------------------------
-- Удары
-------------------------------------------------------------------------------
local function impactFlash(position, size, color, duration)
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Ball
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Size = Vector3.new(0.4, 0.4, 0.4)
	p.Transparency = 0.15
	p.CFrame = CFrame.new(position)
	p.Parent = workspace.CurrentCamera
	TweenService:Create(p, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(size, size, size),
		Transparency = 1,
	}):Play()
	Debris:AddItem(p, duration + 0.05)
end

local function shockRing(cf, size, duration)
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Cylinder
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = Color3.fromRGB(255, 226, 150)
	p.Size = Vector3.new(0.15, 1, 1)
	p.Transparency = 0.2
	p.CFrame = cf
	p.Parent = workspace.CurrentCamera
	TweenService:Create(p, TweenInfo.new(duration, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.05, size, size),
		Transparency = 1,
	}):Play()
	Debris:AddItem(p, duration + 0.05)
end

local function damageNumber(position, amount, big)
	local att = Instance.new("Attachment")
	att.WorldPosition = position
	att.Parent = workspace.Terrain
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(big and 120 or 70, big and 52 or 32)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.StudsOffsetWorldSpace = Vector3.new((math.random() - 0.5) * 1.5, 0.5, 0)
	bb.Parent = att
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = tostring(math.floor(amount * 10 + 0.5) / 10)
	label.TextScaled = true
	label.Font = Enum.Font.GothamBlack
	label.TextColor3 = big and Color3.fromRGB(255, 90, 70) or Color3.fromRGB(255, 226, 140)
	label.TextStrokeTransparency = 0.2
	label.TextStrokeColor3 = Color3.fromRGB(40, 20, 10)
	label.Parent = bb
	TweenService:Create(bb, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		StudsOffsetWorldSpace = bb.StudsOffsetWorldSpace + Vector3.new(0, 2.2, 0),
	}):Play()
	TweenService:Create(label, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	}):Play()
	Debris:AddItem(att, 0.85)
end

local function sparks(position, count)
	fxAttachment.WorldPosition = position
	sparkEmitter:Emit(count)
end

-- hits: список {позиция, урон, отложен}
function Effects.Hit(hits, isFinisher)
	for _, h in ipairs(hits) do
		local pos, dmg, delayed = h[1], h[2], h[3]
		if isFinisher then
			impactFlash(pos, 6, Color3.fromRGB(255, 220, 140), 0.25)
			sparks(pos, 30)
			Effects.Shake(0.9, 0.25)
		else
			impactFlash(pos, delayed and 1.4 or 2.2, delayed and Color3.fromRGB(190, 200, 255) or Color3.fromRGB(255, 236, 170), 0.12)
			sparks(pos, delayed and 3 or 8)
		end
		if not delayed then
			damageNumber(pos, dmg, isFinisher)
		end
		local t = os.clock()
		if isFinisher or t - lastHitSound > 0.05 then
			lastHitSound = t
			playAt(isFinisher and S.Finisher or S.Hit, pos, isFinisher and 1.4 or 0.9, 0.9 + math.random() * 0.25)
		end
	end
end

function Effects.Finisher(model)
	local hand = model:FindFirstChild("RHand")
	local torso = model:FindFirstChild("Torso")
	if torso then
		playAt(S.Swish, torso.Position, 1, 0.7)
	end
	task.delay(Config.Barrage.FinisherDelay, function()
		if hand and hand.Parent then
			local look = (torso and torso.CFrame.LookVector) or Vector3.new(0, 0, -1)
			local pos = hand.Position + look * 0.8
			shockRing(CFrame.lookAt(pos, pos + look) * CFrame.Angles(0, math.rad(90), 0), 9, 0.35)
			impactFlash(pos, 3.5, Color3.fromRGB(255, 240, 200), 0.18)
		end
	end)
end

-------------------------------------------------------------------------------
-- Призыв
-------------------------------------------------------------------------------
function Effects.Summon(model, position)
	playAt(S.Summon, position, 1.1, 1)
	local torso = model:WaitForChild("Torso", 3)
	if torso then
		impactFlash(torso.Position, 7, Color3.fromRGB(255, 214, 120), 0.4)
		shockRing(CFrame.new(position - Vector3.new(0, 2.6, 0)) * CFrame.Angles(0, 0, math.rad(90)), 14, 0.5)
		sparks(torso.Position, 25)
	end
	local owner = Players:GetPlayerByUserId(model:GetAttribute("Owner") or 0)
	if owner == player then
		Effects.Shake(0.35, 0.25)
	end
end

function Effects.Desummon(model)
	local torso = model:FindFirstChild("Torso")
	if torso then
		playAt(S.Summon, torso.Position, 0.6, 1.4)
		impactFlash(torso.Position, 4, Color3.fromRGB(255, 214, 120), 0.3)
	end
end

-------------------------------------------------------------------------------
-- Пробуждение: стрела срывается с алтаря и пронзает игрока
-------------------------------------------------------------------------------
local function setModelFade(model, alpha)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.LocalTransparencyModifier = 1 - alpha
		end
	end
end

function Effects.Awaken(userId)
	local who = Players:GetPlayerByUserId(userId)
	local char = who and who.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local altar = workspace:FindFirstChild("ArrowAltar")
	local arrow = altar and altar:FindFirstChild("Arrow")
	if not hrp or not arrow then
		return
	end

	local clone = arrow:Clone()
	clone.Parent = workspace.CurrentCamera
	setModelFade(arrow, 0)
	local start = arrow:GetPivot()
	local t0 = os.clock()
	local flightTime = 0.55
	local pierced = false
	local TIP = 2.8

	playAt(S.Swish, start.Position, 1.2, 0.6)

	local conn
	conn = RunService.RenderStepped:Connect(function()
		local t = (os.clock() - t0) / flightTime
		if not hrp.Parent then
			conn:Disconnect()
			clone:Destroy()
			setModelFade(arrow, 1)
			return
		end
		local target = hrp.Position + Vector3.new(0, 0.6, 0)
		if t < 1 then
			local e = t * t
			local pos = start.Position:Lerp(target, e) + Vector3.new(0, math.sin(t * math.pi) * 3, 0)
			local cf = CFrame.lookAt(pos, target) * CFrame.Angles(0, math.rad(90), 0)
			clone:PivotTo(cf)
		else
			local dir = (target - start.Position)
			dir = Vector3.new(dir.X, 0, dir.Z)
			if dir.Magnitude < 0.1 then
				dir = hrp.CFrame.LookVector * -1
			end
			dir = dir.Unit
			local center = target - dir * (TIP - 0.9)
			clone:PivotTo(CFrame.lookAt(center, center + dir) * CFrame.Angles(0, math.rad(90), 0))
			if not pierced then
				pierced = true
				playAt(S.Awaken, target, 1.5, 1)
				impactFlash(target, 9, Color3.fromRGB(255, 70, 110), 0.5)
				shockRing(CFrame.new(target - Vector3.new(0, 2.6, 0)) * CFrame.Angles(0, 0, math.rad(90)), 22, 0.7)
				sparks(target, 40)
				if who == player then
					flash(Color3.fromRGB(255, 255, 255), 0.05, 0.9)
					Effects.Shake(1.2, 0.5)
					fovKick(14, 0.12, 0.8)
				end
			end
			if t > 2.6 then
				conn:Disconnect()
				clone:Destroy()
			elseif t > 1.8 then
				setModelFade(clone, 1 - (t - 1.8) / 0.8)
			end
		end
	end)

	-- Стрела на алтаре плавно возвращается
	task.delay(3, function()
		local a = 0
		while a < 1 do
			a = math.min(1, a + RunService.RenderStepped:Wait() * 1.5)
			setModelFade(arrow, a)
		end
	end)
end

-------------------------------------------------------------------------------
-- Остановка времени
-------------------------------------------------------------------------------
local function sphere(position, color, material, transparency)
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Ball
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = material
	p.Color = color
	p.Transparency = transparency
	p.Size = Vector3.new(1, 1, 1)
	p.CFrame = CFrame.new(position)
	p.Parent = workspace.CurrentCamera
	return p
end

local function tweenCC(props, duration, style)
	TweenService:Create(timeCC, TweenInfo.new(duration, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props):Play()
end

local function isStopperInstance(inst, stopperId)
	local stopper = Players:GetPlayerByUserId(stopperId or 0)
	if stopper and stopper.Character and inst:IsDescendantOf(stopper.Character) then
		return true
	end
	local stands = workspace:FindFirstChild("Stands")
	if stands then
		local m = stands:FindFirstChild("Stand_" .. tostring(stopperId))
		if m and inst:IsDescendantOf(m) then
			return true
		end
	end
	return false
end

local function freezeWorldParticles(stopperId)
	for _, d in ipairs(workspace:GetDescendants()) do
		if d:IsA("ParticleEmitter") and d.TimeScale > 0 and not isStopperInstance(d, stopperId) then
			frozenEmitters[d] = d.TimeScale
			d.TimeScale = 0
		end
	end
end

local function unfreezeWorldParticles()
	for e, scale in pairs(frozenEmitters) do
		if e.Parent then
			e.TimeScale = scale
		end
	end
	frozenEmitters = {}
end

function Effects.TimeStopStart(userId, origin, windup)
	play2D(S.TimeStop, 1.4, 1)
	play2D(S.Voice, 2.2, 1)

	local core = sphere(origin, Color3.fromRGB(255, 214, 120), Enum.Material.Neon, 0.82)
	local shell = sphere(origin, Color3.fromRGB(150, 110, 255), Enum.Material.ForceField, 0.1)
	TweenService:Create(core, TweenInfo.new(windup, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Size = Vector3.new(60, 60, 60) }):Play()
	TweenService:Create(shell, TweenInfo.new(windup, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Size = Vector3.new(66, 66, 66) }):Play()
	Debris:AddItem(core, windup + 0.05)
	Debris:AddItem(shell, windup + 0.05)
	tweenCC({ Saturation = -0.3, Contrast = 0.15 }, windup, Enum.EasingStyle.Quad)
	if userId == player.UserId then
		Effects.Shake(0.3, windup)
	end
end

function Effects.TimeFrozen(userId, origin, duration)
	timeStopEndsAt = os.clock() + duration

	-- Ударная волна и вспышка «негатива»
	local wave = sphere(origin, Color3.fromRGB(120, 90, 255), Enum.Material.ForceField, 0)
	wave.Size = Vector3.new(60, 60, 60)
	TweenService:Create(wave, TweenInfo.new(0.55, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Size = Vector3.new(700, 700, 700), Transparency = 1 }):Play()
	Debris:AddItem(wave, 0.6)
	timeCC.Saturation = -1
	timeCC.Contrast = 0.9
	timeCC.Brightness = 0.3
	timeCC.TintColor = Color3.fromRGB(190, 150, 255)
	tweenCC({ Saturation = -0.88, Contrast = 0.32, Brightness = -0.04, TintColor = Color3.fromRGB(212, 222, 255) }, 0.6)
	flash(Color3.fromRGB(210, 190, 255), 0.35, 0.5)
	fovKick(12, 0.1, 0.9)
	Effects.Shake(0.8, 0.35)

	if tickSound then
		tickSound:Destroy()
	end
	tickSound = newSound(S.Tick, SoundService, 1.1, 1)
	tickSound.Looped = true
	tickSound:Play()

	freezeWorldParticles(userId)
	Effects.ShowBanner(true)
end

function Effects.TimeResume(hits)
	if tickSound then
		tickSound:Destroy()
		tickSound = nil
	end
	play2D(S.Resume, 1.3, 1)
	tweenCC({ Saturation = 0, Contrast = 0, Brightness = 0, TintColor = Color3.fromRGB(255, 255, 255) }, 0.8)
	unfreezeWorldParticles()
	Effects.ShowBanner(false)
	if hits and #hits > 0 then
		for _, h in ipairs(hits) do
			impactFlash(h[1], 8, Color3.fromRGB(255, 220, 140), 0.35)
			sparks(h[1], 40)
			damageNumber(h[1], h[2], true)
			playAt(S.Finisher, h[1], 1.5, 0.85)
		end
		Effects.Shake(0.8, 0.4)
	end
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp then
		local wave = sphere(hrp.Position, Color3.fromRGB(120, 90, 255), Enum.Material.ForceField, 0.6)
		wave.Size = Vector3.new(400, 400, 400)
		TweenService:Create(wave, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Size = Vector3.new(1, 1, 1), Transparency = 1 }):Play()
		Debris:AddItem(wave, 0.55)
	end
end

function Effects.ShowBanner(on)
	banner.Visible = on
end

-------------------------------------------------------------------------------
-- Замирание анимаций у застывших персонажей
-------------------------------------------------------------------------------
local function freezeCharacterAnimations()
	local anyFrozen = false
	for _, plr in ipairs(Players:GetPlayers()) do
		local char = plr.Character
		if char and char:GetAttribute("Frozen") then
			anyFrozen = true
			local hum = char:FindFirstChildOfClass("Humanoid")
			local animator = hum and hum:FindFirstChildOfClass("Animator")
			if animator then
				for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
					if track.Speed ~= 0 then
						frozenTracks[track] = true
						track:AdjustSpeed(0)
					end
				end
			end
		end
	end
	if not anyFrozen and next(frozenTracks) then
		for track in pairs(frozenTracks) do
			if track.IsPlaying then
				track:AdjustSpeed(1)
			end
		end
		frozenTracks = {}
	end
end

-------------------------------------------------------------------------------
-- Живой мир
-------------------------------------------------------------------------------
local function startWorld()
	local tower = workspace:WaitForChild("Map", 10) and workspace.Map:WaitForChild("ClockTower", 10)
	local center = tower and tower:FindFirstChild("ClockCenter")
	local hourHand = tower and tower:FindFirstChild("HourHand")
	local minuteHand = tower and tower:FindFirstChild("MinuteHand")

	local altar = workspace:WaitForChild("ArrowAltar", 10)
	local arrow = altar and altar:WaitForChild("Arrow", 10)
	local arrowBase = arrow and arrow:GetPivot()

	local flickers = {}
	for _, d in ipairs(workspace:GetDescendants()) do
		if d:IsA("PointLight") and d:GetAttribute("Flicker") then
			table.insert(flickers, { light = d, base = d.Brightness, seed = math.random() * 100 })
		end
	end

	local clockT = 8 * 60 + 17
	local arrowT = 0

	RunService.RenderStepped:Connect(function(dt)
		local stopped = workspace:GetAttribute("TimeStopped") == true
		if not stopped then
			clockT = clockT + dt * 2
			arrowT = arrowT + dt
		end

		if center and hourHand and minuteHand then
			local c = center.CFrame
			local minuteA = (clockT / 60) * math.pi * 2
			local hourA = (clockT / 720) * math.pi * 2
			hourHand.CFrame = c * CFrame.Angles(0, 0, -hourA) * CFrame.new(0, 1.5, -0.05)
			minuteHand.CFrame = c * CFrame.Angles(0, 0, -minuteA) * CFrame.new(0, 2.4, 0.1)
		end

		if arrow and arrowBase then
			local pos = arrowBase.Position + Vector3.new(0, math.sin(arrowT * 1.4) * 0.2, 0)
			arrow:PivotTo(CFrame.new(pos) * CFrame.Angles(0, arrowT * 0.5, 0) * arrowBase.Rotation)
		end

		if not stopped then
			for _, f in ipairs(flickers) do
				f.light.Brightness = f.base * (0.8 + math.noise(os.clock() * 6, f.seed) * 0.5 + 0.1)
			end
		end

		freezeCharacterAnimations()

		if banner.Visible then
			local left = math.max(0, timeStopEndsAt - os.clock())
			banner.Text = string.format("ВРЕМЯ ОСТАНОВЛЕНО  ·  %.1f", left)
		end
		local myChar = player.Character
		frozenNote.Visible = myChar ~= nil and myChar:GetAttribute("Frozen") == true
	end)
end

-------------------------------------------------------------------------------
-- Инициализация
-------------------------------------------------------------------------------
function Effects.Init(animator)
	Effects.Animator = animator

	timeCC = Instance.new("ColorCorrectionEffect")
	timeCC.Name = "TimeStopCC"
	timeCC.Parent = Lighting

	fxAttachment = Instance.new("Attachment")
	fxAttachment.Parent = workspace.Terrain
	sparkEmitter = Instance.new("ParticleEmitter")
	sparkEmitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparkEmitter.Rate = 0
	sparkEmitter.Lifetime = NumberRange.new(0.25, 0.5)
	sparkEmitter.Speed = NumberRange.new(14, 30)
	sparkEmitter.SpreadAngle = Vector2.new(180, 180)
	sparkEmitter.Drag = 6
	sparkEmitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
	sparkEmitter.Color = ColorSequence.new(Color3.fromRGB(255, 240, 190), Color3.fromRGB(255, 150, 60))
	sparkEmitter.LightEmission = 1
	sparkEmitter.Parent = fxAttachment

	fxGui = Instance.new("ScreenGui")
	fxGui.Name = "FXGui"
	fxGui.IgnoreGuiInset = true
	fxGui.ResetOnSpawn = false
	fxGui.DisplayOrder = 5
	fxGui.Parent = player:WaitForChild("PlayerGui")

	flashFrame = Instance.new("Frame")
	flashFrame.Size = UDim2.fromScale(1, 1)
	flashFrame.BackgroundTransparency = 1
	flashFrame.BorderSizePixel = 0
	flashFrame.Parent = fxGui

	banner = Instance.new("TextLabel")
	banner.Name = "TimeBanner"
	banner.AnchorPoint = Vector2.new(0.5, 0)
	banner.Position = UDim2.new(0.5, 0, 0, 64)
	banner.Size = UDim2.new(0.8, 0, 0, 40)
	banner.BackgroundTransparency = 1
	banner.Font = Enum.Font.GothamBlack
	banner.TextScaled = true
	banner.TextColor3 = Color3.fromRGB(235, 225, 255)
	banner.TextStrokeColor3 = Color3.fromRGB(60, 30, 110)
	banner.TextStrokeTransparency = 0.1
	banner.Visible = false
	banner.Parent = fxGui
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MaxTextSize = 34
	constraint.Parent = banner

	frozenNote = Instance.new("TextLabel")
	frozenNote.AnchorPoint = Vector2.new(0.5, 0)
	frozenNote.Position = UDim2.new(0.5, 0, 0, 108)
	frozenNote.Size = UDim2.new(0.7, 0, 0, 26)
	frozenNote.BackgroundTransparency = 1
	frozenNote.Font = Enum.Font.GothamMedium
	frozenNote.TextScaled = true
	frozenNote.TextColor3 = Color3.fromRGB(200, 210, 255)
	frozenNote.TextStrokeTransparency = 0.3
	frozenNote.Text = "Ты застыл во времени…"
	frozenNote.Visible = false
	frozenNote.Parent = fxGui

	RunService:BindToRenderStep("StandCameraShake", Enum.RenderPriority.Camera.Value + 1, cameraStep)

	-- Если зашли во время остановки времени — сразу показываем застывший мир.
	if workspace:GetAttribute("TimeStopped") then
		local endsAt = workspace:GetAttribute("TimeStopEndsAt") or 0
		timeStopEndsAt = os.clock() + math.max(0, endsAt - workspace:GetServerTimeNow())
		timeCC.Saturation = -0.88
		timeCC.Contrast = 0.32
		timeCC.TintColor = Color3.fromRGB(212, 222, 255)
		freezeWorldParticles(workspace:GetAttribute("TimeStopper"))
		Effects.ShowBanner(true)
	end

	task.spawn(startWorld)

	task.spawn(function()
		local preload = {}
		for _, id in pairs(S) do
			local s = Instance.new("Sound")
			s.SoundId = id
			table.insert(preload, s)
		end
		pcall(function()
			ContentProvider:PreloadAsync(preload)
		end)
	end)
end

return Effects
