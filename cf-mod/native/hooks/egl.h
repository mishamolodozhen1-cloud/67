#pragma once
#include <EGL/egl.h>
namespace cf::egl {
void install();        // перехватываем eglSwapBuffers через xHook
EGLBoolean present(EGLDisplay, EGLSurface);
int   width();
int   height();
}
