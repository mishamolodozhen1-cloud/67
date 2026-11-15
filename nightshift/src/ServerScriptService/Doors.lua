-- Doors: распашные двери (подсказка «Открыть/Закрыть»), автоматические двери входа,
-- а также события: дверь захлопнулась, заперлась, входные двери открылись сами.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Util = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"))

local Doors = {}

local map, S
local SOUND_OPEN = { Swing = "DoorOpen", Metal = "DoorOpen", Freezer = "FreezerDoor" }
local SOUND_CLOSE = { Swing = "DoorSlam", Metal = "DoorSlam", Freezer = "FreezerDoor" }

local function center(door)
	return door.Parts[1].Position
end

local function move(door, open, seconds)
	door.IsOpen = open
	for i, part in ipairs(door.Parts) do
		Util.tween(part, seconds or 0.7, { CFrame = open and door.Open[i] or door.Closed[i] }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	end
	if door.Prompt then
		door.Prompt.ActionText = open and "Закрыть" or "Открыть"
	end
end

local function setDoor(door, open, silent)
	if door.IsOpen == open then
		return
	end
	move(door, open)
	if not silent then
		local name = open and SOUND_OPEN[door.Kind] or SOUND_CLOSE[door.Kind]
		S.Net.Sound(name, center(door), open and 0.8 or 0.45)
	end
	if door.Pair then
		local other = map.Doors[door.Pair]
		if other and other.IsOpen ~= open then
			move(other, open)
		end
	end
end

function Doors.Init(m, services)
	map, S = m, services
	for _, door in pairs(map.Doors) do
		-- у парной двери склада одна подсказка на каждой створке
		local prompt = Util.prompt(door.Parts[1], "Открыть", door.Label, 0, 7)
		prompt.Name = "DoorPrompt"
		door.Prompt = prompt
		prompt.Triggered:Connect(function(player)
			if door.Locked then
				if door.Name == "BackExit" and not door.Jammed then
					-- задний выход запирается на щеколду изнутри: её можно открыть
					Doors.SetLocked(door.Name, false)
					S.Net.Sound("Knock", center(door), 0.4)
					S.Net.Notify(player, "Вы отперли задний выход", "info")
					return
				end
				S.Net.Sound("Knock", center(door), 0.5)
				S.Net.Notify(player, "Дверь не открывается…", "warn")
				return
			end
			setDoor(door, not door.IsOpen)
			if S.Events then
				S.Events.OnDoor(door.Name, door.IsOpen, player)
			end
		end)
	end
end

function Doors.Get(name)
	return map.Doors[name]
end

function Doors.Set(name, open, silent)
	local door = map.Doors[name]
	if door then
		setDoor(door, open, silent)
	end
end

-- Захлопнуть дверь (событие)
function Doors.Slam(name)
	local door = map.Doors[name]
	if door and door.IsOpen then
		move(door, false, 0.25)
		if door.Pair then
			local other = map.Doors[door.Pair]
			if other then
				move(other, false, 0.25)
			end
		end
		S.Net.Sound("DoorSlam", center(door), 1)
		return true
	end
	return false
end

-- jammed = true: дверь заклинило (событие), её нельзя открыть изнутри
function Doors.SetLocked(name, locked, jammed)
	local door = map.Doors[name]
	if door then
		door.Locked = locked
		door.Jammed = locked and jammed == true or false
		if door.Prompt then
			door.Prompt.ObjectText = locked and (door.Label .. " (заперто)") or door.Label
			door.Prompt.ActionText = locked and (door.Jammed and "Открыть" or "Отпереть") or (door.IsOpen and "Закрыть" or "Открыть")
		end
	end
end

-------------------------------------------------------------------------------
-- Автоматические двери входа
-------------------------------------------------------------------------------
local autoOpen = false
local ghostUntil = 0

local function setAuto(open)
	if autoOpen == open then
		return
	end
	autoOpen = open
	local a = map.AutoDoor
	Util.tween(a.Left, 0.9, { CFrame = open and a.LeftOpen or a.LeftClosed })
	Util.tween(a.Right, 0.9, { CFrame = open and a.RightOpen or a.RightClosed })
	S.Net.Sound("AutoDoor", a.Center + Vector3.new(0, 8, 0), 0.6)
	if open then
		S.Net.Sound("DoorChime", a.Center + Vector3.new(0, 8, -4), 0.5)
	end
end

local function someoneNear()
	local c = map.AutoDoor.Center
	local function near(root)
		return root and math.abs(root.Position.X - c.X) < 8 and math.abs(root.Position.Z - c.Z) < 11
	end
	for _, p in ipairs(Players:GetPlayers()) do
		if near(Util.rootOf(p)) then
			return true
		end
	end
	if S.Customers then
		for _, npc in ipairs(S.Customers.All()) do
			if npc.Alive and near(npc.Root) then
				return true
			end
		end
	end
	return false
end

-- Двери открываются сами, хотя у входа никого нет
function Doors.GhostOpen(seconds)
	ghostUntil = os.clock() + (seconds or 4)
end

function Doors.Start()
	task.spawn(function()
		local lastNear = 0
		while true do
			task.wait(0.2)
			local near = someoneNear() or os.clock() < ghostUntil
			if near then
				lastNear = os.clock()
				setAuto(true)
			elseif autoOpen and os.clock() - lastNear > 1.6 then
				setAuto(false)
			end
		end
	end)
end

-- Новая смена: все двери закрыты и не заперты
function Doors.Reset()
	for name, door in pairs(map.Doors) do
		door.Locked = false
		Doors.SetLocked(name, false)
		if door.IsOpen then
			move(door, false, 0.3)
		end
	end
	ghostUntil = 0
end

return Doors
