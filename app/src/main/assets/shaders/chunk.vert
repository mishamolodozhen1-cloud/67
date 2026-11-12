precision highp float;
precision highp int;
layout(location = 0) in highp uvec2 aData;

uniform mat4 uViewProj;      // camera-relative view-projection
uniform vec3 uChunkOffset;   // chunk origin - camera position
uniform vec3 uChunkUv;       // chunk origin mod 64 (keeps world-space UVs precise)
uniform float uTime;
uniform vec4 uWind;          // xy: direction, z: strength, w: gustiness
#ifdef SHADOWS
uniform mat4 uShadowMatrix;  // camera-relative world -> shadow texture space
out vec4 vShadowCoord;
#endif

out highp vec3 vRel;         // camera-relative position
out highp vec3 vUvw;         // uv + array layer
out mediump vec4 vLight;     // ao, sky, block, emissive
flat out mediump vec3 vNormal;
flat out mediump float vFoliage;

const vec3 NORMALS[7] = vec3[7](
    vec3(1.0, 0.0, 0.0), vec3(-1.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, -1.0, 0.0),
    vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, -1.0), vec3(0.0, 1.0, 0.0));

void main() {
    uint w0 = aData.x;
    uint w1 = aData.y;
    vec3 p = vec3(float(w0 & 0x1FFu), float((w0 >> 9u) & 0xFFFu), float((w0 >> 21u) & 0x1FFu)) * 0.0625;
    float layer = float(w1 & 0xFFu);
    int flags = int((w1 >> 8u) & 0xFFu);
    int ni = int((w1 >> 16u) & 7u);
    float ao = float((w1 >> 19u) & 3u) * 0.3333;
    float sky = float((w1 >> 21u) & 15u) * 0.0667;
    float blk = float((w1 >> 25u) & 15u) * 0.0667;

    vec3 wp = p + uChunkUv;
    vec2 uv;
    if ((flags & 16) != 0) {
        int corner = gl_VertexID & 3;
        uv = vec2((corner == 1 || corner == 2) ? 1.0 : 0.0, corner >= 2 ? 0.0 : 1.0);
#ifdef SWAY
        if ((flags & 8) != 0 && corner >= 2) {
            float ph = wp.x * 0.9 + wp.z * 1.3;
            float s = sin(uTime * 1.7 + ph) * 0.6 + sin(uTime * 3.3 + ph * 2.1) * 0.25 * uWind.w;
            p.xz += uWind.xy * (s * 0.07 + 0.05) * uWind.z;
        }
#endif
    } else {
        if (ni <= 1) uv = vec2(wp.z, -wp.y);
        else if (ni <= 3) uv = wp.xz;
        else uv = vec2(wp.x, -wp.y);
        if ((flags & 4) != 0) uv = uv.yx;
        int sc = flags & 3;
        uv *= (sc == 0) ? 1.0 : ((sc == 1) ? 0.5 : 0.25);
#ifdef SWAY
        if ((flags & 32) != 0) {
            // leaf flutter: displacement depends only on position, so shared vertices stay welded
            float ph = dot(wp, vec3(1.3, 2.1, 1.7));
            p += vec3(sin(uTime * 1.3 + ph), sin(uTime * 1.9 + ph * 1.7) * 0.6, cos(uTime * 1.1 + ph)) * 0.022 * uWind.z;
        }
#endif
    }
    vec3 rel = p + uChunkOffset;
    vRel = rel;
    vUvw = vec3(uv, layer);
    vLight = vec4(ao, sky, blk, (flags & 128) != 0 ? 1.0 : 0.0);
    vNormal = NORMALS[ni];
    vFoliage = ni == 6 ? 1.0 : 0.0;
#ifdef SHADOWS
    vShadowCoord = uShadowMatrix * vec4(rel + NORMALS[ni] * 0.06, 1.0);
#endif
    gl_Position = uViewProj * vec4(rel, 1.0);
}
