#pragma once
#include <array>

namespace cf::world {

struct V3  { float x, y, z; };
struct V4  { float x, y, z, w; };
struct Mat4 { float m[16]; };

bool  world_to_screen(const V3 &w, float out[2], int sw, int sh);
Mat4  view_projection();
void  set_view_projection(const Mat4 &);
float dist(const V3 &a, const V3 &b);
}
