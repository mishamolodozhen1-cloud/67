package wildcore.gfx

import wildcore.core.Platform
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * Batched 2D renderer for the interface: rounded rectangles, rings, distance-field text and
 * atlas sprites all go through one shader and (normally) one draw call per frame.
 * Coordinates are in pixels with the origin at the top-left.
 */
class UiBatch(private val gl: GL, private val quads: QuadIndexBuffer, shaders: ShaderLibrary) {
    companion object {
        const val MAX_QUADS = 4096
        private const val STRIDE = 36
        const val MODE_RECT = 0f; const val MODE_TEXT = 1f; const val MODE_ICON = 2f; const val MODE_RING = 3f; const val MODE_AUX = 4f
    }

    private val shader = shaders.load("ui", "ui.vert", "ui.frag", arrayOf("aPos", "aUv", "aColor", "aParams"))
    private val layout = VertexLayout(STRIDE, arrayOf(
        VertexAttrib(0, 2, GL.FLOAT, false, 0),
        VertexAttrib(1, 2, GL.FLOAT, false, 8),
        VertexAttrib(2, 4, GL.UNSIGNED_BYTE, true, 16),
        VertexAttrib(3, 4, GL.FLOAT, false, 20)))
    private val mesh = Mesh(gl, layout, GL.DYNAMIC_DRAW)
    private val buf: ByteBuffer = ByteBuffer.allocateDirect(MAX_QUADS * 4 * STRIDE).order(ByteOrder.nativeOrder())
    private var count = 0
    private var screenW = 1f
    private var screenH = 1f
    var drawCalls = 0; private set
    var fontTex: Texture2D? = null
    var iconTex: Texture2D? = null
    var auxTex: Texture2D? = null

    init {
        mesh.useSharedIndexBuffer(quads.buffer, GL.UNSIGNED_INT)
        quads.ensure(MAX_QUADS)
    }

    fun begin(w: Int, h: Int) {
        screenW = w.toFloat(); screenH = h.toFloat()
        count = 0; drawCalls = 0
        buf.clear()
    }

    private fun vertex(x: Float, y: Float, u: Float, v: Float, color: Int, p0: Float, p1: Float, p2: Float, mode: Float) {
        buf.putFloat(x).putFloat(y).putFloat(u).putFloat(v)
        buf.put((color shr 16).toByte()).put((color shr 8).toByte()).put(color.toByte()).put((color ushr 24).toByte())
        buf.putFloat(p0).putFloat(p1).putFloat(p2).putFloat(mode)
    }

    private fun quad(x: Float, y: Float, w: Float, h: Float, u0: Float, v0: Float, u1: Float, v1: Float, color: Int, p0: Float, p1: Float, p2: Float, mode: Float) {
        if (count == MAX_QUADS) flush()
        vertex(x, y, u0, v0, color, p0, p1, p2, mode)
        vertex(x + w, y, u1, v0, color, p0, p1, p2, mode)
        vertex(x + w, y + h, u1, v1, color, p0, p1, p2, mode)
        vertex(x, y + h, u0, v1, color, p0, p1, p2, mode)
        count++
    }

    /** Rounded rectangle; colour is 0xAARRGGBB. */
    fun rect(x: Float, y: Float, w: Float, h: Float, color: Int, radius: Float = 0f) {
        val hw = w * 0.5f; val hh = h * 0.5f
        val r = minOf(radius, hw, hh)
        // expand by one pixel so the anti-aliased edge is not clipped
        quad(x - 1f, y - 1f, w + 2f, h + 2f, -hw - 1f, -hh - 1f, hw + 1f, hh + 1f, color, hw, hh, r, MODE_RECT)
    }

    fun ring(cx: Float, cy: Float, radius: Float, thickness: Float, color: Int) {
        val r = radius + 1f
        quad(cx - r, cy - r, r * 2f, r * 2f, -r, -r, r, r, color, radius, radius, thickness * 0.5f, MODE_RING)
    }

    fun circle(cx: Float, cy: Float, radius: Float, color: Int) = rect(cx - radius, cy - radius, radius * 2f, radius * 2f, color, radius)

    fun glyph(x: Float, y: Float, w: Float, h: Float, u0: Float, v0: Float, u1: Float, v1: Float, color: Int) =
        quad(x, y, w, h, u0, v0, u1, v1, color, 0f, 0f, 0f, MODE_TEXT)

    fun icon(x: Float, y: Float, w: Float, h: Float, u0: Float, v0: Float, u1: Float, v1: Float, color: Int = -1) =
        quad(x, y, w, h, u0, v0, u1, v1, color, 0f, 0f, 0f, MODE_ICON)

    fun aux(x: Float, y: Float, w: Float, h: Float, u0: Float, v0: Float, u1: Float, v1: Float, color: Int = -1) =
        quad(x, y, w, h, u0, v0, u1, v1, color, 0f, 0f, 0f, MODE_AUX)

    fun flush() {
        if (count == 0) return
        val bytes = count * 4 * STRIDE
        buf.position(0).limit(bytes)
        shader.use()
        shader.set2f("uScreen", screenW, screenH)
        fontTex?.bind(0); iconTex?.bind(1); auxTex?.bind(2)
        shader.set1i("uFont", 0); shader.set1i("uIcons", 1); shader.set1i("uAux", 2)
        mesh.setVertices(buf, bytes)
        mesh.bind()
        gl.drawElements(GL.TRIANGLES, count * 6, GL.UNSIGNED_INT, 0)
        gl.activeTexture(GL.TEXTURE0)
        drawCalls++
        count = 0
        buf.clear()
    }

    fun dispose() = mesh.dispose()
}

/** Distance-field bitmap font baked by tools/build_ui_assets.py. */
class Font(gl: GL, platform: Platform) {
    val texture = Texture2D(gl)
    private val nominal: Float
    val lineHeight: Float
    private val pad: Float
    private val atlasW: Float
    private val atlasH: Float
    // glyph tables: direct index for the common ranges, linear list for the few symbols
    private val table = IntArray(0x500) { -1 }
    private val extraCp: IntArray
    private val gx: FloatArray; private val gy: FloatArray; private val gw: FloatArray; private val gh: FloatArray
    private val gOff: FloatArray; private val gAdv: FloatArray

    init {
        val bb = ByteBuffer.wrap(platform.readAsset("ui/font.bin")).order(ByteOrder.LITTLE_ENDIAN)
        val n = bb.int
        nominal = bb.int.toFloat()
        lineHeight = bb.float
        bb.float // ascent (unused)
        pad = bb.float
        atlasW = bb.float; atlasH = bb.float
        gx = FloatArray(n); gy = FloatArray(n); gw = FloatArray(n); gh = FloatArray(n); gOff = FloatArray(n); gAdv = FloatArray(n)
        val extras = ArrayList<Int>()
        for (i in 0 until n) {
            val cp = bb.int
            gx[i] = bb.float; gy[i] = bb.float; gw[i] = bb.float; gh[i] = bb.float; gOff[i] = bb.float; gAdv[i] = bb.float
            if (cp < table.size) table[cp] = i else { extras.add(cp); extras.add(i) }
        }
        extraCp = extras.toIntArray()
        val img = platform.decodeImage(platform.readAsset("ui/font.png"))
        val r = ByteArray(img.width * img.height)
        for (i in r.indices) r[i] = img.rgba[i * 4]
        texture.uploadRaw(img.width, img.height, r, GL.R8, GL.RED, mipmaps = false, repeat = false, linear = true)
    }

    private fun glyphIndex(c: Char): Int {
        val cp = c.code
        if (cp < table.size) return table[cp]
        var i = 0
        while (i < extraCp.size) { if (extraCp[i] == cp) return extraCp[i + 1]; i += 2 }
        return -1
    }

    fun width(text: CharSequence, px: Float, start: Int = 0, end: Int = text.length): Float {
        val s = px / nominal
        var w = 0f
        for (i in start until end) { val g = glyphIndex(text[i]); if (g >= 0) w += gAdv[g] * s }
        return w
    }

    /** Draws one line. [align]: 0 left, 1 centre, 2 right. Returns the pen x after the text. */
    fun draw(b: UiBatch, text: CharSequence, x: Float, y: Float, px: Float, color: Int, align: Int = 0, start: Int = 0, end: Int = text.length): Float {
        val s = px / nominal
        var pen = when (align) { 1 -> x - width(text, px, start, end) * 0.5f; 2 -> x - width(text, px, start, end); else -> x }
        val top = y - pad * s
        for (i in start until end) {
            val g = glyphIndex(text[i])
            if (g < 0) continue
            if (text[i] != ' ') {
                b.glyph(pen + gOff[g] * s, top, gw[g] * s, gh[g] * s,
                    gx[g] / atlasW, gy[g] / atlasH, (gx[g] + gw[g]) / atlasW, (gy[g] + gh[g]) / atlasH, color)
            }
            pen += gAdv[g] * s
        }
        return pen
    }

    /** Word-wrapped paragraph; returns the height used. Honours '\n'. Pass a null batch to only measure. */
    fun drawWrapped(b: UiBatch?, text: CharSequence, x: Float, y: Float, maxWidth: Float, px: Float, color: Int, spacing: Float = 1.25f): Float {
        val lineH = px * spacing
        val s = px / nominal
        val n = text.length
        var lineStart = 0
        var cy = y
        while (lineStart < n) {
            var i = lineStart
            var lastSpace = -1
            var end = n
            var next = n
            var w = 0f
            while (i < n) {
                val c = text[i]
                if (c == '\n') { end = i; next = i + 1; break }
                if (c == ' ') lastSpace = i
                val g = glyphIndex(c)
                if (g >= 0) w += gAdv[g] * s
                if (w > maxWidth && i > lineStart) {
                    if (lastSpace > lineStart) { end = lastSpace; next = lastSpace + 1 } else { end = i; next = i }
                    break
                }
                i++
            }
            if (b != null && end > lineStart) draw(b, text, x, cy, px, color, 0, lineStart, end)
            cy += lineH
            lineStart = next
        }
        return cy - y
    }

    fun dispose() = texture.dispose()
}
