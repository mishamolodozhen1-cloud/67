-- MatchHUD: интерфейс матча (этапы 7, 9, 11).
--   • сверху по центру — время и счёт: FFA/CHAOS — свои очки и лидер, TDM — красные | синие,
--     GUN GAME — уровень оружия; ниже — режим и карта;
--   • отсчёт перед боем (крупные цифры, звук) и «FIGHT»;
--   • таблица участников — держать Tab (на телефоне — кнопка с тремя полосками сверху справа);
--   • итоги: победитель, таблица, награды (опыт, монеты, новый уровень), обратный отсчёт до лобби;
--   • награды за убийства — «+130 XP» над полосой здоровья; новый уровень — плашка;
--   • CHAOS: метка удара на земле (красный круг сжимается, пищит) и взрыв;
--   • GUN GAME: «NEW WEAPON …» при переходе на следующее оружие.
local ContextActionService = game:GetService("ContextActionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Configs = ReplicatedStorage:WaitForChild("Configs")
local MatchConfig = require(Configs:WaitForChild("MatchConfig"))
local WeaponConfig = require(Configs:WaitForChild("WeaponConfig"))
local Kit = require(script.Parent.Parent:WaitForChild("Ui"):WaitForChild("Kit"))

local MatchHUD = { Name = "MatchHUD" }

local C, F = Kit.Colors, Kit.Fonts
local net, profileCtl = nil, nil
local ui = nil
local match = nil
local countdown = nil
local results = nil
local scoreOpen = false
local toasts = {}

local function fmtTime(s)
	s = math.max(0, math.floor(s))
	return string.format("%d:%02d", math.floor(s / 60), s % 60)
end

local function me()
	return Players.LocalPlayer
end

local function participants()
	local list = {}
	local folder = match and match:FindFirstChild("Participants")
	if not folder then
		return list
	end
	for _, c in ipairs(folder:GetChildren()) do
		if c:GetAttribute("InMatch") then
			table.insert(list, {
				Name = c:GetAttribute("Name") or "?",
				UserId = c:GetAttribute("UserId") or 0,
				IsBot = c:GetAttribute("IsBot") == true,
				Team = c:GetAttribute("Team") or "",
				Kills = c:GetAttribute("Kills") or 0,
				Deaths = c:GetAttribute("Deaths") or 0,
				Assists = c:GetAttribute("Assists") or 0,
				Score = c:GetAttribute("Score") or 0,
				GunLevel = c:GetAttribute("GunLevel") or 1,
			})
		end
	end
	table.sort(list, function(a, b)
		if a.Score ~= b.Score then
			return a.Score > b.Score
		end
		return a.Kills > b.Kills
	end)
	return list
end

-------------------------------------------------------------------------------
-- Построение
-------------------------------------------------------------------------------
local function build()
	local hud = me():WaitForChild("PlayerGui"):WaitForChild("HUD", 10)
	if not hud then
		return
	end
	local root = Instance.new("Frame")
	root.Name = "Match"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.Parent = hud
	-- верх: время и счёт
	local top = Instance.new("Frame")
	top.Name = "Top"
	top.BackgroundTransparency = 1
	top.AnchorPoint = Vector2.new(0.5, 0)
	top.Position = UDim2.new(0.5, 0, 0, 10)
	top.Size = UDim2.fromOffset(420, 70)
	top.Parent = root
	local timer = Kit.Label(top, "0:00", 26, F.Bold, C.Text, { Size = UDim2.new(1, 0, 0, 30), TextXAlignment = Enum.TextXAlignment.Center })
	Kit.Outline(timer)
	local score = Kit.Label(top, "", 16, F.Bold, C.Text, { Size = UDim2.new(1, 0, 0, 20), Position = UDim2.fromOffset(0, 30), TextXAlignment = Enum.TextXAlignment.Center, RichText = true })
	Kit.Outline(score)
	local sub = Kit.Label(top, "", 12, F.Medium, C.Dim, { Size = UDim2.new(1, 0, 0, 16), Position = UDim2.fromOffset(0, 51), TextXAlignment = Enum.TextXAlignment.Center })
	Kit.Outline(sub, 0.6)
	-- отсчёт
	local count = Kit.Label(root, "", 96, F.Title, C.Text, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.4), Size = UDim2.fromOffset(600, 110), TextXAlignment = Enum.TextXAlignment.Center, Visible = false })
	Kit.Outline(count, 0.3)
	local countSub = Kit.Label(root, "", 18, F.Bold, C.Accent, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.4, 70), Size = UDim2.fromOffset(600, 24), TextXAlignment = Enum.TextXAlignment.Center, Visible = false })
	Kit.Outline(countSub, 0.4)
	-- таблица
	local board = Kit.Frame(root, {
		Name = "Scoreboard",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(640, 440),
		BackgroundColor3 = C.Bg,
		BackgroundTransparency = 0.12,
		Visible = false,
	})
	Kit.Corner(board, 10)
	Kit.Padding(board, 16)
	local boardTitle = Kit.Label(board, "", 18, F.Bold, C.Text, { Size = UDim2.new(1, 0, 0, 24) })
	local rows = Instance.new("Frame")
	rows.BackgroundTransparency = 1
	rows.Position = UDim2.fromOffset(0, 34)
	rows.Size = UDim2.new(1, 0, 1, -34)
	rows.Parent = board
	Kit.List(rows, 3)
	-- итоги
	local res = Kit.Frame(root, {
		Name = "Results",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(700, 500),
		BackgroundColor3 = C.Bg,
		BackgroundTransparency = 0.06,
		Visible = false,
	})
	Kit.Corner(res, 12)
	Kit.Padding(res, 20)
	local resTitle = Kit.Label(res, "", 44, F.Title, C.Text, { Size = UDim2.new(1, 0, 0, 50), TextXAlignment = Enum.TextXAlignment.Center })
	local resSub = Kit.Label(res, "", 16, F.Medium, C.Dim, { Size = UDim2.new(1, 0, 0, 20), Position = UDim2.fromOffset(0, 52), TextXAlignment = Enum.TextXAlignment.Center })
	local resRows = Instance.new("Frame")
	resRows.BackgroundTransparency = 1
	resRows.Position = UDim2.fromOffset(0, 86)
	resRows.Size = UDim2.new(0.58, -10, 1, -120)
	resRows.Parent = res
	Kit.List(resRows, 3)
	local rewards = Kit.Frame(res, { Position = UDim2.new(0.58, 10, 0, 86), Size = UDim2.new(0.42, -10, 1, -120), BackgroundColor3 = C.Panel2, BackgroundTransparency = 0.2 })
	Kit.Corner(rewards, 8)
	Kit.Padding(rewards, 14)
	local rewardsList = Instance.new("Frame")
	rewardsList.BackgroundTransparency = 1
	rewardsList.Size = UDim2.fromScale(1, 1)
	rewardsList.Parent = rewards
	Kit.List(rewardsList, 6)
	local resFoot = Kit.Label(res, "", 14, F.Medium, C.Dim, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 20), TextXAlignment = Enum.TextXAlignment.Center })
	-- уведомления (опыт, уровень, оружие)
	local toastFrame = Instance.new("Frame")
	toastFrame.BackgroundTransparency = 1
	toastFrame.AnchorPoint = Vector2.new(0.5, 1)
	toastFrame.Position = UDim2.new(0.5, 0, 1, -210)
	toastFrame.Size = UDim2.fromOffset(400, 120)
	toastFrame.Parent = root
	local tl = Kit.List(toastFrame, 4, false, Enum.HorizontalAlignment.Center)
	tl.VerticalAlignment = Enum.VerticalAlignment.Bottom
	-- кнопка таблицы на телефоне
	local boardButton = Kit.Button(root, "≡", "Secondary", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 14),
		Size = UDim2.fromOffset(44, 36),
		TextSize = 22,
		Visible = false,
	})
	boardButton.Activated:Connect(function()
		scoreOpen = not scoreOpen
	end)
	local scale = Instance.new("UIScale")
	scale.Parent = root
	ui = {
		Root = root,
		Top = top,
		Timer = timer,
		Score = score,
		Sub = sub,
		Count = count,
		CountSub = countSub,
		Board = board,
		BoardTitle = boardTitle,
		Rows = rows,
		Res = res,
		ResTitle = resTitle,
		ResSub = resSub,
		ResRows = resRows,
		RewardsList = rewardsList,
		ResFoot = resFoot,
		Toasts = toastFrame,
		BoardButton = boardButton,
		Scale = scale,
	}
end

local function row(parent, cells, color, bg, bold)
	local r = Kit.Frame(parent, { Size = UDim2.new(1, 0, 0, 26), BackgroundColor3 = bg or C.Panel2, BackgroundTransparency = bg and 0.2 or 0.55 })
	Kit.Corner(r, 4)
	for _, c in ipairs(cells) do
		local l = Kit.Label(r, tostring(c[1]), 15, bold and F.Bold or F.Medium, c[3] or color or C.Text, {
			Position = UDim2.new(c[2], c.X or 8, 0, 0),
			Size = UDim2.new(c.W or 0.12, 0, 1, 0),
			TextXAlignment = c.Align or Enum.TextXAlignment.Left,
		})
		l.TextTruncate = Enum.TextTruncate.AtEnd
	end
	return r
end

local function teamColor(team)
	local t = MatchConfig.Teams[team]
	return t and t.Color or C.Text
end

local function fillBoard()
	for _, c in ipairs(ui.Rows:GetChildren()) do
		if c:IsA("Frame") then
			c:Destroy()
		end
	end
	local list = participants()
	ui.BoardTitle.Text = string.format("%s  ·  %s", match:GetAttribute("ModeName") or "", match:GetAttribute("MapName") or "")
	row(ui.Rows, { { "PLAYER", 0, C.Dim, W = 0.5 }, { "K", 0.55, C.Dim }, { "D", 0.67, C.Dim }, { "A", 0.79, C.Dim }, { "SCORE", 0.88, C.Dim } }, C.Dim, C.Bg, true)
	local myId = me().UserId
	for i, p in ipairs(list) do
		local name = (p.IsBot and "" or "") .. p.Name
		local color = p.Team ~= "" and teamColor(p.Team) or C.Text
		local bg = p.UserId == myId and C.AccentDark or nil
		row(ui.Rows, {
			{ i .. ".  " .. name, 0, color, W = 0.5 },
			{ p.Kills, 0.55 },
			{ p.Deaths, 0.67 },
			{ p.Assists, 0.79 },
			{ p.Score, 0.88 },
		}, C.Text, bg)
	end
end

-------------------------------------------------------------------------------
-- Уведомления
-------------------------------------------------------------------------------
local function toast(text, color, size, life)
	if not ui then
		return
	end
	local l = Kit.Label(ui.Toasts, text, size or 18, F.Bold, color or C.Text, { Size = UDim2.new(1, 0, 0, (size or 18) + 6), TextXAlignment = Enum.TextXAlignment.Center })
	Kit.Outline(l)
	table.insert(toasts, { Label = l, Until = os.clock() + (life or 2.2) })
	while #toasts > 4 do
		table.remove(toasts, 1).Label:Destroy()
	end
end
MatchHUD.Toast = toast

-------------------------------------------------------------------------------
-- События
-------------------------------------------------------------------------------
local function strikeMarker(pos, radius, delay)
	local disk = Instance.new("Part")
	disk.Name = "StrikeMarker"
	disk.Shape = Enum.PartType.Cylinder
	disk.Anchored = true
	disk.CanCollide = false
	disk.CanQuery = false
	disk.CanTouch = false
	disk.CastShadow = false
	disk.Material = Enum.Material.SmoothPlastic
	disk.Color = Color3.fromRGB(230, 60, 46)
	disk.Transparency = 0.55
	disk.Size = Vector3.new(0.15, radius * 2, radius * 2)
	disk.CFrame = CFrame.new(pos + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	disk.Parent = workspace:FindFirstChild("Effects") or workspace
	local ring = disk:Clone()
	ring.Transparency = 0.2
	ring.Size = Vector3.new(0.2, radius * 2, radius * 2)
	ring.Parent = disk.Parent
	local t0 = os.clock()
	local beeps = 0
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local k = math.clamp((os.clock() - t0) / delay, 0, 1)
		ring.Size = Vector3.new(0.2, radius * 2 * (1 - k) + 0.5, radius * 2 * (1 - k) + 0.5)
		local want = math.floor(k * 6)
		if want > beeps then
			beeps = want
			local s = Kit.PlaySound("Warning", 0.35)
			if s then
				s.PlaybackSpeed = 1 + k * 0.4
			end
		end
		if k >= 1 then
			conn:Disconnect()
			disk:Destroy()
			ring:Destroy()
			local boom = Instance.new("Explosion")
			boom.Position = pos + Vector3.new(0, 1, 0)
			boom.BlastRadius = radius
			boom.BlastPressure = 0
			boom.DestroyJointRadiusPercent = 0
			boom.ExplosionType = Enum.ExplosionType.NoCraters
			boom.Parent = workspace
			local dist = (workspace.CurrentCamera.CFrame.Position - pos).Magnitude
			local s = Kit.PlaySound("Explosion", math.clamp(1.2 - dist / 220, 0.15, 1))
			Debris:AddItem(boom, 2)
			if s then
				s.PlaybackSpeed = 0.95 + math.random() * 0.1
			end
		end
	end)
end

local function showResults(r)
	results = { Data = r, Until = os.clock() + MatchConfig.Results }
	local myId = me().UserId
	local myRow = nil
	for _, p in ipairs(r.Players or {}) do
		if p.UserId == myId then
			myRow = p
		end
	end
	local title, color = "MATCH OVER", C.Text
	if r.WinnerTeam then
		if myRow and myRow.Team == r.WinnerTeam then
			title, color = "VICTORY", C.Accent
		elseif myRow then
			title, color = "DEFEAT", C.Danger
		else
			title = (MatchConfig.Teams[r.WinnerTeam] and MatchConfig.Teams[r.WinnerTeam].DisplayName or r.WinnerTeam) .. " WINS"
		end
	elseif r.Winner then
		if r.WinnerUserId == myId then
			title, color = "VICTORY", C.Accent
		else
			title = string.upper(tostring(r.Winner)) .. " WINS"
		end
	end
	ui.ResTitle.Text = title
	ui.ResTitle.TextColor3 = color
	local sub = string.format("%s  ·  %s", r.ModeName or "", r.MapName or "")
	if r.WinnerTeam or (r.RedScore or 0) + (r.BlueScore or 0) > 0 then
		sub = sub .. string.format("  ·  RED %d — %d BLUE", r.RedScore or 0, r.BlueScore or 0)
	end
	ui.ResSub.Text = sub
	for _, c in ipairs(ui.ResRows:GetChildren()) do
		if c:IsA("Frame") then
			c:Destroy()
		end
	end
	row(ui.ResRows, { { "PLAYER", 0, C.Dim, W = 0.55 }, { "K", 0.6, C.Dim }, { "D", 0.72, C.Dim }, { "SCORE", 0.84, C.Dim } }, C.Dim, C.Bg, true)
	for i, p in ipairs(r.Players or {}) do
		if i > 10 then
			break
		end
		row(ui.ResRows, {
			{ i .. ".  " .. p.Name, 0, p.Team ~= "" and teamColor(p.Team) or C.Text, W = 0.55 },
			{ p.Kills, 0.6 },
			{ p.Deaths, 0.72 },
			{ p.Score, 0.84 },
		}, C.Text, p.UserId == myId and C.AccentDark or nil)
	end
	for _, c in ipairs(ui.RewardsList:GetChildren()) do
		if c:IsA("TextLabel") then
			c:Destroy()
		end
	end
	Kit.Label(ui.RewardsList, "REWARDS", 14, F.Bold, C.Dim, { Size = UDim2.new(1, 0, 0, 18), LayoutOrder = 0 })
	ui.Res.Visible = true
	Kit.PlaySound(title == "VICTORY" and "Victory" or (title == "DEFEAT" and "Defeat" or "MatchStart"), 0.6)
end

local function showRewards(rw)
	if not ui then
		return
	end
	for i, line in ipairs(rw.Lines or {}) do
		Kit.Label(ui.RewardsList, string.format("%s   +%d XP   +%d COINS", line.Text, line.Xp, line.Coins), 15, F.Medium, C.Text, { Size = UDim2.new(1, 0, 0, 20), LayoutOrder = i })
	end
	Kit.Label(ui.RewardsList, string.format("TOTAL   +%d XP   +%d COINS", rw.Xp or 0, rw.Coins or 0), 17, F.Bold, C.Accent, { Size = UDim2.new(1, 0, 0, 24), LayoutOrder = 50 })
	for _, lvl in ipairs(rw.LevelUps or {}) do
		Kit.Label(ui.RewardsList, "LEVEL UP!  " .. tostring(lvl), 20, F.Title, C.Good, { Size = UDim2.new(1, 0, 0, 28), LayoutOrder = 60 + lvl })
	end
	if #(rw.LevelUps or {}) > 0 then
		task.delay(0.6, function()
			Kit.PlaySound("LevelUp", 0.6)
		end)
	end
end

local function onEvent(e)
	if type(e) ~= "table" or not ui then
		return
	end
	if e.Type == "Countdown" then
		countdown = { Until = os.clock() + (e.Seconds or 5), Last = nil, Sub = string.format("%s  ·  %s", e.MapName or "", e.ModeName or "") }
		ui.Res.Visible = false
		results = nil
	elseif e.Type == "Start" then
		countdown = { Until = os.clock(), Fight = os.clock() + 1.2, Sub = "" }
		Kit.PlaySound("CountGo", 0.6)
	elseif e.Type == "End" and type(e.Results) == "table" then
		if me():GetAttribute("InMatch") then
			showResults(e.Results)
		end
	elseif e.Type == "Strike" and typeof(e.Position) == "Vector3" then
		strikeMarker(e.Position, e.Radius or 18, e.Delay or 2)
	elseif e.Type == "GunLevel" then
		local def = WeaponConfig.Weapons[e.Weapon]
		toast("NEW WEAPON  ·  " .. (def and def.DisplayName or tostring(e.Weapon)), C.Accent, 22, 2.5)
		Kit.PlaySound("LevelUp", 0.4, 1.2)
	end
end

-------------------------------------------------------------------------------
local function update()
	if not ui or not match then
		return
	end
	local vp = workspace.CurrentCamera.ViewportSize
	ui.Scale.Scale = math.clamp(math.min(vp.X / 1280, vp.Y / 720), 0.62, 1.15)
	local inMatch = me():GetAttribute("InMatch") == true
	local phase = match:GetAttribute("Phase")
	local active = inMatch and (phase == "Starting" or phase == "Running" or phase == "Results")
	ui.Top.Visible = active and phase ~= "Results"
	local touch = UserInputService.TouchEnabled and UserInputService:GetLastInputType() == Enum.UserInputType.Touch
	ui.BoardButton.Visible = active and touch
	if active then
		local left = (match:GetAttribute("EndsAt") or 0) - workspace:GetServerTimeNow()
		ui.Timer.Text = phase == "Starting" and "GET READY" or fmtTime(left)
		ui.Timer.TextColor3 = (phase == "Running" and left < 30) and C.Danger or C.Text
		local mode = match:GetAttribute("Mode")
		ui.Sub.Text = string.format("%s  ·  %s", match:GetAttribute("ModeName") or "", match:GetAttribute("MapName") or "")
		local list = participants()
		local myId = me().UserId
		local mine = nil
		for _, p in ipairs(list) do
			if p.UserId == myId then
				mine = p
			end
		end
		if match:GetAttribute("Teams") then
			local red, blue = match:GetAttribute("RedScore") or 0, match:GetAttribute("BlueScore") or 0
			ui.Score.Text = string.format('<font color="#D64E40">RED %d</font>   <font color="#9A9A96">/ %d /</font>   <font color="#4684DC">%d BLUE</font>', red, match:GetAttribute("ScoreLimit") or 0, blue)
		elseif mode == "GunGame" then
			local weapons = string.split(match:GetAttribute("GunWeapons") or "", ",")
			local lvl = mine and mine.GunLevel or 1
			local w = WeaponConfig.Weapons[weapons[lvl] or ""]
			ui.Score.Text = string.format("WEAPON %d / %d  ·  %s", lvl, #weapons, w and w.DisplayName or "")
		else
			local leaderRow = list[1]
			local myScore = mine and mine.Score or 0
			local lead = leaderRow and leaderRow.Score or 0
			ui.Score.Text = string.format("YOU %d   ·   LEADER %d   ·   TO WIN %d", myScore, lead, match:GetAttribute("ScoreLimit") or 0)
		end
	end
	-- отсчёт
	if countdown then
		local left = countdown.Until - os.clock()
		if left > 0 then
			local n = math.ceil(left)
			ui.Count.Visible = true
			ui.Count.Text = tostring(n)
			ui.CountSub.Visible = true
			ui.CountSub.Text = countdown.Sub
			if countdown.Last ~= n then
				countdown.Last = n
				Kit.PlaySound("Count", 0.5)
			end
		elseif countdown.Fight and os.clock() < countdown.Fight then
			ui.Count.Visible = true
			ui.Count.Text = "FIGHT"
			ui.CountSub.Visible = false
		else
			ui.Count.Visible = false
			ui.CountSub.Visible = false
			if not countdown.Fight or os.clock() >= countdown.Fight then
				countdown = nil
			end
		end
	end
	-- таблица
	local tab = scoreOpen or UserInputService:IsKeyDown(Enum.KeyCode.Tab)
	ui.Board.Visible = active and tab and phase ~= "Results"
	if ui.Board.Visible then
		fillBoard()
	end
	-- итоги
	if results then
		local left = results.Until - os.clock()
		ui.ResFoot.Text = left > 0 and string.format("BACK TO LOBBY IN %d", math.ceil(left)) or ""
		if left <= -1 or not inMatch then
			ui.Res.Visible = false
			results = nil
		end
	end
	-- уведомления
	for i = #toasts, 1, -1 do
		if os.clock() > toasts[i].Until then
			toasts[i].Label:Destroy()
			table.remove(toasts, i)
		end
	end
end

function MatchHUD.Init(context)
	net = context.Get("ClientNet")
	profileCtl = context.Get("ProfileController")
end

function MatchHUD.Start()
	task.spawn(function()
		match = ReplicatedStorage:WaitForChild("Match", 30)
		build()
		if not ui then
			return
		end
		net.On("MatchEvent", onEvent)
		profileCtl.Reward:Connect(function(r)
			toast(string.format("+%d XP   +%d COINS", r.Xp or 0, r.Coins or 0), r.Reason == "Assist" and C.Accent or C.Text, 16, 1.8)
			for _, lvl in ipairs(r.LevelUps or {}) do
				toast("LEVEL UP  ·  " .. tostring(lvl), C.Good, 24, 3)
				Kit.PlaySound("LevelUp", 0.6)
			end
		end)
		profileCtl.MatchRewards:Connect(showRewards)
		-- геймпад: кнопка Select — таблица (вкл/выкл)
		ContextActionService:BindAction("DC_Scoreboard", function(_, state)
			if state == Enum.UserInputState.Begin then
				scoreOpen = not scoreOpen
			end
			return Enum.ContextActionResult.Sink
		end, false, Enum.KeyCode.ButtonSelect)
		RunService.RenderStepped:Connect(update)
	end)
end

return MatchHUD
