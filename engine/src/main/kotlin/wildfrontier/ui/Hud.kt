package wildfrontier.ui

import wildcore.math.clamp
import wildcore.world.Blocks
import wildfrontier.GameScene
import wildfrontier.animals.AState
import wildfrontier.content.Items
import wildfrontier.env.Weather
import wildfrontier.gen.Biome
import wildfrontier.player.Player
import wildfrontier.story.StoryData
import kotlin.math.sqrt

/**
 * In-game interface: touch controls (virtual joystick, look pad, action buttons, hotbar), status
 * display, notifications and the modal screens. Runs once per frame inside the UI render pass.
 */
class Hud(val scene: GameScene) {
    companion object {
        const val NONE = 0; const val INVENTORY = 1; const val CRAFTING = 2; const val MAP = 3; const val JOURNAL = 4
        const val ENCYCLOPEDIA = 5; const val PAUSE = 6; const val SETTINGS = 7; const val CHEST = 8; const val NOTE = 9
        const val DEATH = 10; const val BUILD = 11
        private const val ID_BREAK = 101; private const val ID_PLACE = 102; private const val ID_JUMP = 103; private const val ID_INTERACT = 104
        private const val ID_CROUCH = 105; private const val ID_SPRINT = 106; private const val ID_CAMERA = 107
        private const val ID_TOP = 120; private const val ID_HOTBAR = 140
    }

    val ui: Ui get() = scene.ui
    val screens = Screens(this)
    var screen = NONE; private set
    val modalOpen: Boolean get() = screen != NONE

    // control outputs consumed by GameScene.update
    var breakHeld = false; private set
    var breakPressed = false
    var useClicked = false
    var interactClicked = false
    var lookDx = 0f; var lookDy = 0f
    private var joyX = 0f; private var joyY = 0f; private var joyActive = false
    private var placeRepeat = 0f
    private var sprintHold = 0f

    // notifications
    private class Pickup(var id: Int, var count: Int, var time: Float)
    private val pickups = ArrayList<Pickup>()
    private var toast = ""; private var toastTime = 0f
    private var bannerTitle = ""; private var bannerText = ""; private var bannerTime = 0f
    private val bannerQueue = ArrayList<Pair<String, String>>()
    private val sb = StringBuilder(64)
    var loadingProgress = 1f

    fun open(s: Int) {
        if (s != screen) { screen = s; screens.onOpen(s); scene.audio.play("click", 0.7f) }
    }
    fun close() { screen = NONE; screens.onClose() }

    fun openChest(x: Int, y: Int, z: Int) { screens.chestX = x; screens.chestY = y; screens.chestZ = z; open(CHEST); scene.audio.play("hit_wood", 0.5f, 1.2f) }
    fun openCrafting(station: Int) { screens.forcedStation = station; open(CRAFTING) }
    fun openNote(n: Int) { screens.noteTitle = StoryData.notes[n].title; screens.noteText = StoryData.notes[n].text; open(NOTE) }
    fun openText(title: String, text: String) { screens.noteTitle = title; screens.noteText = text; open(NOTE) }

    fun message(text: String) { toast = text; toastTime = 3.2f }
    fun banner(title: String, text: String) { bannerQueue.add(Pair(title, text)) }
    fun notifyPickup(id: Int, n: Int) {
        for (p in pickups) if (p.id == id && p.time > 0.6f) { p.count += n; p.time = 3f; return }
        if (pickups.size >= 6) pickups.removeAt(0)
        pickups.add(Pickup(id, n, 3f))
    }

    // ------------------------------------------------------------------ frame

    fun frame(dt: Float) {
        val u = ui
        val p = scene.player
        u.begin(scene.game.engine.width, scene.game.engine.height)
        lookDx = 0f; lookDy = 0f
        useClicked = false; interactClicked = false; breakPressed = false

        if (p.dead && screen != DEATH) { screen = DEATH; screens.onOpen(DEATH) }
        if (u.backPressed) {
            if (screen == NONE) open(PAUSE) else if (screen != DEATH) { if (screen == SETTINGS) open(PAUSE) else close() }
        }

        if (!scene.ready) { drawLoading(); u.end(); return }

        if (screen == NONE) {
            controls(dt)
            statusBars()
            topBar()
            hotbar()
            crosshair()
            notifications(dt)
            if (scene.game.engine.settings.showProfiler) profilerOverlay()
        } else {
            breakHeld = false; joyActive = false
            p.moveX = 0f; p.moveZ = 0f; p.jumpHeld = false
            // dim the world and swallow touches that miss the panel
            u.rect(0f, 0f, u.vw, u.vh, 0x99000000.toInt())
            screens.draw(screen, dt)
            u.block(0f, 0f, u.vw, u.vh)
            notifications(dt)
        }
        u.end()
    }

    private fun drawLoading() {
        val u = ui
        u.rect(0f, 0f, u.vw, u.vh, 0xF0101612.toInt())
        u.text("WILD FRONTIER", u.vw * 0.5f, 250f, 64f, Ui.TEXT, 1, true)
        u.text("Создаём архипелаг…", u.vw * 0.5f, 350f, 28f, Ui.TEXT_DIM, 1)
        u.bar(u.vw * 0.5f - 220f, 410f, 440f, 20f, loadingProgress, Ui.ACCENT)
        u.block(0f, 0f, u.vw, u.vh)
    }

    // ------------------------------------------------------------------ touch controls

    private fun controls(dt: Float) {
        val u = ui
        val p = scene.player
        val sens = scene.game.engine.settings.lookSensitivity
        val inv = if (scene.game.engine.settings.invertY) -1f else 1f
        val R = u.vw - u.safeR
        val B = u.vh - u.safeB

        // --- action cluster (bottom right)
        val fb = u.roundButton(ID_BREAK, R - 118f, B - 150f, 64f, "ui_mine")
        breakHeld = fb and Ui.HELD != 0
        if (fb and Ui.PRESSED != 0) breakPressed = true
        val fp = u.roundButton(ID_PLACE, R - 262f, B - 96f, 52f, "ui_place")
        if (fp and Ui.PRESSED != 0) { useClicked = true; placeRepeat = 0.32f }
        else if (fp and Ui.HELD != 0) { placeRepeat -= dt; if (placeRepeat <= 0f) { useClicked = true; placeRepeat = 0.22f } }
        p.jumpHeld = u.roundButton(ID_JUMP, R - 96f, B - 300f, 50f, "ui_jump") and Ui.HELD != 0
        val hint = scene.interaction.interactHint()
        val fi = u.roundButton(ID_INTERACT, R - 250f, B - 232f, 46f, "ui_hand", active = hint != null)
        if (fi and Ui.CLICKED != 0) interactClicked = true
        if (hint != null) {
            val w = u.textWidth(hint, 22f) + 26f
            u.rect(R - 250f - 54f - w, B - 232f - 20f, w, 40f, 0xAA101510.toInt(), 12f)
            u.text(hint, R - 250f - 54f - w * 0.5f, B - 232f - 13f, 22f, Ui.TEXT, 1)
        }
        if (u.roundButton(ID_CROUCH, R - 392f, B - 66f, 36f, "ui_crouch", active = p.crouching) and Ui.CLICKED != 0) p.crouching = !p.crouching
        if (u.roundButton(ID_SPRINT, u.safeL + 318f, B - 76f, 36f, "ui_run", active = p.sprintToggle) and Ui.CLICKED != 0) p.sprintToggle = !p.sprintToggle
        // holding the break button also steers the camera, so the player can mine and aim with one thumb
        u.pointerOwnedBy(ID_BREAK)?.let { lookDx += it.dx; lookDy += it.dy }

        // --- joystick (left) and look pad (everything else)
        for (ptr in u.pointers) {
            if (ptr.active && ptr.down && ptr.owner == 0) {
                ptr.owner = if (ptr.x < u.vw * 0.42f && ptr.y > u.vh * 0.28f) Ui.OWNER_JOYSTICK else Ui.OWNER_LOOK
            }
        }
        val joy = u.pointerOwnedBy(Ui.OWNER_JOYSTICK)
        if (joy != null && !joy.up) {
            val radius = 78f
            var dx = (joy.x - joy.startX) / radius; var dy = (joy.y - joy.startY) / radius
            val l = sqrt(dx * dx + dy * dy)
            if (l > 1f) { dx /= l; dy /= l }
            // small dead zone so a resting thumb does not creep
            val dz = 0.12f
            joyX = if (l < dz) 0f else dx; joyY = if (l < dz) 0f else dy
            joyActive = true
            // pushing the stick fully forward for a moment starts a sprint
            if (l >= 0.97f && dy < -0.8f) { sprintHold += dt; if (sprintHold > 0.5f) p.sprintToggle = true } else sprintHold = 0f
            u.circle(joy.startX, joy.startY, radius, 0x44101510)
            u.ring(joy.startX, joy.startY, radius, 3f, 0x66FFFFFF)
            u.circle(joy.startX + dx * radius, joy.startY + dy * radius, 34f, 0xAAE8F0E0.toInt())
        } else {
            joyX = 0f; joyY = 0f; joyActive = false; sprintHold = 0f
            val jx = u.safeL + 150f; val jy = B - 150f
            u.ring(jx, jy, 78f, 3f, 0x33FFFFFF)
            u.circle(jx, jy, 30f, 0x33FFFFFF)
        }
        p.moveX = joyX; p.moveZ = -joyY
        for (ptr in u.pointers) if (ptr.active && ptr.owner == Ui.OWNER_LOOK) { lookDx += ptr.dx; lookDy += ptr.dy }
        lookDx *= 0.0052f * sens; lookDy *= -0.0052f * sens * inv
    }

    // ------------------------------------------------------------------ status

    private fun statusBars() {
        val u = ui
        val sv = scene.player.survival
        val x = u.safeL + 18f; var y = 16f + u.safeT
        fun row(icon: String, v: Float, color: Int) {
            u.icon(icon, x, y - 2f, 24f)
            u.bar(x + 30f, y + 2f, 168f, 16f, v / 100f, if (v < 22f && (u.time * 3f).toInt() % 2 == 0) Ui.DANGER else color)
            y += 26f
        }
        row("ui_heart", sv.health, 0xFFD9453C.toInt())
        row("ui_food", sv.hunger, 0xFFE09A3A.toInt())
        row("ui_water", sv.thirst, 0xFF4FA4E6.toInt())
        row("ui_energy", sv.energy, 0xFFE6D24F.toInt())
        // temperature: icon + feels-like value, tinted by comfort
        val t = sv.temperature
        val tc = if (t < -0.35f) 0xFF7FC4FF.toInt() else if (t > 0.35f) 0xFFFF8A5C.toInt() else Ui.TEXT
        u.icon("ui_temp", x, y - 2f, 24f)
        sb.setLength(0); sb.append(sv.feelsLikeC.toInt()).append("°")
        if (t < -0.35f) sb.append("  холодно") else if (t > 0.35f) sb.append("  жарко")
        if (sv.wetness > 0.3f) sb.append("  промок")
        u.text(sb, x + 30f, y, 20f, tc, 0, true)
        y += 26f
        if (scene.breath < 0.999f) { u.icon("ui_water", x, y - 2f, 24f, 0xFFB0E0FF.toInt()); u.bar(x + 30f, y + 2f, 168f, 16f, scene.breath, 0xFFB8E6FF.toInt()) }
    }

    private fun topBar() {
        val u = ui
        val R = u.vw - u.safeR
        val y = 44f + u.safeT
        val names = arrayOf("ui_pause", "ui_map", "ui_journal", "ui_paw", "ui_craft", "ui_home", "ui_bag", "ui_camera")
        for (i in names.indices) {
            val cx = R - 44f - i * 66f
            if (u.roundButton(ID_TOP + i, cx, y, 28f, names[i], alpha = 0x77) and Ui.CLICKED != 0) when (i) {
                0 -> open(PAUSE); 1 -> open(MAP); 2 -> open(JOURNAL); 3 -> open(ENCYCLOPEDIA); 4 -> { screens.forcedStation = -1; open(CRAFTING) }
                5 -> open(BUILD); 6 -> open(INVENTORY); 7 -> scene.player.firstPerson = !scene.player.firstPerson
            }
        }
        // clock, weather, compass
        val dn = scene.dayNight
        val cx = u.vw * 0.5f
        val h = dn.hour.toInt(); val m = ((dn.hour - h) * 60f).toInt()
        sb.setLength(0); sb.append("День ").append(dn.day).append("  ").append(if (h < 10) "0" else "").append(h).append(':').append(if (m < 10) "0" else "").append(m)
        val tw = u.textWidth(sb, 22f)
        u.rect(cx - tw * 0.5f - 46f, 10f + u.safeT, tw + 92f, 36f, 0x77101510, 18f)
        u.icon(if (dn.isNight) "ui_moon" else Weather.ICONS[scene.weather.type], cx - tw * 0.5f - 38f, 14f + u.safeT, 28f)
        u.text(sb, cx - tw * 0.5f, 17f + u.safeT, 22f, Ui.TEXT)
        val yawDeg = ((Math.toDegrees(scene.player.yaw.toDouble()) % 360.0) + 360.0) % 360.0
        val dir = arrayOf("С", "СВ", "В", "ЮВ", "Ю", "ЮЗ", "З", "СЗ")[(((yawDeg + 22.5) / 45.0).toInt()) % 8]
        u.text(dir, cx + tw * 0.5f + 14f, 17f + u.safeT, 22f, Ui.ACCENT)
        // quest tracker
        val q = scene.story.activeMain
        if (q >= 0) {
            val quest = StoryData.quests[q]
            sb.setLength(0); sb.append(quest.title)
            if (quest.goal > 1) sb.append("  ").append(minOf(displayProgress(q), quest.goal)).append('/').append(quest.goal)
            u.text(sb, cx, 54f + u.safeT, 20f, 0xFFE8E0B8.toInt(), 1, true)
        }
    }

    /** Quests 1 and 2 store a bit mask of sub-goals; show the number of bits set. */
    fun displayProgress(q: Int): Int {
        val v = scene.story.progress[q]
        return if ((q == 1 || q == 2) && !scene.story.done[q]) Integer.bitCount(v and 3) else v
    }

    private fun hotbar() {
        val u = ui
        val p = scene.player
        val size = 62f; val gap = 6f
        val total = Player.HOTBAR * size + (Player.HOTBAR - 1) * gap
        val x0 = (u.vw - total) * 0.5f
        val y = u.vh - u.safeB - size - 12f
        for (i in 0 until Player.HOTBAR) {
            val x = x0 + i * (size + gap)
            val f = u.press(ID_HOTBAR + i, x, y, size, size)
            if (f and Ui.PRESSED != 0) { p.selected = i; scene.audio.play("click", 0.4f, 1.3f) }
            slot(x, y, size, p.inventory.slots[i], i == p.selected)
        }
        // name of the held item
        val held = p.heldItem
        if (!held.isEmpty) u.text(Items.name(held.id), u.vw * 0.5f, y - 28f, 20f, Ui.TEXT, 1, true)
    }

    /** Draws one inventory slot with icon, stack count and durability. */
    fun slot(x: Float, y: Float, size: Float, s: wildfrontier.content.ItemStack, selected: Boolean, locked: Boolean = false) {
        val u = ui
        u.rect(x, y, size, size, if (locked) 0x66201818 else Ui.SLOT, 10f)
        if (selected) { u.rect(x, y, size, size, 0x555F8F4A, 10f); u.rect(x + 4f, y + size - 6f, size - 8f, 4f, Ui.ACCENT, 2f) }
        if (locked) { u.icon("ui_lock", x + size * 0.25f, y + size * 0.25f, size * 0.5f, 0x88FFFFFF.toInt()); return }
        if (s.isEmpty) return
        val def = Items.get(s.id) ?: return
        u.icon(def.icon, x + size * 0.1f, y + size * 0.08f, size * 0.8f)
        if (s.count > 1) { sb.setLength(0); sb.append(s.count); u.text(sb, x + size - 6f, y + size - 24f, 19f, Ui.TEXT, 2, true) }
        if (def.durability > 0 && s.durability < def.durability) {
            val v = s.durability.toFloat() / def.durability
            u.rect(x + 6f, y + size - 9f, size - 12f, 4f, 0xAA000000.toInt(), 2f)
            u.rect(x + 6f, y + size - 9f, (size - 12f) * v, 4f, if (v > 0.5f) Ui.ACCENT else if (v > 0.2f) Ui.WARN else Ui.DANGER, 2f)
        }
    }

    private fun crosshair() {
        val u = ui
        val cx = u.vw * 0.5f; val cy = u.vh * 0.5f
        val it = scene.interaction
        u.ring(cx, cy, 7f, 2f, 0xCCFFFFFF.toInt())
        if (it.breakProgress > 0f) {
            u.ring(cx, cy, 20f, 4f, 0x55000000)
            u.bar(cx - 36f, cy + 30f, 72f, 8f, it.breakProgress, Ui.TEXT)
        }
        if (it.fishing > 0f) { u.text("Рыбалка…", cx, cy + 44f, 20f, Ui.TEXT, 1, true); u.bar(cx - 50f, cy + 70f, 100f, 8f, it.fishingProgress, 0xFF6FB6E8.toInt()) }
        else if (it.targetAnimal >= 0) {
            val a = scene.animals.store[it.targetAnimal]
            if (a != null) {
                sb.setLength(0); sb.append(a.species.name); if (a.baby) sb.append(" (детёныш)"); sb.append(" — ").append(AState.NAMES[a.state])
                u.text(sb, cx, cy + 26f, 20f, Ui.TEXT, 1, true)
                u.bar(cx - 40f, cy + 52f, 80f, 7f, a.health / a.species.health, Ui.DANGER)
            }
        } else if (it.hasTarget && it.breakProgress <= 0f) {
            u.text(Blocks.get(it.hit.block).displayName, cx, cy + 22f, 18f, 0xCCFFFFFF.toInt(), 1, true)
        }
    }

    private fun notifications(dt: Float) {
        val u = ui
        var y = u.vh * 0.42f
        val x = u.safeL + 20f
        var i = 0
        while (i < pickups.size) {
            val p = pickups[i]
            p.time -= dt
            if (p.time <= 0f) { pickups.removeAt(i); continue }
            val a = (clamp(p.time * 2f, 0f, 1f) * 255f).toInt()
            val def = Items.get(p.id)
            if (def != null && screen == NONE) {
                sb.setLength(0); sb.append('+').append(p.count).append("  ").append(def.name)
                val w = u.textWidth(sb, 20f) + 52f
                u.rect(x, y, w, 34f, (a * 0x77 / 255 shl 24) or 0x101510, 10f)
                u.icon(def.icon, x + 5f, y + 3f, 28f, (a shl 24) or 0xFFFFFF)
                u.text(sb, x + 40f, y + 6f, 20f, (a shl 24) or 0xF2F4F0)
                y += 38f
            }
            i++
        }
        if (toastTime > 0f) {
            toastTime -= dt
            val a = (clamp(toastTime * 2f, 0f, 1f) * 255f).toInt()
            val w = u.textWidth(toast, 24f) + 44f
            u.rect((u.vw - w) * 0.5f, u.vh * 0.66f, w, 46f, (a * 0xAA / 255 shl 24) or 0x101510, 14f)
            u.text(toast, u.vw * 0.5f, u.vh * 0.66f + 10f, 24f, (a shl 24) or 0xF2F4F0, 1)
        }
        if (bannerTime <= 0f && bannerQueue.isNotEmpty() && screen == NONE) {
            val b = bannerQueue.removeAt(0)
            bannerTitle = b.first; bannerText = b.second; bannerTime = 4f
        }
        if (bannerTime > 0f && screen == NONE) {
            bannerTime -= dt
            val k = clamp(minOf(bannerTime, 4f - bannerTime) * 3f, 0f, 1f)
            val a = (k * 255f).toInt()
            val w = maxOf(u.textWidth(bannerText, 30f), u.textWidth(bannerTitle, 20f)) + 80f
            val y0 = 96f + u.safeT - (1f - k) * 30f
            u.rect((u.vw - w) * 0.5f, y0, w, 84f, (a * 0xCC / 255 shl 24) or 0x1A211C, 16f)
            u.rect((u.vw - w) * 0.5f, y0, 6f, 84f, (a shl 24) or 0x7DBB55, 3f)
            u.text(bannerTitle, u.vw * 0.5f, y0 + 10f, 20f, (a shl 24) or 0xB8E08A, 1)
            u.text(bannerText, u.vw * 0.5f, y0 + 38f, 30f, (a shl 24) or 0xF2F4F0, 1)
        }
    }

    private fun profilerOverlay() {
        val u = ui
        val pr = scene.game.engine.profiler
        val x = u.safeL + 18f; var y = 190f + u.safeT
        u.rect(x - 8f, y - 8f, 330f, 250f, 0x99000000.toInt(), 8f)
        fun line(s: CharSequence) { u.text(s, x, y, 16f, 0xFFD8F0C8.toInt()); y += 19f }
        sb.setLength(0); sb.append("FPS ").append(pr.fps.toInt()).append("  кадр ").append((pr.avgFrameMs * 10f).toInt() / 10f).append(" мс  макс ").append(pr.worstFrameMs.toInt()); line(sb)
        sb.setLength(0); sb.append("Draw calls ").append(pr.lastDrawCalls).append("  треуг. ").append(pr.lastTriangles / 1000).append("k"); line(sb)
        sb.setLength(0); sb.append("Чанки: ").append(pr.lastChunksDrawn).append(" видно / ").append(pr.chunksLoaded).append(" загр. / очередь ").append(pr.chunkJobsPending); line(sb)
        sb.setLength(0); sb.append("Ген. ").append((pr.avgChunkGenMs * 10f).toInt() / 10f).append(" мс  меш ").append((pr.avgChunkMeshMs * 10f).toInt() / 10f).append(" мс"); line(sb)
        sb.setLength(0); sb.append("Загрузка мира ").append(pr.worldLoadMs.toInt()).append(" мс"); line(sb)
        sb.setLength(0); sb.append("RAM ").append(pr.usedMemMb).append(" МБ  VRAM≈").append(pr.gpuMemEstimateMb.toInt()).append(" МБ"); line(sb)
        sb.setLength(0); sb.append("Сущности ").append(pr.activeEntities).append("  частицы ").append(pr.particles); line(sb)
        sb.setLength(0); sb.append("Качество ").append(scene.game.engine.settings.effectiveQuality).append("  термо ").append(pr.thermal); line(sb)
        for (i in 0 until pr.sectionCount()) { sb.setLength(0); sb.append(pr.sectionName(i)).append(' ').append((pr.sectionMs(i) * 100f).toInt() / 100f).append(" мс"); line(sb) }
        val c = scene.column
        sb.setLength(0); sb.append(Biome.NAMES[c.biome]).append("  ").append(scene.player.pos.x.toInt()).append(' ').append(scene.player.pos.y.toInt()).append(' ').append(scene.player.pos.z.toInt()); line(sb)
        // frame-time graph
        val gx = x; val gy = y + 4f
        for (i in 0 until wildcore.core.Profiler.HISTORY step 2) {
            val v = minOf(pr.frameMs[i], 50f)
            u.rect(gx + i * 2.6f, gy + 34f - v * 0.68f, 2.2f, v * 0.68f, if (v > 34f) Ui.DANGER else if (v > 18f) Ui.WARN else Ui.ACCENT)
        }
    }
}
