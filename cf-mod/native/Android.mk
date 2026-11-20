LOCAL_PATH := $(call my-dir)

# xHook (vendored submodule). scripts/build.sh клонирует его автоматом.
include $(CLEAR_VARS)
LOCAL_MODULE := xhook
LOCAL_SRC_FILES := \
    xhook/libxhook/jni/xh_core.c \
    xhook/libxhook/jni/xh_elf.c \
    xhook/libxhook/jni/xh_jni.c \
    xhook/libxhook/jni/xh_log.c \
    xhook/libxhook/jni/xh_util.c \
    xhook/libxhook/jni/xh_version.c \
    xhook/libxhook/jni/xhook.c
LOCAL_C_INCLUDES := $(LOCAL_PATH)/xhook/libxhook/jni
include $(BUILD_STATIC_LIBRARY)

include $(CLEAR_VARS)
LOCAL_MODULE := cfcheat
LOCAL_SRC_FILES := \
    entry.cpp \
    menu/menu.cpp \
    menu/renderer_gl.cpp \
    menu/touch.cpp \
    menu/font.cpp \
    menu/overlay_boot.cpp \
    hooks/il2cpp.cpp \
    hooks/egl.cpp \
    cheats/esp.cpp \
    cheats/aim.cpp \
    cheats/fly.cpp \
    cheats/noclip.cpp \
    cheats/skinchanger.cpp \
    cheats/killall.cpp \
    cheats/misc.cpp \
    cheats/state.cpp \
    util/world.cpp \
    util/log.cpp
LOCAL_C_INCLUDES := $(LOCAL_PATH)
LOCAL_STATIC_LIBRARIES := xhook
LOCAL_LDLIBS := -llog -lEGL -lGLESv3 -landroid -ldl
include $(BUILD_SHARED_LIBRARY)
