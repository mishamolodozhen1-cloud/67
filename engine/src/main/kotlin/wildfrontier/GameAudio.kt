package wildfrontier

import wildcore.audio.AudioMixer
import wildcore.audio.Sound
import wildcore.audio.Synth
import wildcore.core.Log
import wildcore.math.Vec3
import wildcore.world.SoundMat
import kotlin.math.PI
import kotlin.math.exp
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * Game-level audio: the procedurally synthesized sound bank, positional one-shots relative to the
 * listener and the layered ambience (wind, surf, birds, crickets, rain, fire, music) that follows
 * the time of day, weather and surroundings.
 */
class GameAudio {
    val mixer = AudioMixer()
    private val bank = HashMap<String, Sound>()
    private val listener = Vec3()
    private val right = Vec3(1f, 0f, 0f)
    var sfxVolume = 1f
    var musicVolume = 0.6f
    var ready = false; private set

    private class Layer(val name: String) { var handle = 0; var volume = 0f }
    private val layers = arrayOf(Layer("amb_wind"), Layer("amb_waves"), Layer("amb_birds"), Layer("amb_crickets"), Layer("amb_rain"), Layer("amb_fire"), Layer("music"))

    /** Synthesizes all sounds (≈0.5 s on a phone core). Call from a worker thread. */
    fun build() {
        val t0 = System.nanoTime()
        val s = Synth(7)
        fun put(name: String, b: FloatArray, loop: Boolean = false, peak: Float = 0.85f) { bank[name] = s.toSound(b, loop, peak) }

        // --- footsteps per material (3 variations each)
        for (v in 0 until 3) {
            put("step_grass$v", s.noiseBurst(0.13f, 1400f + v * 200f, 180f, 9f, 0.08f), peak = 0.5f)
            put("step_sand$v", s.noiseBurst(0.15f, 2600f, 500f + v * 100f, 8f, 0.12f), peak = 0.45f)
            put("step_snow$v", s.noiseBurst(0.17f, 5200f, 1400f + v * 200f, 7f, 0.2f), peak = 0.5f)
            val st = s.noiseBurst(0.07f, 5000f, 900f, 14f); s.mix(st, s.thud(0.07f, 190f + v * 25f, 110f, 18f), 0, 0.9f); put("step_stone$v", st, peak = 0.55f)
            val wd = s.thud(0.11f, 240f + v * 30f, 150f, 14f); s.mix(wd, s.noiseBurst(0.05f, 2200f, 300f, 20f), 0, 0.5f); put("step_wood$v", wd, peak = 0.6f)
            val lf = s.noiseBurst(0.16f, 6500f, 2200f, 7f, 0.15f); put("step_leaves$v", lf, peak = 0.4f)
            val wt = s.noiseBurst(0.22f, 1800f, 250f, 6f, 0.1f); s.tone(wt, 0, wt.size, { t -> 520f - 260f * t + v * 40f }, { t -> s.perc(t, 0.05f, 9f) * 0.5f }); put("step_water$v", wt, peak = 0.55f)
            val mt = s.thud(0.14f, 620f + v * 60f, 580f, 12f); s.mix(mt, s.noiseBurst(0.04f, 7000f, 2000f, 22f), 0, 0.5f); put("step_metal$v", mt, peak = 0.5f)
        }
        // --- digging / building
        fun crumble(lp: Float, hp: Float, n: Int): FloatArray {
            val b = s.buffer(0.42f)
            for (i in 0 until n) s.mix(b, s.noiseBurst(s.rangeF(0.04f, 0.1f), lp * s.rangeF(0.7f, 1.2f), hp, 12f), (s.rangeF(0f, 0.3f) * s.rate).toInt(), s.rangeF(0.4f, 1f))
            s.mix(b, s.thud(0.12f, 150f, 70f, 12f), 0, 0.9f)
            return b
        }
        put("break_stone", crumble(4200f, 500f, 9)); put("break_wood", crumble(1800f, 200f, 6)); put("break_dirt", crumble(1200f, 120f, 7))
        put("break_leaves", crumble(7000f, 2400f, 8), peak = 0.6f); put("break_sand", crumble(3000f, 700f, 8), peak = 0.7f)
        put("hit_stone", s.noiseBurst(0.06f, 4800f, 700f, 16f).also { s.mix(it, s.thud(0.06f, 210f, 120f, 20f), 0, 1f) }, peak = 0.6f)
        put("hit_wood", s.thud(0.09f, 260f, 170f, 16f).also { s.mix(it, s.noiseBurst(0.03f, 2500f, 300f, 24f), 0, 0.5f) }, peak = 0.65f)
        put("hit_soft", s.noiseBurst(0.09f, 1500f, 150f, 12f, 0.1f), peak = 0.55f)
        put("place", s.thud(0.1f, 300f, 140f, 16f).also { s.mix(it, s.noiseBurst(0.04f, 3000f, 400f, 22f), 0, 0.6f) }, peak = 0.7f)
        put("hit_flesh", s.thud(0.14f, 140f, 60f, 12f).also { s.mix(it, s.noiseBurst(0.06f, 900f, 100f, 16f), 0, 0.8f) })
        // --- interface & items
        put("pickup", s.buffer(0.11f).also { s.tone(it, 0, it.size, { t -> 620f + 520f * t }, { t -> s.perc(t, 0.05f, 5f) }) }, peak = 0.4f)
        put("click", s.buffer(0.035f).also { s.tone(it, 0, it.size, { 1250f }, { t -> s.perc(t, 0.05f, 9f) }) }, peak = 0.35f)
        put("craft", s.buffer(0.3f).also { b -> for (k in 0 until 3) s.mix(b, s.thud(0.08f, 700f + k * 180f, 500f + k * 150f, 14f), (k * 0.07f * s.rate).toInt(), 0.8f) }, peak = 0.5f)
        put("eat", s.buffer(0.5f).also { b -> for (k in 0 until 3) s.mix(b, s.noiseBurst(0.09f, 2600f, 500f, 9f, 0.15f), (k * 0.15f * s.rate).toInt(), 0.8f) }, peak = 0.5f)
        put("drink", s.buffer(0.5f).also { b -> for (k in 0 until 3) s.tone(b, (k * 0.15f * s.rate).toInt(), (0.11f * s.rate).toInt(), { t -> 330f + 260f * t }, { t -> s.perc(t, 0.2f, 5f) }) }, peak = 0.45f)
        put("hurt", s.thud(0.2f, 190f, 70f, 9f).also { s.mix(it, s.noiseBurst(0.1f, 1300f, 200f, 12f), 0, 0.7f) })
        put("quest", s.buffer(0.9f).also { b ->
            val notes = floatArrayOf(523f, 659f, 784f, 1047f)
            for (k in notes.indices) s.tone(b, (k * 0.11f * s.rate).toInt(), (0.5f * s.rate).toInt(), { notes[k] }, { t -> s.perc(t, 0.02f, 5f) }, floatArrayOf(1f, 0.3f, 0.1f))
        }, peak = 0.5f)
        put("note", s.noiseBurst(0.25f, 5000f, 1500f, 5f, 0.3f), peak = 0.35f)
        put("splash", s.noiseBurst(0.55f, 3200f, 350f, 5f, 0.04f).also { s.tone(it, 0, it.size, { t -> 420f - 250f * t }, { t -> s.perc(t, 0.03f, 8f) * 0.4f }) }, peak = 0.7f)
        put("bow", s.buffer(0.2f).also { s.tone(it, 0, it.size, { t -> 240f - 120f * t }, { t -> s.perc(t, 0.01f, 10f) }, floatArrayOf(1f, 0.6f, 0.4f)) }, peak = 0.6f)
        // --- animals
        put("wolf_howl", s.buffer(2.9f).also { b ->
            s.tone(b, 0, b.size, { t -> (if (t < 0.18f) 300f + 320f * (t / 0.18f) else 620f - 150f * ((t - 0.18f) / 0.82f)) * (1f + 0.012f * sin(t * 90f)) },
                { t -> (if (t < 0.1f) t / 0.1f else if (t > 0.75f) (1f - t) / 0.25f else 1f) }, floatArrayOf(1f, 0.55f, 0.25f, 0.1f))
            s.lowpass(b, 2400f)
        }, peak = 0.7f)
        put("wolf_growl", s.buffer(0.7f).also { b ->
            s.tone(b, 0, b.size, { t -> 82f + 10f * sin(t * 40f) }, { t -> (0.6f + 0.4f * sin(t * 260f)) * s.perc(t, 0.1f, 2.5f) }, floatArrayOf(1f, 0.8f, 0.6f, 0.5f, 0.3f))
            val n = s.noiseBurst(0.7f, 900f, 120f, 2.5f, 0.1f); s.mix(b, n, 0, 0.5f)
        })
        put("deer_call", s.buffer(0.55f).also { s.tone(it, 0, it.size, { t -> 360f + 90f * sin(t * 5f) - 80f * t }, { t -> s.perc(t, 0.12f, 3.5f) }, floatArrayOf(1f, 0.7f, 0.5f, 0.2f)) }, peak = 0.5f)
        put("deer_alarm", s.buffer(0.3f).also { b -> s.tone(b, 0, b.size, { t -> 520f - 180f * t }, { t -> s.perc(t, 0.03f, 7f) }, floatArrayOf(1f, 0.8f, 0.6f)); s.mix(b, s.noiseBurst(0.2f, 3000f, 600f, 8f), 0, 0.4f) }, peak = 0.6f)
        put("rabbit_thump", s.thud(0.16f, 120f, 55f, 12f), peak = 0.6f)
        // --- weather one-shots
        put("thunder", s.buffer(4.2f).also { b ->
            s.fillNoise(b)
            s.sweepLowpass(b) { t -> 60f + 1400f * exp(-t * 6f) }
            for (i in b.indices) { val t = i.toFloat() / b.size; b[i] *= (exp(-t * 3.2f) + 0.35f * exp(-(t - 0.35f) * (t - 0.35f) * 60f)) }
        })
        // --- ambience loops
        put("amb_wind", s.makeLoop(s.buffer(6.5f).also { b ->
            s.fillNoise(b)
            s.sweepLowpass(b) { t -> 420f + 260f * sin(t * 2f * PI.toFloat() * 2f) + 160f * sin(t * 2f * PI.toFloat() * 5f + 1f) }
            s.highpass(b, 90f)
        }, 1.2f), loop = true, peak = 0.55f)
        put("amb_waves", s.makeLoop(s.buffer(9f).also { b ->
            s.fillNoise(b)
            s.lowpass(b, 1500f); s.highpass(b, 140f)
            for (i in b.indices) { val t = i.toFloat() / b.size; val sw = 0.5f + 0.5f * sin(t * 2f * PI.toFloat() * 2f - 1.2f); b[i] *= 0.18f + 0.82f * sw * sw }
        }, 1.5f), loop = true, peak = 0.6f)
        put("amb_rain", s.makeLoop(s.buffer(4f).also { b ->
            s.fillNoise(b); s.highpass(b, 1800f); s.lowpass(b, 7500f)
            for (k in 0 until 220) s.mix(b, s.noiseBurst(0.012f, 6000f, 2500f, 20f), (s.rangeF(0f, 3.9f) * s.rate).toInt(), s.rangeF(0.6f, 1.6f))
        }, 0.8f), loop = true, peak = 0.5f)
        put("amb_fire", s.makeLoop(s.buffer(3.5f).also { b ->
            s.fillNoise(b, 0.25f); s.lowpass(b, 500f)
            for (k in 0 until 70) s.mix(b, s.noiseBurst(s.rangeF(0.004f, 0.02f), 5500f, 900f, 18f), (s.rangeF(0f, 3.4f) * s.rate).toInt(), s.rangeF(0.4f, 1.3f))
        }, 0.6f), loop = true, peak = 0.5f)
        put("amb_birds", s.makeLoop(s.buffer(11f).also { b ->
            for (k in 0 until 26) {
                val at = (s.rangeF(0f, 10.4f) * s.rate).toInt()
                val base = s.rangeF(2200f, 4600f)
                val kind = k % 4
                val reps = if (kind == 0) 5 else if (kind == 1) 2 else 3
                for (r in 0 until reps) {
                    val len = (s.rangeF(0.05f, 0.13f) * s.rate).toInt()
                    val up = s.chance(0.5f)
                    s.tone(b, at + r * (len + (0.03f * s.rate).toInt()), len, { t -> base * (if (up) 1f + 0.35f * t else 1.3f - 0.3f * t) * (1f + 0.04f * sin(t * 60f)) },
                        { t -> sin(t * PI.toFloat()) * s.rangeF(0.25f, 0.9f) })
                }
            }
        }, 0.6f), loop = true, peak = 0.5f)
        put("amb_crickets", s.makeLoop(s.buffer(5f).also { b ->
            for (voice in 0 until 3) {
                val f = 4200f + voice * 370f
                val rate = 17f + voice * 3f
                s.tone(b, 0, b.size, { f }, { t -> val x = t * 5f * rate; val pulse = if ((x % 1f) < 0.45f) 1f else 0f; val gate = if (((t * 5f * (0.7f + voice * 0.2f)) % 1f) < 0.6f) 1f else 0f; pulse * gate * 0.3f })
            }
        }, 0.5f), loop = true, peak = 0.35f)
        // --- music bed: slow pad chords with sparse pentatonic notes (original, generated)
        put("music", s.makeLoop(s.buffer(48f).also { b ->
            val chords = arrayOf(floatArrayOf(110f, 164.8f, 220f, 261.6f), floatArrayOf(87.3f, 130.8f, 174.6f, 220f),
                floatArrayOf(130.8f, 196f, 261.6f, 329.6f), floatArrayOf(98f, 146.8f, 196f, 246.9f))
            val seg = (11.5f * s.rate).toInt()
            for (c in 0 until 4) for (f in chords[c]) {
                s.tone(b, c * seg, seg + (2f * s.rate).toInt(), { t -> f * (1f + 0.0025f * sin(t * 37f)) },
                    { t -> val e = if (t < 0.28f) t / 0.28f else if (t > 0.72f) (1f - t) / 0.28f else 1f; e * e * 0.16f }, floatArrayOf(1f, 0.32f, 0.12f, 0.05f))
            }
            val scale = floatArrayOf(440f, 523.3f, 587.3f, 659.3f, 784f, 880f)
            for (k in 0 until 22) {
                val at = (s.rangeF(0.5f, 45f) * s.rate).toInt()
                val f = scale[(s.rangeF(0f, 5.99f)).toInt()] * (if (s.chance(0.3f)) 0.5f else 1f)
                s.tone(b, at, (2.4f * s.rate).toInt(), { f }, { t -> s.perc(t, 0.01f, 3.2f) * 0.2f }, floatArrayOf(1f, 0.25f, 0.08f))
            }
            s.lowpass(b, 3200f)
        }, 3f), loop = true, peak = 0.6f)
        ready = true
        Log.i("Audio", "synthesized ${bank.size} sounds in ${(System.nanoTime() - t0) / 1_000_000} ms")
    }

    fun setListener(pos: Vec3, rightDir: Vec3) { listener.set(pos); right.set(rightDir) }

    /** Non-positional sound (interface, own actions). */
    fun play(name: String, volume: Float = 1f, pitch: Float = 1f) {
        if (!ready) return
        val snd = bank[name] ?: return
        mixer.play(snd, volume * sfxVolume, 0f, pitch)
    }

    /** Positional one-shot: attenuated by distance and panned relative to the camera. */
    fun playAt(name: String, x: Float, y: Float, z: Float, volume: Float = 1f, pitch: Float = 1f) {
        if (!ready) return
        val snd = bank[name] ?: return
        val dx = x - listener.x; val dy = y - listener.y; val dz = z - listener.z
        val d = sqrt(dx * dx + dy * dy + dz * dz)
        if (d > 70f) return
        val att = 1f / (1f + d * 0.09f + d * d * 0.004f)
        val pan = if (d > 0.5f) (dx * right.x + dz * right.z) / d else 0f
        mixer.play(snd, volume * att * sfxVolume, pan, pitch)
    }

    fun step(material: Int, x: Float, y: Float, z: Float, volume: Float, variant: Int) {
        val n = when (material) {
            SoundMat.GRASS -> "step_grass"; SoundMat.STONE -> "step_stone"; SoundMat.WOOD -> "step_wood"; SoundMat.SAND -> "step_sand"
            SoundMat.LEAVES -> "step_leaves"; SoundMat.WATER -> "step_water"; SoundMat.SNOW -> "step_snow"; else -> "step_metal"
        }
        playAt(n + (variant % 3), x, y, z, volume, 0.92f + (variant % 5) * 0.04f)
    }

    fun blockSound(material: Int, breaking: Boolean, x: Float, y: Float, z: Float) {
        val n = if (breaking) when (material) {
            SoundMat.STONE, SoundMat.METAL -> "break_stone"; SoundMat.WOOD -> "break_wood"; SoundMat.LEAVES -> "break_leaves"
            SoundMat.SAND, SoundMat.SNOW -> "break_sand"; else -> "break_dirt"
        } else when (material) {
            SoundMat.STONE, SoundMat.METAL -> "hit_stone"; SoundMat.WOOD -> "hit_wood"; else -> "hit_soft"
        }
        playAt(n, x, y, z, 1f, 0.95f + (((x + z).toInt() and 3) * 0.035f))
    }

    /**
     * Updates the ambience mix. All inputs are 0..1 intensities; volumes glide toward their targets.
     */
    fun updateAmbience(dt: Float, wind: Float, surf: Float, birds: Float, crickets: Float, rain: Float, fire: Float, muffled: Boolean) {
        if (!ready) return
        val target = floatArrayOf(wind * 0.5f, surf * 0.55f, birds * 0.42f, crickets * 0.3f, rain * 0.7f, fire * 0.55f, 1f)
        for (i in layers.indices) {
            val l = layers[i]
            val isMusic = i == layers.size - 1
            var t = target[i] * (if (isMusic) musicVolume * 0.5f else sfxVolume)
            if (muffled && !isMusic) t *= 0.25f
            l.volume += (t - l.volume) * minOf(1f, dt * 1.2f)
            if (l.volume > 0.004f && l.handle == 0) {
                val snd = bank[l.name] ?: continue
                l.handle = mixer.play(snd, l.volume, 0f, 1f, loop = true, fadeIn = true)
            } else if (l.handle != 0) {
                if (l.volume <= 0.004f && t <= 0.001f) { mixer.stop(l.handle); l.handle = 0 } else mixer.setVolume(l.handle, l.volume)
            }
        }
    }

    fun stopAmbience() { for (l in layers) { if (l.handle != 0) mixer.stop(l.handle); l.handle = 0; l.volume = 0f } }
    fun sound(name: String): Sound? = bank[name]
}
