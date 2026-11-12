package wildcore.world

/** Open-addressing hash map with primitive long keys (no boxing on lookups). */
class LongMap<V : Any>(capacity: Int = 256) {
    private var keys = LongArray(capacity)
    private var used = BooleanArray(capacity)
    @Suppress("UNCHECKED_CAST")
    private var values = arrayOfNulls<Any>(capacity) as Array<V?>
    private var mask = capacity - 1
    var size = 0; private set

    init { require(capacity and (capacity - 1) == 0) }

    private fun slot(key: Long): Int {
        var h = key * -0x61c8864680b583ebL
        h = h xor (h ushr 32)
        return h.toInt() and mask
    }

    fun get(key: Long): V? {
        var i = slot(key)
        while (used[i]) {
            if (keys[i] == key) return values[i]
            i = (i + 1) and mask
        }
        return null
    }

    fun put(key: Long, value: V) {
        if (size * 2 >= keys.size) grow()
        var i = slot(key)
        while (used[i]) {
            if (keys[i] == key) { values[i] = value; return }
            i = (i + 1) and mask
        }
        used[i] = true; keys[i] = key; values[i] = value; size++
    }

    fun remove(key: Long): V? {
        var i = slot(key)
        while (used[i]) {
            if (keys[i] == key) {
                val v = values[i]
                // backward-shift deletion keeps probe chains intact
                var j = i
                while (true) {
                    j = (j + 1) and mask
                    if (!used[j]) break
                    val home = slot(keys[j])
                    val inRange = if (i <= j) (home in (i + 1)..j) else (home > i || home <= j)
                    if (!inRange) {
                        keys[i] = keys[j]; values[i] = values[j]
                        i = j
                    }
                }
                used[i] = false; values[i] = null
                size--
                return v
            }
            i = (i + 1) and mask
        }
        return null
    }

    private fun grow() {
        val ok = keys; val ou = used; val ov = values
        val cap = ok.size * 2
        keys = LongArray(cap); used = BooleanArray(cap)
        @Suppress("UNCHECKED_CAST")
        values = arrayOfNulls<Any>(cap) as Array<V?>
        mask = cap - 1; size = 0
        for (i in ok.indices) if (ou[i]) put(ok[i], ov[i]!!)
    }

    inline fun forEach(action: (V) -> Unit) {
        val vals = valuesArray()
        val u = usedArray()
        for (i in vals.indices) if (u[i]) action(vals[i]!!)
    }

    @PublishedApi internal fun valuesArray(): Array<V?> = values
    @PublishedApi internal fun usedArray(): BooleanArray = used
}
