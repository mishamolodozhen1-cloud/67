package wildfrontier

import wildcore.core.Engine
import wildcore.core.Platform

/** Application root: creates the engine and switches between the menu and gameplay scenes. */
class WildFrontierGame(platform: Platform) {
    val engine = Engine(platform)
    var gameScene: GameScene? = null; private set

    fun startNewGame(seed: Long) {
        val s = GameScene(this, seed)
        gameScene = s
        engine.scenes.switchTo(s)
    }
}
