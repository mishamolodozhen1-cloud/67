package wildcore.world

/**
 * A 16 x 128 x 16 column of voxels. Blocks are stored column-major — index = ((z*16 + x) * 128) + y —
 * so vertical scans (terrain fill, skylight, heightmaps) are cache friendly.
 */
class Chunk(@JvmField val cx: Int, @JvmField val cz: Int) {
    companion object {
        const val SIZE = 16
        const val HEIGHT = 128
        const val VOLUME = SIZE * SIZE * HEIGHT

        const val STATE_LOADING = 0
        const val STATE_READY = 1

        fun index(x: Int, y: Int, z: Int): Int = (((z shl 4) or x) shl 7) or y
        fun key(cx: Int, cz: Int): Long = (cx.toLong() shl 32) or (cz.toLong() and 0xFFFFFFFFL)
    }

    @JvmField val blocks = ByteArray(VOLUME)
    @Volatile @JvmField var state = STATE_LOADING

    /** True once the chunk differs from pure seed generation and therefore must be saved. */
    @JvmField var modified = false
    /** Bumped on every block edit; lets stale mesh results be detected. */
    @JvmField var revision = 0
    @JvmField var meshedRevision = -1
    @JvmField var meshQueued = false
    @JvmField var needsMesh = false
    @JvmField var urgentMesh = false
    /** Modified since the last successful save. */
    @JvmField var unsaved = false
    @JvmField var mesh: ChunkMesh? = null
    /** Packed local positions (index) of light-emitting blocks; maintained on load and edit. */
    @JvmField var emitters = IntArray(0)
    @JvmField var emitterCount = 0
    /** Game-specific per-block data (chest contents etc.), keyed by block index. */
    @JvmField var blockData: HashMap<Int, Any>? = null
    @JvmField var lastUsedFrame = 0L

    fun get(x: Int, y: Int, z: Int): Int = blocks[index(x, y, z)].toInt() and 255
    fun set(x: Int, y: Int, z: Int, id: Int) { blocks[index(x, y, z)] = id.toByte() }

    fun rebuildEmitters() {
        var n = 0
        val b = blocks
        for (i in 0 until VOLUME) if (Blocks.emission[b[i].toInt() and 255] > 0) n++
        if (emitters.size < n) emitters = IntArray(n + 8)
        var k = 0
        if (n > 0) for (i in 0 until VOLUME) if (Blocks.emission[b[i].toInt() and 255] > 0) emitters[k++] = i
        emitterCount = n
    }

    /** Highest y with a solid (collidable) block in the column, or -1. */
    fun topSolidY(x: Int, z: Int): Int {
        val base = ((z shl 4) or x) shl 7
        for (y in HEIGHT - 1 downTo 0) if (Blocks.solid[blocks[base + y].toInt() and 255]) return y
        return -1
    }
}

/** Produces the pristine (seed-derived) contents of a chunk. Must be thread-safe. */
interface ChunkGenerator {
    fun generate(chunk: Chunk)
}

/** Persists player-modified chunks. Implementations must be thread-safe. */
interface ChunkStorage {
    /** Returns true and fills [chunk] if saved data exists. */
    fun load(chunk: Chunk): Boolean
    fun save(cx: Int, cz: Int, blocks: ByteArray, blockData: HashMap<Int, Any>?)
}
