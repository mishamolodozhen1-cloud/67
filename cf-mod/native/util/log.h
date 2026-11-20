#pragma once
#include <android/log.h>
#define CFLOG(...) __android_log_print(ANDROID_LOG_INFO, "cfcheat", __VA_ARGS__)
#define CFERR(...) __android_log_print(ANDROID_LOG_ERROR, "cfcheat", __VA_ARGS__)
