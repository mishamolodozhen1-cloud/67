"""Процедурная геометрия манекена DUMMY COMBAT: тела вращения, суперэллипсоиды, кольца, метки, запись GLB.

Оси — как в Roblox: Y вверх, персонаж смотрит в −Z, правая рука в +X, единица — 1 stud.
Цвет задаётся не материалом, а UV: каждая вершина указывает в центр клетки палитры (одна текстура
на весь манекен), поэтому у модели одна текстура и её легко заменить (другой цвет — другая палитра).
"""
import io
import json
import math
import struct

import numpy as np

# Палитра: клетка 64×64 в текстуре 256×128 (4 столбца × 2 строки)
SWATCH = {
    "body": 0, "body_shade": 1, "joint": 2, "marker_black": 3,
    "marker_yellow": 4, "sole": 5, "eye": 6, "metal": 7,
}
PALETTE_COLORS = {
    "body": (201, 170, 98),          # охра: пластик краш-тест манекена
    "body_shade": (174, 144, 82),    # чуть темнее: накладные панели
    "joint": (40, 40, 44),           # резина шарниров
    "marker_black": (20, 20, 22),
    "marker_yellow": (236, 198, 54),
    "sole": (30, 30, 32),
    "eye": (58, 52, 44),
    "metal": (150, 150, 156),
}
COLS, ROWS, CELL = 4, 2, 64


def swatch_uv(name):
    i = SWATCH[name]
    c, r = i % COLS, i // COLS
    return ((c + 0.5) / COLS, (r + 0.5) / ROWS)


def palette_png(colors=None):
    from PIL import Image
    colors = colors or PALETTE_COLORS
    img = Image.new("RGB", (COLS * CELL, ROWS * CELL))
    px = img.load()
    for name, i in SWATCH.items():
        c, r = i % COLS, i // COLS
        for y in range(r * CELL, (r + 1) * CELL):
            for x in range(c * CELL, (c + 1) * CELL):
                px[x, y] = colors[name]
    buf = io.BytesIO()
    img.save(buf, "PNG")
    return buf.getvalue()


class Mesh:
    def __init__(self, pos=None, idx=None, color=None, nrm=None):
        self.pos = np.zeros((0, 3)) if pos is None else np.asarray(pos, float)
        self.idx = np.zeros((0, 3), int) if idx is None else np.asarray(idx, int)
        n = len(self.pos)
        self.uv = np.tile(swatch_uv(color or "body"), (n, 1)) if n else np.zeros((0, 2))
        self.nrm = nrm if nrm is not None else self._smooth_normals()

    def _smooth_normals(self):
        n = np.zeros_like(self.pos)
        if len(self.idx):
            a, b, c = (self.pos[self.idx[:, k]] for k in range(3))
            fn = np.cross(b - a, c - a)
            for k in range(3):
                np.add.at(n, self.idx[:, k], fn)
        ln = np.linalg.norm(n, axis=1, keepdims=True)
        ln[ln < 1e-12] = 1
        return n / ln

    def add(self, other):
        off = len(self.pos)
        self.pos = np.vstack([self.pos, other.pos])
        self.nrm = np.vstack([self.nrm, other.nrm])
        self.uv = np.vstack([self.uv, other.uv])
        self.idx = np.vstack([self.idx, other.idx + off])
        return self

    def transformed(self, rot=None, offset=(0, 0, 0)):
        R = np.eye(3) if rot is None else np.asarray(rot, float)
        m = Mesh()
        m.pos = self.pos @ R.T + np.asarray(offset, float)
        m.nrm = self.nrm @ R.T
        m.uv = self.uv.copy()
        m.idx = self.idx.copy()
        return m

    def bbox(self):
        return self.pos.min(0), self.pos.max(0)

    @property
    def tris(self):
        return len(self.idx)


def rot_x(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])


def rot_y(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])


def rot_z(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])


def _superellipse(theta, n):
    """Точка суперэллипса |x|^n + |z|^n = 1 (n = 2 — круг, больше — «квадратнее»)."""
    c, s = math.cos(theta), math.sin(theta)
    return (math.copysign(abs(c) ** (2 / n), c), math.copysign(abs(s) ** (2 / n), s))


def lathe(rings, seg=24, color="body", n=2.0, pole_bottom=None, pole_top=None, center=(0, 0, 0)):
    """Тело вращения вдоль Y. rings: [(y, rx, rz)] снизу вверх; сечение — суперэллипс степени n.
    pole_bottom / pole_top — высота точки, которой закрывается низ / верх (None — открыто)."""
    cx, cy, cz = center
    pos, idx = [], []
    for (y, rx, rz) in rings:
        for k in range(seg):
            sx, sz = _superellipse(2 * math.pi * k / seg, n)
            pos.append((cx + rx * sx, cy + y, cz + rz * sz))
    R = len(rings)
    for r in range(R - 1):
        for k in range(seg):
            a = r * seg + k
            b = r * seg + (k + 1) % seg
            c = (r + 1) * seg + k
            d = (r + 1) * seg + (k + 1) % seg
            idx += [(a, c, b), (b, c, d)]
    if pole_bottom is not None:
        p = len(pos)
        pos.append((cx, cy + pole_bottom, cz))
        for k in range(seg):
            idx.append((p, k, (k + 1) % seg))
    if pole_top is not None:
        p = len(pos)
        pos.append((cx, cy + pole_top, cz))
        base = (R - 1) * seg
        for k in range(seg):
            idx.append((p, base + (k + 1) % seg, base + k))
    return Mesh(pos, idx, color)


def capsule(y0, y1, r0, r1, seg=24, color="body", aspect=1.0, n=2.0, bulge=0.0, bulge_at=0.5, center=(0, 0, 0), dome=0.7):
    """Скруглённый усечённый конус от y0 (низ) до y1 (верх), радиусы r0 / r1, сечение r × r·aspect.
    dome — высота куполов на концах в долях радиуса (1 — полусфера); bulge — утолщение около bulge_at."""
    yb, yt = y0 + r0 * dome, y1 - r1 * dome
    prof = []
    for i in range(1, 7):  # нижний купол: от полюса к экватору
        a = -math.pi / 2 + (math.pi / 2) * i / 6
        prof.append((yb + r0 * dome * math.sin(a), r0 * math.cos(a)))
    for i in range(1, 10):  # стенка
        u = i / 10
        r = (r0 + (r1 - r0) * u) * (1 + bulge * math.exp(-((u - bulge_at) / 0.28) ** 2))
        prof.append((yb + (yt - yb) * u, r))
    for i in range(0, 6):  # верхний купол: от экватора к полюсу
        a = (math.pi / 2) * i / 6
        prof.append((yt + r1 * dome * math.sin(a), r1 * math.cos(a)))
    rings = [(y, r, r * aspect) for (y, r) in prof]
    return lathe(rings, seg, color, n, pole_bottom=y0, pole_top=y1, center=center)


def superellipsoid(center, radii, e=1.0, seg_u=28, seg_v=18, color="body"):
    """Суперэллипсоид: e = 1 — эллипсоид, e < 1 — скруглённый «кирпич»."""
    cx, cy, cz = center
    ax, ay, az = radii
    pos, idx = [], []

    def sgnpow(v, p):
        return math.copysign(abs(v) ** p, v)

    for j in range(seg_v + 1):
        v = -math.pi / 2 + math.pi * j / seg_v
        for i in range(seg_u):
            u = -math.pi + 2 * math.pi * i / seg_u
            x = ax * sgnpow(math.cos(v), e) * sgnpow(math.cos(u), e)
            y = ay * sgnpow(math.sin(v), e)
            z = az * sgnpow(math.cos(v), e) * sgnpow(math.sin(u), e)
            pos.append((cx + x, cy + y, cz + z))
    for j in range(seg_v):
        for i in range(seg_u):
            a = j * seg_u + i
            b = j * seg_u + (i + 1) % seg_u
            c = (j + 1) * seg_u + i
            d = (j + 1) * seg_u + (i + 1) % seg_u
            idx += [(a, b, c), (b, d, c)]
    m = Mesh(pos, idx, color)
    return m


def torus(center, major, minor, seg=28, seg_minor=10, color="joint", aspect=1.0):
    """Кольцо вокруг оси Y (шарнир, пояс). aspect — сплюснутость по Z (эллиптическое кольцо)."""
    cx, cy, cz = center
    pos, idx = [], []
    for i in range(seg):
        a = 2 * math.pi * i / seg
        ca, sa = math.cos(a), math.sin(a)
        for j in range(seg_minor):
            b = 2 * math.pi * j / seg_minor
            r = major + minor * math.cos(b)
            pos.append((cx + r * ca, cy + minor * math.sin(b), cz + r * sa * aspect))
    for i in range(seg):
        for j in range(seg_minor):
            a = i * seg_minor + j
            b = ((i + 1) % seg) * seg_minor + j
            c = i * seg_minor + (j + 1) % seg_minor
            d = ((i + 1) % seg) * seg_minor + (j + 1) % seg_minor
            idx += [(a, c, b), (b, c, d)]
    return Mesh(pos, idx, color)


def marker(center, normal, radius, thickness=0.03, seg=32):
    """Метка краш-теста: диск из четырёх секторов чёрный/жёлтый, лежит на поверхности (normal — наружу)."""
    nrm = np.asarray(normal, float)
    nrm /= np.linalg.norm(nrm)
    up = np.array([0, 1, 0]) if abs(nrm[1]) < 0.9 else np.array([1, 0, 0])
    t1 = np.cross(up, nrm)
    t1 /= np.linalg.norm(t1)
    t2 = np.cross(nrm, t1)
    c = np.asarray(center, float)
    out = Mesh()
    per = seg // 4
    for q in range(4):
        color = "marker_black" if q % 2 == 0 else "marker_yellow"
        pos = [c + nrm * thickness]
        for k in range(per + 1):
            a = 2 * math.pi * (q * per + k) / seg + math.pi / 4
            pos.append(c + nrm * thickness + radius * (math.cos(a) * t1 + math.sin(a) * t2))
        idx = [(0, k + 1, k + 2) for k in range(per)]
        m = Mesh(pos, idx, color)
        # плоская метка: нормаль — наружу; обход согласуем с нормалью
        fn = np.cross(m.pos[1] - m.pos[0], m.pos[2] - m.pos[0])
        if np.dot(fn, nrm) < 0:
            m.idx = m.idx[:, ::-1]
        m.nrm = np.tile(nrm, (len(m.pos), 1))
        out.add(m)
    # бортик метки (тонкое тёмное кольцо по краю)
    rim_pos, rim_idx = [], []
    for k in range(seg):
        a = 2 * math.pi * k / seg
        d = math.cos(a) * t1 + math.sin(a) * t2
        rim_pos.append(c + nrm * thickness * 1.2 + d * radius)
        rim_pos.append(c + nrm * thickness * 1.2 + d * radius * 1.12)
    for k in range(seg):
        a, b = 2 * k, 2 * k + 1
        c2, d2 = 2 * ((k + 1) % seg), 2 * ((k + 1) % seg) + 1
        rim_idx += [(a, b, c2), (b, d2, c2)]
    rim = Mesh(rim_pos, rim_idx, "marker_black")
    fn = np.cross(rim.pos[rim.idx[0][1]] - rim.pos[rim.idx[0][0]], rim.pos[rim.idx[0][2]] - rim.pos[rim.idx[0][0]])
    if np.dot(fn, nrm) < 0:
        rim.idx = rim.idx[:, ::-1]
    rim.nrm = np.tile(nrm, (len(rim.pos), 1))
    out.add(rim)
    return out


###############################################################################
# GLB: каждая часть тела — отдельный узел (Roblox делает из него MeshPart с тем же именем)
###############################################################################
def write_glb(parts, png_bytes, path):
    """parts: [(имя, Mesh)] в осях Roblox. Roblox при импорте разворачивает модель на 180° вокруг Y
    (x → −x, z → −z), поэтому в файл пишем уже развёрнутые координаты — после импорта они совпадут."""
    out = {"asset": {"version": "2.0", "generator": "dummycombat/tools/dummy"}, "scene": 0, "scenes": [{"nodes": []}],
           "nodes": [], "meshes": [], "accessors": [], "bufferViews": [], "buffers": [],
           "materials": [{"name": "DummyPalette", "pbrMetallicRoughness": {"baseColorTexture": {"index": 0}, "metallicFactor": 0.0, "roughnessFactor": 0.55}, "alphaMode": "OPAQUE"}],
           "textures": [{"source": 0, "sampler": 0}], "images": [], "samplers": [{"magFilter": 9728, "minFilter": 9728}]}
    blob = bytearray()

    def view(data, target=None):
        while len(blob) % 4:
            blob.append(0)
        bv = {"buffer": 0, "byteOffset": len(blob), "byteLength": len(data)}
        if target:
            bv["target"] = target
        blob.extend(data)
        out["bufferViews"].append(bv)
        return len(out["bufferViews"]) - 1

    def acc(arr, ctype, typ, target, minmax=False):
        v = view(arr.tobytes(), target)
        a = {"bufferView": v, "componentType": ctype, "count": len(arr), "type": typ}
        if minmax:
            a["min"] = arr.min(0).tolist()
            a["max"] = arr.max(0).tolist()
        out["accessors"].append(a)
        return len(out["accessors"]) - 1

    out["images"].append({"bufferView": view(png_bytes), "mimeType": "image/png"})
    flip = np.array([-1.0, 1.0, -1.0])
    for name, m in parts:
        pos = (m.pos * flip).astype(np.float32)
        nrm = (m.nrm * flip).astype(np.float32)
        uv = m.uv.astype(np.float32)
        idx = m.idx.astype(np.uint32).reshape(-1)
        prim = {"attributes": {"POSITION": acc(pos, 5126, "VEC3", 34962, True), "NORMAL": acc(nrm, 5126, "VEC3", 34962),
                               "TEXCOORD_0": acc(uv, 5126, "VEC2", 34962)},
                "indices": acc(idx, 5125, "SCALAR", 34963), "material": 0}
        out["meshes"].append({"name": name, "primitives": [prim]})
        out["nodes"].append({"name": name, "mesh": len(out["meshes"]) - 1})
        out["scenes"][0]["nodes"].append(len(out["nodes"]) - 1)
    while len(blob) % 4:
        blob.append(0)
    out["buffers"] = [{"byteLength": len(blob)}]
    js = json.dumps(out, separators=(",", ":")).encode()
    while len(js) % 4:
        js += b" "
    glb = struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(blob)) + struct.pack("<I4s", len(js), b"JSON") + js + struct.pack("<I4s", len(blob), b"BIN\x00") + bytes(blob)
    with open(path, "wb") as f:
        f.write(glb)
    return len(glb)
