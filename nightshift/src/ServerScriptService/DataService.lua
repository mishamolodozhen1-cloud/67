-- DataService: сохранение прогресса игрока в DataStore.
-- Храним: сколько смен отработано, какие концовки получены, заработок, лучший процент,
-- до какой ночи открыт доступ и настройки.
-- В Roblox Studio для проверки включите Game Settings → Security → Enable Studio Access to API Services.
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local DataService = {}

local STORE_NAME = "NightShift_Profiles_v1"
local store
local profiles = {}
local dirty = {}

local function defaultProfile()
	return {
		Nights = 0,
		Good = 0,
		Bad = 0,
		Secret = 0,
		Earnings = 0,
		BestPercent = 0,
		NightUnlocked = 1, -- до какой ночи (1–5) открыт доступ
		Completed = 0, -- сколько раз пережита пятая ночь
		Settings = {
			Music = 0.6,
			Sfx = 1,
			Brightness = 0,
			Fov = 80,
			HeadBob = true,
			Subtitles = true,
		},
	}
end

-- Подмешать сохранённые значения к значениям по умолчанию (новые поля появятся у старых профилей)
local function merge(base, saved)
	if type(saved) ~= "table" then
		return base
	end
	for k, v in pairs(base) do
		if type(v) == "table" then
			base[k] = merge(v, saved[k])
		elseif saved[k] ~= nil and type(saved[k]) == type(v) then
			base[k] = saved[k]
		end
	end
	return base
end

local function key(player)
	return "p_" .. player.UserId
end

local function load(player)
	local data
	if store then
		for _ = 1, 3 do
			local ok, res = pcall(function()
				return store:GetAsync(key(player))
			end)
			if ok then
				data = res
				break
			end
			task.wait(1.5)
		end
	end
	profiles[player] = merge(defaultProfile(), data)
	player:SetAttribute("ProfileLoaded", true)
end

local function save(player)
	local profile = profiles[player]
	if not (store and profile) then
		return
	end
	dirty[player] = nil
	local ok, err = pcall(function()
		store:UpdateAsync(key(player), function()
			return profile
		end)
	end)
	if not ok then
		warn("[Сохранение] " .. tostring(err))
	end
end

function DataService.Init()
	local ok, ds = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	store = ok and ds or nil
	Players.PlayerAdded:Connect(load)
	for _, p in ipairs(Players:GetPlayers()) do
		task.spawn(load, p)
	end
	Players.PlayerRemoving:Connect(function(player)
		save(player)
		profiles[player] = nil
		dirty[player] = nil
	end)
	game:BindToClose(function()
		for _, p in ipairs(Players:GetPlayers()) do
			save(p)
		end
	end)
	-- изменённые настройки сохраняем не чаще раза в 30 секунд
	task.spawn(function()
		while true do
			task.wait(30)
			for p in pairs(dirty) do
				if p.Parent then
					save(p)
				end
			end
		end
	end)
end

function DataService.Get(player)
	return profiles[player]
end

-- Итоги смены
function DataService.RecordShift(player, kind, stats)
	local profile = profiles[player]
	if not profile then
		return
	end
	profile.Nights = profile.Nights + 1
	profile[kind] = (profile[kind] or 0) + 1
	profile.Earnings = profile.Earnings + (stats.Salary or 0)
	profile.BestPercent = math.max(profile.BestPercent, stats.Percent or 0)
	-- ночь пройдена (хорошая или секретная концовка) — открывается следующая
	local night = math.clamp(math.floor(tonumber(stats.Night) or 1), 1, 5)
	if kind ~= "Bad" then
		profile.NightUnlocked = math.clamp(math.max(profile.NightUnlocked or 1, night + 1), 1, 5)
		if night >= 5 then
			profile.Completed = (profile.Completed or 0) + 1
		end
	end
	task.spawn(save, player)
end

-- Настройки с клиента (проверяем типы и границы)
function DataService.SaveSettings(player, s)
	local profile = profiles[player]
	if not profile or type(s) ~= "table" then
		return
	end
	local cur = profile.Settings
	local function num(name, lo, hi)
		if type(s[name]) == "number" and s[name] == s[name] then
			cur[name] = math.clamp(s[name], lo, hi)
		end
	end
	num("Music", 0, 1)
	num("Sfx", 0, 1)
	num("Brightness", -0.3, 0.5)
	num("Fov", 60, 100)
	if type(s.HeadBob) == "boolean" then
		cur.HeadBob = s.HeadBob
	end
	if type(s.Subtitles) == "boolean" then
		cur.Subtitles = s.Subtitles
	end
	dirty[player] = true
end

return DataService
