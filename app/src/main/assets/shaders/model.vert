precision highp float;
layout(location = 0) in vec3 aPos;
layout(location = 1) in vec3 aNormal;
layout(location = 2) in vec4 aColor;
layout(location = 3) in vec4 aBones;
layout(location = 4) in vec4 aWeights;
uniform mat4 uViewProj;
uniform mat4 uBones[40];     // bone * inverse-bind, pre-multiplied by the camera-relative model matrix
#ifdef SHADOWS
uniform mat4 uShadowMatrix;
out vec4 vShadowCoord;
#endif
out highp vec3 vRel;
out mediump vec3 vNormal;
out mediump vec4 vColor;
out highp vec3 vObj;
void main() {
    int i0 = int(aBones.x + 0.5);
    int i1 = int(aBones.y + 0.5);
    vec4 p = vec4(aPos, 1.0);
    vec4 n = vec4(aNormal, 0.0);
    vec3 pos = (uBones[i0] * p).xyz * aWeights.x + (uBones[i1] * p).xyz * aWeights.y;
    vec3 nor = (uBones[i0] * n).xyz * aWeights.x + (uBones[i1] * n).xyz * aWeights.y;
    vRel = pos;
    vNormal = nor;
    vColor = aColor;
    vObj = aPos;
#ifdef SHADOWS
    vShadowCoord = uShadowMatrix * vec4(pos + normalize(nor) * 0.05, 1.0);
#endif
    gl_Position = uViewProj * vec4(pos, 1.0);
}
