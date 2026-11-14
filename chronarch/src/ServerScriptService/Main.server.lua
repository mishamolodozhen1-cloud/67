-- Точка входа сервера: строим мир и запускаем логику стенда.
local ServerScriptService = game:GetService("ServerScriptService")

local WorldBuilder = require(ServerScriptService:WaitForChild("WorldBuilder"))
local StandService = require(ServerScriptService:WaitForChild("StandService"))

local prompt, dummies = WorldBuilder.Build()
StandService.Start(prompt, dummies)
