#!/usr/bin/env python3
"""Окраски манекена (этап 10): та же палитра, что у модели, с другим цветом корпуса и накладок.
  python3 tools/dummy/make_skins.py -> build/skins/<Имя>.png
Цвета корпуса — из ProgressionConfig.Skins (здесь продублированы для генерации); накладки — темнее на 14 %.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
import geometry as g  # noqa: E402

SKINS = {
    "Classic": (201, 170, 98), "Graphite": (74, 76, 80), "Arctic": (222, 224, 226), "Olive": (104, 112, 70),
    "Crimson": (162, 52, 46), "Cobalt": (52, 88, 160), "Gold": (214, 172, 62),
    "TeamRed": (198, 66, 54), "TeamBlue": (58, 108, 198),
}
out = os.path.join(ROOT, "build", "skins")
os.makedirs(out, exist_ok=True)
for name, body in SKINS.items():
    colors = dict(g.PALETTE_COLORS)
    colors["body"] = body
    colors["body_shade"] = tuple(int(c * 0.86) for c in body)
    if name == "Graphite":
        colors["marker_yellow"] = (214, 180, 104)
    with open(os.path.join(out, name + ".png"), "wb") as f:
        f.write(g.palette_png(colors))
print(out, len(SKINS))
