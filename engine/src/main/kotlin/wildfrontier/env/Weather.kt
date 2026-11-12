package wildfrontier.env

import wildcore.math.Rng
import wildcore.math.approach
import kotlin.math.cos
import kotlin.math.sin

/**
 * Dynamic weather: a small Markov chain over weather types whose parameters (cloud cover, rain,
 * fog, wind) are interpolated smoothly, plus thunderstorm lightning.
 */
class Weather(seed: Long) {
    companion object {
        const val CLEAR = 0; const val CLOUDY = 1; const val RAIN = 2; const val HEAVY_RAIN = 3; const val STORM = 4; const val FOG = 5
        val NAMES = arrayOf("Ясно", "Облачно", "Дождь", "Ливень", "Гроза", "Туман")
        val ICONS = arrayOf("ui_sun", "ui_cloud", "ui_rain", "ui_rain", "ui_storm", "ui_fog")
        //                       cover  overcast rain  fog   wind
        private val CLOUD = floatArrayOf(0.30f, 0.62f, 0.85f, 0.97f, 1.0f, 0.55f)
        private val OVERCAST = floatArrayOf(0.0f, 0.35f, 0.75f, 0.95f, 1.0f, 0.55f)
        private val RAIN_I = floatArrayOf(0f, 0f, 0.45f, 1.0f, 0.9f, 0f)
        private val FOG_I = floatArrayOf(0f, 0.03f, 0.12f, 0.30f, 0.25f, 1.0f)
        private val WIND = floatArrayOf(0.7f, 1.0f, 1.3f, 1.9f, 2.4f, 0.3f)
        // transition weights from each type
        private val NEXT = arrayOf(
            floatArrayOf(0.30f, 0.50f, 0.05f, 0.00f, 0.00f, 0.15f),
            floatArrayOf(0.40f, 0.15f, 0.30f, 0.05f, 0.03f, 0.07f),
            floatArrayOf(0.10f, 0.40f, 0.15f, 0.25f, 0.10f, 0.00f),
            floatArrayOf(0.00f, 0.25f, 0.40f, 0.10f, 0.25f, 0.00f),
            floatArrayOf(0.00f, 0.20f, 0.45f, 0.35f, 0.00f, 0.00f),
            floatArrayOf(0.55f, 0.40f, 0.05f, 0.00f, 0.00f, 0.00f))
    }

    private val rng = Rng(seed xor 0x77EA7)
    var type = CLEAR
    var timeLeft = 240f
    var cloudCover = 0.3f; private set
    var overcast = 0f; private set
    var rain = 0f; private set
    var fog = 0f; private set
    var wind = 0.7f; private set
    var windAngle = 0.6f; private set
    var gust = 1f; private set
    var wetness = 0f; private set
    var lightning = 0f; private set
    /** Seconds until the thunder of the last flash is heard; < 0 when none pending. */
    var thunderIn = -1f; private set
    var thunderNow = false; private set
    private var flashTimer = 8f
    private var time = 0f

    val isRaining: Boolean get() = rain > 0.15f
    val windX: Float get() = cos(windAngle)
    val windZ: Float get() = sin(windAngle)

    fun set(t: Int, duration: Float = 200f) { type = t; timeLeft = duration }

    fun update(dt: Float) {
        time += dt
        timeLeft -= dt
        if (timeLeft <= 0f) {
            val w = NEXT[type]
            var r = rng.nextFloat()
            var n = 0
            while (n < w.size - 1 && r > w[n]) { r -= w[n]; n++ }
            type = n
            timeLeft = when (n) { CLEAR -> rng.range(260f, 620f); CLOUDY -> rng.range(180f, 420f); FOG -> rng.range(120f, 260f); STORM -> rng.range(90f, 200f); else -> rng.range(120f, 320f) }
        }
        val k = dt * 0.035f
        cloudCover = approach(cloudCover, CLOUD[type], k)
        overcast = approach(overcast, OVERCAST[type], k)
        rain = approach(rain, RAIN_I[type], dt * 0.05f)
        fog = approach(fog, FOG_I[type], dt * 0.03f)
        wind = approach(wind, WIND[type], dt * 0.08f)
        windAngle += dt * 0.004f * sin(time * 0.013f)
        gust = 1f + 0.45f * sin(time * 0.7f) * sin(time * 0.23f + 1.3f)
        wetness = if (rain > 0.1f) minOf(1f, wetness + dt * 0.03f * rain) else maxOf(0f, wetness - dt * 0.006f)

        // lightning
        thunderNow = false
        lightning = maxOf(0f, lightning - dt * 5f)
        if (thunderIn >= 0f) { thunderIn -= dt; if (thunderIn < 0f) thunderNow = true }
        if (type == STORM && rain > 0.5f) {
            flashTimer -= dt
            if (flashTimer <= 0f) {
                flashTimer = rng.range(5f, 16f)
                lightning = rng.range(0.7f, 1.3f)
                thunderIn = rng.range(0.4f, 3.2f)
            }
        }
    }
}
