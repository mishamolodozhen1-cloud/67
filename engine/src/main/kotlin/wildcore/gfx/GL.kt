package wildcore.gfx

import java.nio.Buffer

/**
 * Thin abstraction over OpenGL ES 3.0. The Android app binds it to android.opengl.GLES30;
 * the headless test harness binds it to a desktop GLES 3 context. Only what the engine uses is exposed.
 */
interface GL {
    // --- state
    fun clearColor(r: Float, g: Float, b: Float, a: Float)
    fun clear(mask: Int)
    fun viewport(x: Int, y: Int, w: Int, h: Int)
    fun scissor(x: Int, y: Int, w: Int, h: Int)
    fun enable(cap: Int)
    fun disable(cap: Int)
    fun blendFunc(src: Int, dst: Int)
    fun blendFuncSeparate(srcRgb: Int, dstRgb: Int, srcA: Int, dstA: Int)
    fun depthFunc(func: Int)
    fun depthMask(flag: Boolean)
    fun colorMask(r: Boolean, g: Boolean, b: Boolean, a: Boolean)
    fun cullFace(mode: Int)
    fun polygonOffset(factor: Float, units: Float)

    // --- shaders
    fun createShader(type: Int): Int
    fun shaderSource(shader: Int, source: String)
    fun compileShader(shader: Int)
    fun getShaderCompileStatus(shader: Int): Boolean
    fun getShaderInfoLog(shader: Int): String
    fun deleteShader(shader: Int)
    fun createProgram(): Int
    fun attachShader(program: Int, shader: Int)
    fun bindAttribLocation(program: Int, index: Int, name: String)
    fun linkProgram(program: Int)
    fun getProgramLinkStatus(program: Int): Boolean
    fun getProgramInfoLog(program: Int): String
    fun useProgram(program: Int)
    fun deleteProgram(program: Int)
    fun getUniformLocation(program: Int, name: String): Int
    fun uniform1i(loc: Int, v: Int)
    fun uniform1f(loc: Int, v: Float)
    fun uniform2f(loc: Int, x: Float, y: Float)
    fun uniform3f(loc: Int, x: Float, y: Float, z: Float)
    fun uniform4f(loc: Int, x: Float, y: Float, z: Float, w: Float)
    fun uniform1fv(loc: Int, count: Int, v: FloatArray, offset: Int)
    fun uniform3fv(loc: Int, count: Int, v: FloatArray, offset: Int)
    fun uniform4fv(loc: Int, count: Int, v: FloatArray, offset: Int)
    fun uniformMatrix4fv(loc: Int, count: Int, v: FloatArray, offset: Int)

    // --- buffers / vertex arrays
    fun genBuffer(): Int
    fun bindBuffer(target: Int, buffer: Int)
    fun bufferData(target: Int, sizeBytes: Int, data: Buffer?, usage: Int)
    fun bufferSubData(target: Int, offsetBytes: Int, sizeBytes: Int, data: Buffer)
    fun deleteBuffer(buffer: Int)
    fun genVertexArray(): Int
    fun bindVertexArray(vao: Int)
    fun deleteVertexArray(vao: Int)
    fun enableVertexAttribArray(index: Int)
    fun disableVertexAttribArray(index: Int)
    fun vertexAttribPointer(index: Int, size: Int, type: Int, normalized: Boolean, stride: Int, offset: Int)
    fun vertexAttribIPointer(index: Int, size: Int, type: Int, stride: Int, offset: Int)
    fun vertexAttribDivisor(index: Int, divisor: Int)
    fun drawArrays(mode: Int, first: Int, count: Int)
    fun drawElements(mode: Int, count: Int, type: Int, offsetBytes: Int)
    fun drawArraysInstanced(mode: Int, first: Int, count: Int, instances: Int)
    fun drawElementsInstanced(mode: Int, count: Int, type: Int, offsetBytes: Int, instances: Int)

    // --- textures
    fun genTexture(): Int
    fun bindTexture(target: Int, texture: Int)
    fun activeTexture(unit: Int)
    fun texParameteri(target: Int, pname: Int, value: Int)
    fun texParameterf(target: Int, pname: Int, value: Float)
    fun texImage2D(target: Int, level: Int, internalFormat: Int, w: Int, h: Int, format: Int, type: Int, data: Buffer?)
    fun texSubImage2D(target: Int, level: Int, x: Int, y: Int, w: Int, h: Int, format: Int, type: Int, data: Buffer)
    fun texStorage2D(target: Int, levels: Int, internalFormat: Int, w: Int, h: Int)
    fun texStorage3D(target: Int, levels: Int, internalFormat: Int, w: Int, h: Int, depth: Int)
    fun texSubImage3D(target: Int, level: Int, x: Int, y: Int, z: Int, w: Int, h: Int, d: Int, format: Int, type: Int, data: Buffer)
    fun generateMipmap(target: Int)
    fun deleteTexture(texture: Int)
    fun pixelStorei(pname: Int, value: Int)

    // --- framebuffers
    fun genFramebuffer(): Int
    fun bindFramebuffer(target: Int, fbo: Int)
    fun framebufferTexture2D(target: Int, attachment: Int, texTarget: Int, texture: Int, level: Int)
    fun checkFramebufferStatus(target: Int): Int
    fun deleteFramebuffer(fbo: Int)
    fun blitFramebuffer(sx0: Int, sy0: Int, sx1: Int, sy1: Int, dx0: Int, dy0: Int, dx1: Int, dy1: Int, mask: Int, filter: Int)
    fun invalidateFramebuffer(target: Int, attachments: IntArray)
    fun drawBuffersNone()
    fun readPixels(x: Int, y: Int, w: Int, h: Int, format: Int, type: Int, data: Buffer)

    // --- queries
    fun getString(name: Int): String
    fun getInteger(name: Int): Int
    fun getError(): Int

    companion object {
        const val DEPTH_BUFFER_BIT = 0x0100
        const val COLOR_BUFFER_BIT = 0x4000
        const val POINTS = 0x0000
        const val LINES = 0x0001
        const val TRIANGLES = 0x0004
        const val TRIANGLE_STRIP = 0x0005
        const val ZERO = 0
        const val ONE = 1
        const val SRC_ALPHA = 0x0302
        const val ONE_MINUS_SRC_ALPHA = 0x0303
        const val DST_COLOR = 0x0306
        const val CULL_FACE = 0x0B44
        const val DEPTH_TEST = 0x0B71
        const val BLEND = 0x0BE2
        const val SCISSOR_TEST = 0x0C11
        const val POLYGON_OFFSET_FILL = 0x8037
        const val FRONT = 0x0404
        const val BACK = 0x0405
        const val LESS = 0x0201
        const val LEQUAL = 0x0203
        const val ALWAYS = 0x0207
        const val BYTE = 0x1400
        const val UNSIGNED_BYTE = 0x1401
        const val SHORT = 0x1402
        const val UNSIGNED_SHORT = 0x1403
        const val INT = 0x1404
        const val UNSIGNED_INT = 0x1405
        const val FLOAT = 0x1406
        const val HALF_FLOAT = 0x140B
        const val DEPTH_COMPONENT = 0x1902
        const val RED = 0x1903
        const val RGB = 0x1907
        const val RGBA = 0x1908
        const val R8 = 0x8229
        const val RG8 = 0x822B
        const val RG = 0x8227
        const val RGB8 = 0x8051
        const val RGBA8 = 0x8058
        const val SRGB8_ALPHA8 = 0x8C43
        const val DEPTH_COMPONENT16 = 0x81A5
        const val DEPTH_COMPONENT24 = 0x81A6
        const val NEAREST = 0x2600
        const val LINEAR = 0x2601
        const val NEAREST_MIPMAP_NEAREST = 0x2700
        const val LINEAR_MIPMAP_NEAREST = 0x2701
        const val LINEAR_MIPMAP_LINEAR = 0x2703
        const val TEXTURE_MAG_FILTER = 0x2800
        const val TEXTURE_MIN_FILTER = 0x2801
        const val TEXTURE_WRAP_S = 0x2802
        const val TEXTURE_WRAP_T = 0x2803
        const val TEXTURE_MAX_LEVEL = 0x813D
        const val TEXTURE_COMPARE_MODE = 0x884C
        const val TEXTURE_COMPARE_FUNC = 0x884D
        const val COMPARE_REF_TO_TEXTURE = 0x884E
        const val TEXTURE_MAX_ANISOTROPY_EXT = 0x84FE
        const val MAX_TEXTURE_MAX_ANISOTROPY_EXT = 0x84FF
        const val REPEAT = 0x2901
        const val CLAMP_TO_EDGE = 0x812F
        const val MIRRORED_REPEAT = 0x8370
        const val TEXTURE_2D = 0x0DE1
        const val TEXTURE_2D_ARRAY = 0x8C1A
        const val TEXTURE0 = 0x84C0
        const val ARRAY_BUFFER = 0x8892
        const val ELEMENT_ARRAY_BUFFER = 0x8893
        const val STATIC_DRAW = 0x88E4
        const val DYNAMIC_DRAW = 0x88E8
        const val STREAM_DRAW = 0x88E0
        const val FRAGMENT_SHADER = 0x8B30
        const val VERTEX_SHADER = 0x8B31
        const val FRAMEBUFFER = 0x8D40
        const val READ_FRAMEBUFFER = 0x8CA8
        const val DRAW_FRAMEBUFFER = 0x8CA9
        const val COLOR_ATTACHMENT0 = 0x8CE0
        const val DEPTH_ATTACHMENT = 0x8D00
        const val FRAMEBUFFER_COMPLETE = 0x8CD5
        const val COLOR = 0x1800
        const val DEPTH = 0x1801
        const val UNPACK_ALIGNMENT = 0x0CF5
        const val PACK_ALIGNMENT = 0x0D05
        const val VENDOR = 0x1F00
        const val RENDERER = 0x1F01
        const val VERSION = 0x1F02
        const val EXTENSIONS = 0x1F03
        const val MAX_TEXTURE_SIZE = 0x0D33
        const val MAX_ARRAY_TEXTURE_LAYERS = 0x88FF
        const val NO_ERROR = 0
    }
}

/** Capabilities of the current GL context, queried once per context. */
class GpuCaps(
    val vendor: String,
    val renderer: String,
    val version: String,
    val maxTextureSize: Int,
    val maxArrayLayers: Int,
    val anisotropy: Float,
) {
    companion object {
        fun query(gl: GL): GpuCaps {
            val ext = gl.getString(GL.EXTENSIONS)
            val aniso = if (ext.contains("texture_filter_anisotropic")) gl.getInteger(GL.MAX_TEXTURE_MAX_ANISOTROPY_EXT).toFloat() else 1f
            return GpuCaps(
                gl.getString(GL.VENDOR), gl.getString(GL.RENDERER), gl.getString(GL.VERSION),
                gl.getInteger(GL.MAX_TEXTURE_SIZE), gl.getInteger(GL.MAX_ARRAY_TEXTURE_LAYERS), aniso
            )
        }
    }
}
