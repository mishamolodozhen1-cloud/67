package wildfrontier.gen

object Biome {
    const val OCEAN = 0
    const val BEACH = 1
    const val MEADOW = 2
    const val DECIDUOUS = 3
    const val CONIFER = 4
    const val JUNGLE = 5
    const val SWAMP = 6
    const val MOUNTAIN = 7
    const val SNOW = 8
    const val ROCKY = 9
    const val RIVER = 10
    const val GROVE = 11   // secret natural zone
    const val COUNT = 12

    val NAMES = arrayOf(
        "Океан", "Пляж", "Луга", "Лиственный лес", "Хвойный лес", "Тропический лес",
        "Болото", "Горы", "Снежные земли", "Скалистые пустоши", "Река", "Тайная роща",
    )

    /** Linear RGB used by the map screen and far-terrain LOD (0..1 each). */
    val COLOR = arrayOf(
        floatArrayOf(0.10f, 0.27f, 0.42f), floatArrayOf(0.80f, 0.74f, 0.55f), floatArrayOf(0.40f, 0.58f, 0.22f),
        floatArrayOf(0.22f, 0.44f, 0.14f), floatArrayOf(0.14f, 0.31f, 0.16f), floatArrayOf(0.12f, 0.42f, 0.10f),
        floatArrayOf(0.26f, 0.32f, 0.17f), floatArrayOf(0.45f, 0.44f, 0.42f), floatArrayOf(0.90f, 0.93f, 0.96f),
        floatArrayOf(0.50f, 0.46f, 0.38f), floatArrayOf(0.14f, 0.36f, 0.50f), floatArrayOf(0.30f, 0.62f, 0.45f),
    )
}
