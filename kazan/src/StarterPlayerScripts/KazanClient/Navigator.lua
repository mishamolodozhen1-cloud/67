-- Навигатор для всех игроков: категории мест (полиция, больницы, аптеки, банки, магазины, кафе,
-- отели, остановки, достопримечательности), поиск по названию, метка и линия до выбранного места.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Poi = require(Shared:WaitForChild("Poi"))
local Places = require(Shared:WaitForChild("Places"))

local Navigator = {}

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local CATEGORIES = {
	{ "all", "Все", "🔎" },
	{ "police", "Полиция", "🚓" },
	{ "medical", "Медицина", "🏥" },
	{ "pharmacy", "Аптеки", "💊" },
	{ "fire", "Пожарные", "🚒" },
	{ "bank", "Банки", "🏦" },
	{ "food_shop", "Продукты", "🛒" },
	{ "shop", "Магазины", "🛍" },
	{ "food", "Кафе", "☕" },
	{ "hotel", "Отели", "🏨" },
	{ "bus", "Остановки", "🚌" },
	{ "sights", "Места", "⭐" },
	{ "culture", "Культура", "🎭" },
	{ "education", "Учёба", "🎓" },
	{ "gov", "Госучреждения", "🏛" },
}
local ICON = {}
for _, c in ipairs(CATEGORIES) do
	ICON[c[1]] = c[3]
end

local ACCENT = Color3.fromRGB(46, 160, 100)
local BG = Color3.fromRGB(22, 24, 32)
local BTN = Color3.fromRGB(48, 54, 70)
local TEXT = Color3.fromRGB(240, 242, 248)

local entries = {}
local gui, panel, list, chips, search, hud, hudLabel
local category = "all"
local target -- { name, position, attachment, beam, marker }

local function make(className, props, parent)
	local inst = Instance.new(className)
	for k, v in pairs(props) do
		inst[k] = v
	end
	inst.Parent = parent
	return inst
end

local function corner(inst, px)
	make("UICorner", { CornerRadius = UDim.new(0, px or 10) }, inst)
end

-- Перевод кириллицы и латиницы в нижний регистр для поиска
local function lower(s)
	local out = {}
	for _, cp in utf8.codes(s) do
		if cp >= 0x410 and cp <= 0x42F then
			cp = cp + 0x20
		elseif cp == 0x401 then
			cp = 0x451
		elseif cp >= 65 and cp <= 90 then
			cp = cp + 32
		end
		table.insert(out, utf8.char(cp))
	end
	return table.concat(out)
end

local function rootPart()
	local char = player.Character
	return char and char:FindFirstChild("HumanoidRootPart")
end

local function meters(studs)
	local m = studs * 0.3
	if m >= 1000 then
		return string.format("%.1f км", m / 1000)
	end
	return string.format("%d м", math.floor(m / 10 + 0.5) * 10)
end

-------------------------------------------------------------------------------
-- Метка и линия
-------------------------------------------------------------------------------
local function clearTarget()
	if target then
		for _, inst in ipairs({ target.attachment, target.beam, target.from }) do
			if inst then
				inst:Destroy()
			end
		end
	end
	target = nil
	hud.Visible = false
	player:SetAttribute("NavX", nil)
	player:SetAttribute("NavZ", nil)
end

local function setTarget(name, position)
	clearTarget()
	local att = make("Attachment", { Name = "NavTarget", WorldPosition = position + Vector3.new(0, 10, 0) }, workspace.Terrain)
	local marker = make("BillboardGui", {
		Size = UDim2.fromOffset(180, 60),
		AlwaysOnTop = true,
		LightInfluence = 0,
		StudsOffsetWorldSpace = Vector3.new(0, 4, 0),
	}, att)
	local label = make("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "📍\n" .. name,
		TextColor3 = Color3.fromRGB(120, 255, 170),
		TextStrokeTransparency = 0.2,
		TextScaled = true,
		Font = Enum.Font.GothamBlack,
	}, marker)
	make("UITextSizeConstraint", { MaxTextSize = 22 }, label)
	target = { name = name, position = position, attachment = att }
	hud.Visible = true
	player:SetAttribute("NavX", position.X)
	player:SetAttribute("NavZ", position.Z)
end

local function updateBeam()
	if not target then
		return
	end
	local hrp = rootPart()
	if not hrp then
		return
	end
	if not target.from or target.from.Parent ~= hrp then
		if target.from then
			target.from:Destroy()
		end
		target.from = make("Attachment", { Name = "NavFrom", Position = Vector3.new(0, 6, 0) }, hrp)
		if target.beam then
			target.beam:Destroy()
		end
		target.beam = make("Beam", {
			Attachment0 = target.from,
			Attachment1 = target.attachment,
			Width0 = 1.2,
			Width1 = 1.2,
			FaceCamera = true,
			LightEmission = 1,
			Color = ColorSequence.new(Color3.fromRGB(80, 255, 150)),
			Transparency = NumberSequence.new(0.25),
			Segments = 1,
		}, workspace.Terrain)
	end
	local flat = Vector3.new(hrp.Position.X - target.position.X, 0, hrp.Position.Z - target.position.Z)
	local dist = flat.Magnitude
	hudLabel.Text = "📍 " .. target.name .. "  —  " .. meters(dist)
	if dist < 24 then
		local name = target.name
		clearTarget()
		hud.Visible = true
		hudLabel.Text = "✅ Вы на месте: " .. name
		task.delay(3, function()
			if not target then
				hud.Visible = false
			end
		end)
	end
end

-------------------------------------------------------------------------------
-- Список мест
-------------------------------------------------------------------------------
local function refreshList()
	for _, c in ipairs(list:GetChildren()) do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	local hrp = rootPart()
	local here = hrp and hrp.Position or Vector3.zero
	local query = lower(search.Text or "")
	local rows = {}
	for _, e in ipairs(entries) do
		if (category == "all" or e.cat == category) and (query == "" or string.find(e.lname, query, 1, true)) then
			local d = Vector3.new(e.position.X - here.X, 0, e.position.Z - here.Z).Magnitude
			table.insert(rows, { e = e, d = d })
		end
	end
	table.sort(rows, function(a, b)
		return a.d < b.d
	end)
	for i = 1, math.min(#rows, 60) do
		local e, d = rows[i].e, rows[i].d
		local b = make("TextButton", {
			Size = UDim2.new(1, 0, 0, 46),
			BackgroundColor3 = BTN,
			Text = "",
			LayoutOrder = i,
			AutoButtonColor = true,
		}, list)
		corner(b, 8)
		make("TextLabel", {
			Size = UDim2.new(1, -96, 1, 0),
			Position = UDim2.fromOffset(10, 0),
			BackgroundTransparency = 1,
			Text = (ICON[e.cat] or "•") .. "  " .. e.name,
			TextColor3 = TEXT,
			Font = Enum.Font.GothamBold,
			TextSize = 15,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}, b)
		make("TextLabel", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -10, 0, 0),
			Size = UDim2.new(0, 80, 1, 0),
			BackgroundTransparency = 1,
			Text = meters(d),
			TextColor3 = Color3.fromRGB(150, 210, 175),
			Font = Enum.Font.GothamMedium,
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Right,
		}, b)
		b.Activated:Connect(function()
			setTarget(e.name, e.position)
			panel.Visible = false
		end)
	end
	if #rows == 0 then
		make("TextLabel", {
			Size = UDim2.new(1, 0, 0, 40),
			BackgroundTransparency = 1,
			Text = "Ничего не найдено",
			TextColor3 = Color3.fromRGB(170, 176, 190),
			Font = Enum.Font.GothamMedium,
			TextSize = 15,
		}, list)
	end
end

local function selectCategory(key)
	category = key
	for _, c in ipairs(chips:GetChildren()) do
		if c:IsA("TextButton") then
			c.BackgroundColor3 = (c.Name == key) and ACCENT or BTN
		end
	end
	refreshList()
end

function Navigator.Start(parentGui)
	for _, p in ipairs(Poi) do
		table.insert(entries, { cat = p[1], name = p[2], position = Vector3.new(p[3], 0, p[4]), lname = lower(p[2]) })
	end
	for _, place in ipairs(Places.List) do
		table.insert(entries, { cat = "sights", name = place.name, position = Vector3.new(place.position.X, 0, place.position.Z), lname = lower(place.name) })
	end

	gui = parentGui
	local open = make("TextButton", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 10),
		Size = UDim2.fromOffset(150, 44),
		BackgroundColor3 = ACCENT,
		Text = "🗺  Навигатор",
		TextColor3 = TEXT,
		Font = Enum.Font.GothamBold,
		TextSize = 17,
	}, gui)
	corner(open, 12)

	panel = make("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 60),
		BackgroundColor3 = BG,
		Visible = false,
	}, gui)
	corner(panel, 14)
	make("UIStroke", { Color = ACCENT, Thickness = 2 }, panel)
	local function layout()
		local vp = camera.ViewportSize
		panel.Size = UDim2.fromOffset(math.min(400, vp.X - 20), math.min(470, vp.Y - 90))
	end
	layout()
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(layout)

	search = make("TextBox", {
		Position = UDim2.fromOffset(10, 10),
		Size = UDim2.new(1, -20, 0, 38),
		BackgroundColor3 = BTN,
		PlaceholderText = "🔎 Поиск: аптека, банк, улица…",
		PlaceholderColor3 = Color3.fromRGB(150, 156, 170),
		Text = "",
		ClearTextOnFocus = false,
		TextColor3 = TEXT,
		Font = Enum.Font.Gotham,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, panel)
	corner(search, 9)
	make("UIPadding", { PaddingLeft = UDim.new(0, 10) }, search)
	search:GetPropertyChangedSignal("Text"):Connect(refreshList)

	chips = make("ScrollingFrame", {
		Position = UDim2.fromOffset(10, 54),
		Size = UDim2.new(1, -20, 0, 42),
		BackgroundTransparency = 1,
		ScrollBarThickness = 3,
		ScrollingDirection = Enum.ScrollingDirection.X,
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		CanvasSize = UDim2.new(),
	}, panel)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, chips)
	for i, c in ipairs(CATEGORIES) do
		local key = c[1]
		local b = make("TextButton", {
			Name = key,
			LayoutOrder = i,
			Size = UDim2.fromOffset(0, 36),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundColor3 = BTN,
			Text = "  " .. c[3] .. " " .. c[2] .. "  ",
			TextColor3 = TEXT,
			Font = Enum.Font.GothamBold,
			TextSize = 14,
		}, chips)
		corner(b, 18)
		b.Activated:Connect(function()
			selectCategory(key)
		end)
	end

	list = make("ScrollingFrame", {
		Position = UDim2.fromOffset(10, 104),
		Size = UDim2.new(1, -20, 1, -114),
		BackgroundTransparency = 1,
		ScrollBarThickness = 5,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
	}, panel)
	make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, list)
	make("UIPadding", { PaddingRight = UDim.new(0, 6) }, list)

	hud = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 74),
		Size = UDim2.fromOffset(340, 40),
		BackgroundColor3 = Color3.fromRGB(16, 40, 28),
		BackgroundTransparency = 0.15,
		Visible = false,
	}, gui)
	corner(hud, 12)
	hudLabel = make("TextLabel", {
		Size = UDim2.new(1, -50, 1, 0),
		Position = UDim2.fromOffset(10, 0),
		BackgroundTransparency = 1,
		TextColor3 = TEXT,
		Font = Enum.Font.GothamBold,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, hud)
	local cancel = make("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -6, 0.5, 0),
		Size = UDim2.fromOffset(32, 32),
		BackgroundColor3 = Color3.fromRGB(196, 62, 62),
		Text = "✕",
		TextColor3 = TEXT,
		Font = Enum.Font.GothamBold,
		TextSize = 16,
	}, hud)
	corner(cancel, 16)
	cancel.Activated:Connect(clearTarget)

	open.Activated:Connect(function()
		panel.Visible = not panel.Visible
		if panel.Visible then
			selectCategory(category)
		end
	end)

	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc = acc + dt
		if acc > 0.2 then
			acc = 0
			updateBeam()
		end
	end)
end

return Navigator
