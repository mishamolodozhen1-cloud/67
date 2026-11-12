precision highp float;
precision highp int;
#include "common.glsl"
uniform sampler2D uWaterNormal;
uniform float uTime;
uniform vec3 uChunkUv;
uniform vec3 uChunkOffset;
#if WATER_QUALITY >= 1
uniform sampler2D uSceneColor;
uniform sampler2D uSceneDepth;
uniform vec2 uInvScreen;
uniform vec2 uNearFar;
#endif

in highp vec3 vRel;
in highp vec3 vUvw;
in mediump vec4 vLight;
flat in mediump vec3 vNormal;
out vec4 fragColor;

#if WATER_QUALITY >= 1
float linearDepth(float d) {
    float z = d * 2.0 - 1.0;
    return 2.0 * uNearFar.x * uNearFar.y / (uNearFar.y + uNearFar.x - z * (uNearFar.y - uNearFar.x));
}
#endif

void main() {
    // world-space xz (mod 64) reconstructed from the camera-relative position
    vec2 wxz = (vRel - uChunkOffset + uChunkUv).xz;
    vec3 N = vNormal;
    float top = step(0.5, vNormal.y);
    vec2 n1 = texture(uWaterNormal, wxz * 0.085 + vec2(uTime * 0.011, uTime * 0.007)).xy * 2.0 - 1.0;
    vec2 n2 = texture(uWaterNormal, wxz * 0.23 - vec2(uTime * 0.016, -uTime * 0.012)).xy * 2.0 - 1.0;
    vec2 nn = (n1 + n2 * 0.6) * top;
    float dist = length(vRel);
    nn *= 1.0 / (1.0 + dist * 0.012);
    N = normalize(vec3(nn.x * 0.55, 1.0, nn.y * 0.55) * top + vNormal * (1.0 - top));

    vec3 V = -vRel / max(dist, 0.001);
    bool under = !gl_FrontFacing && top > 0.5;
    float ndv = max(dot(N, V), 0.0);
    if (under) ndv = max(dot(-N, V), 0.0);
    float fres = 0.02 + 0.98 * pow(1.0 - ndv, 5.0);

    float sky = vLight.y;
    float skyLit = sky * sky;
    vec3 R = reflect(-V, N);
    R.y = abs(R.y);
    vec3 refl = skyColor(R) * skyLit;
    float sunVis = smoothstep(0.55, 0.95, sky);
    float spec = pow(max(dot(R, uSunDir), 0.0), 260.0);
    vec3 sunSpec = uSunColor * spec * 2.6 * sunVis;

    vec3 ambient = (uAmbientSky * skyLit + vec3(0.01)) ;
    vec3 deep = vec3(0.012, 0.085, 0.11) * (ambient * 2.0 + uSunColor * 0.25 * sunVis);
    vec3 shallow = vec3(0.05, 0.26, 0.24) * (ambient * 2.0 + uSunColor * 0.3 * sunVis);

#if WATER_QUALITY >= 1
    vec2 suv = gl_FragCoord.xy * uInvScreen;
    float waterZ = linearDepth(gl_FragCoord.z);
    float sceneZ = linearDepth(texture(uSceneDepth, suv).r);
    float depth = max(sceneZ - waterZ, 0.0);
    vec2 duv = suv + nn * 0.025 * clamp(depth * 0.5, 0.0, 1.0);
    float z2 = linearDepth(texture(uSceneDepth, duv).r);
    if (z2 < waterZ) duv = suv; else depth = max(z2 - waterZ, 0.0);
    vec3 scene = texture(uSceneColor, duv).rgb;          // display space
    vec3 trans = exp(-depth * vec3(0.42, 0.13, 0.09));
    vec3 waterCol = toDisplay(mix(deep, shallow, exp(-depth * 0.35)));
    vec3 body = scene * trans + waterCol * (1.0 - trans.g);
    vec3 surface = toDisplay(applyFog(refl + sunSpec, vRel));
    vec3 col = mix(body, surface, under ? 0.15 : fres);
    // shoreline foam
    float foamN = texture(uWaterNormal, wxz * 0.35 + vec2(uTime * 0.03, 0.0)).b;
    float foam = smoothstep(0.55, 0.0, depth) * smoothstep(0.35, 0.75, foamN + (0.45 - depth)) * top;
    col = mix(col, vec3(0.92, 0.95, 0.96) * min(1.0, 0.35 + skyLit), foam * 0.85 * (1.0 - float(under)));
    // far water fades into the fog like everything else
    float x = dist * uFog.x;
    float f = clamp(1.0 - exp(-x * sqrt(x)), 0.0, 1.0);
    col = mix(col, toDisplay(fogColor(-V)), f * 0.85);
    fragColor = vec4(col, 1.0);
#else
    vec3 col = mix(mix(deep, shallow, 0.4), refl, fres) + sunSpec;
    col = applyFog(col, vRel);
    fragColor = vec4(toDisplay(col), under ? 0.5 : (0.72 + 0.26 * fres));
#endif
}
