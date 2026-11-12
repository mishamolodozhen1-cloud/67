precision highp float;
uniform sampler2D uScene;
uniform vec2 uInvSize;
uniform vec4 uFx;      // x: vignette, y: underwater, z: damage flash, w: fade to black
uniform float uTime;
#ifdef BLOOM
uniform sampler2D uBloom;
#endif
in vec2 vUv;
out vec4 fragColor;

#ifdef FXAA
vec3 fxaa(vec2 uv) {
    vec3 m = texture(uScene, uv).rgb;
    vec3 nw = texture(uScene, uv + vec2(-1.0, -1.0) * uInvSize).rgb;
    vec3 ne = texture(uScene, uv + vec2(1.0, -1.0) * uInvSize).rgb;
    vec3 sw = texture(uScene, uv + vec2(-1.0, 1.0) * uInvSize).rgb;
    vec3 se = texture(uScene, uv + vec2(1.0, 1.0) * uInvSize).rgb;
    const vec3 L = vec3(0.299, 0.587, 0.114);
    float lm = dot(m, L), lnw = dot(nw, L), lne = dot(ne, L), lsw = dot(sw, L), lse = dot(se, L);
    float lmin = min(lm, min(min(lnw, lne), min(lsw, lse)));
    float lmax = max(lm, max(max(lnw, lne), max(lsw, lse)));
    if (lmax - lmin < max(0.04, lmax * 0.125)) return m;
    vec2 dir = vec2(-((lnw + lne) - (lsw + lse)), (lnw + lsw) - (lne + lse));
    float rcp = 1.0 / (min(abs(dir.x), abs(dir.y)) + max((lnw + lne + lsw + lse) * 0.03125, 0.0078));
    dir = clamp(dir * rcp, vec2(-8.0), vec2(8.0)) * uInvSize;
    vec3 a = 0.5 * (texture(uScene, uv + dir * (1.0 / 3.0 - 0.5)).rgb + texture(uScene, uv + dir * (2.0 / 3.0 - 0.5)).rgb);
    vec3 b = a * 0.5 + 0.25 * (texture(uScene, uv - dir * 0.5).rgb + texture(uScene, uv + dir * 0.5).rgb);
    float lb = dot(b, L);
    return (lb < lmin || lb > lmax) ? a : b;
}
#endif

void main() {
    vec2 uv = vUv;
    if (uFx.y > 0.0) uv += vec2(sin(uv.y * 28.0 + uTime * 2.0), cos(uv.x * 24.0 + uTime * 1.7)) * 0.0025 * uFx.y;
#ifdef FXAA
    vec3 c = fxaa(uv);
#else
    vec3 c = texture(uScene, uv).rgb;
#endif
#ifdef BLOOM
    c += texture(uBloom, uv).rgb * 0.55;
#endif
    // gentle filmic grade: a touch of contrast and saturation
    float l = dot(c, vec3(0.299, 0.587, 0.114));
    c = mix(vec3(l), c, 1.08);
    c = c * c * (3.0 - 2.0 * c) * 0.35 + c * 0.65;
    vec2 q = vUv - 0.5;
    float v = dot(q, q);
    c *= 1.0 - uFx.x * v * 1.1;
    c = mix(c, c * vec3(0.55, 0.85, 1.0), uFx.y * 0.6);
    c = mix(c, vec3(0.55, 0.02, 0.0), clamp(uFx.z * v * 3.2, 0.0, 0.8));
    c *= 1.0 - uFx.w;
    fragColor = vec4(c, 1.0);
}
