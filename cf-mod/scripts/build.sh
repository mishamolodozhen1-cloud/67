#!/usr/bin/env bash
set -euo pipefail

CF_VER="1.4.1-c7"
APK_URL="https://github.com/Scratchhhh/counterflame-releases/releases/download/v${CF_VER}/CounterFlame-${CF_VER}.apk"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${ROOT}/build"
APK_IN="${WORK}/CounterFlame-${CF_VER}.apk"
APK_OUT="${WORK}/CounterFlame-${CF_VER}-mod.apk"
UNPACK="${WORK}/unpack"
NDK_OUT="${WORK}/libs"

mkdir -p "${WORK}" "${NDK_OUT}"

if [[ ! -f "${APK_IN}" ]]; then
  echo "[*] fetch apk (~1.9 GB) ..."
  curl -L --fail --retry 4 --retry-delay 3 -o "${APK_IN}.part" "${APK_URL}"
  mv "${APK_IN}.part" "${APK_IN}"
fi

echo "[*] prepare xHook dependency"
if [[ ! -d "${ROOT}/native/xhook" ]]; then
  git clone --depth 1 https://github.com/iqiyi/xHook "${ROOT}/native/xhook"
fi

echo "[*] generate bitmap font assets"
python3 "${ROOT}/scripts/gen_font.py"

echo "[*] build native cheats (.so)"
pushd "${ROOT}/native" >/dev/null
  "${ANDROID_NDK_HOME:?set ANDROID_NDK_HOME}"/ndk-build NDK_PROJECT_PATH=. APP_BUILD_SCRIPT=./Android.mk NDK_APPLICATION_MK=./Application.mk NDK_LIBS_OUT="${NDK_OUT}" -j"$(nproc)"
popd >/dev/null

echo "[*] apktool decode"
rm -rf "${UNPACK}"
apktool d -s -f -o "${UNPACK}" "${APK_IN}"

echo "[*] inject cheats loader into smali"
python3 "${ROOT}/scripts/inject_loader.py" "${UNPACK}"

echo "[*] compile overlay service + bridge"
bash "${ROOT}/smali-patch/compile_overlay.sh" "${UNPACK}"

echo "[*] drop libcfcheat.so into every abi"
for abi in arm64-v8a armeabi-v7a x86_64; do
  [[ -d "${UNPACK}/lib/${abi}" ]] || continue
  cp "${NDK_OUT}/${abi}/libcfcheat.so" "${UNPACK}/lib/${abi}/libcfcheat.so"
done

echo "[*] merge menu assets"
mkdir -p "${UNPACK}/assets/cfmenu"
cp -r "${ROOT}/assets/." "${UNPACK}/assets/cfmenu/"

echo "[*] patch manifest overlay permission + extract legacy libs"
python3 "${ROOT}/scripts/patch_manifest.py" "${UNPACK}/AndroidManifest.xml"

echo "[*] apktool build"
apktool b -o "${WORK}/CounterFlame-${CF_VER}-mod.unsigned.apk" "${UNPACK}"

echo "[*] zipalign + sign"
"${ANDROID_HOME:-$HOME/Android/Sdk}"/build-tools/*/zipalign -p -f 4 \
  "${WORK}/CounterFlame-${CF_VER}-mod.unsigned.apk" \
  "${WORK}/CounterFlame-${CF_VER}-mod.aligned.apk"

if [[ ! -f "${ROOT}/cfmod.keystore" ]]; then
  echo "[*] generate throwaway keystore"
  keytool -genkeypair -v -storetype PKCS12 \
    -keystore "${ROOT}/cfmod.keystore" \
    -alias cfmod -keyalg RSA -keysize 2048 -validity 10000 \
    -dname "CN=cfmod, O=cf, C=US" -storepass cfmod123 -keypass cfmod123
fi

"${ANDROID_HOME:-$HOME/Android/Sdk}"/build-tools/*/apksigner sign \
  --ks "${ROOT}/cfmod.keystore" --ks-pass pass:cfmod123 --key-pass pass:cfmod123 \
  --out "${APK_OUT}" "${WORK}/CounterFlame-${CF_VER}-mod.aligned.apk"

echo
echo "[✓] готово: ${APK_OUT}"
