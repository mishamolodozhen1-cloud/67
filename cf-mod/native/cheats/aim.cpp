#include "state.h"
#include "../hooks/il2cpp.h"
#include "../util/world.h"
#include "../util/log.h"
#include <math.h>
#include <mutex>

// Aim: ближайший к центру экрана враг в радиусе FOV,
// плавно уводим камеру в выбранную кость.
namespace cf::aim {

static void tick(int sw, int sh) {
    using namespace cf::state;
    if (!flags.aim.load()) return;

    static void *cls_input = nullptr;
    static void *m_set_look = nullptr;
    if (!m_set_look) {
        auto img = cf::il2cpp::image("Assembly-CSharp");
        cls_input = cf::il2cpp::klass(img, "CF.Input", "LookController");
        m_set_look = cf::il2cpp::method(cls_input, "SetLookDirection", 2);
    }
    if (!m_set_look) return;

    float cx = sw * 0.5f, cy = sh * 0.5f;
    float best = 1e9f;
    cf::world::V3 best_p{};
    bool found = false;

    std::lock_guard<std::mutex> lk(players_mu);
    for (auto &p : players) {
        if (!p.obj || p.hp <= 0) continue;
        if (p.team == local_player.team && local_player.team != 0) continue;
        cf::world::V3 w = flags.aim_bone.load() == 0 ? cf::world::V3{p.hx, p.hy, p.hz}
                           : flags.aim_bone.load() == 1 ? cf::world::V3{p.hx, p.hy - 0.08f, p.hz}
                                                        : cf::world::V3{p.cx, p.cy, p.cz};
        float s[2];
        if (!cf::world::world_to_screen(w, s, sw, sh)) continue;
        float dx = s[0] - cx, dy = s[1] - cy;
        float d = sqrtf(dx*dx + dy*dy);
        if (d > flags.aim_fov.load()) continue;
        if (d < best) { best = d; best_p = w; found = true; }
    }

    if (!found) return;
    float s[2];
    if (!cf::world::world_to_screen(best_p, s, sw, sh)) return;
    float dx = (s[0] - cx) / (float)sw;
    float dy = (s[1] - cy) / (float)sh;
    float t  = 1.f / fmaxf(1.f, flags.aim_smooth.load());
    dx *= t; dy *= t;
    void *args[2] = { &dx, &dy };
    cf::il2cpp::invoke_void(m_set_look, nullptr, args);
}

void bind_present(int sw, int sh) { tick(sw, sh); }
}
