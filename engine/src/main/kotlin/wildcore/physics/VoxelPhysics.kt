package wildcore.physics

import wildcore.math.Vec3
import wildcore.math.floorInt
import wildcore.world.Blocks
import wildcore.world.Shape

/** Read access to voxels for physics queries. */
interface BlockQuery {
    fun getBlock(x: Int, y: Int, z: Int): Int
}

/** Axis-aligned physics body. [pos] is the centre of the feet. */
class Body(var halfWidth: Float, var height: Float) {
    val pos = Vec3()
    val vel = Vec3()
    var onGround = false
    var hitWall = false
    var hitCeiling = false
    /** Fraction of the body submerged in liquid, 0..1. */
    var submerged = 0f
    var stepHeight = 0.55f
    var fallDistance = 0f
}

class RayHit {
    var hit = false
    var x = 0; var y = 0; var z = 0          // block that was hit
    var nx = 0; var ny = 0; var nz = 0       // face normal (points toward the ray origin side)
    var distance = 0f
    var block = 0
    val placeX: Int get() = x + nx
    val placeY: Int get() = y + ny
    val placeZ: Int get() = z + nz
}

object VoxelPhysics {
    private const val EPS = 0.001f

    private fun collisionTop(id: Int): Float {
        if (!Blocks.solid[id]) return 0f
        return if (Blocks.shape[id] == Shape.BOX) Blocks.get(id).boxMaxY else 1f
    }

    /** True if the box overlaps any solid voxel volume. */
    fun collides(w: BlockQuery, minX: Float, minY: Float, minZ: Float, maxX: Float, maxY: Float, maxZ: Float): Boolean {
        val x0 = floorInt(minX); val x1 = floorInt(maxX)
        val y0 = floorInt(minY); val y1 = floorInt(maxY)
        val z0 = floorInt(minZ); val z1 = floorInt(maxZ)
        for (y in y0..y1) for (z in z0..z1) for (x in x0..x1) {
            val top = collisionTop(w.getBlock(x, y, z))
            if (top > 0f && minY < y + top) return true
        }
        return false
    }

    fun bodyCollides(w: BlockQuery, b: Body, x: Float, y: Float, z: Float): Boolean =
        collides(w, x - b.halfWidth + EPS, y + EPS, z - b.halfWidth + EPS, x + b.halfWidth - EPS, y + b.height - EPS, z + b.halfWidth - EPS)

    /**
     * Moves the body by (dx,dy,dz), resolving collisions axis by axis with automatic step-up.
     * Sub-steps large motions so fast bodies cannot tunnel through blocks.
     */
    fun move(w: BlockQuery, b: Body, dx: Float, dy: Float, dz: Float) {
        val maxComp = maxOf(kotlin.math.abs(dx), kotlin.math.abs(dy), kotlin.math.abs(dz))
        val steps = maxOf(1, kotlin.math.ceil(maxComp / 0.4f).toInt())
        b.hitWall = false; b.hitCeiling = false
        val wasOnGround = b.onGround
        if (dy != 0f) b.onGround = false
        val sx = dx / steps; val sy = dy / steps; val sz = dz / steps
        for (i in 0 until steps) {
            // Y
            if (sy != 0f) {
                val ny = b.pos.y + sy
                if (bodyCollides(w, b, b.pos.x, ny, b.pos.z)) {
                    if (sy < 0f) {
                        b.pos.y = landingY(w, b, ny)
                        b.onGround = true
                    } else {
                        b.pos.y = floorInt(ny + b.height) - b.height - EPS
                        b.hitCeiling = true
                    }
                    b.vel.y = 0f
                } else b.pos.y = ny
            }
            // X
            if (sx != 0f) {
                val nx = b.pos.x + sx
                if (bodyCollides(w, b, nx, b.pos.y, b.pos.z)) {
                    if (!tryStep(w, b, nx, b.pos.z, wasOnGround || b.onGround)) {
                        b.pos.x = if (sx > 0f) floorInt(nx + b.halfWidth) - b.halfWidth - EPS else floorInt(nx - b.halfWidth) + 1f + b.halfWidth + EPS
                        if (bodyCollides(w, b, b.pos.x, b.pos.y, b.pos.z)) b.pos.x = nx - sx
                        b.vel.x = 0f; b.hitWall = true
                    }
                } else b.pos.x = nx
            }
            // Z
            if (sz != 0f) {
                val nz = b.pos.z + sz
                if (bodyCollides(w, b, b.pos.x, b.pos.y, nz)) {
                    if (!tryStep(w, b, b.pos.x, nz, wasOnGround || b.onGround)) {
                        b.pos.z = if (sz > 0f) floorInt(nz + b.halfWidth) - b.halfWidth - EPS else floorInt(nz - b.halfWidth) + 1f + b.halfWidth + EPS
                        if (bodyCollides(w, b, b.pos.x, b.pos.y, b.pos.z)) b.pos.z = nz - sz
                        b.vel.z = 0f; b.hitWall = true
                    }
                } else b.pos.z = nz
            }
        }
        if (dy == 0f && wasOnGround) {
            // stay grounded only while something is still underfoot
            b.onGround = bodyCollides(w, b, b.pos.x, b.pos.y - 0.05f, b.pos.z)
        }
    }

    private fun landingY(w: BlockQuery, b: Body, ny: Float): Float {
        // highest collision surface under the feet
        var best = -1e9f
        val x0 = floorInt(b.pos.x - b.halfWidth + EPS); val x1 = floorInt(b.pos.x + b.halfWidth - EPS)
        val z0 = floorInt(b.pos.z - b.halfWidth + EPS); val z1 = floorInt(b.pos.z + b.halfWidth - EPS)
        val y0 = floorInt(ny); val y1 = floorInt(b.pos.y)
        for (y in y0..y1) for (z in z0..z1) for (x in x0..x1) {
            val top = collisionTop(w.getBlock(x, y, z))
            if (top > 0f && y + top > best && y + top <= b.pos.y + EPS * 4f) best = y + top
        }
        return if (best > -1e8f) best + EPS else b.pos.y
    }

    private fun tryStep(w: BlockQuery, b: Body, nx: Float, nz: Float, grounded: Boolean): Boolean {
        if (!grounded || b.stepHeight <= 0f) return false
        var h = 0.0625f
        while (h <= b.stepHeight + 0.001f) {
            if (!bodyCollides(w, b, nx, b.pos.y + h, nz)) {
                if (bodyCollides(w, b, b.pos.x, b.pos.y + h, b.pos.z)) return false
                b.pos.set(nx, b.pos.y + h, nz)
                b.onGround = true
                return true
            }
            h += 0.0625f
        }
        return false
    }

    /** Updates [Body.submerged] from liquid blocks intersecting the body column. */
    fun updateSubmersion(w: BlockQuery, b: Body) {
        val x = floorInt(b.pos.x); val z = floorInt(b.pos.z)
        var liquidTop = -1e9f
        val y0 = floorInt(b.pos.y); val y1 = floorInt(b.pos.y + b.height)
        for (y in y0..y1) {
            if (Blocks.liquid[w.getBlock(x, y, z)]) {
                val surface = if (Blocks.liquid[w.getBlock(x, y + 1, z)]) y + 1f else y + 0.875f
                if (surface > liquidTop) liquidTop = surface
            }
        }
        b.submerged = if (liquidTop < -1e8f) 0f else ((liquidTop - b.pos.y) / b.height).coerceIn(0f, 1f)
    }

    /**
     * Voxel ray cast (Amanatides-Woo DDA). Hits any non-air, non-liquid block
     * (plants included, so they can be harvested).
     */
    fun raycast(w: BlockQuery, ox: Float, oy: Float, oz: Float, dx: Float, dy: Float, dz: Float, maxDist: Float, out: RayHit, hitLiquid: Boolean = false, solidOnly: Boolean = false): Boolean {
        out.hit = false
        var x = floorInt(ox); var y = floorInt(oy); var z = floorInt(oz)
        val stepX = if (dx > 0f) 1 else -1
        val stepY = if (dy > 0f) 1 else -1
        val stepZ = if (dz > 0f) 1 else -1
        val tDeltaX = if (dx != 0f) kotlin.math.abs(1f / dx) else Float.MAX_VALUE
        val tDeltaY = if (dy != 0f) kotlin.math.abs(1f / dy) else Float.MAX_VALUE
        val tDeltaZ = if (dz != 0f) kotlin.math.abs(1f / dz) else Float.MAX_VALUE
        var tMaxX = if (dx != 0f) (if (dx > 0f) (x + 1 - ox) else (ox - x)) * tDeltaX else Float.MAX_VALUE
        var tMaxY = if (dy != 0f) (if (dy > 0f) (y + 1 - oy) else (oy - y)) * tDeltaY else Float.MAX_VALUE
        var tMaxZ = if (dz != 0f) (if (dz > 0f) (z + 1 - oz) else (oz - z)) * tDeltaZ else Float.MAX_VALUE
        var t = 0f
        var nx = 0; var ny = 0; var nz = 0
        while (t <= maxDist) {
            val id = w.getBlock(x, y, z)
            if (id != 0 && (hitLiquid || !Blocks.liquid[id]) && (!solidOnly || Blocks.solid[id])) {
                // partial-height boxes: only hit if the ray actually passes below the top
                val def = Blocks.get(id)
                var ok = true
                if ((def.shape == Shape.BOX || def.shape == Shape.CROSS) && def.boxMaxY < 1f) {
                    val topY = y + def.boxMaxY
                    val yEnter = oy + dy * t
                    val tExit = minOf(tMaxX, tMaxY, tMaxZ)
                    val yExit = oy + dy * tExit
                    ok = minOf(yEnter, yExit) < topY
                    if (ok && yEnter > topY) { nx = 0; ny = 1; nz = 0 }
                }
                if (ok) {
                    out.hit = true; out.x = x; out.y = y; out.z = z
                    out.nx = nx; out.ny = ny; out.nz = nz
                    out.distance = t; out.block = id
                    return true
                }
            }
            if (tMaxX < tMaxY && tMaxX < tMaxZ) {
                x += stepX; t = tMaxX; tMaxX += tDeltaX; nx = -stepX; ny = 0; nz = 0
            } else if (tMaxY < tMaxZ) {
                y += stepY; t = tMaxY; tMaxY += tDeltaY; nx = 0; ny = -stepY; nz = 0
            } else {
                z += stepZ; t = tMaxZ; tMaxZ += tDeltaZ; nx = 0; ny = 0; nz = -stepZ
            }
        }
        return false
    }
}
