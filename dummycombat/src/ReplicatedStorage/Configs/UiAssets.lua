-- UiAssets: звуки интерфейса и музыка (создаётся tools/ui/write_assets.py — не править вручную).
-- Sfx — один файл-спрайт: каждый звук — отрезок [Start, Stop] (Sound.PlaybackRegion).
return table.freeze({
	Sfx = table.freeze({
		Id = "rbxassetid://102930077566190",
		Sounds = table.freeze({
			Hit = table.freeze({ Start = 0.05, Stop = 0.11 }),
			HitHead = table.freeze({ Start = 0.36, Stop = 0.58 }),
			Kill = table.freeze({ Start = 0.83, Stop = 1.28 }),
			Death = table.freeze({ Start = 1.53, Stop = 2.43 }),
			Click = table.freeze({ Start = 2.68, Stop = 2.73 }),
			Hover = table.freeze({ Start = 2.98, Stop = 3.015 }),
			Purchase = table.freeze({ Start = 3.265, Stop = 3.665 }),
			LevelUp = table.freeze({ Start = 3.915, Stop = 4.915 }),
			Xp = table.freeze({ Start = 5.165, Stop = 5.345 }),
			Count = table.freeze({ Start = 5.595, Stop = 5.755 }),
			CountGo = table.freeze({ Start = 6.005, Stop = 6.505 }),
			MatchStart = table.freeze({ Start = 6.755, Stop = 8.055 }),
			Victory = table.freeze({ Start = 8.305, Stop = 10.105 }),
			Defeat = table.freeze({ Start = 10.355, Stop = 12.155 }),
			Error = table.freeze({ Start = 12.405, Stop = 12.585 }),
			Explosion = table.freeze({ Start = 12.835, Stop = 15.035 }),
			Warning = table.freeze({ Start = 15.285, Stop = 15.405 }),
			Equip = table.freeze({ Start = 15.655, Stop = 15.705 }),
		}),
	}),
	Music = table.freeze({
		Lobby = "rbxassetid://135290269538089",
	}),
})
