package wildcore.world

import wildcore.gfx.GL
import wildcore.gfx.Mesh
import wildcore.gfx.QuadIndexBuffer
import wildcore.gfx.VertexAttrib
import wildcore.gfx.VertexLayout

/** GPU geometry of one chunk: a single VBO holding [opaque][cutout cubes][sprites][water] quad ranges. */
class ChunkMesh(private val gl: GL, private val quadIndices: QuadIndexBuffer) {
    companion object {
        val LAYOUT = VertexLayout(ChunkMesher.VERTEX_BYTES, arrayOf(
            VertexAttrib(0, 2, GL.UNSIGNED_INT, false, 0, integer = true)
        ))
    }

    private val mesh = Mesh(gl, LAYOUT, GL.STATIC_DRAW)
    @JvmField var opaqueQuads = 0
    @JvmField var cutoutQuads = 0
    @JvmField var spriteQuads = 0
    @JvmField var waterQuads = 0
    @JvmField var minY = 0
    @JvmField var maxY = 0
    @JvmField var bytes = 0

    init { mesh.useSharedIndexBuffer(quadIndices.buffer, GL.UNSIGNED_INT) }

    fun upload(data: ChunkMeshData) {
        val total = data.totalQuads
        quadIndices.ensure(total)
        bytes = total * 4 * ChunkMesher.VERTEX_BYTES
        if (total > 0) mesh.setVertices(data.buffer, bytes)
        opaqueQuads = data.opaqueQuads; cutoutQuads = data.cutoutQuads
        spriteQuads = data.spriteQuads; waterQuads = data.waterQuads
        minY = data.minY; maxY = data.maxY
    }

    fun bind() = mesh.bind()

    fun drawRange(firstQuad: Int, quads: Int) {
        if (quads <= 0) return
        gl.drawElements(GL.TRIANGLES, quads * 6, GL.UNSIGNED_INT, firstQuad * 6 * 4)
    }

    fun dispose() = mesh.dispose()
}
