-- Weather: ночной дождь (только на клиенте).
--   • над парковкой перед витриной всегда идёт дождь — его видно и изнутри через стекло
--   • когда камера на улице (парковка, задний двор, кат-сцена), дождь идёт и вокруг камеры
-- Капли — ParticleEmitter с вытянутой текстурой, летящие вниз (Orientation = VelocityParallel).
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
-- кадр отрисовки (в серверном тесте его нет — там Heartbeat)
local RENDER = RunService:IsClient() and RunService.RenderStepped or RunService.Heartbeat

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local Weather = {}

local ctx
local follow, followEmitter

local function emitterPart(name, size, cf)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Transparency = 1
	p.Size = size
	p.CFrame = cf
	p.Parent = workspace
	return p
end

-- life — сколько живёт капля (подбираем так, чтобы она долетала до земли)
local function rain(parent, rate, life)
	local pe = Instance.new("ParticleEmitter")
	pe.Name = "Rain"
	pe.Texture = Config.Images.RainStreak
	pe.EmissionDirection = Enum.NormalId.Bottom
	pe.Orientation = Enum.ParticleOrientation.VelocityParallel
	pe.Rate = rate
	pe.Lifetime = NumberRange.new(life * 0.9, life * 1.1)
	pe.Speed = NumberRange.new(62, 78)
	pe.SpreadAngle = Vector2.new(4, 4)
	pe.Acceleration = Vector3.new(-2, -10, 1)
	pe.Size = NumberSequence.new(0.22)
	pe.Squash = NumberSequence.new(2.4)
	pe.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.1, 0.45),
		NumberSequenceKeypoint.new(0.85, 0.55),
		NumberSequenceKeypoint.new(1, 1),
	})
	pe.Color = ColorSequence.new(Color3.fromRGB(196, 210, 228))
	pe.LightInfluence = 0.9
	pe.LightEmission = 0.05
	pe.Parent = parent
	return pe
end

function Weather.Init(c)
	ctx = c
	local mobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	local scale = mobile and 0.5 or 1
	-- Парковка перед витриной (видна через стекло)
	local front = emitterPart("RainFront", Vector3.new(130, 1, 40), CFrame.new(-14, 30, 72))
	rain(front, 1400 * scale, 0.42)
	-- Задний двор
	local alley = emitterPart("RainAlley", Vector3.new(50, 1, 28), CFrame.new(-15, 26, -78))
	rain(alley, 500 * scale, 0.37)
	-- Вокруг камеры, когда она снаружи
	follow = emitterPart("RainCamera", Vector3.new(60, 1, 60), CFrame.new(0, -500, 0))
	followEmitter = rain(follow, 1600 * scale, 0.5)
	followEmitter.Enabled = false

	RENDER:Connect(function()
		local cam = workspace.CurrentCamera
		if not cam then
			return
		end
		local pos = cam.CFrame.Position
		local outside = ctx.Audio.ZoneOf(pos) == "Outside"
		followEmitter.Enabled = outside
		if outside then
			local look = cam.CFrame.LookVector
			follow.CFrame = CFrame.new(pos + Vector3.new(look.X * 18, 22, look.Z * 18))
		end
	end)
end

return Weather
