precision highp float;
precision mediump sampler2DArray;
#include "common.glsl"
uniform sampler2DArray uAlbedo;
in vec2 vUv;
in vec4 vColor;
in vec3 vMisc;
in highp vec3 vRel;
out vec4 fragColor;
void main() {
    int kind = int(vMisc.x + 0.5);
    vec4 c = vColor;
    vec2 q = vUv * 2.0 - 1.0;
    if (kind == 0) {
        c.a *= smoothstep(1.0, 0.35, length(q));
    } else if (kind == 1) {
        c.a *= (1.0 - abs(q.x)) * smoothstep(1.0, 0.2, abs(q.y));
    } else if (kind == 2) {
        // block fragment: a small window of the block's texture
        vec4 t = texture(uAlbedo, vec3(vUv * 0.12 + vec2(vMisc.y), vMisc.z));
        if (t.a < 0.4) discard;
        c.rgb *= t.rgb;
    } else {
        float g = max(1.0 - length(q), 0.0);
        c.a *= g * g;
        fragColor = vec4(c.rgb * c.a, 0.0);   // additive glow (premultiplied, alpha 0)
        return;
    }
    if (kind != 3) {
        c.rgb = toDisplay(applyFog(c.rgb, vRel));
    }
    fragColor = vec4(c.rgb * c.a, c.a);        // premultiplied alpha
}
