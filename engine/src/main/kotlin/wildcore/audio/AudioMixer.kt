package wildcore.audio

/** Mono PCM clip at [AudioMixer.SOURCE_RATE]. */
class Sound(val data: ShortArray, val loop: Boolean = false) {
    val seconds: Float get() = data.size.toFloat() / AudioMixer.SOURCE_RATE
}

/**
 * Software mixer: up to [VOICES] simultaneous voices with per-voice gain, stereo pan and pitch,
 * smoothed gain changes (no clicks) and a soft limiter. Fully testable on the JVM; the host only
 * provides a sink that pulls interleaved stereo frames from [render].
 */
class AudioMixer : AudioSource {
    companion object {
        const val SOURCE_RATE = 22050
        const val OUTPUT_RATE = 44100
        const val VOICES = 24
    }

    private class Voice {
        var sound: Sound? = null
        var pos = 0.0
        var step = 0.5
        var gainL = 0f; var gainR = 0f
        var targetL = 0f; var targetR = 0f
        var loop = false
        var handle = 0
        var stopping = false
    }

    override val sampleRate: Int = OUTPUT_RATE
    private val voices = Array(VOICES) { Voice() }
    private val lock = Any()
    private var nextHandle = 1
    private var mixL = IntArray(2048)
    private var mixR = IntArray(2048)
    @Volatile var masterVolume = 1f
    var activeVoices = 0; private set

    private fun gains(volume: Float, pan: Float, out: FloatArray) {
        val p = pan.coerceIn(-1f, 1f)
        out[0] = volume * (if (p > 0f) 1f - p * 0.75f else 1f)
        out[1] = volume * (if (p < 0f) 1f + p * 0.75f else 1f)
    }
    private val g = FloatArray(2)

    /** Starts a voice and returns its handle (0 if nothing could be played). */
    fun play(sound: Sound, volume: Float, pan: Float = 0f, pitch: Float = 1f, loop: Boolean = sound.loop, fadeIn: Boolean = false): Int {
        if (volume <= 0.0005f && !loop) return 0
        synchronized(lock) {
            var v: Voice? = null
            for (c in voices) if (c.sound == null) { v = c; break }
            if (v == null) {
                // steal the quietest non-looping voice
                var best = Float.MAX_VALUE
                for (c in voices) if (!c.loop && c.gainL + c.gainR < best) { best = c.gainL + c.gainR; v = c }
            }
            val voice = v ?: return 0
            gains(volume, pan, g)
            voice.sound = sound; voice.pos = 0.0
            voice.step = pitch.toDouble() * SOURCE_RATE / OUTPUT_RATE
            voice.targetL = g[0]; voice.targetR = g[1]
            voice.gainL = if (fadeIn) 0f else g[0]; voice.gainR = if (fadeIn) 0f else g[1]
            voice.loop = loop; voice.stopping = false
            voice.handle = nextHandle++
            if (nextHandle == Int.MAX_VALUE) nextHandle = 1
            return voice.handle
        }
    }

    fun setVolume(handle: Int, volume: Float, pan: Float = 0f) {
        if (handle == 0) return
        synchronized(lock) {
            for (v in voices) if (v.handle == handle && v.sound != null) { gains(volume, pan, g); v.targetL = g[0]; v.targetR = g[1] }
        }
    }

    fun setPitch(handle: Int, pitch: Float) {
        if (handle == 0) return
        synchronized(lock) { for (v in voices) if (v.handle == handle && v.sound != null) v.step = pitch.toDouble() * SOURCE_RATE / OUTPUT_RATE }
    }

    /** Fades the voice out and frees it. */
    fun stop(handle: Int) {
        if (handle == 0) return
        synchronized(lock) { for (v in voices) if (v.handle == handle) { v.stopping = true; v.targetL = 0f; v.targetR = 0f } }
    }

    fun stopAll() { synchronized(lock) { for (v in voices) { v.sound = null; v.handle = 0 } } }

    override fun render(out: ShortArray, frames: Int) {
        if (mixL.size < frames) { mixL = IntArray(frames); mixR = IntArray(frames) }
        java.util.Arrays.fill(mixL, 0, frames, 0); java.util.Arrays.fill(mixR, 0, frames, 0)
        var active = 0
        synchronized(lock) {
            for (v in voices) {
                val s = v.sound ?: continue
                active++
                val d = s.data
                val n = d.size
                var pos = v.pos
                val step = v.step
                var gl = v.gainL; var gr = v.gainR
                // ~12 ms gain smoothing
                val k = 1f / (OUTPUT_RATE * 0.012f)
                var ended = false
                for (i in 0 until frames) {
                    var ip = pos.toInt()
                    if (ip >= n - 1) {
                        if (v.loop) { pos -= (n - 1); ip = pos.toInt().coerceIn(0, n - 2) } else { ended = true; break }
                    }
                    val f = (pos - ip).toFloat()
                    val smp = d[ip] + (d[ip + 1] - d[ip]) * f
                    gl += (v.targetL - gl) * k; gr += (v.targetR - gr) * k
                    mixL[i] += (smp * gl).toInt(); mixR[i] += (smp * gr).toInt()
                    pos += step
                }
                v.pos = pos; v.gainL = gl; v.gainR = gr
                if (ended || (v.stopping && gl + gr < 0.002f)) { v.sound = null; v.handle = 0 }
            }
        }
        activeVoices = active
        val mv = masterVolume
        for (i in 0 until frames) {
            out[i * 2] = limit(mixL[i] * mv)
            out[i * 2 + 1] = limit(mixR[i] * mv)
        }
    }

    /** Soft-knee limiter: linear up to ~70% of full scale, then smoothly compressed. */
    private fun limit(x: Float): Short {
        val a = if (x < 0f) -x else x
        val y = if (a <= 23000f) a else 23000f + (32767f - 23000f) * (1f - 1f / (1f + (a - 23000f) / 9767f))
        return (if (x < 0f) -y else y).toInt().toShort()
    }
}
