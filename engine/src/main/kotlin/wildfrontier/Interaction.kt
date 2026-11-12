package wildfrontier

import wildcore.ecs.ComponentStore
import wildcore.math.Vec3
import wildcore.math.floorInt
import wildcore.physics.RayHit
import wildcore.physics.VoxelPhysics
import wildcore.world.BlockDef
import wildcore.world.Blocks
import wildcore.world.Shape
import wildcore.world.ToolKind
import wildfrontier.content.B
import wildfrontier.content.I
import wildfrontier.content.Inventory
import wildfrontier.content.ItemDef
import wildfrontier.content.Items
import wildfrontier.content.Station
import wildfrontier.gen.WorldGen
import wildfrontier.player.Player
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt

/** A flying arrow (ECS component). */
class Arrow { val pos = Vec3(); val vel = Vec3(); var life = 6f }

/** A log raft floating on water (ECS component). */
class Raft { val pos = Vec3(); var yaw = 0f; var speed = 0f }

/**
 * Everything the player does to the world with the three action buttons:
 * break / attack, place / use held item, and interact with the targeted block or object.
 */
class Interaction(private val scene: GameScene) {
    val hit = RayHit()
    private val waterHit = RayHit()
    var hasTarget = false; private set
    var targetAnimal = -1; private set
    var targetRaft = -1; private set
    var breakProgress = 0f; private set
    private var breakX = 0; private var breakY = 0; private var breakZ = 0
    private var hitSoundTimer = 0f
    private var attackCooldown = 0f
    /** Placement orientation for logs: 0 = automatic from the face, 1..3 = forced axis X, Y, Z. */
    var rotateMode = 0
    var fishing = 0f; private set
    private var fishingTotal = 0f
    val arrows: ComponentStore<Arrow> = scene.ecs.store()
    val rafts: ComponentStore<Raft> = scene.ecs.store()
    private val dir = Vec3()
    private val origin = Vec3()
    private val rng get() = scene.particles.rng

    // ------------------------------------------------------------------ targeting

    fun updateTarget() {
        val p = scene.player
        val cam = scene.renderer.camera
        p.aimDirection(dir)
        // start the ray beside the player's head so third-person aiming cannot hit things behind them
        val t0 = maxOf(0f, (p.eye.x - cam.pos.x) * dir.x + (p.eye.y - cam.pos.y) * dir.y + (p.eye.z - cam.pos.z) * dir.z)
        origin.set(cam.pos.x + dir.x * t0, cam.pos.y + dir.y * t0, cam.pos.z + dir.z * t0)
        hasTarget = VoxelPhysics.raycast(scene.world, origin.x, origin.y, origin.z, dir.x, dir.y, dir.z, Player.REACH, hit)
        val reach = if (hasTarget) hit.distance else Player.REACH
        targetAnimal = scene.animals.raycast(origin.x, origin.y, origin.z, dir.x, dir.y, dir.z, minOf(reach, meleeReach()))
        targetRaft = -1
        rafts.each(scene.ecs.highWater) { id, r ->
            val cx = r.pos.x - origin.x; val cy = r.pos.y + 0.2f - origin.y; val cz = r.pos.z - origin.z
            val t = cx * dir.x + cy * dir.y + cz * dir.z
            if (t > 0f && t < reach) {
                val px = cx - dir.x * t; val py = cy - dir.y * t; val pz = cz - dir.z * t
                if (px * px + py * py + pz * pz < 1.3f) targetRaft = id
            }
        }
        val r = scene.renderer
        r.highlightActive = hasTarget && targetAnimal < 0 && !scene.hud.modalOpen
        if (hasTarget) {
            r.highlightX = hit.x; r.highlightY = hit.y; r.highlightZ = hit.z
            val def = Blocks.get(hit.block)
            r.highlightHeight = if (def.shape == Shape.BOX || def.shape == Shape.CROSS) def.boxMaxY else 1f
            r.breakProgress = if (hit.x == breakX && hit.y == breakY && hit.z == breakZ) breakProgress else 0f
        }
    }

    private fun meleeReach(): Float = if (scene.player.heldItem.id == I.SPEAR) 4.2f else 3.2f

    private fun heldDef(): ItemDef? { val s = scene.player.heldItem; return if (s.isEmpty) null else Items.get(s.id) }

    // ------------------------------------------------------------------ breaking / attacking

    fun breakTime(def: BlockDef): Float {
        if (def.hardness < 0f) return -1f
        val tool = heldDef()
        var mult = 1f
        if (tool != null && tool.toolKind != ToolKind.NONE && tool.toolKind == def.tool) mult = 1.6f + tool.toolTier * 1.5f
        var t = def.hardness / mult
        if (!canHarvest(def)) t *= 2.4f else if (def.requiredTier == 1 && mult == 1f) t *= 2.0f
        return t / scene.player.survival.workFactor
    }

    /** Tier-1 blocks (stone, coal, copper) can be worked loose by hand, slowly; higher tiers need the right tool. */
    fun canHarvest(def: BlockDef): Boolean {
        if (def.requiredTier <= 1) return true
        val tool = heldDef() ?: return false
        return tool.toolKind == def.tool && tool.toolTier >= def.requiredTier
    }

    /** Call every frame with the state of the break button. */
    fun updateBreak(dt: Float, held: Boolean, pressed: Boolean) {
        val p = scene.player
        if (attackCooldown > 0f) attackCooldown -= dt
        if (fishing > 0f) updateFishing(dt)
        if (p.dead) { breakProgress = 0f; return }
        if (pressed && (targetAnimal >= 0 || targetRaft >= 0)) { attack(); return }
        if (!held || !hasTarget || targetAnimal >= 0) { breakProgress = 0f; return }
        if (hit.x != breakX || hit.y != breakY || hit.z != breakZ) { breakX = hit.x; breakY = hit.y; breakZ = hit.z; breakProgress = 0f }
        val def = Blocks.get(hit.block)
        val time = breakTime(def)
        if (time < 0f) { breakProgress = 0f; return }
        breakProgress += dt / maxOf(0.05f, time)
        if (p.swingTime <= 0f) { p.swingTime = 0.36f; scene.onPlayerSwing() }
        hitSoundTimer -= dt
        if (hitSoundTimer <= 0f) {
            hitSoundTimer = 0.26f
            scene.audio.blockSound(def.sound, false, hit.x + 0.5f, hit.y + 0.5f, hit.z + 0.5f)
            scene.particles.blockBurst(hit.x + 0.5f + hit.nx * 0.5f, hit.y + 0.5f + hit.ny * 0.5f, hit.z + 0.5f + hit.nz * 0.5f, def.texSide, 2, 0.2f)
        }
        if (breakProgress >= 1f) {
            breakProgress = 0f
            breakBlock(hit.x, hit.y, hit.z, true)
            useDurability(1)
        }
    }

    private fun useDurability(n: Int) {
        val s = scene.player.heldItem
        val def = heldDef() ?: return
        if (def.durability <= 0) return
        s.durability -= n
        if (s.durability <= 0) {
            s.clear()
            scene.player.inventory.touch()
            scene.audio.play("break_wood", 0.8f, 1.3f)
            scene.hud.message("${def.name}: инструмент сломался")
        }
    }

    /** Removes a block, spawning drops, particles and sound. [byPlayer] controls stats and harvest rules. */
    fun breakBlock(x: Int, y: Int, z: Int, byPlayer: Boolean) {
        val w = scene.world
        val id = w.getBlock(x, y, z)
        if (id == B.AIR || id == B.BEDROCK || Blocks.liquid[id]) return
        val def = Blocks.get(id)
        val harvest = !byPlayer || canHarvest(def)
        if (id == B.CHEST) (w.getBlockData(x, y, z) as? Inventory)?.let { inv -> for (s in inv.slots) if (!s.isEmpty) scene.drops.spawn(s.id, s.count, x + 0.5f, y + 0.5f, z + 0.5f, s.durability) }
        if (id == B.CRATE) scene.story.openCrate(x, y, z)
        // dug-out spaces next to water at or below sea level flood
        var flood = false
        if (y < WorldGen.SEA) {
            flood = Blocks.liquid[w.getBlock(x + 1, y, z)] || Blocks.liquid[w.getBlock(x - 1, y, z)] || Blocks.liquid[w.getBlock(x, y, z + 1)] ||
                    Blocks.liquid[w.getBlock(x, y, z - 1)] || Blocks.liquid[w.getBlock(x, y + 1, z)]
        }
        w.setBlock(x, y, z, if (flood) B.WATER else B.AIR)
        if (harvest) spawnDrops(id, def, x, y, z)
        scene.audio.blockSound(def.sound, true, x + 0.5f, y + 0.5f, z + 0.5f)
        scene.particles.blockBurst(x + 0.5f, y + 0.5f, z + 0.5f, def.texSide, if (def.shape == Shape.CROSS) 5 else 12)
        if (byPlayer) {
            scene.player.statBlocksMined++
            if ((id == B.WHEAT_3 || id == B.CARROT_3)) scene.story.onHarvest()
        }
        // unsupported plants and torches above fall off
        val above = w.getBlock(x, y + 1, z)
        if (above != B.AIR && Blocks.get(above).needsSupport) breakBlock(x, y + 1, z, false)
    }

    private fun spawnDrops(id: Int, def: BlockDef, x: Int, y: Int, z: Int) {
        val cx = x + 0.5f; val cy = y + 0.45f; val cz = z + 0.5f
        val d = scene.drops
        val r = rng.nextFloat()
        when {
            id == B.GRAVEL -> { d.spawn(B.GRAVEL, 1, cx, cy, cz); if (r < 0.28f) d.spawn(I.FLINT, 1, cx, cy, cz) }
            id == B.TALL_GRASS -> { if (r < 0.6f) d.spawn(I.PLANT_FIBER, 1, cx, cy, cz); if (r > 0.86f) d.spawn(I.WHEAT_SEEDS, 1, cx, cy, cz) }
            id == B.FERN -> { if (r < 0.45f) d.spawn(I.PLANT_FIBER, 1, cx, cy, cz) }
            id == B.REEDS -> d.spawn(I.PLANT_FIBER, 1 + rng.nextInt(2), cx, cy, cz)
            id == B.PALM_LEAVES -> { if (r < 0.5f) d.spawn(I.PLANT_FIBER, 1, cx, cy, cz); if (r > 0.86f) d.spawn(I.COCONUT, 1, cx, cy, cz) }
            id == B.FRUIT_LEAVES -> d.spawn(I.APPLE, 1 + rng.nextInt(2), cx, cy, cz)
            B.isLeaves(id) -> { if (r < 0.22f) d.spawn(I.STICK, 1, cx, cy, cz) else if (r < 0.30f && id != B.JUNGLE_LEAVES) d.spawn(B.SAPLING, 1, cx, cy, cz) else if (id == B.JUNGLE_LEAVES && r < 0.5f) d.spawn(I.PLANT_FIBER, 1, cx, cy, cz) }
            id == B.BERRY_BUSH -> { d.spawn(I.BERRIES, 2 + rng.nextInt(3), cx, cy, cz); d.spawn(I.STICK, 1, cx, cy, cz) }
            id == B.WHEAT_3 -> { d.spawn(I.WHEAT, 1 + rng.nextInt(2), cx, cy, cz); d.spawn(I.WHEAT_SEEDS, 1 + rng.nextInt(2), cx, cy, cz) }
            id in B.WHEAT_0 until B.WHEAT_3 -> d.spawn(I.WHEAT_SEEDS, 1, cx, cy, cz)
            id == B.CARROT_3 -> d.spawn(I.CARROT, 2 + rng.nextInt(2), cx, cy, cz)
            id in B.CARROT_0 until B.CARROT_3 -> d.spawn(I.CARROT, 1, cx, cy, cz)
            id == B.CRATE -> d.spawn(B.PLANKS_PINE, 2, cx, cy, cz)
            id == B.FARMLAND_WET -> d.spawn(B.DIRT, 1, cx, cy, cz)
            def.dropItem >= 0 -> {
                val n = def.dropMin + (if (def.dropMax > def.dropMin) rng.nextInt(def.dropMax - def.dropMin + 1) else 0)
                if (n > 0) d.spawn(def.dropItem, n, cx, cy, cz)
            }
        }
    }

    private fun attack() {
        val p = scene.player
        if (attackCooldown > 0f) return
        attackCooldown = 0.5f
        p.swingTime = 0.36f
        scene.onPlayerSwing()
        if (targetAnimal >= 0) {
            val a = scene.animals.store[targetAnimal] ?: return
            val dmg = (heldDef()?.damage ?: 1f) + 1f
            scene.animals.damage(targetAnimal, a, dmg, p.pos.x, p.pos.z, true)
            scene.particles.puff(a.body.pos.x, a.body.pos.y + a.species.collisionHeight * 0.6f, a.body.pos.z, 5, 0xAA8A2018.toInt(), 0.09f)
            useDurability(1)
        } else if (targetRaft >= 0 && p.onRaft != targetRaft) {
            val r = rafts[targetRaft] ?: return
            scene.ecs.destroy(targetRaft)
            scene.drops.spawn(I.RAFT, 1, r.pos.x, r.pos.y + 0.5f, r.pos.z)
            scene.audio.playAt("break_wood", r.pos.x, r.pos.y, r.pos.z)
        }
    }

    // ------------------------------------------------------------------ place / use

    /** The place/use button. */
    fun use() {
        val p = scene.player
        if (p.dead) return
        val stack = p.heldItem
        val def = heldDef()
        if (def == null) { if (hasTarget) interact(); return }
        val w = scene.world
        when {
            def.id == I.HOE && hasTarget -> if (scene.farming.till(hit.x, hit.y, hit.z)) { swing(); useDurability(1); scene.audio.playAt("break_dirt", hit.x + 0.5f, hit.y + 1f, hit.z + 0.5f, 0.8f) }
            (def.id == I.WHEAT_SEEDS || def.id == I.CARROT) && hasTarget && (hit.block == B.FARMLAND || hit.block == B.FARMLAND_WET) -> {
                if (scene.farming.plant(hit.x, hit.y, hit.z, if (def.id == I.CARROT) B.CARROT_0 else B.WHEAT_0)) { consume(1); swing(); scene.audio.playAt("place", hit.x + 0.5f, hit.y + 1f, hit.z + 0.5f, 0.6f, 1.4f) }
            }
            def.id == I.BUCKET || def.id == I.WATERSKIN -> {
                if (aimAtWater(4.5f)) { stack.set(if (def.id == I.BUCKET) I.BUCKET_WATER else I.WATERSKIN_FULL, 1); p.inventory.touch(); scene.audio.play("splash", 0.5f, 1.3f); swing() }
                else scene.hud.message("Нужно смотреть на воду")
            }
            def.id == I.BUCKET_WATER && hasTarget -> {
                val n = scene.farming.water(hit.x, hit.y, hit.z)
                if (n == 0) {
                    val px = hit.placeX; val py = hit.placeY; val pz = hit.placeZ
                    if (w.getBlock(px, py, pz) == B.AIR || Blocks.get(w.getBlock(px, py, pz)).replaceable) w.setBlock(px, py, pz, B.WATER)
                }
                stack.set(I.BUCKET, 1); p.inventory.touch(); scene.audio.play("splash", 0.6f, 1.1f); swing()
                scene.particles.puff(hit.x + 0.5f, hit.y + 1.1f, hit.z + 0.5f, 8, 0xAA7FB4E0.toInt(), 0.1f)
            }
            def.id == I.RAFT -> if (aimAtWater(6f)) {
                val r = Raft(); r.pos.set(waterHit.x + 0.5f, WorldGen.SEA - 0.2f, waterHit.z + 0.5f); r.yaw = p.modelYaw
                rafts[scene.ecs.create()] = r
                consume(1); scene.audio.play("splash", 0.8f, 0.8f)
            } else scene.hud.message("Плот спускают на воду")
            def.id == I.BOW -> shoot()
            def.id == I.FISHING_ROD -> startFishing()
            def.id == I.MAP_FRAGMENT -> {
                val s = scene.story.revealNearestSite()
                if (s != null) { consume(1); scene.audio.play("note"); scene.hud.message("На карте отмечено: ${wildfrontier.gen.Site.NAMES[s.type]}") }
                else scene.hud.message("Поблизости больше нечего отмечать")
            }
            def.equipSlot >= 0 -> { equip(p.selected); scene.audio.play("click") }
            def.food > 0f || def.water > 0f -> eat(def)
            def.placesBlock >= 0 -> if (hasTarget) place(def.placesBlock)
            else -> if (hasTarget) interact()
        }
    }

    private fun swing() { scene.player.swingTime = 0.36f; scene.onPlayerSwing() }

    private fun consume(n: Int) {
        val s = scene.player.heldItem
        s.count -= n
        if (s.count <= 0) s.clear()
        scene.player.inventory.touch()
    }

    fun eat(def: ItemDef) {
        val p = scene.player
        val sv = p.survival
        if (def.food > 0f && sv.hunger > 96f && def.water <= 0f) { scene.hud.message("Вы не голодны"); return }
        if (def.food <= 0f && sv.thirst > 96f) { scene.hud.message("Пить не хочется"); return }
        sv.eat(def.food, def.water, def.heal)
        scene.audio.play(if (def.food > 0f) "eat" else "drink")
        if (def.id == I.WATERSKIN_FULL) { p.heldItem.set(I.WATERSKIN, 1); p.inventory.touch() } else consume(1)
    }

    fun equip(slot: Int) {
        val p = scene.player
        val s = p.inventory.slots[slot]
        val def = Items.get(s.id) ?: return
        if (def.equipSlot < 0) return
        val e = p.equipment.slots[def.equipSlot]
        val oldId = e.id; val oldCount = e.count; val oldDur = e.durability
        e.set(s)
        if (oldCount > 0) s.set(oldId, oldCount, oldDur) else s.clear()
        p.inventory.touch(); p.equipment.touch()
        scene.applyBackpack()
    }

    private fun aimAtWater(reach: Float): Boolean =
        VoxelPhysics.raycast(scene.world, origin.x, origin.y, origin.z, dir.x, dir.y, dir.z, reach, waterHit, hitLiquid = true) && Blocks.liquid[waterHit.block]

    private fun place(block: Int) {
        val p = scene.player
        val w = scene.world
        var x = hit.placeX; var y = hit.placeY; var z = hit.placeZ
        if (Blocks.get(hit.block).replaceable) { x = hit.x; y = hit.y; z = hit.z }
        if (y !in 1 until wildcore.world.Chunk.HEIGHT - 1) return
        val cur = w.getBlock(x, y, z)
        if (cur != B.AIR && !Blocks.get(cur).replaceable) return
        var id = block
        val def = Blocks.get(id)
        if (def.needsSupport) {
            val below = w.getBlock(x, y - 1, z)
            if (!Blocks.opaque[below]) { scene.hud.message("Нужна опора снизу"); return }
            if (def.shape == Shape.CROSS && id != B.TORCH && !B.isSoil(below) && below != B.SAND) { scene.hud.message("Здесь это не приживётся"); return }
        }
        if (def.solid) {
            // do not entomb the player
            val b = p.body
            val top = if (def.shape == Shape.BOX) def.boxMaxY else 1f
            if (b.pos.x + b.halfWidth > x && b.pos.x - b.halfWidth < x + 1 && b.pos.z + b.halfWidth > z && b.pos.z - b.halfWidth < z + 1 &&
                b.pos.y + b.height > y && b.pos.y < y + top) return
        }
        // logs lie along the axis of the face they are attached to (or the forced rotation)
        val axis = if (rotateMode != 0) rotateMode - 1 else if (hit.nx != 0) 0 else if (hit.nz != 0) 2 else 1
        id = when (id) {
            B.OAK_LOG -> if (axis == 0) B.OAK_LOG_X else if (axis == 2) B.OAK_LOG_Z else id
            B.PINE_LOG -> if (axis == 0) B.PINE_LOG_X else if (axis == 2) B.PINE_LOG_Z else id
            B.BIRCH_LOG -> if (axis == 0) B.BIRCH_LOG_X else if (axis == 2) B.BIRCH_LOG_Z else id
            else -> id
        }
        if (!w.setBlock(x, y, z, id)) return
        consume(1)
        swing()
        p.statBlocksPlaced++
        scene.story.onBlockPlaced(block)
        scene.audio.playAt("place", x + 0.5f, y + 0.5f, z + 0.5f, 1f, if (def.sound == wildcore.world.SoundMat.STONE) 0.85f else 1.1f)
    }

    // ------------------------------------------------------------------ interact

    /** Short label describing what the interact button would do right now, or null. */
    fun interactHint(): String? {
        val p = scene.player
        if (p.onRaft >= 0) return "Сойти с плота"
        if (targetRaft >= 0) return "Сесть на плот"
        if (!hasTarget) return if (aimAtWater(3.5f)) "Пить" else null
        return when (hit.block) {
            B.CHEST -> "Открыть сундук"
            B.WORKBENCH -> "Верстак"
            B.FURNACE -> "Печь"
            B.CAMPFIRE -> "Готовить"
            B.BEDROLL -> "Спать"
            B.CRATE -> "Открыть ящик"
            B.TERMINAL -> "Терминал"
            B.BERRY_BUSH -> "Собрать ягоды"
            B.FRUIT_LEAVES -> "Сорвать яблоки"
            B.WHEAT_3, B.CARROT_3 -> "Собрать урожай"
            else -> if (aimAtWaterBefore()) "Пить" else null
        }
    }

    private fun aimAtWaterBefore(): Boolean = aimAtWater(3.5f) && waterHit.distance < hit.distance

    fun interact() {
        val p = scene.player
        if (p.dead) return
        val w = scene.world
        if (p.onRaft >= 0) { dismount(); return }
        if (targetRaft >= 0) { p.onRaft = targetRaft; scene.audio.play("step_wood0"); return }
        if (hasTarget) {
            val x = hit.x; val y = hit.y; val z = hit.z
            when (hit.block) {
                B.CHEST -> { scene.hud.openChest(x, y, z); return }
                B.WORKBENCH -> { scene.hud.openCrafting(Station.WORKBENCH); return }
                B.FURNACE -> { scene.hud.openCrafting(Station.FURNACE); return }
                B.CAMPFIRE -> { scene.hud.openCrafting(Station.CAMPFIRE); return }
                B.BEDROLL -> { scene.trySleep(x, y, z); return }
                B.CRATE -> { if (!scene.story.openCrate(x, y, z)) scene.hud.message("Ящик пуст") else scene.audio.play("break_wood", 0.5f, 1.4f); return }
                B.TERMINAL -> { scene.story.useTerminal(x, z)?.let { scene.hud.message(it) }; scene.audio.play("click"); return }
                B.BERRY_BUSH -> { w.setBlock(x, y, z, B.BERRY_BUSH_EMPTY); scene.drops.spawn(I.BERRIES, 2 + rng.nextInt(3), x + 0.5f, y + 0.6f, z + 0.5f, delay = 0.1f); scene.audio.playAt("break_leaves", x + 0.5f, y + 0.5f, z + 0.5f, 0.7f); swing(); return }
                B.FRUIT_LEAVES -> { w.setBlock(x, y, z, B.OAK_LEAVES); scene.drops.spawn(I.APPLE, 1 + rng.nextInt(2), x + 0.5f + hit.nx * 0.6f, y + 0.5f + hit.ny * 0.6f, z + 0.5f + hit.nz * 0.6f, delay = 0.1f); scene.audio.playAt("break_leaves", x + 0.5f, y + 0.5f, z + 0.5f, 0.7f); swing(); return }
                B.WHEAT_3, B.CARROT_3 -> {
                    // harvest and replant in one motion
                    val crop = hit.block
                    spawnDrops(crop, Blocks.get(crop), x, y, z)
                    w.setBlock(x, y, z, if (crop == B.WHEAT_3) B.WHEAT_0 else B.CARROT_0)
                    scene.story.onHarvest(); p.statHarvested++
                    scene.audio.playAt("break_leaves", x + 0.5f, y + 0.5f, z + 0.5f, 0.8f); swing(); return
                }
            }
        }
        if (aimAtWater(3.5f)) {
            if (p.survival.thirst > 97f) scene.hud.message("Пить не хочется")
            else { p.survival.eat(0f, 28f, 0f); scene.audio.play("drink"); swing() }
        }
    }

    private fun dismount() {
        val p = scene.player
        val r = rafts[p.onRaft]
        p.onRaft = -1
        if (r != null) p.teleport(r.pos.x, r.pos.y + 0.45f, r.pos.z)
    }

    // ------------------------------------------------------------------ bow, fishing, rafts

    private fun shoot() {
        val p = scene.player
        if (attackCooldown > 0f) return
        if (!p.inventory.remove(I.ARROW, 1)) { scene.hud.message("Нет стрел"); return }
        attackCooldown = 0.8f
        val a = Arrow()
        a.pos.set(origin.x + dir.x * 0.6f, origin.y + dir.y * 0.6f - 0.1f, origin.z + dir.z * 0.6f)
        a.vel.set(dir.x * 34f, dir.y * 34f + 1.5f, dir.z * 34f)
        arrows[scene.ecs.create()] = a
        scene.audio.play("bow")
        useDurability(1)
        swing()
    }

    private fun startFishing() {
        if (fishing > 0f) return
        if (!aimAtWater(9f)) { scene.hud.message("Забросьте удочку в воду"); return }
        fishingTotal = rng.range(5f, 11f)
        fishing = fishingTotal
        scene.audio.play("splash", 0.4f, 1.5f)
        scene.hud.message("Вы забросили удочку…")
        swing()
    }

    private fun updateFishing(dt: Float) {
        val p = scene.player
        if (p.heldItem.id != I.FISHING_ROD || p.speed > 1.5f) { fishing = 0f; scene.hud.message("Рыбалка прервана"); return }
        fishing -= dt
        if (fishing <= 0f) {
            fishing = 0f
            if (rng.nextFloat() < 0.72f) { scene.give(I.RAW_FISH, 1); scene.hud.message("Поймана рыба!"); scene.audio.play("splash", 0.7f, 1.2f) }
            else scene.hud.message("Сорвалась…")
            useDurability(1)
        }
    }

    val fishingProgress: Float get() = if (fishing > 0f) 1f - fishing / fishingTotal else 0f

    /** Arrows in flight and raft riding. */
    fun updateEntities(dt: Float) {
        val w = scene.world
        arrows.each(scene.ecs.highWater) { id, a ->
            a.life -= dt
            a.vel.y -= 14f * dt
            val sp = a.vel.length()
            val step = sp * dt
            val dx = a.vel.x / sp; val dy = a.vel.y / sp; val dz = a.vel.z / sp
            val animal = scene.animals.raycast(a.pos.x, a.pos.y, a.pos.z, dx, dy, dz, step)
            if (animal >= 0) {
                scene.animals.store[animal]?.let { scene.animals.damage(animal, it, 14f, scene.player.pos.x, scene.player.pos.z, true) }
                scene.ecs.destroy(id); return@each
            }
            if (VoxelPhysics.raycast(w, a.pos.x, a.pos.y, a.pos.z, dx, dy, dz, step, waterHit, solidOnly = true)) {
                if (rng.nextFloat() < 0.6f) scene.drops.spawn(I.ARROW, 1, waterHit.x + 0.5f + waterHit.nx * 0.7f, waterHit.y + 0.5f + waterHit.ny * 0.7f, waterHit.z + 0.5f + waterHit.nz * 0.7f)
                scene.audio.playAt("hit_wood", a.pos.x, a.pos.y, a.pos.z, 0.6f, 1.5f)
                scene.ecs.destroy(id); return@each
            }
            a.pos.addScaled(a.vel, dt)
            if (a.life <= 0f) { scene.ecs.destroy(id); return@each }
            scene.particles.icon(a.pos.x, a.pos.y, a.pos.z, 0.16f, scene.ui.iconId("arrow"))
        }
        val p = scene.player
        rafts.each(scene.ecs.highWater) { id, r ->
            if (p.onRaft == id) {
                // steer with the joystick: forward/back thrust along the camera, turning follows the view
                val target = p.moveZ * 4.6f
                r.speed = wildcore.math.approach(r.speed, target, 3.5f * dt)
                val fy = kotlin.math.atan2(sin(p.yaw), -cos(p.yaw))
                if (kotlin.math.abs(r.speed) > 0.2f) r.yaw += wildcore.math.angleDelta(r.yaw, fy) * minOf(1f, dt * 1.6f)
                val nx = r.pos.x + sin(r.yaw) * r.speed * dt; val nz = r.pos.z + cos(r.yaw) * r.speed * dt
                val ahead = w.getBlock(floorInt(nx + sin(r.yaw) * 1.1f * (if (r.speed >= 0f) 1f else -1f)), WorldGen.SEA - 1, floorInt(nz + cos(r.yaw) * 1.1f * (if (r.speed >= 0f) 1f else -1f)))
                if (Blocks.liquid[ahead]) { r.pos.x = nx; r.pos.z = nz } else r.speed = 0f
                p.body.pos.set(r.pos.x, r.pos.y + 0.22f, r.pos.z)
                p.body.vel.set(0f, 0f, 0f); p.body.fallDistance = 0f
                p.modelYaw = r.yaw
            } else r.speed = wildcore.math.approach(r.speed, 0f, 2f * dt)
            r.pos.y = WorldGen.SEA - 0.2f + sin(scene.renderer.env.time * 1.3f + r.pos.x) * 0.03f
            if (sqrt((r.pos.x - p.pos.x) * (r.pos.x - p.pos.x) + (r.pos.z - p.pos.z) * (r.pos.z - p.pos.z)) > 150f && p.onRaft != id) scene.ecs.destroy(id)
        }
    }
}
