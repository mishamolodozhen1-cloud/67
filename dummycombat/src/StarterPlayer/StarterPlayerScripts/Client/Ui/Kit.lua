-- Kit: общие детали интерфейса DUMMY COMBAT — цвета, шрифты, рамки, кнопки, звуки интерфейса.
-- Стиль: тёмные полупрозрачные панели, белый текст, акцент — охра манекена, без неона и лишних украшений.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local UiAssets = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("UiAssets"))

local Kit = {}

Kit.Colors = table.freeze({
	Bg = Color3.fromRGB(12, 13, 16),
	Panel = Color3.fromRGB(22, 24, 28),
	Panel2 = Color3.fromRGB(32, 34, 39),
	Line = Color3.fromRGB(70, 72, 78),
	Text = Color3.fromRGB(240, 240, 236),
	Dim = Color3.fromRGB(150, 151, 148),
	Accent = Color3.fromRGB(214, 180, 104),
	AccentDark = Color3.fromRGB(150, 122, 62),
	Danger = Color3.fromRGB(255, 92, 72),
	Good = Color3.fromRGB(120, 204, 128),
	Blue = Color3.fromRGB(90, 150, 240),
	Red = Color3.fromRGB(232, 86, 70),
	Shadow = Color3.fromRGB(8, 8, 10),
})
local C = Kit.Colors

Kit.Fonts = table.freeze({
	Title = Enum.Font.GothamBlack,
	Bold = Enum.Font.GothamBold,
	Medium = Enum.Font.GothamMedium,
	Regular = Enum.Font.Gotham,
})

function Kit.Corner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 8)
	c.Parent = parent
	return c
end

function Kit.Stroke(parent, color, thickness, transparency)
	local s = Instance.new("UIStroke")
	s.Color = color or C.Line
	s.Thickness = thickness or 1
	s.Transparency = transparency or 0.4
	s.ApplyStrokeMode = parent:IsA("TextLabel") and Enum.ApplyStrokeMode.Contextual or Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

function Kit.Padding(parent, px)
	local p = Instance.new("UIPadding")
	local u = UDim.new(0, px or 10)
	p.PaddingLeft, p.PaddingRight, p.PaddingTop, p.PaddingBottom = u, u, u, u
	p.Parent = parent
	return p
end

function Kit.List(parent, gap, horizontal, align)
	local l = Instance.new("UIListLayout")
	l.Padding = UDim.new(0, gap or 6)
	l.FillDirection = horizontal and Enum.FillDirection.Horizontal or Enum.FillDirection.Vertical
	l.SortOrder = Enum.SortOrder.LayoutOrder
	if align then
		l.HorizontalAlignment = align
	end
	l.Parent = parent
	return l
end

function Kit.Frame(parent, props)
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.BackgroundColor3 = C.Panel
	f.BackgroundTransparency = 0.12
	for k, v in pairs(props or {}) do
		f[k] = v
	end
	f.Parent = parent
	return f
end

function Kit.Label(parent, text, size, font, color, props)
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Text = text or ""
	t.TextSize = size or 16
	t.Font = font or Kit.Fonts.Medium
	t.TextColor3 = color or C.Text
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.TextYAlignment = Enum.TextYAlignment.Center
	t.RichText = false
	for k, v in pairs(props or {}) do
		t[k] = v
	end
	t.Parent = parent
	return t
end

-- Тень у текста поверх игры (тонкая тёмная обводка) — читается на любом фоне
function Kit.Outline(label, transparency)
	local s = Instance.new("UIStroke")
	s.Color = C.Shadow
	s.Thickness = 1
	s.Transparency = transparency or 0.45
	s.Parent = label
	return s
end

-------------------------------------------------------------------------------
-- Звуки интерфейса
-------------------------------------------------------------------------------
local uiGroup = nil

function Kit.SoundGroup(name)
	local g = SoundService:FindFirstChild(name)
	if not g then
		g = Instance.new("SoundGroup")
		g.Name = name
		g.Volume = 1
		g.Parent = SoundService
	end
	return g
end

function Kit.PlaySound(name, volume, pitch)
	local r = UiAssets.Sfx.Sounds[name]
	if not r then
		return nil
	end
	uiGroup = uiGroup or Kit.SoundGroup("DC_UI")
	local s = Instance.new("Sound")
	s.SoundId = UiAssets.Sfx.Id
	s.PlaybackRegionsEnabled = true
	s.PlaybackRegion = NumberRange.new(r.Start, r.Stop)
	s.Volume = volume or 0.6
	s.PlaybackSpeed = pitch or 1
	s.SoundGroup = uiGroup
	s.Parent = SoundService
	s:Play()
	task.delay((r.Stop - r.Start) / s.PlaybackSpeed + 0.2, function()
		s:Destroy()
	end)
	return s
end

-------------------------------------------------------------------------------
-- Кнопки
-------------------------------------------------------------------------------
-- style: "Primary" (охра, тёмный текст), "Secondary" (тёмная), "Ghost" (прозрачная с рамкой)
function Kit.Button(parent, text, style, props)
	local b = Instance.new("TextButton")
	b.AutoButtonColor = false
	b.BorderSizePixel = 0
	b.Text = text
	b.Font = Kit.Fonts.Bold
	b.TextSize = 18
	style = style or "Secondary"
	local base, hover, textColor
	if style == "Primary" then
		base, hover, textColor = C.Accent, Color3.fromRGB(232, 200, 126), Color3.fromRGB(20, 18, 14)
		b.BackgroundTransparency = 0
	elseif style == "Ghost" then
		base, hover, textColor = C.Panel2, C.Panel2, C.Text
		b.BackgroundTransparency = 1
		Kit.Stroke(b, C.Line, 1, 0.3)
	else
		base, hover, textColor = C.Panel2, Color3.fromRGB(48, 50, 56), C.Text
		b.BackgroundTransparency = 0.05
	end
	b.BackgroundColor3 = base
	b.TextColor3 = textColor
	Kit.Corner(b, 6)
	for k, v in pairs(props or {}) do
		b[k] = v
	end
	local info = TweenInfo.new(0.12, Enum.EasingStyle.Quad)
	b.MouseEnter:Connect(function()
		if b.Active then
			TweenService:Create(b, info, { BackgroundColor3 = hover, BackgroundTransparency = style == "Ghost" and 0.6 or b.BackgroundTransparency }):Play()
			Kit.PlaySound("Hover", 0.35)
		end
	end)
	b.MouseLeave:Connect(function()
		TweenService:Create(b, info, { BackgroundColor3 = base, BackgroundTransparency = style == "Ghost" and 1 or (style == "Primary" and 0 or 0.05) }):Play()
	end)
	b.Activated:Connect(function()
		if b.Active then
			Kit.PlaySound("Click", 0.5)
		end
	end)
	b.Parent = parent
	return b
end

-- Полоса прогресса: возвращает рамку и функцию set(0..1)
function Kit.Bar(parent, color, props)
	local bg = Kit.Frame(parent, { BackgroundColor3 = Color3.fromRGB(60, 62, 66), BackgroundTransparency = 0.35 })
	for k, v in pairs(props or {}) do
		bg[k] = v
	end
	Kit.Corner(bg, 3)
	local fill = Kit.Frame(bg, { BackgroundColor3 = color or C.Accent, BackgroundTransparency = 0, Size = UDim2.fromScale(0, 1) })
	Kit.Corner(fill, 3)
	return bg, function(k)
		fill.Size = UDim2.fromScale(math.clamp(k, 0, 1), 1)
	end, fill
end

-- Холст интерфейса в «единицах дизайна»: рамка на всю область ScreenGui с UIScale. Масштаб s подбирается так,
-- чтобы в экран помещались designW × designH единиц (s = min(высота/designH, ширина/designW) в пределах
-- minS..maxS), а размер рамки — область / s: после UIScale рамка ровно закрывает экран (UIScale уменьшает и саму
-- рамку, поэтому без деления на s она заняла бы только часть экрана). Возвращает рамку и функцию «текущий масштаб».
function Kit.Canvas(gui, designW, designH, minS, maxS)
	local canvas = Instance.new("Frame")
	canvas.Name = "Canvas"
	canvas.BackgroundTransparency = 1
	canvas.BorderSizePixel = 0
	local sc = Instance.new("UIScale")
	sc.Parent = canvas
	local function fit()
		local a = gui.AbsoluteSize
		if not a or a.X < 2 or a.Y < 2 then
			a = workspace.CurrentCamera.ViewportSize
		end
		local s = math.clamp(math.min(a.Y / designH, a.X / designW), minS or 0.6, maxS or 1.5)
		sc.Scale = s
		canvas.Size = UDim2.fromScale(1 / s, 1 / s)
	end
	fit()
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	canvas.Parent = gui
	return canvas, function()
		return sc.Scale
	end
end

-- Холст в безопасной области ScreenGui, который сам занимает весь экран (IgnoreGuiInset = true: там же прицел
-- и метки по центру экрана): рамка ниже полосы кнопок Roblox, внутри — Kit.Canvas по её размеру
function Kit.SafeCanvas(gui, designW, designH, minS, maxS)
	local GuiService = game:GetService("GuiService")
	local holder = Instance.new("Frame")
	holder.Name = "Safe"
	holder.BackgroundTransparency = 1
	holder.BorderSizePixel = 0
	local canvas = Instance.new("Frame")
	canvas.Name = "Canvas"
	canvas.BackgroundTransparency = 1
	canvas.BorderSizePixel = 0
	local sc = Instance.new("UIScale")
	sc.Parent = canvas
	local function fit()
		local vp = workspace.CurrentCamera.ViewportSize
		local top = GuiService:GetGuiInset().Y
		local own = gui.IgnoreGuiInset and top or 0
		holder.Position = UDim2.fromOffset(0, own)
		holder.Size = UDim2.new(1, 0, 1, -own)
		local s = math.clamp(math.min((vp.Y - top) / designH, vp.X / designW), minS or 0.6, maxS or 1.5)
		sc.Scale = s
		canvas.Size = UDim2.fromScale(1 / s, 1 / s)
	end
	fit()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
	canvas.Parent = holder
	holder.Parent = gui
	return canvas, function()
		return sc.Scale
	end
end

-- ScreenGui: не залезать под кнопки Roblox и вырез экрана
function Kit.SafeGui(gui)
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.IgnoreGuiInset = false
	return gui
end

function Kit.Tween(obj, time, props, style)
	local tw = TweenService:Create(obj, TweenInfo.new(time, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end

return Kit
