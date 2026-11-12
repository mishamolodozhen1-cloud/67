precision highp float;
layout(location = 0) in vec2 aPos;
layout(location = 1) in vec2 aUv;
layout(location = 2) in vec4 aColor;
layout(location = 3) in vec4 aParams;   // halfW, halfH, radius, mode
uniform vec2 uScreen;
out vec2 vUv;
out vec4 vColor;
out vec4 vParams;
void main() {
    vUv = aUv;
    vColor = aColor;
    vParams = aParams;
    gl_Position = vec4(aPos.x / uScreen.x * 2.0 - 1.0, 1.0 - aPos.y / uScreen.y * 2.0, 0.0, 1.0);
}
