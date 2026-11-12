package wildfrontier.gen

import wildcore.math.Hash
import wildcore.math.Noise
import wildcore.math.Rng
import wildcore.math.lerp
import wildcore.math.smoothstep
import wildcore.world.Chunk
import wildcore.world.ChunkGenerator
import wildfrontier.content.B
import kotlin.math.abs

/** Everything the generator knows about one world column. */
class Column {
    @JvmField var height = 0f       // terrain surface (top solid block y + 1)
    @JvmField var biome = 0
    @JvmField var river = 0f        // 0..1 river influence
    @JvmField var temp = 0f
    @JvmField var moist = 0f
    @JvmField var rocky = 0f
    @JvmField var land = 0f
}

/**
 * Procedural archipelago generator. Pure function of (seed, coordinates): any chunk can be generated
 * independently on any thread, and unmodified chunks never need to be stored.
 */
class WorldGen(val seed: Long) : ChunkGenerator {
    companion object {
        const val SEA = 40
        const val TREE_CELL = 5
    }

    private val nCont = Noise(seed + 1)
    private val nIsl = Noise(seed + 2)
    private val nHill = Noise(seed + 3)
    private val nMtnMask = Noise(seed + 4)
    private val nMtn = Noise(seed + 5)
    private val nDetail = Noise(seed + 6)
    private val nTemp = Noise(seed + 7)
    private val nMoist = Noise(seed + 8)
    private val nRiver = Noise(seed + 9)
    private val nRocky = Noise(seed + 10)
    private val nLake = Noise(seed + 11)
    private val nCaveA = Noise(seed + 12)
    private val nCaveB = Noise(seed + 13)
    private val nCheese = Noise(seed + 14)
    private val nPatch = Noise(seed + 15)
    private val iseed = (seed xor (seed ushr 32)).toInt()
    val structures = Structures(this, iseed)

    private val scratch = ThreadLocal.withInitial { Scratch() }

    private class Scratch {
        val cols = Array(18 * 18) { Column() }
        val heights = IntArray(18 * 18)
        val col = Column()
    }

    // ------------------------------------------------------------------ column sampling

    /** Fills [out] with terrain height and biome for world column (x, z). */
    fun sample(x: Int, z: Int, out: Column) {
        val fx = x.toFloat(); val fz = z.toFloat()
        // continental shape: large landmasses broken into islands
        val c = nCont.fbm2(fx / 620f, fz / 620f, 3) * 0.62f + nIsl.fbm2(fx / 210f, fz / 210f, 3) * 0.46f - 0.07f
        val land = smoothstep(-0.03f, 0.10f, c)
        val inland = smoothstep(0.06f, 0.42f, c)
        val detail = nDetail.fbm2(fx / 34f, fz / 34f, 3)

        val oceanH = SEA - 3f - 25f * smoothstep(0.0f, -0.55f, c) + detail * 1.8f
        val hillMask = smoothstep(-0.15f, 0.4f, nHill.noise2(fx / 390f, fz / 390f))
        val mtnMask = smoothstep(0.12f, 0.5f, nMtnMask.noise2(fx / 540f, fz / 540f) + inland * 0.25f - 0.1f) * inland
        var landH = SEA + 1.6f + inland * 5f + nHill.fbm2(fx / 96f, fz / 96f, 3) * 4.5f * (0.3f + inland)
        landH += hillMask * inland * 13f * (nHill.fbm2(fx / 61f + 40f, fz / 61f - 12f, 4) * 0.5f + 0.5f)
        val ridge = nMtn.ridged2(fx / 250f, fz / 250f, 4)
        landH += mtnMask * 66f * ridge * ridge * (0.55f + 0.45f * ridge)
        landH += detail * (1.2f + 3.5f * mtnMask)
        var h = lerp(oceanH, landH, land)

        // temperature / moisture
        var temp = nTemp.noise2(fx / 820f, fz / 820f) * 1.15f + nTemp.noise2(fx / 190f + 9f, fz / 190f) * 0.18f
        val moist = nMoist.noise2(fx / 610f, fz / 610f) * 1.1f + nMoist.noise2(fx / 140f, fz / 140f + 5f) * 0.2f
        temp -= maxOf(0f, h - SEA) / 105f

        // rivers: carve where a warped noise crosses zero
        val rv = abs(nRiver.noise2(fx / 330f, fz / 330f) + 0.22f * nRiver.noise2(fx / 85f + 3f, fz / 85f))
        var river = (1f - smoothstep(0.012f, 0.085f, rv)) * land * (1f - smoothstep(SEA + 16f, SEA + 30f, h))
        if (river > 0f) {
            val bed = SEA - 3.2f + detail * 0.6f
            val r2 = river * river
            if (h > bed) h = lerp(h, bed, r2)
        }
        // lakes in inland lowlands
        val lake = smoothstep(0.58f, 0.72f, nLake.noise2(fx / 170f, fz / 170f)) * inland * (1f - smoothstep(SEA + 7f, SEA + 14f, h))
        if (lake > 0f) { h = lerp(h, SEA - 4.5f, lake); river = maxOf(river, lake) }

        // swamp: humid temperate lowland flattened to the waterline
        val swamp = smoothstep(0.28f, 0.5f, moist) * (1f - smoothstep(SEA + 4.5f, SEA + 8f, h)) * land *
                smoothstep(-0.5f, -0.3f, temp) * (1f - smoothstep(0.35f, 0.5f, temp)) * (1f - mtnMask)
        if (swamp > 0f) h = lerp(h, SEA + 0.35f + nDetail.noise2(fx / 9f, fz / 9f) * 1.3f, swamp * 0.9f)

        val rocky = smoothstep(0.42f, 0.62f, nRocky.noise2(fx / 260f, fz / 260f)) * inland

        out.height = h; out.river = river; out.temp = temp; out.moist = moist; out.rocky = rocky; out.land = land
        val alt = h - SEA
        out.biome = when {
            h < SEA - 0.5f -> if (river > 0.35f && land > 0.6f) Biome.RIVER else Biome.OCEAN
            groveFactor(x, z) > 0f && alt > 1f && alt < 30f -> Biome.GROVE
            alt < 2.2f && swamp <= 0.45f -> Biome.BEACH
            swamp > 0.45f -> Biome.SWAMP
            alt > 56f - temp * 12f || temp < -0.62f -> Biome.SNOW
            alt > 32f && mtnMask > 0.3f -> Biome.MOUNTAIN
            rocky > 0.5f -> Biome.ROCKY
            temp > 0.24f -> if (moist > -0.12f) Biome.JUNGLE else Biome.MEADOW
            temp < -0.17f -> Biome.CONIFER
            moist > -0.08f -> Biome.DECIDUOUS
            else -> Biome.MEADOW
        }
    }

    fun heightAt(x: Int, z: Int): Float { val c = scratch.get().col; sample(x, z, c); return c.height }

    /** Secret groves: one candidate per 448-block region, radius ~26. Returns 0..1 inside. */
    fun groveFactor(x: Int, z: Int): Float {
        val rx = Math.floorDiv(x, 448); val rz = Math.floorDiv(z, 448)
        if (Hash.f2(rx, rz, iseed + 771) > 0.55f) return 0f
        val gx = rx * 448 + 60 + (Hash.f2(rx, rz, iseed + 772) * 320f).toInt()
        val gz = rz * 448 + 60 + (Hash.f2(rx, rz, iseed + 773) * 320f).toInt()
        val dx = (x - gx).toFloat(); val dz = (z - gz).toFloat()
        val d = kotlin.math.sqrt(dx * dx + dz * dz)
        return if (d < 26f) 1f - d / 26f else 0f
    }

    // ------------------------------------------------------------------ chunk generation

    override fun generate(chunk: Chunk) {
        val s = scratch.get()
        val wx0 = chunk.cx * 16; val wz0 = chunk.cz * 16
        val b = chunk.blocks
        // sample an 18x18 patch (1-block border) for slope detection
        for (z in -1..16) for (x in -1..16) {
            val col = s.cols[(z + 1) * 18 + x + 1]
            sample(wx0 + x, wz0 + z, col)
            s.heights[(z + 1) * 18 + x + 1] = col.height.toInt().coerceIn(2, Chunk.HEIGHT - 12)
        }
        for (z in 0 until 16) for (x in 0 until 16) {
            val ci = (z + 1) * 18 + x + 1
            val col = s.cols[ci]
            val top = s.heights[ci]            // first air (or water) y
            val wx = wx0 + x; val wz = wz0 + z
            val base = ((z shl 4) or x) shl 7
            val slope = maxOf(
                maxOf(abs(s.heights[ci - 1] - top), abs(s.heights[ci + 1] - top)),
                maxOf(abs(s.heights[ci - 18] - top), abs(s.heights[ci + 18] - top)))
            val h3 = Hash.hash2(wx, wz, iseed)
            val patch = nPatch.noise2(wx / 13f, wz / 13f)
            var surface: Int; var under: Int; var depth = 3 + (h3 and 1)
            when (col.biome) {
                Biome.OCEAN -> { surface = if (top > SEA - 7) B.SAND else if (patch > 0.35f) B.GRAVEL else if (patch < -0.45f) B.CLAY else B.SAND; under = B.SAND }
                Biome.RIVER -> { surface = if (patch > 0.25f) B.GRAVEL else if (patch < -0.35f) B.CLAY else B.SAND; under = B.GRAVEL }
                Biome.BEACH -> { surface = B.SAND; under = B.SAND; depth = 4 }
                Biome.SWAMP -> { surface = if (top <= SEA || patch > 0.2f) B.MUD else B.GRASS; under = B.MUD }
                Biome.CONIFER -> { surface = if (patch > 0.3f) B.GRASS else B.FOREST_FLOOR; under = B.DIRT }
                Biome.JUNGLE -> { surface = B.GRASS_LUSH; under = B.DIRT }
                Biome.MEADOW -> { surface = if (col.temp > 0.24f) B.GRASS_DRY else B.GRASS; under = B.DIRT }
                Biome.SNOW -> { surface = if (top - SEA > 62) B.SNOW else B.SNOWY_GRASS; under = if (top - SEA > 62) B.SNOW else B.DIRT }
                Biome.MOUNTAIN -> { if (patch > 0.15f && slope <= 2) { surface = B.GRASS; under = B.DIRT; depth = 2 } else { surface = if (patch < -0.4f) B.GRAVEL else B.STONE; under = B.STONE } }
                Biome.ROCKY -> { if (patch > 0.3f) { surface = B.GRASS_DRY; under = B.DIRT; depth = 2 } else { surface = if (patch < -0.3f) B.GRAVEL else if ((h3 and 6) == 0) B.MOSSY_STONE else B.STONE; under = B.STONE } }
                Biome.GROVE -> { surface = B.GRASS_LUSH; under = B.DIRT }
                else -> { surface = B.GRASS; under = B.DIRT }
            }
            // cliffs expose bare rock
            if (slope >= 3 && top > SEA + 2 && col.biome != Biome.BEACH) {
                surface = if (col.biome == Biome.SNOW && slope < 5) B.SNOW else if ((h3 and 12) == 0 && col.biome != Biome.SNOW) B.MOSSY_STONE else B.STONE
                under = B.STONE
            }
            if (top <= SEA && surface != B.SAND && surface != B.GRAVEL && surface != B.CLAY && surface != B.MUD) { surface = B.SAND; under = B.SAND }

            b[base] = B.BEDROCK.toByte()
            for (y in 1 until top) {
                b[base + y] = (if (y >= top - 1) surface else if (y >= top - 1 - depth) (if (under == B.SAND && y < top - 3) B.SANDSTONE else under) else B.STONE).toByte()
            }
            // sea / lake / river water, frozen in snowy climate
            if (top <= SEA) {
                for (y in top until SEA) b[base + y] = B.WATER.toByte()
                if (col.temp < -0.62f && top >= SEA - 6) b[base + SEA - 1] = B.ICE.toByte()
            }
            carveCaves(b, base, wx, wz, top, col)
        }
        generateOres(chunk)
        structures.apply(chunk, s.cols)
        decorate(chunk, s)
    }

    private fun carveCaves(b: ByteArray, base: Int, wx: Int, wz: Int, top: Int, col: Column) {
        // keep a solid lid under water bodies so caves never drain the sea
        val roof = if (top <= SEA + 1) top - 7 else top
        val fx = wx.toFloat(); val fz = wz.toFloat()
        var y = 2
        while (y < roof) {
            val fy = y.toFloat()
            val a = nCaveA.noise3(fx / 46f, fy / 38f, fz / 46f)
            var carve = false
            if (abs(a) < 0.13f) {
                val c2 = nCaveB.noise3(fx / 46f + 31f, fy / 38f, fz / 46f - 17f)
                val width = 0.011f + 0.006f * (1f - y / 128f)
                if (a * a + c2 * c2 < width) carve = true
            }
            if (!carve && y < top - 6) {
                val ch = nCheese.noise3(fx / 58f, fy / 30f, fz / 58f)
                if (ch > 0.66f - 0.1f * (1f - y / 60f).coerceAtLeast(0f)) carve = true
            }
            if (carve) {
                val id = b[base + y].toInt() and 255
                if (id == B.STONE || id == B.DIRT || id == B.GRASS || id == B.FOREST_FLOOR || id == B.GRASS_LUSH ||
                    id == B.GRASS_DRY || id == B.SANDSTONE || id == B.MOSSY_STONE || id == B.GRAVEL || id == B.SNOWY_GRASS || id == B.SNOW) {
                    b[base + y] = (if (y <= 9) B.WATER else B.AIR).toByte()
                }
            }
            y++
        }
    }

    private fun generateOres(chunk: Chunk) {
        val rng = Rng(seed xor (chunk.cx * 341873128712L) xor (chunk.cz * 132897987541L))
        fun veins(ore: Int, count: Int, size: Int, yMin: Int, yMax: Int) {
            for (i in 0 until count) {
                var x = rng.nextInt(16); var z = rng.nextInt(16); var y = yMin + rng.nextInt(yMax - yMin)
                for (k in 0 until size) {
                    if (x in 0..15 && z in 0..15 && y in 1..120) {
                        val idx = Chunk.index(x, y, z)
                        if (chunk.blocks[idx].toInt() == B.STONE) chunk.blocks[idx] = ore.toByte()
                    }
                    when (rng.nextInt(6)) { 0 -> x++; 1 -> x--; 2 -> y++; 3 -> y--; 4 -> z++; else -> z-- }
                }
            }
        }
        veins(B.COAL_ORE, 9, 9, 6, 78)
        veins(B.COPPER_ORE, 7, 7, 6, 58)
        veins(B.IRON_ORE, 6, 6, 4, 44)
        veins(B.GOLD_ORE, 2, 5, 3, 24)
        veins(B.CRYSTAL_ORE, 1, 4, 2, 15)
        veins(B.GRAVEL, 2, 14, 4, 50)
        veins(B.CLAY, 1, 10, 20, 44)
    }

    // ------------------------------------------------------------------ vegetation

    private fun decorate(chunk: Chunk, s: Scratch) {
        val wx0 = chunk.cx * 16; val wz0 = chunk.cz * 16
        // trees: one jittered candidate per TREE_CELL x TREE_CELL cell; canopies may cross chunk borders
        val margin = 7
        val c0x = Math.floorDiv(wx0 - margin, TREE_CELL); val c1x = Math.floorDiv(wx0 + 15 + margin, TREE_CELL)
        val c0z = Math.floorDiv(wz0 - margin, TREE_CELL); val c1z = Math.floorDiv(wz0 + 15 + margin, TREE_CELL)
        val col = s.col
        val sink = Trees.ChunkSink(chunk)
        for (cz in c0z..c1z) for (cx in c0x..c1x) {
            val h = Hash.hash2(cx, cz, iseed + 99)
            val tx = cx * TREE_CELL + (h and 3)
            val tz = cz * TREE_CELL + ((h shr 2) and 3)
            val lx = tx - wx0; val lz = tz - wz0
            // reuse the pre-sampled column when the trunk is inside the 18x18 patch
            val c = if (lx in -1..16 && lz in -1..16) s.cols[(lz + 1) * 18 + lx + 1] else { sample(tx, tz, col); col }
            val ground = c.height.toInt().coerceIn(2, Chunk.HEIGHT - 12)
            if (ground <= SEA) continue
            if (structures.blocksVegetation(tx, tz)) continue
            val r = ((h ushr 8) and 0xFFFF) / 65536f
            val kind = treeKind(c, r, h, ground) ?: continue
            Trees.place(sink, tx, ground, tz, kind, h ushr 4)
        }
        // ground cover
        for (z in 0 until 16) for (x in 0 until 16) {
            val c = s.cols[(z + 1) * 18 + x + 1]
            val top = s.heights[(z + 1) * 18 + x + 1]
            if (top <= SEA || top >= Chunk.HEIGHT - 2) continue
            val idx = Chunk.index(x, top, z)
            if (chunk.blocks[idx].toInt() != B.AIR) continue
            val ground = chunk.blocks[idx - 1].toInt() and 255
            val wx = wx0 + x; val wz = wz0 + z
            if (structures.blocksVegetation(wx, wz)) continue
            val r = Hash.f2(wx, wz, iseed + 5)
            val r2 = Hash.f2(wx, wz, iseed + 6)
            val plant = groundPlant(c, ground, top, r, r2, wx, wz)
            if (plant != 0) chunk.blocks[idx] = plant.toByte()
        }
    }

    private fun treeKind(c: Column, r: Float, h: Int, ground: Int): Trees.Kind? {
        val alt = ground - SEA
        return when (c.biome) {
            Biome.DECIDUOUS -> if (r < 0.62f) (if ((h and 0x700) == 0) Trees.Kind.BIRCH else if ((h and 0x7000) == 0x1000) Trees.Kind.APPLE else if ((h and 0x300) == 0x100) Trees.Kind.BIRCH else Trees.Kind.OAK) else null
            Biome.CONIFER -> if (r < 0.72f) (if ((h and 0x100) == 0) Trees.Kind.SPRUCE else Trees.Kind.PINE) else null
            Biome.JUNGLE -> if (r < 0.8f) (if ((h and 0x300) == 0) Trees.Kind.JUNGLE_BIG else if ((h and 0x300) == 0x100) Trees.Kind.PALM else Trees.Kind.JUNGLE) else null
            Biome.MEADOW -> if (r < 0.035f) (if (c.temp > 0.24f) Trees.Kind.PALM else if ((h and 0x300) == 0) Trees.Kind.APPLE else Trees.Kind.OAK) else null
            Biome.SWAMP -> if (r < 0.22f && alt >= 1) Trees.Kind.SWAMP else null
            Biome.BEACH -> if (r < 0.07f && c.temp > 0.05f && alt >= 1) Trees.Kind.PALM else null
            Biome.MOUNTAIN -> if (r < 0.10f && alt < 52) Trees.Kind.PINE else null
            Biome.SNOW -> if (r < 0.2f && alt < 60) Trees.Kind.SPRUCE else null
            Biome.ROCKY -> if (r < 0.03f) Trees.Kind.PINE else null
            Biome.GROVE -> if (r < 0.5f) (if ((h and 0x300) == 0) Trees.Kind.ANCIENT else Trees.Kind.BIRCH) else null
            else -> null
        }
    }

    private fun groundPlant(c: Column, ground: Int, top: Int, r: Float, r2: Float, wx: Int, wz: Int): Int {
        val soil = B.isSoil(ground)
        when (c.biome) {
            Biome.MEADOW -> if (soil) return when {
                r < 0.34f -> B.TALL_GRASS
                r < 0.37f -> B.FLOWER_YELLOW
                r < 0.395f -> B.FLOWER_RED
                r < 0.42f -> B.FLOWER_BLUE
                r < 0.428f -> B.BERRY_BUSH
                r < 0.432f && c.temp > 0.24f -> B.DEAD_BUSH
                else -> 0
            }
            Biome.DECIDUOUS -> if (soil) return when {
                r < 0.2f -> B.TALL_GRASS
                r < 0.26f -> B.FERN
                r < 0.275f -> B.FLOWER_BLUE
                r < 0.288f -> B.MUSHROOM
                r < 0.30f -> B.BERRY_BUSH
                else -> 0
            }
            Biome.CONIFER -> if (soil) return when {
                r < 0.10f -> B.FERN
                r < 0.15f -> B.TALL_GRASS
                r < 0.172f -> B.MUSHROOM
                r < 0.185f -> B.BERRY_BUSH
                else -> 0
            }
            Biome.JUNGLE -> if (soil) return when {
                r < 0.34f -> B.FERN
                r < 0.52f -> B.TALL_GRASS
                r < 0.54f -> B.FLOWER_RED
                r < 0.552f -> B.BERRY_BUSH
                else -> 0
            }
            Biome.SWAMP -> return when {
                (ground == B.MUD || soil) && top <= SEA + 1 && r < 0.3f -> B.REEDS
                soil && r < 0.2f -> B.TALL_GRASS
                soil && r < 0.24f -> B.FERN
                r < 0.26f && (soil || ground == B.MUD) -> B.MUSHROOM
                r < 0.275f && (soil || ground == B.MUD) -> B.DEAD_BUSH
                else -> 0
            }
            Biome.BEACH -> return when {
                ground == B.SAND && top <= SEA + 1 && c.river > 0.2f && r < 0.25f -> B.REEDS
                ground == B.SAND && r < 0.012f -> B.DEAD_BUSH
                else -> 0
            }
            Biome.MOUNTAIN, Biome.ROCKY -> return when {
                soil && r < 0.18f -> B.TALL_GRASS
                soil && r < 0.2f -> B.FLOWER_YELLOW
                r < 0.012f && (ground == B.STONE || ground == B.GRAVEL || soil) -> B.DEAD_BUSH
                else -> 0
            }
            Biome.SNOW -> return if (ground == B.SNOWY_GRASS && r < 0.02f) B.DEAD_BUSH else 0
            Biome.GROVE -> if (soil) return when {
                r < 0.25f -> B.FLOWER_BLUE
                r < 0.4f -> B.FLOWER_YELLOW
                r < 0.55f -> B.FERN
                r < 0.62f -> B.BERRY_BUSH
                r < 0.66f -> B.MUSHROOM
                else -> B.TALL_GRASS
            }
        }
        return 0
    }

    // ------------------------------------------------------------------ spawn

    /** Deterministic spawn: nearest beach to the origin along a spiral search. Returns (x, y, z). */
    fun findSpawn(): IntArray {
        val c = Column()
        var best: IntArray? = null
        var r = 0
        while (r < 4000 && best == null) {
            val steps = maxOf(8, r / 6)
            for (i in 0 until steps) {
                val a = i * 6.2831853f / steps
                val x = (kotlin.math.cos(a) * r).toInt(); val z = (kotlin.math.sin(a) * r).toInt()
                sample(x, z, c)
                if (c.biome == Biome.BEACH && c.height >= SEA + 1.2f && c.temp > -0.3f) {
                    // require real land behind the beach (not a sandbar)
                    var landCount = 0
                    for (k in 0 until 8) {
                        val a2 = k * 0.7853982f
                        sample(x + (kotlin.math.cos(a2) * 40f).toInt(), z + (kotlin.math.sin(a2) * 40f).toInt(), c)
                        if (c.height > SEA + 2) landCount++
                    }
                    if (landCount >= 3) { best = intArrayOf(x, heightAt(x, z).toInt() + 1, z); break }
                }
            }
            r += 12
        }
        return best ?: intArrayOf(0, maxOf(SEA + 2, heightAt(0, 0).toInt() + 1), 0)
    }
}
