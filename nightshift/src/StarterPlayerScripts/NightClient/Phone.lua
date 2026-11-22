-- Phone: телефон охранника.
--   • достаётся из кармана: выезжает снизу с поворотом, шорох куртки; убирается так же обратно
--   • на экране — мессенджер: список чатов (директор, неизвестный номер, рация) с последним сообщением,
--     временем и счётчиком непрочитанных; в чате — «пузыри» сообщений, листаются пальцем или колёсиком
--   • строка состояния: время смены, сеть, заряд
--   • новое сообщение, пока телефон в кармане, — короткое уведомление (его показывает HUD), по нажатию
--     телефон открывается сразу на этом чате
-- Открыть/убрать: кнопка «Телефон», клавиша P, полоска внизу экрана телефона.
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Util = require(Shared:WaitForChild("Util"))

local Phone = {}

local ctx, UI
local gui, device, screenFrame, statusTime, statusBattery, titleLabel, backButton
local listPage, chatPage, listScroll, chatScroll, modalButton
local chats = {} -- имя отправителя -> { Name, Messages, Unread, Last, Color }
local open = false
local current = nil
local animToken = 0

local AVATAR_COLORS = {
	Color3.fromRGB(70, 120, 200),
	Color3.fromRGB(170, 60, 60),
	Color3.fromRGB(60, 150, 100),
	Color3.fromRGB(150, 110, 50),
}

local function initials(name)
	if string.find(name, "Неизвест") then
		return "?"
	end
	local out = {}
	for word in string.gmatch(name, "[^%s%(%)]+") do
		local first = utf8.char(utf8.codepoint(word, 1))
		table.insert(out, first)
		if #out == 2 then
			break
		end
	end
	return table.concat(out)
end

local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do
		o[k] = v
	end
	o.Parent = parent
	return o
end

local function corner(o, scale, px)
	new("UICorner", { CornerRadius = UDim.new(scale or 0, px or 0) }, o)
end

-- размер текста в пикселях от высоты экрана телефона
local function px(k)
	local h = screenFrame and screenFrame.AbsoluteSize.Y or 0
	if h < 100 then
		-- экран ещё не разложен: оценка по высоте окна
		local cam = workspace.CurrentCamera
		h = (cam and cam.ViewportSize.Y or 720) * 0.81
	end
	return math.max(9, math.floor(h * k + 0.5))
end

-------------------------------------------------------------------------------
-- Список чатов и переписка
-------------------------------------------------------------------------------
local function sortedChats()
	local list = {}
	for _, c in pairs(chats) do
		table.insert(list, c)
	end
	table.sort(list, function(a, b)
		return a.Last > b.Last
	end)
	return list
end

local function avatar(parent, chat, size)
	local a = new("TextLabel", {
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = chat.Color,
		TextColor3 = Color3.new(1, 1, 1),
		Font = Enum.Font.GothamBold,
		TextSize = math.floor(size * 0.42),
		Text = initials(chat.Name),
	}, parent)
	corner(a, 0.5)
	return a
end

local refreshList, openChat

refreshList = function()
	if not listScroll then
		return
	end
	for _, c in ipairs(listScroll:GetChildren()) do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	local rowH = px(0.1)
	local list = sortedChats()
	if #list == 0 then
		new("TextLabel", {
			Size = UDim2.new(1, 0, 0, rowH),
			BackgroundTransparency = 1,
			TextColor3 = Color3.fromRGB(140, 146, 156),
			Font = Enum.Font.Gotham,
			TextSize = px(0.026),
			Text = "Сообщений пока нет",
		}, listScroll)
		return
	end
	for i, chat in ipairs(list) do
		local last = chat.Messages[#chat.Messages]
		local row = new("TextButton", {
			Name = "Chat",
			Size = UDim2.new(1, 0, 0, rowH),
			BackgroundTransparency = 1,
			Text = "",
			AutoButtonColor = false,
			LayoutOrder = i,
		}, listScroll)
		row.Activated:Connect(function()
			openChat(chat.Name)
		end)
		local av = avatar(row, chat, math.floor(rowH * 0.66))
		av.AnchorPoint = Vector2.new(0, 0.5)
		av.Position = UDim2.new(0, px(0.016), 0.5, 0)
		local left = math.floor(rowH * 0.66) + px(0.032)
		new("TextLabel", {
			Position = UDim2.new(0, left, 0.14, 0),
			Size = UDim2.new(1, -left - px(0.09), 0.38, 0),
			BackgroundTransparency = 1,
			TextColor3 = Color3.new(1, 1, 1),
			Font = Enum.Font.GothamBold,
			TextSize = px(0.027),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Text = chat.Name,
		}, row)
		new("TextLabel", {
			Position = UDim2.new(0, left, 0.52, 0),
			Size = UDim2.new(1, -left - px(0.06), 0.36, 0),
			BackgroundTransparency = 1,
			TextColor3 = Color3.fromRGB(150, 156, 166),
			Font = Enum.Font.Gotham,
			TextSize = px(0.024),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Text = last and last.Text or "",
		}, row)
		new("TextLabel", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -px(0.016), 0.14, 0),
			Size = UDim2.new(0, px(0.09), 0.38, 0),
			BackgroundTransparency = 1,
			TextColor3 = Color3.fromRGB(150, 156, 166),
			Font = Enum.Font.Gotham,
			TextSize = px(0.021),
			TextXAlignment = Enum.TextXAlignment.Right,
			Text = last and last.Time or "",
		}, row)
		if chat.Unread > 0 then
			local badge = new("TextLabel", {
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -px(0.016), 0.54, 0),
				Size = UDim2.fromOffset(px(0.036), px(0.036)),
				BackgroundColor3 = Color3.fromRGB(40, 170, 90),
				TextColor3 = Color3.new(1, 1, 1),
				Font = Enum.Font.GothamBold,
				TextSize = px(0.02),
				Text = tostring(chat.Unread),
			}, row)
			corner(badge, 0.5)
		end
		new("Frame", {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, left, 1, 0),
			Size = UDim2.new(1, -left, 0, 1),
			BackgroundColor3 = Color3.fromRGB(40, 44, 52),
			BorderSizePixel = 0,
		}, row)
	end
end

local function bubble(msg, order)
	local holder = new("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = order,
	}, chatScroll)
	local b = new("Frame", {
		Size = UDim2.new(0.8, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Color3.fromRGB(38, 42, 50),
	}, holder)
	corner(b, 0, px(0.024))
	new("UIPadding", {
		PaddingLeft = UDim.new(0, px(0.02)),
		PaddingRight = UDim.new(0, px(0.02)),
		PaddingTop = UDim.new(0, px(0.014)),
		PaddingBottom = UDim.new(0, px(0.012)),
	}, b)
	new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, px(0.006)) }, b)
	new("TextLabel", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		TextColor3 = Color3.fromRGB(236, 238, 242),
		Font = Enum.Font.Gotham,
		TextSize = px(0.026),
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = msg.Text,
		LayoutOrder = 1,
	}, b)
	new("TextLabel", {
		Size = UDim2.new(1, 0, 0, px(0.024)),
		BackgroundTransparency = 1,
		TextColor3 = Color3.fromRGB(130, 136, 146),
		Font = Enum.Font.Gotham,
		TextSize = px(0.019),
		TextXAlignment = Enum.TextXAlignment.Right,
		Text = msg.Time,
		LayoutOrder = 2,
	}, b)
end

local function scrollToBottom()
	task.defer(function()
		if chatScroll then
			chatScroll.CanvasPosition = Vector2.new(0, math.max(0, chatScroll.AbsoluteCanvasSize.Y - chatScroll.AbsoluteSize.Y))
		end
	end)
end

local function refreshChat()
	if not (chatScroll and current) then
		return
	end
	for _, c in ipairs(chatScroll:GetChildren()) do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	local chat = chats[current]
	if not chat then
		return
	end
	for i, msg in ipairs(chat.Messages) do
		bubble(msg, i)
	end
	scrollToBottom()
end

local function showList()
	current = nil
	listPage.Visible = true
	chatPage.Visible = false
	backButton.Visible = false
	titleLabel.Text = "Сообщения"
	refreshList()
end

openChat = function(name)
	local chat = chats[name]
	if not chat then
		return
	end
	current = name
	chat.Unread = 0
	listPage.Visible = false
	chatPage.Visible = true
	backButton.Visible = true
	titleLabel.Text = name
	refreshChat()
	if ctx.Audio then
		ctx.Audio.Play("UiClick", nil, 0.3)
	end
end

-------------------------------------------------------------------------------
-- Достать / убрать
-------------------------------------------------------------------------------
local function shownPosition()
	return UI.IsTouch and UDim2.new(0.5, 0, 0.98, 0) or UDim2.new(0.64, 0, 0.97, 0)
end

local function hiddenPosition()
	return UI.IsTouch and UDim2.new(0.56, 0, 1.8, 0) or UDim2.new(0.7, 0, 1.8, 0)
end

local function updateStatus()
	if not open then
		return
	end
	statusTime.Text = Util.clock(ctx.State:GetAttribute("Minutes") or 0)
	local minutes = ctx.State:GetAttribute("Minutes") or 0
	statusBattery.Text = string.format("%d%%", math.max(9, 82 - math.floor(minutes / 12)))
end

function Phone.IsOpen()
	return open
end

function Phone.Open(chatName)
	if ctx.CameraLocked then
		return
	end
	animToken = animToken + 1
	local token = animToken
	if not open then
		ctx.HUD.CloseModals(true)
		open = true
		gui.Enabled = true
		device.Position = hiddenPosition()
		device.Rotation = 16
		ctx.Audio.Play("ClothRustle", nil, 0.5)
		TweenService:Create(device, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = shownPosition(), Rotation = -2 }):Play()
		modalButton.Visible = true
	end
	updateStatus()
	if chatName and chats[chatName] then
		openChat(chatName)
	elseif current then
		openChat(current)
	else
		showList()
	end
	task.delay(0.55, function()
		if token == animToken and open then
			TweenService:Create(device, TweenInfo.new(0.6, Enum.EasingStyle.Sine), { Rotation = 0 }):Play()
		end
	end)
end

function Phone.Close()
	if not open then
		return
	end
	open = false
	animToken = animToken + 1
	local token = animToken
	modalButton.Visible = false
	ctx.Audio.Play("ClothSwish", nil, 0.5)
	TweenService:Create(device, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = hiddenPosition(), Rotation = 14 }):Play()
	task.delay(0.4, function()
		if token == animToken and not open then
			gui.Enabled = false
		end
	end)
end

function Phone.Toggle()
	if open then
		Phone.Close()
	else
		Phone.Open()
	end
end

-- Новое сообщение. Возвращает true, если его сразу видно (открыт этот чат)
function Phone.Add(sender, text, time)
	local chat = chats[sender]
	if not chat then
		local n = 0
		for _ in pairs(chats) do
			n = n + 1
		end
		chat = { Name = sender, Messages = {}, Unread = 0, Last = 0, Color = AVATAR_COLORS[n % #AVATAR_COLORS + 1] }
		chats[sender] = chat
	end
	table.insert(chat.Messages, { Text = text, Time = time })
	chat.Last = os.clock()
	local visible = open and current == sender
	if visible then
		bubble(chat.Messages[#chat.Messages], #chat.Messages)
		scrollToBottom()
	else
		chat.Unread = chat.Unread + 1
		if open and not current then
			refreshList()
		end
	end
	return visible
end

function Phone.Clear()
	chats = {}
	current = nil
	if open then
		showList()
	end
end

function Phone.Unread()
	local n = 0
	for _, c in pairs(chats) do
		n = n + c.Unread
	end
	return n
end

-------------------------------------------------------------------------------
function Phone.Init(c)
	ctx = c
	UI = ctx.UI
	gui = new("ScreenGui", { Name = "NightPhone", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 24, Enabled = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, ctx.Player:WaitForChild("PlayerGui"))
	-- пока телефон в руке, курсор мыши свободен (можно листать и нажимать)
	modalButton = new("TextButton", { Name = "Modal", Size = UDim2.fromOffset(1, 1), BackgroundTransparency = 1, Text = "", Modal = true, Visible = false }, gui)
	device = new("Frame", {
		Name = "Device",
		AnchorPoint = Vector2.new(0.5, 1),
		Size = UDim2.fromScale(0, 0.84),
		Position = UDim2.new(0.7, 0, 1.8, 0),
		BackgroundColor3 = Color3.fromRGB(16, 16, 18),
	}, gui)
	new("UIAspectRatioConstraint", { AspectRatio = 0.485, DominantAxis = Enum.DominantAxis.Height }, device)
	corner(device, 0.13)
	new("UIStroke", { Color = Color3.fromRGB(70, 72, 78), Thickness = 2 }, device)
	-- кнопки громкости и питания на боках
	new("Frame", { Position = UDim2.new(-0.012, 0, 0.18, 0), Size = UDim2.new(0.012, 0, 0.07, 0), BackgroundColor3 = Color3.fromRGB(50, 52, 58), BorderSizePixel = 0 }, device)
	new("Frame", { Position = UDim2.new(-0.012, 0, 0.27, 0), Size = UDim2.new(0.012, 0, 0.07, 0), BackgroundColor3 = Color3.fromRGB(50, 52, 58), BorderSizePixel = 0 }, device)
	new("Frame", { Position = UDim2.new(1, 0, 0.22, 0), Size = UDim2.new(0.012, 0, 0.1, 0), BackgroundColor3 = Color3.fromRGB(50, 52, 58), BorderSizePixel = 0 }, device)
	screenFrame = new("Frame", {
		Name = "Screen",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.93, 0.965),
		BackgroundColor3 = Color3.fromRGB(12, 14, 20),
		ClipsDescendants = true,
	}, device)
	corner(screenFrame, 0.11)
	new("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(Color3.fromRGB(22, 28, 44), Color3.fromRGB(8, 9, 12)),
	}, screenFrame)
	-- камера в экране
	local cam = new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.012, 0), Size = UDim2.fromScale(0.05, 0.023), BackgroundColor3 = Color3.new(0, 0, 0) }, screenFrame)
	new("UIAspectRatioConstraint", { AspectRatio = 1 }, cam)
	corner(cam, 0.5)
	-- строка состояния
	statusTime = new("TextLabel", {
		Position = UDim2.new(0.08, 0, 0.012, 0),
		Size = UDim2.new(0.3, 0, 0.03, 0),
		BackgroundTransparency = 1,
		TextColor3 = Color3.new(1, 1, 1),
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "00:00",
	}, screenFrame)
	statusBattery = new("TextLabel", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(0.92, 0, 0.012, 0),
		Size = UDim2.new(0.34, 0, 0.03, 0),
		BackgroundTransparency = 1,
		TextColor3 = Color3.new(1, 1, 1),
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Right,
		Text = "82%",
	}, screenFrame)
	new("TextLabel", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(0.68, 0, 0.012, 0),
		Size = UDim2.new(0.16, 0, 0.03, 0),
		BackgroundTransparency = 1,
		TextColor3 = Color3.new(1, 1, 1),
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Right,
		Text = "LTE ▮▮▮",
	}, screenFrame)
	-- заголовок
	backButton = new("TextButton", {
		Position = UDim2.new(0.03, 0, 0.055, 0),
		Size = UDim2.new(0.13, 0, 0.06, 0),
		BackgroundTransparency = 1,
		TextColor3 = Color3.fromRGB(110, 170, 255),
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		Text = "‹",
		Visible = false,
	}, screenFrame)
	backButton.Activated:Connect(showList)
	titleLabel = new("TextLabel", {
		Position = UDim2.new(0.17, 0, 0.065, 0),
		Size = UDim2.new(0.74, 0, 0.042, 0),
		BackgroundTransparency = 1,
		TextColor3 = Color3.new(1, 1, 1),
		Font = Enum.Font.GothamBlack,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "Сообщения",
	}, screenFrame)
	new("Frame", { Position = UDim2.new(0, 0, 0.125, 0), Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = Color3.fromRGB(40, 44, 52), BorderSizePixel = 0 }, screenFrame)
	-- страницы
	listPage = new("Frame", { Position = UDim2.new(0, 0, 0.13, 0), Size = UDim2.new(1, 0, 0.8, 0), BackgroundTransparency = 1 }, screenFrame)
	listScroll = new("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 3,
		ScrollingDirection = Enum.ScrollingDirection.Y,
	}, listPage)
	new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }, listScroll)
	new("UIPadding", { PaddingLeft = UDim.new(0.03, 0), PaddingRight = UDim.new(0.03, 0) }, listScroll)
	chatPage = new("Frame", { Position = UDim2.new(0, 0, 0.13, 0), Size = UDim2.new(1, 0, 0.8, 0), BackgroundTransparency = 1, Visible = false }, screenFrame)
	chatScroll = new("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 3,
		ScrollingDirection = Enum.ScrollingDirection.Y,
	}, chatPage)
	new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8) }, chatScroll)
	new("UIPadding", { PaddingLeft = UDim.new(0.04, 0), PaddingRight = UDim.new(0.04, 0), PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8) }, chatScroll)
	-- полоска внизу: убрать телефон
	local home = new("TextButton", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0.995, 0),
		Size = UDim2.new(1, 0, 0.06, 0),
		BackgroundTransparency = 1,
		Text = "",
	}, screenFrame)
	local bar = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.55), Size = UDim2.new(0.36, 0, 0.12, 0), BackgroundColor3 = Color3.fromRGB(220, 222, 228), BorderSizePixel = 0 }, home)
	corner(bar, 0.5)
	new("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.new(0.6, 0, 0.32, 0),
		BackgroundTransparency = 1,
		TextColor3 = Color3.fromRGB(150, 156, 166),
		Font = Enum.Font.Gotham,
		TextScaled = true,
		Text = UI.IsTouch and "убрать в карман" or "убрать в карман [P]",
	}, home)
	home.Activated:Connect(Phone.Close)
	-- время и заряд в строке состояния
	ctx.State:GetAttributeChangedSignal("Minutes"):Connect(updateStatus)
	-- при смене размера окна размеры текста в списке и чате пересчитываются
	screenFrame:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if open then
			if current then
				refreshChat()
			else
				refreshList()
			end
		end
	end)
end

return Phone
