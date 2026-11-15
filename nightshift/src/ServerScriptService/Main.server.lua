-- NIGHT SHIFT — точка входа сервера (Script «Main» в ServerScriptService).
-- Вся логика в модуле GameServer: он строит магазин MART 24 и запускает смену.
local ServerScriptService = game:GetService("ServerScriptService")

require(ServerScriptService:WaitForChild("GameServer")).Start()
