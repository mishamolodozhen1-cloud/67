package wildfrontier.render

import wildcore.core.Engine
import wildcore.gfx.GL
import wildcore.gfx.Mesh
import wildcore.gfx.Shader
import wildcore.gfx.Texture2D
import wildcore.math.Rng
import java.nio.ByteBuffer

/**
 * Pooled particle system drawn with instanced rendering: one static quad, one dynamic per-instance
 * buffer, one draw call for everything (rain, debris, leaves, fireflies, sparks, dropped item icons).
 * Storage is structure-of-arrays and preallocated — emitting never allocates.
 */
class Particles(private val engine: Engine, val capacity: Int) : SceneLayer {
    companion object {
        const val SOFT = 0; const val STREAK = 1; const val FRAGMENT = 2; const val GLOW = 3; const val ICON = 4
        private const val INSTANCE_BYTES = 36
    }

    private val x = FloatArray(capacity); private val y = FloatArray(capacity); private val z = FloatArray(capacity)
    private val vx = FloatArray(capacity); private val vy = FloatArray(capacity); private val vz = FloatArray(capacity)
    private val life = FloatArray(capacity); private val maxLife = FloatArray(capacity)
    private val size = FloatArray(capacity); private val gravity = FloatArray(capacity); private val drag = FloatArray(capacity)
    private val color = IntArray(capacity); private val kind = IntArray(capacity)
    private val misc = FloatArray(capacity); private val layer = FloatArray(capacity)
    private val rot = FloatArray(capacity); private val rotSpeed = FloatArray(capacity)
    var count = 0; private set
    val rng = Rng(99)

    // transient per-frame instances (item icons) appended after the pooled particles
    private val extra = FloatArray(256 * 6)
    private var extraCount = 0

    private lateinit var shader: Shader
    private var vao = 0
    private var quadVbo = 0
    private var instVbo = 0
    private val buf: ByteBuffer = Mesh.directBuffer((capacity + 256) * INSTANCE_BYTES)
    var icons: Texture2D? = null
    /** Scene light applied to non-emissive particles (set each frame). */
    var lightR = 1f; var lightG = 1f; var lightB = 1f
    var windX = 0f; var windZ = 0f

    fun init(r: WorldRenderer) {
        val gl = engine.gl
        shader = r.shaders.load("particle", "particle.vert", "particle.frag", arrayOf("aCorner", "aCenterSize", "aColor", "aMisc"))
        vao = gl.genVertexArray()
        gl.bindVertexArray(vao)
        quadVbo = gl.genBuffer()
        gl.bindBuffer(GL.ARRAY_BUFFER, quadVbo)
        val q = Mesh.directBuffer(32)
        q.asFloatBuffer().put(floatArrayOf(-1f, -1f, 1f, -1f, -1f, 1f, 1f, 1f))
        gl.bufferData(GL.ARRAY_BUFFER, 32, q, GL.STATIC_DRAW)
        gl.enableVertexAttribArray(0)
        gl.vertexAttribPointer(0, 2, GL.FLOAT, false, 8, 0)
        instVbo = gl.genBuffer()
        gl.bindBuffer(GL.ARRAY_BUFFER, instVbo)
        gl.bufferData(GL.ARRAY_BUFFER, buf.capacity(), null, GL.DYNAMIC_DRAW)
        gl.enableVertexAttribArray(1); gl.vertexAttribPointer(1, 4, GL.FLOAT, false, INSTANCE_BYTES, 0); gl.vertexAttribDivisor(1, 1)
        gl.enableVertexAttribArray(2); gl.vertexAttribPointer(2, 4, GL.UNSIGNED_BYTE, true, INSTANCE_BYTES, 16); gl.vertexAttribDivisor(2, 1)
        gl.enableVertexAttribArray(3); gl.vertexAttribPointer(3, 4, GL.FLOAT, false, INSTANCE_BYTES, 20); gl.vertexAttribDivisor(3, 1)
        gl.bindVertexArray(0)
    }

    /** Emits one particle; silently dropped when the pool is full. Colour is 0xAARRGGBB. */
    fun emit(k: Int, px: Float, py: Float, pz: Float, velX: Float, velY: Float, velZ: Float, lifeSec: Float, sz: Float, col: Int,
             grav: Float = 0f, dragK: Float = 0f, m: Float = 0f, lay: Float = 0f, spin: Float = 0f) {
        if (count >= capacity) return
        val i = count++
        kind[i] = k; x[i] = px; y[i] = py; z[i] = pz; vx[i] = velX; vy[i] = velY; vz[i] = velZ
        life[i] = lifeSec; maxLife[i] = lifeSec; size[i] = sz; color[i] = col; gravity[i] = grav; drag[i] = dragK
        misc[i] = m; layer[i] = lay; rot[i] = rng.nextFloat() * 6.28f; rotSpeed[i] = spin
    }

    /** Debris when a block is hit or broken: fragments textured with the block's own material. */
    fun blockBurst(bx: Float, by: Float, bz: Float, texLayer: Int, n: Int, spread: Float = 0.45f) {
        for (i in 0 until n) {
            emit(FRAGMENT, bx + rng.range(-spread, spread), by + rng.range(-spread, spread), bz + rng.range(-spread, spread),
                rng.range(-1.6f, 1.6f), rng.range(0.8f, 3.6f), rng.range(-1.6f, 1.6f), rng.range(0.45f, 0.9f), rng.range(0.045f, 0.085f),
                0xFFFFFFFF.toInt(), 13f, 0.4f, rng.nextFloat() * 0.85f, texLayer.toFloat(), rng.range(-6f, 6f))
        }
    }

    fun puff(px: Float, py: Float, pz: Float, n: Int, col: Int, sz: Float = 0.16f, up: Float = 0.6f) {
        for (i in 0 until n) emit(SOFT, px + rng.range(-0.25f, 0.25f), py + rng.range(-0.1f, 0.2f), pz + rng.range(-0.25f, 0.25f),
            rng.range(-0.7f, 0.7f), rng.range(0.1f, up), rng.range(-0.7f, 0.7f), rng.range(0.4f, 0.9f), sz * rng.range(0.7f, 1.4f), col, -0.3f, 1.8f)
    }

    /** Transient icon billboard for this frame only (dropped items). */
    fun icon(px: Float, py: Float, pz: Float, sz: Float, iconId: Int) {
        if (extraCount >= 256) return
        val o = extraCount * 6
        extra[o] = px; extra[o + 1] = py; extra[o + 2] = pz; extra[o + 3] = sz; extra[o + 4] = iconId.toFloat()
        extraCount++
    }

    fun update(dt: Float, groundY: (Float, Float) -> Float) {
        var i = 0
        while (i < count) {
            life[i] -= dt
            var dead = life[i] <= 0f
            if (!dead) {
                vy[i] -= gravity[i] * dt
                if (drag[i] > 0f) { val k = 1f - minOf(1f, drag[i] * dt); vx[i] *= k; vy[i] *= k; vz[i] *= k }
                x[i] += vx[i] * dt; y[i] += vy[i] * dt; z[i] += vz[i] * dt
                rot[i] += rotSpeed[i] * dt
                if (kind[i] == STREAK || kind[i] == FRAGMENT) {
                    // precipitation and debris stop at the ground
                    if (vy[i] < 0f && y[i] < groundY(x[i], z[i])) {
                        if (kind[i] == STREAK && rng.nextFloat() < 0.25f) {
                            kind[i] = SOFT; life[i] = 0.18f; maxLife[i] = 0.18f; vx[i] = 0f; vz[i] = 0f; vy[i] = 0.4f; gravity[i] = 0f
                            size[i] = 0.06f; color[i] = (color[i] and 0xFFFFFF) or 0x66000000
                        } else dead = true
                    }
                }
            }
            if (dead) {
                val l = --count
                kind[i] = kind[l]; x[i] = x[l]; y[i] = y[l]; z[i] = z[l]; vx[i] = vx[l]; vy[i] = vy[l]; vz[i] = vz[l]
                life[i] = life[l]; maxLife[i] = maxLife[l]; size[i] = size[l]; color[i] = color[l]; gravity[i] = gravity[l]; drag[i] = drag[l]
                misc[i] = misc[l]; layer[i] = layer[l]; rot[i] = rot[l]; rotSpeed[i] = rotSpeed[l]
            } else i++
        }
        engine.profiler.particles = count
    }

    override fun drawTransparent(r: WorldRenderer) {
        val n = count + extraCount
        if (n == 0) return
        val gl = engine.gl
        val cam = r.camera.pos
        buf.clear()
        for (i in 0 until count) {
            val k = kind[i]
            val t = life[i] / maxLife[i]
            val fadeIn = minOf(1f, (1f - t) * 8f)
            val a = ((color[i] ushr 24) * (if (k == FRAGMENT) minOf(1f, t * 3f) else minOf(1f, t * 2f) * fadeIn)).toInt()
            var cr = (color[i] shr 16) and 255; var cg = (color[i] shr 8) and 255; var cb = color[i] and 255
            if (k != GLOW) { cr = (cr * lightR).toInt().coerceAtMost(255); cg = (cg * lightG).toInt().coerceAtMost(255); cb = (cb * lightB).toInt().coerceAtMost(255) }
            buf.putFloat(x[i] - cam.x).putFloat(y[i] - cam.y).putFloat(z[i] - cam.z).putFloat(size[i])
            buf.put(cr.toByte()).put(cg.toByte()).put(cb.toByte()).put(a.toByte())
            buf.putFloat(k.toFloat()).putFloat(misc[i]).putFloat(layer[i]).putFloat(if (k == STREAK) windX * 0.06f else rot[i])
        }
        for (j in 0 until extraCount) {
            val o = j * 6
            buf.putFloat(extra[o] - cam.x).putFloat(extra[o + 1] - cam.y).putFloat(extra[o + 2] - cam.z).putFloat(extra[o + 3])
            buf.put((255 * minOf(1f, lightR)).toInt().toByte()).put((255 * minOf(1f, lightG)).toInt().toByte()).put((255 * minOf(1f, lightB)).toInt().toByte()).put(255.toByte())
            buf.putFloat(ICON.toFloat()).putFloat(extra[o + 4]).putFloat(0f).putFloat(0f)
        }
        extraCount = 0
        val bytes = n * INSTANCE_BYTES
        buf.position(0).limit(bytes)
        gl.bindBuffer(GL.ARRAY_BUFFER, instVbo)
        gl.bufferSubData(GL.ARRAY_BUFFER, 0, bytes, buf)
        r.bindLit(shader)
        val c = r.camera
        shader.set3f("uCamRight", c.right.x, c.right.y, c.right.z)
        // camera up = right x forward
        val ux = c.right.y * c.forward.z - c.right.z * c.forward.y
        val uy = c.right.z * c.forward.x - c.right.x * c.forward.z
        val uz = c.right.x * c.forward.y - c.right.y * c.forward.x
        shader.set3f("uCamUp", ux, uy, uz)
        shader.set1i("uAlbedo", 0)
        icons?.bind(7)
        shader.set1i("uIcons", 7)
        gl.activeTexture(GL.TEXTURE0)
        gl.disable(GL.CULL_FACE)
        gl.bindVertexArray(vao)
        gl.drawArraysInstanced(GL.TRIANGLE_STRIP, 0, 4, n)
        gl.enable(GL.CULL_FACE)
        engine.profiler.drawCalls++
        engine.profiler.triangles += n * 2
    }

    fun clear() { count = 0; extraCount = 0 }
}
