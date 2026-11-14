-- Клиент: заставка «Казань», объявления, подпись источника карты и админ-панель для админов.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

local gui = Instance.new("ScreenGui")
gui.Name = "KazanHUD"
gui.ResetOnSpawn = false
gui.DisplayOrder = 20
gui.Parent = player:WaitForChild("PlayerGui")

local function label(props)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.TextColor3 = Color3.fromRGB(255, 255, 255)
	l.TextStrokeTransparency = 0.4
	l.Font = Enum.Font.GothamBlack
	for k, v in pairs(props) do
		l[k] = v
	end
	l.Parent = gui
	return l
end

-- Обязательная подпись источника данных карты (лицензия ODbL)
label({
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -2),
	Size = UDim2.fromOffset(320, 14),
	Text = "Карта: © OpenStreetMap contributors",
	Font = Enum.Font.Gotham,
	TextSize = 11,
	TextTransparency = 0.35,
	TextStrokeTransparency = 0.7,
})

-- Заставка
local title = label({
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.3),
	Size = UDim2.new(0.8, 0, 0, 64),
	Text = "КАЗАНЬ",
	TextScaled = true,
	TextColor3 = Color3.fromRGB(255, 255, 255),
})
local subtitle = label({
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0.3, 48),
	Size = UDim2.new(0.8, 0, 0, 26),
	Text = "Исторический центр в натуральную величину",
	TextScaled = true,
	Font = Enum.Font.GothamBold,
	TextColor3 = Color3.fromRGB(190, 236, 205),
})
local status = label({
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0.3, 82),
	Size = UDim2.new(0.6, 0, 0, 20),
	Text = workspace:GetAttribute("CityReady") and "" or "Город строится…",
	TextScaled = true,
	Font = Enum.Font.GothamMedium,
	TextColor3 = Color3.fromRGB(230, 230, 230),
})
local function fadeOut(l, delay)
	task.delay(delay, function()
		TweenService:Create(l, TweenInfo.new(1.2), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	end)
end
task.spawn(function()
	while not workspace:GetAttribute("CityReady") do
		workspace:GetAttributeChangedSignal("CityReady"):Wait()
	end
	status.Text = "Добро пожаловать!"
	fadeOut(title, 3)
	fadeOut(subtitle, 3)
	fadeOut(status, 3)
end)

-- Объявления администратора
local banner = label({
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 12),
	Size = UDim2.new(0.9, 0, 0, 56),
	BackgroundTransparency = 0.25,
	BackgroundColor3 = Color3.fromRGB(20, 60, 40),
	TextWrapped = true,
	TextScaled = true,
	Font = Enum.Font.GothamBold,
	Visible = false,
})
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 12)
corner.Parent = banner
local sizeLimit = Instance.new("UITextSizeConstraint")
sizeLimit.MaxTextSize = 24
sizeLimit.Parent = banner

task.spawn(function()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local announce = remotes:WaitForChild("Announcement")
	announce.OnClientEvent:Connect(function(text, from)
		banner.Text = "📢 " .. tostring(from) .. ": " .. tostring(text)
		banner.Visible = true
		local stamp = os.clock()
		banner:SetAttribute("Stamp", stamp)
		task.delay(8, function()
			if banner:GetAttribute("Stamp") == stamp then
				banner.Visible = false
			end
		end)
	end)
end)

-- Админ-панель
local function tryAdmin()
	if player:GetAttribute("IsAdmin") == true and not gui:GetAttribute("AdminStarted") then
		gui:SetAttribute("AdminStarted", true)
		require(script:WaitForChild("AdminPanel")).Start()
	end
end
player:GetAttributeChangedSignal("IsAdmin"):Connect(tryAdmin)
tryAdmin()
