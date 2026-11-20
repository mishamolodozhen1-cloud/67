#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UNPACK="$1"
OUT="${ROOT}/build/overlay-dex"
mkdir -p "${OUT}"

javac -source 1.8 -target 1.8 -d "${OUT}" \
    "${ROOT}/smali-patch/java_src/com/cf/overlay/Bridge.java" \
    "${ROOT}/smali-patch/java_src/com/cf/overlay/OverlayService.java"

d8 --release --output "${OUT}/classes.dex" \
    $(find "${OUT}" -name '*.class')

baksmali disassemble -o "${OUT}/smali" "${OUT}/classes.dex"
cp -r "${OUT}/smali/." "${UNPACK}/smali/"

python3 "${ROOT}/scripts/register_service.py" "${UNPACK}/AndroidManifest.xml"
echo "[+] overlay встроен"
