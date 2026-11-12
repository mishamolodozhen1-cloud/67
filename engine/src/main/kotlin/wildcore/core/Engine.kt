package wildcore.core

import wildcore.gfx.GL
import wildcore.gfx.GpuCaps

/**
 * WildCore Engine root object. Owns the subsystems shared by all scenes and drives the main loop.
 * The host calls the on* methods from its render thread.
 */
class Engine(val platform: Platform) {
    val time = Time()
    val events = EventBus()
    val input = InputQueue()
    val profiler = Profiler()
    val jobs = JobSystem(maxOf(1, minOf(4, platform.deviceInfo.cpuCores - 2)))
    val scenes = SceneManager(this)
    val settings = Settings(platform)

    lateinit var gl: GL; private set
    lateinit var caps: GpuCaps; private set
    var hasContext = false; private set
    var width = 1; private set
    var height = 1; private set
    @Volatile var paused = false; private set
    /** When false, frames only simulate (used while the surface is unavailable and by the test harness). */
    var renderEnabled = true
    /** Invoked right after a GL context is (re)created, before the current scene is notified. */
    var contextHook: (() -> Unit)? = null
    var resizeHook: ((Int, Int) -> Unit)? = null

    init {
        Log.platform = platform
        settings.load()
    }

    fun onContextCreated(gl: GL) {
        this.gl = gl
        caps = GpuCaps.query(gl)
        hasContext = true
        Log.i("Engine", "GL context: ${caps.renderer} / ${caps.version} maxTex=${caps.maxTextureSize}")
        settings.autoDetectIfNeeded(platform.deviceInfo, caps)
        contextHook?.invoke()
        scenes.current?.onContextCreated(this)
    }

    fun onResize(w: Int, h: Int) {
        width = maxOf(1, w); height = maxOf(1, h)
        resizeHook?.invoke(width, height)
        scenes.current?.onResize(this, width, height)
    }

    /** One iteration of the main loop. [overrideDt] is used by the deterministic test harness. */
    fun frame(overrideDt: Float = -1f) {
        time.tick(System.nanoTime(), overrideDt)
        profiler.beginFrame()
        scenes.applyPending()
        jobs.drainMain(4_000_000L)
        val scene = scenes.current
        if (scene != null) {
            scene.update(this, time.dt)
            if (renderEnabled) scene.render(this)
        }
        profiler.endFrame(time.rawDt)
    }

    fun onPause() {
        paused = true
        scenes.current?.onPause(this)
        platform.audioSink?.setPaused(true)
    }

    fun onResume() {
        paused = false
        time.reset()
        platform.audioSink?.setPaused(false)
        scenes.current?.onResume(this)
    }

    fun onContextLost() { hasContext = false }

    fun shutdown() {
        scenes.current?.onExit(this)
        jobs.shutdown()
    }
}
