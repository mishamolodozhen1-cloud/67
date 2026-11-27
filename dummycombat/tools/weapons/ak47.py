#!/usr/bin/env python3
"""AK-47 для DUMMY COMBAT — своя процедурная модель (без чужих моделей).

Оси оружия: ствол смотрит в −Z, верх +Y, правая сторона +X, 1 stud (~0,31 м). Ось канала ствола — y = 0.
Части (узлы GLB = MeshPart в Roblox):
  Body            ствольная коробка, крышка, прицел, ствол, газовая трубка, цевьё, рукоять, приклад, спуск…
  Magazine        изогнутый магазин (отсоединяется при перезарядке)
  ChargingHandle  рукоять затворной рамы (отходит назад при передёргивании)
  Casing          гильза 7,62×39 (клиент выбрасывает копии)
Текстура — атлас 1024×1024: дерево с волокнами вдоль ствола, тёмное дерево рукояти, воронёная сталь,
светлая сталь, латунь, сталь магазина. Дерево и сталь проецируются сбоку (вдоль Z — волокна вдоль ствола).

Запуск: python3 tools/weapons/ak47.py -> build/weapons/AK47.glb, AK47_atlas.png, src/.../Configs/WeaponModels.lua,
build/weapons/preview_ak47.png
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
import geometry as g  # noqa: E402
import render  # noqa: E402

OUT = os.path.join(ROOT, "build", "weapons")

###############################################################################
# Атлас
###############################################################################
ATLAS = 1024
REGIONS = {  # имя: (u0, v0, u1, v1) в долях текстуры
    "wood": (0.0, 0.0, 1.0, 0.25),
    "grip": (0.0, 0.25, 0.5, 0.5),
    "steel": (0.5, 0.25, 1.0, 0.5),
    "steel_light": (0.0, 0.5, 0.5, 0.75),
    "brass": (0.5, 0.5, 0.75, 0.75),
    "black": (0.75, 0.5, 1.0, 0.75),
    "mag": (0.0, 0.75, 0.5, 1.0),
}
# область проекции сбоку: z (вдоль оружия) -> u, y -> v
Z_RANGE = (-1.7, 1.35)
Y_RANGE = (-0.9, 0.4)


def value_noise(w, h, cell, rng):
    gw, gh = w // cell + 2, h // cell + 2
    grid = rng.random((gh, gw))
    ys = np.arange(h) / cell
    xs = np.arange(w) / cell
    y0 = np.floor(ys).astype(int)
    x0 = np.floor(xs).astype(int)
    fy = (ys - y0)[:, None]
    fx = (xs - x0)[None, :]
    fy = fy * fy * (3 - 2 * fy)
    fx = fx * fx * (3 - 2 * fx)
    a = grid[y0][:, x0]
    b = grid[y0][:, x0 + 1]
    c = grid[y0 + 1][:, x0]
    d = grid[y0 + 1][:, x0 + 1]
    return a * (1 - fx) * (1 - fy) + b * fx * (1 - fy) + c * (1 - fx) * fy + d * fx * fy


def fbm(w, h, rng, cells=(64, 32, 16, 8)):
    out = np.zeros((h, w))
    amp, total = 1.0, 0.0
    for cell in cells:
        out += value_noise(w, h, cell, rng) * amp
        total += amp
        amp *= 0.55
    return out / total


def atlas_png():
    rng = np.random.default_rng(47)
    img = np.zeros((ATLAS, ATLAS, 3))

    def region(name):
        u0, v0, u1, v1 = REGIONS[name]
        return int(v0 * ATLAS), int(v1 * ATLAS), int(u0 * ATLAS), int(u1 * ATLAS)

    # дерево: орех, волокна вдоль u (вдоль ствола), годичные полосы с завихрениями
    y0, y1, x0, x1 = region("wood")
    h, w = y1 - y0, x1 - x0
    warp = fbm(w, h, rng, (128, 64, 32)) * 9
    yy = np.arange(h)[:, None] + warp * 6
    rings = 0.5 + 0.5 * np.sin(yy * 0.22 + fbm(w, h, rng, (256, 64)) * 4)
    fine = fbm(w, h, rng, (8, 4, 2))
    base = np.array([112, 64, 34], float)
    dark = np.array([70, 38, 20], float)
    t = np.clip(rings ** 3 * 0.75 + fine * 0.25, 0, 1)[..., None]
    img[y0:y1, x0:x1] = base * (1 - t) + dark * t
    # рукоять: тёмное дерево
    y0, y1, x0, x1 = region("grip")
    h, w = y1 - y0, x1 - x0
    n = fbm(w, h, rng, (64, 16, 4))[..., None]
    img[y0:y1, x0:x1] = np.array([74, 42, 26]) * (0.85 + 0.3 * n)
    # воронёная сталь: тёмная, с лёгким шумом и синевой
    for name, col, amt in (("steel", (44, 47, 52), 0.22), ("steel_light", (92, 94, 98), 0.18), ("mag", (40, 42, 44), 0.2)):
        y0, y1, x0, x1 = region(name)
        h, w = y1 - y0, x1 - x0
        n = fbm(w, h, rng, (32, 8, 2))[..., None]
        img[y0:y1, x0:x1] = np.array(col) * (1 - amt / 2 + amt * n)
    y0, y1, x0, x1 = region("brass")
    n = fbm(x1 - x0, y1 - y0, rng, (16, 4))[..., None]
    img[y0:y1, x0:x1] = np.array([196, 150, 70]) * (0.9 + 0.2 * n)
    y0, y1, x0, x1 = region("black")
    img[y0:y1, x0:x1] = (14, 14, 15)
    im = Image.fromarray(np.clip(img, 0, 255).astype(np.uint8))
    buf = io.BytesIO()
    im.save(buf, "PNG")
    return buf.getvalue(), im


def project(mesh, material):
    """UV: сбоку (z -> u, y -> v) внутри области материала, с полями, чтобы не цеплять соседние области."""
    u0, v0, u1, v1 = REGIONS[material]
    mu, mv = (u1 - u0) * 0.04, (v1 - v0) * 0.04
    zu = (mesh.pos[:, 2] - Z_RANGE[0]) / (Z_RANGE[1] - Z_RANGE[0])
    yv = 1 - (mesh.pos[:, 1] - Y_RANGE[0]) / (Y_RANGE[1] - Y_RANGE[0])
    mesh.uv = np.stack([u0 + mu + np.clip(zu, 0, 1) * (u1 - u0 - 2 * mu), v0 + mv + np.clip(yv, 0, 1) * (v1 - v0 - 2 * mv)], 1)
    return mesh


###############################################################################
# Геометрия
###############################################################################
def flat(mesh):
    """Жёсткие грани: у каждого треугольника свои вершины и своя нормаль."""
    p = mesh.pos[mesh.idx.reshape(-1)]
    uv = mesh.uv[mesh.idx.reshape(-1)]
    n = len(mesh.idx)
    a, b, c = p[0::3], p[1::3], p[2::3]
    fn = np.cross(b - a, c - a)
    ln = np.linalg.norm(fn, axis=1, keepdims=True)
    ln[ln < 1e-12] = 1
    fn = fn / ln
    m = g.Mesh()
    m.pos = p
    m.uv = uv
    m.nrm = np.repeat(fn, 3, axis=0)
    m.idx = np.arange(3 * n).reshape(-1, 3)
    return m


def triangulate(poly):
    """Ушная триангуляция простого многоугольника (вершины против часовой стрелки)."""
    pts = [tuple(p) for p in poly]
    idx = list(range(len(pts)))
    tris = []

    def area(a, b, c):
        return (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])

    def inside(p, a, b, c):
        return area(a, b, p) >= 0 and area(b, c, p) >= 0 and area(c, a, p) >= 0

    guard = 0
    while len(idx) > 3 and guard < 10000:
        guard += 1
        for k in range(len(idx)):
            i0, i1, i2 = idx[k - 1], idx[k], idx[(k + 1) % len(idx)]
            a, b, c = pts[i0], pts[i1], pts[i2]
            if area(a, b, c) <= 1e-12:
                continue
            if any(inside(pts[j], a, b, c) for j in idx if j not in (i0, i1, i2)):
                continue
            tris.append((i0, i1, i2))
            idx.pop(k)
            break
    if len(idx) == 3:
        tris.append(tuple(idx))
    return tris


def signed_area(poly):
    return 0.5 * sum(poly[i][0] * poly[(i + 1) % len(poly)][1] - poly[(i + 1) % len(poly)][0] * poly[i][1] for i in range(len(poly)))


def inset(poly, d):
    """Сдвиг контура внутрь на d (по биссектрисам)."""
    n = len(poly)
    out = []
    for i in range(n):
        p0, p1, p2 = np.array(poly[i - 1]), np.array(poly[i]), np.array(poly[(i + 1) % n])
        e1 = (p1 - p0) / max(1e-9, np.linalg.norm(p1 - p0))
        e2 = (p2 - p1) / max(1e-9, np.linalg.norm(p2 - p1))
        n1 = np.array([-e1[1], e1[0]])  # внутренняя нормаль для обхода против часовой
        n2 = np.array([-e2[1], e2[0]])
        bis = n1 + n2
        bl = np.linalg.norm(bis)
        bis = bis / bl if bl > 1e-9 else n1
        cos = max(0.35, float(np.dot(bis, n1)))
        out.append(tuple(p1 + bis * d / cos))
    return out


def extrude(profile, half_width, bevel=0.012, x_center=0.0):
    """Профиль (z, y) выдавливается вдоль X на ±half_width с фаской bevel по краям. Жёсткие грани."""
    prof = list(profile)
    if signed_area(prof) < 0:
        prof = prof[::-1]
    inner = inset(prof, bevel)
    n = len(prof)
    pos, idx = [], []

    def ring(points, x):
        base = len(pos)
        for (z, y) in points:
            pos.append((x_center + x, y, z))
        return base

    xa, xb = half_width - bevel, half_width
    r_in_l = ring(inner, -xb)
    r_out_l = ring(prof, -xa)
    r_out_r = ring(prof, xa)
    r_in_r = ring(inner, xb)

    def strip(ra, rb):
        for i in range(n):
            j = (i + 1) % n
            idx.append((ra + i, rb + i, ra + j))
            idx.append((ra + j, rb + i, rb + j))

    strip(r_in_l, r_out_l)
    strip(r_out_l, r_out_r)
    strip(r_out_r, r_in_r)
    for (a, b, c) in triangulate(inner):
        idx.append((r_in_r + a, r_in_r + b, r_in_r + c))
        idx.append((r_in_l + a, r_in_l + c, r_in_l + b))
    m = g.Mesh(pos, idx)
    fix_winding(m)
    return m


def orient(m):
    """Лицевые стороны — наружу (Roblox рисует только их). Сначала обход соседних треугольников согласуется
    по общим рёбрам (у соседей общее ребро проходится в разные стороны), затем каждая замкнутая часть
    поворачивается наружу по знаку объёма."""
    idx = m.idx.copy()
    edges = {}
    for f, (a, b, c) in enumerate(idx):
        for u, v in ((a, b), (b, c), (c, a)):
            edges.setdefault((min(u, v), max(u, v)), []).append(f)
    seen = np.zeros(len(idx), bool)
    for start in range(len(idx)):
        if seen[start]:
            continue
        seen[start] = True
        stack, comp = [start], [start]
        while stack:
            f = stack.pop()
            a, b, c = idx[f]
            for u, v in ((a, b), (b, c), (c, a)):
                for h in edges[(min(u, v), max(u, v))]:
                    if seen[h]:
                        continue
                    x, y, z = idx[h]
                    if (u, v) in ((x, y), (y, z), (z, x)):
                        idx[h] = idx[h][::-1]
                    seen[h] = True
                    stack.append(h)
                    comp.append(h)
        sub = idx[comp]
        pa, pb, pc = (m.pos[sub[:, k]] for k in range(3))
        if np.einsum("ij,ij->i", pa, np.cross(pb, pc)).sum() < 0:
            idx[comp] = sub[:, ::-1]
    m.idx = idx
    m.nrm = m._smooth_normals()


fix_winding = orient


def box(lo, hi, e=0.12, seg=(20, 12)):
    lo, hi = np.array(lo, float), np.array(hi, float)
    return g.superellipsoid(tuple((lo + hi) / 2), tuple((hi - lo) / 2), e=e, seg_u=seg[0], seg_v=seg[1])


def cylinder_z(z0, z1, r, center=(0.0, 0.0), seg=24, rounded=0.0, r1=None):
    """Цилиндр вдоль Z (от z0 до z1), радиус r (r1 — на конце z1)."""
    r1 = r if r1 is None else r1
    rings = []
    if rounded:
        rings.append((0.0, r * 0.6, r * 0.6))
    rings += [(rounded, r, r), (1.0 - rounded, r1, r1)]
    if rounded:
        rings.append((1.0, r1 * 0.6, r1 * 0.6))
    m = g.lathe(rings, seg=seg, pole_bottom=0.0, pole_top=1.0)
    # lathe строит вдоль Y от 0 до 1: растягиваем и поворачиваем на ось Z
    m.pos[:, 1] *= (z1 - z0)
    m = m.transformed(g.rot_x(-math.pi / 2), (0, 0, 0))
    m.pos[:, 2] = -m.pos[:, 2]  # y (0..L) -> z (0..L) в положительную сторону
    m.pos += np.array([center[0], center[1], z0])
    m.nrm[:, 2] = -m.nrm[:, 2]
    fix_winding(m)
    return m


def sweep(path, half_x, half_n, n_exp=4.0, seg=20):
    """Сечение (суперэллипс half_x по X и half_n по нормали пути в плоскости YZ) вдоль пути path [(y, z)]."""
    pts = [np.array([0.0, y, z]) for (y, z) in path]
    pos, idx = [], []
    for i, p in enumerate(pts):
        t = pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]
        t = t / np.linalg.norm(t)
        side = np.array([1.0, 0, 0])
        nrm = np.cross(t, side)
        nrm /= np.linalg.norm(nrm)
        hx = half_x[i] if isinstance(half_x, (list, tuple)) else half_x
        hn = half_n[i] if isinstance(half_n, (list, tuple)) else half_n
        for k in range(seg):
            a = 2 * math.pi * k / seg
            c, s = math.cos(a), math.sin(a)
            sx = math.copysign(abs(c) ** (2 / n_exp), c)
            sn = math.copysign(abs(s) ** (2 / n_exp), s)
            pos.append(tuple(p + side * hx * sx + nrm * hn * sn))
    R = len(pts)
    for r in range(R - 1):
        for k in range(seg):
            a = r * seg + k
            b = r * seg + (k + 1) % seg
            c = (r + 1) * seg + k
            d = (r + 1) * seg + (k + 1) % seg
            idx += [(a, c, b), (b, c, d)]
    for (ri, sign) in ((0, 1), (R - 1, -1)):
        center = len(pos)
        pos.append(tuple(pts[ri]))
        for k in range(seg):
            a, b = ri * seg + k, ri * seg + (k + 1) % seg
            idx.append((center, a, b) if sign > 0 else (center, b, a))
    m = g.Mesh(pos, idx)
    fix_winding(m)
    return m


def tube(path, r, seg=10):
    return sweep(path, r, r, n_exp=2.0, seg=seg)


def smooth_path(points, n=24):
    """Сглаженный путь через точки (сплайн Катмулла — Рома)."""
    pts = [np.array(p, float) for p in points]
    out = []
    for i in range(len(pts) - 1):
        p0, p1, p2 = pts[max(i - 1, 0)], pts[i], pts[i + 1]
        p3 = pts[min(i + 2, len(pts) - 1)]
        for k in range(n):
            t = k / n
            t2, t3 = t * t, t * t * t
            out.append(0.5 * ((2 * p1) + (p2 - p0) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (3 * p1 - p0 - 3 * p2 + p3) * t3))
    out.append(pts[-1])
    return [tuple(p) for p in out]


def join(items):
    """items: [(Mesh, материал, жёсткие грани?)] -> один Mesh."""
    out = g.Mesh()
    for m, mat, hard in items:
        project(m, mat)
        out.add(flat(m) if hard else m)
    return out


###############################################################################
# AK-47
###############################################################################
def build():
    body = []
    S, W, G = "steel", "wood", "grip"
    # ствольная коробка и крышка
    body.append((extrude([(-0.74, -0.13), (0.30, -0.13), (0.30, 0.05), (0.26, 0.058), (-0.70, 0.058), (-0.74, 0.04)], 0.072, 0.012), S, True))
    body.append((box((-0.07, 0.03, -0.52), (0.07, 0.115, 0.29), e=0.45, seg=(28, 14)), S, False))
    # рёбра жёсткости на крышке
    for z in (-0.28, -0.12, 0.04, 0.18):
        body.append((box((-0.074, 0.06, z - 0.012), (0.074, 0.1, z + 0.012), e=0.4, seg=(12, 8)), "steel_light", False))
    # прицельная колодка и планка (верх целика — линия прицеливания y = 0.135)
    body.append((extrude([(-0.76, 0.05), (-0.52, 0.05), (-0.52, 0.11), (-0.60, 0.128), (-0.76, 0.128)], 0.05, 0.01), S, True))
    body.append((extrude([(-0.70, 0.125), (-0.56, 0.125), (-0.56, 0.135), (-0.70, 0.142)], 0.032, 0.004), "steel_light", True))
    # передняя часть коробки (трунион) и ствол
    body.append((extrude([(-0.82, -0.11), (-0.74, -0.11), (-0.74, 0.05), (-0.82, 0.04)], 0.068, 0.01), S, True))
    body.append((cylinder_z(-1.50, -0.80, 0.034, (0, 0)), S, False))
    # цевьё: нижнее (дерево, с выемками под пальцы) и верхняя накладка над газовой трубкой
    body.append((box((-0.08, -0.122, -1.13), (0.08, 0.04, -0.80), e=0.3, seg=(32, 18)), W, False))
    for z in (-0.88, -0.96, -1.04):
        body.append((box((-0.084, -0.08, z - 0.012), (0.084, -0.06, z + 0.012), e=0.6, seg=(12, 8)), G, False))
    body.append((box((-0.056, 0.042, -1.11), (0.056, 0.125, -0.82), e=0.38, seg=(28, 14)), W, False))
    # газовая трубка спереди, газовый блок, кольцо
    body.append((cylinder_z(-1.20, -1.08, 0.032, (0, 0.088)), S, False))
    body.append((extrude([(-1.25, -0.045), (-1.18, -0.045), (-1.18, 0.125), (-1.25, 0.125)], 0.048, 0.012), S, True))
    body.append((cylinder_z(-0.84, -0.79, 0.05, (0, 0.0)), S, False))
    # мушка: основание, «уши» и стойка (верх стойки — y = 0.135)
    body.append((cylinder_z(-1.47, -1.39, 0.047, (0, 0.0)), S, False))
    body.append((extrude([(-1.465, 0.02), (-1.40, 0.02), (-1.405, 0.15), (-1.46, 0.15)], 0.009, 0.003, x_center=0.04), S, True))
    body.append((extrude([(-1.465, 0.02), (-1.40, 0.02), (-1.405, 0.15), (-1.46, 0.15)], 0.009, 0.003, x_center=-0.04), S, True))
    body.append((cylinder_z(-1.44, -1.425, 0.007, (0, 0.135)), "steel_light", False))
    body.append((extrude([(-1.44, 0.03), (-1.425, 0.03), (-1.425, 0.135), (-1.44, 0.135)], 0.006, 0.002), "steel_light", True))
    # дульный компенсатор (срез под углом), чёрный канал
    body.append((cylinder_z(-1.61, -1.49, 0.042, (0, 0.0)), S, False))
    body.append((cylinder_z(-1.615, -1.60, 0.016, (0, 0.0)), "black", False))
    # рукоять (тёмное дерево)
    body.append((extrude([(-0.035, -0.12), (0.10, -0.12), (0.135, -0.24), (0.175, -0.42), (0.16, -0.51),
                          (0.08, -0.515), (0.055, -0.40), (0.02, -0.22)], 0.052, 0.014), G, True))
    # спусковая скоба и спусковой крючок
    body.append((tube(smooth_path([(-0.13, 0.03), (-0.22, 0.02), (-0.235, -0.08), (-0.22, -0.24), (-0.13, -0.29)], 8), 0.012), S, False))
    body.append((tube(smooth_path([(-0.125, -0.13), (-0.17, -0.135), (-0.20, -0.15)], 6), 0.009), "steel_light", False))
    # приклад (дерево) и затыльник (сталь)
    body.append((extrude([(0.28, -0.12), (0.30, 0.05), (0.44, 0.045), (1.22, -0.02), (1.22, -0.41), (1.14, -0.43),
                          (0.44, -0.165)], 0.058, 0.016), W, True))
    body.append((extrude([(1.215, -0.025), (1.25, -0.025), (1.25, -0.42), (1.215, -0.42)], 0.064, 0.008), S, True))
    # переводчик огня (длинная планка справа) и заклёпки
    body.append((extrude([(-0.55, -0.01), (-0.10, -0.01), (-0.10, 0.02), (-0.52, 0.03), (-0.55, -0.04), (-0.50, -0.06)], 0.005, 0.002, x_center=0.079), "steel_light", True))
    for z in (-0.66, -0.60, 0.12, 0.22):
        for x in (-0.074, 0.074):
            body.append((g.superellipsoid((x, -0.085, z), (0.008, 0.012, 0.012), e=1.0, seg_u=10, seg_v=6), "steel_light", False))
    body_mesh = join(body)

    # магазин: изогнутый, ребро сзади
    path = []
    for i in range(14):
        t = i / 13
        path.append((-0.10 - 0.70 * t, -0.415 - 0.30 * t ** 1.6))
    depth = [0.115 + 0.012 * (i / 13) for i in range(14)]
    mag = [(sweep(path, 0.043, depth, n_exp=6.0, seg=24), "mag", False)]
    rib = [(y, z + 0.108 + 0.01 * (i / 13)) for i, (y, z) in enumerate(path)]
    mag.append((sweep(rib, 0.012, 0.012, n_exp=4.0, seg=8), "mag", False))
    mag_mesh = join(mag)

    # рукоять затвора (справа)
    ch = [(g.superellipsoid((0.11, 0.02, -0.44), (0.04, 0.016, 0.016), e=0.8, seg_u=14, seg_v=8), "steel_light", False),
          (g.superellipsoid((0.155, 0.02, -0.44), (0.02, 0.022, 0.022), e=1.0, seg_u=14, seg_v=10), "steel_light", False)]
    ch_mesh = join(ch)

    # гильза 7,62×39 (вдоль Z, дно в +Z)
    casing = g.lathe([(0.0, 0.017, 0.017), (0.006, 0.0175, 0.0175), (0.012, 0.015, 0.015), (0.016, 0.0175, 0.0175),
                      (0.085, 0.0165, 0.0165), (0.098, 0.012, 0.012), (0.125, 0.012, 0.012)], seg=16, pole_bottom=0.0, pole_top=0.125)
    casing = casing.transformed(g.rot_x(math.pi / 2), (0, 0, 0))
    project(casing, "brass")
    return {"Body": body_mesh, "Magazine": mag_mesh, "ChargingHandle": ch_mesh, "Casing": casing}


# Точки оружия (в осях оружия): для рук, прицела, вспышки, гильз, перезарядки
POINTS = {
    "Muzzle": (0.0, 0.0, -1.615),
    "Eject": (0.08, 0.06, -0.30),
    "GripRight": (0.0, -0.27, 0.09),     # правая кисть на рукояти
    "GripLeft": (0.0, -0.085, -0.97),    # левая кисть под цевьём
    "SightRear": (0.0, 0.135, -0.63),    # прорезь целика
    "SightFront": (0.0, 0.135, -1.432),  # верх мушки
    "MagWell": (0.0, -0.12, -0.415),     # верх магазина
    "ChargingHandle": (0.155, 0.02, -0.44),
    "Stock": (0.0, -0.21, 1.25),         # затыльник (в плечо)
}


def v3(v):
    return "Vector3.new(%.4f, %.4f, %.4f)" % tuple(float(x) for x in v)


def main():
    os.makedirs(OUT, exist_ok=True)
    png, atlas = atlas_png()
    atlas.save(os.path.join(OUT, "AK47_atlas.png"))
    parts = build()
    order = ["Body", "Magazine", "ChargingHandle", "Casing"]
    size = g.write_glb([(n, parts[n]) for n in order], png, os.path.join(OUT, "AK47.glb"))
    info = {}
    for n in order:
        lo, hi = parts[n].bbox()
        info[n] = ((lo + hi) / 2, hi - lo)
        print(f"{n:15s} tris {parts[n].tris:5d} size {np.round(hi - lo, 3).tolist()}")
    print(f"GLB {size // 1024} КБ")
    # конфиг: центры частей (как их поставит Roblox — по габаритам) и точки — всё относительно центра Body
    body_c = info["Body"][0]
    lines = [
        "-- WeaponModels: геометрия моделей оружия (создаётся tools/weapons/ak47.py — не править вручную).",
        "-- Оси оружия: ствол в −Z, верх +Y, правая сторона +X. Все точки — относительно центра детали Body",
        "-- (так Roblox ставит MeshPart: по центру габаритов), studs.",
        "return table.freeze({",
        "\tAK47 = table.freeze({",
        "\t\tParts = table.freeze({",
    ]
    for n in order:
        c, s = info[n]
        lines.append("\t\t\t%s = table.freeze({ Offset = %s, Size = %s })," % (n, v3(c - body_c), v3(s)))
    lines.append("\t\t}),")
    lines.append("\t\tPoints = table.freeze({")
    for name, p in POINTS.items():
        lines.append("\t\t\t%s = %s," % (name, v3(np.array(p) - body_c)))
    lines.append("\t\t}),")
    lines.append("\t}),")
    lines.append("})")
    path = os.path.join(ROOT, "src", "ReplicatedStorage", "Configs", "WeaponModels.lua")
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    # картинки
    px = np.asarray(atlas, float)

    def items(name, offset=(0, 0, 0)):
        m = parts[name]
        col = px[np.clip((m.uv[:, 1] * ATLAS).astype(int), 0, ATLAS - 1), np.clip((m.uv[:, 0] * ATLAS).astype(int), 0, ATLAS - 1)]
        return (m.pos + np.array(offset), m.nrm, col, m.idx)

    scene = [items("Body"), items("Magazine"), items("ChargingHandle"), items("Casing", (0.3, 0.1, -0.3))]
    views = [("справа", (5.0, 0.05, -0.2)), ("слева, сверху", (-3.4, 1.6, 1.6)), ("три четверти спереди", (2.6, 0.9, -4.2)), ("от приклада", (0.0, 0.25, 4.0))]
    imgs = [render.label(render.render(scene, eye, (0, -0.15, -0.2), fov=34, W=640, H=380, bg=(196, 198, 202)), t) for t, eye in views]
    render.sheet(imgs, 2).save(os.path.join(OUT, "preview_ak47.png"))
    print(os.path.join(OUT, "preview_ak47.png"))


if __name__ == "__main__":
    main()
