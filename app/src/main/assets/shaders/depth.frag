precision mediump float;
precision mediump sampler2DArray;
#ifdef ALPHA_TEST
uniform sampler2DArray uAlbedo;
in highp vec3 vUvw;
#endif
void main() {
#ifdef ALPHA_TEST
    if (texture(uAlbedo, vUvw).a < 0.42) discard;
#endif
}
