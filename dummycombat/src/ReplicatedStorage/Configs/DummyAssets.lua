-- DummyAssets: ассеты манекена в Roblox (создаётся tools/dummy/write_assets.py — не править вручную).
-- BodyModel — модель с 15 частями тела (MeshPart), из неё сервер собирает персонажа (CharacterSystem).
-- Animations: Id, длина цикла (с), «родная» скорость походки (studs/с — при ней ноги не скользят),
-- зациклена ли. CrouchDrop — насколько ниже персонаж в приседе (на столько уменьшается HipHeight).
local function anim(id, length, natural, loop)
	return table.freeze({ Id = "rbxassetid://" .. id, Length = length, Natural = natural, Loop = loop })
end

return table.freeze({
	BodyModel = 135090062587013,
	CrouchDrop = 1,
	Animations = table.freeze({
		Idle = anim(114918988154584, 3.6, 0, true),
		WalkF = anim(102380025671856, 0.675, 12, true),
		WalkL = anim(70967307689026, 0.577, 12, true),
		WalkR = anim(87607910502840, 0.577, 12, true),
		RunF = anim(105432479967867, 0.658, 19, true),
		CrouchIdle = anim(70954845280807, 3.2, 0, true),
		CrouchF = anim(131038187636023, 0.5479, 6.5, true),
		CrouchL = anim(78376481341428, 0.3765, 6.5, true),
		CrouchR = anim(125058267269000, 0.3765, 6.5, true),
		Jump = anim(103459053221514, 0.45, 0, false),
		Fall = anim(85160598111947, 1.1, 0, true),
		Land = anim(138195226004031, 0.42, 0, false),
		Climb = anim(107716884682838, 1, 0, true),
	}),
})
