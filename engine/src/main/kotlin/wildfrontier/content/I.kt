package wildfrontier.content

/**
 * Item ids. Ids below 256 are block items (same id as the block); 256+ are pure items.
 * Persisted in saves — never renumber.
 */
object I {
    // materials
    const val STICK = 256; const val PLANT_FIBER = 257; const val FLINT = 258; const val CLAY_BALL = 259
    const val COAL = 260; const val RAW_COPPER = 261; const val RAW_IRON = 262; const val RAW_GOLD = 263
    const val CRYSTAL = 264; const val COPPER_INGOT = 265; const val IRON_INGOT = 266; const val GOLD_INGOT = 267
    const val ROPE = 268; const val LEATHER = 269; const val BONE = 270; const val FEATHER = 271
    const val BRICK = 272; const val CLOTH = 273; const val CHARCOAL = 274
    // food
    const val BERRIES = 280; const val APPLE = 281; const val MUSHROOM = 282; const val RAW_MEAT = 283
    const val COOKED_MEAT = 284; const val CARROT = 285; const val WHEAT = 286; const val BREAD = 287
    const val RAW_FISH = 288; const val COOKED_FISH = 289; const val COCONUT = 290; const val STEW = 291
    // farming
    const val WHEAT_SEEDS = 295
    // tools & weapons
    const val STONE_AXE = 300; const val STONE_PICKAXE = 301; const val STONE_SHOVEL = 302; const val STONE_KNIFE = 303
    const val COPPER_AXE = 304; const val COPPER_PICKAXE = 305; const val COPPER_SHOVEL = 306
    const val IRON_AXE = 307; const val IRON_PICKAXE = 308; const val IRON_SHOVEL = 309; const val IRON_KNIFE = 310
    const val HOE = 311; const val SICKLE = 312; const val SPEAR = 313; const val BOW = 314; const val ARROW = 315
    const val FISHING_ROD = 316; const val WATERSKIN = 317; const val WATERSKIN_FULL = 318; const val BUCKET = 319
    const val BUCKET_WATER = 320; const val FLINT_STRIKER = 321
    // clothing / equipment
    const val FIBER_SHIRT = 330; const val LEATHER_JACKET = 331; const val FUR_COAT = 332; const val LEATHER_BOOTS = 333
    const val BACKPACK = 334
    // transport
    const val RAFT = 340
    // story
    const val NOTE = 350; const val KEYCARD = 351; const val MAP_FRAGMENT = 352; const val RADIO_PART = 353
}
