-- DevController: клавиши стенда проверки регдолла — ТОЛЬКО в Roblox Studio (в игре не подключаются).
--   J — упасть и встать        K — «выстрел в голову» спереди   L — «выстрел по ногам» сбоку
--   H — взрыв там, куда смотрит прицел (центр экрана)            N — поставить 5 манекенов
--   M — убрать манекены        P — статистика физики (в Output сервера)
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Logger = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Logger"))

local DevController = { Name = "DevController" }

DevController.Keys = {
	[Enum.KeyCode.J] = "Knockdown",
	[Enum.KeyCode.K] = "KillHead",
	[Enum.KeyCode.L] = "KillLegs",
	[Enum.KeyCode.H] = "Explode",
	[Enum.KeyCode.N] = "SpawnDummies",
	[Enum.KeyCode.M] = "ClearDummies",
	[Enum.KeyCode.P] = "Stats",
}

local log = Logger.new("Dev")
local net = nil

-- Куда смотрит прицел: луч из центра экрана (без своего персонажа), не дальше 400 studs
function DevController.AimPoint()
	local camera = workspace.CurrentCamera
	local ray = camera:ViewportPointToRay(camera.ViewportSize.X / 2, camera.ViewportSize.Y / 2)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { Players.LocalPlayer.Character }
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 400, params)
	return hit and hit.Position or (ray.Origin + ray.Direction * 60)
end

local function onKey(_, inputState, input)
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	local command = DevController.Keys[input.KeyCode]
	if not command then
		return Enum.ContextActionResult.Pass
	end
	if command == "Explode" then
		net.Fire("DevCommand", command, DevController.AimPoint())
	else
		net.Fire("DevCommand", command)
	end
	return Enum.ContextActionResult.Sink
end

function DevController.Init(context)
	net = context.Get("ClientNet")
end

function DevController.Start()
	if not RunService:IsStudio() then
		return
	end
	local keys = {}
	for key in pairs(DevController.Keys) do
		table.insert(keys, key)
	end
	ContextActionService:BindActionAtPriority("DC_Dev", onKey, false, Enum.ContextActionPriority.Low.Value, table.unpack(keys))
	log:Info("стенд проверки: J — упасть, K — выстрел в голову, L — по ногам, H — взрыв в прицел, N — манекены, M — убрать, P — статистика")
end

return DevController
