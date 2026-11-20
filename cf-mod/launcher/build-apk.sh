#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

if [[ -f .env ]]; then set -a; source .env; set +a; fi
: "${EXPO_TOKEN:?добавь EXPO_TOKEN в .env (пример в .env.example)}"

npm install --no-audit --no-fund

echo "[*] запуск cloud-сборки apk (preview)"
EXPO_TOKEN="${EXPO_TOKEN}" npx eas-cli build --platform android --profile preview --non-interactive

echo "[✓] готово. ссылка на apk в выводе eas"
