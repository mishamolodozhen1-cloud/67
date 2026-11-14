-- Серверная часть админ-панели. Каждое действие проверяется: доступ есть только у администраторов
-- из Settings.Admins и у владельца игры.
local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local TextService = game:GetService("TextService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Settings = require(Shared:WaitForChild("Settings"))
local Places = require(Shared:WaitForChild("Places"))

local AdminService = {}

local states = {}
local announceRemote

local function isAdmin(player)
	if Settings.Admins[player.UserId] then
		return true
	end
	return game.CreatorType == Enum.CreatorType.User and player.UserId == game.CreatorId
end

local function getState(player)
	local s = states[player]
	if not s then
		s = { speed = 16, jump = 50, god = false, invisible = false }
		states[player] = s
	end
	return s
end

local function humanoidOf(player)
	local char = player.Character
	return char and char:FindFirstChildOfClass("Humanoid"), char
end

local function setInvisible(char, on)
	for _, d in ipairs(char:GetDescendants()) do
		if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" then
			d.Transparency = on and 1 or 0
		elseif d:IsA("Decal") then
			d.Transparency = on and 1 or 0
		end
	end
end

local function apply(player)
	local s = getState(player)
	local hum, char = humanoidOf(player)
	if not hum then
		return
	end
	hum.WalkSpeed = s.speed
	hum.UseJumpPower = true
	hum.JumpPower = s.jump
	local ff = char:FindFirstChild("AdminGod")
	if s.god then
		hum.MaxHealth = math.huge
		hum.Health = math.huge
		if not ff then
			ff = Instance.new("ForceField")
			ff.Name = "AdminGod"
			ff.Visible = false
			ff.Parent = char
		end
	else
		if ff then
			ff:Destroy()
		end
		if hum.MaxHealth == math.huge then
			hum.MaxHealth = 100
			hum.Health = 100
		end
	end
	if s.invisible then
		setInvisible(char, true)
	end
end

local function teleport(player, position)
	local _, char = humanoidOf(player)
	if not char then
		return false
	end
	pcall(function()
		player:RequestStreamAroundAsync(position, 8)
	end)
	char:PivotTo(CFrame.new(position + Vector3.new(0, 3, 0)))
	return true
end

local function findPlayer(userId)
	return Players:GetPlayerByUserId(tonumber(userId) or 0)
end

local function rootPart(player)
	local char = player and player.Character
	return char and char:FindFirstChild("HumanoidRootPart")
end

local HANDLERS = {}

function HANDLERS.Speed(player, value)
	getState(player).speed = math.clamp(tonumber(value) or 16, 4, 500)
	apply(player)
	return "Скорость: " .. getState(player).speed
end

function HANDLERS.Jump(player, value)
	getState(player).jump = math.clamp(tonumber(value) or 50, 0, 600)
	apply(player)
	return "Прыжок: " .. getState(player).jump
end

function HANDLERS.God(player, on)
	getState(player).god = on == true
	apply(player)
	return on and "Бессмертие включено" or "Бессмертие выключено"
end

function HANDLERS.Invisible(player, on)
	getState(player).invisible = on == true
	local _, char = humanoidOf(player)
	if char then
		setInvisible(char, on == true)
	end
	return on and "Ты невидим" or "Ты снова видим"
end

function HANDLERS.Heal(player)
	local hum = humanoidOf(player)
	if hum then
		hum.Health = hum.MaxHealth
	end
	return "Здоровье восстановлено"
end

function HANDLERS.Respawn(player)
	player:LoadCharacter()
	return "Персонаж перерождён"
end

function HANDLERS.Teleport(player, index)
	local place = Places.List[tonumber(index) or 0]
	if not place then
		return "Нет такой точки"
	end
	teleport(player, place.position)
	return "Телепорт: " .. place.name
end

function HANDLERS.GotoPlayer(player, userId)
	local hrp = rootPart(findPlayer(userId))
	if not hrp then
		return "Игрок не найден"
	end
	teleport(player, hrp.Position + hrp.CFrame.LookVector * 6)
	return "Ты рядом с игроком"
end

function HANDLERS.Bring(player, userId)
	local target = findPlayer(userId)
	local me = rootPart(player)
	if not target or not me then
		return "Игрок не найден"
	end
	teleport(target, me.Position + me.CFrame.LookVector * 6)
	return target.DisplayName .. " перенесён к тебе"
end

function HANDLERS.Freeze(player, userId, on)
	local hrp = rootPart(findPlayer(userId))
	if not hrp then
		return "Игрок не найден"
	end
	hrp.Anchored = on == true
	return on and "Игрок заморожен" or "Игрок разморожен"
end

function HANDLERS.Kick(player, userId)
	local target = findPlayer(userId)
	if not target then
		return "Игрок не найден"
	end
	if target == player then
		return "Себя кикнуть нельзя"
	end
	target:Kick("Вас отключил администратор.")
	return "Игрок отключён"
end

function HANDLERS.Time(player, clock)
	Lighting.ClockTime = math.clamp(tonumber(clock) or 14, 0, 24)
	return "Время: " .. string.format("%.1f", Lighting.ClockTime)
end

function HANDLERS.Fog(player, on)
	local atm = Lighting:FindFirstChildOfClass("Atmosphere")
	if atm then
		atm.Density = on and 0.62 or 0.27
		atm.Haze = on and 3 or 1.2
	end
	return on and "Туман включён" or "Туман выключен"
end

function HANDLERS.Gravity(player, value)
	workspace.Gravity = math.clamp(tonumber(value) or 196.2, 10, 400)
	return "Гравитация: " .. workspace.Gravity
end

function HANDLERS.Announce(player, text)
	if type(text) ~= "string" then
		return "Пустое сообщение"
	end
	text = string.sub(text, 1, 200)
	if #text == 0 then
		return "Пустое сообщение"
	end
	local ok, filtered = pcall(function()
		local result = TextService:FilterStringAsync(text, player.UserId, Enum.TextFilterContext.PublicChat)
		return result:GetNonChatStringForBroadcastAsync()
	end)
	if not ok then
		return "Фильтр сообщений недоступен, попробуй позже"
	end
	announceRemote:FireAllClients(filtered, player.DisplayName)
	return "Объявление отправлено"
end

function AdminService.Start()
	local remotes = Instance.new("Folder")
	remotes.Name = "Remotes"
	local request = Instance.new("RemoteFunction")
	request.Name = "AdminRequest"
	request.Parent = remotes
	announceRemote = Instance.new("RemoteEvent")
	announceRemote.Name = "Announcement"
	announceRemote.Parent = remotes
	remotes.Parent = ReplicatedStorage

	request.OnServerInvoke = function(player, action, a, b)
		if not isAdmin(player) then
			return false, "Нет доступа"
		end
		local handler = HANDLERS[action]
		if type(action) ~= "string" or not handler then
			return false, "Неизвестная команда"
		end
		local ok, res = pcall(handler, player, a, b)
		if not ok then
			warn("[Admin]", action, res)
			return false, "Ошибка: " .. tostring(res)
		end
		return true, res
	end

	local function onPlayer(player)
		if isAdmin(player) then
			player:SetAttribute("IsAdmin", true)
			player.CharacterAdded:Connect(function()
				task.wait(0.2)
				apply(player)
			end)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, p in ipairs(Players:GetPlayers()) do
		onPlayer(p)
	end
	Players.PlayerRemoving:Connect(function(p)
		states[p] = nil
	end)
end

return AdminService
