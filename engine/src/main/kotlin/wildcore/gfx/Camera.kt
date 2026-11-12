package wildcore.gfx

import wildcore.math.DEG2RAD
import wildcore.math.Frustum
import wildcore.math.Mat4
import wildcore.math.Vec3
import kotlin.math.cos
import kotlin.math.sin

/**
 * Perspective camera. Rendering is camera-relative: [viewRot] has no translation and geometry is
 * offset by (objectPos - cameraPos) on the CPU, which keeps float precision stable far from the origin.
 */
class Camera {
    val pos = Vec3()
    var yaw = 0f      // radians, 0 = looking toward -Z, positive turns right (toward +X)
    var pitch = 0f    // radians, positive looks up
    var fovY = 65f
    var near = 0.12f
    var far = 1200f
    var aspect = 1.6f

    val forward = Vec3()
    val right = Vec3()
    val proj = FloatArray(16)
    val viewRot = FloatArray(16)      // rotation only
    val viewProjRot = FloatArray(16)  // proj * viewRot (camera at origin)
    val invViewProjRot = FloatArray(16)
    val frustum = Frustum()           // in camera-relative space

    fun update() {
        val cp = cos(pitch); val sp = sin(pitch)
        forward.set(sin(yaw) * cp, sp, -cos(yaw) * cp)
        right.set(cos(yaw), 0f, sin(yaw))
        Mat4.perspective(proj, fovY, aspect, near, far)
        Mat4.lookDir(viewRot, 0f, 0f, 0f, forward.x, forward.y, forward.z, 0f, 1f, 0f)
        Mat4.mul(viewProjRot, proj, viewRot)
        Mat4.invert(invViewProjRot, viewProjRot)
        frustum.setFromMatrix(viewProjRot)
    }

    /** World-space direction of the ray through normalized device coords (-1..1). */
    fun rayDirection(ndcX: Float, ndcY: Float, out: Vec3) {
        Mat4.transformPoint(invViewProjRot, ndcX, ndcY, 1f, out)
        out.normalize()
    }

    val fovYRadians: Float get() = fovY * DEG2RAD
}
