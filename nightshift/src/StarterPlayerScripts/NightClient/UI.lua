-- UI: единый минималистичный стиль интерфейса и помощники для создания элементов.
local UserInputService = game:GetService("UserInputService")

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

-- Кнопка. onClick срабатывает и от мыши, и от касания
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
	if onClick then
		b.Activated:Connect(onClick)
	end
	return b
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
