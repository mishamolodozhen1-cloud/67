"""prep_car.py in.glb out.glb — машина для командной кат-сцены (v15): «[FREE] VAZ 2107», Mcflower's Creations, CC BY 4.0.

Что делает:
  • сливает ~130 мешей в несколько деталей по группам и материалам:
      Body_<мат>, DoorFL_<мат>, DoorFR_<мат>, DoorRL_<мат>, DoorRR_<мат>, Wheel_FL/FR/RL/RR, Steer, Hood
    (двери, колёса и руль — отдельные детали: в игре они двигаются);
  • сиденья-кубы из модели выбрасывает (в них проваливались бы сидящие игроки) — сиденья строит игра;
  • треугольники удваиваются обратной стороной (Roblox рисует меши односторонними, а стёкла и
    часть панелей в модели — плоскости);
  • все материалы — OPAQUE (у Roblox прозрачность из файла превращается в режим Overlay); стекло игра
    делает сама по имени детали «*_Glass»;
  • мелкие пиксельные текстуры увеличиваются без сглаживания (иначе в игре они размываются);
  • бежевая краска кузова перекрашивается в выцветший серо-белый (ночью под фонарями читается лучше).

Оси файла: перёд машины −Z, водитель (левый руль) −X, верх +Y. Roblox при импорте разворачивает модель
на 180° вокруг вертикали: в игре перёд +Z, водитель +X.
"""
import sys, os, io, json, struct
_here = os.path.dirname(os.path.abspath(__file__))
sys.path = [p for p in sys.path if os.path.abspath(p or '.') != _here]  # рядом лежит inspect.py — он заслоняет модуль stdlib
sys.path.append(_here)
import numpy as np
from PIL import Image
from glbread import load, accessor, image_bytes, world_meshes

src, dst = sys.argv[1], sys.argv[2]
j, binc = load(src)
parent = {}
for i, n in enumerate(j['nodes']):
    for c in n.get('children', []):
        parent[c] = i
GROUPS = [('door1', 'DoorFL'), ('door2', 'DoorRL'), ('door3', 'DoorFR'), ('door4', 'DoorRR'),
          ('wheel3', 'Wheel_FL'), ('wheel4', 'Wheel_FR'), ('wheel1', 'Wheel_RL'), ('wheel2', 'Wheel_RR'),
          ('bone3_', 'Steer'), ('kapot', 'Hood'), ('bone8', None)]
MAT = {0: 'Lamp', 1: 'Paint', 2: 'Chrome', 3: 'Glass', 4: 'Trim'}
WHOLE = ('Wheel_', 'Steer', 'Hood')  # эти группы — одной деталью, без деления по материалам


def group_of(n):
    a = n
    while a in parent:
        nm = j['nodes'][a].get('name', '')
        for k, g in GROUPS:
            if nm.startswith(k):
                return g
        a = parent[a]
    return 'Body'


buckets = {}  # имя детали -> {mat: [pos, nrm, uv, idx]}
for n, mi, W in world_meshes(j):
    g = group_of(n)
    if g is None:
        continue
    N = np.linalg.inv(W[:3, :3]).T
    for p in j['meshes'][mi]['primitives']:
        mat = p.get('material', 1)
        name = g if g.startswith(WHOLE) else f"{g}_{MAT[mat]}"
        b = buckets.setdefault(name, {}).setdefault(mat, [[], [], [], [], 0])
        pos = accessor(j, binc, p['attributes']['POSITION'])
        pos = (np.c_[pos, np.ones(len(pos))] @ W.T)[:, :3]
        nrm = accessor(j, binc, p['attributes']['NORMAL']) @ N.T
        nrm /= np.maximum(np.linalg.norm(nrm, axis=1, keepdims=True), 1e-9)
        uv = accessor(j, binc, p['attributes']['TEXCOORD_0'])
        idx = accessor(j, binc, p['indices']).astype(np.int64).reshape(-1, 3)
        b[0].append(pos); b[1].append(nrm); b[2].append(uv); b[3].append(idx + b[4]); b[4] += len(pos)

# текстуры: увеличить без сглаживания, перекрасить кузов
images = []
for i in range(len(j['images'])):
    im = Image.open(io.BytesIO(image_bytes(j, binc, i))).convert('RGBA')
    if i == 2:
        a = np.asarray(im).astype(np.float64)
        r, g_, bl = a[..., 0], a[..., 1], a[..., 2]
        paint = (r - bl > 25) & (r > 90) & (r > g_)
        k = (r / 188.0)[..., None]
        target = np.array([150, 156, 158], np.float64)
        a[..., :3] = np.where(paint[..., None], np.clip(target * k, 0, 255), a[..., :3])
        im = Image.fromarray(a.astype(np.uint8), 'RGBA')
    if max(im.size) < 512:
        f = 512 // max(im.size)
        im = im.resize((im.size[0] * f, im.size[1] * f), Image.NEAREST)
    im = im.convert('RGB')
    buf = io.BytesIO()
    im.save(buf, 'PNG', optimize=True)
    images.append(buf.getvalue())

out = {'asset': {'version': '2.0', 'generator': 'prep_car.py'}, 'scene': 0, 'scenes': [{'nodes': []}], 'nodes': [], 'meshes': [],
       'accessors': [], 'bufferViews': [], 'buffers': [], 'materials': [], 'textures': [], 'images': [], 'samplers': [{'magFilter': 9728, 'minFilter': 9728}]}
blob = bytearray()


def view(data, target=None):
    while len(blob) % 4:
        blob.append(0)
    bv = {'buffer': 0, 'byteOffset': len(blob), 'byteLength': len(data)}
    if target:
        bv['target'] = target
    blob.extend(data)
    out['bufferViews'].append(bv)
    return len(out['bufferViews']) - 1


def acc(arr, ctype, typ, target, minmax=False):
    v = view(arr.tobytes(), target)
    a = {'bufferView': v, 'componentType': ctype, 'count': len(arr), 'type': typ}
    if minmax:
        a['min'] = arr.min(0).tolist()
        a['max'] = arr.max(0).tolist()
    out['accessors'].append(a)
    return len(out['accessors']) - 1


tex_of_mat = {}
for mi, m in enumerate(j['materials']):
    t = m['pbrMetallicRoughness']['baseColorTexture']['index']
    src_img = j['textures'][t]['source']
    out['images'].append({'bufferView': view(images[src_img]), 'mimeType': 'image/png', 'name': MAT[mi]})
    out['textures'].append({'source': len(out['images']) - 1, 'sampler': 0})
    pbr = {'baseColorTexture': {'index': len(out['textures']) - 1},
           'metallicFactor': 0.0, 'roughnessFactor': {0: 0.4, 1: 0.55, 2: 0.25, 3: 0.1, 4: 0.7}[mi]}
    out['materials'].append({'name': MAT[mi], 'pbrMetallicRoughness': pbr, 'alphaMode': 'OPAQUE', 'doubleSided': False})

summary = {}
for name in sorted(buckets):
    prims = []
    tris = 0
    for mat, (P, Nn, U, I, _) in sorted(buckets[name].items()):
        pos = np.concatenate(P).astype(np.float32)
        nrm = np.concatenate(Nn).astype(np.float32)
        uv = np.concatenate(U).astype(np.float32)
        idx = np.concatenate(I)
        # обратная сторона: те же точки с обратной нормалью, обход наоборот
        n0 = len(pos)
        pos = np.r_[pos, pos]
        nrm = np.r_[nrm, -nrm]
        uv = np.r_[uv, uv]
        idx = np.r_[idx, idx[:, ::-1] + n0].astype(np.uint32)
        tris += len(idx)
        prims.append({'attributes': {'POSITION': acc(pos, 5126, 'VEC3', 34962, True), 'NORMAL': acc(nrm, 5126, 'VEC3', 34962),
                                     'TEXCOORD_0': acc(uv, 5126, 'VEC2', 34962)},
                      'indices': acc(idx.reshape(-1), 5125, 'SCALAR', 34963), 'material': mat})
        lo, hi = pos.min(0), pos.max(0)
        s = summary.setdefault(name, [lo, hi])
        s[0] = np.minimum(s[0], lo)
        s[1] = np.maximum(s[1], hi)
    out['meshes'].append({'name': name, 'primitives': prims})
    out['nodes'].append({'name': name, 'mesh': len(out['meshes']) - 1})
    out['scenes'][0]['nodes'].append(len(out['nodes']) - 1)
    print(f"{name:16s} tris {tris:5d}  min {np.round(summary[name][0], 3).tolist()}  max {np.round(summary[name][1], 3).tolist()}")

while len(blob) % 4:
    blob.append(0)
out['buffers'] = [{'byteLength': len(blob)}]
js = json.dumps(out, separators=(',', ':')).encode()
while len(js) % 4:
    js += b' '
glb = struct.pack('<III', 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(blob)) + struct.pack('<I4s', len(js), b'JSON') + js + struct.pack('<I4s', len(blob), b'BIN\x00') + bytes(blob)
open(dst, 'wb').write(glb)
print('->', dst, len(glb) // 1024, 'KB')
