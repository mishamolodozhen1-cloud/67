#include "esp.h"
#include "state.h"
#include "../menu/renderer.h"
#include "../util/world.h"
#include <mutex>
#include <stdio.h>

namespace cf::esp {

static void draw_box(cf::menu::Renderer &r, float x1, float y1, float x2, float y2, uint32_t color) {
    r.line(x1, y1, x2, y1, 1.5f, color);
    r.line(x2, y1, x2, y2, 1.5f, color);
    r.line(x2, y2, x1, y2, 1.5f, color);
    r.line(x1, y2, x1, y1, 1.5f, color);
}

void draw(int sw, int sh) {
    if (!cf::state::flags.esp.load()) return;
    auto &r = cf::menu::Renderer::instance();
    std::lock_guard<std::mutex> lk(cf::state::players_mu);
    const auto &lp = cf::state::local_player;
    for (auto &p : cf::state::players) {
        if (!p.obj || p.hp <= 0) continue;
        if (p.team == lp.team && lp.team != 0) continue;
        float head[2], feet[2];
        if (!cf::world::world_to_screen({p.hx, p.hy + 0.25f, p.hz}, head, sw, sh)) continue;
        if (!cf::world::world_to_screen({p.px, p.py - 0.05f, p.pz}, feet, sw, sh)) continue;
        float h = feet[1] - head[1];
        if (h < 10) continue;
        float w = h * 0.45f;
        float x1 = head[0] - w * 0.5f, x2 = head[0] + w * 0.5f;
        float y1 = head[1],             y2 = feet[1];

        uint32_t col = p.visible ? 0xFFE6D5A6 : 0xFF9FA3AF;
        if (cf::state::flags.esp_box.load())
            draw_box(r, x1, y1, x2, y2, col);

        if (cf::state::flags.esp_hp.load()) {
            float bx = x1 - 4;
            float bh = y2 - y1;
            r.quad(bx - 2, y1, bx + 2, y2, 0x66000000);
            float h01 = p.hp / 100.f; if (h01 < 0) h01 = 0; if (h01 > 1) h01 = 1;
            r.quad(bx - 1, y2 - bh * h01, bx + 1, y2, 0xFFC89B57);
        }

        if (cf::state::flags.esp_name.load() && !p.name.empty()) {
            r.text(x1, y1 - 14, p.name.c_str(), 11, col);
        }

        if (cf::state::flags.esp_tracer.load()) {
            r.line(sw * 0.5f, sh * 1.0f, (x1 + x2) * 0.5f, (y1 + y2) * 0.5f, 1.0f, col);
        }
    }
}
}
