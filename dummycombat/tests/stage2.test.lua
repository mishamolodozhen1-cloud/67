-- Проверка этапа 2 DUMMY COMBAT на сервере Roblox (Open Cloud): python3 tools/cloud.py test 2
-- Персонаж-манекен: сборка из загруженной модели, суставы, столкновения, анимации; передвижение:
-- правила скоростей, событие MoveState (проверка аргументов), логика клиентских контроллеров.
-- Живого клиента нет: камера, ввод и проигрывание анимаций проверяются в Studio (см. README).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")

local results, notes = {}, {}
local function note(s)
	table.insert(notes, s)
end
local function test(name, fn)
	local ok, err = pcall(fn)
	table.insert(results, { Name = name, Ok = ok, Err = err })
end
local function expect(cond, msg)
	if not cond then
		error(msg or "условие не выполнено", 2)
	end
end
local function eq(actual, expected, msg)
	if actual ~= expected then
		error(string.format("%s: ждали %s, получили %s", msg or "", tostring(expected), tostring(actual)), 2)
	end
end
local function near(a, b, eps, msg)
	if math.abs(a - b) > (eps or 1e-3) then
		error(string.format("%s: ждали %.4f, получили %.4f", msg or "", b, a), 2)
	end
end

local Configs = ReplicatedStorage.Configs
local GameConfig = require(Configs.GameConfig)
local DummyRig = require(Configs.DummyRig)
local DummyAssets = require(Configs.DummyAssets)
local MovementRules = require(ReplicatedStorage.Shared.MovementRules)

local JOINTS = { "Root", "Waist", "Neck", "LeftShoulder", "LeftElbow", "LeftWrist", "RightShoulder", "RightElbow", "RightWrist",
	"LeftHip", "LeftKnee", "LeftAnkle", "RightHip", "RightKnee", "RightAnkle" }

test("настройки плейса", function()
	eq(Players.CharacterAutoLoads, false, "CharacterAutoLoads")
	eq(StarterPlayer.CameraMode, Enum.CameraMode.LockFirstPerson, "CameraMode")
	eq(StarterPlayer.CharacterUseJumpPower, false, "CharacterUseJumpPower")
	near(StarterPlayer.CharacterJumpHeight, GameConfig.Movement.JumpHeight, 1e-3, "CharacterJumpHeight")
	near(StarterPlayer.CharacterWalkSpeed, GameConfig.Movement.WalkSpeed, 1e-3, "CharacterWalkSpeed")
	eq(StarterPlayer.AutoJumpEnabled, false, "AutoJumpEnabled")
	eq(StarterPlayer.LoadCharacterAppearance, false, "LoadCharacterAppearance")
	eq(StarterPlayer.EnableMouseLockOption, false, "EnableMouseLockOption")
	expect(StarterPlayer.StarterCharacterScripts:FindFirstChild("Animate"), "нет своего Animate в StarterCharacterScripts")
	eq(StarterPlayer.StarterCharacterScripts.Animate.ClassName, "LocalScript", "Animate")
end)

local Bootstrap = require(ServerScriptService.Server.Bootstrap)
local report = Bootstrap.Start()

test("запуск: сервисы и системы", function()
	eq(report.State, "Ready", "состояние сервера")
	for _, name in ipairs({ "ErrorService", "NetService", "PlayerService", "CharacterSystem", "MovementSystem" }) do
		eq(report.Status[name], "Started", name)
	end
	note(string.format("запуск сервера с манекеном: %.2f с", report.Seconds or -1))
end)

local CharacterSystem = Bootstrap.Get("CharacterSystem")
local MovementSystem = Bootstrap.Get("MovementSystem")
local Net = Bootstrap.Get("NetService")

test("манекен: части, сетки, текстура, столкновения", function()
	local model = StarterPlayer:FindFirstChild("StarterCharacter")
	expect(model and model:IsA("Model"), "нет StarterPlayer.StarterCharacter")
	expect(not CharacterSystem.UsedFallback(), "манекен собран из запасных деталей — модель не загрузилась")
	expect(ServerStorage.CharacterAssets:FindFirstChild("Dummy"), "нет копии в ServerStorage.CharacterAssets")
	local root = model:FindFirstChild("HumanoidRootPart")
	expect(root and model.PrimaryPart == root, "HumanoidRootPart / PrimaryPart")
	eq(root.Transparency, 1, "HumanoidRootPart.Transparency")
	eq(root.CanQuery, false, "HumanoidRootPart.CanQuery (лучи должны попадать в тело, а не в коробку)")
	eq(root.CanCollide, true, "HumanoidRootPart.CanCollide")
	local count = 0
	for _, spec in ipairs(DummyRig.Parts) do
		local p = model:FindFirstChild(spec.Name)
		expect(p, "нет части " .. spec.Name)
		eq(p.ClassName, "MeshPart", spec.Name)
		expect(p.TextureID ~= "", spec.Name .. ": нет текстуры")
		eq(p.CanCollide, spec.Collide, spec.Name .. ".CanCollide")
		eq(p.CanQuery, true, spec.Name .. ".CanQuery")
		eq(p.Anchored, false, spec.Name .. ".Anchored")
		expect((p.Size - spec.Size).Magnitude < 1e-3, spec.Name .. ": размер не совпадает со скелетом")
		count = count + 1
	end
	eq(count, 15, "частей тела")
	local hum = model:FindFirstChildOfClass("Humanoid")
	eq(hum.RigType, Enum.HumanoidRigType.R15, "RigType")
	near(hum.HipHeight, DummyRig.HipHeight, 1e-3, "HipHeight")
	expect(hum:FindFirstChildOfClass("Animator"), "нет Animator")
	eq(#CharacterSystem.Inspect(model), 0, "Inspect: " .. table.concat(CharacterSystem.Inspect(model), "; "))
	for _, name in ipairs({ "RightGripAttachment", "LeftGripAttachment", "HatAttachment", "BodyBackAttachment" }) do
		expect(model:FindFirstChild(name, true), "нет точки крепления " .. name)
	end
end)

test("манекен: суставы R15 на своих местах", function()
	local model = StarterPlayer.StarterCharacter
	local found = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Motor6D") then
			found[d.Name] = d
		end
	end
	for _, name in ipairs(JOINTS) do
		local m = found[name]
		expect(m, "нет сустава " .. name)
		-- в позе покоя Part0 * C0 = Part1 * C1 (точка сустава совпадает с обеих сторон)
		local a = m.Part0.CFrame * m.C0
		local b = m.Part1.CFrame * m.C1
		expect((a.Position - b.Position).Magnitude < 1e-3, name .. ": точки сустава не совпадают")
		eq(m.Parent, m.Part1, name .. ": Motor6D лежит не в дочерней части")
	end
	eq(found.Root.Part0.Name, "HumanoidRootPart", "Root.Part0")
	eq(found.LeftKnee.Part1.Name, "LeftLowerLeg", "LeftKnee.Part1")
	-- рост: от низа стоп до макушки
	local _, size = model:GetBoundingBox()
	near(size.Y, DummyRig.Height, 0.06, "рост манекена")
end)

test("анимации: все 13 загружаются, позы совпадают со скелетом", function()
	local parts = { HumanoidRootPart = true }
	for _, spec in ipairs(DummyRig.Parts) do
		parts[spec.Name] = true
	end
	local n = 0
	for name, def in pairs(DummyAssets.Animations) do
		local ok, ks = pcall(KeyframeSequenceProvider.GetKeyframeSequenceAsync, KeyframeSequenceProvider, def.Id)
		expect(ok and ks, name .. ": не загрузилась (" .. tostring(ks) .. ")")
		local frames = ks:GetKeyframes()
		expect(#frames >= 10, name .. ": мало кадров")
		near(frames[#frames].Time, def.Length, 0.01, name .. ": длина")
		eq(ks.Loop, def.Loop, name .. ".Loop")
		local poses = {}
		for _, p in ipairs(frames[1]:GetDescendants()) do
			if p:IsA("Pose") then
				expect(parts[p.Name], name .. ": поза для неизвестной части " .. p.Name)
				poses[p.Name] = true
			end
		end
		for part in pairs(parts) do
			expect(poses[part], name .. ": нет позы для " .. part)
		end
		if def.Natural > 0 then
			-- шаги отмечены для звуков шагов
			local steps = 0
			for _, f in ipairs(frames) do
				for _, m in ipairs(f:GetChildren()) do
					if m:IsA("KeyframeMarker") and m.Name == "Step" then
						steps = steps + 1
					end
				end
			end
			expect(steps >= 2, name .. ": нет меток шагов")
		end
		n = n + 1
	end
	eq(n, 13, "анимаций")
	-- аниматор манекена принимает их (на сервере Roblox их не проигрывает, но загрузка проверяет формат)
	local dummy = StarterPlayer.StarterCharacter:Clone()
	dummy.Parent = workspace
	local animator = dummy.Humanoid.Animator
	local anim = Instance.new("Animation")
	anim.AnimationId = DummyAssets.Animations.WalkF.Id
	local track = animator:LoadAnimation(anim)
	expect(track, "Animator:LoadAnimation")
	dummy:Destroy()
end)

test("правила передвижения", function()
	local mv = GameConfig.Movement
	eq(MovementRules.SpeedFor("Stand", false), mv.WalkSpeed, "шаг")
	eq(MovementRules.SpeedFor("Stand", true), mv.SprintSpeed, "бег")
	eq(MovementRules.SpeedFor("Crouch", false), mv.CrouchSpeed, "присед")
	eq(MovementRules.SpeedFor("Crouch", true), mv.CrouchSpeed, "бег в приседе невозможен")
	local s, r = MovementRules.Resolve("Fly", true)
	expect(s == "Stand" and r == true, "неизвестная стойка — стоя")
	near(MovementRules.HipHeight("Crouch"), DummyRig.HipHeight - DummyAssets.CrouchDrop, 1e-6, "HipHeight в приседе")
	expect(MovementRules.IsCrouchedHip(MovementRules.CrouchHipHeight) and not MovementRules.IsCrouchedHip(MovementRules.StandHipHeight), "IsCrouchedHip")
	local look = Vector3.new(0, 0, -1)
	expect(MovementRules.IsForward(Vector3.new(0, 0, -1), look), "вперёд")
	expect(MovementRules.IsForward(Vector3.new(0.5, 0, -0.85), look), "вперёд-вбок (30°)")
	expect(not MovementRules.IsForward(Vector3.new(1, 0, 0), look), "вбок — не бег")
	expect(not MovementRules.IsForward(Vector3.new(0, 0, 1), look), "назад — не бег")
	expect(not MovementRules.IsForward(Vector3.zero, look), "стоя — не бег")
	near(MovementRules.TopAboveRoot, DummyRig.Height - (DummyRig.HipHeight + DummyRig.RootSize.Y / 2), 1e-6, "TopAboveRoot")
end)

test("MoveState: сервер ставит скорость и атрибуты, отклоняет неверное", function()
	local dummy = StarterPlayer.StarterCharacter:Clone()
	dummy.Parent = workspace
	local hum = dummy.Humanoid
	local fake = { Name = "FakeMover", UserId = -50, Character = dummy }
	function fake:Kick() end
	local handler = Net.BuildHandler("MoveState", function(player, state)
		MovementSystem.Apply(player, state)
	end)
	handler(fake, { Stance = "Crouch", Sprint = false })
	eq(hum.WalkSpeed, GameConfig.Movement.CrouchSpeed, "скорость в приседе")
	eq(dummy:GetAttribute("Stance"), "Crouch", "атрибут Stance")
	handler(fake, { Stance = "Crouch", Sprint = true })
	eq(dummy:GetAttribute("Sprinting"), false, "бег в приседе отклонён")
	handler(fake, { Stance = "Stand", Sprint = true })
	eq(hum.WalkSpeed, GameConfig.Movement.SprintSpeed, "скорость бега")
	eq(dummy:GetAttribute("Sprinting"), true, "атрибут Sprinting")
	local before = Net.ViolationCount(fake)
	handler(fake, { Stance = "Fly", Sprint = false })
	handler(fake, { Stance = "Stand" })
	handler(fake, { Stance = "Stand", Sprint = true, Speed = 500 })
	handler(fake, "Stand", true)
	eq(Net.ViolationCount(fake) - before, 4, "неверные MoveState — нарушения")
	eq(hum.WalkSpeed, GameConfig.Movement.SprintSpeed, "неверные MoveState не изменили скорость")
	hum.Health = 0
	eq(MovementSystem.Apply(fake, { Stance = "Stand", Sprint = false }), nil, "у мёртвого стойка не меняется")
	dummy:Destroy()
	expect(not CharacterSystem.Spawn(fake), "Spawn не игрока")
end)

test("клиент: раскладка кнопок для телефона", function()
	local Touch = require(StarterPlayer.StarterPlayerScripts.Client.Controllers.TouchControls)
	for _, vp in ipairs({ Vector2.new(667, 375), Vector2.new(844, 390), Vector2.new(1024, 768), Vector2.new(1920, 1080) }) do
		local size, run, crouch = Touch.Layout(vp)
		expect(size >= 48, "кнопка меньше 48 px на экране " .. tostring(vp))
		for _, pos in ipairs({ run, crouch }) do
			local x = vp.X + pos.X.Offset
			local y = vp.Y + pos.Y.Offset
			expect(x >= 0 and x + size <= vp.X and y >= 0 and y + size <= vp.Y, "кнопка за краем экрана " .. tostring(vp))
		end
		-- кнопки не перекрывают друг друга
		local rx, ry = vp.X + run.X.Offset, vp.Y + run.Y.Offset
		local cx, cy = vp.X + crouch.X.Offset, vp.Y + crouch.Y.Offset
		expect(rx + size <= cx or cx + size <= rx or ry + size <= cy or cy + size <= ry, "кнопки перекрываются " .. tostring(vp))
	end
end)

test("клиент: камера и контроллер (логика)", function()
	local Cam = require(StarterPlayer.StarterPlayerScripts.Client.Controllers.CameraController)
	local cfg = GameConfig.Camera
	for i = 0, 40 do
		local x, y = Cam.BobOffset(i * 0.37, 1)
		expect(math.abs(x) <= cfg.BobSide + 1e-6 and y <= 1e-6 and y >= -cfg.BobVertical - 1e-6, "покачивание вне пределов")
	end
	local x0, y0 = Cam.BobOffset(1.3, 0)
	expect(x0 == 0 and y0 == 0, "без движения — без покачивания")
	for _, name in ipairs({ "Head", "UpperTorso", "RightHand" }) do
		expect(Cam.HiddenParts[name], name .. " должна быть скрыта от своей камеры")
	end
	for _, name in ipairs({ "LowerTorso", "LeftFoot", "RightUpperLeg" }) do
		expect(not Cam.HiddenParts[name], name .. " должна быть видна (свои ноги)")
	end
	local CC = require(StarterPlayer.StarterPlayerScripts.Client.Controllers.CharacterController)
	expect(CC.CanStand(), "без персонажа встать можно")
	CC.ToggleCrouch()
	expect(CC.WantsCrouch(), "ToggleCrouch")
	CC.SetSprintToggle(true)
	expect(CC.SprintToggled() and not CC.WantsCrouch(), "бег снимает присед")
	CC.ToggleCrouch()
	expect(CC.WantsCrouch() and not CC.SprintToggled(), "присед снимает бег")
end)

local passed, failed = 0, {}
for _, r in ipairs(results) do
	if r.Ok then
		passed = passed + 1
	else
		table.insert(failed, r.Name .. " → " .. tostring(r.Err))
	end
end
return string.format("ПРОЙДЕНО %d из %d", passed, #results),
	"ПРОВАЛЫ: " .. (#failed == 0 and "нет" or table.concat(failed, " | ")),
	"ЗАМЕТКИ: " .. table.concat(notes, " | ")
