-- Проверка этапов 5–10 DUMMY COMBAT на сервере Roblox: python3 tools/cloud.py test 5
-- Игроков и клиента в облачном сервере нет, физика не идёт. Стрелки — «игроки-заглушки» с настоящими манекенами
-- и боты BotSystem; выстрелы подаются прямо в WeaponSystem.HandleFire (как после проверки события Fire).
-- Проверяется: пять стволов (модели, позы, звуки), дробь (одинаковые направления у клиента и сервера, урон по
-- дробинам), затвор снайперской, все пять карт (сборка, точки появления на полу и не в стенах, командные точки),
-- режимы FFA / TDM / GUN GAME / CHAOS с ботами (свои/чужие, уровни оружия, взрыв), конфиг прогресса и магазина.
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

local Configs = ReplicatedStorage.Configs
local Shared = ReplicatedStorage.Shared
local DummyRig = require(Configs.DummyRig)
local WeaponConfig = require(Configs.WeaponConfig)
local WeaponModels = require(Configs.WeaponModels)
local WeaponAssets = require(Configs.WeaponAssets)
local WeaponPoses = require(Configs.WeaponPoses)
local MatchConfig = require(Configs.MatchConfig)
local ProgressionConfig = require(Configs.ProgressionConfig)
local SkinAssets = require(Configs.SkinAssets)
local Pellets = require(Shared.Pellets)
local WeaponAnim = require(Shared.WeaponAnim)

local Bootstrap = require(ServerScriptService.Server.Bootstrap)
local report = Bootstrap.Start()
local Weapons = Bootstrap.Get("WeaponSystem")
local Ragdoll = Bootstrap.Get("RagdollSystem")
local Combat = Bootstrap.Get("CombatSystem")
local Maps = Bootstrap.Get("MapSystem")
local Match = Bootstrap.Get("MatchSystem")
local Bots = Bootstrap.Get("BotSystem")
local Progression = Bootstrap.Get("ProgressionSystem")
Match.Paused = true

local NAMES = { "AK47", "SMG", "Shotgun", "Sniper", "Pistol" }
local template = StarterPlayer:FindFirstChild("StarterCharacter")
local testFolder = Instance.new("Folder")
testFolder.Name = "DevDummies" -- по манекенам стенда урон проходит и вне матча
testFolder.Parent = workspace

local shotId = 1000
local function nextId()
	shotId = shotId + 1
	return shotId
end

local function spawnAt(pos, name)
	local d = template:Clone()
	d.Name = name or "TestDummy"
	d:PivotTo(CFrame.new(pos + Vector3.new(0, DummyRig.HipHeight + DummyRig.RootSize.Y / 2, 0)))
	d.Parent = testFolder
	Ragdoll.OnSpawn(d)
	CollectionService:AddTag(d, Weapons.TargetTag)
	return d
end

test("сервер запущен, все системы, модели всех стволов загружены", function()
	eq(report.State, "Ready", "состояние сервера")
	for _, name in ipairs({ "WeaponSystem", "CombatSystem", "MapSystem", "MatchSystem", "LobbySystem", "BotSystem", "ProgressionSystem" }) do
		eq(report.Status[name], "Started", name)
	end
	eq(Weapons.UsedFallback(), false, "все модели оружия из Roblox (не запасные)")
end)

test("пять стволов: шаблоны, точки, гильзы, позы, звуки", function()
	local folder = ReplicatedStorage.Assets.Weapons
	for _, name in ipairs(NAMES) do
		local def = WeaponConfig.Weapons[name]
		expect(def, "нет конфига " .. name)
		local gun = folder:FindFirstChild(name)
		expect(gun and gun.PrimaryPart and gun.PrimaryPart.Name == "Body", name .. ": шаблон")
		for part, spec in pairs(WeaponModels[name].Parts) do
			if part ~= "Casing" then
				local p = gun:FindFirstChild(part)
				expect(p and p:IsA("MeshPart") and p.TextureID ~= "", name .. ": деталь " .. part)
				expect((p.Size - spec.Size).Magnitude < 1e-3, name .. "." .. part .. ": размер")
			end
		end
		for point in pairs(WeaponModels[name].Points) do
			expect(gun.Body:FindFirstChild(point), name .. ": точка " .. point)
		end
		expect(folder:FindFirstChild(name .. "Casing"), name .. ": гильза")
		local poses = WeaponPoses[name]
		expect(poses and poses.Viewmodel and poses.ThirdPerson, name .. ": позы")
		for kind, r in pairs(poses.Reloads) do
			for _, key in ipairs(r.LeftHand) do
				expect(poses.Hands[key[2]], name .. "." .. kind .. ": нет хвата " .. key[2])
			end
			for _, key in ipairs(r.RightHand) do
				expect(poses.Hands[key[2]], name .. "." .. kind .. ": нет хвата " .. key[2])
			end
			for _, ev in ipairs(r.Sounds) do
				expect(WeaponAssets.Sfx.Groups[ev[2]] or WeaponAssets.Sfx2.Groups[ev[2]], name .. ": нет звука " .. ev[2])
			end
			local st = WeaponAnim.Reload(poses, kind, r.Length * 0.5)
			expect(st.Left and st.Right, name .. "." .. kind .. ": ключи считаются")
		end
		local shot = def.ShotSound
		expect(WeaponAssets.Sfx.Groups[shot] or WeaponAssets.Sfx2.Groups[shot], name .. ": звук выстрела " .. tostring(shot))
		expect(WeaponAssets.Models[name], name .. ": id модели")
		expect(table.find(def.Modes, def.DefaultMode), name .. ": режим огня")
	end
	expect(WeaponPoses.Sniper.Reloads.Cycle, "у снайперской — передёргивание затвора")
	for _, r in ipairs(WeaponAssets.Sfx2.Groups.ShotShotgun) do
		expect(r.Stop <= WeaponAssets.Sfx2.Length, "отрезок в файле")
	end
	note("стволы: " .. table.concat(NAMES, ", "))
end)

test("дробь: одинаковые направления по номеру выстрела, в пределах конуса", function()
	local dir = Vector3.new(0.3, 0.1, -1).Unit
	local a = Pellets.Directions(dir, 8, 4.2, 777)
	local b = Pellets.Directions(dir, 8, 4.2, 777)
	local c = Pellets.Directions(dir, 8, 4.2, 778)
	eq(#a, 8, "дробин")
	local same, diff = true, false
	for i = 1, 8 do
		same = same and (a[i] - b[i]).Magnitude < 1e-9
		diff = diff or (a[i] - c[i]).Magnitude > 1e-4
		local angle = math.deg(math.acos(math.clamp(a[i]:Dot(dir), -1, 1)))
		expect(angle <= 4.2 + 1e-3, string.format("дробина %d вне конуса: %.2f°", i, angle))
		expect(math.abs(a[i].Magnitude - 1) < 1e-6, "единичное направление")
	end
	expect(same, "один номер — те же направления")
	expect(diff, "другой номер — другой узор")
	eq((a[1] - dir).Magnitude < 1e-9, true, "первая — по центру")
end)

-- стрелок-заглушка с оружием name в точке pos, смотрит на target
local function shooterWith(name, pos)
	local body = spawnAt(pos, "Shooter_" .. name)
	local player = { Name = "Tester_" .. name, UserId = -500 }
	player.Character = body
	Weapons.Equip(player, body, name)
	return player, body
end

test("дробовик: попадания дробин по зонам, урон вблизи и издалека", function()
	local player, body = shooterWith("Shotgun", Vector3.new(0, 0, 40))
	local target = spawnAt(Vector3.new(0, 0, 30), "ShotgunTarget")
	task.wait(WeaponConfig.Weapons.Shotgun.EquipTime + 0.1)
	local origin = body.Head.Position + Vector3.new(0, 0.2, -0.3)
	local aim = target.UpperTorso.Position
	local dir = (aim - origin).Unit
	local hit = nil
	local conn = Weapons.HitConfirmed:Connect(function(_, h)
		hit = h
	end)
	local ok, out = Weapons.HandleFire(player, nextId(), origin, dir, workspace:GetServerTimeNow(), target.UpperTorso, aim)
	conn:Disconnect()
	expect(ok, "выстрел принят: " .. tostring(out))
	expect(hit and hit.PelletHits, "попадание дробью")
	expect(#hit.PelletHits >= 5, "вблизи в цель попало " .. #hit.PelletHits .. " дробин из 8")
	expect(hit.Damage and hit.Damage >= 100, string.format("вблизи — смертельно (урон %.0f)", hit.Damage or -1))
	eq(hit.Killed, true, "цель убита одним выстрелом вблизи")
	note(string.format("дробовик 10 studs: %d из 8 дробин, урон %.0f", #hit.PelletHits, hit.Damage))
	-- издалека: часть дроби мимо, урон меньше
	local far = spawnAt(Vector3.new(0, 0, -30), "ShotgunFar")
	task.wait(60 / WeaponConfig.Weapons.Shotgun.Rpm + 0.05)
	aim = far.UpperTorso.Position
	dir = (aim - origin).Unit
	hit = nil
	conn = Weapons.HitConfirmed:Connect(function(_, h)
		hit = h
	end)
	ok, out = Weapons.HandleFire(player, nextId(), origin, dir, workspace:GetServerTimeNow(), far.UpperTorso, aim)
	conn:Disconnect()
	expect(ok, "второй выстрел принят: " .. tostring(out))
	expect(hit and hit.Damage and hit.Damage < 60, string.format("на 70 studs урон небольшой (%.0f)", hit and hit.Damage or -1))
	note(string.format("дробовик 70 studs: %d дробин, урон %.0f", hit and #hit.PelletHits or 0, hit and hit.Damage or 0))
	-- заявка о попадании, когда дробь прошла мимо, не засчитывается
	task.wait(60 / WeaponConfig.Weapons.Shotgun.Rpm + 0.05)
	hit = nil
	conn = Weapons.HitConfirmed:Connect(function(_, h)
		hit = h
	end)
	ok = Weapons.HandleFire(player, nextId(), origin, Vector3.new(0, 1, -0.2).Unit, workspace:GetServerTimeNow(), far.Head, far.Head.Position)
	conn:Disconnect()
	expect(ok and hit == nil, "дробь вверх — попадания нет")
	body:Destroy()
	target:Destroy()
	far:Destroy()
end)

test("снайперская: затвор после выстрела, темп, урон в корпус", function()
	local player, body = shooterWith("Sniper", Vector3.new(30, 0, 60))
	local target = spawnAt(Vector3.new(30, 0, -60), "SniperTarget")
	task.wait(WeaponConfig.Weapons.Sniper.EquipTime + 0.1)
	local origin = body.Head.Position + Vector3.new(0, 0.2, -0.3)
	local aim = target.UpperTorso.Position
	local hit = nil
	local conn = Weapons.HitConfirmed:Connect(function(_, h)
		hit = h
	end)
	local ok = Weapons.HandleFire(player, nextId(), origin, (aim - origin).Unit, workspace:GetServerTimeNow(), target.UpperTorso, aim)
	conn:Disconnect()
	expect(ok and hit, "выстрел и попадание")
	eq(hit.Killed, true, "в корпус — наповал")
	expect(type(body:GetAttribute("Cycling")) == "number" and body:GetAttribute("Cycling") > 0, "атрибут Cycling (другие видят передёргивание)")
	task.wait(0.3)
	local ok2, why = Weapons.HandleFire(player, nextId(), origin, Vector3.new(0, 0, -1), workspace:GetServerTimeNow())
	eq(ok2, false, "через 0,3 с — ещё передёргивает (" .. tostring(why) .. ")")
	eq(Weapons.GetState(player).Ammo, WeaponConfig.Weapons.Sniper.Magazine - 1, "патронов")
	body:Destroy()
	target:Destroy()
end)

test("пистолет и ПП: выдача, выстрел, урон", function()
	for _, name in ipairs({ "Pistol", "SMG" }) do
		local player, body = shooterWith(name, Vector3.new(-30, 0, 20))
		local target = spawnAt(Vector3.new(-30, 0, 0), name .. "Target")
		task.wait(WeaponConfig.Weapons[name].EquipTime + 0.1)
		eq(body:GetAttribute("Weapon"), name, "атрибут оружия")
		local origin = body.Head.Position + Vector3.new(0, 0.2, -0.3)
		local aim = target.Head.Position
		local hit = nil
		local conn = Weapons.HitConfirmed:Connect(function(_, h)
			hit = h
		end)
		local ok = Weapons.HandleFire(player, nextId(), origin, (aim - origin).Unit, workspace:GetServerTimeNow(), target.Head, aim)
		conn:Disconnect()
		expect(ok and hit and hit.Headshot, name .. ": попадание в голову")
		eq(math.floor(hit.Damage + 0.5), WeaponConfig.Weapons[name].Damage.Head, name .. ": урон в голову вблизи")
		body:Destroy()
		target:Destroy()
	end
end)

test("клиент без клиента: дробь, затвор снайперской и прицел, полуавтомат пистолета", function()
	local Controllers = StarterPlayer.StarterPlayerScripts.Client.Controllers
	local floor = Instance.new("Part")
	floor.Anchored = true
	floor.Size = Vector3.new(200, 2, 200)
	floor.CFrame = CFrame.new(0, -1, -200)
	floor.Parent = workspace
	local me = spawnAt(Vector3.new(0, 0, -200), "Me")
	local hum, root = me.Humanoid, me.HumanoidRootPart
	local cam = workspace.CurrentCamera
	if not cam then
		cam = Instance.new("Camera")
		cam.Parent = workspace
		workspace.CurrentCamera = cam
	end
	local eye = me.Head.Position + Vector3.new(0, 0.2, -0.3)
	cam.CFrame = CFrame.lookAt(eye, eye + Vector3.new(0, -0.35, -1))
	local sent = {}
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
			AddRecoil = function() end,
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
	local function run(seconds)
		local t = os.clock()
		while os.clock() - t < seconds do
			WC.Step(1 / 60)
			VM.Step(1 / 60)
			task.wait()
		end
	end
	local function equip(name)
		local def = WeaponConfig.Weapons[name]
		me:SetAttribute("Weapon", name)
		WC.OnCharacter(me)
		task.wait(0.3)
		WC.ServerState({ Weapon = name, Ammo = def.Magazine, Reserve = def.Reserve, Mode = def.DefaultMode, Reloading = false, Reason = "Equip" })
		run(def.EquipTime + 0.1)
		table.clear(sent)
	end
	local function fires()
		local n = 0
		for _, e in ipairs(sent) do
			if e[1] == "Fire" then
				n = n + 1
			end
		end
		return n
	end
	-- дробовик: один выстрел — восемь следов дроби на полу
	equip("Shotgun")
	expect(VM.Exists(), "вид от первого лица дробовика")
	local holesBefore = 0
	for _, c in ipairs(workspace.Effects:GetChildren()) do
		if c.Name == "BulletHole" then
			holesBefore = holesBefore + 1
		end
	end
	WC.SetTrigger(true)
	run(0.2)
	WC.SetTrigger(false)
	eq(fires(), 1, "дробовик: один выстрел за нажатие")
	local holes = 0
	for _, c in ipairs(workspace.Effects:GetChildren()) do
		if c.Name == "BulletHole" then
			holes = holes + 1
		end
	end
	expect(holes - holesBefore >= 6, "следы дроби: " .. (holes - holesBefore))
	-- снайперская: после выстрела передёргивает затвор (прицел отходит), потом снова в прицел
	equip("Sniper")
	WC.SetAim(true)
	run(0.5)
	expect(WC.IsScoped(), "в оптическом прицеле")
	WC.SetTrigger(true)
	run(0.1)
	WC.SetTrigger(false)
	eq(fires(), 1, "снайперская: выстрел")
	expect(WC.IsCycling(), "передёргивает затвор")
	run(0.25)
	expect(not WC.IsScoped(), "на время затвора — не в прицеле")
	local parts = VM.Parts()
	run(0.15)
	local bolt = parts.Body.CFrame:PointToObjectSpace(parts.Bolt.Position) - WeaponModels.Sniper.Parts.ChargingHandle.Offset
	expect(bolt.Z > 0.1, string.format("рукоять затвора оттянута (%.2f)", bolt.Z))
	run(WeaponPoses.Sniper.Reloads.Cycle.Length)
	expect(not WC.IsCycling(), "затвор дослан")
	run(0.4)
	expect(WC.IsScoped(), "снова в прицеле")
	WC.SetAim(false)
	-- пистолет: удержание спуска — один выстрел
	equip("Pistol")
	WC.SetTrigger(true)
	run(0.8)
	WC.SetTrigger(false)
	eq(fires(), 1, "пистолет: полуавтомат")
	run(0.1)
	WC.SetTrigger(true)
	run(0.1)
	WC.SetTrigger(false)
	eq(fires(), 2, "пистолет: второе нажатие — второй выстрел")
	VM.Destroy()
	floor:Destroy()
	me:Destroy()
end)

testFolder:Destroy()

test("пять карт: сборка, точки появления на полу и не в стенах", function()
	local ids = {}
	for _, m in ipairs(Maps.List()) do
		table.insert(ids, m.Id)
	end
	for _, r in ipairs(MatchConfig.Rotation) do
		expect(Maps.Get(r.Map), "карта из ротации есть: " .. r.Map)
		expect(MatchConfig.Modes[r.Mode], "режим из ротации есть: " .. r.Mode)
	end
	eq(#ids, 5, "карт")
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Include
	local lines = {}
	for _, id in ipairs(ids) do
		local t0 = os.clock()
		local info = Maps.Load(id)
		local folder = Maps.Folder()
		params.FilterDescendantsInstances = { folder }
		overlap.FilterDescendantsInstances = { folder }
		expect(info and info.Parts > 300, id .. ": деталей " .. tostring(info and info.Parts))
		expect(#info.Spawns >= 16, id .. ": точек появления " .. #info.Spawns)
		expect(#info.TeamSpawns.Red >= 6 and #info.TeamSpawns.Blue >= 6, id .. ": командные точки")
		local bad = {}
		for i, cf in ipairs(info.Spawns) do
			local p = cf.Position
			local r = workspace:Raycast(p + Vector3.new(0, 2.5, 0), Vector3.new(0, -4, 0), params)
			local grounded = r and r.Instance.CanCollide and math.abs(r.Position.Y - p.Y) < 0.75
			local blockers = {}
			for _, part in ipairs(workspace:GetPartBoundsInBox(cf * CFrame.new(0, 3.1, 0), Vector3.new(2.6, 4.8, 2.6), overlap)) do
				if part.CanCollide and part.Transparency < 1 then
					table.insert(blockers, part.Name .. "@" .. (part.Parent and part.Parent.Name or "?"))
				end
			end
			if not grounded or #blockers > 0 then
				table.insert(bad, string.format("#%d (%.0f, %.1f, %.0f)%s%s", i, p.X, p.Y, p.Z, grounded and "" or " не на полу",
					#blockers > 0 and (" в " .. table.concat(blockers, ",")) or ""))
			end
		end
		expect(#bad == 0, id .. ": " .. table.concat(bad, "; "))
		table.insert(lines, string.format("%s %d дет. %d точек %.2f с", id, info.Parts, #info.Spawns, os.clock() - t0))
		Maps.Unload()
	end
	note(table.concat(lines, " | "))
end)

local function setupMatch(map, mode, nBots)
	Match.StartMatch(map, mode)
	for _ = 1, nBots do
		Bots.AddBot()
	end
	local list = Bots.List()
	for _, item in ipairs(list) do
		item.Identity.Model:SetAttribute("ProtectedUntil", 0)
	end
	Match.BeginFight()
	return list
end

local function endMatch()
	Match.Finish("Test")
	Match.ReturnToLobby()
end

test("FFA и TDM: свои и чужие", function()
	local list = setupMatch("CityBlock", "FFA", 3)
	eq(Match.Phase(), "Running", "фаза")
	local a, b = list[1].Identity, list[2].Identity
	expect(Match.CanDamage(a, b.Model), "FFA: все против всех")
	endMatch()
	list = setupMatch("MilitaryBase", "TDM", 4)
	local red, blue = {}, {}
	for _, item in ipairs(list) do
		local p = Match.Participant(item.Identity)
		if p.Team == "Red" then
			table.insert(red, item.Identity)
		elseif p.Team == "Blue" then
			table.insert(blue, item.Identity)
		end
	end
	expect(#red >= 1 and #blue >= 1, string.format("команды: красных %d, синих %d", #red, #blue))
	expect(Match.CanDamage(red[1], blue[1].Model), "по чужим — можно")
	if #red >= 2 then
		eq(Match.CanDamage(red[1], red[2].Model), false, "по своим — нельзя")
	elseif #blue >= 2 then
		eq(Match.CanDamage(blue[1], blue[2].Model), false, "по своим — нельзя")
	end
	-- урон по своему не проходит и через CombatSystem
	local mate = (#red >= 2 and red) or blue
	if #mate >= 2 then
		local hum = mate[2].Model:FindFirstChildOfClass("Humanoid")
		local before = hum.Health
		Combat.Damage(mate[2].Model, 50, { Attacker = mate[1], Weapon = "AK47", Cause = "Weapon" })
		eq(hum.Health, before, "здоровье своего не изменилось")
	end
	local hum = blue[1].Model:FindFirstChildOfClass("Humanoid")
	Combat.Damage(blue[1].Model, 500, { Attacker = red[1], Weapon = "AK47", Cause = "Weapon", Part = "UpperTorso" })
	eq(hum.Health, 0, "чужой убит")
	eq(Match.State().Scores.Red, 1, "очко команде")
	endMatch()
end)

test("GUN GAME: начинают с пистолета, после двух убийств — следующее оружие", function()
	local list = setupMatch("TestChamber", "GunGame", 3)
	local killer = list[1].Identity
	local first = MatchConfig.Modes.GunGame.Weapons[1]
	eq(killer.Model:GetAttribute("Weapon"), first, "первое оружие")
	for i = 2, 3 do
		local victim = list[i].Identity
		victim.Model:SetAttribute("ProtectedUntil", 0)
		Combat.Damage(victim.Model, 500, { Attacker = killer, Weapon = first, Cause = "Weapon", Part = "Head" })
	end
	local p = Match.Participant(killer)
	eq(p.GunLevel, 2, "уровень оружия")
	eq(killer.Model:GetAttribute("Weapon"), MatchConfig.Modes.GunGame.Weapons[2], "выдано следующее оружие")
	note("GUN GAME: " .. table.concat(MatchConfig.Modes.GunGame.Weapons, " → "))
	endMatch()
end)

test("CHAOS: взрыв ранит и убивает рядом, далеко — нет", function()
	local list = setupMatch("ConstructionSite", "Chaos", 3)
	local a, b = list[1].Identity, list[2].Identity
	a.Model:PivotTo(CFrame.new(0, 3, 70))
	b.Model:PivotTo(CFrame.new(60, 3, 70))
	local ha, hb = a.Model:FindFirstChildOfClass("Humanoid"), b.Model:FindFirstChildOfClass("Humanoid")
	local cfg = MatchConfig.Modes.Chaos.Strike
	Match.Explode(Vector3.new(0, 0, 70), cfg.Radius, cfg.Damage)
	expect(ha.Health <= 0, "в центре взрыва — погиб")
	eq(hb.Health, hb.MaxHealth, "далеко — цел")
	endMatch()
	eq(Bots.Count(), 0, "после матча боты убраны")
	eq(#workspace.ActiveMap:GetChildren(), 0, "карта выгружена")
end)

test("прогресс и магазин: цены, уровни, предметы существуют", function()
	local data = Progression.DefaultData()
	expect(data.Coins == ProgressionConfig.StartCoins and data.Level == 1, "новый профиль")
	expect(data.Loadout and WeaponConfig.Weapons[data.Loadout.Primary], "оружие по умолчанию")
	for id, item in pairs(ProgressionConfig.Weapons) do
		expect(WeaponConfig.Weapons[id], "в магазине несуществующее оружие " .. id)
		expect(item.Price >= 0 and item.Level >= 1, id .. ": цена/уровень")
	end
	for id in pairs(ProgressionConfig.Skins) do
		expect(SkinAssets[id], "нет текстуры окраски " .. id)
	end
	expect(ProgressionConfig.XpToNext(1) > 0 and ProgressionConfig.XpToNext(10) > ProgressionConfig.XpToNext(1), "опыт до уровня растёт")
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
