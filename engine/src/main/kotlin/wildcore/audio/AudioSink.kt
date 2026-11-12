package wildcore.audio

/** Pull-model PCM source: the host audio thread asks the mixer for interleaved stereo 16-bit frames. */
interface AudioSource {
    val sampleRate: Int
    fun render(out: ShortArray, frames: Int)
}

/** Host audio output (Android: AudioTrack thread). */
interface AudioSink {
    fun start(source: AudioSource)
    fun setPaused(paused: Boolean)
    fun stop()
}
