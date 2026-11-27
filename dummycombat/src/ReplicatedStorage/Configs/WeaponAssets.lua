-- WeaponAssets: ассеты оружия в Roblox (создаётся tools/weapons/write_assets.py — не править вручную).
-- Models: модели (MeshPart-ы внутри узлов *_Node); Sfx: один звуковой файл-спрайт, Groups — варианты звука
-- (отрезки [Start, Stop] в секундах, играются через Sound.PlaybackRegion); Images: текстуры эффектов.
local function region(a, b)
	return table.freeze({ Start = a, Stop = b })
end

return table.freeze({
	Models = table.freeze({
		AK47 = 118166080540260,
	}),
	Sfx = table.freeze({
		Id = "rbxassetid://132502180907399",
		Length = 20.304,
		Groups = table.freeze({
			Shot = table.freeze({ region(0.05, 1.112), region(1.512, 2.574), region(2.974, 4.036) }),
			Distant = table.freeze({ region(4.436, 5.936) }),
			Dry = table.freeze({ region(6.336, 6.466) }),
			Select = table.freeze({ region(6.866, 7.066) }),
			MagOut = table.freeze({ region(7.466, 7.906) }),
			MagIn = table.freeze({ region(8.306, 8.666) }),
			Charge = table.freeze({ region(9.066, 9.526) }),
			Casing = table.freeze({ region(9.926, 10.246), region(10.646, 10.986), region(11.386, 11.936) }),
			Metal = table.freeze({ region(12.336, 12.836), region(13.236, 13.736), region(14.136, 14.636) }),
			Concrete = table.freeze({ region(15.036, 15.586), region(15.986, 16.366), region(16.766, 17.366) }),
			Wood = table.freeze({ region(17.766, 17.9744), region(18.3744, 18.4644) }),
			Body = table.freeze({ region(18.8644, 19.1644), region(19.5644, 19.9044) }),
		}),
	}),
	Images = table.freeze({
		MuzzleFlash = "rbxassetid://111513173813443",
		MuzzleFlashSide = "rbxassetid://106155004129581",
		BulletHole = "rbxassetid://94500673265895",
	}),
})
