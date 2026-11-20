#include "state.h"
#include "../hooks/il2cpp.h"

namespace cf::misc {

void tick() {
    using namespace cf::state;
    if (!local_player.obj) return;

    static void *img = nullptr;
    static void *m_set_speed = nullptr, *m_set_god = nullptr;
    static void *m_set_recoil = nullptr, *m_set_fire_delay = nullptr;
    static void *m_set_pen = nullptr;
    if (!m_set_speed) {
        img = cf::il2cpp::image("Assembly-CSharp");
        auto cls_mot = cf::il2cpp::klass(img, "CF.Player", "PlayerMotor");
        auto cls_hp  = cf::il2cpp::klass(img, "CF.Player", "PlayerHealth");
        auto cls_w   = cf::il2cpp::klass(img, "CF.Weapon", "Weapon");
        m_set_speed      = cf::il2cpp::method(cls_mot, "SetSpeedMultiplier", 1);
        m_set_god        = cf::il2cpp::method(cls_hp,  "SetInvulnerable", 1);
        m_set_recoil     = cf::il2cpp::method(cls_w,   "SetRecoilMultiplier", 1);
        m_set_fire_delay = cf::il2cpp::method(cls_w,   "SetFireDelayMultiplier", 1);
        m_set_pen        = cf::il2cpp::method(cls_w,   "SetPenetration", 1);
    }

    float sp = flags.speed.load();
    { void *a[1] = { &sp }; cf::il2cpp::invoke_void(m_set_speed, local_player.obj, a); }
    { bool  v = flags.god.load(); void *a[1] = { &v }; cf::il2cpp::invoke_void(m_set_god, local_player.obj, a); }
    float r = flags.nospread.load() ? 0.f : 1.f;
    { void *a[1] = { &r }; cf::il2cpp::invoke_void(m_set_recoil, local_player.obj, a); }
    float fd = flags.rapid.load() ? 0.05f : 1.f;
    { void *a[1] = { &fd }; cf::il2cpp::invoke_void(m_set_fire_delay, local_player.obj, a); }
    bool wb = flags.wallbang.load();
    { void *a[1] = { &wb }; cf::il2cpp::invoke_void(m_set_pen, local_player.obj, a); }
}
}
