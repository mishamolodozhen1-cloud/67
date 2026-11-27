#!/usr/bin/env python3
"""Roblox Open Cloud для DUMMY COMBAT: сохранить сборку как версию плейса и запустить Luau на сервере.

  python3 tools/cloud.py save build/DummyCombat.rbxl          — НЕопубликованная версия (игроки её не видят)
  python3 tools/cloud.py run tests/stage1.test.lua <версия>   — запустить скрипт на безголовом сервере Roblox
  python3 tools/cloud.py test [stage]                         — сборка + save + run tests/stage<N>.test.lua (по умолчанию все)
  python3 tools/cloud.py upload <тип> <имя> <файл> [...]       — загрузить ассет (Model, Animation, Decal, Audio);
                                                                можно несколько троек подряд; печатает JSON с id

Плейс: переменные окружения DC_PLACE_ID и DC_UNIVERSE_ID. Пока у DUMMY COMBAT нет своего плейса,
по умолчанию используется общий плейс проекта (там опубликована NIGHT SHIFT): сохраняются только
неопубликованные версии, опубликованная игра не меняется. Публикация (publish) — только с явно
заданным DC_PLACE_ID, чтобы не опубликовать DUMMY COMBAT поверх другой игры по ошибке.
Ключ API: ROBLOX_API_KEY (в облачной сессии Claude его подставляет прокси).
"""
import json
import os
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_PLACE = "126350560275847"
DEFAULT_UNIVERSE = "7168539009"
PLACE = os.environ.get("DC_PLACE_ID", DEFAULT_PLACE)
UNIVERSE = os.environ.get("DC_UNIVERSE_ID", DEFAULT_UNIVERSE)


def curl(args, data=None):
    cmd = ["curl", "-sS"]
    key = os.environ.get("ROBLOX_API_KEY")
    if key:
        cmd += ["-H", "x-api-key: " + key]
    out = subprocess.run(cmd + args, input=data, capture_output=True, text=True)
    if out.returncode != 0:
        raise RuntimeError(out.stderr.strip())
    return out.stdout


def save(path, publish=False):
    if publish and "DC_PLACE_ID" not in os.environ:
        sys.exit("Публикация только с явно заданным DC_PLACE_ID (своим плейсом DUMMY COMBAT).")
    req = json.dumps({"assetId": int(PLACE), "assetType": "Place", "published": publish})
    resp = json.loads(curl(["--request", "PATCH", f"https://apis.roblox.com/assets/v1/assets/{PLACE}",
                            "--form", "request=" + req, "--form", f"fileContent=@{path};type=application/octet-stream"]))
    op = resp.get("operationId")
    if not op:
        sys.exit("Ошибка сохранения: " + json.dumps(resp, ensure_ascii=False))
    for _ in range(90):
        time.sleep(2)
        r = json.loads(curl([f"https://apis.roblox.com/assets/v1/operations/{op}"]))
        if r.get("done"):
            version = r.get("response", {}).get("revisionId")
            print(f"Сохранено: плейс {PLACE}, версия {version}, опубликовано: {publish}")
            return int(version)
    sys.exit("Сохранение не закончилось за 3 минуты: operations/" + op)


def run(script_path, version):
    script = open(script_path, encoding="utf-8").read()
    base = f"https://apis.roblox.com/cloud/v2/universes/{UNIVERSE}/places/{PLACE}"
    url = base + (f"/versions/{version}" if version else "") + "/luau-execution-session-tasks"
    resp = json.loads(curl(["-X", "POST", url, "-H", "Content-Type: application/json", "--data-binary", "@-"],
                           data=json.dumps({"script": script, "timeout": "300s"})))
    path = resp.get("path")
    if not path:
        sys.exit("Ошибка запуска: " + json.dumps(resp, ensure_ascii=False))
    task = {}
    for _ in range(120):
        time.sleep(3)
        task = json.loads(curl(["https://apis.roblox.com/cloud/v2/" + path]))
        if task.get("state") in ("COMPLETE", "FAILED", "CANCELLED"):
            break
    print("STATE", task.get("state"))
    if task.get("error"):
        print("ERROR", json.dumps(task["error"], ensure_ascii=False))
    for value in (task.get("output") or {}).get("results", []):
        print(value)
    logs = json.loads(curl(["https://apis.roblox.com/cloud/v2/" + path + "/logs"]) or "{}")
    for chunk in logs.get("luauExecutionSessionTaskLogs", []):
        for m in chunk.get("messages", []):
            print("LOG", m[:500])
    return task.get("state") == "COMPLETE"


MIME = {"Model": "model/gltf-binary", "Animation": "model/x-rbxm", "Decal": "image/png", "Audio": "audio/ogg"}
CREATOR = os.environ.get("DC_CREATOR_USER_ID", "7945431606")  # аккаунт, от имени которого грузятся ассеты


def upload(kind, name, path):
    mime = MIME[kind]
    if kind == "Model" and path.endswith(".rbxm"):
        mime = "model/x-rbxm"
    req = {"assetType": kind, "displayName": name, "description": "DUMMY COMBAT", "creationContext": {"creator": {"userId": CREATOR}}}
    resp = json.loads(curl(["-X", "POST", "https://apis.roblox.com/assets/v1/assets", "--form-string", "request=" + json.dumps(req),
                            "--form", f"fileContent=@{path};type={mime}"]))
    op = resp.get("operationId") or (resp.get("path", "").split("/")[-1] if resp.get("path") else None)
    if not op:
        return {"error": resp}
    for _ in range(60):
        time.sleep(2)
        r = json.loads(curl([f"https://apis.roblox.com/assets/v1/operations/{op}"]))
        if r.get("done"):
            res = r.get("response", {})
            return {"assetId": res.get("assetId"), "moderation": res.get("moderationResult", {}).get("moderationState")}
    return {"error": "timeout", "operation": op}


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    cmd = sys.argv[1]
    if cmd == "save":
        save(sys.argv[2], publish=len(sys.argv) > 3 and sys.argv[3] == "publish")
    elif cmd == "run":
        ok = run(sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else None)
        sys.exit(0 if ok else 1)
    elif cmd == "test":
        subprocess.run([sys.executable, os.path.join(ROOT, "build.py")], check=True)
        version = save(os.path.join(ROOT, "build", "DummyCombat.rbxl"))
        tests = sorted(f for f in os.listdir(os.path.join(ROOT, "tests")) if f.endswith(".test.lua"))
        if len(sys.argv) > 2:
            tests = [f"stage{sys.argv[2]}.test.lua"]
        ok = True
        for name in tests:
            print("==", name)
            ok = run(os.path.join(ROOT, "tests", name), version) and ok
        sys.exit(0 if ok else 1)
    elif cmd == "upload":
        args = sys.argv[2:]
        if len(args) % 3 != 0 or not args:
            sys.exit(__doc__)
        result = {}
        for i in range(0, len(args), 3):
            kind, name, path = args[i:i + 3]
            result[name] = upload(kind, name, path)
            print(name, result[name], flush=True)
        print(json.dumps(result, ensure_ascii=False))
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
