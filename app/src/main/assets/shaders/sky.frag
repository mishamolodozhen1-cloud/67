precision highp float;
#include "common.glsl"
uniform mat4 uInvViewProj;
uniform sampler2D uNoise;
uniform vec3 uMoonDir;
uniform vec4 uCloud;      // x: coverage 0..1, y: time offset, z: darkness, w: star visibility
uniform vec2 uCloudOffset; // camera xz scaled into cloud space
in vec2 vUv;
out vec4 fragColor;

float cloudDensity(vec2 p) {
    float n = texture(uNoise, p * 0.5).r * 0.55;
    n += texture(uNoise, p * 1.3 + vec2(0.37, 0.11)).g * 0.28;
#if CLOUD_OCTAVES >= 3
    n += texture(uNoise, p * 3.1 + vec2(0.71, 0.53)).b * 0.14;
#endif
#if CLOUD_OCTAVES >= 4
    n += texture(uNoise, p * 7.3).r * 0.06;
#endif
    return n;
}

void main() {
    vec4 far = uInvViewProj * vec4(vUv * 2.0 - 1.0, 1.0, 1.0);
    vec3 d = normalize(far.xyz / far.w);
    vec3 c = skyColor(d);

    // sun and moon discs
    float sd = dot(d, uSunTrueDir);
    c += vec3(1.0, 0.92, 0.75) * smoothstep(0.9993, 0.99965, sd) * 14.0 * clamp(uSunTrueDir.y * 6.0 + 0.6, 0.0, 1.0);
    float md = dot(d, uMoonDir);
    c += vec3(0.75, 0.82, 1.0) * smoothstep(0.9990, 0.9994, md) * 1.6 * clamp(uMoonDir.y * 4.0 + 0.3, 0.0, 1.0);

    // stars
    if (uCloud.w > 0.01 && d.y > -0.05) {
        vec2 sp = d.xz / (abs(d.y) + 0.35) * 42.0;
        vec2 cell = floor(sp);
        vec2 f = fract(sp) - 0.5;
        float h = fract(sin(dot(cell, vec2(127.1, 311.7))) * 43758.5453);
        float star = step(0.94, h) * smoothstep(0.12, 0.0, length(f + (h - 0.97) * 4.0));
        c += vec3(0.9, 0.95, 1.0) * star * uCloud.w * (0.5 + 0.5 * fract(h * 57.0));
    }

    // cloud layer on a plane above the camera
    if (d.y > 0.015) {
        vec2 p = (d.xz / d.y) * 0.035 + uCloudOffset + vec2(uCloud.y, uCloud.y * 0.35);
        float den = cloudDensity(p);
        float cover = smoothstep(1.0 - uCloud.x, 1.0 - uCloud.x + 0.2, den + 0.05);
        // cheap self-shadowing: density sampled toward the light
        float lit = clamp(den - cloudDensity(p + uSunDir.xz * 0.02) + 0.5, 0.0, 1.0);
        vec3 bright = uSunColor * 0.42 + uAmbientSky * 1.6;
        vec3 dark = (uAmbientSky * 0.85 + uSunColor * 0.06) * (1.0 - uCloud.z * 0.6);
        vec3 cc = mix(dark, bright, lit) + uFog.w * 1.5;
        float horizonFade = smoothstep(0.015, 0.16, d.y);
        c = mix(c, cc, cover * horizonFade * 0.95);
    }
    fragColor = vec4(toDisplay(c), 1.0);
}
