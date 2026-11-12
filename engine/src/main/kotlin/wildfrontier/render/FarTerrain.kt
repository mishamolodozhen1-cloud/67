package wildfrontier.render

import wildcore.core.Engine
import wildcore.gfx.GL
import wildcore.gfx.Mesh
import wildcore.gfx.Shader
import wildcore.gfx.VertexAttrib
import wildcore.gfx.VertexLayout
import wildcore.world.Chunk
import wildcore.world.LongMap
import wildfrontier.content.Tex
import wildfrontier.gen.Biome
import wildfrontier.gen.Column
import wildfrontier.gen.WorldGen
import java.nio.ByteBuffer

/**
 * Level-of-detail terrain beyond the voxel view distance: 64-block heightfield tiles sampled straight
 * from the world generator (no voxel data), so distant islands and mountains stay visible for a few
 * hundred triangles each. Tiles are built on worker threads and culled against the frustum.
 */
class FarTerrain(private val engine: Engine, private val renderer: WorldRenderer, private val gen: WorldGen) : SceneLayer {
    companion object {
        const val TILE = 64
        const val CELLS = 16
        const val STEP = TILE / CELLS
        const val VERTS = (CELLS + 1) * (CELLS + 1)
        private val LAYOUT = VertexLayout(20, arrayOf(
            VertexAttrib(0, 3, GL.FLOAT, false, 0),
            VertexAttrib(1, 4, GL.BYTE, true, 12),
            VertexAttrib(2, 4, GL.UNSIGNED_BYTE, true, 16)))
    }

    private class Tile(val tx: Int, val tz: Int) {
        var mesh: Mesh? = null
        var minY = 0f; var maxY = 0f
        var building = true
    }

    private val gl: GL get() = engine.gl
    private val tiles = LongMap<Tile>(256)
    private lateinit var shader: Shader
    private var indexBuffer = 0
    private var centerTx = Int.MIN_VALUE
    private var centerTz = Int.MIN_VALUE
    private var inFlight = 0
    private val pending = ArrayList<Long>()
    var radiusTiles = 6
    var nearRadius = 0f
    private var colors = FloatArray(0)

    fun init() {
        shader = renderer.shaders.load("far", "farterrain.vert", "farterrain.frag", arrayOf("aPos", "aNormal", "aColor"))
        val bb = Mesh.directBuffer(CELLS * CELLS * 6 * 2)
        val sb = bb.asShortBuffer()
        for (z in 0 until CELLS) for (x in 0 until CELLS) {
            val i = z * (CELLS + 1) + x
            sb.put(i.toShort()).put((i + CELLS + 1).toShort()).put((i + 1).toShort())
            sb.put((i + 1).toShort()).put((i + CELLS + 1).toShort()).put((i + CELLS + 2).toShort())
        }
        indexBuffer = gl.genBuffer()
        gl.bindVertexArray(0)
        gl.bindBuffer(GL.ELEMENT_ARRAY_BUFFER, indexBuffer)
        gl.bufferData(GL.ELEMENT_ARRAY_BUFFER, CELLS * CELLS * 6 * 2, bb, GL.STATIC_DRAW)
        colors = renderer.textures.layerColor
        // GL context was (re)created: every tile must be rebuilt
        tiles.forEach { it.mesh = null }
        val keep = ArrayList<Tile>()
        tiles.forEach { keep.add(it) }
        for (t in keep) tiles.remove(Chunk.key(t.tx, t.tz))
        centerTx = Int.MIN_VALUE
    }

    val farDistance: Float get() = (radiusTiles + 0.5f) * TILE

    fun update(camX: Float, camZ: Float) {
        val tx = Math.floorDiv(camX.toInt(), TILE); val tz = Math.floorDiv(camZ.toInt(), TILE)
        if (tx != centerTx || tz != centerTz) {
            centerTx = tx; centerTz = tz
            pending.clear()
            val r = radiusTiles
            for (dz in -r..r) for (dx in -r..r) {
                if (dx * dx + dz * dz > r * r + r) continue
                val key = Chunk.key(tx + dx, tz + dz)
                if (tiles.get(key) == null) pending.add(key)
            }
            pending.sortWith { a, b ->
                val ax = (a shr 32).toInt() - tx; val az = a.toInt() - tz
                val bx = (b shr 32).toInt() - tx; val bz = b.toInt() - tz
                (bx * bx + bz * bz).compareTo(ax * ax + az * az)
            }
            var drop: ArrayList<Tile>? = null
            tiles.forEach { t ->
                val dx = t.tx - tx; val dz = t.tz - tz
                if (dx * dx + dz * dz > (r + 2) * (r + 2)) { if (drop == null) drop = ArrayList(); drop!!.add(t) }
            }
            drop?.forEach { t -> t.mesh?.dispose(); t.mesh = null; tiles.remove(Chunk.key(t.tx, t.tz)) }
        }
        while (inFlight < 3 && pending.isNotEmpty()) {
            val key = pending.removeAt(pending.size - 1)
            if (tiles.get(key) != null) continue
            val t = Tile((key shr 32).toInt(), key.toInt())
            tiles.put(key, t)
            inFlight++
            engine.jobs.submit(5000f, Runnable {
                val data = build(t)
                engine.jobs.runOnMain(Runnable {
                    inFlight--
                    t.building = false
                    if (tiles.get(key) === t) {
                        val m = Mesh(gl, LAYOUT)
                        m.setVertices(data, VERTS * 20)
                        m.useSharedIndexBuffer(indexBuffer, GL.UNSIGNED_SHORT)
                        t.mesh = m
                    }
                })
            })
        }
    }

    private fun layerColor(name: Int, out: FloatArray, k: Float) {
        out[0] += colors[name * 3] * k; out[1] += colors[name * 3 + 1] * k; out[2] += colors[name * 3 + 2] * k
    }

    private val tGrass = Tex.of("grass_top"); private val tDry = Tex.of("grass_dry"); private val tLush = Tex.of("grass_lush")
    private val tSand = Tex.of("sand"); private val tStone = Tex.of("stone"); private val tSnow = Tex.of("snow")
    private val tMud = Tex.of("mud"); private val tFloor = Tex.of("forest_floor")
    private val tOak = Tex.of("oak_leaves"); private val tPine = Tex.of("pine_leaves"); private val tJungle = Tex.of("jungle_leaves")

    private fun build(t: Tile): ByteBuffer {
        val n = CELLS + 3
        val h = FloatArray(n * n)
        val biome = IntArray(n * n)
        val temp = FloatArray(n * n)
        val col = Column()
        val x0 = t.tx * TILE; val z0 = t.tz * TILE
        for (j in 0 until n) for (i in 0 until n) {
            gen.sample(x0 + (i - 1) * STEP, z0 + (j - 1) * STEP, col)
            h[j * n + i] = col.height; biome[j * n + i] = col.biome; temp[j * n + i] = col.temp
        }
        val bb = Mesh.directBuffer(VERTS * 20)
        var minY = 1e9f; var maxY = -1e9f
        val c = FloatArray(3)
        for (j in 1..CELLS + 1) for (i in 1..CELLS + 1) {
            val k = j * n + i
            val hh = h[k]
            val water = hh < WorldGen.SEA + 0.25f   // shoals and the wet shoreline read as water from afar
            val wx = x0 + (i - 1) * STEP; val wz = z0 + (j - 1) * STEP
            val r = wildcore.math.Hash.f2(wx, wz, 91)
            var y: Float
            c[0] = 0f; c[1] = 0f; c[2] = 0f
            var canopy = 0f
            if (water) {
                y = WorldGen.SEA - 0.55f   // kept below the voxel water surface where the two overlap
                val depth = ((WorldGen.SEA - hh) / 14f).coerceIn(0f, 1f)
                c[0] = 0.030f - 0.020f * depth; c[1] = 0.18f - 0.12f * depth; c[2] = 0.19f - 0.095f * depth
            } else {
                val slope = maxOf(kotlin.math.abs(h[k + 1] - h[k - 1]), kotlin.math.abs(h[k + n] - h[k - n])) / (2f * STEP)
                when (biome[k]) {
                    Biome.BEACH, Biome.OCEAN, Biome.RIVER -> layerColor(tSand, c, 1f)
                    Biome.MEADOW -> layerColor(if (temp[k] > 0.24f) tDry else tGrass, c, 1f)
                    Biome.DECIDUOUS -> { layerColor(tGrass, c, 0.35f); layerColor(tOak, c, 0.65f); canopy = 5f }
                    Biome.CONIFER -> { layerColor(tFloor, c, 0.3f); layerColor(tPine, c, 0.7f); canopy = 7f }
                    Biome.JUNGLE -> { layerColor(tLush, c, 0.25f); layerColor(tJungle, c, 0.75f); canopy = 9f }
                    Biome.SWAMP -> { layerColor(tMud, c, 0.5f); layerColor(tGrass, c, 0.5f); canopy = 2f }
                    Biome.MOUNTAIN -> { layerColor(tStone, c, 0.7f); layerColor(tGrass, c, 0.3f) }
                    Biome.SNOW -> layerColor(tSnow, c, 1f)
                    Biome.ROCKY -> { layerColor(tStone, c, 0.6f); layerColor(tDry, c, 0.4f) }
                    else -> { layerColor(tLush, c, 0.5f); layerColor(tOak, c, 0.5f); canopy = 6f }
                }
                if (slope > 0.9f && biome[k] != Biome.BEACH) {
                    val s = ((slope - 0.9f) * 2f).coerceIn(0f, 1f)
                    c[0] = c[0] * (1 - s) + colors[tStone * 3] * s; c[1] = c[1] * (1 - s) + colors[tStone * 3 + 1] * s; c[2] = c[2] * (1 - s) + colors[tStone * 3 + 2] * s
                    canopy *= 1f - s
                }
                // canopies read slightly darker than a lit leaf texture (self-shadowing)
                val shade = if (canopy > 0f) 0.62f + 0.2f * r else 0.9f + 0.2f * r
                c[0] *= shade; c[1] *= shade; c[2] *= shade
                y = hh - 1.2f + canopy * (0.55f + 0.45f * r)
            }
            if (y < minY) minY = y; if (y > maxY) maxY = y
            // normal from the height field (water is flat)
            var nx = 0f; var nz = 0f
            if (!water) { nx = (h[k - 1] - h[k + 1]) / (2f * STEP); nz = (h[k - n] - h[k + n]) / (2f * STEP) }
            val nl = 1f / kotlin.math.sqrt(nx * nx + 1f + nz * nz)
            bb.putFloat((wx - x0).toFloat()).putFloat(y).putFloat((wz - z0).toFloat())
            bb.put((nx * nl * 127f).toInt().toByte()).put((nl * 127f).toInt().toByte()).put((nz * nl * 127f).toInt().toByte()).put(0)
            bb.put((kotlin.math.sqrt(c[0].coerceIn(0f, 1f)) * 255f).toInt().toByte())
            bb.put((kotlin.math.sqrt(c[1].coerceIn(0f, 1f)) * 255f).toInt().toByte())
            bb.put((kotlin.math.sqrt(c[2].coerceIn(0f, 1f)) * 255f).toInt().toByte())
            bb.put(if (water) 0 else 255.toByte())
        }
        bb.flip()
        t.minY = minY; t.maxY = maxY
        return bb
    }

    override fun drawOpaque(r: WorldRenderer) {
        val cam = r.camera
        r.bindLit(shader)
        shader.set1f("uNearRadius", nearRadius)
        val loc = shader.loc("uOffset")
        val prof = engine.profiler
        tiles.forEach { t ->
            val m = t.mesh
            if (m != null) {
                val ox = t.tx * TILE - cam.pos.x; val oz = t.tz * TILE - cam.pos.z
                // skip tiles completely inside the voxel radius
                val fx = maxOf(kotlin.math.abs(ox), kotlin.math.abs(ox + TILE)); val fz = maxOf(kotlin.math.abs(oz), kotlin.math.abs(oz + TILE))
                if (fx * fx + fz * fz > nearRadius * nearRadius &&
                    cam.frustum.intersectsAabb(ox, t.minY - cam.pos.y, oz, ox + TILE, t.maxY - cam.pos.y, oz + TILE)) {
                    gl.uniform3f(loc, ox, -cam.pos.y, oz)
                    m.bind()
                    gl.drawElements(GL.TRIANGLES, CELLS * CELLS * 6, GL.UNSIGNED_SHORT, 0)
                    prof.drawCalls++
                    prof.triangles += CELLS * CELLS * 2
                }
            }
        }
    }

    fun dispose() {
        tiles.forEach { it.mesh?.dispose(); it.mesh = null }
        if (indexBuffer != 0) gl.deleteBuffer(indexBuffer)
        indexBuffer = 0
    }

    val tileCount: Int get() = tiles.size
    val busy: Boolean get() = inFlight > 0 || pending.isNotEmpty()
}
