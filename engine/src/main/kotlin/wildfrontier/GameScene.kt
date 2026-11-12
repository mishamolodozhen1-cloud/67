package wildfrontier

import wildcore.core.Engine
import wildcore.core.Scene
import wildcore.world.VoxelWorld
import wildfrontier.content.B
import wildfrontier.env.DayNight
import wildfrontier.gen.WorldGen
import wildfrontier.render.WorldRenderer

/** Gameplay scene: owns the world, simulation systems and the render pipeline. */
class GameScene(private val game: WildFrontierGame, val seed: Long) : Scene {
    lateinit var gen: WorldGen; private set
    lateinit var world: VoxelWorld; private set
    val renderer = WorldRenderer(game.engine)
    val dayNight = DayNight()
    var overcast = 0.2f
    var ready = false; private set
    private var loadStart = 0L

    override fun onEnter(engine: Engine) {
        B.registerAll()
        gen = WorldGen(seed)
        world = VoxelWorld(engine.jobs, gen, null, engine.profiler, B.BEDROCK)
        world.viewDistance = engine.settings.profile.viewDistance
        world.leafInnerFaces = engine.settings.profile.leafInnerFaces
        world.meshSink = renderer
        val s = gen.structures.spawn
        renderer.camera.pos.set(s[0] + 0.5f, s[1] + 1.7f, s[2] + 0.5f)
        loadStart = System.nanoTime()
    }

    override fun onContextCreated(engine: Engine) {
        renderer.init()
        world.remeshAll()
    }

    override fun onResize(engine: Engine, width: Int, height: Int) = renderer.resize(width, height)

    override fun update(engine: Engine, dt: Float) {
        val cam = renderer.camera
        world.update(cam.pos.x, cam.pos.z)
        dayNight.update(dt)
        val far = (engine.settings.profile.viewDistance * 16f)
        dayNight.apply(renderer.env, overcast, 0f, far * 2.2f)
        renderer.env.time = engine.time.elapsed.toFloat()
        cam.far = far * 3f
        if (!ready && world.isAreaReady(cam.pos.x, cam.pos.z, minOf(3, world.viewDistance - 1))) {
            ready = true
            engine.profiler.worldLoadMs = (System.nanoTime() - loadStart) / 1_000_000f
        }
    }

    override fun render(engine: Engine) {
        renderer.render(world) {}
    }

    override fun onExit(engine: Engine) {
        renderer.dispose()
    }
}
