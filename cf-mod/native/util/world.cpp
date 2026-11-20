#include "world.h"
#include <atomic>
#include <math.h>
#include <string.h>

namespace cf::world {

static Mat4 g_vp{};
static std::atomic_flag g_lock = ATOMIC_FLAG_INIT;

void set_view_projection(const Mat4 &m) {
    while (g_lock.test_and_set(std::memory_order_acquire)) {}
    memcpy(&g_vp, &m, sizeof(Mat4));
    g_lock.clear(std::memory_order_release);
}

Mat4 view_projection() {
    while (g_lock.test_and_set(std::memory_order_acquire)) {}
    Mat4 c = g_vp;
    g_lock.clear(std::memory_order_release);
    return c;
}

bool world_to_screen(const V3 &w, float out[2], int sw, int sh) {
    Mat4 vp = view_projection();
    V4 c;
    c.x = vp.m[0]*w.x + vp.m[4]*w.y + vp.m[8] *w.z + vp.m[12];
    c.y = vp.m[1]*w.x + vp.m[5]*w.y + vp.m[9] *w.z + vp.m[13];
    c.z = vp.m[2]*w.x + vp.m[6]*w.y + vp.m[10]*w.z + vp.m[14];
    c.w = vp.m[3]*w.x + vp.m[7]*w.y + vp.m[11]*w.z + vp.m[15];
    if (c.w < 0.001f) return false;
    float inv = 1.f / c.w;
    out[0] = (c.x * inv * 0.5f + 0.5f) * sw;
    out[1] = (1.f - (c.y * inv * 0.5f + 0.5f)) * sh;
    return true;
}

float dist(const V3 &a, const V3 &b) {
    float dx = a.x - b.x, dy = a.y - b.y, dz = a.z - b.z;
    return sqrtf(dx*dx + dy*dy + dz*dz);
}
}
