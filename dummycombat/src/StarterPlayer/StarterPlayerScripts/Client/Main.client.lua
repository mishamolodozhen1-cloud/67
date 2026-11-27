-- Точка входа клиента DUMMY COMBAT. Запускает контроллеры из Client/Controllers тем же загрузчиком,
-- что и сервер (Shared/ModuleLoader): сначала Init у всех, потом Start.
-- ErrorReporter — первым, чтобы ловить ошибки остальных при запуске; ClientNet — до всего, что
-- пользуется сетью; затем персонаж, камера и кнопки для телефона. Контроллеры следующих этапов
-- (оружие, интерфейс…) добавляются в ORDER.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Logger = require(Shared:WaitForChild("Logger"))
local ModuleLoader = require(Shared:WaitForChild("ModuleLoader"))
local GameConfig = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("GameConfig"))

local ORDER = { "ErrorReporter", "ClientNet", "CharacterController", "CameraController", "TouchControls" }
local CRITICAL = { ClientNet = true, CharacterController = true }

local logging = GameConfig.Logging
Logger.Configure({
	Level = RunService:IsStudio() and logging.StudioLevel or logging.ClientLevel,
	HistorySize = logging.HistorySize,
	DuplicateWindow = logging.DuplicateWindow,
})

local report = ModuleLoader.Run({
	Name = "Client",
	Folder = script.Parent:WaitForChild("Controllers"),
	Order = ORDER,
	Critical = CRITICAL,
})

-- состояние загрузки клиента — атрибут локального игрока (виден только самому клиенту; для отладки)
local state = report.CriticalFailed and "Failed" or (report.Failures > 0 and "Degraded" or "Ready")
Players.LocalPlayer:SetAttribute("DC_ClientState", state)
