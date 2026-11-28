#!/usr/bin/env python3
"""Пистолет, пистолет-пулемёт, дробовик и снайперская винтовка DUMMY COMBAT — свои процедурные модели
(без чужих моделей и без копирования реальных образцов один в один: общие черты класса оружия, свой облик).

Те же оси и те же части, что у AK-47 (tools/weapons/ak47.py), — поэтому вся остальная игра (сервер, вид от
первого лица, руки по ИК, перезарядка, гильзы) работает с ними без отдельного кода:
  Body            рамка / ствольная коробка, ствол, рукоять, приклад, прицельные приспособления…
  Magazine        отъёмный магазин
  ChargingHandle  то, что ходит назад: у пистолета — затвор-кожух целиком, у снайперской — рукоять затвора
  Casing          гильза (у дробовика — пластиковая гильза с латунным донцем)
Текстура — общий атлас 1024×1024 для всех четырёх: чёрный и оливковый полимер, рукояти с насечкой, воронёная
и светлая сталь, латунь, чёрный, сталь магазинов, красный пластик гильз, стекло прицела.

Запуск: python3 tools/weapons/guns.py -> build/weapons/<Имя>.glb, Guns_atlas.png, preview_<имя>.png и
src/ReplicatedStorage/Configs/WeaponModels.lua (там же и AK-47 — его геометрию берём из ak47.py).
"""
import io
import math
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(ROOT, "tools", "dummy"))
sys.path.insert(0, HERE)
import ak47  # noqa: E402
import geometry as g  # noqa: E402
import render  # noqa: E402

OUT = os.path.join(ROOT, "build", "weapons")
extrude, box, cyl, sweep, tube, smooth_path, flat = ak47.extrude, ak47.box, ak47.cylinder_z, ak47.sweep, ak47.tube, ak47.smooth_path, ak47.flat

###############################################################################
# Атлас
###############################################################################
ATLAS = 1024
REGIONS = {
    "polymer": (0.0, 0.0, 0.5, 0.25),
    "od": (0.5, 0.0, 1.0, 0.25),
    "grip": (0.0, 0.25, 0.5, 0.5),
    "steel": (0.5, 0.25, 1.0, 0.5),
    "steel_light": (0.0, 0.5, 0.5, 0.75),
    "brass": (0.5, 0.5, 0.75, 0.75),
    "black": (0.75, 0.5, 1.0, 0.75),
    "mag": (0.0, 0.75, 0.5, 1.0),
    "red": (0.5, 0.75, 0.75, 1.0),
    "glass": (0.75, 0.75, 1.0, 1.0),
}
Z_RANGE = (-2.5, 1.35)
Y_RANGE = (-0.75, 0.35)


def atlas_png():
    rng = np.random.default_rng(91)
    img = np.zeros((ATLAS, ATLAS, 3))

    def region(name):
        u0, v0, u1, v1 = REGIONS[name]
        return int(v0 * ATLAS), int(v1 * ATLAS), int(u0 * ATLAS), int(u1 * ATLAS)

    def fill(name, col, amt, cells=(32, 8, 2)):
        y0, y1, x0, x1 = region(name)
        n = ak47.fbm(x1 - x0, y1 - y0, rng, cells)[..., None]
        img[y0:y1, x0:x1] = np.array(col, float) * (1 - amt / 2 + amt * n)

    fill("polymer", (52, 53, 56), 0.16, (64, 16, 4))
    fill("od", (78, 82, 62), 0.18, (64, 16, 4))
    # рукояти: мелкая насечка (зерно) поверх тёмного полимера
    y0, y1, x0, x1 = region("grip")
    base = ak47.fbm(x1 - x0, y1 - y0, rng, (16, 4))[..., None]
    grain = rng.random((y1 - y0, x1 - x0))[..., None]
    img[y0:y1, x0:x1] = np.array([31, 32, 34]) * (0.85 + 0.2 * base) * (0.82 + 0.3 * grain)
    fill("steel", (58, 61, 66), 0.2)
    fill("steel_light", (96, 98, 102), 0.18)
    fill("brass", (196, 150, 70), 0.2, (16, 4))
    fill("black", (17, 17, 18), 0.25, (32, 8))
    fill("mag", (36, 37, 39), 0.2)
    fill("red", (128, 30, 26), 0.15, (16, 4))
    # стекло: тёмно-синее с бликом сверху
    y0, y1, x0, x1 = region("glass")
    h = y1 - y0
    grad = np.linspace(1.0, 0.0, h)[:, None, None]
    img[y0:y1, x0:x1] = np.array([16, 30, 44]) + grad * np.array([40, 60, 70])
    im = Image.fromarray(np.clip(img, 0, 255).astype(np.uint8))
    buf = io.BytesIO()
    im.save(buf, "PNG")
    return buf.getvalue(), im


def project(mesh, material):
    u0, v0, u1, v1 = REGIONS[material]
    mu, mv = (u1 - u0) * 0.04, (v1 - v0) * 0.04
    zu = (mesh.pos[:, 2] - Z_RANGE[0]) / (Z_RANGE[1] - Z_RANGE[0])
    yv = 1 - (mesh.pos[:, 1] - Y_RANGE[0]) / (Y_RANGE[1] - Y_RANGE[0])
    mesh.uv = np.stack([u0 + mu + np.clip(zu, 0, 1) * (u1 - u0 - 2 * mu), v0 + mv + np.clip(yv, 0, 1) * (v1 - v0 - 2 * mv)], 1)
    return mesh


def join(items):
    out = g.Mesh()
    for m, mat, hard in items:
        project(m, mat)
        out.add(flat(m) if hard else m)
    return out


def blob(center, radii, e=1.0, seg=(14, 8)):
    return g.superellipsoid(tuple(center), tuple(radii), e=e, seg_u=seg[0], seg_v=seg[1])


def casing_mesh(length, radius, neck=None, material="brass"):
    """Гильза вдоль Z (дно в +Z): закраина, корпус, (скат и шейка — у винтовочных)."""
    r, L = radius, length
    rings = [(0.0, r, r), (0.05 * L, r * 1.03, r * 1.03), (0.1 * L, r * 0.88, r * 0.88), (0.14 * L, r, r)]
    if neck:
        rings += [(0.68 * L, r * 0.97, r * 0.97), (0.78 * L, neck, neck), (L, neck, neck)]
    else:
        rings += [(L, r * 0.96, r * 0.96)]
    m = g.lathe(rings, seg=16, pole_bottom=0.0, pole_top=L)
    m = m.transformed(g.rot_x(math.pi / 2), (0, 0, 0))
    project(m, material)
    return m


def shell_mesh():
    """Гильза дробовика: латунное донце и красный пластиковый корпус."""
    base = g.lathe([(0.0, 0.041, 0.041), (0.006, 0.042, 0.042), (0.012, 0.037, 0.037), (0.05, 0.037, 0.037)],
                   seg=18, pole_bottom=0.0, pole_top=0.05)
    hull = g.lathe([(0.0, 0.036, 0.036), (0.2, 0.036, 0.036), (0.215, 0.03, 0.03)], seg=18, pole_bottom=0.0, pole_top=0.215)
    hull.pos[:, 1] += 0.045
    out = g.Mesh()
    for m, mat in ((base, "brass"), (hull, "red")):
        m = m.transformed(g.rot_x(math.pi / 2), (0, 0, 0))
        project(m, mat)
        out.add(m)
    return out


###############################################################################
# Пистолет: полимерная рамка, стальной затвор-кожух, магазин в рукояти
###############################################################################
PISTOL_SCALE = 1.2


def pistol():
    P, S, L, G = "polymer", "steel", "steel_light", "grip"
    body = []
    # рамка: пылезащитная часть под затвором, бобровый хвост, рукоять (под углом)
    body.append((extrude([(-0.385, -0.05), (0.3, -0.05), (0.3, -0.085), (0.245, -0.11), (0.215, -0.2), (0.235, -0.36),
                          (0.25, -0.5), (0.075, -0.5), (0.055, -0.38), (0.03, -0.24), (0.0, -0.14), (-0.06, -0.128),
                          (-0.385, -0.128)], 0.052, 0.012), P, True))
    # накладки с насечкой на рукояти
    for x in (-0.054, 0.054):
        body.append((extrude([(0.05, -0.17), (0.2, -0.17), (0.205, -0.3), (0.225, -0.47), (0.09, -0.47), (0.07, -0.36), (0.045, -0.24)],
                             0.004, 0.0015, x_center=x), G, True))
    # планка под фонарь (пазы) снизу спереди
    for z in (-0.33, -0.27, -0.21):
        body.append((box((-0.054, -0.13, z - 0.012), (0.054, -0.105, z + 0.012), e=0.5, seg=(10, 6)), "black", False))
    # спусковая скоба (полимер) и спуск
    body.append((tube(smooth_path([(-0.125, -0.2), (-0.2, -0.215), (-0.245, -0.16), (-0.25, -0.07), (-0.23, 0.01)], 8), 0.016), P, False))
    body.append((tube(smooth_path([(-0.125, -0.075), (-0.175, -0.085), (-0.205, -0.07)], 6), 0.011), L, False))
    # ствол, видимый спереди из-под затвора
    body.append((cyl(-0.4, -0.37, 0.028, (0, 0)), S, False))
    body.append((cyl(-0.405, -0.398, 0.017, (0, 0)), "black", False))
    body_mesh = join(body)

    # затвор-кожух: ходит назад при каждом выстреле и при передёргивании
    slide = [(extrude([(-0.39, -0.05), (0.3, -0.05), (0.3, 0.052), (0.285, 0.07), (-0.37, 0.07), (-0.39, 0.055)], 0.044, 0.01), S, True)]
    for z in np.linspace(0.17, 0.27, 6):  # насечки сзади
        slide.append((box((-0.047, -0.03, z - 0.006), (0.047, 0.055, z + 0.006), e=0.6, seg=(8, 6)), L, False))
    slide.append((box((0.03, 0.012, -0.06), (0.046, 0.06, 0.075), e=0.4, seg=(10, 6)), "black", False))  # окно выброса
    # прицел: целик с прорезью и мушка (линия прицеливания — y = 0.1)
    for x in (-0.026, 0.026):
        slide.append((box((x - 0.012, 0.065, 0.225), (x + 0.012, 0.102, 0.265), e=0.4, seg=(8, 6)), S, False))
    slide.append((box((-0.038, 0.065, 0.225), (0.038, 0.082, 0.265), e=0.4, seg=(8, 6)), S, False))
    slide.append((box((-0.008, 0.065, -0.36), (0.008, 0.1, -0.33), e=0.5, seg=(8, 6)), S, False))
    slide.append((blob((0.0, 0.094, -0.342), (0.005, 0.005, 0.004)), L, False))
    slide_mesh = join(slide)

    # магазин: корпус внутри рукояти (по её наклону) и выступающее дно
    path = [(-0.13 - 0.37 * t, 0.112 + 0.06 * t) for t in np.linspace(0, 1, 8)]
    mag = [(sweep(path, 0.036, 0.062, n_exp=6.0, seg=20), "mag", False),
           (box((-0.05, -0.53, 0.07), (0.05, -0.495, 0.26), e=0.35, seg=(14, 8)), P, False)]
    mag_mesh = join(mag)
    points = {
        "Muzzle": (0.0, 0.0, -0.405),
        "Eject": (0.05, 0.045, 0.0),
        "GripRight": (0.0, -0.3, 0.155),
        "GripLeft": (0.0, -0.33, 0.12),
        "SightRear": (0.0, 0.1, 0.245),
        "SightFront": (0.0, 0.1, -0.345),
        "MagWell": (0.0, -0.5, 0.165),
        "ChargingHandle": (0.0, 0.03, 0.22),
        "Stock": (0.0, -0.1, 0.3),
    }
    # руки манекена крупные: пистолет чуть больше натурального, чтобы его было видно в руках
    parts = {"Body": body_mesh, "Magazine": mag_mesh, "ChargingHandle": slide_mesh}
    for m in parts.values():
        m.pos = m.pos * PISTOL_SCALE
    parts["Casing"] = casing_mesh(0.062, 0.0105)
    return parts, {k: tuple(np.array(v) * PISTOL_SCALE) for k, v in points.items()}


###############################################################################
# Пистолет-пулемёт: стальная коробка с планкой, полимерный низ, прямой магазин, складной трубчатый приклад
###############################################################################
def smg():
    P, S, L, G = "polymer", "steel", "steel_light", "grip"
    body = []
    body.append((extrude([(-0.56, -0.06), (0.25, -0.06), (0.25, 0.08), (0.23, 0.095), (-0.54, 0.095), (-0.56, 0.08)], 0.06, 0.012), S, True))
    body.append((box((-0.036, 0.09, -0.72), (0.036, 0.122, 0.22), e=0.3, seg=(16, 8)), S, False))
    for z in np.arange(-0.68, 0.2, 0.07):
        body.append((box((-0.038, 0.11, z - 0.012), (0.038, 0.124, z + 0.012), e=0.5, seg=(8, 6)), "black", False))
    # цевьё с вентиляцией
    body.append((box((-0.066, -0.095, -0.99), (0.066, 0.085, -0.55), e=0.32, seg=(24, 12)), P, False))
    for z in (-0.9, -0.8, -0.7):
        for y in (-0.03, 0.035):
            body.append((box((-0.068, y - 0.014, z - 0.035), (0.068, y + 0.014, z + 0.035), e=0.5, seg=(8, 6)), "black", False))
    # ствол, дульный тормоз
    body.append((cyl(-1.12, -0.98, 0.026, (0, 0)), S, False))
    body.append((cyl(-1.21, -1.1, 0.036, (0, 0)), S, False))
    for z in (-1.18, -1.15, -1.12):
        body.append((box((-0.038, 0.01, z - 0.009), (0.038, 0.03, z + 0.009), e=0.5, seg=(8, 6)), "black", False))
    body.append((cyl(-1.215, -1.205, 0.016, (0, 0)), "black", False))
    # нижняя часть: шахта магазина, спусковая скоба, рукоять
    body.append((extrude([(-0.52, -0.06), (0.22, -0.06), (0.22, -0.155), (-0.29, -0.155), (-0.3, -0.25), (-0.5, -0.25), (-0.52, -0.2)], 0.058, 0.012), P, True))
    body.append((tube(smooth_path([(-0.155, -0.27), (-0.225, -0.25), (-0.255, -0.17), (-0.25, -0.05), (-0.19, 0.03)], 8), 0.014), P, False))
    body.append((tube(smooth_path([(-0.155, -0.14), (-0.2, -0.152), (-0.225, -0.136)], 6), 0.01), L, False))
    body.append((extrude([(0.0, -0.15), (0.14, -0.15), (0.2, -0.3), (0.24, -0.5), (0.14, -0.52), (0.09, -0.38), (0.04, -0.24)], 0.05, 0.014), G, True))
    # приклад: две трубки и затыльник
    for y in (0.01, -0.12):
        body.append((cyl(0.24, 0.84, 0.017, (0, y)), S, False))
    body.append((box((-0.06, -0.16, 0.2), (0.06, 0.07, 0.3), e=0.35, seg=(14, 8)), P, False))
    body.append((box((-0.06, -0.3, 0.8), (0.06, 0.05, 0.88), e=0.35, seg=(14, 8)), P, False))
    body.append((box((-0.062, -0.3, 0.87), (0.062, 0.05, 0.9), e=0.4, seg=(14, 8)), G, False))
    # целик (диоптр) и мушка с «ушами» (линия прицеливания — y = 0.19)
    body.append((box((-0.036, 0.12, 0.08), (0.036, 0.16, 0.16), e=0.35, seg=(10, 6)), S, False))
    body.append((cyl(0.11, 0.13, 0.03, (0, 0.19)), S, False))
    body.append((cyl(0.105, 0.135, 0.012, (0, 0.19)), "black", False))
    body.append((box((-0.034, 0.12, -0.65), (0.034, 0.145, -0.6), e=0.35, seg=(10, 6)), S, False))
    for x in (-0.027, 0.027):
        body.append((box((x - 0.006, 0.14, -0.645), (x + 0.006, 0.205, -0.605), e=0.5, seg=(8, 6)), S, False))
    body.append((box((-0.005, 0.14, -0.632), (0.005, 0.19, -0.618), e=0.6, seg=(8, 6)), L, False))
    body_mesh = join(body)

    path = [(-0.1 - 0.52 * t, -0.4 + 0.06 * t ** 1.5) for t in np.linspace(0, 1, 12)]
    mag = [(sweep(path, 0.034, 0.064, n_exp=6.0, seg=20), "mag", False),
           (box((-0.042, -0.65, -0.43), (0.042, -0.615, -0.27), e=0.35, seg=(12, 8)), P, False)]
    mag_mesh = join(mag)
    ch = [(blob((0.085, 0.03, -0.45), (0.03, 0.014, 0.016), e=0.8), L, False),
          (blob((0.118, 0.03, -0.45), (0.016, 0.022, 0.022)), L, False)]
    points = {
        "Muzzle": (0.0, 0.0, -1.215),
        "Eject": (0.065, 0.04, -0.2),
        "GripRight": (0.0, -0.31, 0.14),
        "GripLeft": (0.0, -0.058, -0.8),
        "SightRear": (0.0, 0.19, 0.12),
        "SightFront": (0.0, 0.19, -0.625),
        "MagWell": (0.0, -0.1, -0.4),
        "ChargingHandle": (0.12, 0.03, -0.45),
        "Stock": (0.0, -0.12, 0.9),
    }
    return {"Body": body_mesh, "Magazine": mag_mesh, "ChargingHandle": join(ch), "Casing": casing_mesh(0.066, 0.011)}, points


###############################################################################
# Дробовик: самозарядный, с коробчатым магазином, полимерная ложа, ствол с прицельной планкой
###############################################################################
def shotgun():
    P, S, L, G = "polymer", "steel", "steel_light", "grip"
    body = []
    body.append((extrude([(-0.62, -0.12), (0.34, -0.12), (0.34, 0.07), (0.31, 0.085), (-0.58, 0.085), (-0.62, 0.07)], 0.072, 0.014), S, True))
    # ствол, газовая трубка, цевьё с канавками
    body.append((cyl(-1.95, -0.6, 0.041, (0, 0)), S, False))
    body.append((cyl(-1.96, -1.945, 0.03, (0, 0)), "black", False))
    body.append((cyl(-1.28, -0.6, 0.03, (0, -0.075)), S, False))
    body.append((box((-0.078, -0.16, -1.24), (0.078, 0.035, -0.64), e=0.3, seg=(28, 14)), P, False))
    for z in np.arange(-1.18, -0.68, 0.075):
        body.append((box((-0.08, -0.13, z - 0.012), (0.08, -0.0, z + 0.012), e=0.6, seg=(10, 6)), "black", False))
    # прицельная планка на стволе, мушка-шарик, целик на коробке (линия прицеливания — y = 0.087)
    body.append((box((-0.016, 0.038, -1.92), (0.016, 0.058, -0.62), e=0.4, seg=(10, 6)), S, False))
    for z in np.arange(-1.85, -0.7, 0.12):
        body.append((box((-0.006, 0.035, z - 0.03), (0.006, 0.05, z + 0.03), e=0.6, seg=(8, 6)), "black", False))
    body.append((blob((0.0, 0.075, -1.9), (0.011, 0.011, 0.011)), "brass", False))
    for x in (-0.022, 0.022):
        body.append((box((x - 0.01, 0.075, 0.22), (x + 0.01, 0.1, 0.27), e=0.4, seg=(8, 6)), S, False))
    body.append((box((-0.034, 0.075, 0.22), (0.034, 0.085, 0.27), e=0.4, seg=(8, 6)), S, False))
    # окно выброса, шахта магазина
    body.append((box((0.06, -0.02, -0.38), (0.074, 0.055, -0.1), e=0.4, seg=(10, 6)), "black", False))
    body.append((extrude([(-0.52, -0.12), (-0.18, -0.12), (-0.18, -0.2), (-0.52, -0.2)], 0.068, 0.012), P, True))
    # спусковая скоба, спуск, рукоять
    body.append((tube(smooth_path([(-0.12, -0.12), (-0.2, -0.11), (-0.235, -0.02), (-0.23, 0.09), (-0.17, 0.15)], 8), 0.015), S, False))
    body.append((tube(smooth_path([(-0.12, 0.0), (-0.17, -0.012), (-0.2, 0.004)], 6), 0.011), L, False))
    body.append((extrude([(0.12, -0.12), (0.27, -0.12), (0.32, -0.27), (0.36, -0.46), (0.26, -0.48), (0.22, -0.35), (0.16, -0.21)], 0.052, 0.014), G, True))
    # приклад и резиновый затыльник
    body.append((extrude([(0.33, -0.12), (0.34, 0.075), (0.48, 0.066), (1.04, 0.02), (1.04, -0.33), (0.97, -0.35), (0.62, -0.25),
                          (0.5, -0.2)], 0.06, 0.016), P, True))
    body.append((extrude([(1.035, 0.025), (1.08, 0.025), (1.08, -0.335), (1.035, -0.335)], 0.064, 0.01), G, True))
    body_mesh = join(body)

    path = [(-0.1 - 0.46 * t, -0.35 + 0.05 * t) for t in np.linspace(0, 1, 8)]
    mag = [(sweep(path, 0.052, 0.1, n_exp=6.0, seg=20), "mag", False),
           (box((-0.06, -0.6, -0.47), (0.06, -0.555, -0.18), e=0.35, seg=(14, 8)), P, False)]
    ch = [(blob((0.1, 0.02, -0.5), (0.03, 0.016, 0.018), e=0.8), L, False),
          (blob((0.135, 0.02, -0.5), (0.018, 0.024, 0.024)), L, False)]
    points = {
        "Muzzle": (0.0, 0.0, -1.96),
        "Eject": (0.075, 0.03, -0.24),
        "GripRight": (0.0, -0.3, 0.27),
        "GripLeft": (0.0, -0.123, -0.95),
        "SightRear": (0.0, 0.087, 0.245),
        "SightFront": (0.0, 0.087, -1.9),
        "MagWell": (0.0, -0.1, -0.35),
        "ChargingHandle": (0.135, 0.02, -0.5),
        "Stock": (0.0, -0.16, 1.08),
    }
    return {"Body": body_mesh, "Magazine": join(mag), "ChargingHandle": join(ch), "Casing": shell_mesh()}, points


###############################################################################
# Снайперская винтовка: продольно-скользящий затвор, оливковая ложа, оптический прицел, дульный тормоз
###############################################################################
def sniper():
    P, S, L, G, OD = "polymer", "steel", "steel_light", "grip", "od"
    body = []
    # ствольная коробка и тяжёлый ствол с сужением, дульный тормоз
    body.append((cyl(-0.56, 0.26, 0.06, (0, 0)), S, False))
    body.append((cyl(-2.25, -0.55, 0.031, (0, 0), r1=0.045), S, False))
    body.append((box((-0.046, -0.046, -2.42), (0.046, 0.046, -2.24), e=0.35, seg=(14, 8)), S, False))
    for z in (-2.39, -2.33, -2.27):
        body.append((box((-0.048, -0.03, z - 0.018), (0.048, 0.03, z + 0.018), e=0.5, seg=(8, 6)), "black", False))
    body.append((cyl(-2.425, -2.415, 0.018, (0, 0)), "black", False))
    # ложа: цевьё, ложе коробки, рукоять, приклад с щекой, затыльник
    body.append((extrude([(-1.38, -0.05), (-0.5, -0.05), (-0.5, -0.21), (-1.32, -0.19), (-1.38, -0.15)], 0.074, 0.016), OD, True))
    body.append((extrude([(-0.52, -0.05), (0.3, -0.05), (0.3, -0.165), (-0.52, -0.21)], 0.07, 0.014), OD, True))
    body.append((extrude([(0.18, -0.16), (0.32, -0.16), (0.38, -0.32), (0.42, -0.48), (0.32, -0.5), (0.27, -0.36), (0.22, -0.24)], 0.05, 0.014), G, True))
    body.append((extrude([(0.29, -0.05), (0.45, -0.0), (0.95, 0.02), (1.12, 0.0), (1.12, -0.42), (1.04, -0.44), (0.56, -0.25),
                          (0.42, -0.165), (0.29, -0.165)], 0.064, 0.018), OD, True))
    body.append((extrude([(1.115, 0.005), (1.17, 0.005), (1.17, -0.425), (1.115, -0.425)], 0.066, 0.01), G, True))
    for x in (-0.072, 0.072):  # антабки
        body.append((blob((x, -0.17, -1.2), (0.006, 0.02, 0.02)), L, False))
    # спусковая скоба и спуск
    body.append((tube(smooth_path([(-0.165, -0.04), (-0.25, -0.03), (-0.275, 0.06), (-0.26, 0.15), (-0.17, 0.2)], 8), 0.014), S, False))
    body.append((tube(smooth_path([(-0.165, 0.07), (-0.21, 0.06), (-0.235, 0.08)], 6), 0.01), L, False))
    # шахта магазина
    body.append((box((-0.058, -0.25, -0.36), (0.058, -0.17, -0.13), e=0.35, seg=(14, 8)), "black", False))
    # прицел: планка, кольца, труба, объектив, окуляр, барабанчики, стёкла (ось — y = 0.2)
    body.append((box((-0.03, 0.05, -0.5), (0.03, 0.082, 0.2), e=0.3, seg=(14, 8)), S, False))
    for z in (-0.32, 0.02):
        body.append((box((-0.028, 0.07, z - 0.03), (0.028, 0.17, z + 0.03), e=0.35, seg=(10, 6)), S, False))
        body.append((cyl(z - 0.03, z + 0.03, 0.05, (0, 0.2)), S, False))
    body.append((cyl(-0.58, 0.14, 0.039, (0, 0.2)), "black", False))
    body.append((cyl(-0.68, -0.56, 0.04, (0, 0.2), r1=0.04), "black", False))
    body.append((cyl(-0.8, -0.66, 0.064, (0, 0.2), r1=0.042), "black", False))
    body.append((cyl(0.12, 0.32, 0.042, (0, 0.2), r1=0.047), "black", False))
    body.append((cyl(-0.806, -0.798, 0.056, (0, 0.2)), "glass", False))
    body.append((cyl(0.318, 0.326, 0.038, (0, 0.2)), "glass", False))
    body.append((blob((0.0, 0.27, -0.18), (0.034, 0.04, 0.034), e=0.3), "black", False))
    body.append((blob((0.065, 0.2, -0.18), (0.034, 0.03, 0.03), e=0.3), "black", False))
    body.append((blob((0.0, 0.312, -0.18), (0.03, 0.006, 0.03), e=0.4), L, False))
    body_mesh = join(body)

    path = [(-0.13 - 0.22 * t, -0.245 + 0.01 * t) for t in np.linspace(0, 1, 6)]
    mag = [(sweep(path, 0.04, 0.085, n_exp=6.0, seg=20), "mag", False),
           (box((-0.046, -0.38, -0.34), (0.046, -0.345, -0.14), e=0.35, seg=(12, 8)), P, False)]
    # затвор: хвостовик сзади коробки и рукоять справа с шаром
    bolt = [(cyl(0.25, 0.36, 0.042, (0, 0)), S, False),
            (blob((0.1, 0.0, 0.215), (0.062, 0.012, 0.012), e=1.0), L, False),
            (blob((0.168, -0.012, 0.215), (0.028, 0.028, 0.028)), "black", False)]
    points = {
        "Muzzle": (0.0, 0.0, -2.425),
        "Eject": (0.065, 0.06, -0.08),
        "GripRight": (0.0, -0.32, 0.31),
        "GripLeft": (0.0, -0.165, -0.95),
        "SightRear": (0.0, 0.2, 0.33),
        "SightFront": (0.0, 0.2, -0.8),
        "MagWell": (0.0, -0.13, -0.24),
        "ChargingHandle": (0.168, -0.012, 0.215),
        "Stock": (0.0, -0.21, 1.17),
    }
    return {"Body": body_mesh, "Magazine": join(mag), "ChargingHandle": join(bolt),
            "Casing": casing_mesh(0.165, 0.0155, neck=0.011)}, points


GUNS = {"Pistol": pistol, "SMG": smg, "Shotgun": shotgun, "Sniper": sniper}
ORDER = ["Body", "Magazine", "ChargingHandle", "Casing"]


def all_models():
    """Все модели (вместе с AK-47): имя -> (части, точки, атлас-картинка)."""
    out = {"AK47": (ak47.build(), ak47.POINTS, "ak")}
    for name, fn in GUNS.items():
        parts, points = fn()
        out[name] = (parts, points, "guns")
    return out


def v3(v):
    return "Vector3.new(%.4f, %.4f, %.4f)" % tuple(float(x) for x in v)


def write_config(models):
    lines = [
        "-- WeaponModels: геометрия моделей оружия (создаётся tools/weapons/guns.py — не править вручную).",
        "-- Оси оружия: ствол в −Z, верх +Y, правая сторона +X. Все точки — относительно центра детали Body",
        "-- (так Roblox ставит MeshPart: по центру габаритов), studs.",
        "return table.freeze({",
    ]
    for name in ["AK47"] + list(GUNS):
        parts, points, _ = models[name]
        info = {}
        for n in ORDER:
            lo, hi = parts[n].bbox()
            info[n] = ((lo + hi) / 2, hi - lo)
        body_c = info["Body"][0]
        lines += ["\t%s = table.freeze({" % name, "\t\tParts = table.freeze({"]
        for n in ORDER:
            c, s = info[n]
            lines.append("\t\t\t%s = table.freeze({ Offset = %s, Size = %s })," % (n, v3(c - body_c), v3(s)))
        lines += ["\t\t}),", "\t\tPoints = table.freeze({"]
        for pname, p in points.items():
            lines.append("\t\t\t%s = %s," % (pname, v3(np.array(p) - body_c)))
        lines += ["\t\t}),", "\t}),"]
    lines.append("})")
    path = os.path.join(ROOT, "src", "ReplicatedStorage", "Configs", "WeaponModels.lua")
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    print(path)


def colors(mesh, px):
    return px[np.clip((mesh.uv[:, 1] * ATLAS).astype(int), 0, ATLAS - 1), np.clip((mesh.uv[:, 0] * ATLAS).astype(int), 0, ATLAS - 1)]


def preview(name, parts, px):
    scene = []
    for n in ORDER:
        m = parts[n]
        off = np.array([0.25, 0.1, -0.2]) if n == "Casing" else np.zeros(3)
        scene.append((m.pos + off, m.nrm, colors(m, px), m.idx))
    lo, hi = parts["Body"].bbox()
    c = (lo + hi) / 2
    L = float(hi[2] - lo[2])
    views = [("справа", (L * 1.7, c[1], c[2])), ("слева, сверху", (-L * 1.2, L * 0.55, c[2] + L * 0.5)),
             ("три четверти спереди", (L * 0.9, L * 0.3, c[2] - L * 1.4)), ("от приклада", (0.0, c[1] + 0.25, c[2] + L * 1.4))]
    imgs = [render.label(render.render(scene, eye, tuple(c), fov=34, W=560, H=330, bg=(196, 198, 202)), t) for t, eye in views]
    render.sheet(imgs, 2).save(os.path.join(OUT, "preview_%s.png" % name.lower()))


def main():
    os.makedirs(OUT, exist_ok=True)
    png, atlas = atlas_png()
    atlas.save(os.path.join(OUT, "Guns_atlas.png"))
    px = np.asarray(atlas, float)
    models = all_models()
    for name in GUNS:
        parts = models[name][0]
        size = g.write_glb([(n, parts[n]) for n in ORDER], png, os.path.join(OUT, name + ".glb"))
        tris = sum(parts[n].tris for n in ORDER)
        lo, hi = parts["Body"].bbox()
        print("%-8s tris %5d  GLB %3d КБ  длина %.2f studs" % (name, tris, size // 1024, hi[2] - lo[2]))
        preview(name, parts, px)
    write_config(models)


if __name__ == "__main__":
    main()
