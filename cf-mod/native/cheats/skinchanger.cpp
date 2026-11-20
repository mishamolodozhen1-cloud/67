#include "state.h"
#include "../hooks/il2cpp.h"
#include <string>
#include <vector>

namespace cf::skin {

static const char *g_presets[] = {
    "default",
    "neon_sunset",
    "brass_veteran",
    "obsidian_ink",
    "porcelain_gold",
    "olive_steel",
    "coral_matte",
    "midnight_pearl",
};
static const int g_preset_count = sizeof(g_presets) / sizeof(g_presets[0]);

int preset_count()      { return g_preset_count; }
const char *preset(int i){ return g_presets[(i % g_preset_count + g_preset_count) % g_preset_count]; }

void tick() {
    using namespace cf::state;
    if (!flags.skin_enabled.load() || !local_player.obj) return;

    static void *img = nullptr;
    static void *m_invent = nullptr, *m_set_skin_by_name = nullptr;
    if (!m_set_skin_by_name) {
        img = cf::il2cpp::image("Assembly-CSharp");
        auto cls_inv = cf::il2cpp::klass(img, "CF.Inventory", "LocalInventory");
        m_invent  = cf::il2cpp::method(cls_inv, "GetWeaponList", 0);
        auto cls_w  = cf::il2cpp::klass(img, "CF.Weapon", "WeaponSkin");
        m_set_skin_by_name = cf::il2cpp::method(cls_w, "ApplySkinName", 1);
    }

    void *list = cf::il2cpp::invoke_obj(m_invent, local_player.obj, nullptr);
    if (!list) return;
    int32_t len = *(int32_t*)((char*)list + sizeof(void*) * 2);
    void **items = (void**)((char*)list + sizeof(void*) * 4);
    const char *name = preset(flags.skin_preset.load());
    for (int i = 0; i < len; ++i) {
        void *args[1] = { (void*)name };
        cf::il2cpp::invoke_void(m_set_skin_by_name, items[i], args);
    }
}
}
