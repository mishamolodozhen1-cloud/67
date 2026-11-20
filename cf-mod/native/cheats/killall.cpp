#include "state.h"
#include "../hooks/il2cpp.h"
#include <mutex>

namespace cf::killall {

void fire() {
    using namespace cf::state;
    if (!flags.killall_armed.load() || !flags.killall_fire.load()) return;

    static void *img = nullptr, *cls_health = nullptr, *m_damage = nullptr;
    if (!m_damage) {
        img = cf::il2cpp::image("Assembly-CSharp");
        cls_health = cf::il2cpp::klass(img, "CF.Player", "PlayerHealth");
        m_damage   = cf::il2cpp::method(cls_health, "ApplyDamage", 2);
    }
    if (!m_damage) return;

    std::lock_guard<std::mutex> lk(players_mu);
    float dmg = 9999.f;
    int   src = 0;
    for (auto &p : players) {
        if (!p.obj || p.hp <= 0) continue;
        if (p.team == local_player.team && local_player.team != 0) continue;
        void *args[2] = { &dmg, &src };
        cf::il2cpp::invoke_void(m_damage, p.obj, args);
    }
    flags.killall_fire = false;
}
}
