package wildfrontier.ui

import wildcore.core.Engine
import wildcore.core.TouchEvent
import wildcore.gfx.Font
import wildcore.gfx.Texture2D
import wildcore.gfx.UiBatch
import wildfrontier.render.WorldRenderer

/** One finger. Coordinates are in virtual units (see [Ui]). */
class Pointer {
    var id = -1
    var active = false
    var x = 0f; var y = 0f
    var startX = 0f; var startY = 0f
    var dx = 0f; var dy = 0f
    var down = false          // went down this frame
    var up = false            // released this frame
    var owner = 0             // widget id that captured it; 0 = free
    var heldTime = 0f
    var travel = 0f
}

/**
 * Immediate-mode interface toolkit. Everything is laid out in virtual units where the screen is always
 * 720 units tall and proportionally wide, so the same layout fits any phone resolution and aspect ratio.
 */
class Ui(private val engine: Engine) {
    companion object {
        const val OWNER_JOYSTICK = -1
        const val OWNER_LOOK = -2
        const val OWNER_BLOCKED = -3
        const val HELD = 1; const val CLICKED = 2; const val PRESSED = 4

        const val WHITE = -1
        const val TEXT = 0xFFF2F4F0.toInt()
        const val TEXT_DIM = 0xFFB4BBB0.toInt()
        const val PANEL = 0xE61A211C.toInt()
        const val PANEL_LIGHT = 0xE62A332C.toInt()
        const val SLOT = 0xCC101510.toInt()
        const val SLOT_HI = 0xFF5F8F4A.toInt()
        const val ACCENT = 0xFF7DBB55.toInt()
        const val ACCENT_DARK = 0xFF41702E.toInt()
        const val WARN = 0xFFE0B040.toInt()
        const val DANGER = 0xFFD9503C.toInt()
        const val SHADOW = 0x99000000.toInt()
    }

    lateinit var batch: UiBatch; private set
    lateinit var font: Font; private set
    private lateinit var icons: Texture2D
    private val iconIndex = HashMap<String, Int>()
    private var iconCols = 16
    private var iconRows = 16

    val pointers = Array(10) { Pointer() }
    var scale = 1f; private set          // pixels per virtual unit
    var vw = 1280f; private set          // virtual width
    val vh = 720f
    var safeL = 0f; private set
    var safeR = 0f; private set
    var safeT = 0f; private set
    var safeB = 0f; private set
    var time = 0f; private set
    /** Set by modal screens: gameplay controls ignore input while true. */
    var modal = false
    var backPressed = false; private set

    fun init(renderer: WorldRenderer?) {
        val gl = engine.gl
        val quads = renderer?.quads ?: wildcore.gfx.QuadIndexBuffer(gl)
        val shaders = renderer?.shaders ?: wildcore.gfx.ShaderLibrary(gl, engine.platform)
        batch = UiBatch(gl, quads, shaders)
        font = Font(gl, engine.platform)
        icons = Texture2D(gl)
        val img = engine.platform.decodeImage(engine.platform.readAsset("ui/icons.png"))
        icons.upload(img, srgb = false, mipmaps = true, repeat = false)
        iconCols = img.width / 64; iconRows = img.height / 64
        iconIndex.clear()
        String(engine.platform.readAsset("ui/icons.txt"), Charsets.UTF_8).lineSequence().filter { it.isNotBlank() }
            .forEachIndexed { i, n -> iconIndex[n.trim()] = i }
        batch.fontTex = font.texture
        batch.iconTex = icons
    }

    fun iconId(name: String): Int = iconIndex[name] ?: 0
    fun hasIcon(name: String): Boolean = iconIndex.containsKey(name)

    fun resize(w: Int, h: Int) {
        scale = h / vh
        vw = w / scale
        val ins = engine.platform.safeInsets()
        safeL = ins[0] / scale; safeT = ins[1] / scale; safeR = ins[2] / scale; safeB = ins[3] / scale
    }

    // ------------------------------------------------------------------ input

    /** Feed this frame's raw touch events. Call once per frame before any widget. */
    fun beginInput(events: List<TouchEvent>, dt: Float) {
        time += dt
        backPressed = engine.input.consumeBack()
        for (p in pointers) {
            if (p.up) { p.active = false; p.id = -1; p.owner = 0 }
            p.down = false; p.up = false; p.dx = 0f; p.dy = 0f
            if (p.active) p.heldTime += dt
        }
        for (e in events) {
            val x = e.x / scale; val y = e.y / scale
            when (e.action) {
                TouchEvent.DOWN -> {
                    val p = pointers.firstOrNull { !it.active } ?: continue
                    p.id = e.id; p.active = true; p.down = true; p.up = false
                    p.x = x; p.y = y; p.startX = x; p.startY = y; p.dx = 0f; p.dy = 0f
                    p.owner = 0; p.heldTime = 0f; p.travel = 0f
                }
                TouchEvent.MOVE -> {
                    val p = pointers.firstOrNull { it.active && it.id == e.id } ?: continue
                    p.dx += x - p.x; p.dy += y - p.y
                    p.travel += kotlin.math.abs(x - p.x) + kotlin.math.abs(y - p.y)
                    p.x = x; p.y = y
                }
                else -> {
                    val p = pointers.firstOrNull { it.active && it.id == e.id } ?: continue
                    p.x = x; p.y = y; p.up = true
                    if (e.action == TouchEvent.CANCEL) p.travel = 9999f
                }
            }
        }
    }

    fun begin(w: Int, h: Int) { batch.begin(w, h) }
    fun end() { batch.flush(); engine.profiler.drawCalls += batch.drawCalls }

    /** Hit-tests a rectangular widget. Returns a combination of HELD / CLICKED / PRESSED. */
    fun press(id: Int, x: Float, y: Float, w: Float, h: Float): Int {
        var f = 0
        for (p in pointers) {
            if (!p.active) continue
            val inside = p.x >= x && p.x <= x + w && p.y >= y && p.y <= y + h
            if (p.down && p.owner == 0 && inside) { p.owner = id; f = f or PRESSED }
            if (p.owner == id) {
                if (p.up) { if (inside) f = f or CLICKED } else f = f or HELD
            }
        }
        return f
    }

    /** Captures every still-free pointer that went down inside the rectangle (modal backgrounds). */
    fun block(x: Float, y: Float, w: Float, h: Float) {
        for (p in pointers) if (p.active && p.down && p.owner == 0 && p.x >= x && p.x <= x + w && p.y >= y && p.y <= y + h) p.owner = OWNER_BLOCKED
    }

    fun pointerOwnedBy(id: Int): Pointer? { for (p in pointers) if (p.active && p.owner == id) return p; return null }

    // ------------------------------------------------------------------ drawing (virtual units)

    fun rect(x: Float, y: Float, w: Float, h: Float, color: Int, radius: Float = 0f) =
        batch.rect(x * scale, y * scale, w * scale, h * scale, color, radius * scale)

    fun ring(cx: Float, cy: Float, r: Float, thickness: Float, color: Int) = batch.ring(cx * scale, cy * scale, r * scale, thickness * scale, color)
    fun circle(cx: Float, cy: Float, r: Float, color: Int) = batch.circle(cx * scale, cy * scale, r * scale, color)

    fun text(s: CharSequence, x: Float, y: Float, size: Float, color: Int = TEXT, align: Int = 0, shadow: Boolean = false) {
        if (shadow) font.draw(batch, s, (x + size * 0.06f) * scale, (y + size * 0.08f) * scale, size * scale, SHADOW, align)
        font.draw(batch, s, x * scale, y * scale, size * scale, color, align)
    }

    fun textWidth(s: CharSequence, size: Float): Float = font.width(s, size * scale) / scale

    /** Wrapped paragraph; returns its height in virtual units. */
    fun paragraph(s: CharSequence, x: Float, y: Float, maxW: Float, size: Float, color: Int = TEXT, draw: Boolean = true): Float =
        font.drawWrapped(if (draw) batch else null, s, x * scale, y * scale, maxW * scale, size * scale, color) / scale

    fun icon(id: Int, x: Float, y: Float, size: Float, color: Int = WHITE) {
        val cx = id % iconCols; val cy = id / iconCols
        val pad = 0.5f / 64f
        batch.icon(x * scale, y * scale, size * scale, size * scale,
            (cx + pad) / iconCols, (cy + pad) / iconRows, (cx + 1 - pad) / iconCols, (cy + 1 - pad) / iconRows, color)
    }
    fun icon(name: String, x: Float, y: Float, size: Float, color: Int = WHITE) = icon(iconId(name), x, y, size, color)

    fun aux(x: Float, y: Float, w: Float, h: Float, u0: Float, v0: Float, u1: Float, v1: Float, color: Int = WHITE) =
        batch.aux(x * scale, y * scale, w * scale, h * scale, u0, v0, u1, v1, color)

    // ------------------------------------------------------------------ widgets

    fun panel(x: Float, y: Float, w: Float, h: Float, color: Int = PANEL, radius: Float = 18f) {
        rect(x + 2f, y + 4f, w, h, 0x55000000, radius)
        rect(x, y, w, h, color, radius)
    }

    /** Text button. Returns true when tapped. */
    fun button(id: Int, x: Float, y: Float, w: Float, h: Float, label: CharSequence, enabled: Boolean = true, color: Int = ACCENT_DARK, size: Float = 26f, iconName: String? = null): Boolean {
        val f = if (enabled) press(id, x, y, w, h) else 0
        val held = f and HELD != 0
        val bg = if (!enabled) 0xAA3A3F3A.toInt() else if (held) ACCENT else color
        rect(x, y + (if (held) 2f else 0f), w, h, bg, minOf(h * 0.3f, 16f))
        var tx = x + w * 0.5f
        if (iconName != null) {
            val isz = h * 0.6f
            val tw = textWidth(label, size)
            val total = isz + 8f + tw
            icon(iconName, x + (w - total) * 0.5f, y + (h - isz) * 0.5f + (if (held) 2f else 0f), isz)
            tx = x + (w - total) * 0.5f + isz + 8f + tw * 0.5f
        }
        text(label, tx, y + (h - size) * 0.5f - size * 0.08f + (if (held) 2f else 0f), size, if (enabled) TEXT else TEXT_DIM, 1)
        return f and CLICKED != 0
    }

    /** Round icon button used by the HUD. Returns press flags. */
    fun roundButton(id: Int, cx: Float, cy: Float, r: Float, iconName: String, active: Boolean = false, alpha: Int = 0x66): Int {
        val f = press(id, cx - r, cy - r, r * 2f, r * 2f)
        val held = f and HELD != 0
        val bg = if (held || active) (0xAA shl 24) or 0x5F8F4A else (alpha shl 24) or 0x101510
        circle(cx, cy, r, bg)
        ring(cx, cy, r, 2.5f, if (held || active) 0xCCB8E08A.toInt() else 0x55FFFFFF)
        val s = r * 1.15f
        icon(iconName, cx - s * 0.5f, cy - s * 0.5f, s, if (held) WHITE else 0xE6FFFFFF.toInt())
        return f
    }

    /** Horizontal slider 0..1; returns the new value. */
    fun slider(id: Int, x: Float, y: Float, w: Float, value: Float): Float {
        var v = value
        val h = 44f
        press(id, x - 10f, y, w + 20f, h)
        val p = pointerOwnedBy(id)
        if (p != null) v = ((p.x - x) / w).coerceIn(0f, 1f)
        rect(x, y + h * 0.5f - 5f, w, 10f, SLOT, 5f)
        rect(x, y + h * 0.5f - 5f, w * v, 10f, ACCENT, 5f)
        circle(x + w * v, y + h * 0.5f, if (p != null) 17f else 14f, TEXT)
        return v
    }

    fun bar(x: Float, y: Float, w: Float, h: Float, value: Float, color: Int, back: Int = 0x99101510.toInt()) {
        rect(x, y, w, h, back, h * 0.5f)
        val v = value.coerceIn(0f, 1f)
        if (v > 0.01f) rect(x + 2f, y + 2f, maxOf(h - 4f, (w - 4f) * v), h - 4f, color, (h - 4f) * 0.5f)
    }

    fun dispose() {
        batch.dispose(); font.dispose(); icons.dispose()
    }
}
