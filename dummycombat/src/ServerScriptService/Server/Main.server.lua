-- Точка входа сервера DUMMY COMBAT. Вся логика — в модулях: Server/Bootstrap запускает сервисы
-- из ServerScriptService.Services, системы следующих этапов будут лежать в ServerScriptService.Systems.
require(script.Parent:WaitForChild("Bootstrap")).Start()
