-- Матч: меню паузы (II / M) поверх HUD
local Signal = M.Signal
dofile_match = true
SetupMatch({ Phase = "Running", EndsAt = 1000 + 200, Mode = "FFA", ModeName = "FREE FOR ALL", Map = "TestChamber", MapName = "TEST CHAMBER", ScoreLimit = 25 })
game:GetService("Players").LocalPlayer:SetAttribute("InMatch", true)
local mods = {
	ClientNet = Stub({ Fire = function() return true end }),
	ProfileController = Stub({
		Get = function() return { Level = 3, Xp = 240, XpToNext = 900, Coins = 1250, Owned = { Weapons = {}, Skins = {} }, Loadout = { Primary = "AK47", Skin = "Classic" }, Stats = {} } end,
		Settings = function() return { Sensitivity = 1, AimSensitivity = 0.72, Fov = 72, Master = 1, Music = 0.5, Sfx = 1, Crosshair = 1 } end,
		Changed = Signal.new(), ShopResult = Signal.new(),
	}),
	LobbyController = Stub({ InLobby = function() return false end, ModeChanged = Signal.new() }),
}
local Menu = require(Controllers.MainMenu)
Menu.Init(Context(mods))
Menu.Start()
M.advance(0.2)
Menu.SetPaused(true)
M.advance(0.5)
