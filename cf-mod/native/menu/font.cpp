// Шрифт из APK assets: assets/cfmenu/inter_18.r8 + metrics.bin (генерится scripts/gen_font.py)
#include "font.h"
#include "../util/log.h"
#include "../cheats/state.h"
#include <GLES3/gl3.h>
#include <android/asset_manager.h>
#include <android/asset_manager_jni.h>
#include <vector>
#include <string.h>

namespace cf::menu {

struct Metrics {
    uint16_t w, h;
    uint16_t base;
    uint16_t pad;
    float g[128][10];
};

static Metrics g_metrics{};
static bool g_loaded = false;
static unsigned g_tex = 0;

static AAssetManager *acquire_assets() {
    JNIEnv *env = nullptr;
    cf::state::vm->AttachCurrentThread(&env, nullptr);
    jclass cls = env->FindClass("android/app/ActivityThread");
    jmethodID cur = env->GetStaticMethodID(cls, "currentActivityThread", "()Landroid/app/ActivityThread;");
    jobject at   = env->CallStaticObjectMethod(cls, cur);
    jmethodID app = env->GetMethodID(cls, "getApplication", "()Landroid/app/Application;");
    jobject ap   = env->CallObjectMethod(at, app);
    jclass ctx   = env->FindClass("android/content/Context");
    jmethodID am = env->GetMethodID(ctx, "getAssets", "()Landroid/content/res/AssetManager;");
    jobject jam  = env->CallObjectMethod(ap, am);
    return AAssetManager_fromJava(env, jam);
}

static void load_once() {
    if (g_loaded) return;
    auto mgr = acquire_assets();
    if (!mgr) { CFERR("no asset manager"); return; }
    AAsset *am = AAssetManager_open(mgr, "cfmenu/metrics.bin", AASSET_MODE_BUFFER);
    AAsset *at = AAssetManager_open(mgr, "cfmenu/inter_18.r8",  AASSET_MODE_BUFFER);
    if (!am || !at) { CFERR("font assets missing"); return; }
    memcpy(&g_metrics, AAsset_getBuffer(am), sizeof(Metrics));
    std::vector<uint8_t> buf(AAsset_getLength(at));
    memcpy(buf.data(), AAsset_getBuffer(at), buf.size());
    AAsset_close(am); AAsset_close(at);

    glGenTextures(1, &g_tex);
    glBindTexture(GL_TEXTURE_2D, g_tex);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S,     GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T,     GL_CLAMP_TO_EDGE);
    glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_R8, g_metrics.w, g_metrics.h, 0, GL_RED, GL_UNSIGNED_BYTE, buf.data());
    g_loaded = true;
}

unsigned font_atlas_tex() { load_once(); return g_tex; }

Glyph font_glyph(unsigned char c) {
    load_once();
    Glyph g{};
    const auto &r = g_metrics.g[c];
    g.u0 = r[0]; g.v0 = r[1]; g.u1 = r[2]; g.v1 = r[3];
    g.w = r[4]; g.h = r[5]; g.off_x = r[6]; g.off_y = r[7];
    g.advance = r[8]; g.base = r[9] > 0 ? r[9] : g_metrics.base;
    return g;
}
}
