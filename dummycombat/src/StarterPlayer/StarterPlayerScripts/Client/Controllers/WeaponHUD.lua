-- WeaponHUD: интерфейс оружия — перекрестие, патроны, режим огня, перезарядка, отметка попадания.
--
--   • перекрестие из четырёх штрихов: расходится ровно на текущий разброс (WeaponController.CurrentSpread) —
--     что видно на экране, то и разлёт пуль; при прицеливании гаснет (целятся мушкой), на бегу — тоже;
--   • отметка попадания — косой крест на 0.2 с, когда сервер засчитал попадание (в голову — красноватый,
--     крупнее);
--   • патроны справа внизу (на телефоне — справа вверху, внизу кнопки): в магазине / в запасе, оружие и режим
--     огня; мало патронов — янтарный, пусто — подсказка RELOAD; при перезарядке — полоса прогресса.
-- Стиль — минимальный: белый текст с тонкой тёмной обводкой, без подложек.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Logger"))

local WeaponHUD = { Name = "WeaponHUD" }

local log = Logger.new("HUD")
local weapons, characters, cameraCtl = nil, nil, nil
local ui = nil
local hitAt, hitHead, hitKill = -math.huge, false, false

local WHITE = Color3.fromRGB(240, 240, 236)
local DIM = Color3.fromRGB(170, 170, 166)
local AMBER = Color3.fromRGB(236, 186, 72)
local RED = Color3.fromRGB(255, 92, 72)
local SHADOW = Color3.fromRGB(10, 10, 12)

local function stroke(parent, transparency)
	local s = Instance.new("UIStroke")
	s.Color = SHADOW
	s.Thickness = 1
	s.Transparency = transparency or 0.45
	s.Parent = parent
	return s
end

local function line(parent, w, h)
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Size = UDim2.fromOffset(w, h)
	f.BackgroundColor3 = WHITE
	f.BorderSizePixel = 0
	stroke(f, 0.5).ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	f.Parent = parent
	return f
end

local function label(parent, font, size, color, align)
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Font = font
	t.TextSize = size
	t.TextColor3 = color
	t.TextXAlignment = align or Enum.TextXAlignment.Right
	t.Text = ""
	stroke(t, 0.55)
	t.Parent = parent
	return t
end

-- На сколько пикселей от центра — угол spread (градусы) при вертикальном поле зрения fov и высоте экрана h
function WeaponHUD.SpreadPixels(spread, fov, h)
	return math.tan(math.rad(spread)) / math.tan(math.rad(fov) / 2) * (h / 2)
end

local function build()
	local hud = Players.LocalPlayer:WaitForChild("PlayerGui"):WaitForChild("HUD", 10)
	if not hud then
		log:Error("нет интерфейса HUD — прицел и патроны не показаны")
		return
	end
	local root = Instance.new("Frame")
	root.Name = "Weapon"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.Parent = hud
	-- оптический прицел снайперской: круглое поле зрения (вокруг — чёрное: обводка UIStroke круглой рамки),
	-- тонкая сетка с утолщениями к краям и делениями
	local scope = Instance.new("Frame")
	scope.Name = "Scope"
	scope.Size = UDim2.fromScale(1, 1)
	scope.BackgroundTransparency = 1
	scope.Visible = false
	scope.Parent = root
	local lens = Instance.new("Frame")
	lens.Name = "Lens"
	lens.AnchorPoint = Vector2.new(0.5, 0.5)
	lens.Position = UDim2.fromScale(0.5, 0.5)
	lens.SizeConstraint = Enum.SizeConstraint.RelativeYY
	lens.Size = UDim2.fromScale(0.92, 0.92)
	lens.BackgroundTransparency = 1
	lens.Parent = scope
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = lens
	local mask = Instance.new("UIStroke")
	mask.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	mask.Color = Color3.new(0, 0, 0)
	mask.Thickness = 2400
	mask.Parent = lens
	local rim = Instance.new("Frame")
	rim.AnchorPoint = Vector2.new(0.5, 0.5)
	rim.Position = UDim2.fromScale(0.5, 0.5)
	rim.Size = UDim2.fromScale(1, 1)
	rim.BackgroundTransparency = 1
	rim.Parent = lens
	local rimCorner = corner:Clone()
	rimCorner.Parent = rim
	local rimStroke = Instance.new("UIStroke")
	rimStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	rimStroke.Color = Color3.fromRGB(28, 30, 32)
	rimStroke.Thickness = 10
	rimStroke.Parent = rim
	local function reticle(x, y, w, h)
		local f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = UDim2.new(0.5, x, 0.5, y)
		f.Size = UDim2.new(w[1], w[2], h[1], h[2])
		f.BackgroundColor3 = Color3.fromRGB(8, 8, 8)
		f.BorderSizePixel = 0
		f.Parent = lens
		return f
	end
	reticle(0, 0, { 1, 0 }, { 0, 1 }) -- тонкие линии через всё поле
	reticle(0, 0, { 0, 1 }, { 1, 0 })
	for _, sgn in ipairs({ -1, 1 }) do -- утолщения от края к центру
		local f = reticle(0, 0, { 0.32, 0 }, { 0, 4 })
		f.AnchorPoint = Vector2.new(sgn < 0 and 0 or 1, 0.5)
		f.Position = UDim2.fromScale(sgn < 0 and 0 or 1, 0.5)
		local v = reticle(0, 0, { 0, 4 }, { 0.32, 0 })
		v.AnchorPoint = Vector2.new(0.5, sgn < 0 and 0 or 1)
		v.Position = UDim2.fromScale(0.5, sgn < 0 and 0 or 1)
	end
	for i = 1, 4 do -- деления
		for _, sgn in ipairs({ -1, 1 }) do
			reticle(sgn * i * 22, 0, { 0, 2 }, { 0, i == 4 and 12 or 7 })
			reticle(0, sgn * i * 22, { 0, i == 4 and 12 or 7 }, { 0, 2 })
		end
	end
	-- перекрестие
	local cross = Instance.new("Frame")
	cross.Name = "Crosshair"
	cross.AnchorPoint = Vector2.new(0.5, 0.5)
	cross.Position = UDim2.fromScale(0.5, 0.5)
	cross.Size = UDim2.fromOffset(0, 0)
	cross.BackgroundTransparency = 1
	cross.Parent = root
	local lines = { Top = line(cross, 2, 9), Bottom = line(cross, 2, 9), Left = line(cross, 9, 2), Right = line(cross, 9, 2) }
	local dot = line(cross, 2, 2)
	-- отметка попадания
	local hit = Instance.new("Frame")
	hit.Name = "Hitmarker"
	hit.AnchorPoint = Vector2.new(0.5, 0.5)
	hit.Position = UDim2.fromScale(0.5, 0.5)
	hit.Size = UDim2.fromOffset(0, 0)
	hit.BackgroundTransparency = 1
	hit.Visible = false
	hit.Parent = root
	local marks = {}
	for i, a in ipairs({ 45, 135, 225, 315 }) do
		local m = line(hit, 2, 8)
		m.Rotation = a
		marks[i] = { Frame = m, Angle = math.rad(a) }
	end
	-- патроны
	local ammo = Instance.new("Frame")
	ammo.Name = "Ammo"
	ammo.BackgroundTransparency = 1
	ammo.Size = UDim2.fromOffset(220, 86)
	ammo.Parent = root
	local count = label(ammo, Enum.Font.GothamBold, 44, WHITE)
	count.Size = UDim2.new(1, -78, 0, 46)
	count.Position = UDim2.fromOffset(0, 10)
	local reserve = label(ammo, Enum.Font.GothamMedium, 20, DIM, Enum.TextXAlignment.Left)
	reserve.Size = UDim2.fromOffset(72, 24)
	reserve.Position = UDim2.new(1, -72, 0, 28)
	local info = label(ammo, Enum.Font.GothamMedium, 13, DIM)
	info.Size = UDim2.new(1, 0, 0, 16)
	info.Position = UDim2.fromOffset(0, 60)
	local bar = Instance.new("Frame")
	bar.BackgroundColor3 = Color3.fromRGB(60, 60, 62)
	bar.BackgroundTransparency = 0.3
	bar.BorderSizePixel = 0
	bar.AnchorPoint = Vector2.new(1, 0)
	bar.Size = UDim2.new(0.7, 0, 0, 3)
	bar.Position = UDim2.new(1, 0, 0, 80)
	bar.Visible = false
	bar.Parent = ammo
	local fill = Instance.new("Frame")
	fill.BackgroundColor3 = WHITE
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(0, 1)
	fill.Parent = bar
	ui = { Root = root, Scope = scope, Cross = cross, Lines = lines, Dot = dot, Hit = hit, Marks = marks, Ammo = ammo, Count = count, Reserve = reserve, Info = info, Bar = bar, Fill = fill }
end

local function layoutAmmo()
	local touch = UserInputService.TouchEnabled and UserInputService:GetLastInputType() == Enum.UserInputType.Touch
	if touch then
		ui.Ammo.AnchorPoint = Vector2.new(1, 0)
		ui.Ammo.Position = UDim2.new(1, -18, 0, 58)
	else
		ui.Ammo.AnchorPoint = Vector2.new(1, 1)
		ui.Ammo.Position = UDim2.new(1, -28, 1, -22)
	end
end

local function update()
	if not ui then
		return
	end
	local character, humanoid = characters.GetCharacter()
	local s = weapons.GetState()
	local show = character ~= nil and humanoid ~= nil and humanoid.Health > 0 and s.Equipped and not characters.IsRagdolled()
	ui.Root.Visible = show
	if not show then
		return
	end
	local camera = workspace.CurrentCamera
	ui.Scope.Visible = weapons.IsScoped() and cameraCtl.IsFirstPerson()
	-- перекрестие
	local moving = characters.GetState().Sprint
	local fade = math.max(s.AimAlpha, moving and 1 or 0)
	local crossVisible = fade < 0.95 and cameraCtl.IsFirstPerson()
	ui.Cross.Visible = crossVisible
	if crossVisible then
		local gap = WeaponHUD.SpreadPixels(s.Spread, camera.FieldOfView, camera.ViewportSize.Y) + 3
		gap = math.clamp(gap, 4, 140)
		ui.Lines.Top.Position = UDim2.fromOffset(0, -gap - 4.5)
		ui.Lines.Bottom.Position = UDim2.fromOffset(0, gap + 4.5)
		ui.Lines.Left.Position = UDim2.fromOffset(-gap - 4.5, 0)
		ui.Lines.Right.Position = UDim2.fromOffset(gap + 4.5, 0)
		for _, f in pairs(ui.Lines) do
			f.BackgroundTransparency = fade
		end
		ui.Dot.BackgroundTransparency = math.max(0.25, fade)
	end
	-- отметка попадания
	local age = os.clock() - hitAt
	ui.Hit.Visible = age < (hitKill and 0.4 or 0.22)
	if ui.Hit.Visible then
		local grow = hitKill and 1.6 or (hitHead and 1.35 or 1)
		for _, m in ipairs(ui.Marks) do
			local r = (7 + age * 22) * grow
			m.Frame.Position = UDim2.fromOffset(math.sin(m.Angle) * r, -math.cos(m.Angle) * r)
			m.Frame.Size = UDim2.fromOffset(2, 8 * grow)
			m.Frame.BackgroundColor3 = (hitHead or hitKill) and RED or WHITE
			m.Frame.BackgroundTransparency = age / (hitKill and 0.4 or 0.22)
		end
	end
	-- патроны
	ui.Count.Text = tostring(s.Ammo)
	ui.Reserve.Text = "/ " .. tostring(s.Reserve)
	local low = s.Ammo <= math.floor(s.Magazine * 0.25)
	ui.Count.TextColor3 = s.Ammo == 0 and RED or (low and AMBER or WHITE)
	local mode = s.Mode == "Auto" and "AUTO" or "SEMI"
	if s.Reloading then
		ui.Info.Text = s.DisplayName .. "   RELOADING"
		ui.Info.TextColor3 = WHITE
	elseif s.Ammo == 0 and s.Reserve > 0 then
		ui.Info.Text = s.DisplayName .. "   RELOAD"
		ui.Info.TextColor3 = AMBER
	elseif s.Ammo == 0 then
		ui.Info.Text = s.DisplayName .. "   NO AMMO"
		ui.Info.TextColor3 = RED
	else
		ui.Info.Text = s.DisplayName .. "   " .. mode
		ui.Info.TextColor3 = DIM
	end
	ui.Bar.Visible = s.Reloading
	if s.Reloading then
		ui.Fill.Size = UDim2.fromScale(s.ReloadProgress or 0, 1)
	end
end

function WeaponHUD.Init(context)
	weapons = context.Get("WeaponController")
	characters = context.Get("CharacterController")
	cameraCtl = context.Get("CameraController")
end

function WeaponHUD.Start()
	task.spawn(function()
		build()
		if not ui then
			return
		end
		layoutAmmo()
		UserInputService.LastInputTypeChanged:Connect(layoutAmmo)
		weapons.HitConfirmed:Connect(function(info)
			hitAt = os.clock()
			hitHead = info.Headshot == true
			hitKill = info.Kill == true
		end)
		RunService.RenderStepped:Connect(update)
	end)
end

return WeaponHUD
