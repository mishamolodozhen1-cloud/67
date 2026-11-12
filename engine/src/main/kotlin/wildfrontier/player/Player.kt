package wildfrontier.player

import wildcore.math.Vec3
import wildcore.math.angleDelta
import wildcore.math.approach
import wildcore.math.clamp
import wildcore.math.floorInt
import wildcore.physics.Body
import wildcore.physics.RayHit
import wildcore.physics.VoxelPhysics
import wildcore.world.Blocks
import wildcore.world.VoxelWorld
import wildfrontier.content.Inventory
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt

/** The survivor: movement physics, camera rig and personal state. */
class Player {
    companion object {
        const val WALK = 4.3f; const val SPRINT = 6.3f; const val CROUCH = 1.7f; const val SWIM = 2.7f
        const val GRAVITY = 27f; const val JUMP = 8.1f
        const val HOTBAR = 8
        const val REACH = 5.0f
    }

    val body = Body(0.3f, 1.8f)
    val survival = Survival()
    val inventory = Inventory(36)
    val equipment = Inventory(3)
    var selected = 0

    // look / camera
    var yaw = 0f
    var pitch = -0.15f
    var firstPerson = false
    var cameraDistance = 3.8f
    val eye = Vec3()
    /** Facing of the body (entity convention: 0 = +Z). */
    var modelYaw = 0f

    // input (written by the HUD each frame)
    var moveX = 0f           // strafe, -1..1
    var moveZ = 0f           // forward, -1..1
    var jumpHeld = false
    var sprintToggle = false
    var crouching = false

    // state
    var sprinting = false; private set
    var swimming = false; private set
    var headUnderwater = false; private set
    var onRaft = -1          // raft entity id or -1
    var speed = 0f; private set
    var stepPhase = 0f; private set
    var airTime = 0f; private set
    var hurtFlash = 0f
    var swingTime = 0f       // > 0 while the arm swing animation plays
    var dead = false
    val spawn = Vec3()
    var justLanded = false; private set
    var landingFall = 0f; private set
    var justJumped = false; private set
    var footstep = false; private set

    // statistics / achievements
    var statBlocksMined = 0; var statBlocksPlaced = 0; var statDistance = 0f; var statCrafted = 0
    var statAnimalsHunted = 0; var statDaysSurvived = 0; var statDeaths = 0; var statHarvested = 0

    private val tmp = Vec3()
    private val camHit = RayHit()
    private var lastStepIndex = 0

    val pos: Vec3 get() = body.pos
    val eyeHeight: Float get() = if (crouching) 1.32f else 1.62f

    fun teleport(x: Float, y: Float, z: Float) { body.pos.set(x, y, z); body.vel.set(0f, 0f, 0f); body.fallDistance = 0f }

    fun update(dt: Float, world: VoxelWorld, autoJump: Boolean) {
        justLanded = false; justJumped = false; footstep = false
        if (dead) { body.vel.set(0f, 0f, 0f); return }
        val b = body
        b.height = if (crouching) 1.5f else 1.8f
        VoxelPhysics.updateSubmersion(world, b)
        swimming = b.submerged > 0.55f
        val inWater = b.submerged > 0.1f
        headUnderwater = Blocks.liquid[world.getBlock(floorInt(b.pos.x), floorInt(b.pos.y + eyeHeight), floorInt(b.pos.z))]

        // desired horizontal velocity from the joystick, relative to the camera yaw
        var ix = moveX; var iz = moveZ
        val il = sqrt(ix * ix + iz * iz)
        if (il > 1f) { ix /= il; iz /= il }
        val moving = il > 0.08f
        sprinting = sprintToggle && moving && iz > 0.3f && !crouching && survival.canSprint && !swimming
        if (!moving) sprintToggle = false
        val maxSpeed = (if (swimming) SWIM else if (crouching) CROUCH else if (sprinting) SPRINT else WALK) * survival.speedFactor
        val sy = sin(yaw); val cy = cos(yaw)
        // camera forward on the ground plane is (sin yaw, -cos yaw); right is (cos yaw, sin yaw)
        val wishX = (sy * iz + cy * ix) * maxSpeed
        val wishZ = (-cy * iz + sy * ix) * maxSpeed
        val accel = if (b.onGround) 46f else if (inWater) 14f else 9f
        b.vel.x = approach(b.vel.x, wishX, accel * dt)
        b.vel.z = approach(b.vel.z, wishZ, accel * dt)

        // vertical
        if (swimming) {
            b.vel.y -= GRAVITY * 0.12f * dt
            b.vel.y *= (1f - minOf(1f, dt * 2.6f))
            if (jumpHeld) b.vel.y = approach(b.vel.y, 3.2f, 26f * dt)
            b.fallDistance = 0f
        } else {
            b.vel.y -= GRAVITY * dt * (if (inWater) 0.5f else 1f)
            if (b.vel.y < -52f) b.vel.y = -52f
            if (jumpHeld && b.onGround) { b.vel.y = JUMP; b.onGround = false; justJumped = true }
            else if (jumpHeld && inWater && b.vel.y < 2.5f) b.vel.y = approach(b.vel.y, 3.0f, 30f * dt)
        }

        val wasGround = b.onGround
        val preY = b.pos.y
        val px = b.pos.x; val pz = b.pos.z
        // crouching keeps the player from walking off ledges
        if (crouching && b.onGround) {
            val nx = b.pos.x + b.vel.x * dt; val nz = b.pos.z + b.vel.z * dt
            if (!VoxelPhysics.bodyCollides(world, b, nx, b.pos.y - 0.6f, b.pos.z)) b.vel.x = 0f
            if (!VoxelPhysics.bodyCollides(world, b, b.pos.x, b.pos.y - 0.6f, nz)) b.vel.z = 0f
        }
        VoxelPhysics.move(world, b, b.vel.x * dt, b.vel.y * dt, b.vel.z * dt)

        // auto-jump: blocked by a one-block ledge while walking on the ground
        if (autoJump && b.hitWall && wasGround && moving && !crouching && !swimming) {
            val wl = sqrt(wishX * wishX + wishZ * wishZ).coerceAtLeast(0.001f)
            val ax = b.pos.x + wishX / wl * 0.5f; val az = b.pos.z + wishZ / wl * 0.5f
            val fx = floorInt(ax); val fz = floorInt(az); val fy = floorInt(b.pos.y + 0.1f)
            if (Blocks.solid[world.getBlock(fx, fy, fz)] && !Blocks.solid[world.getBlock(fx, fy + 1, fz)] &&
                !Blocks.solid[world.getBlock(fx, fy + 2, fz)] && !Blocks.solid[world.getBlock(floorInt(b.pos.x), fy + 2, floorInt(b.pos.z))]) {
                b.vel.y = JUMP; b.onGround = false; justJumped = true
            }
        }

        // fall tracking
        if (!b.onGround && !inWater) {
            airTime += dt
            if (b.pos.y < preY) b.fallDistance += preY - b.pos.y
        } else {
            if (!wasGround && b.onGround) { justLanded = true; landingFall = b.fallDistance }
            if (b.onGround || inWater) { b.fallDistance = 0f; airTime = 0f }
        }

        val dx = b.pos.x - px; val dz = b.pos.z - pz
        val moved = sqrt(dx * dx + dz * dz)
        speed = if (dt > 0f) moved / dt else 0f
        statDistance += moved
        if (b.onGround && moved > 0.001f) {
            stepPhase += moved * (if (sprinting) 0.42f else 0.55f)
            val idx = stepPhase.toInt()
            if (idx != lastStepIndex) { lastStepIndex = idx; footstep = true }
        }
        // body turns toward travel direction (or the camera direction in first person / while acting)
        val targetYaw = if (moved > 0.004f && !firstPerson && swingTime <= 0f) atan2(dx, dz) else atan2(sy, -cy)
        if (moved > 0.004f || firstPerson || swingTime > 0f) modelYaw += angleDelta(modelYaw, targetYaw) * minOf(1f, dt * 12f)

        if (hurtFlash > 0f) hurtFlash = maxOf(0f, hurtFlash - dt * 2.2f)
        if (swingTime > 0f) swingTime = maxOf(0f, swingTime - dt)
        eye.set(b.pos.x, b.pos.y + eyeHeight, b.pos.z)
    }

    fun look(dYaw: Float, dPitch: Float) {
        yaw += dYaw
        pitch = clamp(pitch + dPitch, -1.5f, 1.5f)
    }

    /** Positions the camera (third person with wall avoidance, or first person). */
    fun placeCamera(world: VoxelWorld, camPos: Vec3) {
        val cp = cos(pitch)
        val fx = sin(yaw) * cp; val fy = sin(pitch); val fz = -cos(yaw) * cp
        if (firstPerson) { camPos.set(eye); return }
        val tx = eye.x + cos(yaw) * 0.45f; val ty = eye.y + 0.22f; val tz = eye.z + sin(yaw) * 0.45f
        var d = cameraDistance
        // probe a small bundle of rays so the camera does not clip corners
        for (k in 0 until 3) {
            val ox = if (k == 1) cos(yaw) * 0.22f else if (k == 2) -cos(yaw) * 0.22f else 0f
            val oz = if (k == 1) sin(yaw) * 0.22f else if (k == 2) -sin(yaw) * 0.22f else 0f
            if (VoxelPhysics.raycast(world, tx + ox, ty, tz + oz, -fx, -fy, -fz, cameraDistance + 0.3f, camHit, solidOnly = true)) {
                d = minOf(d, camHit.distance - 0.28f)
            }
        }
        d = maxOf(0.35f, d)
        camPos.set(tx - fx * d, ty - fy * d, tz - fz * d)
    }

    fun aimDirection(out: Vec3) {
        val cp = cos(pitch)
        out.set(sin(yaw) * cp, sin(pitch), -cos(yaw) * cp)
    }

    fun hurt(amount: Float, cause: String) {
        if (dead || amount <= 0f) return
        var armor = 0f
        for (s in equipment.slots) if (!s.isEmpty) armor += wildfrontier.content.Items.get(s.id)?.armor ?: 0f
        survival.damage(amount * (1f - minOf(0.6f, armor)), cause)
        hurtFlash = 1f
    }

    fun clothingWarmth(): Float {
        var w = 0f
        for (s in equipment.slots) if (!s.isEmpty) w += wildfrontier.content.Items.get(s.id)?.warmth ?: 0f
        return w
    }

    val heldItem: wildfrontier.content.ItemStack get() = inventory.slots[selected]
    val backpackBonus: Boolean get() = !equipment.slots[2].isEmpty
}
