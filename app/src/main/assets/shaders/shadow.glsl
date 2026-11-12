// Shadow-map lookup shared by lit shaders.
#ifdef SHADOWS
uniform mediump sampler2DShadow uShadowMap;
uniform vec4 uShadowParams;   // x: texel size, y: fade start (blocks), z: fade range, w: unused

float shadowTerm(vec4 sc, float dist) {
    vec3 p = sc.xyz;
    if (p.x <= 0.0 || p.x >= 1.0 || p.y <= 0.0 || p.y >= 1.0 || p.z >= 1.0) return 1.0;
    float s;
#if SHADOW_TAPS >= 4
    float t = uShadowParams.x;
    s = texture(uShadowMap, p + vec3(-0.6 * t, -0.6 * t, 0.0));
    s += texture(uShadowMap, p + vec3(0.6 * t, -0.6 * t, 0.0));
    s += texture(uShadowMap, p + vec3(-0.6 * t, 0.6 * t, 0.0));
    s += texture(uShadowMap, p + vec3(0.6 * t, 0.6 * t, 0.0));
    s *= 0.25;
#else
    s = texture(uShadowMap, p);
#endif
    float fade = clamp((dist - uShadowParams.y) / uShadowParams.z, 0.0, 1.0);
    return mix(s, 1.0, fade);
}
#endif
