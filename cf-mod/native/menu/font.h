#pragma once
#include <cstdint>
namespace cf::menu {

struct Glyph {
    float u0, v0, u1, v1;
    float w, h, off_x, off_y, advance, base;
};

unsigned font_atlas_tex();
Glyph    font_glyph(unsigned char);
}
