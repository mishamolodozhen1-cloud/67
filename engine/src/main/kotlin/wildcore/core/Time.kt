package wildcore.core

/** Frame timing. dt is clamped so a long hitch never explodes physics. */
class Time {
    var dt: Float = 0f; private set
    var rawDt: Float = 0f; private set
    var elapsed: Double = 0.0; private set
    var frame: Long = 0; private set
    private var lastNanos = 0L

    fun reset() { lastNanos = 0L }

    fun tick(nowNanos: Long, overrideDt: Float = -1f) {
        rawDt = if (overrideDt >= 0f) overrideDt
        else if (lastNanos == 0L) 1f / 60f
        else (nowNanos - lastNanos) / 1_000_000_000f
        lastNanos = nowNanos
        dt = if (rawDt > 0.1f) 0.1f else rawDt
        elapsed += dt
        frame++
    }
}
