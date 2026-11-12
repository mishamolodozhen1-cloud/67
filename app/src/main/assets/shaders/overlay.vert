precision highp float;
layout(location = 0) in vec3 aPos;
uniform mat4 uViewProj;
uniform vec3 uOffset;
uniform vec3 uScale;
out vec3 vLocal;
void main() {
    vLocal = aPos;
    gl_Position = uViewProj * vec4((aPos - 0.5) * (uScale + 0.004) + 0.5 * uScale + uOffset, 1.0);
}
