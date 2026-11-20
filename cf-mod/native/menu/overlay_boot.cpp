#include "../cheats/state.h"
#include "../util/log.h"
#include <jni.h>

namespace cf::menu {

void start_overlay_service() {
    JNIEnv *env = nullptr;
    cf::state::vm->AttachCurrentThread(&env, nullptr);

    jclass clsAT  = env->FindClass("android/app/ActivityThread");
    jmethodID mCur = env->GetStaticMethodID(clsAT, "currentActivityThread", "()Landroid/app/ActivityThread;");
    jobject at    = env->CallStaticObjectMethod(clsAT, mCur);
    jmethodID mApp= env->GetMethodID(clsAT, "getApplication", "()Landroid/app/Application;");
    jobject app   = env->CallObjectMethod(at, mApp);
    if (!app) { CFERR("no application"); return; }

    jclass clsCtx = env->FindClass("android/content/Context");

    jclass clsSet = env->FindClass("android/provider/Settings");
    jmethodID mCan= env->GetStaticMethodID(clsSet, "canDrawOverlays",
                                           "(Landroid/content/Context;)Z");
    jboolean can  = env->CallStaticBooleanMethod(clsSet, mCan, app);
    if (!can) {
        CFERR("overlay perm missing, ask user in Settings");
        return;
    }

    jclass clsIntent = env->FindClass("android/content/Intent");
    jmethodID mIntent= env->GetMethodID(clsIntent, "<init>",
                                        "(Landroid/content/Context;Ljava/lang/Class;)V");
    jclass clsSvc    = env->FindClass("com/cf/overlay/OverlayService");
    if (!clsSvc) { CFERR("overlay service not packed"); env->ExceptionClear(); return; }

    jobject intent   = env->NewObject(clsIntent, mIntent, app, clsSvc);
    jmethodID mStart = env->GetMethodID(clsCtx, "startService",
                                        "(Landroid/content/Intent;)Landroid/content/ComponentName;");
    env->CallObjectMethod(app, mStart, intent);
    CFLOG("overlay service started");
}
}
