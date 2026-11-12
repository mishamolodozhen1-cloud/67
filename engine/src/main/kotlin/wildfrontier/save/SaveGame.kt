package wildfrontier.save

import wildcore.core.Log
import wildcore.world.Chunk
import wildcore.world.ChunkStorage
import wildfrontier.content.Inventory
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.File
import java.io.FileOutputStream
import java.util.zip.CRC32

/**
 * On-disk persistence of one world: `level.dat` (everything except voxels) and one small file per
 * player-modified chunk. Every file is written atomically (temp file + fsync + rename, previous version
 * kept as .bak) and carries a CRC32, so a crash or power loss mid-write can never corrupt a save.
 */
class SaveGame(val dir: File) : ChunkStorage {
    companion object {
        const val MAGIC = 0x57465356   // "WFSV"
        const val VERSION = 1
        private const val CHUNK_MAGIC = 0x57464348 // "WFCH"

        /** Writes [body] to [file] with a validated header. Never leaves a half-written file in place. */
        fun atomicWrite(file: File, magic: Int, body: ByteArray) {
            file.parentFile?.mkdirs()
            val tmp = File(file.parentFile, file.name + "." + Thread.currentThread().id + ".tmp")
            val crc = CRC32(); crc.update(body)
            FileOutputStream(tmp).use { fos ->
                val o = DataOutputStream(fos)
                o.writeInt(magic); o.writeInt(VERSION); o.writeInt(body.size); o.writeLong(crc.value)
                o.write(body)
                o.flush()
                try { fos.fd.sync() } catch (e: Exception) { /* some filesystems do not support fsync */ }
            }
            if (file.exists()) {
                val bak = File(file.parentFile, file.name + ".bak")
                bak.delete()
                file.renameTo(bak)
            }
            if (!tmp.renameTo(file)) { tmp.copyTo(file, overwrite = true); tmp.delete() }
        }

        /** Returns the validated body, falling back to the .bak copy when the main file is damaged. */
        fun safeRead(file: File, magic: Int): ByteArray? {
            for (f in arrayOf(file, File(file.parentFile, file.name + ".bak"))) {
                if (!f.isFile) continue
                try {
                    DataInputStream(f.inputStream().buffered()).use { i ->
                        if (i.readInt() != magic) throw IllegalStateException("bad magic")
                        i.readInt() // version
                        val len = i.readInt()
                        val crcStored = i.readLong()
                        if (len < 0 || len > 64 * 1024 * 1024) throw IllegalStateException("bad length")
                        val body = ByteArray(len)
                        i.readFully(body)
                        val crc = CRC32(); crc.update(body)
                        if (crc.value != crcStored) throw IllegalStateException("checksum mismatch")
                        return body
                    }
                } catch (e: Exception) {
                    Log.w("Save", "${f.name} unreadable (${e.message}); trying backup")
                }
            }
            return null
        }
    }

    private val levelFile = File(dir, "level.dat")
    private val chunkDir = File(dir, "chunks")

    fun exists(): Boolean = levelFile.isFile || File(dir, "level.dat.bak").isFile

    fun writeLevel(body: ByteArray) = atomicWrite(levelFile, MAGIC, body)
    fun readLevel(): ByteArray? = safeRead(levelFile, MAGIC)

    fun deleteAll() { dir.deleteRecursively() }

    private fun chunkFile(cx: Int, cz: Int) = File(chunkDir, "c.$cx.$cz.bin")

    val savedChunkCount: Int get() = chunkDir.list()?.count { it.endsWith(".bin") } ?: 0

    override fun load(chunk: Chunk): Boolean {
        val f = chunkFile(chunk.cx, chunk.cz)
        if (!f.isFile && !File(chunkDir, f.name + ".bak").isFile) return false
        val body = safeRead(f, CHUNK_MAGIC) ?: return false
        val i = DataInputStream(ByteArrayInputStream(body))
        // run-length encoded blocks
        var pos = 0
        val b = chunk.blocks
        while (pos < Chunk.VOLUME) {
            val run = i.readUnsignedShort()
            val id = i.readByte()
            if (run == 0 || pos + run > Chunk.VOLUME) return false
            java.util.Arrays.fill(b, pos, pos + run, id)
            pos += run
        }
        val n = i.readInt()
        if (n > 0) {
            val map = HashMap<Int, Any>()
            for (k in 0 until n) {
                val idx = i.readInt()
                val type = i.readByte().toInt()
                if (type == 1) map[idx] = readInventory(i)
            }
            chunk.blockData = map
        }
        return true
    }

    override fun save(cx: Int, cz: Int, blocks: ByteArray, blockData: HashMap<Int, Any>?) {
        val bos = ByteArrayOutputStream(4096)
        val o = DataOutputStream(bos)
        var pos = 0
        while (pos < Chunk.VOLUME) {
            val id = blocks[pos]
            var run = 1
            while (pos + run < Chunk.VOLUME && run < 65535 && blocks[pos + run] == id) run++
            o.writeShort(run); o.writeByte(id.toInt())
            pos += run
        }
        val entries = blockData?.filter { it.value is Inventory }
        o.writeInt(entries?.size ?: 0)
        entries?.forEach { (idx, v) -> o.writeInt(idx); o.writeByte(1); writeInventory(o, v as Inventory) }
        o.flush()
        try { atomicWrite(chunkFile(cx, cz), CHUNK_MAGIC, bos.toByteArray()) }
        catch (e: Exception) { Log.e("Save", "failed to save chunk $cx,$cz", e) }
    }
}

fun writeInventory(o: DataOutputStream, inv: Inventory) {
    o.writeInt(inv.size)
    for (s in inv.slots) { o.writeShort(s.id); o.writeShort(s.count); o.writeShort(s.durability) }
}

fun readInventory(i: DataInputStream, into: Inventory? = null): Inventory {
    val n = i.readInt()
    val inv = into ?: Inventory(n)
    for (k in 0 until n) {
        val id = i.readShort().toInt(); val c = i.readShort().toInt(); val d = i.readShort().toInt()
        if (k < inv.size) { if (c > 0 && wildfrontier.content.Items.get(id) != null) inv.slots[k].set(id, c, d) else inv.slots[k].clear() }
    }
    inv.touch()
    return inv
}
