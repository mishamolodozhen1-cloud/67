-- Окружение клиента для симулятора интерфейса: игрок, PlayerGui (копии ScreenGui из StarterGui), сервисы,
-- камера с размером экрана SCREEN. Сценарии (tools/uisim/scenarios/*.lua) подключают свои контроллеры.
local Signal = M.Signal

local Players = game:GetService("Players")
local me = Instance.new("Player")
me.Name = "Forzza_133"
me.DisplayName = "Forzza_133"
me.UserId = 1001
local pg = Instance.new("PlayerGui")
pg.Name = "PlayerGui"
pg.Parent = me
me.Parent = Players
Players.LocalPlayer = me
rawset(Players, "__custom", {
	GetPlayers = function()
		return { me }
	end,
})
rawset(me, "__custom", {
	GetMouse = function()
		return { X = 0, Y = 0, Hit = CFrame.new(0, 0, 0) }
	end,
	GetNetworkPing = function()
		return 0.05
	end,
})
-- размер области ScreenGui (как в Roblox): без отступов — весь экран; CoreUISafeInsets — без полосы кнопок
local function screenArea(g)
	local ins = g.__props.ScreenInsets
	local W, H, top, left = SCREEN.W, SCREEN.H, SCREEN.InsetTop, SCREEN.InsetLeft
	if ins then
		if ins.Name == "None" then
			return Vector2.new(W, H)
		elseif ins.Name == "DeviceSafeInsets" then
			return Vector2.new(W - 2 * left, H)
		end
		return Vector2.new(W - 2 * left, H - top)
	end
	if g.__props.IgnoreGuiInset then
		return Vector2.new(W, H)
	end
	return Vector2.new(W, H - top)
end
for _, g in ipairs(game:GetService("StarterGui"):GetChildren()) do
	if g:IsA("ScreenGui") then
		local c = g:Clone()
		rawset(c, "__getters", { AbsoluteSize = screenArea })
		c.Parent = pg
	end
end

local cam = Instance.new("Camera")
cam.Name = "Camera"
cam.ViewportSize = Vector2.new(SCREEN.W, SCREEN.H)
cam.FieldOfView = 70
cam.CFrame = CFrame.new(0, 5, 0)
cam.Parent = workspace
workspace.CurrentCamera = cam
rawset(workspace, "__custom", {
	GetServerTimeNow = function()
		return 1000 + M.Time()
	end,
	Raycast = function()
		return nil
	end,
	BulkMoveTo = function() end,
	GetPartBoundsInBox = function()
		return {}
	end,
})

local RunService = game:GetService("RunService")
RunService.RenderStepped = Signal.new()
RunService.Heartbeat = Signal.new()
RunService.PreSimulation = Signal.new()
RunService.Stepped = Signal.new()
rawset(RunService, "__custom", {
	IsStudio = function()
		return false
	end,
	IsClient = function()
		return true
	end,
	IsServer = function()
		return false
	end,
	BindToRenderStep = function(_, _, _, fn)
		RunService.RenderStepped:Connect(fn)
	end,
	UnbindFromRenderStep = function() end,
})

local UIS = game:GetService("UserInputService")
UIS.TouchEnabled = SCREEN.Touch ~= 0
UIS.KeyboardEnabled = SCREEN.Touch == 0
UIS.MouseEnabled = SCREEN.Touch == 0
UIS.GamepadEnabled = false
UIS.MouseDeltaSensitivity = 1
UIS.LastInputTypeChanged = Signal.new()
UIS.InputBegan = Signal.new()
UIS.InputChanged = Signal.new()
UIS.InputEnded = Signal.new()
UIS.TouchStarted = Signal.new()
UIS.TouchMoved = Signal.new()
UIS.TouchEnded = Signal.new()
rawset(UIS, "__custom", {
	GetLastInputType = function()
		return UIS.TouchEnabled and Enum.UserInputType.Touch or Enum.UserInputType.MouseMovement
	end,
	GetMouseLocation = function()
		return Vector2.new(0, 0)
	end,
	IsKeyDown = function()
		return false
	end,
	GetConnectedGamepads = function()
		return {}
	end,
})

local CAS = game:GetService("ContextActionService")
rawset(CAS, "__custom", {
	BindAction = function() end,
	BindActionAtPriority = function() end,
	UnbindAction = function() end,
	SetTitle = function() end,
	SetPosition = function() end,
	GetButton = function()
		return nil
	end,
})

local GuiService = game:GetService("GuiService")
GuiService.TopbarInset = Rect.new(SCREEN.InsetLeft + 170, 0, SCREEN.W - 70, SCREEN.InsetTop)
rawset(GuiService, "__custom", {
	GetGuiInset = function()
		return Vector2.new(0, SCREEN.InsetTop), Vector2.new(0, 0)
	end,
})
GuiService.MenuOpened = Signal.new()
GuiService.MenuClosed = Signal.new()

local TweenService = game:GetService("TweenService")
rawset(TweenService, "__custom", {
	Create = function(_, obj, _, props)
		local tw = { Completed = Signal.new() }
		function tw.Play()
			for k, v in pairs(props) do
				obj[k] = v
			end
			tw.Completed:Fire(Enum.PlaybackState.Completed)
		end
		tw.Cancel = function() end
		tw.Pause = function() end
		return tw
	end,
})
rawset(game:GetService("Debris"), "__custom", { AddItem = function() end })
rawset(game:GetService("ContentProvider"), "__custom", { PreloadAsync = function() end })
rawset(game:GetService("StarterGui"), "__custom", {
	SetCoreGuiEnabled = function() end,
	SetCore = function() end,
	GetCoreGuiEnabled = function()
		return true
	end,
})
rawset(game:GetService("SoundService"), "__custom", { PlayLocalSound = function() end })
rawset(game:GetService("CollectionService"), "__custom", {
	GetTagged = function()
		return {}
	end,
	HasTag = function()
		return false
	end,
	GetInstanceAddedSignal = function()
		return Signal.new()
	end,
	GetInstanceRemovedSignal = function()
		return Signal.new()
	end,
})

-- Состояние матча, как его публикует сервер (ReplicatedStorage.Match)
function SetupMatch(attrs, participants)
	local RS = game:GetService("ReplicatedStorage")
	local f = RS:FindFirstChild("Match") or Instance.new("Folder")
	f.Name = "Match"
	f.Parent = RS
	for k, v in pairs(attrs) do
		f:SetAttribute(k, v)
	end
	local parts = f:FindFirstChild("Participants") or Instance.new("Folder")
	parts.Name = "Participants"
	parts.Parent = f
	for _, p in ipairs(participants or {}) do
		local c = Instance.new("Configuration")
		c.Name = tostring(p.UserId)
		for k, v in pairs(p) do
			c:SetAttribute(k, v)
		end
		c.Parent = parts
	end
	return f
end

-- Простая заглушка контроллера: любые вызовы ничего не делают, сигналы — настоящие
function Stub(fields)
	return setmetatable(fields or {}, {
		__index = function(t, k)
			local v = function() end
			rawset(t, k, v)
			return v
		end,
	})
end

-- Кадры: RenderStepped/Heartbeat каждые 1/30 с
M.OnFrame = function(dt)
	RunService.RenderStepped:Fire(dt)
	RunService.Heartbeat:Fire(dt)
	RunService.PreSimulation:Fire(dt)
end

function Context(mods)
	return {
		Get = function(name)
			return mods[name]
		end,
	}
end

Controllers = game:GetService("StarterPlayer").StarterPlayerScripts.Client.Controllers
