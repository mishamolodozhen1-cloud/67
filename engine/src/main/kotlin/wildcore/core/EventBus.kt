package wildcore.core

/**
 * Tiny typed publish/subscribe bus. Listeners are invoked synchronously on the posting thread
 * (the game thread); cross-thread producers should go through JobSystem.runOnMain.
 */
class EventBus {
    private val listeners = HashMap<Class<*>, ArrayList<(Any) -> Unit>>()

    @Suppress("UNCHECKED_CAST")
    fun <T : Any> subscribe(type: Class<T>, listener: (T) -> Unit) {
        listeners.getOrPut(type) { ArrayList() }.add(listener as (Any) -> Unit)
    }

    inline fun <reified T : Any> on(noinline listener: (T) -> Unit) = subscribe(T::class.java, listener)

    fun post(event: Any) {
        val list = listeners[event.javaClass] ?: return
        for (i in 0 until list.size) list[i](event)
    }

    fun clear() = listeners.clear()
}
