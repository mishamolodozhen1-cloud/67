-- CharacterController: управление своим манекеном — бег, присед, прыжок.
--
-- Управление:
--   ПК       Shift (держать) — бег; C — присед (вкл/выкл), Ctrl (держать) — присед; Пробел — прыжок
--   Геймпад  L3 — бег (вкл/выкл), B — присед (вкл/выкл), A — прыжок
--   Телефон  кнопки «RUN» и «CROUCH» (Controllers/TouchControls) и стандартная кнопка прыжка
--
-- Правила (Shared/MovementRules — те же, что на сервере):
--   • бег — только стоя и только вперёд (не дальше ~53° от взгляда), в воздухе скорость сохраняется;
--   • присед плавно опускает персонажа (HipHeight) за StanceTime; встать нельзя, если над головой
--     нет места — персонаж остаётся в приседе, пока не выйдет из-под препятствия;
--   • прыжок из приседа сначала поднимает персонажа; после приземления — пауза JumpCooldown;
--   • пока персонаж лежит тряпичной куклой (атрибут Ragdolled), управление ничего не делает.
-- Скорость клиент ставит сразу (предсказание), а серверу сообщает состояние (MoveState) — сервер
-- ставит ту же скорость и атрибуты Stance / Sprinting, которые видят все.
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Logger = require(Shared:WaitForChild("Logger"))
local Signal = require(Shared:WaitForChild("Signal"))
local MovementRules = require(Shared:WaitForChild("MovementRules"))
local GameConfig = require(ReplicatedStorage:WaitForChild("Configs"):WaitForChild("GameConfig"))

local CharacterController = { Name = "CharacterController" }

CharacterController.StateChanged = Signal.new() -- (state) — стойка или бег изменились
CharacterController.CharacterChanged = Signal.new() -- (character, humanoid) — новый персонаж

local log = Logger.new("Character")
local cfg = GameConfig.Movement

local net = nil
local state = { Stance = "Stand", Sprint = false }
local wants = { CrouchToggle = false, CrouchHold = false, SprintHold = false, SprintToggle = false }
local character, humanoid, root = nil, nil, nil
local lastSent = nil
local landedAt = -math.huge
local overlap = OverlapParams.new()
overlap.FilterType = Enum.RaycastFilterType.Exclude
overlap.RespectCanCollide = true

function CharacterController.GetState()
	return { Stance = state.Stance, Sprint = state.Sprint }
end

function CharacterController.GetCharacter()
	return character, humanoid, root
end

function CharacterController.WantsCrouch()
	return wants.CrouchToggle or wants.CrouchHold
end

function CharacterController.SprintToggled()
	return wants.SprintToggle
end

function CharacterController.ToggleCrouch()
	wants.CrouchToggle = not wants.CrouchToggle
	if wants.CrouchToggle then
		wants.SprintToggle = false
	end
end

function CharacterController.SetSprintToggle(on)
	wants.SprintToggle = on == true
	if wants.SprintToggle then
		wants.CrouchToggle = false
	end
end

-- Есть ли место, чтобы встать: свободна ли полоса над головой высотой CrouchDrop (+ запас)
function CharacterController.CanStand()
	if not (root and character) then
		return true
	end
	local drop = math.max(0, MovementRules.StandHipHeight - humanoid.HipHeight)
	if drop < 0.01 then
		return true
	end
	local height = drop + cfg.StandClearance
	local center = root.CFrame * CFrame.new(0, MovementRules.TopAboveRoot + height / 2, 0)
	overlap.FilterDescendantsInstances = { character }
	local parts = workspace:GetPartBoundsInBox(center, Vector3.new(1.6, height, 1.0), overlap)
	return #parts == 0
end

local function alive()
	return humanoid and humanoid.Health > 0 and root and root.Parent
end

-- Лежит ли персонаж тряпичной куклой (атрибут ставит сервер, RagdollSystem)
function CharacterController.IsRagdolled()
	return character ~= nil and character:GetAttribute("Ragdolled") == true
end

-- Чего хочет игрок сейчас (с учётом правил): стойка и бег
local function desired()
	local stance = CharacterController.WantsCrouch() and "Crouch" or "Stand"
	if stance == "Stand" and state.Stance == "Crouch" and not CharacterController.CanStand() then
		stance = "Crouch" -- над головой препятствие: остаёмся в приседе
	end
	local wantSprint = wants.SprintHold or wants.SprintToggle
	local sprint = false
	if wantSprint and stance == "Stand" then
		local airborne = humanoid.FloorMaterial == Enum.Material.Air
		if airborne then
			sprint = state.Sprint -- в прыжке бег не включается и не выключается
		else
			sprint = MovementRules.IsForward(humanoid.MoveDirection, root.CFrame.LookVector)
		end
	end
	return MovementRules.Resolve(stance, sprint)
end

local function send()
	if not net then
		return
	end
	if lastSent and lastSent.Stance == state.Stance and lastSent.Sprint == state.Sprint then
		return
	end
	-- если лимит не пустил — попробуем в следующем кадре (lastSent не меняется)
	if net.Fire("MoveState", { Stance = state.Stance, Sprint = state.Sprint }) then
		lastSent = { Stance = state.Stance, Sprint = state.Sprint }
	end
end

local function update(dt)
	if not alive() or CharacterController.IsRagdolled() then
		-- в регдолле телом управляет физика сервера: ни скорости, ни приседа, ни сообщений серверу
		return
	end
	local stance, sprint = desired()
	if stance ~= state.Stance or sprint ~= state.Sprint then
		state.Stance, state.Sprint = stance, sprint
		humanoid.WalkSpeed = MovementRules.SpeedFor(stance, sprint)
		-- в приседе прыгать нельзя (прыжок сначала поднимает); отключение снимается после подъёма
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, stance == "Stand" and os.clock() - landedAt >= cfg.JumpCooldown)
		CharacterController.StateChanged:Fire(CharacterController.GetState())
	end
	-- плавный присед / подъём
	local target = MovementRules.HipHeight(state.Stance)
	local current = humanoid.HipHeight
	if math.abs(target - current) > 0.001 then
		local stepSize = MovementRules.CrouchDrop / math.max(0.05, cfg.StanceTime) * dt
		humanoid.HipHeight = current + math.clamp(target - current, -stepSize, stepSize)
	end
	-- пауза между прыжками
	if state.Stance == "Stand" and os.clock() - landedAt >= cfg.JumpCooldown and not humanoid:GetStateEnabled(Enum.HumanoidStateType.Jumping) then
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
	end
	send()
end

local function onCharacter(newCharacter)
	character = newCharacter
	humanoid = newCharacter:WaitForChild("Humanoid", 10)
	root = newCharacter:WaitForChild("HumanoidRootPart", 10)
	if not (humanoid and root) then
		log:Error("у персонажа нет Humanoid или HumanoidRootPart")
		character, humanoid, root = nil, nil, nil
		return
	end
	-- новый персонаж: стоя, шагом
	state.Stance, state.Sprint = "Stand", false
	wants.CrouchToggle, wants.CrouchHold, wants.SprintToggle = false, false, false
	lastSent = { Stance = "Stand", Sprint = false }
	humanoid.HipHeight = MovementRules.StandHipHeight
	humanoid.WalkSpeed = MovementRules.SpeedFor("Stand", false)
	humanoid.StateChanged:Connect(function(_, new)
		if new == Enum.HumanoidStateType.Landed then
			landedAt = os.clock()
			humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
		end
	end)
	-- упал (регдолл, физику считает сервер) / встал (физика снова у клиента): состояние Humanoid у себя
	-- тоже меняем, чтобы после подъёма персонаж не остался «ватным», а скорость и высота были как до падения
	local myCharacter, myHumanoid = character, humanoid
	myCharacter:GetAttributeChangedSignal("Ragdolled"):Connect(function()
		if myHumanoid.Health <= 0 then
			return
		end
		if myCharacter:GetAttribute("Ragdolled") == true then
			myHumanoid:ChangeState(Enum.HumanoidStateType.Physics)
		else
			myHumanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
			myHumanoid.WalkSpeed = MovementRules.SpeedFor(state.Stance, state.Sprint)
			lastSent = nil -- сообщить серверу состояние заново
		end
	end)
	CharacterController.CharacterChanged:Fire(character, humanoid)
	CharacterController.StateChanged:Fire(CharacterController.GetState())
end

local function onSprint(_, inputState, input)
	local began = inputState == Enum.UserInputState.Begin
	if input.KeyCode == Enum.KeyCode.ButtonL3 then
		if began then
			CharacterController.SetSprintToggle(not wants.SprintToggle)
		end
	elseif inputState == Enum.UserInputState.Begin or inputState == Enum.UserInputState.End then
		wants.SprintHold = began
		if began then
			wants.CrouchToggle = false
		end
	end
	return Enum.ContextActionResult.Sink
end

local function onCrouch(_, inputState, input)
	local began = inputState == Enum.UserInputState.Begin
	if input.KeyCode == Enum.KeyCode.LeftControl then
		if inputState == Enum.UserInputState.Begin or inputState == Enum.UserInputState.End then
			wants.CrouchHold = began
		end
	elseif began then
		CharacterController.ToggleCrouch()
	end
	return Enum.ContextActionResult.Sink
end

function CharacterController.Init(context)
	net = context.Get("ClientNet")
end

function CharacterController.Start()
	local player = Players.LocalPlayer
	ContextActionService:BindAction("DC_Sprint", onSprint, false, Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonL3)
	ContextActionService:BindAction("DC_Crouch", onCrouch, false, Enum.KeyCode.C, Enum.KeyCode.LeftControl, Enum.KeyCode.ButtonB)
	-- прыжок из приседа: сначала встать (если есть место)
	UserInputService.JumpRequest:Connect(function()
		if alive() and state.Stance == "Crouch" then
			wants.CrouchToggle, wants.CrouchHold = false, false
		end
	end)
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
	RunService.Heartbeat:Connect(update)
end

return CharacterController
