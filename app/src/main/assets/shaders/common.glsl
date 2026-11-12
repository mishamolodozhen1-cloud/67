// Shared lighting / atmosphere code for WildCore forward shaders.
uniform vec3 uSunDir;        // direction towards the active key light (sun by day, moon by night)
uniform vec3 uSunColor;      // key light radiance
uniform vec3 uSunTrueDir;    // direction towards the sun disc (may be below the horizon)
uniform vec3 uSkyZenith;
uniform vec3 uSkyHorizon;
uniform vec3 uSunGlow;
uniform vec3 uAmbientSky;
uniform vec3 uAmbientGround;
uniform vec4 uFog;           // x: density, y: 1 = underwater, z: wetness (rain), w: lightning flash
uniform vec3 uFogTint;       // underwater / weather tint of the fog colour
uniform float uExposure;

vec3 skyColor(vec3 d) {
    float h = clamp(d.y, 0.0, 1.0);
    float t = 1.0 - h;
    t = t * t * t;
    vec3 c = mix(uSkyZenith, uSkyHorizon, t);
    float s = max(dot(d, uSunTrueDir), 0.0);
    float s2 = s * s; float s8 = s2 * s2 * s2 * s2;
    c += uSunGlow * (s8 * 0.35 + s8 * s8 * s8 * s8 * 0.9) * (0.25 + 0.75 * t);
    return c;
}

vec3 fogColor(vec3 dir) {
    if (uFog.y > 0.5) return uFogTint;
    return skyColor(vec3(dir.x, max(dir.y, 0.03), dir.z)) * uFogTint;
}

vec3 applyFog(vec3 color, vec3 rel) {
    float d = length(rel);
    float x = d * uFog.x;
    float f = 1.0 - exp(-x * sqrt(x));
    return mix(color, fogColor(rel / max(d, 0.001)), clamp(f, 0.0, 1.0));
}

// ACES filmic fit + display gamma
vec3 toDisplay(vec3 c) {
    c *= uExposure;
    c = (c * (2.51 * c + 0.03)) / (c * (2.43 * c + 0.59) + 0.14);
    return pow(clamp(c, 0.0, 1.0), vec3(0.4545));
}
