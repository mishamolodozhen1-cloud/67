-- Общие настройки игры «Казань».
return {
	-- Администраторы (UserId). Владелец игры тоже получает доступ автоматически.
	Admins = {
		[7945431606] = true, -- Forzza_133
	},
	-- Текстуры (загружены через Open Cloud).
	Textures = {
		WindowClassic = "rbxassetid://132445009558563",
		WindowModern = "rbxassetid://73907412103145",
		WindowPanel = "rbxassetid://131968325556172",
		Storefront = "rbxassetid://95601814899233",
		Zebra = "rbxassetid://89278905213555",
	},
	-- 1 стад = 0,3 м: город в натуральную величину.
	MetersPerStud = 0.3,
	-- Цикл светофора, секунд: зелёный, жёлтый, красный (для второго направления — наоборот).
	TrafficCycle = { Green = 12, Yellow = 3, Red = 15 },
}
