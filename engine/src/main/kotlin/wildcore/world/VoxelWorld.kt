package wildcore.world

import wildcore.core.JobSystem
import wildcore.core.Profiler
import java.util.concurrent.ConcurrentLinkedQueue

/** Receives finished chunk geometry on the main thread (the renderer implements this). */
interface ChunkMeshSink {
    fun onChunkMeshed(chunk: Chunk, data: ChunkMeshData)
    fun onChunkUnloaded(chunk: Chunk)
}

/**
 * The voxel world: chunk map, block access, asynchronous streaming around a focus point,
 * mesh scheduling and persistence of modified chunks.
 *
 * Threading: all public methods are main-thread only. Generation, disk I/O and meshing run on the
 * [JobSystem]; workers never touch the chunk map (neighbour references are captured at submit time).
 */
class VoxelWorld(
    private val jobs: JobSystem,
    private val generator: ChunkGenerator,
    private val storage: ChunkStorage?,
    private val profiler: Profiler,
    /** Block id returned for coordinates outside the vertical range / used as light wall. */
    private val barrierBlock: Int,
) : wildcore.physics.BlockQuery {
    val chunks = LongMap<Chunk>(1024)
    var viewDistance = 7
    var meshSink: ChunkMeshSink? = null
    var leafInnerFaces = true
    /** Called on the main thread after any block edit (old id, new id). */
    var onBlockChanged: ((x: Int, y: Int, z: Int, old: Int, new: Int) -> Unit)? = null
    /** Called on the main thread when a chunk finishes loading. */
    var onChunkReady: ((Chunk) -> Unit)? = null

    private var centerCx = Int.MIN_VALUE
    private var centerCz = Int.MIN_VALUE
    private val pendingLoad = ArrayList<Long>()
    private var loadsInFlight = 0
    private var meshesInFlight = 0
    private val needMesh = ArrayList<Chunk>()
    private val meshers = ThreadLocal.withInitial { ChunkMesher() }
    private val meshDataPool = ConcurrentLinkedQueue<ChunkMeshData>()
    private var lastChunk: Chunk? = null
    private var frame = 0L
    private var genTimeAccum = 0f
    private var genCount = 0
    private var meshTimeAccum = 0f
    private var meshCount = 0

    val loadedCount: Int get() = chunks.size
    val pendingJobs: Int get() = pendingLoad.size + loadsInFlight + meshesInFlight + needMesh.size

    // ------------------------------------------------------------ block access

    fun getChunk(cx: Int, cz: Int): Chunk? {
        val lc = lastChunk
        if (lc != null && lc.cx == cx && lc.cz == cz) return lc
        val c = chunks.get(Chunk.key(cx, cz))
        if (c != null) lastChunk = c
        return c
    }

    /** Block id at world coordinates; unloaded space reads as the barrier block, above the world as air. */
    override fun getBlock(x: Int, y: Int, z: Int): Int {
        if (y < 0) return barrierBlock
        if (y >= Chunk.HEIGHT) return 0
        val c = getChunk(x shr 4, z shr 4)
        if (c == null || c.state != Chunk.STATE_READY) return barrierBlock
        return c.blocks[(((z and 15) shl 4 or (x and 15)) shl 7) or y].toInt() and 255
    }

    fun isLoaded(x: Int, z: Int): Boolean {
        val c = getChunk(x shr 4, z shr 4)
        return c != null && c.state == Chunk.STATE_READY
    }

    fun isSolid(x: Int, y: Int, z: Int): Boolean = Blocks.solid[getBlock(x, y, z)]

    /** Highest solid block y in the column, or -1 if unloaded/empty. */
    fun surfaceY(x: Int, z: Int): Int {
        val c = getChunk(x shr 4, z shr 4) ?: return -1
        if (c.state != Chunk.STATE_READY) return -1
        return c.topSolidY(x and 15, z and 15)
    }

    fun setBlock(x: Int, y: Int, z: Int, id: Int): Boolean {
        if (y < 0 || y >= Chunk.HEIGHT) return false
        val cx = x shr 4; val cz = z shr 4
        val c = getChunk(cx, cz) ?: return false
        if (c.state != Chunk.STATE_READY) return false
        val lx = x and 15; val lz = z and 15
        val idx = Chunk.index(lx, y, lz)
        val old = c.blocks[idx].toInt() and 255
        if (old == id) return false
        c.blocks[idx] = id.toByte()
        c.modified = true
        c.unsaved = true
        c.revision++
        if (Blocks.emission[old] > 0 || Blocks.emission[id] > 0) c.rebuildEmitters()
        if (Blocks.get(old).shape != Shape.AIR) c.blockData?.remove(idx)
        // remesh: this chunk now; neighbours that share the edited border now; others in light range later
        requestMesh(c, urgent = true)
        for (dz in -1..1) for (dx in -1..1) {
            if (dx == 0 && dz == 0) continue
            val n = getChunk(cx + dx, cz + dz) ?: continue
            val touchX = dx == 0 || (dx < 0 && lx == 0) || (dx > 0 && lx == 15)
            val touchZ = dz == 0 || (dz < 0 && lz == 0) || (dz > 0 && lz == 15)
            n.revision++
            requestMesh(n, urgent = touchX && touchZ)
        }
        onBlockChanged?.invoke(x, y, z, old, id)
        return true
    }

    fun getBlockData(x: Int, y: Int, z: Int): Any? {
        val c = getChunk(x shr 4, z shr 4) ?: return null
        return c.blockData?.get(Chunk.index(x and 15, y, z and 15))
    }

    fun setBlockData(x: Int, y: Int, z: Int, data: Any?) {
        val c = getChunk(x shr 4, z shr 4) ?: return
        val idx = Chunk.index(x and 15, y, z and 15)
        if (data == null) c.blockData?.remove(idx)
        else {
            var m = c.blockData
            if (m == null) { m = HashMap(); c.blockData = m }
            m[idx] = data
        }
        c.modified = true
        c.unsaved = true
    }

    private fun requestMesh(c: Chunk, urgent: Boolean) {
        if (urgent) c.urgentMesh = true
        if (!c.needsMesh) { c.needsMesh = true; needMesh.add(c) }
    }

    // ------------------------------------------------------------ streaming

    /** Call every frame with the focus position (player) in world blocks. */
    fun update(focusX: Float, focusZ: Float) {
        frame++
        val cx = Math.floorDiv(focusX.toInt(), 16)
        val cz = Math.floorDiv(focusZ.toInt(), 16)
        if (cx != centerCx || cz != centerCz) {
            centerCx = cx; centerCz = cz
            rebuildLoadList()
            unloadFar()
        }
        scheduleLoads()
        scheduleMeshes()
        profiler.chunksLoaded = chunks.size
        profiler.chunkJobsPending = pendingJobs
    }

    private fun dataRadius(): Int = viewDistance + 1

    private fun rebuildLoadList() {
        pendingLoad.clear()
        val r = dataRadius()
        for (dz in -r..r) for (dx in -r..r) {
            if (dx * dx + dz * dz > r * r + r) continue
            val key = Chunk.key(centerCx + dx, centerCz + dz)
            if (chunks.get(key) == null) pendingLoad.add(key)
        }
        val ccx = centerCx; val ccz = centerCz
        // farthest first so the nearest can be popped cheaply from the end
        pendingLoad.sortWith { a, b ->
            val ax = (a shr 32).toInt() - ccx; val az = a.toInt() - ccz
            val bx = (b shr 32).toInt() - ccx; val bz = b.toInt() - ccz
            (bx * bx + bz * bz).compareTo(ax * ax + az * az)
        }
    }

    private fun scheduleLoads() {
        val maxInFlight = jobs.workerCount * 2 + 1
        while (loadsInFlight < maxInFlight && pendingLoad.isNotEmpty()) {
            val key = pendingLoad.removeAt(pendingLoad.size - 1)
            if (chunks.get(key) != null) continue
            val cx = (key shr 32).toInt(); val cz = key.toInt()
            val chunk = Chunk(cx, cz)
            chunks.put(key, chunk)
            loadsInFlight++
            val dx = cx - centerCx; val dz = cz - centerCz
            jobs.submit((dx * dx + dz * dz).toFloat(), Runnable {
                val t0 = System.nanoTime()
                var fromDisk = false
                try { fromDisk = storage?.load(chunk) == true } catch (e: Exception) { wildcore.core.Log.e("World", "chunk load failed $cx,$cz", e) }
                if (!fromDisk) generator.generate(chunk) else chunk.modified = true
                chunk.rebuildEmitters()
                val ms = (System.nanoTime() - t0) / 1_000_000f
                jobs.runOnMain(Runnable {
                    loadsInFlight--
                    if (!fromDisk) {
                        genTimeAccum += ms; genCount++
                        profiler.lastChunkGenMs = ms
                        profiler.avgChunkGenMs = genTimeAccum / genCount
                    }
                    if (chunks.get(key) === chunk) {
                        chunk.state = Chunk.STATE_READY
                        onChunkReady?.invoke(chunk)
                        for (nz in -1..1) for (nx in -1..1) {
                            val n = chunks.get(Chunk.key(cx + nx, cz + nz)) ?: continue
                            if (n.state == Chunk.STATE_READY) requestMesh(n, false)
                        }
                    }
                })
            })
        }
    }

    private val neighbourScratch = arrayOfNulls<Chunk>(9)

    private fun scheduleMeshes() {
        if (needMesh.isEmpty()) return
        val maxInFlight = jobs.workerCount + 1
        // pick the best candidates: urgent first, then nearest
        var guard = 0
        while (meshesInFlight < maxInFlight && guard++ < 8) {
            var best = -1; var bestScore = Float.MAX_VALUE
            for (i in 0 until needMesh.size) {
                val c = needMesh[i]
                if (c.meshQueued) continue
                val dx = c.cx - centerCx; val dz = c.cz - centerCz
                val d2 = dx * dx + dz * dz
                if (d2 > viewDistance * viewDistance + viewDistance) continue
                val score = if (c.urgentMesh) -1000f + d2 else d2.toFloat()
                if (score < bestScore && neighboursReady(c)) { best = i; bestScore = score }
            }
            if (best < 0) break
            val c = needMesh[best]
            needMesh[best] = needMesh[needMesh.size - 1]
            needMesh.removeAt(needMesh.size - 1)
            submitMesh(c, bestScore)
        }
        // drop entries whose chunk was unloaded
        if (frame % 120L == 0L) needMesh.removeAll { chunks.get(Chunk.key(it.cx, it.cz)) !== it }
    }

    private fun neighboursReady(c: Chunk): Boolean {
        for (dz in -1..1) for (dx in -1..1) {
            val n = chunks.get(Chunk.key(c.cx + dx, c.cz + dz)) ?: return false
            if (n.state != Chunk.STATE_READY) return false
        }
        return true
    }

    private fun submitMesh(c: Chunk, priority: Float) {
        val neigh = arrayOfNulls<Chunk>(9)
        for (dz in -1..1) for (dx in -1..1) neigh[(dz + 1) * 3 + dx + 1] = chunks.get(Chunk.key(c.cx + dx, c.cz + dz))
        c.needsMesh = false
        c.urgentMesh = false
        c.meshQueued = true
        val revision = c.revision
        meshesInFlight++
        val inner = leafInnerFaces
        jobs.submit(priority, Runnable {
            val t0 = System.nanoTime()
            val data = meshDataPool.poll() ?: ChunkMeshData()
            val mesher = meshers.get()
            mesher.leafInnerFaces = inner
            var ok = true
            try { mesher.mesh(neigh, barrierBlock, data) } catch (t: Throwable) { ok = false; wildcore.core.Log.e("World", "mesh failed", t) }
            data.revision = revision
            val ms = (System.nanoTime() - t0) / 1_000_000f
            jobs.runOnMain(Runnable {
                meshesInFlight--
                c.meshQueued = false
                meshTimeAccum += ms; meshCount++
                profiler.avgChunkMeshMs = meshTimeAccum / meshCount
                if (ok && chunks.get(Chunk.key(c.cx, c.cz)) === c) {
                    meshSink?.onChunkMeshed(c, data)
                    c.meshedRevision = revision
                    if (c.revision != revision) requestMesh(c, false)
                }
                meshDataPool.add(data)
            })
        })
    }

    private fun unloadFar() {
        val r = dataRadius() + 2
        var toRemove: ArrayList<Chunk>? = null
        chunks.forEach { c ->
            val dx = c.cx - centerCx; val dz = c.cz - centerCz
            if (dx * dx + dz * dz > r * r) {
                if (toRemove == null) toRemove = ArrayList()
                toRemove!!.add(c)
            }
        }
        val list = toRemove ?: return
        for (c in list) {
            if (c.state == Chunk.STATE_READY && c.modified && c.unsaved) saveChunkAsync(c)
            meshSink?.onChunkUnloaded(c)
            chunks.remove(Chunk.key(c.cx, c.cz))
            if (lastChunk === c) lastChunk = null
        }
    }

    private fun saveChunkAsync(c: Chunk) {
        val st = storage ?: return
        val copy = c.blocks.clone()
        val data = c.blockData?.let { HashMap(it) }
        c.unsaved = false
        jobs.submit(-10f, Runnable { st.save(c.cx, c.cz, copy, data) })
    }

    /** Persist every modified chunk (manual save / autosave / app pause). [sync] writes on the calling thread. */
    fun saveAll(sync: Boolean) {
        val st = storage ?: return
        chunks.forEach { c ->
            if (c.state == Chunk.STATE_READY && c.modified && c.unsaved) {
                if (sync) { st.save(c.cx, c.cz, c.blocks, c.blockData); c.unsaved = false }
                else saveChunkAsync(c)
            }
        }
    }

    /** True when every chunk within [radius] chunks of the focus is loaded and meshed. */
    fun isAreaReady(focusX: Float, focusZ: Float, radius: Int): Boolean {
        val cx = Math.floorDiv(focusX.toInt(), 16); val cz = Math.floorDiv(focusZ.toInt(), 16)
        for (dz in -radius..radius) for (dx in -radius..radius) {
            val c = chunks.get(Chunk.key(cx + dx, cz + dz)) ?: return false
            if (c.state != Chunk.STATE_READY || c.meshedRevision < 0) return false
        }
        return true
    }

    /** Forces every loaded chunk to be re-meshed (graphics tier change, GL context loss). */
    fun remeshAll() {
        chunks.forEach { c -> if (c.state == Chunk.STATE_READY) { c.meshedRevision = -1; requestMesh(c, false) } }
    }

    fun markUnsaved(c: Chunk) { c.unsaved = true }
}
