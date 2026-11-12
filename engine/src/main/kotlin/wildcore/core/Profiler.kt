package wildcore.core

/**
 * Built-in performance profiler: frame time history, named section timers and counters.
 * All storage is preallocated; safe to leave enabled in release builds.
 */
class Profiler {
    companion object { const val HISTORY = 120 }

    val frameMs = FloatArray(HISTORY)
    private var head = 0
    private var frameStart = 0L

    var fps = 0f; private set
    var avgFrameMs = 0f; private set
    var worstFrameMs = 0f; private set
    var low1PercentFps = 0f; private set

    // Per-frame counters (reset each frame)
    @JvmField var drawCalls = 0
    @JvmField var triangles = 0
    @JvmField var chunksDrawn = 0
    @JvmField var chunksCulled = 0

    // Gauges set by subsystems
    @JvmField var chunksLoaded = 0
    @JvmField var chunkJobsPending = 0
    @JvmField var activeEntities = 0
    @JvmField var particles = 0
    @JvmField var lastChunkGenMs = 0f
    @JvmField var avgChunkGenMs = 0f
    @JvmField var avgChunkMeshMs = 0f
    @JvmField var worldLoadMs = 0f
    @JvmField var gpuMemEstimateMb = 0f
    @JvmField var usedMemMb = 0
    @JvmField var thermal = 0

    // Last completed frame's counters (stable values for display)
    var lastDrawCalls = 0; private set
    var lastTriangles = 0; private set
    var lastChunksDrawn = 0; private set

    private val sectionNames = ArrayList<String>()
    private val sectionAccum = LongArray(16)
    private val sectionMs = FloatArray(16)
    private val sectionStart = LongArray(16)
    private var accumFrames = 0

    fun section(name: String): Int {
        val i = sectionNames.indexOf(name)
        if (i >= 0) return i
        sectionNames.add(name)
        return sectionNames.size - 1
    }
    fun begin(id: Int) { sectionStart[id] = System.nanoTime() }
    fun end(id: Int) { sectionAccum[id] += System.nanoTime() - sectionStart[id] }
    fun sectionCount(): Int = sectionNames.size
    fun sectionName(i: Int): String = sectionNames[i]
    fun sectionMs(i: Int): Float = sectionMs[i]

    fun beginFrame() {
        frameStart = System.nanoTime()
        drawCalls = 0; triangles = 0; chunksDrawn = 0; chunksCulled = 0
    }

    fun endFrame(rawDtSeconds: Float) {
        frameMs[head] = rawDtSeconds * 1000f
        head = (head + 1) % HISTORY
        lastDrawCalls = drawCalls; lastTriangles = triangles; lastChunksDrawn = chunksDrawn
        accumFrames++
        if (head % 20 == 0) {
            var sum = 0f; var worst = 0f
            for (v in frameMs) { sum += v; if (v > worst) worst = v }
            avgFrameMs = sum / HISTORY
            worstFrameMs = worst
            fps = if (avgFrameMs > 0f) 1000f / avgFrameMs else 0f
            low1PercentFps = if (worst > 0f) 1000f / worst else 0f
            for (i in 0 until sectionNames.size) {
                sectionMs[i] = sectionAccum[i] / 1_000_000f / accumFrames
                sectionAccum[i] = 0
            }
            accumFrames = 0
        }
    }
}
