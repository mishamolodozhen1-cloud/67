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
	Brightness = 2,
	Ambient = Color3.fromRGB(58, 58, 64),
	OutdoorAmbient = Color3.fromRGB(110, 110, 116),
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
	-- пол
	b:Box(Vector3.new(W, 2, D), at(0, -1, 0), M.SmoothPlastic, Color3.fromRGB(70, 71, 74), { Reflectance = 0.06 })
	for x = -60, 60, 20 do
		b:Box(Vector3.new(0.15, 0.04, D - 4), at(x, 0.02, 0), M.SmoothPlastic, Color3.fromRGB(52, 53, 56), { CastShadow = false })
	end
	b:Box(Vector3.new(W - 8, 0.05, 0.6), at(0, 0.03, 30), M.SmoothPlastic, C.Yellow, { CastShadow = false })
	-- стены из профлиста
	local wallColor = Color3.fromRGB(88, 92, 96)
	b:Box(Vector3.new(W, H, 1), at(0, H / 2, -D / 2), M.CorrodedMetal, wallColor)
	b:Box(Vector3.new(W, H, 1), at(0, H / 2, D / 2), M.CorrodedMetal, wallColor)
	b:Box(Vector3.new(1, H, D), at(-W / 2, H / 2, 0), M.CorrodedMetal, wallColor)
	b:Box(Vector3.new(1, H, D), at(W / 2, H / 2, 0), M.CorrodedMetal, wallColor)
	for x = -W / 2 + 4, W / 2 - 4, 4 do
		b:Box(Vector3.new(0.5, H - 2, 0.3), at(x, H / 2, D / 2 - 0.6), M.Metal, wallColor, { CastShadow = false })
	end
	-- крыша, фермы, световые полосы
	b:Box(Vector3.new(W + 2, 1, D + 2), at(0, H + 0.5, 0), M.Metal, Color3.fromRGB(50, 52, 56))
	for x = -60, 60, 15 do
		b:Box(Vector3.new(1, 2.4, D - 2), at(x, H - 1.2, 0), M.Metal, Color3.fromRGB(42, 44, 48), { CastShadow = false })
		b:Box(Vector3.new(4, 0.2, D - 10), at(x + 7.5, H - 0.2, 0), M.SmoothPlastic, Color3.fromRGB(248, 246, 238), { CastShadow = false, Transparency = 0.05 })
		local stripe = b:Box(Vector3.new(4, 0.2, 2), at(x + 7.5, H - 0.4, 0), M.SmoothPlastic, Color3.fromRGB(248, 246, 238), { Transparency = 1, CastShadow = false })
		local light = Instance.new("SurfaceLight")
		light.Face = Enum.NormalId.Bottom
		light.Range = 40
		light.Angle = 120
		light.Brightness = 1.2
		light.Color = Color3.fromRGB(255, 248, 236)
		light.Parent = stripe
	end
	-- подиум и стена с названием (север)
	b:Cylinder(1.2, 16, at(0, 0.6, -24), M.SmoothPlastic, Color3.fromRGB(34, 35, 38), { Reflectance = 0.08 })
	b:Cylinder(0.2, 16.6, at(0, 1.22, -24), M.SmoothPlastic, C.Yellow, { CastShadow = false })
	local back = b:Box(Vector3.new(70, 22, 1.5), at(0, 13, -48.5), M.SmoothPlastic, Color3.fromRGB(26, 27, 30))
	signText(back, Enum.NormalId.Back, "DUMMY COMBAT", 230, Color3.fromRGB(232, 228, 216))
	local stripe = b:Box(Vector3.new(64, 0.6, 0.2), at(0, 7.4, -47.6), M.SmoothPlastic, C.Yellow, { CastShadow = false })
	stripe.Name = "SignStripe"
	for _, x in ipairs({ -16, 16 }) do
		local lamp = b:Box(Vector3.new(1.4, 1.4, 2), at(x, 22, -14) * CFrame.Angles(math.rad(-50), 0, 0), M.Metal, Color3.fromRGB(30, 30, 32))
		local spot = Instance.new("SpotLight")
		spot.Face = Enum.NormalId.Front
		spot.Range = 40
		spot.Angle = 40
		spot.Brightness = 4
		spot.Color = Color3.fromRGB(255, 240, 214)
		spot.Shadows = true
		spot.Parent = lamp
	end
	local showcase = Instance.new("Part")
	showcase.Name = "Showcase"
	showcase.Anchored = true
	showcase.CanCollide = false
	showcase.CanQuery = false
	showcase.Transparency = 1
	showcase.Size = Vector3.new(1, 1, 1)
	showcase.CFrame = at(0, 1.2, -24) * CFrame.Angles(0, math.rad(200), 0)
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
