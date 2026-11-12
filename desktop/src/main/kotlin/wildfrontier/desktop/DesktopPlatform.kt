package wildfrontier.desktop

import wildcore.audio.AudioSink
import wildcore.core.DeviceInfo
import wildcore.core.ImageData
import wildcore.core.Platform
import java.io.ByteArrayInputStream
import java.io.File
import javax.imageio.ImageIO

class DesktopPlatform(private val assetsDir: File, override val filesDir: File, w: Int, h: Int) : Platform {
    override val deviceInfo = DeviceInfo("desktop-harness", Runtime.getRuntime().availableProcessors(), 8192, w, h, 35)
    override val audioSink: AudioSink? = null
    var thermal = 0

    init { filesDir.mkdirs() }

    override fun readAsset(path: String): ByteArray = File(assetsDir, path).readBytes()
    override fun assetExists(path: String): Boolean = File(assetsDir, path).isFile
    override fun decodeImage(bytes: ByteArray): ImageData {
        val img = ImageIO.read(ByteArrayInputStream(bytes))
        val w = img.width; val h = img.height
        val argb = img.getRGB(0, 0, w, h, null, 0, w)
        val out = ByteArray(w * h * 4)
        val hasAlpha = img.colorModel.hasAlpha()
        for (i in argb.indices) {
            val p = argb[i]
            out[i * 4] = (p shr 16).toByte(); out[i * 4 + 1] = (p shr 8).toByte(); out[i * 4 + 2] = p.toByte()
            out[i * 4 + 3] = if (hasAlpha) (p ushr 24).toByte() else 255.toByte()
        }
        return ImageData(w, h, out)
    }
    override fun thermalStatus(): Int = thermal
    override fun usedMemoryMb(): Int = ((Runtime.getRuntime().totalMemory() - Runtime.getRuntime().freeMemory()) / (1024 * 1024)).toInt()
    override fun log(level: Int, tag: String, msg: String) {
        val l = when (level) { 0 -> "I"; 1 -> "W"; else -> "E" }
        (if (level >= 2) System.err else System.out).println("$l/$tag: $msg")
    }
}
