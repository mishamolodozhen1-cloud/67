-- NIGHT SHIFT — точка входа сервера (Script «Main» в ServerScriptService).
-- Публичный сервер — главное меню (холл): там создают комнаты и выбирают, с кем играть.
-- Комната (зарезервированный сервер) — сама игра: GameServer строит магазин MART 24 и запускает смену.
local ServerScriptService = game:GetService("ServerScriptService")

local GameServer = require(ServerScriptService:WaitForChild("GameServer"))
local Rooms = require(ServerScriptService:WaitForChild("Rooms"))

if Rooms.IsHub() then
	GameServer.StartHub()
else
	GameServer.Start()
end
