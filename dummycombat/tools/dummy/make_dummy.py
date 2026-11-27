#!/usr/bin/env python3
"""Манекен DUMMY COMBAT -> build/dummy/DummyBody.glb (загружается в Roblox как Model),
src/ReplicatedStorage/Configs/DummyRig.lua (скелет для сборки персонажа на сервере)
и картинки для проверки: build/dummy/preview_*.png.

Запуск: python3 tools/dummy/make_dummy.py
"""
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import geometry as g  # noqa: E402
import rig  # noqa: E402
import render  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(HERE))
OUT = os.path.join(ROOT, "build", "dummy")
RIG_LUA = os.path.join(ROOT, "src", "ReplicatedStorage", "Configs", "DummyRig.lua")


def v3(v):
    return "Vector3.new(%s)" % ", ".join("%.4f" % float(x) for x in v)


def write_rig_lua(info, atts, tris):
    lines = [
        "-- DummyRig: скелет манекена DUMMY COMBAT (создаётся tools/dummy/make_dummy.py — не править вручную).",
        "-- Координаты в позе покоя относительно центра HumanoidRootPart, studs. Персонаж смотрит в −Z.",
        "-- Parts: размер и центр каждой части (MeshPart из модели DummyBody того же имени).",
        "-- Attachments: точки суставов «<Сустав>RigAttachment» (по ним строятся Motor6D) и точки",
        "-- крепления аксессуаров и оружия — в осях своей части.",
        "return table.freeze({",
        "\tHeight = %.3f," % 5.62,
        "\tHipHeight = %.3f," % rig.HIP_HEIGHT,
        "\tRootSize = %s," % v3(rig.HRP_SIZE),
        "\tTriangles = %d," % tris,
        "\tParts = table.freeze({",
    ]
    root = np.array(rig.HRP_CENTER)
    for name in rig.PART_ORDER:
        c = info[name]["Center"] - root
        lines.append("\t\ttable.freeze({ Name = %r, Offset = %s, Size = %s, Collide = %s }),".replace("%r", '"%s"') % (
            name, v3(c), v3(info[name]["Size"]), "true" if name in rig.COLLIDE else "false"))
    lines.append("\t}),")
    lines.append("\t-- суставы: имя (Motor6D), родительская часть (Part0), дочерняя (Part1); точки — «<имя>RigAttachment»")
    lines.append("\tJoints = table.freeze({")
    for joint, (p0, p1, _) in rig.JOINTS.items():
        lines.append('\t\ttable.freeze({ "%s", "%s", "%s" }),' % (joint, p0, p1))
    lines.append("\t}),")
    lines.append("\tAttachments = table.freeze({")
    for part in ["HumanoidRootPart"] + rig.PART_ORDER:
        items = ", ".join('{ "%s", %s }' % (n, v3(p)) for n, p in atts[part])
        lines.append('\t\t%s = table.freeze({ %s }),' % (part, items))
    lines.append("\t}),")
    lines.append("})")
    with open(RIG_LUA, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")


def colored(mesh, R=None, t=None):
    from PIL import Image
    import io
    pal = Image.open(io.BytesIO(g.palette_png())).convert("RGB")
    px = np.asarray(pal, float)
    h, w = px.shape[:2]
    uv = mesh.uv
    col = px[np.clip((uv[:, 1] * h).astype(int), 0, h - 1), np.clip((uv[:, 0] * w).astype(int), 0, w - 1)]
    pos, nrm = mesh.pos, mesh.nrm
    if R is not None:
        pos = pos @ R.T + t
        nrm = nrm @ R.T
    return pos, nrm, col, mesh.idx


def posed_items(parts, info, poses, root_offset=(0, 0, 0)):
    world = rig.pose_world(info, poses, root_offset)
    items = []
    for name in rig.PART_ORDER:
        R, t = world[name]
        m = parts[name]
        local = m.transformed(None, -info[name]["Center"])  # меш относительно центра части
        items.append(colored(local, R, t))
    return items


def main():
    os.makedirs(OUT, exist_ok=True)
    parts = rig.build_parts()
    tris = sum(m.tris for m in parts.values())
    info, atts = rig.spec(parts)
    size = g.write_glb([(n, parts[n]) for n in rig.PART_ORDER], g.palette_png(), os.path.join(OUT, "DummyBody.glb"))
    write_rig_lua(info, atts, tris)
    for n in rig.PART_ORDER:
        print(f"{n:15s} tris {parts[n].tris:5d} size {np.round(info[n]['Size'], 3).tolist()}")
    print(f"всего треугольников {tris}, GLB {size // 1024} КБ, HipHeight {rig.HIP_HEIGHT:.2f}")
    # картинки: спереди, сбоку, три четверти, сзади
    floor = render.ground(4, 0.5)
    items = posed_items(parts, info, {}) + [floor]
    views = [("спереди", (0, 3.0, -11)), ("сбоку", (11, 3.0, 0)), ("три четверти", (-7, 4.2, -8)), ("сзади", (0, 3.0, 11))]
    imgs = [render.label(render.render(items, eye, (0, 2.8, 0), fov=32, W=420, H=640), t) for t, eye in views]
    render.sheet(imgs, 4).save(os.path.join(OUT, "preview_body.png"))
    head = [render.label(render.render(items, (-2.2, 5.4, -3.2), (0, 5.0, 0), fov=30, W=420, H=420), "голова"),
            render.label(render.render(items, (3.2, 4.6, -2.6), (0.8, 3.6, 0), fov=34, W=420, H=420), "плечо и рука")]
    render.sheet(head, 2).save(os.path.join(OUT, "preview_detail.png"))
    print("картинки:", os.path.join(OUT, "preview_body.png"), os.path.join(OUT, "preview_detail.png"))


if __name__ == "__main__":
    main()
