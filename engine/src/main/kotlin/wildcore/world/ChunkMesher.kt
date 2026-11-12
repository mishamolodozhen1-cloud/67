package wildcore.world

import wildcore.math.Hash
import java.nio.ByteBuffer
import java.nio.ByteOrder

/** CPU-side result of meshing one chunk; uploaded to the GPU on the render thread. */
class ChunkMeshData {
    @JvmField var buffer: ByteBuffer = ByteBuffer.allocateDirect(64 * 1024).order(ByteOrder.nativeOrder())
    @JvmField var opaqueQuads = 0
    @JvmField var cutoutQuads = 0
    @JvmField var spriteQuads = 0
    @JvmField var waterQuads = 0
    @JvmField var minY = 0
    @JvmField var maxY = 0
    @JvmField var revision = 0
    val totalQuads: Int get() = opaqueQuads + cutoutQuads + spriteQuads + waterQuads

    fun ensure(bytes: Int) {
        if (buffer.capacity() < bytes) {
            var cap = buffer.capacity()
            while (cap < bytes) cap *= 2
            buffer = ByteBuffer.allocateDirect(cap).order(ByteOrder.nativeOrder())
        }
    }
}

/** Growable int list used as a per-bucket vertex stream (2 ints per vertex). */
class IntStream(initial: Int) {
    @JvmField var data = IntArray(initial)
    @JvmField var size = 0
    fun put2(a: Int, b: Int) {
        if (size + 2 > data.size) data = data.copyOf(data.size * 2)
        data[size] = a; data[size + 1] = b; size += 2
    }
    fun clear() { size = 0 }
}

/**
 * Turns voxel data into render geometry.
 *
 * - Hidden faces between opaque cubes are never emitted.
 * - Visible faces are merged with greedy meshing (per direction, per slice) when their material,
 *   ambient occlusion and light are identical and uniform.
 * - Per-vertex ambient occlusion and smooth sky/block light are baked in. Light is recomputed
 *   statelessly from the 3x3 chunk neighbourhood with a flood fill, which is exact because light
 *   travels at most 15 blocks.
 *
 * Vertex format: 2 x uint32.
 *   w0 = x(9, 1/16 block) | y(12) << 9 | z(9) << 21
 *   w1 = layer(8) | flags(8) << 8 | normal(3) << 16 | ao(2) << 19 | sky(4) << 21 | block(4) << 25
 *
 * One instance per worker thread (holds large scratch buffers).
 */
class ChunkMesher {
    companion object {
        const val R = 48                  // region edge in blocks (3 chunks)
        const val RY = 130                // 128 + bottom/top padding
        const val SX = RY                 // index stride for +x
        const val SZ = RY * R             // index stride for +z
        const val REGION = R * R * RY
        const val VERTEX_BYTES = 8
        const val NORMAL_UP_FOLIAGE = 6

        private const val NO_MERGE = 1L shl 62
        private const val QCAP = 1 shl 19

        // axisN, axisU, axisV per face direction: +X,-X,+Y,-Y,+Z,-Z  (axes: 0=x 1=y 2=z); u x v = n
        private val AXIS_N = intArrayOf(0, 0, 1, 1, 2, 2)
        private val AXIS_U = intArrayOf(1, 2, 2, 0, 0, 1)
        private val AXIS_V = intArrayOf(2, 1, 0, 2, 1, 0)
        private val SIGN = intArrayOf(1, -1, 1, -1, 1, -1)
        private val STRIDE = intArrayOf(SX, 1, SZ)
    }

    private val blk = ByteArray(REGION)
    private val light = ByteArray(REGION)
    private val top = IntArray(R * R)
    private val queue = IntArray(QCAP)
    private val mask = LongArray(16 * 128)
    private val opaque = IntStream(1 shl 15)
    private val cutout = IntStream(1 shl 14)
    private val sprite = IntStream(1 shl 13)
    private val water = IntStream(1 shl 12)
    private val cAo = IntArray(4)
    private val cSky = IntArray(4)
    private val cBlk = IntArray(4)
    private val pos = IntArray(3)

    /** Options that depend on the graphics tier. */
    @JvmField var leafInnerFaces = true

    private fun regionIndex(x: Int, y: Int, z: Int): Int = ((z + 16) * R + (x + 16)) * RY + (y + 1)

    /**
     * @param neighbours 3x3 chunks, index (dz+1)*3 + (dx+1); centre at 4. All must be READY.
     */
    fun mesh(neighbours: Array<Chunk?>, wallBlock: Int, out: ChunkMeshData) {
        copyRegion(neighbours, wallBlock)
        computeLight(neighbours)
        opaque.clear(); cutout.clear(); sprite.clear(); water.clear()

        // vertical extent of the centre chunk
        var maxY = 0
        for (z in 0 until 16) for (x in 0 until 16) {
            val base = regionIndex(x, 0, z)
            var y = 127
            while (y > maxY && blk[base + y] == 0.toByte()) y--
            if (y > maxY) maxY = y
        }
        var minQuadY = 4096; var maxQuadY = 0

        for (dir in 0 until 6) buildFaces(dir, maxY)
        buildModels(maxY)

        // scan y range from emitted vertices (cheap: only first word needed)
        fun range(s: IntStream) {
            var i = 0
            while (i < s.size) {
                val y = (s.data[i] ushr 9) and 0xFFF
                if (y < minQuadY) minQuadY = y
                if (y > maxQuadY) maxQuadY = y
                i += 2
            }
        }
        range(opaque); range(cutout); range(sprite); range(water)
        if (minQuadY > maxQuadY) { minQuadY = 0; maxQuadY = 0 }

        val totalInts = opaque.size + cutout.size + sprite.size + water.size
        out.ensure(totalInts * 4)
        val bb = out.buffer
        bb.clear()
        val ib = bb.asIntBuffer()
        ib.put(opaque.data, 0, opaque.size)
        ib.put(cutout.data, 0, cutout.size)
        ib.put(sprite.data, 0, sprite.size)
        ib.put(water.data, 0, water.size)
        bb.position(0).limit(totalInts * 4)
        out.opaqueQuads = opaque.size / 8
        out.cutoutQuads = cutout.size / 8
        out.spriteQuads = sprite.size / 8
        out.waterQuads = water.size / 8
        out.minY = minQuadY / 16
        out.maxY = (maxQuadY + 15) / 16
    }

    // ---------------------------------------------------------------- region copy

    private fun copyRegion(n: Array<Chunk?>, wallBlock: Int) {
        val wall = wallBlock.toByte()
        for (cz in 0 until 3) for (cx in 0 until 3) {
            val c = n[cz * 3 + cx]
            for (z in 0 until 16) for (x in 0 until 16) {
                val rx = cx * 16 + x; val rz = cz * 16 + z
                val dst = (rz * R + rx) * RY
                val edge = rx == 0 || rz == 0 || rx == R - 1 || rz == R - 1
                if (c == null || edge) {
                    // outermost ring acts as an opaque wall so the light flood fill needs no bounds checks
                    java.util.Arrays.fill(blk, dst, dst + RY, wall)
                } else {
                    blk[dst] = wall
                    System.arraycopy(c.blocks, ((z shl 4) or x) shl 7, blk, dst + 1, 128)
                    blk[dst + 129] = 0
                }
            }
        }
    }

    // ---------------------------------------------------------------- lighting

    private fun computeLight(n: Array<Chunk?>) {
        java.util.Arrays.fill(light, 0)
        val opacity = Blocks.lightOpacity
        // 1) direct skylight straight down each column
        for (c in 0 until R * R) {
            val base = c * RY
            light[base + 129] = 15
            var yy = 128
            while (yy >= 1 && opacity[blk[base + yy].toInt() and 255] == 0) {
                light[base + yy] = 15
                yy--
            }
            top[c] = yy // region-y (block y + 1) of first non-transparent block, 0 if none
        }
        // 2) seeds: lit cells next to unlit, non-opaque cells
        var head = 0; var tail = 0
        for (z in 1 until R - 1) for (x in 1 until R - 1) {
            val c = z * R + x
            val t = top[c]
            val base = c * RY
            // light entering semi-transparent blocks (leaves, water) from directly above
            if (t >= 1 && opacity[blk[base + t].toInt() and 255] < 15) { queue[tail++] = base + t + 1 }
            val m = maxOf(maxOf(top[c - 1], top[c + 1]), maxOf(top[c - R], top[c + R]))
            if (m <= t) continue
            var yy = t + 1
            while (yy <= m) {
                val i = base + yy
                if ((top[c - 1] >= yy && opacity[blk[i - SX].toInt() and 255] < 15) ||
                    (top[c + 1] >= yy && opacity[blk[i + SX].toInt() and 255] < 15) ||
                    (top[c - R] >= yy && opacity[blk[i - SZ].toInt() and 255] < 15) ||
                    (top[c + R] >= yy && opacity[blk[i + SZ].toInt() and 255] < 15)) {
                    if (tail < QCAP) queue[tail++] = i
                }
                yy++
            }
        }
        flood(head, tail, 0)
        // 3) block light from emitters
        head = 0; tail = 0
        for (cz in 0 until 3) for (cx in 0 until 3) {
            val ch = n[cz * 3 + cx] ?: continue
            for (k in 0 until ch.emitterCount) {
                val idx = ch.emitters[k]
                val y = idx and 127; val x = (idx shr 7) and 15; val z = idx shr 11
                val rx = cx * 16 + x; val rz = cz * 16 + z
                if (rx == 0 || rz == 0 || rx == R - 1 || rz == R - 1) continue
                val i = (rz * R + rx) * RY + y + 1
                val e = Blocks.emission[blk[i].toInt() and 255]
                if (e <= 0) continue
                light[i] = ((light[i].toInt() and 0x0F) or (e shl 4)).toByte()
                if (tail < QCAP) queue[tail++] = i
            }
        }
        flood(head, tail, 4)
    }

    /** Breadth-first light propagation on one nibble (shift 0 = sky, 4 = block). */
    private fun flood(headIn: Int, tailIn: Int, shift: Int) {
        var head = headIn; var tail = tailIn
        val opacity = Blocks.lightOpacity
        val keep = if (shift == 0) 0xF0 else 0x0F
        while (head < tail) {
            val i = queue[head++]
            val l = (light[i].toInt() shr shift) and 15
            if (l <= 1) continue
            for (d in 0 until 6) {
                val j = when (d) { 0 -> i + 1; 1 -> i - 1; 2 -> i + SX; 3 -> i - SX; 4 -> i + SZ; else -> i - SZ }
                val op = opacity[blk[j].toInt() and 255]
                if (op >= 15) continue
                val nl = l - (if (op < 1) 1 else op)
                val cur = (light[j].toInt() shr shift) and 15
                if (nl > cur) {
                    light[j] = ((light[j].toInt() and keep) or (nl shl shift)).toByte()
                    if (tail < QCAP) queue[tail++] = j
                }
            }
        }
    }

    // ---------------------------------------------------------------- cube faces

    private fun buildFaces(dir: Int, maxY: Int) {
        val an = AXIS_N[dir]; val au = AXIS_U[dir]; val av = AXIS_V[dir]
        val sn = STRIDE[an] * SIGN[dir]; val su = STRIDE[au]; val sv = STRIDE[av]
        val sizeN = if (an == 1) maxY + 1 else 16
        val sizeU = if (au == 1) maxY + 1 else 16
        val sizeV = if (av == 1) maxY + 1 else 16
        val shape = Blocks.shape
        val opq = Blocks.opaque
        val origin = regionIndex(0, 0, 0)
        val positive = SIGN[dir] > 0

        for (n in 0 until sizeN) {
            var any = false
            // --- build mask
            for (v in 0 until sizeV) {
                var cell = origin + n * STRIDE[an] + v * sv
                val row = v * sizeU
                for (u in 0 until sizeU) {
                    val a = blk[cell].toInt() and 255
                    var key = 0L
                    if (a != 0) {
                        val sa = shape[a]
                        if (sa == Shape.CUBE || sa == Shape.CUTOUT || sa == Shape.LIQUID) {
                            val b = blk[cell + sn].toInt() and 255
                            val visible = when (sa) {
                                Shape.CUBE -> !opq[b]
                                Shape.CUTOUT -> !opq[b] && (b != a || (leafInnerFaces && positive && (Blocks.get(a).flags and VFlag.FLUTTER) != 0))
                                else -> !opq[b] && shape[b] != Shape.LIQUID && (dir != 3)
                            }
                            if (visible) key = faceKey(a, sa, cell + sn, su, sv)
                        }
                    }
                    mask[row + u] = key
                    if (key != 0L) any = true
                    cell += su
                }
            }
            if (!any) continue
            // --- greedy merge
            for (v in 0 until sizeV) {
                var u = 0
                while (u < sizeU) {
                    val key = mask[v * sizeU + u]
                    if (key == 0L) { u++; continue }
                    var w = 1; var h = 1
                    if (key and NO_MERGE == 0L) {
                        while (u + w < sizeU && mask[v * sizeU + u + w] == key) w++
                        outer@ while (v + h < sizeV) {
                            val r = (v + h) * sizeU + u
                            for (k in 0 until w) if (mask[r + k] != key) break@outer
                            h++
                        }
                        for (dv in 0 until h) {
                            val r = (v + dv) * sizeU + u
                            for (k in 0 until w) mask[r + k] = 0L
                        }
                    }
                    emitFace(dir, n, u, v, w, h, key)
                    u += w
                }
            }
        }
    }

    /** Computes per-corner AO + light for a face whose outside cell is [o], and packs the merge key. */
    private fun faceKey(block: Int, shapeA: Int, o: Int, su: Int, sv: Int): Long {
        val opq = Blocks.opaque
        var key = block.toLong()
        val bucket = when (shapeA) { Shape.CUBE -> 0L; Shape.CUTOUT -> 1L; else -> 2L }
        key = key or (bucket shl 8)
        val lo = light[o].toInt()
        if (shapeA == Shape.LIQUID) {
            val c = (3 or ((lo and 15) shl 2) or (((lo shr 4) and 15) shl 6)).toLong()
            return key or (c shl 10) or (c shl 20) or (c shl 30) or (c shl 40)
        }
        var first = 0; var uniform = true
        for (ci in 0 until 4) {
            // corner order (u,v): (0,0) (1,0) (1,1) (0,1)
            val du = if (ci == 1 || ci == 2) su else -su
            val dv = if (ci >= 2) sv else -sv
            val s1 = o + du; val s2 = o + dv; val cc = o + du + dv
            val o1 = opq[blk[s1].toInt() and 255]
            val o2 = opq[blk[s2].toInt() and 255]
            val oc = opq[blk[cc].toInt() and 255]
            val ao = if (o1 && o2) 0 else 3 - ((if (o1) 1 else 0) + (if (o2) 1 else 0) + (if (oc) 1 else 0))
            var sky = lo and 15; var bl = (lo shr 4) and 15; var cnt = 1
            if (!o1) { val l = light[s1].toInt(); sky += l and 15; bl += (l shr 4) and 15; cnt++ }
            if (!o2) { val l = light[s2].toInt(); sky += l and 15; bl += (l shr 4) and 15; cnt++ }
            if (!oc && !(o1 && o2)) { val l = light[cc].toInt(); sky += l and 15; bl += (l shr 4) and 15; cnt++ }
            sky = (sky + cnt / 2) / cnt; bl = (bl + cnt / 2) / cnt
            val c = ao or (sky shl 2) or (bl shl 6)
            if (ci == 0) first = c else if (c != first) uniform = false
            key = key or (c.toLong() shl (10 + ci * 10))
        }
        if (!uniform) key = key or NO_MERGE
        return key
    }

    private fun emitFace(dir: Int, n: Int, u: Int, v: Int, w: Int, h: Int, key: Long) {
        val block = (key and 0xFF).toInt()
        val bucket = ((key shr 8) and 3).toInt()
        val def = Blocks.get(block)
        val an = AXIS_N[dir]; val au = AXIS_U[dir]; val av = AXIS_V[dir]
        var flags = def.flags
        val layer: Int
        if (def.axis == 1) {
            layer = when (dir) { 2 -> def.texTop; 3 -> def.texBottom; else -> def.texSide }
        } else {
            // rotated block (sideways log): end-grain on the faces along its axis, bark elsewhere
            layer = if (an == def.axis) def.texTop else def.texSide
            if (an != def.axis && (def.axis == 0 || an == 0)) flags = flags or VFlag.UV_SWAP
        }
        val stream = when (bucket) { 0 -> opaque; 1 -> cutout; else -> water }
        var lowered = 0
        if (bucket == 2) {
            flags = flags or VFlag.WATER
            if (dir == 2) lowered = 2 // water surface sits 2/16 below the block top
        }
        for (ci in 0 until 4) {
            val c = ((key shr (10 + ci * 10)) and 0x3FF).toInt()
            cAo[ci] = c and 3; cSky[ci] = (c shr 2) and 15; cBlk[ci] = (c shr 6) and 15
        }
        // choose the triangulation diagonal so AO/light gradients stay localized to the dark corner
        val b0 = cAo[0] * 5 + cSky[0] + cBlk[0]; val b1 = cAo[1] * 5 + cSky[1] + cBlk[1]
        val b2 = cAo[2] * 5 + cSky[2] + cBlk[2]; val b3 = cAo[3] * 5 + cSky[3] + cBlk[3]
        val start = if (b0 + b2 < b1 + b3) 1 else 0
        val nCoord = (if (SIGN[dir] > 0) n + 1 else n) * 16
        for (k in 0 until 4) {
            val ci = (k + start) and 3
            val cu = if (ci == 1 || ci == 2) u + w else u
            val cv = if (ci >= 2) v + h else v
            pos[an] = nCoord - (if (an == 1) lowered else 0)
            pos[au] = cu * 16
            pos[av] = cv * 16
            val w0 = pos[0] or (pos[1] shl 9) or (pos[2] shl 21)
            val w1 = layer or (flags shl 8) or (dir shl 16) or (cAo[ci] shl 19) or (cSky[ci] shl 21) or (cBlk[ci] shl 25)
            stream.put2(w0, w1)
        }
    }

    // ---------------------------------------------------------------- non-cube models

    private fun buildModels(maxY: Int) {
        val shape = Blocks.shape
        for (z in 0 until 16) for (x in 0 until 16) {
            val base = regionIndex(x, 0, z)
            for (y in 0..maxY) {
                val a = blk[base + y].toInt() and 255
                if (a == 0) continue
                val s = shape[a]
                if (s == Shape.CROSS) emitCross(x, y, z, a, light[base + y].toInt())
                else if (s == Shape.BOX) emitBox(x, y, z, a, light[base + y].toInt())
            }
        }
    }

    private fun emitCross(x: Int, y: Int, z: Int, block: Int, l: Int) {
        val def = Blocks.get(block)
        val h = Hash.hash3(x, y, z, 7919)
        // random offset within the cell keeps meadows from looking like a grid
        val ox = ((h and 7) - 3)
        val oz = (((h shr 3) and 7) - 3)
        val height = (def.boxMaxY * 16f).toInt() + ((h shr 6) and 3) - 1
        val flags = def.flags or VFlag.SPRITE_UV
        val sky = l and 15; val bl = (l shr 4) and 15
        val w1base = def.texSide or (flags shl 8) or (NORMAL_UP_FOLIAGE shl 16) or (3 shl 19) or (sky shl 21) or (bl shl 25)
        val x0 = x * 16 + 8 + ox; val z0 = z * 16 + 8 + oz
        val y0 = y * 16; val y1 = y0 + height
        val r = 7
        // two diagonal quads; corner order (0,0) (1,0) (1,1) (0,1) => bottom-left, bottom-right, top-right, top-left
        for (q in 0 until 2) {
            val ax = x0 - r; val bx = x0 + r
            val az = if (q == 0) z0 - r else z0 + r
            val bz = if (q == 0) z0 + r else z0 - r
            sprite.put2(pack(ax, y0, az), w1base)
            sprite.put2(pack(bx, y0, bz), w1base)
            sprite.put2(pack(bx, y1, bz), w1base)
            sprite.put2(pack(ax, y1, az), w1base)
        }
    }

    private fun emitBox(x: Int, y: Int, z: Int, block: Int, l: Int) {
        val def = Blocks.get(block)
        val inset = (def.boxMin * 16f).toInt()
        val x0 = x * 16 + inset; val x1 = x * 16 + 16 - inset
        val z0 = z * 16 + inset; val z1 = z * 16 + 16 - inset
        val y0 = y * 16; val y1 = y0 + (def.boxMaxY * 16f).toInt()
        val sky = l and 15; val bl = (l shr 4) and 15
        val stream = opaque
        fun w1(layer: Int, dir: Int) = layer or (def.flags shl 8) or (dir shl 16) or (3 shl 19) or (sky shl 21) or (bl shl 25)
        // +X
        var w = w1(def.texSide, 0)
        stream.put2(pack(x1, y0, z0), w); stream.put2(pack(x1, y1, z0), w); stream.put2(pack(x1, y1, z1), w); stream.put2(pack(x1, y0, z1), w)
        // -X
        w = w1(def.texSide, 1)
        stream.put2(pack(x0, y0, z0), w); stream.put2(pack(x0, y0, z1), w); stream.put2(pack(x0, y1, z1), w); stream.put2(pack(x0, y1, z0), w)
        // +Y
        w = w1(def.texTop, 2)
        stream.put2(pack(x0, y1, z0), w); stream.put2(pack(x0, y1, z1), w); stream.put2(pack(x1, y1, z1), w); stream.put2(pack(x1, y1, z0), w)
        // -Y
        w = w1(def.texBottom, 3)
        stream.put2(pack(x0, y0, z0), w); stream.put2(pack(x1, y0, z0), w); stream.put2(pack(x1, y0, z1), w); stream.put2(pack(x0, y0, z1), w)
        // +Z
        w = w1(def.texSide, 4)
        stream.put2(pack(x0, y0, z1), w); stream.put2(pack(x1, y0, z1), w); stream.put2(pack(x1, y1, z1), w); stream.put2(pack(x0, y1, z1), w)
        // -Z
        w = w1(def.texSide, 5)
        stream.put2(pack(x0, y0, z0), w); stream.put2(pack(x0, y1, z0), w); stream.put2(pack(x1, y1, z0), w); stream.put2(pack(x1, y0, z0), w)
    }

    private fun pack(x: Int, y: Int, z: Int): Int = (x and 0x1FF) or ((y and 0xFFF) shl 9) or ((z and 0x1FF) shl 21)
}
