-- TouchControls: кнопки на телефоне и планшете.
--
-- Стандартные джойстик, кнопка прыжка и обзор пальцем — от Roblox. Здесь — свои кнопки рядом с кнопкой
-- прыжка: RUN (бег вкл/выкл), CROUCH (присед вкл/выкл) и оружие (этап 4):
--   FIRE — держать: огонь; палец можно вести — обзор поворачивается (стрелять и целиться одним пальцем);
--   AIM — прицел вкл/выкл; R — перезарядка; AUTO/SEMI — режим огня.
-- Размер и место считаются от кнопки прыжка Roblox (маленький экран — 70 px, большой — 120 px) и
-- пересчитываются при повороте экрана. Кнопки видны, только когда игрок управляет касанием и его персонаж
-- жив (оружия — пока оно в руках). Включённая кнопка подсвечена.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Logger = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Logger"))

local TouchControls = { Name = "TouchControls" }

local log = Logger.new("Touch")
local characters = nil
local weapons = nil
local cameraCtl = nil
local fireTouch = nil -- палец, которым держат FIRE

-- Поворот обзора пальцем на кнопке огня: радиан на пиксель
TouchControls.LookPerPixel = math.rad(0.24)
local frame = nil
local buttons = {}

local IDLE_BG = Color3.fromRGB(18, 19, 22)
local ACTIVE_BG = Color3.fromRGB(201, 170, 98)
local IDLE_TEXT = Color3.fromRGB(236, 236, 232)
local ACTIVE_TEXT = Color3.fromRGB(24, 22, 18)

-- Где кнопки при размере экрана viewport: возвращает размер и позиции (UDim2) RUN и CROUCH
function TouchControls.Layout(viewport)
	local minAxis = math.min(viewport.X, viewport.Y)
	local small = minAxis <= 500
	local jump = small and 70 or 120
	-- кнопка прыжка Roblox: правый нижний угол
	local jumpX = -(jump * 1.5 - 10)
	local jumpY = small and (-jump - 20) or (-jump * 1.75)
	local size = math.floor(jump * 0.72)
	local gap = small and 10 or 16
	-- CROUCH — слева от прыжка на одной высоте, RUN — над прыжком
	local crouch = UDim2.new(1, jumpX - gap - size, 1, jumpY + (jump - size) / 2)
	local run = UDim2.new(1, jumpX + (jump - size) / 2, 1, jumpY - gap - size)
	return size, run, crouch
end

-- Кнопки оружия при размере экрана viewport: { Name = { Size, Position } } (Position — левый верхний угол).
-- FIRE — крупнее, слева-выше RUN; AIM — над FIRE; R — над RUN; режим огня — слева от AIM
function TouchControls.WeaponLayout(viewport)
	local minAxis = math.min(viewport.X, viewport.Y)
	local small = minAxis <= 500
	local jump = small and 70 or 120
	local jumpX = -(jump * 1.5 - 10)
	local jumpY = small and (-jump - 20) or (-jump * 1.75)
	local size = math.floor(jump * 0.72)
	local gap = small and 10 or 16
	local fire = math.floor(jump * 1.05)
	local mode = math.floor(size * 0.62)
	-- центры (от правого нижнего угла)
	local crouchX = jumpX - gap - size / 2
	local runX, runY = jumpX + jump / 2, jumpY - gap - size / 2
	local fireX, fireY = crouchX - fire * 0.35, runY - fire * 0.25
	local aimX, aimY = fireX + fire * 0.1, fireY - fire / 2 - gap - size / 2
	local reloadX, reloadY = runX, runY - size - gap
	local modeX, modeY = aimX - size / 2 - gap - mode / 2, aimY
	local function at(cx, cy, s)
		return { Size = s, Position = UDim2.new(1, math.floor(cx - s / 2), 1, math.floor(cy - s / 2)) }
	end
	return {
		Fire = at(fireX, fireY, fire),
		Aim = at(aimX, aimY, size),
		Reload = at(reloadX, reloadY, size),
		Mode = at(modeX, modeY, mode),
	}
end

local function makeButton(name, text)
	local b = Instance.new("TextButton")
	b.Name = name
	b.Text = text
	b.Font = Enum.Font.GothamBold
	b.TextScaled = true
	b.AutoButtonColor = false
	b.BackgroundColor3 = IDLE_BG
	b.BackgroundTransparency = 0.35
	b.TextColor3 = IDLE_TEXT
	b.Active = true
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = b
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = Color3.fromRGB(236, 236, 232)
	stroke.Transparency = 0.55
	stroke.Thickness = 1.5
	stroke.Parent = b
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0.16, 0)
	pad.PaddingRight = UDim.new(0.16, 0)
	pad.PaddingTop = UDim.new(0.3, 0)
	pad.PaddingBottom = UDim.new(0.3, 0)
	pad.Parent = b
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = 18
	limit.MinTextSize = 8
	limit.Parent = b
	b.Parent = frame
	return b
end

local function setActive(b, on)
	b.BackgroundColor3 = on and ACTIVE_BG or IDLE_BG
	b.BackgroundTransparency = on and 0.1 or 0.35
	b.TextColor3 = on and ACTIVE_TEXT or IDLE_TEXT
end

local function relayout()
	if not frame then
		return
	end
	local size, run, crouch = TouchControls.Layout(workspace.CurrentCamera.ViewportSize)
	buttons.Run.Size = UDim2.fromOffset(size, size)
	buttons.Run.Position = run
	buttons.Crouch.Size = UDim2.fromOffset(size, size)
	buttons.Crouch.Position = crouch
	for name, spot in pairs(TouchControls.WeaponLayout(workspace.CurrentCamera.ViewportSize)) do
		local b = buttons[name]
		if b then
			b.Size = UDim2.fromOffset(spot.Size, spot.Size)
			b.Position = spot.Position
		end
	end
end

local function refresh()
	if not frame then
		return
	end
	local _, humanoid = characters.GetCharacter()
	local touch = UserInputService.TouchEnabled and UserInputService:GetLastInputType() == Enum.UserInputType.Touch
	frame.Visible = touch and humanoid ~= nil and humanoid.Health > 0
	setActive(buttons.Run, characters.SprintToggled())
	setActive(buttons.Crouch, characters.WantsCrouch())
	if weapons and buttons.Fire then
		local s = weapons.GetState()
		for _, name in ipairs({ "Fire", "Aim", "Reload", "Mode" }) do
			buttons[name].Visible = s.Equipped
		end
		setActive(buttons.Fire, fireTouch ~= nil)
		setActive(buttons.Aim, s.Aiming)
		buttons.Mode.Text = s.Mode == "Auto" and "AUTO" or "SEMI"
	end
end

-- FIRE: держать — огонь; вести пальцем — поворот обзора (камера Roblox этот палец не берёт: он начался на кнопке)
local function bindFire(button)
	button.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.Touch or fireTouch then
			return
		end
		fireTouch = input
		weapons.SetTrigger(true)
		refresh()
	end)
	UserInputService.InputChanged:Connect(function(input)
		if input == fireTouch and cameraCtl then
			local d = input.Delta
			cameraCtl.AddLook(d.X * TouchControls.LookPerPixel, -d.Y * TouchControls.LookPerPixel)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input == fireTouch then
			fireTouch = nil
			weapons.SetTrigger(false)
			refresh()
		end
	end)
end

local function build()
	local hud = Players.LocalPlayer:WaitForChild("PlayerGui"):WaitForChild("HUD", 10)
	if not hud then
		log:Error("нет интерфейса HUD — кнопки для телефона не созданы")
		return
	end
	frame = Instance.new("Frame")
	frame.Name = "TouchActions"
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundTransparency = 1
	frame.Visible = false
	frame.Parent = hud
	buttons.Run = makeButton("Run", "RUN")
	buttons.Crouch = makeButton("Crouch", "CROUCH")
	if weapons then
		buttons.Fire = makeButton("Fire", "FIRE")
		buttons.Aim = makeButton("Aim", "AIM")
		buttons.Reload = makeButton("Reload", "R")
		buttons.Mode = makeButton("Mode", "AUTO")
		bindFire(buttons.Fire)
		buttons.Aim.Activated:Connect(function()
			weapons.ToggleAim()
			refresh()
		end)
		buttons.Reload.Activated:Connect(function()
			weapons.RequestReload()
		end)
		buttons.Mode.Activated:Connect(function()
			weapons.ToggleMode()
			refresh()
		end)
		weapons.StateChanged:Connect(refresh)
	end
	buttons.Run.Activated:Connect(function()
		characters.SetSprintToggle(not characters.SprintToggled())
		refresh()
	end)
	buttons.Crouch.Activated:Connect(function()
		characters.ToggleCrouch()
		refresh()
	end)
	relayout()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(relayout)
	UserInputService.LastInputTypeChanged:Connect(refresh)
	characters.StateChanged:Connect(refresh)
	characters.CharacterChanged:Connect(function(_, humanoid)
		humanoid.Died:Connect(refresh)
		refresh()
	end)
	refresh()
end

function TouchControls.Init(context)
	characters = context.Get("CharacterController")
	weapons = context.Get("WeaponController")
	cameraCtl = context.Get("CameraController")
end

function TouchControls.Start()
	if UserInputService.TouchEnabled then
		task.spawn(build)
	end
end

return TouchControls
