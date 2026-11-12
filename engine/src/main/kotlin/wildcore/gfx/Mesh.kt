package wildcore.gfx

import java.nio.ByteBuffer
import java.nio.ByteOrder

/** One vertex attribute inside an interleaved buffer. */
class VertexAttrib(val index: Int, val size: Int, val type: Int, val normalized: Boolean, val offset: Int, val integer: Boolean = false)

class VertexLayout(val stride: Int, val attribs: Array<VertexAttrib>) {
    fun apply(gl: GL, divisor: Int = 0) {
        for (a in attribs) {
            gl.enableVertexAttribArray(a.index)
            if (a.integer) gl.vertexAttribIPointer(a.index, a.size, a.type, stride, a.offset)
            else gl.vertexAttribPointer(a.index, a.size, a.type, a.normalized, stride, a.offset)
            if (divisor != 0) gl.vertexAttribDivisor(a.index, divisor)
        }
    }
}

/** VAO + VBO (+ optional IBO). Buffers can be re-specified for dynamic geometry. */
class Mesh(private val gl: GL, val layout: VertexLayout, private val usage: Int = GL.STATIC_DRAW) {
    val vao: Int = gl.genVertexArray()
    val vbo: Int = gl.genBuffer()
    private var ibo = 0
    var vertexCount = 0; private set
    var indexCount = 0; private set
    var indexType = GL.UNSIGNED_SHORT; private set
    var vboBytes = 0; private set
    private var vboCapacity = 0

    init {
        gl.bindVertexArray(vao)
        gl.bindBuffer(GL.ARRAY_BUFFER, vbo)
        layout.apply(gl)
        gl.bindVertexArray(0)
    }

    /** Uploads [bytes] bytes from [data] (position..limit must cover them). */
    fun setVertices(data: ByteBuffer, bytes: Int) {
        gl.bindBuffer(GL.ARRAY_BUFFER, vbo)
        if (bytes > vboCapacity || usage == GL.STATIC_DRAW) {
            gl.bufferData(GL.ARRAY_BUFFER, bytes, data, usage)
            vboCapacity = bytes
        } else {
            gl.bufferSubData(GL.ARRAY_BUFFER, 0, bytes, data)
        }
        vboBytes = bytes
        vertexCount = bytes / layout.stride
    }

    fun setIndices(data: ByteBuffer, count: Int, type: Int) {
        if (ibo == 0) ibo = gl.genBuffer()
        gl.bindVertexArray(vao)
        gl.bindBuffer(GL.ELEMENT_ARRAY_BUFFER, ibo)
        gl.bufferData(GL.ELEMENT_ARRAY_BUFFER, count * (if (type == GL.UNSIGNED_INT) 4 else 2), data, usage)
        gl.bindVertexArray(0)
        indexCount = count
        indexType = type
    }

    /** Attach an index buffer shared between meshes (e.g. the global quad index buffer). */
    fun useSharedIndexBuffer(buffer: Int, type: Int) {
        gl.bindVertexArray(vao)
        gl.bindBuffer(GL.ELEMENT_ARRAY_BUFFER, buffer)
        gl.bindVertexArray(0)
        indexType = type
    }

    fun bind() = gl.bindVertexArray(vao)

    fun draw(mode: Int = GL.TRIANGLES) {
        gl.bindVertexArray(vao)
        if (indexCount > 0) gl.drawElements(mode, indexCount, indexType, 0)
        else gl.drawArrays(mode, 0, vertexCount)
    }

    fun dispose() {
        gl.deleteVertexArray(vao)
        gl.deleteBuffer(vbo)
        if (ibo != 0) gl.deleteBuffer(ibo)
    }

    companion object {
        fun directBuffer(bytes: Int): ByteBuffer = ByteBuffer.allocateDirect(bytes).order(ByteOrder.nativeOrder())
    }
}

/**
 * Index buffer shared by every quad-based mesh (voxel chunks, particles, UI): quad q uses vertices
 * 4q..4q+3 with indices (0,1,2, 2,3,0). Grows on demand; one buffer instead of one per chunk.
 */
class QuadIndexBuffer(private val gl: GL) {
    var buffer = gl.genBuffer(); private set
    var quadCapacity = 0; private set

    init { ensure(16384) }

    /** Returns true if the buffer was reallocated (it keeps the same GL name, so VAOs stay valid). */
    fun ensure(quads: Int): Boolean {
        if (quads <= quadCapacity) return false
        var cap = maxOf(quadCapacity, 16384)
        while (cap < quads) cap *= 2
        val bb = Mesh.directBuffer(cap * 6 * 4)
        val ib = bb.asIntBuffer()
        for (q in 0 until cap) {
            val v = q * 4
            ib.put(v).put(v + 1).put(v + 2).put(v + 2).put(v + 3).put(v)
        }
        gl.bindVertexArray(0)
        gl.bindBuffer(GL.ELEMENT_ARRAY_BUFFER, buffer)
        gl.bufferData(GL.ELEMENT_ARRAY_BUFFER, cap * 6 * 4, bb, GL.STATIC_DRAW)
        quadCapacity = cap
        return true
    }

    fun dispose() = gl.deleteBuffer(buffer)
}
