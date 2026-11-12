package wildfrontier.env

import wildcore.math.PI_F
import wildcore.math.Vec3
import wildcore.math.lerp
import wildcore.math.smoothstep
import wildfrontier.render.Env
import kotlin.math.cos
import kotlin.math.sin

/** Game clock + sun/moon/sky model. One in-game day lasts [DAY_SECONDS] real seconds. */
class DayNight {
    companion object { const val DAY_SECONDS = 1200f }

    /** Hours, 0..24. Start a little after sunrise. */
    var hour = 8.0f
    var day = 1
    private val t = Vec3()

    fun update(dt: Float, timeScale: Float = 1f) {
        hour += dt * timeScale * 24f / DAY_SECONDS
        while (hour >= 24f) { hour -= 24f; day++ }
    }

    val isNight: Boolean get() = hour < 5.5f || hour > 19.5f

    private fun mix3(out: Vec3, ax: Float, ay: Float, az: Float, bx: Float, by: Float, bz: Float, k: Float) {
        out.set(lerp(ax, bx, k), lerp(ay, by, k), lerp(az, bz, k))
    }

    /** Writes the lighting state for the current time; [overcast] 0..1 and [fogBoost] come from the weather. */
    fun apply(env: Env, overcast: Float, fogBoost: Float, farDistance: Float) {
        val a = (hour - 6f) / 12f * PI_F
        env.sunDir.set(cos(a), sin(a), 0.38f).normalize()
        env.moonDir.set(-cos(a), -sin(a) * 0.9f, -0.3f).normalize()
        val e = env.sunDir.y
        val dayK = smoothstep(-0.10f, 0.22f, e)             // 0 night .. 1 day
        val lowSun = (1f - smoothstep(0.0f, 0.42f, kotlin.math.abs(e))) * smoothstep(-0.2f, -0.02f, e)
        env.daylight = dayK

        // key light
        val sunI = smoothstep(-0.03f, 0.14f, e)
        if (sunI > 0.02f) {
            env.keyDir.set(env.sunDir)
            mix3(env.keyColor, 1.0f, 0.95f, 0.86f, 1.0f, 0.52f, 0.24f, lowSun)
            env.keyColor.scale(1.75f * sunI * (1f - 0.85f * overcast))
        } else {
            env.keyDir.set(env.moonDir)
            if (env.keyDir.y < 0.1f) { env.keyDir.y = 0.1f; env.keyDir.normalize() }
            val moonI = smoothstep(-0.05f, 0.2f, env.moonDir.y)
            env.keyColor.set(0.20f, 0.27f, 0.42f).scale(0.16f * moonI * (1f - 0.7f * overcast) * (1f - sunI * 40f).coerceAtLeast(0f))
        }

        // sky gradient
        mix3(env.skyZenith, 0.0035f, 0.006f, 0.016f, 0.07f, 0.20f, 0.52f, dayK)
        mix3(env.skyHorizon, 0.010f, 0.016f, 0.032f, 0.36f, 0.52f, 0.74f, dayK)
        mix3(t, env.skyHorizon.x, env.skyHorizon.y, env.skyHorizon.z, 0.95f, 0.46f, 0.20f, lowSun * 0.85f); env.skyHorizon.set(t)
        mix3(t, env.skyZenith.x, env.skyZenith.y, env.skyZenith.z, 0.10f, 0.14f, 0.34f, lowSun * 0.6f); env.skyZenith.set(t)
        mix3(env.sunGlow, 0.9f, 0.75f, 0.5f, 1.5f, 0.55f, 0.15f, lowSun)
        env.sunGlow.scale(smoothstep(-0.25f, 0.05f, e) * (1f - overcast))

        // overcast: grey out and darken
        val g = (env.skyHorizon.x + env.skyHorizon.y + env.skyHorizon.z) / 3f * 0.72f
        mix3(t, env.skyHorizon.x, env.skyHorizon.y, env.skyHorizon.z, g, g * 1.02f, g * 1.06f, overcast * 0.9f); env.skyHorizon.set(t)
        mix3(t, env.skyZenith.x, env.skyZenith.y, env.skyZenith.z, g * 0.6f, g * 0.63f, g * 0.68f, overcast * 0.9f); env.skyZenith.set(t)

        // ambient follows the sky
        env.ambientSky.set(env.skyZenith).scale(0.5f).addScaled(env.skyHorizon, 0.5f).scale(0.62f - 0.12f * overcast)
        env.ambientSky.add(0.006f, 0.008f, 0.014f)
        env.ambientGround.set(env.ambientSky).scale(0.42f)
        env.ambientGround.x *= 1.08f; env.ambientGround.z *= 0.86f

        env.stars = (1f - dayK) * (1f - overcast)
        env.exposure = lerp(2.3f, 1.0f, dayK)
        env.fogDensity = (2.1f / farDistance) * (1f + fogBoost * 5f + overcast * 0.6f)
        env.fogTint.set(1f, 1f, 1f)
    }
}
