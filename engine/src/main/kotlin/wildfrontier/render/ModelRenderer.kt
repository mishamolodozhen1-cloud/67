package wildfrontier.render

import wildcore.anim.SkinnedMesh
import wildcore.core.Engine
import wildcore.gfx.GL
import wildcore.gfx.Shader

/** One skinned model queued for drawing this frame. Instances are pooled and reused. */
class ModelInstance {
    var mesh: SkinnedMesh? = null
    val palette = FloatArray(16 * wildcore.anim.Skeleton.MAX_BONES)
    var boneCount = 0
    var sky = 1f
    var blockLight = 0f
    var hurt = 0f
    var castShadow = true
}

/** Draws every queued skinned model (animals, player) in the lit pass and the shadow pass. */
class ModelRenderer(private val engine: Engine) : SceneLayer {
    private lateinit var shader: Shader
    private lateinit var depthShader: Shader
    private val pool = ArrayList<ModelInstance>()
    private var used = 0

    fun init(r: WorldRenderer) {
        val attribs = arrayOf("aPos", "aNormal", "aColor", "aBones", "aWeights")
        shader = r.shaders.load("model", "model.vert", "model.frag", attribs, r.litDefines())
        depthShader = r.shaders.load("modelDepth", "modeldepth.vert", "depth.frag", attribs)
    }

    /** Clears the queue; call at the start of each frame's update. */
    fun beginFrame() { used = 0 }

    fun next(): ModelInstance {
        if (used == pool.size) pool.add(ModelInstance())
        return pool[used++]
    }

    val count: Int get() = used

    override fun drawOpaque(r: WorldRenderer) {
        if (used == 0) return
        val gl = engine.gl
        r.bindLit(shader)
        shader.set1i("uNoise", 3)
        val locBones = shader.loc("uBones"); val locLight = shader.loc("uEntityLight")
        for (i in 0 until used) {
            val m = pool[i]
            val mesh = m.mesh ?: continue
            gl.uniformMatrix4fv(locBones, m.boneCount, m.palette, 0)
            gl.uniform4f(locLight, m.sky, m.blockLight, m.hurt, 1f)
            mesh.draw()
            engine.profiler.drawCalls++
            engine.profiler.triangles += mesh.triangles
        }
    }

    override fun drawShadow(r: WorldRenderer) {
        if (used == 0) return
        val gl: GL = engine.gl
        depthShader.use()
        depthShader.setMat4("uViewProj", r.shadowViewProj)
        val locBones = depthShader.loc("uBones")
        for (i in 0 until used) {
            val m = pool[i]
            val mesh = m.mesh ?: continue
            if (!m.castShadow) continue
            gl.uniformMatrix4fv(locBones, m.boneCount, m.palette, 0)
            mesh.draw()
            engine.profiler.drawCalls++
        }
    }
}
