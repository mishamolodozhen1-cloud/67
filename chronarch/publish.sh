#!/usr/bin/env bash
# Собирает плейс и публикует его в Roblox через Open Cloud (Assets API).
# Ключ API: переменная ROBLOX_API_KEY. В облачной сессии Claude ключ подставляет прокси сам.
set -euo pipefail
cd "$(dirname "$0")"

PLACE_ID="${PLACE_ID:-126350560275847}"
python3 build.py

AUTH=()
if [[ -n "${ROBLOX_API_KEY:-}" ]]; then
  AUTH=(-H "x-api-key: ${ROBLOX_API_KEY}")
fi

resp=$(curl -sS "${AUTH[@]}" --request PATCH "https://apis.roblox.com/assets/v1/assets/${PLACE_ID}" \
  --form "request={\"assetId\": ${PLACE_ID}, \"assetType\": \"Place\", \"published\": true}" \
  --form "fileContent=@build/ArrowOfFate.rbxl;type=application/octet-stream")
op=$(echo "$resp" | python3 -c 'import sys,json; print(json.load(sys.stdin)["operationId"])')

for _ in $(seq 1 30); do
  result=$(curl -sS "${AUTH[@]}" "https://apis.roblox.com/assets/v1/operations/${op}")
  if echo "$result" | grep -q '"done":true'; then
    echo "$result"
    exit 0
  fi
  sleep 2
done
echo "Публикация ещё обрабатывается: operations/${op}" >&2
exit 1
