precision highp float;
layout(location = 0) in vec2 aCorner;       // per-vertex quad corner (-1..1)
layout(location = 1) in vec4 aCenterSize;   // per-instance: camera-relative xyz, size
layout(location = 2) in vec4 aColor;        // per-instance colour
layout(location = 3) in vec4 aMisc;         // per-instance: kind, stretch, layer, rotation
uniform mat4 uViewProj;
uniform vec3 uCamRight;
uniform vec3 uCamUp;
out vec2 vUv;
out vec4 vColor;
out vec3 vMisc;
out highp vec3 vRel;
void main() {
    float kind = aMisc.x;
    vec3 right = uCamRight;
    vec3 up = uCamUp;
    vec2 c = aCorner;
    if (kind > 0.5 && kind < 1.5) { up = normalize(vec3(aMisc.w, -1.0, 0.0)); c.y *= aMisc.y; c.x *= 0.5; }
    else if (aMisc.w != 0.0) {
        float s = sin(aMisc.w), co = cos(aMisc.w);
        c = vec2(c.x * co - c.y * s, c.x * s + c.y * co);
    }
    vec3 pos = aCenterSize.xyz + (right * c.x + up * c.y) * aCenterSize.w;
    vRel = pos;
    vUv = aCorner * 0.5 + 0.5;
    vColor = aColor;
    vMisc = aMisc.xyz;
    gl_Position = uViewProj * vec4(pos, 1.0);
}
