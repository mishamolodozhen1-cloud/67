precision highp float;
precision highp int;
precision mediump sampler2DArray;
#include "common.glsl"
#include "shadow.glsl"

uniform sampler2DArray uAlbedo;
#ifdef NORMAL_MAP
uniform sampler2DArray uNormalMap;
#endif

in highp vec3 vRel;
in highp vec3 vUvw;
in mediump vec4 vLight;
flat in mediump vec3 vNormal;
flat in mediump float vFoliage;
#ifdef SHADOWS
in vec4 vShadowCoord;
#endif
out vec4 fragColor;

void main() {
    vec4 tex = texture(uAlbedo, vUvw);
#ifdef ALPHA_TEST
    if (tex.a < 0.42) discard;
#endif
    vec3 albedo = tex.rgb;
    vec3 N = vNormal;
    float rough = 0.9;
    float dist = length(vRel);
#ifdef NORMAL_MAP
    if (vFoliage < 0.5 && dist < 48.0) {
        vec4 nm = texture(uNormalMap, vUvw);
        vec2 t = nm.xy * 2.0 - 1.0;
        float fade = 1.0 - smoothstep(32.0, 48.0, dist);
        t *= fade;
        // tangent frame of an axis-aligned face (matches the UV mapping in chunk.vert)
        vec3 T = abs(N.y) > 0.5 ? vec3(1.0, 0.0, 0.0) : (abs(N.x) > 0.5 ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0));
        vec3 B = abs(N.y) > 0.5 ? vec3(0.0, 0.0, 1.0) : vec3(0.0, -1.0, 0.0);
        N = normalize(N + T * t.x + B * t.y);
        rough = nm.b;
    }
#endif
    float ao = 0.35 + 0.65 * vLight.x;
    float sky = vLight.y;
    float skyLit = sky * sky;
    float ndl = max(dot(N, uSunDir), 0.0);
    if (vFoliage > 0.5) ndl = 0.55 + 0.25 * max(uSunDir.y, 0.0);
#ifdef ALPHA_TEST
    // leaves: wrap lighting so canopies read as soft volumes
    ndl = mix(ndl, 0.6, 0.45);
#endif
    float sunVis = smoothstep(0.55, 0.95, sky);
#ifdef SHADOWS
    sunVis *= shadowTerm(vShadowCoord, dist);
#endif
    vec3 light = uSunColor * (ndl * sunVis);
    light += mix(uAmbientGround, uAmbientSky, N.y * 0.5 + 0.5) * (skyLit * ao);
    float bl = vLight.z;
    light += vec3(1.0, 0.62, 0.32) * (bl * bl * 1.9 * ao);
    light += vec3(0.012, 0.013, 0.016) * ao;          // never fully black underground
    light += uFog.w * skyLit * 0.8;                    // lightning flash
    float wet = uFog.z * skyLit * max(N.y, 0.0);
    albedo *= 1.0 - 0.3 * wet;
    vec3 color = albedo * light;
#ifdef NORMAL_MAP
    vec3 V = normalize(-vRel);
    vec3 H = normalize(V + uSunDir);
    float gloss = (1.0 - rough) + wet * 0.5;
    float spec = pow(max(dot(N, H), 0.0), 8.0 + gloss * 90.0) * gloss * gloss * 1.2;
    color += uSunColor * (spec * sunVis * ndl);
#endif
    color = mix(color, tex.rgb * 2.2, vLight.w);       // emissive surfaces
    color = applyFog(color, vRel);
    fragColor = vec4(toDisplay(color), 1.0);
}
