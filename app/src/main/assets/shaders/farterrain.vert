precision highp float;
layout(location = 0) in vec3 aPos;
layout(location = 1) in vec4 aNormal;
layout(location = 2) in vec4 aColor;
uniform mat4 uViewProj;
uniform vec3 uOffset;
out highp vec3 vRel;
out mediump vec3 vNormal;
out mediump vec4 vColor;
void main() {
    vec3 rel = aPos + uOffset;
    vRel = rel;
    vNormal = aNormal.xyz;
    vColor = aColor;
    gl_Position = uViewProj * vec4(rel, 1.0);
}
