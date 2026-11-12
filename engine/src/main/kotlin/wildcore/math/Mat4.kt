package wildcore.math

import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt
import kotlin.math.tan

/**
 * Column-major 4x4 matrix helpers operating on FloatArray(16) (optionally at an offset),
 * so matrices can live inside flat arrays (bone palettes) without object overhead.
 */
object Mat4 {
    fun identity(m: FloatArray, o: Int = 0) {
        for (i in 0 until 16) m[o + i] = 0f
        m[o] = 1f; m[o + 5] = 1f; m[o + 10] = 1f; m[o + 15] = 1f
    }

    fun copy(src: FloatArray, so: Int, dst: FloatArray, d: Int) {
        System.arraycopy(src, so, dst, d, 16)
    }

    /** out = a * b. out may alias neither a nor b. */
    fun mul(out: FloatArray, oo: Int, a: FloatArray, ao: Int, b: FloatArray, bo: Int) {
        for (c in 0 until 4) {
            val b0 = b[bo + c * 4]; val b1 = b[bo + c * 4 + 1]; val b2 = b[bo + c * 4 + 2]; val b3 = b[bo + c * 4 + 3]
            out[oo + c * 4] = a[ao] * b0 + a[ao + 4] * b1 + a[ao + 8] * b2 + a[ao + 12] * b3
            out[oo + c * 4 + 1] = a[ao + 1] * b0 + a[ao + 5] * b1 + a[ao + 9] * b2 + a[ao + 13] * b3
            out[oo + c * 4 + 2] = a[ao + 2] * b0 + a[ao + 6] * b1 + a[ao + 10] * b2 + a[ao + 14] * b3
            out[oo + c * 4 + 3] = a[ao + 3] * b0 + a[ao + 7] * b1 + a[ao + 11] * b2 + a[ao + 15] * b3
        }
    }
    fun mul(out: FloatArray, a: FloatArray, b: FloatArray) = mul(out, 0, a, 0, b, 0)

    fun perspective(m: FloatArray, fovYDeg: Float, aspect: Float, near: Float, far: Float) {
        val f = 1f / tan(fovYDeg * DEG2RAD * 0.5f)
        for (i in 0 until 16) m[i] = 0f
        m[0] = f / aspect
        m[5] = f
        m[10] = (far + near) / (near - far)
        m[11] = -1f
        m[14] = 2f * far * near / (near - far)
    }

    fun ortho(m: FloatArray, l: Float, r: Float, b: Float, t: Float, n: Float, f: Float) {
        for (i in 0 until 16) m[i] = 0f
        m[0] = 2f / (r - l)
        m[5] = 2f / (t - b)
        m[10] = -2f / (f - n)
        m[12] = -(r + l) / (r - l)
        m[13] = -(t + b) / (t - b)
        m[14] = -(f + n) / (f - n)
        m[15] = 1f
    }

    /** View matrix looking from eye along direction (dx,dy,dz) (need not be normalized). */
    fun lookDir(m: FloatArray, ex: Float, ey: Float, ez: Float, dx: Float, dy: Float, dz: Float, upX: Float, upY: Float, upZ: Float) {
        var fx = dx; var fy = dy; var fz = dz
        val fl = 1f / sqrt(fx * fx + fy * fy + fz * fz)
        fx *= fl; fy *= fl; fz *= fl
        var sx = fy * upZ - fz * upY
        var sy = fz * upX - fx * upZ
        var sz = fx * upY - fy * upX
        val sl = 1f / sqrt(sx * sx + sy * sy + sz * sz)
        sx *= sl; sy *= sl; sz *= sl
        val ux = sy * fz - sz * fy
        val uy = sz * fx - sx * fz
        val uz = sx * fy - sy * fx
        m[0] = sx; m[1] = ux; m[2] = -fx; m[3] = 0f
        m[4] = sy; m[5] = uy; m[6] = -fy; m[7] = 0f
        m[8] = sz; m[9] = uz; m[10] = -fz; m[11] = 0f
        m[12] = -(sx * ex + sy * ey + sz * ez)
        m[13] = -(ux * ex + uy * ey + uz * ez)
        m[14] = (fx * ex + fy * ey + fz * ez)
        m[15] = 1f
    }

    fun translation(m: FloatArray, o: Int, x: Float, y: Float, z: Float) {
        identity(m, o); m[o + 12] = x; m[o + 13] = y; m[o + 14] = z
    }

    /** Compose translation * rotation(quaternion) * uniform scale. */
    fun fromTRS(m: FloatArray, o: Int, tx: Float, ty: Float, tz: Float, qx: Float, qy: Float, qz: Float, qw: Float, s: Float) {
        val xx = qx * qx; val yy = qy * qy; val zz = qz * qz
        val xy = qx * qy; val xz = qx * qz; val yz = qy * qz
        val wx = qw * qx; val wy = qw * qy; val wz = qw * qz
        m[o] = (1f - 2f * (yy + zz)) * s; m[o + 1] = 2f * (xy + wz) * s; m[o + 2] = 2f * (xz - wy) * s; m[o + 3] = 0f
        m[o + 4] = 2f * (xy - wz) * s; m[o + 5] = (1f - 2f * (xx + zz)) * s; m[o + 6] = 2f * (yz + wx) * s; m[o + 7] = 0f
        m[o + 8] = 2f * (xz + wy) * s; m[o + 9] = 2f * (yz - wx) * s; m[o + 10] = (1f - 2f * (xx + yy)) * s; m[o + 11] = 0f
        m[o + 12] = tx; m[o + 13] = ty; m[o + 14] = tz; m[o + 15] = 1f
    }

    fun rotationY(m: FloatArray, o: Int, angle: Float) {
        identity(m, o)
        val c = cos(angle); val s = sin(angle)
        m[o] = c; m[o + 2] = -s; m[o + 8] = s; m[o + 10] = c
    }

    /** General inverse. Returns false if singular. */
    fun invert(out: FloatArray, m: FloatArray): Boolean {
        val a00 = m[0]; val a01 = m[1]; val a02 = m[2]; val a03 = m[3]
        val a10 = m[4]; val a11 = m[5]; val a12 = m[6]; val a13 = m[7]
        val a20 = m[8]; val a21 = m[9]; val a22 = m[10]; val a23 = m[11]
        val a30 = m[12]; val a31 = m[13]; val a32 = m[14]; val a33 = m[15]
        val b00 = a00 * a11 - a01 * a10; val b01 = a00 * a12 - a02 * a10
        val b02 = a00 * a13 - a03 * a10; val b03 = a01 * a12 - a02 * a11
        val b04 = a01 * a13 - a03 * a11; val b05 = a02 * a13 - a03 * a12
        val b06 = a20 * a31 - a21 * a30; val b07 = a20 * a32 - a22 * a30
        val b08 = a20 * a33 - a23 * a30; val b09 = a21 * a32 - a22 * a31
        val b10 = a21 * a33 - a23 * a31; val b11 = a22 * a33 - a23 * a32
        var det = b00 * b11 - b01 * b10 + b02 * b09 + b03 * b08 - b04 * b07 + b05 * b06
        if (det == 0f) return false
        det = 1f / det
        out[0] = (a11 * b11 - a12 * b10 + a13 * b09) * det
        out[1] = (a02 * b10 - a01 * b11 - a03 * b09) * det
        out[2] = (a31 * b05 - a32 * b04 + a33 * b03) * det
        out[3] = (a22 * b04 - a21 * b05 - a23 * b03) * det
        out[4] = (a12 * b08 - a10 * b11 - a13 * b07) * det
        out[5] = (a00 * b11 - a02 * b08 + a03 * b07) * det
        out[6] = (a32 * b02 - a30 * b05 - a33 * b01) * det
        out[7] = (a20 * b05 - a22 * b02 + a23 * b01) * det
        out[8] = (a10 * b10 - a11 * b08 + a13 * b06) * det
        out[9] = (a01 * b08 - a00 * b10 - a03 * b06) * det
        out[10] = (a30 * b04 - a31 * b02 + a33 * b00) * det
        out[11] = (a21 * b02 - a20 * b04 - a23 * b00) * det
        out[12] = (a11 * b07 - a10 * b09 - a12 * b06) * det
        out[13] = (a00 * b09 - a01 * b07 + a02 * b06) * det
        out[14] = (a31 * b01 - a30 * b03 - a32 * b00) * det
        out[15] = (a20 * b03 - a21 * b01 + a22 * b00) * det
        return true
    }

    /** Transforms point (x,y,z,1); writes xyz/w into out. */
    fun transformPoint(m: FloatArray, x: Float, y: Float, z: Float, out: Vec3) {
        val w = m[3] * x + m[7] * y + m[11] * z + m[15]
        val iw = if (w != 0f) 1f / w else 1f
        out.set(
            (m[0] * x + m[4] * y + m[8] * z + m[12]) * iw,
            (m[1] * x + m[5] * y + m[9] * z + m[13]) * iw,
            (m[2] * x + m[6] * y + m[10] * z + m[14]) * iw
        )
    }
}

/** Minimal quaternion helpers on float arrays (x,y,z,w). */
object Quat {
    fun fromEuler(out: FloatArray, o: Int, pitchX: Float, yawY: Float, rollZ: Float) {
        // Rotation order: Y (yaw) * X (pitch) * Z (roll)
        val cx = cos(pitchX * 0.5f); val sx = sin(pitchX * 0.5f)
        val cy = cos(yawY * 0.5f); val sy = sin(yawY * 0.5f)
        val cz = cos(rollZ * 0.5f); val sz = sin(rollZ * 0.5f)
        out[o] = cy * sx * cz + sy * cx * sz
        out[o + 1] = sy * cx * cz - cy * sx * sz
        out[o + 2] = cy * cx * sz - sy * sx * cz
        out[o + 3] = cy * cx * cz + sy * sx * sz
    }

    /** Normalized lerp (shortest path). out may alias a. */
    fun nlerp(out: FloatArray, oo: Int, a: FloatArray, ao: Int, b: FloatArray, bo: Int, t: Float) {
        var bx = b[bo]; var by = b[bo + 1]; var bz = b[bo + 2]; var bw = b[bo + 3]
        val dot = a[ao] * bx + a[ao + 1] * by + a[ao + 2] * bz + a[ao + 3] * bw
        if (dot < 0f) { bx = -bx; by = -by; bz = -bz; bw = -bw }
        val x = a[ao] + (bx - a[ao]) * t
        val y = a[ao + 1] + (by - a[ao + 1]) * t
        val z = a[ao + 2] + (bz - a[ao + 2]) * t
        val w = a[ao + 3] + (bw - a[ao + 3]) * t
        val l = 1f / sqrt(x * x + y * y + z * z + w * w)
        out[oo] = x * l; out[oo + 1] = y * l; out[oo + 2] = z * l; out[oo + 3] = w * l
    }
}
