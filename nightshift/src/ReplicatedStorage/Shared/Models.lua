-- Models: 3D-модели и собственные анимации NIGHT SHIFT (ID ассетов Roblox).
-- Файл собран скриптом по результатам загрузки моделей в Roblox (Open Cloud).
--
-- Источники (обе работы — лицензия CC BY 4.0, авторов нужно указывать):
--   • полки, холодильники, кассы, стеллажи склада, коробки — «[FREE] Store Props [Asset pack]»,
--     автор SimplePolygon: https://sketchfab.com/3d-models/free-store-props-asset-pack-87a7f07bf1414543a073060388294f59
--   • продукты — «Food Collection - Game Ready», автор Melon Polygons:
--     https://sketchfab.com/3d-models/food-collection-game-ready-969b4e6ef7444650ba8a22a46d57ff43
--     Изменения: убраны пиво, вино и таблетки, этикетки с упоминанием алкоголя перерисованы,
--     модели разрезаны на отдельные продукты, выровнены и уменьшены текстуры до 1024×1024.
--
-- Size — размер модели в метрах (как в файле). В игре полки масштабируются Models.ShelfScale
-- (studs на метр), продукты — Models.ProductScale.
-- Pose продукта: Stand — стоит этикеткой вперёд; Stack — стоит и ставится в несколько ярусов;
-- Flat — лежит этикеткой вверх, стопкой; Upright — плоский пакет, поставленный на ребро.
local Models = {}

Models.Credits = {
	"«[FREE] Store Props» — SimplePolygon, CC BY 4.0",
	"«Food Collection - Game Ready» — Melon Polygons, CC BY 4.0",
	"«Cash register» — Dester, CC BY 4.0",
	"машины «Milano '95», «Fairheaven LT '80», «Fairheaven SW '84», «Negotiator '80», «Ace '11» — Daniel Zhabotinsky, CC BY 4.0",
	"«Flashlight» — Brandon Baldwin, CC BY 4.0",
	"«Pay Station Kiosk» — djeustice, CC BY 4.0",
	"«Anti-Theft Gate» — sneirox, CC BY 4.0",
	"«Shopping Cart» — AdrianXY, CC BY 4.0",
	"«Supermarket Basket» — cicinha, CC BY 4.0",
	"«Fire Extinguisher» — Loïc, CC BY 4.0",
	"«Office Chair Modern» — thethieme, CC BY 4.0",
	"«Office Computer» — sebodeweb, CC BY 4.0",
	"«Parcel 01» — tblunden, CC BY 4.0",
	"«Basket Shelving» — jimbogies, CC BY 4.0",
	"«CCTV Camera» — Smoggybeard, CC BY 4.0",
	"«Basic PC Monitors» — Sousinho, CC BY 4.0",
	"«Hanging Monitor» — MaX3Dd, CC BY 4.0",
	"«Retro CRT Computer» — MadeByYeshe, CC BY 4.0",
	"«Office Phone» — maxdragonn, CC BY 4.0",
	"«Security Cameras» — Renend Studio, CC BY 4.0",
	"«Trash can» — bazz4r, CC BY 4.0",
	"«Wooden Pallets» — YadroGames, CC BY 4.0",
	"«Low Poly Pallet Jack» — Monke, CC BY 4.0",
	"«Cardboard Box Set» — Nodeaxis Interactive, CC BY 4.0",
	"«Water cooler» — tboiston, CC BY 4.0",
	"«Smoke Detectors» — Lady Lion Studios, CC BY 4.0",
	"«Pothos Potted Plant» — AllQuad, CC BY 4.0",
	"«Step Ladder» и «Wet Floor Sign» — louis-muir, CC BY 4.0",
	"«File Cabinet» — Siberia, CC BY 4.0",
	"«Payment terminal» — nofurion, CC BY 4.0",
	"«Wooden Chair (Low Poly)» — Berk Gedik, CC BY 4.0",
	"«Microwave Oven» — MustafaYerebasmaz, CC BY 4.0",
	"«wheelie bin game asset» — BLENDERBROCPT, CC BY 4.0",
	"«Low Poly | Plastic Garbage Bags» — Anna Denisova, CC BY 4.0",
	"существо: «New Breaking News Rig» — NO DONT EAT ME CASEOH (Ferris wheel), CC BY 4.0",
	-- v14: окружение
	"«Pine Tree [Game-ready]» — Wenedi, CC BY 4.0",
	"«Spruce», «Fir tree», «Birch tree» — evolveduk, CC BY 4.0",
	"«Old russian house» — akiprensky, CC BY 4.0",
	"«Old Russian House» — Vodum Games, CC BY 4.0",
	"«Russian village house» — Ivan-Kanaev, CC BY 4.0",
	"«Simple russia village house» — Nkz, CC BY 4.0",
	"«Low-poly Brick House» — Vitalii.Sandula, CC BY 4.0",
	"«5 storey residential building» — bean(alwayshasbean), CC BY 4.0",
	"«Khrushchevka» — quizzes, CC BY 4.0",
	"«Worn Shed PBR Game-Ready» — donnichols, CC BY 4.0",
	"«Old House wooden» — wagnerlima07, CC BY 4.0",
	"«Wood Wooden fence Protector of the farm» — Mehdi Shahsavan, CC BY 4.0",
	"«Fence (Wood)» — trentspi, CC BY 4.0",
	"«Old Soviet Bus Stop» — Coozy, CC BY 4.0",
	-- v15: машина командной кат-сцены
	"«[FREE] VAZ 2107» — Mcflower's Creations, CC BY 4.0",
}

-- Существо из подсобки (v10): скелетная модель (53 кости, сетка 17 000 треугольников, рост 8.6),
-- анимации — Shared/BeastAnims (кадры Bone.Transform, играет клиент)
Models.Beast = { Id = 83140460125902, Height = 8.6 }

-- Целые модели с текстурами (загружаются через InsertService:LoadAsset):
--   Checkout — кассовый стол с лентой, кассовым аппаратом и денежным ящиком
--     https://sketchfab.com/3d-models/cash-register-ac4a966b35da48ddb0621a821c351074 (Dester)
--   Car* — машины вымышленных марок, значки на кузове заменены однотонным хромом
--     https://sketchfab.com/DanielZhabotinsky
--   Flashlight — фонарик https://sketchfab.com/3d-models/flashlight-fc5a0e9799de4eda932f2714f63f8d0c (Brandon Baldwin)
-- Scale — во сколько раз увеличить модель (в файле 1 единица = 1 stud).
Models.Assets = {
	Checkout = { Id = 140224040413189, Scale = 7.56 },
	Flashlight = { Id = 79324152063738 },
	CarMilano = { Id = 108547573785421, Scale = 3.6 },
	CarFairheavenLT = { Id = 77110994894817, Scale = 3.6 },
	CarNegotiator = { Id = 120487318164975, Scale = 3.6 },
	CarFairheavenSW = { Id = 103191321469470, Scale = 3.6 },
	CarAce = { Id = 105040233127033, Scale = 3.6 },
	-- v5: охрана и самообслуживание
	Kiosk = { Id = 88823043389915, Scale = 0.111 }, -- касса самообслуживания (экран смотрит в -Z)
	Gate = { Id = 139444852525706, Scale = 0.034 }, -- антикражные ворота
	Cart = { Id = 120126840224949, Scale = 4.2 }, -- тележка (ручка в +Z)
	Basket = { Id = 114267600200939, Scale = 0.65 }, -- корзина
	Extinguisher = { Id = 119882460876467, Scale = 1.1 },
	Chair = { Id = 102843122769194, Scale = 3.6 },
	Desk = { Id = 121794127557590, Scale = 0.034 }, -- стол охраны с компьютером и креслом (охранник смотрит в +X)
	Parcel = { Id = 89547355781897, Scale = 3.6 }, -- коробка заказа
	WireShelf = { Id = 99423585283502, Scale = 0.0914 }, -- сетчатый стеллаж выдачи заказов
	Cctv = { Id = 84074956484334, Scale = 0.65 }, -- уличная камера (объектив в -Z)
	-- v7: мониторы видеонаблюдения и детали магазина. Размер задаётся высотой (ModelKit.MakeAssetFit).
	-- Yaw — поворот модели (градусы), чтобы её перёд смотрел в LookVector; Pivot — точка опоры
	-- ("Bottom" — центр низа, по умолчанию; "Top" — центр верха; "Center" — центр).
	-- Screen — где у модели экран (в долях высоты модели, от центра низа, до поворота Yaw):
	--   Center — середина экрана, Normal — куда он смотрит, Size — ширина и высота.
	Monitor = { Id = 125105642155375, Screen = { Center = Vector3.new(0, 0.6074, -0.0064), Normal = Vector3.new(0, 0, -1), Size = Vector2.new(1.6036, 0.7852) } },
	HangMonitor = { Id = 85875618391017, Screen = { Center = Vector3.new(0.0006, 0.5019, -0.2058), Normal = Vector3.new(0, 0, -1), Size = Vector2.new(1.949, 0.9564) } },
	CrtPc = { Id = 71766440912992, Yaw = -90, Screen = { Center = Vector3.new(-0.2128, 0.6985, -0.043), Normal = Vector3.new(-1, 0, 0), Size = Vector2.new(0.5178, 0.429) } },
	Phone = { Id = 94426021245434 }, -- настольный телефон (кнопки к LookVector)
	Dome = { Id = 118805049958553, Pivot = "Top" }, -- купольная камера под потолком
	Dumpster = { Id = 79062416739544 }, -- два мусорных контейнера на колёсах
	Pallet = { Id = 71517003225220 }, -- деревянный поддон
	PalletJack = { Id = 113793426228049 }, -- тележка-рохля (ручка в -Z)
	Boxes = { Id = 104486093738413 }, -- груда картонных коробок
	Cooler = { Id = 112307488862621 }, -- кулер с водой (краники к LookVector)
	Smoke = { Id = 134169485672237, Pivot = "Center" }, -- датчик дыма (лицо к LookVector)
	Plant = { Id = 139199681076649 }, -- комнатное растение в горшке
	Ladder = { Id = 124769423327419 }, -- стремянка
	WetFloor = { Id = 75496316109050 }, -- табличка «Осторожно, мокрый пол» (надписи на сторонах ±X)
	FileCab = { Id = 83969532200460 }, -- картотечный шкаф (ящики к LookVector)
	-- v8: платёжный терминал на кассе самообслуживания (клавиатура к LookVector, надпись производителя закрашена)
	Terminal = { Id = 135635399525375 },
	-- v9: комната персонала и склад
	WoodChair = { Id = 99262791783790, Yaw = 180 }, -- деревянный стул (сиденье к LookVector)
	Microwave = { Id = 137128632495880 }, -- микроволновка (дверца к LookVector, логотип закрашен)
	Bin = { Id = 73474780575399 }, -- мусорный бак на колёсах (надпись на корпусе закрашена)
	Bags = { Id = 94638446661345 }, -- чёрные мешки с мусором
	-- v14: окружение магазина (Surroundings). Размеры — как в файле модели, масштаб задаёт Surroundings
	EnvPine = { Id = 124078411463680 }, -- густая ель (высота 75)
	EnvSpruce = { Id = 127346657724529 }, -- высокая ель (10.5)
	EnvFir = { Id = 83527090935545 }, -- пихта (4.4)
	EnvBirch = { Id = 106108147033559 }, -- берёза (8.2)
	EnvHouseAki = { Id = 88025745110275 }, -- изба с резными наличниками (5.1 × 3.4 × 5.6)
	EnvHouseVodum = { Id = 122596926624355 }, -- старый дом, вход со ступеньками сбоку (9.1 × 5.7 × 9.3)
	EnvHouseLong = { Id = 102864424351525 }, -- длинный деревенский дом (22 × 6.1 × 13)
	EnvHouseSmall = { Id = 100724127614950 }, -- маленький дом (9 × 8.6 × 10.4)
	EnvHouseBrick = { Id = 95380698140771 }, -- кирпичный дом с верандой (4.8 × 3.1 × 5.6)
	EnvPanel5 = { Id = 126052708515261 }, -- пятиэтажка (32 × 18.8 × 15.6)
	EnvKhrush = { Id = 71980335507064 }, -- хрущёвка (5.5 × 6.6 × 13.3)
	EnvShed = { Id = 77235282581891 }, -- сарай с крыльцом (644 × 355 × 434)
	EnvShack = { Id = 114336275103441 }, -- заброшенная лачуга (10.3 × 7.8 × 7.8)
	EnvFence = { Id = 122080121602864 }, -- секция деревянного забора с кирпичным столбом (длина по Z 285)
	EnvRail = { Id = 125870193960634 }, -- жердевая изгородь (длина по Z 4)
	EnvBusStop = { Id = 139000138218733 }, -- советская остановка (длина по Z 247; открыта в −X)
	-- v15: «семёрка» командной кат-сцены (tools/models/prep_car.py): двери, колёса и руль — отдельные детали;
	-- в игре перёд машины +Z, водитель (левый руль) +X; опора — центр низа
	TeamCar = { Id = 116238015565300, Scale = 3.5 },
}
-- Листва и хвоя (v14): загрузка в Roblox не сохраняет прозрачность (SurfaceAppearance — режим Overlay),
-- поэтому у этих деталей SurfaceAppearance снимается, а текстура с альфой ставится в MeshPart.TextureID.
-- Ключ — начало имени детали в модели
Models.Leaves = {
	EnvPine = { Branches = "rbxassetid://82627531100240" },
	EnvSpruce = { ["spruce branch"] = "rbxassetid://102145612007561", branch06 = "rbxassetid://106717516922242" },
	EnvFir = { Tree_1 = "rbxassetid://70566649463073" },
	EnvBirch = { ["birch leaf"] = "rbxassetid://110074246295649" },
}

Models.StaffCar = "CarMilano"
Models.ParkedCars = { "CarFairheavenLT", "CarNegotiator", "CarFairheavenSW", "CarAce" }

-- Кассовый стол: где лента, столешница и ящик (единицы модели; ось X модели — длина, Z — глубина).
-- Roblox при импорте разворачивает модель на 180°, поэтому в игре знаки X и Z противоположны файлу.
Models.Checkout = {
	BeltTop = 0.41, -- верх ленты от низа модели
	Top = 0.432, -- столешница
	BeltLength = { -0.475, 0.205 }, -- лента вдоль X (в файле)
	BeltDepth = { 0.009, 0.25 }, -- лента по Z (в файле, сторона кассира)
	Drawer = { 0.22, 0.46 }, -- денежный ящик вдоль X (в файле)
}

-- Собственные анимации (tools/make_anims.py): ходьба, бег, ожидание.
-- В ходьбе и беге стоят метки «Step» (L/R) в момент касания пяткой — по ним играют звуки шагов.
Models.Anim = {
	Walk = "rbxassetid://105108708797939",
	Run = "rbxassetid://81706662511100",
	Idle = "rbxassetid://109915448085677",
	WalkNatural = 9, -- скорость (studs/с), при которой шаг идёт в своём темпе
	RunNatural = 17,
	RunFrom = 15, -- с этой скорости персонаж бежит
	-- действия покупателей (с метками звуков: Beep, Bag, Grab, Rustle, Tap, Take)
	Actions = {
		Scan = "rbxassetid://130847971220121", -- сканирует товары на кассе самообслуживания (цикл)
		Reach = "rbxassetid://97470065632038", -- берёт товар с полки
		Conceal = "rbxassetid://78183686321833", -- прячет товар под куртку
		Pay = "rbxassetid://133420934800294", -- прикладывает карту
		Take = "rbxassetid://90800489403547", -- берёт коробку с заказом
		Look = "rbxassetid://127169663327962", -- оглядывается
		HandsUp = "rbxassetid://128214517532276", -- пойман: руки вверх
	},
}

-- Реалистичные покупатели (тела, лица, одежда из каталога Roblox)
Models.RealisticPeople = true

Models.ShelfScale = 3.6
Models.ProductScale = 4.4

Models.Palette = "rbxassetid://80074182632801" -- текстура-палитра набора полок

-- Модели с текстурами продуктов: у них берём PBR-материал (SurfaceAppearance)
Models.Carriers = {
	Asset = 119073258280364,
	Asset_2 = 94395595599002,
}

Models.Meshes = {
	-- полки, холодильники, кассы, склад
	GondolaDouble2m = { Mesh = "rbxassetid://130389583565694", Size = Vector3.new(1.2006, 1.9317, 2.0420), Atlas = "Palette", Precise = true }, -- двусторонний стеллаж 2 м
	GondolaDouble1m = { Mesh = "rbxassetid://76348776621783", Size = Vector3.new(1.2001, 1.9317, 1.0212), Atlas = "Palette", Precise = true }, -- двусторонний стеллаж 1 м
	WallShelf2m = { Mesh = "rbxassetid://107140029072070", Size = Vector3.new(0.6007, 1.9317, 2.0417), Atlas = "Palette", Precise = true }, -- пристенный стеллаж 2 м
	WallShelf1m = { Mesh = "rbxassetid://88431396121295", Size = Vector3.new(0.6003, 1.9317, 1.0209), Atlas = "Palette", Precise = true }, -- пристенный стеллаж 1 м
	CornerShelf = { Mesh = "rbxassetid://75606026940673", Size = Vector3.new(1.2527, 1.9317, 1.2531), Atlas = "Palette", Precise = true }, -- угловой стеллаж
	OpenChiller2m = { Mesh = "rbxassetid://122223785570520", Size = Vector3.new(0.6008, 2.2614, 2.1233), Atlas = "Palette", Precise = true }, -- открытая холодильная горка 2 м
	OpenChiller1m = { Mesh = "rbxassetid://95010295745158", Size = Vector3.new(0.6003, 2.2614, 1.0618), Atlas = "Palette", Precise = true }, -- открытая холодильная горка 1 м
	DrinkCooler1 = { Mesh = "rbxassetid://89621837535661", Size = Vector3.new(0.4714, 2.0854, 0.7400), Atlas = "Palette", Precise = true }, -- шкаф-холодильник для напитков, 1 дверь
	DrinkCooler2 = { Mesh = "rbxassetid://82581719935055", Size = Vector3.new(0.4714, 2.0854, 1.4799), Atlas = "Palette", Precise = true }, -- шкаф-холодильник для напитков, 2 двери
	CoolerDoor1 = { Mesh = "rbxassetid://114464594786472", Size = Vector3.new(0.0620, 1.5523, 0.7177), Atlas = "Palette", Precise = false }, -- рама стеклянной двери, 1 створка
	CoolerDoor2 = { Mesh = "rbxassetid://84161466914968", Size = Vector3.new(0.0621, 1.5523, 1.4575), Atlas = "Palette", Precise = false }, -- рама стеклянной двери, 2 створки
	Rack2m = { Mesh = "rbxassetid://101721151294959", Size = Vector3.new(0.7713, 2.9786, 1.7845), Atlas = "Palette", Precise = true }, -- складской стеллаж 3 м, 1.8 м длиной
	Rack1m = { Mesh = "rbxassetid://121759250889232", Size = Vector3.new(0.7710, 2.9786, 1.0476), Atlas = "Palette", Precise = true }, -- складской стеллаж 3 м, 1 м длиной
	RackLow2m = { Mesh = "rbxassetid://72258371867958", Size = Vector3.new(0.7713, 2.3935, 1.7845), Atlas = "Palette", Precise = true }, -- складской стеллаж 2.4 м
	RackLow1m = { Mesh = "rbxassetid://118825387882017", Size = Vector3.new(0.7710, 2.3935, 1.0476), Atlas = "Palette", Precise = true }, -- складской стеллаж 2.4 м, узкий
	Register = { Mesh = "rbxassetid://93378367538519", Size = Vector3.new(0.4331, 0.5473, 0.6469), Atlas = "Palette", Precise = false }, -- кассовый аппарат
	PosScreen = { Mesh = "rbxassetid://119082506251272", Size = Vector3.new(0.3565, 0.4998, 0.5580), Atlas = "Palette", Precise = false }, -- монитор кассы
	CashDrawer = { Mesh = "rbxassetid://77611474422581", Size = Vector3.new(0.3507, 0.1408, 0.6199), Atlas = "Palette", Precise = false }, -- денежный ящик
	BoxClosed = { Mesh = "rbxassetid://74730342116204", Size = Vector3.new(0.4153, 0.4185, 0.4153), Atlas = "Palette", Precise = false }, -- закрытая коробка
	BoxFlat = { Mesh = "rbxassetid://121637475646330", Size = Vector3.new(0.4154, 0.2710, 0.5341), Atlas = "Palette", Precise = false }, -- плоская коробка
	BoxOpen = { Mesh = "rbxassetid://91043171986620", Size = Vector3.new(0.4154, 0.4186, 0.5808), Atlas = "Palette", Precise = false }, -- открытая коробка
	BoxTray = { Mesh = "rbxassetid://99319936748984", Size = Vector3.new(0.4154, 0.2710, 0.6884), Atlas = "Palette", Precise = false }, -- лоток
	-- продукты
	Bleach = { Mesh = "rbxassetid://97946264192640", Size = Vector3.new(0.1608, 0.3004, 0.1542), Atlas = "Asset_2", Pose = "Stand", Shadow = false },
	Bottle = { Mesh = "rbxassetid://70468853169406", Size = Vector3.new(0.0503, 0.1889, 0.0504), Atlas = "Asset_2", Pose = "Stand", Shadow = false },
	BottlesPack = { Mesh = "rbxassetid://82827252776180", Size = Vector3.new(0.2149, 0.1978, 0.1735), Atlas = "Asset_2", Pose = "Stand", Shadow = false },
	Candies = { Mesh = "rbxassetid://124591860782097", Size = Vector3.new(0.2118, 0.0253, 0.0957), Atlas = "Asset", Pose = "Flat", Shadow = false },
	Sardines = { Mesh = "rbxassetid://136815890161200", Size = Vector3.new(0.1283, 0.0270, 0.0776), Atlas = "Asset", Pose = "Flat", Shadow = false },
	Can06 = { Mesh = "rbxassetid://96086407622600", Size = Vector3.new(0.0761, 0.1277, 0.0761), Atlas = "Asset", Pose = "Stack", Shadow = false },
	Can07 = { Mesh = "rbxassetid://84558680570497", Size = Vector3.new(0.0761, 0.1277, 0.0761), Atlas = "Asset", Pose = "Stack", Shadow = false },
	Can08 = { Mesh = "rbxassetid://133844029576848", Size = Vector3.new(0.0762, 0.0847, 0.0761), Atlas = "Asset", Pose = "Stack", Shadow = false },
	Can09 = { Mesh = "rbxassetid://116336221145467", Size = Vector3.new(0.0760, 0.0847, 0.0762), Atlas = "Asset", Pose = "Stack", Shadow = false },
	Can10 = { Mesh = "rbxassetid://86224898285580", Size = Vector3.new(0.0761, 0.0422, 0.0761), Atlas = "Asset", Pose = "Stack", Shadow = false },
	Can11 = { Mesh = "rbxassetid://97148106734663", Size = Vector3.new(0.0761, 0.0428, 0.0760), Atlas = "Asset", Pose = "Stack", Shadow = false },
	Can12 = { Mesh = "rbxassetid://110156203084960", Size = Vector3.new(0.0759, 0.0628, 0.0761), Atlas = "Asset", Pose = "Stack", Shadow = false },
	Can13 = { Mesh = "rbxassetid://83648253122651", Size = Vector3.new(0.0760, 0.0628, 0.0761), Atlas = "Asset", Pose = "Stack", Shadow = false },
	Cereal = { Mesh = "rbxassetid://122245746694747", Size = Vector3.new(0.1545, 0.1865, 0.0353), Atlas = "Asset_2", Pose = "Stand", Shadow = false },
	Gum = { Mesh = "rbxassetid://74125848176668", Size = Vector3.new(0.0655, 0.0075, 0.0182), Atlas = "Asset_2", Pose = "Flat", Shadow = false },
	ChocoBar1 = { Mesh = "rbxassetid://98958734444772", Size = Vector3.new(0.1205, 0.0097, 0.0279), Atlas = "Asset_2", Pose = "Flat", Shadow = false },
	ChocoBar2 = { Mesh = "rbxassetid://89473022524394", Size = Vector3.new(0.1204, 0.0097, 0.0276), Atlas = "Asset_2", Pose = "Flat", Shadow = false },
	Coffee = { Mesh = "rbxassetid://108604341718128", Size = Vector3.new(0.1261, 0.2155, 0.0300), Atlas = "Asset", Pose = "Stand", Shadow = false },
	DetergentLiquid = { Mesh = "rbxassetid://121524837597375", Size = Vector3.new(0.1203, 0.2347, 0.0849), Atlas = "Asset_2", Pose = "Stand", Shadow = false },
	DetergentPowder1 = { Mesh = "rbxassetid://138677926550380", Size = Vector3.new(0.0846, 0.2313, 0.0836), Atlas = "Asset_2", Pose = "Stand", Shadow = false },
	DetergentPowder2 = { Mesh = "rbxassetid://130329003898278", Size = Vector3.new(0.1546, 0.1865, 0.0358), Atlas = "Asset_2", Pose = "Stand", Shadow = false },
	DetergentPowder3 = { Mesh = "rbxassetid://73128032737933", Size = Vector3.new(0.0465, 0.1380, 0.0477), Atlas = "Asset_2", Pose = "Stand", Shadow = false },
	DishSoap = { Mesh = "rbxassetid://127776170308781", Size = Vector3.new(0.1009, 0.2262, 0.0592), Atlas = "Asset_2", Pose = "Stand", Shadow = false },
	Glue = { Mesh = "rbxassetid://116682396331544", Size = Vector3.new(0.1199, 0.0264, 0.0284), Atlas = "Asset_2", Pose = "Flat", Shadow = false },
	Juice = { Mesh = "rbxassetid://86008994287010", Size = Vector3.new(0.1000, 0.2373, 0.0716), Atlas = "Asset_2", Pose = "Stand", Shadow = false },
	Matches = { Mesh = "rbxassetid://123084819706874", Size = Vector3.new(0.0500, 0.0109, 0.0332), Atlas = "Asset_2", Pose = "Flat", Shadow = false },
	Milk = { Mesh = "rbxassetid://107406249064768", Size = Vector3.new(0.0891, 0.2343, 0.0888), Atlas = "Asset", Pose = "Stand", Shadow = false },
	OliveOil = { Mesh = "rbxassetid://115460882747759", Size = Vector3.new(0.0632, 0.2310, 0.0632), Atlas = "Asset_2", Pose = "Stand", Shadow = false },
	Pasta = { Mesh = "rbxassetid://138281691636019", Size = Vector3.new(0.0888, 0.2518, 0.0490), Atlas = "Asset_2", Pose = "Stand", Shadow = false },
	Porridge = { Mesh = "rbxassetid://109531710568078", Size = Vector3.new(0.1477, 0.2155, 0.0393), Atlas = "Asset", Pose = "Stand", Shadow = false },
	ProteinJar = { Mesh = "rbxassetid://92408595118032", Size = Vector3.new(0.1485, 0.1907, 0.1483), Atlas = "Asset", Pose = "Stand", Shadow = false },
	Salt = { Mesh = "rbxassetid://85154039387059", Size = Vector3.new(0.0955, 0.2155, 0.0299), Atlas = "Asset", Pose = "Stand", Shadow = false },
	Sausages = { Mesh = "rbxassetid://120791929912253", Size = Vector3.new(0.1613, 0.0373, 0.2158), Atlas = "Asset", Pose = "Flat", Shadow = false },
	Sauce = { Mesh = "rbxassetid://122262232631738", Size = Vector3.new(0.0812, 0.1943, 0.0613), Atlas = "Asset", Pose = "Stand", Shadow = false },
	Snack = { Mesh = "rbxassetid://122209754886272", Size = Vector3.new(0.1400, 0.0463, 0.2223), Atlas = "Asset_2", Pose = "Upright", Shadow = false },
}

-- Какие продукты на каких полках
Models.Shelf = {
	Snacks = { "Snack", "ChocoBar1", "ChocoBar2", "Candies", "Gum" },
	Grocery = { "Cereal", "Pasta", "Porridge", "Coffee", "Salt", "OliveOil", "Sauce" },
	Drinks = { "Bottle", "Juice", "BottlesPack" },
	Cans = { "Can06", "Can07", "Can08", "Can09", "Can10", "Can11", "Can12", "Can13", "Sardines" },
	Household = { "Bleach", "DetergentLiquid", "DetergentPowder1", "DetergentPowder2", "DetergentPowder3", "DishSoap", "Glue", "Matches" },
	Chilled = { "Milk", "Juice", "Sausages", "ProteinJar" },
}

-- Высоты полок у моделей (метры от низа модели, по замерам меша)
Models.Levels = {
	Gondola = { 0.22, 0.8, 1.38 }, -- верх 1.93
	WallShelf = { 0.22, 0.8, 1.38 },
	OpenChiller = { 0.5, 1.04, 1.59 }, -- верх ниши 2.07
	DrinkCooler = { 0.33, 0.7, 1.07, 1.44 }, -- верх 1.84
	Rack = { 0.06, 0.65, 1.23, 1.81, 2.39 },
}

return Models
