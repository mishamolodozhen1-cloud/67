-- Rooms: главное меню и комнаты.
--
-- Публичный сервер — это «холл» (главное меню): смена там не идёт, у игроков нет персонажей,
-- на фоне — ночной MART 24 под дождём. Из меню можно:
--   • играть одному — для игрока резервируется отдельный сервер, туда никто не зайдёт;
--   • создать комнату — резервируется сервер с кодом из 4 цифр; открытую комнату видно в списке,
--     закрытую — только по коду;
--   • войти по коду или выбрать комнату из списка открытых.
-- Комната — это зарезервированный сервер (TeleportService:ReserveServer), на нём идёт обычная игра.
-- Сведения о комнатах хранятся в MemoryStore:
--   NS_Rooms_v1   — код -> { Access, Host, Players, Max, Phase, Open }, живёт 90 с, сервер комнаты
--                   обновляет запись каждые 20 с (пока в комнате кто-то есть);
--   NS_Servers_v1 — id сервера -> { Code, Access, Solo, Open, Max, Host }: по нему сервер комнаты
--                   узнаёт свой код (данным телепорта от клиента не доверяем).
-- Из комнаты можно выйти в меню: игрок телепортируется на публичный сервер, то есть в холл.
local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Rooms = {}

local ROOM_TTL = 90
local SERVER_TTL = 6 * 3600
local MAX_PLAYERS = 4

local roomsMap, serversMap
local function maps()
	if not roomsMap then
		roomsMap = MemoryStoreService:GetSortedMap("NS_Rooms_v1")
		serversMap = MemoryStoreService:GetSortedMap("NS_Servers_v1")
	end
	return roomsMap, serversMap
end

local function retry(fn, tries)
	local last
	for i = 1, tries or 3 do
		local ok, a, b = pcall(fn)
		if ok then
			return true, a, b
		end
		last = a
		task.wait(0.4 * i)
	end
	return false, last
end

-------------------------------------------------------------------------------
-- Режим сервера
-------------------------------------------------------------------------------
-- Холл — публичный сервер. Любой зарезервированный или частный сервер — комната с игрой.
function Rooms.IsHub()
	if RunService:IsStudio() then
		return false -- в Studio сразу игра (телепорты там не работают)
	end
	return game.PrivateServerId == ""
end

-------------------------------------------------------------------------------
-- Холл: создание комнат, вход, список
-------------------------------------------------------------------------------
local cooldown = {}
local busy = {}

local function newCode()
	local rooms = maps()
	for _ = 1, 12 do
		local code = string.format("%04d", math.random(1000, 9999))
		local ok, existing = pcall(function()
			return rooms:GetAsync(code)
		end)
		if ok and existing == nil then
			return code
		end
	end
	return nil
end

local function teleport(player, accessCode, data)
	local options = Instance.new("TeleportOptions")
	options.ReservedServerAccessCode = accessCode
	options:SetTeleportData(data or {})
	local ok, err = retry(function()
		return TeleportService:TeleportAsync(game.PlaceId, { player }, options)
	end, 3)
	if not ok then
		warn("[Комнаты] телепорт не удался: " .. tostring(err))
	end
	return ok
end

-- Зарезервировать сервер и записать его в MemoryStore
local function reserve(player, solo, open, max)
	local _, servers = maps()
	local okR, access, psid = retry(function()
		return TeleportService:ReserveServer(game.PlaceId)
	end, 3)
	if not okR or not access then
		return nil, "Не удалось создать сервер. Попробуйте ещё раз."
	end
	local code = nil
	if not solo then
		code = newCode()
		if not code then
			return nil, "Не удалось выбрать код комнаты. Попробуйте ещё раз."
		end
	end
	local info = { Code = code, Access = access, Solo = solo, Open = open, Max = max, Host = player.DisplayName }
	if psid then
		retry(function()
			servers:SetAsync(psid, info, SERVER_TTL)
		end, 3)
	end
	if code then
		local rooms = maps()
		local ok = retry(function()
			rooms:SetAsync(code, { Access = access, Host = player.DisplayName, Players = 0, Max = max, Phase = "Lobby", Open = open, Created = os.time() }, ROOM_TTL)
		end, 3)
		if not ok then
			return nil, "Не удалось сохранить комнату. Попробуйте ещё раз."
		end
	end
	return info
end

local HANDLERS = {}

function HANDLERS.Solo(player)
	local info, err = reserve(player, true, false, 1)
	if not info then
		return { Ok = false, Error = err }
	end
	task.spawn(teleport, player, info.Access, { Solo = true })
	return { Ok = true }
end

function HANDLERS.Create(player, opts)
	opts = type(opts) == "table" and opts or {}
	local open = opts.Open ~= false
	local max = math.clamp(math.floor(tonumber(opts.Max) or MAX_PLAYERS), 2, MAX_PLAYERS)
	local info, err = reserve(player, false, open, max)
	if not info then
		return { Ok = false, Error = err }
	end
	task.spawn(teleport, player, info.Access, { Room = info.Code })
	return { Ok = true, Code = info.Code }
end

function HANDLERS.Join(player, code)
	code = type(code) == "string" and string.match(code, "^%s*(%d%d%d%d)%s*$") or nil
	if not code then
		return { Ok = false, Error = "Код комнаты — 4 цифры." }
	end
	local rooms = maps()
	local ok, room = retry(function()
		return rooms:GetAsync(code)
	end, 2)
	if not ok then
		return { Ok = false, Error = "Сервис комнат недоступен. Попробуйте ещё раз." }
	end
	if type(room) ~= "table" or not room.Access then
		return { Ok = false, Error = "Комната " .. code .. " не найдена. Проверьте код." }
	end
	if (room.Players or 0) >= (room.Max or MAX_PLAYERS) then
		return { Ok = false, Error = "Комната " .. code .. " заполнена." }
	end
	task.spawn(teleport, player, room.Access, { Room = code })
	return { Ok = true, Code = code }
end

function HANDLERS.List()
	local rooms = maps()
	local ok, items = retry(function()
		return rooms:GetRangeAsync(Enum.SortDirection.Ascending, 100)
	end, 2)
	if not ok then
		return { Ok = false, Error = "Сервис комнат недоступен." }
	end
	local list = {}
	for _, item in ipairs(items or {}) do
		local r = item.value
		if type(r) == "table" and r.Open and (r.Players or 0) < (r.Max or MAX_PLAYERS) then
			table.insert(list, {
				Code = item.key,
				Host = r.Host or "?",
				Players = r.Players or 0,
				Max = r.Max or MAX_PLAYERS,
				Phase = r.Phase or "Lobby",
			})
		end
	end
	-- сначала комнаты, где уже есть люди и смена ещё не началась
	table.sort(list, function(a, b)
		local la, lb = a.Phase == "Lobby", b.Phase == "Lobby"
		if la ~= lb then
			return la
		end
		return a.Players > b.Players
	end)
	return { Ok = true, Rooms = list }
end

-- Запрос игрока из меню (RemoteFunction Remotes.Rooms)
function Rooms.Handle(player, action, arg)
	local fn = type(action) == "string" and HANDLERS[action]
	if not fn then
		return { Ok = false, Error = "Неизвестное действие" }
	end
	-- не чаще раза в 1.5 с; создание и вход — по одному запросу за раз
	local now = os.clock()
	if action ~= "List" then
		if busy[player] or (cooldown[player] and now - cooldown[player] < 1.5) then
			return { Ok = false, Error = "Подождите секунду…" }
		end
		cooldown[player] = now
		busy[player] = true
	end
	local ok, result = pcall(fn, player, arg)
	busy[player] = nil
	if not ok then
		warn("[Комнаты] " .. action .. ": " .. tostring(result))
		return { Ok = false, Error = "Что-то пошло не так. Попробуйте ещё раз." }
	end
	return result
end

function Rooms.InitHub(remote)
	remote.OnServerInvoke = Rooms.Handle
	Players.PlayerRemoving:Connect(function(p)
		cooldown[p] = nil
		busy[p] = nil
	end)
	-- если телепорт не удался — сообщаем игроку, он может попробовать снова
	TeleportService.TeleportInitFailed:Connect(function(player, result, message)
		warn("[Комнаты] телепорт " .. player.Name .. ": " .. tostring(result) .. " " .. tostring(message))
		local e = ReplicatedStorage:FindFirstChild("Remotes") and ReplicatedStorage.Remotes:FindFirstChild("Notify")
		if e then
			e:FireClient(player, "Не удалось перейти на сервер. Попробуйте ещё раз.", "warn")
		end
	end)
end

-------------------------------------------------------------------------------
-- Комната (сервер с игрой)
-------------------------------------------------------------------------------
Rooms.Info = { Code = nil, Solo = false, Open = false, Max = MAX_PLAYERS }

local function publish(state)
	state:SetAttribute("RoomCode", Rooms.Info.Code or "")
	state:SetAttribute("RoomSolo", Rooms.Info.Solo == true)
	state:SetAttribute("RoomOpen", Rooms.Info.Open == true)
	state:SetAttribute("RoomMax", Rooms.Info.Max or MAX_PLAYERS)
end

local function updateRoom(state)
	local info = Rooms.Info
	if not info.Code then
		return
	end
	local rooms = maps()
	local count = #Players:GetPlayers()
	if count == 0 then
		return
	end
	pcall(function()
		rooms:SetAsync(info.Code, {
			Access = info.Access,
			Host = info.Host,
			Players = count,
			Max = info.Max,
			Phase = state:GetAttribute("Phase") or "Lobby",
			Open = info.Open,
		}, ROOM_TTL)
	end)
end

function Rooms.InitGame(state, remote)
	publish(state)
	remote.OnServerInvoke = function(player, action)
		if action == "Info" then
			return { Ok = true, Code = Rooms.Info.Code, Solo = Rooms.Info.Solo, Open = Rooms.Info.Open, Max = Rooms.Info.Max }
		elseif action == "Leave" then
			-- в меню: на публичный сервер (холл)
			task.spawn(function()
				local ok = retry(function()
					return TeleportService:TeleportAsync(game.PlaceId, { player })
				end, 3)
				if not ok then
					local e = ReplicatedStorage.Remotes:FindFirstChild("Notify")
					if e then
						e:FireClient(player, "Не удалось выйти в меню. Попробуйте ещё раз.", "warn")
					end
				end
			end)
			return { Ok = true }
		end
		return { Ok = false }
	end
	if game.PrivateServerId == "" or RunService:IsStudio() then
		return -- публичный сервер в Studio или тест: обычная игра без комнаты
	end
	task.spawn(function()
		local _, servers = maps()
		local info
		for _ = 1, 8 do
			local ok, v = pcall(function()
				return servers:GetAsync(game.PrivateServerId)
			end)
			if ok and type(v) == "table" then
				info = v
				break
			end
			task.wait(1.5)
		end
		if info then
			Rooms.Info = {
				Code = info.Code,
				Access = info.Access,
				Solo = info.Solo == true,
				Open = info.Open == true,
				Max = info.Max or MAX_PLAYERS,
				Host = info.Host,
			}
		else
			-- частный сервер Roblox (VIP) или запись пропала: играем без кода
			Rooms.Info = { Solo = false, Open = false, Max = MAX_PLAYERS }
		end
		publish(state)
		updateRoom(state)
		state:GetAttributeChangedSignal("Phase"):Connect(function()
			updateRoom(state)
		end)
		Players.PlayerAdded:Connect(function()
			updateRoom(state)
		end)
		Players.PlayerRemoving:Connect(function()
			task.defer(updateRoom, state)
		end)
		while true do
			task.wait(20)
			updateRoom(state)
		end
	end)
	game:BindToClose(function()
		if Rooms.Info.Code then
			local rooms = maps()
			pcall(function()
				rooms:RemoveAsync(Rooms.Info.Code)
			end)
		end
	end)
end

return Rooms
