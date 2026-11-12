package wildcore.math

import kotlin.math.sqrt

/** Mutable 3D float vector. Hot paths reuse instances to avoid garbage. */
class Vec3(@JvmField var x: Float = 0f, @JvmField var y: Float = 0f, @JvmField var z: Float = 0f) {
    fun set(nx: Float, ny: Float, nz: Float): Vec3 { x = nx; y = ny; z = nz; return this }
    fun set(o: Vec3): Vec3 { x = o.x; y = o.y; z = o.z; return this }
    fun add(o: Vec3): Vec3 { x += o.x; y += o.y; z += o.z; return this }
    fun add(ax: Float, ay: Float, az: Float): Vec3 { x += ax; y += ay; z += az; return this }
    fun addScaled(o: Vec3, s: Float): Vec3 { x += o.x * s; y += o.y * s; z += o.z * s; return this }
    fun sub(o: Vec3): Vec3 { x -= o.x; y -= o.y; z -= o.z; return this }
    fun scale(s: Float): Vec3 { x *= s; y *= s; z *= s; return this }
    fun length(): Float = sqrt(x * x + y * y + z * z)
    fun lengthSq(): Float = x * x + y * y + z * z
    fun dot(o: Vec3): Float = x * o.x + y * o.y + z * o.z
    fun normalize(): Vec3 {
        val l = length()
        if (l > 1e-8f) { x /= l; y /= l; z /= l }
        return this
    }
    fun cross(a: Vec3, b: Vec3): Vec3 {
        val cx = a.y * b.z - a.z * b.y
        val cy = a.z * b.x - a.x * b.z
        val cz = a.x * b.y - a.y * b.x
        x = cx; y = cy; z = cz
        return this
    }
    fun distance(o: Vec3): Float {
        val dx = x - o.x; val dy = y - o.y; val dz = z - o.z
        return sqrt(dx * dx + dy * dy + dz * dz)
    }
    fun copy(): Vec3 = Vec3(x, y, z)
    override fun toString(): String = "($x, $y, $z)"
}
