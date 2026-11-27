-- MovementSystem: стойка (стоя / присед) и бег на сервере.
--
-- Клиент управляет своим персонажем сам (физика у владельца), а серверу сообщает состояние событием
-- MoveState { Stance, Sprint, Aim }. Сервер:
--   • ставит скорость Humanoid.WalkSpeed по общим правилам (Shared/MovementRules; клиент делает то же
--     самое у себя сразу, без ожидания — это предсказание; сервер подтверждает);
--   • бег в приседе и с прицелом невозможен: такой Sprint сервер игнорирует; с прицелом (оружие у глаза,
--     этап 4) персонаж идёт медленнее;
--   • пишет атрибуты персонажа Stance и Sprinting — их видят все клиенты (интерфейс, звуки шагов,
--     а на этапах 4–5 — разброс оружия и зоны попаданий).
-- Высоту приседа (HipHeight) клиент меняет плавно сам: её видят все через положение персонажа.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Logger = require(Shared:WaitForChild("Logger"))
local MovementRules = require(Shared:WaitForChild("MovementRules"))

local MovementSystem = { Name = "MovementSystem" }

local log = Logger.new("Movement")

local function aliveHumanoid(character)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		return humanoid
	end
	return nil
end

-- Применить состояние к персонажу игрока. Возвращает итоговые (stance, sprint) или nil
function MovementSystem.Apply(player, state)
	local character = player.Character
	local humanoid = aliveHumanoid(character)
	if not humanoid then
		return nil
	end
	local aim = state.Aim == true
	local stance, sprint = MovementRules.Resolve(state.Stance, state.Sprint and not aim)
	humanoid.WalkSpeed = MovementRules.SpeedFor(stance, sprint, aim)
	if character:GetAttribute("Stance") ~= stance then
		character:SetAttribute("Stance", stance)
	end
	if character:GetAttribute("Sprinting") ~= sprint then
		character:SetAttribute("Sprinting", sprint)
	end
	if character:GetAttribute("Aiming") ~= aim then
		character:SetAttribute("Aiming", aim)
	end
	return stance, sprint
end

function MovementSystem.GetState(player)
	local character = player.Character
	if not character then
		return nil
	end
	return {
		Stance = character:GetAttribute("Stance") or "Stand",
		Sprint = character:GetAttribute("Sprinting") == true,
		Aim = character:GetAttribute("Aiming") == true,
	}
end

function MovementSystem.Start(context)
	context.Get("NetService").Connect("MoveState", function(player, state)
		if not MovementSystem.Apply(player, state) then
			log:Debug("MoveState от %s без живого персонажа — пропущено", player.Name)
		end
	end)
	-- новый персонаж всегда начинает стоя и шагом
	context.Get("CharacterSystem").CharacterSpawned:Connect(function(player)
		MovementSystem.Apply(player, { Stance = "Stand", Sprint = false })
	end)
end

return MovementSystem
