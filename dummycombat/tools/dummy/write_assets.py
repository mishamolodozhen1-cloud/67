#!/usr/bin/env python3
"""tools/dummy/assets.json (что загружено в Roblox) + build/anims/anims.json (длины и скорости анимаций)
-> src/ReplicatedStorage/Configs/DummyAssets.lua.

Запуск после загрузки: python3 tools/dummy/write_assets.py
"""
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
assets = json.load(open(os.path.join(HERE, "assets.json")))
anims = json.load(open(os.path.join(ROOT, "build", "anims", "anims.json")))

lines = [
    "-- DummyAssets: ассеты манекена в Roblox (создаётся tools/dummy/write_assets.py — не править вручную).",
    "-- BodyModel — модель с 15 частями тела (MeshPart), из неё сервер собирает персонажа (CharacterSystem).",
    "-- Animations: Id, длина цикла (с), «родная» скорость походки (studs/с — при ней ноги не скользят),",
    "-- зациклена ли. CrouchDrop — насколько ниже персонаж в приседе (на столько уменьшается HipHeight).",
    "local function anim(id, length, natural, loop)",
    "\treturn table.freeze({ Id = \"rbxassetid://\" .. id, Length = length, Natural = natural, Loop = loop })",
    "end",
    "",
    "return table.freeze({",
    "\tBodyModel = %s," % assets["DC_DummyBody"]["assetId"],
    "\tCrouchDrop = %g," % anims["_CrouchDrop"],
    "\tAnimations = table.freeze({",
]
for name, m in anims.items():
    if name.startswith("_"):
        continue
    aid = assets["DC_" + name]["assetId"]
    lines.append("\t\t%s = anim(%s, %g, %g, %s)," % (name, aid, m["Length"], m["Natural"], "true" if m["Loop"] else "false"))
lines += ["\t}),", "})"]
path = os.path.join(ROOT, "src", "ReplicatedStorage", "Configs", "DummyAssets.lua")
with open(path, "w", encoding="utf-8") as f:
    f.write("\n".join(lines) + "\n")
print(path)
