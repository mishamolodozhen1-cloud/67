package wildfrontier.animals

import wildcore.anim.Animator
import wildcore.anim.SkinnedMesh
import wildcore.ecs.ComponentStore
import wildcore.math.Hash
import wildcore.math.Mat4
import wildcore.math.Rng
import wildcore.math.TAU_F
import wildcore.math.angleDelta
import wildcore.math.floorInt
import wildcore.physics.Body
import wildcore.physics.VoxelPhysics
import wildcore.world.Blocks
import wildfrontier.GameScene
import wildfrontier.content.B
import wildfrontier.content.I
import wildfrontier.gen.Column
import wildfrontier.gen.WorldGen
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt

object AState {
    const val IDLE = 0; const val WANDER = 1; const val GRAZE = 2; const val REST = 3; const val ALERT = 4
    const val FLEE = 5; const val STALK = 6; const val CHASE = 7; const val ATTACK = 8; const val FOLLOW = 9
    const val EAT = 10; const val DEAD = 11
    val NAMES = arrayOf("стоит", "бродит", "идёт пастись", "отдыхает", "насторожен", "убегает", "крадётся", "преследует", "атакует", "идёт за стадом", "ест", "мёртв")
}

/** A living animal (ECS component). */
class Animal(val species: Species, val model: AnimalModel) {
    val body = Body(species.collisionRadius, species.collisionHeight)
    val animator = Animator(model.skeleton)
    var yaw = 0f
    var health = species.health
    var state = AState.IDLE
    var stateTime = 0f
    var stateDuration = 2f
    var targetX = 0f; var targetZ = 0f
    var hasTarget = false
    var hunger = 20f
    var age = 0f
    var baby = false
    var male = true
    var herd = 0
    var leader = -1
    var targetEntity = -1
    var hostileToPlayer = false
    var attackCooldown = 0f
    var breedCooldown = 240f
    var hurtFlash = 0f
    var skyLight = 1f
    var thinkTimer = 0f
    var deadTime = 0f
    var dropped = false
    var distToPlayer = 0f
    var moveSpeed = 0f
    var soundTimer = 6f
    val scale: Float get() = if (baby) 0.5f + 0.5f * (age / 420f).coerceIn(0f, 1f) else 1f
    val isDead: Boolean get() = state == AState.DEAD
}

/**
 * Wildlife simulation: population management around the player, behaviour state machines
 * (grazing, resting, herding, fleeing, pack hunting, breeding) and rendering of visible animals.
 * Update rates scale down with distance so far-away animals cost almost nothing.
 */
class AnimalSystem(private val scene: GameScene) {
    val store: ComponentStore<Animal> = scene.ecs.store()
    val models = arrayOfNulls<AnimalModel>(3)
    private val gpu = HashMap<wildcore.anim.SkinnedMeshData, SkinnedMesh>()
    private val rng = Rng(scene.seed xor 0x5EEDL)
    private val col = Column()
    private var spawnTimer = 1.5f
    private var nextHerd = 1
    private val modelMat = FloatArray(16)
    private val tmpMat = FloatArray(16)
    var count = 0; private set
    val speciesCount = IntArray(3)

    init {
        for (i in 0 until 3) models[i] = AnimalModel(SpeciesDb.get(i))
    }

    /** (Re)creates GPU meshes after the GL context was created. */
    fun initGpu() {
        gpu.clear()
        for (m in models) for (d in m!!.meshes) gpu[d] = SkinnedMesh(scene.game.engine.gl, d)
    }

    // ------------------------------------------------------------------ spawning

    fun spawn(speciesId: Int, x: Float, y: Float, z: Float, herd: Int, baby: Boolean, male: Boolean): Int {
        val sp = SpeciesDb.get(speciesId)
        val a = Animal(sp, models[speciesId]!!)
        a.body.pos.set(x, y, z)
        a.body.stepHeight = if (sp.hops) 0.55f else 0.62f
        a.yaw = rng.nextFloat() * TAU_F
        a.herd = herd; a.baby = baby; a.male = male
        a.hunger = rng.range(5f, 45f)
        a.breedCooldown = rng.range(120f, 420f)
        a.animator.play(a.model.idle, 0f)
        a.animator.time = rng.nextFloat() * 4f
        val id = scene.ecs.create()
        store[id] = a
        return id
    }

    private fun trySpawnGroup() {
        val p = scene.player.pos
        val ang = rng.nextFloat() * TAU_F
        val dist = rng.range(34f, 62f)
        val x = p.x + cos(ang) * dist; val z = p.z + sin(ang) * dist
        val ix = floorInt(x); val iz = floorInt(z)
        if (!scene.world.isLoaded(ix, iz)) return
        scene.gen.sample(ix, iz, col)
        if (col.height <= WorldGen.SEA + 1) return
        val candidates = ArrayList<Int>(3)
        for (i in 0 until 3) {
            val sp = SpeciesDb.get(i)
            if (!sp.biomes.contains(col.biome)) continue
            val cap = when (i) { SpeciesDb.DEER -> 8; SpeciesDb.WOLF -> 5; else -> 9 }
            if (speciesCount[i] >= cap) continue
            // wolves mostly appear at dusk and night
            if (sp.nocturnal && !scene.dayNight.isNight && rng.nextFloat() > 0.25f) continue
            candidates.add(i)
        }
        if (candidates.isEmpty()) return
        val sid = candidates[rng.nextInt(candidates.size)]
        val sp = SpeciesDb.get(sid)
        val n = sp.groupMin + rng.nextInt(sp.groupMax - sp.groupMin + 1)
        val herd = nextHerd++
        var leader = -1
        for (k in 0 until n) {
            val sx = x + rng.range(-3.5f, 3.5f); val sz = z + rng.range(-3.5f, 3.5f)
            val sy = scene.world.surfaceY(floorInt(sx), floorInt(sz))
            if (sy < WorldGen.SEA) continue
            if (Blocks.liquid[scene.world.getBlock(floorInt(sx), sy + 1, floorInt(sz))]) continue
            val baby = k >= 2 && rng.nextFloat() < 0.4f
            val id = spawn(sid, sx, sy + 1.02f, sz, herd, baby, male = k == 0 || rng.nextFloat() < 0.35f)
            if (leader < 0) leader = id
            store[id]!!.leader = leader
        }
    }

    // ------------------------------------------------------------------ update

    fun update(dt: Float) {
        val ecs = scene.ecs
        val player = scene.player
        val maxAnimals = scene.game.engine.settings.profile.maxAnimals
        count = 0
        speciesCount[0] = 0; speciesCount[1] = 0; speciesCount[2] = 0
        store.each(ecs.highWater) { _, a -> if (!a.isDead) { count++; speciesCount[a.species.id]++ } }

        spawnTimer -= dt
        if (spawnTimer <= 0f) {
            spawnTimer = 2.5f
            if (count < maxAnimals) trySpawnGroup()
        }

        store.each(ecs.highWater) { id, a ->
            val dx = a.body.pos.x - player.pos.x; val dz = a.body.pos.z - player.pos.z
            a.distToPlayer = sqrt(dx * dx + dz * dz)
            if (a.distToPlayer > 120f || !scene.world.isLoaded(floorInt(a.body.pos.x), floorInt(a.body.pos.z))) {
                ecs.destroy(id)
            } else {
                // distance-based update rate: full rate nearby, a fraction far away
                val think = if (a.distToPlayer < 40f) 0.25f else if (a.distToPlayer < 80f) 0.6f else 1.2f
                a.thinkTimer -= dt
                a.stateTime += dt
                if (a.attackCooldown > 0f) a.attackCooldown -= dt
                if (a.hurtFlash > 0f) a.hurtFlash = maxOf(0f, a.hurtFlash - dt * 3f)
                if (a.isDead) updateDead(id, a, dt)
                else {
                    a.age += dt
                    if (a.baby && a.age > 420f) a.baby = false
                    a.hunger = minOf(100f, a.hunger + dt * (if (a.species.predator) 0.22f else 0.30f))
                    a.breedCooldown -= dt
                    if (a.thinkTimer <= 0f) { a.thinkTimer = think * (0.8f + rng.nextFloat() * 0.4f); think(id, a) }
                    if (a.distToPlayer < 90f) move(a, dt)
                    ambientSound(a, dt)
                }
            }
        }
    }

    private fun setState(a: Animal, s: Int, duration: Float) {
        a.state = s; a.stateTime = 0f; a.stateDuration = duration
        if (s != AState.WANDER && s != AState.GRAZE && s != AState.FLEE && s != AState.FOLLOW && s != AState.STALK && s != AState.CHASE) a.hasTarget = false
    }

    private fun think(id: Int, a: Animal) {
        val sp = a.species
        val player = scene.player
        val pos = a.body.pos
        a.skyLight = if (scene.world.surfaceY(floorInt(pos.x), floorInt(pos.z)) > pos.y + 1.5f) 0.45f else 1f
        val night = scene.dayNight.isNight

        // ---- perception
        var threatX = 0f; var threatZ = 0f; var threatDist = Float.MAX_VALUE
        if (!sp.predator) {
            val sneak = if (player.crouching) 0.5f else if (player.sprinting) 1.25f else 1f
            if (!player.dead && a.distToPlayer < sp.senseDistance * sneak) { threatX = player.pos.x; threatZ = player.pos.z; threatDist = a.distToPlayer / sneak }
            store.each(scene.ecs.highWater) { _, o ->
                if (o.species.predator && !o.isDead) {
                    val d = dist(o, a)
                    val eff = if (o.state == AState.STALK) d * 1.6f else d   // stalking wolves are harder to notice
                    if (eff < threatDist && d < sp.senseDistance) { threatDist = eff; threatX = o.body.pos.x; threatZ = o.body.pos.z }
                }
            }
            if (threatDist < sp.fleeDistance) {
                if (a.state != AState.FLEE) {
                    alarmHerd(a)
                    scene.audio.playAt(if (sp.id == SpeciesDb.DEER) "deer_alarm" else "rabbit_thump", pos.x, pos.y, pos.z, 1f, sp.soundPitch)
                }
                fleeFrom(a, threatX, threatZ)
                return
            }
            if (a.state == AState.FLEE) { if (a.stateTime > a.stateDuration) setState(a, AState.ALERT, 2f); else return }
            if (threatDist < sp.senseDistance && a.state != AState.ALERT && a.state != AState.REST && rng.nextFloat() < 0.6f) {
                setState(a, AState.ALERT, 1.5f + rng.nextFloat() * 2f)
                a.yaw = atan2(threatX - pos.x, threatZ - pos.z)
                return
            }
        } else if (thinkPredator(id, a, night)) return

        // ---- routine
        if (a.stateTime < a.stateDuration && a.state != AState.IDLE) return
        val leader = if (a.leader >= 0 && a.leader != id) store[a.leader] else null
        if (leader != null && !leader.isDead && dist(leader, a) > 13f) {
            setState(a, AState.FOLLOW, 6f)
            a.targetX = leader.body.pos.x + rng.range(-3f, 3f); a.targetZ = leader.body.pos.z + rng.range(-3f, 3f); a.hasTarget = true
            return
        }
        tryBreed(id, a)
        val restful = if (sp.nocturnal) !night else night
        val r = rng.nextFloat()
        when {
            restful && r < 0.7f -> setState(a, AState.REST, rng.range(12f, 30f))
            !sp.predator && a.hunger > 35f && r < 0.75f -> {
                setState(a, AState.GRAZE, 6f)
                pickTarget(a, 7f)
            }
            r < 0.55f -> { setState(a, AState.WANDER, rng.range(4f, 9f)); pickTarget(a, 11f) }
            else -> setState(a, AState.IDLE, rng.range(2f, 6f))
        }
    }

    /** Predator decision making. Returns true when a hunting/defensive state was chosen. */
    private fun thinkPredator(id: Int, a: Animal, night: Boolean): Boolean {
        val sp = a.species
        val player = scene.player
        val pos = a.body.pos
        if (a.state == AState.EAT && a.stateTime < a.stateDuration) return true
        if (a.state == AState.ATTACK && a.stateTime < 0.5f) return true
        // fire keeps wolves at bay; badly wounded wolves retreat
        val fire = scene.nearFire(pos.x, pos.y, pos.z, 7f)
        if (fire > 0f || a.health < sp.health * 0.3f) {
            if (a.distToPlayer < 14f || fire > 0f) { fleeFrom(a, player.pos.x, player.pos.z); a.hostileToPlayer = false; return true }
        }
        val hungry = a.hunger > 55f || (night && a.hunger > 32f)
        // player as a target: provoked, very hungry, or a pack at night meeting a lone human up close
        var wantsPlayer = a.hostileToPlayer
        if (!wantsPlayer && !player.dead && a.distToPlayer < sp.senseDistance) {
            if (a.hunger > 78f) wantsPlayer = true
            else if (night && a.distToPlayer < 9f && packSize(a) >= 2 && !player.crouching) wantsPlayer = true
        }
        if (wantsPlayer && !player.dead && a.distToPlayer < 40f) {
            a.targetEntity = -1
            a.targetX = player.pos.x; a.targetZ = player.pos.z; a.hasTarget = true
            if (a.distToPlayer < 1.7f) {
                if (a.attackCooldown <= 0f) {
                    setState(a, AState.ATTACK, 0.6f)
                    a.attackCooldown = 1.3f
                    a.animator.play(a.model.attack, 0.05f, restart = true)
                    player.hurt(sp.attackDamage, "волк")
                    scene.audio.playAt("wolf_growl", pos.x, pos.y, pos.z, 1f, 1f)
                    scene.onPlayerHurt()
                }
            } else if (a.state != AState.CHASE) setState(a, AState.CHASE, 20f)
            return true
        }
        if (a.hostileToPlayer && (player.dead || a.distToPlayer > 45f)) a.hostileToPlayer = false
        if (!hungry) return false
        // look for prey
        var best = -1; var bestD = sp.senseDistance
        store.each(scene.ecs.highWater) { oid, o ->
            if (!o.isDead && sp.prey.contains(o.species.id)) { val d = dist(o, a); if (d < bestD) { bestD = d; best = oid } }
        }
        if (best < 0) return false
        val prey = store[best]!!
        a.targetEntity = best
        a.targetX = prey.body.pos.x; a.targetZ = prey.body.pos.z; a.hasTarget = true
        if (bestD < 1.5f) {
            if (a.attackCooldown <= 0f) {
                setState(a, AState.ATTACK, 0.6f)
                a.attackCooldown = 1.1f
                a.animator.play(a.model.attack, 0.05f, restart = true)
                damage(best, prey, sp.attackDamage * 1.4f, pos.x, pos.z, byPlayer = false)
                if (prey.isDead) {
                    a.hunger = 0f
                    setState(a, AState.EAT, 9f)
                    // the pack shares the kill
                    store.each(scene.ecs.highWater) { _, o -> if (o.herd == a.herd && o !== a) o.hunger = minOf(o.hunger, 15f) }
                }
            }
        } else if (bestD < 10f) { if (a.state != AState.CHASE) setState(a, AState.CHASE, 14f) }
        else if (a.state != AState.STALK && a.state != AState.CHASE) setState(a, AState.STALK, 12f)
        return true
    }

    private fun packSize(a: Animal): Int {
        var n = 0
        store.each(scene.ecs.highWater) { _, o -> if (o.herd == a.herd && !o.isDead && dist(o, a) < 18f) n++ }
        return n
    }

    private fun alarmHerd(a: Animal) {
        store.each(scene.ecs.highWater) { _, o ->
            if (o !== a && !o.isDead && o.species === a.species && dist(o, a) < 12f && o.state != AState.FLEE) {
                o.thinkTimer = 0.05f + rng.nextFloat() * 0.3f
                if (o.state == AState.REST || o.state == AState.GRAZE) setState(o, AState.ALERT, 0.5f)
            }
        }
    }

    private fun fleeFrom(a: Animal, fx: Float, fz: Float) {
        val pos = a.body.pos
        var dx = pos.x - fx; var dz = pos.z - fz
        val l = sqrt(dx * dx + dz * dz).coerceAtLeast(0.01f); dx /= l; dz /= l
        // rabbits zig-zag
        val jitter = if (a.species.hops) rng.range(-0.9f, 0.9f) else rng.range(-0.3f, 0.3f)
        val c = cos(jitter); val s = sin(jitter)
        val rx = dx * c - dz * s; val rz = dx * s + dz * c
        a.targetX = pos.x + rx * 16f; a.targetZ = pos.z + rz * 16f; a.hasTarget = true
        if (a.state != AState.FLEE) setState(a, AState.FLEE, rng.range(3.5f, 6f))
    }

    private fun pickTarget(a: Animal, radius: Float) {
        val pos = a.body.pos
        for (attempt in 0 until 4) {
            val ang = rng.nextFloat() * TAU_F; val d = rng.range(radius * 0.3f, radius)
            val tx = pos.x + cos(ang) * d; val tz = pos.z + sin(ang) * d
            val sy = scene.world.surfaceY(floorInt(tx), floorInt(tz))
            if (sy < WorldGen.SEA || kotlin.math.abs(sy + 1 - pos.y) > 4f) continue
            if (Blocks.liquid[scene.world.getBlock(floorInt(tx), sy + 1, floorInt(tz))]) continue
            a.targetX = tx; a.targetZ = tz; a.hasTarget = true
            return
        }
        a.hasTarget = false
    }

    private fun tryBreed(id: Int, a: Animal) {
        val sp = a.species
        if (a.male || a.baby || a.breedCooldown > 0f || a.hunger > 55f) return
        if (speciesCount[sp.id] >= (if (sp.id == SpeciesDb.RABBIT) 10 else 7)) return
        var mate = false
        store.each(scene.ecs.highWater) { _, o -> if (o.species === sp && o.male && !o.baby && !o.isDead && dist(o, a) < 10f) mate = true }
        if (!mate) return
        a.breedCooldown = if (sp.id == SpeciesDb.RABBIT) 300f else 600f
        val n = if (sp.id == SpeciesDb.RABBIT) 1 + rng.nextInt(2) else 1
        for (k in 0 until n) {
            val bid = spawn(sp.id, a.body.pos.x + rng.range(-0.8f, 0.8f), a.body.pos.y + 0.1f, a.body.pos.z + rng.range(-0.8f, 0.8f), a.herd, baby = true, male = rng.nextFloat() < 0.5f)
            store[bid]!!.leader = id
            speciesCount[sp.id]++
        }
    }

    // ------------------------------------------------------------------ locomotion

    private fun move(a: Animal, dt: Float) {
        val sp = a.species
        val b = a.body
        val w = scene.world
        VoxelPhysics.updateSubmersion(w, b)
        var want = 0f
        if (a.hasTarget && (a.state == AState.WANDER || a.state == AState.GRAZE || a.state == AState.FLEE || a.state == AState.FOLLOW ||
                    a.state == AState.STALK || a.state == AState.CHASE)) {
            // chase targets move: refresh from the entity / player
            if (a.state == AState.CHASE || a.state == AState.STALK) {
                val t = if (a.targetEntity >= 0) store[a.targetEntity] else null
                if (t != null && !t.isDead) { a.targetX = t.body.pos.x; a.targetZ = t.body.pos.z }
                else if (a.targetEntity < 0) { a.targetX = scene.player.pos.x; a.targetZ = scene.player.pos.z }
            }
            val dx = a.targetX - b.pos.x; val dz = a.targetZ - b.pos.z
            val d = sqrt(dx * dx + dz * dz)
            val arrive = if (a.state == AState.CHASE) 1.1f else 0.8f
            if (d < arrive) {
                a.hasTarget = false
                if (a.state == AState.GRAZE) { setState(a, AState.EAT, rng.range(4f, 9f)); a.hunger = maxOf(0f, a.hunger - 35f); grazeBlock(a) }
                else if (a.state == AState.WANDER || a.state == AState.FOLLOW) setState(a, AState.IDLE, rng.range(1.5f, 4f))
            } else {
                val targetYaw = atan2(dx, dz)
                a.yaw += angleDelta(a.yaw, targetYaw) * minOf(1f, dt * (if (a.state == AState.FLEE) 7f else 4.5f))
                want = when (a.state) {
                    AState.FLEE, AState.CHASE -> sp.runSpeed * (if (a.baby) 0.8f else 1f)
                    AState.FOLLOW -> if (d > 9f) sp.runSpeed * 0.7f else sp.walkSpeed * 1.3f
                    AState.STALK -> sp.walkSpeed * 0.9f
                    else -> sp.walkSpeed
                }
                // look ahead: avoid walking into water or off cliffs unless fleeing for its life
                val ax = b.pos.x + sin(a.yaw) * 1.4f; val az = b.pos.z + cos(a.yaw) * 1.4f
                val gy = w.surfaceY(floorInt(ax), floorInt(az))
                val water = Blocks.liquid[w.getBlock(floorInt(ax), floorInt(b.pos.y - 0.2f), floorInt(az))] || Blocks.liquid[w.getBlock(floorInt(ax), floorInt(b.pos.y + 0.3f), floorInt(az))]
                if ((water && b.submerged < 0.2f) || gy < b.pos.y - 4.5f) {
                    a.yaw += (if (Hash.hash2(floorInt(b.pos.x), floorInt(b.pos.z), 3) and 1 == 0) 1f else -1f) * dt * 5f
                    want *= 0.25f
                    if (a.state == AState.WANDER || a.state == AState.GRAZE) a.hasTarget = false
                }
            }
        }
        val vx = sin(a.yaw) * want; val vz = cos(a.yaw) * want
        val acc = if (b.onGround) 26f else 6f
        b.vel.x = wildcore.math.approach(b.vel.x, vx, acc * dt)
        b.vel.z = wildcore.math.approach(b.vel.z, vz, acc * dt)
        if (b.submerged > 0.5f) { b.vel.y = wildcore.math.approach(b.vel.y, 1.2f, 12f * dt) }
        else b.vel.y = maxOf(-40f, b.vel.y - 26f * dt)
        val wasGround = b.onGround
        VoxelPhysics.move(w, b, b.vel.x * dt, b.vel.y * dt, b.vel.z * dt)
        // hop over one-block ledges
        if (b.hitWall && (wasGround || b.onGround) && want > 0.1f) {
            val fx = floorInt(b.pos.x + sin(a.yaw) * (b.halfWidth + 0.5f)); val fz = floorInt(b.pos.z + cos(a.yaw) * (b.halfWidth + 0.5f))
            val fy = floorInt(b.pos.y + 0.1f)
            if (!Blocks.solid[w.getBlock(fx, fy + 1, fz)] && !Blocks.solid[w.getBlock(fx, fy + 2, fz)]) b.vel.y = 7.4f
            else { a.yaw += 1.2f; if (a.state == AState.WANDER) a.hasTarget = false }
        }
        a.moveSpeed = sqrt(b.vel.x * b.vel.x + b.vel.z * b.vel.z)

        // animation
        val m = a.model
        val an = a.animator
        when {
            a.state == AState.ATTACK && !an.finished -> {}
            a.moveSpeed > sp.walkSpeed * 1.8f -> { an.play(m.run, 0.15f); an.speed = (a.moveSpeed / sp.runSpeed).coerceIn(0.6f, 1.3f) }
            a.moveSpeed > 0.25f -> { an.play(m.walk, 0.2f); an.speed = (a.moveSpeed / sp.walkSpeed).coerceIn(0.5f, 1.8f) }
            a.state == AState.REST -> { an.play(m.rest, 0.6f); an.speed = 1f }
            a.state == AState.EAT -> { an.play(m.eat, 0.4f); an.speed = 1f }
            a.state == AState.ALERT -> { an.play(m.alert, 0.2f); an.speed = 1f }
            else -> { an.play(m.idle, 0.3f); an.speed = 1f }
        }
    }

    /** Grazing occasionally consumes the tall grass it stands in — animals shape the meadow. */
    private fun grazeBlock(a: Animal) {
        if (rng.nextFloat() > 0.12f) return
        val x = floorInt(a.body.pos.x + sin(a.yaw) * 0.6f); val y = floorInt(a.body.pos.y + 0.2f); val z = floorInt(a.body.pos.z + cos(a.yaw) * 0.6f)
        if (scene.world.getBlock(x, y, z) == B.TALL_GRASS) scene.world.setBlock(x, y, z, B.AIR)
    }

    private fun ambientSound(a: Animal, dt: Float) {
        a.soundTimer -= dt
        if (a.soundTimer > 0f) return
        a.soundTimer = rng.range(14f, 40f)
        if (a.distToPlayer > 60f) return
        val p = a.body.pos
        when (a.species.id) {
            SpeciesDb.WOLF -> if (scene.dayNight.isNight && a.state != AState.CHASE) scene.audio.playAt("wolf_howl", p.x, p.y, p.z, 1f, 0.9f + rng.nextFloat() * 0.2f)
            SpeciesDb.DEER -> if (a.state == AState.IDLE || a.state == AState.ALERT) scene.audio.playAt("deer_call", p.x, p.y, p.z, 0.7f, 0.9f + rng.nextFloat() * 0.2f)
        }
    }

    // ------------------------------------------------------------------ damage / death

    fun damage(id: Int, a: Animal, amount: Float, fromX: Float, fromZ: Float, byPlayer: Boolean) {
        if (a.isDead) return
        a.health -= amount
        a.hurtFlash = 1f
        val p = a.body.pos
        var dx = p.x - fromX; var dz = p.z - fromZ
        val l = sqrt(dx * dx + dz * dz).coerceAtLeast(0.01f); dx /= l; dz /= l
        a.body.vel.x += dx * 4f; a.body.vel.z += dz * 4f; a.body.vel.y = 3f
        scene.audio.playAt("hit_flesh", p.x, p.y, p.z, 1f, a.species.soundPitch)
        if (a.health <= 0f) {
            setState(a, AState.DEAD, 0f)
            a.animator.play(a.model.die, 0.1f)
            a.animator.speed = 1f
            a.body.vel.x = 0f; a.body.vel.z = 0f
            if (byPlayer) { scene.player.statAnimalsHunted++; scene.story.onHunt(a.species.id) }
            return
        }
        if (a.species.predator) {
            if (byPlayer) store.each(scene.ecs.highWater) { _, o -> if (o.herd == a.herd) o.hostileToPlayer = true }
        } else {
            alarmHerd(a)
            fleeFrom(a, fromX, fromZ)
        }
        a.thinkTimer = 0f
    }

    private fun updateDead(id: Int, a: Animal, dt: Float) {
        a.deadTime += dt
        val b = a.body
        b.vel.y = maxOf(-40f, b.vel.y - 26f * dt)
        b.vel.x = 0f; b.vel.z = 0f
        VoxelPhysics.move(scene.world, b, 0f, b.vel.y * dt, 0f)
        if (!a.dropped && a.deadTime > 1.0f) {
            a.dropped = true
            val sp = a.species
            val p = b.pos
            val k = if (a.baby) 0 else 1
            if (sp.dropMeat * k > 0) scene.drops.spawn(I.RAW_MEAT, sp.dropMeat, p.x, p.y + 0.4f, p.z)
            if (sp.dropLeather * k > 0) scene.drops.spawn(I.LEATHER, sp.dropLeather, p.x, p.y + 0.4f, p.z)
            if (sp.extraDrop >= 0 && rng.nextFloat() < 0.7f) scene.drops.spawn(sp.extraDrop, 1, p.x, p.y + 0.4f, p.z)
            if (a.baby) scene.drops.spawn(I.RAW_MEAT, 1, p.x, p.y + 0.4f, p.z)
        }
        if (a.deadTime > 25f) scene.ecs.destroy(id)
    }

    /** Nearest living animal hit by a ray (used for melee and arrows). Returns the entity id or -1. */
    fun raycast(ox: Float, oy: Float, oz: Float, dx: Float, dy: Float, dz: Float, maxDist: Float): Int {
        var best = -1; var bestT = maxDist
        store.each(scene.ecs.highWater) { id, a ->
            if (!a.isDead) {
                val s = a.scale
                val cx = a.body.pos.x - ox; val cy = a.body.pos.y + a.species.collisionHeight * 0.5f * s - oy; val cz = a.body.pos.z - oz
                val t = cx * dx + cy * dy + cz * dz
                if (t > 0f && t < bestT) {
                    val px = cx - dx * t; val py = cy - dy * t; val pz = cz - dz * t
                    val r = maxOf(a.species.collisionRadius * 1.7f, a.species.collisionHeight * 0.55f) * s
                    if (px * px + py * py + pz * pz < r * r) { best = id; bestT = t }
                }
            }
        }
        return best
    }

    private fun dist(a: Animal, b: Animal): Float {
        val dx = a.body.pos.x - b.body.pos.x; val dz = a.body.pos.z - b.body.pos.z
        return sqrt(dx * dx + dz * dz)
    }

    // ------------------------------------------------------------------ rendering

    /** Queues visible animals for drawing and advances their animation (LOD: fewer updates when far). */
    fun queueRender(dt: Float, frame: Long) {
        val cam = scene.renderer.camera
        val mr = scene.modelRenderer
        store.each(scene.ecs.highWater) { id, a ->
            if (a.distToPlayer < 95f) {
                val p = a.body.pos
                val s = a.scale
                val rx = p.x - cam.pos.x; val ry = p.y - cam.pos.y; val rz = p.z - cam.pos.z
                if (cam.frustum.intersectsSphere(rx, ry + a.species.collisionHeight * 0.5f, rz, a.species.bodyLength * 1.2f + 0.5f)) {
                    // animation LOD: skip frames with distance, compensate with a larger time step
                    val skip = if (a.distToPlayer < 35f) 1 else if (a.distToPlayer < 65f) 2 else 4
                    if ((frame + id) % skip == 0L) a.animator.update(dt * skip)
                    Mat4.rotationY(tmpMat, 0, a.yaw)
                    for (i in 0 until 12) tmpMat[i] *= s
                    tmpMat[12] = rx; tmpMat[13] = ry; tmpMat[14] = rz
                    val inst = mr.next()
                    val variant = if (a.model.meshes.size > 1 && (!a.male || a.baby)) 1 else 0
                    inst.mesh = gpu[a.model.meshes[variant]]
                    inst.boneCount = a.model.skeleton.count
                    a.animator.palette(tmpMat, inst.palette)
                    inst.sky = a.skyLight; inst.blockLight = 0f; inst.hurt = a.hurtFlash * 0.6f
                    inst.castShadow = a.distToPlayer < 50f
                    scene.story.onAnimalSeen(a.species.id, a.distToPlayer)
                }
            }
        }
    }
}
