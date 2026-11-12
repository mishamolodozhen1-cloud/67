package wildcore.gfx

import wildcore.core.Log

/** Offscreen render target with optional color texture and depth texture. */
class Framebuffer(private val gl: GL, val width: Int, val height: Int, color: Boolean, depth: Boolean, shadowCompare: Boolean = false, linear: Boolean = true) {
    val fbo: Int = gl.genFramebuffer()
    var colorTex: Texture2D? = null; private set
    var depthTex: Texture2D? = null; private set

    init {
        gl.bindFramebuffer(GL.FRAMEBUFFER, fbo)
        if (color) {
            val t = Texture2D(gl)
            t.allocate(width, height, GL.RGBA8, GL.RGBA, GL.UNSIGNED_BYTE, linear)
            gl.framebufferTexture2D(GL.FRAMEBUFFER, GL.COLOR_ATTACHMENT0, GL.TEXTURE_2D, t.id, 0)
            colorTex = t
        } else {
            gl.drawBuffersNone()
        }
        if (depth) {
            val t = Texture2D(gl)
            t.allocate(width, height, GL.DEPTH_COMPONENT24, GL.DEPTH_COMPONENT, GL.UNSIGNED_INT, shadowCompare)
            if (shadowCompare) {
                gl.texParameteri(GL.TEXTURE_2D, GL.TEXTURE_COMPARE_MODE, GL.COMPARE_REF_TO_TEXTURE)
                gl.texParameteri(GL.TEXTURE_2D, GL.TEXTURE_COMPARE_FUNC, GL.LEQUAL)
            }
            gl.framebufferTexture2D(GL.FRAMEBUFFER, GL.DEPTH_ATTACHMENT, GL.TEXTURE_2D, t.id, 0)
            depthTex = t
        }
        val status = gl.checkFramebufferStatus(GL.FRAMEBUFFER)
        if (status != GL.FRAMEBUFFER_COMPLETE) Log.e("Framebuffer", "incomplete framebuffer: 0x${Integer.toHexString(status)} (${width}x$height)")
        gl.bindFramebuffer(GL.FRAMEBUFFER, 0)
    }

    fun bind() {
        gl.bindFramebuffer(GL.FRAMEBUFFER, fbo)
        gl.viewport(0, 0, width, height)
    }

    val memoryBytes: Long get() = (if (colorTex != null) width.toLong() * height * 4 else 0L) + (if (depthTex != null) width.toLong() * height * 4 else 0L)

    fun dispose() {
        colorTex?.dispose()
        depthTex?.dispose()
        gl.deleteFramebuffer(fbo)
    }
}
