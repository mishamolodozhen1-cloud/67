-- Матч: HUD оружия, здоровья, матча и кнопки телефона. SHOW = "board" — таблица, "results" — итоги
local Signal = M.Signal
SetupMatch({ Phase = "Running", EndsAt = 1000 + 263, Mode = "TDM", ModeName = "TEAM DEATHMATCH", Map = "CityBlock", MapName = "CITY BLOCK",
	ScoreLimit = 50, RedScore = 17, BlueScore = 21, Teams = true }, {
	{ UserId = 1001, Name = "Forzza_133", Team = "Red", Kills = 9, Deaths = 4, Assists = 2, Score = 9, InMatch = true },
	{ UserId = -1, Name = "BOT Gasket", Team = "Blue", Kills = 12, Deaths = 6, Score = 12, InMatch = true, IsBot = true },
	{ UserId = -2, Name = "BOT Torque", Team = "Red", Kills = 5, Deaths = 8, Score = 5, InMatch = true, IsBot = true },
	{ UserId = -3, Name = "BOT Rivet", Team = "Blue", Kills = 7, Deaths = 7, Score = 7, InMatch = true, IsBot = true },
})
local me = game:GetService("Players").LocalPlayer
me:SetAttribute("InMatch", true)
me:SetAttribute("Team", "Red")
local char = Instance.new("Model")
char.Name = me.Name
local hum = Instance.new("Humanoid")
hum.Health = 72
hum.MaxHealth = 100
hum.Died = Signal.new()
hum.HealthChanged = Signal.new()
hum.Parent = char
local root = Instance.new("Part")
root.Name = "HumanoidRootPart"
root.Parent = char
char:SetAttribute("Weapon", "AK47")
char.Parent = workspace
me.Character = char
local wstate = { Equipped = true, Weapon = "AK47", DisplayName = "AK-47", Ammo = 23, Reserve = 90, Magazine = 30, Mode = "Auto", Spread = 2.4,
	AimAlpha = 0, Reloading = false, ReloadProgress = 0 }
local mods = {
	ClientNet = Stub({ Fire = function() return true end }),
	CharacterController = Stub({
		GetCharacter = function() return char, hum, root end,
		GetState = function() return { Stance = "Stand", Sprint = false, Aim = false } end,
		IsRagdolled = function() return false end,
		CharacterChanged = Signal.new(), StateChanged = Signal.new(), SprintToggled = function() return false end,
		WantsCrouch = function() return false end,
	}),
	WeaponController = Stub({
		GetState = function() return wstate end,
		HitConfirmed = Signal.new(), StateChanged = Signal.new(), Fired = Signal.new(),
		IsScoped = function() return false end,
	}),
	CameraController = Stub({ IsFirstPerson = function() return true end }),
	ProfileController = Stub({ Changed = Signal.new(), Reward = Signal.new(), MatchRewards = Signal.new(), ShopResult = Signal.new(),
		Get = function() return { Level = 3, Xp = 240, XpToNext = 900, Coins = 1250 } end }),
	LobbyController = Stub({ InLobby = function() return false end, ModeChanged = Signal.new() }),
}
local ctx = Context(mods)
for _, name in ipairs({ "WeaponHUD", "CombatHUD", "MatchHUD", "TouchControls", "MainMenu" }) do
	local mod = require(Controllers[name])
	mod.Init(ctx)
	mod.Start()
end
M.advance(0.5)
-- лента убийств и попадание
local CombatHUD = require(Controllers.CombatHUD)
if CombatHUD.PushFeed then
	CombatHUD.PushFeed({ Killer = "BOT Gasket", KillerId = -1, Victim = "BOT Torque", VictimId = -2, Weapon = "AK47", Headshot = true, KillerTeam = "Blue", VictimTeam = "Red" })
	CombatHUD.PushFeed({ Killer = "Forzza_133", KillerId = 1001, Victim = "BOT Rivet", VictimId = -3, Weapon = "SMG", KillerTeam = "Red", VictimTeam = "Blue" })
end
local MatchHUD = require(Controllers.MatchHUD)
if SHOW == "board" then
	MatchHUD.SetBoardOpen(true)
elseif SHOW == "results" then
	MatchHUD.ShowResults({ WinnerTeam = "Blue", ModeName = "TEAM DEATHMATCH", MapName = "CITY BLOCK", RedScore = 46, BlueScore = 50, Players = {
		{ UserId = -1, Name = "BOT Gasket", Team = "Blue", Kills = 18, Deaths = 9, Score = 18 },
		{ UserId = 1001, Name = "Forzza_133", Team = "Red", Kills = 15, Deaths = 8, Score = 15 },
		{ UserId = -3, Name = "BOT Rivet", Team = "Blue", Kills = 12, Deaths = 11, Score = 12 },
		{ UserId = -2, Name = "BOT Torque", Team = "Red", Kills = 9, Deaths = 14, Score = 9 },
	} })
elseif SHOW == "dead" then
	CombatHUD.ShowEliminated({ Role = "Victim", Name = "BOT Gasket", Weapon = "VX-9", Headshot = true, Respawn = 4 })
end
M.advance(0.5)
