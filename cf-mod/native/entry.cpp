#include <jni.h>
#include <pthread.h>
#include <unistd.h>
#include <android/log.h>
#include "hooks/il2cpp.h"
#include "hooks/egl.h"
#include "menu/menu.h"
namespace cf::menu { void start_overlay_service(); }
#include "cheats/state.h"
#include "util/log.h"

static void *bootstrap(void *) {
    CFLOG("cfcheat boot");
    cf::state::init();
    for (int tries = 0; tries < 120; ++tries) {
        if (cf::il2cpp::attach()) break;
        sleep(1);
    }
    cf::egl::install();      // hook eglSwapBuffers → меню + ESP
    cf::menu::install();     // overlay-рендер и тач-слой
    cf::menu::start_overlay_service();
    CFLOG("cfcheat ready");
    return nullptr;
}

extern "C" JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM *vm, void *) {
    cf::state::vm = vm;
    pthread_t t;
    pthread_create(&t, nullptr, bootstrap, nullptr);
    pthread_detach(t);
    return JNI_VERSION_1_6;
}
