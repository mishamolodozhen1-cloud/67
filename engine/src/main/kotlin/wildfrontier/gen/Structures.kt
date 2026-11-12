package wildfrontier.gen

import wildcore.math.Hash
import wildcore.world.Chunk
import wildfrontier.content.B
import java.util.concurrent.ConcurrentHashMap

/** A generated point of interest (abandoned camp, cabin, research station, …). */
class Site(val id: Int, val type: Int, val x: Int, val y: Int, val z: Int, val radius: Int, val variant: Int) {
    companion object {
        const val WRECK = 0     // the player's shipwreck on the starting beach
        const val CAMP = 1      // abandoned expedition camp
        const val CABIN = 2     // ruined settler cabin
        const val TOWER = 3     // stone watchtower
        const val STATION = 4   // research station
        const val BUNKER = 5    // underground laboratory
        val NAMES = arrayOf("Место крушения", "Брошенный лагерь", "Старая хижина", "Сторожевая башня", "Исследовательская станция", "Лаборатория «Эфир»")
    }
    fun contains(wx: Int, wz: Int, margin: Int = 0): Boolean =
        wx >= x - radius - margin && wx <= x + radius + margin && wz >= z - radius - margin && wz <= z + radius + margin
}

/**
 * Deterministic placement and construction of story locations. One candidate site per REGION x REGION
 * block cell, kept well inside its cell so a chunk only ever needs to consult its own region.
 */
class Structures(private val gen: WorldGen, private val seed: Int) {
    companion object {
        const val REGION = 176
        private const val EDGE = 26
        private val NONE = Site(-1, -1, 0, 0, 0, 0, 0)
    }

    private val cache = ConcurrentHashMap<Long, Site>()
    private val spawnSite: Site by lazy {
        val s = gen.findSpawn()
        Site(0, Site.WRECK, s[0] + 5, s[1] - 1, s[2] + 3, 6, 0)
    }
    val spawn: IntArray by lazy { gen.findSpawn() }

    fun wreck(): Site = spawnSite

    /** The site of region (rx, rz) or null. */
    fun regionSite(rx: Int, rz: Int): Site? {
        val key = Chunk.key(rx, rz)
        var s = cache[key]
        if (s == null) {
            s = compute(rx, rz)
            cache[key] = s
        }
        return if (s === NONE) null else s
    }

    private fun compute(rx: Int, rz: Int): Site {
        val h = Hash.hash2(rx, rz, seed + 4242)
        if ((h and 0xFF) > 150) return NONE
        val span = REGION - 2 * EDGE
        val x = rx * REGION + EDGE + ((h ushr 8) and 0xFFFF) % span
        val z = rz * REGION + EDGE + ((h ushr 12) and 0xFFFF) % span
        val w = spawnSite
        if (kotlin.math.abs(x - w.x) < 60 && kotlin.math.abs(z - w.z) < 60) return NONE
        val c = Column()
        gen.sample(x, z, c)
        val alt = c.height - WorldGen.SEA
        if (alt < 2.5f || alt > 46f || c.biome == Biome.OCEAN || c.biome == Biome.RIVER || c.biome == Biome.SWAMP) return NONE
        // reject sites on strongly uneven ground
        var minH = c.height; var maxH = c.height
        for (k in 0 until 8) {
            val a = k * 0.7853982f
            val hh = gen.heightAt(x + (kotlin.math.cos(a) * 7f).toInt(), z + (kotlin.math.sin(a) * 7f).toInt())
            if (hh < minH) minH = hh; if (hh > maxH) maxH = hh
        }
        if (maxH - minH > 7f || minH < WorldGen.SEA + 1) return NONE
        val pick = (h ushr 20) and 15
        val type = when (c.biome) {
            Biome.BEACH -> Site.CAMP
            Biome.MOUNTAIN, Biome.ROCKY, Biome.SNOW -> if (pick < 7) Site.BUNKER else if (pick < 12) Site.TOWER else Site.STATION
            Biome.MEADOW -> if (pick < 5) Site.CAMP else if (pick < 9) Site.CABIN else if (pick < 12) Site.TOWER else Site.STATION
            Biome.GROVE -> Site.STATION
            else -> if (pick < 6) Site.CABIN else if (pick < 9) Site.CAMP else if (pick < 12) Site.STATION else Site.BUNKER
        }
        val radius = when (type) { Site.CAMP -> 5; Site.CABIN -> 6; Site.TOWER -> 4; Site.STATION -> 8; else -> 21 }
        val id = 1 + (Hash.hash2(rx, rz, seed + 99) and 0x7FFFFFF)
        return Site(id, type, x, c.height.toInt(), z, radius, (h ushr 24) and 0xFF)
    }

    /** Site whose footprint contains the given world position (used by loot and story lookups). */
    fun siteAt(wx: Int, wz: Int, margin: Int = 2): Site? {
        if (spawnSite.contains(wx, wz, margin)) return spawnSite
        val s = regionSite(Math.floorDiv(wx, REGION), Math.floorDiv(wz, REGION)) ?: return null
        return if (s.contains(wx, wz, margin)) s else null
    }

    fun blocksVegetation(wx: Int, wz: Int): Boolean = siteAt(wx, wz, 1) != null

    /** All sites whose region centre lies within [range] regions of the position (for the map). */
    fun sitesNear(wx: Int, wz: Int, range: Int, out: ArrayList<Site>) {
        out.clear()
        val rx = Math.floorDiv(wx, REGION); val rz = Math.floorDiv(wz, REGION)
        for (dz in -range..range) for (dx in -range..range) regionSite(rx + dx, rz + dz)?.let { out.add(it) }
        out.add(spawnSite)
    }

    // ------------------------------------------------------------------ construction

    fun apply(chunk: Chunk, cols: Array<Column>) {
        val x0 = chunk.cx * 16; val z0 = chunk.cz * 16
        val w = spawnSite
        if (overlaps(w, x0, z0)) build(chunk, w)
        val rx0 = Math.floorDiv(x0, REGION); val rx1 = Math.floorDiv(x0 + 15, REGION)
        val rz0 = Math.floorDiv(z0, REGION); val rz1 = Math.floorDiv(z0 + 15, REGION)
        for (rz in rz0..rz1) for (rx in rx0..rx1) {
            val s = regionSite(rx, rz) ?: continue
            if (overlaps(s, x0, z0)) build(chunk, s)
        }
    }

    private fun overlaps(s: Site, x0: Int, z0: Int): Boolean =
        s.x + s.radius >= x0 && s.x - s.radius <= x0 + 15 && s.z + s.radius >= z0 && s.z - s.radius <= z0 + 15

    private class Pen(val c: Chunk) {
        fun set(wx: Int, y: Int, wz: Int, id: Int) {
            val lx = wx - c.cx * 16; val lz = wz - c.cz * 16
            if (lx !in 0..15 || lz !in 0..15 || y !in 1 until Chunk.HEIGHT) return
            c.blocks[Chunk.index(lx, y, lz)] = id.toByte()
        }
        fun get(wx: Int, y: Int, wz: Int): Int {
            val lx = wx - c.cx * 16; val lz = wz - c.cz * 16
            if (lx !in 0..15 || lz !in 0..15 || y !in 0 until Chunk.HEIGHT) return -1
            return c.blocks[Chunk.index(lx, y, lz)].toInt() and 255
        }
        fun box(x0: Int, y0: Int, z0: Int, x1: Int, y1: Int, z1: Int, id: Int) {
            for (z in z0..z1) for (x in x0..x1) for (y in y0..y1) set(x, y, z, id)
        }
        /** Level the ground: fill below floor with [fill], clear [clear] blocks above. */
        fun pad(x0: Int, z0: Int, x1: Int, z1: Int, floorY: Int, fill: Int, top: Int, clear: Int) {
            for (z in z0..z1) for (x in x0..x1) {
                var y = floorY - 1
                while (y > 1) {
                    val cur = get(x, y, z)
                    if (cur == -1) break
                    if (cur != B.AIR && cur != B.WATER && cur < B.TALL_GRASS && !B.isLeaves(cur) && !B.isLog(cur)) break
                    set(x, y, z, fill); y--
                }
                set(x, floorY - 1, z, top)
                for (yy in floorY until floorY + clear) set(x, yy, z, B.AIR)
            }
        }
    }

    private fun build(chunk: Chunk, s: Site) {
        val p = Pen(chunk)
        val x = s.x; val y = s.y; val z = s.z
        when (s.type) {
            Site.WRECK -> {
                // broken hull ribs half-buried in the sand, a mast, and the survivor's first crate
                for (i in -4..4) {
                    val hgt = 2 - kotlin.math.abs(i) / 2
                    for (k in 0..hgt) { p.set(x + i, y + k, z - 2, B.PLANKS_OAK); if (i % 2 == 0) p.set(x + i, y + k, z + 2, B.PLANKS_OAK) }
                    p.set(x + i, y - 1, z - 1, B.PLANKS_OAK); p.set(x + i, y - 1, z, B.PLANKS_OAK); p.set(x + i, y - 1, z + 1, B.PLANKS_OAK)
                }
                for (k in 0..4) p.set(x - 1, y + k, z, B.PINE_LOG)
                p.set(x - 2, y + 4, z, B.PINE_LOG_X); p.set(x, y + 4, z, B.PINE_LOG_X)
                p.set(x + 2, y, z, B.CRATE)
                p.set(x + 3, y, z + 1, B.CRATE)
            }
            Site.CAMP -> {
                p.pad(x - 4, z - 4, x + 4, z + 4, y, B.DIRT, if (p.get(x, y - 1, z) == B.SAND) B.SAND else B.DIRT, 5)
                p.set(x, y, z, B.CAMPFIRE)
                p.set(x - 2, y, z - 1, B.BEDROLL); p.set(x - 2, y, z + 1, B.BEDROLL)
                p.set(x + 2, y, z - 2, B.CRATE)
                p.set(x + 1, y, z + 2, B.OAK_LOG_X); p.set(x + 2, y, z + 2, B.OAK_LOG_X)
                // lean-to shelter
                for (i in -3..-1) { p.set(x + i, y + 2, z - 2, B.THATCH); p.set(x + i, y + 2, z - 1, B.THATCH) }
                p.set(x - 3, y, z - 2, B.OAK_LOG); p.set(x - 3, y + 1, z - 2, B.OAK_LOG)
                p.set(x - 1, y, z - 2, B.OAK_LOG); p.set(x - 1, y + 1, z - 2, B.OAK_LOG)
            }
            Site.CABIN -> {
                val hx = 4; val hz = 3
                p.pad(x - hx - 1, z - hz - 1, x + hx + 1, z + hz + 1, y, B.COBBLE, B.COBBLE, 7)
                p.box(x - hx, y - 1, z - hz, x + hx, y - 1, z + hz, B.PLANKS_PINE)
                for (yy in y..y + 2) for (i in -hx..hx) for (k in -hz..hz) {
                    val wall = i == -hx || i == hx || k == -hz || k == hz
                    if (!wall) continue
                    val corner = (i == -hx || i == hx) && (k == -hz || k == hz)
                    val ruin = Hash.f3(x + i, yy, z + k, s.id) < 0.16f * (yy - y + 1)
                    if (corner) p.set(x + i, yy, z + k, B.PINE_LOG)
                    else if (!ruin) p.set(x + i, yy, z + k, if (yy == y + 1 && (i == -2 || i == 2) && (k == -hz || k == hz)) B.GLASS else B.PLANKS_OAK)
                }
                p.set(x, y, z + hz, B.AIR); p.set(x, y + 1, z + hz, B.AIR) // doorway
                for (i in -hx - 1..hx + 1) for (k in -hz - 1..hz + 1) {
                    val rise = minOf(hz + 1 - kotlin.math.abs(k), 3)
                    if (Hash.f3(x + i, 7, z + k, s.id) > 0.22f) p.set(x + i, y + 2 + rise, z + k, B.THATCH)
                }
                p.set(x - 3, y, z - 2, B.CRATE)
                p.set(x + 3, y, z - 2, B.BEDROLL)
                p.set(x + 3, y, z + 2, B.WORKBENCH)
                p.set(x - 3, y, z + 2, B.FURNACE)
            }
            Site.TOWER -> {
                p.pad(x - 3, z - 3, x + 3, z + 3, y, B.COBBLE, B.COBBLE, 3)
                val hgt = 11
                p.box(x - 1, y, z - 1, x + 1, y + hgt, z + 1, B.STONE_BRICKS)
                // spiral stair around the core
                val ring = intArrayOf(-2, -2, -1, -2, 0, -2, 1, -2, 2, -2, 2, -1, 2, 0, 2, 1, 2, 2, 1, 2, 0, 2, -1, 2, -2, 2, -2, 1, -2, 0, -2, -1)
                for (i in 0..hgt) {
                    val k = i % 16
                    val sx = x + ring[k * 2]; val sz = z + ring[k * 2 + 1]
                    p.set(sx, y + i, sz, if (i % 4 == 3) B.MOSSY_STONE else B.COBBLE)
                    for (yy in y + i + 1..y + i + 3) p.set(sx, yy, sz, B.AIR)
                }
                p.box(x - 2, y + hgt + 1, z - 2, x + 2, y + hgt + 1, z + 2, B.PLANKS_OAK)
                val lastK = hgt % 16
                p.set(x + ring[lastK * 2], y + hgt + 1, z + ring[lastK * 2 + 1], B.AIR)
                p.set(x, y + hgt + 2, z, B.CRATE)
                p.set(x - 2, y + hgt + 2, z - 2, B.TORCH); p.set(x + 2, y + hgt + 2, z + 2, B.TORCH)
            }
            Site.STATION -> {
                val hx = 6; val hz = 4
                p.pad(x - hx - 1, z - hz - 1, x + hx + 1, z + hz + 1, y, B.STONE, B.COBBLE, 7)
                p.box(x - hx, y - 1, z - hz, x + hx, y - 1, z + hz, B.LAB_FLOOR)
                for (yy in y..y + 3) for (i in -hx..hx) for (k in -hz..hz) {
                    val wall = i == -hx || i == hx || k == -hz || k == hz
                    if (!wall) continue
                    val window = yy in y + 1..y + 2 && ((kotlin.math.abs(i) % 3 == 1 && (k == -hz || k == hz)) || (k == 0 && (i == -hx || i == hx)))
                    val rust = Hash.f3(x + i, yy, z + k, s.id) < 0.25f
                    p.set(x + i, yy, z + k, if (window) B.GLASS else if (rust) B.RUSTY_METAL else B.METAL_PANEL)
                }
                p.box(x - hx, y + 4, z - hz, x + hx, y + 4, z + hz, B.METAL_PANEL)
                p.set(x, y, z + hz, B.AIR); p.set(x, y + 1, z + hz, B.AIR)
                p.set(x - 3, y + 4, z, B.LAMP); p.set(x + 3, y + 4, z, B.LAMP)
                p.set(x - 5, y, z - 3, B.TERMINAL); p.set(x - 5, y + 1, z - 3, B.METAL_PANEL)
                p.set(x + 5, y, z - 3, B.CRATE); p.set(x + 4, y, z - 3, B.CRATE); p.set(x + 5, y + 1, z - 3, B.CRATE)
                p.set(x + 5, y, z + 3, B.WORKBENCH)
                p.set(x - 5, y, z + 3, B.CHEST)
                // antenna mast
                for (k in 5..10) p.set(x + hx, y + k, z - hz, B.RUSTY_METAL)
            }
            Site.BUNKER -> {
                // surface entrance hut
                p.pad(x - 3, z - 3, x + 3, z + 3, y, B.STONE, B.COBBLE, 5)
                for (yy in y..y + 2) for (i in -2..2) for (k in -2..2) {
                    if (i == -2 || i == 2 || k == -2 || k == 2) p.set(x + i, yy, z + k, B.STONE_BRICKS)
                }
                p.box(x - 2, y + 3, z - 2, x + 2, y + 3, z + 2, B.STONE_BRICKS)
                p.set(x - 2, y, z, B.AIR); p.set(x - 2, y + 1, z, B.AIR) // door on -x side
                p.set(x, y + 2, z - 1, B.LAMP)
                // staircase descending toward +x
                val depth = 9
                for (i in 0..depth) {
                    val sx = x + i; val sy = y - 1 - i
                    for (k in -1..1) {
                        p.set(sx, sy, z + k, if (k == 0) B.LAB_FLOOR else B.STONE_BRICKS)
                        for (yy in sy + 1..sy + 4) p.set(sx, yy, z + k, if (k == 0) B.AIR else B.STONE_BRICKS)
                        p.set(sx, sy + 5, z + k, B.STONE_BRICKS)
                    }
                    if (i % 4 == 2) p.set(sx, sy + 4, z, B.LAMP)
                }
                // laboratory hall
                val fy = y - 1 - depth
                val x0 = x + depth + 1; val x1 = x0 + 10
                p.box(x0 - 1, fy - 1, z - 5, x1 + 1, fy + 5, z + 5, B.METAL_PANEL)
                p.box(x0, fy, z - 4, x1, fy + 4, z + 4, B.AIR)
                p.box(x0, fy - 1, z - 4, x1, fy - 1, z + 4, B.LAB_FLOOR)
                for (yy in fy..fy + 3) p.set(x0 - 1, yy, z, B.AIR)
                for (i in 0..2) { p.set(x0 + 2 + i * 3, fy + 4, z - 2, B.LAMP); p.set(x0 + 2 + i * 3, fy + 4, z + 2, B.LAMP) }
                p.set(x1, fy, z - 4, B.TERMINAL); p.set(x1, fy, z + 4, B.TERMINAL)
                p.set(x1, fy, z, B.CRATE); p.set(x1, fy, z - 1, B.CRATE); p.set(x1, fy + 1, z, B.CRATE)
                p.set(x0 + 4, fy, z - 4, B.CHEST)
                p.set(x0 + 5, fy, z + 4, B.CRYSTAL_ORE); p.set(x0 + 6, fy, z + 4, B.CRYSTAL_ORE); p.set(x0 + 5, fy + 1, z + 4, B.CRYSTAL_ORE)
                p.box(x0 + 3, fy, z - 1, x0 + 6, fy, z + 1, B.METAL_PANEL) // central lab table
            }
        }
    }
}
