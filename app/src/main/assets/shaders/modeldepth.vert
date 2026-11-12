precision highp float;
layout(location = 0) in vec3 aPos;
layout(location = 3) in vec4 aBones;
layout(location = 4) in vec4 aWeights;
uniform mat4 uViewProj;
uniform mat4 uBones[40];
void main() {
    int i0 = int(aBones.x + 0.5);
    int i1 = int(aBones.y + 0.5);
    vec4 p = vec4(aPos, 1.0);
    vec3 pos = (uBones[i0] * p).xyz * aWeights.x + (uBones[i1] * p).xyz * aWeights.y;
    gl_Position = uViewProj * vec4(pos, 1.0);
}
