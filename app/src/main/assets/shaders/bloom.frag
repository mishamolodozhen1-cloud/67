precision highp float;
uniform sampler2D uTex;
uniform vec4 uDir;   // xy: blur direction in uv units, z: 1 = bright-pass extraction
in vec2 vUv;
out vec4 fragColor;
void main() {
    if (uDir.z > 0.5) {
        vec3 c = texture(uTex, vUv).rgb;
        float l = max(c.r, max(c.g, c.b));
        fragColor = vec4(c * smoothstep(0.82, 1.0, l), 1.0);
    } else {
        vec3 c = texture(uTex, vUv).rgb * 0.227;
        c += (texture(uTex, vUv + uDir.xy * 1.385).rgb + texture(uTex, vUv - uDir.xy * 1.385).rgb) * 0.316;
        c += (texture(uTex, vUv + uDir.xy * 3.231).rgb + texture(uTex, vUv - uDir.xy * 3.231).rgb) * 0.070;
        fragColor = vec4(c, 1.0);
    }
}
