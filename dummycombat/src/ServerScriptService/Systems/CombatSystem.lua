-- CombatSystem: урон, здоровье и убийства (этап 5). Всё считает сервер.
--
-- Попадание (WeaponSystem.HitConfirmed) → урон по зоне тела (голова, корпус, руки, ноги — GameConfig.Combat.Zones)
-- из характеристик оружия (WeaponConfig.Damage), со спадом по расстоянию (Falloff). Урон не проходит:
--   • по себе и по тем, кого правила матча защищают (свой в командном режиме) — правило задаёт MatchSystem
--     через SetRules;
--   • сразу после появления (SpawnProtection), пока защищённый сам не выстрелит.
-- Здоровье восстанавливается через RegenDelay секунд без урона.
-- Убийство: смертельный урон → Humanoid.Health = 0 (регдолл и возрождение — RagdollSystem / CharacterSystem).
-- Убийца — кто ранил последним (не раньше KillCredit секунд назад); помощь — кто нанёс за AssistWindow
-- секунд не меньше AssistDamage. Сигнал Killed — для счёта матча, опыта и наград; всем игрокам — KillFeed,
-- убийце, помощникам и погибшему — Eliminated; раненому — Damaged (откуда стреляли, для индикатора).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Configs = ReplicatedStorage:WaitForChild("Configs")
local Logger = require(Shared:WaitForChild("Logger"))
local Signal = require(Shared:WaitForChild("Signal"))
local GameConfig = require(Configs:WaitForChild("GameConfig"))
local WeaponConfig = require(Configs:WaitForChild("WeaponConfig"))

local CombatSystem = { Name = "CombatSystem" }

CombatSystem.Damaged = Signal.new() -- (victimModel, amount, info)
CombatSystem.Killed = Signal.new() -- (kill) kill = { Victim, VictimPlayer, Killer, Weapon, Headshot, Assists, Position, Cause }

local log = Logger.new("Combat")
local cfg = GameConfig.Combat

local net = nil
local records = setmetatable({}, { __mode = "k" }) -- модель → { Damage = { [player] = { Amount, At } }, LastAttacker, LastAt, LastHit }
local rules = { CanDamage = nil }

local function now()
	return workspace:GetServerTimeNow()
end

local function isPlayer(p)
	return typeof(p) == "Instance" and p:IsA("Player")
end

-- Нападающий — игрок (Player) или бот (таблица { Name, UserId, IsBot = true, Model } от BotSystem)
local function stillHere(a)
	if isPlayer(a) then
		return a.Parent == Players
	end
	return type(a) == "table" and a.Active ~= false
end

local function characterOf(a)
	if isPlayer(a) then
		return a.Character
	end
	return type(a) == "table" and a.Model or nil
end
CombatSystem.CharacterOf = characterOf

local function displayName(model, player)
	if player then
		return player.DisplayName ~= "" and player.DisplayName or player.Name
	end
	return model and model.Name or "?"
end

-- Правила матча: { CanDamage = function(attackerPlayer, victimModel, victimPlayer) -> bool }
function CombatSystem.SetRules(r)
	rules = r or {}
end

function CombatSystem.Zone(partName)
	return cfg.Zones[partName] or "Torso"
end

-- Урон оружия weaponName по зоне zone на расстоянии distance
function CombatSystem.WeaponDamage(weaponName, zone, distance)
	local def = WeaponConfig.Weapons[weaponName]
	if not def or not def.Damage then
		return 0
	end
	local base = def.Damage[zone] or def.Damage.Torso
	local f = def.Falloff
	local k = 1
	if f and distance and distance > f.Start then
		local t = math.clamp((distance - f.Start) / math.max(f.End - f.Start, 1), 0, 1)
		k = 1 + (f.Min - 1) * t
	end
	return base * k
end

function CombatSystem.IsProtected(model)
	local untilT = model:GetAttribute("ProtectedUntil")
	return type(untilT) == "number" and now() < untilT
end

function CombatSystem.Protect(model, seconds)
	model:SetAttribute("ProtectedUntil", now() + seconds)
end

function CombatSystem.Unprotect(model)
	if model:GetAttribute("ProtectedUntil") then
		model:SetAttribute("ProtectedUntil", 0)
	end
end

local function record(model)
	local r = records[model]
	if not r then
		r = { Damage = {}, LastAttacker = nil, LastAt = -math.huge, LastHit = -math.huge }
		records[model] = r
	end
	return r
end

-- Кто убил и кто помог
local function credit(model, finalAttacker)
	local r = record(model)
	local t = now()
	local killer = finalAttacker
	if not killer and r.LastAttacker and t - r.LastAt <= cfg.KillCredit and stillHere(r.LastAttacker) then
		killer = r.LastAttacker
	end
	local assists = {}
	for p, d in pairs(r.Damage) do
		if p ~= killer and stillHere(p) and t - d.At <= cfg.AssistWindow and d.Amount >= cfg.AssistDamage then
			table.insert(assists, p)
		end
	end
	return killer, assists
end

-- Нанести урон. info: { Attacker (Player|nil), Weapon, Part (имя части), Headshot, Position (Vector3), Origin (Vector3),
-- Cause ("Weapon" | "Explosion" | ...) }. Возвращает фактический урон и true, если это был смертельный удар
function CombatSystem.Damage(model, amount, info)
	info = info or {}
	local humanoid = model and model:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 or amount <= 0 then
		return 0, false
	end
	local victimPlayer = Players:GetPlayerFromCharacter(model)
	local attacker = info.Attacker
	if attacker and (victimPlayer == attacker or characterOf(attacker) == model) then
		if info.Cause == "Weapon" then
			return 0, false -- в себя из оружия не попасть
		end
	elseif attacker and rules.CanDamage and not rules.CanDamage(attacker, model, victimPlayer) then
		return 0, false
	end
	if CombatSystem.IsProtected(model) then
		return 0, false
	end
	local before = humanoid.Health
	local dealt = math.min(before, amount)
	local r = record(model)
	local t = now()
	r.LastHit = t
	if attacker and attacker ~= victimPlayer and characterOf(attacker) ~= model then
		local d = r.Damage[attacker]
		if not d or t - d.At > cfg.AssistWindow then
			d = { Amount = 0, At = t }
			r.Damage[attacker] = d
		end
		d.Amount = d.Amount + dealt
		d.At = t
		r.LastAttacker, r.LastAt = attacker, t
	end
	local lethal = before - amount <= 0
	CombatSystem.Damaged:Fire(model, dealt, info)
	if victimPlayer and net then
		net.Fire(victimPlayer, "Damaged", {
			Amount = math.floor(dealt + 0.5),
			From = info.Origin,
			Health = math.max(0, before - amount),
		})
	end
	if lethal then
		local selfKill = attacker ~= nil and (attacker == victimPlayer or characterOf(attacker) == model)
		local killer, assists = credit(model, (attacker and not selfKill) and attacker or nil)
		local kill = {
			Victim = model,
			VictimPlayer = victimPlayer,
			Killer = killer,
			Weapon = info.Weapon,
			Headshot = info.Headshot == true,
			Assists = assists,
			Position = info.Position,
			Cause = info.Cause or "Weapon",
		}
		records[model] = nil
		humanoid.Health = 0
		CombatSystem.Killed:Fire(kill)
		if net then
			local weaponName = kill.Weapon and WeaponConfig.Weapons[kill.Weapon] and WeaponConfig.Weapons[kill.Weapon].DisplayName or (kill.Cause == "Explosion" and "EXPLOSION" or "")
			local killerName = killer and displayName(nil, killer) or ""
			local victimName = displayName(model, victimPlayer)
			net.FireAll("KillFeed", {
				Killer = killerName,
				KillerId = killer and killer.UserId or 0,
				Victim = victimName,
				VictimId = victimPlayer and victimPlayer.UserId or 0,
				Weapon = weaponName,
				Headshot = kill.Headshot,
			})
			if killer and isPlayer(killer) then
				net.Fire(killer, "Eliminated", { Role = "Killer", Name = victimName, Headshot = kill.Headshot, Weapon = weaponName })
			end
			for _, p in ipairs(assists) do
				if isPlayer(p) then
					net.Fire(p, "Eliminated", { Role = "Assist", Name = victimName })
				end
			end
			if victimPlayer then
				net.Fire(victimPlayer, "Eliminated", {
					Role = "Victim",
					Name = killerName,
					Weapon = weaponName,
					Headshot = kill.Headshot,
					Respawn = GameConfig.Character.RespawnDelay,
					From = killer and characterOf(killer) and characterOf(killer):FindFirstChild("Head") and characterOf(killer).Head.Position or nil,
				})
			end
		end
		log:Debug("%s → %s (%s%s)", killer and tostring(killer.Name) or "—", displayName(model, victimPlayer), tostring(kill.Weapon), kill.Headshot and ", в голову" or "")
	else
		humanoid.Health = before - amount
	end
	return dealt, lethal
end

-- Попадание из оружия (сигнал WeaponSystem.HitConfirmed): урон по зоне со спадом по расстоянию.
-- Записывает в hit.Damage и hit.Killed (WeaponSystem отправит их стрелку вместе с подтверждением)
function CombatSystem.OnHit(player, hit)
	local zone = CombatSystem.Zone(hit.Part.Name)
	local amount = CombatSystem.WeaponDamage(hit.Weapon, zone, hit.Distance)
	local origin = hit.Position - hit.Direction * hit.Distance
	local dealt, lethal = CombatSystem.Damage(hit.Target, amount, {
		Attacker = player,
		Weapon = hit.Weapon,
		Part = hit.Part.Name,
		Headshot = zone == "Head",
		Position = hit.Position,
		Origin = origin,
		Cause = "Weapon",
	})
	hit.Damage = dealt
	hit.Killed = lethal
	return dealt, lethal
end

local extraRegen = {} -- модели ботов, которым тоже восстанавливается здоровье

function CombatSystem.TrackRegen(model)
	extraRegen[model] = true
end

local function regen(dt)
	local t = now()
	local list = {}
	for _, player in ipairs(Players:GetPlayers()) do
		table.insert(list, player.Character)
	end
	for model in pairs(extraRegen) do
		if model.Parent then
			table.insert(list, model)
		else
			extraRegen[model] = nil
		end
	end
	for _, character in ipairs(list) do
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 and humanoid.Health < humanoid.MaxHealth then
			local r = records[character]
			if not r or t - r.LastHit >= cfg.RegenDelay then
				humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + cfg.RegenRate * dt)
			end
		end
	end
end

function CombatSystem.Init(context)
	net = context.Get("NetService")
end

function CombatSystem.Start(context)
	local weapons = context.Get("WeaponSystem")
	local characters = context.Get("CharacterSystem")
	weapons.HitConfirmed:Connect(CombatSystem.OnHit)
	weapons.ShotFired:Connect(function(player)
		local character = characterOf(player)
		if character then
			CombatSystem.Unprotect(character) -- выстрелил — защита после появления снята
		end
	end)
	characters.CharacterSpawned:Connect(function(_, character)
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.MaxHealth = cfg.MaxHealth
			humanoid.Health = cfg.MaxHealth
		end
		records[character] = nil
		CombatSystem.Protect(character, cfg.SpawnProtection)
	end)
	RunService.Heartbeat:Connect(regen)
end

return CombatSystem
