-- ProfileController: профиль игрока на клиенте (уровень, опыт, монеты, купленное, снаряжение, настройки)
-- и настройки, применённые к игре: чувствительность обзора, поле зрения, громкость (группы звуков
-- DC_Music, DC_SFX, DC_UI). Профиль присылает сервер (событие Profile), он же решает покупки.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Signal = require(Shared:WaitForChild("Signal"))
local Kit = require(script.Parent.Parent:WaitForChild("Ui"):WaitForChild("Kit"))

local ProfileController = { Name = "ProfileController" }

ProfileController.Changed = Signal.new() -- (profile)
ProfileController.Reward = Signal.new() -- (reward) за убийство / помощь
ProfileController.MatchRewards = Signal.new() -- (rewards) за матч
ProfileController.ShopResult = Signal.new() -- (result)

local net = nil
local profile = nil
local settings = { Sensitivity = 1, AimSensitivity = 0.72, Fov = 72, Master = 1, Music = 0.5, Sfx = 1, Crosshair = 1 }

function ProfileController.Get()
	return profile
end

function ProfileController.Settings()
	return settings
end

local function applySettings()
	local master = settings.Master
	Kit.SoundGroup("DC_Music").Volume = master * settings.Music
	Kit.SoundGroup("DC_SFX").Volume = master * settings.Sfx
	Kit.SoundGroup("DC_UI").Volume = master * math.max(settings.Sfx, 0.3)
end

-- Изменить настройку (сразу применяется; на сервер — Commit)
function ProfileController.SetSetting(key, value)
	settings[key] = value
	applySettings()
	ProfileController.Changed:Fire(profile)
end

function ProfileController.CommitSettings()
	if net then
		net.Fire("SaveSettings", {
			Sensitivity = settings.Sensitivity,
			AimSensitivity = settings.AimSensitivity,
			Fov = settings.Fov,
			Master = settings.Master,
			Music = settings.Music,
			Sfx = settings.Sfx,
			Crosshair = settings.Crosshair,
		})
	end
end

function ProfileController.Buy(category, id)
	return net.Fire("Buy", category, id)
end

function ProfileController.Equip(slot, id)
	return net.Fire("EquipItem", slot, id)
end

function ProfileController.Init(context)
	net = context.Get("ClientNet")
end

function ProfileController.Start()
	applySettings()
	net.On("Profile", function(p)
		if type(p) ~= "table" then
			return
		end
		profile = p
		if type(p.Settings) == "table" then
			for k, v in pairs(p.Settings) do
				if settings[k] ~= nil and type(v) == type(settings[k]) then
					settings[k] = v
				end
			end
			applySettings()
		end
		ProfileController.Changed:Fire(profile)
	end)
	net.On("Reward", function(r)
		if type(r) == "table" then
			ProfileController.Reward:Fire(r)
		end
	end)
	net.On("Rewards", function(r)
		if type(r) == "table" then
			ProfileController.MatchRewards:Fire(r)
		end
	end)
	net.On("ShopResult", function(r)
		if type(r) == "table" then
			ProfileController.ShopResult:Fire(r)
		end
	end)
	task.delay(3, function()
		if not profile then
			net.Fire("RequestProfile")
		end
	end)
end

return ProfileController
