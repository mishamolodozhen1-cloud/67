package wildfrontier.content

object Station {
    const val HAND = 0; const val WORKBENCH = 1; const val FURNACE = 2; const val CAMPFIRE = 3
    val NAMES = arrayOf("Руками", "Верстак", "Печь", "Костёр")
}

class Recipe(val result: Int, val count: Int, val station: Int, val category: Int, vararg ing: Int) {
    /** Pairs of (item id, amount). */
    val ingredients: IntArray = ing
    fun canCraft(inv: Inventory): Boolean {
        var i = 0
        while (i < ingredients.size) { if (inv.count(ingredients[i]) < ingredients[i + 1]) return false; i += 2 }
        return true
    }
}

/** Every crafting recipe, grouped by item category for the crafting screen tabs. */
object Recipes {
    val all = ArrayList<Recipe>()
    private var registered = false

    private fun r(result: Int, count: Int, station: Int, cat: Int, vararg ing: Int) { all.add(Recipe(result, count, station, cat, *ing)) }

    @Synchronized fun registerAll() {
        if (registered) return
        registered = true
        val H = Station.HAND; val W = Station.WORKBENCH; val F = Station.FURNACE; val C = Station.CAMPFIRE
        // --- by hand: the first hour of survival
        r(B.PLANKS_OAK, 4, H, Cat.BLOCKS, B.OAK_LOG, 1)
        r(B.PLANKS_PINE, 4, H, Cat.BLOCKS, B.PINE_LOG, 1)
        r(B.PLANKS_OAK, 4, H, Cat.BLOCKS, B.BIRCH_LOG, 1)
        r(B.PLANKS_PINE, 4, H, Cat.BLOCKS, B.PALM_LOG, 1)
        r(I.STICK, 4, H, Cat.MATERIALS, B.PLANKS_OAK, 1)
        r(I.STICK, 4, H, Cat.MATERIALS, B.PLANKS_PINE, 1)
        r(I.ROPE, 1, H, Cat.MATERIALS, I.PLANT_FIBER, 3)
        r(I.STONE_KNIFE, 1, H, Cat.TOOLS, I.FLINT, 1, I.STICK, 1)
        r(I.STONE_AXE, 1, H, Cat.TOOLS, B.COBBLE, 2, I.STICK, 2, I.PLANT_FIBER, 2)
        r(I.STONE_PICKAXE, 1, H, Cat.TOOLS, B.COBBLE, 3, I.STICK, 2, I.PLANT_FIBER, 2)
        r(I.STONE_SHOVEL, 1, H, Cat.TOOLS, B.COBBLE, 1, I.STICK, 2, I.PLANT_FIBER, 1)
        r(B.WORKBENCH, 1, H, Cat.BLOCKS, B.PLANKS_OAK, 4)
        r(B.WORKBENCH, 1, H, Cat.BLOCKS, B.PLANKS_PINE, 4)
        r(B.CAMPFIRE, 1, H, Cat.BLOCKS, I.STICK, 4, B.COBBLE, 3)
        r(B.TORCH, 4, H, Cat.BLOCKS, I.STICK, 1, I.COAL, 1)
        r(B.TORCH, 2, H, Cat.BLOCKS, I.STICK, 1, I.CHARCOAL, 1)
        r(B.BEDROLL, 1, H, Cat.BLOCKS, I.PLANT_FIBER, 8)
        r(I.FIBER_SHIRT, 1, H, Cat.CLOTHING, I.PLANT_FIBER, 10)
        // --- workbench
        r(B.CHEST, 1, W, Cat.BLOCKS, B.PLANKS_OAK, 8)
        r(B.CHEST, 1, W, Cat.BLOCKS, B.PLANKS_PINE, 8)
        r(B.FURNACE, 1, W, Cat.BLOCKS, B.COBBLE, 8)
        r(B.STONE_BRICKS, 4, W, Cat.BLOCKS, B.COBBLE, 4)
        r(B.BRICKS, 2, W, Cat.BLOCKS, I.BRICK, 4)
        r(B.THATCH, 2, W, Cat.BLOCKS, I.PLANT_FIBER, 4)
        r(I.CLOTH, 1, W, Cat.MATERIALS, I.PLANT_FIBER, 4)
        r(I.HOE, 1, W, Cat.FARMING, B.COBBLE, 2, I.STICK, 2)
        r(I.SICKLE, 1, W, Cat.FARMING, I.COPPER_INGOT, 2, I.STICK, 1)
        r(I.BUCKET, 1, W, Cat.FARMING, I.COPPER_INGOT, 3)
        r(I.SPEAR, 1, W, Cat.TOOLS, I.STICK, 3, I.FLINT, 1, I.ROPE, 1)
        r(I.BOW, 1, W, Cat.TOOLS, I.STICK, 3, I.ROPE, 2)
        r(I.ARROW, 4, W, Cat.TOOLS, I.STICK, 1, I.FLINT, 1, I.FEATHER, 1)
        r(I.FISHING_ROD, 1, W, Cat.TOOLS, I.STICK, 3, I.ROPE, 2)
        r(I.WATERSKIN, 1, W, Cat.TOOLS, I.LEATHER, 2, I.ROPE, 1)
        r(I.COPPER_AXE, 1, W, Cat.TOOLS, I.COPPER_INGOT, 3, I.STICK, 2)
        r(I.COPPER_PICKAXE, 1, W, Cat.TOOLS, I.COPPER_INGOT, 3, I.STICK, 2)
        r(I.COPPER_SHOVEL, 1, W, Cat.TOOLS, I.COPPER_INGOT, 1, I.STICK, 2)
        r(I.IRON_AXE, 1, W, Cat.TOOLS, I.IRON_INGOT, 3, I.STICK, 2)
        r(I.IRON_PICKAXE, 1, W, Cat.TOOLS, I.IRON_INGOT, 3, I.STICK, 2)
        r(I.IRON_SHOVEL, 1, W, Cat.TOOLS, I.IRON_INGOT, 1, I.STICK, 2)
        r(I.IRON_KNIFE, 1, W, Cat.TOOLS, I.IRON_INGOT, 1, I.STICK, 1)
        r(I.LEATHER_JACKET, 1, W, Cat.CLOTHING, I.LEATHER, 5, I.ROPE, 2)
        r(I.FUR_COAT, 1, W, Cat.CLOTHING, I.LEATHER, 8, I.CLOTH, 2)
        r(I.LEATHER_BOOTS, 1, W, Cat.CLOTHING, I.LEATHER, 3, I.ROPE, 1)
        r(I.BACKPACK, 1, W, Cat.CLOTHING, I.LEATHER, 4, I.CLOTH, 2, I.ROPE, 2)
        r(I.RAFT, 1, W, Cat.TRANSPORT, B.OAK_LOG, 6, I.ROPE, 4)
        r(I.RAFT, 1, W, Cat.TRANSPORT, B.PINE_LOG, 6, I.ROPE, 4)
        r(I.RAFT, 1, W, Cat.TRANSPORT, B.PALM_LOG, 6, I.ROPE, 4)
        r(B.METAL_PANEL, 2, W, Cat.BLOCKS, I.IRON_INGOT, 1)
        r(B.LAMP, 1, W, Cat.BLOCKS, B.GLASS, 1, I.CRYSTAL, 1, I.COPPER_INGOT, 1)
        // --- furnace
        r(I.COPPER_INGOT, 1, F, Cat.MATERIALS, I.RAW_COPPER, 1)
        r(I.IRON_INGOT, 1, F, Cat.MATERIALS, I.RAW_IRON, 1)
        r(I.GOLD_INGOT, 1, F, Cat.MATERIALS, I.RAW_GOLD, 1)
        r(I.BRICK, 1, F, Cat.MATERIALS, I.CLAY_BALL, 1)
        r(I.CHARCOAL, 2, F, Cat.MATERIALS, B.OAK_LOG, 1)
        r(I.CHARCOAL, 2, F, Cat.MATERIALS, B.PINE_LOG, 1)
        r(B.GLASS, 1, F, Cat.BLOCKS, B.SAND, 1)
        r(B.STONE, 1, F, Cat.BLOCKS, B.COBBLE, 1)
        r(I.BREAD, 1, F, Cat.FOOD, I.WHEAT, 3)
        // --- campfire cooking
        r(I.COOKED_MEAT, 1, C, Cat.FOOD, I.RAW_MEAT, 1)
        r(I.COOKED_FISH, 1, C, Cat.FOOD, I.RAW_FISH, 1)
        r(I.STEW, 1, C, Cat.FOOD, I.RAW_MEAT, 1, I.CARROT, 1, I.MUSHROOM, 1)
        r(I.CHARCOAL, 1, C, Cat.MATERIALS, I.STICK, 4)
    }
}
