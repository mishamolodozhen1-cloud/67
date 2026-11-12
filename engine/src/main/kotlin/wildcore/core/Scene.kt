package wildcore.core

/** A top-level application state (main menu, gameplay…). */
interface Scene {
    fun onEnter(engine: Engine) {}
    fun onExit(engine: Engine) {}
    /** GL context was (re)created: rebuild every GPU resource. */
    fun onContextCreated(engine: Engine) {}
    fun onResize(engine: Engine, width: Int, height: Int) {}
    fun update(engine: Engine, dt: Float)
    fun render(engine: Engine)
    fun onPause(engine: Engine) {}
    fun onResume(engine: Engine) {}
}

class SceneManager(private val engine: Engine) {
    var current: Scene? = null; private set
    private var pending: Scene? = null

    fun switchTo(scene: Scene) { pending = scene }

    fun applyPending() {
        val next = pending ?: return
        pending = null
        current?.onExit(engine)
        current = next
        next.onEnter(engine)
        if (engine.hasContext) {
            next.onContextCreated(engine)
            next.onResize(engine, engine.width, engine.height)
        }
    }
}
