-- MainMenu: главное меню лобби (этап 8) и меню паузы в матче (клавиша M / кнопка «II»).
--
-- Слева — название, разделы и карточка игрока (уровень, опыт, монеты); справа — содержимое раздела:
--   PLAY     — что сейчас на сервере (голосование за следующую карту и режим / идущий матч / итоги) и
--              большая кнопка PLAY: войти в идущий матч или встать в очередь на следующий;
--   LOADOUT  — основное оружие и окраска манекена (из купленного); на подиуме сразу видно;
--   SHOP     — оружие и окраски за монеты (с порога уровня);
--   PROFILE  — уровень, опыт, монеты, статистика;
--   SETTINGS — чувствительность (обычная и в прицеле), поле зрения, громкость (общая, музыка, эффекты).
-- В матче по M — пауза: продолжить, настройки, выйти в лобби.
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Configs = ReplicatedStorage:WaitForChild("Configs")
local PC = require(Configs:WaitForChild("ProgressionConfig"))
local MatchConfig = require(Configs:WaitForChild("MatchConfig"))
local WeaponConfig = require(Configs:WaitForChild("WeaponConfig"))
local Kit = require(script.Parent.Parent:WaitForChild("Ui"):WaitForChild("Kit"))

local MainMenu = { Name = "MainMenu" }

local C, F = Kit.Colors, Kit.Fonts
local net, profileCtl, lobbyCtl = nil, nil, nil
local ui = nil
local tab = "Play"
local paused = false
local match = nil
local myVote = nil
local notice = nil
local conns = {} -- соединения текущего раздела (ползунки) — снимаются при перерисовке

local TABS = { { "Play", "PLAY" }, { "Loadout", "LOADOUT" }, { "Shop", "SHOP" }, { "Profile", "PROFILE" }, { "Settings", "SETTINGS" } }

local function fmtTime(s)
	s = math.max(0, math.floor(s))
	return string.format("%d:%02d", math.floor(s / 60), s % 60)
end

local function clear(frame)
	for _, c in ipairs(frame:GetChildren()) do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
end

local function sorted(items)
	local list = {}
	for id, it in pairs(items) do
		if not it.Hidden then
			table.insert(list, { Id = id, Item = it })
		end
	end
	table.sort(list, function(a, b)
		return (a.Item.Order or 99) < (b.Item.Order or 99)
	end)
	return list
end

-------------------------------------------------------------------------------
-- Каркас. Всё меню — на «холсте» (Kit.Canvas) размером не меньше 900 × 400 единиц дизайна: на телефоне масштаб
-- около 0.8, на мониторе — до 1.5. Область меню не заходит под кнопки Roblox (Kit.SafeGui).
--   слева: название, разделы, карточка игрока внизу; справа: панель раздела; в середине виден свой манекен.
-------------------------------------------------------------------------------
local W_LEFT, W_PANEL, MARGIN = 228, 420, 16

local function build()
	local gui = Players.LocalPlayer:WaitForChild("PlayerGui"):WaitForChild("MainUI", 10)
	if not gui then
		return
	end
	Kit.SafeGui(gui)
	gui.DisplayOrder = 30
	-- затемнение слева (шире области меню: и под полосой кнопок Roblox)
	local shade = Kit.Frame(gui, { Name = "Shade", Position = UDim2.new(0, -80, 0, -120), Size = UDim2.new(0.55, 80, 1, 240), BackgroundColor3 = C.Bg, BackgroundTransparency = 0 })
	local grad = Instance.new("UIGradient")
	grad.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(0.6, 0.55), NumberSequenceKeypoint.new(1, 1) })
	grad.Parent = shade
	local root = Kit.Canvas(gui, 900, 400, 0.6, 1.5)
	root.Name = "Menu"
	-- освобождает мышь, пока меню открыто (камера от первого лица её иначе держит)
	local modal = Instance.new("TextButton")
	modal.Name = "Modal"
	modal.BackgroundTransparency = 1
	modal.Text = ""
	modal.Size = UDim2.fromOffset(0, 0)
	modal.Modal = true
	modal.Parent = root
	-- левая колонка
	local left = Instance.new("Frame")
	left.Name = "Left"
	left.BackgroundTransparency = 1
	left.Position = UDim2.fromOffset(MARGIN, 10)
	left.Size = UDim2.new(0, W_LEFT, 1, -20)
	left.Parent = root
	Kit.Label(left, "DUMMY", 30, F.Title, C.Text, { Size = UDim2.new(1, 0, 0, 30) })
	Kit.Label(left, "COMBAT", 30, F.Title, C.Accent, { Size = UDim2.new(1, 0, 0, 30), Position = UDim2.fromOffset(0, 27) })
	local nav = Instance.new("Frame")
	nav.Name = "Nav"
	nav.BackgroundTransparency = 1
	nav.Position = UDim2.fromOffset(0, 72)
	nav.Size = UDim2.new(1, 0, 0, 5 * 36 + 4 * 4)
	nav.Parent = left
	Kit.List(nav, 4)
	local navButtons = {}
	for i, t in ipairs(TABS) do
		local b = Kit.Button(nav, t[2], "Ghost", { Size = UDim2.new(1, 0, 0, 36), TextXAlignment = Enum.TextXAlignment.Left, TextSize = 16, LayoutOrder = i })
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 16)
		pad.Parent = b
		local bar = Kit.Frame(b, { Size = UDim2.new(0, 3, 1, -12), Position = UDim2.fromOffset(-16, 6), BackgroundColor3 = C.Accent, BackgroundTransparency = 0, Visible = false })
		navButtons[t[1]] = { Button = b, Bar = bar }
		b.Activated:Connect(function()
			tab = t[1]
			MainMenu.Render()
		end)
	end
	-- карточка игрока (внизу колонки)
	local card = Kit.Frame(left, { Name = "Card", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 66), BackgroundColor3 = C.Panel, BackgroundTransparency = 0.15 })
	Kit.Corner(card, 8)
	Kit.Padding(card, 10)
	local pname = Kit.Label(card, Players.LocalPlayer.DisplayName, 14, F.Bold, C.Text, { Size = UDim2.new(1, -56, 0, 18), TextTruncate = Enum.TextTruncate.AtEnd })
	local level = Kit.Label(card, "LVL 1", 13, F.Bold, C.Accent, { Size = UDim2.new(0, 56, 0, 18), Position = UDim2.new(1, -56, 0, 0), TextXAlignment = Enum.TextXAlignment.Right })
	local _, setXp = Kit.Bar(card, C.Accent, { Size = UDim2.new(1, 0, 0, 4), Position = UDim2.fromOffset(0, 23) })
	local xpText = Kit.Label(card, "", 11, F.Medium, C.Dim, { Size = UDim2.new(0.6, 0, 0, 14), Position = UDim2.fromOffset(0, 32) })
	local coins = Kit.Label(card, "0 COINS", 12, F.Bold, C.Text, { Size = UDim2.new(0.4, 0, 0, 14), Position = UDim2.new(0.6, 0, 0, 32), TextXAlignment = Enum.TextXAlignment.Right })
	-- правая панель
	local panel = Kit.Frame(root, { Name = "Panel", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -MARGIN, 0, 10), Size = UDim2.new(0, W_PANEL, 1, -20), BackgroundColor3 = C.Bg, BackgroundTransparency = 0.12 })
	Kit.Corner(panel, 10)
	Kit.Padding(panel, 14)
	local title = Kit.Label(panel, "", 18, F.Bold, C.Text, { Size = UDim2.new(1, 0, 0, 22) })
	local content = Instance.new("ScrollingFrame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.BorderSizePixel = 0
	content.Position = UDim2.fromOffset(0, 32)
	content.Size = UDim2.new(1, 0, 1, -32)
	content.ScrollBarThickness = 3
	content.ScrollBarImageColor3 = C.Line
	content.AutomaticCanvasSize = Enum.AutomaticSize.Y
	content.CanvasSize = UDim2.fromOffset(0, 0)
	content.ScrollingDirection = Enum.ScrollingDirection.Y
	content.Parent = panel
	Kit.List(content, 8)
	-- уведомление (покупка и т. п.) — над серединой низа
	local toast = Kit.Label(root, "", 15, F.Bold, C.Text, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -18), Size = UDim2.fromOffset(420, 22), TextXAlignment = Enum.TextXAlignment.Center, Visible = false })
	Kit.Outline(toast)
	-- пауза на телефоне (в матче; меню при этом скрыто — кнопка прямо в ScreenGui)
	local pauseLayer = Kit.Canvas(gui, 900, 400, 0.6, 1.25)
	pauseLayer.Name = "PauseLayer"
	local pauseButton = Kit.Button(pauseLayer, "II", "Secondary", {
		Name = "PauseButton",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 6),
		Size = UDim2.fromOffset(44, 34),
		TextSize = 16,
		BackgroundTransparency = 0.35,
		Visible = false,
	})
	pauseButton.Activated:Connect(function()
		MainMenu.SetPaused(not paused)
	end)
	ui = {
		PauseButton = pauseButton,
		Gui = gui,
		Root = root,
		Modal = modal,
		Shade = shade,
		Left = left,
		NavButtons = navButtons,
		Name = pname,
		Level = level,
		SetXp = setXp,
		XpText = xpText,
		Coins = coins,
		Panel = panel,
		Title = title,
		Content = content,
		Toast = toast,
	}
end

local function showNotice(text, color)
	notice = { Text = text, Color = color or C.Text, Until = os.clock() + 2.5 }
end

-------------------------------------------------------------------------------
-- Разделы
-------------------------------------------------------------------------------
local function section(text, order)
	return Kit.Label(ui.Content, text, 11, F.Bold, C.Dim, { Size = UDim2.new(1, 0, 0, 16), LayoutOrder = order })
end

local function card(order, height)
	local f = Kit.Frame(ui.Content, { Size = UDim2.new(1, -6, 0, height or 56), BackgroundColor3 = C.Panel2, BackgroundTransparency = 0.15, LayoutOrder = order })
	Kit.Corner(f, 8)
	return f
end

local function touchDevice()
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

local CONTROLS_PC = {
	{ "MOVE", "WASD · SHIFT sprint · C crouch · SPACE jump" },
	{ "SHOOT", "LMB fire · RMB aim · R reload · B fire mode" },
	{ "MATCH", "TAB scoreboard · M pause menu" },
}
local CONTROLS_TOUCH = {
	{ "MOVE", "Left side of the screen · RUN and CROUCH buttons" },
	{ "SHOOT", "FIRE (drag to look) · AIM · R reload" },
	{ "MATCH", "Scores button at the top · II — pause menu" },
}

local function renderPlay()
	local phase = match and match:GetAttribute("Phase") or "Idle"
	local me = Players.LocalPlayer
	local myPart = match and match:FindFirstChild("Participants") and match.Participants:FindFirstChild(tostring(me.UserId))
	local queued = myPart and myPart:GetAttribute("Queued") == true
	local left = (match and match:GetAttribute("EndsAt") or 0) - workspace:GetServerTimeNow()
	local mapName = match and match:GetAttribute("MapName") or ""
	local modeName = match and match:GetAttribute("ModeName") or ""
	-- что сейчас на сервере
	local head, sub, headColor = "", "", C.Text
	if phase == "Intermission" then
		head = "NEXT MATCH IN " .. fmtTime(left)
		sub = queued and "YOU'RE IN · VOTE FOR THE MAP BELOW" or "JOIN NOW · VOTE FOR THE MAP BELOW"
	elseif phase == "Starting" then
		head, headColor = "STARTING · " .. mapName, C.Good
		sub = modeName
	elseif phase == "Running" then
		head, headColor = "LIVE · " .. modeName, C.Good
		sub = string.format("%s · %s LEFT", mapName, fmtTime(left))
	elseif phase == "Results" then
		head = "MATCH OVER"
		sub = "NEXT VOTE IN " .. fmtTime(left)
	else
		head = "WAITING FOR THE SERVER"
	end
	local status = card(1, 40)
	status.BackgroundTransparency = 1
	Kit.Label(status, head, 17, F.Bold, headColor, { Size = UDim2.new(1, 0, 0, 22), TextTruncate = Enum.TextTruncate.AtEnd })
	Kit.Label(status, sub, 11, F.Medium, C.Dim, { Size = UDim2.new(1, 0, 0, 14), Position = UDim2.fromOffset(0, 24), TextTruncate = Enum.TextTruncate.AtEnd })
	-- кнопка PLAY
	local playText, style = "PLAY", "Primary"
	if phase == "Running" or phase == "Starting" then
		playText = "JOIN MATCH"
	elseif queued then
		playText, style = "READY · TAP TO CANCEL", "Secondary"
	end
	local f = card(2, 50)
	f.BackgroundTransparency = 1
	local play = Kit.Button(f, playText, style, { Size = UDim2.fromScale(1, 1), TextSize = queued and 17 or 24, Font = F.Title })
	play.Activated:Connect(function()
		if queued and not (phase == "Running" or phase == "Starting") then
			net.Fire("LeaveMatch")
		else
			net.Fire("Play")
			Kit.PlaySound("MatchStart", 0.5)
		end
		task.delay(0.4, MainMenu.Render)
	end)
	-- голосование за следующую карту
	if phase == "Intermission" then
		section("VOTE FOR THE NEXT MAP", 10)
		for i = 1, MatchConfig.VoteOptions do
			local optMap = match:GetAttribute("Option" .. i .. "MapName")
			if optMap and optMap ~= "" then
				local modeId = match:GetAttribute("Option" .. i .. "Mode")
				local mode = MatchConfig.Modes[modeId]
				local votes = match:GetAttribute("Option" .. i .. "Votes") or 0
				local chosen = myVote == i
				local vf = card(10 + i, 46)
				local b = Kit.Button(vf, "", chosen and "Primary" or "Secondary", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = chosen and 0.05 or 0.55 })
				local textColor = chosen and Color3.fromRGB(20, 18, 14) or C.Text
				Kit.Label(b, optMap, 15, F.Bold, textColor, { Position = UDim2.fromOffset(12, 5), Size = UDim2.new(1, -64, 0, 20) })
				Kit.Label(b, mode and mode.DisplayName or tostring(modeId), 11, F.Bold, chosen and Color3.fromRGB(70, 58, 34) or C.Dim, { Position = UDim2.fromOffset(12, 25), Size = UDim2.new(1, -64, 0, 14) })
				Kit.Label(b, tostring(votes), 20, F.Bold, textColor, { Position = UDim2.new(1, -52, 0, 0), Size = UDim2.new(0, 40, 1, 0), TextXAlignment = Enum.TextXAlignment.Right })
				b.Activated:Connect(function()
					myVote = i
					net.Fire("Vote", i)
					MainMenu.Render()
				end)
			end
		end
	end
	-- управление (под устройство)
	section("CONTROLS", 30)
	for i, row in ipairs(touchDevice() and CONTROLS_TOUCH or CONTROLS_PC) do
		local cf = card(30 + i, 38)
		Kit.Label(cf, row[1], 11, F.Bold, C.Accent, { Position = UDim2.fromOffset(12, 0), Size = UDim2.new(0, 56, 1, 0) })
		Kit.Label(cf, row[2], 12, F.Medium, C.Text, { Position = UDim2.fromOffset(70, 0), Size = UDim2.new(1, -80, 1, 0), TextWrapped = true })
	end
end

local function itemCard(order, name, info, right, rightStyle, onClick, selected)
	local c = card(order, 50)
	if selected then
		Kit.Stroke(c, C.Accent, 2, 0)
	end
	Kit.Label(c, name, 15, F.Bold, C.Text, { Position = UDim2.fromOffset(16, 6), Size = UDim2.new(1, -150, 0, 20), TextTruncate = Enum.TextTruncate.AtEnd })
	Kit.Label(c, info, 11, F.Medium, C.Dim, { Position = UDim2.fromOffset(16, 27), Size = UDim2.new(1, -150, 0, 14), TextTruncate = Enum.TextTruncate.AtEnd })
	if right then
		local b = Kit.Button(c, right, rightStyle or "Secondary", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(118, 34), TextSize = 13 })
		b.Activated:Connect(onClick)
	end
	return c
end

local function weaponInfo(id)
	local w = WeaponConfig.Weapons[id]
	if not w then
		return ""
	end
	local torso, head = w.Damage and w.Damage.Torso or 0, w.Damage and w.Damage.Head or 0
	if w.Pellets and w.Pellets > 1 then
		return string.format("%d RPM · MAG %d · DMG %d×%d", w.Rpm, w.Magazine, torso, w.Pellets)
	end
	return string.format("%d RPM · MAG %d · DMG %d/%d", w.Rpm, w.Magazine, torso, head)
end

local function renderLoadout()
	local p = profileCtl.Get()
	if not p then
		section("LOADING PROFILE…", 1)
		return
	end
	section("PRIMARY WEAPON", 1)
	for i, it in ipairs(sorted(PC.Weapons)) do
		local w = WeaponConfig.Weapons[it.Id]
		if w then
			local owned = p.Owned.Weapons[it.Id]
			local selected = p.Loadout.Primary == it.Id
			itemCard(1 + i, w.DisplayName, weaponInfo(it.Id), selected and "EQUIPPED" or (owned and "EQUIP" or "IN SHOP"), selected and "Primary" or "Secondary", function()
				if owned and not selected then
					profileCtl.Equip("Primary", it.Id)
				elseif not owned then
					tab = "Shop"
					MainMenu.Render()
				end
			end, selected)
		end
	end
	section("DUMMY FINISH", 20)
	for i, it in ipairs(sorted(PC.Skins)) do
		local owned = p.Owned.Skins[it.Id]
		local selected = p.Loadout.Skin == it.Id
		local c = itemCard(20 + i, it.Item.DisplayName, owned and "OWNED" or (it.Item.Price .. " COINS"), selected and "EQUIPPED" or (owned and "EQUIP" or "IN SHOP"), selected and "Primary" or "Secondary", function()
			if owned and not selected then
				profileCtl.Equip("Skin", it.Id)
			elseif not owned then
				tab = "Shop"
				MainMenu.Render()
			end
		end, selected)
		local sw = Kit.Frame(c, { Size = UDim2.fromOffset(6, 34), Position = UDim2.fromOffset(4, 8), BackgroundColor3 = it.Item.Color, BackgroundTransparency = 0 })
		Kit.Corner(sw, 2)
	end
end

local function renderShop()
	local p = profileCtl.Get()
	if not p then
		section("LOADING PROFILE…", 1)
		return
	end
	section(string.format("YOU HAVE %d COINS · LEVEL %d", p.Coins, p.Level), 1)
	section("WEAPONS", 2)
	for i, it in ipairs(sorted(PC.Weapons)) do
		local w = WeaponConfig.Weapons[it.Id]
		if w and it.Item.Price > 0 then
			local owned = p.Owned.Weapons[it.Id]
			local locked = p.Level < (it.Item.Level or 1)
			local label = owned and "OWNED" or (locked and ("LEVEL " .. it.Item.Level) or (it.Item.Price .. " COINS"))
			itemCard(2 + i, w.DisplayName, weaponInfo(it.Id), label, (owned or locked) and "Ghost" or "Primary", function()
				if not owned and not locked then
					profileCtl.Buy("Weapon", it.Id)
				end
			end)
		end
	end
	section("DUMMY FINISHES", 20)
	for i, it in ipairs(sorted(PC.Skins)) do
		if it.Item.Price > 0 then
			local owned = p.Owned.Skins[it.Id]
			local locked = p.Level < (it.Item.Level or 1)
			local label = owned and "OWNED" or (locked and ("LEVEL " .. it.Item.Level) or (it.Item.Price .. " COINS"))
			local c = itemCard(20 + i, it.Item.DisplayName, "Paint for your dummy", label, (owned or locked) and "Ghost" or "Primary", function()
				if not owned and not locked then
					profileCtl.Buy("Skin", it.Id)
				end
			end)
			local sw = Kit.Frame(c, { Size = UDim2.fromOffset(8, 40), Position = UDim2.fromOffset(0, 9), BackgroundColor3 = it.Item.Color, BackgroundTransparency = 0 })
			Kit.Corner(sw, 2)
		end
	end
end

local function renderProfile()
	local p = profileCtl.Get()
	if not p then
		section("LOADING PROFILE…", 1)
		return
	end
	local c = card(1, 84)
	Kit.Padding(c, 12)
	Kit.Label(c, "LEVEL " .. p.Level, 24, F.Title, C.Accent, { Size = UDim2.new(1, 0, 0, 28) })
	local _, set = Kit.Bar(c, C.Accent, { Size = UDim2.new(1, 0, 0, 6), Position = UDim2.fromOffset(0, 34) })
	set(p.Xp / math.max(p.XpToNext, 1))
	Kit.Label(c, string.format("%d / %d XP  ·  %d COINS", p.Xp, p.XpToNext, p.Coins), 12, F.Medium, C.Dim, { Size = UDim2.new(1, 0, 0, 16), Position = UDim2.fromOffset(0, 44) })
	local s = p.Stats or {}
	local kd = (s.Deaths or 0) > 0 and (s.Kills or 0) / s.Deaths or (s.Kills or 0)
	local rows = {
		{ "KILLS", s.Kills or 0 },
		{ "DEATHS", s.Deaths or 0 },
		{ "K/D", string.format("%.2f", kd) },
		{ "HEADSHOTS", s.Headshots or 0 },
		{ "ASSISTS", s.Assists or 0 },
		{ "MATCHES", s.Matches or 0 },
		{ "WINS", s.Wins or 0 },
	}
	section("STATS", 2)
	for i, r in ipairs(rows) do
		local f = card(2 + i, 30)
		Kit.Label(f, r[1], 12, F.Medium, C.Dim, { Position = UDim2.fromOffset(12, 0), Size = UDim2.new(0.6, 0, 1, 0) })
		Kit.Label(f, tostring(r[2]), 14, F.Bold, C.Text, { Position = UDim2.new(0.6, 0, 0, 0), Size = UDim2.new(0.4, -12, 1, 0), TextXAlignment = Enum.TextXAlignment.Right })
	end
end

local function slider(order, label, min, max, step, key, fmt)
	local s = profileCtl.Settings()
	local f = card(order, 54)
	Kit.Label(f, label, 12, F.Medium, C.Dim, { Position = UDim2.fromOffset(14, 6), Size = UDim2.new(0.7, 0, 0, 18) })
	local value = Kit.Label(f, "", 13, F.Bold, C.Text, { Position = UDim2.new(0.7, 0, 0, 6), Size = UDim2.new(0.3, -14, 0, 18), TextXAlignment = Enum.TextXAlignment.Right })
	local track = Kit.Frame(f, { Position = UDim2.new(0, 14, 0, 34), Size = UDim2.new(1, -28, 0, 6), BackgroundColor3 = C.Line, BackgroundTransparency = 0.2 })
	Kit.Corner(track, 3)
	local fill = Kit.Frame(track, { Size = UDim2.fromScale(0, 1), BackgroundColor3 = C.Accent, BackgroundTransparency = 0 })
	Kit.Corner(fill, 3)
	local knob = Kit.Frame(track, { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(16, 16), BackgroundColor3 = C.Text, BackgroundTransparency = 0 })
	Kit.Corner(knob, 8)
	local function show(v)
		local k = (v - min) / (max - min)
		fill.Size = UDim2.fromScale(k, 1)
		knob.Position = UDim2.fromScale(k, 0.5)
		value.Text = fmt and fmt(v) or string.format("%.2f", v)
	end
	show(s[key])
	local dragging = false
	local hit = Instance.new("TextButton")
	hit.BackgroundTransparency = 1
	hit.Text = ""
	hit.Position = UDim2.new(0, 6, 0, 22)
	hit.Size = UDim2.new(1, -12, 0, 30)
	hit.Parent = f
	local function set(x)
		local k = math.clamp((x - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0, 1)
		local v = min + (max - min) * k
		v = math.floor(v / step + 0.5) * step
		profileCtl.SetSetting(key, v)
		show(v)
	end
	hit.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			set(input.Position.X)
		end
	end)
	table.insert(conns, UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			set(input.Position.X)
		end
	end))
	table.insert(conns, UserInputService.InputEnded:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
			dragging = false
			profileCtl.CommitSettings()
		end
	end))
end

local function renderSettings()
	local pct = function(v)
		return string.format("%d%%", math.floor(v * 100 + 0.5))
	end
	if paused then
		local rf = card(0, 46)
		rf.BackgroundTransparency = 1
		local resume = Kit.Button(rf, "RESUME", "Primary", { Size = UDim2.fromScale(1, 1), TextSize = 18, Font = F.Title })
		resume.Activated:Connect(function()
			MainMenu.SetPaused(false)
		end)
	end
	section("CONTROLS", 1)
	slider(2, "LOOK SENSITIVITY", 0.2, 3, 0.05, "Sensitivity")
	slider(3, "AIM SENSITIVITY", 0.3, 1.2, 0.02, "AimSensitivity", pct)
	slider(4, "FIELD OF VIEW", 60, 95, 1, "Fov", function(v)
		return string.format("%d°", v)
	end)
	section("AUDIO", 10)
	slider(11, "MASTER", 0, 1, 0.05, "Master", pct)
	slider(12, "MUSIC", 0, 1, 0.05, "Music", pct)
	slider(13, "EFFECTS", 0, 1, 0.05, "Sfx", pct)
	if paused then
		section("MATCH", 20)
		local f = card(21, 46)
		f.BackgroundTransparency = 1
		local leave = Kit.Button(f, "LEAVE MATCH", "Secondary", { Size = UDim2.fromScale(1, 1) })
		leave.TextColor3 = C.Danger
		leave.Activated:Connect(function()
			net.Fire("LeaveMatch")
			paused = false
			MainMenu.Render()
		end)
	end
end

local RENDER = { Play = renderPlay, Loadout = renderLoadout, Shop = renderShop, Profile = renderProfile, Settings = renderSettings }

function MainMenu.Render()
	if not ui then
		return
	end
	clear(ui.Content)
	for _, c in ipairs(conns) do
		c:Disconnect()
	end
	table.clear(conns)
	for id, nb in pairs(ui.NavButtons) do
		nb.Bar.Visible = id == tab
		nb.Button.TextColor3 = id == tab and C.Text or C.Dim
	end
	local titles = { Play = "PLAY", Loadout = "LOADOUT", Shop = "SHOP", Profile = "PROFILE", Settings = "SETTINGS" }
	ui.Title.Text = paused and ("PAUSED  ·  " .. titles[tab]) or titles[tab]
	RENDER[tab]()
end

local function updateCard()
	local p = profileCtl.Get()
	if not (ui and p) then
		return
	end
	ui.Level.Text = "LVL " .. p.Level
	ui.SetXp(p.Xp / math.max(p.XpToNext, 1))
	ui.XpText.Text = string.format("%d / %d XP", p.Xp, p.XpToNext)
	ui.Coins.Text = string.format("%d COINS", p.Coins)
end

-------------------------------------------------------------------------------
local lastRender = 0
local function update()
	if not ui then
		return
	end
	local inLobby = lobbyCtl.InLobby()
	local visible = inLobby or paused
	ui.Root.Visible = visible
	ui.Modal.Modal = visible
	ui.Shade.Visible = inLobby
	ui.Left.Visible = inLobby
	-- в паузе панель ниже кнопки «II» (она остаётся на месте и закрывает паузу)
	ui.Panel.Position = UDim2.new(1, -MARGIN, 0, inLobby and 10 or 48)
	ui.Panel.Size = UDim2.new(0, W_PANEL, 1, inLobby and -20 or -58)
	local touch = UserInputService.TouchEnabled and UserInputService:GetLastInputType() == Enum.UserInputType.Touch
	ui.PauseButton.Visible = touch and not inLobby
	-- в паузе — только настройки и выход
	if paused and not inLobby and tab ~= "Settings" then
		tab = "Settings"
		MainMenu.Render()
	end
	-- раздел PLAY живой: обновляем раз в секунду
	if visible and tab == "Play" and os.clock() - lastRender > 1 then
		lastRender = os.clock()
		MainMenu.Render()
	end
	if notice and os.clock() < notice.Until then
		ui.Toast.Visible = true
		ui.Toast.Text = notice.Text
		ui.Toast.TextColor3 = notice.Color
	else
		ui.Toast.Visible = false
	end
end

function MainMenu.SetPaused(on)
	paused = on and not lobbyCtl.InLobby()
	if paused then
		tab = "Settings"
	else
		tab = "Play"
	end
	MainMenu.Render()
end

function MainMenu.SetTab(t)
	tab = t
	MainMenu.Render()
end

function MainMenu.IsPaused()
	return paused
end

function MainMenu.Init(context)
	net = context.Get("ClientNet")
	profileCtl = context.Get("ProfileController")
	lobbyCtl = context.Get("LobbyController")
end

function MainMenu.Start()
	task.spawn(function()
		match = ReplicatedStorage:WaitForChild("Match", 30)
		build()
		if not ui then
			return
		end
		profileCtl.Changed:Connect(function()
			updateCard()
			if tab ~= "Play" and tab ~= "Settings" then
				MainMenu.Render()
			end
		end)
		profileCtl.ShopResult:Connect(function(r)
			if r.Ok then
				showNotice("PURCHASED", C.Good)
				Kit.PlaySound("Purchase", 0.6)
			else
				local why = { Coins = "NOT ENOUGH COINS", Level = "LEVEL TOO LOW", Owned = "ALREADY OWNED" }
				showNotice(why[r.Reason] or "UNAVAILABLE", C.Danger)
				Kit.PlaySound("Error", 0.5)
			end
		end)
		lobbyCtl.ModeChanged:Connect(function(inLobby)
			paused = false
			myVote = nil
			tab = "Play"
			MainMenu.Render()
			if inLobby then
				updateCard()
			end
		end)
		match:GetAttributeChangedSignal("Phase"):Connect(function()
			if match:GetAttribute("Phase") == "Intermission" then
				myVote = nil
			end
		end)
		ContextActionService:BindAction("DC_Pause", function(_, state)
			if state == Enum.UserInputState.Begin and not lobbyCtl.InLobby() then
				MainMenu.SetPaused(not paused)
			end
			return Enum.ContextActionResult.Sink
		end, false, Enum.KeyCode.M, Enum.KeyCode.ButtonStart)
		updateCard()
		MainMenu.Render()
		RunService.RenderStepped:Connect(update)
	end)
end

return MainMenu
