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
sfx2 = json.load(open(os.path.join(ROOT, "build", "weapons", "sfx2_index.json")))


def grouped(index):
    out = {}
    for name, s in index["Sounds"].items():
        out.setdefault(s["Group"], []).append((name, s["Start"], s["Stop"]))
    return out


def sprite(key, index, asset):
    out = [
        "\t%s = table.freeze({" % key,
        "\t\tId = \"rbxassetid://%s\"," % asset,
        "\t\tLength = %g," % index["Length"],
        "\t\tGroups = table.freeze({",
    ]
    for g, items in grouped(index).items():
        body = ", ".join("region(%g, %g)" % (a, b) for _, a, b in items)
        out.append("\t\t\t%s = table.freeze({ %s })," % (g, body))
    out += ["\t\t}),", "\t}),"]
    return out

lines = [
    "-- WeaponAssets: ассеты оружия в Roblox (создаётся tools/weapons/write_assets.py — не править вручную).",
    "-- Models: модели (MeshPart-ы внутри узлов *_Node); Sfx: один звуковой файл-спрайт, Groups — варианты звука",
    "-- (отрезки [Start, Stop] в секундах, играются через Sound.PlaybackRegion); Sfx2 — второй спрайт (выстрелы",
    "-- пистолета, ПП, дробовика, снайперской винтовки, затворы); Images: текстуры эффектов.",
    "local function region(a, b)",
    "\treturn table.freeze({ Start = a, Stop = b })",
    "end",
    "",
    "return table.freeze({",
    "\tModels = table.freeze({",
    "\t\tAK47 = %s," % assets["DC_AK47"]["assetId"],
    "\t\tPistol = %s," % assets["DC_Pistol"]["assetId"],
    "\t\tSMG = %s," % assets["DC_SMG"]["assetId"],
    "\t\tShotgun = %s," % assets["DC_Shotgun"]["assetId"],
    "\t\tSniper = %s," % assets["DC_Sniper"]["assetId"],
    "\t}),",
]
lines += sprite("Sfx", sfx, assets["DC_WeaponSfx"]["assetId"])
lines += sprite("Sfx2", sfx2, assets["DC_WeaponSfx2"]["assetId"])
lines += [
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
