#!/usr/bin/env python3
"""tools/ui/assets.json (что загружено) + build/ui/ui_sfx_index.json -> src/ReplicatedStorage/Configs/UiAssets.lua"""
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
assets = json.load(open(os.path.join(HERE, "assets.json")))
index = json.load(open(os.path.join(ROOT, "build", "ui", "ui_sfx_index.json")))
L = [
    "-- UiAssets: звуки интерфейса и музыка (создаётся tools/ui/write_assets.py — не править вручную).",
    "-- Sfx — один файл-спрайт: каждый звук — отрезок [Start, Stop] (Sound.PlaybackRegion).",
    "return table.freeze({",
    "\tSfx = table.freeze({",
    "\t\tId = \"rbxassetid://%s\"," % assets["DC_UiSfx"]["assetId"],
    "\t\tSounds = table.freeze({",
]
for name, r in index["Sounds"].items():
    L.append("\t\t\t%s = table.freeze({ Start = %g, Stop = %g })," % (name, r["Start"], r["Stop"]))
L += ["\t\t}),", "\t}),", "\tMusic = table.freeze({", "\t\tLobby = \"rbxassetid://%s\"," % assets["DC_LobbyMusic"]["assetId"], "\t}),", "})"]
path = os.path.join(ROOT, "src", "ReplicatedStorage", "Configs", "UiAssets.lua")
open(path, "w", encoding="utf-8").write("\n".join(L) + "\n")
print(path)
