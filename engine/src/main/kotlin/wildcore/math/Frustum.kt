package wildcore.math

import kotlin.math.sqrt

/** View frustum extracted from a view-projection matrix; used for chunk and entity culling. */
class Frustum {
    private val p = FloatArray(24) // 6 planes * (a,b,c,d)

    fun setFromMatrix(m: FloatArray) {
        setPlane(0, m[3] + m[0], m[7] + m[4], m[11] + m[8], m[15] + m[12])   // left
        setPlane(1, m[3] - m[0], m[7] - m[4], m[11] - m[8], m[15] - m[12])   // right
        setPlane(2, m[3] + m[1], m[7] + m[5], m[11] + m[9], m[15] + m[13])   // bottom
        setPlane(3, m[3] - m[1], m[7] - m[5], m[11] - m[9], m[15] - m[13])   // top
        setPlane(4, m[3] + m[2], m[7] + m[6], m[11] + m[10], m[15] + m[14])  // near
        setPlane(5, m[3] - m[2], m[7] - m[6], m[11] - m[10], m[15] - m[14])  // far
    }

    private fun setPlane(i: Int, a: Float, b: Float, c: Float, d: Float) {
        val l = 1f / sqrt(a * a + b * b + c * c)
        p[i * 4] = a * l; p[i * 4 + 1] = b * l; p[i * 4 + 2] = c * l; p[i * 4 + 3] = d * l
    }

    /** Conservative AABB test: false only when the box is fully outside one plane. */
    fun intersectsAabb(minX: Float, minY: Float, minZ: Float, maxX: Float, maxY: Float, maxZ: Float): Boolean {
        for (i in 0 until 6) {
            val a = p[i * 4]; val b = p[i * 4 + 1]; val c = p[i * 4 + 2]; val d = p[i * 4 + 3]
            val x = if (a >= 0f) maxX else minX
            val y = if (b >= 0f) maxY else minY
            val z = if (c >= 0f) maxZ else minZ
            if (a * x + b * y + c * z + d < 0f) return false
        }
        return true
    }

    fun intersectsSphere(x: Float, y: Float, z: Float, r: Float): Boolean {
        for (i in 0 until 6) {
            if (p[i * 4] * x + p[i * 4 + 1] * y + p[i * 4 + 2] * z + p[i * 4 + 3] < -r) return false
        }
        return true
    }
}
