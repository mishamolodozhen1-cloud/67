-- Проверка этапа 3 DUMMY COMBAT (регдолл) на сервере Roblox: python3 tools/cloud.py test 3
-- Физика на облачном сервере не идёт (её нельзя и шагнуть вручную), поэтому здесь проверяется всё,
-- что не требует движения: устройство суставов, пределы против всех кадров анимаций, переключение
-- туда-обратно, толчки по частям, взрыв, тела, группы столкновений. Само падение — стенд в Studio.
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
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
		error(string.format("%s: ждали %.3f, получили %.3f", msg or "", b, a), 2)
	end
end

local Configs = ReplicatedStorage.Configs
local RagdollConfig = require(Configs.RagdollConfig)
local DummyRig = require(Configs.DummyRig)
local DummyAssets = require(Configs.DummyAssets)

local Bootstrap = require(ServerScriptService.Server.Bootstrap)
local report = Bootstrap.Start()
local Ragdoll = Bootstrap.Get("RagdollSystem")
local Dev = Bootstrap.Get("DevSystem")
local Net = Bootstrap.Get("NetService")

local template = StarterPlayer:FindFirstChild("StarterCharacter")
local floor = Instance.new("Part")
floor.Name = "TestFloor"
floor.Anchored = true
floor.Size = Vector3.new(400, 2, 400)
floor.CFrame = CFrame.new(0, -1, 0)
floor.Parent = workspace
local dummyFolder = workspace:FindFirstChild("DevDummies") or Instance.new("Folder")
dummyFolder.Name = "DevDummies"
dummyFolder.Parent = workspace

local function spawnAt(x, z, parent)
	local d = template:Clone()
	d:PivotTo(CFrame.new(x, DummyRig.HipHeight + DummyRig.RootSize.Y / 2, z))
	d.Parent = parent or dummyFolder
	Ragdoll.OnSpawn(d)
	return d
end

test("запуск с регдоллом", function()
	eq(report.State, "Ready", "состояние сервера")
	for _, name in ipairs({ "RagdollSystem", "CharacterSystem", "MovementSystem", "DevSystem" }) do
		eq(report.Status[name], "Started", name)
	end
end)

test("шаблон: суставы регдолла готовы и выключены", function()
	expect(template, "нет шаблона")
	local hum = template.Humanoid
	eq(hum.BreakJointsOnDeath, false, "BreakJointsOnDeath")
	eq(hum.RequiresNeck, false, "RequiresNeck")
	local balls, hinges, nocol = 0, 0, 0
	for _, d in ipairs(template:GetDescendants()) do
		if d:IsA("BallSocketConstraint") then
			balls = balls + 1
			expect(not d.Enabled and d.LimitsEnabled and d.TwistLimitsEnabled, d.Name .. ": включён или без пределов")
		elseif d:IsA("HingeConstraint") then
			hinges = hinges + 1
			expect(not d.Enabled and d.LimitsEnabled, d.Name .. ": включён или без пределов")
		elseif d:IsA("NoCollisionConstraint") then
			nocol = nocol + 1
		end
	end
	eq(balls, 10, "шаровых суставов")
	eq(hinges, 4, "шарниров (локти, колени)")
	eq(nocol, 14, "запретов столкновения соседних частей")
	for _, spec in ipairs(DummyRig.Parts) do
		eq(template[spec.Name].CollisionFidelity, Enum.CollisionFidelity.Hull, spec.Name .. ".CollisionFidelity")
	end
end)

test("группы столкновений", function()
	local g = RagdollConfig.CollisionGroups
	eq(PhysicsService:CollisionGroupsAreCollidable(g.Ragdoll, g.Characters), false, "регдолл ↔ живые")
	eq(PhysicsService:CollisionGroupsAreCollidable(g.Ragdoll, "Default"), true, "регдолл ↔ мир")
	eq(PhysicsService:CollisionGroupsAreCollidable(g.Ragdoll, g.Ragdoll), true, "регдолл ↔ регдолл")
	eq(PhysicsService:CollisionGroupsAreCollidable(g.Characters, g.Characters), true, "живые ↔ живые")
end)

-- знак угла шарнира — по самому Roblox (HingeConstraint.CurrentAngle)
local hingeSign = 1
test("знак угла шарнира (калибровка по Roblox)", function()
	local a = Instance.new("Part")
	a.Anchored = true
	a.CFrame = CFrame.new(50, 10, 50)
	a.Parent = workspace
	local b = Instance.new("Part")
	b.Anchored = true
	b.Parent = workspace
	local f = CFrame.fromMatrix(Vector3.zero, Vector3.new(1, 0, 0), Vector3.new(0, -1, 0))
	local a0 = Instance.new("Attachment")
	a0.CFrame = f
	a0.Parent = a
	local a1 = Instance.new("Attachment")
	a1.CFrame = f
	a1.Parent = b
	local h = Instance.new("HingeConstraint")
	h.Attachment0 = a0
	h.Attachment1 = a1
	h.Parent = a
	b.CFrame = a.CFrame * CFrame.Angles(math.rad(30), 0, 0)
	local angle = h.CurrentAngle
	expect(math.abs(math.abs(angle) - 30) < 0.5, "CurrentAngle " .. tostring(angle))
	hingeSign = angle > 0 and 1 or -1
	note(string.format("поворот +30° вокруг оси шарнира → CurrentAngle %.1f", angle))
	a:Destroy()
	b:Destroy()
end)

-- Углы сустава при повороте дочерней части R (относительно родительской), как их считает Roblox
local function jointAngles(def, R)
	local Rig = Ragdoll.Rig
	local f0, f1 = Rig.AttachmentFrames(def, Vector3.zero, Vector3.zero)
	local w1 = R * f1
	if def.Type == "Hinge" then
		local x0, y0, y1 = f0.XVector, f0.YVector, w1.YVector
		return hingeSign * math.deg(math.atan2(y0:Cross(y1):Dot(x0), y0:Dot(y1)))
	end
	local x0, y0 = f0.XVector, f0.YVector
	local x1, y1 = w1.XVector, w1.YVector
	local cone = math.deg(math.acos(math.clamp(x0:Dot(x1), -1, 1)))
	-- поворот-колебание (swing), совмещающий оси, затем закрутка (twist) между вторыми осями
	local axis = x1:Cross(x0)
	if axis.Magnitude > 1e-6 then
		y1 = CFrame.fromAxisAngle(axis.Unit, math.acos(math.clamp(x1:Dot(x0), -1, 1))) * y1
	end
	local twist = math.deg(math.atan2(y0:Cross(y1):Dot(x0), y0:Dot(y1)))
	return cone, twist
end

test("пределы суставов: поза покоя и все кадры всех анимаций внутри", function()
	local worst = {}
	local function check(joint, def, R, where)
		if def.Type == "Hinge" then
			local a = jointAngles(def, R)
			local over = math.max(def.Lower - a, a - def.Upper)
			if over > (worst[joint] and worst[joint].Over or -math.huge) then
				worst[joint] = { Over = over, Where = where, Value = string.format("%.1f°", a) }
			end
		else
			local cone, twist = jointAngles(def, R)
			local over = math.max(cone - def.Cone, def.TwistLower - twist, twist - def.TwistUpper)
			if over > (worst[joint] and worst[joint].Over or -math.huge) then
				worst[joint] = { Over = over, Where = where, Value = string.format("конус %.1f° закрутка %.1f°", cone, twist) }
			end
		end
	end
	-- сустав -> дочерняя часть (поза в анимации называется её именем)
	local childOf = {}
	for _, j in ipairs(DummyRig.Joints) do
		childOf[j[1]] = j[3]
	end
	for joint, def in pairs(RagdollConfig.Joints) do
		check(joint, def, CFrame.identity, "покой")
	end
	local frames = 0
	for name, a in pairs(DummyAssets.Animations) do
		local ks = KeyframeSequenceProvider:GetKeyframeSequenceAsync(a.Id)
		for _, kf in ipairs(ks:GetKeyframes()) do
			local poses = {}
			for _, p in ipairs(kf:GetDescendants()) do
				if p:IsA("Pose") then
					poses[p.Name] = p.CFrame
				end
			end
			for joint, def in pairs(RagdollConfig.Joints) do
				local pose = poses[childOf[joint]] or CFrame.identity
				check(joint, def, pose.Rotation, name .. string.format(" %.2f с", kf.Time))
			end
			frames = frames + 1
		end
	end
	local bad, summary = {}, {}
	for joint, w in pairs(worst) do
		table.insert(summary, string.format("%s %+.0f", joint, w.Over))
		if w.Over > 1 then
			table.insert(bad, string.format("%s: %s (%s), за пределом на %.1f°", joint, w.Value, w.Where, w.Over))
		end
	end
	table.sort(summary)
	note(string.format("проверено кадров: %d; запас до предела (минус — внутри): %s", frames, table.concat(summary, ", ")))
	expect(#bad == 0, table.concat(bad, " | "))
end)

test("регдолл и подъём: всё возвращается как было", function()
	local d = spawnAt(0, 0)
	local snap = {}
	for _, p in ipairs(d:GetChildren()) do
		if p:IsA("BasePart") then
			snap[p.Name] = { p.CanCollide, p.Massless, p.CollisionGroup }
		end
	end
	local head = d.Head
	expect(Ragdoll.Ragdoll(d, "Knockdown", { { Part = head, Velocity = Vector3.new(0, 0, 30) } }), "Ragdoll")
	expect(Ragdoll.IsRagdolled(d) and d:GetAttribute("RagdollReason") == "Knockdown", "атрибуты регдолла")
	for _, m in ipairs(d:GetDescendants()) do
		if m:IsA("Motor6D") then
			eq(m.Enabled, m.Name == "Root", m.Name .. ".Enabled в регдолле")
		elseif m:IsA("BallSocketConstraint") or m:IsA("HingeConstraint") then
			eq(m.Enabled, true, m.Name .. ".Enabled в регдолле")
		end
	end
	for _, p in ipairs(d:GetChildren()) do
		if p:IsA("BasePart") then
			eq(p.CollisionGroup, RagdollConfig.CollisionGroups.Ragdoll, p.Name .. ".CollisionGroup")
			if p.Name == "HumanoidRootPart" then
				expect(not p.CanCollide and p.Massless, "HumanoidRootPart в регдолле: без столкновений и невесомая")
			else
				expect(p.CanCollide, p.Name .. " в регдолле должна сталкиваться")
			end
		end
	end
	near(head.AssemblyLinearVelocity.Z, 30, 0.5, "толчок головы")
	-- поднять: стоит на полу, всё как было
	d:PivotTo(CFrame.new(60, 1.2, 40) * CFrame.Angles(math.rad(80), 0, 0)) -- подальше от площадки появления
	expect(Ragdoll.Recover(d), "Recover")
	expect(not Ragdoll.IsRagdolled(d), "после подъёма не в регдолле")
	for _, p in ipairs(d:GetChildren()) do
		if p:IsA("BasePart") then
			local s = snap[p.Name]
			expect(p.CanCollide == s[1] and p.Massless == s[2] and p.CollisionGroup == s[3], p.Name .. ": не вернулось как было")
		end
	end
	for _, m in ipairs(d:GetDescendants()) do
		if m:IsA("Motor6D") then
			eq(m.Enabled, true, m.Name .. ".Enabled после подъёма")
		elseif m:IsA("BallSocketConstraint") or m:IsA("HingeConstraint") then
			eq(m.Enabled, false, m.Name .. ".Enabled после подъёма")
		end
	end
	local root = d.HumanoidRootPart
	near(root.Position.Y, DummyRig.HipHeight + DummyRig.RootSize.Y / 2, 0.05, "высота после подъёма (стоит на полу)")
	expect(root.CFrame.UpVector.Y > 0.99, "после подъёма стоит вертикально")
	d:Destroy()
end)

test("смерть: толчок от попадания, разные части — разная реакция", function()
	local a = spawnAt(20, 0)
	Ragdoll.Track(a)
	Ragdoll.RecordHit(a, "Head", Vector3.new(0, 0, 1), 1, a.Head.Position)
	a.Humanoid.Health = 0
	task.wait(0.2)
	expect(Ragdoll.IsRagdolled(a) and a:GetAttribute("RagdollReason") == "Death", "после смерти — регдолл")
	near(a.Head.AssemblyLinearVelocity.Z, RagdollConfig.Hit.PartSpeed, 0.5, "голова получила полный толчок")
	near(a.UpperTorso.AssemblyLinearVelocity.Z, RagdollConfig.Hit.BodySpeed, 0.5, "корпус — долю")
	expect(a.Head.AssemblyAngularVelocity.Magnitude > 1, "голова запрокидывается")
	local b = spawnAt(30, 0)
	Ragdoll.Track(b)
	Ragdoll.RecordHit(b, "LeftLowerLeg", Vector3.new(1, 0, 0), 1, b.LeftLowerLeg.Position)
	b.Humanoid.Health = 0
	task.wait(0.2)
	near(b.LeftLowerLeg.AssemblyLinearVelocity.X, RagdollConfig.Hit.PartSpeed, 0.5, "голень получила полный толчок")
	expect(b.Head.AssemblyLinearVelocity.Magnitude < 0.5, "голова при попадании в ногу не толкается")
	-- старое попадание (за окном) толчка не даёт
	local c = spawnAt(40, 0)
	Ragdoll.Track(c)
	Ragdoll.RecordHit(c, "Head", Vector3.new(0, 0, 1), 1)
	task.wait(RagdollConfig.Hit.Window + 0.15)
	c.Humanoid.Health = 0
	task.wait(0.2)
	expect(Ragdoll.IsRagdolled(c), "регдолл и без толчка")
	expect(c.Head.AssemblyLinearVelocity.Magnitude < 0.5, "давнее попадание не толкает")
	for _, m in ipairs({ a, b, c }) do
		m:Destroy()
	end
end)

test("взрыв: близко — смерть, дальше — падение, далеко — ничего; ближняя часть летит сильнее", function()
	local center = Vector3.new(100, 1, 0)
	local near1 = spawnAt(103, 0)
	local mid = spawnAt(112, 0)
	local far = spawnAt(160, 0)
	for _, m in ipairs({ near1, mid, far }) do
		Ragdoll.Track(m)
	end
	local affected = Ragdoll.Explode(center, 18, 1, { LethalRadius = 5 })
	local effect = {}
	for _, e in ipairs(affected) do
		effect[e.Model] = e.Effect
	end
	eq(effect[near1], "Killed", "ближний")
	eq(effect[mid], "Knocked", "средний")
	eq(effect[far], nil, "дальний")
	expect(near1.Humanoid.Health == 0 and Ragdoll.IsRagdolled(near1), "ближний погиб и лежит")
	expect(mid.Humanoid.Health > 0 and Ragdoll.IsRagdolled(mid) and mid:GetAttribute("RagdollReason") == "Knockdown", "средний упал живым")
	expect(not Ragdoll.IsRagdolled(far), "дальний стоит")
	-- у среднего: часть ближе к взрыву летит сильнее (левая сторона ближе к центру)
	local nearSide = mid.LeftUpperArm.AssemblyLinearVelocity.Magnitude
	local farSide = mid.RightUpperArm.AssemblyLinearVelocity.Magnitude
	expect(nearSide > farSide, string.format("ближняя рука %.1f, дальняя %.1f", nearSide, farSide))
	local up = mid.UpperTorso.AssemblyLinearVelocity
	expect(up.Y > 0 and up.X > 0, "толчок от центра и вверх")
	Ragdoll.Recover(mid)
	for _, m in ipairs({ near1, mid, far }) do
		m:Destroy()
	end
end)

test("тела: отделение, засыпание, лимит, пробуждение взрывом", function()
	local corpses = workspace:FindFirstChild("Corpses")
	expect(corpses, "нет папки Corpses")
	local first = spawnAt(200, 0)
	Ragdoll.Ragdoll(first, "Death")
	for _, p in ipairs(first:GetChildren()) do
		if p:IsA("BasePart") then
			p.AssemblyLinearVelocity = Vector3.zero
		end
	end
	expect(Ragdoll.DetachCorpse(nil, first) == first, "DetachCorpse")
	eq(first.Parent, corpses, "тело в Corpses")
	eq(first:GetAttribute("DC_Corpse"), true, "атрибут тела")
	for _ = 1, 8 do
		Ragdoll.StepCorpses(0.25)
	end
	local sleeping = false
	for _, c in ipairs(Ragdoll.Corpses()) do
		if c.Model == first then
			sleeping = c.Sleeping
		end
	end
	expect(sleeping and first.UpperTorso.Anchored, "неподвижное тело заснуло (части закреплены)")
	-- взрыв будит тело
	local hit = Ragdoll.Explode(first.UpperTorso.Position + Vector3.new(2, 0, 0), 10, 1)
	expect(#hit >= 1 and hit[1].Effect == "Pushed", "взрыв толкнул тело")
	expect(not first.UpperTorso.Anchored, "тело проснулось")
	-- лимит тел
	local max = RagdollConfig.Corpses.Max
	local made = {}
	for i = 1, max + 2 do
		local d = spawnAt(220 + i * 6, 0)
		Ragdoll.Ragdoll(d, "Death")
		Ragdoll.DetachCorpse(nil, d)
		table.insert(made, d)
	end
	eq(#Ragdoll.Corpses(), max, "тел не больше лимита")
	expect(first.Parent == nil, "самое старое тело убрано")
	expect(made[#made].Parent == corpses, "новое тело на месте")
	-- живого не отделить (не в регдолле)
	local alive = spawnAt(300, 0)
	eq(Ragdoll.DetachCorpse(nil, alive), nil, "живого в тела не превратить")
	alive:Destroy()
end)

test("стенд проверки выключен вне Studio, команды проверяются", function()
	eq(Dev.IsActive(), false, "стенд вне Studio")
	expect(not Dev.Run({ Name = "X", UserId = -1 }, "Stats"), "команда вне Studio")
	local got = 0
	local handler = Net.BuildHandler("DevCommand", function()
		got = got + 1
	end)
	local fake = { Name = "FakeDev", UserId = -70 }
	function fake:Kick() end
	handler(fake, "Explode", Vector3.new(1, 2, 3))
	handler(fake, "Stats")
	handler(fake, "DeleteMap")
	handler(fake, "Explode", Vector3.new(0 / 0, 0, 0))
	eq(got, 2, "верные команды прошли, неверные — нет")
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
