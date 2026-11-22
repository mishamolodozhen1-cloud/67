-- BeastClient: существо из подсобки на клиенте (v10).
--   • анимации: кадры Shared/BeastAnims → Bone.Transform каждой кости (idle, walk, roar, attack1, grab, stomp1),
--     смена анимации — плавная (0.25 с); ходьба — модель плавно идёт по пути (атрибуты Walk*)
--   • «увидел»: существо на экране и ничем не загорожено → сервер узнаёт (BeastSeen)
--   • скример (BeastScare): существо бросается в камеру — визг, удар, тряска, красная вспышка, темнота
--   • за спиной (BeastBehind): лампы над игроком гаснут, сзади рычание; обернёшься — скример
--   • вспышка в темноте (BeastFlash): на миг что-то освещает его прямо перед тобой
--   • голос охранника (Voice): игрок иногда говорит сам с собой — фраза и субтитр
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Anims = require(Shared:WaitForChild("BeastAnims"))
local VoiceLines = require(Shared:WaitForChild("VoiceLines"))

local BeastClient = {}

local ctx
local RENDER = RunService:IsClient() and RunService.RenderStepped or RunService.Heartbeat
local BONES = Anims.Bones
local clips = {} -- имя -> { Length, Loop, Frames = { { CFrame на каждую кость } } }
local models = {} -- модель -> { Bones = { [i] = Bone }, Anim, Blend = { From = {...}, T0 } }
local reported = {}
local scaring = false
local voiceUntil = 0
local rng = Random.new()

local function now()
	return workspace:GetServerTimeNow()
end

-------------------------------------------------------------------------------
-- Анимации
-------------------------------------------------------------------------------
local function decode()
	for name, a in pairs(Anims.Anims) do
		local frames = {}
		for _, str in ipairs(a.Frames) do
			local vals = string.split(str, ",")
			local cfs = table.create(#BONES)
			for b = 1, #BONES do
				local k = (b - 1) * 4
				local qx, qy, qz, qw = tonumber(vals[k + 1]) / 1000, tonumber(vals[k + 2]) / 1000, tonumber(vals[k + 3]) / 1000, tonumber(vals[k + 4]) / 1000
				local len = math.sqrt(qx * qx + qy * qy + qz * qz + qw * qw)
				if len < 1e-6 then
					cfs[b] = CFrame.identity
				else
					cfs[b] = CFrame.new(0, 0, 0, qx / len, qy / len, qz / len, qw / len)
				end
			end
			local base = #BONES * 4
			for j, bi in ipairs(a.Moves) do
				local k = base + (j - 1) * 3
				cfs[bi] = CFrame.new(tonumber(vals[k + 1]) / 1000, tonumber(vals[k + 2]) / 1000, tonumber(vals[k + 3]) / 1000) * cfs[bi]
			end
			table.insert(frames, cfs)
		end
		clips[name] = { Length = a.Length, Loop = a.Loop, Frames = frames }
	end
end

-- Поза в момент t (секунды от начала анимации): список CFrame по костям
local function sample(clip, t)
	local frames = clip.Frames
	local n = #frames
	local f = t * Anims.Fps
	local i, u
	if clip.Loop then
		f = f % (n - 1)
		i = math.floor(f)
		u = f - i
	else
		f = math.clamp(f, 0, n - 1)
		i = math.min(math.floor(f), n - 2)
		u = f - i
	end
	local a, b = frames[i + 1], frames[i + 2] or frames[i + 1]
	local out = table.create(#BONES)
	for k = 1, #BONES do
		out[k] = a[k]:Lerp(b[k], u)
	end
	return out
end

local function track(m)
	local rec = models[m]
	if rec then
		return rec
	end
	local byName = {}
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("Bone") then
			byName[d.Name] = d
		end
	end
	local bones = {}
	for i, name in ipairs(BONES) do
		bones[i] = byName[name]
	end
	rec = { Bones = bones, Anim = nil, Pose = nil }
	models[m] = rec
	return rec
end

-- Одна модель за кадр: ходьба по пути + кости
function BeastClient.Step(m, t)
	local rec = track(m)
	-- ходьба (плавно, у себя)
	local wt0 = m:GetAttribute("WalkT0")
	if wt0 then
		local from, to, dur = m:GetAttribute("WalkFrom"), m:GetAttribute("WalkTo"), m:GetAttribute("WalkDur")
		if typeof(from) == "Vector3" and typeof(to) == "Vector3" and dur and dur > 0 then
			local alpha = math.clamp((t - wt0) / dur, 0, 1)
			local pos = from:Lerp(to, alpha)
			local dir = to - from
			if dir.Magnitude > 0.05 then
				m:PivotTo(CFrame.lookAt(pos, pos + Vector3.new(dir.X, 0, dir.Z)))
			end
		end
	end
	-- анимация
	local name = m:GetAttribute("Anim") or "idle"
	local clip = clips[name] or clips.idle
	if not clip then
		return
	end
	local at = ((t - (m:GetAttribute("AnimT0") or t)) * (m:GetAttribute("AnimSpeed") or 1))
	local pose = sample(clip, math.max(0, at))
	-- плавный переход со старой анимации
	if rec.Anim ~= name then
		rec.BlendFrom = rec.Pose
		rec.BlendT0 = os.clock()
		rec.Anim = name
	end
	if rec.BlendFrom then
		local u = (os.clock() - rec.BlendT0) / 0.25
		if u >= 1 then
			rec.BlendFrom = nil
		else
			for k = 1, #pose do
				pose[k] = rec.BlendFrom[k]:Lerp(pose[k], u)
			end
		end
	end
	rec.Pose = pose
	for k, bone in pairs(rec.Bones) do
		bone.Transform = pose[k]
	end
end

-------------------------------------------------------------------------------
-- Видит ли игрок существо
-------------------------------------------------------------------------------
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function visible(m)
	local cam = workspace.CurrentCamera
	local pivot = m:GetPivot()
	local chest = pivot.Position + Vector3.new(0, 5.5, 0)
	local to = chest - cam.CFrame.Position
	if to.Magnitude > 95 then
		return false
	end
	local vp, onScreen = cam:WorldToViewportPoint(chest)
	if not onScreen or vp.Z <= 0 then
		return false
	end
	local size = cam.ViewportSize
	if vp.X < size.X * 0.08 or vp.X > size.X * 0.92 or vp.Y < size.Y * 0.05 or vp.Y > size.Y * 0.95 then
		return false
	end
	rayParams.FilterDescendantsInstances = { m, ctx.Player.Character }
	local hit = workspace:Raycast(cam.CFrame.Position, to, rayParams)
	if hit and hit.Instance.Transparency < 0.5 and hit.Instance.Material ~= Enum.Material.Glass then
		return false
	end
	return true
end

local lastCheck = 0
local function onFrame()
	local t = now()
	local camPos = workspace.CurrentCamera.CFrame.Position
	for _, m in ipairs(CollectionService:GetTagged("NS_Beast")) do
		if m:IsDescendantOf(workspace) and (m:GetPivot().Position - camPos).Magnitude < 160 then
			BeastClient.Step(m, t)
		end
	end
	for m in pairs(models) do
		if not m.Parent then
			models[m] = nil
			reported[m] = nil
		end
	end
	if os.clock() - lastCheck > 0.15 then
		lastCheck = os.clock()
		for _, m in ipairs(CollectionService:GetTagged("NS_Beast")) do
			if not reported[m] and m:IsDescendantOf(workspace) and not ctx.CameraLocked and visible(m) then
				reported[m] = true
				ctx.Remotes.Action:FireServer("BeastSeen", m)
			end
		end
	end
end

-------------------------------------------------------------------------------
-- Голос охранника
-------------------------------------------------------------------------------
-- line — группа (VoiceLines.Player: Saw, Dark…) или ключ реплики (Start3)
function BeastClient.Voice(line)
	local group = VoiceLines.Player[line]
	local key = group and group[rng:NextInteger(1, #group)] or line
	local clip = VoiceLines.Clips["P_" .. tostring(key)]
	if not clip or os.clock() < voiceUntil or ctx.CameraLocked then
		return false
	end
	voiceUntil = os.clock() + (clip.Stop - clip.Start) + 2.5
	ctx.Audio.Play("P_" .. key, nil, 0.95)
	ctx.HUD.Subtitle("Вы", clip.Text, (clip.Stop - clip.Start) + 1.5)
	return true
end

-------------------------------------------------------------------------------
-- Скример
-------------------------------------------------------------------------------
local function shake(seconds, strength)
	local untilT = os.clock() + seconds
	local name = "NS_BeastShake" .. tostring(math.random(1, 1e6))
	RunService:BindToRenderStep(name, Enum.RenderPriority.Camera.Value + 3, function()
		local left = untilT - os.clock()
		if left <= 0 then
			RunService:UnbindFromRenderStep(name)
			return
		end
		local k = strength * (left / seconds)
		local cam = workspace.CurrentCamera
		cam.CFrame = cam.CFrame * CFrame.Angles((math.random() - 0.5) * k, (math.random() - 0.5) * k, (math.random() - 0.5) * k * 0.6)
	end)
end

function BeastClient.Scare()
	if scaring or ctx.CameraLocked then
		return
	end
	local tpl = ReplicatedStorage:FindFirstChild("BeastTemplate")
	if not tpl then
		-- модель не загрузилась — старый скример
		if ctx.Effects.JumpScare then
			ctx.Effects.JumpScare()
		end
		return
	end
	scaring = true
	local cam = workspace.CurrentCamera
	local look = Vector3.new(cam.CFrame.LookVector.X, 0, cam.CFrame.LookVector.Z)
	if look.Magnitude < 0.1 then
		look = Vector3.new(0, 0, -1)
	end
	look = look.Unit
	local eye = cam.CFrame.Position
	local height = tpl:GetAttribute("Height") or 8.6
	-- голова существа (на 0.88 его роста) — на уровне глаз
	local feetY = eye.Y - height * 0.86
	local m = tpl:Clone()
	m.Name = "BeastScare"
	m:SetAttribute("Anim", "attack1")
	m:SetAttribute("AnimT0", now() - 0.15)
	m:SetAttribute("AnimSpeed", 1.35)
	local function placeAt(dist)
		local p = Vector3.new(eye.X, feetY, eye.Z) + look * dist
		m:PivotTo(CFrame.lookAt(p, Vector3.new(eye.X, feetY, eye.Z)))
	end
	placeAt(6.5)
	-- лицо должно быть видно: холодный свет прямо от камеры
	local lamp = Instance.new("Part")
	lamp.Name = "ScareLight"
	lamp.Anchored = true
	lamp.CanCollide = false
	lamp.CanQuery = false
	lamp.Transparency = 1
	lamp.Size = Vector3.new(0.2, 0.2, 0.2)
	lamp.CFrame = CFrame.new(eye + look * 0.6 + Vector3.new(0, 0.6, 0))
	local light = Instance.new("PointLight")
	light.Range = 14
	light.Brightness = 3.5
	light.Color = Color3.fromRGB(255, 220, 210)
	light.Parent = lamp
	lamp.Parent = workspace
	m.Parent = workspace
	local grade = Instance.new("ColorCorrectionEffect")
	grade.Name = "NS_BeastScare"
	grade.TintColor = Color3.fromRGB(255, 170, 160)
	grade.Contrast = 0.35
	grade.Saturation = -0.3
	grade.Parent = Lighting
	ctx.Audio.Play("ScareSting", nil, 1)
	ctx.Audio.Play("BeastShriek", nil, 1)
	task.delay(0.12, function()
		ctx.Audio.Play("BeastRoar", nil, 0.8, 1.15)
	end)
	shake(0.9, 0.12)
	if ctx.Effects.SetVignetteBoost then
		ctx.Effects.SetVignetteBoost(0.8)
	end
	-- бросок: с 6.5 до 1.4 studs за 0.2 с, потом ещё ближе
	local t0 = os.clock()
	local conn
	conn = RENDER:Connect(function()
		local u = (os.clock() - t0) / 0.2
		placeAt(6.5 - math.min(1, u) ^ 0.6 * 5.1 - math.max(0, (os.clock() - t0 - 0.2)) * 0.8)
		BeastClient.Step(m, now())
	end)
	task.delay(0.75, function()
		ctx.HUD.Fade(0, 0.06, Color3.fromRGB(25, 0, 0))
	end)
	task.delay(1.0, function()
		if conn then
			conn:Disconnect()
		end
		m:Destroy()
		lamp:Destroy()
		grade:Destroy()
		ctx.HUD.Fade(1, 0.9)
		if ctx.Effects.SetVignetteBoost then
			ctx.Effects.SetVignetteBoost(0)
		end
	end)
	task.delay(2.0, function()
		BeastClient.Voice("Scared")
	end)
	task.delay(3, function()
		scaring = false
	end)
end

-------------------------------------------------------------------------------
-- За спиной и вспышка
-------------------------------------------------------------------------------
local function flatYaw(v)
	return math.atan2(-v.X, -v.Z)
end

function BeastClient.Behind()
	if ctx.CameraLocked or scaring then
		return
	end
	local cam = workspace.CurrentCamera
	local cf = cam.CFrame
	local look = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
	if look.Magnitude < 0.1 then
		return
	end
	local back = cf.Position - look.Unit * 2.6 + Vector3.new(0, 1, 0)
	if ctx.Effects.LampsOut then
		ctx.Effects.LampsOut({ Center = cf.Position, Radius = 16, Duration = 6 })
	end
	ctx.Audio.Play("BeastGrowlLow", back, 1)
	task.delay(1.2, function()
		ctx.Audio.Play("BoneCrack", back, 0.9)
	end)
	local startYaw = flatYaw(cf.LookVector)
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < 4.5 do
			task.wait(0.05)
			local d = (flatYaw(cam.CFrame.LookVector) - startYaw + math.pi) % (2 * math.pi) - math.pi
			if math.abs(d) > math.rad(110) then
				BeastClient.Scare()
				return
			end
		end
		-- не обернулся: тяжёлый шаг прочь
		ctx.Audio.Play("BeastStep", cam.CFrame.Position - look.Unit * 8, 0.8)
	end)
end

function BeastClient.Flash(data)
	local pos = data and data.Pos
	if typeof(pos) ~= "Vector3" then
		return
	end
	local cam = workspace.CurrentCamera
	local p = Instance.new("Part")
	p.Name = "BeastFlash"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.Transparency = 1
	p.Size = Vector3.new(0.2, 0.2, 0.2)
	-- свет между игроком и существом, чуть сверху
	p.CFrame = CFrame.new(pos:Lerp(cam.CFrame.Position, 0.35) + Vector3.new(0, 3, 0))
	local light = Instance.new("PointLight")
	light.Range = 18
	light.Brightness = 0
	light.Color = Color3.fromRGB(230, 235, 255)
	light.Parent = p
	p.Parent = workspace
	ctx.Audio.Play("FluorFlicker", p.Position, 0.8)
	task.spawn(function()
		for _, step in ipairs({ { 3, 0.09 }, { 0, 0.12 }, { 4, 0.16 }, { 0, 0.1 } }) do
			light.Brightness = step[1]
			if step[1] > 0 then
				ctx.Audio.Play("ScareSting", nil, 0.55)
			end
			task.wait(step[2])
		end
		p:Destroy()
	end)
end

function BeastClient.Init(c)
	ctx = c
	decode()
	RENDER:Connect(onFrame)
end

-- для проверок
BeastClient.Clips = clips
BeastClient.Sample = sample

return BeastClient
