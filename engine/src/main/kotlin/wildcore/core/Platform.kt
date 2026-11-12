package wildcore.core

import wildcore.audio.AudioSink
import java.io.File

/** Decoded RGBA8 image, rows top-to-bottom. */
class ImageData(@JvmField val width: Int, @JvmField val height: Int, @JvmField val rgba: ByteArray)

/** Static facts about the device, used by automatic quality detection. */
class DeviceInfo(
    val model: String,
    val cpuCores: Int,
    val totalRamMb: Int,
    val screenWidth: Int,
    val screenHeight: Int,
    val sdkLevel: Int,
)

/**
 * Everything the engine needs from the host OS. The Android app provides the real implementation;
 * the headless test harness provides a desktop one. The engine itself has no Android imports.
 */
interface Platform {
    val deviceInfo: DeviceInfo
    val filesDir: File
    val audioSink: AudioSink?
    fun readAsset(path: String): ByteArray
    fun assetExists(path: String): Boolean
    fun decodeImage(bytes: ByteArray): ImageData
    /** 0 = none … 4+ = severe. Mirrors Android PowerManager thermal status. */
    fun thermalStatus(): Int
    /** Used Java heap + native heap in MB (best effort). */
    fun usedMemoryMb(): Int
    fun log(level: Int, tag: String, msg: String)
    /** Ask host to close the app (main menu "exit"). */
    fun requestExit() {}
    /** Display cut-out / system bar insets in pixels: left, top, right, bottom. */
    fun safeInsets(): IntArray = intArrayOf(0, 0, 0, 0)
    /** Tell the host which frame rate we are targeting (0 = display default). */
    fun setTargetFrameRate(fps: Int) {}
}

object Log {
    @Volatile var platform: Platform? = null
    fun i(tag: String, msg: String) { platform?.log(0, tag, msg) ?: println("I/$tag: $msg") }
    fun w(tag: String, msg: String) { platform?.log(1, tag, msg) ?: println("W/$tag: $msg") }
    fun e(tag: String, msg: String, t: Throwable? = null) {
        val full = if (t != null) msg + "\n" + t.stackTraceToString() else msg
        platform?.log(2, tag, full) ?: System.err.println("E/$tag: $full")
    }
}
