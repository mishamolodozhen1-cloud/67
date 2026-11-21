-- UI: единый минималистичный стиль интерфейса и помощники для создания элементов.
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local UI = {}

UI.Colors = {
	Panel = Color3.fromRGB(12, 14, 18),
	PanelLight = Color3.fromRGB(28, 31, 38),
	Text = Color3.fromRGB(240, 240, 236),
	Muted = Color3.fromRGB(150, 156, 166),
	Accent = Color3.fromRGB(226, 52, 52),
	Amber = Color3.fromRGB(255, 196, 70),
	Good = Color3.fromRGB(90, 220, 130),
	Warn = Color3.fromRGB(255, 120, 70),
	Anomaly = Color3.fromRGB(190, 120, 255),
}

-- Телефон или планшет без клавиатуры
UI.IsTouch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

local GUI_CLASSES = {
	Frame = true,
	TextLabel = true,
	TextButton = true,
	ImageLabel = true,
	ImageButton = true,
	ScrollingFrame = true,
}

function UI.new(className, props, parent)
	local inst = Instance.new(className)
	if GUI_CLASSES[className] then
		inst.BorderSizePixel = 0
	end
	for k, v in pairs(props or {}) do
		inst[k] = v
	end
	inst.Parent = parent
	return inst
end

function UI.corner(parent, radius)
	return UI.new("UICorner", { CornerRadius = UDim.new(0, radius or 10) }, parent)
end

function UI.stroke(parent, color, thickness, transparency)
	return UI.new("UIStroke", {
		Color = color or Color3.fromRGB(255, 255, 255),
		Thickness = thickness or 1,
		Transparency = transparency or 0.85,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, parent)
end

function UI.padding(parent, px)
	return UI.new("UIPadding", {
		PaddingLeft = UDim.new(0, px),
		PaddingRight = UDim.new(0, px),
		PaddingTop = UDim.new(0, px),
		PaddingBottom = UDim.new(0, px),
	}, parent)
end

function UI.list(parent, gap, horizontal)
	return UI.new("UIListLayout", {
		Padding = UDim.new(0, gap or 6),
		FillDirection = horizontal and Enum.FillDirection.Horizontal or Enum.FillDirection.Vertical,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, parent)
end

-- Полупрозрачная тёмная панель со скруглением
function UI.panel(props, parent)
	local f = UI.new("Frame", {
		BackgroundColor3 = UI.Colors.Panel,
		BackgroundTransparency = 0.25,
	}, parent)
	for k, v in pairs(props or {}) do
		f[k] = v
	end
	UI.corner(f, 12)
	UI.stroke(f, Color3.fromRGB(255, 255, 255), 1, 0.9)
	return f
end

function UI.text(text, props, parent)
	local t = UI.new("TextLabel", {
		BackgroundTransparency = 1,
		Text = text,
		TextColor3 = UI.Colors.Text,
		Font = Enum.Font.GothamMedium,
		TextSize = 16,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, parent)
	for k, v in pairs(props or {}) do
		t[k] = v
	end
	return t
end

-- Звук нажатия (его задаёт клиент, когда загружен модуль звуков)
UI.ClickSound = nil

-- Кнопка. onClick срабатывает и от мыши, и от касания.
-- Состояния: наведение — светлее, нажатие — кнопка «вдавливается», отпускание — пружинит назад, щелчок.
function UI.button(text, props, parent, onClick)
	local b = UI.new("TextButton", {
		BackgroundColor3 = UI.Colors.PanelLight,
		BackgroundTransparency = 0.1,
		Text = text,
		TextColor3 = UI.Colors.Text,
		Font = Enum.Font.GothamBold,
		TextSize = 16,
		AutoButtonColor = true,
	}, parent)
	for k, v in pairs(props or {}) do
		b[k] = v
	end
	UI.corner(b, 10)
	local press = UI.new("UIScale", { Name = "Press", Scale = 1 }, b)
	b.MouseButton1Down:Connect(function()
		TweenService:Create(press, TweenInfo.new(0.07, Enum.EasingStyle.Quad), { Scale = 0.95 }):Play()
	end)
	local function release()
		TweenService:Create(press, TweenInfo.new(0.32, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	end
	b.MouseButton1Up:Connect(release)
	b.MouseLeave:Connect(release)
	if onClick then
		b.Activated:Connect(function(...)
			release()
			if UI.ClickSound then
				task.spawn(UI.ClickSound)
			end
			onClick(...)
		end)
	end
	return b
end

-- Стрелка из двух полосок (у шрифтов на телефоне не всегда есть символы стрелок).
-- dir: "Down", "Up", "Left", "Right"
local DIR_ANGLE = { Down = 0, Left = 90, Up = 180, Right = 270 }
function UI.chevron(parent, dir, size, color, thickness)
	size = size or 16
	thickness = thickness or 3
	local holder = UI.new("Frame", {
		Name = "Chevron",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(size, size),
		BackgroundTransparency = 1,
	}, parent)
	local theta = math.rad(DIR_ANGLE[dir] or 0)
	local cos, sin = math.cos(theta), math.sin(theta)
	local len = size * 0.62
	local c = len / 2 * 0.7071
	local vy = len * 0.7071 / 2 -- вершина «V» чуть ниже центра
	local bars = {}
	for _, side in ipairs({ -1, 1 }) do
		local x, y = side * c, vy - c
		local rx, ry = x * cos - y * sin, x * sin + y * cos
		local bar = UI.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, rx, 0.5, ry),
			Size = UDim2.fromOffset(len, thickness),
			BackgroundColor3 = color or UI.Colors.Text,
			Rotation = -side * 45 + (DIR_ANGLE[dir] or 0),
		}, holder)
		UI.corner(bar, math.ceil(thickness / 2))
		table.insert(bars, bar)
	end
	holder:SetAttribute("Dir", dir)
	return holder, bars
end

-- Круглая отметка: пустая (обводка) или заполненная
function UI.dot(parent, size, color, filled)
	local d = UI.new("Frame", {
		Name = "Dot",
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = color,
		BackgroundTransparency = filled and 0 or 1,
	}, parent)
	UI.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, d)
	local st = UI.stroke(d, color, 2, filled and 1 or 0)
	d:SetAttribute("Filled", filled == true)
	return d, st
end

function UI.setDot(d, color, filled)
	d.BackgroundColor3 = color
	d.BackgroundTransparency = filled and 0 or 1
	local st = d:FindFirstChildOfClass("UIStroke")
	if st then
		st.Color = color
		st.Transparency = filled and 1 or 0
	end
end

-- Переключатель «вкл/выкл»: дорожка и бегунок, который плавно переезжает
function UI.toggle(parent, props, get, onChange)
	local b = UI.new("TextButton", {
		Size = UDim2.fromOffset(62, 32),
		BackgroundColor3 = UI.Colors.PanelLight,
		Text = "",
		AutoButtonColor = false,
	}, parent)
	for k, v in pairs(props or {}) do
		b[k] = v
	end
	UI.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, b)
	local knob = UI.new("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Size = UDim2.fromOffset(24, 24),
		BackgroundColor3 = UI.Colors.Text,
		ZIndex = b.ZIndex + 1,
	}, b)
	UI.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, knob)
	local function refresh(animate)
		local on = get()
		local pos = on and UDim2.new(1, -28, 0.5, 0) or UDim2.new(0, 4, 0.5, 0)
		local color = on and UI.Colors.Good or Color3.fromRGB(60, 64, 74)
		if animate then
			TweenService:Create(knob, TweenInfo.new(0.22, Enum.EasingStyle.Back), { Position = pos }):Play()
			TweenService:Create(b, TweenInfo.new(0.18), { BackgroundColor3 = color }):Play()
		else
			knob.Position = pos
			b.BackgroundColor3 = color
		end
	end
	b.Activated:Connect(function()
		if UI.ClickSound then
			task.spawn(UI.ClickSound)
		end
		onChange()
		refresh(true)
	end)
	refresh(false)
	return b, refresh
end

-------------------------------------------------------------------------------
-- Масштаб интерфейса под экран (на телефоне элементы крупнее).
-- UIScale кладём в каждый корневой контейнер: он масштабирует контейнер вокруг его AnchorPoint.
-------------------------------------------------------------------------------
local scales = {}

local function currentScale()
	local cam = workspace.CurrentCamera
	if not cam then
		return 1
	end
	local v = cam.ViewportSize
	if UI.IsTouch then
		return math.clamp(math.min(v.X / 900, v.Y / 430), 0.55, 1.3)
	end
	return math.clamp(math.min(v.X / 1280, v.Y / 720), 0.75, 1.6)
end

function UI.scaled(frame)
	local s = UI.new("UIScale", { Scale = currentScale() }, frame)
	table.insert(scales, s)
	return s
end

function UI.Scale()
	return currentScale()
end

task.spawn(function()
	local cam = workspace.CurrentCamera
	while not cam do
		task.wait(0.2)
		cam = workspace.CurrentCamera
	end
	cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		local v = currentScale()
		for _, s in ipairs(scales) do
			s.Scale = v
		end
	end)
end)

return UI
