#include "renderer.h"
#include "font.h"
#include "../util/log.h"
#include <GLES3/gl3.h>
#include <string>
#include <vector>
#include <cmath>

namespace cf::menu {

static const char *VS_QUAD = R"(#version 300 es
layout(location=0) in vec2 pos;
uniform vec2 uScreen;
void main() {
    vec2 ndc = vec2((pos.x / uScreen.x) * 2.0 - 1.0,
                    1.0 - (pos.y / uScreen.y) * 2.0);
    gl_Position = vec4(ndc, 0.0, 1.0);
}
)";
static const char *FS_QUAD = R"(#version 300 es
precision mediump float;
uniform vec4 uColor;
out vec4 fragColor;
void main() { fragColor = uColor; }
)";
static const char *VS_TEXT = R"(#version 300 es
layout(location=0) in vec2 pos;
layout(location=1) in vec2 uv;
uniform vec2 uScreen;
out vec2 vUv;
void main() {
    vec2 ndc = vec2((pos.x / uScreen.x) * 2.0 - 1.0,
                    1.0 - (pos.y / uScreen.y) * 2.0);
    gl_Position = vec4(ndc, 0.0, 1.0);
    vUv = uv;
}
)";
static const char *FS_TEXT = R"(#version 300 es
precision mediump float;
in vec2 vUv;
uniform sampler2D uAtlas;
uniform vec4 uColor;
out vec4 fragColor;
void main() {
    float a = texture(uAtlas, vUv).r;
    fragColor = vec4(uColor.rgb, uColor.a * a);
}
)";

static unsigned compile(GLenum type, const char *src) {
    unsigned s = glCreateShader(type);
    glShaderSource(s, 1, &src, nullptr);
    glCompileShader(s);
    GLint ok = 0; glGetShaderiv(s, GL_COMPILE_STATUS, &ok);
    if (!ok) { char log[1024]; glGetShaderInfoLog(s, 1024, nullptr, log); CFERR("shader: %s", log); }
    return s;
}
static unsigned link(unsigned vs, unsigned fs) {
    unsigned p = glCreateProgram();
    glAttachShader(p, vs); glAttachShader(p, fs); glLinkProgram(p);
    return p;
}
static inline void rgba_unpack(uint32_t c, float o[4]) {
    o[3] = ((c >> 24) & 0xFF) / 255.f;
    o[0] = ((c >> 16) & 0xFF) / 255.f;
    o[1] = ((c >>  8) & 0xFF) / 255.f;
    o[2] = ( c        & 0xFF) / 255.f;
}

Renderer &Renderer::instance() { static Renderer r; return r; }
Renderer::Renderer() = default;

void Renderer::ensure_init() {
    if (inited_) return;
    unsigned vs1 = compile(GL_VERTEX_SHADER,   VS_QUAD);
    unsigned fs1 = compile(GL_FRAGMENT_SHADER, FS_QUAD);
    prog_quad_ = link(vs1, fs1);
    unsigned vs2 = compile(GL_VERTEX_SHADER,   VS_TEXT);
    unsigned fs2 = compile(GL_FRAGMENT_SHADER, FS_TEXT);
    prog_text_ = link(vs2, fs2);
    glGenVertexArrays(1, &vao_);
    glGenBuffers(1, &vbo_);
    tex_font_ = cf::menu::font_atlas_tex();
    inited_ = true;
}

void Renderer::begin(int sw, int sh) {
    ensure_init();
    sw_ = sw; sh_ = sh;
    glBindVertexArray(vao_);
    glBindBuffer(GL_ARRAY_BUFFER, vbo_);
}
void Renderer::end() {
    glBindBuffer(GL_ARRAY_BUFFER, 0);
    glBindVertexArray(0);
    glUseProgram(0);
}

void Renderer::quad(float x1, float y1, float x2, float y2, uint32_t rgba) {
    glUseProgram(prog_quad_);
    glUniform2f(glGetUniformLocation(prog_quad_, "uScreen"), (float)sw_, (float)sh_);
    float col[4]; rgba_unpack(rgba, col);
    glUniform4fv(glGetUniformLocation(prog_quad_, "uColor"), 1, col);
    float v[12] = { x1,y1, x2,y1, x2,y2, x1,y1, x2,y2, x1,y2 };
    glBufferData(GL_ARRAY_BUFFER, sizeof(v), v, GL_STREAM_DRAW);
    glEnableVertexAttribArray(0);
    glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 8, (void*)0);
    glDrawArrays(GL_TRIANGLES, 0, 6);
}

void Renderer::rquad(float x1, float y1, float x2, float y2, float r, uint32_t rgba) {
    if (r < 0.5f) { quad(x1,y1,x2,y2,rgba); return; }
    quad(x1 + r, y1,     x2 - r, y2,     rgba);
    quad(x1,     y1 + r, x1 + r, y2 - r, rgba);
    quad(x2 - r, y1 + r, x2,     y2 - r, rgba);
    glUseProgram(prog_quad_);
    glUniform2f(glGetUniformLocation(prog_quad_, "uScreen"), (float)sw_, (float)sh_);
    float col[4]; rgba_unpack(rgba, col);
    glUniform4fv(glGetUniformLocation(prog_quad_, "uColor"), 1, col);
    const int seg = 10;
    struct Corner { float cx, cy, a0; };
    Corner cs[4] = {
        { x1 + r, y1 + r, 3.14159265f },
        { x2 - r, y1 + r, 4.71238898f },
        { x2 - r, y2 - r, 0.f },
        { x1 + r, y2 - r, 1.57079632f },
    };
    std::vector<float> v; v.reserve((seg+2)*2*4);
    for (auto &c : cs) {
        float cx = c.cx, cy = c.cy;
        v.push_back(cx); v.push_back(cy);
        for (int i = 0; i <= seg; ++i) {
            float a = c.a0 + (1.57079632f * i / seg);
            v.push_back(cx + cosf(a) * r);
            v.push_back(cy + sinf(a) * r);
        }
    }
    glBufferData(GL_ARRAY_BUFFER, v.size()*sizeof(float), v.data(), GL_STREAM_DRAW);
    glEnableVertexAttribArray(0);
    glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 8, (void*)0);
    for (int k = 0; k < 4; ++k)
        glDrawArrays(GL_TRIANGLE_FAN, k * (seg + 2), seg + 2);
}

void Renderer::line(float x1, float y1, float x2, float y2, float thick, uint32_t rgba) {
    float dx = x2 - x1, dy = y2 - y1;
    float len = sqrtf(dx*dx + dy*dy); if (len < 0.0001f) return;
    float nx = -dy / len * thick * 0.5f;
    float ny =  dx / len * thick * 0.5f;
    float v[12] = {
        x1 + nx, y1 + ny,  x2 + nx, y2 + ny,  x2 - nx, y2 - ny,
        x1 + nx, y1 + ny,  x2 - nx, y2 - ny,  x1 - nx, y1 - ny,
    };
    glUseProgram(prog_quad_);
    glUniform2f(glGetUniformLocation(prog_quad_, "uScreen"), (float)sw_, (float)sh_);
    float col[4]; rgba_unpack(rgba, col);
    glUniform4fv(glGetUniformLocation(prog_quad_, "uColor"), 1, col);
    glBufferData(GL_ARRAY_BUFFER, sizeof(v), v, GL_STREAM_DRAW);
    glEnableVertexAttribArray(0);
    glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 8, (void*)0);
    glDrawArrays(GL_TRIANGLES, 0, 6);
}

void Renderer::text(float x, float y, const char *s, float size_px, uint32_t rgba) {
    glUseProgram(prog_text_);
    glUniform2f(glGetUniformLocation(prog_text_, "uScreen"), (float)sw_, (float)sh_);
    float col[4]; rgba_unpack(rgba, col);
    glUniform4fv(glGetUniformLocation(prog_text_, "uColor"), 1, col);
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, tex_font_);
    glUniform1i(glGetUniformLocation(prog_text_, "uAtlas"), 0);

    float cx = x;
    for (const char *p = s; *p; ++p) {
        auto g = cf::menu::font_glyph((unsigned char)*p);
        float gw = g.w * (size_px / g.base);
        float gh = g.h * (size_px / g.base);
        float x1 = cx + g.off_x, y1 = y + g.off_y;
        float x2 = x1 + gw,      y2 = y1 + gh;
        float v[24] = {
            x1,y1, g.u0,g.v0,  x2,y1, g.u1,g.v0,  x2,y2, g.u1,g.v1,
            x1,y1, g.u0,g.v0,  x2,y2, g.u1,g.v1,  x1,y2, g.u0,g.v1,
        };
        glBufferData(GL_ARRAY_BUFFER, sizeof(v), v, GL_STREAM_DRAW);
        glEnableVertexAttribArray(0);
        glEnableVertexAttribArray(1);
        glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 16, (void*)0);
        glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, 16, (void*)8);
        glDrawArrays(GL_TRIANGLES, 0, 6);
        cx += g.advance * (size_px / g.base);
    }
}

void Renderer::glyph(float x, float y, int code, float size_px, uint32_t rgba) {
    char s[2] = { (char)code, 0 };
    text(x, y, s, size_px, rgba);
}

}
