-- GameConfig: общие настройки DUMMY COMBAT. Их читают и сервер, и клиент.
-- Таблица заморожена: во время игры её не изменить (ни случайно, ни эксплойтом на клиенте —
-- на сервере у клиента всё равно своей копии нет). Менять значения — только здесь.
-- Настройки отдельных систем (оружие, карты, режимы) будут лежать рядом, в своих модулях Configs.
local function deepFreeze(t)
	for _, v in pairs(t) do
		if type(v) == "table" and not table.isfrozen(v) then
			deepFreeze(v)
		end
	end
	return table.freeze(t)
end

return deepFreeze({
	GameName = "DUMMY COMBAT",

	-- Журнал (Shared/Logger): уровни Debug < Info < Warn < Error
	Logging = {
		ServerLevel = "Info", -- опубликованная игра, сервер
		ClientLevel = "Warn", -- опубликованная игра, клиент (в Output игрока — только важное)
		StudioLevel = "Debug", -- Roblox Studio: подробно
		HistorySize = 200, -- сколько последних записей держать в памяти
		DuplicateWindow = 10, -- одинаковое сообщение чаще этого (секунды) не печатается, а считается
	},

	-- Ошибки на клиентах (клиент сообщает, ErrorService собирает)
	ClientErrors = {
		MaxMessage = 400, -- байт в тексте ошибки
		MaxTrace = 1200, -- байт в стеке вызовов
		MaxPerSession = 25, -- больше этого от одного клиента за сессию не принимаем (дальше — шум)
		History = 100, -- сколько последних ошибок (сервера и клиентов) держит ErrorService
	},

	-- Сеть (Services/NetService, Controllers/ClientNet)
	Net = {
		RemotesFolder = "Remotes", -- ReplicatedStorage.Remotes
		ReadyTimeout = 30, -- сколько клиент ждёт, пока сервер подготовит remotes (с)
		ViolationWindow = 60, -- окно подсчёта нарушений (с)
		ViolationLimit = 30, -- нарушений за окно: игрока отключают с сервера
		KickOnViolations = true,
		-- клиент шлёт чуть реже, чем разрешает сервер: честный клиент никогда не упирается в лимит
		ClientRateFactor = 0.8,
	},
})
