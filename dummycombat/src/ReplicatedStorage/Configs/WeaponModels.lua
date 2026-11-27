-- WeaponModels: геометрия моделей оружия (создаётся tools/weapons/ak47.py — не править вручную).
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
})
