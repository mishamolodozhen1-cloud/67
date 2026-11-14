-- Переключение светофоров на клиенте. Все клиенты синхронизированы по серверному времени:
-- одно направление перекрёстка горит зелёным, пока у поперечного — красный.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Settings = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Settings"))

local TrafficLights = {}

local ON = {
	Red = Color3.fromRGB(255, 42, 30),
	Yellow = Color3.fromRGB(255, 186, 26),
	Green = Color3.fromRGB(40, 232, 96),
}
local OFF = Color3.fromRGB(36, 36, 36)
local NAMES = { "Red", "Yellow", "Green" }

local function stateAt(axis, t)
	local c = Settings.TrafficCycle
	local cycle = c.Green + c.Yellow + c.Red
	local tt = t % cycle
	if axis == 1 then
		tt = (tt - (c.Green + c.Yellow)) % cycle
	end
	if tt < c.Green then
		return "Green"
	elseif tt < c.Green + c.Yellow then
		return "Yellow"
	end
	return "Red"
end

function TrafficLights.Start()
	local last = setmetatable({}, { __mode = "k" })
	CollectionService:GetInstanceAddedSignal("TrafficLight"):Connect(function(m)
		last[m] = nil
	end)
	task.spawn(function()
		while true do
			local t = workspace:GetServerTimeNow()
			local states = { [0] = stateAt(0, t), [1] = stateAt(1, t) }
			for _, m in ipairs(CollectionService:GetTagged("TrafficLight")) do
				local st = states[m:GetAttribute("Axis") == 1 and 1 or 0]
				if last[m] ~= st then
					last[m] = st
					for _, name in ipairs(NAMES) do
						local lamp = m:FindFirstChild(name)
						if lamp then
							local on = name == st
							lamp.Color = on and ON[name] or OFF
							lamp.Material = on and Enum.Material.Neon or Enum.Material.SmoothPlastic
						end
					end
				end
			end
			task.wait(0.25)
		end
	end)
end

return TrafficLights
