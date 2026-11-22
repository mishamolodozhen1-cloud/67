-- NIGHT SHIFT — клиент (LocalScript «NightClient» в StarterPlayer.StarterPlayerScripts).
-- Дочерние ModuleScript: UI, Audio, Weather, HUD, Controls, CameraSystem, Effects, Cinematic.
-- Здесь создаётся общая таблица ctx, загружаются настройки игрока и подключаются события сервера.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

if not game:IsLoaded() then
	game.Loaded:Wait()
end

local player = Players.LocalPlayer
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local State = ReplicatedStorage:WaitForChild("GameState")

-- Лишние стандартные элементы интерфейса (здоровья и рюкзака в игре нет)
pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
end)

local ctx = {
	Player = player,
	Remotes = Remotes,
	State = State,
	CameraLocked = false,
	IntroPlaying = false,
	-- настройки по умолчанию (потом подменяются сохранёнными)
	Settings = {
		Music = 0.6,
		Sfx = 1,
		Brightness = 0,
		Fov = 80,
		HeadBob = true,
		Subtitles = true,
	},
}

ctx.UI = require(script:WaitForChild("UI"))
ctx.Audio = require(script:WaitForChild("Audio"))
ctx.Weather = require(script:WaitForChild("Weather"))
-- щелчок у всех кнопок интерфейса
ctx.UI.ClickSound = function()
	ctx.Audio.Play("UiClick", nil, 0.4)
end

-------------------------------------------------------------------------------
-- Главное меню (публичный сервер): только меню на фоне ночного магазина
-------------------------------------------------------------------------------
while State:GetAttribute("Mode") == nil do
	State:GetAttributeChangedSignal("Mode"):Wait()
end
ctx.Mode = State:GetAttribute("Mode")
if ctx.Mode == "Hub" then
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
	end)
	ctx.Menu = require(script:WaitForChild("Menu"))
	ctx.Effects = require(script:WaitForChild("Effects"))
	ctx.Audio.Init(ctx)
	ctx.Weather.Init(ctx)
	ctx.Menu.Init(ctx)
	ctx.Audio.SetVolumes(ctx.Settings.Music, ctx.Settings.Sfx)
	Remotes:WaitForChild("Notify").OnClientEvent:Connect(function(text, style)
		ctx.Menu.Toast(text, style)
	end)
	task.spawn(function()
		ctx.Effects.Init(ctx)
	end)
	task.spawn(function()
		local ok, profile = pcall(function()
			return Remotes:WaitForChild("GetProfile"):InvokeServer()
		end)
		if ok and type(profile) == "table" then
			if type(profile.Settings) == "table" then
				for k, v in pairs(profile.Settings) do
					if ctx.Settings[k] ~= nil and type(v) == type(ctx.Settings[k]) then
						ctx.Settings[k] = v
					end
				end
			end
			ctx.Audio.SetVolumes(ctx.Settings.Music, ctx.Settings.Sfx)
			ctx.Menu.SetProfile(profile)
		end
	end)
	return
end

ctx.HUD = require(script:WaitForChild("HUD"))
ctx.Controls = require(script:WaitForChild("Controls"))
ctx.Cameras = require(script:WaitForChild("CameraSystem"))
ctx.Effects = require(script:WaitForChild("Effects"))
ctx.Cinematic = require(script:WaitForChild("Cinematic"))

function ctx.ApplySettings()
	ctx.Audio.SetVolumes(ctx.Settings.Music, ctx.Settings.Sfx)
	ctx.Controls.ApplySettings()
end

ctx.Audio.Init(ctx)
ctx.Weather.Init(ctx)
ctx.HUD.Init(ctx)
ctx.Controls.Init(ctx)
ctx.Cameras.Init(ctx)
ctx.Cinematic.Init(ctx)
ctx.ApplySettings()

-------------------------------------------------------------------------------
-- События сервера
-------------------------------------------------------------------------------
local NOTIFY_SOUND = { task = "CameraSwitch", done = "Scan" }

Remotes:WaitForChild("Notify").OnClientEvent:Connect(function(text, style)
	ctx.HUD.Notify(text, style)
	if NOTIFY_SOUND[style] then
		ctx.Audio.Play(NOTIFY_SOUND[style], nil, 0.45)
	end
end)

Remotes:WaitForChild("Phone").OnClientEvent:Connect(function(sender, text)
	ctx.HUD.Phone(sender, text)
	ctx.Audio.Play("Phone", nil, 0.7)
end)

Remotes:WaitForChild("Subtitle").OnClientEvent:Connect(function(speaker, text, seconds)
	ctx.HUD.Subtitle(speaker, text, seconds)
end)

Remotes:WaitForChild("Sound").OnClientEvent:Connect(function(name, position, volume, pitch, fx)
	ctx.Audio.Play(name, position, volume, pitch, fx)
end)

local EFFECTS = {
	OpenCameras = function()
		ctx.Cameras.Open()
	end,
	Battery = function()
		ctx.Controls.RefillBattery()
	end,
	Flicker = function(data)
		ctx.Effects.Flicker(data)
	end,
	LampsOut = function(data)
		ctx.Effects.LampsOut(data)
	end,
	Intro = function(data)
		ctx.Cinematic.Play(data)
	end,
	Apparition = function(data)
		ctx.Effects.Apparition(data)
	end,
	Caught = function(data)
		ctx.Effects.Caught(data)
	end,
	LightsChase = function(data)
		ctx.Effects.LightsChase(data)
	end,
	BehindYou = function(data)
		ctx.Effects.BehindYou(data or {})
	end,
	Read = function(data)
		ctx.HUD.ShowDocument(data)
	end,
	VhsTape = function(data)
		ctx.Cameras.PlayTape(data)
	end,
	Ending = function(stats)
		ctx.Effects.Ending(stats)
	end,
}

Remotes:WaitForChild("Effect").OnClientEvent:Connect(function(name, data)
	local fn = EFFECTS[name]
	if fn then
		local ok, err = pcall(fn, data)
		if not ok then
			warn("[Эффект " .. tostring(name) .. "] " .. tostring(err))
		end
	end
end)

-- Свет, монстр и сцены (ждут, пока сервер построит магазин)
task.spawn(function()
	ctx.Effects.Init(ctx)
end)

-- Сохранённый профиль: настройки и статистика
task.spawn(function()
	local ok, profile = pcall(function()
		return Remotes:WaitForChild("GetProfile"):InvokeServer()
	end)
	if ok and type(profile) == "table" then
		if type(profile.Settings) == "table" then
			for k, v in pairs(profile.Settings) do
				if ctx.Settings[k] ~= nil and type(v) == type(ctx.Settings[k]) then
					ctx.Settings[k] = v
				end
			end
		end
		ctx.ApplySettings()
		ctx.HUD.RefreshSettings()
		ctx.HUD.SetProfile(profile)
	end
end)
