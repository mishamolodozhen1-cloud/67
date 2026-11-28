-- MatchConfig: матчи и режимы (этапы 7 и 9). Читают сервер (MatchSystem, BotSystem) и клиент (интерфейс).
local function deepFreeze(t)
	for _, v in pairs(t) do
		if type(v) == "table" and not table.isfrozen(v) then
			deepFreeze(v)
		end
	end
	return table.freeze(t)
end

return deepFreeze({
	-- Время фаз (с): голосование в лобби → отсчёт на карте → бой → итоги
	Intermission = 22,
	Starting = 5,
	Results = 12,
	RespawnDelay = 4,

	-- Сколько участников держать в матче: не хватает живых игроков — добавляются боты-манекены
	FillTo = 8,
	MaxBots = 7,

	Modes = {
		FFA = {
			DisplayName = "FREE FOR ALL",
			Short = "FFA",
			Description = "Каждый сам за себя. Первый до 25 убийств",
			ScoreLimit = 25,
			TimeLimit = 480,
			Teams = false,
		},
		TDM = {
			DisplayName = "TEAM DEATHMATCH",
			Short = "TDM",
			Description = "Две команды. Первая до 50 убийств",
			ScoreLimit = 50,
			TimeLimit = 540,
			Teams = true,
		},
		GunGame = {
			DisplayName = "GUN GAME",
			Short = "GUN",
			Description = "Каждое убийство — новое оружие. Победа — убийство с последним",
			TimeLimit = 540,
			Teams = false,
			KillsPerWeapon = 2,
			Weapons = { "Pistol", "SMG", "Shotgun", "AK47", "Sniper" },
		},
		Chaos = {
			DisplayName = "CHAOS",
			Short = "CHAOS",
			Description = "Каждый сам за себя под обстрелом: взрывы раскидывают манекены. До 20 убийств",
			ScoreLimit = 20,
			TimeLimit = 420,
			Teams = false,
			Strike = { Every = 9, Warning = 2.2, Radius = 18, Damage = 140, Count = 2 },
		},
	},

	-- Какие сочетания карт и режимов предлагать в голосовании
	Rotation = {
		{ Map = "IndustrialZone", Mode = "FFA" },
		{ Map = "IndustrialZone", Mode = "TDM" },
		{ Map = "IndustrialZone", Mode = "Chaos" },
		{ Map = "CityBlock", Mode = "TDM" },
		{ Map = "CityBlock", Mode = "FFA" },
		{ Map = "MilitaryBase", Mode = "TDM" },
		{ Map = "MilitaryBase", Mode = "GunGame" },
		{ Map = "ConstructionSite", Mode = "FFA" },
		{ Map = "ConstructionSite", Mode = "Chaos" },
		{ Map = "TestChamber", Mode = "GunGame" },
		{ Map = "TestChamber", Mode = "FFA" },
	},
	VoteOptions = 3,

	Teams = {
		Red = { DisplayName = "RED", Color = Color3.fromRGB(214, 78, 64) },
		Blue = { DisplayName = "BLUE", Color = Color3.fromRGB(70, 132, 220) },
	},
})
