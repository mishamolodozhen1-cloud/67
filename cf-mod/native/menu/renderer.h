#pragma once
#include <cstdint>
namespace cf::menu {

class Renderer {
public:
    static Renderer &instance();
    void begin(int sw, int sh);
    void end();

    void quad(float x1, float y1, float x2, float y2, uint32_t rgba);
    void rquad(float x1, float y1, float x2, float y2, float radius, uint32_t rgba);
    void line(float x1, float y1, float x2, float y2, float thick, uint32_t rgba);
    void text(float x, float y, const char *s, float size_px, uint32_t rgba);
    void glyph(float x, float y, int code, float size_px, uint32_t rgba);

private:
    Renderer();
    void ensure_init();
    unsigned prog_quad_ = 0, prog_text_ = 0;
    unsigned vbo_ = 0, vao_ = 0;
    unsigned tex_font_ = 0;
    int sw_ = 0, sh_ = 0;
    bool inited_ = false;
};
}
