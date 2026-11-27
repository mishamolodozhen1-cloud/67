-- TouchControls: кнопки бега и приседа на телефоне и планшете.
--
-- Стандартные джойстик, кнопка прыжка и обзор пальцем — от Roblox. Здесь — две свои кнопки рядом с кнопкой
-- прыжка: RUN (бег вкл/выкл) и CROUCH (присед вкл/выкл). Размер и место считаются так же, как у кнопки
-- прыжка Roblox (маленький экран — 70 px, большой — 120 px), и пересчитываются при повороте экрана.
-- Кнопки видны, только когда игрок управляет касанием и его персонаж жив. Включённая кнопка подсвечена.
-- Остальные кнопки (стрельба, прицел, перезарядка, оружие) — этапы 4 и 11.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Logger = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Logger"))

local TouchControls = { Name = "TouchControls" }

local log = Logger.new("Touch")
local characters = nil
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
end

function TouchControls.Start()
	if UserInputService.TouchEnabled then
		task.spawn(build)
	end
end

return TouchControls
