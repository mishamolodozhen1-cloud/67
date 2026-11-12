precision highp float;
precision highp int;
layout(location = 0) in highp uvec2 aData;
uniform mat4 uViewProj;
uniform vec3 uChunkOffset;
#ifdef ALPHA_TEST
uniform vec3 uChunkUv;
out highp vec3 vUvw;
#endif
void main() {
    uint w0 = aData.x;
    uint w1 = aData.y;
    vec3 p = vec3(float(w0 & 0x1FFu), float((w0 >> 9u) & 0xFFFu), float((w0 >> 21u) & 0x1FFu)) * 0.0625;
#ifdef ALPHA_TEST
    int flags = int((w1 >> 8u) & 0xFFu);
    int ni = int((w1 >> 16u) & 7u);
    vec2 uv;
    if ((flags & 16) != 0) {
        int corner = gl_VertexID & 3;
        uv = vec2((corner == 1 || corner == 2) ? 1.0 : 0.0, corner >= 2 ? 0.0 : 1.0);
    } else {
        vec3 wp = p + uChunkUv;
        if (ni <= 1) uv = vec2(wp.z, -wp.y);
        else if (ni <= 3) uv = wp.xz;
        else uv = vec2(wp.x, -wp.y);
        if ((flags & 4) != 0) uv = uv.yx;
        int sc = flags & 3;
        uv *= (sc == 0) ? 1.0 : ((sc == 1) ? 0.5 : 0.25);
    }
    vUvw = vec3(uv, float(w1 & 0xFFu));
#endif
    gl_Position = uViewProj * vec4(p + uChunkOffset, 1.0);
}
