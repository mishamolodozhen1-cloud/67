package wildfrontier.desktop

import org.lwjgl.BufferUtils
import org.lwjgl.opengles.GLES20
import org.lwjgl.opengles.GLES30
import wildcore.gfx.GL
import java.nio.Buffer
import java.nio.ByteBuffer

/** GL binding for the headless test harness (LWJGL GLES 3 on Mesa llvmpipe). Development tool only. */
class DesktopGL : GL {
    private val fb = BufferUtils.createFloatBuffer(16 * 64)

    private fun bytes(data: Buffer, size: Int): ByteBuffer {
        val b = (data as ByteBuffer).duplicate()
        b.limit(b.position() + size)
        return b
    }
    private fun floats(v: FloatArray, offset: Int, n: Int): java.nio.FloatBuffer {
        fb.clear(); fb.put(v, offset, n); fb.flip(); return fb
    }

    override fun clearColor(r: Float, g: Float, b: Float, a: Float) = GLES20.glClearColor(r, g, b, a)
    override fun clear(mask: Int) = GLES20.glClear(mask)
    override fun viewport(x: Int, y: Int, w: Int, h: Int) = GLES20.glViewport(x, y, w, h)
    override fun scissor(x: Int, y: Int, w: Int, h: Int) = GLES20.glScissor(x, y, w, h)
    override fun enable(cap: Int) = GLES20.glEnable(cap)
    override fun disable(cap: Int) = GLES20.glDisable(cap)
    override fun blendFunc(src: Int, dst: Int) = GLES20.glBlendFunc(src, dst)
    override fun blendFuncSeparate(srcRgb: Int, dstRgb: Int, srcA: Int, dstA: Int) = GLES20.glBlendFuncSeparate(srcRgb, dstRgb, srcA, dstA)
    override fun depthFunc(func: Int) = GLES20.glDepthFunc(func)
    override fun depthMask(flag: Boolean) = GLES20.glDepthMask(flag)
    override fun colorMask(r: Boolean, g: Boolean, b: Boolean, a: Boolean) = GLES20.glColorMask(r, g, b, a)
    override fun cullFace(mode: Int) = GLES20.glCullFace(mode)
    override fun polygonOffset(factor: Float, units: Float) = GLES20.glPolygonOffset(factor, units)

    override fun createShader(type: Int): Int = GLES20.glCreateShader(type)
    override fun shaderSource(shader: Int, source: String) = GLES20.glShaderSource(shader, source)
    override fun compileShader(shader: Int) = GLES20.glCompileShader(shader)
    override fun getShaderCompileStatus(shader: Int): Boolean = GLES20.glGetShaderi(shader, GLES20.GL_COMPILE_STATUS) != 0
    override fun getShaderInfoLog(shader: Int): String = GLES20.glGetShaderInfoLog(shader)
    override fun deleteShader(shader: Int) = GLES20.glDeleteShader(shader)
    override fun createProgram(): Int = GLES20.glCreateProgram()
    override fun attachShader(program: Int, shader: Int) = GLES20.glAttachShader(program, shader)
    override fun bindAttribLocation(program: Int, index: Int, name: String) = GLES20.glBindAttribLocation(program, index, name)
    override fun linkProgram(program: Int) = GLES20.glLinkProgram(program)
    override fun getProgramLinkStatus(program: Int): Boolean = GLES20.glGetProgrami(program, GLES20.GL_LINK_STATUS) != 0
    override fun getProgramInfoLog(program: Int): String = GLES20.glGetProgramInfoLog(program)
    override fun useProgram(program: Int) = GLES20.glUseProgram(program)
    override fun deleteProgram(program: Int) = GLES20.glDeleteProgram(program)
    override fun getUniformLocation(program: Int, name: String): Int = GLES20.glGetUniformLocation(program, name)
    override fun uniform1i(loc: Int, v: Int) = GLES20.glUniform1i(loc, v)
    override fun uniform1f(loc: Int, v: Float) = GLES20.glUniform1f(loc, v)
    override fun uniform2f(loc: Int, x: Float, y: Float) = GLES20.glUniform2f(loc, x, y)
    override fun uniform3f(loc: Int, x: Float, y: Float, z: Float) = GLES20.glUniform3f(loc, x, y, z)
    override fun uniform4f(loc: Int, x: Float, y: Float, z: Float, w: Float) = GLES20.glUniform4f(loc, x, y, z, w)
    override fun uniform1fv(loc: Int, count: Int, v: FloatArray, offset: Int) = GLES20.glUniform1fv(loc, floats(v, offset, count))
    override fun uniform3fv(loc: Int, count: Int, v: FloatArray, offset: Int) = GLES20.glUniform3fv(loc, floats(v, offset, count * 3))
    override fun uniform4fv(loc: Int, count: Int, v: FloatArray, offset: Int) = GLES20.glUniform4fv(loc, floats(v, offset, count * 4))
    override fun uniformMatrix4fv(loc: Int, count: Int, v: FloatArray, offset: Int) = GLES20.glUniformMatrix4fv(loc, false, floats(v, offset, count * 16))

    override fun genBuffer(): Int = GLES20.glGenBuffers()
    override fun bindBuffer(target: Int, buffer: Int) = GLES20.glBindBuffer(target, buffer)
    override fun bufferData(target: Int, sizeBytes: Int, data: Buffer?, usage: Int) {
        if (data == null) GLES20.glBufferData(target, sizeBytes.toLong(), usage) else GLES20.glBufferData(target, bytes(data, sizeBytes), usage)
    }
    override fun bufferSubData(target: Int, offsetBytes: Int, sizeBytes: Int, data: Buffer) = GLES20.glBufferSubData(target, offsetBytes.toLong(), bytes(data, sizeBytes))
    override fun deleteBuffer(buffer: Int) = GLES20.glDeleteBuffers(buffer)
    override fun genVertexArray(): Int = GLES30.glGenVertexArrays()
    override fun bindVertexArray(vao: Int) = GLES30.glBindVertexArray(vao)
    override fun deleteVertexArray(vao: Int) = GLES30.glDeleteVertexArrays(vao)
    override fun enableVertexAttribArray(index: Int) = GLES20.glEnableVertexAttribArray(index)
    override fun disableVertexAttribArray(index: Int) = GLES20.glDisableVertexAttribArray(index)
    override fun vertexAttribPointer(index: Int, size: Int, type: Int, normalized: Boolean, stride: Int, offset: Int) =
        GLES20.glVertexAttribPointer(index, size, type, normalized, stride, offset.toLong())
    override fun vertexAttribIPointer(index: Int, size: Int, type: Int, stride: Int, offset: Int) =
        GLES30.glVertexAttribIPointer(index, size, type, stride, offset.toLong())
    override fun vertexAttribDivisor(index: Int, divisor: Int) = GLES30.glVertexAttribDivisor(index, divisor)
    override fun drawArrays(mode: Int, first: Int, count: Int) = GLES20.glDrawArrays(mode, first, count)
    override fun drawElements(mode: Int, count: Int, type: Int, offsetBytes: Int) = GLES20.glDrawElements(mode, count, type, offsetBytes.toLong())
    override fun drawArraysInstanced(mode: Int, first: Int, count: Int, instances: Int) = GLES30.glDrawArraysInstanced(mode, first, count, instances)
    override fun drawElementsInstanced(mode: Int, count: Int, type: Int, offsetBytes: Int, instances: Int) =
        GLES30.glDrawElementsInstanced(mode, count, type, offsetBytes.toLong(), instances)

    override fun genTexture(): Int = GLES20.glGenTextures()
    override fun bindTexture(target: Int, texture: Int) = GLES20.glBindTexture(target, texture)
    override fun activeTexture(unit: Int) = GLES20.glActiveTexture(unit)
    override fun texParameteri(target: Int, pname: Int, value: Int) = GLES20.glTexParameteri(target, pname, value)
    override fun texParameterf(target: Int, pname: Int, value: Float) = GLES20.glTexParameterf(target, pname, value)
    override fun texImage2D(target: Int, level: Int, internalFormat: Int, w: Int, h: Int, format: Int, type: Int, data: Buffer?) =
        GLES20.glTexImage2D(target, level, internalFormat, w, h, 0, format, type, data as ByteBuffer?)
    override fun texSubImage2D(target: Int, level: Int, x: Int, y: Int, w: Int, h: Int, format: Int, type: Int, data: Buffer) =
        GLES20.glTexSubImage2D(target, level, x, y, w, h, format, type, data as ByteBuffer)
    override fun texStorage2D(target: Int, levels: Int, internalFormat: Int, w: Int, h: Int) = GLES30.glTexStorage2D(target, levels, internalFormat, w, h)
    override fun texStorage3D(target: Int, levels: Int, internalFormat: Int, w: Int, h: Int, depth: Int) = GLES30.glTexStorage3D(target, levels, internalFormat, w, h, depth)
    override fun texSubImage3D(target: Int, level: Int, x: Int, y: Int, z: Int, w: Int, h: Int, d: Int, format: Int, type: Int, data: Buffer) =
        GLES30.glTexSubImage3D(target, level, x, y, z, w, h, d, format, type, data as ByteBuffer)
    override fun generateMipmap(target: Int) = GLES20.glGenerateMipmap(target)
    override fun deleteTexture(texture: Int) = GLES20.glDeleteTextures(texture)
    override fun pixelStorei(pname: Int, value: Int) = GLES20.glPixelStorei(pname, value)

    override fun genFramebuffer(): Int = GLES20.glGenFramebuffers()
    override fun bindFramebuffer(target: Int, fbo: Int) = GLES20.glBindFramebuffer(target, fbo)
    override fun framebufferTexture2D(target: Int, attachment: Int, texTarget: Int, texture: Int, level: Int) =
        GLES20.glFramebufferTexture2D(target, attachment, texTarget, texture, level)
    override fun checkFramebufferStatus(target: Int): Int = GLES20.glCheckFramebufferStatus(target)
    override fun deleteFramebuffer(fbo: Int) = GLES20.glDeleteFramebuffers(fbo)
    override fun blitFramebuffer(sx0: Int, sy0: Int, sx1: Int, sy1: Int, dx0: Int, dy0: Int, dx1: Int, dy1: Int, mask: Int, filter: Int) =
        GLES30.glBlitFramebuffer(sx0, sy0, sx1, sy1, dx0, dy0, dx1, dy1, mask, filter)
    override fun invalidateFramebuffer(target: Int, attachments: IntArray) = GLES30.glInvalidateFramebuffer(target, attachments)
    override fun drawBuffersNone() { GLES30.glDrawBuffers(intArrayOf(GLES20.GL_NONE)); GLES30.glReadBuffer(GLES20.GL_NONE) }
    override fun readPixels(x: Int, y: Int, w: Int, h: Int, format: Int, type: Int, data: Buffer) =
        GLES20.glReadPixels(x, y, w, h, format, type, data as ByteBuffer)

    override fun getString(name: Int): String = GLES20.glGetString(name) ?: ""
    override fun getInteger(name: Int): Int = GLES20.glGetInteger(name)
    override fun getError(): Int = GLES20.glGetError()
}
