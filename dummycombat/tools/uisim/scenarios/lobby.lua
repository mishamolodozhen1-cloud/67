-- Лобби: главное меню, раздел PLAY во время голосования (или другой раздел — переменная TAB)
local Signal = M.Signal
SetupMatch({ Phase = SCENE_PHASE or "Intermission", EndsAt = 1000 + 17, Mode = "FFA", ModeName = "FREE FOR ALL", Map = "CityBlock", MapName = "CITY BLOCK",
	Option1Map = "IndustrialZone", Option1MapName = "INDUSTRIAL ZONE", Option1Mode = "FFA", Option1Votes = 2,
	Option2Map = "CityBlock", Option2MapName = "CITY BLOCK", Option2Mode = "TDM", Option2Votes = 1,
	Option3Map = "TestChamber", Option3MapName = "TEST CHAMBER", Option3Mode = "GunGame", Option3Votes = 0 })
local profile = {
	Level = 3, Xp = 240, XpToNext = 900, Coins = 1250,
	Owned = { Weapons = { AK47 = true, SMG = true }, Skins = { Classic = true, Graphite = true } },
	Loadout = { Primary = "AK47", Skin = "Classic" },
	Stats = { Kills = 42, Deaths = 30, Headshots = 11, Assists = 7, Matches = 6, Wins = 2 },
}
local mods = {
	ClientNet = Stub({ Fire = function() return true end }),
	ProfileController = Stub({
		Get = function() return profile end,
		Settings = function() return { Sensitivity = 1, AimSensitivity = 0.72, Fov = 72, Master = 1, Music = 0.5, Sfx = 1, Crosshair = 1 } end,
		Changed = Signal.new(), ShopResult = Signal.new(), Reward = Signal.new(), MatchRewards = Signal.new(),
	}),
	LobbyController = Stub({ InLobby = function() return true end, ModeChanged = Signal.new() }),
}
local Menu = require(Controllers.MainMenu)
Menu.Init(Context(mods))
Menu.Start()
M.advance(0.2)
if TAB then
	Menu.SetTab(TAB)
end
M.advance(1.2)
