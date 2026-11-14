#!/usr/bin/env python3
"""Переводит выгрузку OpenStreetMap центра Казани в компактные данные для Roblox.

Вход: merged.json (узлы/линии/отношения OSM, см. merge_osm.py).
Выход: ModuleScript-ы с данными в kazan/src/ServerScriptService/CityData/.

Масштаб: 1 стад = 0,3 м (персонаж ~1,65 м), то есть город в натуральную величину.
Оси: +X — восток, -Z — север, Y — вверх. Начало координат — Спасская башня Кремля.
Данные © OpenStreetMap contributors, ODbL.
"""
import json
import math
import os
import random
import sys

import numpy as np

M_PER_STUD = 0.3
S = 1.0 / M_PER_STUD

BBOX = (55.7880, 49.0980, 55.8150, 49.1265)  # юг, запад, север, восток
CELL = 8.0  # шаг растра для рельефа, стадов

HERE = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.join(HERE, "..", "src", "ServerScriptService", "CityData")

# Достопримечательности, которые строятся вручную (их OSM-контуры пропускаем).
LANDMARKS = {
    "KulSharif": ("way", "230132591"),
    "Syuyumbike": ("way", "228963085"),
    "Annunciation": ("way", "259988409"),
    "FarmersPalace": ("way", "90251771"),
    "BellTower": ("way", "99325935"),
    "FamilyCenter": ("way", "222787130"),
    "PeterPaul": ("way", "90178098"),
    "Spasskaya": ("relation", "15958803"),
    "Preobrazhenskaya": ("relation", "15958805"),
    "Tainitskaya": ("relation", "15958807"),
    "SouthWest": ("relation", "15958804"),
    "SouthEast": ("relation", "15958802"),
    "Nameless": ("relation", "15958806"),
    "Konsistorskaya": ("relation", "6303321"),
}
# Известные цвета зданий, которых нет в OSM.
COLOR_OVERRIDES = {
    "90162019": ("e9cd74", "5a6a5e"),  # Президентский (Губернаторский) дворец — жёлтый с белым
}
# Точки интереса для телепортов: имя в игре -> название улицы в OSM.
POI_STREETS = {
    "Улица Баумана": "улица Баумана",
    "Кремлёвская дамба": "Кремлёвская дамба",
    "Кремлёвская набережная": "Кремлёвская набережная",
}
LANDMARK_TITLES = {
    "Spasskaya": "Спасская башня", "KulSharif": "Мечеть Кул Шариф", "Syuyumbike": "Башня Сююмбике",
    "Annunciation": "Благовещенский собор", "FarmersPalace": "Дворец земледельцев",
    "BellTower": "Колокольня Богоявленского собора", "PeterPaul": "Петропавловский собор",
    "FamilyCenter": "Центр семьи «Казан»",
}
TOWER_HEIGHTS_M = {"Spasskaya": 47, "Preobrazhenskaya": 21.5, "Tainitskaya": 29, "SouthWest": 14,
                   "SouthEast": 19, "Nameless": 23, "Konsistorskaya": 23}


def load(path):
    d = json.load(open(path))
    return d["nodes"], d["ways"], d["rels"]


def setup_projection(lat0, lon0):
    phi = math.radians(lat0)
    m_lat = 111132.954 - 559.822 * math.cos(2 * phi) + 1.175 * math.cos(4 * phi)
    m_lon = 111412.84 * math.cos(phi) - 93.5 * math.cos(3 * phi)

    def proj(lat, lon):
        return ((lon - lon0) * m_lon * S, -(lat - lat0) * m_lat * S)

    return proj


# ---------------------------------------------------------------- геометрия
def ring_area(r):
    a = 0.0
    for i in range(len(r)):
        x1, z1 = r[i]
        x2, z2 = r[(i + 1) % len(r)]
        a += x1 * z2 - x2 * z1
    return a / 2


def centroid(r):
    a = ring_area(r)
    if abs(a) < 1e-6:
        xs = [p[0] for p in r]
        zs = [p[1] for p in r]
        return sum(xs) / len(xs), sum(zs) / len(zs)
    cx = cz = 0.0
    for i in range(len(r)):
        x1, z1 = r[i]
        x2, z2 = r[(i + 1) % len(r)]
        f = x1 * z2 - x2 * z1
        cx += (x1 + x2) * f
        cz += (z1 + z2) * f
    return cx / (6 * a), cz / (6 * a)


def convex_hull(pts):
    pts = sorted(set(pts))
    if len(pts) <= 2:
        return pts

    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])

    lower, upper = [], []
    for p in pts:
        while len(lower) >= 2 and cross(lower[-2], lower[-1], p) <= 0:
            lower.pop()
        lower.append(p)
    for p in reversed(pts):
        while len(upper) >= 2 and cross(upper[-2], upper[-1], p) <= 0:
            upper.pop()
        upper.append(p)
    return lower[:-1] + upper[:-1]


def min_rect_angle(pts):
    hull = convex_hull(pts)
    best = (float("inf"), 0.0)
    for i in range(len(hull)):
        x1, z1 = hull[i]
        x2, z2 = hull[(i + 1) % len(hull)]
        ang = math.atan2(z2 - z1, x2 - x1)
        c, s = math.cos(-ang), math.sin(-ang)
        xs = [p[0] * c - p[1] * s for p in hull]
        zs = [p[0] * s + p[1] * c for p in hull]
        area = (max(xs) - min(xs)) * (max(zs) - min(zs))
        if area < best[0]:
            best = (area, ang)
    return best[1]


def scan_fill(rings, xs0, z_centers, nx, cell):
    """Растр по правилу чёт-нечет: rings — список колец, возвращает bool[rows, nx]."""
    grid = np.zeros((len(z_centers), nx), dtype=bool)
    edges = []
    for r in rings:
        for i in range(len(r)):
            x1, z1 = r[i]
            x2, z2 = r[(i + 1) % len(r)]
            if z1 != z2:
                edges.append((x1, z1, x2, z2))
    if not edges:
        return grid
    e = np.array(edges)
    zmin = np.minimum(e[:, 1], e[:, 3])
    zmax = np.maximum(e[:, 1], e[:, 3])
    for row, zc in enumerate(z_centers):
        m = (zmin <= zc) & (zmax > zc)
        if not m.any():
            continue
        ee = e[m]
        t = (zc - ee[:, 1]) / (ee[:, 3] - ee[:, 1])
        xi = np.sort(ee[:, 0] + t * (ee[:, 2] - ee[:, 0]))
        for k in range(0, len(xi) - 1, 2):
            a = int(math.ceil((xi[k] - xs0) / cell - 0.5))
            b = int(math.floor((xi[k + 1] - xs0) / cell - 0.5))
            a = max(a, 0)
            b = min(b, nx - 1)
            if b >= a:
                grid[row, a:b + 1] = True
    return grid


def greedy_rects(grid):
    """Склеивает одинаковые отрезки соседних строк в прямоугольники."""
    rects = []
    openr = {}
    rows, cols = grid.shape
    for r in range(rows + 1):
        runs = set()
        if r < rows:
            c = 0
            while c < cols:
                if grid[r, c]:
                    s = c
                    while c < cols and grid[r, c]:
                        c += 1
                    runs.add((s, c))
                else:
                    c += 1
        newopen = {}
        for key, start in openr.items():
            if key in runs:
                newopen[key] = start
            else:
                rects.append((key[0], start, key[1], r))
        for key in runs:
            if key not in newopen:
                newopen[key] = r
        openr = newopen
    return rects


def simplify(r, eps, closed=True):
    if len(r) < (4 if closed else 3):
        return r

    def dp(pts):
        if len(pts) < 3:
            return pts
        (x1, z1), (x2, z2) = pts[0], pts[-1]
        dx, dz = x2 - x1, z2 - z1
        L = math.hypot(dx, dz) or 1e-9
        best, idx = -1, 0
        for i in range(1, len(pts) - 1):
            d = abs(dz * pts[i][0] - dx * pts[i][1] + x2 * z1 - z2 * x1) / L
            if d > best:
                best, idx = d, i
        if best > eps:
            return dp(pts[: idx + 1])[:-1] + dp(pts[idx:])
        return [pts[0], pts[-1]]

    if not closed:
        return dp(list(r))
    # Замкнутое кольцо делим на две ломаные: от первой точки до самой дальней и обратно.
    far = max(range(len(r)), key=lambda i: math.dist(r[0], r[i]))
    out = dp(r[: far + 1])[:-1] + dp(r[far:] + [r[0]])[:-1]
    return out if len(out) >= 3 else r


def ear_clip(ring):
    pts = list(ring)
    if ring_area(pts) < 0:
        pts.reverse()
    idx = list(range(len(pts)))
    tris = []

    def is_convex(a, b, c):
        return (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0]) > 1e-9

    def inside(p, a, b, c):
        d1 = (p[0] - b[0]) * (a[1] - b[1]) - (a[0] - b[0]) * (p[1] - b[1])
        d2 = (p[0] - c[0]) * (b[1] - c[1]) - (b[0] - c[0]) * (p[1] - c[1])
        d3 = (p[0] - a[0]) * (c[1] - a[1]) - (c[0] - a[0]) * (p[1] - a[1])
        neg = d1 < 0 or d2 < 0 or d3 < 0
        pos = d1 > 0 or d2 > 0 or d3 > 0
        return not (neg and pos)

    guard = 0
    while len(idx) > 3 and guard < 5000:
        guard += 1
        found = False
        for i in range(len(idx)):
            ia, ib, ic = idx[i - 1], idx[i], idx[(i + 1) % len(idx)]
            a, b, c = pts[ia], pts[ib], pts[ic]
            if not is_convex(a, b, c):
                continue
            if any(inside(pts[j], a, b, c) for j in idx if j not in (ia, ib, ic)):
                continue
            tris.append((a, b, c))
            idx.pop(i)
            found = True
            break
        if not found:
            break
    if len(idx) == 3:
        tris.append(tuple(pts[i] for i in idx))
    return tris


def tri_to_wedges(a, b, c):
    """Треугольник (в плоскости XZ) -> два прямоугольных треугольника для WedgePart."""
    pts = [a, b, c]
    best = None
    for i in range(3):
        p, q, r = pts[i], pts[(i + 1) % 3], pts[(i + 2) % 3]
        L = math.dist(p, q)
        if best is None or L > best[0]:
            best = (L, p, q, r)
    L, p, q, r = best
    if L < 0.1:
        return []
    ux, uz = (q[0] - p[0]) / L, (q[1] - p[1]) / L
    t = (r[0] - p[0]) * ux + (r[1] - p[1]) * uz
    f = (p[0] + ux * t, p[1] + uz * t)
    out = []
    for end in (p, q):
        a_len = math.dist(f, r)
        b_len = math.dist(f, end)
        if a_len < 0.05 or b_len < 0.05:
            continue
        u = ((r[0] - f[0]) / a_len, (r[1] - f[1]) / a_len)
        v = ((end[0] - f[0]) / b_len, (end[1] - f[1]) / b_len)
        cx = f[0] + u[0] * a_len / 2 + v[0] * b_len / 2
        cz = f[1] + u[1] * a_len / 2 + v[1] * b_len / 2
        out.append((cx, cz, u, v, a_len, b_len))
    return out


# ---------------------------------------------------------------- OSM
def ways_to_rings(way_ids, ways, nodes, proj):
    segs = []
    for wid in way_ids:
        if wid not in ways:
            continue
        nds = [n for n in ways[wid][0] if n in nodes]
        if len(nds) >= 2:
            segs.append(nds)
    rings = []
    while segs:
        cur = segs.pop(0)
        changed = True
        while cur[0] != cur[-1] and changed:
            changed = False
            for i, s in enumerate(segs):
                if s[0] == cur[-1]:
                    cur = cur + s[1:]
                elif s[-1] == cur[-1]:
                    cur = cur + s[::-1][1:]
                elif s[-1] == cur[0]:
                    cur = s + cur[1:]
                elif s[0] == cur[0]:
                    cur = s[::-1] + cur[1:]
                else:
                    continue
                segs.pop(i)
                changed = True
                break
        if len(cur) >= 4 and cur[0] == cur[-1]:
            rings.append([proj(nodes[n][0], nodes[n][1]) for n in cur[:-1]])
    return rings


def polygons(ways, rels, nodes, proj, pred):
    """Площадные объекты: [(id, tags, outer_rings, inner_rings)]."""
    out = []
    for wid, (nds, t) in ways.items():
        if pred(t) and len(nds) >= 4 and nds[0] == nds[-1] and all(n in nodes for n in nds):
            out.append((("way", wid), t, [[proj(nodes[n][0], nodes[n][1]) for n in nds[:-1]]], []))
    for rid, (mem, t) in rels.items():
        if t.get("type") == "multipolygon" and pred(t):
            outer = ways_to_rings([m[1] for m in mem if m[0] == "way" and m[2] in ("outer", "")], ways, nodes, proj)
            inner = ways_to_rings([m[1] for m in mem if m[0] == "way" and m[2] == "inner"], ways, nodes, proj)
            if outer:
                out.append((("relation", rid), t, outer, inner))
    return out


def parse_m(v):
    if not v:
        return None
    try:
        return float(v.replace("m", "").replace(",", ".").strip().split()[0])
    except ValueError:
        return None


NAMED_COLORS = {
    "white": "eeebe4", "red": "a8463a", "yellow": "e6cc84", "brown": "8a5a3c", "grey": "a8a8a4",
    "gray": "a8a8a4", "beige": "e3d3b4", "pink": "e2b8b0", "orange": "e0a070", "green": "8fb08a",
    "blue": "9fb6cc", "lightgray": "c8c8c4", "lightgrey": "c8c8c4", "darkgray": "6a6a6a", "black": "333333",
    "maroon": "7a3030", "cream": "efe4c8", "silver": "c0c0c0",
}
FACADE = ["e8dcbe", "ecd696", "e6c0a0", "e2b8b0", "eeebe4", "c8ceb8", "b4c4d2", "d8c8a8", "f0e4cc", "e0cfa8"]
ROOFS = ["5a6460", "4f6a58", "6e4a3c", "7a7a76", "8c4c3c", "50555c"]


def parse_color(v):
    if not v:
        return None
    v = v.strip().lower()
    if v.startswith("#") and len(v) in (4, 7):
        if len(v) == 4:
            v = "#" + "".join(ch * 2 for ch in v[1:])
        return v[1:]
    return NAMED_COLORS.get(v)


DEFAULT_LEVELS = {
    "house": 2, "detached": 2, "garage": 1, "garages": 1, "shed": 1, "kiosk": 1, "roof": 1, "hut": 1,
    "service": 1, "transformer_tower": 1, "commercial": 3, "retail": 2, "office": 5, "apartments": 5,
    "residential": 5, "university": 4, "school": 3, "kindergarten": 2, "hospital": 5, "hotel": 6,
    "church": 2, "cathedral": 3, "public": 3, "civic": 3, "industrial": 2, "warehouse": 2, "train_station": 2,
    "construction": 2, "ruins": 1, "chapel": 1, "mosque": 2,
}


def building_height(t):
    h = parse_m(t.get("height"))
    if h is None:
        lv = parse_m(t.get("building:levels"))
        if lv is None:
            lv = DEFAULT_LEVELS.get(t.get("building", t.get("building:part", "yes")), 3)
        h = lv * 3.3 + 1.0
        rl = parse_m(t.get("roof:levels"))
        if rl:
            h += rl * 2.5
    minh = parse_m(t.get("min_height"))
    if minh is None:
        ml = parse_m(t.get("building:min_level"))
        minh = ml * 3.3 if ml else 0.0
    return max(minh, 0.0), max(h, minh + 2.5)


def point_in_rings(p, rings):
    x, z = p
    inside = False
    for r in rings:
        for i in range(len(r)):
            x1, z1 = r[i]
            x2, z2 = r[(i + 1) % len(r)]
            if (z1 > z) != (z2 > z):
                xi = x1 + (z - z1) * (x2 - x1) / (z2 - z1)
                if xi > x:
                    inside = not inside
    return inside


def fmt(v, nd=1):
    s = f"{v:.{nd}f}"
    if "." in s:
        s = s.rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s


def main(merged):
    nodes, ways, rels = load(merged)
    south, west, north, east = BBOX

    # Начало координат — центр Спасской башни
    spass_outer = ways_to_rings([m[1] for m in rels["15958803"][0] if m[2] == "outer"], ways, nodes, lambda la, lo: (lo, la))
    lon0, lat0 = centroid(spass_outer[0])
    proj = setup_projection(lat0, lon0)
    x_min, z_max = proj(south, west)
    x_max, z_min = proj(north, east)
    print(f"origin {lat0:.6f},{lon0:.6f}; area {x_max - x_min:.0f} x {z_max - z_min:.0f} studs")

    def in_area(x, z, pad=0):
        return x_min - pad <= x <= x_max + pad and z_min - pad <= z <= z_max + pad

    # ---------------- Рельеф: вода и зелень
    nx = int((x_max - x_min) / CELL)
    nz = int((z_max - z_min) / CELL)
    zc = z_min + (np.arange(nz) + 0.5) * CELL
    water = np.zeros((nz, nx), dtype=bool)
    green = np.zeros((nz, nx), dtype=bool)
    forest = np.zeros((nz, nx), dtype=bool)

    def is_water(t):
        return t.get("natural") == "water" or t.get("waterway") == "riverbank"

    for pid, t, outer, inner in polygons(ways, rels, nodes, proj, is_water):
        water |= scan_fill(outer + inner, x_min, zc, nx, CELL)

    def is_green(t):
        return (t.get("leisure") in ("park", "garden", "pitch") or
                t.get("landuse") in ("grass", "recreation_ground", "meadow", "forest") or
                t.get("natural") in ("wood", "scrub", "grassland"))

    green_polys = polygons(ways, rels, nodes, proj, is_green)
    for pid, t, outer, inner in green_polys:
        g = scan_fill(outer + inner, x_min, zc, nx, CELL)
        if t.get("landuse") == "forest" or t.get("natural") == "wood":
            forest |= g
        else:
            green |= g
    green &= ~water
    forest &= ~water

    def is_parking(t):
        return t.get("amenity") == "parking" and t.get("parking") not in ("underground", "multi-storey", "rooftop")

    parking = np.zeros((nz, nx), dtype=bool)
    for pid, t, outer, inner in polygons(ways, rels, nodes, proj, is_parking):
        parking |= scan_fill(outer + inner, x_min, zc, nx, CELL)
    parking &= ~water
    green &= ~parking

    terrain = []
    for code, grid in (("w", water), ("g", green), ("f", forest), ("k", parking)):
        for r in range(nz):
            row = grid[r]
            c = 0
            while c < nx:
                if row[c]:
                    s = c
                    while c < nx and row[c]:
                        c += 1
                    terrain.append(f"{code},{r},{s},{c - s}")
                else:
                    c += 1
    print("terrain spans", len(terrain), "water cells", int(water.sum()))

    # ---------------- Достопримечательности
    lm_out = []
    lm_rings = []
    for name, (typ, oid) in LANDMARKS.items():
        if typ == "way":
            if oid not in ways:
                print("missing landmark", name)
                continue
            nds = ways[oid][0]
            rings = [[proj(nodes[n][0], nodes[n][1]) for n in nds[:-1] if n in nodes]]
            t = ways[oid][1]
        else:
            mem, t = rels[oid]
            rings = ways_to_rings([m[1] for m in mem if m[2] == "outer"], ways, nodes, proj)
        if not rings:
            print("no geometry", name)
            continue
        ring = max(rings, key=lambda r: abs(ring_area(r)))
        cx, cz = centroid(ring)
        ang = min_rect_angle(ring)
        c, s = math.cos(-ang), math.sin(-ang)
        xs = [(p[0] - cx) * c - (p[1] - cz) * s for p in ring]
        zs = [(p[0] - cx) * s + (p[1] - cz) * c for p in ring]
        w, d = max(xs) - min(xs), max(zs) - min(zs)
        h = parse_m(t.get("height")) or TOWER_HEIGHTS_M.get(name) or 20
        lm_out.append(f"{name},{fmt(cx)},{fmt(cz)},{fmt(w)},{fmt(d)},{fmt(-ang, 4)},{fmt(h * S)}")
        lm_rings.append(ring)

    def in_landmark(p):
        return any(point_in_rings(p, [r]) for r in lm_rings)

    # ---------------- Здания
    def is_building(t):
        return "building" in t and t.get("building") not in ("no", "construction") and t.get("historic") != "ruins"

    def is_part(t):
        return "building:part" in t and t.get("building:part") != "no"

    parts = polygons(ways, rels, nodes, proj, is_part)
    part_centroids = [centroid(o[0]) for _, _, o, _ in parts]
    blds = polygons(ways, rels, nodes, proj, is_building)

    boxes, wedges = [], []
    skipped = 0
    rng = random.Random(7)
    box_geom = []
    bld_records = []

    def emit(pid, t, outer, inner, is_part_poly):
        nonlocal skipped
        main_ring = max(outer, key=lambda r: abs(ring_area(r)))
        cx, cz = centroid(main_ring)
        if not in_area(cx, cz) or in_landmark((cx, cz)):
            skipped += 1
            return
        y0_m, h_m = building_height(t)
        y0, top = y0_m * S, h_m * S
        h = top - y0
        seed = int(pid[1]) % 9973
        wall = parse_color(t.get("building:colour")) or FACADE[seed % len(FACADE)]
        roof = parse_color(t.get("roof:colour")) or ROOFS[(seed // 7) % len(ROOFS)]
        if pid[1] in COLOR_OVERRIDES:
            wall, roof = COLOR_OVERRIDES[pid[1]]
        btype = t.get("building", t.get("building:part", "yes"))
        mat = "p"
        if t.get("building:material") in ("brick",) or wall in ("a8463a", "8a5a3c", "7a3030"):
            mat = "b"
        elif btype in ("garage", "garages", "shed", "industrial", "warehouse", "service", "roof"):
            mat = "c"
        elif h_m > 30 and not t.get("building:colour"):
            mat = "g"
            wall = ["8fa0b0", "a8b4bc", "7d90a4"][seed % 3]
        windows = btype not in ("garage", "garages", "shed", "roof", "service", "kiosk", "transformer_tower", "hut") and h > 12
        levels = parse_m(t.get("building:levels")) or 0
        if mat == "g" or (btype in ("office", "commercial", "retail", "hotel") and h_m >= 18):
            style = "m"
        elif levels >= 7 and btype in ("apartments", "residential", "yes", "dormitory"):
            style = "p"
        else:
            style = "c"
        record = {"tags": t, "boxes": [], "ring": main_ring, "y0": y0}
        bld_records.append(record)
        gable = (not is_part_poly and t.get("roof:shape") in ("gabled", "hipped", "pitched")) or (
            not is_part_poly and t.get("roof:shape") is None and h_m <= 14 and btype in ("yes", "house", "residential", "apartments", "commercial") and seed % 3 == 0)

        allpts = [p for r in outer for p in r]
        ang = min_rect_angle(allpts)
        c, s = math.cos(-ang), math.sin(-ang)

        def to_local(r):
            return [((p[0] - cx) * c - (p[1] - cz) * s, (p[0] - cx) * s + (p[1] - cz) * c) for p in r]

        lrings = [to_local(r) for r in outer + inner]
        lx = [p[0] for r in lrings[: len(outer)] for p in r]
        lz = [p[1] for r in lrings[: len(outer)] for p in r]
        bw, bd = max(lx) - min(lx), max(lz) - min(lz)
        if bw < 2 or bd < 2:
            return
        g = 3.0 if max(bw, bd) < 300 else 6.0
        gx = max(1, int(math.ceil(bw / g)))
        gz = max(1, int(math.ceil(bd / g)))
        zcs = min(lz) + (np.arange(gz) + 0.5) * g
        grid = scan_fill(lrings, min(lx), zcs, gx, g)
        rects = [r for r in greedy_rects(grid) if (r[2] - r[0]) * (r[3] - r[1]) >= 2 or grid.sum() < 6]
        fill = grid.sum() * g * g / max(abs(sum(ring_area(r) for r in outer)), 1)
        ca, sa = math.cos(ang), math.sin(ang)
        if 0 < len(rects) <= 14 and 0.6 < fill < 1.6:
            single = len(rects) == 1
            for (x0, z0, x1, z1) in rects:
                rx = min(lx) + (x0 + x1) / 2 * g
                rz = min(lz) + (z0 + z1) / 2 * g
                w = (x1 - x0) * g
                d = (z1 - z0) * g
                if single:  # одиночный блок — точный размер по контуру
                    rx, rz = (min(lx) + max(lx)) / 2, (min(lz) + max(lz)) / 2
                    w, d = bw, bd
                wx = cx + rx * ca - rz * sa
                wz = cz + rx * sa + rz * ca
                flags = (1 if windows else 0) | (2 if (gable and single and w * d < 9000) else 0)
                boxes.append(f"{fmt(wx)},{fmt(wz)},{fmt(w)},{fmt(d)},{fmt(-ang, 4)},{fmt(y0)},{fmt(h)},{wall},{roof},{mat},{flags},{style}")
                record["boxes"].append(len(box_geom))
                box_geom.append((wx, wz, w, d, -ang, y0, h))
        else:
            ring = simplify(main_ring, 5.0)
            for tri in ear_clip(ring):
                for (wx, wz, u, v, a_len, b_len) in tri_to_wedges(*tri):
                    wedges.append(f"{fmt(wx)},{fmt(wz)},{fmt(u[0], 4)},{fmt(u[1], 4)},{fmt(v[0], 4)},{fmt(v[1], 4)},{fmt(a_len)},{fmt(b_len)},{fmt(y0)},{fmt(h)},{wall}")

    for pid, t, outer, inner in parts:
        emit(pid, t, outer, inner, True)
    for pid, t, outer, inner in blds:
        main_ring = max(outer, key=lambda r: abs(ring_area(r)))
        if any(point_in_rings(pc, outer) for pc in part_centroids):
            continue  # здание описано частями building:part
        emit(pid, t, outer, inner, False)
    print("boxes", len(boxes), "wedges", len(wedges), "skipped", skipped)

    # ---------------- Дороги
    WIDTH = {"motorway": 18, "trunk": 16, "primary": 15, "secondary": 12, "tertiary": 10, "residential": 7,
             "unclassified": 7, "living_street": 6, "service": 4.5, "pedestrian": 12, "footway": 3, "path": 2,
             "cycleway": 2.5, "steps": 3, "track": 3, "primary_link": 8, "secondary_link": 7, "tertiary_link": 7}
    KIND = {"motorway": "a", "trunk": "a", "primary": "a", "secondary": "a", "tertiary": "a", "residential": "r",
            "unclassified": "r", "living_street": "r", "service": "s", "pedestrian": "p", "footway": "f",
            "path": "f", "cycleway": "f", "steps": "f", "track": "s", "primary_link": "a", "secondary_link": "a",
            "tertiary_link": "a"}
    roads = []
    for wid, (nds, t) in ways.items():
        hw = t.get("highway")
        if hw not in WIDTH or t.get("area") == "yes" or t.get("indoor") == "yes" or t.get("tunnel") in ("yes", "building_passage"):
            continue
        if hw == "footway" and t.get("footway") in ("sidewalk", "crossing", "traffic_island"):
            continue  # тротуары вдоль дорог дублируют проезжую часть
        pts = [proj(nodes[n][0], nodes[n][1]) for n in nds if n in nodes]
        if len(pts) < 2:
            continue
        if len(pts) > 2:
            pts = simplify(pts, 2.0 if KIND[hw] in ("f", "s") else 0.8, closed=False)
        w = parse_m(t.get("width")) or WIDTH[hw]
        w = min(max(w, 1.5), 30) * S
        bridge = 1 if t.get("bridge") in ("yes", "viaduct") else 0
        for i in range(len(pts) - 1):
            (x1, z1), (x2, z2) = pts[i], pts[i + 1]
            if not (in_area(x1, z1, 50) or in_area(x2, z2, 50)):
                continue
            if math.dist((x1, z1), (x2, z2)) < 0.3:
                continue
            roads.append(f"{fmt(x1)},{fmt(z1)},{fmt(x2)},{fmt(z2)},{fmt(w)},{KIND[hw]},{bridge}")
    print("road segments", len(roads))

    # ---------------- Стены Кремля и прочие стены
    walls = []
    for wid, (nds, t) in ways.items():
        b = t.get("barrier")
        if b not in ("city_wall", "wall") and t.get("historic") != "citywalls":
            continue
        kind = "k" if (b == "city_wall" or t.get("historic") == "citywalls") else "w"
        pts = [proj(nodes[n][0], nodes[n][1]) for n in nds if n in nodes]
        pts = simplify(pts, 0.6, closed=False) if len(pts) > 2 else pts
        for i in range(len(pts) - 1):
            (x1, z1), (x2, z2) = pts[i], pts[i + 1]
            if in_area(x1, z1) and math.dist((x1, z1), (x2, z2)) > 0.3:
                walls.append(f"{fmt(x1)},{fmt(z1)},{fmt(x2)},{fmt(z2)},{kind}")
    print("wall segments", len(walls))

    # ---------------- Деревья
    trees = []
    for nid, (la, lo, t) in nodes.items():
        if t.get("natural") == "tree":
            x, z = proj(la, lo)
            if in_area(x, z):
                trees.append((x, z))
    for wid, (nds, t) in ways.items():
        if t.get("natural") == "tree_row":
            pts = [proj(nodes[n][0], nodes[n][1]) for n in nds if n in nodes]
            for i in range(len(pts) - 1):
                (x1, z1), (x2, z2) = pts[i], pts[i + 1]
                n = int(math.dist((x1, z1), (x2, z2)) / 28)
                for k in range(n + 1):
                    trees.append((x1 + (x2 - x1) * k / max(n, 1), z1 + (z2 - z1) * k / max(n, 1)))
    # Немного деревьев в парках
    gz_, gx_ = np.nonzero(green)
    for idx in rng.sample(range(len(gz_)), min(450, len(gz_))):
        x = x_min + (gx_[idx] + rng.random()) * CELL
        z = z_min + (gz_[idx] + rng.random()) * CELL
        trees.append((x, z))
    tree_out = [f"{fmt(x)},{fmt(z)},{fmt(0.8 + rng.random() * 0.5, 2)}" for x, z in trees if in_area(x, z)]
    print("trees", len(tree_out))

    # ---------------- Инфраструктура для РП
    sys.path.insert(0, HERE)
    import infra
    infra_data = infra.build(nodes, ways, proj, in_area, box_geom, bld_records, WIDTH, KIND, simplify, parse_m, fmt)

    # ---------------- Точки для телепортов
    places = []
    lm = {r.split(",")[0]: [float(v) for v in r.split(",")[1:]] for r in lm_out}
    sx, sz = lm["Spasskaya"][0], lm["Spasskaya"][1]
    spawn = (sx + 40, sz + 175)
    places.append(("Спасская башня (спавн)", spawn[0], spawn[1]))
    for key, title in LANDMARK_TITLES.items():
        if key in lm and key != "Spasskaya":
            x, z, w, d = lm[key][:4]
            places.append((title, x, z + max(w, d) / 2 + 45))
    for title, street in POI_STREETS.items():
        pts = []
        for wid, (nds, t) in ways.items():
            if t.get("name") == street and "highway" in t:
                pts += [proj(nodes[n][0], nodes[n][1]) for n in nds if n in nodes]
        pts = [p for p in pts if in_area(*p)]
        if pts:
            pts.sort(key=lambda p: p[0] + p[1])
            mx, mz = pts[len(pts) // 2]
            places.append((title, mx, mz))
    print("places", [p[0] for p in places])

    # ---------------- Запись
    os.makedirs(OUT_DIR, exist_ok=True)
    header = "-- Сгенерировано tools/osm_to_luau.py из OpenStreetMap. Данные © OpenStreetMap contributors, ODbL.\n"

    def write(name, fields, chunk=6000):
        parts_lua = []
        for key, items in fields:
            chunks = [";".join(items[i:i + chunk]) for i in range(0, len(items), chunk)] or [""]
            body = ",\n".join(f"[==[{c}]==]" for c in chunks)
            parts_lua.append(f"M.{key} = {{\n{body}\n}}\n")
        path = os.path.join(OUT_DIR, name + ".lua")
        with open(path, "w", encoding="utf-8") as f:
            f.write(header + "local M = {}\n" + "".join(parts_lua) + "return M\n")
        print("wrote", path, os.path.getsize(path))

    meta = {
        "xMin": x_min, "zMin": z_min, "cell": CELL, "nx": nx, "nz": nz,
        "lat0": lat0, "lon0": lon0,
    }
    with open(os.path.join(OUT_DIR, "Meta.lua"), "w", encoding="utf-8") as f:
        f.write(header + "return {\n" + "".join(
            f"\t{k} = {v!r},\n" if isinstance(v, str) else f"\t{k} = {v:.6f},\n" for k, v in meta.items()) + "}\n")
    shared = os.path.join(HERE, "..", "src", "ReplicatedStorage", "Shared")
    os.makedirs(shared, exist_ok=True)
    with open(os.path.join(shared, "Places.lua"), "w", encoding="utf-8") as f:
        f.write(header + "-- Точки для телепорта (координаты в стадах) и точка появления.\nreturn {\n")
        f.write(f"\tSpawn = Vector3.new({fmt(spawn[0])}, 4, {fmt(spawn[1])}),\n")
        f.write(f"\tSpasskaya = Vector3.new({fmt(sx)}, 0, {fmt(sz)}),\n\tList = {{\n")
        for title, x, z in places:
            f.write(f'\t\t{{ name = "{title}", position = Vector3.new({fmt(x)}, 6, {fmt(z)}) }},\n')
        f.write("\t},\n}\n")
    write("Buildings", [("Boxes", boxes), ("Wedges", wedges)])
    write("Roads", [("Segments", roads)])
    write("Terrain", [("Spans", terrain)])
    write("Misc", [("Walls", walls), ("Trees", tree_out), ("Landmarks", lm_out)])
    write("Infra", [(k, v) for k, v in infra_data.items() if k != "Navigator"])
    with open(os.path.join(shared, "Poi.lua"), "w", encoding="utf-8") as f:
        f.write(header + "-- Места для навигатора: категория, название, координаты.\nreturn {\n")
        for cat, name, x, z in infra_data["Navigator"]:
            safe = name.replace("\\", "").replace('"', "'")
            f.write(f'\t{{ "{cat}", "{safe}", {fmt(x)}, {fmt(z)} }},\n')
        f.write("}\n")


if __name__ == "__main__":
    main(sys.argv[1])
