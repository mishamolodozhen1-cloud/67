package wildfrontier.desktop

import wildcore.core.TouchEvent
import wildcore.math.floorInt
import wildfrontier.GameScene
import wildfrontier.content.B
import wildfrontier.content.I
import wildfrontier.env.Weather
import wildfrontier.gen.Column
import wildfrontier.ui.Hud

/** Scripted verification runs against the real game. Each prints measurements and writes screenshots. */
object Scenarios {
    private lateinit var h: Harness
    private val scene: GameScene get() = h.game.gameScene!!

    fun run(name: String, harness: Harness, opts: Map<String, String>) {
        h = harness
        val seed = opts["seed"]?.toLong() ?: 20260L
        when (name) {
            "smoke" -> smoke(seed)
            "tour" -> tour(seed)
            "water" -> water(seed)
            "animals" -> animals(seed)
            "gameplay" -> gameplay(seed)
            "save" -> saveTest(seed)
            "perf" -> perf(seed)
            else -> error("unknown scenario $name")
        }
    }

    // ------------------------------------------------------------------ helpers

    private fun newGame(seed: Long) {
        h.game.startNewGame(seed)
        h.frames(2)
        val t0 = System.nanoTime()
        val used = h.until(20000) { scene.ready && scene.world.pendingJobs == 0 }
        println("world ready: $used sim frames, ${(System.nanoTime() - t0) / 1_000_000} ms wall, chunks=${scene.world.loadedCount}")
        scene.debugFreezeTime = true
        h.frames(3)
    }

    private fun settle(render: Int = 3) {
        h.until(20000) { scene.ready && scene.world.pendingJobs == 0 }
        h.frames(render)
    }

    private fun tp(x: Float, z: Float) {
        val p = scene.player
        p.teleport(x, 120f, z)
        // wait for the destination to stream in, holding the player in the air
        h.until(20000) { p.teleport(x, 120f, z); scene.world.isAreaReady(x, z, 3) && scene.world.pendingJobs == 0 }
        val y = scene.world.surfaceY(floorInt(x), floorInt(z))
        p.teleport(x, y + 1.05f, z)
        h.frames(3)
    }

    private fun findBiome(biome: Int, fromX: Float, fromZ: Float, minAlt: Float = 2f): FloatArray? {
        val c = Column()
        var r = 0
        while (r < 6000) {
            val steps = maxOf(8, r / 10)
            for (i in 0 until steps) {
                val a = i * 6.2831853f / steps
                val x = fromX + kotlin.math.cos(a) * r; val z = fromZ + kotlin.math.sin(a) * r
                scene.gen.sample(x.toInt(), z.toInt(), c)
                if (c.biome == biome && c.height > wildfrontier.gen.WorldGen.SEA + minAlt) return floatArrayOf(x, z)
            }
            r += 24
        }
        return null
    }

    private fun look(yaw: Float, pitch: Float) { scene.player.yaw = yaw; scene.player.pitch = pitch }

    /** Tap in virtual UI coordinates. */
    private fun tap(vx: Float, vy: Float, holdFrames: Int = 2) {
        val s = h.game.ui.scale
        h.game.engine.input.push(TouchEvent.DOWN, 7, vx * s, vy * s)
        h.frames(holdFrames)
        h.game.engine.input.push(TouchEvent.UP, 7, vx * s, vy * s)
        h.frames(2)
    }

    private fun stats(tag: String) {
        val p = h.game.engine.profiler
        println("[$tag] drawCalls=${p.lastDrawCalls} tris=${p.lastTriangles} chunksDrawn=${p.lastChunksDrawn} loaded=${p.chunksLoaded} " +
                "genMs=${"%.2f".format(p.avgChunkGenMs)} meshMs=${"%.2f".format(p.avgChunkMeshMs)} gpuMB=${"%.1f".format(p.gpuMemEstimateMb)} " +
                "ramMB=${p.usedMemMb} entities=${p.activeEntities} particles=${p.particles} worldLoadMs=${p.worldLoadMs.toInt()}")
    }

    // ------------------------------------------------------------------ scenarios

    private fun smoke(seed: Long) {
        h.frames(40)
        h.screenshot("01_menu")
        newGame(seed)
        scene.dayNight.hour = 10f
        look(2.4f, -0.12f)
        h.frames(6)
        h.screenshot("02_hud")
        stats("spawn")
        val ui = h.game.ui
        scene.give(B.OAK_LOG, 12); scene.give(B.COBBLE, 9); scene.give(I.STICK, 6); scene.give(I.PLANT_FIBER, 8); scene.give(I.APPLE, 3)
        scene.give(I.STONE_AXE, 1); scene.give(B.PLANKS_OAK, 20); scene.give(I.FLINT, 2)
        h.frames(2)
        for ((id, name) in listOf(Hud.INVENTORY to "03_inventory", Hud.CRAFTING to "04_crafting", Hud.MAP to "05_map", Hud.JOURNAL to "06_journal",
            Hud.ENCYCLOPEDIA to "07_encyclopedia", Hud.BUILD to "08_build", Hud.PAUSE to "09_pause", Hud.SETTINGS to "10_settings")) {
            scene.hud.open(id)
            h.frames(if (id == Hud.MAP) 30 else 4)
            if (id == Hud.CRAFTING) { tap(ui.vw * 0.5f - 300f, 200f); h.frames(2) }
            h.screenshot(name)
            scene.hud.close()
            h.frames(2)
        }
        scene.hud.openNote(0); h.frames(3); h.screenshot("11_note"); scene.hud.close()
        scene.game.engine.settings.showProfiler = true
        h.frames(30); h.screenshot("12_profiler")
        scene.game.engine.settings.showProfiler = false
    }

    private fun water(seed: Long) {
        newGame(seed)
        scene.weather.set(Weather.CLEAR, 99999f)
        val p = scene.player
        scene.player.firstPerson = true
        // walk downhill from the spawn until the waterline, remember the seaward direction
        var x = p.pos.x; var z = p.pos.z
        var dirX = 0f; var dirZ = 1f
        for (step in 0 until 200) {
            var best = Float.MAX_VALUE
            for (k in 0 until 16) {
                val a = k * 0.3927f
                val hh = scene.gen.heightAt((x + kotlin.math.cos(a) * 3f).toInt(), (z + kotlin.math.sin(a) * 3f).toInt())
                if (hh < best) { best = hh; dirX = kotlin.math.cos(a); dirZ = kotlin.math.sin(a) }
            }
            if (scene.gen.heightAt(x.toInt(), z.toInt()) < wildfrontier.gen.WorldGen.SEA + 0.6f) break
            x += dirX; z += dirZ
        }
        val seaYaw = kotlin.math.atan2(dirX, -dirZ)
        tp(x - dirX * 3f, z - dirZ * 3f)
        scene.dayNight.hour = 11f
        look(seaYaw, -0.13f); h.frames(8); h.screenshot("water_day")
        look(seaYaw, -0.6f); h.frames(4); h.screenshot("water_shore_down")
        look(seaYaw + 1.2f, -0.08f); h.frames(4); h.screenshot("water_along_coast")
        scene.dayNight.hour = 18.3f
        look(seaYaw, -0.05f); h.frames(8); h.screenshot("water_sunset")
        look(seaYaw - 0.9f, -0.05f); h.frames(4); h.screenshot("water_sunset_b")
        scene.dayNight.hour = 13f
        // wade out and look back at the land: reflections of trees and terrain
        tp(x + dirX * 9f, z + dirZ * 9f)
        look(seaYaw + 3.14f, 0.02f); h.frames(8); h.screenshot("water_reflection")
        scene.dayNight.hour = 22f
        look(seaYaw, 0.0f); h.frames(8); h.screenshot("water_night")
        stats("water")
    }

    private fun tour(seed: Long) {
        newGame(seed)
        val p = scene.player
        val sx = p.pos.x; val sz = p.pos.z
        scene.weather.set(Weather.CLEAR, 99999f)
        val stops = listOf(
            Triple(wildfrontier.gen.Biome.DECIDUOUS, 10.5f, "forest"), Triple(wildfrontier.gen.Biome.CONIFER, 15.5f, "conifer"),
            Triple(wildfrontier.gen.Biome.MOUNTAIN, 9f, "mountain"), Triple(wildfrontier.gen.Biome.JUNGLE, 12f, "jungle"),
            Triple(wildfrontier.gen.Biome.MEADOW, 18.3f, "meadow_sunset"), Triple(wildfrontier.gen.Biome.SNOW, 13f, "snow"),
            Triple(wildfrontier.gen.Biome.SWAMP, 7.2f, "swamp_dawn"), Triple(wildfrontier.gen.Biome.BEACH, 23.5f, "beach_night"))
        for ((biome, hour, name) in stops) {
            val pos = findBiome(biome, sx, sz, if (biome == wildfrontier.gen.Biome.SWAMP || biome == wildfrontier.gen.Biome.BEACH) 0.5f else 3f)
            if (pos == null) { println("biome $name not found"); continue }
            tp(pos[0], pos[1])
            scene.dayNight.hour = hour
            look(0.8f, -0.1f)
            h.frames(8)
            h.screenshot("tour_$name")
            stats(name)
        }
        // weather: storm at the last stop
        tp(sx, sz)
        scene.dayNight.hour = 14f
        scene.debugFreezeTime = false
        scene.weather.set(Weather.STORM, 9999f)
        h.until(1500, 0.5f) { scene.weather.rain > 0.85f }
        scene.debugFreezeTime = true
        look(2.4f, -0.05f)
        h.frames(40)
        h.screenshot("tour_storm")
    }

    private fun animals(seed: Long) {
        newGame(seed)
        val p = scene.player
        val pos = findBiome(wildfrontier.gen.Biome.MEADOW, p.pos.x, p.pos.z, 3f)!!
        tp(pos[0], pos[1])
        scene.dayNight.hour = 11f
        scene.weather.set(Weather.CLEAR, 99999f)
        val a = scene.animals
        fun at(dx: Float, dz: Float): FloatArray {
            val x = p.pos.x + dx; val z = p.pos.z + dz
            return floatArrayOf(x, scene.world.surfaceY(floorInt(x), floorInt(z)) + 1.05f, z)
        }
        var q = at(0f, -5f); a.spawn(0, q[0], q[1], q[2], 900, false, true)
        q = at(2.5f, -6f); a.spawn(0, q[0], q[1], q[2], 900, false, false)
        q = at(-2.5f, -4.5f); a.spawn(1, q[0], q[1], q[2], 901, false, true)
        q = at(1.2f, -3f); a.spawn(2, q[0], q[1], q[2], 902, false, true)
        q = at(-0.8f, -3.2f); a.spawn(2, q[0], q[1], q[2], 902, true, false)
        look(0f, -0.2f)
        h.frames(3)
        h.screenshot("animals_close")
        h.frames(45)
        h.screenshot("animals_after_1.5s")
        println("animal count=${a.count} deer=${a.speciesCount[0]} wolves=${a.speciesCount[1]} rabbits=${a.speciesCount[2]}")
    }

    private fun gameplay(seed: Long) {
        newGame(seed)
        println("gameplay scenario placeholder")
    }

    private fun saveTest(seed: Long) { newGame(seed) }
    private fun perf(seed: Long) { newGame(seed); stats("perf") }
}
