-- ProgressionSystem: профиль игрока (этап 10) — уровень, опыт, монеты, статистика, купленное оружие и
-- окраски, снаряжение, настройки. Хранится в DataStore (ProgressionConfig.DataStore), ключ u_<UserId>.
--
-- Загрузка — при входе (до 3 попыток); если хранилище недоступно (например, Studio без доступа к API) —
-- профиль по умолчанию на эту сессию, без сохранения (и предупреждение). Сохранение — при выходе,
-- каждые AutosaveEvery секунд и при остановке сервера (UpdateAsync: не затираем более новые данные).
--
-- Награды: за убийство, выстрел в голову, помощь (сразу, событие Reward) и за матч — участие, тройка
-- лучших, победа (событие Rewards с разбором и новыми уровнями). Боты наград не получают.
-- Магазин (событие Buy): оружие и окраски за монеты, с порога уровня. Снаряжение (EquipItem): основное
-- оружие и окраска. Окраска на персонаже — текстура частей тела (SkinAssets); в командном режиме — цвет
-- команды.
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Configs = ReplicatedStorage:WaitForChild("Configs")
local Logger = require(Shared:WaitForChild("Logger"))
local Signal = require(Shared:WaitForChild("Signal"))
local PC = require(Configs:WaitForChild("ProgressionConfig"))
local SkinAssets = require(Configs:WaitForChild("SkinAssets"))
local WeaponConfig = require(Configs:WaitForChild("WeaponConfig"))

local ProgressionSystem = { Name = "ProgressionSystem" }

ProgressionSystem.LevelUp = Signal.new() -- (player, level)

local log = Logger.new("Progress")
local net, match, characters = nil, nil, nil
local profiles = {} -- player → { Data, Loaded, Persistent, Dirty }
local store = nil
local BODY_PARTS = {
	"Head", "UpperTorso", "LowerTorso", "LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm", "RightLowerArm",
	"RightHand", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg", "RightLowerLeg", "RightFoot",
}

function ProgressionSystem.DefaultData()
	local owned = { Weapons = {}, Skins = { Classic = true } }
	for id, w in pairs(PC.Weapons) do
		if w.Price == 0 then
			owned.Weapons[id] = true
		end
	end
	return {
		Version = 1,
		Level = 1,
		Xp = 0,
		Coins = PC.StartCoins,
		Stats = { Kills = 0, Deaths = 0, Assists = 0, Headshots = 0, Wins = 0, Matches = 0 },
		Owned = owned,
		Loadout = { Primary = WeaponConfig.Default, Skin = "Classic" },
		Settings = { Sensitivity = 1, AimSensitivity = 0.72, Fov = 72, Master = 1, Music = 0.5, Sfx = 1, Crosshair = 1 },
	}
end

-- Слить сохранённое с значениями по умолчанию (новые поля в новых версиях игры)
local function merge(saved, default)
	if type(saved) ~= "table" then
		return default
	end
	for k, v in pairs(default) do
		if saved[k] == nil then
			saved[k] = v
		elseif type(v) == "table" and type(saved[k]) == "table" and k ~= "Owned" then
			merge(saved[k], v)
		end
	end
	saved.Owned = saved.Owned or default.Owned
	saved.Owned.Weapons = saved.Owned.Weapons or {}
	saved.Owned.Skins = saved.Owned.Skins or { Classic = true }
	for id, w in pairs(PC.Weapons) do
		if w.Price == 0 then
			saved.Owned.Weapons[id] = true
		end
	end
	saved.Owned.Skins.Classic = true
	return saved
end

function ProgressionSystem.Get(player)
	local p = profiles[player]
	return p and p.Data or nil
end

local function snapshot(data)
	return {
		Level = data.Level,
		Xp = data.Xp,
		XpToNext = PC.XpToNext(data.Level),
		Coins = data.Coins,
		Stats = data.Stats,
		Owned = data.Owned,
		Loadout = data.Loadout,
		Settings = data.Settings,
	}
end

local function push(player)
	local p = profiles[player]
	if p and net and typeof(player) == "Instance" then
		net.Fire(player, "Profile", snapshot(p.Data))
	end
end

function ProgressionSystem.PrimaryWeapon(player)
	local d = ProgressionSystem.Get(player)
	return d and d.Loadout.Primary or nil
end

-------------------------------------------------------------------------------
-- Сохранение
-------------------------------------------------------------------------------
local function key(player)
	return "u_" .. tostring(player.UserId)
end

local function load(player)
	local data, persistent = nil, false
	if store then
		for attempt = 1, 3 do
			local ok, result = pcall(store.GetAsync, store, key(player))
			if ok then
				data, persistent = result, true
				break
			end
			log:Warn("профиль %s: попытка %d: %s", player.Name, attempt, tostring(result))
			task.wait(attempt)
		end
	end
	if not persistent then
		log:Warn("профиль %s не загружен — на эту сессию, без сохранения", player.Name)
	end
	profiles[player] = { Data = merge(data, ProgressionSystem.DefaultData()), Persistent = persistent, Dirty = false }
	player:SetAttribute("Level", profiles[player].Data.Level)
	push(player)
end

local function save(player)
	local p = profiles[player]
	if not (p and p.Persistent and store) then
		return false
	end
	local data = p.Data
	local ok, err = pcall(store.UpdateAsync, store, key(player), function()
		return data
	end)
	if ok then
		p.Dirty = false
	else
		log:Warn("профиль %s не сохранён: %s", player.Name, tostring(err))
	end
	return ok
end
ProgressionSystem.Save = save

-------------------------------------------------------------------------------
-- Опыт и монеты
-------------------------------------------------------------------------------
-- Добавить опыт и монеты. Возвращает список новых уровней
function ProgressionSystem.Grant(player, xp, coins)
	local p = profiles[player]
	if not p then
		return {}
	end
	local d = p.Data
	d.Coins = d.Coins + (coins or 0)
	d.Xp = d.Xp + (xp or 0)
	local ups = {}
	while d.Level < PC.MaxLevel and d.Xp >= PC.XpToNext(d.Level) do
		d.Xp = d.Xp - PC.XpToNext(d.Level)
		d.Level = d.Level + 1
		table.insert(ups, d.Level)
		ProgressionSystem.LevelUp:Fire(player, d.Level)
	end
	if #ups > 0 and typeof(player) == "Instance" then
		player:SetAttribute("Level", d.Level)
	end
	p.Dirty = true
	return ups
end

local function onKill(kill, killerP, victimP)
	local killer = kill.Killer
	if typeof(killer) == "Instance" and profiles[killer] and killerP and not killerP.IsBot then
		local d = profiles[killer].Data
		d.Stats.Kills = d.Stats.Kills + 1
		local xp, coins = PC.Xp.Kill, PC.Coins.Kill
		if kill.Headshot then
			d.Stats.Headshots = d.Stats.Headshots + 1
			xp, coins = xp + PC.Xp.Headshot, coins + PC.Coins.Headshot
		end
		local ups = ProgressionSystem.Grant(killer, xp, coins)
		net.Fire(killer, "Reward", { Xp = xp, Coins = coins, Reason = kill.Headshot and "Headshot" or "Kill", LevelUps = ups })
		push(killer)
	end
	for _, a in ipairs(kill.Assists or {}) do
		if typeof(a) == "Instance" and profiles[a] then
			profiles[a].Data.Stats.Assists = profiles[a].Data.Stats.Assists + 1
			local ups = ProgressionSystem.Grant(a, PC.Xp.Assist, PC.Coins.Assist)
			net.Fire(a, "Reward", { Xp = PC.Xp.Assist, Coins = PC.Coins.Assist, Reason = "Assist", LevelUps = ups })
			push(a)
		end
	end
	local victim = kill.VictimPlayer
	if victim and profiles[victim] and victimP and victimP.InMatch then
		profiles[victim].Data.Stats.Deaths = profiles[victim].Data.Stats.Deaths + 1
		profiles[victim].Dirty = true
	end
end

-- Итоги матча: участие, тройка лучших, победа
function ProgressionSystem.MatchRewards(results)
	local out = {}
	for rank, row in ipairs(results.Players) do
		if not row.IsBot then
			local player = Players:GetPlayerByUserId(row.UserId)
			if player and profiles[player] then
				local lines = { { Text = "MATCH COMPLETE", Xp = PC.Xp.Match, Coins = PC.Coins.Match } }
				local won = (results.WinnerTeam and row.Team == results.WinnerTeam) or (not results.WinnerTeam and results.WinnerUserId == row.UserId)
				if won then
					table.insert(lines, { Text = "VICTORY", Xp = PC.Xp.Win, Coins = PC.Coins.Win })
				end
				if rank <= 3 and #results.Players >= 3 and not results.WinnerTeam then
					table.insert(lines, { Text = "TOP 3", Xp = PC.Xp.TopThree, Coins = PC.Coins.TopThree })
				end
				local xp, coins = 0, 0
				for _, l in ipairs(lines) do
					xp, coins = xp + l.Xp, coins + l.Coins
				end
				local d = profiles[player].Data
				d.Stats.Matches = d.Stats.Matches + 1
				if won then
					d.Stats.Wins = d.Stats.Wins + 1
				end
				local ups = ProgressionSystem.Grant(player, xp, coins)
				out[player] = { Lines = lines, Xp = xp, Coins = coins, LevelUps = ups, Won = won, Rank = rank }
				if net then
					net.Fire(player, "Rewards", out[player])
				end
				push(player)
				task.spawn(save, player)
			end
		end
	end
	return out
end

-------------------------------------------------------------------------------
-- Магазин и снаряжение
-------------------------------------------------------------------------------
local function catalog(category)
	if category == "Weapon" then
		return PC.Weapons, "Weapons"
	elseif category == "Skin" then
		return PC.Skins, "Skins"
	end
	return nil
end

-- Купить. Возвращает true или false и причину
function ProgressionSystem.Buy(player, category, id)
	local d = ProgressionSystem.Get(player)
	local items, bucket = catalog(category)
	local item = items and items[id]
	if not (d and item) or item.Hidden then
		return false, "Unknown"
	end
	if d.Owned[bucket][id] then
		return false, "Owned"
	end
	if d.Level < (item.Level or 1) then
		return false, "Level"
	end
	if d.Coins < item.Price then
		return false, "Coins"
	end
	d.Coins = d.Coins - item.Price
	d.Owned[bucket][id] = true
	profiles[player].Dirty = true
	push(player)
	return true
end

function ProgressionSystem.EquipItem(player, slot, id)
	local d = ProgressionSystem.Get(player)
	if not d then
		return false
	end
	if slot == "Primary" and d.Owned.Weapons[id] and PC.Weapons[id] and not PC.Weapons[id].Hidden then
		d.Loadout.Primary = id
	elseif slot == "Skin" and d.Owned.Skins[id] and PC.Skins[id] and not PC.Skins[id].Hidden then
		d.Loadout.Skin = id
	else
		return false
	end
	profiles[player].Dirty = true
	push(player)
	return true
end

function ProgressionSystem.SaveSettings(player, settings)
	local d = ProgressionSystem.Get(player)
	if not d then
		return
	end
	for k, v in pairs(settings) do
		if d.Settings[k] ~= nil then
			d.Settings[k] = v
		end
	end
	profiles[player].Dirty = true
end

-- Окраска персонажа: текстура частей тела
function ProgressionSystem.ApplySkin(model, skinId)
	local tex = SkinAssets[skinId] or SkinAssets.Classic
	for _, name in ipairs(BODY_PARTS) do
		local p = model:FindFirstChild(name)
		if p and p:IsA("MeshPart") then
			p.TextureID = tex
		end
	end
	model:SetAttribute("Skin", skinId)
end

-- Какая окраска нужна персонажу: в командном режиме — цвет команды, иначе — выбранная
function ProgressionSystem.SkinFor(key)
	local p = match and match.Participant(key)
	if p and p.InMatch and p.Team ~= "" then
		return p.Team == "Red" and "TeamRed" or "TeamBlue"
	end
	local d = typeof(key) == "Instance" and ProgressionSystem.Get(key)
	return d and d.Loadout.Skin or (type(key) == "table" and key.Skin) or "Classic"
end

-------------------------------------------------------------------------------
function ProgressionSystem.Init(context)
	net = context.Get("NetService")
	characters = context.Get("CharacterSystem")
	local ok, s = pcall(DataStoreService.GetDataStore, DataStoreService, PC.DataStore)
	if ok then
		store = s
	else
		log:Warn("DataStore недоступен: %s — профили без сохранения", tostring(s))
	end
end

function ProgressionSystem.Start(context)
	match = context.Get("MatchSystem")
	match.Kill:Connect(onKill)
	match.MatchEnded:Connect(ProgressionSystem.MatchRewards)
	characters.CharacterSpawned:Connect(function(player, character)
		ProgressionSystem.ApplySkin(character, ProgressionSystem.SkinFor(player))
	end)
	net.Connect("Buy", function(player, category, id)
		local ok, why = ProgressionSystem.Buy(player, category, id)
		net.Fire(player, "ShopResult", { Ok = ok, Reason = why, Category = category, Id = id })
	end)
	net.Connect("EquipItem", function(player, slot, id)
		ProgressionSystem.EquipItem(player, slot, id)
		-- в лобби — сразу видно на своём манекене
		local character = player.Character
		if slot == "Skin" and character and not (match.Participant(player) and match.Participant(player).InMatch) then
			ProgressionSystem.ApplySkin(character, ProgressionSystem.SkinFor(player))
		end
	end)
	net.Connect("SaveSettings", function(player, settings)
		ProgressionSystem.SaveSettings(player, settings)
	end)
	net.Connect("RequestProfile", function(player)
		push(player)
	end)
	Players.PlayerAdded:Connect(load)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(load, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		save(player)
		profiles[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(PC.AutosaveEvery)
			for player, p in pairs(profiles) do
				if p.Dirty then
					task.spawn(save, player)
				end
			end
		end
	end)
	if not RunService:IsStudio() then
		game:BindToClose(function()
			for player in pairs(profiles) do
				save(player)
			end
		end)
	end
end

return ProgressionSystem
