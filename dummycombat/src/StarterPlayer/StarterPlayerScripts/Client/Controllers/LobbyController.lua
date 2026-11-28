-- LobbyController: лобби на клиенте (этап 8) — камера меню, свой манекен на подиуме, музыка.
--
-- Пока игрок не в матче (атрибут InMatch = false): камера неподвижна (чуть плавает) и смотрит на подиум,
-- управление персонажем выключено (открыто главное меню), играет музыка лобби. На подиуме — свой манекен
-- в выбранной окраске с выбранным оружием в руках (поза — как у других игроков в матче, руки — по ИК).
-- Вошёл в матч — обычная камера от первого лица, управление включено, музыка затихает.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Configs = ReplicatedStorage:WaitForChild("Configs")
local Signal = require(Shared:WaitForChild("Signal"))
local ArmIK = require(Shared:WaitForChild("ArmIK"))
local DummyRig = require(Configs:WaitForChild("DummyRig"))
local WeaponPoses = require(Configs:WaitForChild("WeaponPoses"))
local WeaponModels = require(Configs:WaitForChild("WeaponModels"))
local WeaponConfig = require(Configs:WaitForChild("WeaponConfig"))
local SkinAssets = require(Configs:WaitForChild("SkinAssets"))
local UiAssets = require(Configs:WaitForChild("UiAssets"))
local Kit = require(script.Parent.Parent:WaitForChild("Ui"):WaitForChild("Kit"))

local LobbyController = { Name = "LobbyController" }

LobbyController.ModeChanged = Signal.new() -- (inLobby)

local profileCtl, characters = nil, nil
local inLobby = nil
local showcase = nil -- { Model, Parts, Gun, Weapon, Skin }
local music = nil
local controls = nil
local t0 = os.clock()

local OFFSETS = {}
for _, spec in ipairs(DummyRig.Parts) do
	OFFSETS[spec.Name] = spec.Offset
end
local ROOT_Y = DummyRig.HipHeight + DummyRig.RootSize.Y / 2

function LobbyController.InLobby()
	return inLobby == true
end

local function getControls()
	if controls then
		return controls
	end
	local ok, module = pcall(function()
		return require(Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule", 10))
	end)
	if ok and module then
		controls = module:GetControls()
	end
	return controls
end

local function anchor()
	local hangar = workspace:FindFirstChild("Lobby") and workspace.Lobby:FindFirstChild("Hangar")
	return hangar and hangar:FindFirstChild("Showcase")
end

-------------------------------------------------------------------------------
-- Манекен на подиуме
-------------------------------------------------------------------------------
local function clearShowcase()
	if showcase then
		showcase.Model:Destroy()
		showcase = nil
	end
end

local function buildShowcase(weaponName, skin)
	clearShowcase()
	local template = StarterPlayer:FindFirstChild("StarterCharacter")
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local weapons = assets and assets:FindFirstChild("Weapons")
	if not template then
		return
	end
	local model = Instance.new("Model")
	model.Name = "ShowcaseDummy"
	local parts = {}
	for _, spec in ipairs(DummyRig.Parts) do
		local src = template:FindFirstChild(spec.Name)
		if src then
			local p = src:Clone()
			p:ClearAllChildren()
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			if p:IsA("MeshPart") and SkinAssets[skin] then
				p.TextureID = SkinAssets[skin]
			end
			p.Parent = model
			parts[spec.Name] = p
		end
	end
	local gun = nil
	local gunTemplate = weapons and weapons:FindFirstChild(weaponName)
	if gunTemplate then
		gun = gunTemplate:Clone()
		for _, d in ipairs(gun:GetDescendants()) do
			if d:IsA("Motor6D") then
				d:Destroy()
			elseif d:IsA("BasePart") then
				d.Anchored = true
				d.CanQuery = false
			end
		end
		gun.Parent = model
	end
	model.Parent = workspace:FindFirstChild("Lobby") or workspace
	showcase = { Model = model, Parts = parts, Gun = gun, Weapon = weaponName, Skin = skin }
end

local function poseShowcase()
	local a = anchor()
	if not (showcase and a) then
		return
	end
	-- модели оружия сервер загружает при запуске: если к сборке витрины их ещё не было — собрать заново
	if not showcase.Gun and os.clock() - (showcase.Retry or 0) > 1 then
		showcase.Retry = os.clock()
		local assets = ReplicatedStorage:FindFirstChild("Assets")
		local weapons = assets and assets:FindFirstChild("Weapons")
		if weapons and weapons:FindFirstChild(showcase.Weapon) then
			buildShowcase(showcase.Weapon, showcase.Skin)
			return
		end
	end
	local poses = WeaponPoses[showcase.Weapon]
	local geo = WeaponModels[showcase.Weapon]
	local t = os.clock() - t0
	local rootCF = a.CFrame * CFrame.new(0, ROOT_Y, 0)
	local tp = poses and poses.ThirdPerson
	local twist = tp and tp.Twist or 0
	local breath = math.sin(t * 1.4) * 0.012
	-- корпус: поворот у пояса (боевая стойка), голова — обратно вперёд
	local waist = OFFSETS.LowerTorso + Vector3.new(0, 0.2772, -0.0038)
	local ut = rootCF * CFrame.new(waist) * CFrame.Angles(breath, twist, 0) * CFrame.new(-waist) * CFrame.new(OFFSETS.UpperTorso)
	local neck = Vector3.new(0, 0.73, 0.0113)
	local head = ut * CFrame.new(neck) * CFrame.Angles(0, -twist, 0) * CFrame.Angles(-breath, 0, 0) * CFrame.new(-neck) * CFrame.new(OFFSETS.Head - OFFSETS.UpperTorso)
	local list, frames = {}, {}
	local function put(name, cf)
		local p = showcase.Parts[name]
		if p then
			table.insert(list, p)
			table.insert(frames, cf)
		end
	end
	for name, off in pairs(OFFSETS) do
		if not string.find(name, "Arm") and not string.find(name, "Hand") and name ~= "UpperTorso" and name ~= "Head" then
			put(name, rootCF * CFrame.new(off))
		end
	end
	put("UpperTorso", ut)
	put("Head", head)
	if tp and showcase.Gun and geo then
		local hold = tp.Poses.Ready * CFrame.Angles(math.sin(t * 1.1) * 0.01, 0, 0)
		local gunCF = ut * hold
		local gun = showcase.Gun
		table.insert(list, gun.Body)
		table.insert(frames, gunCF)
		if gun:FindFirstChild("Magazine") then
			table.insert(list, gun.Magazine)
			table.insert(frames, gunCF * CFrame.new(geo.Parts.Magazine.Offset))
		end
		if gun:FindFirstChild("ChargingHandle") then
			table.insert(list, gun.ChargingHandle)
			table.insert(frames, gunCF * CFrame.new(geo.Parts.ChargingHandle.Offset))
		end
		for _, side in ipairs({ "Right", "Left" }) do
			local upper, lower, hand = ArmIK.Solve(side, ArmIK.Dims[side].ShoulderTorso, hold * poses.Hands[side], tp.Poles[side])
			put(side .. "UpperArm", ut * upper)
			put(side .. "LowerArm", ut * lower)
			put(side .. "Hand", ut * hand)
		end
	else
		for _, side in ipairs({ "Left", "Right" }) do
			for _, n in ipairs({ "UpperArm", "LowerArm", "Hand" }) do
				put(side .. n, rootCF * CFrame.new(OFFSETS[side .. n]))
			end
		end
	end
	workspace:BulkMoveTo(list, frames, Enum.BulkMoveMode.FireCFrameChanged)
end

-------------------------------------------------------------------------------
-- Камера и режимы
-------------------------------------------------------------------------------
local function menuCamera()
	local a = anchor()
	local camera = workspace.CurrentCamera
	if not a then
		return
	end
	camera.CameraType = Enum.CameraType.Scriptable
	local t = os.clock() - t0
	local target = a.Position + Vector3.new(0, 4.4, 0)
	local fwd = a.CFrame.LookVector
	local right = a.CFrame.RightVector
	local sway = math.sin(t * 0.22) * 0.9
	local pos = target + fwd * 12.5 + right * (1.5 + sway) + Vector3.new(0, 1.4 + math.sin(t * 0.17) * 0.25, 0)
	local camRight = (target - pos):Cross(Vector3.yAxis).Unit
	local lookAt = target + camRight * 2.6 - Vector3.new(0, 0.2, 0)
	camera.CFrame = CFrame.lookAt(pos, lookAt)
	camera.FieldOfView = 50
end

local function setMusic(on)
	if not music then
		music = Instance.new("Sound")
		music.Name = "LobbyMusic"
		music.SoundId = UiAssets.Music.Lobby
		music.Looped = true
		music.Volume = 0
		music.SoundGroup = Kit.SoundGroup("DC_Music")
		music.Parent = workspace.CurrentCamera
	end
	if on and not music.IsPlaying then
		music:Play()
	end
	TweenService:Create(music, TweenInfo.new(on and 2 or 1.2), { Volume = on and 0.55 or 0 }):Play()
	if not on then
		task.delay(1.3, function()
			if not inLobby and music.Volume < 0.01 then
				music:Pause()
			end
		end)
	end
end

local function setLobby(on)
	if inLobby == on then
		return
	end
	inLobby = on
	local c = getControls()
	if on then
		if c then
			c:Disable()
		end
		Players.LocalPlayer.CameraMode = Enum.CameraMode.Classic
		local p = profileCtl.Get()
		buildShowcase(p and p.Loadout and p.Loadout.Primary or WeaponConfig.Default, p and p.Loadout and p.Loadout.Skin or "Classic")
	else
		if c then
			c:Enable()
		end
		clearShowcase()
		local camera = workspace.CurrentCamera
		camera.CameraType = Enum.CameraType.Custom
		local _, humanoid = characters.GetCharacter()
		if humanoid then
			camera.CameraSubject = humanoid
		end
		Players.LocalPlayer.CameraMode = Enum.CameraMode.LockFirstPerson
	end
	setMusic(on)
	LobbyController.ModeChanged:Fire(on)
end

local function refresh()
	local player = Players.LocalPlayer
	setLobby(player:GetAttribute("InMatch") ~= true)
end

function LobbyController.Init(context)
	profileCtl = context.Get("ProfileController")
	characters = context.Get("CharacterController")
end

function LobbyController.Start()
	local player = Players.LocalPlayer
	player:GetAttributeChangedSignal("InMatch"):Connect(refresh)
	characters.CharacterChanged:Connect(function()
		-- новый персонаж: CameraController вернул камеру от первого лица — в лобби снова камера меню
		task.defer(function()
			if inLobby then
				Players.LocalPlayer.CameraMode = Enum.CameraMode.Classic
				local c = getControls()
				if c then
					c:Disable()
				end
			end
		end)
		refresh()
	end)
	profileCtl.Changed:Connect(function(p)
		if inLobby and p and p.Loadout then
			if not showcase or showcase.Weapon ~= p.Loadout.Primary or showcase.Skin ~= p.Loadout.Skin then
				buildShowcase(p.Loadout.Primary, p.Loadout.Skin)
			end
		end
	end)
	RunService:BindToRenderStep("DC_Lobby", Enum.RenderPriority.Camera.Value + 3, function()
		if inLobby then
			menuCamera()
			poseShowcase()
		end
	end)
	refresh()
end

return LobbyController
