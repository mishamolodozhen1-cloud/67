package wildfrontier.desktop

/** Scripted verification runs. Each produces screenshots and prints measurements. */
object Scenarios {
    fun run(name: String, h: Harness, opts: Map<String, String>) {
        when (name) {
            "terrain" -> terrain(h, opts)
            else -> error("unknown scenario $name")
        }
    }

    private fun terrain(h: Harness, opts: Map<String, String>) {
        val seed = opts["seed"]?.toLong() ?: 20260L
        h.game.startNewGame(seed)
        h.frames(2)
        val scene = h.game.gameScene!!
        val t0 = System.nanoTime()
        val used = h.until(6000) { scene.world.pendingJobs == 0 && scene.ready }
        h.frames(12)
        println("world ready after $used frames, ${(System.nanoTime() - t0) / 1_000_000} ms; chunks=${scene.world.loadedCount}")
        val cam = scene.renderer.camera
        println("spawn camera at ${cam.pos}")
        cam.pos.y += 6f
        for ((k, yaw) in floatArrayOf(0f, 1.57f, 3.14f, 4.71f).withIndex()) {
            cam.yaw = yaw; cam.pitch = -0.12f
            h.frames(2)
            h.screenshot("terrain_$k")
        }
        val p = h.game.engine.profiler
        println("drawCalls=${p.lastDrawCalls} tris=${p.lastTriangles} chunksDrawn=${p.lastChunksDrawn} avgGenMs=${p.avgChunkGenMs} avgMeshMs=${p.avgChunkMeshMs} gpuMB=${p.gpuMemEstimateMb}")
    }
}
