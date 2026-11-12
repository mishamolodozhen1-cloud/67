package wildfrontier.farming

import wildcore.math.Rng
import wildcore.world.Blocks
import wildcore.world.Chunk
import wildcore.world.VoxelWorld
import wildfrontier.GameScene
import wildfrontier.content.B
import wildfrontier.content.I
import wildfrontier.gen.Biome
import wildfrontier.gen.Trees

/** Writes tree blocks into the live world (sapling growth). */
class WorldSink(private val world: VoxelWorld) : Trees.Sink {
    override fun get(wx: Int, y: Int, wz: Int): Int = if (y !in 1 until Chunk.HEIGHT || !world.isLoaded(wx, wz)) -1 else world.getBlock(wx, y, wz)
    override fun set(wx: Int, y: Int, wz: Int, id: Int) { world.setBlock(wx, y, wz, id) }
}

/**
 * Living-world simulation driven by random block ticks around the player: crop growth and soil
 * moisture, sapling growth, berry regrowth, grass spreading and leaf decay. Runs at a low fixed rate
 * with a small per-tick budget, so its cost is independent of frame rate.
 */
class Farming(private val scene: GameScene) {
    private val rng = Rng(scene.seed xor 0xFA2317L)
    private var accum = 0f
    private val sink by lazy { WorldSink(scene.world) }
    var ticks = 0L; private set

    fun update(dt: Float) {
        accum += dt
        // fixed 4 Hz; never more than two catch-up ticks per frame
        var steps = 0
        while (accum >= 0.25f && steps < 2) { accum -= 0.25f; steps++; tick() }
        if (accum > 1f) accum = 0f
    }

    private fun tick() {
        ticks++
        val w = scene.world
        val pcx = Math.floorDiv(scene.player.pos.x.toInt(), 16); val pcz = Math.floorDiv(scene.player.pos.z.toInt(), 16)
        val radius = 3
        for (dz in -radius..radius) for (dx in -radius..radius) {
            val c = w.getChunk(pcx + dx, pcz + dz) ?: continue
            if (c.state != Chunk.STATE_READY) continue
            for (k in 0 until 5) tickColumn(c, rng.nextInt(16), rng.nextInt(16))
        }
    }

    private fun tickColumn(c: Chunk, lx: Int, lz: Int) {
        val base = ((lz shl 4) or lx) shl 7
        var y = Chunk.HEIGHT - 1
        val b = c.blocks
        while (y > 0 && b[base + y].toInt() == 0) y--
        if (y <= 0) return
        val wx = c.cx * 16 + lx; val wz = c.cz * 16 + lz
        tickBlock(wx, y, wz, b[base + y].toInt() and 255, true)
        if (y > 1) tickBlock(wx, y - 1, wz, b[base + y - 1].toInt() and 255, false)
    }

    private fun waterNear(x: Int, y: Int, z: Int): Boolean {
        val w = scene.world
        for (dz in -2..2) for (dx in -2..2) if (Blocks.liquid[w.getBlock(x + dx, y, z + dz)]) return true
        return false
    }

    private fun tickBlock(x: Int, y: Int, z: Int, id: Int, top: Boolean) {
        val w = scene.world
        val raining = scene.weather.isRaining
        when {
            id in B.WHEAT_0 until B.WHEAT_3 || id in B.CARROT_0 until B.CARROT_3 -> {
                val soil = w.getBlock(x, y - 1, z)
                var p = when (soil) { B.FARMLAND_WET -> 0.075f; B.FARMLAND -> 0.022f; else -> -1f }
                if (p < 0f) { w.setBlock(x, y, z, B.AIR); scene.drops.spawn(if (id >= B.CARROT_0) I.CARROT else I.WHEAT_SEEDS, 1, x + 0.5f, y + 0.3f, z + 0.5f); return }
                if (scene.dayNight.isNight) p *= 0.3f
                if (rng.nextFloat() < p) w.setBlock(x, y, z, id + 1)
            }
            id == B.FARMLAND -> if ((raining && top) || (raining && w.getBlock(x, y + 1, z) >= B.TALL_GRASS) || waterNear(x, y, z)) w.setBlock(x, y, z, B.FARMLAND_WET)
            id == B.FARMLAND_WET -> if (!raining && !waterNear(x, y, z) && rng.nextFloat() < 0.035f) w.setBlock(x, y, z, B.FARMLAND)
            id == B.SAPLING -> if (rng.nextFloat() < 0.03f) growSapling(x, y, z)
            id == B.BERRY_BUSH_EMPTY -> if (rng.nextFloat() < 0.012f) w.setBlock(x, y, z, B.BERRY_BUSH)
            id == B.TALL_GRASS -> if (rng.nextFloat() < 0.006f) {
                val nx = x + rng.nextInt(3) - 1; val nz = z + rng.nextInt(3) - 1
                val soil = w.getBlock(nx, y - 1, nz)
                if ((soil == B.GRASS || soil == B.GRASS_LUSH || soil == B.GRASS_DRY) && w.getBlock(nx, y, nz) == B.AIR) w.setBlock(nx, y, nz, B.TALL_GRASS)
            }
            id == B.DIRT -> if (top && rng.nextFloat() < 0.04f) {
                // grass creeps over bare soil from neighbouring turf
                for (k in 0 until 4) {
                    val n = w.getBlock(x + (if (k == 0) 1 else if (k == 1) -1 else 0), y, z + (if (k == 2) 1 else if (k == 3) -1 else 0))
                    if (n == B.GRASS || n == B.GRASS_LUSH || n == B.GRASS_DRY) { w.setBlock(x, y, z, n); break }
                }
            }
            B.isLeaves(id) -> if (rng.nextFloat() < 0.3f && !logNear(x, y, z)) {
                w.setBlock(x, y, z, B.AIR)
                val r = rng.nextFloat()
                if (id == B.FRUIT_LEAVES && r < 0.5f) scene.drops.spawn(I.APPLE, 1, x + 0.5f, y + 0.3f, z + 0.5f)
                else if (r < 0.10f) scene.drops.spawn(I.STICK, 1, x + 0.5f, y + 0.3f, z + 0.5f)
                else if (r < 0.15f && id != B.PALM_LEAVES && id != B.JUNGLE_LEAVES) scene.drops.spawn(B.SAPLING, 1, x + 0.5f, y + 0.3f, z + 0.5f)
            }
        }
    }

    private fun logNear(x: Int, y: Int, z: Int): Boolean {
        val w = scene.world
        for (dy in -3..3) for (dz in -4..4) for (dx in -4..4) if (B.isLog(w.getBlock(x + dx, y + dy, z + dz))) return true
        return false
    }

    private fun growSapling(x: Int, y: Int, z: Int) {
        val w = scene.world
        if (!B.isSoil(w.getBlock(x, y - 1, z))) return
        for (h in 1..6) if (w.getBlock(x, y + h, z) != B.AIR) return
        val col = scene.column
        scene.gen.sample(x, z, col)
        val h = rng.nextInt(1 shl 20)
        val kind = when (col.biome) {
            Biome.CONIFER, Biome.SNOW, Biome.MOUNTAIN -> if (h and 1 == 0) Trees.Kind.SPRUCE else Trees.Kind.PINE
            Biome.JUNGLE -> Trees.Kind.JUNGLE
            Biome.BEACH -> Trees.Kind.PALM
            else -> if (h % 5 == 0) Trees.Kind.APPLE else if (h % 3 == 0) Trees.Kind.BIRCH else Trees.Kind.OAK
        }
        w.setBlock(x, y, z, B.AIR)
        Trees.place(sink, x, y, z, kind, h)
        scene.particles.puff(x + 0.5f, y + 1f, z + 0.5f, 10, 0xCC6FA84A.toInt(), 0.2f, 1.2f)
    }

    // ------------------------------------------------------------------ player actions

    fun till(x: Int, y: Int, z: Int): Boolean {
        val id = scene.world.getBlock(x, y, z)
        if (!(id == B.GRASS || id == B.DIRT || id == B.GRASS_LUSH || id == B.GRASS_DRY || id == B.FOREST_FLOOR)) return false
        val above = scene.world.getBlock(x, y + 1, z)
        if (above != B.AIR && !Blocks.get(above).replaceable) return false
        if (above != B.AIR) scene.world.setBlock(x, y + 1, z, B.AIR)
        scene.world.setBlock(x, y, z, if (waterNear(x, y, z)) B.FARMLAND_WET else B.FARMLAND)
        return true
    }

    fun plant(x: Int, y: Int, z: Int, crop: Int): Boolean {
        val soil = scene.world.getBlock(x, y, z)
        if (soil != B.FARMLAND && soil != B.FARMLAND_WET) return false
        if (scene.world.getBlock(x, y + 1, z) != B.AIR) return false
        scene.world.setBlock(x, y + 1, z, crop)
        return true
    }

    /** Waters the 3x3 patch around a block. Returns the number of plots moistened. */
    fun water(x: Int, y: Int, z: Int): Int {
        var n = 0
        for (dz in -1..1) for (dx in -1..1) for (dy in -1..0) {
            if (scene.world.getBlock(x + dx, y + dy, z + dz) == B.FARMLAND) { scene.world.setBlock(x + dx, y + dy, z + dz, B.FARMLAND_WET); n++ }
        }
        return n
    }
}
