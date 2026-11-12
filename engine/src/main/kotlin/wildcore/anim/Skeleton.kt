package wildcore.anim

import wildcore.math.Mat4
import wildcore.math.Quat

/** Bone hierarchy with a bind pose. Parents must precede their children. */
class Skeleton(val names: Array<String>, val parents: IntArray, val bindPos: FloatArray, val bindRot: FloatArray) {
    val count: Int = names.size
    val inverseBind = FloatArray(16 * count)

    init {
        require(count <= MAX_BONES) { "too many bones: $count" }
        val world = FloatArray(16 * count)
        val local = FloatArray(16)
        val tmp = FloatArray(16)
        for (i in 0 until count) {
            Mat4.fromTRS(local, 0, bindPos[i * 3], bindPos[i * 3 + 1], bindPos[i * 3 + 2], bindRot[i * 4], bindRot[i * 4 + 1], bindRot[i * 4 + 2], bindRot[i * 4 + 3], 1f)
            if (parents[i] < 0) Mat4.copy(local, 0, world, i * 16) else Mat4.mul(world, i * 16, world, parents[i] * 16, local, 0)
            System.arraycopy(world, i * 16, tmp, 0, 16)
            val inv = FloatArray(16)
            Mat4.invert(inv, tmp)
            System.arraycopy(inv, 0, inverseBind, i * 16, 16)
        }
    }

    fun index(name: String): Int { val i = names.indexOf(name); require(i >= 0) { "no bone $name" }; return i }

    companion object { const val MAX_BONES = 40 }
}

/** Local transforms of every bone. */
class Pose(val count: Int) {
    val rot = FloatArray(count * 4)
    val pos = FloatArray(count * 3)

    fun setBind(s: Skeleton) {
        System.arraycopy(s.bindRot, 0, rot, 0, count * 4)
        System.arraycopy(s.bindPos, 0, pos, 0, count * 3)
    }
    fun copyFrom(o: Pose) {
        System.arraycopy(o.rot, 0, rot, 0, count * 4)
        System.arraycopy(o.pos, 0, pos, 0, count * 3)
    }
    /** this = lerp(this, o, t) */
    fun blendToward(o: Pose, t: Float) {
        for (i in 0 until count) Quat.nlerp(rot, i * 4, rot, i * 4, o.rot, i * 4, t)
        for (i in 0 until count * 3) pos[i] += (o.pos[i] - pos[i]) * t
    }
}

/** Authoring helper handed to procedural clip functions: rotations are relative to the bind pose. */
class PoseBuilder(private val skeleton: Skeleton, private val pose: Pose) {
    private val q = FloatArray(4)
    private val r = FloatArray(4)

    fun reset() = pose.setBind(skeleton)

    /** Rotates a bone by Euler angles (radians): pitch about X, yaw about Y, roll about Z. */
    fun rot(bone: Int, pitch: Float, yaw: Float = 0f, roll: Float = 0f) {
        Quat.fromEuler(q, 0, pitch, yaw, roll)
        val o = bone * 4
        // result = current * delta
        val ax = pose.rot[o]; val ay = pose.rot[o + 1]; val az = pose.rot[o + 2]; val aw = pose.rot[o + 3]
        r[0] = aw * q[0] + ax * q[3] + ay * q[2] - az * q[1]
        r[1] = aw * q[1] - ax * q[2] + ay * q[3] + az * q[0]
        r[2] = aw * q[2] + ax * q[1] - ay * q[0] + az * q[3]
        r[3] = aw * q[3] - ax * q[0] - ay * q[1] - az * q[2]
        pose.rot[o] = r[0]; pose.rot[o + 1] = r[1]; pose.rot[o + 2] = r[2]; pose.rot[o + 3] = r[3]
    }

    fun move(bone: Int, dx: Float, dy: Float, dz: Float) {
        pose.pos[bone * 3] += dx; pose.pos[bone * 3 + 1] += dy; pose.pos[bone * 3 + 2] += dz
    }
}

/** Keyframed animation: per-frame local rotation + translation for every bone, sampled with interpolation. */
class AnimationClip(val name: String, val duration: Float, val loop: Boolean, val frames: Int, private val boneCount: Int) {
    val rot = FloatArray(frames * boneCount * 4)
    val pos = FloatArray(frames * boneCount * 3)

    fun sample(time: Float, out: Pose) {
        var t = if (duration > 0f) time / duration else 0f
        t = if (loop) t - kotlin.math.floor(t) else t.coerceIn(0f, 1f)
        val span = if (loop) frames else frames - 1
        val f = t * span
        val i0 = minOf(f.toInt(), frames - 1)
        val i1 = if (loop) (i0 + 1) % frames else minOf(i0 + 1, frames - 1)
        val k = f - i0
        val r0 = i0 * boneCount * 4; val r1 = i1 * boneCount * 4
        for (b in 0 until boneCount) wildcore.math.Quat.nlerp(out.rot, b * 4, rot, r0 + b * 4, rot, r1 + b * 4, k)
        val p0 = i0 * boneCount * 3; val p1 = i1 * boneCount * 3
        for (j in 0 until boneCount * 3) out.pos[j] = pos[p0 + j] + (pos[p1 + j] - pos[p0 + j]) * k
    }

    companion object {
        /** Bakes a procedural motion into keyframes. [fn] receives the normalized phase 0..1. */
        fun bake(s: Skeleton, name: String, duration: Float, loop: Boolean, fps: Int = 24, fn: (phase: Float, p: PoseBuilder) -> Unit): AnimationClip {
            val frames = maxOf(2, (duration * fps).toInt())
            val clip = AnimationClip(name, duration, loop, frames, s.count)
            val pose = Pose(s.count)
            val pb = PoseBuilder(s, pose)
            for (f in 0 until frames) {
                pb.reset()
                fn(if (loop) f.toFloat() / frames else f.toFloat() / (frames - 1), pb)
                System.arraycopy(pose.rot, 0, clip.rot, f * s.count * 4, s.count * 4)
                System.arraycopy(pose.pos, 0, clip.pos, f * s.count * 3, s.count * 3)
            }
            return clip
        }
    }
}

/**
 * Plays clips on a skeleton: cross-fades between clips, supports an overlay clip restricted to a bone
 * mask (e.g. an arm swing on top of a walk cycle) and produces the skinning matrix palette.
 */
class Animator(val skeleton: Skeleton) {
    private val pose = Pose(skeleton.count)
    private val from = Pose(skeleton.count)
    private val scratch = Pose(skeleton.count)
    private val world = FloatArray(16 * skeleton.count)
    private val local = FloatArray(16)
    private val tmp = FloatArray(16)
    var clip: AnimationClip? = null; private set
    var time = 0f
    var speed = 1f
    private var fade = 1f
    private var fadeDuration = 0.2f

    var overlay: AnimationClip? = null; private set
    var overlayTime = 0f
    var overlayMask: BooleanArray? = null
    private var overlayWeight = 0f

    init { pose.setBind(skeleton) }

    fun play(c: AnimationClip, fadeTime: Float = 0.2f, restart: Boolean = false) {
        if (clip === c && !restart) return
        from.copyFrom(pose)
        clip = c
        time = 0f
        fade = if (fadeTime <= 0f) 1f else 0f
        fadeDuration = fadeTime
    }

    fun playOverlay(c: AnimationClip, mask: BooleanArray) { overlay = c; overlayMask = mask; overlayTime = 0f }
    val overlayActive: Boolean get() = overlay != null
    val finished: Boolean get() { val c = clip ?: return true; return !c.loop && time >= c.duration }

    fun update(dt: Float) {
        val c = clip ?: return
        time += dt * speed
        c.sample(time, pose)
        if (fade < 1f) {
            fade = minOf(1f, fade + dt / fadeDuration)
            val k = fade * fade * (3f - 2f * fade)
            scratch.copyFrom(from)
            scratch.blendToward(pose, k)
            pose.copyFrom(scratch)
        }
        val o = overlay
        if (o != null) {
            overlayTime += dt
            val ending = overlayTime >= o.duration
            overlayWeight = if (ending) maxOf(0f, overlayWeight - dt * 8f) else minOf(1f, overlayWeight + dt * 10f)
            o.sample(minOf(overlayTime, o.duration), scratch)
            val mask = overlayMask!!
            for (b in 0 until skeleton.count) if (mask[b]) wildcore.math.Quat.nlerp(pose.rot, b * 4, pose.rot, b * 4, scratch.rot, b * 4, overlayWeight)
            if (ending && overlayWeight <= 0f) overlay = null
        }
    }

    /** Writes model * boneWorld * inverseBind for every bone into [out] (16 floats per bone). */
    fun palette(model: FloatArray, out: FloatArray) {
        val s = skeleton
        for (i in 0 until s.count) {
            Mat4.fromTRS(local, 0, pose.pos[i * 3], pose.pos[i * 3 + 1], pose.pos[i * 3 + 2], pose.rot[i * 4], pose.rot[i * 4 + 1], pose.rot[i * 4 + 2], pose.rot[i * 4 + 3], 1f)
            if (s.parents[i] < 0) Mat4.mul(world, i * 16, model, 0, local, 0)
            else Mat4.mul(world, i * 16, world, s.parents[i] * 16, local, 0)
        }
        for (i in 0 until s.count) Mat4.mul(out, i * 16, world, i * 16, s.inverseBind, i * 16)
    }

    /** World-space (model-relative) position of a bone origin after [palette] was called. */
    fun boneWorld(bone: Int, out: FloatArray) { System.arraycopy(world, bone * 16, out, 0, 16) }
}
