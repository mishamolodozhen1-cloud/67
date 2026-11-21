-- Products: ассортимент MART 24 (все бренды выдуманные).
-- Category — отдел магазина; Shape — форма товара на ленте кассы; Price — цена в рублях.
local Config = require(script.Parent:WaitForChild("Config"))

local Products = {}

-- Отделы: название для интерфейса и текстура полки
Products.Categories = {
	Snacks = { Name = "Снеки", Texture = Config.Images.Snacks },
	Grocery = { Name = "Бакалея", Texture = Config.Images.Grocery },
	Drinks = { Name = "Напитки", Texture = Config.Images.Drinks },
	Cans = { Name = "Консервы", Texture = Config.Images.Cans },
	Household = { Name = "Бытовая химия", Texture = Config.Images.Household },
	Chilled = { Name = "Молочное и охлаждённое", Texture = Config.Images.Chilled },
	Bread = { Name = "Хлеб", Texture = Config.Images.Bread },
	Produce = { Name = "Овощи и фрукты", Texture = Config.Images.ProduceTop },
}

-- Как выглядят товары на полках отдела: форма, размер (ширина, высота, глубина) и этикетка.
-- Каждая полка заполняется одним из вариантов — объёмными товарами с этикеткой спереди.
local I = Config.Images
Products.ShelfStyles = {
	Snacks = {
		{ Shape = "Bag", Size = Vector3.new(1.0, 1.25, 0.42), Label = I.LabelChips },
		{ Shape = "Box", Size = Vector3.new(0.82, 1.1, 0.32), Label = I.LabelCereal },
	},
	Grocery = {
		{ Shape = "Box", Size = Vector3.new(0.92, 1.28, 0.36), Label = I.LabelCereal },
		{ Shape = "Bag", Size = Vector3.new(0.72, 1.05, 0.42), Label = I.LabelCoffee },
	},
	Drinks = {
		{ Shape = "Can", Size = Vector3.new(0.44, 0.72, 0.44), Label = I.LabelSoda },
		{ Shape = "Bottle", Size = Vector3.new(0.5, 1.22, 0.5), Label = I.LabelWater },
	},
	Cans = {
		{ Shape = "Can", Size = Vector3.new(0.52, 0.64, 0.52), Label = I.LabelCanned },
	},
	Household = {
		{ Shape = "Flask", Size = Vector3.new(0.62, 1.15, 0.36), Label = I.LabelHousehold },
	},
	Chilled = {
		{ Shape = "Carton", Size = Vector3.new(0.62, 1.15, 0.62), Label = I.LabelMilk },
		{ Shape = "Box", Size = Vector3.new(0.9, 0.85, 0.34), Label = I.LabelFrozen },
	},
}

-- Отделы, товар для которых лежит в коробках на складе (их выкладывают на полки)
Products.RestockCategories = { "Snacks", "Grocery", "Drinks", "Cans", "Household" }

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

Products.List = {
	-- Model — 3D-модель продукта (Shared/Models.Meshes), Shape/Color/Accent — простая замена, если модели нет
	{ Id = "milk", Name = "Молоко «Утро» 1 л", Price = 89, Category = "Chilled", Model = "Milk", Shape = "Carton", Color = rgb(246, 246, 240), Accent = rgb(40, 110, 196) },
	{ Id = "juice", Name = "Сок «Нектар» 1 л", Price = 119, Category = "Chilled", Model = "Juice", Shape = "Carton", Color = rgb(240, 200, 200), Accent = rgb(200, 40, 60) },
	{ Id = "sausages", Name = "Сосиски «Сытно»", Price = 199, Category = "Chilled", Model = "Sausages", Shape = "Pack", Color = rgb(226, 130, 120), Accent = rgb(150, 30, 40) },
	{ Id = "paste", Name = "Арахисовая паста", Price = 249, Category = "Chilled", Model = "ProteinJar", Shape = "Jar", Color = rgb(60, 50, 40), Accent = rgb(230, 190, 90) },
	{ Id = "bread", Name = "Хлеб нарезной", Price = 45, Category = "Bread", Shape = "Loaf", Color = rgb(210, 150, 80), Accent = rgb(250, 240, 220) },
	{ Id = "apples", Name = "Яблоки 1 кг", Price = 129, Category = "Produce", Shape = "Fruit", Color = rgb(200, 30, 40), Accent = rgb(240, 240, 235) },
	{ Id = "chips", Name = "Чипсы «Хрум»", Price = 99, Category = "Snacks", Model = "Snack", Shape = "Bag", Color = rgb(240, 196, 40), Accent = rgb(200, 40, 44) },
	{ Id = "chocolate", Name = "Шоколад «Ночка»", Price = 89, Category = "Snacks", Model = "ChocoBar1", Shape = "Bar", Color = rgb(90, 50, 30), Accent = rgb(230, 200, 120) },
	{ Id = "bar", Name = "Батончик «Вечер»", Price = 59, Category = "Snacks", Model = "ChocoBar2", Shape = "Bar", Color = rgb(40, 50, 90), Accent = rgb(230, 200, 120) },
	{ Id = "candies", Name = "Конфеты «Ассорти»", Price = 179, Category = "Snacks", Model = "Candies", Shape = "Pack", Color = rgb(236, 120, 30), Accent = rgb(250, 240, 210) },
	{ Id = "gum", Name = "Жвачка «Мята»", Price = 39, Category = "Snacks", Model = "Gum", Shape = "Bar", Color = rgb(200, 60, 160), Accent = rgb(250, 250, 250) },
	{ Id = "soda", Name = "Газировка «Капля» 0,5 л", Price = 75, Category = "Drinks", Model = "Bottle", Shape = "Bottle", Color = rgb(196, 40, 44), Accent = rgb(250, 250, 250) },
	{ Id = "waterpack", Name = "Вода «Север», 6 шт.", Price = 299, Category = "Drinks", Model = "BottlesPack", Shape = "Pack", Color = rgb(110, 170, 220), Accent = rgb(250, 250, 250) },
	{ Id = "cereal", Name = "Хлопья «Утро»", Price = 189, Category = "Grocery", Model = "Cereal", Shape = "Box", Color = rgb(240, 196, 40), Accent = rgb(200, 40, 44) },
	{ Id = "pasta", Name = "Макароны «Перья»", Price = 79, Category = "Grocery", Model = "Pasta", Shape = "Box", Color = rgb(40, 70, 140), Accent = rgb(240, 220, 150) },
	{ Id = "oats", Name = "Овсяные хлопья", Price = 69, Category = "Grocery", Model = "Porridge", Shape = "Box", Color = rgb(220, 190, 130), Accent = rgb(150, 40, 30) },
	{ Id = "coffee", Name = "Кофе «Луч»", Price = 349, Category = "Grocery", Model = "Coffee", Shape = "Box", Color = rgb(60, 36, 24), Accent = rgb(230, 190, 90) },
	{ Id = "salt", Name = "Соль поваренная", Price = 29, Category = "Grocery", Model = "Salt", Shape = "Box", Color = rgb(230, 240, 250), Accent = rgb(40, 110, 196) },
	{ Id = "oil", Name = "Масло оливковое", Price = 459, Category = "Grocery", Model = "OliveOil", Shape = "Bottle", Color = rgb(40, 70, 40), Accent = rgb(230, 200, 120) },
	{ Id = "ketchup", Name = "Кетчуп «Томатный»", Price = 99, Category = "Grocery", Model = "Sauce", Shape = "Bottle", Color = rgb(200, 30, 30), Accent = rgb(250, 250, 250) },
	{ Id = "peas", Name = "Горошек зелёный", Price = 89, Category = "Cans", Model = "Can06", Shape = "Can", Color = rgb(60, 140, 60), Accent = rgb(250, 240, 200) },
	{ Id = "stew", Name = "Тушёнка «Волга»", Price = 249, Category = "Cans", Model = "Can07", Shape = "Can", Color = rgb(170, 170, 176), Accent = rgb(180, 40, 40) },
	{ Id = "corn", Name = "Кукуруза сладкая", Price = 99, Category = "Cans", Model = "Can08", Shape = "Can", Color = rgb(240, 200, 40), Accent = rgb(40, 110, 60) },
	{ Id = "beans", Name = "Фасоль «Дачная»", Price = 109, Category = "Cans", Model = "Can09", Shape = "Can", Color = rgb(46, 120, 60), Accent = rgb(245, 240, 220) },
	{ Id = "sprats", Name = "Шпроты", Price = 159, Category = "Cans", Model = "Sardines", Shape = "Pack", Color = rgb(200, 170, 60), Accent = rgb(150, 30, 30) },
	{ Id = "bleach", Name = "Отбеливатель", Price = 159, Category = "Household", Model = "Bleach", Shape = "Bottle", Color = rgb(240, 240, 250), Accent = rgb(40, 110, 196) },
	{ Id = "gel", Name = "Гель для стирки", Price = 399, Category = "Household", Model = "DetergentLiquid", Shape = "Bottle", Color = rgb(240, 200, 220), Accent = rgb(200, 60, 120) },
	{ Id = "powder", Name = "Стиральный порошок", Price = 349, Category = "Household", Model = "DetergentPowder1", Shape = "Box", Color = rgb(30, 30, 30), Accent = rgb(200, 40, 40) },
	{ Id = "dish", Name = "Средство для посуды", Price = 119, Category = "Household", Model = "DishSoap", Shape = "Bottle", Color = rgb(200, 40, 60), Accent = rgb(250, 250, 250) },
	{ Id = "matches", Name = "Спички", Price = 15, Category = "Household", Model = "Matches", Shape = "Bar", Color = rgb(200, 60, 40), Accent = rgb(250, 240, 220) },
}

-- Размеры товара на ленте (в стадах): форма -> Vector3
Products.ShapeSize = {
	Carton = Vector3.new(0.7, 1.3, 0.7),
	Cup = Vector3.new(0.55, 0.55, 0.55),
	Pack = Vector3.new(1.0, 0.35, 0.7),
	Bag = Vector3.new(1.1, 1.3, 0.4),
	Loaf = Vector3.new(1.4, 0.6, 0.7),
	Fruit = Vector3.new(1.0, 0.8, 0.7),
	Bar = Vector3.new(0.9, 0.12, 0.4),
	Bottle = Vector3.new(0.5, 1.6, 0.5),
	Can = Vector3.new(0.45, 0.75, 0.45),
	Jar = Vector3.new(0.6, 0.9, 0.6),
	Box = Vector3.new(0.9, 0.6, 0.35),
}

local byId, byCategory = {}, {}
for _, p in ipairs(Products.List) do
	byId[p.Id] = p
	byCategory[p.Category] = byCategory[p.Category] or {}
	table.insert(byCategory[p.Category], p)
end

function Products.Get(id)
	return byId[id]
end

-- Случайный товар из отдела (или из всего магазина, если отдел не указан)
function Products.Random(category, rng)
	rng = rng or Random.new()
	local list = (category and byCategory[category]) or Products.List
	return list[rng:NextInteger(1, #list)]
end

function Products.FormatPrice(rub)
	return tostring(rub) .. " ₽"
end

return Products
