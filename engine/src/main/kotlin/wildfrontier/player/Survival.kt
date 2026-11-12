package wildfrontier.player

import wildcore.math.clamp

/** Vital statistics of the survivor and how the environment wears them down. All values 0..100. */
class Survival {
    var health = 100f
    var hunger = 100f
    var thirst = 100f
    var energy = 100f
    /** Comfort scale: -1 freezing … 0 comfortable … +1 overheating. */
    var temperature = 0f
    var wetness = 0f
    var feelsLikeC = 18f
    var lastDamageCause = ""

    val speedFactor: Float get() {
        var f = 1f
        if (energy < 20f) f *= 0.78f
        if (hunger < 15f) f *= 0.88f
        if (temperature < -0.6f) f *= 0.9f
        return f
    }
    val canSprint: Boolean get() = energy > 12f && thirst > 10f && hunger > 5f
    val workFactor: Float get() = (if (energy < 20f) 0.75f else 1f) * (if (temperature < -0.5f) 0.85f else 1f)

    fun damage(amount: Float, cause: String) {
        if (amount <= 0f) return
        health = maxOf(0f, health - amount)
        lastDamageCause = cause
    }

    /**
     * @param ambientC air temperature at the player's position
     * @param warmth clothing warmth in °C equivalent
     * @param nearFire 0..1 proximity to a heat source
     */
    fun update(dt: Float, ambientC: Float, warmth: Float, nearFire: Float, inWater: Boolean, raining: Boolean, sheltered: Boolean,
               sprinting: Boolean, working: Boolean, resting: Boolean) {
        val effort = if (sprinting) 2.2f else if (working) 1.5f else if (resting) 0.6f else 1f
        hunger = maxOf(0f, hunger - dt * 0.036f * effort)
        val heatThirst = if (temperature > 0.3f) 1.6f else 1f
        thirst = maxOf(0f, thirst - dt * 0.058f * effort * heatThirst)
        energy = clamp(energy - dt * (if (sprinting) 0.11f else if (working) 0.05f else if (resting) -0.12f else 0.022f), 0f, 100f)

        // wetness: soaked when swimming or standing in rain without a roof; dries by the fire and in the sun
        if (inWater) wetness = minOf(1f, wetness + dt * 1.5f)
        else if (raining && !sheltered) wetness = minOf(1f, wetness + dt * 0.04f)
        else wetness = maxOf(0f, wetness - dt * (0.012f + nearFire * 0.08f))

        feelsLikeC = ambientC + warmth + nearFire * 16f - wetness * 9f + (if (sprinting) 2f else 0f)
        val target = when {
            feelsLikeC < 10f -> -clamp((10f - feelsLikeC) / 22f, 0f, 1f)
            feelsLikeC > 31f -> clamp((feelsLikeC - 31f) / 14f, 0f, 1f)
            else -> 0f
        }
        temperature += (target - temperature) * minOf(1f, dt * 0.06f)

        // consequences
        if (hunger <= 0f) damage(dt * 0.55f, "голод")
        if (thirst <= 0f) damage(dt * 0.8f, "жажда")
        if (temperature < -0.72f) damage(dt * 0.7f * (-temperature), "холод")
        if (temperature > 0.8f) damage(dt * 0.6f * temperature, "жара")
        if (hunger > 55f && thirst > 55f && temperature > -0.5f && health < 100f && health > 0f) {
            health = minOf(100f, health + dt * (if (resting) 1.4f else 0.45f))
        }
    }

    fun eat(food: Float, water: Float, heal: Float) {
        hunger = minOf(100f, hunger + food)
        thirst = minOf(100f, thirst + water)
        if (heal > 0f) health = minOf(100f, health + heal) else if (heal < 0f) damage(-heal, "несвежая еда")
        energy = minOf(100f, energy + food * 0.12f)
    }

    fun reset() { health = 100f; hunger = 80f; thirst = 80f; energy = 80f; temperature = 0f; wetness = 0f }
}
