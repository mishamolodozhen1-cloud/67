package wildcore.gfx

import wildcore.core.ImageData
import java.nio.ByteBuffer
import java.nio.ByteOrder

class Texture2D(private val gl: GL) {
    val id: Int = gl.genTexture()
    var width = 0; private set
    var height = 0; private set

    fun bind(unit: Int) {
        gl.activeTexture(GL.TEXTURE0 + unit)
        gl.bindTexture(GL.TEXTURE_2D, id)
    }

    fun upload(img: ImageData, srgb: Boolean, mipmaps: Boolean, repeat: Boolean) {
        uploadRaw(img.width, img.height, img.rgba, if (srgb) GL.SRGB8_ALPHA8 else GL.RGBA8, GL.RGBA, mipmaps, repeat, true)
    }

    fun uploadRaw(w: Int, h: Int, bytes: ByteArray, internalFormat: Int, format: Int, mipmaps: Boolean, repeat: Boolean, linear: Boolean) {
        width = w; height = h
        val bb = ByteBuffer.allocateDirect(bytes.size).order(ByteOrder.nativeOrder())
        bb.put(bytes).flip()
        gl.bindTexture(GL.TEXTURE_2D, id)
        gl.pixelStorei(GL.UNPACK_ALIGNMENT, 1)
        gl.texImage2D(GL.TEXTURE_2D, 0, internalFormat, w, h, format, GL.UNSIGNED_BYTE, bb)
        setParams(mipmaps, repeat, linear)
        if (mipmaps) gl.generateMipmap(GL.TEXTURE_2D)
    }

    /** Allocate storage without data (render targets). */
    fun allocate(w: Int, h: Int, internalFormat: Int, format: Int, type: Int, linear: Boolean) {
        width = w; height = h
        gl.bindTexture(GL.TEXTURE_2D, id)
        gl.texImage2D(GL.TEXTURE_2D, 0, internalFormat, w, h, format, type, null)
        setParams(false, false, linear)
    }

    private fun setParams(mipmaps: Boolean, repeat: Boolean, linear: Boolean) {
        val min = if (mipmaps) GL.LINEAR_MIPMAP_LINEAR else if (linear) GL.LINEAR else GL.NEAREST
        gl.texParameteri(GL.TEXTURE_2D, GL.TEXTURE_MIN_FILTER, min)
        gl.texParameteri(GL.TEXTURE_2D, GL.TEXTURE_MAG_FILTER, if (linear) GL.LINEAR else GL.NEAREST)
        val wrap = if (repeat) GL.REPEAT else GL.CLAMP_TO_EDGE
        gl.texParameteri(GL.TEXTURE_2D, GL.TEXTURE_WRAP_S, wrap)
        gl.texParameteri(GL.TEXTURE_2D, GL.TEXTURE_WRAP_T, wrap)
    }

    fun dispose() = gl.deleteTexture(id)
}

/**
 * 2D array texture: every block material lives in one layer, so all voxel geometry is drawn with a
 * single texture bind (the tiling-friendly evolution of a texture atlas).
 */
class TextureArray(private val gl: GL, val size: Int, val layers: Int, srgb: Boolean, anisotropy: Float) {
    val id: Int = gl.genTexture()
    val mipLevels: Int = 32 - Integer.numberOfLeadingZeros(size)
    private val scratch = ByteBuffer.allocateDirect(size * size * 4).order(ByteOrder.nativeOrder())

    init {
        gl.bindTexture(GL.TEXTURE_2D_ARRAY, id)
        gl.texStorage3D(GL.TEXTURE_2D_ARRAY, mipLevels, if (srgb) GL.SRGB8_ALPHA8 else GL.RGBA8, size, size, layers)
        gl.texParameteri(GL.TEXTURE_2D_ARRAY, GL.TEXTURE_MIN_FILTER, GL.LINEAR_MIPMAP_LINEAR)
        gl.texParameteri(GL.TEXTURE_2D_ARRAY, GL.TEXTURE_MAG_FILTER, GL.LINEAR)
        gl.texParameteri(GL.TEXTURE_2D_ARRAY, GL.TEXTURE_WRAP_S, GL.REPEAT)
        gl.texParameteri(GL.TEXTURE_2D_ARRAY, GL.TEXTURE_WRAP_T, GL.REPEAT)
        if (anisotropy > 1f) gl.texParameterf(GL.TEXTURE_2D_ARRAY, GL.TEXTURE_MAX_ANISOTROPY_EXT, minOf(anisotropy, 4f))
    }

    /** Upload one layer; the image is box-downsampled to the array size when larger. */
    fun setLayer(layer: Int, img: ImageData) {
        val data = if (img.width == size && img.height == size) img.rgba else resample(img, size)
        scratch.clear()
        scratch.put(data, 0, size * size * 4).flip()
        gl.bindTexture(GL.TEXTURE_2D_ARRAY, id)
        gl.pixelStorei(GL.UNPACK_ALIGNMENT, 1)
        gl.texSubImage3D(GL.TEXTURE_2D_ARRAY, 0, 0, 0, layer, size, size, 1, GL.RGBA, GL.UNSIGNED_BYTE, scratch)
    }

    fun finish() {
        gl.bindTexture(GL.TEXTURE_2D_ARRAY, id)
        gl.generateMipmap(GL.TEXTURE_2D_ARRAY)
    }

    fun bind(unit: Int) {
        gl.activeTexture(GL.TEXTURE0 + unit)
        gl.bindTexture(GL.TEXTURE_2D_ARRAY, id)
    }

    /** Approximate GPU memory in bytes (base level + mip chain). */
    val memoryBytes: Long get() = (size.toLong() * size * 4 * layers * 4) / 3

    fun dispose() = gl.deleteTexture(id)

    companion object {
        /** Box filter (integer ratio) or nearest (otherwise) resample to size×size. */
        fun resample(img: ImageData, size: Int): ByteArray {
            val out = ByteArray(size * size * 4)
            val src = img.rgba
            if (img.width == img.height && img.width % size == 0 && img.width > size) {
                val f = img.width / size
                val area = f * f
                for (y in 0 until size) for (x in 0 until size) {
                    var r = 0; var g = 0; var b = 0; var a = 0
                    for (sy in 0 until f) {
                        var i = ((y * f + sy) * img.width + x * f) * 4
                        for (sx in 0 until f) {
                            r += src[i].toInt() and 255; g += src[i + 1].toInt() and 255
                            b += src[i + 2].toInt() and 255; a += src[i + 3].toInt() and 255
                            i += 4
                        }
                    }
                    val o = (y * size + x) * 4
                    out[o] = (r / area).toByte(); out[o + 1] = (g / area).toByte()
                    out[o + 2] = (b / area).toByte(); out[o + 3] = (a / area).toByte()
                }
            } else {
                for (y in 0 until size) for (x in 0 until size) {
                    val sx = x * img.width / size; val sy = y * img.height / size
                    System.arraycopy(src, (sy * img.width + sx) * 4, out, (y * size + x) * 4, 4)
                }
            }
            return out
        }
    }
}
