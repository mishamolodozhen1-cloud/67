package wildfrontier

import wildcore.core.Engine
import wildcore.core.Scene
import wildcore.gfx.GL
import wildfrontier.env.DayNight
import wildfrontier.render.SkyBackdrop
import wildfrontier.ui.Ui
import wildfrontier.ui.drawSettings

/** Main menu: continue / new game / settings / exit over an animated evening sky. */
class MenuScene(private val game: WildFrontierGame) : Scene {
    private val sky = SkyBackdrop(game.engine)
    private val dayNight = DayNight()
    private var time = 0f
    private var mode = 0            // 0 main, 1 settings, 2 confirm new game
    private var seed = newSeed()
    private var summary: WildFrontierGame.SaveSummary? = null
    private var hasContext = false
    private val sb = StringBuilder()

    private fun newSeed(): Long = (System.nanoTime() xor (System.currentTimeMillis() shl 20)) and 0xFFFFFFFFL

    override fun onEnter(engine: Engine) {
        summary = game.saveSummary()
        dayNight.hour = 17.6f
        game.audio.stopAmbience()
    }

    override fun onContextCreated(engine: Engine) { sky.init(); hasContext = true }

    override fun onExit(engine: Engine) { if (hasContext && engine.hasContext) sky.dispose(); hasContext = false }

    override fun update(engine: Engine, dt: Float) {
        time += dt
        game.ui.beginInput(engine.input.drain(), dt)
        // a slow, endless golden hour
        dayNight.hour = 17.2f + 0.9f * kotlin.math.sin(time * 0.02f)
        dayNight.apply(sky.env, 0.1f, 0f, 600f)
        sky.env.cloudCover = 0.5f
        sky.camera.yaw = 1.2f + time * 0.008f
        sky.camera.pitch = 0.42f
        game.audio.updateAmbience(dt, 0.35f, 0.5f, 0.15f, 0f, 0f, 0f, false)
    }

    override fun render(engine: Engine) {
        val gl = engine.gl
        sky.draw(time)
        gl.enable(GL.BLEND)
        gl.blendFuncSeparate(GL.SRC_ALPHA, GL.ONE_MINUS_SRC_ALPHA, GL.ONE, GL.ONE_MINUS_SRC_ALPHA)
        val u = game.ui
        u.begin(engine.width, engine.height)
        if (u.backPressed) { if (mode != 0) mode = 0 else engine.platform.requestExit() }
        // darken the lower part so the buttons read well
        u.rect(0f, 0f, u.vw, u.vh, 0x33000000)
        when (mode) {
            0 -> main(u, engine)
            1 -> settings(u)
            else -> confirm(u)
        }
        u.end()
        gl.disable(GL.BLEND)
    }

    private fun main(u: Ui, engine: Engine) {
        val cx = u.vw * 0.5f
        u.text("WILD FRONTIER", cx, 96f, 96f, Ui.TEXT, 1, true)
        u.text("Архипелаг ждёт. Выживи, построй, раскрой его тайну.", cx, 206f, 26f, 0xFFE8E0C8.toInt(), 1, true)
        val bw = 420f; val bx = cx - bw * 0.5f
        var y = 290f
        val s = summary
        if (s != null) {
            sb.setLength(0); sb.append("Продолжить  ·  день ").append(s.day)
            if (u.button(1, bx, y, bw, 70f, sb, iconName = "ui_play", size = 28f)) { game.audio.play("click"); game.continueGame() }
            y += 84f
        }
        if (u.button(2, bx, y, bw, 70f, "Новая игра", iconName = "ui_star", size = 28f, color = if (s == null) Ui.ACCENT_DARK else 0xFF30404A.toInt())) {
            game.audio.play("click")
            if (s != null) mode = 2 else game.startNewGame(seed)
        }
        y += 84f
        if (u.button(3, bx, y, bw, 70f, "Настройки", iconName = "ui_settings", size = 28f, color = 0xFF30404A.toInt())) { game.audio.play("click"); mode = 1 }
        y += 84f
        if (u.button(4, bx, y, bw, 70f, "Выход", iconName = "ui_no", size = 28f, color = 0xFF4A3A30.toInt())) engine.platform.requestExit()
        sb.setLength(0); sb.append("Seed нового мира: ").append(seed)
        u.text(sb, u.safeL + 24f, u.vh - 40f, 18f, Ui.TEXT_DIM, 0, true)
        if (u.button(5, u.safeL + 24f + u.textWidth(sb, 18f) + 14f, u.vh - 52f, 150f, 38f, "Другой мир", size = 17f, color = 0xAA30404A.toInt())) seed = newSeed()
        u.text("WildCore Engine · v" + wildcore.WildCore.VERSION, u.vw - u.safeR - 24f, u.vh - 40f, 18f, Ui.TEXT_DIM, 2, true)
    }

    private fun settings(u: Ui) {
        val w = minOf(900f, u.vw - 60f); val x = (u.vw - w) * 0.5f
        u.panel(x - 24f, 40f, w + 48f, 640f)
        u.text("Настройки", x, 56f, 32f, Ui.TEXT)
        if (u.button(40, x + w - 150f, 50f, 150f, 48f, "Назад", size = 22f)) { game.engine.settings.save(); mode = 0 }
        drawSettings(game, u, x, 124f, w, 50) { }
    }

    private fun confirm(u: Ui) {
        val w = 640f; val x = (u.vw - w) * 0.5f
        u.panel(x, 220f, w, 280f)
        u.text("Начать новый мир?", x + w * 0.5f, 244f, 32f, Ui.TEXT, 1)
        u.paragraph("Текущее сохранение будет удалено без возможности восстановления.", x + 40f, 300f, w - 80f, 22f, Ui.TEXT_DIM)
        if (u.button(60, x + 40f, 400f, 260f, 64f, "Удалить и начать", color = 0xFF7A2E26.toInt(), size = 22f)) game.startNewGame(seed)
        if (u.button(61, x + w - 300f, 400f, 260f, 64f, "Отмена", size = 22f)) mode = 0
    }
}
