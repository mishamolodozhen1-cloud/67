#include "menu.h"
#include "renderer.h"
#include "../cheats/state.h"
#include "../cheats/esp.h"
#include "../util/log.h"
#include <atomic>
#include <string>
#include <vector>
#include <mutex>
#include <deque>

namespace cf::menu {

// палитра: без неона, тёплый gun-metal
static constexpr uint32_t C_BG       = 0xEE12141A;
static constexpr uint32_t C_BG2      = 0xFF171A22;
static constexpr uint32_t C_LINE     = 0xFF22262E;
static constexpr uint32_t C_CARD     = 0xFF1B1E25;
static constexpr uint32_t C_CARD_HOV = 0xFF1F232B;
static constexpr uint32_t C_TEXT     = 0xFFE5E5E5;
static constexpr uint32_t C_MUTED    = 0xFF8A8E94;
static constexpr uint32_t C_ACC      = 0xFFC89B57;
static constexpr uint32_t C_ACC_SOFT = 0x40C89B57;
static constexpr uint32_t C_TRACK    = 0xFF2A2F38;
static constexpr uint32_t C_HANDLE   = 0xFFDBD3C1;
static constexpr uint32_t C_WARN     = 0xFFA76547;

static std::atomic<bool> g_open{false};
static int    g_tab = 0;
static float  g_x = 60, g_y = 110;
static float  g_w = 540, g_h = 740;
static float  g_toggle_x = 24, g_toggle_y = 24;
static float  g_toggle_sz = 56;
static bool   g_dragging_panel = false;
static bool   g_dragging_fab   = false;
static float  g_drag_dx = 0, g_drag_dy = 0;
static float  g_last_tx = 0, g_last_ty = 0;
static bool   g_down = false;
static bool   g_press_consumed = false;

extern bool poll_touch(struct TouchEv&);
struct TouchEv { float x, y; int action; };

static bool inside(float x, float y, float x1, float y1, float x2, float y2) {
    return x >= x1 && x <= x2 && y >= y1 && y <= y2;
}

static bool draw_toggle(Renderer &r, float x, float y, float w, float h, const char *label, std::atomic<bool> &val) {
    bool hov = inside(g_last_tx, g_last_ty, x, y, x + w, y + h);
    uint32_t bg = hov ? C_CARD_HOV : C_CARD;
    r.rquad(x, y, x + w, y + h, 10, bg);
    r.text(x + 16, y + h * 0.5f - 7, label, 14, C_TEXT);
    float tw = 46, th = 24;
    float tx = x + w - tw - 14, ty = y + (h - th) * 0.5f;
    r.rquad(tx, ty, tx + tw, ty + th, 12, val.load() ? C_ACC : C_TRACK);
    float kx = val.load() ? tx + tw - th + 2 : tx + 2;
    r.rquad(kx, ty + 2, kx + th - 4, ty + th - 2, 10, C_HANDLE);
    if (hov && g_down && !g_press_consumed) { val = !val.load(); g_press_consumed = true; return true; }
    return false;
}

static float draw_slider(Renderer &r, float x, float y, float w, float h, const char *label, std::atomic<float> &val, float lo, float hi) {
    r.rquad(x, y, x + w, y + h, 10, C_CARD);
    r.text(x + 16, y + 10, label, 12, C_MUTED);
    char v[32]; snprintf(v, 32, "%.1f", val.load());
    r.text(x + w - 60, y + 10, v, 12, C_TEXT);
    float tr_x1 = x + 16, tr_x2 = x + w - 16;
    float tr_y  = y + h - 18;
    r.rquad(tr_x1, tr_y, tr_x2, tr_y + 4, 2, C_TRACK);
    float t = (val.load() - lo) / (hi - lo);
    if (t < 0) t = 0; if (t > 1) t = 1;
    float hx = tr_x1 + (tr_x2 - tr_x1) * t;
    r.rquad(tr_x1, tr_y, hx, tr_y + 4, 2, C_ACC);
    r.rquad(hx - 7, tr_y - 6, hx + 7, tr_y + 10, 8, C_HANDLE);
    bool hov = inside(g_last_tx, g_last_ty, tr_x1 - 10, tr_y - 16, tr_x2 + 10, tr_y + 20);
    if (hov && g_down) {
        float nt = (g_last_tx - tr_x1) / (tr_x2 - tr_x1);
        if (nt < 0) nt = 0; if (nt > 1) nt = 1;
        val = lo + (hi - lo) * nt;
    }
    return val.load();
}

static int draw_segmented(Renderer &r, float x, float y, float w, float h, const char *label, const char *const *items, int n, std::atomic<int> &sel) {
    r.text(x + 16, y + 8, label, 12, C_MUTED);
    float cy = y + 28, ch = h - 28 - 8;
    float cw = (w - 32) / n;
    for (int i = 0; i < n; ++i) {
        float x1 = x + 16 + cw * i, x2 = x1 + cw - 6;
        bool active = sel.load() == i;
        bool hov = inside(g_last_tx, g_last_ty, x1, cy, x2, cy + ch);
        r.rquad(x1, cy, x2, cy + ch, 8, active ? C_ACC_SOFT : (hov ? C_CARD_HOV : C_CARD));
        if (active) r.line(x1 + 10, cy + ch - 3, x2 - 10, cy + ch - 3, 2, C_ACC);
        r.text(x1 + 12, cy + ch * 0.5f - 6, items[i], 12, active ? C_TEXT : C_MUTED);
        if (hov && g_down && !g_press_consumed) { sel = i; g_press_consumed = true; }
    }
    return sel.load();
}

static bool draw_button(Renderer &r, float x, float y, float w, float h, const char *label, uint32_t accent = C_ACC) {
    bool hov = inside(g_last_tx, g_last_ty, x, y, x + w, y + h);
    r.rquad(x, y, x + w, y + h, 10, hov ? C_CARD_HOV : C_CARD);
    r.line(x + 14, y + h - 2, x + w - 14, y + h - 2, 1.4f, accent);
    r.text(x + 16, y + h * 0.5f - 7, label, 14, C_TEXT);
    if (hov && g_down && !g_press_consumed) { g_press_consumed = true; return true; }
    return false;
}

static void draw_section(Renderer &r, float x, float y, float w, const char *title) {
    r.text(x, y, title, 11, C_MUTED);
    r.line(x, y + 16, x + w, y + 16, 1, C_LINE);
}

static void tab_esp(Renderer &r, float x, float y, float w) {
    draw_section(r, x, y, w, "VISUALS");
    float cy = y + 26;
    draw_toggle(r, x, cy, w, 48, "Enemy ESP",    cf::state::flags.esp);        cy += 56;
    draw_toggle(r, x, cy, w, 48, "Bounding box", cf::state::flags.esp_box);    cy += 56;
    draw_toggle(r, x, cy, w, 48, "Name tag",     cf::state::flags.esp_name);   cy += 56;
    draw_toggle(r, x, cy, w, 48, "Health bar",   cf::state::flags.esp_hp);     cy += 56;
    draw_toggle(r, x, cy, w, 48, "Tracers",      cf::state::flags.esp_tracer); cy += 56;
}
static void tab_aim(Renderer &r, float x, float y, float w) {
    draw_section(r, x, y, w, "AIM");
    float cy = y + 26;
    draw_toggle(r, x, cy, w, 48, "Aim assist", cf::state::flags.aim);         cy += 56;
    draw_slider(r, x, cy, w, 54, "FOV",        cf::state::flags.aim_fov, 10, 240);  cy += 62;
    draw_slider(r, x, cy, w, 54, "Smoothness", cf::state::flags.aim_smooth, 1, 10); cy += 62;
    static const char *bones[] = { "Head", "Neck", "Chest" };
    draw_segmented(r, x, cy, w, 60, "Target bone", bones, 3, cf::state::flags.aim_bone);
}
static void tab_move(Renderer &r, float x, float y, float w) {
    draw_section(r, x, y, w, "MOVEMENT");
    float cy = y + 26;
    draw_toggle(r, x, cy, w, 48, "Fly",       cf::state::flags.fly);       cy += 56;
    draw_slider(r, x, cy, w, 54, "Fly speed", cf::state::flags.fly_speed, 1, 24); cy += 62;
    draw_toggle(r, x, cy, w, 48, "Noclip",    cf::state::flags.noclip);
}
static void tab_skins(Renderer &r, float x, float y, float w) {
    extern int  preset_count();
    extern const char *preset(int);
    draw_section(r, x, y, w, "SKIN CHANGER");
    float cy = y + 26;
    draw_toggle(r, x, cy, w, 48, "Enable skin changer", cf::state::flags.skin_enabled); cy += 56;
    int n = preset_count();
    float cw = (w - 12) / 2;
    for (int i = 0; i < n; ++i) {
        int col = i % 2, row = i / 2;
        float x1 = x + col * (cw + 12), y1 = cy + row * 58;
        bool sel = cf::state::flags.skin_preset.load() == i;
        bool hov = inside(g_last_tx, g_last_ty, x1, y1, x1 + cw, y1 + 50);
        r.rquad(x1, y1, x1 + cw, y1 + 50, 10, sel ? C_ACC_SOFT : (hov ? C_CARD_HOV : C_CARD));
        r.text(x1 + 16, y1 + 18, preset(i), 13, sel ? C_TEXT : C_MUTED);
        if (sel) r.line(x1 + 14, y1 + 46, x1 + cw - 14, y1 + 46, 2, C_ACC);
        if (hov && g_down && !g_press_consumed) { cf::state::flags.skin_preset = i; g_press_consumed = true; }
    }
}
static void tab_world(Renderer &r, float x, float y, float w) {
    draw_section(r, x, y, w, "WORLD");
    float cy = y + 26;
    draw_toggle(r, x, cy, w, 48, "Arm 'kill all'", cf::state::flags.killall_armed); cy += 56;
    if (draw_button(r, x, cy, w, 48, "Execute: kill all enemies", C_WARN)) {
        cf::state::flags.killall_fire = true;
    }
}
static void tab_misc(Renderer &r, float x, float y, float w) {
    draw_section(r, x, y, w, "MISC");
    float cy = y + 26;
    draw_toggle(r, x, cy, w, 48, "God mode",         cf::state::flags.god);      cy += 56;
    draw_toggle(r, x, cy, w, 48, "Rapid fire",       cf::state::flags.rapid);    cy += 56;
    draw_toggle(r, x, cy, w, 48, "No spread",        cf::state::flags.nospread); cy += 56;
    draw_toggle(r, x, cy, w, 48, "Wallbang",         cf::state::flags.wallbang); cy += 56;
    draw_slider(r, x, cy, w, 54, "Speed multiplier", cf::state::flags.speed, 0.5f, 3.0f);
}

static void handle_touch() {
    TouchEv ev;
    while (poll_touch(ev)) {
        g_last_tx = ev.x; g_last_ty = ev.y;
        float fx1 = g_toggle_x, fy1 = g_toggle_y;
        float fx2 = fx1 + g_toggle_sz, fy2 = fy1 + g_toggle_sz;
        bool on_fab = inside(ev.x, ev.y, fx1, fy1, fx2, fy2);
        if (ev.action == 0) {
            g_down = true; g_press_consumed = false;
            if (on_fab) { g_dragging_fab = true; g_drag_dx = ev.x - fx1; g_drag_dy = ev.y - fy1; }
            else if (g_open.load() && inside(ev.x, ev.y, g_x, g_y, g_x + g_w, g_y + 60)) {
                g_dragging_panel = true; g_drag_dx = ev.x - g_x; g_drag_dy = ev.y - g_y;
            }
        } else if (ev.action == 1) {
            if (g_dragging_fab) { g_toggle_x = ev.x - g_drag_dx; g_toggle_y = ev.y - g_drag_dy; }
            else if (g_dragging_panel) { g_x = ev.x - g_drag_dx; g_y = ev.y - g_drag_dy; }
        } else {
            if (g_dragging_fab && on_fab) g_open = !g_open.load();
            g_dragging_fab = g_dragging_panel = false; g_down = false;
        }
    }
}

void install() {}

static void draw_fab(Renderer &r) {
    float x = g_toggle_x, y = g_toggle_y, s = g_toggle_sz;
    r.rquad(x, y, x + s, y + s, s * 0.5f, 0xE0171A22);
    r.line(x + s * 0.25f, y + s * 0.5f, x + s * 0.75f, y + s * 0.5f, 2, C_ACC);
    r.line(x + s * 0.5f,  y + s * 0.3f, x + s * 0.5f,  y + s * 0.7f, 2, C_ACC);
}

static void draw_panel(Renderer &r, int sw, int sh) {
    r.quad(0, 0, sw, sh, 0x88000000);
    r.rquad(g_x, g_y, g_x + g_w, g_y + g_h, 18, C_BG);
    r.rquad(g_x, g_y, g_x + g_w, g_y + 60, 18, C_BG2);
    r.text(g_x + 22, g_y + 20, "CF · Tuning bench", 16, C_TEXT);
    r.text(g_x + g_w - 92, g_y + 22, "v1.4.1-c7", 11, C_MUTED);
    r.line(g_x, g_y + 60, g_x + g_w, g_y + 60, 1, C_LINE);
    static const char *tabs[] = { "ESP", "Aim", "Move", "Skins", "World", "Misc" };
    float tx = g_x + 18, ty = g_y + 80;
    float tw = 128, th = 42;
    for (int i = 0; i < 6; ++i) {
        float y1 = ty + i * (th + 6);
        bool active = g_tab == i;
        bool hov = inside(g_last_tx, g_last_ty, tx, y1, tx + tw, y1 + th);
        r.rquad(tx, y1, tx + tw, y1 + th, 10, active ? C_ACC_SOFT : (hov ? C_CARD_HOV : C_CARD));
        if (active) r.rquad(tx, y1 + 10, tx + 3, y1 + th - 10, 2, C_ACC);
        r.text(tx + 18, y1 + th * 0.5f - 7, tabs[i], 14, active ? C_TEXT : C_MUTED);
        if (hov && g_down && !g_press_consumed) { g_tab = i; g_press_consumed = true; }
    }
    float cx = g_x + 18 + tw + 16, cy = g_y + 80;
    float cw = g_w - (cx - g_x) - 18;
    r.rquad(cx - 6, cy - 6, cx + cw + 6, g_y + g_h - 72, 12, 0x301B1E25);
    switch (g_tab) {
        case 0: tab_esp(r, cx, cy, cw);   break;
        case 1: tab_aim(r, cx, cy, cw);   break;
        case 2: tab_move(r, cx, cy, cw);  break;
        case 3: tab_skins(r, cx, cy, cw); break;
        case 4: tab_world(r, cx, cy, cw); break;
        case 5: tab_misc(r, cx, cy, cw);  break;
    }
    float fy = g_y + g_h - 46;
    r.line(g_x, fy, g_x + g_w, fy, 1, C_LINE);
    r.text(g_x + 22, fy + 16, "удерживай шапку чтобы перетащить", 11, C_MUTED);
}

void draw(int sw, int sh) {
    handle_touch();
    auto &r = Renderer::instance();
    r.begin(sw, sh);
    if (g_open.load()) draw_panel(r, sw, sh);
    draw_fab(r);
    r.end();
}

}
