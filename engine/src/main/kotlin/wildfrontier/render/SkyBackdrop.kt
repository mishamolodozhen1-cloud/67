package wildfrontier.render

import wildcore.core.Engine
import wildcore.gfx.Camera
import wildcore.gfx.GL
import wildcore.gfx.Shader
import wildcore.gfx.ShaderLibrary
import wildcore.gfx.Texture2D

/** Stand-alone animated sky (used behind the main menu) built from the same sky shader as the game. */
class SkyBackdrop(private val engine: Engine) {
    private lateinit var shaders: ShaderLibrary
    private lateinit var shader: Shader
    private lateinit var noise: Texture2D
    private var vao = 0
    val camera = Camera()
    val env = Env()

    fun init() {
        val gl = engine.gl
        shaders = ShaderLibrary(gl, engine.platform)
        shader = shaders.load("menuSky", "fullscreen.vert", "sky.frag", arrayOf(), listOf("CLOUD_OCTAVES 3"))
        noise = Texture2D(gl)
        noise.upload(engine.platform.decodeImage(engine.platform.readAsset("textures/noise.png")), srgb = false, mipmaps = true, repeat = true)
        vao = gl.genVertexArray()
    }

    fun draw(time: Float) {
        val gl = engine.gl
        camera.aspect = engine.width.toFloat() / engine.height
        camera.update()
        gl.bindFramebuffer(GL.FRAMEBUFFER, 0)
        gl.viewport(0, 0, engine.width, engine.height)
        gl.disable(GL.DEPTH_TEST); gl.disable(GL.CULL_FACE); gl.disable(GL.BLEND)
        val s = shader
        s.use()
        s.setMat4("uInvViewProj", camera.invViewProjRot)
        s.set3f("uSunDir", env.keyDir.x, env.keyDir.y, env.keyDir.z)
        s.set3f("uSunColor", env.keyColor.x, env.keyColor.y, env.keyColor.z)
        s.set3f("uSunTrueDir", env.sunDir.x, env.sunDir.y, env.sunDir.z)
        s.set3f("uSkyZenith", env.skyZenith.x, env.skyZenith.y, env.skyZenith.z)
        s.set3f("uSkyHorizon", env.skyHorizon.x, env.skyHorizon.y, env.skyHorizon.z)
        s.set3f("uSunGlow", env.sunGlow.x, env.sunGlow.y, env.sunGlow.z)
        s.set3f("uAmbientSky", env.ambientSky.x, env.ambientSky.y, env.ambientSky.z)
        s.set3f("uAmbientGround", env.ambientGround.x, env.ambientGround.y, env.ambientGround.z)
        s.set4f("uFog", env.fogDensity, 0f, 0f, 0f)
        s.set3f("uFogTint", 1f, 1f, 1f)
        s.set1f("uExposure", env.exposure)
        s.set3f("uMoonDir", env.moonDir.x, env.moonDir.y, env.moonDir.z)
        s.set4f("uCloud", env.cloudCover, time * 0.004f, env.cloudDark, env.stars)
        s.set2f("uCloudOffset", 0f, 0f)
        noise.bind(3)
        s.set1i("uNoise", 3)
        gl.activeTexture(GL.TEXTURE0)
        gl.bindVertexArray(vao)
        gl.drawArrays(GL.TRIANGLES, 0, 3)
    }

    fun dispose() {
        shaders.disposeAll(); noise.dispose(); engine.gl.deleteVertexArray(vao)
    }
}
