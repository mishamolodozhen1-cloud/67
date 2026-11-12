package wildfrontier.gen

import wildcore.math.Hash
import wildcore.world.Chunk
import wildfrontier.content.B

/** Procedural tree shapes built from log and leaf blocks. Deterministic per (position, hash). */
object Trees {
    enum class Kind { OAK, BIRCH, SPRUCE, PINE, PALM, JUNGLE, JUNGLE_BIG, SWAMP, APPLE, ANCIENT }

    private fun put(c: Chunk, wx: Int, y: Int, wz: Int, id: Int, replaceSoft: Boolean) {
        val lx = wx - c.cx * 16; val lz = wz - c.cz * 16
        if (lx !in 0..15 || lz !in 0..15 || y !in 1 until Chunk.HEIGHT) return
        val idx = Chunk.index(lx, y, lz)
        val cur = c.blocks[idx].toInt() and 255
        if (cur == B.AIR || (replaceSoft && (B.isLeaves(cur) || cur >= B.TALL_GRASS))) c.blocks[idx] = id.toByte()
    }

    private fun trunk(c: Chunk, x: Int, y0: Int, z: Int, h: Int, log: Int) {
        for (y in y0 until y0 + h) put(c, x, y, z, log, true)
    }

    /** Leaf blob: horizontal discs with per-layer radius, ragged edge from a position hash. */
    private fun disc(c: Chunk, x: Int, y: Int, z: Int, r: Float, leaf: Int, seed: Int, alt: Int = 0, altChance: Float = 0f) {
        val ir = r.toInt() + 1
        for (dz in -ir..ir) for (dx in -ir..ir) {
            val d2 = dx * dx + dz * dz
            val jitter = Hash.f3(x + dx, y, z + dz, seed) * 1.3f - 0.4f
            if (d2 <= r * r + jitter) {
                val id = if (alt != 0 && Hash.f3(x + dx, y, z + dz, seed + 17) < altChance) alt else leaf
                put(c, x + dx, y, z + dz, id, false)
            }
        }
    }

    fun place(c: Chunk, x: Int, ground: Int, z: Int, kind: Kind, h: Int) {
        when (kind) {
            Kind.OAK -> {
                val th = 4 + (h and 3) % 3
                trunk(c, x, ground, z, th, B.OAK_LOG)
                val top = ground + th
                disc(c, x, top - 2, z, 2.2f, B.OAK_LEAVES, h)
                disc(c, x, top - 1, z, 2.9f, B.OAK_LEAVES, h)
                disc(c, x, top, z, 2.7f, B.OAK_LEAVES, h)
                disc(c, x, top + 1, z, 2.0f, B.OAK_LEAVES, h)
                disc(c, x, top + 2, z, 1.0f, B.OAK_LEAVES, h)
            }
            Kind.APPLE -> {
                val th = 3 + (h and 1)
                trunk(c, x, ground, z, th, B.OAK_LOG)
                val top = ground + th
                disc(c, x, top - 1, z, 2.1f, B.OAK_LEAVES, h, B.FRUIT_LEAVES, 0.3f)
                disc(c, x, top, z, 2.3f, B.OAK_LEAVES, h, B.FRUIT_LEAVES, 0.3f)
                disc(c, x, top + 1, z, 1.4f, B.OAK_LEAVES, h, B.FRUIT_LEAVES, 0.2f)
            }
            Kind.BIRCH -> {
                val th = 5 + (h and 3) % 3
                trunk(c, x, ground, z, th, B.BIRCH_LOG)
                val top = ground + th
                disc(c, x, top - 3, z, 1.3f, B.BIRCH_LEAVES, h)
                disc(c, x, top - 2, z, 2.0f, B.BIRCH_LEAVES, h)
                disc(c, x, top - 1, z, 2.2f, B.BIRCH_LEAVES, h)
                disc(c, x, top, z, 1.8f, B.BIRCH_LEAVES, h)
                disc(c, x, top + 1, z, 1.1f, B.BIRCH_LEAVES, h)
            }
            Kind.SPRUCE -> {
                val th = 7 + (h and 7) % 5
                trunk(c, x, ground, z, th, B.PINE_LOG)
                val top = ground + th
                var y = ground + 2
                while (y <= top) {
                    val t = (top - y).toFloat()
                    val r = minOf(3.6f, 0.5f + t * 0.36f + (if (((y - ground) and 1) == 0) 0.7f else 0f))
                    disc(c, x, y, z, r, B.PINE_LEAVES, h)
                    y++
                }
                put(c, x, top + 1, z, B.PINE_LEAVES, false)
                put(c, x, top + 2, z, B.PINE_LEAVES, false)
            }
            Kind.PINE -> {
                val th = 8 + (h and 7) % 4
                trunk(c, x, ground, z, th, B.PINE_LOG)
                val top = ground + th
                disc(c, x, top - 3, z, 1.6f, B.PINE_LEAVES, h)
                disc(c, x, top - 2, z, 2.6f, B.PINE_LEAVES, h)
                disc(c, x, top - 1, z, 1.5f, B.PINE_LEAVES, h)
                disc(c, x, top, z, 2.3f, B.PINE_LEAVES, h)
                disc(c, x, top + 1, z, 1.2f, B.PINE_LEAVES, h)
            }
            Kind.PALM -> {
                val th = 5 + (h and 3)
                // slight lean: shift the upper trunk by one block
                val lx = if ((h and 16) != 0) 1 else -1
                val lz = if ((h and 32) != 0) 1 else 0
                val bend = th / 2 + 1
                for (i in 0 until th) {
                    val ox = if (i >= bend) lx else 0; val oz = if (i >= bend) lz else 0
                    put(c, x + ox, ground + i, z + oz, B.PALM_LOG, true)
                }
                val tx = x + lx; val tz = z + lz; val top = ground + th
                put(c, tx, top, tz, B.PALM_LEAVES, false)
                val dirs = intArrayOf(1, 0, -1, 0, 0, 1, 0, -1, 1, 1, -1, 1, 1, -1, -1, -1)
                for (d in 0 until 8) {
                    val dx = dirs[d * 2]; val dz = dirs[d * 2 + 1]
                    val len = if (d < 4) 3 else 2
                    for (k in 1..len) {
                        val droop = if (k == len) -1 else 0
                        put(c, tx + dx * k, top + droop, tz + dz * k, B.PALM_LEAVES, false)
                    }
                    if (d < 4) put(c, tx + dx * 4, top - 2, tz + dz * 4, B.PALM_LEAVES, false)
                }
            }
            Kind.JUNGLE -> {
                val th = 8 + (h and 7) % 5
                trunk(c, x, ground, z, th, B.OAK_LOG)
                val top = ground + th
                disc(c, x, top - 2, z, 2.4f, B.JUNGLE_LEAVES, h)
                disc(c, x, top - 1, z, 3.5f, B.JUNGLE_LEAVES, h)
                disc(c, x, top, z, 3.2f, B.JUNGLE_LEAVES, h)
                disc(c, x, top + 1, z, 2.0f, B.JUNGLE_LEAVES, h)
                disc(c, x, ground + th / 2, z, 1.4f, B.JUNGLE_LEAVES, h + 3)
            }
            Kind.JUNGLE_BIG -> {
                val th = 12 + (h and 7) % 6
                trunk(c, x, ground, z, th, B.OAK_LOG)
                trunk(c, x + 1, ground, z, th - 1, B.OAK_LOG)
                trunk(c, x, ground, z + 1, th - 2, B.OAK_LOG)
                val top = ground + th
                disc(c, x, top - 3, z, 2.5f, B.JUNGLE_LEAVES, h)
                disc(c, x, top - 2, z, 4.0f, B.JUNGLE_LEAVES, h)
                disc(c, x, top - 1, z, 4.6f, B.JUNGLE_LEAVES, h)
                disc(c, x, top, z, 4.0f, B.JUNGLE_LEAVES, h)
                disc(c, x, top + 1, z, 2.6f, B.JUNGLE_LEAVES, h)
                disc(c, x + 1, ground + th / 2, z, 1.8f, B.JUNGLE_LEAVES, h + 5)
            }
            Kind.SWAMP -> {
                val th = 4 + (h and 1)
                trunk(c, x, ground - 1, z, th + 1, B.OAK_LOG)
                val top = ground + th
                disc(c, x, top - 1, z, 3.4f, B.OAK_LEAVES, h)
                disc(c, x, top, z, 3.0f, B.OAK_LEAVES, h)
                disc(c, x, top + 1, z, 1.6f, B.OAK_LEAVES, h)
                // hanging moss curtains
                for (k in 0 until 8) {
                    val a = Hash.hash2(x * 31 + k, z * 17, h)
                    val dx = (a and 7) - 3; val dz = ((a shr 3) and 7) - 3
                    if (dx * dx + dz * dz in 6..12) {
                        val len = 1 + ((a shr 6) and 1)
                        for (j in 1..len) put(c, x + dx, top - 1 - j, z + dz, B.OAK_LEAVES, false)
                    }
                }
            }
            Kind.ANCIENT -> {
                val th = 14 + (h and 3)
                for (dz in 0..1) for (dx in 0..1) trunk(c, x + dx, ground - 1, z + dz, th + 1, B.OAK_LOG)
                // buttress roots
                put(c, x - 1, ground, z, B.OAK_LOG, true); put(c, x + 2, ground, z + 1, B.OAK_LOG, true)
                put(c, x, ground, z - 1, B.OAK_LOG, true); put(c, x + 1, ground, z + 2, B.OAK_LOG, true)
                val top = ground + th
                disc(c, x, top - 4, z, 3.0f, B.OAK_LEAVES, h, B.FRUIT_LEAVES, 0.08f)
                disc(c, x, top - 3, z, 4.8f, B.OAK_LEAVES, h)
                disc(c, x, top - 2, z, 5.6f, B.OAK_LEAVES, h)
                disc(c, x, top - 1, z, 5.6f, B.OAK_LEAVES, h)
                disc(c, x, top, z, 4.8f, B.OAK_LEAVES, h)
                disc(c, x, top + 1, z, 3.4f, B.OAK_LEAVES, h)
                disc(c, x, top + 2, z, 1.8f, B.OAK_LEAVES, h)
            }
        }
    }
}
