-- WeaponAnim: процедурная анимация оружия по ключам из Configs/WeaponPoses (их же рисует превью
-- tools/weapons/viewmodel.py). Общая для вида от первого лица (Viewmodel) и от третьего (ThirdPersonWeapons).
--
-- Reload(poses, kind, t) — состояние перезарядки kind ("Tactical" / "Empty") через t секунд после начала:
--   Gun       0..1 — насколько оружие повёрнуто в позу перезарядки (к левой руке);
--   Left/Right — CFrame кистей в осях оружия; MagInHand — магазин сейчас в левой руке (отстёгнут);
--   Charge    0..1 — насколько оттянута рукоять затвора.
-- Между ключами — плавно (smoothstep), повороты — по кратчайшей дуге (CFrame:Lerp).
local WeaponAnim = {}

function WeaponAnim.Smooth(t)
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end
local smooth = WeaponAnim.Smooth

local function trackNumber(keys, t)
	if t <= keys[1][1] then
		return keys[1][2]
	end
	for i = 1, #keys - 1 do
		local k0, k1 = keys[i], keys[i + 1]
		if t <= k1[1] then
			local a = smooth((t - k0[1]) / math.max(k1[1] - k0[1], 1e-6))
			return k0[2] + (k1[2] - k0[2]) * a
		end
	end
	return keys[#keys][2]
end

local function trackHand(keys, hands, t)
	if t <= keys[1][1] then
		return hands[keys[1][2]]
	end
	for i = 1, #keys - 1 do
		local k0, k1 = keys[i], keys[i + 1]
		if t <= k1[1] then
			local a = smooth((t - k0[1]) / math.max(k1[1] - k0[1], 1e-6))
			return hands[k0[2]]:Lerp(hands[k1[2]], a)
		end
	end
	return hands[keys[#keys][2]]
end

function WeaponAnim.Length(poses, kind)
	return poses.Reloads[kind].Length
end

function WeaponAnim.Reload(poses, kind, t)
	local r = poses.Reloads[kind]
	local charge = 0
	if r.Charge then
		local c0, c1, c2 = r.Charge[1], r.Charge[2], r.Charge[3]
		if t >= c0 and t < c1 then
			charge = smooth((t - c0) / (c1 - c0))
		elseif t >= c1 and t < c2 then
			charge = 1 -- держат в крайнем заднем
		elseif t >= c2 and t < c2 + 0.05 then
			charge = 1 - (t - c2) / 0.05 -- отпустили: рама влетает вперёд пружиной
		end
	end
	return {
		Gun = trackNumber(r.Gun, t),
		Left = trackHand(r.LeftHand, poses.Hands, t),
		Right = trackHand(r.RightHand, poses.Hands, t),
		MagInHand = t >= r.MagInHand[1] and t < r.MagInHand[2],
		Charge = charge,
	}
end

-- Где магазин относительно левой кисти, пока она его держит (его берут в ключе LeftMag)
function WeaponAnim.MagOffsetInHand(poses)
	return poses.Hands.LeftMag:Inverse() * CFrame.new(poses.Magazine)
end

-- Звуки перезарядки: { { время, имя группы звуков }, ... }
function WeaponAnim.Sounds(poses, kind)
	return poses.Reloads[kind].Sounds
end

return WeaponAnim
