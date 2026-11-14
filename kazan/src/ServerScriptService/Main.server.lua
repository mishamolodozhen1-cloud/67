-- Точка входа сервера: освещение, админка, затем постройка города.
local ServerScriptService = game:GetService("ServerScriptService")
local Lighting = game:GetService("Lighting")

local function make(className, props, parent)
	local inst = Instance.new(className)
	for k, v in pairs(props) do
		inst[k] = v
	end
	inst.Parent = parent
	return inst
end

-- Летний день над Казанью (широта 55,8°)
Lighting.ClockTime = 14.5
Lighting.GeographicLatitude = 55.8
Lighting.Brightness = 3
Lighting.Ambient = Color3.fromRGB(62, 62, 70)
Lighting.OutdoorAmbient = Color3.fromRGB(128, 128, 134)
Lighting.EnvironmentDiffuseScale = 1
Lighting.EnvironmentSpecularScale = 1
Lighting.GlobalShadows = true
Lighting.ShadowSoftness = 0.2
for _, c in ipairs(Lighting:GetChildren()) do
	if c:IsA("PostEffect") or c:IsA("Atmosphere") then
		c:Destroy()
	end
end
make("Atmosphere", {
	Density = 0.27,
	Offset = 0.15,
	Color = Color3.fromRGB(199, 206, 214),
	Decay = Color3.fromRGB(106, 112, 125),
	Glare = 0.2,
	Haze = 1.2,
}, Lighting)
make("BloomEffect", { Intensity = 0.4, Size = 24, Threshold = 2 }, Lighting)
make("SunRaysEffect", { Intensity = 0.05, Spread = 0.6 }, Lighting)
make("ColorCorrectionEffect", { Saturation = 0.06, Contrast = 0.05 }, Lighting)

require(ServerScriptService:WaitForChild("AdminService")).Start()

local CityBuilder = require(ServerScriptService:WaitForChild("CityBuilder"))
local Landmarks = require(ServerScriptService:WaitForChild("Landmarks"))
local Infrastructure = require(ServerScriptService:WaitForChild("Infrastructure"))

local started = os.clock()
local root = Instance.new("Folder")
root.Name = "Kazan"
root.Parent = workspace

CityBuilder.BuildTerrain()
local landmarkData = CityBuilder.BuildMisc(root)
Landmarks.BuildAll(root, landmarkData)
CityBuilder.BuildRoads(root)
CityBuilder.BuildBuildings(root)
Infrastructure.Build(root)

workspace:SetAttribute("CityReady", true)
print(string.format("[Казань] город построен за %.1f с", os.clock() - started))
