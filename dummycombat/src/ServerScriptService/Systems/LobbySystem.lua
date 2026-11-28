-- LobbySystem: 3D-лобби (этап 8) — ангар, где игроки ждут матча, выбирают снаряжение и голосуют.
-- Строится один раз при запуске в Workspace.Lobby, далеко от карт (Center). В лобби нет оружия и урона.
--
-- Ангар 140 × 100, высота 34: полированный бетонный пол, стены из профлиста, фермы и световые полосы под
-- крышей. На севере — подиум (на нём клиент показывает своего манекена с выбранным оружием — его видит
-- камера меню), за ним — стена с названием игры. На западе — стенд с оружием, на востоке — тир с
-- мишенями-манекенами, на юге — место появления.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local Configs = ReplicatedStorage:WaitForChild("Configs")
local Logger = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Logger"))
local DummyRig = require(Configs:WaitForChild("DummyRig"))

local LobbySystem = { Name = "LobbySystem" }

LobbySystem.Center = Vector3.new(2400, 0, 0)
LobbySystem.Lighting = {
	ClockTime = 14.5,
	Brightness = 1.6,
	Ambient = Color3.fromRGB(96, 96, 102),
	OutdoorAmbient = Color3.fromRGB(118, 118, 124),
	EnvironmentDiffuseScale = 0.7,
	EnvironmentSpecularScale = 0.6,
	Atmosphere = { Density = 0.25, Offset = 0, Haze = 1, Glare = 0, Color = Color3.fromRGB(196, 196, 200), Decay = Color3.fromRGB(100, 100, 106) },
	ColorCorrection = { Contrast = 0.1, Saturation = -0.05, Brightness = 0, TintColor = Color3.fromRGB(255, 250, 244) },
}

local log = Logger.new("Lobby")
local spawns = {}
local rng = Random.new()
local MapKit = nil

local function signText(part, face, text, size, color)
	local g = Instance.new("SurfaceGui")
	g.Face = face
	g.CanvasSize = Vector2.new(1600, 400)
	g.LightInfluence = 0.2
	g.Parent = part
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 1)
	t.Font = Enum.Font.GothamBlack
	t.Text = text
	t.TextColor3 = color
	t.TextSize = size
	t.Parent = g
	return t
end

function LobbySystem.Build()
	local old = workspace:FindFirstChild("Lobby")
	if old then
		old:ClearAllChildren()
	end
	local folder = old or Instance.new("Folder")
	folder.Name = "Lobby"
	folder.Parent = workspace
	local root = Instance.new("Model")
	root.Name = "Hangar"
	root.Parent = folder
	local b = MapKit.new(root)
	local C = MapKit.Colors
	local M = Enum.Material
	local L = LobbySystem.Center
	local function at(x, y, z)
		return CFrame.new(L + Vector3.new(x, y, z))
	end
	local W, D, H = 140, 100, 34
	-- пол: шлифованный бетон, швы, жёлтая линия у места появления
	b:Box(Vector3.new(W, 2, D), at(0, -1, 0), M.Concrete, Color3.fromRGB(128, 128, 126), { Reflectance = 0.02 })
	for x = -60, 60, 20 do
		b:Box(Vector3.new(0.15, 0.04, D - 4), at(x, 0.02, 0), M.SmoothPlastic, Color3.fromRGB(100, 100, 98), { CastShadow = false })
	end
	for z = -40, 40, 20 do
		b:Box(Vector3.new(W - 4, 0.04, 0.15), at(0, 0.02, z), M.SmoothPlastic, Color3.fromRGB(100, 100, 98), { CastShadow = false })
	end
	b:Box(Vector3.new(W - 8, 0.05, 0.6), at(0, 0.03, 30), M.SmoothPlastic, C.Yellow, { CastShadow = false })
	-- стены: светлый профлист (рёбра), снизу — бетонный цоколь
	local wallColor = Color3.fromRGB(150, 153, 156)
	local plinth = Color3.fromRGB(96, 96, 96)
	for _, w in ipairs({
		{ Vector3.new(W, H, 1), at(0, H / 2, -D / 2) },
		{ Vector3.new(W, H, 1), at(0, H / 2, D / 2) },
		{ Vector3.new(1, H, D), at(-W / 2, H / 2, 0) },
		{ Vector3.new(1, H, D), at(W / 2, H / 2, 0) },
	}) do
		b:Box(w[1], w[2], M.Metal, wallColor)
	end
	b:Box(Vector3.new(W - 1, 3, 1.4), at(0, 1.5, D / 2 - 0.6), M.Concrete, plinth)
	b:Box(Vector3.new(1.4, 3, D - 1), at(-W / 2 + 0.6, 1.5, 0), M.Concrete, plinth)
	b:Box(Vector3.new(1.4, 3, D - 1), at(W / 2 - 0.6, 1.5, 0), M.Concrete, plinth)
	for x = -W / 2 + 4, W / 2 - 4, 3 do
		b:Box(Vector3.new(0.6, H - 4, 0.35), at(x, H / 2 + 1, D / 2 - 0.65), M.Metal, Color3.fromRGB(136, 139, 142), { CastShadow = false })
	end
	for z = -D / 2 + 4, D / 2 - 4, 3 do
		b:Box(Vector3.new(0.35, H - 4, 0.6), at(-W / 2 + 0.65, H / 2 + 1, z), M.Metal, Color3.fromRGB(136, 139, 142), { CastShadow = false })
		b:Box(Vector3.new(0.35, H - 4, 0.6), at(W / 2 - 0.65, H / 2 + 1, z), M.Metal, Color3.fromRGB(136, 139, 142), { CastShadow = false })
	end
	-- крыша, фермы, световые полосы
	b:Box(Vector3.new(W + 2, 1, D + 2), at(0, H + 0.5, 0), M.Metal, Color3.fromRGB(70, 72, 76))
	for x = -60, 60, 15 do
		b:Box(Vector3.new(1, 2.4, D - 2), at(x, H - 1.2, 0), M.Metal, Color3.fromRGB(58, 60, 64), { CastShadow = false })
		b:Box(Vector3.new(3, 0.2, D - 10), at(x + 7.5, H - 0.2, 0), M.SmoothPlastic, Color3.fromRGB(248, 246, 238), { CastShadow = false, Transparency = 0.05 })
		local stripe = b:Box(Vector3.new(3, 0.2, 2), at(x + 7.5, H - 0.4, 0), M.SmoothPlastic, Color3.fromRGB(248, 246, 238), { Transparency = 1, CastShadow = false })
		local light = Instance.new("SurfaceLight")
		light.Face = Enum.NormalId.Bottom
		light.Range = 44
		light.Angle = 120
		light.Brightness = 1.1
		light.Color = Color3.fromRGB(255, 248, 236)
		light.Parent = stripe
	end
	-- испытательный бокс (север): подиум, тёмная задняя стена с вертикальными светильниками и полосой
	local podiumTop = 1.2
	b:Cylinder(1.0, 16.4, at(0, 0.5, -24), M.Metal, C.Yellow, { CastShadow = false })
	b:Cylinder(podiumTop, 16, at(0, podiumTop / 2, -24), M.Concrete, Color3.fromRGB(58, 60, 64))
	b:Cylinder(0.05, 12, at(0, podiumTop + 0.02, -24), M.SmoothPlastic, Color3.fromRGB(46, 48, 52), { CastShadow = false })
	b:Box(Vector3.new(70, 22, 1.5), at(0, 11, -48.6), M.SmoothPlastic, Color3.fromRGB(34, 35, 38))
	for _, x in ipairs({ -30, -18, 18, 30 }) do
		local strip = b:Box(Vector3.new(1.2, 16, 0.3), at(x, 11, -47.7), M.SmoothPlastic, Color3.fromRGB(236, 238, 240), { CastShadow = false })
		local glow = Instance.new("SurfaceLight")
		glow.Face = Enum.NormalId.Back
		glow.Range = 14
		glow.Angle = 90
		glow.Brightness = 0.8
		glow.Color = Color3.fromRGB(240, 244, 255)
		glow.Parent = strip
	end
	for i = 0, 15 do
		b:Box(Vector3.new(4.3, 1.2, 0.2), at(-32.25 + i * 4.3, 2.2, -47.75), M.SmoothPlastic, i % 2 == 0 and C.Yellow or Color3.fromRGB(28, 28, 30), { CastShadow = false })
	end
	local plate = b:Box(Vector3.new(16, 3, 0.2), at(-22, 19.4, -47.75), M.SmoothPlastic, Color3.fromRGB(34, 35, 38), { CastShadow = false })
	signText(plate, Enum.NormalId.Back, "TEST BAY 01", 150, Color3.fromRGB(190, 190, 184))
	-- свет на подиум: сверху, ключевой спереди-слева, контровой сзади
	local podium = L + Vector3.new(0, podiumTop + 3, -24)
	local function spotAt(pos, brightness, angle, color, shadows)
		local lamp = b:Box(Vector3.new(1.2, 1.2, 1.8), CFrame.lookAt(L + pos, podium), M.Metal, Color3.fromRGB(30, 30, 32))
		local spot = Instance.new("SpotLight")
		spot.Face = Enum.NormalId.Front
		spot.Range = 48
		spot.Angle = angle
		spot.Brightness = brightness
		spot.Color = color
		spot.Shadows = shadows
		spot.Parent = lamp
	end
	spotAt(Vector3.new(0, H - 3, -22), 2.2, 45, Color3.fromRGB(255, 246, 232), true)
	spotAt(Vector3.new(-14, 16, -6), 3, 35, Color3.fromRGB(255, 240, 216), true)
	spotAt(Vector3.new(16, 14, -10), 1.4, 35, Color3.fromRGB(220, 232, 255), false)
	spotAt(Vector3.new(6, 18, -44), 2.4, 30, Color3.fromRGB(255, 236, 200), false)
	local showcase = Instance.new("Part")
	showcase.Name = "Showcase"
	showcase.Anchored = true
	showcase.CanCollide = false
	showcase.CanQuery = false
	showcase.Transparency = 1
	showcase.Size = Vector3.new(1, 1, 1)
	showcase.CFrame = at(0, podiumTop, -24) * CFrame.Angles(0, math.rad(200), 0)
	showcase.Parent = root
	-- стенд с оружием (запад)
	b:Box(Vector3.new(1, 14, 40), at(-W / 2 + 1.5, 9, -6), M.SmoothPlastic, Color3.fromRGB(30, 31, 34))
	local rack = b:Box(Vector3.new(0.2, 0.2, 0.2), at(-W / 2 + 2.6, 9, -6), M.SmoothPlastic, C.White, { Transparency = 1, CanCollide = false, CanQuery = false })
	rack.Name = "WeaponRack"
	-- тир (восток): кабинки, мишени-манекены на линии
	for i = -2, 2 do
		local z = i * 9
		b:Box(Vector3.new(12, 4, 0.6), at(40, 2, z - 4.5), M.SmoothPlastic, Color3.fromRGB(40, 41, 44))
		b:Box(Vector3.new(1.2, 4, 8.4), at(34, 2, z), M.Wood, C.WoodDark)
	end
	b:Box(Vector3.new(0.6, 0.06, 46), at(35, 0.03, 0), M.SmoothPlastic, C.Yellow, { CastShadow = false })
	local template = StarterPlayer:FindFirstChild("StarterCharacter") or ServerStorage:FindFirstChild("CharacterAssets") and ServerStorage.CharacterAssets:FindFirstChild("Dummy")
	if template then
		for i = -2, 2 do
			local d = template:Clone()
			d.Name = "RangeDummy"
			for _, p in ipairs(d:GetDescendants()) do
				if p:IsA("BasePart") then
					p.Anchored = true
				elseif p:IsA("Script") or p:IsA("LocalScript") then
					p:Destroy()
				end
			end
			local hum = d:FindFirstChildOfClass("Humanoid")
			if hum then
				hum:Destroy()
			end
			d:PivotTo(at(62, DummyRig.HipHeight + DummyRig.RootSize.Y / 2 + 1, i * 9) * CFrame.Angles(0, math.rad(90), 0))
			b:Box(Vector3.new(3, 1, 3), at(62, 0.5, i * 9), M.Metal, C.SteelDark)
			d.Parent = root
		end
	end
	-- ящики, контейнер, тележки
	b:Container(at(-48, 0, 34) * CFrame.Angles(0, 0.04, 0), C.ContainerOrange, false)
	b:Crate(at(-30, 0, 40), Vector3.new(5, 5, 5))
	b:Crate(at(-25, 0, 42), Vector3.new(4, 4, 4))
	b:Crate(at(-27, 5, 40), Vector3.new(3, 3, 3))
	b:Pallet(at(50, 0, 40), 3)
	b:Barrel(at(58, 0, 42))
	b:Barrel(at(60.3, 0, 41), C.ContainerRed)
	-- граница (на всякий случай)
	b:Bounds(L, Vector3.new(W - 2, 0, D - 2), H)
	-- место появления (юг)
	spawns = {}
	for i = 1, 16 do
		local x = ((i - 1) % 8 - 3.5) * 6
		local z = 22 + math.floor((i - 1) / 8) * 7
		table.insert(spawns, at(x, DummyRig.HipHeight + DummyRig.RootSize.Y / 2 + 0.05, z) * CFrame.Angles(0, 0, 0))
	end
	log:Info("лобби построено: %d деталей", b.Parts)
	return root
end

-- Точка появления в лобби (случайная из 16 на юге ангара, лицом к подиуму)
function LobbySystem.SpawnPoint()
	if #spawns == 0 then
		return nil
	end
	return spawns[rng:NextInteger(1, #spawns)]
end

function LobbySystem.Init(context)
	MapKit = require(ServerStorage:WaitForChild("Maps"):WaitForChild("MapKit"))
	LobbySystem.Build()
	local maps = context.Get("MapSystem")
	maps.SetLobbyLighting(LobbySystem.Lighting)
	maps.ApplyLighting(LobbySystem.Lighting)
end

return LobbySystem
