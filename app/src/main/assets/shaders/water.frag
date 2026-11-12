precision highp float;
precision highp int;
#include "common.glsl"
// Water surface: layered wind-driven normals, Fresnel reflection of the sky with clouds
// (plus screen-space reflections on the high tier), refraction with depth absorption and
// in-scattering, animated shoreline foam, whitecaps and sun glitter.
uniform sampler2D uWaterNormal;   // RG: normal, B: foam noise
uniform sampler2D uNoise;
uniform float uTime;
uniform vec4 uWind;
uniform vec3 uChunkUv;
uniform vec3 uChunkOffset;
uniform vec4 uCloud;
uniform vec2 uCloudOffset;
#if WATER_QUALITY >= 1
uniform sampler2D uSceneColor;
uniform sampler2D uSceneDepth;
uniform vec2 uInvScreen;
uniform vec2 uNearFar;
#endif
#if WATER_QUALITY >= 2
uniform mat4 uViewProj;
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

// sky + cloud layer as seen in a reflection
vec3 reflectedSky(vec3 R) {
    vec3 c = skyColor(R);
    if (R.y > 0.02) {
        vec2 p = (R.xz / R.y) * 0.035 + uCloudOffset + vec2(uCloud.y, uCloud.y * 0.35);
        float den = texture(uNoise, p * 0.5).r * 0.55 + texture(uNoise, p * 1.3 + vec2(0.37, 0.11)).g * 0.28 + 0.1;
        float cover = smoothstep(1.0 - uCloud.x, 1.0 - uCloud.x + 0.2, den + 0.05) * smoothstep(0.02, 0.2, R.y);
        vec3 cc = mix(uAmbientSky * 0.9, uSunColor * 0.4 + uAmbientSky * 1.5, 0.55) * (1.0 - uCloud.z * 0.5);
        c = mix(c, cc, cover * 0.85);
    }
    return c;
}

void main() {
    // world-space xz (mod 64); every texture scale below is a multiple of 1/64 so tiles wrap seamlessly
    vec2 wxz = (vRel - uChunkOffset + uChunkUv).xz;
    float top = step(0.5, vNormal.y);
    float dist = length(vRel);
    vec3 V = -vRel / max(dist, 0.001);
    bool under = !gl_FrontFacing && top > 0.5;

    // --- surface normal: swell + chop + ripples drifting with the wind
    vec2 flow = uWind.xy;
    float chop = 0.46 + 0.26 * uWind.z;
    vec2 n1 = texture(uWaterNormal, wxz * 0.046875 + flow * uTime * 0.012).xy * 2.0 - 1.0;
    vec2 n2 = texture(uWaterNormal, wxz * 0.109375 - flow.yx * uTime * 0.017 + vec2(0.37, 0.13)).xy * 2.0 - 1.0;
    vec2 n3 = texture(uWaterNormal, wxz * 0.3125 + flow * uTime * 0.034 + vec2(0.11, 0.71)).xy * 2.0 - 1.0;
    float rippleFade = 1.0 / (1.0 + dist * 0.035);
    vec2 nn = (n1 * 0.62 + n2 * 0.40 + n3 * 0.30 * rippleFade) * chop * top;
    // distant water averages out: flatten the normal with distance to avoid noisy shimmer
    vec2 nGeo = nn / (1.0 + dist * 0.010);
    vec3 N = normalize(vec3(nGeo.x, 1.0, nGeo.y) * top + vNormal * (1.0 - top));
    vec3 Nspec = normalize(vec3(nn.x * 1.3, 1.0, nn.y * 1.3) * top + vNormal * (1.0 - top));

    float ndv = max(dot(under ? -N : N, V), 0.0);
    float fres = min(0.02 + 0.98 * pow(1.0 - ndv, 5.0), 0.86);

    float sky = vLight.y;
    float skyLit = sky * sky;
    float sunVis = smoothstep(0.55, 0.95, sky);

    // --- reflection
    vec3 R = reflect(-V, N);
    R = normalize(vec3(R.x, max(abs(R.y), 0.06), R.z));
    vec3 refl = reflectedSky(R) * skyLit;
    // sun glitter: tight highlight on the fine normal plus a broad sheen
    vec3 H = normalize(V + uSunDir);
    float nh = max(dot(Nspec, H), 0.0);
    float glitter = pow(nh, 520.0) * 7.0 + pow(nh, 70.0) * 0.22;
    vec3 sunSpec = uSunColor * glitter * sunVis;

    // --- water body colours (linear)
    vec3 lightIn = uAmbientSky * 1.7 * skyLit + uSunColor * 0.42 * sunVis * max(uSunDir.y, 0.0) + vec3(0.004);
    vec3 deepCol = vec3(0.010, 0.060, 0.095) * lightIn;
    vec3 shallowCol = vec3(0.050, 0.300, 0.290) * lightIn;
    // light scattered back out of wave slopes facing the viewer
    float sss = pow(max(dot(V, -uSunDir) * 0.5 + 0.5, 0.0), 3.0) * max(nn.x * flow.x + nn.y * flow.y + 0.25, 0.0);
    vec3 scatterAdd = vec3(0.02, 0.22, 0.18) * uSunColor * sss * 0.35 * sunVis;

#if WATER_QUALITY >= 1
    vec2 suv = gl_FragCoord.xy * uInvScreen;
    float waterZ = linearDepth(gl_FragCoord.z);
    float sceneZ0 = linearDepth(texture(uSceneDepth, suv).r);
    float depth0 = max(sceneZ0 - waterZ, 0.0);
    // refraction: bend the view through the surface, never sampling geometry in front of the water
    vec2 duv = suv + nn * 0.045 * clamp(depth0 * 0.6, 0.0, 1.0) / (1.0 + dist * 0.03);
    float sceneZ = linearDepth(texture(uSceneDepth, duv).r);
    if (sceneZ < waterZ) { duv = suv; sceneZ = sceneZ0; }
    float depth = max(sceneZ - waterZ, 0.0);
    float vdepth = max(-vRel.y * (sceneZ / max(waterZ, 0.001) - 1.0), 0.0);   // vertical water depth
    vec3 scene = texture(uSceneColor, duv).rgb;                                // display space
    // absorption along the view ray plus a floor from the vertical depth, so even shallows read as water
    vec3 trans = exp(-(depth * 0.75 + vdepth * 0.6) * vec3(0.62, 0.21, 0.15)) * vec3(0.80, 0.95, 0.93);
    vec3 inscatter = toDisplay(mix(deepCol, shallowCol, exp(-vdepth * 0.55)) + scatterAdd);
    vec3 body = scene * trans + inscatter * (1.0 - trans);

    vec3 reflLin = refl;
#if WATER_QUALITY >= 2
    // screen-space reflection of terrain and trees
    if (!under && top > 0.5) {
        float t = 0.7;
        vec3 hitCol = vec3(0.0);
        float hit = 0.0;
        for (int i = 0; i < 14; i++) {
            vec3 p = vRel + R * t;
            vec4 clip = uViewProj * vec4(p, 1.0);
            if (clip.w <= 0.05) break;
            vec2 uv = clip.xy / clip.w * 0.5 + 0.5;
            if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) break;
            float sz = linearDepth(texture(uSceneDepth, uv).r);
            float diff = clip.w - sz;
            if (diff > 0.0 && diff < 1.2 + t * 0.35 && sz < uNearFar.y * 0.9) {
                vec2 e = min(uv, 1.0 - uv);
                hit = smoothstep(0.0, 0.08, min(e.x, e.y)) * (1.0 - float(i) / 14.0 * 0.5);
                hitCol = texture(uSceneColor, uv).rgb;
                break;
            }
            t *= 1.42;
        }
        // scene colour is display-encoded; undo approximately so it can be mixed with the linear sky
        reflLin = mix(reflLin, hitCol * hitCol * 1.15, hit * 0.9);
    }
#endif
    vec3 surface = toDisplay(applyFog(reflLin + sunSpec, vRel));
    vec3 col = mix(body, surface, under ? 0.12 : fres);

    // --- foam: surf line breathing in and out at the shore, plus wind-driven whitecaps
    float foamN = texture(uWaterNormal, wxz * 0.34375 + flow * uTime * 0.02).b;
    float foamN2 = texture(uWaterNormal, wxz * 0.125 - flow * uTime * 0.01 + 0.5).b;
    float surge = 0.16 + 0.10 * sin(uTime * 1.1 + foamN2 * 6.0);
    float shore = (1.0 - smoothstep(0.0, surge + 0.22, vdepth)) * smoothstep(0.34, 0.62, foamN + 0.34 - vdepth * 0.9);
    float lace = (1.0 - smoothstep(0.25, 1.4, vdepth)) * smoothstep(0.62, 0.8, foamN * 0.6 + foamN2 * 0.55) * 0.5;
    float caps = smoothstep(0.80, 0.93, foamN2 * 0.55 + n1.x * 0.5 + 0.38) * clamp(uWind.z - 1.1, 0.0, 1.0) * smoothstep(1.0, 3.0, vdepth);
    float foam = clamp(shore + lace + caps * 0.7, 0.0, 1.0) * top * (1.0 - float(under));
    vec3 foamCol = toDisplay(vec3(0.82, 0.86, 0.88) * (uAmbientSky * 1.6 * skyLit + uSunColor * 0.5 * sunVis));
    col = mix(col, foamCol, foam * 0.85);

    // --- soft waterline instead of a hard polygon edge
    float edge = smoothstep(0.0, 0.10, vdepth + (1.0 - top));
    col = mix(texture(uSceneColor, suv).rgb, col, max(edge, foam));

    // far water fades into the atmosphere like everything else
    float x = dist * uFog.x;
    float f = clamp(1.0 - exp(-x * sqrt(x)), 0.0, 1.0);
    col = mix(col, toDisplay(fogColor(-V)), f * 0.9);
    fragColor = vec4(col, 1.0);
#else
    vec3 col = mix(mix(deepCol, shallowCol, 0.35) + scatterAdd, refl, fres) + sunSpec;
    col = applyFog(col, vRel);
    fragColor = vec4(toDisplay(col), under ? 0.5 : (0.74 + 0.24 * fres));
#endif
}
