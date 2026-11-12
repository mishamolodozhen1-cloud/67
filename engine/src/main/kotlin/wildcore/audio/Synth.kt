package wildcore.audio

import wildcore.math.Rng
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.exp
import kotlin.math.pow
import kotlin.math.sin

/**
 * Procedural sound design toolkit: every sound effect, ambience loop and the music bed of the game is
 * synthesized at start-up from oscillators, filtered noise and envelopes (no audio files shipped).
 */
class Synth(seed: Long = 42L) {
    private val rng = Rng(seed)
    val rate = AudioMixer.SOURCE_RATE

    fun buffer(seconds: Float) = FloatArray((seconds * rate).toInt())

    fun noise(): Float = rng.nextFloat() * 2f - 1f

    /** One-pole low-pass in place. */
    fun lowpass(b: FloatArray, cutoffHz: Float) {
        val a = 1f - exp(-2f * PI.toFloat() * cutoffHz / rate)
        var y = 0f
        for (i in b.indices) { y += (b[i] - y) * a; b[i] = y }
    }

    fun highpass(b: FloatArray, cutoffHz: Float) {
        val a = 1f - exp(-2f * PI.toFloat() * cutoffHz / rate)
        var y = 0f
        for (i in b.indices) { y += (b[i] - y) * a; b[i] -= y }
    }

    /** Low-pass whose cutoff follows [cutoff] (Hz per sample index fraction 0..1). */
    fun sweepLowpass(b: FloatArray, cutoff: (Float) -> Float) {
        var y = 0f
        for (i in b.indices) {
            val a = 1f - exp(-2f * PI.toFloat() * cutoff(i.toFloat() / b.size) / rate)
            y += (b[i] - y) * a; b[i] = y
        }
    }

    fun fillNoise(b: FloatArray, amp: Float = 1f) { for (i in b.indices) b[i] = noise() * amp }

    /** Adds a tone whose frequency follows [freq](t01) with amplitude envelope [env](t01). */
    fun tone(b: FloatArray, start: Int, length: Int, freq: (Float) -> Float, env: (Float) -> Float, harmonics: FloatArray = floatArrayOf(1f)) {
        var phase = 0.0
        for (i in 0 until length) {
            val idx = start + i
            if (idx >= b.size) break
            val t = i.toFloat() / length
            phase += 2.0 * PI * freq(t) / rate
            var s = 0f
            for (h in harmonics.indices) s += sin(phase * (h + 1)).toFloat() * harmonics[h]
            b[idx] += s * env(t)
        }
    }

    /** Percussive decay envelope with a short attack. */
    fun perc(t: Float, attack: Float = 0.02f, decay: Float = 6f): Float =
        (if (t < attack) t / attack else 1f) * exp(-decay * t)

    fun mix(dst: FloatArray, src: FloatArray, at: Int, gain: Float = 1f) {
        for (i in src.indices) { val j = at + i; if (j >= dst.size) break; dst[j] += src[i] * gain }
    }

    /** Makes a buffer loop seamlessly by cross-fading its tail into its head. */
    fun makeLoop(b: FloatArray, fadeSeconds: Float): FloatArray {
        val f = (fadeSeconds * rate).toInt().coerceAtMost(b.size / 2)
        val out = FloatArray(b.size - f)
        for (i in out.indices) out[i] = b[i]
        for (i in 0 until f) {
            val k = i.toFloat() / f
            out[i] = b[i] * k + b[b.size - f + i] * (1f - k)
        }
        return out
    }

    fun normalize(b: FloatArray, peak: Float = 0.9f) {
        var m = 0f
        for (v in b) { val a = abs(v); if (a > m) m = a }
        if (m > 1e-6f) { val k = peak / m; for (i in b.indices) b[i] *= k }
    }

    fun toSound(b: FloatArray, loop: Boolean = false, peak: Float = 0.9f): Sound {
        normalize(b, peak)
        val s = ShortArray(b.size)
        for (i in b.indices) s[i] = (b[i] * 32767f).toInt().coerceIn(-32767, 32767).toShort()
        return Sound(s, loop)
    }

    // ------------------------------------------------------------------ recipes

    fun noiseBurst(seconds: Float, lp: Float, hp: Float, decay: Float, attack: Float = 0.01f): FloatArray {
        val b = buffer(seconds)
        fillNoise(b)
        if (lp > 0f) lowpass(b, lp)
        if (hp > 0f) highpass(b, hp)
        for (i in b.indices) b[i] *= perc(i.toFloat() / b.size, attack, decay)
        return b
    }

    fun thud(seconds: Float, f0: Float, f1: Float, decay: Float): FloatArray {
        val b = buffer(seconds)
        tone(b, 0, b.size, { t -> f0 + (f1 - f0) * t }, { t -> perc(t, 0.01f, decay) }, floatArrayOf(1f, 0.4f))
        return b
    }

    fun rangeF(lo: Float, hi: Float) = rng.range(lo, hi)
    fun chance(p: Float) = rng.chance(p)
    fun pow2(semitones: Float): Float = 2f.pow(semitones / 12f)
}
