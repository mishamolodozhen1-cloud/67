package wildfrontier

import wildcore.ecs.ComponentStore
import wildcore.math.Vec3
import wildcore.math.floorInt
import wildcore.world.Blocks
import wildfrontier.content.Items
import kotlin.math.sin
import kotlin.math.sqrt

/** An item lying in the world (ECS component). */
class Drop(var id: Int, var count: Int, var durability: Int) {
    val pos = Vec3()
    val vel = Vec3()
    var age = 0f
    var pickupDelay = 0.5f
    var resting = false
}

/** Dropped items: simple physics, magnet-style pickup into the player's inventory, despawn. */
class DropSystem(private val scene: GameScene) {
    val store: ComponentStore<Drop> = scene.ecs.store()
    var count = 0; private set

    fun spawn(id: Int, count: Int, x: Float, y: Float, z: Float, durability: Int = -1, delay: Float = 0.45f, throwX: Float = 0f, throwZ: Float = 0f) {
        if (count <= 0 || Items.get(id) == null) return
        val d = Drop(id, count, durability)
        val r = scene.particles.rng
        d.pos.set(x + r.range(-0.2f, 0.2f), y, z + r.range(-0.2f, 0.2f))
        d.vel.set(throwX + r.range(-1.2f, 1.2f), r.range(2f, 3.6f), throwZ + r.range(-1.2f, 1.2f))
        d.pickupDelay = delay
        store[scene.ecs.create()] = d
    }

    fun update(dt: Float) {
        val w = scene.world
        val p = scene.player
        var n = 0
        store.each(scene.ecs.highWater) { id, d ->
            n++
            d.age += dt
            d.pickupDelay -= dt
            val dx = p.pos.x - d.pos.x; val dy = p.pos.y + 0.9f - d.pos.y; val dz = p.pos.z - d.pos.z
            val dist = sqrt(dx * dx + dy * dy + dz * dz)
            var attracted = false
            if (!p.dead && d.pickupDelay <= 0f && dist < 2.4f && p.inventory.canFit(d.id, 1)) {
                attracted = true
                val k = 14f / maxOf(dist, 0.3f)
                d.vel.x += dx * k * dt; d.vel.y += dy * k * dt + 20f * dt; d.vel.z += dz * k * dt
                d.resting = false
                if (dist < 0.75f) {
                    val left = p.inventory.add(d.id, d.count, d.durability)
                    val taken = d.count - left
                    if (taken > 0) {
                        scene.audio.play("pickup", 0.8f, 0.9f + (d.id % 5) * 0.05f)
                        scene.hud.notifyPickup(d.id, taken)
                        scene.story.onItemGained(d.id, taken)
                    }
                    d.count = left
                    if (left <= 0) { scene.ecs.destroy(id); return@each }
                }
            }
            if (!d.resting || attracted) {
                d.vel.y -= 20f * dt
                val k = 1f - minOf(1f, dt * (if (attracted) 4f else 0.6f))
                d.vel.x *= k; d.vel.z *= k
                val nx = d.pos.x + d.vel.x * dt; val ny = d.pos.y + d.vel.y * dt; val nz = d.pos.z + d.vel.z * dt
                // treat the item as a point: stop on solid blocks, float on water
                if (Blocks.solid[w.getBlock(floorInt(nx), floorInt(d.pos.y), floorInt(d.pos.z))]) d.vel.x = 0f else d.pos.x = nx
                if (Blocks.solid[w.getBlock(floorInt(d.pos.x), floorInt(d.pos.y), floorInt(nz))]) d.vel.z = 0f else d.pos.z = nz
                val below = w.getBlock(floorInt(d.pos.x), floorInt(ny - 0.12f), floorInt(d.pos.z))
                if (Blocks.solid[below] && d.vel.y <= 0f) {
                    d.pos.y = floorInt(ny - 0.12f) + 1.12f
                    d.vel.y = 0f; d.vel.x *= 0.5f; d.vel.z *= 0.5f
                    if (!attracted && kotlin.math.abs(d.vel.x) + kotlin.math.abs(d.vel.z) < 0.05f) d.resting = true
                } else if (Blocks.liquid[below] && d.vel.y < 0f) { d.vel.y *= (1f - minOf(1f, dt * 8f)); d.vel.y += 21f * dt; d.pos.y = ny }
                else d.pos.y = ny
            } else if (d.age % 1f < dt && !Blocks.solid[w.getBlock(floorInt(d.pos.x), floorInt(d.pos.y - 0.2f), floorInt(d.pos.z))]) d.resting = false
            if (d.age > 420f || d.pos.y < -10f) { scene.ecs.destroy(id); return@each }
            val def = Items.get(d.id)
            if (def != null) scene.particles.icon(d.pos.x, d.pos.y + 0.12f + sin(d.age * 2.4f) * 0.05f, d.pos.z, 0.19f, scene.ui.iconId(def.icon))
        }
        count = n
    }
}
