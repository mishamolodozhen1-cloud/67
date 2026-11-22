#!/usr/bin/env python3
"""Готовит скелетную (rigged) модель glTF к загрузке в Roblox и вынимает из неё анимации.

  prep_rig.py in.glb out_dir --height 8.6 --tris 17000 [--anims idle,walk,roar] [--fps 20]

Что делает:
  • сворачивает всё, что выше корневой кости (повороты и масштабы Sketchfab/FBX), в одну систему:
    модель стоит на земле (низ = 0), по центру, смотрит вперёд (+Z файла), высота = --height;
  • у костей не остаётся масштаба — только поворот и смещение (Roblox так и ждёт);
  • выбрасывает концевые кости без веса (*_end) и чистит имена (pelvis_01 -> pelvis);
  • уменьшает число треугольников до --tris (лимит Roblox на одну сетку — 20 000), веса и UV сохраняются;
  • текстуры: цвет — маленькая однотонная картинка (средний цвет исходной), нормали — 1024×1024;
  • анимации пересчитывает в новую систему и пишет в anims.json: для каждой кости и кадра —
    локальное смещение и поворот (кватернион x, y, z, w), а также позу покоя.

На выходе: out_dir/model.glb (без анимаций — для загрузки как Model), out_dir/anims.json.
"""
import argparse
import io
import json
import os
import re
import struct

import numpy as np
from PIL import Image

CT = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
NC = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


def load_glb(path):
    f = open(path, "rb").read()
    clen = struct.unpack("<I", f[12:16])[0]
    j = json.loads(f[20:20 + clen])
    binoff = 20 + clen + 8
    return f, j, binoff


def accessor(f, j, binoff, i):
    a = j["accessors"][i]
    bv = j["bufferViews"][a["bufferView"]]
    n = NC[a["type"]]
    dt = np.dtype(CT[a["componentType"]])
    off = binoff + bv.get("byteOffset", 0) + a.get("byteOffset", 0)
    stride = bv.get("byteStride") or n * dt.itemsize
    if stride == n * dt.itemsize:
        arr = np.frombuffer(f, dtype=dt, count=a["count"] * n, offset=off).reshape(a["count"], n)
    else:
        rows = [np.frombuffer(f, dtype=dt, count=n, offset=off + k * stride) for k in range(a["count"])]
        arr = np.array(rows)
    if a.get("normalized"):
        arr = arr.astype(np.float64) / np.iinfo(dt).max
    return arr


def quat_to_mat(q):
    x, y, z, w = q
    return np.array([
        [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
        [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
        [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)],
    ])


def mat_to_quat(m):
    t = np.trace(m)
    if t > 0:
        s = np.sqrt(t + 1.0) * 2
        w = 0.25 * s
        x = (m[2, 1] - m[1, 2]) / s
        y = (m[0, 2] - m[2, 0]) / s
        z = (m[1, 0] - m[0, 1]) / s
    elif m[0, 0] > m[1, 1] and m[0, 0] > m[2, 2]:
        s = np.sqrt(1.0 + m[0, 0] - m[1, 1] - m[2, 2]) * 2
        w = (m[2, 1] - m[1, 2]) / s
        x = 0.25 * s
        y = (m[0, 1] + m[1, 0]) / s
        z = (m[0, 2] + m[2, 0]) / s
    elif m[1, 1] > m[2, 2]:
        s = np.sqrt(1.0 + m[1, 1] - m[0, 0] - m[2, 2]) * 2
        w = (m[0, 2] - m[2, 0]) / s
        x = (m[0, 1] + m[1, 0]) / s
        y = 0.25 * s
        z = (m[1, 2] + m[2, 1]) / s
    else:
        s = np.sqrt(1.0 + m[2, 2] - m[0, 0] - m[1, 1]) * 2
        w = (m[1, 0] - m[0, 1]) / s
        x = (m[0, 2] + m[2, 0]) / s
        y = (m[1, 2] + m[2, 1]) / s
        z = 0.25 * s
    q = np.array([x, y, z, w])
    q /= np.linalg.norm(q)
    if q[3] < 0:
        q = -q
    return q


def slerp(a, b, t):
    d = float(np.dot(a, b))
    if d < 0:
        b, d = -b, -d
    if d > 0.9995:
        r = a + (b - a) * t
        return r / np.linalg.norm(r)
    th = np.arccos(d)
    return (np.sin((1 - t) * th) * a + np.sin(t * th) * b) / np.sin(th)


def trs(t=None, r=None, s=None):
    m = np.eye(4)
    rot = quat_to_mat(r) if r is not None else np.eye(3)
    sc = np.diag(s) if s is not None else np.eye(3)
    m[:3, :3] = rot @ sc
    if t is not None:
        m[:3, 3] = t
    return m


def node_local(n):
    if "matrix" in n:
        return np.array(n["matrix"], dtype=np.float64).reshape(4, 4).T
    return trs(n.get("translation"), n.get("rotation"), n.get("scale"))


def rigid(m):
    """Убрать масштаб: ортонормировать поворот (масштаб у нас равномерный)."""
    r = m[:3, :3]
    u, _, vt = np.linalg.svd(r)
    rr = u @ vt
    if np.linalg.det(rr) < 0:
        raise SystemExit("отражение в матрице кости — не поддерживается")
    out = np.eye(4)
    out[:3, :3] = rr
    out[:3, 3] = m[:3, 3]
    return out


def clean_name(name):
    name = re.sub(r"_\d+$", "", name)
    return {"_rootJoint": "Root"}.get(name, name)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("out")
    ap.add_argument("--height", type=float, default=8.6)
    ap.add_argument("--tris", type=int, default=17000)
    ap.add_argument("--anims", default="")
    ap.add_argument("--fps", type=float, default=20)
    ap.add_argument("--forward", default="auto", help="auto | +z | -z | +x | -x — куда смотрит модель в файле")
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    f, j, binoff = load_glb(a.src)
    acc = lambda i: accessor(f, j, binoff, i)  # noqa: E731
    nodes = j["nodes"]
    parent = {}
    for i, n in enumerate(nodes):
        for c in n.get("children", []):
            parent[c] = i

    def world_of(local_fn):
        cache = {}

        def w(i):
            if i not in cache:
                m = local_fn(i)
                cache[i] = (w(parent[i]) @ m) if i in parent else m
            return cache[i]
        return w

    rest_local = [node_local(n) for n in nodes]
    W = world_of(lambda i: rest_local[i])

    skin = j["skins"][0]
    joints = skin["joints"]
    ibm = acc(skin["inverseBindMatrices"]).reshape(-1, 4, 4).transpose(0, 2, 1)
    mesh_node = next(i for i, n in enumerate(nodes) if "mesh" in n and "skin" in n)
    prim = j["meshes"][nodes[mesh_node]["mesh"]]["primitives"][0]
    P = acc(prim["attributes"]["POSITION"]).astype(np.float64)
    N = acc(prim["attributes"]["NORMAL"]).astype(np.float64)
    UV = acc(prim["attributes"]["TEXCOORD_0"]).astype(np.float64)
    JO = acc(prim["attributes"]["JOINTS_0"]).astype(np.int64)
    WE = acc(prim["attributes"]["WEIGHTS_0"]).astype(np.float64)
    WE = WE / WE.sum(1, keepdims=True)
    F = acc(prim["indices"]).reshape(-1, 3).astype(np.int64)

    # Поза покоя: вершины, как их видно в сцене (скиннинг с матрицами покоя)
    skinmats = np.array([W(jn) @ ibm[k] for k, jn in enumerate(joints)])
    Ph = np.c_[P, np.ones(len(P))]
    Pw = np.zeros((len(P), 3))
    Nw = np.zeros((len(P), 3))
    for c in range(4):
        m = skinmats[JO[:, c]]
        Pw += WE[:, c:c + 1] * np.einsum("nij,nj->ni", m, Ph)[:, :3]
        Nw += WE[:, c:c + 1] * np.einsum("nij,nj->ni", m[:, :3, :3], N)
    Nw /= np.linalg.norm(Nw, axis=1, keepdims=True) + 1e-12

    # Нормализация: верх — Y, рост --height, стоит на нуле, по центру, лицом в +Z
    lo, hi = Pw.min(0), Pw.max(0)
    up = int(np.argmax(hi - lo)) if False else 1
    height = hi[up] - lo[up]
    k = a.height / height
    name_of = {jn: nodes[jn].get("name", str(jn)) for jn in joints}
    by_name = {clean_name(v): kk for kk, v in name_of.items()}
    T = np.eye(4)
    T[:3, :3] *= k
    center = np.array([(lo[0] + hi[0]) / 2, lo[1], (lo[2] + hi[2]) / 2])
    # куда смотрит: носки стоп (ball) впереди пяток (foot)
    fwd = None
    if "ball_l" in by_name and "foot_l" in by_name:
        d = W(by_name["ball_l"])[:3, 3] - W(by_name["foot_l"])[:3, 3] + W(by_name["ball_r"])[:3, 3] - W(by_name["foot_r"])[:3, 3]
        d[1] = 0
        fwd = d / (np.linalg.norm(d) + 1e-9)
    if a.forward != "auto":
        fwd = {"+z": [0, 0, 1], "-z": [0, 0, -1], "+x": [1, 0, 0], "-x": [-1, 0, 0]}[a.forward]
        fwd = np.array(fwd, dtype=float)
    ang = np.arctan2(fwd[0], fwd[2]) if fwd is not None else 0.0  # поворот вокруг Y, чтобы fwd -> +Z
    c_, s_ = np.cos(-ang), np.sin(-ang)
    Ry = np.eye(4)
    Ry[:3, :3] = np.array([[c_, 0, s_], [0, 1, 0], [-s_, 0, c_]])
    Tc = np.eye(4)
    Tc[:3, 3] = -center
    TF = Ry @ T @ Tc
    print("рост в файле %.3f -> %.2f, масштаб %.5f, взгляд %s, поворот %.1f°" % (height, a.height, k, None if fwd is None else np.round(fwd, 2), np.degrees(ang)))

    Pn = (TF @ np.c_[Pw, np.ones(len(Pw))].T).T[:, :3]
    Nn = (Ry[:3, :3] @ Nw.T).T

    # Кости: оставляем те, у которых есть вес, их предков-костей и корень
    jset = set(joints)
    used = set(int(x) for x in np.unique(JO[WE > 1e-4]))
    keep = set()
    for kk in used:
        n = joints[kk]
        while n in jset:
            keep.add(n)
            n = parent.get(n)
    keep.add(skin.get("skeleton", joints[0]) if skin.get("skeleton") in jset else joints[0])
    order = [jn for jn in joints if jn in keep]
    new_index = {jn: i for i, jn in enumerate(order)}

    def kept_parent(jn):
        p = parent.get(jn)
        while p is not None and p not in keep:
            p = parent.get(p)
        return p

    remap = np.array([new_index.get(jn, -1) for jn in joints])
    JO2 = remap[JO]
    WE2 = np.where(JO2 >= 0, WE, 0)
    JO2 = np.where(JO2 >= 0, JO2, 0)
    WE2 = WE2 / WE2.sum(1, keepdims=True)

    def new_world(wfn):
        return {jn: rigid(TF @ wfn(jn)) for jn in order}

    Jw = new_world(W)

    def locals_from(Jw_):
        out = {}
        for jn in order:
            p = kept_parent(jn)
            pw = Jw_[p] if p is not None else np.eye(4)
            out[jn] = np.linalg.inv(pw) @ Jw_[jn]
        return out

    L0 = locals_from(Jw)
    ibm2 = np.array([np.linalg.inv(Jw[jn]) for jn in order])

    # Меньше треугольников (атрибуты берём у ближайшей исходной вершины)
    if len(F) > a.tris:
        import fast_simplification as fs
        red = 1 - a.tris / len(F)
        pts, faces, coll = fs.simplify(Pn.astype(np.float32), F.astype(np.int32), target_reduction=red, return_collapses=True)
        pts2, faces2, mapping = fs.replay_simplification(Pn.astype(np.float32), F.astype(np.int32), coll)
        # mapping: старая вершина -> новая; для каждой новой берём первую исходную
        rep = np.full(len(pts2), -1)
        for old, nw in enumerate(mapping):
            if 0 <= nw < len(rep) and rep[nw] < 0:
                rep[nw] = old
        Pn2 = pts2.astype(np.float64)
        Nn, UV, JO2, WE2 = Nn[rep], UV[rep], JO2[rep], WE2[rep]
        Pn, F = Pn2, faces2.reshape(-1, 3).astype(np.int64)
        print("треугольников: %d -> %d, вершин: %d" % (len(acc(prim["indices"])) // 3, len(F), len(Pn)))

    # Текстуры
    mat = j["materials"][prim.get("material", 0)]
    pbr = mat.get("pbrMetallicRoughness", {})

    def image_of(tex_index):
        im = j["images"][j["textures"][tex_index]["source"]]
        bv = j["bufferViews"][im["bufferView"]]
        data = f[binoff + bv.get("byteOffset", 0): binoff + bv.get("byteOffset", 0) + bv["byteLength"]]
        return Image.open(io.BytesIO(data))

    base_rgb = (30, 30, 34)
    if "baseColorTexture" in pbr:
        arr = np.asarray(image_of(pbr["baseColorTexture"]["index"]).convert("RGB"), dtype=np.float64)
        base_rgb = tuple(int(x) for x in arr.reshape(-1, 3).mean(0))
    color_png = io.BytesIO()
    Image.new("RGB", (8, 8), base_rgb).save(color_png, "PNG")
    normal_png = None
    if "normalTexture" in mat:
        img = image_of(mat["normalTexture"]["index"]).convert("RGB")
        img = img.resize((min(1024, img.width), min(1024, img.height)), Image.LANCZOS)
        normal_png = io.BytesIO()
        img.save(normal_png, "PNG", optimize=True)
    print("средний цвет", base_rgb)

    # Сборка нового GLB
    blobs = []

    def add_blob(b, align=4):
        off = sum(len(x) for x in blobs)
        pad = (-off) % align
        if pad:
            blobs.append(b"\0" * pad)
            off += pad
        blobs.append(b)
        return off

    gl = {"asset": {"version": "2.0", "generator": "nightshift prep_rig"}, "buffers": [], "bufferViews": [], "accessors": [],
          "nodes": [], "meshes": [], "skins": [], "materials": [], "images": [], "textures": [], "samplers": [{}], "scenes": [{"nodes": []}], "scene": 0}

    def add_acc(arr, ctype, atype, target=None, minmax=False):
        arr = np.ascontiguousarray(arr)
        off = add_blob(arr.tobytes())
        bv = {"buffer": 0, "byteOffset": off, "byteLength": arr.nbytes}
        if target:
            bv["target"] = target
        gl["bufferViews"].append(bv)
        acc_ = {"bufferView": len(gl["bufferViews"]) - 1, "componentType": ctype, "count": len(arr), "type": atype}
        if minmax:
            acc_["min"] = arr.min(0).tolist()
            acc_["max"] = arr.max(0).tolist()
        gl["accessors"].append(acc_)
        return len(gl["accessors"]) - 1

    def add_image(buf):
        off = add_blob(buf.getvalue())
        gl["bufferViews"].append({"buffer": 0, "byteOffset": off, "byteLength": len(buf.getvalue())})
        gl["images"].append({"bufferView": len(gl["bufferViews"]) - 1, "mimeType": "image/png"})
        gl["textures"].append({"sampler": 0, "source": len(gl["images"]) - 1})
        return len(gl["textures"]) - 1

    material = {"name": "Skin", "pbrMetallicRoughness": {"baseColorTexture": {"index": add_image(color_png)}, "metallicFactor": 0.0, "roughnessFactor": 0.55}}
    if normal_png:
        material["normalTexture"] = {"index": add_image(normal_png)}
    gl["materials"].append(material)

    # узлы костей
    node_of = {}
    for jn in order:
        loc = L0[jn]
        q = mat_to_quat(loc[:3, :3])
        node_of[jn] = len(gl["nodes"])
        gl["nodes"].append({"name": clean_name(name_of[jn]), "translation": loc[:3, 3].tolist(), "rotation": q.tolist()})
    for jn in order:
        p = kept_parent(jn)
        if p is not None:
            gl["nodes"][node_of[p]].setdefault("children", []).append(node_of[jn])
    roots = [node_of[jn] for jn in order if kept_parent(jn) is None]
    pos_i = add_acc(Pn.astype(np.float32), 5126, "VEC3", 34962, True)
    nor_i = add_acc(Nn.astype(np.float32), 5126, "VEC3", 34962)
    uv_i = add_acc(UV.astype(np.float32), 5126, "VEC2", 34962)
    jo_i = add_acc(JO2.astype(np.uint16), 5123, "VEC4", 34962)
    we_i = add_acc(WE2.astype(np.float32), 5126, "VEC4", 34962)
    ind_i = add_acc(F.reshape(-1).astype(np.uint32), 5125, "SCALAR", 34963)
    ibm_i = add_acc(ibm2.transpose(0, 2, 1).reshape(-1, 16).astype(np.float32), 5126, "MAT4")
    gl["meshes"].append({"name": "Body", "primitives": [{"attributes": {"POSITION": pos_i, "NORMAL": nor_i, "TEXCOORD_0": uv_i, "JOINTS_0": jo_i, "WEIGHTS_0": we_i}, "indices": ind_i, "material": 0}]})
    gl["skins"].append({"joints": [node_of[jn] for jn in order], "inverseBindMatrices": ibm_i, "skeleton": roots[0]})
    mesh_i = len(gl["nodes"])
    gl["nodes"].append({"name": "Body", "mesh": 0, "skin": 0})
    gl["scenes"][0]["nodes"] = roots + [mesh_i]

    binary = b"".join(blobs)
    binary += b"\0" * ((-len(binary)) % 4)
    gl["buffers"].append({"byteLength": len(binary)})
    js = json.dumps(gl, separators=(",", ":")).encode()
    js += b" " * ((-len(js)) % 4)
    glb = struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(binary)) + struct.pack("<II", len(js), 0x4E4F534A) + js + struct.pack("<II", len(binary), 0x004E4942) + binary
    open(os.path.join(a.out, "model.glb"), "wb").write(glb)
    print("model.glb: %.1f КБ, костей %d" % (len(glb) / 1024, len(order)))

    # Анимации
    wanted = [x for x in a.anims.split(",") if x]
    out = {"Fps": a.fps, "Bones": [clean_name(name_of[jn]) for jn in order],
           "Parents": [clean_name(name_of[kept_parent(jn)]) if kept_parent(jn) is not None else "" for jn in order],
           "Rest": {}, "Anims": {}}
    for jn in order:
        loc = L0[jn]
        out["Rest"][clean_name(name_of[jn])] = [round(float(x), 5) for x in list(loc[:3, 3]) + list(mat_to_quat(loc[:3, :3]))]
    for anim in j.get("animations", []):
        aname = anim["name"].split("|")[-1]
        if wanted and aname not in wanted:
            continue
        chans = {}
        tmax = 0.0
        for ch in anim["channels"]:
            smp = anim["samplers"][ch["sampler"]]
            tin = acc(smp["input"]).reshape(-1).astype(np.float64)
            vout = acc(smp["output"]).astype(np.float64)
            chans.setdefault(ch["target"]["node"], {})[ch["target"]["path"]] = (tin, vout)
            tmax = max(tmax, float(tin.max()))
        nfr = max(2, int(round(tmax * a.fps)) + 1)
        frames = []
        for fi in range(nfr):
            t = min(tmax, fi / a.fps)

            def sample(tin, vout, path):
                if len(tin) == 1 or t <= tin[0]:
                    return vout[0]
                if t >= tin[-1]:
                    return vout[-1]
                i = int(np.searchsorted(tin, t) - 1)
                u = (t - tin[i]) / (tin[i + 1] - tin[i])
                if path == "rotation":
                    return slerp(vout[i] / np.linalg.norm(vout[i]), vout[i + 1] / np.linalg.norm(vout[i + 1]), u)
                return vout[i] * (1 - u) + vout[i + 1] * u

            def local_at(i):
                n = nodes[i]
                if i not in chans or "matrix" in n:
                    return rest_local[i]
                c = chans[i]
                tt = sample(*c["translation"], "translation") if "translation" in c else n.get("translation")
                rr = sample(*c["rotation"], "rotation") if "rotation" in c else n.get("rotation")
                ss = sample(*c["scale"], "scale") if "scale" in c else n.get("scale")
                return trs(tt, rr, ss)

            Wt = world_of(local_at)
            Lt = locals_from(new_world(Wt))
            fr = {}
            for jn in order:
                loc = Lt[jn]
                fr[clean_name(name_of[jn])] = [round(float(x), 4) for x in list(loc[:3, 3]) + list(mat_to_quat(loc[:3, :3]))]
            frames.append(fr)
        out["Anims"][aname] = {"Length": round(tmax, 3), "Frames": frames}
        print("анимация %s: %.2f с, %d кадров" % (aname, tmax, nfr))
    json.dump(out, open(os.path.join(a.out, "anims.json"), "w"))


if __name__ == "__main__":
    main()
