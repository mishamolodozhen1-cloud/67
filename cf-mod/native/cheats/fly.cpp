#include "state.h"
#include "../hooks/il2cpp.h"

namespace cf::fly {

void tick(float dt) {
    using namespace cf::state;
    if (!flags.fly.load() || !local_player.obj) return;

    static void *img = nullptr, *cls_rb = nullptr;
    static void *f_useGravity = nullptr, *m_setVelocity = nullptr;
    static void *m_getBody = nullptr;
    if (!m_setVelocity) {
        img = cf::il2cpp::image("UnityEngine.PhysicsModule");
        cls_rb = cf::il2cpp::klass(img, "UnityEngine", "Rigidbody");
        f_useGravity  = cf::il2cpp::field(cls_rb, "m_useGravity");
        m_setVelocity = cf::il2cpp::method(cls_rb, "set_velocity_Injected", 1);
        auto img2 = cf::il2cpp::image("Assembly-CSharp");
        auto cls_pm = cf::il2cpp::klass(img2, "CF.Player", "PlayerMotor");
        m_getBody   = cf::il2cpp::method(cls_pm, "get_Rigidbody", 0);
    }

    void *rb = cf::il2cpp::invoke_obj(m_getBody, local_player.obj, nullptr);
    if (!rb) return;
    bool off = false;
    cf::il2cpp::write_field(rb, f_useGravity, off);
    float sp = flags.fly_speed.load();
    float v[3] = { 0, sp, 0 };
    void *args[1] = { v };
    cf::il2cpp::invoke_void(m_setVelocity, rb, args);
}
}
