precision highp float;
#include "common.glsl"
uniform float uNearRadius;   // far terrain is hidden inside the detailed voxel radius
in highp vec3 vRel;
in mediump vec3 vNormal;
in mediump vec4 vColor;
out vec4 fragColor;
void main() {
    float d = length(vRel.xz);
    if (d < uNearRadius) discard;
    vec3 N = normalize(vNormal);
    vec3 color;
    vec3 base = vColor.rgb * vColor.rgb;   // stored sqrt-encoded
    if (vColor.a < 0.5) {
        // distant water: sky reflection by fresnel over a deep-water body colour
        vec3 V = normalize(-vRel);
        float fres = min(0.02 + 0.98 * pow(1.0 - max(V.y, 0.0), 5.0), 0.7);
        vec3 R = reflect(-V, vec3(0.0, 1.0, 0.0));
        R = normalize(vec3(R.x, max(R.y, 0.14), R.z));   // rough water never mirrors the exact horizon
        vec3 body = base * (uAmbientSky * 2.0 + uSunColor * 0.27);
        float spec = pow(max(dot(R, uSunDir), 0.0), 180.0);
        color = mix(body, skyColor(R), fres) + uSunColor * spec * 1.5;
    } else {
        float ndl = max(dot(N, uSunDir), 0.0);
        vec3 light = uSunColor * ndl + mix(uAmbientGround, uAmbientSky, N.y * 0.5 + 0.5);
        color = base * light;
    }
    color = applyFog(color, vRel);
    fragColor = vec4(toDisplay(color), 1.0);
}
