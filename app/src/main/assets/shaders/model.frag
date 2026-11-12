precision highp float;
#include "common.glsl"
#include "shadow.glsl"
uniform sampler2D uNoise;
uniform vec4 uEntityLight;   // x: sky light 0..1, y: block light 0..1, z: hurt flash, w: alpha
in highp vec3 vRel;
in mediump vec3 vNormal;
in mediump vec4 vColor;
in highp vec3 vObj;
#ifdef SHADOWS
in vec4 vShadowCoord;
#endif
out vec4 fragColor;
void main() {
    vec3 N = normalize(vNormal);
    // fur / cloth micro detail from tiling noise in object space
    float n = texture(uNoise, vObj.xz * 1.7 + vObj.y * 0.9).r;
    float n2 = texture(uNoise, vObj.xy * 5.3 + vObj.z * 2.1).g;
    vec3 albedo = vColor.rgb * (0.82 + 0.3 * n + 0.12 * (n2 - 0.5) * vColor.a);
    float sky = uEntityLight.x;
    float ndl = max(dot(N, uSunDir), 0.0);
    float wrap = max(dot(N, uSunDir) * 0.6 + 0.4, 0.0);
    float sunVis = smoothstep(0.55, 0.95, sky);
#ifdef SHADOWS
    sunVis *= shadowTerm(vShadowCoord, length(vRel));
#endif
    vec3 light = uSunColor * (mix(ndl, wrap, 0.5) * sunVis);
    light += mix(uAmbientGround, uAmbientSky, N.y * 0.5 + 0.5) * (sky * sky);
    light += vec3(1.0, 0.62, 0.32) * (uEntityLight.y * uEntityLight.y * 1.9);
    light += vec3(0.012, 0.013, 0.016) + uFog.w * sky * 0.8;
    vec3 V = normalize(-vRel);
    float rim = pow(1.0 - max(dot(N, V), 0.0), 3.0);
    vec3 color = albedo * light + uAmbientSky * rim * 0.25 * sky * sky;
    color = mix(color, vec3(0.9, 0.1, 0.05), uEntityLight.z);
    color = applyFog(color, vRel);
    fragColor = vec4(toDisplay(color), uEntityLight.w);
}
