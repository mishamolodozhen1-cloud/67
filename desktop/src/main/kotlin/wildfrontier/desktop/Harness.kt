package wildfrontier.desktop

import org.lwjgl.BufferUtils
import org.lwjgl.egl.EGL10.*
import org.lwjgl.opengles.GLES
import org.lwjgl.opengles.GLES20
import org.lwjgl.system.Configuration
import org.lwjgl.system.MemoryStack
import wildcore.core.Quality
import wildfrontier.WildFrontierGame
import java.awt.image.BufferedImage
import java.io.File
import javax.imageio.ImageIO

/**
 * Headless test harness: runs the real engine + game against a software GLES 3 context, drives it
 * with scripted steps and writes screenshots. Development/verification tool — not part of the APK.
 */
class Harness(val width: Int, val height: Int, val outDir: File, quality: Quality?) {
    val platform = DesktopPlatform(File("app/src/main/assets"), File(outDir, "files"), width, height)
    val gl = DesktopGL()
    val game: WildFrontierGame

    init {
        outDir.mkdirs()
        createContext()
        game = WildFrontierGame(platform)
        if (quality != null) {
            game.engine.settings.quality = quality
            game.engine.settings.qualityChosenByUser = true
            game.engine.settings.effectiveQuality = quality
        }
        game.engine.onContextCreated(gl)
        game.engine.onResize(width, height)
    }

    private fun createContext() {
        Configuration.EGL_LIBRARY_NAME.set("libEGL.so.1")
        Configuration.OPENGLES_LIBRARY_NAME.set("libGLESv2.so.2")
        MemoryStack.stackPush().use { stack ->
            val display = eglGetDisplay(0L)
            check(display != 0L) { "no EGL display" }
            check(eglInitialize(display, stack.mallocInt(1), stack.mallocInt(1))) { "eglInitialize failed" }
            val cfgAttribs = stack.ints(EGL_SURFACE_TYPE, EGL_PBUFFER_BIT, 0x3040, 0x40,
                EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE, 8, EGL_ALPHA_SIZE, 8, EGL_DEPTH_SIZE, 24, EGL_NONE)
            val configs = stack.mallocPointer(1); val num = stack.mallocInt(1)
            check(eglChooseConfig(display, cfgAttribs, configs, num) && num[0] > 0) { "no EGL config" }
            val surface = eglCreatePbufferSurface(display, configs[0], stack.ints(EGL_WIDTH, width, EGL_HEIGHT, height, EGL_NONE))
            org.lwjgl.egl.EGL12.eglBindAPI(org.lwjgl.egl.EGL12.EGL_OPENGL_ES_API)
            val ctx = eglCreateContext(display, configs[0], EGL_NO_CONTEXT, stack.ints(0x3098, 3, EGL_NONE))
            check(ctx != 0L) { "no GLES3 context" }
            check(eglMakeCurrent(display, surface, surface, ctx))
            GLES.createCapabilities()
        }
    }

    fun frames(n: Int, dt: Float = 1f / 30f) { for (i in 0 until n) game.engine.frame(dt) }

    /** Runs frames until [cond] holds (or the limit is hit). Returns frames used. */
    fun until(limit: Int, dt: Float = 1f / 30f, cond: () -> Boolean): Int {
        var n = 0
        while (n < limit && !cond()) { game.engine.frame(dt); n++; if (n % 4 == 0) Thread.sleep(2) }
        return n
    }

    fun screenshot(name: String) {
        val buf = BufferUtils.createByteBuffer(width * height * 4)
        GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, 0)
        GLES20.glReadPixels(0, 0, width, height, GLES20.GL_RGBA, GLES20.GL_UNSIGNED_BYTE, buf)
        val img = BufferedImage(width, height, BufferedImage.TYPE_INT_RGB)
        for (y in 0 until height) for (x in 0 until width) {
            val i = ((height - 1 - y) * width + x) * 4
            img.setRGB(x, y, ((buf.get(i).toInt() and 255) shl 16) or ((buf.get(i + 1).toInt() and 255) shl 8) or (buf.get(i + 2).toInt() and 255))
        }
        val f = File(outDir, "$name.png")
        ImageIO.write(img, "png", f)
        println("screenshot: ${f.path}")
        val err = GLES20.glGetError()
        if (err != 0) println("GL ERROR after $name: 0x${Integer.toHexString(err)}")
    }
}

fun main(args: Array<String>) {
    val opts = HashMap<String, String>()
    var i = 0
    while (i < args.size) { if (args[i].startsWith("--") && i + 1 < args.size) { opts[args[i].substring(2)] = args[i + 1]; i += 2 } else i++ }
    val w = opts["w"]?.toInt() ?: 1280
    val h = opts["h"]?.toInt() ?: 720
    val out = File(opts["out"] ?: "build/harness")
    val quality = opts["quality"]?.let { Quality.valueOf(it) }
    val harness = Harness(w, h, out, quality)
    Scenarios.run(opts["scenario"] ?: "terrain", harness, opts)
    harness.game.engine.shutdown()
    System.exit(0)
}
