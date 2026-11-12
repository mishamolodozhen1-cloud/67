package wildfrontier.animals

import wildfrontier.content.I
import wildfrontier.gen.Biome

/** Static description of an animal species: body plan for the model builder plus behaviour tuning. */
class Species(
    val id: Int, val key: String, val name: String, val icon: String,
    val implemented: Boolean,
    val description: String,
    // habitat
    val biomes: IntArray = intArrayOf(),
    val groupMin: Int = 1, val groupMax: Int = 1,
    // body (metres)
    val bodyLength: Float = 1f, val bodyHeight: Float = 0.5f, val bodyWidth: Float = 0.3f,
    val shoulderHeight: Float = 0.8f, val neckLength: Float = 0.4f, val neckAngle: Float = 0.9f,
    val headLength: Float = 0.3f, val headSize: Float = 0.12f, val earLength: Float = 0.12f,
    val legThickness: Float = 0.05f, val tailLength: Float = 0.15f, val tailBushy: Float = 0.04f,
    val antlers: Boolean = false, val hindLegScale: Float = 1f, val bellyDrop: Float = 0f,
    val colorBack: Int = 0x8A6A46, val colorBelly: Int = 0xD8C8A8, val colorLeg: Int = 0x6A5036, val colorAccent: Int = 0xFFFFFF,
    // behaviour
    val walkSpeed: Float = 1.2f, val runSpeed: Float = 6f, val health: Float = 20f,
    val predator: Boolean = false, val fleeDistance: Float = 10f, val senseDistance: Float = 18f,
    val attackDamage: Float = 0f, val nocturnal: Boolean = false, val hops: Boolean = false,
    val prey: IntArray = intArrayOf(),
    val dropMeat: Int = 1, val dropLeather: Int = 0, val extraDrop: Int = -1,
    val collisionRadius: Float = 0.3f, val collisionHeight: Float = 0.9f,
    val soundPitch: Float = 1f,
)

/**
 * The fauna catalogue. Three species are fully implemented (model, animation, AI, ecology); the rest are
 * registered as encyclopedia entries so the roadmap to 50+ species is data-driven.
 */
object SpeciesDb {
    const val DEER = 0; const val WOLF = 1; const val RABBIT = 2
    val all = ArrayList<Species>()

    init {
        all.add(Species(DEER, "deer", "Благородный олень", "a_deer", true,
            "Осторожное стадное животное лугов и лесов. Пасётся на рассвете и в сумерках, держится группами под присмотром вожака. Чуткий слух замечает охотника издалека — подходите медленно и против ветра.",
            biomes = intArrayOf(Biome.MEADOW, Biome.DECIDUOUS, Biome.CONIFER, Biome.GROVE), groupMin = 2, groupMax = 5,
            bodyLength = 1.35f, bodyHeight = 0.50f, bodyWidth = 0.34f, shoulderHeight = 1.02f, neckLength = 0.55f, neckAngle = 1.0f,
            headLength = 0.36f, headSize = 0.13f, earLength = 0.17f, legThickness = 0.05f, tailLength = 0.14f, tailBushy = 0.05f,
            antlers = true, colorBack = 0x8B5E3C, colorBelly = 0xE2D2B4, colorLeg = 0x5E4028, colorAccent = 0xF4EEE0,
            walkSpeed = 1.3f, runSpeed = 8.5f, health = 28f, fleeDistance = 13f, senseDistance = 24f,
            dropMeat = 3, dropLeather = 2, extraDrop = I.BONE, collisionRadius = 0.38f, collisionHeight = 1.35f, soundPitch = 0.8f))
        all.add(Species(WOLF, "wolf", "Серый волк", "a_wolf", true,
            "Стайный хищник хвойных лесов и предгорий. Охотится ночью на оленей и кроликов, сытый волк человека сторонится, голодная стая — нет. Держите костёр зажжённым: огня волки избегают.",
            biomes = intArrayOf(Biome.CONIFER, Biome.MOUNTAIN, Biome.SNOW, Biome.ROCKY), groupMin = 2, groupMax = 4,
            bodyLength = 1.15f, bodyHeight = 0.40f, bodyWidth = 0.30f, shoulderHeight = 0.74f, neckLength = 0.30f, neckAngle = 0.45f,
            headLength = 0.34f, headSize = 0.14f, earLength = 0.11f, legThickness = 0.055f, tailLength = 0.50f, tailBushy = 0.09f,
            colorBack = 0x6E6E6C, colorBelly = 0xCFCAC0, colorLeg = 0x8A8780, colorAccent = 0x2A2A2A,
            walkSpeed = 1.6f, runSpeed = 8.0f, health = 36f, predator = true, fleeDistance = 0f, senseDistance = 26f,
            attackDamage = 9f, nocturnal = true, prey = intArrayOf(DEER, RABBIT),
            dropMeat = 2, dropLeather = 2, extraDrop = I.BONE, collisionRadius = 0.34f, collisionHeight = 0.95f, soundPitch = 1.0f))
        all.add(Species(RABBIT, "rabbit", "Дикий кролик", "a_rabbit", true,
            "Мелкий травоядный зверёк. Живёт семьями, кормится травой и быстро плодится, если рядом нет хищников. При опасности замирает, а затем уносится зигзагами.",
            biomes = intArrayOf(Biome.MEADOW, Biome.DECIDUOUS, Biome.GROVE, Biome.ROCKY, Biome.CONIFER), groupMin = 2, groupMax = 4,
            bodyLength = 0.38f, bodyHeight = 0.19f, bodyWidth = 0.15f, shoulderHeight = 0.20f, neckLength = 0.06f, neckAngle = 0.9f,
            headLength = 0.13f, headSize = 0.075f, earLength = 0.13f, legThickness = 0.028f, tailLength = 0.05f, tailBushy = 0.045f,
            hindLegScale = 1.5f, colorBack = 0x9A8468, colorBelly = 0xE8E0D0, colorLeg = 0x8A7458, colorAccent = 0xFFFFFF,
            walkSpeed = 1.0f, runSpeed = 7.0f, health = 6f, fleeDistance = 7f, senseDistance = 12f, hops = true,
            dropMeat = 1, dropLeather = 1, collisionRadius = 0.18f, collisionHeight = 0.35f, soundPitch = 1.8f))

        var next = 3
        fun planned(key: String, name: String, icon: String, desc: String) { all.add(Species(next++, key, name, "a_$icon", false, desc)) }
        planned("roe", "Косуля", "roe", "Небольшой олень опушек и перелесков.")
        planned("moose", "Лось", "moose", "Крупнейший обитатель болот и хвойных лесов.")
        planned("fox", "Лисица", "fox", "Одиночный хищник, мышкует на лугах.")
        planned("bear", "Бурый медведь", "bear", "Всеядный хозяин леса. Опасен у добычи и берлоги.")
        planned("hare", "Заяц", "hare", "Крупнее кролика, живёт в одиночку.")
        planned("squirrel", "Белка", "squirrel", "Древесный грызун, запасает орехи.")
        planned("boar", "Кабан", "boar", "Роет землю в поисках корней, защищает поросят.")
        planned("lynx", "Рысь", "lynx", "Скрытная кошка горных лесов.")
        planned("horse", "Дикая лошадь", "horse", "Табуны на лугах; можно приручить.")
        planned("eagle", "Орёл", "eagle", "Парит над скалами в поисках добычи.")
        planned("falcon", "Сокол", "falcon", "Стремительный воздушный охотник.")
        planned("owl", "Сова", "owl", "Ночной хищник лесных опушек.")
        planned("crow", "Ворон", "crow", "Умная птица, собирается у брошенных лагерей.")
        planned("gull", "Чайка", "gull", "Кружит над побережьем.")
        planned("duck", "Утка", "duck", "Гнездится на озёрах и реках.")
        planned("goose", "Гусь", "goose", "Перелётные стаи у воды.")
        planned("woodpecker", "Дятел", "woodpecker", "Стук слышен в лиственных лесах.")
        planned("parrot", "Попугай", "parrot", "Яркая птица тропических лесов.")
        planned("pigeon", "Голубь", "pigeon", "Селится у старых построек.")
        planned("songbird", "Певчие птицы", "songbird", "Наполняют лес голосами на рассвете.")
        planned("fish", "Рыба", "fish", "Речные и морские виды; ловится удочкой.")
        planned("shark", "Акула", "shark", "Патрулирует глубокую воду.")
        planned("dolphin", "Дельфин", "dolphin", "Сопровождает плоты между островами.")
        planned("turtle", "Морская черепаха", "turtle", "Выходит на пляжи откладывать яйца.")
        planned("crab", "Краб", "crab", "Бегает по линии прибоя.")
        planned("octopus", "Осьминог", "octopus", "Прячется среди подводных скал.")
        planned("jellyfish", "Медуза", "jellyfish", "Дрейфует в тёплых водах.")
        planned("seal", "Морской котик", "seal", "Лежбища на холодных берегах.")
        planned("snake", "Змея", "snake", "Греется на камнях; не тревожьте.")
        planned("lizard", "Ящерица", "lizard", "Юркий обитатель скал.")
        planned("crocodile", "Крокодил", "crocodile", "Засадный хищник тропических рек.")
        planned("frog", "Лягушка", "frog", "Хор болот по вечерам.")
        planned("toad", "Жаба", "toad", "Ночной охотник на насекомых.")
        planned("salamander", "Саламандра", "salamander", "Живёт у холодных ручьёв.")
        planned("butterfly", "Бабочки", "butterfly", "Порхают над цветущими лугами.")
        planned("bee", "Пчёлы", "bee", "Опыляют цветы и плодовые деревья.")
        planned("ant", "Муравьи", "ant", "Строят муравейники в хвойных лесах.")
        planned("dragonfly", "Стрекозы", "dragonfly", "Охотятся над водой.")
        planned("beetle", "Жуки", "beetle", "Лесные санитары.")
        planned("firefly", "Светлячки", "firefly", "Огоньки над травой тёплыми ночами.")
        planned("mosquito", "Комары", "mosquito", "Тучи над болотом в сумерках.")
    }

    fun get(id: Int): Species = all[id]
}
