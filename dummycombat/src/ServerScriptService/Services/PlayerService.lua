-- PlayerService: сессии игроков на сервере.
--   • сессия создаётся при входе и удаляется при выходе (PlayerLeaving срабатывает до удаления);
--   • клиент, закончив загрузку, присылает ClientReady — сервер отмечает игрока готовым, отвечает
--     ServerInfo (игра, версия сборки, время сервера) и сообщает остальным системам (PlayerReady).
--     Дальнейшие этапы (лобби, матчи, данные) будут начинать работу с игроком именно с PlayerReady,
--     а не с PlayerAdded: к этому моменту у клиента уже есть все remotes и обработчики.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Configs = ReplicatedStorage:WaitForChild("Configs")
local Logger = require(Shared:WaitForChild("Logger"))
local Signal = require(Shared:WaitForChild("Signal"))
local GameConfig = require(Configs:WaitForChild("GameConfig"))
local BuildInfo = require(Configs:WaitForChild("BuildInfo"))

local PlayerService = { Name = "PlayerService" }

PlayerService.PlayerReady = Signal.new() -- (player, session)
PlayerService.PlayerLeaving = Signal.new() -- (player, session)

local log = Logger.new("Players")
local net = nil
local sessions = {}

local function addSession(player)
	if sessions[player] then
		return sessions[player]
	end
	local s = { UserId = player.UserId, Name = player.Name, JoinedAt = os.clock(), Ready = false }
	sessions[player] = s
	log:Info("вошёл %s (%d), игроков: %d", player.Name, player.UserId, #Players:GetPlayers())
	return s
end

local function removeSession(player)
	local s = sessions[player]
	if not s then
		return
	end
	PlayerService.PlayerLeaving:Fire(player, s)
	sessions[player] = nil
	log:Info("вышел %s (%d), был на сервере %.0f с", player.Name, player.UserId, os.clock() - s.JoinedAt)
end

function PlayerService.GetSession(player)
	return sessions[player]
end

function PlayerService.IsReady(player)
	local s = sessions[player]
	return s ~= nil and s.Ready
end

function PlayerService.ReadyPlayers()
	local out = {}
	for player, s in pairs(sessions) do
		if s.Ready then
			table.insert(out, player)
		end
	end
	return out
end

-- Что сервер сообщает клиенту о себе
function PlayerService.ServerInfo()
	return {
		Game = GameConfig.GameName,
		Version = BuildInfo.Version,
		Build = BuildInfo.Commit,
		PlaceVersion = game.PlaceVersion,
		ServerTime = workspace:GetServerTimeNow(),
	}
end

-- Клиент сообщил, что загрузился. Повторное сообщение ничего не делает. Возвращает сессию или nil
function PlayerService.MarkReady(player)
	local s = sessions[player]
	if not s and typeof(player) == "Instance" and player:IsA("Player") and player.Parent == Players then
		s = addSession(player)
	end
	if not s then
		return nil
	end
	if s.Ready then
		log:Debug("повторный ClientReady от %s — пропущен", player.Name)
		return nil
	end
	s.Ready = true
	s.ReadyAt = os.clock()
	if net then
		net.Fire(player, "ServerInfo", PlayerService.ServerInfo())
	end
	log:Info("%s готов (загрузка %.1f с)", player.Name, s.ReadyAt - s.JoinedAt)
	PlayerService.PlayerReady:Fire(player, s)
	return s
end

function PlayerService.Init(context)
	net = context.Get("NetService")
	Players.PlayerAdded:Connect(addSession)
	Players.PlayerRemoving:Connect(removeSession)
	for _, player in ipairs(Players:GetPlayers()) do
		addSession(player)
	end
end

function PlayerService.Start()
	net.Connect("ClientReady", PlayerService.MarkReady)
end

return PlayerService
