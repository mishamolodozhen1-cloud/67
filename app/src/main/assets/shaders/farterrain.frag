precision highp float;
#include "common.glsl"
uniform float uNearRadius;   // far terrain is hidden inside the detailed voxel radius
in highp vec3 vRel;
in mediump vec3 vNormal;
in mediump vec3 vColor;
out vec4 fragColor;
void main() {
    float d = length(vRel.xz);
    if (d < uNearRadius) discard;
    vec3 N = normalize(vNormal);
    float ndl = max(dot(N, uSunDir), 0.0);
    vec3 light = uSunColor * ndl + mix(uAmbientGround, uAmbientSky, N.y * 0.5 + 0.5);
    vec3 color = vColor * light;
    color = applyFog(color, vRel);
    fragColor = vec4(toDisplay(color), 1.0);
}
