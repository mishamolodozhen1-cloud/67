#!/bin/bash
# Runs the headless verification harness (software GLES 3). Usage: tools/harness.sh --scenario terrain --out <dir> ...
cd "$(dirname "$0")/.."
ANDROID_HOME=${ANDROID_HOME:-/opt/android-sdk} ./gradlew -q :desktop:installDist 2>&1 | grep -E "^e:|FAILED|rror:" && exit 1
export EGL_PLATFORM=surfaceless LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe
exec desktop/build/install/desktop/bin/desktop "$@" 2>&1 | grep --line-buffered -v JAVA_TOOL_OPTIONS
