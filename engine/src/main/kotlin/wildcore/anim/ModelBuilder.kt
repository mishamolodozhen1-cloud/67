package wildcore.anim

import wildcore.gfx.GL
import wildcore.gfx.Mesh
import wildcore.gfx.VertexAttrib
import wildcore.gfx.VertexLayout
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt

/** CPU-side skinned mesh (kept so GPU buffers can be rebuilt after a context loss). */
class SkinnedMeshData(val vertices: java.nio.ByteBuffer, val vertexCount: Int, val indices: java.nio.ByteBuffer, val indexCount: Int,
                      val minY: Float, val maxY: Float, val radius: Float)

class SkinnedMesh(gl: GL, val data: SkinnedMeshData) {
    companion object {
        const val STRIDE = 28
        val LAYOUT = VertexLayout(STRIDE, arrayOf(
            VertexAttrib(0, 3, GL.FLOAT, false, 0),
            VertexAttrib(1, 4, GL.BYTE, true, 12),
            VertexAttrib(2, 4, GL.UNSIGNED_BYTE, true, 16),
            VertexAttrib(3, 4, GL.UNSIGNED_BYTE, false, 20),
            VertexAttrib(4, 4, GL.UNSIGNED_BYTE, true, 24)))
    }
    val mesh = Mesh(gl, LAYOUT)
    val triangles: Int get() = data.indexCount / 3

    init {
        data.vertices.position(0); data.indices.position(0)
        mesh.setVertices(data.vertices, data.vertexCount * STRIDE)
        mesh.setIndices(data.indices, data.indexCount, GL.UNSIGNED_SHORT)
    }
    fun draw() = mesh.draw()
    fun dispose() = mesh.dispose()
}

/** One cross-section of a lofted tube. */
class Ring(
    val x: Float, val y: Float, val z: Float,
    val rx: Float, val ry: Float,
    val boneA: Int, val boneB: Int = boneA, val weightA: Float = 1f,
    val colorTop: Int, val colorBottom: Int = colorTop,
)

/**
 * Builds organic skinned meshes from lofted tubes and ellipsoids. Smooth normals are computed from
 * the finished geometry, so shapes shade as continuous surfaces instead of faceted primitives.
 * Colours are 0xRRGGBB; the vertex alpha channel carries a "fur detail" amount for the shader.
 */
class ModelBuilder {
    private var px = FloatArray(1024); private var py = FloatArray(1024); private var pz = FloatArray(1024)
    private var nx = FloatArray(1024); private var ny = FloatArray(1024); private var nz = FloatArray(1024)
    private var col = IntArray(1024); private var bone = IntArray(1024); private var wgt = FloatArray(1024)
    private var vcount = 0
    private var idx = ShortArray(4096)
    private var icount = 0
    var detail = 200   // 0..255 fur/cloth noise strength written to vertex alpha

    private fun vertex(x: Float, y: Float, z: Float, color: Int, bA: Int, bB: Int, wA: Float): Int {
        if (vcount == px.size) {
            val n = vcount * 2
            px = px.copyOf(n); py = py.copyOf(n); pz = pz.copyOf(n); nx = nx.copyOf(n); ny = ny.copyOf(n); nz = nz.copyOf(n)
            col = col.copyOf(n); bone = bone.copyOf(n); wgt = wgt.copyOf(n)
        }
        px[vcount] = x; py[vcount] = y; pz[vcount] = z
        col[vcount] = (color and 0xFFFFFF) or (detail shl 24)
        bone[vcount] = bA or (bB shl 8); wgt[vcount] = wA
        return vcount++
    }

    private fun tri(a: Int, b: Int, c: Int) {
        if (icount + 3 > idx.size) idx = idx.copyOf(idx.size * 2)
        idx[icount++] = a.toShort(); idx[icount++] = b.toShort(); idx[icount++] = c.toShort()
    }

    private fun mixColor(a: Int, b: Int, t: Float): Int {
        val r = ((a shr 16 and 255) * (1 - t) + (b shr 16 and 255) * t).toInt()
        val g = ((a shr 8 and 255) * (1 - t) + (b shr 8 and 255) * t).toInt()
        val bl = ((a and 255) * (1 - t) + (b and 255) * t).toInt()
        return (r shl 16) or (g shl 8) or bl
    }

    /** Lofts a closed tube through the rings. Ring planes follow the path direction; ends are capped. */
    fun tube(rings: List<Ring>, segments: Int = 8, capStart: Boolean = true, capEnd: Boolean = true) {
        val base = vcount
        val n = rings.size
        for (i in 0 until n) {
            val r = rings[i]
            val a = rings[maxOf(i - 1, 0)]; val b = rings[minOf(i + 1, n - 1)]
            var tx = b.x - a.x; var ty = b.y - a.y; var tz = b.z - a.z
            val tl = sqrt(tx * tx + ty * ty + tz * tz).coerceAtLeast(1e-5f); tx /= tl; ty /= tl; tz /= tl
            // side = ref x tangent, up = tangent x side
            val refX: Float; val refY: Float; val refZ: Float
            if (kotlin.math.abs(ty) > 0.85f) { refX = 0f; refY = 0f; refZ = if (ty > 0f) -1f else 1f } else { refX = 0f; refY = 1f; refZ = 0f }
            var sx = refY * tz - refZ * ty; var sy = refZ * tx - refX * tz; var sz = refX * ty - refY * tx
            val sl = sqrt(sx * sx + sy * sy + sz * sz).coerceAtLeast(1e-5f); sx /= sl; sy /= sl; sz /= sl
            val ux = ty * sz - tz * sy; val uy = tz * sx - tx * sz; val uz = tx * sy - ty * sx
            for (k in 0 until segments) {
                val ang = k * 6.2831853f / segments
                val c = cos(ang); val s = sin(ang)
                val color = mixColor(r.colorBottom, r.colorTop, s * 0.5f + 0.5f)
                vertex(r.x + sx * c * r.rx + ux * s * r.ry, r.y + sy * c * r.rx + uy * s * r.ry, r.z + sz * c * r.rx + uz * s * r.ry,
                    color, r.boneA, r.boneB, r.weightA)
            }
        }
        for (i in 0 until n - 1) for (k in 0 until segments) {
            val a = base + i * segments + k; val b = base + i * segments + (k + 1) % segments
            val c = a + segments; val d = b + segments
            tri(a, b, c); tri(b, d, c)
        }
        if (capStart) cap(rings[0], base, segments, true)
        if (capEnd) cap(rings[n - 1], base + (n - 1) * segments, segments, false)
    }

    private fun cap(r: Ring, ringBase: Int, segments: Int, start: Boolean) {
        val c = vertex(r.x, r.y, r.z, mixColor(r.colorBottom, r.colorTop, 0.5f), r.boneA, r.boneB, r.weightA)
        for (k in 0 until segments) {
            val a = ringBase + k; val b = ringBase + (k + 1) % segments
            if (start) tri(c, b, a) else tri(c, a, b)
        }
    }

    fun ellipsoid(cx: Float, cy: Float, cz: Float, rx: Float, ry: Float, rz: Float, bone: Int, color: Int, colorBottom: Int = color, lat: Int = 5, lon: Int = 8) {
        val base = vcount
        for (i in 0..lat) {
            val v = i.toFloat() / lat
            val phi = v * 3.14159265f
            for (k in 0 until lon) {
                val th = k * 6.2831853f / lon
                val sy = cos(phi)
                vertex(cx + sin(phi) * cos(th) * rx, cy + sy * ry, cz + sin(phi) * sin(th) * rz, mixColor(colorBottom, color, sy * 0.5f + 0.5f), bone, bone, 1f)
            }
        }
        for (i in 0 until lat) for (k in 0 until lon) {
            val a = base + i * lon + k; val b = base + i * lon + (k + 1) % lon
            val c = a + lon; val d = b + lon
            tri(a, b, c); tri(b, d, c)
        }
    }

    /** Axis-aligned box (hard-edged accessories such as a backpack). */
    fun box(x0: Float, y0: Float, z0: Float, x1: Float, y1: Float, z1: Float, bone: Int, color: Int) {
        val xs = floatArrayOf(x0, x1); val ys = floatArrayOf(y0, y1); val zs = floatArrayOf(z0, z1)
        fun face(ax: Int, side: Int) {
            val b = vcount
            for (j in 0..1) for (i in 0..1) {
                val p = FloatArray(3)
                p[ax] = if (ax == 0) xs[side] else if (ax == 1) ys[side] else zs[side]
                val u = (ax + 1) % 3; val v = (ax + 2) % 3
                p[u] = if (u == 0) xs[i] else if (u == 1) ys[i] else zs[i]
                p[v] = if (v == 0) xs[j] else if (v == 1) ys[j] else zs[j]
                vertex(p[0], p[1], p[2], color, bone, bone, 1f)
            }
            if (side == 1) { tri(b, b + 1, b + 3); tri(b, b + 3, b + 2) } else { tri(b, b + 3, b + 1); tri(b, b + 2, b + 3) }
        }
        for (ax in 0..2) { face(ax, 0); face(ax, 1) }
    }

    private fun computeNormals() {
        java.util.Arrays.fill(nx, 0, vcount, 0f); java.util.Arrays.fill(ny, 0, vcount, 0f); java.util.Arrays.fill(nz, 0, vcount, 0f)
        var i = 0
        while (i < icount) {
            val a = idx[i].toInt() and 0xFFFF; val b = idx[i + 1].toInt() and 0xFFFF; val c = idx[i + 2].toInt() and 0xFFFF
            val e1x = px[b] - px[a]; val e1y = py[b] - py[a]; val e1z = pz[b] - pz[a]
            val e2x = px[c] - px[a]; val e2y = py[c] - py[a]; val e2z = pz[c] - pz[a]
            val fx = e1y * e2z - e1z * e2y; val fy = e1z * e2x - e1x * e2z; val fz = e1x * e2y - e1y * e2x
            nx[a] += fx; ny[a] += fy; nz[a] += fz
            nx[b] += fx; ny[b] += fy; nz[b] += fz
            nx[c] += fx; ny[c] += fy; nz[c] += fz
            i += 3
        }
        for (v in 0 until vcount) {
            val l = sqrt(nx[v] * nx[v] + ny[v] * ny[v] + nz[v] * nz[v]).coerceAtLeast(1e-6f)
            nx[v] /= l; ny[v] /= l; nz[v] /= l
        }
    }

    /** Makes triangles face outward relative to their part (flips those whose normal points at the centroid). */
    fun build(): SkinnedMeshData {
        require(vcount < 65536) { "skinned mesh too large" }
        computeNormals()
        val vb = Mesh.directBuffer(vcount * SkinnedMesh.STRIDE)
        var minY = 1e9f; var maxY = -1e9f; var rad = 0f
        for (v in 0 until vcount) {
            vb.putFloat(px[v]).putFloat(py[v]).putFloat(pz[v])
            vb.put((nx[v] * 127f).toInt().toByte()).put((ny[v] * 127f).toInt().toByte()).put((nz[v] * 127f).toInt().toByte()).put(0)
            val c = col[v]
            vb.put((c shr 16).toByte()).put((c shr 8).toByte()).put(c.toByte()).put((c ushr 24).toByte())
            vb.put((bone[v] and 255).toByte()).put((bone[v] shr 8 and 255).toByte()).put(0).put(0)
            val wa = (wgt[v] * 255f + 0.5f).toInt().coerceIn(0, 255)
            vb.put(wa.toByte()).put((255 - wa).toByte()).put(0).put(0)
            if (py[v] < minY) minY = py[v]; if (py[v] > maxY) maxY = py[v]
            val r = sqrt(px[v] * px[v] + pz[v] * pz[v]); if (r > rad) rad = r
        }
        vb.flip()
        val ib = Mesh.directBuffer(icount * 2)
        ib.asShortBuffer().put(idx, 0, icount)
        return SkinnedMeshData(vb, vcount, ib, icount, minY, maxY, rad)
    }
}
