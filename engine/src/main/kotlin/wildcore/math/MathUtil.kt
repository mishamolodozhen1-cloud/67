package wildcore.math

import kotlin.math.floor

const val PI_F = 3.14159265f
const val TAU_F = 6.2831853f
const val DEG2RAD = PI_F / 180f

fun clamp(v: Float, lo: Float, hi: Float): Float = if (v < lo) lo else if (v > hi) hi else v
fun clamp(v: Int, lo: Int, hi: Int): Int = if (v < lo) lo else if (v > hi) hi else v
fun saturate(v: Float): Float = if (v < 0f) 0f else if (v > 1f) 1f else v
fun lerp(a: Float, b: Float, t: Float): Float = a + (b - a) * t
fun smoothstep(e0: Float, e1: Float, x: Float): Float {
    val t = saturate((x - e0) / (e1 - e0))
    return t * t * (3f - 2f * t)
}
fun floorInt(v: Float): Int { val i = v.toInt(); return if (v < i) i - 1 else i }
fun floorInt(v: Double): Int = floor(v).toInt()
fun fract(v: Float): Float = v - floorInt(v)

/** Shortest signed angular difference b-a in radians, in (-PI, PI]. */
fun angleDelta(a: Float, b: Float): Float {
    var d = (b - a) % TAU_F
    if (d > PI_F) d -= TAU_F
    if (d < -PI_F) d += TAU_F
    return d
}
fun approach(cur: Float, target: Float, maxStep: Float): Float =
    if (cur < target) minOf(cur + maxStep, target) else maxOf(cur - maxStep, target)

/** Fast integer hashing used for deterministic world decoration. */
object Hash {
    fun hash2(x: Int, y: Int, seed: Int): Int {
        var h = seed xor (x * 374761393) xor (y * 668265263)
        h = (h xor (h ushr 13)) * 1274126177
        h = h xor (h ushr 16)
        return h
    }
    fun hash3(x: Int, y: Int, z: Int, seed: Int): Int {
        var h = seed xor (x * 374761393) xor (y * 668265263) xor (z * 1440662683)
        h = (h xor (h ushr 13)) * 1274126177
        h = h xor (h ushr 16)
        return h
    }
    /** Uniform float in [0,1). */
    fun f2(x: Int, y: Int, seed: Int): Float = (hash2(x, y, seed) and 0xFFFFFF) / 16777216f
    fun f3(x: Int, y: Int, z: Int, seed: Int): Float = (hash3(x, y, z, seed) and 0xFFFFFF) / 16777216f
}

/** Small deterministic PRNG (xorshift) with no allocation. */
class Rng(seed: Long) {
    private var s: Long = if (seed == 0L) 0x9E3779B97F4A7C15uL.toLong() else seed
    fun nextLong(): Long {
        var x = s
        x = x xor (x shl 13); x = x xor (x ushr 7); x = x xor (x shl 17)
        s = x
        return x
    }
    fun nextInt(bound: Int): Int = ((nextLong() ushr 33) % bound).toInt()
    fun nextFloat(): Float = ((nextLong() ushr 40).toInt() and 0xFFFFFF) / 16777216f
    fun range(lo: Float, hi: Float): Float = lo + (hi - lo) * nextFloat()
    fun chance(p: Float): Boolean = nextFloat() < p
}
