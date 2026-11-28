-- WeaponModels: геометрия моделей оружия (создаётся tools/weapons/guns.py — не править вручную).
-- Оси оружия: ствол в −Z, верх +Y, правая сторона +X. Все точки — относительно центра детали Body
-- (так Roblox ставит MeshPart: по центру габаритов), studs.
return table.freeze({
	AK47 = table.freeze({
		Parts = table.freeze({
			Body = table.freeze({ Offset = Vector3.new(0.0000, 0.0000, 0.0000), Size = Vector3.new(0.1680, 0.6650, 2.8650) }),
			Magazine = table.freeze({ Offset = Vector3.new(0.0000, -0.2976, -0.3753), Size = Vector3.new(0.0860, 0.7812, 0.5255) }),
			ChargingHandle = table.freeze({ Offset = Vector3.new(0.1225, 0.2025, -0.2575), Size = Vector3.new(0.1050, 0.0440, 0.0429) }),
			Casing = table.freeze({ Offset = Vector3.new(0.0000, 0.1825, 0.2450), Size = Vector3.new(0.0350, 0.0350, 0.1250) }),
		}),
		Points = table.freeze({
			Muzzle = Vector3.new(0.0000, 0.1825, -1.4325),
			Eject = Vector3.new(0.0800, 0.2425, -0.1175),
			GripRight = Vector3.new(0.0000, -0.0875, 0.2725),
			GripLeft = Vector3.new(0.0000, 0.0975, -0.7875),
			SightRear = Vector3.new(0.0000, 0.3175, -0.4475),
			SightFront = Vector3.new(0.0000, 0.3175, -1.2495),
			MagWell = Vector3.new(0.0000, 0.0625, -0.2325),
			ChargingHandle = Vector3.new(0.1550, 0.2025, -0.2575),
			Stock = Vector3.new(0.0000, -0.0275, 1.4325),
		}),
	}),
	Pistol = table.freeze({
		Parts = table.freeze({
			Body = table.freeze({ Offset = Vector3.new(0.0000, 0.0000, 0.0000), Size = Vector3.new(0.1392, 0.6336, 0.8460) }),
			Magazine = table.freeze({ Offset = Vector3.new(0.0000, -0.1068, 0.2490), Size = Vector3.new(0.1200, 0.4919, 0.2500) }),
			ChargingHandle = table.freeze({ Offset = Vector3.new(0.0000, 0.3144, 0.0090), Size = Vector3.new(0.1128, 0.1824, 0.8280) }),
			Casing = table.freeze({ Offset = Vector3.new(0.0000, 0.2832, 0.0940), Size = Vector3.new(0.0216, 0.0216, 0.0620) }),
		}),
		Points = table.freeze({
			Muzzle = Vector3.new(0.0000, 0.2832, -0.4230),
			Eject = Vector3.new(0.0600, 0.3372, 0.0630),
			GripRight = Vector3.new(0.0000, -0.0768, 0.2490),
			GripLeft = Vector3.new(0.0000, -0.1128, 0.2070),
			SightRear = Vector3.new(0.0000, 0.4032, 0.3570),
			SightFront = Vector3.new(0.0000, 0.4032, -0.3510),
			MagWell = Vector3.new(0.0000, -0.3168, 0.2610),
			ChargingHandle = Vector3.new(0.0000, 0.3192, 0.3270),
			Stock = Vector3.new(0.0000, 0.1632, 0.4230),
		}),
	}),
	SMG = table.freeze({
		Parts = table.freeze({
			Body = table.freeze({ Offset = Vector3.new(0.0000, 0.0000, 0.0000), Size = Vector3.new(0.1360, 0.7400, 2.1148) }),
			Magazine = table.freeze({ Offset = Vector3.new(0.0000, -0.2239, -0.2094), Size = Vector3.new(0.0840, 0.5522, 0.1940) }),
			ChargingHandle = table.freeze({ Offset = Vector3.new(0.0945, 0.1800, -0.2924), Size = Vector3.new(0.0790, 0.0440, 0.0429) }),
			Casing = table.freeze({ Offset = Vector3.new(0.0000, 0.1500, 0.1906), Size = Vector3.new(0.0227, 0.0227, 0.0660) }),
		}),
		Points = table.freeze({
			Muzzle = Vector3.new(0.0000, 0.1500, -1.0574),
			Eject = Vector3.new(0.0650, 0.1900, -0.0424),
			GripRight = Vector3.new(0.0000, -0.1600, 0.2976),
			GripLeft = Vector3.new(0.0000, 0.0920, -0.6424),
			SightRear = Vector3.new(0.0000, 0.3400, 0.2776),
			SightFront = Vector3.new(0.0000, 0.3400, -0.4674),
			MagWell = Vector3.new(0.0000, 0.0500, -0.2424),
			ChargingHandle = Vector3.new(0.1200, 0.1800, -0.2924),
			Stock = Vector3.new(0.0000, 0.0300, 1.0576),
		}),
	}),
	Shotgun = table.freeze({
		Parts = table.freeze({
			Body = table.freeze({ Offset = Vector3.new(0.0000, 0.0000, 0.0000), Size = Vector3.new(0.1600, 0.5800, 3.0400) }),
			Magazine = table.freeze({ Offset = Vector3.new(0.0000, -0.1546, 0.1150), Size = Vector3.new(0.1200, 0.5108, 0.2874) }),
			ChargingHandle = table.freeze({ Offset = Vector3.new(0.1115, 0.2100, -0.0600), Size = Vector3.new(0.0830, 0.0480, 0.0468) }),
			Casing = table.freeze({ Offset = Vector3.new(0.0000, 0.1900, 0.5700), Size = Vector3.new(0.0840, 0.0827, 0.2600) }),
		}),
		Points = table.freeze({
			Muzzle = Vector3.new(0.0000, 0.1900, -1.5200),
			Eject = Vector3.new(0.0750, 0.2200, 0.2000),
			GripRight = Vector3.new(0.0000, -0.1100, 0.7100),
			GripLeft = Vector3.new(0.0000, 0.0670, -0.5100),
			SightRear = Vector3.new(0.0000, 0.2770, 0.6850),
			SightFront = Vector3.new(0.0000, 0.2770, -1.4600),
			MagWell = Vector3.new(0.0000, 0.0900, 0.0900),
			ChargingHandle = Vector3.new(0.1350, 0.2100, -0.0600),
			Stock = Vector3.new(0.0000, 0.0300, 1.5200),
		}),
	}),
	Sniper = table.freeze({
		Parts = table.freeze({
			Body = table.freeze({ Offset = Vector3.new(0.0000, 0.0000, 0.0000), Size = Vector3.new(0.1770, 0.8180, 3.5950) }),
			Magazine = table.freeze({ Offset = Vector3.new(-0.0105, -0.1621, 0.3875), Size = Vector3.new(0.0920, 0.2539, 0.2000) }),
			ChargingHandle = table.freeze({ Offset = Vector3.new(0.0665, 0.0910, 0.9014), Size = Vector3.new(0.2380, 0.0840, 0.1723) }),
			Casing = table.freeze({ Offset = Vector3.new(-0.0105, 0.0910, 0.7100), Size = Vector3.new(0.0319, 0.0319, 0.1650) }),
		}),
		Points = table.freeze({
			Muzzle = Vector3.new(-0.0105, 0.0910, -1.7975),
			Eject = Vector3.new(0.0545, 0.1510, 0.5475),
			GripRight = Vector3.new(-0.0105, -0.2290, 0.9375),
			GripLeft = Vector3.new(-0.0105, -0.0740, -0.3225),
			SightRear = Vector3.new(-0.0105, 0.2910, 0.9575),
			SightFront = Vector3.new(-0.0105, 0.2910, -0.1725),
			MagWell = Vector3.new(-0.0105, -0.0390, 0.3875),
			ChargingHandle = Vector3.new(0.1575, 0.0790, 0.8425),
			Stock = Vector3.new(-0.0105, -0.1190, 1.7975),
		}),
	}),
})
