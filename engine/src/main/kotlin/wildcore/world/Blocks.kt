package wildcore.world

/** Geometry class of a block; decides which mesh bucket and algorithm it uses. */
object Shape {
    const val AIR = 0
    const val CUBE = 1        // opaque full cube, greedy-meshed
    const val CUTOUT = 2      // alpha-tested full cube (leaves, glass)
    const val LIQUID = 3      // water
    const val CROSS = 4       // two crossed sprite quads (grass, flowers, crops)
    const val BOX = 5         // axis-aligned sub-block box (torch, slab, bedroll)
}

object ToolKind {
    const val NONE = 0
    const val AXE = 1
    const val PICKAXE = 2
    const val SHOVEL = 3
    const val SICKLE = 4
}

object SoundMat {
    const val GRASS = 0; const val STONE = 1; const val WOOD = 2; const val SAND = 3
    const val LEAVES = 4; const val WATER = 5; const val SNOW = 6; const val METAL = 7
}

/** Vertex flag bits consumed by the chunk shader. */
object VFlag {
    const val UV_SCALE_MASK = 0x03   // 0: 1 block per tile, 1: 2 blocks, 2: 4 blocks
    const val UV_SWAP = 0x04         // swap u/v (sideways logs keep their grain direction)
    const val SWAY = 0x08            // wind sway (top vertices of sprites)
    const val SPRITE_UV = 0x10       // UV from corner index instead of world position
    const val FLUTTER = 0x20         // subtle leaf flutter
    const val WATER = 0x40
    const val EMISSIVE = 0x80
}

class BlockDef(
    val id: Int,
    val key: String,
    val displayName: String,
    val shape: Int,
    val texTop: Int,
    val texSide: Int,
    val texBottom: Int,
    val solid: Boolean = true,
    val lightOpacity: Int = 15,
    val emission: Int = 0,
    val hardness: Float = 1f,          // seconds to break with bare hands; < 0 = unbreakable
    val tool: Int = ToolKind.NONE,     // preferred tool (speeds up breaking)
    val requiredTier: Int = 0,         // minimum tool tier to get drops (0 = hand)
    val dropItem: Int = -1,            // item id dropped; -1 = nothing; resolved by game content
    val dropMin: Int = 1,
    val dropMax: Int = 1,
    val flags: Int = 0,
    val sound: Int = SoundMat.STONE,
    val replaceable: Boolean = false,  // can be overwritten when placing (plants, water)
    val boxMin: Float = 0f, val boxMaxY: Float = 1f, // BOX/CROSS shape: inset from sides / height
    val climbable: Boolean = false,
    val needsSupport: Boolean = false, // breaks when the block below is removed
    val axis: Int = 1,                 // axis of the top/bottom texture: 0=x 1=y 2=z (rotated logs)
)

/** Global block registry with flat lookup tables for the hot meshing/physics loops. */
object Blocks {
    val defs = arrayOfNulls<BlockDef>(256)
    val shape = IntArray(256)
    val opaque = BooleanArray(256)       // full cube that completely hides neighbours' faces
    val solid = BooleanArray(256)
    val lightOpacity = IntArray(256)
    val emission = IntArray(256)
    val liquid = BooleanArray(256)

    fun register(d: BlockDef) {
        require(defs[d.id] == null) { "duplicate block id ${d.id}" }
        defs[d.id] = d
        shape[d.id] = d.shape
        opaque[d.id] = d.shape == Shape.CUBE
        solid[d.id] = d.solid
        lightOpacity[d.id] = if (d.shape == Shape.CUBE) 15 else d.lightOpacity
        emission[d.id] = d.emission
        liquid[d.id] = d.shape == Shape.LIQUID
    }

    fun get(id: Int): BlockDef = defs[id and 255] ?: defs[0]!!
    fun clear() {
        java.util.Arrays.fill(defs, null)
        java.util.Arrays.fill(shape, 0); java.util.Arrays.fill(opaque, false); java.util.Arrays.fill(solid, false)
        java.util.Arrays.fill(lightOpacity, 0); java.util.Arrays.fill(emission, 0); java.util.Arrays.fill(liquid, false)
    }
}
