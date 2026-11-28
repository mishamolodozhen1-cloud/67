-- CombatHUD: боевой интерфейс (этап 5) — здоровье, ранение, лента убийств, «ликвидирован», экран гибели.
--
--   • здоровье слева внизу: число и полоса (мало — красная); пока действует защита после появления —
--     подпись PROTECTED;
--   • ранение: края экрана краснеют (сильнее при большом уроне и при малом здоровье), стрелка у прицела
--     показывает, откуда стреляли (поворачивается вместе со взглядом, гаснет за 1.6 с);
--   • лента убийств справа вверху: «кто [оружие] кого», в голову — значок; строки со своим участием выделены;
--   • свои убийства: по центру внизу ELIMINATED + имя (и HEADSHOT), помощь — ASSIST; звук;
--   • своя гибель: снизу — кто убил, чем, и отсчёт до возрождения.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Kit = require(script.Parent.Parent:WaitForChild("Ui"):WaitForChild("Kit"))

local CombatHUD = { Name = "CombatHUD" }

local C, F = Kit.Colors, Kit.Fonts
local net, characters, weapons = nil, nil, nil
local ui = nil
local indicators = {}
local feed = {}
local hurt = 0
local death = nil -- { Until = os.clock(), Text }
local MAX_FEED = 5

local function viewportGui()
	local hud = Players.LocalPlayer:WaitForChild("PlayerGui"):WaitForChild("HUD", 10)
	return hud
end

local function edge(parent, rotation, anchor, pos, size)
	local f = Kit.Frame(parent, {
		AnchorPoint = anchor,
		Position = pos,
		Size = size,
		BackgroundColor3 = C.Danger,
		BackgroundTransparency = 0,
	})
	local g = Instance.new("UIGradient")
	g.Rotation = rotation
	g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 1) })
	g.Parent = f
	return f, g
end

local function build()
	local hud = viewportGui()
	if not hud then
		return
	end
	local root = Instance.new("Frame")
	root.Name = "Combat"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.Parent = hud
	-- края экрана при ранении
	local vignette = Instance.new("Frame")
	vignette.Name = "Hurt"
	vignette.BackgroundTransparency = 1
	vignette.Size = UDim2.fromScale(1, 1)
	vignette.ZIndex = 0
	vignette.Parent = root
	local edges = {
		{ edge(vignette, 90, Vector2.new(0, 0), UDim2.fromScale(0, 0), UDim2.new(1, 0, 0.22, 0)) },
		{ edge(vignette, 270, Vector2.new(0, 1), UDim2.fromScale(0, 1), UDim2.new(1, 0, 0.22, 0)) },
		{ edge(vignette, 0, Vector2.new(0, 0), UDim2.fromScale(0, 0), UDim2.new(0.16, 0, 1, 0)) },
		{ edge(vignette, 180, Vector2.new(1, 0), UDim2.fromScale(1, 0), UDim2.new(0.16, 0, 1, 0)) },
	}
	-- здоровье
	local health = Instance.new("Frame")
	health.Name = "Health"
	health.BackgroundTransparency = 1
	health.AnchorPoint = Vector2.new(0, 1)
	health.Position = UDim2.new(0, 28, 1, -24)
	health.Size = UDim2.fromOffset(240, 60)
	health.Parent = root
	local hpText = Kit.Label(health, "100", 40, F.Bold, C.Text, { Size = UDim2.fromOffset(90, 44), Position = UDim2.fromOffset(0, 0) })
	Kit.Outline(hpText)
	local hpCaption = Kit.Label(health, "HP", 14, F.Medium, C.Dim, { Size = UDim2.fromOffset(40, 20), Position = UDim2.fromOffset(84, 18) })
	Kit.Outline(hpCaption, 0.6)
	local barBg, setBar, barFill = Kit.Bar(health, C.Text, { Size = UDim2.fromOffset(180, 5), Position = UDim2.fromOffset(2, 48) })
	local protect = Kit.Label(health, "PROTECTED", 12, F.Bold, C.Accent, { Size = UDim2.fromOffset(120, 16), Position = UDim2.fromOffset(122, 20), Visible = false })
	Kit.Outline(protect, 0.6)
	-- указатели направления урона
	local dirs = Instance.new("Frame")
	dirs.Name = "DamageDirections"
	dirs.BackgroundTransparency = 1
	dirs.AnchorPoint = Vector2.new(0.5, 0.5)
	dirs.Position = UDim2.fromScale(0.5, 0.5)
	dirs.Size = UDim2.fromOffset(0, 0)
	dirs.Parent = root
	-- лента убийств
	local feedFrame = Instance.new("Frame")
	feedFrame.Name = "KillFeed"
	feedFrame.BackgroundTransparency = 1
	feedFrame.AnchorPoint = Vector2.new(1, 0)
	feedFrame.Position = UDim2.new(1, -20, 0, 70)
	feedFrame.Size = UDim2.fromOffset(420, 200)
	feedFrame.Parent = root
	local list = Kit.List(feedFrame, 4, false, Enum.HorizontalAlignment.Right)
	list.VerticalAlignment = Enum.VerticalAlignment.Top
	-- свои убийства
	local banner = Instance.new("Frame")
	banner.Name = "Eliminated"
	banner.BackgroundTransparency = 1
	banner.AnchorPoint = Vector2.new(0.5, 1)
	banner.Position = UDim2.new(0.5, 0, 1, -150)
	banner.Size = UDim2.fromOffset(420, 64)
	banner.Visible = false
	banner.Parent = root
	local bTitle = Kit.Label(banner, "ELIMINATED", 15, F.Bold, C.Danger, { Size = UDim2.new(1, 0, 0, 20), TextXAlignment = Enum.TextXAlignment.Center })
	Kit.Outline(bTitle)
	local bName = Kit.Label(banner, "", 26, F.Bold, C.Text, { Size = UDim2.new(1, 0, 0, 32), Position = UDim2.fromOffset(0, 22), TextXAlignment = Enum.TextXAlignment.Center })
	Kit.Outline(bName)
	-- своя гибель
	local deathFrame = Kit.Frame(root, {
		Name = "Death",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -70),
		Size = UDim2.fromOffset(460, 92),
		BackgroundColor3 = C.Bg,
		BackgroundTransparency = 0.25,
		Visible = false,
	})
	Kit.Corner(deathFrame, 8)
	local dTitle = Kit.Label(deathFrame, "ELIMINATED BY", 13, F.Bold, C.Dim, { Size = UDim2.new(1, 0, 0, 18), Position = UDim2.fromOffset(0, 10), TextXAlignment = Enum.TextXAlignment.Center })
	local dName = Kit.Label(deathFrame, "", 26, F.Bold, C.Text, { Size = UDim2.new(1, 0, 0, 30), Position = UDim2.fromOffset(0, 28), TextXAlignment = Enum.TextXAlignment.Center })
	local dInfo = Kit.Label(deathFrame, "", 14, F.Medium, C.Dim, { Size = UDim2.new(1, 0, 0, 18), Position = UDim2.fromOffset(0, 62), TextXAlignment = Enum.TextXAlignment.Center })
	ui = {
		Root = root,
		Edges = edges,
		Health = health,
		HpText = hpText,
		SetBar = setBar,
		BarFill = barFill,
		BarBg = barBg,
		Protect = protect,
		Dirs = dirs,
		Feed = feedFrame,
		Banner = banner,
		BTitle = bTitle,
		BName = bName,
		Death = deathFrame,
		DTitle = dTitle,
		DName = dName,
		DInfo = dInfo,
		BannerUntil = 0,
	}
end

-------------------------------------------------------------------------------
-- События
-------------------------------------------------------------------------------
local function addIndicator(from)
	if typeof(from) ~= "Vector3" then
		return
	end
	local f = Kit.Frame(ui.Dirs, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(6, 46),
		BackgroundColor3 = C.Danger,
		BackgroundTransparency = 0.1,
	})
	Kit.Corner(f, 3)
	table.insert(indicators, { Frame = f, From = from, Born = os.clock() })
	while #indicators > 6 do
		table.remove(indicators, 1).Frame:Destroy()
	end
end

local function onDamaged(info)
	if type(info) ~= "table" or not ui then
		return
	end
	hurt = math.min(1, hurt + (tonumber(info.Amount) or 10) / 45)
	addIndicator(info.From)
end

local function feedRow(info)
	local me = Players.LocalPlayer.UserId
	local mine = info.KillerId == me or info.VictimId == me
	local row = Kit.Frame(ui.Feed, {
		Size = UDim2.fromOffset(0, 26),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = mine and C.AccentDark or C.Bg,
		BackgroundTransparency = mine and 0.25 or 0.45,
	})
	Kit.Corner(row, 4)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 10), UDim.new(0, 10)
	pad.Parent = row
	Kit.List(row, 8, true).VerticalAlignment = Enum.VerticalAlignment.Center
	local function text(t, color, font, order)
		local l = Kit.Label(row, t, 15, font or F.Bold, color, { AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 26), LayoutOrder = order })
		return l
	end
	if info.Killer and info.Killer ~= "" then
		text(info.Killer, info.KillerId == me and C.Accent or C.Text, F.Bold, 1)
	end
	text("[" .. tostring(info.Weapon or "") .. "]", C.Dim, F.Medium, 2)
	if info.Headshot then
		text("HS", C.Danger, F.Bold, 3)
	end
	text(info.Victim or "?", info.VictimId == me and C.Accent or C.Text, F.Bold, 4)
	table.insert(feed, { Frame = row, Born = os.clock() })
	while #feed > MAX_FEED do
		table.remove(feed, 1).Frame:Destroy()
	end
	for i, item in ipairs(feed) do
		item.Frame.LayoutOrder = -i
	end
end

local function onEliminated(info)
	if type(info) ~= "table" or not ui then
		return
	end
	if info.Role == "Killer" or info.Role == "Assist" then
		ui.BTitle.Text = info.Role == "Assist" and "ASSIST" or (info.Headshot and "HEADSHOT · ELIMINATED" or "ELIMINATED")
		ui.BTitle.TextColor3 = info.Role == "Assist" and C.Accent or C.Danger
		ui.BName.Text = tostring(info.Name or "")
		ui.Banner.Visible = true
		ui.BannerUntil = os.clock() + 2.2
		if info.Role == "Killer" then
			Kit.PlaySound("Kill", 0.6)
		else
			Kit.PlaySound("Xp", 0.5)
		end
	elseif info.Role == "Victim" then
		death = { Until = os.clock() + (tonumber(info.Respawn) or 4) }
		ui.DTitle.Text = (info.Name and info.Name ~= "") and "ELIMINATED BY" or "ELIMINATED"
		ui.DName.Text = tostring(info.Name or "")
		local extra = tostring(info.Weapon or "")
		if info.Headshot then
			extra = extra .. "  ·  HEADSHOT"
		end
		death.Base = extra
		ui.DInfo.Text = extra
		ui.Death.Visible = true
		Kit.PlaySound("Death", 0.55)
	end
end

-------------------------------------------------------------------------------
local function update(dt)
	if not ui then
		return
	end
	local character, humanoid = characters.GetCharacter()
	local alive = humanoid ~= nil and humanoid.Health > 0
	local inMatch = character ~= nil and (character:GetAttribute("Weapon") or "") ~= ""
	-- здоровье
	ui.Health.Visible = alive and inMatch
	if alive then
		local hp = math.max(0, humanoid.Health)
		ui.HpText.Text = tostring(math.ceil(hp))
		local k = hp / math.max(humanoid.MaxHealth, 1)
		ui.SetBar(k)
		local low = k < 0.35
		ui.BarFill.BackgroundColor3 = low and C.Danger or C.Text
		ui.HpText.TextColor3 = low and C.Danger or C.Text
		local protectedUntil = character:GetAttribute("ProtectedUntil")
		ui.Protect.Visible = type(protectedUntil) == "number" and workspace:GetServerTimeNow() < protectedUntil
		-- края экрана: от урона и от малого здоровья
		hurt = math.max(0, hurt - dt * 1.4)
		local base = math.clamp((0.35 - k) / 0.35, 0, 1) * (0.55 + 0.15 * math.sin(os.clock() * 5))
		local amount = math.clamp(math.max(hurt, base), 0, 1)
		for _, e in ipairs(ui.Edges) do
			e[1].BackgroundTransparency = 1 - amount * 0.75
		end
	else
		for _, e in ipairs(ui.Edges) do
			e[1].BackgroundTransparency = 1
		end
	end
	-- указатели урона
	local camera = workspace.CurrentCamera
	local look = camera.CFrame.LookVector
	local camYaw = math.atan2(-look.X, -look.Z)
	for i = #indicators, 1, -1 do
		local ind = indicators[i]
		local age = os.clock() - ind.Born
		if age > 1.6 or not alive then
			ind.Frame:Destroy()
			table.remove(indicators, i)
		else
			local d = ind.From - camera.CFrame.Position
			local yaw = math.atan2(-d.X, -d.Z)
			local rel = yaw - camYaw -- влево положительно
			local r = 118
			ind.Frame.Position = UDim2.fromOffset(-math.sin(rel) * r, -math.cos(rel) * r)
			ind.Frame.Rotation = math.deg(-rel)
			ind.Frame.BackgroundTransparency = 0.1 + 0.9 * (age / 1.6) ^ 2
		end
	end
	-- лента убийств: строки исчезают через 7 с
	for i = #feed, 1, -1 do
		local item = feed[i]
		local age = os.clock() - item.Born
		if age > 7 then
			item.Frame:Destroy()
			table.remove(feed, i)
		end
	end
	-- «ликвидирован»
	if ui.Banner.Visible and os.clock() > ui.BannerUntil then
		ui.Banner.Visible = false
	end
	-- экран гибели
	if death then
		local left = math.max(0, math.ceil(death.Until - os.clock()))
		local base = death.Base ~= "" and (death.Base .. "  ·  ") or ""
		ui.DInfo.Text = base .. (left > 0 and string.format("RESPAWN %d", left) or "RESPAWNING")
	end
end

function CombatHUD.Init(context)
	net = context.Get("ClientNet")
	characters = context.Get("CharacterController")
	weapons = context.Get("WeaponController")
end

function CombatHUD.Start()
	task.spawn(function()
		build()
		if not ui then
			return
		end
		net.On("Damaged", onDamaged)
		net.On("KillFeed", function(info)
			if type(info) == "table" then
				feedRow(info)
			end
		end)
		net.On("Eliminated", onEliminated)
		weapons.HitConfirmed:Connect(function(info)
			if info.Kill then
				return -- звук убийства — в Eliminated
			end
			Kit.PlaySound(info.Headshot and "HitHead" or "Hit", info.Headshot and 0.55 or 0.45)
		end)
		characters.CharacterChanged:Connect(function()
			death = nil
			ui.Death.Visible = false
			hurt = 0
		end)
		RunService.RenderStepped:Connect(update)
		UserInputService.LastInputTypeChanged:Connect(function()
			local touch = UserInputService:GetLastInputType() == Enum.UserInputType.Touch
			ui.Health.Position = touch and UDim2.new(0, 24, 0, 58) or UDim2.new(0, 28, 1, -24)
			ui.Health.AnchorPoint = touch and Vector2.new(0, 0) or Vector2.new(0, 1)
		end)
	end)
end

return CombatHUD
