#include "menu.h"
#include <mutex>
#include <deque>

namespace cf::menu {

struct TouchEv { float x, y; int action; };

static std::mutex g_mu;
static std::deque<TouchEv> g_q;

void on_touch(float x, float y, int action) {
    std::lock_guard<std::mutex> lk(g_mu);
    g_q.push_back({x, y, action});
    if (g_q.size() > 64) g_q.pop_front();
}

bool poll_touch(TouchEv &out) {
    std::lock_guard<std::mutex> lk(g_mu);
    if (g_q.empty()) return false;
    out = g_q.front(); g_q.pop_front();
    return true;
}
}

extern "C" JNIEXPORT void JNICALL
Java_com_cf_overlay_Bridge_feedTouch(JNIEnv*, jclass, jfloat x, jfloat y, jint a) {
    cf::menu::on_touch(x, y, a);
}
