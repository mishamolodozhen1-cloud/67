-- Проверка этапа 4 DUMMY COMBAT (FPS и AK-47) на сервере Roblox: python3 tools/cloud.py test 4
-- Игроков и клиента в облачном сервере нет, физика не идёт. Поэтому стрелок — «игрок-заглушка» с настоящим
-- манекеном, а выстрелы подаются прямо в WeaponSystem.HandleFire (то же, что делает событие Fire после
-- проверки аргументов). Проверяется: модель и ассеты, конфиги, ИК рук против превью, ключи перезарядки,
-- геометрия попаданий, история положений, вся серверная логика выстрела (темп, патроны, точка выстрела,
-- стены, компенсация задержки), перезарядка, режим огня, проверка аргументов, оружие в регдолле и после
-- смерти, позы оружия от третьего лица. Сама стрельба на экране (камера, руки, эффекты, звук) — в Studio.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local StarterPlayer = game:GetService("StarterPlayer")

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
local function cfNear(a, b, eps, msg)
	local ca, cb = { a:GetComponents() }, { b:GetComponents() }
	for i = 1, 12 do
		if math.abs(ca[i] - cb[i]) > (eps or 1e-3) then
			error(string.format("%s: компонента %d — ждали %.4f, получили %.4f", msg or "", i, cb[i], ca[i]), 2)
		end
	end
end

local Configs = ReplicatedStorage.Configs
local Shared = ReplicatedStorage.Shared
local DummyRig = require(Configs.DummyRig)
local GameConfig = require(Configs.GameConfig)
local WeaponConfig = require(Configs.WeaponConfig)
local WeaponModels = require(Configs.WeaponModels)
local WeaponAssets = require(Configs.WeaponAssets)
local WeaponPoses = require(Configs.WeaponPoses)
local RemoteDefinitions = require(Configs.RemoteDefinitions)
local ArmIK = require(Shared.ArmIK)
local WeaponAnim = require(Shared.WeaponAnim)
local MovementRules = require(Shared.MovementRules)

local Bootstrap = require(ServerScriptService.Server.Bootstrap)
local report = Bootstrap.Start()
local Weapons = Bootstrap.Get("WeaponSystem")
local Ragdoll = Bootstrap.Get("RagdollSystem")
local Movement = Bootstrap.Get("MovementSystem")
local Net = Bootstrap.Get("NetService")
local HitCheck = require(ServerScriptService.Systems.WeaponSystem.HitCheck)
local History = require(ServerScriptService.Systems.WeaponSystem.History)

local Controllers = StarterPlayer.StarterPlayerScripts.Client.Controllers

local template = StarterPlayer:FindFirstChild("StarterCharacter")
local floor = Instance.new("Part")
floor.Name = "TestFloor"
floor.Anchored = true
floor.Size = Vector3.new(600, 2, 600)
floor.CFrame = CFrame.new(0, -1, 0)
floor.Parent = workspace
local testFolder = Instance.new("Folder")
testFolder.Name = "Stage4Test"
testFolder.Parent = workspace

local AK = WeaponConfig.Weapons.AK47
local poses = WeaponPoses.AK47

-- Персонаж-манекен в точке (x, z), смотрит в −Z (физика в облаке не идёт — стоит на месте)
local function spawnAt(x, z, name)
	local d = template:Clone()
	d.Name = name or "TestDummy"
	d:PivotTo(CFrame.new(x, DummyRig.HipHeight + DummyRig.RootSize.Y / 2, z))
	d.Parent = testFolder
	Ragdoll.OnSpawn(d)
	return d
end

local function fakePlayer(name, character)
	return { Name = name, UserId = -400, Character = character }
end

local shotId = 0
local function nextId()
	shotId = shotId + 1
	return shotId
end

test("запуск с оружием", function()
	eq(report.State, "Ready", "состояние сервера")
	eq(report.Status.WeaponSystem, "Started", "WeaponSystem")
	eq(Weapons.UsedFallback(), false, "модель AK-47 загружена из Roblox (не запасная из деталей)")
end)

test("шаблон AK-47: детали, суставы, точки, гильза", function()
	local folder = ReplicatedStorage.Assets.Weapons
	local gun = folder:FindFirstChild("AK47")
	expect(gun and gun.PrimaryPart and gun.PrimaryPart.Name == "Body", "нет шаблона / PrimaryPart")
	for name, spec in pairs(WeaponModels.AK47.Parts) do
		if name ~= "Casing" then
			local p = gun:FindFirstChild(name)
			expect(p and p:IsA("MeshPart"), "нет детали " .. name)
			expect(p.TextureID ~= "", name .. ": нет текстуры")
			expect((p.Size - spec.Size).Magnitude < 1e-3, name .. ": размер")
			expect((gun.Body.CFrame:PointToObjectSpace(p.Position) - spec.Offset).Magnitude < 1e-3, name .. ": место")
			eq(p.CanQuery, false, name .. ".CanQuery")
			eq(p.Massless, true, name .. ".Massless")
		end
	end
	expect(gun.Magazine:FindFirstChild("MagJoint") and gun.ChargingHandle:FindFirstChild("BoltJoint"), "суставы магазина / затвора")
	for name, pos in pairs(WeaponModels.AK47.Points) do
		local a = gun.Body:FindFirstChild(name)
		expect(a and a:IsA("Attachment"), "нет точки " .. name)
		expect((a.Position - pos).Magnitude < 1e-4, name .. ": место точки")
	end
	local casing = folder:FindFirstChild("AK47Casing")
	expect(casing and casing:IsA("MeshPart"), "нет гильзы")
	note(string.format("AK-47: длина %.2f studs, магазин %d+%d, %d выстр/мин", gun.Body.Size.Z, AK.Magazine, AK.Reserve, AK.Rpm))
end)

test("конфиги оружия и звуки", function()
	expect(AK.Rpm > 0 and AK.Magazine == 30 and AK.Reserve >= 0, "AK47: темп/магазин")
	expect(table.find(AK.Modes, AK.DefaultMode), "режим по умолчанию в списке")
	expect(AK.Spread.Aim < AK.Spread.Hip, "с прицелом разброс меньше")
	for _, kind in ipairs({ "Tactical", "Empty" }) do
		local r = poses.Reloads[kind]
		expect(r and r.Length > 1, "перезарядка " .. kind)
		for _, ev in ipairs(r.Sounds) do
			expect(WeaponAssets.Sfx.Groups[ev[2]], "нет звука " .. ev[2])
			expect(ev[1] < r.Length, "звук после конца перезарядки")
		end
		for _, key in ipairs(r.LeftHand) do
			expect(poses.Hands[key[2]], "нет хвата " .. key[2])
		end
	end
	for _, group in ipairs({ "Shot", "Distant", "Dry", "Select", "MagOut", "MagIn", "Charge", "Casing", "Metal", "Concrete", "Wood", "Body" }) do
		local list = WeaponAssets.Sfx.Groups[group]
		expect(list and #list > 0, "нет группы звуков " .. group)
		for _, r in ipairs(list) do
			expect(r.Start >= 0 and r.Stop > r.Start and r.Stop <= WeaponAssets.Sfx.Length, group .. ": отрезок вне файла")
		end
	end
	for _, id in pairs(WeaponAssets.Images) do
		expect(string.match(id, "^rbxassetid://%d+$"), "картинка " .. tostring(id))
	end
end)

test("события оружия созданы и проверяют аргументы", function()
	local remotes = ReplicatedStorage.Remotes
	for name, class in pairs({ Fire = "RemoteEvent", Reload = "RemoteEvent", FireMode = "RemoteEvent", AimPitch = "UnreliableRemoteEvent", WeaponState = "RemoteEvent", ShotFired = "UnreliableRemoteEvent", HitConfirmed = "RemoteEvent" }) do
		local r = remotes:FindFirstChild(name)
		expect(r and r.ClassName == class, name .. " — " .. class)
		expect(RemoteDefinitions[name], name .. " в RemoteDefinitions")
	end
	local got = 0
	local handler = Net.BuildHandler("Fire", function()
		got = got + 1
	end)
	local fake = { Name = "FakeShooter", UserId = -401 }
	function fake:Kick() end
	local o, d = Vector3.new(0, 5, 0), Vector3.new(0, 0, -1)
	handler(fake, 1, o, d, 1.7e9)
	handler(fake, 2, o, d, 1.7e9, floor, Vector3.new(0, 0, -10))
	handler(fake, 3, o, Vector3.new(0, 0, -5), 1.7e9) -- направление не единичное
	handler(fake, 4, Vector3.new(0 / 0, 0, 0), d, 1.7e9) -- NaN
	handler(fake, 5.5, o, d, 1.7e9) -- номер не целый
	handler(fake, 6, o, d, 1.7e9, "Head") -- не деталь
	handler(fake, 7, o, d, 1.7e9, nil, nil, "лишний")
	eq(got, 2, "верные выстрелы прошли, неверные — нет")
	local pitches = 0
	local pitchHandler = Net.BuildHandler("AimPitch", function()
		pitches = pitches + 1
	end)
	pitchHandler(fake, 12.5)
	pitchHandler(fake, 120)
	pitchHandler(fake, "12")
	eq(pitches, 1, "AimPitch: только число от −90 до 90")
end)

test("ИК рук совпадает с превью (tools/weapons/viewmodel.py)", function()
	local vmPoses = poses.Viewmodel
	local gun = vmPoses.Poses.Hip -- камера в начале координат
	for _, side in ipairs({ "Right", "Left" }) do
		local hand = gun * poses.Hands[side]
		local upper, lower, h = ArmIK.Solve(side, vmPoses.Shoulders[side], hand, vmPoses.Poles[side])
		cfNear(upper, poses.Check[side .. "UpperArm"], 2e-3, side .. "UpperArm")
		cfNear(lower, poses.Check[side .. "LowerArm"], 2e-3, side .. "LowerArm")
		cfNear(h, poses.Check[side .. "Hand"], 2e-3, side .. "Hand")
		-- суставы сходятся: локоть плеча = локоть предплечья, запястье предплечья = запястье кисти
		local d = ArmIK.Dims[side]
		expect((upper:PointToWorldSpace(d.ElbowUp) - lower:PointToWorldSpace(d.ElbowLo)).Magnitude < 1e-3, side .. ": локоть разошёлся")
		expect((lower:PointToWorldSpace(d.WristLo) - h:PointToWorldSpace(d.WristHand)).Magnitude < 1e-3, side .. ": запястье разошлось")
		expect((upper:PointToWorldSpace(d.ShoulderUp) - vmPoses.Shoulders[side]).Magnitude < 1e-3, side .. ": плечо не на месте")
	end
end)

test("ключи перезарядки", function()
	local r0 = WeaponAnim.Reload(poses, "Tactical", 0)
	near(r0.Gun, 0, 1e-6, "в начале оружие в обычной позе")
	cfNear(r0.Left, poses.Hands.Left, 1e-4, "в начале левая рука на цевье")
	local mid = WeaponAnim.Reload(poses, "Tactical", 1.0)
	expect(mid.MagInHand, "в середине магазин в руке")
	near(mid.Gun, 1, 1e-6, "в середине оружие повёрнуто к руке")
	local done = WeaponAnim.Reload(poses, "Tactical", poses.Reloads.Tactical.Length)
	expect(not done.MagInHand and done.Gun < 1e-6, "в конце всё на месте")
	local c = poses.Reloads.Empty.Charge
	near(WeaponAnim.Reload(poses, "Empty", (c[2] + c[3]) / 2).Charge, 1, 1e-6, "затвор оттянут")
	near(WeaponAnim.Reload(poses, "Empty", c[1] - 0.01).Charge, 0, 1e-6, "затвор на месте до передёргивания")
	near(WeaponAnim.Reload(poses, "Tactical", 1.0).Charge, 0, 1e-6, "без передёргивания при неполной перезарядке")
	-- магазин в руке там же, где был в оружии, в момент захвата
	local grab = poses.Hands.LeftMag * WeaponAnim.MagOffsetInHand(poses)
	expect((grab.Position - poses.Magazine).Magnitude < 1e-4, "магазин в руке при захвате")
end)

test("геометрия попаданий: луч и коробка, отмотка, точка выстрела", function()
	local box = CFrame.new(0, 0, -10)
	local half = Vector3.new(1, 1, 1)
	near(HitCheck.RayBox(Vector3.zero, Vector3.new(0, 0, -1), box, half), 9, 1e-6, "в лоб")
	eq(HitCheck.RayBox(Vector3.new(3, 0, 0), Vector3.new(0, 0, -1), box, half), nil, "мимо")
	eq(HitCheck.RayBox(Vector3.zero, Vector3.new(0, 0, 1), box, half), nil, "назад")
	near(HitCheck.RayBox(Vector3.new(0, 0, -10), Vector3.new(0, 0, -1), box, half), 0, 1e-6, "изнутри")
	local turned = CFrame.new(0, 0, -10) * CFrame.Angles(0, math.rad(45), 0)
	expect(HitCheck.RayBox(Vector3.new(1.3, 0, 0), Vector3.new(0, 0, -1), turned, half), "повёрнутая коробка шире по диагонали")
	local rootNow, rootThen = CFrame.new(10, 3, 0), CFrame.new(0, 3, 0)
	local part = CFrame.new(10, 5, 0)
	expect((HitCheck.Rewind(part, rootNow, rootThen).Position - Vector3.new(0, 5, 0)).Magnitude < 1e-6, "отмотка части вместе с корнем")
	expect(HitCheck.OriginOk(Vector3.new(0, 0, 3), Vector3.zero, 0, 0.1, 4.5), "рядом с головой")
	expect(not HitCheck.OriginOk(Vector3.new(0, 0, 30), Vector3.zero, 12, 0.2, 4.5), "далеко от головы")
	near(HitCheck.RewindTime(100, 100.05, 0.1, 0.5), 99.9, 1e-9, "отмотка: время выстрела минус показ")
	near(HitCheck.RewindTime(10, 100, 0.1, 0.5), 99.5, 1e-9, "отмотка не дальше MaxRewind")
	near(HitCheck.RewindTime(200, 100, 0.1, 0.5), 100, 1e-9, "отмотка не в будущее")
	expect(HitCheck.PointOnRay(Vector3.zero, Vector3.new(0, 0, -1), Vector3.new(0.5, 0, -20), 100, 1), "точка у луча")
	expect(not HitCheck.PointOnRay(Vector3.zero, Vector3.new(0, 0, -1), Vector3.new(5, 0, -20), 100, 1), "точка далеко от луча")
end)

test("история положений", function()
	local h = History.new(1.0)
	local m = {}
	h:Record(m, 10.0, CFrame.new(0, 0, 0))
	h:Record(m, 10.1, CFrame.new(10, 0, 0))
	near(h:At(m, 10.05).Position.X, 5, 1e-6, "между записями")
	near(h:At(m, 9).Position.X, 0, 1e-6, "до первой")
	near(h:At(m, 11).Position.X, 10, 1e-6, "после последней")
	for i = 1, 40 do
		h:Record(m, 10.1 + i * 0.05, CFrame.new(i, 0, 0))
	end
	expect(h:Count(m) <= 23, "старое удаляется (записей " .. h:Count(m) .. ")")
end)

-- Стрелок и мишень: стрелок в (0, 0), мишень в 30 studs впереди (−Z)
local shooter = spawnAt(0, 0, "Shooter")
local target = spawnAt(0, -30, "Target")
CollectionService:AddTag(target, Weapons.TargetTag)
local player = fakePlayer("FakePlayer", shooter)
local hits = {}
Weapons.HitConfirmed:Connect(function(p, hit)
	if p == player then
		table.insert(hits, hit)
	end
end)

local function aimAt(part)
	local origin = shooter.Head.Position + Vector3.new(0, 0.2, -0.3)
	return origin, (part.Position - origin).Unit
end

test("выдача оружия", function()
	local gun = Weapons.Equip(player, shooter)
	expect(gun and gun.Parent == shooter and gun.Name == "Weapon", "оружие у персонажа")
	local hold = gun.Body:FindFirstChild("RifleHold")
	expect(hold and hold.Part0 == shooter.UpperTorso and hold.Part1 == gun.Body, "крепление к корпусу")
	cfNear(hold.C0, poses.ThirdPerson.Poses.Ready, 1e-4, "поза у плеча")
	local s = Weapons.GetState(player)
	eq(s.Ammo, AK.Magazine, "патроны")
	eq(s.Reserve, AK.Reserve, "запас")
	eq(s.Mode, AK.DefaultMode, "режим")
	eq(shooter:GetAttribute("Weapon"), "AK47", "атрибут Weapon")
	expect(CollectionService:HasTag(shooter, Weapons.TargetTag), "персонаж — цель")
	-- суставы тела по-прежнему 15: оружейные суставы лежат в деталях оружия
	local body = 0
	for _, d in ipairs(shooter:GetDescendants()) do
		if d:IsA("Motor6D") and d.Parent and d.Parent.Parent == shooter then
			body = body + 1
		end
	end
	eq(body, 15, "суставов тела")
end)

test("выстрел: пока достаёт — нельзя, потом попадание в голову засчитано", function()
	local origin, dir = aimAt(target.Head)
	local ok, why = Weapons.HandleFire(player, nextId(), origin, dir, workspace:GetServerTimeNow(), target.Head, target.Head.Position)
	expect(not ok, "выстрел сразу после выдачи должен быть отклонён")
	note("сразу после выдачи: " .. tostring(why))
	task.wait(AK.EquipTime + 0.1)
	Weapons.RecordTargets()
	ok, why = Weapons.HandleFire(player, nextId(), origin, dir, workspace:GetServerTimeNow(), target.Head, target.Head.Position)
	expect(ok, "выстрел отклонён: " .. tostring(why))
	expect(why.Hit and why.Hit.Headshot and why.Hit.Target == target, "попадание в голову")
	eq(#hits, 1, "сигнал HitConfirmed")
	eq(Weapons.GetState(player).Ammo, AK.Magazine - 1, "минус патрон")
	near(why.Hit.Distance, (target.Head.Position - origin).Magnitude, 1.5, "расстояние")
end)

test("выстрел: темп, повтор номера, точка выстрела", function()
	task.wait(0.3)
	local origin, dir = aimAt(target.UpperTorso)
	local accepted, lastAccepted = 0, nil
	for _ = 1, 6 do
		local id = nextId()
		if Weapons.HandleFire(player, id, origin, dir, workspace:GetServerTimeNow()) then
			accepted = accepted + 1
			lastAccepted = id
		end
	end
	expect(accepted >= 2 and accepted <= 3, "пачкой проходит не больше 2–3 выстрелов, прошло " .. accepted)
	task.wait(0.4)
	local ok = Weapons.HandleFire(player, lastAccepted, origin, dir, workspace:GetServerTimeNow())
	expect(not ok, "повтор номера уже принятого выстрела")
	ok = Weapons.HandleFire(player, nextId(), origin + Vector3.new(0, 0, -40), dir, workspace:GetServerTimeNow())
	expect(not ok, "точка выстрела в 40 studs от головы")
	task.wait(0.15)
	ok = Weapons.HandleFire(player, nextId(), origin, dir, workspace:GetServerTimeNow())
	expect(ok, "обычный выстрел после паузы")
end)

test("попадание: мимо цели и сквозь стену — не засчитано", function()
	task.wait(0.15)
	local origin = aimAt(target.Head)
	local off = (CFrame.lookAt(origin, target.Head.Position) * CFrame.Angles(0, math.rad(25), 0)).LookVector
	local before = #hits
	local ok, out = Weapons.HandleFire(player, nextId(), origin, off, workspace:GetServerTimeNow(), target.Head, target.Head.Position)
	expect(ok and not out.Hit, "луч в 25° от цели: выстрел есть, попадания нет")
	local wall = Instance.new("Part")
	wall.Anchored = true
	wall.Size = Vector3.new(20, 20, 1)
	wall.CFrame = CFrame.new(0, 5, -15)
	wall.Parent = testFolder
	task.wait(0.15)
	local _, dir = aimAt(target.Head)
	ok, out = Weapons.HandleFire(player, nextId(), origin, dir, workspace:GetServerTimeNow(), target.Head, target.Head.Position)
	expect(ok and not out.Hit, "сквозь стену попадания нет")
	expect(out.Kind == "World" and (out.End - Vector3.new(0, out.End.Y, -14.5)).Magnitude < 1, "луч сервера упёрся в стену")
	eq(#hits, before, "сигналов попадания не было")
	wall:Destroy()
end)

test("компенсация задержки: цель ушла — попадание по тому, что видел стрелок", function()
	task.wait(0.15)
	local history = Weapons.History()
	local t0 = workspace:GetServerTimeNow()
	local cfA = target.HumanoidRootPart.CFrame
	history:Record(target, t0, cfA)
	local origin, dirA = aimAt(target.Head)
	-- цель отошла на 6 studs вбок
	target:PivotTo(cfA * CFrame.new(6, 0, 0))
	history:Record(target, workspace:GetServerTimeNow(), target.HumanoidRootPart.CFrame)
	local cfg = WeaponConfig.Server
	local ok, out = Weapons.HandleFire(player, nextId(), origin, dirA, t0 + cfg.InterpDelay, target.Head, origin + dirA * 30)
	expect(ok and out.Hit, "по месту, где цель была в момент выстрела, — попадание")
	note(string.format("отмотано на %.3f с", out.Hit.Rewind))
	task.wait(0.15)
	ok, out = Weapons.HandleFire(player, nextId(), origin, dirA, workspace:GetServerTimeNow() + cfg.InterpDelay, target.Head, origin + dirA * 30)
	expect(ok and not out.Hit, "выстрел «сейчас» по старому месту — мимо")
	target:PivotTo(cfA)
end)

test("перезарядка: частичная, во время неё не стреляют, патроны переходят", function()
	task.wait(0.15)
	local before = Weapons.GetState(player)
	expect(before.Ammo < AK.Magazine, "магазин не полный")
	expect(Weapons.StartReload(player), "перезарядка началась")
	eq(shooter:GetAttribute("ReloadKind"), "Tactical", "вид перезарядки")
	expect(shooter:GetAttribute("Reloading") > 0, "атрибут Reloading")
	local origin, dir = aimAt(target.Head)
	expect(not Weapons.HandleFire(player, nextId(), origin, dir, workspace:GetServerTimeNow()), "во время перезарядки не стреляют")
	expect(not Weapons.StartReload(player), "вторая перезарядка не начинается")
	Weapons.FinishReloadNow(player)
	local after = Weapons.GetState(player)
	eq(after.Ammo, AK.Magazine, "магазин полный")
	eq(after.Reserve, before.Reserve - (AK.Magazine - before.Ammo), "из запаса ушло ровно недостающее")
	eq(shooter:GetAttribute("Reloading"), 0, "атрибут снят")
	expect(not Weapons.StartReload(player), "полный магазин не перезаряжается")
end)

test("пустой магазин: стрельба до конца, щелчок, перезарядка с передёргиванием", function()
	local origin, dir = aimAt(target.UpperTorso)
	local interval = 60 / AK.Rpm
	local fired = 0
	for _ = 1, AK.Magazine + 3 do
		task.wait(interval + 0.01)
		if Weapons.HandleFire(player, nextId(), origin, dir, workspace:GetServerTimeNow()) then
			fired = fired + 1
		end
	end
	eq(fired, AK.Magazine, "выстрелов из полного магазина ровным темпом")
	eq(Weapons.GetState(player).Ammo, 0, "пусто")
	expect(Weapons.StartReload(player), "перезарядка пустого")
	eq(shooter:GetAttribute("ReloadKind"), "Empty", "с передёргиванием затвора")
	Weapons.FinishReloadNow(player)
	eq(Weapons.GetState(player).Ammo, AK.Magazine, "снова полный")
end)

test("режим огня", function()
	expect(Weapons.SetMode(player, "Semi"), "одиночный")
	eq(Weapons.GetState(player).Mode, "Semi", "режим сменился")
	expect(not Weapons.SetMode(player, "Burst"), "неизвестный режим не ставится")
	eq(Weapons.GetState(player).Mode, "Semi", "режим не сбился")
	Weapons.SetMode(player, "Auto")
end)

test("прицел замедляет и запрещает бег", function()
	near(MovementRules.SpeedFor("Stand", false, true), GameConfig.Movement.WalkSpeed * GameConfig.Movement.AimSpeedFactor, 1e-6, "шаг с прицелом")
	near(MovementRules.SpeedFor("Stand", true, true), GameConfig.Movement.WalkSpeed * GameConfig.Movement.AimSpeedFactor, 1e-6, "бег с прицелом — шаг")
	local hum = shooter.Humanoid
	Movement.Apply(player, { Stance = "Stand", Sprint = true, Aim = true })
	eq(shooter:GetAttribute("Sprinting"), false, "с прицелом не бежит")
	eq(shooter:GetAttribute("Aiming"), true, "атрибут Aiming")
	near(hum.WalkSpeed, GameConfig.Movement.WalkSpeed * GameConfig.Movement.AimSpeedFactor, 1e-6, "скорость")
	Movement.Apply(player, { Stance = "Stand", Sprint = false })
	eq(shooter:GetAttribute("Aiming"), false, "без поля Aim — без прицела (совместимо со старым MoveState)")
end)

test("оружие от третьего лица: руки на рукояти и цевье", function()
	local TP = require(Controllers.ThirdPersonWeapons)
	local data = TP.Collect(shooter)
	expect(data, "Collect")
	for _, pose in ipairs({ "Ready", "Aim" }) do
		shooter:SetAttribute("Aiming", pose == "Aim")
		data.Aim = pose == "Aim" and 1 or 0
		expect(TP.Pose(shooter, data, 1 / 60, workspace:GetServerTimeNow(), true), "Pose")
		local hold = poses.ThirdPerson.Poses[pose]
		cfNear(data.Hold.C0 * data.Hold.Transform, hold, 1e-4, pose .. ": оружие")
		for side, arm in pairs(data.Arms) do
			-- цепочка суставов в осях UpperTorso: Part1 = Part0 · C0 · Transform · C1⁻¹
			local upper = arm.Shoulder.C0 * arm.Shoulder.Transform * arm.Shoulder.C1:Inverse()
			local lower = upper * arm.Elbow.C0 * arm.Elbow.Transform * arm.Elbow.C1:Inverse()
			local hand = lower * arm.Wrist.C0 * arm.Wrist.Transform * arm.Wrist.C1:Inverse()
			local want = hold * poses.Hands[side]
			local miss = (hand.Position - want.Position).Magnitude
			expect(miss < 0.05, string.format("%s %s: кисть не на оружии (%.3f)", pose, side, miss))
		end
	end
	shooter:SetAttribute("Aiming", false)
	-- перезарядка: магазин в левой руке
	shooter:SetAttribute("ReloadKind", "Tactical")
	shooter:SetAttribute("Reloading", workspace:GetServerTimeNow() - 1.0)
	TP.Pose(shooter, data, 1 / 60, workspace:GetServerTimeNow(), true)
	expect(data.Mag.Transform ~= CFrame.identity, "магазин сдвинут в руку")
	shooter:SetAttribute("Reloading", 0)
	shooter:SetAttribute("ReloadKind", "")
end)

test("клиентские расчёты: конус разброса, перекрестие, кнопки телефона", function()
	local WC = require(Controllers.WeaponController)
	local rnd = Random.new(7)
	local cf = CFrame.lookAt(Vector3.zero, Vector3.new(1, 0.2, -1))
	local maxAngle = 0
	for _ = 1, 400 do
		local d = WC.ConeDirection(cf, 3, rnd)
		maxAngle = math.max(maxAngle, math.deg(math.acos(math.clamp(d:Dot(cf.LookVector), -1, 1))))
	end
	expect(maxAngle <= 3.001 and maxAngle > 2.5, string.format("отклонение до 3°, наибольшее %.3f", maxAngle))
	local HUD = require(Controllers.WeaponHUD)
	near(HUD.SpreadPixels(36, 72, 1000), 500, 1e-6, "половина поля зрения — до края экрана")
	local Touch = require(Controllers.TouchControls)
	for _, vp in ipairs({ Vector2.new(844, 390), Vector2.new(667, 375), Vector2.new(1366, 1024), Vector2.new(2048, 1536) }) do
		local size, run, crouch = Touch.Layout(vp)
		local boxes = {
			Run = { run.X.Offset + vp.X, run.Y.Offset + vp.Y, size },
			Crouch = { crouch.X.Offset + vp.X, crouch.Y.Offset + vp.Y, size },
		}
		local small = math.min(vp.X, vp.Y) <= 500
		local jump = small and 70 or 120
		boxes.Jump = { vp.X - (jump * 1.5 - 10), vp.Y + (small and (-jump - 20) or (-jump * 1.75)), jump }
		for name, spot in pairs(Touch.WeaponLayout(vp)) do
			boxes[name] = { spot.Position.X.Offset + vp.X, spot.Position.Y.Offset + vp.Y, spot.Size }
		end
		for a, A in pairs(boxes) do
			expect(A[1] >= 0 and A[2] >= 0 and A[1] + A[3] <= vp.X and A[2] + A[3] <= vp.Y, string.format("%s вне экрана %dx%d", a, vp.X, vp.Y))
			for b, B in pairs(boxes) do
				if a < b then
					local overlap = A[1] < B[1] + B[3] and B[1] < A[1] + A[3] and A[2] < B[2] + B[3] and B[2] < A[2] + A[3]
					expect(not overlap, string.format("%s и %s перекрываются на %dx%d", a, b, vp.X, vp.Y))
				end
			end
		end
	end
end)

test("регдолл: оружие остаётся в руках; смерть — оружие падает", function()
	expect(Ragdoll.Ragdoll(shooter, "Knockdown", {}), "Ragdoll")
	local gun = shooter.Weapon
	eq(gun.Body.RifleHold.Enabled, true, "крепление оружия в регдолле не выключается")
	eq(gun.Magazine.MagJoint.Enabled, true, "магазин в регдолле на месте")
	eq(shooter.LeftLowerLeg.LeftKnee.Enabled, false, "суставы тела выключены")
	local origin, dir = aimAt(target.Head)
	task.wait(0.15)
	expect(not Weapons.HandleFire(player, nextId(), origin, dir, workspace:GetServerTimeNow()), "лёжа не стреляют")
	Ragdoll.Recover(shooter)
	eq(gun.Body.RifleHold.Enabled, true, "после подъёма крепление на месте")
	Weapons.Drop(shooter)
	expect(not gun.Body:FindFirstChild("RifleHold"), "крепление снято")
	eq(gun.Body.CanCollide, true, "оружие сталкивается с миром")
	eq(gun.Body.CollisionGroup, Weapons.DebrisGroup, "группа столкновений")
	eq(shooter:GetAttribute("Weapon"), "", "атрибут Weapon снят")
end)

test("клиент без клиента: кадры стрельбы, перезарядки и вида от первого лица", function()
	local Validate = require(Shared.Validate)
	local me = spawnAt(40, 0, "Me")
	me:SetAttribute("Weapon", "AK47") -- как будто сервер выдал оружие
	local hum, root = me.Humanoid, me.HumanoidRootPart
	local cam = workspace.CurrentCamera
	if not cam then
		cam = Instance.new("Camera")
		cam.Parent = workspace
		workspace.CurrentCamera = cam
	end
	local eye = me.Head.Position + Vector3.new(0, 0.2, -0.3)
	cam.CFrame = CFrame.lookAt(eye, eye + Vector3.new(0, -0.3, -1))
	local sent, recoils = {}, 0
	local mods = {
		ClientNet = {
			Fire = function(name, ...)
				table.insert(sent, table.pack(name, ...))
				return true
			end,
			On = function() end,
		},
		CharacterController = {
			GetCharacter = function()
				return me, hum, root
			end,
			GetState = function()
				return { Stance = "Stand", Sprint = false, Aim = false }
			end,
			IsRagdolled = function()
				return false
			end,
			SetSprintBlocked = function() end,
			SetAim = function() end,
		},
		CameraController = {
			AddRecoil = function()
				recoils = recoils + 1
			end,
			SetAim = function() end,
			ResetRecoil = function() end,
			IsFirstPerson = function()
				return true
			end,
		},
		WeaponEffects = require(Controllers.WeaponEffects),
		Viewmodel = require(Controllers.Viewmodel),
	}
	local ctx = {
		Get = function(name)
			return mods[name]
		end,
	}
	local WC = require(Controllers.WeaponController)
	local VM = mods.Viewmodel
	mods.WeaponEffects.Init(ctx)
	VM.Init(ctx)
	WC.Init(ctx)
	WC.OnCharacter(me)
	task.wait(0.3)
	expect(VM.Exists(), "вид от первого лица собран")
	WC.ServerState({ Weapon = "AK47", Ammo = 30, Reserve = 90, Mode = "Auto", Reloading = false, Reason = "Equip" })
	local function run(seconds)
		local t = os.clock()
		while os.clock() - t < seconds do
			WC.Step(1 / 60)
			VM.Step(1 / 60)
			task.wait()
		end
	end
	run(AK.EquipTime + 0.05)
	WC.SetTrigger(true)
	run(1.05)
	WC.SetTrigger(false)
	local fires = 0
	for _, e in ipairs(sent) do
		if e[1] == "Fire" then
			fires = fires + 1
			local ok, why = Validate.Args(RemoteDefinitions.Fire.Args, table.unpack(e, 2, e.n))
			expect(ok, "аргументы Fire не прошли бы проверку сервера: " .. tostring(why))
		end
	end
	expect(fires >= 10 and fires <= 11, "за 1.05 с очереди при 600 выстр/мин — 11 выстрелов (первый сразу), ушло " .. fires)
	eq(WC.GetState().Ammo, 30 - fires, "патроны (предсказание)")
	eq(recoils, fires, "отдача на каждый выстрел")
	note("клиент: за 1.05 с очереди — " .. fires .. " выстрелов")
	local parts = VM.Parts()
	expect(parts.Model.Parent == cam, "модель в камере")
	local gunCF = parts.Body.CFrame
	local miss = (parts.Arms.RightHand.Position - (gunCF * poses.Hands.Right).Position).Magnitude
	expect(miss < 0.05, string.format("правая кисть на рукояти (%.3f)", miss))
	miss = (parts.Arms.LeftHand.Position - (gunCF * poses.Hands.Left).Position).Magnitude
	expect(miss < 0.05, string.format("левая кисть на цевье (%.3f)", miss))
	expect((parts.Body.Position - cam.CFrame.Position).Magnitude < 3, "оружие у камеры")
	local holes = 0
	for _, c in ipairs(workspace.Effects:GetChildren()) do
		if c.Name == "BulletHole" then
			holes = holes + 1
		end
	end
	expect(holes > 0, "следы от пуль на полу")
	-- перезарядка
	expect(WC.RequestReload(), "перезарядка")
	expect(WC.GetState().Reloading, "идёт перезарядка")
	expect(sent[#sent][1] == "Reload", "серверу ушло Reload")
	WC.ServerState({ Weapon = "AK47", Ammo = 30 - fires, Reserve = 90, Mode = "Auto", Reloading = true, ReloadKind = "Tactical", Reason = "Reload" })
	run(1.0)
	expect((parts.Body.CFrame:PointToObjectSpace(parts.Mag.Position) - poses.Magazine).Magnitude > 0.3, "магазин ушёл из оружия в руку")
	WC.ServerState({ Weapon = "AK47", Ammo = 30, Reserve = 90 - fires, Mode = "Auto", Reloading = false, Reason = "Reloaded" })
	run(poses.Reloads.Tactical.Length - 1.0 + 0.1)
	expect(not WC.GetState().Reloading, "перезарядка закончилась")
	eq(WC.GetState().Ammo, 30, "магазин полный")
	VM.Destroy()
	me:Destroy()
end)

shooter:Destroy()
target:Destroy()
testFolder:Destroy()
floor:Destroy()

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
