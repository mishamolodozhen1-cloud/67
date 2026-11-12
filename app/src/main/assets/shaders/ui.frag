precision highp float;
uniform sampler2D uFont;
uniform sampler2D uIcons;
uniform sampler2D uAux;
in vec2 vUv;
in vec4 vColor;
in vec4 vParams;
out vec4 fragColor;
void main() {
    int mode = int(vParams.w + 0.5);
    vec4 c = vColor;
    if (mode == 0) {
        // rounded rectangle; vUv = pixel offset from the centre
        vec2 q = abs(vUv) - (vParams.xy - vec2(vParams.z));
        float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - vParams.z;
        c.a *= clamp(0.5 - d, 0.0, 1.0);
    } else if (mode == 1) {
        float sd = texture(uFont, vUv).r;
        float w = max(fwidth(sd) * 0.75, 0.02);
        c.a *= smoothstep(0.5 - w, 0.5 + w, sd);
    } else if (mode == 2) {
        c *= texture(uIcons, vUv);
    } else if (mode == 3) {
        // ring: radius = halfW - thickness, thickness = vParams.z
        float d = abs(length(vUv) - (vParams.x - vParams.z)) - vParams.z;
        c.a *= clamp(0.5 - d, 0.0, 1.0);
    } else {
        c *= texture(uAux, vUv);
    }
    if (c.a < 0.004) discard;
    fragColor = c;
}
