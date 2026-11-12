package wildfrontier

import wildcore.core.Engine
import wildcore.core.Log
import wildcore.core.Platform
import wildfrontier.save.SaveGame
import wildfrontier.ui.Ui
import java.io.ByteArrayInputStream
import java.io.DataInputStream
import java.io.File

/** Application root: owns the engine, the shared UI toolkit and audio, and switches scenes. */
class WildFrontierGame(platform: Platform) {
    class SaveSummary(val seed: Long, val day: Int)

    val engine = Engine(platform)
    val ui = Ui(engine)
    val audio = GameAudio()
    var gameScene: GameScene? = null; private set

    init {
        engine.contextHook = { ui.init(null); ui.resize(engine.width, engine.height) }
        engine.resizeHook = { w, h -> ui.resize(w, h) }
        audio.sfxVolume = engine.settings.sfxVolume
        audio.musicVolume = engine.settings.musicVolume
        // sound synthesis takes a moment: do it off the render thread while the menu appears
        engine.jobs.submit(-1000f, Runnable {
            audio.build()
            platform.audioSink?.start(audio.mixer)
        })
        toMenu()
    }

    private fun saveDir() = File(engine.platform.filesDir, "saves/world")

    /** Reads just enough of the save to describe it on the Continue button. */
    fun saveSummary(): SaveSummary? {
        return try {
            val body = SaveGame(saveDir()).readLevel() ?: return null
            val i = DataInputStream(ByteArrayInputStream(body))
            if (i.readInt() != 1) return null
            SaveSummary(i.readLong(), i.readInt())
        } catch (e: Exception) { Log.w("Game", "save summary unreadable: $e"); null }
    }

    fun startNewGame(seed: Long) {
        val s = GameScene(this, seed, false)
        gameScene = s
        engine.scenes.switchTo(s)
    }

    fun continueGame(): Boolean {
        val sum = saveSummary() ?: return false
        val s = GameScene(this, sum.seed, true)
        gameScene = s
        engine.scenes.switchTo(s)
        return true
    }

    fun toMenu() {
        gameScene = null
        engine.scenes.switchTo(MenuScene(this))
    }

    /** Tells the host which frame rate to pace for (battery / thermal aware). */
    fun applyFrameRate(throttle: Boolean = false) {
        val s = engine.settings
        var fps = if (s.fpsLimit > 0) minOf(s.fpsLimit, s.profile.targetFps) else s.profile.targetFps
        if (throttle) fps = minOf(fps, 30)
        engine.platform.setTargetFrameRate(fps)
    }
}
