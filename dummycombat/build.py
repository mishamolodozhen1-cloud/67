#!/usr/bin/env python3
"""Сборка плейса DUMMY COMBAT: src/ -> build/DummyCombat.rbxl (бинарный формат Roblox).

Правила (как в Rojo, без лишнего):
  src/<Служба>/                     верхний уровень — службы Roblox (Workspace, ReplicatedStorage, ...)
  папка                             -> Folder (или класс из init.meta.json в этой папке)
  Имя.server.lua                    -> Script
  Имя.client.lua                    -> LocalScript
  Имя.lua                           -> ModuleScript
  Имя.model.json                    -> экземпляр: {"className": ..., "properties": {...}, "children": [...]}
  init.meta.json                    -> класс и свойства самой папки: {"className": ..., "properties": {...}}
  файлы, начинающиеся с точки       -> пропускаются (.keep держит пустые папки в git)

Свойства в JSON: "Имя": [тип, значение], типы: bool, int, float, string, token, Vector3, CFrame, Color3uint8.
Color3uint8 можно писать строкой "#RRGGBB". CFrame — [x, y, z] (без поворота) или 12 чисел.
Имена свойств — как в файле плейса: у деталей размер — "size", цвет — "Color3uint8".

Дополнительно сборщик:
  • кладёт в ReplicatedStorage.Configs модуль BuildInfo (версия из VERSION, коммит git, время сборки);
  • запрещает одинаковые имена у соседей (иначе WaitForChild/FindFirstChild находили бы случайный);
  • пишет build/manifest.txt — дерево собранного плейса (по нему видно, что вошло в сборку).

Запуск: python3 build.py
"""
import datetime
import json
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(ROOT, "tools"))
from rbxl import write_binary  # noqa: E402

SRC = os.path.join(ROOT, "src")
OUT_DIR = os.path.join(ROOT, "build")
OUT_BIN = os.path.join(OUT_DIR, "DummyCombat.rbxl")
OUT_MANIFEST = os.path.join(OUT_DIR, "manifest.txt")

# Контейнеры, у которых класс совпадает с именем папки
NAMED_CLASSES = {"StarterPlayerScripts", "StarterCharacterScripts"}
SERVICE_NAMES = {"Workspace", "Lighting", "Players", "ReplicatedStorage", "ServerScriptService", "ServerStorage", "StarterGui", "StarterPlayer", "SoundService"}


class Inst:
    def __init__(self, cls, name, props=None):
        self.cls = cls
        self.name = name
        self.props = props or []
        self.children = []

    def add(self, child):
        if any(c.name == child.name for c in self.children):
            raise ValueError(f"два объекта с именем «{child.name}» внутри «{self.name}»")
        self.children.append(child)
        return child


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def color(v):
    if isinstance(v, str):
        return int(v.lstrip("#"), 16)
    return int(v)


def prop_list(props):
    out = []
    for name, (kind, value) in sorted((props or {}).items()):
        if kind == "Color3uint8":
            value = color(value)
        elif kind == "CFrame" and len(value) == 3:
            value = list(value) + [1, 0, 0, 0, 1, 0, 0, 0, 1]
        elif kind == "Vector3":
            value = tuple(value)
        out.append((kind, name, value))
    return out


def script_inst(cls, name, path):
    props = [("source", "Source", read(path))]
    if cls == "Script":
        props.append(("token", "RunContext", 0))  # Legacy: обычный серверный скрипт
    return Inst(cls, name, props)


def model_inst(data, name=None):
    inst = Inst(data["className"], data.get("name", name), prop_list(data.get("properties")))
    for child in data.get("children", []):
        inst.add(model_inst(child))
    return inst


def dir_inst(path, name, top=False):
    meta_path = os.path.join(path, "init.meta.json")
    meta = json.loads(read(meta_path)) if os.path.exists(meta_path) else {}
    if top:
        cls = name
    elif name in NAMED_CLASSES:
        cls = name
    else:
        cls = meta.get("className", "Folder")
    inst = Inst(cls, name, prop_list(meta.get("properties")))
    for entry in sorted(os.listdir(path)):
        full = os.path.join(path, entry)
        if entry.startswith(".") or entry == "init.meta.json":
            continue
        if os.path.isdir(full):
            inst.add(dir_inst(full, entry))
        elif entry.endswith(".server.lua"):
            inst.add(script_inst("Script", entry[: -len(".server.lua")], full))
        elif entry.endswith(".client.lua"):
            inst.add(script_inst("LocalScript", entry[: -len(".client.lua")], full))
        elif entry.endswith(".lua"):
            inst.add(script_inst("ModuleScript", entry[: -len(".lua")], full))
        elif entry.endswith(".model.json"):
            inst.add(model_inst(json.loads(read(full)), entry[: -len(".model.json")]))
        elif entry.endswith(".md"):
            continue  # пояснения для людей
        else:
            raise ValueError(f"не знаю, что делать с файлом {full}")
    return inst


def build_info():
    version = read(os.path.join(ROOT, "VERSION")).strip()
    try:
        commit = subprocess.run(["git", "rev-parse", "--short", "HEAD"], cwd=ROOT, capture_output=True, text=True, check=True).stdout.strip()
        dirty = subprocess.run(["git", "status", "--porcelain", "--", "src", "VERSION", "build.py", "tools"], cwd=ROOT, capture_output=True, text=True).stdout.strip()
        if dirty:
            commit += "+"  # исходники изменены после этого коммита
    except Exception:
        commit = "unknown"
    built = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    source = (
        "-- BuildInfo: создаётся сборщиком (build.py), в репозитории его нет. Не редактировать вручную.\n"
        "return table.freeze({\n"
        f"\tVersion = {json.dumps(version)},\n"
        f"\tCommit = {json.dumps(commit)},\n"
        f"\tBuiltAt = {json.dumps(built)},\n"
        "})\n"
    )
    return Inst("ModuleScript", "BuildInfo", [("source", "Source", source)]), version, commit


def manifest(inst, depth=0, lines=None):
    lines = [] if lines is None else lines
    lines.append("  " * depth + f"{inst.name} ({inst.cls})")
    for c in inst.children:
        manifest(c, depth + 1, lines)
    return lines


def build():
    services = []
    for name in sorted(os.listdir(SRC)):
        path = os.path.join(SRC, name)
        if not os.path.isdir(path) or name.startswith("."):
            continue
        if name not in SERVICE_NAMES:
            raise ValueError(f"src/{name}: неизвестная служба Roblox")
        services.append(dir_inst(path, name, top=True))
    rs = next(s for s in services if s.name == "ReplicatedStorage")
    configs = next(c for c in rs.children if c.name == "Configs")
    info, version, commit = build_info()
    configs.add(info)

    os.makedirs(OUT_DIR, exist_ok=True)
    data = write_binary(services)
    with open(OUT_BIN, "wb") as f:
        f.write(data)
    lines = []
    for s in services:
        manifest(s, 0, lines)
    with open(OUT_MANIFEST, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    count = len(lines)
    print(f"Собрано: {OUT_BIN} ({len(data)} байт, {count} объектов, версия {version}, коммит {commit})")


if __name__ == "__main__":
    build()
