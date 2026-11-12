package wildcore.math

/**
 * Seeded gradient noise (2D/3D) with fBm and ridged helpers.
 * Implementation: classic improved Perlin noise over a seeded permutation table.
 * Output range is approximately [-1, 1].
 */
class Noise(seed: Long) {
    private val perm = IntArray(512)

    init {
        val p = IntArray(256) { it }
        val rng = Rng(seed * 6364136223846793005L + 1442695040888963407L)
        for (i in 255 downTo 1) {
            val j = rng.nextInt(i + 1)
            val t = p[i]; p[i] = p[j]; p[j] = t
        }
        for (i in 0 until 512) perm[i] = p[i and 255]
    }

    private fun fade(t: Float): Float = t * t * t * (t * (t * 6f - 15f) + 10f)

    private fun grad2(h: Int, x: Float, y: Float): Float = when (h and 7) {
        0 -> x + y; 1 -> x - y; 2 -> -x + y; 3 -> -x - y
        4 -> x; 5 -> -x; 6 -> y; else -> -y
    }

    private fun grad3(h: Int, x: Float, y: Float, z: Float): Float = when (h and 15) {
        0 -> x + y; 1 -> -x + y; 2 -> x - y; 3 -> -x - y
        4 -> x + z; 5 -> -x + z; 6 -> x - z; 7 -> -x - z
        8 -> y + z; 9 -> -y + z; 10 -> y - z; 11 -> -y - z
        12 -> y + x; 13 -> -y + z; 14 -> y - x; else -> -y - z
    }

    fun noise2(x: Float, y: Float): Float {
        val xi = floorInt(x); val yi = floorInt(y)
        val xf = x - xi; val yf = y - yi
        val X = xi and 255; val Y = yi and 255
        val u = fade(xf); val v = fade(yf)
        val aa = perm[perm[X] + Y]; val ab = perm[perm[X] + Y + 1]
        val ba = perm[perm[X + 1] + Y]; val bb = perm[perm[X + 1] + Y + 1]
        val x1 = lerp(grad2(aa, xf, yf), grad2(ba, xf - 1f, yf), u)
        val x2 = lerp(grad2(ab, xf, yf - 1f), grad2(bb, xf - 1f, yf - 1f), u)
        return lerp(x1, x2, v) * 0.7071f * 1.6f
    }

    fun noise3(x: Float, y: Float, z: Float): Float {
        val xi = floorInt(x); val yi = floorInt(y); val zi = floorInt(z)
        val xf = x - xi; val yf = y - yi; val zf = z - zi
        val X = xi and 255; val Y = yi and 255; val Z = zi and 255
        val u = fade(xf); val v = fade(yf); val w = fade(zf)
        val a = perm[X] + Y; val aa = perm[a] + Z; val ab = perm[a + 1] + Z
        val b = perm[X + 1] + Y; val ba = perm[b] + Z; val bb = perm[b + 1] + Z
        val x1 = lerp(grad3(perm[aa], xf, yf, zf), grad3(perm[ba], xf - 1f, yf, zf), u)
        val x2 = lerp(grad3(perm[ab], xf, yf - 1f, zf), grad3(perm[bb], xf - 1f, yf - 1f, zf), u)
        val y1 = lerp(x1, x2, v)
        val x3 = lerp(grad3(perm[aa + 1], xf, yf, zf - 1f), grad3(perm[ba + 1], xf - 1f, yf, zf - 1f), u)
        val x4 = lerp(grad3(perm[ab + 1], xf, yf - 1f, zf - 1f), grad3(perm[bb + 1], xf - 1f, yf - 1f, zf - 1f), u)
        val y2 = lerp(x3, x4, v)
        return lerp(y1, y2, w)
    }

    /** Fractal Brownian motion, normalized to roughly [-1,1]. */
    fun fbm2(x: Float, y: Float, octaves: Int, lacunarity: Float = 2f, gain: Float = 0.5f): Float {
        var sum = 0f; var amp = 1f; var freq = 1f; var norm = 0f
        for (i in 0 until octaves) {
            sum += noise2(x * freq + i * 17.3f, y * freq - i * 9.1f) * amp
            norm += amp
            amp *= gain; freq *= lacunarity
        }
        return sum / norm
    }

    /** Ridged multifractal in [0,1]: sharp crests, good for mountain ranges. */
    fun ridged2(x: Float, y: Float, octaves: Int): Float {
        var sum = 0f; var amp = 1f; var freq = 1f; var norm = 0f
        for (i in 0 until octaves) {
            var n = 1f - kotlin.math.abs(noise2(x * freq + i * 31.7f, y * freq + i * 11.9f))
            n *= n
            sum += n * amp
            norm += amp
            amp *= 0.5f; freq *= 2f
        }
        return sum / norm
    }
}
