#include "state.h"
#include "../hooks/il2cpp.h"

namespace cf::noclip {

void tick() {
    using namespace cf::state;
    if (!local_player.obj) return;

    static void *cls_col = nullptr, *m_getColliders = nullptr, *m_setEnabled = nullptr;
    static void *img = nullptr;
    if (!m_getColliders) {
        img = cf::il2cpp::image("Assembly-CSharp");
        auto cls_pm = cf::il2cpp::klass(img, "CF.Player", "PlayerCollision");
        m_getColliders = cf::il2cpp::method(cls_pm, "GetColliders", 0);
        auto img2 = cf::il2cpp::image("UnityEngine.PhysicsModule");
        cls_col = cf::il2cpp::klass(img2, "UnityEngine", "Collider");
        m_setEnabled = cf::il2cpp::method(cls_col, "set_enabled", 1);
    }

    bool want = flags.noclip.load();
    void *arr = cf::il2cpp::invoke_obj(m_getColliders, local_player.obj, nullptr);
    if (!arr) return;

    int32_t len = *(int32_t*)((char*)arr + sizeof(void*) * 2);
    void **items = (void**)((char*)arr + sizeof(void*) * 4);
    for (int i = 0; i < len; ++i) {
        bool v = !want;
        void *args[1] = { &v };
        cf::il2cpp::invoke_void(m_setEnabled, items[i], args);
    }
}
}
