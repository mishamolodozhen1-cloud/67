APP_ABI := arm64-v8a armeabi-v7a x86_64
APP_PLATFORM := android-26
APP_STL := c++_static
APP_CPPFLAGS := -std=c++20 -fexceptions -frtti -fvisibility=hidden -O2 -fno-rtti
APP_CFLAGS := -O2 -ffunction-sections -fdata-sections
APP_LDFLAGS := -Wl,--gc-sections -Wl,--strip-all
