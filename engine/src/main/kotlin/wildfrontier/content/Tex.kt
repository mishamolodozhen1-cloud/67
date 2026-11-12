package wildfrontier.content

/** Block texture layers. Order defines the layer index inside the texture arrays. */
object Tex {
    val NAMES = arrayOf(
        "grass_top", "dirt", "stone", "sand", "gravel", "clay", "snow", "ice",
        "oak_bark", "oak_top", "oak_leaves", "pine_bark", "pine_top", "pine_leaves",
        "birch_bark", "birch_top", "birch_leaves", "palm_bark", "palm_top", "palm_leaves",
        "jungle_leaves", "fruit_leaves",
        "coal_ore", "copper_ore", "iron_ore", "gold_ore", "crystal_ore",
        "mossy_stone", "sandstone", "mud", "forest_floor", "grass_lush", "grass_dry", "bedrock",
        "grass_side", "snow_side", "lush_side", "dry_side",
        "planks_oak", "planks_pine", "cobblestone", "stone_bricks", "bricks", "glass", "thatch",
        "workbench_top", "workbench_side", "furnace_side", "furnace_top", "chest_side", "chest_top",
        "farmland", "farmland_wet", "metal_panel", "lab_floor", "rusty_metal", "lamp", "crate", "terminal",
        "campfire", "torch", "bedroll",
        "tall_grass", "fern", "flower_red", "flower_yellow", "flower_blue", "mushroom", "reeds",
        "berry_bush", "berry_bush_empty", "dead_bush", "sapling",
        "wheat_0", "wheat_1", "wheat_2", "wheat_3", "carrot_0", "carrot_1", "carrot_2", "carrot_3",
        "flames",
    )
    private val index = HashMap<String, Int>().also { m -> NAMES.forEachIndexed { i, n -> m[n] = i } }
    fun of(name: String): Int = index[name] ?: error("unknown texture layer: $name")
    val COUNT: Int get() = NAMES.size
}
