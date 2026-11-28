-- Моки Roblox для запуска клиентского кода интерфейса вне Roblox (tools/uisim/uisim.py).
-- Хватает того, что нужно меню и HUD: Instance с произвольными свойствами, дети, атрибуты, сигналы,
-- типы данных (UDim2, Vector2/3, Color3 …), Enum, сервисы, task (сопрограммы с ручным временем).
local M = {}
local now = 0
M.Time = function()
	return now
end

-------------------------------------------------------------------------------
-- Совместимость Luau
-------------------------------------------------------------------------------
table.freeze = function(t)
	return t
end
table.isfrozen = function()
	return false
end
table.clear = function(t)
	for k in pairs(t) do
		t[k] = nil
	end
end
table.find = function(t, v)
	for i, x in ipairs(t) do
		if x == v then
			return i
		end
	end
	return nil
end
table.create = function(n, v)
	local t = {}
	for i = 1, n do
		t[i] = v
	end
	return t
end
math.clamp = function(x, a, b)
	return math.max(a, math.min(b, x))
end
math.sign = function(x)
	return x > 0 and 1 or (x < 0 and -1 or 0)
end
math.atan2 = function(y, x)
	return math.atan(y, x)
end
math.pow = function(a, b)
	return a ^ b
end
math.round = function(x)
	return math.floor(x + 0.5)
end
local fmt = string.format
string.format = function(f, ...)
	local args = table.pack(...)
	local i = 0
	-- %d с дробным числом в Luau отбрасывает дробь
	for spec in f:gmatch("%%[%-%+ #0]*%d*%.?%d*[%a%%]") do
		if spec ~= "%%" then
			i = i + 1
			if spec:sub(-1) == "d" and type(args[i]) == "number" then
				args[i] = math.floor(args[i])
			end
		end
	end
	return fmt(f, table.unpack(args, 1, args.n))
end
string.split = function(s, sep)
	local out = {}
	for part in (s .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do
		table.insert(out, part)
	end
	return out
end
utf8 = utf8 or {}

-------------------------------------------------------------------------------
-- Сигналы
-------------------------------------------------------------------------------
local Signal = {}
Signal.__index = Signal
function Signal.new()
	return setmetatable({ list = {} }, Signal)
end
function Signal:Connect(fn)
	local c = { fn = fn, Connected = true }
	local sig = self
	function c:Disconnect()
		c.Connected = false
		for i, x in ipairs(sig.list) do
			if x == c then
				table.remove(sig.list, i)
				break
			end
		end
	end
	table.insert(self.list, c)
	return c
end
Signal.connect = Signal.Connect
function Signal:Once(fn)
	local c
	c = self:Connect(function(...)
		c:Disconnect()
		fn(...)
	end)
	return c
end
function Signal:Fire(...)
	local copy = { table.unpack(self.list) }
	for _, c in ipairs(copy) do
		if c.Connected then
			M.spawn(c.fn, ...)
		end
	end
end
function Signal:Wait()
	return coroutine.yield({ signal = self })
end
M.Signal = Signal

-------------------------------------------------------------------------------
-- Планировщик task
-------------------------------------------------------------------------------
local sleeping = {}
function M.spawn(fn, ...)
	local co = type(fn) == "thread" and fn or coroutine.create(fn)
	M.resume(co, ...)
	return co
end
function M.resume(co, ...)
	local ok, req = coroutine.resume(co, ...)
	if not ok then
		M.errors = M.errors or {}
		table.insert(M.errors, debug.traceback(co, tostring(req)))
		return
	end
	if coroutine.status(co) == "suspended" and type(req) == "table" then
		if req.wake then
			table.insert(sleeping, { co = co, at = req.wake })
		elseif req.signal then
			req.signal:Connect(function(...)
				M.resume(co, ...)
			end)
		end
	end
end
function M.advance(dt, step)
	step = step or 1 / 30
	local t1 = now + dt
	while now < t1 do
		now = math.min(t1, now + step)
		local ready = {}
		for i = #sleeping, 1, -1 do
			if sleeping[i].at <= now then
				table.insert(ready, sleeping[i])
				table.remove(sleeping, i)
			end
		end
		table.sort(ready, function(a, b)
			return a.at < b.at
		end)
		for _, s in ipairs(ready) do
			M.resume(s.co, now - (s.at - 0))
		end
		if M.OnFrame then
			M.OnFrame(step)
		end
	end
end
task = {
	spawn = function(fn, ...)
		return M.spawn(fn, ...)
	end,
	defer = function(fn, ...)
		return M.spawn(fn, ...)
	end,
	delay = function(t, fn, ...)
		local args = table.pack(...)
		return M.spawn(function()
			coroutine.yield({ wake = now + (t or 0) })
			fn(table.unpack(args, 1, args.n))
		end)
	end,
	wait = function(t)
		if not coroutine.isyieldable() then
			return 0
		end
		coroutine.yield({ wake = now + (t or 0) })
		return t or 0
	end,
	cancel = function() end,
}

-------------------------------------------------------------------------------
-- Типы данных
-------------------------------------------------------------------------------
local function datatype(name, fields)
	local mt = { __type = name }
	mt.__index = function(t, k)
		local m = mt.methods and mt.methods[k]
		if m then
			return m
		end
		local g = mt.getters and mt.getters[k]
		if g then
			return g(t)
		end
		return nil
	end
	mt.__tostring = function(t)
		local parts = {}
		for _, f in ipairs(fields) do
			table.insert(parts, tostring(rawget(t, f)))
		end
		return table.concat(parts, ", ")
	end
	mt.__eq = function(a, b)
		for _, f in ipairs(fields) do
			if rawget(a, f) ~= rawget(b, f) then
				return false
			end
		end
		return true
	end
	return mt
end

local V2 = datatype("Vector2", { "X", "Y" })
Vector2 = {}
function Vector2.new(x, y)
	return setmetatable({ X = x or 0, Y = y or 0 }, V2)
end
Vector2.zero = Vector2.new(0, 0)
Vector2.one = Vector2.new(1, 1)
V2.__add = function(a, b)
	return Vector2.new(a.X + b.X, a.Y + b.Y)
end
V2.__sub = function(a, b)
	return Vector2.new(a.X - b.X, a.Y - b.Y)
end
V2.__mul = function(a, b)
	if type(a) == "number" then
		return Vector2.new(a * b.X, a * b.Y)
	elseif type(b) == "number" then
		return Vector2.new(a.X * b, a.Y * b)
	end
	return Vector2.new(a.X * b.X, a.Y * b.Y)
end
V2.__div = function(a, b)
	return type(b) == "number" and Vector2.new(a.X / b, a.Y / b) or Vector2.new(a.X / b.X, a.Y / b.Y)
end
V2.__unm = function(a)
	return Vector2.new(-a.X, -a.Y)
end
V2.getters = {
	Magnitude = function(v)
		return math.sqrt(v.X * v.X + v.Y * v.Y)
	end,
	Unit = function(v)
		local m = math.sqrt(v.X * v.X + v.Y * v.Y)
		return m > 0 and Vector2.new(v.X / m, v.Y / m) or v
	end,
}
V2.methods = {
	Lerp = function(a, b, t)
		return Vector2.new(a.X + (b.X - a.X) * t, a.Y + (b.Y - a.Y) * t)
	end,
	Dot = function(a, b)
		return a.X * b.X + a.Y * b.Y
	end,
}

local V3 = datatype("Vector3", { "X", "Y", "Z" })
Vector3 = {}
function Vector3.new(x, y, z)
	return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, V3)
end
Vector3.zero = Vector3.new(0, 0, 0)
Vector3.one = Vector3.new(1, 1, 1)
Vector3.xAxis = Vector3.new(1, 0, 0)
Vector3.yAxis = Vector3.new(0, 1, 0)
Vector3.zAxis = Vector3.new(0, 0, 1)
V3.__add = function(a, b)
	return Vector3.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end
V3.__sub = function(a, b)
	return Vector3.new(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
end
V3.__mul = function(a, b)
	if type(a) == "number" then
		return Vector3.new(a * b.X, a * b.Y, a * b.Z)
	elseif type(b) == "number" then
		return Vector3.new(a.X * b, a.Y * b, a.Z * b)
	end
	return Vector3.new(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
V3.__div = function(a, b)
	return Vector3.new(a.X / b, a.Y / b, a.Z / b)
end
V3.__unm = function(a)
	return Vector3.new(-a.X, -a.Y, -a.Z)
end
V3.getters = {
	Magnitude = function(v)
		return math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
	end,
	Unit = function(v)
		local m = math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
		return m > 0 and Vector3.new(v.X / m, v.Y / m, v.Z / m) or v
	end,
}
V3.methods = {
	Dot = function(a, b)
		return a.X * b.X + a.Y * b.Y + a.Z * b.Z
	end,
	Cross = function(a, b)
		return Vector3.new(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X)
	end,
	Lerp = function(a, b, t)
		return a + (b - a) * t
	end,
}

local UD = datatype("UDim", { "Scale", "Offset" })
UDim = {}
function UDim.new(s, o)
	return setmetatable({ Scale = s or 0, Offset = o or 0 }, UD)
end
UD.__add = function(a, b)
	return UDim.new(a.Scale + b.Scale, a.Offset + b.Offset)
end

local UD2 = datatype("UDim2", { "X", "Y" })
UDim2 = {}
function UDim2.new(xs, xo, ys, yo)
	if type(xs) == "table" then
		return setmetatable({ X = xs, Y = xo }, UD2)
	end
	return setmetatable({ X = UDim.new(xs, xo), Y = UDim.new(ys, yo) }, UD2)
end
function UDim2.fromScale(x, y)
	return UDim2.new(x, 0, y, 0)
end
function UDim2.fromOffset(x, y)
	return UDim2.new(0, x, 0, y)
end
UD2.__add = function(a, b)
	return UDim2.new(a.X.Scale + b.X.Scale, a.X.Offset + b.X.Offset, a.Y.Scale + b.Y.Scale, a.Y.Offset + b.Y.Offset)
end
UD2.__sub = function(a, b)
	return UDim2.new(a.X.Scale - b.X.Scale, a.X.Offset - b.X.Offset, a.Y.Scale - b.Y.Scale, a.Y.Offset - b.Y.Offset)
end
UD2.__eq = function(a, b)
	return a.X.Scale == b.X.Scale and a.X.Offset == b.X.Offset and a.Y.Scale == b.Y.Scale and a.Y.Offset == b.Y.Offset
end
UD2.getters = {
	Width = function(u)
		return u.X
	end,
	Height = function(u)
		return u.Y
	end,
}
UD2.methods = {
	Lerp = function(a, b, t)
		return UDim2.new(a.X.Scale + (b.X.Scale - a.X.Scale) * t, a.X.Offset + (b.X.Offset - a.X.Offset) * t, a.Y.Scale + (b.Y.Scale - a.Y.Scale) * t, a.Y.Offset + (b.Y.Offset - a.Y.Offset) * t)
	end,
}

local C3 = datatype("Color3", { "R", "G", "B" })
Color3 = {}
function Color3.new(r, g, b)
	return setmetatable({ R = r or 0, G = g or 0, B = b or 0 }, C3)
end
function Color3.fromRGB(r, g, b)
	return Color3.new((r or 0) / 255, (g or 0) / 255, (b or 0) / 255)
end
function Color3.fromHSV(h, s, v)
	local i = math.floor(h * 6)
	local f = h * 6 - i
	local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
	local m = i % 6
	local r, g, b
	if m == 0 then
		r, g, b = v, t, p
	elseif m == 1 then
		r, g, b = q, v, p
	elseif m == 2 then
		r, g, b = p, v, t
	elseif m == 3 then
		r, g, b = p, q, v
	elseif m == 4 then
		r, g, b = t, p, v
	else
		r, g, b = v, p, q
	end
	return Color3.new(r, g, b)
end
C3.methods = {
	Lerp = function(a, b, t)
		return Color3.new(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t)
	end,
	ToHSV = function(c)
		local mx, mn = math.max(c.R, c.G, c.B), math.min(c.R, c.G, c.B)
		return 0, mx > 0 and (mx - mn) / mx or 0, mx
	end,
}

local NR = datatype("NumberRange", { "Min", "Max" })
NumberRange = {
	new = function(a, b)
		return setmetatable({ Min = a, Max = b or a }, NR)
	end,
}
local NSK = datatype("NumberSequenceKeypoint", { "Time", "Value" })
NumberSequenceKeypoint = {
	new = function(t, v)
		return setmetatable({ Time = t, Value = v }, NSK)
	end,
}
local NS = datatype("NumberSequence", {})
NumberSequence = {
	new = function(a, b)
		if type(a) == "table" then
			return setmetatable({ Keypoints = a }, NS)
		end
		return setmetatable({ Keypoints = { NumberSequenceKeypoint.new(0, a), NumberSequenceKeypoint.new(1, b or a) } }, NS)
	end,
}
local CSK = datatype("ColorSequenceKeypoint", { "Time", "Value" })
ColorSequenceKeypoint = {
	new = function(t, v)
		return setmetatable({ Time = t, Value = v }, CSK)
	end,
}
local CS = datatype("ColorSequence", {})
ColorSequence = {
	new = function(a, b)
		if type(a) == "table" and getmetatable(a) ~= C3 then
			return setmetatable({ Keypoints = a }, CS)
		end
		return setmetatable({ Keypoints = { ColorSequenceKeypoint.new(0, a), ColorSequenceKeypoint.new(1, b or a) } }, CS)
	end,
}
local TI = datatype("TweenInfo", {})
TweenInfo = {
	new = function(t)
		return setmetatable({ Time = t or 1 }, TI)
	end,
}
local RC = datatype("Rect", {})
Rect = {
	new = function(a, b, c, d)
		return setmetatable({ Min = Vector2.new(a, b), Max = Vector2.new(c, d) }, RC)
	end,
}
local CFM = datatype("CFrame", {})
CFrame = {}
local function cf(x, y, z)
	return setmetatable({ Position = Vector3.new(x, y, z), X = x, Y = y, Z = z }, CFM)
end
CFrame.new = function(x, y, z)
	if type(x) == "table" then
		return cf(x.X, x.Y, x.Z)
	end
	return cf(x or 0, y or 0, z or 0)
end
CFrame.identity = cf(0, 0, 0)
CFrame.Angles = function()
	return cf(0, 0, 0)
end
CFrame.lookAt = function(p)
	return cf(p.X, p.Y, p.Z)
end
CFrame.fromMatrix = function(p)
	return cf(p.X, p.Y, p.Z)
end
CFM.__mul = function(a, b)
	if getmetatable(b) == V3 then
		return a.Position + b
	end
	return cf(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end
CFM.getters = {
	LookVector = function()
		return Vector3.new(0, 0, -1)
	end,
	RightVector = function()
		return Vector3.new(1, 0, 0)
	end,
	UpVector = function()
		return Vector3.new(0, 1, 0)
	end,
	Rotation = function()
		return cf(0, 0, 0)
	end,
}
CFM.methods = {
	Inverse = function(c)
		return cf(-c.X, -c.Y, -c.Z)
	end,
	Lerp = function(a)
		return a
	end,
	PointToWorldSpace = function(c, v)
		return c.Position + v
	end,
	VectorToWorldSpace = function(_, v)
		return v
	end,
	PointToObjectSpace = function(c, v)
		return v - c.Position
	end,
	ToEulerAnglesYXZ = function()
		return 0, 0, 0
	end,
	GetComponents = function(c)
		return c.X, c.Y, c.Z, 1, 0, 0, 0, 1, 0, 0, 0, 1
	end,
}
local RNG = {}
RNG.__index = RNG
Random = {
	new = function(seed)
		return setmetatable({ s = seed or 1 }, RNG)
	end,
}
function RNG:NextNumber(a, b)
	self.s = (self.s * 1103515245 + 12345) % 2147483648
	local r = self.s / 2147483648
	if a then
		return a + (b - a) * r
	end
	return r
end
function RNG:NextInteger(a, b)
	return math.floor(self:NextNumber(a, b + 1 - 1e-9))
end

-------------------------------------------------------------------------------
-- Enum
-------------------------------------------------------------------------------
local enumItems = {}
Enum = setmetatable({}, {
	__index = function(_, typeName)
		local t = setmetatable({}, {
			__index = function(tt, itemName)
				local key = typeName .. "." .. itemName
				local item = enumItems[key]
				if not item then
					item = setmetatable({ Name = itemName, EnumType = typeName, Value = 0 }, { __tostring = function()
						return "Enum." .. key
					end, __type = "EnumItem" })
					enumItems[key] = item
				end
				rawset(tt, itemName, item)
				return item
			end,
		})
		function t.GetEnumItems()
			return {}
		end
		rawset(Enum, typeName, t)
		return t
	end,
})

function typeof(v)
	local mt = getmetatable(v)
	if type(v) == "table" and mt and mt.__type then
		return mt.__type
	end
	if type(v) == "table" and rawget(v, "__instance") then
		return "Instance"
	end
	return type(v)
end

-------------------------------------------------------------------------------
-- Instance
-------------------------------------------------------------------------------
local CLASS_PARENTS = {
	Frame = "GuiObject", TextLabel = "GuiObject", TextButton = "GuiButton", ImageLabel = "GuiObject", ImageButton = "GuiButton",
	ScrollingFrame = "GuiObject", TextBox = "GuiObject", GuiButton = "GuiObject", CanvasGroup = "GuiObject", ViewportFrame = "GuiObject",
	GuiObject = "GuiBase2d", ScreenGui = "LayerCollector", LayerCollector = "GuiBase2d", BillboardGui = "LayerCollector", SurfaceGui = "LayerCollector",
	GuiBase2d = "Instance", UIListLayout = "UIGridStyleLayout", UIGridLayout = "UIGridStyleLayout", UIGridStyleLayout = "UILayout", UILayout = "UIComponent",
	UIPadding = "UIComponent", UICorner = "UIComponent", UIStroke = "UIComponent", UIScale = "UIComponent", UIGradient = "UIComponent",
	UIAspectRatioConstraint = "UIConstraint", UISizeConstraint = "UIConstraint", UITextSizeConstraint = "UIConstraint", UIConstraint = "UIComponent", UIComponent = "Instance",
	Folder = "Instance", Configuration = "Instance", ModuleScript = "LuaSourceContainer", LocalScript = "LuaSourceContainer", Script = "LuaSourceContainer",
	Sound = "Instance", SoundGroup = "Instance", Camera = "Instance", Model = "PVInstance", Part = "BasePart", BasePart = "PVInstance", PVInstance = "Instance",
	Player = "Instance", PlayerGui = "Instance", Attachment = "Instance",
}
local DEFAULTS = {
	GuiObject = {
		Visible = true, Position = UDim2.new(0, 0, 0, 0), Size = UDim2.new(0, 100, 0, 100), AnchorPoint = Vector2.new(0, 0), ZIndex = 1, LayoutOrder = 0,
		BackgroundColor3 = Color3.fromRGB(163, 162, 165), BackgroundTransparency = 0, BorderSizePixel = 1, Rotation = 0, ClipsDescendants = false,
		AutomaticSize = Enum.AutomaticSize.None, SizeConstraint = Enum.SizeConstraint.RelativeXY, Active = false, Selectable = false,
	},
	TextLabel = { Text = "Label", TextSize = 14, TextColor3 = Color3.fromRGB(27, 42, 53), TextTransparency = 0, Font = Enum.Font.Legacy, TextScaled = false,
		TextWrapped = false, TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center, TextStrokeTransparency = 1, RichText = false,
		TextTruncate = Enum.TextTruncate.None, Size = UDim2.new(0, 200, 0, 50), LineHeight = 1 },
	TextButton = { Text = "Button", TextSize = 14, TextColor3 = Color3.fromRGB(27, 42, 53), TextTransparency = 0, Font = Enum.Font.Legacy, TextScaled = false,
		TextWrapped = false, TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center, TextStrokeTransparency = 1, AutoButtonColor = true,
		Size = UDim2.new(0, 200, 0, 50), Active = true, Modal = false, TextTruncate = Enum.TextTruncate.None, RichText = false, LineHeight = 1 },
	TextBox = { Text = "", TextSize = 14, TextColor3 = Color3.fromRGB(27, 42, 53), Font = Enum.Font.Legacy, PlaceholderText = "" },
	ImageLabel = { Image = "", ImageTransparency = 0, ImageColor3 = Color3.new(1, 1, 1), ScaleType = Enum.ScaleType.Stretch },
	ImageButton = { Image = "", ImageTransparency = 0, ImageColor3 = Color3.new(1, 1, 1), Active = true },
	ScrollingFrame = { CanvasSize = UDim2.new(0, 0, 2, 0), ScrollBarThickness = 12, CanvasPosition = Vector2.new(0, 0), ClipsDescendants = true,
		AutomaticCanvasSize = Enum.AutomaticSize.None, ScrollingDirection = Enum.ScrollingDirection.XY },
	ScreenGui = { Enabled = true, DisplayOrder = 0, IgnoreGuiInset = false, ResetOnSpawn = true, ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets },
	UIListLayout = { Padding = UDim.new(0, 0), FillDirection = Enum.FillDirection.Vertical, SortOrder = Enum.SortOrder.Name,
		HorizontalAlignment = Enum.HorizontalAlignment.Left, VerticalAlignment = Enum.VerticalAlignment.Top, Wraps = false },
	UIPadding = { PaddingLeft = UDim.new(0, 0), PaddingRight = UDim.new(0, 0), PaddingTop = UDim.new(0, 0), PaddingBottom = UDim.new(0, 0) },
	UICorner = { CornerRadius = UDim.new(0, 8) },
	UIStroke = { Color = Color3.new(0, 0, 0), Thickness = 1, Transparency = 0, Enabled = true, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual },
	UIScale = { Scale = 1 },
	UIGradient = { Rotation = 0, Enabled = true },
	UIAspectRatioConstraint = { AspectRatio = 1, DominantAxis = Enum.DominantAxis.Width },
	UISizeConstraint = { MinSize = Vector2.new(0, 0), MaxSize = Vector2.new(math.huge, math.huge) },
	Sound = { Volume = 0.5, PlaybackSpeed = 1, IsPlaying = false, TimeLength = 1, Looped = false },
	SoundGroup = { Volume = 1 },
}
local EVENTS = {
	Activated = true, MouseButton1Click = true, MouseButton1Down = true, MouseButton1Up = true, MouseEnter = true, MouseLeave = true, InputBegan = true,
	InputEnded = true, InputChanged = true, Changed = true, ChildAdded = true, ChildRemoved = true, DescendantAdded = true, AncestryChanged = true,
	Destroying = true, FocusLost = true, Ended = true, Completed = true, Played = true, Stopped = true, TouchTap = true,
}

local Instance_mt = {}
local nextId = 0
local function isa(cls, name)
	while cls do
		if cls == name then
			return true
		end
		cls = CLASS_PARENTS[cls]
	end
	return name == "Instance"
end
local function default(cls, key)
	local c = cls
	while c do
		local d = DEFAULTS[c]
		if d and d[key] ~= nil then
			return d[key]
		end
		c = CLASS_PARENTS[c]
	end
	return nil
end

local methods = {}
function methods:GetChildren()
	local out = {}
	for _, c in ipairs(self.__children) do
		table.insert(out, c)
	end
	return out
end
function methods:GetDescendants()
	local out = {}
	local function walk(x)
		for _, c in ipairs(x.__children) do
			table.insert(out, c)
			walk(c)
		end
	end
	walk(self)
	return out
end
function methods:FindFirstChild(name, recursive)
	for _, c in ipairs(self.__children) do
		if c.__props.Name == name then
			return c
		end
	end
	if recursive then
		for _, c in ipairs(self.__children) do
			local f = c:FindFirstChild(name, true)
			if f then
				return f
			end
		end
	end
	return nil
end
function methods:WaitForChild(name)
	return self:FindFirstChild(name)
end
function methods:FindFirstChildOfClass(cls)
	for _, c in ipairs(self.__children) do
		if c.__class == cls then
			return c
		end
	end
	return nil
end
function methods:FindFirstChildWhichIsA(cls)
	for _, c in ipairs(self.__children) do
		if isa(c.__class, cls) then
			return c
		end
	end
	return nil
end
function methods:FindFirstAncestorOfClass(cls)
	local p = self.__props.Parent
	while p do
		if p.__class == cls then
			return p
		end
		p = p.__props.Parent
	end
	return nil
end
function methods:FindFirstAncestor(name)
	local p = self.__props.Parent
	while p do
		if p.__props.Name == name then
			return p
		end
		p = p.__props.Parent
	end
	return nil
end
function methods:IsA(name)
	return isa(self.__class, name)
end
function methods:IsDescendantOf(x)
	local p = self.__props.Parent
	while p do
		if p == x then
			return true
		end
		p = p.__props.Parent
	end
	return false
end
function methods:Destroy()
	self.Parent = nil
	self.__destroyed = true
	for _, c in ipairs(self:GetChildren()) do
		c:Destroy()
	end
end
function methods:ClearAllChildren()
	for _, c in ipairs(self:GetChildren()) do
		c:Destroy()
	end
end
function methods:Clone()
	local c = Instance.new(self.__class)
	for k, v in pairs(self.__props) do
		if k ~= "Parent" then
			c.__props[k] = v
		end
	end
	for k, v in pairs(self.__attrs) do
		c.__attrs[k] = v
	end
	for _, ch in ipairs(self.__children) do
		ch:Clone().Parent = c
	end
	return c
end
function methods:SetAttribute(k, v)
	self.__attrs[k] = v
	local s = self.__attrSignals[k]
	if s then
		s:Fire()
	end
end
function methods:GetAttribute(k)
	return self.__attrs[k]
end
function methods:GetAttributes()
	return self.__attrs
end
function methods:GetAttributeChangedSignal(k)
	self.__attrSignals[k] = self.__attrSignals[k] or Signal.new()
	return self.__attrSignals[k]
end
function methods:GetPropertyChangedSignal(k)
	self.__propSignals[k] = self.__propSignals[k] or Signal.new()
	return self.__propSignals[k]
end
function methods:GetFullName()
	local parts = {}
	local x = self
	while x do
		table.insert(parts, 1, x.__props.Name)
		x = x.__props.Parent
	end
	return table.concat(parts, ".")
end
-- звук, анимации и прочее — ничего не делают
for _, name in ipairs({ "Play", "Stop", "Pause", "Resume", "Cancel", "PivotTo", "SetNetworkOwner", "ApplyImpulse", "BreakJoints" }) do
	methods[name] = function() end
end

Instance_mt.__index = function(self, key)
	local m = methods[key]
	if m then
		return m
	end
	local props = rawget(self, "__props")
	local getters = rawget(self, "__getters")
	if getters and getters[key] then
		return getters[key](self)
	end
	local v = props[key]
	if v ~= nil then
		return v
	end
	if EVENTS[key] then
		local s = Signal.new()
		props[key] = s
		return s
	end
	local d = default(rawget(self, "__class"), key)
	if d ~= nil then
		return d
	end
	-- ребёнок по имени
	for _, c in ipairs(rawget(self, "__children")) do
		if c.__props.Name == key then
			return c
		end
	end
	local custom = rawget(self, "__custom")
	if custom and custom[key] then
		return custom[key]
	end
	return nil
end
Instance_mt.__newindex = function(self, key, value)
	local props = rawget(self, "__props")
	if key == "Parent" then
		local old = props.Parent
		if old == value then
			return
		end
		if old then
			local list = rawget(old, "__children")
			for i, c in ipairs(list) do
				if c == self then
					table.remove(list, i)
					break
				end
			end
		end
		props.Parent = value
		if value then
			table.insert(rawget(value, "__children"), self)
			local ca = rawget(value, "__props").ChildAdded
			if ca then
				ca:Fire(self)
			end
		end
		return
	end
	props[key] = value
	local ps = rawget(self, "__propSignals")[key]
	if ps then
		ps:Fire()
	end
end
Instance_mt.__tostring = function(self)
	return self.__props.Name
end

Instance = {}
function Instance.new(cls, parent)
	nextId = nextId + 1
	local o = setmetatable({ __instance = true, __class = cls, __props = { Name = cls, ClassName = cls }, __children = {}, __attrs = {}, __attrSignals = {},
		__propSignals = {}, __id = nextId }, Instance_mt)
	if parent then
		o.Parent = parent
	end
	return o
end
M.Instance = Instance
M.methods = methods

-------------------------------------------------------------------------------
-- Сервисы и game
-------------------------------------------------------------------------------
local services = {}
local function service(name)
	local s = services[name]
	if not s then
		s = Instance.new(name)
		s.Name = name
		services[name] = s
	end
	return s
end
game = Instance.new("DataModel")
game.Name = "Game"
rawset(game, "__custom", {})
methods.GetService = function(self, name)
	return service(name)
end
workspace = service("Workspace")
M.service = service

return M
