precision highp float;
uniform sampler2D uNoise;
uniform vec4 uParams;   // x: break progress 0..1, y: highlight strength
in vec3 vLocal;
out vec4 fragColor;
void main() {
    // distance to the nearest cube edge on this face
    vec3 q = min(vLocal, 1.0 - vLocal);
    // on a face one component is ~0; the middle component is the distance to the face border
    float e = max(min(q.x, q.y), min(max(q.x, q.y), q.z));
    float edge = 1.0 - smoothstep(0.012, 0.03, e);
    // procedural cracks that spread with break progress
    vec2 uv = vLocal.xy + vLocal.zz * vec2(0.73, 0.41) + vLocal.yx * 0.31;
    float n = abs(texture(uNoise, uv * 0.9).r - 0.5) + abs(texture(uNoise, uv * 2.3 + 0.37).g - 0.5) * 0.5;
    float crack = (1.0 - smoothstep(0.0, 0.035 + uParams.x * 0.05, n)) * step(0.01, uParams.x) * smoothstep(0.0, 0.25, uParams.x + 0.1);
    float alpha = max(edge * uParams.y * 0.85, crack * (0.55 + 0.4 * uParams.x));
    vec3 col = mix(vec3(0.02), vec3(1.0), edge * (1.0 - crack) * 0.35);
    if (alpha < 0.01) discard;
    fragColor = vec4(col, alpha);
}
