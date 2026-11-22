#!/usr/bin/env python3
"""Анимации существа (v10) -> ModuleScript с кадрами для Bone.Transform.

  beast_anims.py rig/anims.json src/ReplicatedStorage/Shared/BeastAnims.lua

Roblox при импорте оставил локальные позы костей такими же, как в файле (проверено на сервере:
Bone.CFrame совпадает с позой покоя из anims.json), поэтому Transform кости = Покой⁻¹ · Поза(t).
Для каждого кадра строка чисел ×1000: для всех костей кватернион поворота (x, y, z, w),
затем смещения (x, y, z) только у тех костей, которые в этой анимации двигаются.
"""
import json
import sys

import numpy as np

sys.path.insert(0, __import__("os").path.dirname(__file__))
from prep_rig import mat_to_quat, quat_to_mat  # noqa: E402

LOOP = {"idle": True, "walk": True}


def M(v):
    m = np.eye(4)
    m[:3, :3] = quat_to_mat(v[3:])
    m[:3, 3] = v[:3]
    return m


def main():
    src, dst = sys.argv[1], sys.argv[2]
    A = json.load(open(src))
    bones = A["Bones"]
    rest_inv = {b: np.linalg.inv(M(A["Rest"][b])) for b in bones}
    lines = [
        "-- Анимации существа (сгенерировано tools/models/beast_anims.py из модели «New Breaking News Rig»).",
        "-- Кадр: числа ×1000 — кватернионы (x, y, z, w) всех костей по порядку Bones, затем смещения (x, y, z)",
        "-- костей из Moves. Значения — Bone.Transform относительно позы покоя.",
        "return {",
        "\tFps = %g," % A["Fps"],
        "\tBones = { %s }," % ", ".join('"%s"' % b for b in bones),
        "\tAnims = {",
    ]
    for name, an in A["Anims"].items():
        frames = an["Frames"]
        deltas = []
        for fr in frames:
            deltas.append({b: rest_inv[b] @ M(fr[b]) for b in bones})
        moves = [i for i, b in enumerate(bones) if max(np.abs(d[b][:3, 3]).max() for d in deltas) > 0.003]
        lines.append("\t\t%s = {" % name)
        lines.append("\t\t\tLength = %g," % an["Length"])
        lines.append("\t\t\tLoop = %s," % ("true" if LOOP.get(name) else "false"))
        lines.append("\t\t\tMoves = { %s }," % ", ".join(str(i + 1) for i in moves))
        lines.append("\t\t\tFrames = {")
        for d in deltas:
            vals = []
            for b in bones:
                q = mat_to_quat(d[b][:3, :3])
                vals += [int(round(x * 1000)) for x in q]
            for i in moves:
                vals += [int(round(x * 1000)) for x in d[bones[i]][:3, 3]]
            lines.append('\t\t\t\t"%s",' % ",".join(str(v) for v in vals))
        lines.append("\t\t\t},")
        lines.append("\t\t},")
    lines.append("\t},")
    lines.append("}")
    open(dst, "w").write("\n".join(lines) + "\n")
    print("ok", dst, sum(len(x) for x in lines) // 1024, "КБ")


if __name__ == "__main__":
    main()
