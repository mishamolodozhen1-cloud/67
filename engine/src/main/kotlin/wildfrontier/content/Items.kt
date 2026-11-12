package wildfrontier.content

import wildcore.world.Blocks
import wildcore.world.Shape
import wildcore.world.ToolKind

object Cat {
    const val BLOCKS = 0; const val MATERIALS = 1; const val FOOD = 2; const val TOOLS = 3
    const val CLOTHING = 4; const val FARMING = 5; const val TRANSPORT = 6; const val STORY = 7
    val NAMES = arrayOf("Блоки", "Материалы", "Еда", "Инструменты", "Одежда", "Фермерство", "Транспорт", "Находки")
}

object Equip { const val NONE = -1; const val BODY = 0; const val FEET = 1; const val BACK = 2 }

class ItemDef(
    val id: Int, val key: String, val name: String, val icon: String, val category: Int,
    val maxStack: Int = 64,
    val toolKind: Int = ToolKind.NONE, val toolTier: Int = 0, val durability: Int = 0,
    val damage: Float = 1f,
    val food: Float = 0f, val water: Float = 0f, val heal: Float = 0f,
    val placesBlock: Int = -1,
    val equipSlot: Int = Equip.NONE, val warmth: Float = 0f, val armor: Float = 0f,
    val description: String = "",
)

/** The item database. Block items share the block's id and are generated from the block registry. */
object Items {
    private val defs = arrayOfNulls<ItemDef>(512)
    val all = ArrayList<ItemDef>()
    private var registered = false

    fun get(id: Int): ItemDef? = if (id in 0 until 512) defs[id] else null
    fun name(id: Int): String = get(id)?.name ?: "?"

    private fun add(d: ItemDef) { defs[d.id] = d; all.add(d) }

    @Synchronized fun registerAll() {
        if (registered) return
        registered = true
        B.registerAll()
        // block items
        val skip = setOf(B.AIR, B.WATER, B.BEDROCK, B.FARMLAND_WET, B.BERRY_BUSH_EMPTY, B.TERMINAL,
            B.OAK_LOG_X, B.OAK_LOG_Z, B.PINE_LOG_X, B.PINE_LOG_Z, B.BIRCH_LOG_X, B.BIRCH_LOG_Z)
        for (id in 1 until 256) {
            val b = Blocks.defs[id] ?: continue
            if (id in skip || id in B.WHEAT_0..B.CARROT_3) continue
            val cat = if (b.shape == Shape.CROSS) Cat.FARMING else Cat.BLOCKS
            add(ItemDef(id, b.key, b.displayName, "b_" + b.key, cat, placesBlock = id, description = blockDescription(id)))
        }
        fun mat(id: Int, key: String, name: String, desc: String) = add(ItemDef(id, key, name, key, Cat.MATERIALS, description = desc))
        fun food(id: Int, key: String, name: String, food: Float, water: Float, heal: Float, desc: String, stack: Int = 32) =
            add(ItemDef(id, key, name, key, Cat.FOOD, maxStack = stack, food = food, water = water, heal = heal, description = desc))
        fun tool(id: Int, key: String, name: String, kind: Int, tier: Int, dur: Int, dmg: Float, desc: String) =
            add(ItemDef(id, key, name, key, Cat.TOOLS, maxStack = 1, toolKind = kind, toolTier = tier, durability = dur, damage = dmg, description = desc))

        mat(I.STICK, "stick", "Палка", "Основа почти любого инструмента.")
        mat(I.PLANT_FIBER, "plant_fiber", "Растительное волокно", "Из него вьют верёвки и ткут грубую ткань.")
        mat(I.FLINT, "flint", "Кремень", "Острый камень. Попадается в гравии.")
        mat(I.CLAY_BALL, "clay_ball", "Комок глины", "Обжигается в кирпич.")
        mat(I.COAL, "coal", "Уголь", "Лучшее топливо для печи.")
        mat(I.RAW_COPPER, "raw_copper", "Медная руда", "Переплавьте в печи.")
        mat(I.RAW_IRON, "raw_iron", "Железная руда", "Переплавьте в печи.")
        mat(I.RAW_GOLD, "raw_gold", "Золотая руда", "Переплавьте в печи.")
        mat(I.CRYSTAL, "crystal", "Кристалл эфирита", "Светится изнутри. Экспедиция искала именно его.")
        mat(I.COPPER_INGOT, "copper_ingot", "Медный слиток", "Мягкий металл для первых инструментов.")
        mat(I.IRON_INGOT, "iron_ingot", "Железный слиток", "Прочный металл.")
        mat(I.GOLD_INGOT, "gold_ingot", "Золотой слиток", "Редкий металл.")
        mat(I.ROPE, "rope", "Верёвка", "Скручена из волокна.")
        mat(I.LEATHER, "leather", "Шкура", "Выделанная шкура животного.")
        mat(I.BONE, "bone", "Кость", "Годится для инструментов и удобрения.")
        mat(I.FEATHER, "feather", "Перо", "Оперение для стрел.")
        mat(I.BRICK, "brick", "Кирпич", "Обожжённая глина.")
        mat(I.CLOTH, "cloth", "Ткань", "Грубое полотно из волокна.")
        mat(I.CHARCOAL, "charcoal", "Древесный уголь", "Топливо, выжженное из дерева.")

        food(I.BERRIES, "berries", "Ягоды", 6f, 4f, 0f, "Кисло-сладкие лесные ягоды.")
        food(I.APPLE, "apple", "Яблоко", 10f, 6f, 1f, "Дикое яблоко.")
        food(I.MUSHROOM, "mushroom_item", "Гриб", 5f, 1f, 0f, "Съедобный лесной гриб.")
        food(I.RAW_MEAT, "raw_meat", "Сырое мясо", 8f, 0f, -4f, "Лучше приготовить на костре.")
        food(I.COOKED_MEAT, "cooked_meat", "Жареное мясо", 32f, 0f, 6f, "Сытная горячая еда.")
        food(I.CARROT, "carrot", "Морковь", 9f, 3f, 0f, "Хрустящий корнеплод. Можно посадить.")
        mat(I.WHEAT, "wheat", "Пшеница", "Колосья для хлеба.")
        food(I.BREAD, "bread", "Хлеб", 26f, 0f, 2f, "Свежий хлеб из печи.")
        food(I.RAW_FISH, "raw_fish", "Сырая рыба", 7f, 2f, -2f, "Свежий улов.")
        food(I.COOKED_FISH, "cooked_fish", "Жареная рыба", 24f, 0f, 4f, "Ароматная рыба с костра.")
        food(I.COCONUT, "coconut", "Кокос", 8f, 18f, 0f, "Мякоть и прохладное молоко.")
        food(I.STEW, "stew", "Похлёбка", 40f, 22f, 10f, "Густая похлёбка из мяса и овощей.", 8)
        add(ItemDef(I.WHEAT_SEEDS, "wheat_seeds", "Семена пшеницы", "wheat_seeds", Cat.FARMING, description = "Посадите на грядку."))

        tool(I.STONE_AXE, "stone_axe", "Каменный топор", ToolKind.AXE, 1, 90, 3f, "Рубит дерево втрое быстрее рук.")
        tool(I.STONE_PICKAXE, "stone_pickaxe", "Каменная кирка", ToolKind.PICKAXE, 1, 90, 2f, "Добывает камень, уголь и медь.")
        tool(I.STONE_SHOVEL, "stone_shovel", "Каменная лопата", ToolKind.SHOVEL, 1, 90, 1.5f, "Быстро копает землю и песок.")
        tool(I.STONE_KNIFE, "stone_knife", "Каменный нож", ToolKind.SICKLE, 1, 70, 4f, "Срезает траву и помогает в охоте.")
        tool(I.COPPER_AXE, "copper_axe", "Медный топор", ToolKind.AXE, 2, 220, 4f, "Надёжный топор.")
        tool(I.COPPER_PICKAXE, "copper_pickaxe", "Медная кирка", ToolKind.PICKAXE, 2, 220, 3f, "Берёт железную руду.")
        tool(I.COPPER_SHOVEL, "copper_shovel", "Медная лопата", ToolKind.SHOVEL, 2, 220, 2f, "Быстрая лопата.")
        tool(I.IRON_AXE, "iron_axe", "Железный топор", ToolKind.AXE, 3, 520, 5f, "Валит деревья за секунды.")
        tool(I.IRON_PICKAXE, "iron_pickaxe", "Железная кирка", ToolKind.PICKAXE, 3, 520, 4f, "Добывает золото и эфирит.")
        tool(I.IRON_SHOVEL, "iron_shovel", "Железная лопата", ToolKind.SHOVEL, 3, 520, 2.5f, "Лучшая лопата.")
        tool(I.IRON_KNIFE, "iron_knife", "Железный нож", ToolKind.SICKLE, 3, 400, 7f, "Острый охотничий нож.")
        tool(I.HOE, "hoe", "Мотыга", ToolKind.NONE, 1, 120, 1f, "Превращает землю в грядку.")
        tool(I.SICKLE, "sickle", "Серп", ToolKind.SICKLE, 2, 200, 2f, "Собирает урожай и траву.")
        tool(I.SPEAR, "spear", "Копьё", ToolKind.NONE, 1, 120, 8f, "Охотничье копьё. Бьёт дальше ножа.")
        tool(I.BOW, "bow", "Лук", ToolKind.NONE, 1, 200, 2f, "Стреляет стрелами по прицелу.")
        add(ItemDef(I.ARROW, "arrow", "Стрела", "arrow", Cat.TOOLS, description = "Боеприпас для лука."))
        tool(I.FISHING_ROD, "fishing_rod", "Удочка", ToolKind.NONE, 1, 80, 1f, "Используйте, глядя на воду.")
        add(ItemDef(I.WATERSKIN, "waterskin", "Бурдюк (пустой)", "waterskin", Cat.TOOLS, maxStack = 1, description = "Наполните у воды."))
        add(ItemDef(I.WATERSKIN_FULL, "waterskin_full", "Бурдюк с водой", "waterskin_full", Cat.FOOD, maxStack = 1, water = 45f, description = "Запас воды в дорогу."))
        add(ItemDef(I.BUCKET, "bucket", "Ведро", "bucket", Cat.FARMING, maxStack = 1, description = "Зачерпните воды для полива."))
        add(ItemDef(I.BUCKET_WATER, "bucket_water", "Ведро воды", "bucket_water", Cat.FARMING, maxStack = 1, description = "Полейте грядку."))

        add(ItemDef(I.FIBER_SHIRT, "fiber_shirt", "Рубаха из волокна", "fiber_shirt", Cat.CLOTHING, maxStack = 1, equipSlot = Equip.BODY, warmth = 4f, armor = 0.05f, description = "Немного греет."))
        add(ItemDef(I.LEATHER_JACKET, "leather_jacket", "Кожаная куртка", "leather_jacket", Cat.CLOTHING, maxStack = 1, equipSlot = Equip.BODY, warmth = 9f, armor = 0.2f, description = "Защищает от ветра и зубов."))
        add(ItemDef(I.FUR_COAT, "fur_coat", "Меховая шуба", "fur_coat", Cat.CLOTHING, maxStack = 1, equipSlot = Equip.BODY, warmth = 18f, armor = 0.25f, description = "Для снежных земель."))
        add(ItemDef(I.LEATHER_BOOTS, "leather_boots", "Кожаные сапоги", "leather_boots", Cat.CLOTHING, maxStack = 1, equipSlot = Equip.FEET, warmth = 4f, armor = 0.08f, description = "Сухие ноги — тёплые ноги."))
        add(ItemDef(I.BACKPACK, "backpack", "Рюкзак", "backpack", Cat.CLOTHING, maxStack = 1, equipSlot = Equip.BACK, description = "+9 ячеек инвентаря."))
        add(ItemDef(I.RAFT, "raft", "Плот", "raft", Cat.TRANSPORT, maxStack = 1, description = "Поставьте на воду, чтобы плыть между островами."))
        add(ItemDef(I.NOTE, "note", "Записка", "note", Cat.STORY, maxStack = 1, description = "Страница из дневника экспедиции."))
        add(ItemDef(I.KEYCARD, "keycard", "Ключ-карта", "keycard", Cat.STORY, maxStack = 1, description = "Открывает терминалы лаборатории «Эфир»."))
        add(ItemDef(I.MAP_FRAGMENT, "map_fragment", "Обрывок карты", "map_fragment", Cat.STORY, description = "Отмечает место на карте архипелага."))
        add(ItemDef(I.RADIO_PART, "radio_part", "Деталь радиостанции", "radio_part", Cat.STORY, description = "Нужна, чтобы подать сигнал бедствия."))
    }

    private fun blockDescription(id: Int): String = when (id) {
        B.WORKBENCH -> "Открывает рецепты инструментов и построек."
        B.FURNACE -> "Плавит руду, обжигает глину, печёт хлеб."
        B.CHEST -> "Хранит 27 стопок предметов."
        B.CAMPFIRE -> "Греет, освещает и жарит еду."
        B.TORCH -> "Источник света."
        B.BEDROLL -> "Сон восстанавливает силы и пропускает ночь."
        B.FARMLAND -> "Основа огорода."
        B.SAPLING -> "Со временем вырастет в дерево."
        else -> "Строительный блок."
    }
}

class ItemStack(@JvmField var id: Int = 0, @JvmField var count: Int = 0, @JvmField var durability: Int = 0) {
    val isEmpty: Boolean get() = count <= 0 || id == 0
    fun clear() { id = 0; count = 0; durability = 0 }
    fun set(o: ItemStack) { id = o.id; count = o.count; durability = o.durability }
    fun set(nid: Int, n: Int, dur: Int = 0) { id = nid; count = n; durability = dur }
    fun copy() = ItemStack(id, count, durability)
}

/** A fixed-size item container (player backpack, chest…). */
class Inventory(val size: Int) {
    val slots = Array(size) { ItemStack() }
    var version = 0; private set
    /** Slots beyond this index are locked (e.g. extra rows unlocked by a backpack). */
    var activeSize = size

    /** Adds items; returns how many did not fit. */
    fun add(id: Int, count: Int, durability: Int = -1): Int {
        val def = Items.get(id) ?: return count
        var left = count
        if (def.maxStack > 1) {
            for (i in 0 until activeSize) {
                val s = slots[i]
                if (left <= 0) break
                if (!s.isEmpty && s.id == id && s.count < def.maxStack) {
                    val n = minOf(left, def.maxStack - s.count)
                    s.count += n; left -= n
                }
            }
        }
        for (i in 0 until activeSize) {
            val s = slots[i]
            if (left <= 0) break
            if (s.isEmpty) {
                val n = minOf(left, def.maxStack)
                s.set(id, n, if (durability >= 0) durability else def.durability)
                left -= n
            }
        }
        if (left != count) version++
        return left
    }

    fun count(id: Int): Int { var n = 0; for (s in slots) if (!s.isEmpty && s.id == id) n += s.count; return n }

    fun remove(id: Int, count: Int): Boolean {
        if (count(id) < count) return false
        var left = count
        for (i in slots.indices.reversed()) {
            val s = slots[i]
            if (left <= 0) break
            if (!s.isEmpty && s.id == id) {
                val n = minOf(left, s.count)
                s.count -= n; left -= n
                if (s.count <= 0) s.clear()
            }
        }
        version++
        return true
    }

    fun canFit(id: Int, count: Int): Boolean {
        val def = Items.get(id) ?: return false
        var room = 0
        for (i in 0 until activeSize) {
            val s = slots[i]
            if (s.isEmpty) room += def.maxStack
            else if (s.id == id) room += def.maxStack - s.count
            if (room >= count) return true
        }
        return false
    }

    fun touch() { version++ }
    val isEmpty: Boolean get() = slots.all { it.isEmpty }
}
