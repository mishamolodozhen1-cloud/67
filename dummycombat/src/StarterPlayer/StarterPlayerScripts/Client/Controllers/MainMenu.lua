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
-- Каркас
-------------------------------------------------------------------------------
local function build()
	local gui = Players.LocalPlayer:WaitForChild("PlayerGui"):WaitForChild("MainUI", 10)
	if not gui then
		return
	end
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 30
	local root = Instance.new("Frame")
	root.Name = "Menu"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Parent = root
	-- освобождает мышь, пока меню открыто (камера от первого лица её иначе держит)
	local modal = Instance.new("TextButton")
	modal.Name = "Modal"
	modal.BackgroundTransparency = 1
	modal.Text = ""
	modal.Size = UDim2.fromOffset(0, 0)
	modal.Modal = true
	modal.Parent = root
	-- затемнение слева
	local shade = Kit.Frame(root, { Size = UDim2.new(0, 520, 1, 0), BackgroundColor3 = C.Bg, BackgroundTransparency = 0 })
	local grad = Instance.new("UIGradient")
	grad.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.05), NumberSequenceKeypoint.new(0.7, 0.35), NumberSequenceKeypoint.new(1, 1) })
	grad.Parent = shade
	-- левая колонка
	local left = Instance.new("Frame")
	left.BackgroundTransparency = 1
	left.Position = UDim2.fromOffset(48, 40)
	left.Size = UDim2.new(0, 300, 1, -80)
	left.Parent = root
	Kit.Label(left, "DUMMY", 52, F.Title, C.Text, { Size = UDim2.new(1, 0, 0, 52) })
	Kit.Label(left, "COMBAT", 52, F.Title, C.Accent, { Size = UDim2.new(1, 0, 0, 52), Position = UDim2.fromOffset(0, 48) })
	Kit.Label(left, "BUILT TO BREAK", 13, F.Bold, C.Dim, { Size = UDim2.new(1, 0, 0, 18), Position = UDim2.fromOffset(2, 104) })
	local nav = Instance.new("Frame")
	nav.BackgroundTransparency = 1
	nav.Position = UDim2.fromOffset(0, 150)
	nav.Size = UDim2.new(1, 0, 0, 300)
	nav.Parent = left
	Kit.List(nav, 4)
	local navButtons = {}
	for i, t in ipairs(TABS) do
		local b = Kit.Button(nav, "   " .. t[2], "Ghost", { Size = UDim2.new(1, 0, 0, 44), TextXAlignment = Enum.TextXAlignment.Left, TextSize = 22, LayoutOrder = i })
		local bar = Kit.Frame(b, { Size = UDim2.new(0, 4, 1, -12), Position = UDim2.fromOffset(0, 6), BackgroundColor3 = C.Accent, BackgroundTransparency = 0, Visible = false })
		navButtons[t[1]] = { Button = b, Bar = bar }
		b.Activated:Connect(function()
			tab = t[1]
			MainMenu.Render()
		end)
	end
	-- карточка игрока
	local card = Kit.Frame(left, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 96), BackgroundColor3 = C.Panel, BackgroundTransparency = 0.15 })
	Kit.Corner(card, 8)
	Kit.Padding(card, 12)
	local pname = Kit.Label(card, Players.LocalPlayer.DisplayName, 18, F.Bold, C.Text, { Size = UDim2.new(1, -60, 0, 22) })
	local level = Kit.Label(card, "LVL 1", 16, F.Bold, C.Accent, { Size = UDim2.new(0, 70, 0, 22), Position = UDim2.new(1, -70, 0, 0), TextXAlignment = Enum.TextXAlignment.Right })
	local _, setXp = Kit.Bar(card, C.Accent, { Size = UDim2.new(1, 0, 0, 6), Position = UDim2.fromOffset(0, 32) })
	local xpText = Kit.Label(card, "", 12, F.Medium, C.Dim, { Size = UDim2.new(1, 0, 0, 16), Position = UDim2.fromOffset(0, 42) })
	local coins = Kit.Label(card, "0 COINS", 15, F.Bold, C.Text, { Size = UDim2.new(1, 0, 0, 20), Position = UDim2.fromOffset(0, 58) })
	-- правая панель
	local panel = Kit.Frame(root, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -40, 0.5, 0), Size = UDim2.fromOffset(470, 560), BackgroundColor3 = C.Bg, BackgroundTransparency = 0.18 })
	Kit.Corner(panel, 10)
	Kit.Padding(panel, 18)
	local title = Kit.Label(panel, "", 24, F.Bold, C.Text, { Size = UDim2.new(1, 0, 0, 28) })
	local content = Instance.new("ScrollingFrame")
	content.BackgroundTransparency = 1
	content.BorderSizePixel = 0
	content.Position = UDim2.fromOffset(0, 40)
	content.Size = UDim2.new(1, 0, 1, -40)
	content.ScrollBarThickness = 4
	content.ScrollBarImageColor3 = C.Line
	content.AutomaticCanvasSize = Enum.AutomaticSize.Y
	content.CanvasSize = UDim2.fromOffset(0, 0)
	content.Parent = panel
	Kit.List(content, 10)
	-- уведомление (покупка и т. п.)
	local toast = Kit.Label(root, "", 16, F.Bold, C.Text, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -30), Size = UDim2.fromOffset(500, 24), TextXAlignment = Enum.TextXAlignment.Center, Visible = false })
	Kit.Outline(toast)
	-- пауза на телефоне (в матче)
	local pauseButton = Kit.Button(gui, "II", "Secondary", {
		Name = "PauseButton",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -70, 0, 14),
		Size = UDim2.fromOffset(44, 36),
		TextSize = 18,
		Visible = false,
	})
	pauseButton.Activated:Connect(function()
		MainMenu.SetPaused(not paused)
	end)
	ui = {
		PauseButton = pauseButton,
		Gui = gui,
		Root = root,
		Scale = scale,
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
	return Kit.Label(ui.Content, text, 13, F.Bold, C.Dim, { Size = UDim2.new(1, 0, 0, 18), LayoutOrder = order })
end

local function card(order, height)
	local f = Kit.Frame(ui.Content, { Size = UDim2.new(1, -6, 0, height or 64), BackgroundColor3 = C.Panel2, BackgroundTransparency = 0.15, LayoutOrder = order })
	Kit.Corner(f, 8)
	return f
end

local function renderPlay()
	local phase = match and match:GetAttribute("Phase") or "Idle"
	local me = Players.LocalPlayer
	local myPart = match and match:FindFirstChild("Participants") and match.Participants:FindFirstChild(tostring(me.UserId))
	local queued = myPart and myPart:GetAttribute("Queued") == true
	local left = (match and match:GetAttribute("EndsAt") or 0) - workspace:GetServerTimeNow()
	local status = card(1, 74)
	Kit.Padding(status, 12)
	local head, sub = "", ""
	if phase == "Intermission" then
		head = "NEXT MATCH IN " .. fmtTime(left)
		sub = queued and "YOU'RE IN — VOTE FOR THE MAP" or "PRESS PLAY TO JOIN · VOTE FOR THE MAP"
	elseif phase == "Starting" or phase == "Running" then
		head = string.format("LIVE  ·  %s", match:GetAttribute("ModeName") or "")
		sub = string.format("%s  ·  %s LEFT", match:GetAttribute("MapName") or "", fmtTime(phase == "Running" and left or 0))
	elseif phase == "Results" then
		head = "MATCH ENDING"
		sub = "NEXT VOTE IN " .. fmtTime(left)
	else
		head = "SERVER STARTING"
	end
	Kit.Label(status, head, 20, F.Bold, phase == "Running" and C.Good or C.Text, { Size = UDim2.new(1, 0, 0, 26) })
	Kit.Label(status, sub, 13, F.Medium, C.Dim, { Size = UDim2.new(1, 0, 0, 18), Position = UDim2.fromOffset(0, 30) })
	-- голосование
	if phase == "Intermission" then
		section("VOTE", 2)
		for i = 1, MatchConfig.VoteOptions do
			local mapName = match:GetAttribute("Option" .. i .. "MapName")
			if mapName and mapName ~= "" then
				local modeId = match:GetAttribute("Option" .. i .. "Mode")
				local mode = MatchConfig.Modes[modeId]
				local votes = match:GetAttribute("Option" .. i .. "Votes") or 0
				local f = card(2 + i, 62)
				local b = Kit.Button(f, "", myVote == i and "Primary" or "Secondary", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = myVote == i and 0.1 or 0.6 })
				local textColor = myVote == i and Color3.fromRGB(20, 18, 14) or C.Text
				Kit.Label(b, mapName, 18, F.Bold, textColor, { Position = UDim2.fromOffset(14, 8), Size = UDim2.new(1, -90, 0, 22) })
				Kit.Label(b, mode and mode.DisplayName or tostring(modeId), 13, F.Medium, myVote == i and Color3.fromRGB(60, 50, 30) or C.Dim, { Position = UDim2.fromOffset(14, 32), Size = UDim2.new(1, -90, 0, 18) })
				Kit.Label(b, tostring(votes), 26, F.Bold, textColor, { Position = UDim2.new(1, -70, 0, 0), Size = UDim2.new(0, 56, 1, 0), TextXAlignment = Enum.TextXAlignment.Right })
				b.Activated:Connect(function()
					myVote = i
					net.Fire("Vote", i)
					MainMenu.Render()
				end)
			end
		end
	end
	-- кнопка PLAY
	local playText, style = "PLAY", "Primary"
	if phase == "Running" or phase == "Starting" then
		playText = "JOIN MATCH"
	elseif queued then
		playText, style = "READY  ·  CANCEL", "Secondary"
	end
	local f = card(20, 70)
	f.BackgroundTransparency = 1
	local play = Kit.Button(f, playText, style, { Size = UDim2.fromScale(1, 1), TextSize = 28, Font = F.Title })
	play.Activated:Connect(function()
		if queued and not (phase == "Running" or phase == "Starting") then
			net.Fire("LeaveMatch")
		else
			net.Fire("Play")
			Kit.PlaySound("MatchStart", 0.5)
		end
		task.delay(0.4, MainMenu.Render)
	end)
	section("MODES", 30)
	for i, id in ipairs({ "FFA", "TDM", "GunGame", "Chaos" }) do
		local m = MatchConfig.Modes[id]
		local c = card(30 + i, 52)
		Kit.Padding(c, 10)
		Kit.Label(c, m.DisplayName, 15, F.Bold, C.Text, { Size = UDim2.new(1, 0, 0, 18) })
		Kit.Label(c, m.Description, 12, F.Medium, C.Dim, { Size = UDim2.new(1, 0, 0, 16), Position = UDim2.fromOffset(0, 18), TextTruncate = Enum.TextTruncate.AtEnd })
	end
end

local function itemCard(order, name, info, right, rightStyle, onClick, selected)
	local c = card(order, 58)
	if selected then
		Kit.Stroke(c, C.Accent, 2, 0)
	end
	Kit.Label(c, name, 17, F.Bold, C.Text, { Position = UDim2.fromOffset(14, 8), Size = UDim2.new(1, -170, 0, 22) })
	Kit.Label(c, info, 12, F.Medium, C.Dim, { Position = UDim2.fromOffset(14, 30), Size = UDim2.new(1, -170, 0, 18) })
	if right then
		local b = Kit.Button(c, right, rightStyle or "Secondary", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(140, 38), TextSize = 15 })
		b.Activated:Connect(onClick)
	end
	return c
end

local function weaponInfo(id)
	local w = WeaponConfig.Weapons[id]
	if not w then
		return ""
	end
	return string.format("%d RPM · MAG %d · DMG %d/%d", w.Rpm, w.Magazine, w.Damage and w.Damage.Torso or 0, w.Damage and w.Damage.Head or 0)
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
		local sw = Kit.Frame(c, { Size = UDim2.fromOffset(8, 40), Position = UDim2.fromOffset(0, 9), BackgroundColor3 = it.Item.Color, BackgroundTransparency = 0 })
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
	local c = card(1, 110)
	Kit.Padding(c, 14)
	Kit.Label(c, "LEVEL " .. p.Level, 30, F.Title, C.Accent, { Size = UDim2.new(1, 0, 0, 34) })
	local _, set = Kit.Bar(c, C.Accent, { Size = UDim2.new(1, 0, 0, 8), Position = UDim2.fromOffset(0, 44) })
	set(p.Xp / math.max(p.XpToNext, 1))
	Kit.Label(c, string.format("%d / %d XP  ·  %d COINS", p.Xp, p.XpToNext, p.Coins), 14, F.Medium, C.Dim, { Size = UDim2.new(1, 0, 0, 18), Position = UDim2.fromOffset(0, 58) })
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
		local f = card(2 + i, 36)
		Kit.Label(f, r[1], 14, F.Medium, C.Dim, { Position = UDim2.fromOffset(14, 0), Size = UDim2.new(0.6, 0, 1, 0) })
		Kit.Label(f, tostring(r[2]), 16, F.Bold, C.Text, { Position = UDim2.new(0.6, 0, 0, 0), Size = UDim2.new(0.4, -14, 1, 0), TextXAlignment = Enum.TextXAlignment.Right })
	end
end

local function slider(order, label, min, max, step, key, fmt)
	local s = profileCtl.Settings()
	local f = card(order, 62)
	Kit.Label(f, label, 14, F.Medium, C.Dim, { Position = UDim2.fromOffset(14, 6), Size = UDim2.new(0.7, 0, 0, 20) })
	local value = Kit.Label(f, "", 15, F.Bold, C.Text, { Position = UDim2.new(0.7, 0, 0, 6), Size = UDim2.new(0.3, -14, 0, 20), TextXAlignment = Enum.TextXAlignment.Right })
	local track = Kit.Frame(f, { Position = UDim2.new(0, 14, 0, 38), Size = UDim2.new(1, -28, 0, 6), BackgroundColor3 = C.Line, BackgroundTransparency = 0.2 })
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
	hit.Position = UDim2.new(0, 14, 0, 26)
	hit.Size = UDim2.new(1, -28, 0, 30)
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
		local f = card(21, 54)
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
	local vp = workspace.CurrentCamera.ViewportSize
	ui.Scale.Scale = math.clamp(math.min(vp.X / 1366, vp.Y / 768), 0.55, 1.2)
	local inLobby = lobbyCtl.InLobby()
	local visible = inLobby or paused
	ui.Root.Visible = visible
	ui.Modal.Modal = visible
	ui.Shade.Visible = inLobby
	ui.Left.Visible = inLobby
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
