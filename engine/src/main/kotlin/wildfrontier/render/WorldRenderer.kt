package wildfrontier.render

import wildcore.core.Engine
import wildcore.core.GraphicsProfile
import wildcore.core.Log
import wildcore.gfx.Camera
import wildcore.gfx.Framebuffer
import wildcore.gfx.GL
import wildcore.gfx.Mesh
import wildcore.gfx.QuadIndexBuffer
import wildcore.gfx.Shader
import wildcore.gfx.ShaderLibrary
import wildcore.gfx.VertexAttrib
import wildcore.gfx.VertexLayout
import wildcore.math.Frustum
import wildcore.math.Mat4
import wildcore.math.Vec3
import wildcore.world.Chunk
import wildcore.world.ChunkMesh
import wildcore.world.ChunkMeshData
import wildcore.world.ChunkMeshSink
import wildcore.world.VoxelWorld

/** Extra content drawn inside the 3D passes (entities, particles, far terrain…). */
interface SceneLayer {
    fun drawShadow(r: WorldRenderer) {}
    fun drawOpaque(r: WorldRenderer) {}
    fun drawTransparent(r: WorldRenderer) {}
}

/**
 * The forward rendering pipeline of the game:
 *   shadow map -> opaque voxels -> entities / far terrain -> cutout foliage -> sky ->
 *   (scene copy) -> water -> particles -> post-process upscale -> UI.
 * The 3D scene is rendered into an offscreen target at the tier's render scale; every tier-dependent
 * feature is compiled out of the shaders with #defines rather than branched at runtime.
 */
class WorldRenderer(private val engine: Engine) : ChunkMeshSink {
    val gl: GL get() = engine.gl
    lateinit var profile: GraphicsProfile; private set
    lateinit var textures: BlockTextures; private set
    lateinit var quads: QuadIndexBuffer; private set
    lateinit var shaders: ShaderLibrary; private set

    val camera = Camera()
    val env = Env()
    val layers = ArrayList<SceneLayer>()

    private lateinit var sChunk: Shader
    private lateinit var sCutout: Shader
    private lateinit var sWater: Shader
    private lateinit var sDepth: Shader
    private lateinit var sDepthCutout: Shader
    private lateinit var sSky: Shader
    private lateinit var sPost: Shader
    private lateinit var sOverlay: Shader
    private var sBloom: Shader? = null

    private var sceneFbo: Framebuffer? = null
    private var copyFbo: Framebuffer? = null
    private var shadowFbo: Framebuffer? = null
    private var bloomA: Framebuffer? = null
    private var bloomB: Framebuffer? = null
    private lateinit var cubeMesh: Mesh
    private var triVao = 0

    val shadowsEnabled: Boolean get() = profile.shadowMapSize > 0
    val shadowViewProj = FloatArray(16)
    private val shadowMatrix0 = FloatArray(16)      // bias * proj * view at the camera position of the last shadow render
    val shadowMatrix = FloatArray(16)               // same, re-based to the current camera position
    private val shadowCam = Vec3()
    private var shadowAge = 9999
    private val shadowFrustum = Frustum()
    private val tmpA = FloatArray(16)
    private val tmpB = FloatArray(16)
    private val tmpC = FloatArray(16)

    private var visible = arrayOfNulls<Chunk>(512)
    private var sortKeys = LongArray(512)
    private var visibleCount = 0
    private val envApplied = HashMap<Shader, Long>()
    private var frameId = 0L
    private var screenW = 1
    private var screenH = 1
    var meshBytes = 0L; private set

    // post-process inputs driven by gameplay
    var damageFlash = 0f
    var fade = 0f
    // block highlight / breaking overlay
    var highlightActive = false
    var highlightX = 0; var highlightY = 0; var highlightZ = 0
    var highlightHeight = 1f
    var breakProgress = 0f

    // ------------------------------------------------------------------ lifecycle

    fun init() {
        profile = engine.settings.profile
        quads = QuadIndexBuffer(gl)
        shaders = ShaderLibrary(gl, engine.platform)
        textures = BlockTextures(gl, engine.platform, engine.caps, profile.textureSize, profile.normalMapping)
        val defs = ArrayList<String>()
        if (profile.shadowMapSize > 0) { defs.add("SHADOWS"); defs.add("SHADOW_TAPS ${profile.shadowPcfTaps}") }
        if (profile.normalMapping) { defs.add("NORMAL_MAP"); defs.add("DETAIL") }
        if (profile.vegetationSway) defs.add("SWAY")
        defs.add("WATER_QUALITY ${profile.waterQuality}")
        defs.add("CLOUD_OCTAVES ${profile.cloudOctaves}")
        val a = arrayOf("aData")
        sChunk = shaders.load("chunk", "chunk.vert", "chunk.frag", a, defs)
        sCutout = shaders.load("cutout", "chunk.vert", "chunk.frag", a, defs + "ALPHA_TEST")
        sWater = shaders.load("water", "chunk.vert", "water.frag", a, defs + "WATER_PASS")
        sDepth = shaders.load("depth", "depth.vert", "depth.frag", a)
        sDepthCutout = shaders.load("depthCutout", "depth.vert", "depth.frag", a, listOf("ALPHA_TEST"))
        sSky = shaders.load("sky", "fullscreen.vert", "sky.frag", arrayOf(), defs)
        val postDefs = ArrayList<String>()
        if (profile.fxaa) postDefs.add("FXAA")
        if (profile.bloom) postDefs.add("BLOOM")
        sPost = shaders.load("post", "fullscreen.vert", "post.frag", arrayOf(), postDefs)
        sOverlay = shaders.load("overlay", "overlay.vert", "overlay.frag", arrayOf("aPos"))
        sBloom = if (profile.bloom) shaders.load("bloom", "fullscreen.vert", "bloom.frag", arrayOf()) else null
        triVao = gl.genVertexArray()
        buildCube()
        if (profile.shadowMapSize > 0) shadowFbo = Framebuffer(gl, profile.shadowMapSize, profile.shadowMapSize, color = false, depth = true, shadowCompare = true)
        shadowAge = 9999
        envApplied.clear()
        Log.i("Renderer", "initialized for ${profile.quality}")
    }

    /** Shader defines shared with other renderers (models, far terrain) so they match this tier. */
    fun litDefines(): List<String> {
        val d = ArrayList<String>()
        if (profile.shadowMapSize > 0) { d.add("SHADOWS"); d.add("SHADOW_TAPS ${profile.shadowPcfTaps}") }
        return d
    }

    private fun buildCube() {
        val v = floatArrayOf(
            1f, 0f, 0f, 1f, 1f, 0f, 1f, 1f, 1f, 1f, 0f, 1f,   // +X
            0f, 0f, 0f, 0f, 0f, 1f, 0f, 1f, 1f, 0f, 1f, 0f,   // -X
            0f, 1f, 0f, 0f, 1f, 1f, 1f, 1f, 1f, 1f, 1f, 0f,   // +Y
            0f, 0f, 0f, 1f, 0f, 0f, 1f, 0f, 1f, 0f, 0f, 1f,   // -Y
            0f, 0f, 1f, 1f, 0f, 1f, 1f, 1f, 1f, 0f, 1f, 1f,   // +Z
            0f, 0f, 0f, 0f, 1f, 0f, 1f, 1f, 0f, 1f, 0f, 0f)   // -Z
        val bb = Mesh.directBuffer(v.size * 4)
        bb.asFloatBuffer().put(v)
        cubeMesh = Mesh(gl, VertexLayout(12, arrayOf(VertexAttrib(0, 3, GL.FLOAT, false, 0))))
        cubeMesh.setVertices(bb, v.size * 4)
        cubeMesh.useSharedIndexBuffer(quads.buffer, GL.UNSIGNED_INT)
    }

    fun resize(w: Int, h: Int) {
        screenW = w; screenH = h
        sceneFbo?.dispose(); copyFbo?.dispose(); bloomA?.dispose(); bloomB?.dispose()
        val sw = maxOf(64, (w * profile.renderScale).toInt()) and 1.inv()
        val sh = maxOf(64, (h * profile.renderScale).toInt()) and 1.inv()
        sceneFbo = Framebuffer(gl, sw, sh, color = true, depth = true, linear = true)
        copyFbo = if (profile.waterQuality >= 1) Framebuffer(gl, sw, sh, color = true, depth = true, linear = false) else null
        if (profile.bloom) {
            bloomA = Framebuffer(gl, sw / 4, sh / 4, color = true, depth = false)
            bloomB = Framebuffer(gl, sw / 4, sh / 4, color = true, depth = false)
        } else { bloomA = null; bloomB = null }
        camera.aspect = w.toFloat() / h.toFloat()
        engine.profiler.gpuMemEstimateMb = gpuMemoryEstimateMb()
    }

    fun gpuMemoryEstimateMb(): Float {
        var bytes = textures.memoryBytes + meshBytes
        sceneFbo?.let { bytes += it.memoryBytes }; copyFbo?.let { bytes += it.memoryBytes }
        shadowFbo?.let { bytes += it.memoryBytes }; bloomA?.let { bytes += it.memoryBytes * 2 }
        bytes += quads.quadCapacity * 24L
        return bytes / (1024f * 1024f)
    }

    fun dispose() {
        sceneFbo?.dispose(); copyFbo?.dispose(); shadowFbo?.dispose(); bloomA?.dispose(); bloomB?.dispose()
        sceneFbo = null; copyFbo = null; shadowFbo = null; bloomA = null; bloomB = null
        textures.dispose(); shaders.disposeAll(); quads.dispose(); cubeMesh.dispose()
        gl.deleteVertexArray(triVao)
        meshBytes = 0
    }

    // ------------------------------------------------------------------ chunk mesh sink

    override fun onChunkMeshed(chunk: Chunk, data: ChunkMeshData) {
        var m = chunk.mesh
        if (m == null) { m = ChunkMesh(gl, quads); chunk.mesh = m } else meshBytes -= m.bytes
        m.upload(data)
        meshBytes += m.bytes
        shadowAge = 9999
    }

    override fun onChunkUnloaded(chunk: Chunk) {
        chunk.mesh?.let { meshBytes -= it.bytes; it.dispose() }
        chunk.mesh = null
    }

    // ------------------------------------------------------------------ uniforms

    /** Applies camera + environment uniforms once per frame per shader. */
    fun bindLit(s: Shader, viewProj: FloatArray = camera.viewProjRot) {
        s.use()
        if (envApplied[s] == frameId) { return }
        envApplied[s] = frameId
        s.setMat4("uViewProj", viewProj)
        s.set3f("uSunDir", env.keyDir.x, env.keyDir.y, env.keyDir.z)
        s.set3f("uSunColor", env.keyColor.x, env.keyColor.y, env.keyColor.z)
        s.set3f("uSunTrueDir", env.sunDir.x, env.sunDir.y, env.sunDir.z)
        s.set3f("uSkyZenith", env.skyZenith.x, env.skyZenith.y, env.skyZenith.z)
        s.set3f("uSkyHorizon", env.skyHorizon.x, env.skyHorizon.y, env.skyHorizon.z)
        s.set3f("uSunGlow", env.sunGlow.x, env.sunGlow.y, env.sunGlow.z)
        s.set3f("uAmbientSky", env.ambientSky.x, env.ambientSky.y, env.ambientSky.z)
        s.set3f("uAmbientGround", env.ambientGround.x, env.ambientGround.y, env.ambientGround.z)
        s.set4f("uFog", env.fogDensity, if (env.underwater) 1f else 0f, env.wetness, env.lightning)
        s.set3f("uFogTint", env.fogTint.x, env.fogTint.y, env.fogTint.z)
        s.set1f("uExposure", env.exposure)
        s.set1f("uTime", env.time)
        s.set4f("uWind", env.windX, env.windZ, env.windStrength, env.gust)
        if (shadowsEnabled) {
            s.setMat4("uShadowMatrix", shadowMatrix)
            s.set4f("uShadowParams", 1f / profile.shadowMapSize, profile.shadowDistance * 0.78f, profile.shadowDistance * 0.2f, 0f)
            s.set1i("uShadowMap", 2)
        }
    }

    // ------------------------------------------------------------------ frame

    fun render(world: VoxelWorld, drawUi: () -> Unit) {
        frameId++
        val prof = engine.profiler
        val scene = sceneFbo ?: return
        camera.update()
        collectVisible(world)

        if (shadowsEnabled) updateShadows(world)

        scene.bind()
        gl.clearColor(0f, 0f, 0f, 1f)
        gl.depthMask(true)
        gl.clear(GL.COLOR_BUFFER_BIT or GL.DEPTH_BUFFER_BIT)
        gl.enable(GL.DEPTH_TEST); gl.depthFunc(GL.LESS)
        gl.enable(GL.CULL_FACE); gl.cullFace(GL.BACK)
        gl.disable(GL.BLEND)

        textures.albedo.bind(0)
        textures.normal?.bind(1)
        shadowFbo?.depthTex?.bind(2)
        textures.noise.bind(3)

        // --- opaque voxels, front to back
        bindLit(sChunk)
        sChunk.set1i("uAlbedo", 0)
        if (profile.normalMapping) { sChunk.set1i("uNormalMap", 1); sChunk.set1i("uNoise", 3) }
        drawChunks(sChunk, 0, false)

        for (l in layers) l.drawOpaque(this)

        // --- cutout foliage (double sided)
        gl.disable(GL.CULL_FACE)
        bindLit(sCutout)
        sCutout.set1i("uAlbedo", 0)
        if (profile.normalMapping) { sCutout.set1i("uNormalMap", 1); sCutout.set1i("uNoise", 3) }
        drawChunks(sCutout, 1, false)
        gl.enable(GL.CULL_FACE)

        drawHighlight()

        // --- sky behind everything
        gl.depthFunc(GL.LEQUAL); gl.depthMask(false)
        bindLit(sSky)
        sSky.setMat4("uInvViewProj", camera.invViewProjRot)
        sSky.set1i("uNoise", 3)
        sSky.set3f("uMoonDir", env.moonDir.x, env.moonDir.y, env.moonDir.z)
        sSky.set4f("uCloud", env.cloudCover, env.time * 0.0035f * env.windStrength, env.cloudDark, env.stars)
        sSky.set2f("uCloudOffset", ((camera.pos.x * 0.00012f) % 1f), ((camera.pos.z * 0.00012f) % 1f))
        gl.bindVertexArray(triVao)
        gl.drawArrays(GL.TRIANGLES, 0, 3)
        prof.drawCalls++
        gl.depthFunc(GL.LESS); gl.depthMask(true)

        // --- water
        drawWater(scene)

        // --- particles and other blended content
        gl.enable(GL.BLEND)
        gl.blendFunc(GL.ONE, GL.ONE_MINUS_SRC_ALPHA)
        gl.depthMask(false)
        for (l in layers) l.drawTransparent(this)
        gl.depthMask(true)
        gl.disable(GL.BLEND)

        // --- post process to the screen
        gl.disable(GL.DEPTH_TEST)
        gl.disable(GL.CULL_FACE)
        if (profile.bloom) renderBloom(scene)
        gl.bindFramebuffer(GL.FRAMEBUFFER, 0)
        gl.viewport(0, 0, screenW, screenH)
        sPost.use()
        scene.colorTex!!.bind(0)
        sPost.set1i("uScene", 0)
        sPost.set2f("uInvSize", 1f / scene.width, 1f / scene.height)
        sPost.set4f("uFx", 0.55f, if (env.underwater) 1f else 0f, damageFlash, fade)
        sPost.set1f("uTime", env.time)
        if (profile.bloom) { bloomA!!.colorTex!!.bind(1); sPost.set1i("uBloom", 1) }
        gl.bindVertexArray(triVao)
        gl.drawArrays(GL.TRIANGLES, 0, 3)
        prof.drawCalls++

        // --- UI on top at native resolution
        gl.enable(GL.BLEND)
        gl.blendFuncSeparate(GL.SRC_ALPHA, GL.ONE_MINUS_SRC_ALPHA, GL.ONE, GL.ONE_MINUS_SRC_ALPHA)
        drawUi()
        gl.disable(GL.BLEND)
    }

    private fun collectVisible(world: VoxelWorld) {
        val cam = camera.pos
        var n = 0
        var culled = 0
        val fr = camera.frustum
        world.chunks.forEach { c ->
            val m = c.mesh
            if (m != null && (m.opaqueQuads + m.cutoutQuads + m.spriteQuads + m.waterQuads) > 0) {
                val x0 = c.cx * 16 - cam.x; val z0 = c.cz * 16 - cam.z
                if (fr.intersectsAabb(x0, m.minY - cam.y, z0, x0 + 16f, m.maxY - cam.y, z0 + 16f)) {
                    if (n == visible.size) { visible = visible.copyOf(n * 2); sortKeys = sortKeys.copyOf(n * 2) }
                    val dx = x0 + 8f; val dz = z0 + 8f
                    val d = (dx * dx + dz * dz).toLong()
                    visible[n] = c
                    sortKeys[n] = (d shl 20) or n.toLong()
                    n++
                } else culled++
            }
        }
        java.util.Arrays.sort(sortKeys, 0, n)
        visibleCount = n
        engine.profiler.chunksDrawn = n
        engine.profiler.chunksCulled = culled
    }

    /** pass: 0 opaque, 1 cutout (+ sprites nearby), 2 water. */
    private fun drawChunks(s: Shader, pass: Int, backToFront: Boolean) {
        val cam = camera.pos
        val locOff = s.loc("uChunkOffset"); val locUv = s.loc("uChunkUv")
        val prof = engine.profiler
        val detail2 = profile.detailDistance * profile.detailDistance
        for (k in 0 until visibleCount) {
            val i = if (backToFront) visibleCount - 1 - k else k
            val key = sortKeys[i]
            val c = visible[(key and 0xFFFFF).toInt()]!!
            val m = c.mesh ?: continue
            val first: Int; val count: Int
            when (pass) {
                0 -> { first = 0; count = m.opaqueQuads }
                1 -> {
                    first = m.opaqueQuads
                    // LOD: small plants are skipped beyond the detail distance
                    count = if ((key ushr 20) <= detail2.toLong()) m.cutoutQuads + m.spriteQuads else m.cutoutQuads
                }
                else -> { first = m.opaqueQuads + m.cutoutQuads + m.spriteQuads; count = m.waterQuads }
            }
            if (count == 0) continue
            val ox = c.cx * 16; val oz = c.cz * 16
            gl.uniform3f(locOff, ox - cam.x, -cam.y, oz - cam.z)
            gl.uniform3f(locUv, (ox and 63).toFloat(), 0f, (oz and 63).toFloat())
            m.bind()
            m.drawRange(first, count)
            prof.drawCalls++
            prof.triangles += count * 2
        }
    }

    private fun drawWater(scene: Framebuffer) {
        var any = false
        for (k in 0 until visibleCount) {
            val c = visible[(sortKeys[k] and 0xFFFFF).toInt()]!!
            if ((c.mesh?.waterQuads ?: 0) > 0) { any = true; break }
        }
        if (!any) return
        val copy = copyFbo
        if (copy != null) {
            gl.bindFramebuffer(GL.READ_FRAMEBUFFER, scene.fbo)
            gl.bindFramebuffer(GL.DRAW_FRAMEBUFFER, copy.fbo)
            gl.blitFramebuffer(0, 0, scene.width, scene.height, 0, 0, scene.width, scene.height, GL.COLOR_BUFFER_BIT or GL.DEPTH_BUFFER_BIT, GL.NEAREST)
            scene.bind()
        }
        gl.disable(GL.CULL_FACE)
        bindLit(sWater)
        textures.waterNormal.bind(4)
        sWater.set1i("uWaterNormal", 4)
        if (copy != null) {
            copy.colorTex!!.bind(5); copy.depthTex!!.bind(6)
            sWater.set1i("uSceneColor", 5); sWater.set1i("uSceneDepth", 6)
            sWater.set2f("uInvScreen", 1f / scene.width, 1f / scene.height)
            sWater.set2f("uNearFar", camera.near, camera.far)
            drawChunks(sWater, 2, true)
        } else {
            gl.enable(GL.BLEND)
            gl.blendFuncSeparate(GL.SRC_ALPHA, GL.ONE_MINUS_SRC_ALPHA, GL.ONE, GL.ONE_MINUS_SRC_ALPHA)
            gl.depthMask(false)
            drawChunks(sWater, 2, true)
            gl.depthMask(true)
            gl.disable(GL.BLEND)
        }
        gl.enable(GL.CULL_FACE)
        gl.activeTexture(GL.TEXTURE0)
    }

    private fun drawHighlight() {
        if (!highlightActive) return
        gl.enable(GL.BLEND)
        gl.blendFuncSeparate(GL.SRC_ALPHA, GL.ONE_MINUS_SRC_ALPHA, GL.ONE, GL.ONE_MINUS_SRC_ALPHA)
        gl.enable(GL.POLYGON_OFFSET_FILL)
        gl.polygonOffset(-1f, -2f)
        gl.depthMask(false)
        sOverlay.use()
        sOverlay.setMat4("uViewProj", camera.viewProjRot)
        sOverlay.set3f("uOffset", highlightX - camera.pos.x, highlightY - camera.pos.y, highlightZ - camera.pos.z)
        sOverlay.set3f("uScale", 1f, highlightHeight, 1f)
        sOverlay.set4f("uParams", breakProgress, 1f, 0f, 0f)
        sOverlay.set1i("uNoise", 3)
        cubeMesh.bind()
        gl.drawElements(GL.TRIANGLES, 36, GL.UNSIGNED_INT, 0)
        engine.profiler.drawCalls++
        gl.depthMask(true)
        gl.disable(GL.POLYGON_OFFSET_FILL)
        gl.disable(GL.BLEND)
    }

    // ------------------------------------------------------------------ shadows

    private fun updateShadows(world: VoxelWorld) {
        val fbo = shadowFbo ?: return
        shadowAge++
        val cam = camera.pos
        if (shadowAge >= profile.shadowUpdateInterval) {
            shadowAge = 0
            val r = profile.shadowDistance
            val L = env.keyDir
            // light view (camera-relative), looking along -L
            Mat4.lookDir(tmpA, L.x * 120f, L.y * 120f, L.z * 120f, -L.x, -L.y, -L.z, 0f, 1f, 0.001f)
            // snap the window to world-fixed texels so shadows do not shimmer when the camera moves
            val texel = (2f * r) / profile.shadowMapSize
            val lx = (cam.x * tmpA[0] + cam.y * tmpA[4] + cam.z * tmpA[8]).toDouble()
            val ly = (cam.x * tmpA[1] + cam.y * tmpA[5] + cam.z * tmpA[9]).toDouble()
            val fx = (lx - Math.floor(lx / texel) * texel).toFloat()
            val fy = (ly - Math.floor(ly / texel) * texel).toFloat()
            Mat4.ortho(tmpB, -r - fx, r - fx, -r - fy, r - fy, 1f, 300f)
            Mat4.mul(shadowViewProj, tmpB, tmpA)
            // bias matrix: clip (-1..1) -> texture (0..1)
            Mat4.identity(tmpC)
            tmpC[0] = 0.5f; tmpC[5] = 0.5f; tmpC[10] = 0.5f; tmpC[12] = 0.5f; tmpC[13] = 0.5f; tmpC[14] = 0.5f
            Mat4.mul(shadowMatrix0, tmpC, shadowViewProj)
            shadowCam.set(cam)
            shadowFrustum.setFromMatrix(shadowViewProj)

            fbo.bind()
            gl.depthMask(true)
            gl.enable(GL.DEPTH_TEST); gl.depthFunc(GL.LESS)
            gl.clear(GL.DEPTH_BUFFER_BIT)
            gl.enable(GL.CULL_FACE); gl.cullFace(GL.BACK)
            gl.enable(GL.POLYGON_OFFSET_FILL)
            gl.polygonOffset(2.2f, 5f)
            gl.colorMask(false, false, false, false)
            textures.albedo.bind(0)
            for (pass in 0..1) {
                val s = if (pass == 0) sDepth else sDepthCutout
                s.use()
                s.setMat4("uViewProj", shadowViewProj)
                if (pass == 1) { s.set1i("uAlbedo", 0); gl.disable(GL.CULL_FACE) }
                val locOff = s.loc("uChunkOffset")
                val locUv = if (pass == 1) s.loc("uChunkUv") else -1
                world.chunks.forEach { c ->
                    val m = c.mesh
                    if (m != null) {
                        val count = if (pass == 0) m.opaqueQuads else m.cutoutQuads
                        if (count > 0) {
                            val x0 = c.cx * 16 - cam.x; val z0 = c.cz * 16 - cam.z
                            if (shadowFrustum.intersectsAabb(x0, m.minY - cam.y, z0, x0 + 16f, m.maxY - cam.y, z0 + 16f)) {
                                gl.uniform3f(locOff, x0, -cam.y, z0)
                                if (locUv >= 0) gl.uniform3f(locUv, ((c.cx * 16) and 63).toFloat(), 0f, ((c.cz * 16) and 63).toFloat())
                                m.bind()
                                m.drawRange(if (pass == 0) 0 else m.opaqueQuads, count)
                                engine.profiler.drawCalls++
                            }
                        }
                    }
                }
            }
            gl.enable(GL.CULL_FACE)
            for (l in layers) l.drawShadow(this)
            gl.colorMask(true, true, true, true)
            gl.disable(GL.POLYGON_OFFSET_FILL)
        }
        // re-base the stored matrix to the current camera position
        Mat4.translation(tmpA, 0, cam.x - shadowCam.x, cam.y - shadowCam.y, cam.z - shadowCam.z)
        Mat4.mul(shadowMatrix, shadowMatrix0, tmpA)
    }

    /** Camera position at the time of the last shadow render (for layers drawing into the shadow map). */
    fun shadowCameraPos(): Vec3 = shadowCam

    // ------------------------------------------------------------------ bloom

    private fun renderBloom(scene: Framebuffer) {
        val s = sBloom ?: return
        val a = bloomA ?: return
        val b = bloomB ?: return
        s.use()
        s.set1i("uTex", 0)
        gl.bindVertexArray(triVao)
        a.bind()
        scene.colorTex!!.bind(0)
        s.set4f("uDir", 0f, 0f, 1f, 0f)
        gl.drawArrays(GL.TRIANGLES, 0, 3)
        b.bind()
        a.colorTex!!.bind(0)
        s.set4f("uDir", 1f / a.width, 0f, 0f, 0f)
        gl.drawArrays(GL.TRIANGLES, 0, 3)
        a.bind()
        b.colorTex!!.bind(0)
        s.set4f("uDir", 0f, 1f / a.height, 0f, 0f)
        gl.drawArrays(GL.TRIANGLES, 0, 3)
        engine.profiler.drawCalls += 3
    }
}
