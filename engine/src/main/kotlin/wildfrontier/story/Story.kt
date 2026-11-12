package wildfrontier.story

import wildcore.math.Hash
import wildfrontier.GameScene
import wildfrontier.animals.SpeciesDb
import wildfrontier.content.B
import wildfrontier.content.I
import wildfrontier.gen.Biome
import wildfrontier.gen.Site
import java.io.DataInputStream
import java.io.DataOutputStream

/**
 * Narrative state: quest progress, collected notes, discovered locations/biomes, the animal
 * encyclopedia, achievements and expedition crate loot. Gameplay systems report events here.
 */
class Story(private val scene: GameScene) {
    val progress = IntArray(StoryData.quests.size)
    val done = BooleanArray(StoryData.quests.size)
    val notes = BooleanArray(StoryData.notes.size)
    val noteOrder = ArrayList<Int>()
    val biomesSeen = BooleanArray(Biome.COUNT)
    val speciesSeen = IntArray(SpeciesDb.all.size)      // observation counter per species
    val achievements = BooleanArray(StoryData.achievements.size)
    val sites = ArrayList<Site>()                        // discovered or map-revealed locations
    private val siteVisited = HashSet<Int>()
    private val siteFlags = HashMap<Int, Int>()
    private val lootedCrates = HashSet<Long>()
    var harvests = 0
    var finished = false
    private var checkTimer = 0f

    /** The main quest currently being pursued, or -1 when the story is complete. */
    val activeMain: Int get() { for (q in StoryData.quests) if (q.main && !done[q.id]) return q.id; return -1 }
    fun isActive(q: Int): Boolean = !done[q] && (!StoryData.quests[q].main || activeMain == q)
    val notesCollected: Int get() = noteOrder.size

    private fun advance(q: Int, value: Int, absolute: Boolean = false) {
        if (done[q]) return
        if (StoryData.quests[q].main && activeMain != q && !absolute) return
        progress[q] = if (absolute) maxOf(progress[q], value) else progress[q] + value
        if (progress[q] >= StoryData.quests[q].goal && isActive(q)) complete(q)
    }

    private fun complete(q: Int) {
        val quest = StoryData.quests[q]
        done[q] = true
        progress[q] = quest.goal
        scene.audio.play("quest")
        scene.hud.banner("Задание выполнено", quest.title)
        if (quest.rewardItem >= 0) scene.give(quest.rewardItem, quest.rewardCount)
        // a quest that became active may already be satisfied (e.g. tools crafted early)
        val next = activeMain
        if (next >= 0 && progress[next] >= StoryData.quests[next].goal) complete(next)
    }

    // ------------------------------------------------------------------ events

    fun onItemGained(id: Int, n: Int) {
        if (B.isLog(id)) advance(0, n)
        if (id == I.CRYSTAL) advance(6, n, false)
    }

    fun onCrafted(id: Int) {
        if (id == I.STONE_AXE) advance(1, progress[1] or 1, true).also { progress[1] = progress[1] or 1 }
        if (id == I.STONE_PICKAXE) progress[1] = progress[1] or 2
        if (!done[1] && activeMain == 1 && (progress[1] and 3) == 3) { progress[1] = 2; complete(1) }
        if (id == I.IRON_INGOT) advance(13, 1)
    }

    fun onBlockPlaced(id: Int) {
        advance(12, 1)
        if (id == B.CAMPFIRE) progress[2] = progress[2] or 1
        if (id == B.BEDROLL) progress[2] = progress[2] or 2
        if (!done[2] && activeMain == 2 && (progress[2] and 3) == 3) { progress[2] = 2; complete(2) }
    }

    fun onHunt(species: Int) = advance(8, 1)
    fun onHarvest() { harvests++; advance(9, 1) }

    fun onAnimalSeen(species: Int, dist: Float) {
        if (dist > 20f) return
        if (speciesSeen[species] == 0) {
            speciesSeen[species] = 1
            val sp = SpeciesDb.get(species)
            scene.hud.banner("Новая запись в энциклопедии", sp.name)
            scene.audio.play("note")
            var n = 0
            for (i in 0 until 3) if (speciesSeen[i] > 0) n++
            advance(11, n, true)
        } else if (speciesSeen[species] < 600) speciesSeen[species]++
    }

    private fun discover(s: Site) {
        if (!siteVisited.add(s.id)) return
        if (sites.none { it.id == s.id }) sites.add(s)
        scene.hud.banner("Обнаружено", Site.NAMES[s.type])
        scene.audio.play("quest", 0.6f, 1.2f)
        when (s.type) {
            Site.CAMP, Site.CABIN, Site.TOWER -> advance(3, 1)
            Site.STATION -> { advance(3, 1); advance(4, 1, true) }
            Site.BUNKER -> { advance(3, 1); advance(5, 0) }
        }
        if (s.type == Site.STATION && !done[4]) { progress[4] = 1; if (activeMain == 4) complete(4) }
    }

    /** Reveals the nearest location the player has not yet found (map fragment). */
    fun revealNearestSite(): Site? {
        val tmp = ArrayList<Site>()
        scene.gen.structures.sitesNear(scene.player.pos.x.toInt(), scene.player.pos.z.toInt(), 4, tmp)
        var best: Site? = null; var bd = Float.MAX_VALUE
        for (s in tmp) {
            if (sites.any { it.id == s.id }) continue
            val dx = s.x - scene.player.pos.x; val dz = s.z - scene.player.pos.z
            val d = dx * dx + dz * dz
            if (d < bd) { bd = d; best = s }
        }
        best?.let { sites.add(it) }
        return best
    }

    fun update(dt: Float, biome: Int) {
        checkTimer -= dt
        if (checkTimer > 0f) return
        checkTimer = 1f
        val p = scene.player
        if (biome in 0 until Biome.COUNT && !biomesSeen[biome]) {
            biomesSeen[biome] = true
            var n = 0; for (b in biomesSeen) if (b) n++
            advance(10, n, true)
            if (biome != Biome.OCEAN) scene.hud.banner("Новая территория", Biome.NAMES[biome])
            if (biome == Biome.GROVE) unlock(8)
        }
        scene.gen.structures.siteAt(p.pos.x.toInt(), p.pos.z.toInt(), 6)?.let { discover(it) }
        if (p.statDaysSurvived >= 1) unlock(0)
        if (p.statDaysSurvived >= 7) unlock(1)
        if (p.statBlocksMined >= 100) unlock(2)
        if (p.statBlocksPlaced >= 200) unlock(3)
        if (p.statCrafted >= 25) unlock(4)
        if (p.statDistance >= 5000f) unlock(5)
        if (notesCollected >= 6) unlock(6)
        if (harvests >= 20) unlock(7)
        if (finished) unlock(9)
    }

    private fun unlock(a: Int) {
        if (achievements[a]) return
        achievements[a] = true
        scene.hud.banner("Достижение", StoryData.achievements[a].title)
        scene.audio.play("quest", 0.7f, 1.35f)
    }

    private fun giveNote(n: Int): Boolean {
        if (notes[n]) return false
        notes[n] = true
        noteOrder.add(n)
        scene.audio.play("note")
        scene.hud.openNote(n)
        return true
    }

    // ------------------------------------------------------------------ crates & terminals

    private fun noteForSite(s: Site, second: Boolean): Int = when (s.type) {
        Site.WRECK -> 0
        Site.CAMP -> if (s.variant % 2 == 0) 1 else 2
        Site.CABIN -> if (s.variant % 2 == 0) 3 else 4
        Site.TOWER -> 5
        Site.STATION -> if (second) 8 else if (s.variant % 3 == 2) 11 else if (s.variant % 3 == 0) 6 else 7
        else -> if (second) 10 else 9
    }

    /** Opens an expedition crate: gives its supplies once, plus the site's story items. Returns false if already empty. */
    fun openCrate(x: Int, y: Int, z: Int): Boolean {
        val key = (x.toLong() and 0x3FFFFFF) or ((z.toLong() and 0x3FFFFFF) shl 26) or (y.toLong() shl 52)
        if (!lootedCrates.add(key)) return false
        val s = scene.gen.structures.siteAt(x, z, 3)
        val h = Hash.hash3(x, y, z, 1234)
        val type = s?.type ?: Site.CAMP
        var flags = if (s != null) siteFlags[s.id] ?: 0 else 0
        when (type) {
            Site.WRECK -> if (flags and 8 == 0) { scene.give(I.BREAD, 2); scene.give(I.APPLE, 3); scene.give(I.WATERSKIN_FULL, 1); scene.give(B.TORCH, 4); flags = flags or 8 }
                          else { scene.give(I.ROPE, 2); scene.give(I.CLOTH, 2); scene.give(I.STICK, 4) }
            Site.CAMP -> { scene.give(I.COAL, 2 + (h and 1)); scene.give(I.COOKED_MEAT, 1 + (h shr 1 and 1)); scene.give(I.FLINT, 2); if (h and 12 == 0) scene.give(I.FIBER_SHIRT, 1) }
            Site.CABIN -> { scene.give(I.WHEAT_SEEDS, 6); scene.give(I.CARROT, 3); scene.give(I.BREAD, 1); if (h and 4 == 0) scene.give(I.HOE, 1)
                if (flags and 4 == 0 && (h and 3) == 0) { scene.give(I.KEYCARD, 1); flags = flags or 4 } }
            Site.TOWER -> { scene.give(I.ARROW, 8); scene.give(B.TORCH, 4); scene.give(I.MAP_FRAGMENT, 1); if (h and 1 == 0) scene.give(I.BOW, 1)
                if (flags and 4 == 0) { scene.give(I.KEYCARD, 1); flags = flags or 4 } }
            Site.STATION -> { scene.give(I.COPPER_INGOT, 2 + (h and 1)); scene.give(B.GLASS, 4); if (h and 2 == 0) scene.give(I.IRON_INGOT, 2)
                if (flags and 2 == 0) { scene.give(I.RADIO_PART, 1); flags = flags or 2 } }
            else -> { scene.give(I.CRYSTAL, 1); scene.give(I.IRON_INGOT, 2)
                if (flags and 2 == 0) { scene.give(I.RADIO_PART, 1); flags = flags or 2 }
                if (flags and 8 == 0) { scene.give(I.IRON_PICKAXE, 1); flags = flags or 8 } }
        }
        if (s != null) {
            if (flags and 1 == 0) { if (giveNote(noteForSite(s, false))) flags = flags or 1 }
            siteFlags[s.id] = flags
        }
        return true
    }

    /** Uses a research terminal. Returns a message for the HUD when nothing else happened. */
    fun useTerminal(x: Int, z: Int): String? {
        val s = scene.gen.structures.siteAt(x, z, 3) ?: return "Терминал не отвечает."
        val inv = scene.player.inventory
        if (s.type == Site.BUNKER) {
            if (inv.count(I.KEYCARD) == 0) return "Доступ закрыт. Нужна ключ-карта."
            if (!done[5]) { progress[5] = 1; if (activeMain == 5) complete(5) }
            if (!giveNote(10)) scene.hud.openNote(10)
            return null
        }
        if (inv.count(I.RADIO_PART) >= 3 && !finished) {
            inv.remove(I.RADIO_PART, 3)
            finished = true
            progress[7] = 1
            if (activeMain == 7) complete(7) else done[7] = true
            scene.audio.play("quest")
            scene.hud.openText("Сигнал", StoryData.ENDING)
            return null
        }
        if (!giveNote(8)) {
            val have = inv.count(I.RADIO_PART)
            return if (finished) "Передатчик работает. Сигнал уходит в эфир." else "Передатчик неисправен. Деталей радиостанции: $have из 3."
        }
        return null
    }

    // ------------------------------------------------------------------ persistence

    fun save(o: DataOutputStream) {
        o.writeInt(progress.size); for (i in progress.indices) { o.writeInt(progress[i]); o.writeBoolean(done[i]) }
        o.writeInt(noteOrder.size); for (n in noteOrder) o.writeInt(n)
        o.writeInt(biomesSeen.size); for (b in biomesSeen) o.writeBoolean(b)
        o.writeInt(speciesSeen.size); for (v in speciesSeen) o.writeInt(v)
        o.writeInt(achievements.size); for (b in achievements) o.writeBoolean(b)
        o.writeInt(sites.size); for (s in sites) { o.writeInt(s.id); o.writeInt(s.type); o.writeInt(s.x); o.writeInt(s.y); o.writeInt(s.z); o.writeInt(s.radius); o.writeInt(s.variant); o.writeBoolean(siteVisited.contains(s.id)) }
        o.writeInt(siteFlags.size); for ((k, v) in siteFlags) { o.writeInt(k); o.writeInt(v) }
        o.writeInt(lootedCrates.size); for (k in lootedCrates) o.writeLong(k)
        o.writeInt(harvests); o.writeBoolean(finished)
    }

    fun load(i: DataInputStream) {
        var n = i.readInt(); for (k in 0 until n) { val p = i.readInt(); val d = i.readBoolean(); if (k < progress.size) { progress[k] = p; done[k] = d } }
        n = i.readInt(); noteOrder.clear(); for (k in 0 until n) { val v = i.readInt(); if (v in notes.indices) { noteOrder.add(v); notes[v] = true } }
        n = i.readInt(); for (k in 0 until n) { val b = i.readBoolean(); if (k < biomesSeen.size) biomesSeen[k] = b }
        n = i.readInt(); for (k in 0 until n) { val v = i.readInt(); if (k < speciesSeen.size) speciesSeen[k] = v }
        n = i.readInt(); for (k in 0 until n) { val b = i.readBoolean(); if (k < achievements.size) achievements[k] = b }
        n = i.readInt(); sites.clear(); siteVisited.clear()
        for (k in 0 until n) { val s = Site(i.readInt(), i.readInt(), i.readInt(), i.readInt(), i.readInt(), i.readInt(), i.readInt()); sites.add(s); if (i.readBoolean()) siteVisited.add(s.id) }
        n = i.readInt(); siteFlags.clear(); for (k in 0 until n) siteFlags[i.readInt()] = i.readInt()
        n = i.readInt(); lootedCrates.clear(); for (k in 0 until n) lootedCrates.add(i.readLong())
        harvests = i.readInt(); finished = i.readBoolean()
    }
}
