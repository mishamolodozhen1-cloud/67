-- Pos: экран кассы. Появляется, когда вы встаёте за кассу (в зону кассира).
--   • список товаров покупателя: пробитые отмечены зелёным, итог сверху;
--   • большая кнопка «Пробить товар» (ПК — Q): товар проезжает над сканером и уходит в зону упаковки;
--   • оплата: картой — «Принять оплату картой» (Q); наличными — покупатель дал купюру,
--     выберите правильную сдачу из трёх вариантов (ПК — 1, 2, 3). Ошибка — покупатель возмутится.
-- Состояние кассы приходит с сервера (ReplicatedStorage.Lanes.LaneN), действия — Action("Pos", …).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local ContextActionService = game:GetService("ContextActionService")

local Pos = {}

local ctx, UI
local holder, group, title, totalLabel, list, status, actionRow, mainButton, optionButtons, stroke
local current = nil -- папка кассы, за которой стоит игрок
local shown = false
local rows = {}
local lastVersion = -1
local lastError = 0
local stage = "Idle"

local function tween(obj, t, props, style)
	TweenService:Create(obj, TweenInfo.new(t, style or Enum.EasingStyle.Quint, Enum.EasingDirection.Out), props):Play()
end

local function send(op, arg)
	if current then
		ctx.Remotes.Action:FireServer("Pos", current:GetAttribute("Index"), op, arg)
	end
end

local function decode(s)
	local ok, v = pcall(function()
		return HttpService:JSONDecode(s or "[]")
	end)
	return ok and type(v) == "table" and v or {}
end

local function keyHint(k)
	return UI.IsTouch and "" or ("  [" .. k .. "]")
end

-------------------------------------------------------------------------------
-- Отрисовка состояния
-------------------------------------------------------------------------------
local function setRow(i, item)
	local r = rows[i]
	if not r then
		local f = UI.new("Frame", { Size = UDim2.new(1, -6, 0, 24), BackgroundTransparency = 1, LayoutOrder = i }, list)
		local dot = UI.dot(f, 10, UI.Colors.Muted, false)
		dot.AnchorPoint = Vector2.new(0, 0.5)
		dot.Position = UDim2.new(0, 2, 0.5, 0)
		local name = UI.text("", { Position = UDim2.fromOffset(20, 0), Size = UDim2.new(1, -100, 1, 0), TextSize = 14, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd }, f)
		local price = UI.text("", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(80, 24), TextSize = 14, Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Right }, f)
		r = { Frame = f, Dot = dot, Name = name, Price = price, Scanned = nil }
		rows[i] = r
	end
	r.Frame.Visible = true
	r.Name.Text = item.N or "?"
	r.Price.Text = tostring(item.P or 0) .. " руб."
	local scanned = item.S == true
	if r.Scanned ~= scanned then
		UI.setDot(r.Dot, scanned and UI.Colors.Good or UI.Colors.Muted, scanned)
		r.Name.TextColor3 = scanned and UI.Colors.Text or UI.Colors.Muted
		r.Price.TextColor3 = scanned and UI.Colors.Good or UI.Colors.Muted
		if scanned and r.Scanned == false then
			-- только что пробили: строка вспыхивает
			r.Frame.BackgroundColor3 = UI.Colors.Good
			r.Frame.BackgroundTransparency = 0.6
			tween(r.Frame, 0.6, { BackgroundTransparency = 1 })
			list.CanvasPosition = Vector2.new(0, math.max(0, (i - 3) * 26))
		end
		r.Scanned = scanned
	end
end

local function refresh()
	if not current then
		return
	end
	local f = current
	stage = f:GetAttribute("Stage") or "Idle"
	local items = decode(f:GetAttribute("Items"))
	title.Text = "КАССА " .. tostring(f:GetAttribute("Index") or "")
	local scannedCount, sum = 0, 0
	for i, item in ipairs(items) do
		setRow(i, item)
		sum = sum + (item.P or 0)
		if item.S then
			scannedCount = scannedCount + 1
		end
	end
	for i = #items + 1, #rows do
		rows[i].Frame.Visible = false
		rows[i].Scanned = nil
	end
	totalLabel.Text = "ИТОГО " .. tostring(f:GetAttribute("Total") or 0) .. " руб."
	list.Visible = #items > 0
	local method = f:GetAttribute("Method")
	for _, b in ipairs(optionButtons) do
		b.Visible = false
	end
	mainButton.Visible = true
	if f:GetAttribute("Closed") then
		status.Text = "Касса закрыта"
		mainButton.Visible = false
	elseif stage == "Idle" then
		status.Text = "Ждите покупателя. Он сам подойдёт к кассе."
		mainButton.Visible = false
	elseif stage == "Scanning" then
		status.Text = string.format("Пробито %d из %d · к оплате будет %d руб.", scannedCount, #items, sum)
		mainButton.Text = "ПРОБИТЬ ТОВАР" .. keyHint("Q")
		mainButton.BackgroundColor3 = UI.Colors.Accent
	elseif stage == "Payment" then
		if method == "Cash" then
			local given = f:GetAttribute("Given") or 0
			status.Text = string.format("Наличные: дали %d руб., к оплате %d. Какая сдача?", given, f:GetAttribute("Total") or 0)
			mainButton.Visible = false
			local options = decode(f:GetAttribute("Options"))
			for i, b in ipairs(optionButtons) do
				local v = options[i]
				b.Visible = v ~= nil
				if v then
					b.Text = tostring(v) .. " руб." .. keyHint(tostring(i))
					b:SetAttribute("Value", v)
				end
			end
		else
			status.Text = "Покупатель платит картой."
			mainButton.Text = "ПРИНЯТЬ ОПЛАТУ КАРТОЙ" .. keyHint("Q")
			mainButton.BackgroundColor3 = Color3.fromRGB(46, 120, 230)
		end
	elseif stage == "Paid" then
		status.Text = "Оплачено. Спасибо за покупку!"
		mainButton.Visible = false
	end
	-- ошибка (штрихкод не считался, неверная сдача): рамка мигает красным, панель вздрагивает
	local err = f:GetAttribute("ScanError") or 0
	if err ~= lastError then
		if lastError ~= 0 then
			stroke.Color = UI.Colors.Warn
			stroke.Transparency = 0
			tween(stroke, 0.8, { Transparency = 0.85 })
			task.spawn(function()
				local base = holder.Position
				for _, dx in ipairs({ 8, -6, 4, -2, 0 }) do
					holder.Position = base + UDim2.fromOffset(dx, 0)
					task.wait(0.03)
				end
				holder.Position = base
			end)
		end
		lastError = err
	end
end

-------------------------------------------------------------------------------
-- Показ и скрытие
-------------------------------------------------------------------------------
local function setShown(on)
	if shown == on then
		return
	end
	shown = on
	if ctx.HUD and ctx.HUD.SetTasksHidden then
		ctx.HUD.SetTasksHidden(on)
	end
	if on then
		holder.Visible = true
		group.Position = UDim2.fromOffset(40, 0)
		group.GroupTransparency = 1
		tween(group, 0.35, { Position = UDim2.fromOffset(0, 0), GroupTransparency = 0 })
		ctx.Audio.Play("UiOpen", nil, 0.3)
	else
		tween(group, 0.25, { Position = UDim2.fromOffset(40, 0), GroupTransparency = 1 })
		task.delay(0.26, function()
			if not shown then
				holder.Visible = false
			end
		end)
	end
end

local function findLane()
	local ch = ctx.Player.Character
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	local folder = ReplicatedStorage:FindFirstChild("Lanes")
	if not (root and folder) then
		return nil
	end
	local p = root.Position
	for _, f in ipairs(folder:GetChildren()) do
		local x0, x1, z0, z1 = f:GetAttribute("X0"), f:GetAttribute("X1"), f:GetAttribute("Z0"), f:GetAttribute("Z1")
		if x0 and p.X >= x0 - 0.5 and p.X <= x1 + 0.5 and p.Z >= z0 - 0.5 and p.Z <= z1 + 0.5 then
			return f
		end
	end
	return nil
end

-------------------------------------------------------------------------------
local function build()
	local gui = UI.new("ScreenGui", { Name = "NightPos", ResetOnSpawn = false, IgnoreGuiInset = false, DisplayOrder = 7 }, ctx.Player:WaitForChild("PlayerGui"))
	Pos.Gui = gui
	holder = UI.new("Frame", {
		Name = "Pos",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 10),
		Size = UDim2.fromOffset(330, 262),
		BackgroundTransparency = 1,
		Visible = false,
	}, gui)
	UI.scaled(holder)
	group = UI.new("CanvasGroup", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = UI.Colors.Panel, BackgroundTransparency = 0.12, GroupTransparency = 1 }, holder)
	UI.corner(group, 12)
	stroke = UI.stroke(group, Color3.new(1, 1, 1), 2, 0.85)
	UI.padding(group, 12)
	title = UI.text("КАССА", { Size = UDim2.new(0.45, 0, 0, 22), TextSize = 17, Font = Enum.Font.GothamBlack }, group)
	totalLabel = UI.text("", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.new(0.55, 0, 0, 22), TextSize = 16, Font = Enum.Font.GothamBlack, TextColor3 = UI.Colors.Amber, TextXAlignment = Enum.TextXAlignment.Right, TextWrapped = false }, group)
	list = UI.new("ScrollingFrame", {
		Position = UDim2.fromOffset(0, 28),
		Size = UDim2.new(1, 0, 0, 104),
		BackgroundTransparency = 1,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 4,
		ScrollingDirection = Enum.ScrollingDirection.Y,
	}, group)
	UI.list(list, 2)
	status = UI.text("", { Position = UDim2.fromOffset(0, 136), Size = UDim2.new(1, 0, 0, 34), TextSize = 13, TextColor3 = Color3.fromRGB(214, 216, 222) }, group)
	actionRow = UI.new("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(1, 0, 0, 54), BackgroundTransparency = 1 }, group)
	mainButton = UI.button("ПРОБИТЬ ТОВАР", { Size = UDim2.fromScale(1, 1), TextSize = 17, Font = Enum.Font.GothamBlack, BackgroundColor3 = UI.Colors.Accent }, actionRow, function()
		if stage == "Scanning" then
			send("Scan")
		elseif stage == "Payment" then
			send("Card")
		end
	end)
	optionButtons = {}
	for i = 1, 3 do
		local b = UI.button("", {
			Position = UDim2.new((i - 1) / 3, i > 1 and 3 or 0, 0, 0),
			Size = UDim2.new(1 / 3, -4, 1, 0),
			TextSize = 15,
			Font = Enum.Font.GothamBlack,
			BackgroundColor3 = Color3.fromRGB(40, 120, 70),
			Visible = false,
		}, actionRow, function(btn)
			send("Change", optionButtons[i]:GetAttribute("Value"))
		end)
		optionButtons[i] = b
	end
end

function Pos.Init(c)
	ctx = c
	UI = ctx.UI
	build()
	-- клавиши: Q — пробить / оплата картой; 1, 2, 3 — варианты сдачи
	if RunService:IsClient() then
		ContextActionService:BindAction("NS_PosMain", function(_, state)
			if state ~= Enum.UserInputState.Begin or not shown then
				return Enum.ContextActionResult.Pass
			end
			if stage == "Scanning" then
				send("Scan")
			elseif stage == "Payment" and current and current:GetAttribute("Method") ~= "Cash" then
				send("Card")
			else
				return Enum.ContextActionResult.Pass
			end
			ctx.Audio.Play("UiClick", nil, 0.3)
			return Enum.ContextActionResult.Sink
		end, false, Enum.KeyCode.Q, Enum.KeyCode.ButtonX)
		ContextActionService:BindAction("NS_PosChange", function(_, state, input)
			if state ~= Enum.UserInputState.Begin or not shown or stage ~= "Payment" then
				return Enum.ContextActionResult.Pass
			end
			local i = ({ [Enum.KeyCode.One] = 1, [Enum.KeyCode.Two] = 2, [Enum.KeyCode.Three] = 3 })[input.KeyCode]
			local b = i and optionButtons[i]
			if b and b.Visible then
				send("Change", b:GetAttribute("Value"))
				ctx.Audio.Play("UiClick", nil, 0.3)
				return Enum.ContextActionResult.Sink
			end
			return Enum.ContextActionResult.Pass
		end, false, Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three)
	end
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc = acc + dt
		if acc < 0.15 then
			return
		end
		acc = 0
		local lane = (not ctx.CameraLocked and not ctx.IntroPlaying) and findLane() or nil
		if lane ~= current then
			current = lane
			lastVersion = -1
			lastError = lane and (lane:GetAttribute("ScanError") or 0) or 0
			for _, r in ipairs(rows) do
				r.Scanned = nil
			end
		end
		setShown(current ~= nil)
		if current then
			local v = current:GetAttribute("Version") or 0
			if v ~= lastVersion or (current:GetAttribute("ScanError") or 0) ~= lastError then
				lastVersion = v
				refresh()
			end
		end
	end)
end

-- Для тестов
function Pos.Debug()
	return {
		Shown = shown,
		Lane = current and current.Name,
		Stage = stage,
		Status = status and status.Text,
		Main = mainButton and mainButton.Visible and mainButton.Text or "",
		Options = optionButtons and table.concat((function()
			local t = {}
			for _, b in ipairs(optionButtons) do
				if b.Visible then
					table.insert(t, b.Text)
				end
			end
			return t
		end)(), "|") or "",
		Rows = #rows,
	}
end

return Pos
