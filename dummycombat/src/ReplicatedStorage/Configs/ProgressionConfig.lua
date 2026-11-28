-- ProgressionConfig: опыт, уровни, монеты, магазин (этап 10). Цены и награды — только здесь.
local function deepFreeze(t)
	for _, v in pairs(t) do
		if type(v) == "table" and not table.isfrozen(v) then
			deepFreeze(v)
		end
	end
	return table.freeze(t)
end

local Config = {
	DataStore = "DummyCombat_Profiles_v1",
	AutosaveEvery = 120,
	StartCoins = 300,
	MaxLevel = 100,

	-- Награды: опыт и монеты
	Xp = { Kill = 100, Headshot = 30, Assist = 40, Win = 300, Match = 120, TopThree = 80, GunLevel = 40 },
	Coins = { Kill = 10, Headshot = 4, Assist = 4, Win = 60, Match = 25, TopThree = 15 },

	-- Оружие: цена в монетах и с какого уровня можно купить. Price = 0 — есть у всех
	Weapons = {
		AK47 = { Price = 0, Level = 1, Order = 1 },
		SMG = { Price = 450, Level = 2, Order = 2 },
		Shotgun = { Price = 700, Level = 3, Order = 3 },
		Sniper = { Price = 1200, Level = 5, Order = 4 },
		Pistol = { Price = 0, Level = 1, Order = 5, Hidden = true }, -- только в GUN GAME
	},

	-- Окраска манекена (текстура тела). Team* — для командных режимов, не продаются
	Skins = {
		Classic = { DisplayName = "CLASSIC", Price = 0, Level = 1, Order = 1, Color = Color3.fromRGB(201, 170, 98) },
		Graphite = { DisplayName = "GRAPHITE", Price = 300, Level = 1, Order = 2, Color = Color3.fromRGB(74, 76, 80) },
		Arctic = { DisplayName = "ARCTIC", Price = 300, Level = 2, Order = 3, Color = Color3.fromRGB(222, 224, 226) },
		Olive = { DisplayName = "OLIVE", Price = 450, Level = 3, Order = 4, Color = Color3.fromRGB(104, 112, 70) },
		Crimson = { DisplayName = "CRIMSON", Price = 600, Level = 4, Order = 5, Color = Color3.fromRGB(162, 52, 46) },
		Cobalt = { DisplayName = "COBALT", Price = 600, Level = 4, Order = 6, Color = Color3.fromRGB(52, 88, 160) },
		Gold = { DisplayName = "GOLD", Price = 2500, Level = 8, Order = 7, Color = Color3.fromRGB(214, 172, 62) },
		TeamRed = { DisplayName = "RED", Hidden = true, Color = Color3.fromRGB(198, 66, 54) },
		TeamBlue = { DisplayName = "BLUE", Hidden = true, Color = Color3.fromRGB(58, 108, 198) },
	},
}

-- Опыт до следующего уровня
function Config.XpToNext(level)
	return 600 + 150 * (level - 1)
end

return deepFreeze(Config)
