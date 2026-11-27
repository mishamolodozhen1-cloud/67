#!/usr/bin/env python3
"""tools/weapons/assets.json (что загружено в Roblox) + build/weapons/sfx_index.json (разметка звукового спрайта)
-> src/ReplicatedStorage/Configs/WeaponAssets.lua.

Запуск после загрузки: python3 tools/weapons/write_assets.py
У картинок (Decal) в assets.json хранится и id самой картинки ("image"): его даёт Decal.Texture после
InsertService:LoadAsset — именно он нужен ParticleEmitter/ImageLabel/Decal.
"""
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
assets = json.load(open(os.path.join(HERE, "assets.json")))
sfx = json.load(open(os.path.join(ROOT, "build", "weapons", "sfx_index.json")))

groups = {}
for name, s in sfx["Sounds"].items():
    groups.setdefault(s["Group"], []).append((name, s["Start"], s["Stop"]))

lines = [
    "-- WeaponAssets: ассеты оружия в Roblox (создаётся tools/weapons/write_assets.py — не править вручную).",
    "-- Models: модели (MeshPart-ы внутри узлов *_Node); Sfx: один звуковой файл-спрайт, Groups — варианты звука",
    "-- (отрезки [Start, Stop] в секундах, играются через Sound.PlaybackRegion); Images: текстуры эффектов.",
    "local function region(a, b)",
    "\treturn table.freeze({ Start = a, Stop = b })",
    "end",
    "",
    "return table.freeze({",
    "\tModels = table.freeze({",
    "\t\tAK47 = %s," % assets["DC_AK47"]["assetId"],
    "\t}),",
    "\tSfx = table.freeze({",
    "\t\tId = \"rbxassetid://%s\"," % assets["DC_WeaponSfx"]["assetId"],
    "\t\tLength = %g," % sfx["Length"],
    "\t\tGroups = table.freeze({",
]
for g, items in groups.items():
    body = ", ".join("region(%g, %g)" % (a, b) for _, a, b in items)
    lines.append("\t\t\t%s = table.freeze({ %s })," % (g, body))
lines += [
    "\t\t}),",
    "\t}),",
    "\tImages = table.freeze({",
    "\t\tMuzzleFlash = \"rbxassetid://%s\"," % assets["DC_FxFlash"]["image"],
    "\t\tMuzzleFlashSide = \"rbxassetid://%s\"," % assets["DC_FxFlashSide"]["image"],
    "\t\tBulletHole = \"rbxassetid://%s\"," % assets["DC_FxHole"]["image"],
    "\t}),",
    "})",
]
path = os.path.join(ROOT, "src", "ReplicatedStorage", "Configs", "WeaponAssets.lua")
with open(path, "w", encoding="utf-8") as f:
    f.write("\n".join(lines) + "\n")
print(path)
