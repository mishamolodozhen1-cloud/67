package wildfrontier.player

import wildcore.anim.AnimationClip
import wildcore.anim.ModelBuilder
import wildcore.anim.Ring
import wildcore.anim.Skeleton
import wildcore.anim.SkinnedMeshData
import wildcore.math.TAU_F
import kotlin.math.PI
import kotlin.math.max
import kotlin.math.sin

/** Procedurally built survivor: skeleton, body mesh, held-tool mesh and animation clips. */
class PlayerModel {
    companion object {
        const val HIPS = 0; const val SPINE = 1; const val HEAD = 2
        const val ARM_LU = 3; const val ARM_LL = 4; const val ARM_RU = 5; const val ARM_RL = 6
        const val LEG_LU = 7; const val LEG_LL = 8; const val LEG_RU = 9; const val LEG_RL = 10
        private val NAMES = arrayOf("hips", "spine", "head", "armLU", "armLL", "armRU", "armRL", "legLU", "legLL", "legRU", "legRL")
        private val PARENTS = intArrayOf(-1, 0, 1, 1, 3, 1, 5, 0, 7, 0, 9)
        const val HIP_Y = 0.95f
        const val SKIN = 0xD9A57E; const val SHIRT = 0x6C7F5A; const val PANTS = 0x3B4658; const val BOOTS = 0x4A3524
        const val HAIR = 0x3A2A1E; const val PACK = 0x7A6240
    }

    val skeleton: Skeleton
    val body: SkinnedMeshData
    val tool: SkinnedMeshData
    val raft: SkinnedMeshData
    val idle: AnimationClip; val walk: AnimationClip; val run: AnimationClip; val air: AnimationClip
    val swim: AnimationClip; val crouchIdle: AnimationClip; val crouchWalk: AnimationClip
    val swing: AnimationClip; val die: AnimationClip; val sit: AnimationClip
    val swingMask = BooleanArray(11).also { it[SPINE] = true; it[ARM_RU] = true; it[ARM_RL] = true }

    init {
        val pos = floatArrayOf(
            0f, HIP_Y, 0f,   0f, 0.12f, 0f,   0f, 0.48f, 0f,
            0.215f, 0.38f, 0f,   0f, -0.28f, 0f,   -0.215f, 0.38f, 0f,   0f, -0.28f, 0f,
            0.095f, -0.03f, 0f,   0f, -0.44f, 0f,   -0.095f, -0.03f, 0f,   0f, -0.44f, 0f)
        val rot = FloatArray(11 * 4); for (i in 0 until 11) rot[i * 4 + 3] = 1f
        skeleton = Skeleton(NAMES, PARENTS, pos, rot)
        body = buildBody()
        tool = buildTool()
        raft = buildRaft()
        idle = AnimationClip.bake(skeleton, "idle", 4f, true) { ph, p ->
            val a = ph * TAU_F
            p.move(HIPS, 0f, sin(a) * 0.004f, 0f)
            p.rot(SPINE, 0.02f + sin(a) * 0.012f)
            p.rot(HEAD, sin(a * 0.5f) * 0.03f, sin(a) * 0.06f)
            p.rot(ARM_LU, 0.04f, 0f, -0.07f); p.rot(ARM_RU, 0.04f, 0f, 0.07f)
            p.rot(ARM_LL, -0.12f); p.rot(ARM_RL, -0.12f)
        }
        walk = gait("walk", 0.92f, 0.52f, 0.42f, 0.05f, -0.25f)
        run = gait("run", 0.60f, 0.95f, 0.85f, 0.17f, -1.15f)
        air = AnimationClip.bake(skeleton, "air", 1f, true) { ph, p ->
            p.rot(SPINE, 0.06f)
            p.rot(LEG_LU, -0.45f); p.rot(LEG_LL, 0.7f); p.rot(LEG_RU, -0.1f); p.rot(LEG_RL, 0.45f)
            p.rot(ARM_LU, -0.5f, 0f, -0.35f); p.rot(ARM_RU, -0.5f, 0f, 0.35f); p.rot(ARM_LL, -0.4f); p.rot(ARM_RL, -0.4f)
        }
        swim = AnimationClip.bake(skeleton, "swim", 1.3f, true) { ph, p ->
            val a = ph * TAU_F
            p.rot(HIPS, 1.2f)
            p.move(HIPS, 0f, 0.35f, 0f)
            p.rot(HEAD, -0.75f)
            p.rot(ARM_LU, -2.6f + sin(a) * 0.9f, 0f, -0.25f); p.rot(ARM_RU, -2.6f - sin(a) * 0.9f, 0f, 0.25f)
            p.rot(ARM_LL, -0.35f); p.rot(ARM_RL, -0.35f)
            p.rot(LEG_LU, sin(a * 2f) * 0.35f); p.rot(LEG_RU, -sin(a * 2f) * 0.35f)
            p.rot(LEG_LL, 0.25f + max(0f, sin(a * 2f)) * 0.3f); p.rot(LEG_RL, 0.25f + max(0f, -sin(a * 2f)) * 0.3f)
        }
        crouchIdle = AnimationClip.bake(skeleton, "crouchIdle", 3f, true) { ph, p -> crouchBase(p, 0f, ph) }
        crouchWalk = AnimationClip.bake(skeleton, "crouchWalk", 1.1f, true) { ph, p -> crouchBase(p, 1f, ph) }
        swing = AnimationClip.bake(skeleton, "swing", 0.36f, false, 30) { ph, p ->
            val k = if (ph < 0.35f) ph / 0.35f else 1f - (ph - 0.35f) / 0.65f   // raise fast, strike, recover
            val strike = if (ph < 0.35f) 0f else sin((ph - 0.35f) / 0.65f * PI.toFloat())
            p.rot(SPINE, 0.10f * strike, -0.25f * k + 0.3f * strike)
            p.rot(ARM_RU, -2.3f * k - 0.9f * strike, 0f, 0.15f)
            p.rot(ARM_RL, -0.9f * k - 0.2f * strike)
        }
        die = AnimationClip.bake(skeleton, "die", 1.0f, false, 30) { ph, p ->
            val k = ph * ph * (3f - 2f * ph)
            p.rot(HIPS, -1.5f * k)
            p.move(HIPS, 0f, -(HIP_Y - 0.14f) * k, -0.4f * k)
            p.rot(ARM_LU, 0f, 0f, -0.9f * k); p.rot(ARM_RU, 0f, 0f, 0.9f * k)
            p.rot(LEG_LU, -0.15f * k, 0f, -0.15f * k); p.rot(LEG_RU, 0.1f * k, 0f, 0.15f * k)
        }
        sit = AnimationClip.bake(skeleton, "sit", 3f, true) { ph, p ->
            val a = ph * TAU_F
            p.move(HIPS, 0f, -0.62f, 0f)
            p.rot(SPINE, 0.12f + sin(a) * 0.01f)
            p.rot(LEG_LU, -1.45f, 0f, -0.12f); p.rot(LEG_RU, -1.45f, 0f, 0.12f); p.rot(LEG_LL, 0.35f); p.rot(LEG_RL, 0.35f)
            p.rot(ARM_LU, -0.5f); p.rot(ARM_RU, -0.5f); p.rot(ARM_LL, -0.7f); p.rot(ARM_RL, -0.7f)
        }
    }

    private fun crouchBase(p: wildcore.anim.PoseBuilder, walkAmt: Float, ph: Float) {
        val a = ph * TAU_F
        p.move(HIPS, 0f, -0.30f, 0f)
        p.rot(SPINE, 0.42f)
        p.rot(HEAD, -0.35f)
        val s = sin(a) * 0.35f * walkAmt
        p.rot(LEG_LU, -0.95f - s); p.rot(LEG_LL, 1.55f + max(0f, s) * 0.4f)
        p.rot(LEG_RU, -0.95f + s); p.rot(LEG_RL, 1.55f + max(0f, -s) * 0.4f)
        p.rot(ARM_LU, -0.25f + s * 0.6f); p.rot(ARM_RU, -0.25f - s * 0.6f)
        p.rot(ARM_LL, -0.7f); p.rot(ARM_RL, -0.7f)
    }

    private fun gait(name: String, dur: Float, legAmp: Float, armAmp: Float, lean: Float, elbow: Float) =
        AnimationClip.bake(skeleton, name, dur, true, 30) { ph, p ->
            val a = ph * TAU_F
            val s = sin(a)
            p.move(HIPS, 0f, kotlin.math.abs(kotlin.math.cos(a)) * 0.035f * legAmp - 0.02f * legAmp, 0f)
            p.rot(HIPS, 0f, s * 0.07f * legAmp)
            p.rot(SPINE, lean, -s * 0.13f * legAmp)
            p.rot(HEAD, -lean * 0.6f, s * 0.05f)
            p.rot(LEG_LU, -s * legAmp); p.rot(LEG_RU, s * legAmp)
            p.rot(LEG_LL, max(0f, -kotlin.math.cos(a + 0.5f)) * legAmp * 1.25f + 0.06f)
            p.rot(LEG_RL, max(0f, kotlin.math.cos(a + 0.5f)) * legAmp * 1.25f + 0.06f)
            p.rot(ARM_LU, s * armAmp, 0f, -0.06f); p.rot(ARM_RU, -s * armAmp, 0f, 0.06f)
            p.rot(ARM_LL, elbow - max(0f, s) * 0.25f); p.rot(ARM_RL, elbow - max(0f, -s) * 0.25f)
        }

    private fun buildBody(): SkinnedMeshData {
        val b = ModelBuilder()
        b.detail = 120
        // legs (pants + boots)
        for (side in intArrayOf(1, -1)) {
            val u = if (side == 1) LEG_LU else LEG_RU; val l = if (side == 1) LEG_LL else LEG_RL
            val x = side * 0.095f
            b.tube(listOf(
                Ring(x, HIP_Y + 0.02f, 0f, 0.092f, 0.10f, HIPS, u, 0.5f, PANTS),
                Ring(x, HIP_Y - 0.20f, 0f, 0.086f, 0.092f, u, u, 1f, PANTS),
                Ring(x, HIP_Y - 0.42f, 0.005f, 0.066f, 0.070f, u, l, 0.6f, PANTS),
                Ring(x, HIP_Y - 0.50f, 0.005f, 0.064f, 0.068f, l, u, 0.7f, PANTS),
                Ring(x, 0.26f, -0.005f, 0.056f, 0.060f, l, l, 1f, PANTS),
                Ring(x, 0.22f, -0.005f, 0.066f, 0.070f, l, l, 1f, BOOTS),
                Ring(x, 0.07f, 0.0f, 0.062f, 0.075f, l, l, 1f, BOOTS),
                Ring(x, 0.012f, 0.035f, 0.064f, 0.115f, l, l, 1f, 0x2E2018)), 8, capStart = false)
        }
        // torso
        b.tube(listOf(
            Ring(0f, HIP_Y - 0.06f, 0f, 0.165f, 0.105f, HIPS, HIPS, 1f, PANTS),
            Ring(0f, HIP_Y + 0.06f, 0f, 0.168f, 0.108f, HIPS, SPINE, 0.6f, 0x4A3A28),
            Ring(0f, HIP_Y + 0.11f, 0f, 0.160f, 0.104f, SPINE, HIPS, 0.6f, SHIRT),
            Ring(0f, HIP_Y + 0.26f, 0.005f, 0.172f, 0.110f, SPINE, SPINE, 1f, SHIRT),
            Ring(0f, HIP_Y + 0.42f, 0.01f, 0.198f, 0.118f, SPINE, SPINE, 1f, SHIRT),
            Ring(0f, HIP_Y + 0.52f, 0f, 0.185f, 0.105f, SPINE, SPINE, 1f, SHIRT),
            Ring(0f, HIP_Y + 0.575f, 0f, 0.075f, 0.07f, SPINE, HEAD, 0.6f, SKIN),
            Ring(0f, HIP_Y + 0.63f, 0.005f, 0.058f, 0.06f, HEAD, HEAD, 1f, SKIN)), 10, capEnd = false)
        // arms
        for (side in intArrayOf(1, -1)) {
            val u = if (side == 1) ARM_LU else ARM_RU; val l = if (side == 1) ARM_LL else ARM_RL
            val x = side * 0.235f; val top = HIP_Y + 0.51f
            b.tube(listOf(
                Ring(x - side * 0.03f, top + 0.01f, 0f, 0.058f, 0.06f, SPINE, u, 0.4f, SHIRT),
                Ring(x, top - 0.06f, 0f, 0.056f, 0.058f, u, u, 1f, SHIRT),
                Ring(x, top - 0.24f, 0f, 0.046f, 0.048f, u, l, 0.7f, SHIRT),
                Ring(x, top - 0.30f, 0f, 0.043f, 0.045f, l, u, 0.7f, SKIN),
                Ring(x, top - 0.50f, 0.005f, 0.036f, 0.038f, l, l, 1f, SKIN),
                Ring(x, top - 0.58f, 0.01f, 0.040f, 0.030f, l, l, 1f, SKIN),
                Ring(x, top - 0.635f, 0.015f, 0.022f, 0.02f, l, l, 1f, SKIN)), 7, capStart = false)
        }
        // head, hair, face
        val hy = HIP_Y + 0.735f
        b.detail = 60
        b.ellipsoid(0f, hy, 0.005f, 0.098f, 0.122f, 0.108f, HEAD, SKIN, SKIN, 7, 10)
        b.detail = 220
        b.ellipsoid(0f, hy + 0.03f, -0.018f, 0.106f, 0.112f, 0.112f, HEAD, HAIR, HAIR, 6, 10)
        b.detail = 0
        b.ellipsoid(0.038f, hy + 0.012f, 0.098f, 0.014f, 0.011f, 0.012f, HEAD, 0x1A1410)
        b.ellipsoid(-0.038f, hy + 0.012f, 0.098f, 0.014f, 0.011f, 0.012f, HEAD, 0x1A1410)
        b.detail = 60
        b.ellipsoid(0f, hy - 0.02f, 0.108f, 0.014f, 0.022f, 0.016f, HEAD, 0xC8946E)
        // backpack with bedroll
        b.detail = 160
        b.box(-0.14f, HIP_Y + 0.14f, -0.245f, 0.14f, HIP_Y + 0.50f, -0.10f, SPINE, PACK)
        b.box(-0.10f, HIP_Y + 0.20f, -0.275f, 0.10f, HIP_Y + 0.36f, -0.245f, SPINE, 0x5E4A30)
        b.tube(listOf(Ring(-0.17f, HIP_Y + 0.555f, -0.17f, 0.055f, 0.055f, SPINE, SPINE, 1f, 0x6E8050), Ring(0.17f, HIP_Y + 0.555f, -0.17f, 0.055f, 0.055f, SPINE, SPINE, 1f, 0x6E8050)), 8)
        return b.build()
    }

    /** Generic hand tool held in the right hand (handle + head). */
    private fun buildTool(): SkinnedMeshData {
        val b = ModelBuilder()
        b.detail = 120
        val x = -0.235f; val y = HIP_Y + 0.51f - 0.60f; val z = 0.02f
        b.tube(listOf(Ring(x, y, z - 0.10f, 0.014f, 0.014f, ARM_RL, ARM_RL, 1f, 0x7A5632), Ring(x, y, z + 0.42f, 0.013f, 0.013f, ARM_RL, ARM_RL, 1f, 0x8A6238)), 6)
        b.box(x - 0.022f, y - 0.085f, z + 0.33f, x + 0.022f, y + 0.085f, z + 0.42f, ARM_RL, 0x8E9298)
        return b.build()
    }

    /** Log raft: a single-bone mesh drawn with the same skinned shader. */
    private fun buildRaft(): SkinnedMeshData {
        val b = ModelBuilder()
        b.detail = 230
        for (i in 0 until 6) {
            val x = -0.75f + i * 0.30f
            b.tube(listOf(Ring(x, 0.02f, -1.15f, 0.145f, 0.145f, 0, 0, 1f, 0x6E4E30, 0x4E3622), Ring(x, 0.02f, 1.15f, 0.14f, 0.14f, 0, 0, 1f, 0x74543A, 0x4E3622)), 8)
        }
        for (z in floatArrayOf(-0.8f, 0.8f)) {
            b.tube(listOf(Ring(-0.9f, 0.16f, z, 0.05f, 0.05f, 0, 0, 1f, 0x8A6A44), Ring(0.9f, 0.16f, z, 0.05f, 0.05f, 0, 0, 1f, 0x8A6A44)), 6)
        }
        return b.build()
    }
}
