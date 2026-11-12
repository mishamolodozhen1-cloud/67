package wildfrontier.render

import wildcore.core.ImageData
import wildcore.core.Log
import wildcore.core.Platform
import wildcore.gfx.GL
import wildcore.gfx.GpuCaps
import wildcore.gfx.Texture2D
import wildcore.gfx.TextureArray
import wildfrontier.content.Tex

/** Loads every block material into texture arrays sized for the active graphics tier. */
class BlockTextures(private val gl: GL, private val platform: Platform, caps: GpuCaps, size: Int, withNormals: Boolean) {
    val albedo = TextureArray(gl, size, Tex.COUNT, srgb = true, anisotropy = caps.anisotropy)
    val normal: TextureArray? = if (withNormals) TextureArray(gl, minOf(size, 256), Tex.COUNT, srgb = false, anisotropy = 1f) else null
    val noise = Texture2D(gl)
    val waterNormal = Texture2D(gl)
    /** Average linear colour of each layer (used for particles and far terrain tinting). */
    val layerColor = FloatArray(Tex.COUNT * 3)

    init {
        val t0 = System.nanoTime()
        val flat = ByteArray(4 * 4 * 4).also { for (i in 0 until 16) { it[i * 4] = 128.toByte(); it[i * 4 + 1] = 128.toByte(); it[i * 4 + 2] = 225.toByte(); it[i * 4 + 3] = 255.toByte() } }
        val flatImg = ImageData(4, 4, flat)
        for (i in 0 until Tex.COUNT) {
            val name = Tex.NAMES[i]
            val img = decode("textures/blocks/$name.jpg") ?: decode("textures/blocks/$name.png")
            if (img == null) { Log.w("Textures", "missing block texture $name"); continue }
            albedo.setLayer(i, img)
            averageColor(img, i)
            if (normal != null) normal.setLayer(i, decode("textures/blocks/${name}_n.jpg") ?: flatImg)
        }
        albedo.finish()
        normal?.finish()
        noise.upload(platform.decodeImage(platform.readAsset("textures/noise.png")), srgb = false, mipmaps = true, repeat = true)
        waterNormal.upload(platform.decodeImage(platform.readAsset("textures/water_normal.png")), srgb = false, mipmaps = true, repeat = true)
        Log.i("Textures", "loaded ${Tex.COUNT} block layers at ${albedo.size}px in ${(System.nanoTime() - t0) / 1_000_000} ms")
    }

    private fun decode(path: String): ImageData? =
        if (platform.assetExists(path)) platform.decodeImage(platform.readAsset(path)) else null

    private fun averageColor(img: ImageData, layer: Int) {
        var r = 0.0; var g = 0.0; var b = 0.0; var n = 0
        val d = img.rgba
        var i = 0
        val step = 4 * 7
        while (i < d.size) {
            if ((d[i + 3].toInt() and 255) > 128) {
                r += d[i].toInt() and 255; g += d[i + 1].toInt() and 255; b += d[i + 2].toInt() and 255; n++
            }
            i += step
        }
        if (n == 0) n = 1
        // sRGB -> linear (gamma 2.2 approximation)
        layerColor[layer * 3] = Math.pow(r / n / 255.0, 2.2).toFloat()
        layerColor[layer * 3 + 1] = Math.pow(g / n / 255.0, 2.2).toFloat()
        layerColor[layer * 3 + 2] = Math.pow(b / n / 255.0, 2.2).toFloat()
    }

    val memoryBytes: Long get() = albedo.memoryBytes + (normal?.memoryBytes ?: 0L) + 2 * 256 * 256 * 4

    fun dispose() {
        albedo.dispose(); normal?.dispose(); noise.dispose(); waterNormal.dispose()
    }
}
