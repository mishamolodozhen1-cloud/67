package wildfrontier.render

import wildcore.math.Vec3

/** Per-frame lighting / atmosphere state produced by the day-night and weather systems. */
class Env {
    val sunDir = Vec3(0.4f, 0.8f, 0.3f)        // towards the sun disc
    val moonDir = Vec3(-0.4f, -0.8f, -0.3f)
    val keyDir = Vec3(0.4f, 0.8f, 0.3f)        // active key light direction (sun or moon)
    val keyColor = Vec3(3.2f, 3.0f, 2.7f)
    val skyZenith = Vec3(0.18f, 0.36f, 0.72f)
    val skyHorizon = Vec3(0.62f, 0.76f, 0.92f)
    val sunGlow = Vec3(1.0f, 0.8f, 0.55f)
    val ambientSky = Vec3(0.42f, 0.52f, 0.68f)
    val ambientGround = Vec3(0.16f, 0.15f, 0.12f)
    val fogTint = Vec3(1f, 1f, 1f)
    var fogDensity = 0.0022f
    var underwater = false
    var wetness = 0f
    var lightning = 0f
    var exposure = 1.0f
    var cloudCover = 0.45f
    var cloudDark = 0f
    var stars = 0f
    var time = 0f
    var windX = 0.8f
    var windZ = 0.6f
    var windStrength = 1f
    var gust = 1f
    /** 0 = night … 1 = full day; convenient scalar for gameplay systems. */
    var daylight = 1f
}
