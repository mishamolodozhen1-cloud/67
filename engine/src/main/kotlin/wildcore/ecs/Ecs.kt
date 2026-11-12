package wildcore.ecs

/**
 * Minimal entity-component-system. Entities are int ids; each component type lives in its own dense
 * array indexed by entity id, so systems iterate without hashing or allocation.
 */
class EcsWorld(private var capacity: Int = 256) {
    private var alive = BooleanArray(capacity)
    private val free = ArrayList<Int>()
    private var next = 0
    private val stores = ArrayList<ComponentStore<*>>()
    var aliveCount = 0; private set

    fun <T : Any> store(): ComponentStore<T> { val s = ComponentStore<T>(capacity); stores.add(s); return s }

    fun create(): Int {
        val id = if (free.isNotEmpty()) free.removeAt(free.size - 1) else next++
        if (id >= capacity) {
            capacity *= 2
            alive = alive.copyOf(capacity)
            for (s in stores) s.grow(capacity)
        }
        alive[id] = true
        aliveCount++
        return id
    }

    fun destroy(id: Int) {
        if (id < 0 || id >= capacity || !alive[id]) return
        alive[id] = false
        aliveCount--
        for (s in stores) s.remove(id)
        free.add(id)
    }

    fun isAlive(id: Int): Boolean = id in 0 until capacity && alive[id]
    val highWater: Int get() = next

    fun clear() {
        for (i in 0 until next) if (alive[i]) destroy(i)
    }
}

class ComponentStore<T : Any>(capacity: Int) {
    @PublishedApi internal var data = arrayOfNulls<Any>(capacity)

    internal fun grow(n: Int) { data = data.copyOf(n) }
    operator fun set(entity: Int, c: T) { data[entity] = c }
    @Suppress("UNCHECKED_CAST")
    operator fun get(entity: Int): T? = data[entity] as T?
    fun remove(entity: Int) { data[entity] = null }

    /** Iterates entities that have this component. */
    @Suppress("UNCHECKED_CAST")
    inline fun each(limit: Int, action: (entity: Int, c: T) -> Unit) {
        val d = data
        val n = minOf(limit, d.size)
        for (i in 0 until n) { val c = d[i]; if (c != null) action(i, c as T) }
    }
}
