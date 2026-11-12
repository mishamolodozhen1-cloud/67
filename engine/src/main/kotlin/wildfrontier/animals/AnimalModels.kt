package wildfrontier.animals

import wildcore.anim.AnimationClip
import wildcore.anim.ModelBuilder
import wildcore.anim.Ring
import wildcore.anim.Skeleton
import wildcore.anim.SkinnedMeshData
import wildcore.math.TAU_F
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.sin

/** Skeleton, meshes and animation clips of one quadruped species, generated procedurally from [Species]. */
class AnimalModel(val species: Species) {
    companion object {
        const val ROOT = 0; const val CHEST = 1; const val NECK = 2; const val HEAD = 3; const val PELVIS = 4; const val TAIL = 5
        const val FLU = 6; const val FLL = 7; const val FRU = 8; const val FRL = 9
        const val HLU = 10; const val HLL = 11; const val HRU = 12; const val HRL = 13
        const val EAR_L = 14; const val EAR_R = 15
        private val NAMES = arrayOf("root", "chest", "neck", "head", "pelvis", "tail", "flu", "fll", "fru", "frl", "hlu", "hll", "hru", "hrl", "earL", "earR")
        private val PARENTS = intArrayOf(-1, 0, 1, 2, 0, 4, 1, 6, 1, 8, 4, 10, 4, 12, 3, 3)
    }

    val skeleton: Skeleton
    /** Variant 0 = male (antlers where applicable), 1 = female. */
    val meshes: Array<SkinnedMeshData>
    val idle: AnimationClip; val walk: AnimationClip; val run: AnimationClip; val eat: AnimationClip
    val rest: AnimationClip; val alert: AnimationClip; val attack: AnimationClip; val die: AnimationClip

    private val s = species
    private val yc = s.shoulderHeight - s.bodyHeight * 0.5f
    private val hipY = -s.bodyHeight * 0.22f
    private val legLen = yc + hipY
    private val headTilt = if (s.predator) 0.12f else 0.32f

    init {
        val L = s.bodyLength
        val pos = FloatArray(16 * 3)
        fun p(i: Int, x: Float, y: Float, z: Float) { pos[i * 3] = x; pos[i * 3 + 1] = y; pos[i * 3 + 2] = z }
        p(ROOT, 0f, yc, 0f)
        p(CHEST, 0f, 0f, L * 0.30f)
        p(NECK, 0f, s.bodyHeight * 0.22f, L * 0.15f)
        p(HEAD, 0f, sin(s.neckAngle) * s.neckLength, cos(s.neckAngle) * s.neckLength)
        p(PELVIS, 0f, 0f, -L * 0.30f)
        p(TAIL, 0f, s.bodyHeight * 0.28f, -L * 0.19f)
        val lx = s.bodyWidth * 0.30f
        p(FLU, lx, hipY, L * 0.06f); p(FLL, 0f, -legLen * 0.5f, 0f)
        p(FRU, -lx, hipY, L * 0.06f); p(FRL, 0f, -legLen * 0.5f, 0f)
        p(HLU, lx, hipY, -L * 0.06f); p(HLL, 0f, -legLen * 0.5f, 0f)
        p(HRU, -lx, hipY, -L * 0.06f); p(HRL, 0f, -legLen * 0.5f, 0f)
        p(EAR_L, s.headSize * 0.62f, s.headSize * 0.75f, -s.headLength * 0.05f)
        p(EAR_R, -s.headSize * 0.62f, s.headSize * 0.75f, -s.headLength * 0.05f)
        val rot = FloatArray(16 * 4); for (i in 0 until 16) rot[i * 4 + 3] = 1f
        skeleton = Skeleton(NAMES, PARENTS, pos, rot)
        meshes = if (s.antlers) arrayOf(buildMesh(true), buildMesh(false)) else arrayOf(buildMesh(false))
        idle = bakeIdle(); walk = bakeGait("walk", if (s.hops) 0.55f else 1.0f, false)
        run = bakeGait("run", if (s.hops) 0.34f else 0.46f, true)
        eat = bakeEat(); rest = bakeRest(); alert = bakeAlert(); attack = bakeAttack(); die = bakeDie()
    }

    // ------------------------------------------------------------------ mesh

    private fun buildMesh(antlers: Boolean): SkinnedMeshData {
        val b = ModelBuilder()
        val L = s.bodyLength; val W = s.bodyWidth * 0.5f; val Hb = s.bodyHeight * 0.5f
        val back = s.colorBack; val belly = s.colorBelly
        // torso
        fun tr(zf: Float, fx: Float, fy: Float, dy: Float, a: Int, bb: Int, w: Float) =
            Ring(0f, yc + dy * Hb - (if (zf > -0.3f && zf < 0.2f) s.bellyDrop else 0f), zf * L, W * fx, Hb * fy, a, bb, w, back, belly)
        b.tube(listOf(
            tr(-0.50f, 0.50f, 0.58f, 0.10f, PELVIS, PELVIS, 1f),
            tr(-0.40f, 0.92f, 0.96f, 0.04f, PELVIS, ROOT, 0.85f),
            tr(-0.18f, 1.00f, 1.00f, 0.00f, ROOT, PELVIS, 0.6f),
            tr(0.10f, 1.00f, 1.04f, -0.02f, ROOT, CHEST, 0.6f),
            tr(0.32f, 0.96f, 1.08f, -0.04f, CHEST, ROOT, 0.85f),
            tr(0.46f, 0.66f, 0.84f, 0.06f, CHEST, CHEST, 1f)), 10)
        // neck
        val nbx = 0f; val nby = yc + s.bodyHeight * 0.22f; val nbz = L * 0.45f
        val hx = 0f; val hy = nby + sin(s.neckAngle) * s.neckLength; val hz = nbz + cos(s.neckAngle) * s.neckLength
        val nr0 = W * 0.72f; val nr1 = s.headSize * 0.82f
        b.tube(listOf(
            Ring(nbx, nby - Hb * 0.35f, nbz - L * 0.10f, nr0 * 1.05f, nr0 * 1.25f, CHEST, CHEST, 1f, back, belly),
            Ring(0f, nby + (hy - nby) * 0.35f, nbz + (hz - nbz) * 0.35f, nr0 * 0.8f + nr1 * 0.2f, nr0 * 0.85f + nr1 * 0.2f, NECK, CHEST, 0.7f, back, belly),
            Ring(0f, nby + (hy - nby) * 0.75f, nbz + (hz - nbz) * 0.75f, nr1 * 1.05f, nr1 * 1.1f, NECK, HEAD, 0.75f, back, belly),
            Ring(hx, hy, hz, nr1, nr1, HEAD, HEAD, 1f, back, belly)), 8, capStart = false, capEnd = false)
        // head: skull -> muzzle -> nose, tilted downward
        val ct = cos(headTilt); val st = sin(headTilt)
        fun hp(t: Float, dy: Float = 0f): FloatArray = floatArrayOf(0f, hy + dy - st * t * s.headLength, hz + ct * t * s.headLength)
        val hs = s.headSize
        val nose = s.colorAccent.let { if (s.predator) 0x1E1E1E else 0x2A1E18 }
        val h0 = hp(-0.28f, hs * 0.1f); val h1 = hp(0.05f, hs * 0.18f); val h2 = hp(0.42f, hs * 0.02f); val h3 = hp(0.82f, -hs * 0.1f); val h4 = hp(1.0f, -hs * 0.12f)
        val muzzle = if (s.predator) 0.56f else 0.5f
        b.tube(listOf(
            Ring(h0[0], h0[1], h0[2], hs * 0.62f, hs * 0.66f, HEAD, HEAD, 1f, back, belly),
            Ring(h1[0], h1[1], h1[2], hs * 1.0f, hs * 0.98f, HEAD, HEAD, 1f, back, belly),
            Ring(h2[0], h2[1], h2[2], hs * 0.78f, hs * 0.8f, HEAD, HEAD, 1f, back, belly),
            Ring(h3[0], h3[1], h3[2], hs * muzzle, hs * muzzle, HEAD, HEAD, 1f, back, s.colorAccent),
            Ring(h4[0], h4[1], h4[2], hs * muzzle * 0.62f, hs * muzzle * 0.6f, HEAD, HEAD, 1f, nose, nose)), 8)
        // eyes
        b.detail = 0
        val e = hp(0.22f, hs * 0.34f)
        b.ellipsoid(hs * 0.74f, e[1], e[2], hs * 0.13f, hs * 0.15f, hs * 0.17f, HEAD, 0x0E0C0A, 0x0E0C0A, 4, 6)
        b.ellipsoid(-hs * 0.74f, e[1], e[2], hs * 0.13f, hs * 0.15f, hs * 0.17f, HEAD, 0x0E0C0A, 0x0E0C0A, 4, 6)
        b.detail = 200
        // ears
        for (side in intArrayOf(1, -1)) {
            val bone = if (side == 1) EAR_L else EAR_R
            val ex = side * hs * 0.62f; val ey = hy + hs * 0.75f; val ez = hz - s.headLength * 0.05f
            val out = if (s.hops) 0.12f else 0.55f
            val tipX = ex + side * s.earLength * out; val tipY = ey + s.earLength * (if (s.hops) 1f else 0.82f); val tipZ = ez - s.earLength * 0.15f
            val inner = if (s.hops) 0xD8A8A0 else belly
            b.tube(listOf(
                Ring(ex, ey - hs * 0.2f, ez, hs * 0.2f, hs * 0.14f, HEAD, bone, 0.6f, back, inner),
                Ring((ex + tipX) * 0.5f, (ey + tipY) * 0.5f, (ez + tipZ) * 0.5f, hs * (if (s.hops) 0.26f else 0.3f), hs * 0.1f, bone, bone, 1f, back, inner),
                Ring(tipX, tipY, tipZ, hs * 0.06f, hs * 0.04f, bone, bone, 1f, back, back)), 6)
        }
        // legs
        fun leg(upper: Int, lower: Int, x: Float, z: Float, hind: Boolean) {
            val t = s.legThickness * (if (hind) s.hindLegScale else 1f)
            val top = yc + hipY
            val hoof = 0x2A2420
            b.tube(listOf(
                Ring(x, top + Hb * 0.45f, z, t * 2.3f, t * (if (hind) 3.0f else 2.5f), if (hind) PELVIS else CHEST, upper, 0.6f, back, back),
                Ring(x, top - legLen * 0.12f, z, t * 1.9f, t * (if (hind) 2.4f else 2.0f), upper, upper, 1f, back, s.colorLeg),
                Ring(x, top - legLen * 0.42f, z, t * 1.15f, t * 1.25f, upper, lower, 0.7f, s.colorLeg, s.colorLeg),
                Ring(x, top - legLen * 0.56f, z, t * 1.0f, t * 1.05f, lower, upper, 0.75f, s.colorLeg, s.colorLeg),
                Ring(x, top - legLen * 0.88f, z, t * 0.82f, t * 0.86f, lower, lower, 1f, s.colorLeg, s.colorLeg),
                Ring(x, 0.012f, z + t * 0.3f, t * 1.0f, t * 1.15f, lower, lower, 1f, hoof, hoof)), 6, capStart = false)
        }
        val lx = s.bodyWidth * 0.30f
        leg(FLU, FLL, lx, L * 0.36f, false); leg(FRU, FRL, -lx, L * 0.36f, false)
        leg(HLU, HLL, lx, -L * 0.36f, true); leg(HRU, HRL, -lx, -L * 0.36f, true)
        // tail
        val tz = -L * 0.49f; val ty = yc + s.bodyHeight * 0.28f
        if (s.hops) {
            b.ellipsoid(0f, ty - s.bodyHeight * 0.1f, tz - s.tailBushy * 0.3f, s.tailBushy, s.tailBushy, s.tailBushy, TAIL, s.colorAccent, s.colorAccent, 4, 6)
        } else {
            val droop = if (s.predator) 0.55f else 0.85f
            b.tube(listOf(
                Ring(0f, ty, tz + L * 0.04f, s.tailBushy * 0.7f, s.tailBushy * 0.7f, PELVIS, TAIL, 0.5f, back, back),
                Ring(0f, ty - s.tailLength * droop * 0.45f, tz - s.tailLength * 0.4f, s.tailBushy, s.tailBushy, TAIL, TAIL, 1f, back, s.colorAccent),
                Ring(0f, ty - s.tailLength * droop * 0.9f, tz - s.tailLength * 0.75f, s.tailBushy * 0.85f, s.tailBushy * 0.85f, TAIL, TAIL, 1f, back, s.colorAccent),
                Ring(0f, ty - s.tailLength * droop * 1.1f, tz - s.tailLength * 0.9f, s.tailBushy * 0.2f, s.tailBushy * 0.2f, TAIL, TAIL, 1f, if (s.predator) 0x2A2A2A else s.colorAccent, s.colorAccent)), 6)
        }
        if (antlers) {
            b.detail = 40
            val bone = 0xCDBB98
            for (side in intArrayOf(1, -1)) {
                val ax = side * hs * 0.36f; val ay = hy + hs * 0.85f; val az = hz - hs * 0.1f
                val r = 0.017f
                fun beam(x0: Float, y0: Float, z0: Float, x1: Float, y1: Float, z1: Float, r0: Float, r1: Float) =
                    b.tube(listOf(Ring(x0, y0, z0, r0, r0, HEAD, HEAD, 1f, bone), Ring((x0 + x1) / 2f + side * 0.02f, (y0 + y1) / 2f, (z0 + z1) / 2f, (r0 + r1) / 2f, (r0 + r1) / 2f, HEAD, HEAD, 1f, bone), Ring(x1, y1, z1, r1, r1, HEAD, HEAD, 1f, bone)), 5)
                val mx = ax + side * 0.20f; val my = ay + 0.34f; val mz = az - 0.16f
                beam(ax, ay, az, mx, my, mz, r, r * 0.7f)
                beam(mx, my, mz, mx + side * 0.06f, my + 0.20f, mz + 0.10f, r * 0.7f, r * 0.25f)
                beam(ax + side * 0.07f, ay + 0.12f, az - 0.05f, ax + side * 0.10f, ay + 0.20f, az + 0.18f, r * 0.8f, r * 0.25f)
                beam(ax + side * 0.15f, ay + 0.25f, az - 0.12f, ax + side * 0.27f, ay + 0.40f, az + 0.02f, r * 0.7f, r * 0.25f)
            }
            b.detail = 200
        }
        return b.build()
    }

    // ------------------------------------------------------------------ animation

    private val hindBaseU = -0.34f; private val hindBaseL = 0.62f
    private val frontBaseU = 0.07f; private val frontBaseL = -0.10f

    private fun stance(p: wildcore.anim.PoseBuilder) {
        p.rot(HLU, hindBaseU); p.rot(HLL, hindBaseL); p.rot(HRU, hindBaseU); p.rot(HRL, hindBaseL)
        p.rot(FLU, frontBaseU); p.rot(FLL, frontBaseL); p.rot(FRU, frontBaseU); p.rot(FRL, frontBaseL)
    }

    private fun bakeIdle() = AnimationClip.bake(skeleton, "idle", 5f, true) { ph, p ->
        stance(p)
        val a = ph * TAU_F
        p.move(ROOT, 0f, sin(a * 2f) * 0.004f * s.shoulderHeight, 0f)
        p.rot(CHEST, sin(a * 2f) * 0.012f)
        p.rot(NECK, sin(a) * 0.05f, sin(a) * 0.22f)
        p.rot(HEAD, 0.04f * sin(a * 2f), sin(a + 0.6f) * 0.25f)
        val tw = max(0f, sin(a * 5f)) * (if (ph > 0.6f && ph < 0.8f) 1f else 0f)
        p.rot(EAR_L, 0f, 0f, tw * 0.35f); p.rot(EAR_R, 0f, 0f, -tw * 0.25f)
        p.rot(TAIL, sin(a * 3f) * 0.08f, sin(a * 2f) * 0.2f)
    }

    private fun bakeGait(name: String, dur: Float, fast: Boolean) = AnimationClip.bake(skeleton, name, dur, true, 30) { ph, p ->
        stance(p)
        val amp = if (fast) 0.95f else 0.42f
        // phase offsets: walk = four-beat lateral sequence; run/hop = fore pair then hind pair
        val pFL: Float; val pFR: Float; val pHL: Float; val pHR: Float
        if (fast || s.hops) { pFL = 0f; pFR = if (s.hops) 0.04f else 0.12f; pHL = 0.5f; pHR = if (s.hops) 0.5f else 0.62f }
        else { pFL = 0f; pHR = 0.25f; pFR = 0.5f; pHL = 0.75f }
        fun leg(u: Int, l: Int, off: Float, hind: Boolean) {
            val a = (ph + off) * TAU_F
            val swing = -sin(a) * amp * (if (hind && s.hops) 1.25f else 1f)
            val lift = max(0f, cos(a)) // leg is travelling forward
            p.rot(u, swing)
            p.rot(l, if (hind) -lift * amp * 0.9f else lift * amp * 1.5f)
        }
        leg(FLU, FLL, pFL, false); leg(FRU, FRL, pFR, false); leg(HLU, HLL, pHL, true); leg(HRU, HRL, pHR, true)
        val a = ph * TAU_F
        if (fast || s.hops) {
            val bob = if (s.hops) 0.16f else 0.05f
            p.move(ROOT, 0f, (sin(a + 1.2f) * 0.5f + 0.5f) * bob * s.shoulderHeight, 0f)
            p.rot(ROOT, sin(a + 0.3f) * (if (s.hops) 0.16f else 0.07f))
            p.rot(PELVIS, sin(a) * 0.16f); p.rot(CHEST, -sin(a) * 0.10f)
            p.rot(NECK, 0.18f + sin(a + 0.5f) * 0.06f); p.rot(HEAD, -0.12f)
            p.rot(TAIL, -0.5f + sin(a) * 0.15f)
            p.rot(EAR_L, 0.35f); p.rot(EAR_R, 0.35f)
        } else {
            p.move(ROOT, 0f, sin(a * 2f) * 0.012f * s.shoulderHeight, 0f)
            p.rot(PELVIS, 0f, sin(a) * 0.05f, sin(a) * 0.03f); p.rot(CHEST, 0f, -sin(a) * 0.04f)
            p.rot(NECK, sin(a * 2f) * 0.035f + 0.05f); p.rot(HEAD, -sin(a * 2f) * 0.02f)
            p.rot(TAIL, 0f, sin(a) * 0.18f)
        }
    }

    private fun bakeEat() = AnimationClip.bake(skeleton, "eat", 3f, true) { ph, p ->
        stance(p)
        val a = ph * TAU_F
        val reach = (s.neckAngle + 0.75f)
        p.rot(CHEST, 0.10f)
        p.rot(NECK, reach * 0.78f + sin(a) * 0.04f)
        p.rot(HEAD, 0.25f + sin(a * 7f) * 0.05f)
        p.rot(FLU, 0.12f); p.rot(FRU, -0.08f)
        p.rot(TAIL, 0f, sin(a * 2f) * 0.25f)
        p.rot(EAR_L, 0f, 0f, sin(a * 3f) * 0.1f)
    }

    private fun bakeRest() = AnimationClip.bake(skeleton, "rest", 4f, true) { ph, p ->
        val a = ph * TAU_F
        p.move(ROOT, 0f, -legLen * 0.86f + sin(a) * 0.004f, 0f)
        p.rot(FLU, -1.35f); p.rot(FLL, 2.5f); p.rot(FRU, -1.35f); p.rot(FRL, 2.5f)
        p.rot(HLU, -1.45f); p.rot(HLL, 2.55f); p.rot(HRU, -1.45f); p.rot(HRL, 2.55f)
        p.rot(NECK, 0.35f + sin(a) * 0.02f); p.rot(HEAD, 0.2f)
        p.rot(TAIL, 0.3f)
        p.rot(EAR_L, 0.2f); p.rot(EAR_R, 0.2f)
    }

    private fun bakeAlert() = AnimationClip.bake(skeleton, "alert", 2f, true) { ph, p ->
        stance(p)
        val a = ph * TAU_F
        p.rot(NECK, -0.22f, sin(a) * 0.05f); p.rot(HEAD, -0.1f)
        p.rot(EAR_L, -0.25f, 0.2f); p.rot(EAR_R, -0.25f, -0.2f)
        p.rot(TAIL, -0.6f)
    }

    private fun bakeAttack() = AnimationClip.bake(skeleton, "attack", 0.5f, false, 30) { ph, p ->
        stance(p)
        val k = sin(ph * PI.toFloat())
        p.move(ROOT, 0f, -0.03f * k, 0.22f * k * s.bodyLength)
        p.rot(NECK, 0.35f * k); p.rot(HEAD, -0.45f * k)
        p.rot(FLU, -0.5f * k); p.rot(FRU, -0.5f * k)
        p.rot(TAIL, -0.4f)
    }

    private fun bakeDie() = AnimationClip.bake(skeleton, "die", 0.9f, false, 30) { ph, p ->
        stance(p)
        val k = ph * ph * (3f - 2f * ph)
        p.rot(ROOT, 0f, 0f, 1.5f * k)
        p.move(ROOT, 0f, -(yc - s.bodyWidth * 0.5f) * k, 0f)
        p.rot(NECK, 0.5f * k); p.rot(HEAD, 0.3f * k)
        p.rot(FLU, -0.3f * k); p.rot(FRU, 0.2f * k); p.rot(HLU, 0.3f * k); p.rot(HRU, -0.2f * k)
    }
}
