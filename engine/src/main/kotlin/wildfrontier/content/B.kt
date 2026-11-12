package wildfrontier.content

import wildcore.world.BlockDef
import wildcore.world.Blocks
import wildcore.world.Shape
import wildcore.world.SoundMat
import wildcore.world.ToolKind
import wildcore.world.VFlag

/** Block ids of WILD FRONTIER. Ids are persisted in save files — never renumber. */
object B {
    const val AIR = 0
    const val GRASS = 1; const val DIRT = 2; const val STONE = 3; const val SAND = 4; const val GRAVEL = 5
    const val CLAY = 6; const val SNOW = 7; const val ICE = 8; const val WATER = 9
    const val OAK_LOG = 10; const val OAK_LEAVES = 11; const val PINE_LOG = 12; const val PINE_LEAVES = 13
    const val BIRCH_LOG = 14; const val BIRCH_LEAVES = 15; const val PALM_LOG = 16; const val PALM_LEAVES = 17
    const val JUNGLE_LEAVES = 18; const val FRUIT_LEAVES = 19
    const val COAL_ORE = 20; const val COPPER_ORE = 21; const val IRON_ORE = 22; const val GOLD_ORE = 23; const val CRYSTAL_ORE = 24
    const val MOSSY_STONE = 25; const val SANDSTONE = 26; const val MUD = 27; const val FOREST_FLOOR = 28
    const val GRASS_LUSH = 29; const val GRASS_DRY = 30; const val SNOWY_GRASS = 31; const val BEDROCK = 32
    const val OAK_LOG_X = 33; const val OAK_LOG_Z = 34; const val PINE_LOG_X = 35; const val PINE_LOG_Z = 36
    const val BIRCH_LOG_X = 37; const val BIRCH_LOG_Z = 38
    const val PLANKS_OAK = 40; const val PLANKS_PINE = 41; const val COBBLE = 42; const val STONE_BRICKS = 43
    const val BRICKS = 44; const val GLASS = 45; const val THATCH = 46
    const val WORKBENCH = 50; const val FURNACE = 51; const val CHEST = 52; const val CAMPFIRE = 53; const val TORCH = 54
    const val BEDROLL = 55; const val FARMLAND = 56; const val FARMLAND_WET = 57
    const val METAL_PANEL = 60; const val LAB_FLOOR = 61; const val RUSTY_METAL = 62; const val LAMP = 63
    const val CRATE = 64; const val TERMINAL = 65
    const val TALL_GRASS = 70; const val FERN = 71; const val FLOWER_RED = 72; const val FLOWER_YELLOW = 73
    const val FLOWER_BLUE = 74; const val MUSHROOM = 75; const val REEDS = 76; const val BERRY_BUSH = 77
    const val BERRY_BUSH_EMPTY = 78; const val DEAD_BUSH = 79; const val SAPLING = 80
    const val WHEAT_0 = 84; const val WHEAT_3 = 87
    const val CARROT_0 = 88; const val CARROT_3 = 91

    private var registered = false

    /** Registers every block. Item drop ids are resolved against [I]. Safe to call repeatedly. */
    @Synchronized fun registerAll() {
        if (registered) return
        registered = true
        Blocks.clear()
        fun t(n: String) = Tex.of(n)
        fun cube(id: Int, key: String, name: String, top: String, side: String = top, bottom: String = side,
                 hard: Float, tool: Int = ToolKind.NONE, tier: Int = 0, drop: Int = id, dropMin: Int = 1, dropMax: Int = 1,
                 uv: Int = 2, sound: Int = SoundMat.STONE, emission: Int = 0, flags: Int = 0, axis: Int = 1) {
            Blocks.register(BlockDef(id, key, name, Shape.CUBE, t(top), t(side), t(bottom), hardness = hard, tool = tool,
                requiredTier = tier, dropItem = drop, dropMin = dropMin, dropMax = dropMax, flags = uv or flags,
                sound = sound, emission = emission, axis = axis))
        }
        fun leaves(id: Int, key: String, name: String, tex: String, drop: Int, dropMax: Int = 1) {
            Blocks.register(BlockDef(id, key, name, Shape.CUTOUT, t(tex), t(tex), t(tex), lightOpacity = 2, hardness = 0.35f,
                tool = ToolKind.SICKLE, dropItem = drop, dropMin = 0, dropMax = dropMax, flags = 1 or VFlag.FLUTTER, sound = SoundMat.LEAVES))
        }
        fun plant(id: Int, key: String, name: String, tex: String, drop: Int, height: Float = 0.9f, dropMin: Int = 1, dropMax: Int = 1, sway: Boolean = true) {
            Blocks.register(BlockDef(id, key, name, Shape.CROSS, t(tex), t(tex), t(tex), solid = false, lightOpacity = 0,
                hardness = 0.08f, tool = ToolKind.SICKLE, dropItem = drop, dropMin = dropMin, dropMax = dropMax,
                flags = if (sway) VFlag.SWAY else 0, sound = SoundMat.LEAVES, replaceable = true, boxMaxY = height, needsSupport = true))
        }

        Blocks.register(BlockDef(AIR, "air", "Воздух", Shape.AIR, 0, 0, 0, solid = false, lightOpacity = 0, hardness = -1f, replaceable = true))
        // --- natural ground
        cube(GRASS, "grass", "Дёрн", "grass_top", "grass_side", "dirt", hard = 0.9f, tool = ToolKind.SHOVEL, drop = DIRT, sound = SoundMat.GRASS)
        cube(DIRT, "dirt", "Земля", "dirt", hard = 0.8f, tool = ToolKind.SHOVEL, sound = SoundMat.GRASS)
        cube(STONE, "stone", "Камень", "stone", hard = 6f, tool = ToolKind.PICKAXE, tier = 1, drop = COBBLE)
        cube(SAND, "sand", "Песок", "sand", hard = 0.7f, tool = ToolKind.SHOVEL, sound = SoundMat.SAND)
        cube(GRAVEL, "gravel", "Гравий", "gravel", hard = 0.9f, tool = ToolKind.SHOVEL, sound = SoundMat.SAND)
        cube(CLAY, "clay", "Глина", "clay", hard = 1.0f, tool = ToolKind.SHOVEL, drop = I.CLAY_BALL, dropMin = 2, dropMax = 4, sound = SoundMat.SAND)
        cube(SNOW, "snow", "Снег", "snow", hard = 0.5f, tool = ToolKind.SHOVEL, sound = SoundMat.SNOW)
        cube(ICE, "ice", "Лёд", "ice", hard = 1.5f, tool = ToolKind.PICKAXE, sound = SoundMat.STONE)
        Blocks.register(BlockDef(WATER, "water", "Вода", Shape.LIQUID, t("ice"), t("ice"), t("ice"), solid = false, lightOpacity = 1,
            hardness = -1f, flags = VFlag.WATER, sound = SoundMat.WATER, replaceable = true))
        cube(MOSSY_STONE, "mossy_stone", "Замшелый камень", "mossy_stone", hard = 6f, tool = ToolKind.PICKAXE, tier = 1)
        cube(SANDSTONE, "sandstone", "Песчаник", "sandstone", hard = 4f, tool = ToolKind.PICKAXE, tier = 1)
        cube(MUD, "mud", "Ил", "mud", hard = 0.9f, tool = ToolKind.SHOVEL, sound = SoundMat.SAND)
        cube(FOREST_FLOOR, "forest_floor", "Лесная подстилка", "forest_floor", "dirt", "dirt", hard = 0.9f, tool = ToolKind.SHOVEL, drop = DIRT, sound = SoundMat.GRASS)
        cube(GRASS_LUSH, "grass_lush", "Тропический дёрн", "grass_lush", "lush_side", "dirt", hard = 0.9f, tool = ToolKind.SHOVEL, drop = DIRT, sound = SoundMat.GRASS)
        cube(GRASS_DRY, "grass_dry", "Сухой дёрн", "grass_dry", "dry_side", "dirt", hard = 0.9f, tool = ToolKind.SHOVEL, drop = DIRT, sound = SoundMat.GRASS)
        cube(SNOWY_GRASS, "snowy_grass", "Заснеженная земля", "snow", "snow_side", "dirt", hard = 0.9f, tool = ToolKind.SHOVEL, drop = DIRT, sound = SoundMat.SNOW)
        cube(BEDROCK, "bedrock", "Коренная порода", "bedrock", hard = -1f)
        // --- trees
        cube(OAK_LOG, "oak_log", "Бревно дуба", "oak_top", "oak_bark", "oak_top", hard = 2.4f, tool = ToolKind.AXE, uv = 0, sound = SoundMat.WOOD)
        cube(PINE_LOG, "pine_log", "Бревно сосны", "pine_top", "pine_bark", "pine_top", hard = 2.2f, tool = ToolKind.AXE, uv = 0, sound = SoundMat.WOOD)
        cube(BIRCH_LOG, "birch_log", "Бревно берёзы", "birch_top", "birch_bark", "birch_top", hard = 2.2f, tool = ToolKind.AXE, uv = 0, sound = SoundMat.WOOD)
        cube(PALM_LOG, "palm_log", "Ствол пальмы", "palm_top", "palm_bark", "palm_top", hard = 2.0f, tool = ToolKind.AXE, uv = 0, sound = SoundMat.WOOD)
        cube(OAK_LOG_X, "oak_log_x", "Бревно дуба", "oak_top", "oak_bark", "oak_top", hard = 2.4f, tool = ToolKind.AXE, uv = 0, sound = SoundMat.WOOD, drop = OAK_LOG, axis = 0)
        cube(OAK_LOG_Z, "oak_log_z", "Бревно дуба", "oak_top", "oak_bark", "oak_top", hard = 2.4f, tool = ToolKind.AXE, uv = 0, sound = SoundMat.WOOD, drop = OAK_LOG, axis = 2)
        cube(PINE_LOG_X, "pine_log_x", "Бревно сосны", "pine_top", "pine_bark", "pine_top", hard = 2.2f, tool = ToolKind.AXE, uv = 0, sound = SoundMat.WOOD, drop = PINE_LOG, axis = 0)
        cube(PINE_LOG_Z, "pine_log_z", "Бревно сосны", "pine_top", "pine_bark", "pine_top", hard = 2.2f, tool = ToolKind.AXE, uv = 0, sound = SoundMat.WOOD, drop = PINE_LOG, axis = 2)
        cube(BIRCH_LOG_X, "birch_log_x", "Бревно берёзы", "birch_top", "birch_bark", "birch_top", hard = 2.2f, tool = ToolKind.AXE, uv = 0, sound = SoundMat.WOOD, drop = BIRCH_LOG, axis = 0)
        cube(BIRCH_LOG_Z, "birch_log_z", "Бревно берёзы", "birch_top", "birch_bark", "birch_top", hard = 2.2f, tool = ToolKind.AXE, uv = 0, sound = SoundMat.WOOD, drop = BIRCH_LOG, axis = 2)
        leaves(OAK_LEAVES, "oak_leaves", "Листва дуба", "oak_leaves", I.STICK)
        leaves(PINE_LEAVES, "pine_leaves", "Хвоя", "pine_leaves", I.STICK)
        leaves(BIRCH_LEAVES, "birch_leaves", "Листва берёзы", "birch_leaves", I.STICK)
        leaves(PALM_LEAVES, "palm_leaves", "Листья пальмы", "palm_leaves", I.PLANT_FIBER, 2)
        leaves(JUNGLE_LEAVES, "jungle_leaves", "Тропическая листва", "jungle_leaves", I.PLANT_FIBER)
        leaves(FRUIT_LEAVES, "fruit_leaves", "Яблоня", "fruit_leaves", I.APPLE, 2)
        // --- ores
        cube(COAL_ORE, "coal_ore", "Угольная руда", "coal_ore", hard = 7f, tool = ToolKind.PICKAXE, tier = 1, drop = I.COAL, dropMax = 2)
        cube(COPPER_ORE, "copper_ore", "Медная руда", "copper_ore", hard = 8f, tool = ToolKind.PICKAXE, tier = 1, drop = I.RAW_COPPER)
        cube(IRON_ORE, "iron_ore", "Железная руда", "iron_ore", hard = 9f, tool = ToolKind.PICKAXE, tier = 2, drop = I.RAW_IRON)
        cube(GOLD_ORE, "gold_ore", "Золотая руда", "gold_ore", hard = 10f, tool = ToolKind.PICKAXE, tier = 3, drop = I.RAW_GOLD)
        cube(CRYSTAL_ORE, "crystal_ore", "Кристалл эфирита", "crystal_ore", hard = 12f, tool = ToolKind.PICKAXE, tier = 3, drop = I.CRYSTAL, emission = 7)
        // --- building
        cube(PLANKS_OAK, "planks_oak", "Дубовые доски", "planks_oak", hard = 1.8f, tool = ToolKind.AXE, uv = 1, sound = SoundMat.WOOD)
        cube(PLANKS_PINE, "planks_pine", "Сосновые доски", "planks_pine", hard = 1.8f, tool = ToolKind.AXE, uv = 1, sound = SoundMat.WOOD)
        cube(COBBLE, "cobblestone", "Булыжник", "cobblestone", hard = 6f, tool = ToolKind.PICKAXE, tier = 1, uv = 1)
        cube(STONE_BRICKS, "stone_bricks", "Каменный кирпич", "stone_bricks", hard = 7f, tool = ToolKind.PICKAXE, tier = 1, uv = 1)
        cube(BRICKS, "bricks", "Кирпич", "bricks", hard = 6f, tool = ToolKind.PICKAXE, tier = 1, uv = 1)
        Blocks.register(BlockDef(GLASS, "glass", "Стекло", Shape.CUTOUT, t("glass"), t("glass"), t("glass"), lightOpacity = 0,
            hardness = 0.5f, dropItem = GLASS, flags = 0, sound = SoundMat.STONE))
        cube(THATCH, "thatch", "Соломенная кровля", "thatch", hard = 0.8f, tool = ToolKind.SICKLE, uv = 1, sound = SoundMat.LEAVES)
        // --- stations & utility
        cube(WORKBENCH, "workbench", "Верстак", "workbench_top", "workbench_side", "planks_oak", hard = 2f, tool = ToolKind.AXE, uv = 0, sound = SoundMat.WOOD)
        cube(FURNACE, "furnace", "Печь", "furnace_top", "furnace_side", "furnace_top", hard = 6f, tool = ToolKind.PICKAXE, uv = 0)
        cube(CHEST, "chest", "Сундук", "chest_top", "chest_side", "chest_top", hard = 2f, tool = ToolKind.AXE, uv = 0, sound = SoundMat.WOOD)
        Blocks.register(BlockDef(CAMPFIRE, "campfire", "Костёр", Shape.BOX, t("campfire"), t("campfire"), t("campfire"), solid = true, lightOpacity = 0,
            emission = 13, hardness = 1f, dropItem = CAMPFIRE, flags = 0, sound = SoundMat.WOOD, boxMin = 0.0625f, boxMaxY = 0.375f))
        Blocks.register(BlockDef(TORCH, "torch", "Факел", Shape.BOX, t("torch"), t("torch"), t("planks_oak"), solid = false, lightOpacity = 0,
            emission = 14, hardness = 0.05f, dropItem = TORCH, flags = VFlag.EMISSIVE, sound = SoundMat.WOOD, boxMin = 0.4375f, boxMaxY = 0.625f, needsSupport = true))
        Blocks.register(BlockDef(BEDROLL, "bedroll", "Спальный мешок", Shape.BOX, t("bedroll"), t("bedroll"), t("bedroll"), solid = true, lightOpacity = 0,
            hardness = 0.6f, dropItem = BEDROLL, flags = 0, sound = SoundMat.LEAVES, boxMin = 0f, boxMaxY = 0.25f))
        cube(FARMLAND, "farmland", "Грядка", "farmland", "dirt", "dirt", hard = 0.8f, tool = ToolKind.SHOVEL, drop = DIRT, uv = 0, sound = SoundMat.GRASS)
        cube(FARMLAND_WET, "farmland_wet", "Политая грядка", "farmland_wet", "dirt", "dirt", hard = 0.8f, tool = ToolKind.SHOVEL, drop = DIRT, uv = 0, sound = SoundMat.GRASS)
        // --- expedition / laboratory
        cube(METAL_PANEL, "metal_panel", "Металлическая панель", "metal_panel", hard = 9f, tool = ToolKind.PICKAXE, tier = 2, uv = 1, sound = SoundMat.METAL)
        cube(LAB_FLOOR, "lab_floor", "Лабораторный пол", "lab_floor", hard = 8f, tool = ToolKind.PICKAXE, tier = 2, uv = 1, sound = SoundMat.METAL)
        cube(RUSTY_METAL, "rusty_metal", "Ржавый металл", "rusty_metal", hard = 7f, tool = ToolKind.PICKAXE, tier = 1, uv = 1, sound = SoundMat.METAL)
        cube(LAMP, "lamp", "Лампа", "lamp", hard = 1f, uv = 0, emission = 15, flags = VFlag.EMISSIVE, sound = SoundMat.METAL)
        cube(CRATE, "crate", "Ящик экспедиции", "crate", hard = 2f, tool = ToolKind.AXE, uv = 0, sound = SoundMat.WOOD)
        cube(TERMINAL, "terminal", "Терминал", "metal_panel", "terminal", "metal_panel", hard = -1f, uv = 0, emission = 6, sound = SoundMat.METAL)
        // --- plants
        plant(TALL_GRASS, "tall_grass", "Трава", "tall_grass", I.PLANT_FIBER, 0.85f, 0, 1)
        plant(FERN, "fern", "Папоротник", "fern", I.PLANT_FIBER, 0.8f, 0, 1)
        plant(FLOWER_RED, "flower_red", "Мак", "flower_red", FLOWER_RED, 0.7f)
        plant(FLOWER_YELLOW, "flower_yellow", "Лютик", "flower_yellow", FLOWER_YELLOW, 0.65f)
        plant(FLOWER_BLUE, "flower_blue", "Василёк", "flower_blue", FLOWER_BLUE, 0.7f)
        plant(MUSHROOM, "mushroom", "Гриб", "mushroom", I.MUSHROOM, 0.45f, sway = false)
        plant(REEDS, "reeds", "Камыш", "reeds", I.PLANT_FIBER, 1.0f, 1, 2)
        plant(BERRY_BUSH, "berry_bush", "Ягодный куст", "berry_bush", I.BERRIES, 0.95f, 2, 4, sway = false)
        plant(BERRY_BUSH_EMPTY, "berry_bush_empty", "Ягодный куст", "berry_bush_empty", I.STICK, 0.95f, 0, 1, sway = false)
        plant(DEAD_BUSH, "dead_bush", "Сухой куст", "dead_bush", I.STICK, 0.7f, 1, 2, sway = false)
        plant(SAPLING, "sapling", "Саженец", "sapling", SAPLING, 0.8f)
        for (i in 0..3) {
            plant(WHEAT_0 + i, "wheat_$i", "Пшеница", "wheat_$i", if (i == 3) I.WHEAT else I.WHEAT_SEEDS, 0.35f + i * 0.2f, 1, if (i == 3) 2 else 1)
            plant(CARROT_0 + i, "carrot_$i", "Морковь", "carrot_$i", I.CARROT, 0.3f + i * 0.12f, 1, if (i == 3) 3 else 1, sway = false)
        }
    }

    fun isLog(id: Int) = id == OAK_LOG || id == PINE_LOG || id == BIRCH_LOG || id == PALM_LOG || id in OAK_LOG_X..BIRCH_LOG_Z
    fun isLeaves(id: Int) = id == OAK_LEAVES || id == PINE_LEAVES || id == BIRCH_LEAVES || id == PALM_LEAVES || id == JUNGLE_LEAVES || id == FRUIT_LEAVES
    fun isSoil(id: Int) = id == GRASS || id == DIRT || id == FOREST_FLOOR || id == GRASS_LUSH || id == GRASS_DRY || id == MUD || id == SNOWY_GRASS
}
