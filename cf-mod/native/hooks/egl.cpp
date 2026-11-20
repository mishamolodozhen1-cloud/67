#include "egl.h"
#include "../util/log.h"
#include "../menu/menu.h"
#include "../cheats/esp.h"
#include <EGL/egl.h>
#include <GLES3/gl3.h>
#include <xhook/libxhook/jni/xhook.h>
#include <atomic>

namespace cf::aim    { void bind_present(int, int); }
namespace cf::fly    { void tick(float); }
namespace cf::noclip { void tick();        }
namespace cf::skin   { void tick();        }
namespace cf::killall{ void fire();        }
namespace cf::misc   { void tick();        }

namespace cf::egl {

static std::atomic<int> g_w{0};
static std::atomic<int> g_h{0};

using fn_swap = EGLBoolean (*)(EGLDisplay, EGLSurface);
static fn_swap orig_swap = nullptr;

static EGLBoolean hk_swap(EGLDisplay dpy, EGLSurface sfc) {
    EGLint w = 0, h = 0;
    eglQuerySurface(dpy, sfc, EGL_WIDTH,  &w);
    eglQuerySurface(dpy, sfc, EGL_HEIGHT, &h);
    g_w = w; g_h = h;

    GLint vp[4]; glGetIntegerv(GL_VIEWPORT, vp);
    glViewport(0, 0, w, h);
    glDisable(GL_DEPTH_TEST);
    glDisable(GL_CULL_FACE);
    glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

    cf::aim::bind_present(w, h);
    cf::fly::tick(1.0f / 60.f);
    cf::noclip::tick();
    cf::skin::tick();
    cf::misc::tick();
    cf::killall::fire();

    cf::esp::draw(w, h);
    cf::menu::draw(w, h);

    glViewport(vp[0], vp[1], vp[2], vp[3]);
    return orig_swap(dpy, sfc);
}

void install() {
    xhook_register(".*libunity\\.so$",  "eglSwapBuffers", (void*)hk_swap, (void**)&orig_swap);
    xhook_register(".*libil2cpp\\.so$", "eglSwapBuffers", (void*)hk_swap, (void**)&orig_swap);
    xhook_register(".*libmain\\.so$",   "eglSwapBuffers", (void*)hk_swap, (void**)&orig_swap);
    xhook_refresh(0);
    if (!orig_swap) orig_swap = (fn_swap)eglGetProcAddress("eglSwapBuffers");
    CFLOG("egl hook installed");
}

EGLBoolean present(EGLDisplay d, EGLSurface s) { return orig_swap ? orig_swap(d, s) : EGL_TRUE; }
int width()  { return g_w.load(); }
int height() { return g_h.load(); }

}
