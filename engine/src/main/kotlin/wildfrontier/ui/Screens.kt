package wildfrontier.ui

import wildcore.core.Quality
import wildcore.gfx.Texture2D
import wildcore.world.Blocks
import wildfrontier.animals.SpeciesDb
import wildfrontier.content.B
import wildfrontier.content.Cat
import wildfrontier.content.Equip
import wildfrontier.content.Inventory
import wildfrontier.content.ItemStack
import wildfrontier.content.Items
import wildfrontier.content.Recipe
import wildfrontier.content.Recipes
import wildfrontier.content.Station
import wildfrontier.gen.Biome
import wildfrontier.gen.Column
import wildfrontier.gen.Site
import wildfrontier.gen.WorldGen
import wildfrontier.player.Player
import wildfrontier.story.StoryData
import kotlin.math.cos
import kotlin.math.sin

/** Modal screens of the in-game interface (inventory, crafting, map, journal, …). */
class Screens(private val hud: Hud) {
    private val scene get() = hud.scene
    private val ui: Ui get() = hud.ui
    private val sb = StringBuilder(96)

    // shared panel geometry (virtual units), set by frame()
    private var px = 0f; private var py = 0f; private var pw = 0f; private var ph = 0f

    // inventory / chest
    private var selInv: Inventory? = null
    private var selSlot = -1
    var chestX = 0; var chestY = 0; var chestZ = 0
    // crafting
    var forcedStation = -1
    private var craftCat = -1
    private var craftSel: Recipe? = null
    private var craftScroll = 0f
    private val stations = BooleanArray(4)
    private val filtered = ArrayList<Recipe>()
    // journal / encyclopedia / note
    private var journalTab = 0
    private var listScroll = 0f
    private var encSel = 0
    var noteTitle = ""; var noteText = ""
    // map
    private var mapTex: Texture2D? = null
    private var mapScale = 4
    private var mapCx = 0; private var mapCz = 0
    private var mapPending = false
    private var mapReady = false
    private val nearSites = ArrayList<Site>()
    private var settingsFromPause = true

    fun onOpen(s: Int) {
        selInv = null; selSlot = -1; listScroll = 0f; craftScroll = 0f
        when (s) {
            Hud.CRAFTING -> { detectStations(); craftSel = null; refilter() }
            Hud.MAP -> requestMap()
        }
    }

    fun onClose() { selInv = null; selSlot = -1 }

    fun onContextLost() { mapTex = null; mapReady = false }

    fun draw(screen: Int, dt: Float) {
        when (screen) {
            Hud.INVENTORY -> inventory()
            Hud.CHEST -> chest()
            Hud.CRAFTING -> crafting()
            Hud.MAP -> map()
            Hud.JOURNAL -> journal()
            Hud.ENCYCLOPEDIA -> encyclopedia()
            Hud.PAUSE -> pause()
            Hud.SETTINGS -> settings()
            Hud.NOTE -> note()
            Hud.DEATH -> death()
            Hud.BUILD -> build()
        }
    }

    /** Draws the standard window frame and returns nothing; content area is px,py,pw,ph. */
    private fun frame(title: String, width: Float = 1120f, height: Float = 610f, closable: Boolean = true) {
        val u = ui
        pw = minOf(width, u.vw - u.safeL - u.safeR - 40f); ph = minOf(height, u.vh - 40f)
        px = (u.vw - pw) * 0.5f; py = (u.vh - ph) * 0.5f
        u.panel(px, py, pw, ph)
        u.rect(px, py, pw, 58f, Ui.PANEL_LIGHT, 18f)
        u.text(title, px + 26f, py + 14f, 30f, Ui.TEXT)
        if (closable && u.button(900, px + pw - 62f, py + 8f, 48f, 42f, "×", color = 0xFF5A2A26.toInt(), size = 30f)) hud.close()
        py += 70f; ph -= 82f; px += 22f; pw -= 44f
    }

    // ------------------------------------------------------------------ inventory

    private fun tapSlot(inv: Inventory, index: Int) {
        val cur = selInv
        if (cur == null) {
            if (!inv.slots[index].isEmpty) { selInv = inv; selSlot = index }
        } else if (cur === inv && selSlot == index) {
            selInv = null; selSlot = -1
        } else {
            move(cur, selSlot, inv, index)
            selInv = null; selSlot = -1
        }
        scene.audio.play("click", 0.4f, 1.2f)
    }

    private fun move(a: Inventory, ai: Int, b: Inventory, bi: Int) {
        val s = a.slots[ai]; val d = b.slots[bi]
        if (s.isEmpty) return
        // equipment slots only accept matching gear
        if (b === scene.player.equipment) { val def = Items.get(s.id); if (def == null || def.equipSlot != bi) { hud.message("Сюда это не надеть"); return } }
        if (a === scene.player.equipment && !d.isEmpty) { val def = Items.get(d.id); if (def == null || def.equipSlot != ai) return }
        val def = Items.get(s.id) ?: return
        if (!d.isEmpty && d.id == s.id && def.maxStack > 1) {
            val n = minOf(s.count, def.maxStack - d.count)
            d.count += n; s.count -= n
            if (s.count <= 0) s.clear()
        } else {
            val tid = d.id; val tc = d.count; val td = d.durability
            d.set(s)
            if (tc > 0) s.set(tid, tc, td) else s.clear()
        }
        a.touch(); b.touch()
        scene.applyBackpack()
    }

    private fun grid(inv: Inventory, x: Float, y: Float, cols: Int, idBase: Int, size: Float = 62f, from: Int = 0, count: Int = inv.size): Float {
        val gap = 6f
        for (k in 0 until count) {
            val i = from + k
            val sx = x + (k % cols) * (size + gap); val sy = y + (k / cols) * (size + gap)
            val locked = i >= inv.activeSize
            if (!locked && ui.press(idBase + i, sx, sy, size, size) and Ui.CLICKED != 0) tapSlot(inv, i)
            hud.slot(sx, sy, size, inv.slots[i], selInv === inv && selSlot == i, locked)
        }
        return y + ((count + cols - 1) / cols) * (size + gap)
    }

    private fun itemInfo(x: Float, y: Float, w: Float, s: ItemStack?, actions: Boolean) {
        val u = ui
        u.rect(x, y, w, ph - (y - py), 0x55101510, 12f)
        if (s == null || s.isEmpty) { u.paragraph("Коснитесь предмета, затем — ячейки, куда его переложить.", x + 14f, y + 14f, w - 28f, 20f, Ui.TEXT_DIM); return }
        val def = Items.get(s.id) ?: return
        u.icon(def.icon, x + 14f, y + 12f, 72f)
        u.paragraph(def.name, x + 96f, y + 14f, w - 106f, 24f, Ui.TEXT)
        u.text(Cat.NAMES[def.category], x + 96f, y + 66f, 18f, Ui.ACCENT)
        var cy = y + 100f
        cy += u.paragraph(def.description, x + 14f, cy, w - 28f, 19f, Ui.TEXT_DIM) + 6f
        sb.setLength(0)
        if (def.food > 0f) sb.append("Сытость +").append(def.food.toInt()).append("   ")
        if (def.water > 0f) sb.append("Вода +").append(def.water.toInt()).append("   ")
        if (def.heal != 0f) sb.append("Здоровье ").append(if (def.heal > 0) "+" else "").append(def.heal.toInt())
        if (def.durability > 0) sb.append("Прочность ").append(s.durability).append('/').append(def.durability).append("   ")
        if (def.toolTier > 0 && def.toolKind != 0) sb.append("Уровень ").append(def.toolTier).append("   ")
        if (def.damage > 1f) sb.append("Урон ").append(def.damage.toInt())
        if (def.warmth > 0f) sb.append("Тепло +").append(def.warmth.toInt()).append("°")
        if (sb.isNotEmpty()) cy += u.paragraph(sb, x + 14f, cy, w - 28f, 18f, 0xFFE8E0B8.toInt()) + 4f
        if (!actions) return
        val by = py + ph - 170f
        val bw = w - 28f
        val inv = selInv ?: return
        if ((def.food > 0f || def.water > 0f) && u.button(910, x + 14f, by, bw, 46f, "Съесть / выпить", size = 22f)) {
            scene.player.survival.eat(def.food, def.water, def.heal)
            scene.audio.play(if (def.food > 0f) "eat" else "drink")
            if (def.id == wildfrontier.content.I.WATERSKIN_FULL) s.set(wildfrontier.content.I.WATERSKIN, 1) else { s.count--; if (s.count <= 0) { s.clear(); selInv = null; selSlot = -1 } }
            inv.touch()
        } else if (def.equipSlot >= 0 && inv === scene.player.inventory && u.button(911, x + 14f, by, bw, 46f, "Надеть", size = 22f)) {
            scene.interaction.equip(selSlot); selInv = null; selSlot = -1
        }
        if (u.button(912, x + 14f, by + 54f, bw * 0.5f - 4f, 46f, "Бросить 1", size = 20f, color = 0xFF4A4030.toInt())) dropSelected(1)
        if (u.button(913, x + 14f + bw * 0.5f + 4f, by + 54f, bw * 0.5f - 4f, 46f, "Бросить всё", size = 20f, color = 0xFF4A4030.toInt())) dropSelected(9999)
        if (s.count > 1 && u.button(914, x + 14f, by + 108f, bw, 46f, "Разделить пополам", size = 20f, color = 0xFF30404A.toInt())) {
            val half = s.count / 2
            for (t in inv.slots.indices) if (t < inv.activeSize && inv.slots[t].isEmpty) { inv.slots[t].set(s.id, half, s.durability); s.count -= half; inv.touch(); break }
        }
    }

    private fun dropSelected(n: Int) {
        val inv = selInv ?: return
        val s = inv.slots[selSlot]
        if (s.isEmpty) return
        val k = minOf(n, s.count)
        val p = scene.player
        scene.drops.spawn(s.id, k, p.pos.x + sin(p.yaw) * 0.8f, p.pos.y + 1.2f, p.pos.z - cos(p.yaw) * 0.8f, s.durability, 1.6f, sin(p.yaw) * 3f, -cos(p.yaw) * 3f)
        s.count -= k
        if (s.count <= 0) { s.clear(); selInv = null; selSlot = -1 }
        inv.touch(); scene.applyBackpack()
    }

    private fun inventory() {
        frame("Инвентарь")
        val u = ui
        val p = scene.player
        // equipment column
        val labels = arrayOf("Одежда", "Обувь", "Рюкзак")
        for (i in 0 until 3) {
            val sy = py + i * 92f
            u.text(labels[i], px, sy, 18f, Ui.TEXT_DIM)
            if (u.press(950 + i, px, sy + 22f, 62f, 62f) and Ui.CLICKED != 0) tapSlot(p.equipment, i)
            hud.slot(px, sy + 22f, 62f, p.equipment.slots[i], selInv === p.equipment && selSlot == i)
        }
        val sv = p.survival
        var ty = py + 290f
        fun stat(name: String, v: Int) { sb.setLength(0); sb.append(name).append(": ").append(v); u.text(sb, px, ty, 18f, Ui.TEXT_DIM); ty += 24f }
        stat("Здоровье", sv.health.toInt()); stat("Сытость", sv.hunger.toInt()); stat("Вода", sv.thirst.toInt()); stat("Силы", sv.energy.toInt())
        stat("Тепло одежды", p.clothingWarmth().toInt()); stat("Дней прожито", p.statDaysSurvived)
        // main grid: first row = quick access
        val gx = px + 150f
        u.text("Быстрый доступ", gx, py - 2f, 18f, Ui.ACCENT)
        grid(p.inventory, gx, py + 22f, 9, 1000)
        u.rect(gx, py + 22f + 66f, Player.HOTBAR * 68f - 6f, 3f, Ui.ACCENT_DARK, 1f)
        val sel = selInv?.slots?.get(selSlot)
        itemInfo(gx + 9 * 68f + 14f, py, pw - (150f + 9 * 68f + 14f), sel, true)
    }

    private fun chest() {
        frame("Сундук")
        val u = ui
        val w = scene.world
        var inv = w.getBlockData(chestX, chestY, chestZ) as? Inventory
        if (inv == null) { inv = Inventory(27); w.setBlockData(chestX, chestY, chestZ, inv) }
        if (w.getBlock(chestX, chestY, chestZ) != B.CHEST) { hud.close(); return }
        u.text("Содержимое", px, py - 2f, 18f, Ui.TEXT_DIM)
        val y2 = grid(inv, px, py + 22f, 9, 1100, 56f)
        u.text("Ваш инвентарь", px, y2 + 4f, 18f, Ui.TEXT_DIM)
        grid(scene.player.inventory, px, y2 + 28f, 9, 1000, 56f)
        val ix = px + 9 * 62f + 14f
        val sel = selInv?.slots?.get(selSlot)
        itemInfo(ix, py, pw - (9 * 62f + 14f), sel, false)
        if (u.button(920, ix + 14f, py + ph - 60f, pw - (9 * 62f + 14f) - 28f, 48f, "Забрать всё", size = 22f)) {
            for (s in inv.slots) if (!s.isEmpty) { val left = scene.player.inventory.add(s.id, s.count, s.durability); if (left <= 0) s.clear() else s.count = left }
            inv.touch()
        }
        // chest edits must be persisted with the chunk
        w.getChunk(chestX shr 4, chestZ shr 4)?.let { it.modified = true; it.unsaved = true }
    }

    // ------------------------------------------------------------------ crafting

    private fun detectStations() {
        stations[Station.HAND] = true
        for (i in 1..3) stations[i] = forcedStation == i
        val p = scene.player.pos
        val w = scene.world
        val bx = p.x.toInt(); val by = p.y.toInt(); val bz = p.z.toInt()
        for (dy in -2..3) for (dz in -4..4) for (dx in -4..4) {
            when (w.getBlock(bx + dx, by + dy, bz + dz)) {
                B.WORKBENCH -> stations[Station.WORKBENCH] = true
                B.FURNACE -> stations[Station.FURNACE] = true
                B.CAMPFIRE -> stations[Station.CAMPFIRE] = true
            }
        }
    }

    private fun refilter() {
        filtered.clear()
        // forced station view (opened by touching a station) lists that station's recipes first
        for (pass in 0..1) for (r in Recipes.all) {
            if (craftCat >= 0 && r.category != craftCat) continue
            val available = stations[r.station]
            if ((pass == 0) == available) filtered.add(r)
        }
        if (forcedStation > 0) filtered.sortBy { if (it.station == forcedStation) 0 else if (stations[it.station]) 1 else 2 }
    }

    private fun crafting() {
        frame(if (forcedStation > 0) "Создание — ${Station.NAMES[forcedStation]}" else "Создание предметов")
        val u = ui
        val inv = scene.player.inventory
        // category tabs
        val tabs = arrayOf("Все", Cat.NAMES[0], Cat.NAMES[1], Cat.NAMES[2], Cat.NAMES[3], Cat.NAMES[4], Cat.NAMES[5], Cat.NAMES[6])
        for (i in tabs.indices) {
            val cat = i - 1
            if (u.button(930 + i, px, py + i * 54f, 170f, 48f, tabs[i], color = if (craftCat == cat) Ui.ACCENT_DARK else 0xFF2E3A30.toInt(), size = 20f)) { craftCat = cat; craftScroll = 0f; refilter() }
        }
        // recipe grid
        val gx = px + 186f; val cols = 6; val cell = 76f
        val gw = cols * cell; val gh = ph
        val rows = (filtered.size + cols - 1) / cols
        craftScroll = u.scroll(940, gx, py, gw, gh, rows * cell + 8f, craftScroll)
        u.rect(gx - 6f, py - 4f, gw + 12f, gh + 8f, 0x44101510, 10f)
        u.clip(gx, py, gw, gh)
        for (k in filtered.indices) {
            val r = filtered[k]
            val sx = gx + (k % cols) * cell + 4f; val sy = py + (k / cols) * cell + 4f - craftScroll
            if (sy < py - cell || sy > py + gh) continue
            val can = stations[r.station] && r.canCraft(inv)
            val stationOk = stations[r.station]
            if (u.tapIn(940, sx, sy, cell - 8f, cell - 8f)) { craftSel = r; scene.audio.play("click", 0.4f) }
            u.rect(sx, sy, cell - 8f, cell - 8f, if (craftSel === r) 0xFF41702E.toInt() else if (can) 0xCC243024.toInt() else 0x99181C18.toInt(), 10f)
            val def = Items.get(r.result) ?: continue
            u.icon(def.icon, sx + 6f, sy + 4f, cell - 20f, if (can) Ui.WHITE else if (stationOk) 0x99FFFFFF.toInt() else 0x55FFFFFF)
            if (r.count > 1) { sb.setLength(0); sb.append(r.count); u.text(sb, sx + cell - 14f, sy + cell - 30f, 17f, Ui.TEXT, 2, true) }
            if (can) u.circle(sx + 11f, sy + 11f, 5f, Ui.ACCENT)
        }
        u.unclip()
        // details
        val dx = gx + gw + 18f; val dw = px + pw - dx
        u.rect(dx, py, dw, ph, 0x55101510, 12f)
        val r = craftSel
        if (r == null) { u.paragraph("Выберите рецепт. Зелёная точка — хватает материалов. Верстак, печь и костёр открывают новые рецепты, когда стоят рядом.", dx + 14f, py + 14f, dw - 28f, 20f, Ui.TEXT_DIM); return }
        val def = Items.get(r.result) ?: return
        u.icon(def.icon, dx + 14f, py + 12f, 72f)
        sb.setLength(0); sb.append(def.name); if (r.count > 1) sb.append(" ×").append(r.count)
        var cy = py + 14f
        u.paragraph(sb, dx + 96f, cy, dw - 106f, 24f, Ui.TEXT)
        cy = py + 96f
        cy += u.paragraph(def.description, dx + 14f, cy, dw - 28f, 18f, Ui.TEXT_DIM) + 8f
        val stOk = stations[r.station]
        sb.setLength(0); sb.append(if (r.station == Station.HAND) "Делается руками" else "Нужно рядом: ").append(if (r.station == Station.HAND) "" else Station.NAMES[r.station])
        u.text(sb, dx + 14f, cy, 19f, if (stOk) Ui.ACCENT else Ui.DANGER); cy += 30f
        var i = 0
        while (i < r.ingredients.size) {
            val id = r.ingredients[i]; val need = r.ingredients[i + 1]; val have = inv.count(id)
            val d = Items.get(id)
            if (d != null) {
                u.icon(d.icon, dx + 14f, cy - 4f, 34f)
                sb.setLength(0); sb.append(d.name)
                u.text(sb, dx + 56f, cy + 2f, 19f, Ui.TEXT)
                sb.setLength(0); sb.append(have).append('/').append(need)
                u.text(sb, dx + dw - 16f, cy + 2f, 19f, if (have >= need) Ui.ACCENT else Ui.DANGER, 2)
            }
            cy += 38f; i += 2
        }
        val can = stOk && r.canCraft(inv)
        if (u.button(960, dx + 14f, py + ph - 116f, dw - 28f, 50f, "Создать", enabled = can, size = 24f)) craft(r, 1)
        if (u.button(961, dx + 14f, py + ph - 60f, dw - 28f, 46f, "Создать ×5", enabled = can, size = 20f, color = 0xFF30404A.toInt())) craft(r, 5)
    }

    private fun craft(r: Recipe, times: Int) {
        val inv = scene.player.inventory
        var made = 0
        for (t in 0 until times) {
            if (!r.canCraft(inv)) break
            var i = 0
            while (i < r.ingredients.size) { inv.remove(r.ingredients[i], r.ingredients[i + 1]); i += 2 }
            scene.give(r.result, r.count)
            scene.player.statCrafted++
            scene.story.onCrafted(r.result)
            made++
        }
        if (made > 0) { scene.audio.play("craft"); refilter() }
    }

    // ------------------------------------------------------------------ build palette

    private fun build() {
        frame("Строительство", 980f, 560f)
        val u = ui
        val p = scene.player
        val it = scene.interaction
        u.paragraph("Выберите блок — он попадёт в активную ячейку быстрого доступа. Кнопка с кирпичами ставит блок по прицелу (удерживайте для серии), кирка — разбирает.", px, py, pw - 300f, 19f, Ui.TEXT_DIM)
        // rotation selector
        val rx = px + pw - 280f
        u.text("Ориентация брёвен", rx, py, 18f, Ui.TEXT_DIM)
        val modes = arrayOf("Авто", "X", "Y", "Z")
        for (i in modes.indices) if (u.button(970 + i, rx + i * 70f, py + 26f, 64f, 44f, modes[i], color = if (it.rotateMode == i) Ui.ACCENT_DARK else 0xFF2E3A30.toInt(), size = 20f)) it.rotateMode = i
        // palette of every placeable stack in the inventory
        val y0 = py + 92f
        val cell = 74f; val cols = ((pw) / cell).toInt()
        var k = 0
        val inv = p.inventory
        for (i in 0 until inv.activeSize) {
            val s = inv.slots[i]
            if (s.isEmpty) continue
            val def = Items.get(s.id) ?: continue
            if (def.placesBlock < 0) continue
            val sx = px + (k % cols) * cell; val sy = y0 + (k / cols) * cell
            if (u.press(1300 + i, sx, sy, cell - 8f, cell - 8f) and Ui.CLICKED != 0) {
                if (i != p.selected) { val a = inv.slots[p.selected]; val tid = a.id; val tc = a.count; val td = a.durability; a.set(s); if (tc > 0) s.set(tid, tc, td) else s.clear(); inv.touch() }
                scene.audio.play("click"); hud.close(); return
            }
            hud.slot(sx, sy, cell - 8f, s, i == p.selected)
            k++
        }
        if (k == 0) u.text("В инвентаре нет строительных блоков. Добудьте дерево, камень или создайте доски.", px, y0 + 20f, 20f, Ui.WARN)
    }

    // ------------------------------------------------------------------ map

    private fun requestMap() {
        if (mapPending) return
        mapPending = true
        val cx = scene.player.pos.x.toInt(); val cz = scene.player.pos.z.toInt()
        val scale = mapScale
        val explored = HashSet(scene.explored)
        val gen = scene.gen
        scene.game.engine.jobs.submit(-5f, Runnable {
            val n = 256
            val data = ByteArray(n * n * 4)
            val col = Column()
            val heights = FloatArray(n * n)
            for (j in 0 until n) for (i in 0 until n) {
                val wx = cx + (i - n / 2) * scale; val wz = cz + (j - n / 2) * scale
                val o = (j * n + i) * 4
                val known = explored.contains(wildcore.world.Chunk.key(Math.floorDiv(wx, 16), Math.floorDiv(wz, 16)))
                if (!known) {
                    val v = 34 + (wildcore.math.Hash.hash2(i, j, 5) and 7)
                    data[o] = v.toByte(); data[o + 1] = (v + 4).toByte(); data[o + 2] = v.toByte(); data[o + 3] = 255.toByte()
                    heights[j * n + i] = -1f
                    continue
                }
                gen.sample(wx, wz, col)
                heights[j * n + i] = col.height
                val c = Biome.COLOR[col.biome]
                var r = Math.sqrt(c[0].toDouble()).toFloat(); var g = Math.sqrt(c[1].toDouble()).toFloat(); var b = Math.sqrt(c[2].toDouble()).toFloat()
                if (col.height < WorldGen.SEA) { val d = ((WorldGen.SEA - col.height) / 24f).coerceIn(0f, 1f); r = 0.20f - 0.12f * d; g = 0.46f - 0.2f * d; b = 0.62f - 0.18f * d }
                else { val e = ((col.height - WorldGen.SEA) / 90f).coerceIn(0f, 1f); r += e * 0.12f; g += e * 0.10f; b += e * 0.10f }
                data[o] = (r.coerceIn(0f, 1f) * 255f).toInt().toByte(); data[o + 1] = (g.coerceIn(0f, 1f) * 255f).toInt().toByte()
                data[o + 2] = (b.coerceIn(0f, 1f) * 255f).toInt().toByte(); data[o + 3] = 255.toByte()
            }
            // hill shading from the height field
            for (j in 1 until n - 1) for (i in 1 until n - 1) {
                val h = heights[j * n + i]
                if (h < WorldGen.SEA) continue
                val a = heights[j * n + i - 1]; val bq = heights[(j - 1) * n + i]
                if (a < 0f || bq < 0f) continue
                val s = (1f + ((h - a) + (h - bq)) * 0.06f).coerceIn(0.7f, 1.3f)
                val o = (j * n + i) * 4
                for (k in 0..2) data[o + k] = ((data[o + k].toInt() and 255) * s).toInt().coerceIn(0, 255).toByte()
            }
            scene.game.engine.jobs.runOnMain(Runnable {
                mapPending = false
                if (!scene.game.engine.hasContext) return@Runnable
                val t = mapTex ?: Texture2D(scene.game.engine.gl).also { mapTex = it }
                t.uploadRaw(n, n, data, wildcore.gfx.GL.RGBA8, wildcore.gfx.GL.RGBA, mipmaps = false, repeat = false, linear = true)
                mapCx = cx; mapCz = cz; mapReady = true
                scene.gen.structures.sitesNear(cx, cz, 3, nearSites)
            })
        })
    }

    private fun map() {
        frame("Карта архипелага")
        val u = ui
        val size = minOf(ph, pw - 320f)
        val mx = px; val my = py
        u.rect(mx - 4f, my - 4f, size + 8f, size + 8f, 0xFF2A2218.toInt(), 8f)
        val p = scene.player
        if (mapReady && mapTex != null) {
            u.batch.flush()
            u.batch.auxTex = mapTex
            u.aux(mx, my, size, size, 0f, 0f, 1f, 1f)
            u.batch.flush()
            val k = size / (256f * mapScale)
            fun sx(wx: Float) = mx + size * 0.5f + (wx - mapCx) * k
            fun sy(wz: Float) = my + size * 0.5f + (wz - mapCz) * k
            for (s in scene.story.sites) {
                val x = sx(s.x.toFloat()); val y = sy(s.z.toFloat())
                if (x < mx + 10f || x > mx + size - 10f || y < my + 10f || y > my + size - 10f) continue
                u.icon(if (s.type == Site.WRECK) "ui_flag" else "ui_marker", x - 14f, y - 26f, 28f)
                u.text(Site.NAMES[s.type], x, y + 2f, 15f, Ui.TEXT, 1, true)
            }
            val hx = sx(p.spawn.x); val hy = sy(p.spawn.z)
            if (hx > mx && hx < mx + size && hy > my && hy < my + size) u.icon("ui_home", hx - 13f, hy - 13f, 26f)
            val ax = sx(p.pos.x); val ay = sy(p.pos.z)
            if (ax > mx && ax < mx + size && ay > my && ay < my + size) {
                u.circle(ax, ay, 9f, 0xFFFFFFFF.toInt()); u.circle(ax, ay, 6f, Ui.DANGER)
                u.circle(ax + sin(p.yaw) * 14f, ay - cos(p.yaw) * 14f, 4f, 0xFFFFFFFF.toInt())
            }
            u.text("С", mx + size * 0.5f, my + 6f, 22f, Ui.TEXT, 1, true)
        } else u.text("Составляем карту…", mx + size * 0.5f, my + size * 0.5f - 12f, 24f, Ui.TEXT_DIM, 1)
        val ix = mx + size + 24f; val iw = px + pw - ix
        var cy = py
        val col = scene.column
        u.text("Вы здесь", ix, cy, 18f, Ui.TEXT_DIM); cy += 24f
        u.text(Biome.NAMES[col.biome], ix, cy, 26f, Ui.TEXT); cy += 36f
        sb.setLength(0); sb.append("X ").append(p.pos.x.toInt()).append("   Z ").append(p.pos.z.toInt()).append("   высота ").append(p.pos.y.toInt() - WorldGen.SEA)
        u.text(sb, ix, cy, 18f, Ui.TEXT_DIM); cy += 34f
        sb.setLength(0); sb.append("Найдено мест: ").append(scene.story.sites.size); u.text(sb, ix, cy, 18f, Ui.TEXT_DIM); cy += 24f
        var nb = 0; for (b in scene.story.biomesSeen) if (b) nb++
        sb.setLength(0); sb.append("Природных зон: ").append(nb).append(" из ").append(Biome.COUNT); u.text(sb, ix, cy, 18f, Ui.TEXT_DIM); cy += 40f
        cy += u.paragraph("Карта показывает только разведанные земли. Обрывки карты из ящиков экспедиции отмечают ближайшие объекты.", ix, cy, iw, 18f, Ui.TEXT_DIM) + 12f
        u.text("Масштаб", ix, cy, 18f, Ui.TEXT_DIM); cy += 26f
        val scales = intArrayOf(2, 4, 8)
        for (i in scales.indices) if (u.button(980 + i, ix + i * 88f, cy, 80f, 46f, "1:" + scales[i], color = if (mapScale == scales[i]) Ui.ACCENT_DARK else 0xFF2E3A30.toInt(), size = 20f)) { mapScale = scales[i]; requestMap() }
    }

    // ------------------------------------------------------------------ journal

    private fun journal() {
        frame("Журнал")
        val u = ui
        val st = scene.story
        val tabs = arrayOf("Задания", "Записи", "Достижения", "Статистика")
        for (i in tabs.indices) if (u.button(990 + i, px + i * 190f, py, 182f, 46f, tabs[i], color = if (journalTab == i) Ui.ACCENT_DARK else 0xFF2E3A30.toInt(), size = 21f)) { journalTab = i; listScroll = 0f }
        val ly = py + 60f; val lh = ph - 60f
        u.rect(px - 6f, ly - 4f, pw + 12f, lh + 8f, 0x44101510, 10f)
        when (journalTab) {
            0 -> {
                var content = 0f
                for (q in StoryData.quests) if (st.done[q.id] || st.isActive(q.id)) content += 96f
                listScroll = u.scroll(995, px, ly, pw, lh, content, listScroll)
                u.clip(px, ly, pw, lh)
                var y = ly - listScroll
                for (pass in 0..1) for (q in StoryData.quests) {
                    val active = st.isActive(q.id)
                    if ((pass == 0 && !active) || (pass == 1 && !st.done[q.id])) continue
                    u.rect(px, y, pw, 88f, if (active) 0xAA243024.toInt() else 0x66181C18, 10f)
                    u.icon(if (st.done[q.id]) "ui_ok" else if (q.main) "ui_star" else "ui_info", px + 12f, y + 14f, 40f)
                    u.text(q.title, px + 64f, y + 8f, 23f, if (active) Ui.TEXT else Ui.TEXT_DIM)
                    u.paragraph(q.desc, px + 64f, y + 38f, pw - 240f, 17f, Ui.TEXT_DIM)
                    if (active && q.goal > 1) { sb.setLength(0); sb.append(minOf(hud.displayProgress(q.id), q.goal)).append(" / ").append(q.goal); u.text(sb, px + pw - 20f, y + 12f, 22f, Ui.ACCENT, 2) }
                    if (q.rewardItem >= 0 && !st.done[q.id]) { Items.get(q.rewardItem)?.let { u.icon(it.icon, px + pw - 60f, y + 42f, 36f) }; u.text("награда", px + pw - 68f, y + 52f, 15f, Ui.TEXT_DIM, 2) }
                    y += 96f
                }
                u.unclip()
            }
            1 -> {
                val n = st.noteOrder.size
                listScroll = u.scroll(995, px, ly, pw, lh, n * 64f + 8f, listScroll)
                u.clip(px, ly, pw, lh)
                if (n == 0) u.text("Пока ни одной записи. Ищите ящики экспедиции.", px + 14f, ly + 14f, 20f, Ui.TEXT_DIM)
                for (k in 0 until n) {
                    val y = ly + k * 64f - listScroll
                    val note = StoryData.notes[st.noteOrder[k]]
                    if (u.tapIn(995, px, y, pw, 58f)) { noteTitle = note.title; noteText = note.text; hud.open(Hud.NOTE) }
                    u.rect(px, y, pw, 58f, if (u.hoverIn(995, px, y, pw, 58f)) 0xFF41702E.toInt() else 0xAA243024.toInt(), 10f)
                    u.icon("note", px + 10f, y + 9f, 40f)
                    u.text(note.title, px + 62f, y + 16f, 22f, Ui.TEXT)
                }
                u.unclip()
            }
            2 -> {
                var y = ly + 4f
                for (i in StoryData.achievements.indices) {
                    val a = StoryData.achievements[i]; val got = st.achievements[i]
                    val x = px + (i % 2) * (pw * 0.5f)
                    u.rect(x, y, pw * 0.5f - 8f, 62f, if (got) 0xAA2E4A24.toInt() else 0x66181C18, 10f)
                    u.icon(if (got) "ui_star" else "ui_lock", x + 10f, y + 11f, 40f, if (got) Ui.WHITE else 0x88FFFFFF.toInt())
                    u.text(a.title, x + 60f, y + 8f, 21f, if (got) Ui.TEXT else Ui.TEXT_DIM)
                    u.text(a.desc, x + 60f, y + 34f, 16f, Ui.TEXT_DIM)
                    if (i % 2 == 1) y += 70f
                }
            }
            else -> {
                val p = scene.player
                var y = ly + 10f
                fun row(name: String, v: String) { u.text(name, px + 14f, y, 21f, Ui.TEXT_DIM); u.text(v, px + 420f, y, 21f, Ui.TEXT); y += 34f }
                row("Дней прожито", p.statDaysSurvived.toString()); row("Пройдено", "${p.statDistance.toInt()} м")
                row("Блоков добыто", p.statBlocksMined.toString()); row("Блоков поставлено", p.statBlocksPlaced.toString())
                row("Предметов создано", p.statCrafted.toString()); row("Урожаев собрано", st.harvests.toString())
                row("Животных добыто", p.statAnimalsHunted.toString()); row("Записей найдено", "${st.notesCollected} из ${StoryData.notes.size}")
                row("Смертей", p.statDeaths.toString()); row("Seed мира", scene.seed.toString())
            }
        }
    }

    // ------------------------------------------------------------------ encyclopedia

    private fun encyclopedia() {
        frame("Энциклопедия животных")
        val u = ui
        val st = scene.story
        val cols = 6; val cell = 78f
        val gw = cols * cell
        val all = SpeciesDb.all
        val rows = (all.size + cols - 1) / cols
        listScroll = u.scroll(996, px, py, gw, ph, rows * cell + 8f, listScroll)
        u.rect(px - 6f, py - 4f, gw + 12f, ph + 8f, 0x44101510, 10f)
        u.clip(px, py, gw, ph)
        for (k in all.indices) {
            val sp = all[k]
            val x = px + (k % cols) * cell + 4f; val y = py + (k / cols) * cell + 4f - listScroll
            if (y < py - cell || y > py + ph) continue
            if (u.tapIn(996, x, y, cell - 8f, cell - 8f)) { encSel = k; scene.audio.play("click", 0.4f) }
            val seen = sp.implemented && st.speciesSeen[k] > 0
            u.rect(x, y, cell - 8f, cell - 8f, if (encSel == k) 0xFF41702E.toInt() else if (seen) 0xCC243024.toInt() else 0x88181C18.toInt(), 10f)
            u.icon(sp.icon, x + 7f, y + 7f, cell - 22f, if (seen) Ui.WHITE else if (sp.implemented) 0xFF303830.toInt() else 0x66606860)
        }
        u.unclip()
        val dx = px + gw + 20f; val dw = px + pw - dx
        u.rect(dx, py, dw, ph, 0x55101510, 12f)
        val sp = all[encSel]
        val seen = sp.implemented && st.speciesSeen[encSel] > 0
        u.icon(sp.icon, dx + 14f, py + 12f, 84f, if (seen || !sp.implemented) Ui.WHITE else 0xFF303830.toInt())
        u.paragraph(if (seen || !sp.implemented) sp.name else "Неизвестное животное", dx + 110f, py + 16f, dw - 120f, 26f, Ui.TEXT)
        var cy = py + 110f
        if (!sp.implemented) {
            u.text("В разработке", dx + 110f, py + 72f, 18f, Ui.WARN)
            cy += u.paragraph(sp.description, dx + 14f, cy, dw - 28f, 19f, Ui.TEXT_DIM) + 10f
            u.paragraph("Этот вид запланирован и появится в следующих обновлениях архипелага.", dx + 14f, cy, dw - 28f, 17f, Ui.TEXT_DIM)
            return
        }
        if (!seen) { u.paragraph("Вы ещё не встречали это животное. Подойдите ближе, чтобы описать его.", dx + 14f, cy, dw - 28f, 19f, Ui.TEXT_DIM); return }
        val obs = st.speciesSeen[encSel]
        sb.setLength(0); sb.append("Изучено: ").append(minOf(100, obs / 6)).append('%')
        u.text(sb, dx + 110f, py + 72f, 18f, Ui.ACCENT)
        cy += u.paragraph(sp.description, dx + 14f, cy, dw - 28f, 19f, Ui.TEXT) + 10f
        sb.setLength(0); sb.append("Обитает: ")
        for ((i, b) in sp.biomes.withIndex()) { if (i > 0) sb.append(", "); sb.append(Biome.NAMES[b].lowercase()) }
        cy += u.paragraph(sb, dx + 14f, cy, dw - 28f, 18f, Ui.TEXT_DIM) + 6f
        // deeper facts unlock with observation time
        if (obs > 120) {
            sb.setLength(0); sb.append("Группа: ").append(sp.groupMin).append('–').append(sp.groupMax).append(" особей. ")
            sb.append(if (sp.nocturnal) "Активен ночью. " else "Активен днём, ночью отдыхает. ")
            sb.append(if (sp.predator) "Хищник." else "Травоядное.")
            cy += u.paragraph(sb, dx + 14f, cy, dw - 28f, 18f, Ui.TEXT_DIM) + 6f
        } else cy += u.paragraph("Наблюдайте дольше, чтобы узнать о повадках.", dx + 14f, cy, dw - 28f, 17f, 0xFF8A9488.toInt()) + 6f
        if (obs > 360) {
            sb.setLength(0); sb.append("Скорость бега до ").append(sp.runSpeed.toInt()).append(" м/с. Замечает человека с ").append(sp.senseDistance.toInt()).append(" м")
            sb.append(if (sp.predator) "; огня избегает." else "; пригнувшись, можно подойти вдвое ближе.")
            u.paragraph(sb, dx + 14f, cy, dw - 28f, 18f, Ui.TEXT_DIM)
        }
    }

    // ------------------------------------------------------------------ pause / settings / note / death

    private fun pause() {
        frame("Пауза", 520f, 500f)
        val u = ui
        val bw = pw
        if (u.button(1200, px, py, bw, 62f, "Продолжить", iconName = "ui_play")) hud.close()
        if (u.button(1201, px, py + 74f, bw, 62f, "Сохранить игру", iconName = "ui_save", color = 0xFF30404A.toInt())) { scene.saveGame(true); hud.message("Игра сохранена") ; hud.close() }
        if (u.button(1202, px, py + 148f, bw, 62f, "Настройки", iconName = "ui_settings", color = 0xFF30404A.toInt())) { settingsFromPause = true; hud.open(Hud.SETTINGS) }
        if (u.button(1203, px, py + 222f, bw, 62f, "В главное меню", iconName = "ui_home", color = 0xFF4A3A30.toInt())) { scene.saveGame(true); scene.game.toMenu() }
        sb.setLength(0); sb.append("Seed мира: ").append(scene.seed).append("   Автосохранение каждые 2 мин")
        u.text(sb, px + bw * 0.5f, py + 304f, 16f, Ui.TEXT_DIM, 1)
    }

    private fun settings() {
        frame("Настройки", 900f, 620f)
        drawSettings(scene.game, ui, px, py, pw, 1210) { scene.applyQuality() }
    }

    private fun note() {
        val u = ui
        frame(noteTitle, 860f, 620f)
        u.rect(px - 6f, py - 4f, pw + 12f, ph + 8f, 0xFFE8DCC0.toInt(), 10f)
        val h = u.paragraph(noteText, px + 18f, py + 14f, pw - 36f, 22f, 0xFF2A2218.toInt(), draw = false)
        listScroll = u.scroll(997, px, py, pw, ph, h + 40f, listScroll)
        u.clip(px, py, pw, ph)
        u.paragraph(noteText, px + 18f, py + 14f - listScroll, pw - 36f, 22f, 0xFF2A2218.toInt())
        u.unclip()
    }

    private fun death() {
        val u = ui
        u.rect(0f, 0f, u.vw, u.vh, 0x99400808.toInt())
        frame("Вы погибли", 620f, 380f, closable = false)
        u.icon("ui_skull", px + pw * 0.5f - 44f, py, 88f)
        sb.setLength(0); sb.append("Причина: ").append(scene.player.survival.lastDamageCause.ifEmpty { "неизвестно" })
        u.text(sb, px + pw * 0.5f, py + 104f, 24f, Ui.TEXT, 1)
        u.text("Вы очнётесь у последнего места ночлега. Вещи останутся при вас.", px + pw * 0.5f, py + 142f, 17f, Ui.TEXT_DIM, 1)
        if (u.button(1250, px + 60f, py + 190f, pw - 120f, 62f, "Возродиться", iconName = "ui_heart")) { scene.respawn(); hud.close() }
    }
}

/** Settings controls shared by the pause menu and the main menu. Returns nothing; applies changes immediately. */
fun drawSettings(game: wildfrontier.WildFrontierGame, u: Ui, x: Float, y: Float, w: Float, idBase: Int, onQuality: () -> Unit) {
    val s = game.engine.settings
    var cy = y
    u.text("Графика", x, cy, 20f, Ui.ACCENT); cy += 30f
    val names = arrayOf("Низкая", "Средняя", "Высокая")
    for (i in 0..2) {
        val q = Quality.values()[i]
        if (u.button(idBase + i, x + i * 190f, cy, 182f, 50f, names[i], color = if (s.quality == q) Ui.ACCENT_DARK else 0xFF2E3A30.toInt(), size = 21f) && s.quality != q) {
            s.quality = q; s.qualityChosenByUser = true; s.effectiveQuality = q; s.save(); onQuality()
        }
    }
    if (u.button(idBase + 3, x + 3 * 190f, cy, 182f, 50f, "Авто", color = if (!s.qualityChosenByUser) Ui.ACCENT_DARK else 0xFF2E3A30.toInt(), size = 21f) && s.qualityChosenByUser) {
        s.qualityChosenByUser = false
        s.quality = wildcore.core.Settings.detect(game.engine.platform.deviceInfo, game.engine.caps.renderer); s.effectiveQuality = s.quality; s.save(); onQuality()
    }
    cy += 62f
    val pr = s.profile
    val sbl = StringBuilder().append("Дальность ").append(pr.viewDistance * 16).append(" м · рендер ").append((pr.renderScale * 100).toInt()).append("% · тени ")
        .append(if (pr.shadowMapSize > 0) pr.shadowMapSize.toString() else "выкл").append(" · текстуры ").append(pr.textureSize).append(" · цель ").append(pr.targetFps).append(" FPS")
    u.text(sbl, x, cy, 16f, Ui.TEXT_DIM); cy += 34f

    fun toggle(id: Int, label: String, value: Boolean, col: Int): Boolean {
        val bx = x + col * (w * 0.5f)
        val clicked = u.button(id, bx, cy, 74f, 42f, if (value) "Вкл" else "Выкл", color = if (value) Ui.ACCENT_DARK else 0xFF3A3030.toInt(), size = 19f)
        u.text(label, bx + 86f, cy + 9f, 20f, Ui.TEXT)
        return if (clicked) !value else value
    }
    var v = toggle(idBase + 10, "Счётчик производительности", s.showProfiler, 0); if (v != s.showProfiler) { s.showProfiler = v; s.save() }
    v = toggle(idBase + 11, "Автопрыжок", s.autoJump, 1); if (v != s.autoJump) { s.autoJump = v; s.save() }
    cy += 52f
    v = toggle(idBase + 12, "Инверсия камеры по вертикали", s.invertY, 0); if (v != s.invertY) { s.invertY = v; s.save() }
    v = toggle(idBase + 13, "Снижать нагрузку при нагреве", s.thermalThrottle, 1); if (v != s.thermalThrottle) { s.thermalThrottle = v; s.save() }
    cy += 52f
    v = toggle(idBase + 14, "Ограничить 30 FPS (экономия батареи)", s.fpsLimit == 30, 0); if (v != (s.fpsLimit == 30)) { s.fpsLimit = if (v) 30 else 0; s.save(); game.applyFrameRate() }
    cy += 60f

    fun slider(id: Int, label: String, value: Float, min: Float, max: Float): Float {
        u.text(label, x, cy + 10f, 20f, Ui.TEXT)
        val nv = u.slider(id, x + 330f, cy, w - 430f, (value - min) / (max - min)) * (max - min) + min
        val pct = StringBuilder().append((nv * 100f).toInt()).append('%')
        u.text(pct, x + w, cy + 10f, 20f, Ui.TEXT_DIM, 2)
        cy += 54f
        return nv
    }
    var f = slider(idBase + 20, "Чувствительность камеры", s.lookSensitivity, 0.3f, 2.5f); if (f != s.lookSensitivity) { s.lookSensitivity = f }
    f = slider(idBase + 21, "Громкость звуков", s.sfxVolume, 0f, 1f); if (f != s.sfxVolume) { s.sfxVolume = f; game.audio.sfxVolume = f }
    f = slider(idBase + 22, "Громкость музыки", s.musicVolume, 0f, 1f); if (f != s.musicVolume) { s.musicVolume = f; game.audio.musicVolume = f }
}
