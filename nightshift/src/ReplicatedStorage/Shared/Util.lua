-- Util: маленькие помощники, которыми пользуются и сервер, и клиент.
local TweenService = game:GetService("TweenService")

local Util = {}

-- Создать объект и сразу задать свойства: Util.make("Part", { Size = ..., Parent = ... })
function Util.make(className, props, parent)
	local inst = Instance.new(className)
	if props then
		for k, v in pairs(props) do
			if k ~= "Parent" then
				inst[k] = v
			end
		end
	end
	inst.Parent = parent or (props and props.Parent)
	return inst
end

-- Плавно изменить свойства объекта
function Util.tween(inst, seconds, props, style, direction)
	local t = TweenService:Create(
		inst,
		TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.InOut),
		props
	)
	t:Play()
	return t
end

-- Подсказка взаимодействия (на ПК — клавиша E, на телефоне — нажать на кнопку подсказки)
function Util.prompt(parent, action, object, hold, distance)
	local p = Instance.new("ProximityPrompt")
	p.ActionText = action
	p.ObjectText = object or ""
	p.HoldDuration = hold or 0
	p.MaxActivationDistance = distance or 8
	p.RequiresLineOfSight = false
	p.ClickablePrompt = true
	p.Parent = parent
	return p
end

-- Расстояние по горизонтали (без учёта высоты)
function Util.flatDistance(a, b)
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

function Util.shuffle(list, rng)
	rng = rng or Random.new()
	for i = #list, 2, -1 do
		local j = rng:NextInteger(1, i)
		list[i], list[j] = list[j], list[i]
	end
	return list
end

function Util.pick(list, rng)
	rng = rng or Random.new()
	if #list == 0 then
		return nil
	end
	return list[rng:NextInteger(1, #list)]
end

-- "03:07" из числа минут с полуночи
function Util.clock(minutes)
	local m = math.max(0, math.floor(minutes))
	return string.format("%02d:%02d", math.floor(m / 60) % 24, m % 60)
end

-- Корневая деталь персонажа игрока (или nil)
function Util.rootOf(player)
	local ch = player and player.Character
	return ch and ch:FindFirstChild("HumanoidRootPart")
end

return Util
