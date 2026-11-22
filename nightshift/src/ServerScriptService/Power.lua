-- Power: электричество магазина. При аварии выбивает автоматы в щитке (служебный коридор),
-- свет гаснет у всех игроков (клиент читает атрибут GameState.Power), кассы и холодильники не работают.
-- Чтобы вернуть свет, нужно поднять все выбитые автоматы.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Util = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"))

local Power = {}

local map, S
local down = {}
local outageCount = 0
local blackoutToken = 0 -- короткое отключение (v10): свет вернётся сам
Power.OnRestored = nil -- вызывается, когда свет снова горит (покупатели успокаиваются)

local GREEN = Color3.fromRGB(40, 220, 80)
local RED = Color3.fromRGB(255, 40, 30)

local function updatePanel()
	local any = false
	for k, b in ipairs(map.Panel.Breakers) do
		local isDown = down[k] == true
		any = any or isDown
		b.Led.Color = isDown and RED or GREEN
		b.Prompt.Enabled = isDown
		Util.tween(b.Lever, 0.15, { CFrame = isDown and b.DownCFrame or b.UpCFrame })
	end
	map.Panel.Label.Text = any and "АВАРИЯ: ПОДНИМИТЕ АВТОМАТЫ" or "СЕТЬ: НОРМА"
	map.Panel.Label.TextColor3 = any and RED or GREEN
end

function Power.IsOn()
	return S.Net.Get("Power") == true
end

function Power.Init(m, services)
	map, S = m, services
	for k, b in ipairs(map.Panel.Breakers) do
		local prompt = Util.prompt(b.Lever, "Поднять автомат", "Автомат №" .. k, 0.6, 6)
		prompt.Enabled = false
		b.Prompt = prompt
		prompt.Triggered:Connect(function(player)
			Power.Flip(k, player)
		end)
	end
	updatePanel()
end

-- Поднять автомат №k в щитке
function Power.Flip(k, player)
	if not down[k] then
		return
	end
	down[k] = nil
	S.Net.Sound("Knock", map.Panel.Breakers[k].Lever.Position, 0.35)
	updatePanel()
	if next(down) == nil then
		Power.Restore(player)
	elseif player then
		S.Net.Notify(player, "Автомат №" .. k .. " включён. Остались ещё", "info")
	end
end

-- Авария: гаснет свет, выбивает 2–3 автомата
function Power.Cut()
	if not Power.IsOn() then
		return false
	end
	outageCount = outageCount + 1
	down = {}
	local rng = Random.new()
	local count = rng:NextInteger(2, #map.Panel.Breakers)
	local order = Util.shuffle({ 1, 2, 3 }, rng)
	for i = 1, count do
		down[order[i]] = true
	end
	S.Net.Set("Power", false)
	S.Net.Sound("PowerDown", nil, 1)
	updatePanel()
	if Power.OnCut then
		task.spawn(Power.OnCut)
	end
	S.Tasks.Add({
		Id = "power_" .. outageCount,
		Kind = "power",
		Text = "Восстановить электричество в щитке",
		Room = "Служебный коридор",
		Count = 1,
	})
	return true
end

-- Короткое отключение (v10): весь свет гаснет на seconds секунд даже при покупателях, потом
-- включается сам (автоматы не выбивает). Возвращает false, если света и так нет
function Power.Blackout(seconds)
	if not Power.IsOn() then
		return false
	end
	blackoutToken = blackoutToken + 1
	local token = blackoutToken
	S.Net.Set("Power", false)
	S.Net.Sound("Blackout", nil, 0.9)
	task.delay(seconds or 12, function()
		if token == blackoutToken and next(down) == nil and not Power.IsOn() then
			S.Net.Set("Power", true)
			S.Net.Sound("Breaker", nil, 0.6)
			S.Net.Sound("FluorOn", nil, 0.8)
			if Power.OnRestored then
				task.spawn(Power.OnRestored)
			end
		end
	end)
	return true
end

function Power.Restore(player)
	down = {}
	updatePanel()
	if Power.IsOn() then
		return
	end
	S.Net.Set("Power", true)
	S.Net.Sound("FluorOn", nil, 0.8)
	if Power.OnRestored then
		task.spawn(Power.OnRestored)
	end
	S.Tasks.ProgressKind("power", 1)
	if player then
		S.Net.Notify(nil, player.DisplayName .. " восстановил(а) электричество", "done")
	end
end

function Power.Reset()
	blackoutToken = blackoutToken + 1
	down = {}
	outageCount = 0
	S.Net.Set("Power", true)
	updatePanel()
end

return Power
