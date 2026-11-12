package wildcore.core

import wildcore.gfx.GpuCaps
import java.io.File
import java.util.Properties

enum class Quality { LOW, MEDIUM, HIGH }

/** Everything a quality tier controls. Tuned for mobile GPUs: fill-rate and draw calls first. */
class GraphicsProfile(
    val quality: Quality,
    val viewDistance: Int,          // chunk radius of fully simulated voxel terrain
    val farTerrainRings: Int,       // extra rings of low-detail far terrain tiles (0 = off)
    val renderScale: Float,         // internal 3D resolution relative to the screen
    val shadowMapSize: Int,         // 0 = shadows disabled
    val shadowDistance: Float,
    val shadowUpdateInterval: Int,  // re-render the shadow map every N frames
    val shadowPcfTaps: Int,
    val normalMapping: Boolean,
    val textureSize: Int,           // block texture resolution per layer
    val waterQuality: Int,          // 0 simple, 1 refraction+foam, 2 + screen-space reflections
    val maxParticles: Int,
    val detailDistance: Float,      // distance (blocks) at which small plants stop rendering
    val fxaa: Boolean,
    val bloom: Boolean,
    val cloudOctaves: Int,
    val leafInnerFaces: Boolean,
    val vegetationSway: Boolean,
    val maxAnimals: Int,
    val targetFps: Int,
) {
    companion object {
        fun of(q: Quality): GraphicsProfile = when (q) {
            Quality.LOW -> GraphicsProfile(q, viewDistance = 5, farTerrainRings = 3, renderScale = 0.6f,
                shadowMapSize = 0, shadowDistance = 0f, shadowUpdateInterval = 0, shadowPcfTaps = 0,
                normalMapping = false, textureSize = 128, waterQuality = 0, maxParticles = 300,
                detailDistance = 28f, fxaa = false, bloom = false, cloudOctaves = 2, leafInnerFaces = false,
                vegetationSway = false, maxAnimals = 10, targetFps = 30)
            Quality.MEDIUM -> GraphicsProfile(q, viewDistance = 7, farTerrainRings = 5, renderScale = 0.75f,
                shadowMapSize = 1024, shadowDistance = 40f, shadowUpdateInterval = 3, shadowPcfTaps = 1,
                normalMapping = true, textureSize = 256, waterQuality = 1, maxParticles = 900,
                detailDistance = 48f, fxaa = false, bloom = false, cloudOctaves = 3, leafInnerFaces = true,
                vegetationSway = true, maxAnimals = 18, targetFps = 60)
            Quality.HIGH -> GraphicsProfile(q, viewDistance = 10, farTerrainRings = 7, renderScale = 1.0f,
                shadowMapSize = 2048, shadowDistance = 64f, shadowUpdateInterval = 1, shadowPcfTaps = 4,
                normalMapping = true, textureSize = 512, waterQuality = 2, maxParticles = 2000,
                detailDistance = 72f, fxaa = true, bloom = true, cloudOctaves = 4, leafInnerFaces = true,
                vegetationSway = true, maxAnimals = 28, targetFps = 60)
        }
    }
}

/** User-facing settings persisted between runs. */
class Settings(private val platform: Platform) {
    var quality = Quality.MEDIUM
    var qualityChosenByUser = false
    var lookSensitivity = 1.0f
    var invertY = false
    var musicVolume = 0.6f
    var sfxVolume = 0.9f
    var showProfiler = false
    var fpsLimit = 0                 // 0 = profile default
    var autoJump = true
    var language = "ru"
    var thermalThrottle = true

    /** Thermal/perf governor may lower effective quality at runtime without touching the saved choice. */
    var effectiveQuality = Quality.MEDIUM
    val profile: GraphicsProfile get() = GraphicsProfile.of(effectiveQuality)

    private val file: File get() = File(platform.filesDir, "settings.properties")

    fun load() {
        try {
            if (file.exists()) {
                val p = Properties()
                file.inputStream().use { p.load(it) }
                quality = runCatching { Quality.valueOf(p.getProperty("quality", "MEDIUM")) }.getOrDefault(Quality.MEDIUM)
                qualityChosenByUser = p.getProperty("qualityChosen", "false").toBoolean()
                lookSensitivity = p.getProperty("sensitivity", "1.0").toFloatOrNull() ?: 1f
                invertY = p.getProperty("invertY", "false").toBoolean()
                musicVolume = p.getProperty("music", "0.6").toFloatOrNull() ?: 0.6f
                sfxVolume = p.getProperty("sfx", "0.9").toFloatOrNull() ?: 0.9f
                showProfiler = p.getProperty("profiler", "false").toBoolean()
                fpsLimit = p.getProperty("fpsLimit", "0").toIntOrNull() ?: 0
                autoJump = p.getProperty("autoJump", "true").toBoolean()
                language = p.getProperty("language", "ru")
                thermalThrottle = p.getProperty("thermalThrottle", "true").toBoolean()
            }
        } catch (e: Exception) {
            Log.w("Settings", "failed to load settings: $e")
        }
        effectiveQuality = quality
    }

    fun save() {
        try {
            val p = Properties()
            p.setProperty("quality", quality.name)
            p.setProperty("qualityChosen", qualityChosenByUser.toString())
            p.setProperty("sensitivity", lookSensitivity.toString())
            p.setProperty("invertY", invertY.toString())
            p.setProperty("music", musicVolume.toString())
            p.setProperty("sfx", sfxVolume.toString())
            p.setProperty("profiler", showProfiler.toString())
            p.setProperty("fpsLimit", fpsLimit.toString())
            p.setProperty("autoJump", autoJump.toString())
            p.setProperty("language", language)
            p.setProperty("thermalThrottle", thermalThrottle.toString())
            val tmp = File(platform.filesDir, "settings.properties.tmp")
            tmp.outputStream().use { p.store(it, "WILD FRONTIER settings") }
            if (!tmp.renameTo(file)) { file.delete(); tmp.renameTo(file) }
        } catch (e: Exception) {
            Log.w("Settings", "failed to save settings: $e")
        }
    }

    /** First-run heuristic: pick a tier from RAM, CPU cores and the GPU family. */
    fun autoDetectIfNeeded(info: DeviceInfo, caps: GpuCaps) {
        if (qualityChosenByUser) { effectiveQuality = quality; return }
        quality = detect(info, caps.renderer)
        effectiveQuality = quality
        Log.i("Settings", "auto-detected quality: $quality (ram=${info.totalRamMb}MB cores=${info.cpuCores} gpu=${caps.renderer})")
    }

    companion object {
        fun detect(info: DeviceInfo, renderer: String): Quality {
            var score = 0
            score += when {
                info.totalRamMb >= 7000 -> 2
                info.totalRamMb >= 3500 -> 1
                else -> 0
            }
            score += if (info.cpuCores >= 8) 1 else 0
            val r = renderer.lowercase()
            val num = Regex("(\\d{3,4})").find(r)?.value?.toIntOrNull() ?: 0
            score += when {
                r.contains("adreno") -> when { num >= 640 -> 3; num >= 610 -> 2; num >= 530 -> 1; else -> 0 }
                r.contains("mali-g") -> {
                    val g = Regex("mali-g(\\d+)").find(r)?.groupValues?.get(1)?.toIntOrNull() ?: 0
                    when { g >= 710 || g in 77..99 -> 3; g in 71..76 || g >= 610 -> 2; g >= 52 -> 1; else -> 0 }
                }
                r.contains("immortalis") || r.contains("xclipse") -> 3
                r.contains("apple") -> 3
                r.contains("powervr") -> 0
                r.contains("llvmpipe") || r.contains("swiftshader") -> 0
                else -> 1
            }
            return when {
                score >= 5 -> Quality.HIGH
                score >= 2 -> Quality.MEDIUM
                else -> Quality.LOW
            }
        }
    }
}
