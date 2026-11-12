package wildfrontier

import wildcore.anim.Animator
import wildcore.anim.SkinnedMesh
import wildcore.core.Engine
import wildcore.core.Log
import wildcore.core.Quality
import wildcore.core.Scene
import wildcore.ecs.EcsWorld
import wildcore.math.Mat4
import wildcore.math.floorInt
import wildcore.world.Blocks
import wildcore.world.Chunk
import wildcore.world.ToolKind
import wildcore.world.VoxelWorld
import wildfrontier.animals.AnimalSystem
import wildfrontier.content.B
import wildfrontier.content.I
import wildfrontier.content.Items
import wildfrontier.content.Recipes
import wildfrontier.content.Tex
import wildfrontier.env.DayNight
import wildfrontier.env.Weather
import wildfrontier.farming.Farming
import wildfrontier.gen.Biome
import wildfrontier.gen.Column
import wildfrontier.gen.WorldGen
import wildfrontier.player.Player
import wildfrontier.player.PlayerModel
import wildfrontier.render.FarTerrain
import wildfrontier.render.ModelRenderer
import wildfrontier.render.Particles
import wildfrontier.render.WorldRenderer
import wildfrontier.save.SaveGame
import wildfrontier.save.readInventory
import wildfrontier.save.writeInventory
import wildfrontier.story.Story
import wildfrontier.ui.Hud
import wildfrontier.ui.Ui
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.File
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt

/** Gameplay scene: owns the world, every simulation system and the render pipeline, and wires them together. */
class GameScene(val game: WildFrontierGame, val seed: Long, private val loadExisting: Boolean) : Scene {
    private val engine: Engine get() = game.engine
    val ui: Ui get() = game.ui
    val audio: GameAudio get() = game.audio

    lateinit var gen: WorldGen; private set
    lateinit var world: VoxelWorld; private set
    lateinit var save: SaveGame; private set
    val renderer = WorldRenderer(game.engine)
    val modelRenderer = ModelRenderer(game.engine)
    lateinit var particles: Particles; private set
    private var farTerrain: FarTerrain? = null

    val ecs = EcsWorld()
    val player = Player()
    private val playerModel = PlayerModel()
    private val playerAnimator = Animator(playerModel.skeleton)
    private var playerMesh: SkinnedMesh? = null
    private var toolMesh: SkinnedMesh? = null
    private var raftMesh: SkinnedMesh? = null
    lateinit var animals: AnimalSystem; private set
    lateinit var drops: DropSystem; private set
    lateinit var interaction: Interaction; private set
    lateinit var farming: Farming; private set
    lateinit var story: Story; private set
    lateinit var weather: Weather; private set
    val dayNight = DayNight()
    val hud = Hud(this)

    val column = Column()
    val explored = HashSet<Long>()
    var ready = false; private set
    var breath = 1f; private set
    var playTime = 0f; private set
    private var lastDt = 0.016f
    private var slowTimer = 0f
    private var autosaveTimer = 0f
    private var governorTimer = 0f
    private var coolTime = 0f
    private var lowFpsTime = 0f
    private var loadStart = 0L
    private var sleepPhase = 0
    private var sleepTimer = 0f
    private var fireLevel = 0f
    private var sheltered = false
    private var ambientC = 18f
    private var stepVariant = 0
    private val mat = FloatArray(16)
    private var secUpdate = 0; private var secRender = 0
    /** Scripted-test hook: freezes the clock and weather when set. */
    var debugFreezeTime = false

    // ------------------------------------------------------------------ lifecycle

    override fun onEnter(engine: Engine) {
        Items.registerAll(); Recipes.registerAll()
        gen = WorldGen(seed)
        save = SaveGame(File(engine.platform.filesDir, "saves/world"))
        if (!loadExisting) save.deleteAll()
        world = VoxelWorld(engine.jobs, gen, save, engine.profiler, B.BEDROCK)
        world.meshSink = renderer
        weather = Weather(seed)
        animals = AnimalSystem(this)
        drops = DropSystem(this)
        interaction = Interaction(this)
        farming = Farming(this)
        story = Story(this)
        particles = Particles(engine, 2200)
        val s = gen.structures.spawn
        player.teleport(s[0] + 0.5f, s[1] + 0.2f, s[2] + 0.5f)
        player.spawn.set(player.pos)
        player.yaw = 2.4f
        var loaded = false
        if (loadExisting) {
            try { loaded = loadLevel() } catch (e: Exception) { Log.e("Game", "save could not be loaded", e) }
        }
        if (!loaded) story.sites.add(gen.structures.wreck())
        applyBackpack()
        playerAnimator.play(playerModel.idle, 0f)
        loadStart = System.nanoTime()
        secUpdate = engine.profiler.section("update"); secRender = engine.profiler.section("render")
        audio.sfxVolume = engine.settings.sfxVolume; audio.musicVolume = engine.settings.musicVolume
        Log.i("Game", "world seed=$seed loaded=$loaded spawn=${s[0]},${s[1]},${s[2]}")
    }

    override fun onContextCreated(engine: Engine) {
        val p = engine.settings.profile
        renderer.init()
        modelRenderer.init(renderer)
        particles.init(renderer)
        particles.icons = ui.iconTexture
        world.viewDistance = p.viewDistance
        world.leafInnerFaces = p.leafInnerFaces
        renderer.layers.clear()
        farTerrain?.let { /* GL objects of the previous context are gone */ }
        if (p.farTerrainRings > 0) {
            val ft = farTerrain ?: FarTerrain(engine, renderer, gen).also { farTerrain = it }
            ft.radiusTiles = p.viewDistance / 4 + p.farTerrainRings
            ft.init()
            renderer.layers.add(ft)
        } else farTerrain = null
        renderer.layers.add(modelRenderer)
        renderer.layers.add(particles)
        animals.initGpu()
        playerMesh = SkinnedMesh(engine.gl, playerModel.body)
        toolMesh = SkinnedMesh(engine.gl, playerModel.tool)
        raftMesh = SkinnedMesh(engine.gl, playerModel.raft)
        world.chunks.forEach { it.mesh = null }
        world.remeshAll()
        hud.screens.onContextLost()
        game.applyFrameRate()
    }

    override fun onResize(engine: Engine, width: Int, height: Int) = renderer.resize(width, height)

    /** Rebuilds GPU resources for a new graphics tier without leaving the game. */
    fun applyQuality() {
        if (!engine.hasContext) return
        world.chunks.forEach { c -> c.mesh?.dispose(); c.mesh = null }
        farTerrain?.dispose()
        renderer.dispose()
        onContextCreated(engine)
        renderer.resize(engine.width, engine.height)
        ready = false
        loadStart = System.nanoTime()
    }

    override fun onPause(engine: Engine) { saveGame(true) }

    override fun onExit(engine: Engine) {
        audio.stopAmbience()
        if (engine.hasContext) {
            world.chunks.forEach { c -> c.mesh?.dispose(); c.mesh = null }
            farTerrain?.dispose()
            renderer.dispose()
        }
    }

    // ------------------------------------------------------------------ helpers used by other systems

    /** Adds items to the inventory; whatever does not fit is dropped at the player's feet. */
    fun give(id: Int, count: Int) {
        if (count <= 0) return
        val left = player.inventory.add(id, count)
        if (count - left > 0) { hud.notifyPickup(id, count - left); story.onItemGained(id, count - left) }
        if (left > 0) drops.spawn(id, left, player.pos.x, player.pos.y + 1f, player.pos.z, delay = 1.5f)
    }

    fun applyBackpack() { player.inventory.activeSize = if (player.backpackBonus) 36 else 27 }

    /** 0..1 warmth from campfires (and weakly torches) within [radius] blocks. */
    fun nearFire(x: Float, y: Float, z: Float, radius: Float): Float {
        var best = 0f
        val cx = Math.floorDiv(x.toInt(), 16); val cz = Math.floorDiv(z.toInt(), 16)
        for (dz in -1..1) for (dx in -1..1) {
            val c = world.getChunk(cx + dx, cz + dz) ?: continue
            for (k in 0 until c.emitterCount) {
                val idx = c.emitters[k]
                val id = c.blocks[idx].toInt() and 255
                if (id != B.CAMPFIRE && id != B.TORCH) continue
                val ex = c.cx * 16 + ((idx shr 7) and 15) + 0.5f; val ey = (idx and 127) + 0.5f; val ez = c.cz * 16 + (idx shr 11) + 0.5f
                val d = sqrt((ex - x) * (ex - x) + (ey - y) * (ey - y) + (ez - z) * (ez - z))
                val r = if (id == B.CAMPFIRE) radius else radius * 0.35f
                if (d < r) best = maxOf(best, (1f - d / r) * (if (id == B.CAMPFIRE) 1f else 0.4f))
            }
        }
        return best
    }

    fun onPlayerHurt() { audio.play("hurt", 0.9f) }
    fun onPlayerSwing() { playerAnimator.playOverlay(playerModel.swing, playerModel.swingMask) }

    fun trySleep(x: Int, y: Int, z: Int) {
        if (sleepPhase != 0) return
        if (!(dayNight.isNight || dayNight.hour > 18.5f || player.survival.energy < 35f)) { hud.message("Спать ещё рано — дождитесь вечера"); return }
        player.spawn.set(x + 0.5f, y + 0.4f, z + 0.5f)
        sleepPhase = 1; sleepTimer = 0f
    }

    fun respawn() {
        player.dead = false
        player.survival.reset()
        player.statDeaths++
        val sx = floorInt(player.spawn.x); val sz = floorInt(player.spawn.z)
        val sy = world.surfaceY(sx, sz)
        player.teleport(player.spawn.x, if (sy >= 0) maxOf(player.spawn.y, sy + 1.05f) else player.spawn.y, player.spawn.z)
        player.onRaft = -1
        breath = 1f
        playerAnimator.play(playerModel.idle, 0f)
    }

    // ------------------------------------------------------------------ update

    override fun update(engine: Engine, dt: Float) {
        val prof = engine.profiler
        prof.begin(secUpdate)
        lastDt = dt
        modelRenderer.beginFrame()
        ui.beginInput(engine.input.drain(), dt)
        val cam = renderer.camera

        if (!ready) {
            world.update(player.pos.x, player.pos.z)
            farTerrain?.update(player.pos.x, player.pos.z)
            val need = minOf(3, world.viewDistance - 1)
            hud.loadingProgress = (world.meshedRadius() / (need * 16f)).coerceIn(0f, 1f)
            if (world.isAreaReady(player.pos.x, player.pos.z, need)) {
                ready = true
                prof.worldLoadMs = (System.nanoTime() - loadStart) / 1_000_000f
                // make sure the player stands on the surface (terrain edits may have changed it)
                if (!loadExisting || world.isSolid(floorInt(player.pos.x), floorInt(player.pos.y + 0.5f), floorInt(player.pos.z))) {
                    val sy = world.surfaceY(floorInt(player.pos.x), floorInt(player.pos.z))
                    if (sy >= 0) player.teleport(player.pos.x, sy + 1.05f, player.pos.z)
                }
                Log.i("Game", "world ready in ${prof.worldLoadMs.toInt()} ms, ${world.loadedCount} chunks")
            }
            player.eye.set(player.pos.x, player.pos.y + 1.62f, player.pos.z)
            cam.pos.set(player.eye); cam.yaw = player.yaw; cam.pitch = player.pitch
            updateEnvironment(dt)
            prof.end(secUpdate)
            return
        }
        playTime += dt

        // --- player
        if (!hud.modalOpen) player.look(hud.lookDx, hud.lookDy)
        if (player.onRaft < 0) player.update(dt, world, engine.settings.autoJump) else { player.eye.set(player.pos.x, player.pos.y + 1.1f, player.pos.z); player.swingTime = maxOf(0f, player.swingTime - dt) }
        handleMovementEvents()
        player.placeCamera(world, cam.pos)
        cam.yaw = player.yaw; cam.pitch = player.pitch
        cam.fovY = wildcore.math.approach(cam.fovY, if (player.sprinting) 71f else 65f, dt * 30f)
        cam.update()

        // --- actions
        interaction.updateTarget()
        if (!hud.modalOpen) {
            interaction.updateBreak(dt, hud.breakHeld, hud.breakPressed)
            if (hud.useClicked) interaction.use()
            if (hud.interactClicked) interaction.interact()
        } else interaction.updateBreak(dt, false, false)
        interaction.updateEntities(dt)

        // --- world & simulation
        world.update(player.pos.x, player.pos.z)
        updateEnvironment(dt)
        slowTimer -= dt
        if (slowTimer <= 0f) { slowTimer = 0.5f; slowUpdate(0.5f) }
        updateSurvival(dt)
        animals.update(dt)
        drops.update(dt)
        farming.update(dt)
        story.update(dt, column.biome)
        updateParticles(dt)
        updateSleep(dt)
        updateAudio(dt)

        // --- queue models
        queuePlayer(dt)
        animals.queueRender(dt, engine.time.frame)
        queueRafts()

        farTerrain?.let { ft ->
            ft.update(cam.pos.x, cam.pos.z)
            if (engine.time.frame % 10L == 0L) ft.nearRadius = maxOf(0f, world.meshedRadius() - 12f)
        }
        autosaveTimer += dt
        if (autosaveTimer > 120f) { autosaveTimer = 0f; saveGame(false) }
        governor(dt)
        prof.activeEntities = ecs.aliveCount
        prof.end(secUpdate)
    }

    private fun handleMovementEvents() {
        val p = player
        if (p.footstep || p.justLanded) {
            val bx = floorInt(p.pos.x); val by = floorInt(p.pos.y - 0.2f); val bz = floorInt(p.pos.z)
            val below = world.getBlock(bx, by, bz)
            val mat = if (p.body.submerged > 0.15f) wildcore.world.SoundMat.WATER else Blocks.get(below).sound
            val vol = if (p.justLanded) minOf(1f, 0.5f + p.landingFall * 0.12f) else if (p.crouching) 0.25f else if (p.sprinting) 0.9f else 0.6f
            audio.step(mat, p.pos.x, p.pos.y, p.pos.z, vol, stepVariant++)
            if (p.justLanded && p.landingFall > 2f) particles.puff(p.pos.x, p.pos.y + 0.05f, p.pos.z, 6, 0x88B8A888.toInt(), 0.14f, 0.5f)
        }
        if (p.justLanded && p.landingFall > 3.6f && p.body.submerged < 0.2f) {
            p.hurt((p.landingFall - 3f) * 7f, "падение")
            onPlayerHurt()
        }
        if (p.swimming && engine.time.frame % 40L == 0L && p.speed > 0.8f) audio.step(wildcore.world.SoundMat.WATER, p.pos.x, p.pos.y, p.pos.z, 0.5f, stepVariant++)
    }

    private fun updateEnvironment(dt: Float) {
        val env = renderer.env
        val cam = renderer.camera
        if (!debugFreezeTime) {
            val dayBefore = dayNight.day
            dayNight.update(dt)
            weather.update(dt)
            if (dayNight.day != dayBefore) { player.statDaysSurvived++; hud.banner("Рассвет", "День ${dayNight.day}") }
        }
        val far = farTerrain?.farDistance ?: (world.viewDistance * 16f)
        dayNight.apply(env, weather.overcast, weather.fog, far)
        cam.far = far * 1.35f
        env.time = engine.time.elapsed.toFloat()
        env.cloudCover = weather.cloudCover
        env.cloudDark = weather.overcast
        env.wetness = weather.wetness
        env.lightning = weather.lightning
        env.windX = weather.windX; env.windZ = weather.windZ
        env.windStrength = weather.wind; env.gust = weather.gust
        if (weather.thunderNow) audio.play("thunder", 0.9f, 0.85f + particles.rng.nextFloat() * 0.3f)
        // underwater: dense tinted fog and a muffled soundscape
        val eyeBlock = world.getBlock(floorInt(cam.pos.x), floorInt(cam.pos.y), floorInt(cam.pos.z))
        env.underwater = Blocks.liquid[eyeBlock]
        if (env.underwater) {
            val k = 0.35f + 0.65f * env.daylight
            env.fogTint.set(0.02f * k, 0.10f * k, 0.13f * k)
            env.fogDensity = 0.085f
        }
        renderer.damageFlash = player.hurtFlash
        particles.lightR = minOf(1.2f, env.ambientSky.x * 1.6f + env.keyColor.x * 0.42f)
        particles.lightG = minOf(1.2f, env.ambientSky.y * 1.6f + env.keyColor.y * 0.42f)
        particles.lightB = minOf(1.2f, env.ambientSky.z * 1.6f + env.keyColor.z * 0.42f)
        particles.windX = weather.windX * weather.wind
        particles.windZ = weather.windZ * weather.wind
    }

    /** Twice-per-second bookkeeping: biome lookup, shelter, fire proximity, map exploration. */
    private fun slowUpdate(dt: Float) {
        val p = player
        gen.sample(floorInt(p.pos.x), floorInt(p.pos.z), column)
        val surface = world.surfaceY(floorInt(p.pos.x), floorInt(p.pos.z))
        sheltered = surface > p.pos.y + 1.6f
        fireLevel = nearFire(p.pos.x, p.pos.y + 1f, p.pos.z, 6.5f)
        val underground = sheltered && p.pos.y < column.height - 6f
        ambientC = if (underground) 11f else 17f + column.temp * 21f - maxOf(0f, p.pos.y - WorldGen.SEA) * 0.13f - 7f * (1f - renderer.env.daylight) - 4f * weather.rain
        val cx = Math.floorDiv(p.pos.x.toInt(), 16); val cz = Math.floorDiv(p.pos.z.toInt(), 16)
        for (dz in -4..4) for (dx in -4..4) if (dx * dx + dz * dz <= 18) explored.add(Chunk.key(cx + dx, cz + dz))
        engine.profiler.usedMemMb = engine.platform.usedMemoryMb()
        engine.profiler.gpuMemEstimateMb = renderer.gpuMemoryEstimateMb()
    }

    private fun updateSurvival(dt: Float) {
        val p = player
        if (p.dead) return
        val sv = p.survival
        val working = interaction.breakProgress > 0f
        val resting = p.speed < 0.2f && fireLevel > 0.3f
        sv.update(dt, ambientC, p.clothingWarmth(), fireLevel, p.body.submerged > 0.4f, weather.isRaining, sheltered, p.sprinting, working, resting)
        // breath: about 25 seconds under water, then drowning
        if (p.headUnderwater) {
            breath = maxOf(0f, breath - dt / 25f)
            if (breath <= 0f) { sv.damage(dt * 9f, "утопление"); if ((engine.time.frame % 30L) == 0L) { p.hurtFlash = 1f; onPlayerHurt() } }
        } else breath = minOf(1f, breath + dt * 0.5f)
        if (sv.health <= 0f) {
            p.dead = true
            p.onRaft = -1
            playerAnimator.play(playerModel.die, 0.1f)
            audio.play("hurt", 1f, 0.7f)
        }
    }

    private fun updateSleep(dt: Float) {
        if (sleepPhase == 0) { renderer.fade = maxOf(0f, renderer.fade - dt * 1.5f); return }
        sleepTimer += dt
        if (sleepPhase == 1) {
            renderer.fade = minOf(1f, sleepTimer / 0.9f)
            if (sleepTimer >= 1.1f) {
                val sv = player.survival
                if (dayNight.isNight || dayNight.hour > 18.5f) {
                    if (dayNight.hour > 12f) { dayNight.day++; player.statDaysSurvived++ }
                    dayNight.hour = 6.4f
                } else dayNight.hour = minOf(23.5f, dayNight.hour + 2f)
                sv.energy = minOf(100f, sv.energy + 78f)
                sv.hunger = maxOf(4f, sv.hunger - 10f); sv.thirst = maxOf(4f, sv.thirst - 12f)
                sv.health = minOf(100f, sv.health + 20f)
                sleepPhase = 2; sleepTimer = 0f
                saveGame(false)
                hud.message("Вы выспались. День ${dayNight.day}")
            }
        } else {
            renderer.fade = maxOf(0f, 1f - sleepTimer / 1.2f)
            if (sleepTimer >= 1.2f) sleepPhase = 0
        }
    }

    // ------------------------------------------------------------------ particles & audio

    private fun updateParticles(dt: Float) {
        val pt = particles
        val r = pt.rng
        val cam = renderer.camera.pos
        val scale = pt.capacity / 900f
        val outdoors = !(sheltered && player.pos.y < column.height - 4f)
        // precipitation
        if (weather.rain > 0.05f && outdoors) {
            val snow = column.temp < -0.55f
            val n = (weather.rain * (if (snow) 90f else 240f) * scale * dt + r.nextFloat()).toInt()
            for (i in 0 until n) {
                val a = r.nextFloat() * 6.283f; val d = sqrt(r.nextFloat()) * 14f
                val x = cam.x + cos(a) * d + player.body.vel.x * 0.4f; val z = cam.z + sin(a) * d + player.body.vel.z * 0.4f
                val y = cam.y + 5f + r.nextFloat() * 5f
                if (world.surfaceY(floorInt(x), floorInt(z)) > y) continue
                if (snow) pt.emit(Particles.SOFT, x, y, z, pt.windX * 0.8f, -1.5f, pt.windZ * 0.8f, 6f, 0.035f, 0xDDFFFFFF.toInt(), 0f, 0f)
                else pt.emit(Particles.STREAK, x, y, z, pt.windX * 2.5f, -17f, pt.windZ * 2.5f, 1.1f, 0.03f, 0x66B8D0E8, 0f, 0f, 8f)
            }
        }
        val night = dayNight.isNight
        val b = column.biome
        // fireflies on warm nights; butterflies over meadows by day
        if (night && weather.rain < 0.1f && outdoors && (b == Biome.MEADOW || b == Biome.DECIDUOUS || b == Biome.GROVE || b == Biome.SWAMP || b == Biome.JUNGLE)) {
            if (r.nextFloat() < dt * 4f * scale) {
                val x = cam.x + r.range(-14f, 14f); val z = cam.z + r.range(-14f, 14f)
                val gy = world.surfaceY(floorInt(x), floorInt(z))
                if (gy > 0) pt.emit(Particles.GLOW, x, gy + 1.2f + r.nextFloat() * 1.5f, z, r.range(-0.3f, 0.3f), r.range(-0.1f, 0.15f), r.range(-0.3f, 0.3f), r.range(3f, 6f), 0.09f, 0xFFD8FF70.toInt())
            }
        } else if (!night && weather.rain < 0.1f && outdoors && (b == Biome.MEADOW || b == Biome.GROVE)) {
            if (r.nextFloat() < dt * 1.2f * scale) {
                val x = cam.x + r.range(-10f, 10f); val z = cam.z + r.range(-10f, 10f)
                val gy = world.surfaceY(floorInt(x), floorInt(z))
                val colors = intArrayOf(0xFFF2D24A.toInt(), 0xFFFFFFFF.toInt(), 0xFFE8803A.toInt(), 0xFF8AB4F0.toInt())
                if (gy > 0) pt.emit(Particles.SOFT, x, gy + 1.3f + r.nextFloat(), z, r.range(-0.9f, 0.9f), r.range(-0.2f, 0.4f), r.range(-0.9f, 0.9f), r.range(4f, 7f), 0.045f, colors[r.nextInt(4)], 0f, 0.2f)
            }
        }
        // falling leaves in windy forests
        if (!night && outdoors && (b == Biome.DECIDUOUS || b == Biome.GROVE) && r.nextFloat() < dt * 0.8f * weather.wind * scale) {
            val x = cam.x + r.range(-9f, 9f); val z = cam.z + r.range(-9f, 9f)
            pt.emit(Particles.FRAGMENT, x, cam.y + r.range(2f, 6f), z, pt.windX * 0.8f, -0.4f, pt.windZ * 0.8f, 5f, 0.06f, 0xFFFFFFFF.toInt(), 0.9f, 1.4f,
                r.nextFloat() * 0.8f, Tex.of("oak_leaves").toFloat(), r.range(-3f, 3f))
        }
        // fires: flames, sparks and smoke for every campfire/torch in the nearby chunks
        val cx = Math.floorDiv(cam.x.toInt(), 16); val cz = Math.floorDiv(cam.z.toInt(), 16)
        for (dz in -1..1) for (dx in -1..1) {
            val c = world.getChunk(cx + dx, cz + dz) ?: continue
            for (k in 0 until c.emitterCount) {
                val idx = c.emitters[k]
                val id = c.blocks[idx].toInt() and 255
                val fx = c.cx * 16 + ((idx shr 7) and 15) + 0.5f; val fy = (idx and 127).toFloat(); val fz = c.cz * 16 + (idx shr 11) + 0.5f
                if (id == B.CAMPFIRE) {
                    if (r.nextFloat() < dt * 22f) pt.emit(Particles.GLOW, fx + r.range(-0.22f, 0.22f), fy + 0.42f, fz + r.range(-0.22f, 0.22f), r.range(-0.1f, 0.1f), r.range(0.9f, 1.7f), r.range(-0.1f, 0.1f), r.range(0.35f, 0.6f), r.range(0.16f, 0.3f), 0xFFFF9A30.toInt())
                    if (r.nextFloat() < dt * 5f) pt.emit(Particles.GLOW, fx + r.range(-0.2f, 0.2f), fy + 0.6f, fz + r.range(-0.2f, 0.2f), r.range(-0.6f, 0.6f), r.range(1.6f, 3.2f), r.range(-0.6f, 0.6f), r.range(0.6f, 1.2f), 0.035f, 0xFFFFD070.toInt(), 1.5f)
                    if (r.nextFloat() < dt * 3f) pt.emit(Particles.SOFT, fx, fy + 0.9f, fz, pt.windX * 0.3f + r.range(-0.1f, 0.1f), r.range(0.7f, 1.1f), pt.windZ * 0.3f + r.range(-0.1f, 0.1f), r.range(2f, 3.5f), r.range(0.22f, 0.36f), 0x44A0A0A0, -0.1f, 0.3f)
                } else if (id == B.TORCH) {
                    if (r.nextFloat() < dt * 9f) pt.emit(Particles.GLOW, fx + r.range(-0.03f, 0.03f), fy + 0.68f, fz + r.range(-0.03f, 0.03f), 0f, r.range(0.3f, 0.6f), 0f, r.range(0.25f, 0.45f), r.range(0.07f, 0.12f), 0xFFFFA840.toInt())
                }
            }
        }
        pt.update(dt) { x, z -> world.surfaceY(floorInt(x), floorInt(z)) + 1.02f }
    }

    private fun updateAudio(dt: Float) {
        val cam = renderer.camera
        audio.setListener(cam.pos, cam.right)
        val alt = ((player.pos.y - WorldGen.SEA) / 60f).coerceIn(0f, 1f)
        val underground = sheltered && player.pos.y < column.height - 6f
        val wind = if (underground) 0.05f else (0.25f + weather.wind * 0.3f + alt * 0.4f).coerceIn(0f, 1f)
        val surf = if (underground) 0f else (1f - ((column.height - WorldGen.SEA).coerceAtLeast(0f) / 9f)).coerceIn(0f, 1f) * (if (column.biome == Biome.BEACH || column.biome == Biome.OCEAN || column.biome == Biome.RIVER) 1f else 0.35f)
        val forest = column.biome == Biome.DECIDUOUS || column.biome == Biome.CONIFER || column.biome == Biome.JUNGLE || column.biome == Biome.GROVE || column.biome == Biome.MEADOW || column.biome == Biome.SWAMP
        val day = renderer.env.daylight
        val birds = if (underground || !forest) 0f else day * (1f - weather.rain) * (if (column.biome == Biome.MEADOW) 0.6f else 1f)
        val crickets = if (underground || !forest) 0f else (1f - day) * (1f - weather.rain) * (if (column.temp < -0.3f) 0.2f else 1f)
        audio.updateAmbience(dt, wind, surf, birds, crickets, if (underground) 0f else weather.rain * (if (sheltered) 0.5f else 1f), fireLevel, renderer.env.underwater)
    }

    // ------------------------------------------------------------------ model queue

    private fun queuePlayer(dt: Float) {
        val p = player
        val m = playerModel
        val an = playerAnimator
        val clip = when {
            p.dead -> m.die
            p.onRaft >= 0 -> m.sit
            p.swimming -> m.swim
            p.airTime > 0.18f -> m.air
            p.crouching -> if (p.speed > 0.3f) m.crouchWalk else m.crouchIdle
            p.speed > 5.2f -> m.run
            p.speed > 0.35f -> m.walk
            else -> m.idle
        }
        an.play(clip, if (clip === m.die) 0.1f else 0.16f)
        an.speed = when (clip) { m.walk -> (p.speed / Player.WALK).coerceIn(0.5f, 1.4f); m.run -> (p.speed / Player.SPRINT).coerceIn(0.7f, 1.2f); m.crouchWalk -> (p.speed / Player.CROUCH).coerceIn(0.5f, 1.3f); else -> 1f }
        an.update(dt)
        if (p.firstPerson) return
        val cam = renderer.camera.pos
        Mat4.rotationY(mat, 0, p.modelYaw)
        mat[12] = p.pos.x - cam.x; mat[13] = p.pos.y - cam.y; mat[14] = p.pos.z - cam.z
        val inst = modelRenderer.next()
        inst.mesh = playerMesh; inst.boneCount = m.skeleton.count
        an.palette(mat, inst.palette)
        inst.sky = if (sheltered) 0.5f else 1f; inst.blockLight = fireLevel * 0.8f; inst.hurt = p.hurtFlash * 0.5f; inst.castShadow = true
        val held = p.heldItem
        if (!held.isEmpty && !p.dead) {
            val def = Items.get(held.id)
            if (def != null && (def.toolKind != ToolKind.NONE || def.durability > 0)) {
                val t = modelRenderer.next()
                t.mesh = toolMesh; t.boneCount = m.skeleton.count
                System.arraycopy(inst.palette, 0, t.palette, 0, m.skeleton.count * 16)
                t.sky = inst.sky; t.blockLight = inst.blockLight; t.hurt = 0f; t.castShadow = false
            }
        }
    }

    private fun queueRafts() {
        val cam = renderer.camera.pos
        interaction.rafts.each(ecs.highWater) { _, r ->
            Mat4.rotationY(mat, 0, r.yaw)
            mat[12] = r.pos.x - cam.x; mat[13] = r.pos.y - cam.y; mat[14] = r.pos.z - cam.z
            val inst = modelRenderer.next()
            inst.mesh = raftMesh; inst.boneCount = 1
            System.arraycopy(mat, 0, inst.palette, 0, 16)
            inst.sky = 1f; inst.blockLight = 0f; inst.hurt = 0f; inst.castShadow = true
        }
    }

    // ------------------------------------------------------------------ performance governor

    /**
     * Protects the device: lowers the effective graphics tier when the OS reports thermal pressure or
     * (in automatic mode) when the frame rate stays far below target, and restores it once cool.
     */
    private fun governor(dt: Float) {
        governorTimer += dt
        if (governorTimer < 2f) return
        val s = engine.settings
        val thermal = engine.platform.thermalStatus()
        engine.profiler.thermal = thermal
        val target = if (s.fpsLimit > 0) minOf(s.fpsLimit, s.profile.targetFps) else s.profile.targetFps
        val fps = engine.profiler.fps
        if (ready && fps > 1f && fps < target * 0.55f) lowFpsTime += governorTimer else lowFpsTime = maxOf(0f, lowFpsTime - governorTimer)
        if (thermal <= 1) coolTime += governorTimer else coolTime = 0f
        governorTimer = 0f
        var want = s.effectiveQuality
        if (s.thermalThrottle && thermal >= 3 && want != Quality.LOW) want = Quality.values()[want.ordinal - 1]
        else if (!s.qualityChosenByUser && lowFpsTime > 12f && want != Quality.LOW) { want = Quality.values()[want.ordinal - 1]; s.quality = want }
        else if (coolTime > 90f && want.ordinal < s.quality.ordinal) want = Quality.values()[want.ordinal + 1]
        if (want != s.effectiveQuality) {
            val lowering = want.ordinal < s.effectiveQuality.ordinal
            s.effectiveQuality = want
            lowFpsTime = 0f; coolTime = 0f
            hud.message(if (lowering) "Графика снижена для защиты устройства" else "Качество графики восстановлено")
            applyQuality()
        }
        game.applyFrameRate(thermal >= 2 && s.thermalThrottle)
    }

    // ------------------------------------------------------------------ render

    override fun render(engine: Engine) {
        val prof = engine.profiler
        prof.begin(secRender)
        renderer.render(world) { hud.frame(lastDt) }
        prof.end(secRender)
    }

    // ------------------------------------------------------------------ persistence

    fun saveGame(sync: Boolean) {
        if (!::world.isInitialized) return
        try {
            val bos = ByteArrayOutputStream(8192)
            val o = DataOutputStream(bos)
            o.writeInt(1)                     // payload version
            o.writeLong(seed)
            o.writeInt(dayNight.day); o.writeFloat(dayNight.hour); o.writeFloat(playTime)
            o.writeInt(weather.type); o.writeFloat(weather.timeLeft)
            val p = player
            o.writeFloat(p.pos.x); o.writeFloat(p.pos.y); o.writeFloat(p.pos.z); o.writeFloat(p.yaw); o.writeFloat(p.pitch)
            o.writeBoolean(p.firstPerson); o.writeInt(p.selected)
            o.writeFloat(p.spawn.x); o.writeFloat(p.spawn.y); o.writeFloat(p.spawn.z)
            val sv = p.survival
            o.writeFloat(sv.health); o.writeFloat(sv.hunger); o.writeFloat(sv.thirst); o.writeFloat(sv.energy); o.writeFloat(sv.temperature); o.writeFloat(sv.wetness)
            writeInventory(o, p.inventory); writeInventory(o, p.equipment)
            o.writeInt(p.statBlocksMined); o.writeInt(p.statBlocksPlaced); o.writeFloat(p.statDistance); o.writeInt(p.statCrafted)
            o.writeInt(p.statAnimalsHunted); o.writeInt(p.statDaysSurvived); o.writeInt(p.statDeaths); o.writeInt(p.statHarvested)
            story.save(o)
            o.writeInt(explored.size); for (k in explored) o.writeLong(k)
            o.flush()
            save.writeLevel(bos.toByteArray())
            world.saveAll(sync)
        } catch (e: Exception) {
            Log.e("Game", "save failed", e)
            hud.message("Не удалось сохранить игру")
        }
    }

    private fun loadLevel(): Boolean {
        val body = save.readLevel() ?: return false
        val i = DataInputStream(ByteArrayInputStream(body))
        if (i.readInt() != 1) return false
        if (i.readLong() != seed) return false
        dayNight.day = i.readInt(); dayNight.hour = i.readFloat(); playTime = i.readFloat()
        weather.set(i.readInt(), i.readFloat())
        val p = player
        p.teleport(i.readFloat(), i.readFloat(), i.readFloat()); p.yaw = i.readFloat(); p.pitch = i.readFloat()
        p.firstPerson = i.readBoolean(); p.selected = i.readInt().coerceIn(0, Player.HOTBAR - 1)
        p.spawn.set(i.readFloat(), i.readFloat(), i.readFloat())
        val sv = p.survival
        sv.health = i.readFloat(); sv.hunger = i.readFloat(); sv.thirst = i.readFloat(); sv.energy = i.readFloat(); sv.temperature = i.readFloat(); sv.wetness = i.readFloat()
        readInventory(i, p.inventory); readInventory(i, p.equipment)
        p.statBlocksMined = i.readInt(); p.statBlocksPlaced = i.readInt(); p.statDistance = i.readFloat(); p.statCrafted = i.readInt()
        p.statAnimalsHunted = i.readInt(); p.statDaysSurvived = i.readInt(); p.statDeaths = i.readInt(); p.statHarvested = i.readInt()
        story.load(i)
        val n = i.readInt(); explored.clear(); for (k in 0 until n) explored.add(i.readLong())
        if (sv.health <= 0f) sv.reset()
        return true
    }
}
