package wildcore.gfx

import wildcore.core.Log
import wildcore.core.Platform

/** Linked GLSL program with a uniform-location cache. */
class Shader(private val gl: GL, val name: String, vertexSrc: String, fragmentSrc: String, attribs: Array<String>) {
    val program: Int
    private val locations = HashMap<String, Int>()

    init {
        val vs = compile(GL.VERTEX_SHADER, vertexSrc)
        val fs = compile(GL.FRAGMENT_SHADER, fragmentSrc)
        program = gl.createProgram()
        gl.attachShader(program, vs)
        gl.attachShader(program, fs)
        for (i in attribs.indices) gl.bindAttribLocation(program, i, attribs[i])
        gl.linkProgram(program)
        if (!gl.getProgramLinkStatus(program)) {
            val log = gl.getProgramInfoLog(program)
            throw IllegalStateException("Shader link failed [$name]: $log")
        }
        gl.deleteShader(vs)
        gl.deleteShader(fs)
    }

    private fun compile(type: Int, src: String): Int {
        val s = gl.createShader(type)
        gl.shaderSource(s, src)
        gl.compileShader(s)
        if (!gl.getShaderCompileStatus(s)) {
            val log = gl.getShaderInfoLog(s)
            val kind = if (type == GL.VERTEX_SHADER) "vertex" else "fragment"
            val numbered = src.lineSequence().mapIndexed { i, l -> "${i + 1}: $l" }.joinToString("\n")
            Log.e("Shader", "$kind shader [$name] failed:\n$log\n$numbered")
            throw IllegalStateException("Shader compile failed [$name/$kind]: $log")
        }
        return s
    }

    fun use() = gl.useProgram(program)

    fun loc(uniform: String): Int = locations.getOrPut(uniform) { gl.getUniformLocation(program, uniform) }

    fun set1i(name: String, v: Int) = gl.uniform1i(loc(name), v)
    fun set1f(name: String, v: Float) = gl.uniform1f(loc(name), v)
    fun set2f(name: String, x: Float, y: Float) = gl.uniform2f(loc(name), x, y)
    fun set3f(name: String, x: Float, y: Float, z: Float) = gl.uniform3f(loc(name), x, y, z)
    fun set4f(name: String, x: Float, y: Float, z: Float, w: Float) = gl.uniform4f(loc(name), x, y, z, w)
    fun setMat4(name: String, m: FloatArray) = gl.uniformMatrix4fv(loc(name), 1, m, 0)

    fun dispose() = gl.deleteProgram(program)
}

/**
 * Loads GLSL from assets/shaders, resolving `#include "file"` and injecting the version header and
 * quality-dependent `#define`s so one source serves all three graphics tiers.
 */
class ShaderLibrary(private val gl: GL, private val platform: Platform) {
    private val includeCache = HashMap<String, String>()
    private val shaders = ArrayList<Shader>()

    private fun source(path: String): String = includeCache.getOrPut(path) {
        val raw = String(platform.readAsset("shaders/$path"), Charsets.UTF_8)
        val sb = StringBuilder()
        for (line in raw.lineSequence()) {
            val t = line.trim()
            if (t.startsWith("#include")) {
                val file = t.substringAfter('"').substringBefore('"')
                sb.append(source(file)).append('\n')
            } else sb.append(line).append('\n')
        }
        sb.toString()
    }

    fun load(name: String, vertFile: String, fragFile: String, attribs: Array<String>, defines: List<String> = emptyList()): Shader {
        val header = StringBuilder("#version 300 es\n")
        for (d in defines) header.append("#define ").append(d).append('\n')
        val vs = header.toString() + "precision highp float;\nprecision highp int;\n" + source(vertFile)
        val fs = header.toString() + "precision mediump float;\nprecision highp int;\nprecision mediump sampler2DArray;\nprecision mediump sampler2DShadow;\n" + source(fragFile)
        val s = Shader(gl, name, vs, fs, attribs)
        shaders.add(s)
        return s
    }

    fun disposeAll() {
        for (s in shaders) s.dispose()
        shaders.clear()
    }
}
