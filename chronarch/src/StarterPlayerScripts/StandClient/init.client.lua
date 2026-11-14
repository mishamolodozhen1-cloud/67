-- Клиент: связывает эффекты, анимацию стендов и управление с событиями сервера.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Effects = require(script:WaitForChild("Effects"))
local StandAnimator = require(script:WaitForChild("StandAnimator"))
local Controls = require(script:WaitForChild("Controls"))

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local actionRemote = remotes:WaitForChild("StandAction")
local fxRemote = remotes:WaitForChild("StandFX")

Effects.Init(StandAnimator)
StandAnimator.Start(Effects.PlaySwish)
Controls.Start(actionRemote)

local handlers = {
	Hit = Effects.Hit,
	Finisher = Effects.Finisher,
	Summon = Effects.Summon,
	Desummon = Effects.Desummon,
	TimeStopStart = Effects.TimeStopStart,
	TimeFrozen = Effects.TimeFrozen,
	TimeResume = Effects.TimeResume,
	Awaken = function(userId)
		Effects.Awaken(userId)
		if userId == player.UserId then
			task.delay(0.6, Controls.OnAwaken)
		end
	end,
}

fxRemote.OnClientEvent:Connect(function(kind, ...)
	local handler = handlers[kind]
	if handler then
		local ok, err = pcall(handler, ...)
		if not ok then
			warn("[Stand FX]", kind, err)
		end
	end
end)
