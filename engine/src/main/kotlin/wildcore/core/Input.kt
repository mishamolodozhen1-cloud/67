package wildcore.core

/** Raw touch event forwarded from the host UI thread. Coordinates are in surface pixels. */
class TouchEvent(@JvmField var action: Int = 0, @JvmField var id: Int = 0, @JvmField var x: Float = 0f, @JvmField var y: Float = 0f) {
    companion object {
        const val DOWN = 0
        const val MOVE = 1
        const val UP = 2
        const val CANCEL = 3
    }
}

/** Thread-safe touch queue with pooled events (no per-event garbage during play). */
class InputQueue {
    private val lock = Any()
    private var pending = ArrayList<TouchEvent>(64)
    private var processing = ArrayList<TouchEvent>(64)
    private val pool = ArrayList<TouchEvent>(64)
    @Volatile var backPressed = false

    fun push(action: Int, id: Int, x: Float, y: Float) {
        synchronized(lock) {
            val e = if (pool.isEmpty()) TouchEvent() else pool.removeAt(pool.size - 1)
            e.action = action; e.id = id; e.x = x; e.y = y
            pending.add(e)
        }
    }

    /** Swap buffers and return this frame's events. Valid until the next call. */
    fun drain(): List<TouchEvent> {
        synchronized(lock) {
            pool.addAll(processing)
            processing.clear()
            val t = processing; processing = pending; pending = t
        }
        return processing
    }

    fun consumeBack(): Boolean { val b = backPressed; backPressed = false; return b }
}
