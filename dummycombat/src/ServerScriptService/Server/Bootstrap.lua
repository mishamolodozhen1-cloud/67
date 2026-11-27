-- Bootstrap: запуск сервера DUMMY COMBAT. Вызывается из Server/Main один раз (повторный вызов
-- возвращает тот же отчёт).
--
-- Порядок важен: ErrorService первым (ловит ошибки остальных при запуске), затем сеть, затем всё,
-- что ей пользуется. Сначала постоянные сервисы (Services), потом игровые системы (Systems): системы
-- берут сервисы через context.Get. Новые модули следующих этапов добавляются в эти списки.
-- Состояние загрузки видно в атрибутах ServerScriptService: DC_BootState (Starting / Ready / Degraded /
-- Failed) и DC_BootFailures.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Configs = ReplicatedStorage:WaitForChild("Configs")
local Logger = require(Shared:WaitForChild("Logger"))
local ModuleLoader = require(Shared:WaitForChild("ModuleLoader"))
local GameConfig = require(Configs:WaitForChild("GameConfig"))
local BuildInfo = require(Configs:WaitForChild("BuildInfo"))

local Bootstrap = {}

local SERVICE_ORDER = { "ErrorService", "NetService", "PlayerService" }
local SYSTEM_ORDER = { "RagdollSystem", "CharacterSystem", "MovementSystem", "DevSystem" }
local CRITICAL = { NetService = true, PlayerService = true, CharacterSystem = true, RagdollSystem = true }

local report = nil

function Bootstrap.Start()
	if report then
		return report
	end
	report = { Pending = true }
	local logging = GameConfig.Logging
	Logger.Configure({
		Level = RunService:IsStudio() and logging.StudioLevel or logging.ServerLevel,
		HistorySize = logging.HistorySize,
		DuplicateWindow = logging.DuplicateWindow,
	})
	local log = Logger.new("Boot")
	ServerScriptService:SetAttribute("DC_BootState", "Starting")
	log:Info("%s %s (сборка %s от %s), версия плейса %d", GameConfig.GameName, BuildInfo.Version, BuildInfo.Commit, BuildInfo.BuiltAt, game.PlaceVersion)

	report = ModuleLoader.Run({
		Name = "Server",
		Groups = {
			{ Folder = ServerScriptService:WaitForChild("Services"), Order = SERVICE_ORDER },
			{ Folder = ServerScriptService:WaitForChild("Systems"), Order = SYSTEM_ORDER },
		},
		Critical = CRITICAL,
	})
	local state = "Ready"
	if report.CriticalFailed then
		state = "Failed"
	elseif report.Failures > 0 then
		state = "Degraded"
	end
	report.State = state
	ServerScriptService:SetAttribute("DC_BootState", state)
	ServerScriptService:SetAttribute("DC_BootFailures", report.Failures)
	if state ~= "Ready" then
		log:Error("сервер запущен с ошибками: %s", state)
	end
	return report
end

-- Сервис по имени (после Start)
function Bootstrap.Get(name)
	assert(report and report.Context, "Bootstrap.Get: сервер ещё не запущен")
	return report.Context.Get(name)
end

return Bootstrap
