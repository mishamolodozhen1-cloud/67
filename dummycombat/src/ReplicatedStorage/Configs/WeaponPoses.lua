-- WeaponPoses: позы оружия и рук (создаётся tools/weapons/viewmodel.py — не править вручную).
-- Viewmodel: всё в осях камеры (−Z — взгляд). Poses — CFrame детали Body; Shoulders/Poles — точки плеч
-- и направления локтей для ИК рук. ThirdPerson: в осях UpperTorso; Twist — разворот корпуса (рад).
-- Hands — CFrame кистей (центр части) в осях оружия. Reloads — ключи перезарядки (см. viewmodel.py).
return table.freeze({
	AK47 = table.freeze({
		Hands = table.freeze({
			Right = CFrame.fromMatrix(Vector3.new(0.1500, -0.1075, 0.3725), Vector3.new(0.9992, -0.0320, 0.0240), Vector3.new(-0.0000, 0.6000, 0.8000), Vector3.new(-0.0400, -0.7994, 0.5995)),
			Left = CFrame.fromMatrix(Vector3.new(-0.0600, -0.0725, -0.7675), Vector3.new(-0.1399, 0.9702, 0.1980), Vector3.new(-0.9222, -0.2005, 0.3308), Vector3.new(0.3606, -0.1363, 0.9227)),
			LeftMag = CFrame.fromMatrix(Vector3.new(-0.1700, -0.3476, -0.4953), Vector3.new(0.9675, 0.1529, 0.2013), Vector3.new(-0.2494, 0.4490, 0.8580), Vector3.new(0.0408, -0.8804, 0.4725)),
			RightCharge = CFrame.fromMatrix(Vector3.new(0.3150, 0.1825, -0.1575), Vector3.new(0.9956, -0.0874, 0.0326), Vector3.new(-0.0000, 0.3489, 0.9371), Vector3.new(-0.0933, -0.9331, 0.3474)),
			Below = CFrame.fromMatrix(Vector3.new(-0.3500, -1.5476, -0.1253), Vector3.new(0.9611, 0.2424, 0.1328), Vector3.new(-0.2063, 0.3094, 0.9283), Vector3.new(0.1839, -0.9195, 0.3474)),
			Enter = CFrame.fromMatrix(Vector3.new(-0.1700, -0.6676, -0.6153), Vector3.new(0.9675, 0.1529, 0.2013), Vector3.new(-0.2494, 0.4490, 0.8580), Vector3.new(0.0408, -0.8804, 0.4725)),
			RightChargePulled = CFrame.fromMatrix(Vector3.new(0.3150, 0.1825, 0.2625), Vector3.new(0.9956, -0.0874, 0.0326), Vector3.new(-0.0000, 0.3489, 0.9371), Vector3.new(-0.0933, -0.9331, 0.3474)),
		}),
		Magazine = Vector3.new(0.0000, -0.2976, -0.3753),
		ChargeTravel = 0.420,
		Viewmodel = table.freeze({
			AimFov = 55,
			Shoulders = table.freeze({ Right = Vector3.new(1.1000, -1.4500, 0.1500), Left = Vector3.new(-0.5000, -1.2500, -0.5000) }),
			Poles = table.freeze({ Right = Vector3.new(0.8000, -1.0000, 0.1000), Left = Vector3.new(-0.7000, -1.0000, 0.0000) }),
			Poses = table.freeze({
				Hip = CFrame.fromMatrix(Vector3.new(0.3600, -0.5000, -1.2200), Vector3.new(0.9972, 0.0615, -0.0428), Vector3.new(-0.0599, 0.9975, 0.0376), Vector3.new(0.0450, -0.0350, 0.9984)),
				Aim = CFrame.fromMatrix(Vector3.new(0.0000, -0.3175, -1.5525), Vector3.new(1.0000, 0.0000, 0.0000), Vector3.new(0.0000, 1.0000, 0.0000), Vector3.new(0.0000, 0.0000, 1.0000)),
				Sprint = CFrame.fromMatrix(Vector3.new(0.2200, -0.7200, -1.2000), Vector3.new(0.7142, 0.1422, -0.6853), Vector3.new(-0.3902, 0.8938, -0.2212), Vector3.new(0.5810, 0.4254, 0.6939)),
				Reload = CFrame.fromMatrix(Vector3.new(0.3000, -0.5000, -1.3500), Vector3.new(0.8434, -0.4217, -0.3329), Vector3.new(0.4608, 0.8864, 0.0445), Vector3.new(0.2764, -0.1909, 0.9419)),
				Equip = CFrame.fromMatrix(Vector3.new(0.5000, -1.6000, -0.9000), Vector3.new(0.9363, -0.1034, -0.3357), Vector3.new(-0.1898, 0.6552, -0.7312), Vector3.new(0.2955, 0.7483, 0.5938)),
			}),
		}),
		ThirdPerson = table.freeze({
			Twist = -0.5500,
			Poles = table.freeze({ Right = Vector3.new(0.7000, -1.0000, 0.3000), Left = Vector3.new(-0.3500, -1.0000, -0.1000) }),
			Poses = table.freeze({
				Ready = CFrame.fromMatrix(Vector3.new(-0.2524, 0.3800, -1.4640), Vector3.new(0.8525, 0.0000, -0.5227), Vector3.new(-0.0522, 0.9950, -0.0851), Vector3.new(0.5201, 0.0998, 0.8483)),
				Aim = CFrame.fromMatrix(Vector3.new(-0.4353, 0.7200, -1.3988), Vector3.new(0.8525, 0.0000, -0.5227), Vector3.new(0.0000, 1.0000, 0.0000), Vector3.new(0.5227, 0.0000, 0.8525)),
				Sprint = CFrame.fromMatrix(Vector3.new(-0.4209, 0.0000, -0.9736), Vector3.new(0.1511, -0.2363, -0.9599), Vector3.new(-0.3992, 0.8737, -0.2780), Vector3.new(0.9043, 0.4252, 0.0377)),
				Reload = CFrame.fromMatrix(Vector3.new(-0.3385, 0.3000, -1.3174), Vector3.new(0.4884, -0.3901, -0.7806), Vector3.new(0.4142, 0.8910, -0.1861), Vector3.new(0.7681, -0.2324, 0.5967)),
			}),
		}),
		Reloads = table.freeze({
			Tactical = table.freeze({
				Length = 2.5,
				Gun = table.freeze({ { 0, 0 }, { 0.3, 1 }, { 1.95, 1 }, { 2.4, 0 } }),
				LeftHand = table.freeze({ { 0, "Left" }, { 0.28, "Left" }, { 0.55, "LeftMag" }, { 0.66, "LeftMag" }, { 0.98, "Below" }, { 1.2, "Below" }, { 1.42, "Enter" }, { 1.6, "LeftMag" }, { 1.68, "LeftMag" }, { 1.98, "Left" } }),
				RightHand = table.freeze({ { 0, "Right" } }),
				MagInHand = { 0.62, 1.58 },
				Sounds = table.freeze({ { 0.62, "MagOut" }, { 1.56, "MagIn" } }),
			}),
			Empty = table.freeze({
				Length = 3.1,
				Gun = table.freeze({ { 0, 0 }, { 0.3, 1 }, { 1.7, 1 }, { 1.95, 0.6 }, { 2.6, 0.6 }, { 3, 0 } }),
				LeftHand = table.freeze({ { 0, "Left" }, { 0.28, "Left" }, { 0.55, "LeftMag" }, { 0.66, "LeftMag" }, { 0.98, "Below" }, { 1.2, "Below" }, { 1.42, "Enter" }, { 1.6, "LeftMag" }, { 1.66, "LeftMag" }, { 1.95, "Left" } }),
				RightHand = table.freeze({ { 0, "Right" }, { 1.7, "Right" }, { 1.98, "RightCharge" }, { 2.12, "RightChargePulled" }, { 2.2, "RightChargePulled" }, { 2.55, "Right" } }),
				MagInHand = { 0.62, 1.58 },
				Charge = { 2, 2.12, 2.2 },
				Sounds = table.freeze({ { 0.62, "MagOut" }, { 1.56, "MagIn" }, { 2.02, "Charge" } }),
			}),
		}),
		Check = table.freeze({
			RightUpperArm = CFrame.fromMatrix(Vector3.new(1.1754, -1.2474, -0.2734), Vector3.new(0.7386, 0.6546, 0.1614), Vector3.new(0.0287, -0.2696, 0.9625), Vector3.new(0.6736, -0.7063, -0.2179)),
			RightLowerArm = CFrame.fromMatrix(Vector3.new(0.8542, -0.7798, -0.6703), Vector3.new(0.7293, 0.6245, 0.2795), Vector3.new(0.6817, -0.6980, -0.2191), Vector3.new(0.0583, 0.3503, -0.9348)),
			RightHand = CFrame.fromMatrix(Vector3.new(0.5328, -0.6110, -0.8586), Vector3.new(0.9994, 0.0287, -0.0200), Vector3.new(0.0000, 0.5705, 0.8213), Vector3.new(0.0350, -0.8208, 0.5702)),
			LeftUpperArm = CFrame.fromMatrix(Vector3.new(-0.5590, -1.2567, -0.9717), Vector3.new(0.8144, -0.5577, 0.1604), Vector3.new(-0.0842, 0.1599, 0.9835), Vector3.new(-0.5742, -0.8145, 0.0833)),
			LeftLowerArm = CFrame.fromMatrix(Vector3.new(-0.2695, -0.9920, -1.6574), Vector3.new(0.8127, -0.5810, 0.0437), Vector3.new(-0.5518, -0.7434, 0.3779), Vector3.new(-0.1871, -0.3313, -0.9248)),
			LeftHand = CFrame.fromMatrix(Vector3.new(0.2700, -0.5492, -1.9864), Vector3.new(-0.1887, 0.9522, 0.2401), Vector3.new(-0.8927, -0.2682, 0.3621), Vector3.new(0.4093, -0.1460, 0.9007)),
		}),
	}),
})
