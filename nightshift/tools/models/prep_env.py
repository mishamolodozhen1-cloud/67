"""prep_env.py in.glb out.glb [--max 1024] [--double] [--alpha-out DIR]
Готовит модель окружения к загрузке в Roblox:
  • текстуры не больше --max px;
  • --double: у материалов с прозрачностью (листва, хвоя — MASK/BLEND) треугольники удваиваются обратной стороной
    (Roblox при загрузке делает модели односторонними, и половина веток пропадала бы);
  • --alpha-out: текстуры таких материалов (с альфой) сохраняются отдельными PNG — их грузим как картинки и
    ставим в игре в MeshPart.TextureID (SurfaceAppearance из загрузки не умеет прозрачность — режим Overlay).
"""
import sys, json, struct, io, os
import numpy as np
from PIL import Image
args = sys.argv[1:]
src, dst = args[0], args[1]
maxpx = int(args[args.index('--max') + 1]) if '--max' in args else 1024
double = '--double' in args
alpha_out = args[args.index('--alpha-out') + 1] if '--alpha-out' in args else None
d = open(src, 'rb').read()
off = 12; chunks = []
while off < len(d):
    clen, ctype = struct.unpack('<I4s', d[off:off + 8]); chunks.append(d[off + 8:off + 8 + clen]); off += 8 + clen
j = json.loads(chunks[0]); binc = chunks[1] if len(chunks) > 1 else b''
CT = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
NC = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4}
def read_acc(i):
    a = j['accessors'][i]; bv = j['bufferViews'][a['bufferView']]
    n = NC[a['type']]; dt = CT[a['componentType']]; start = bv.get('byteOffset', 0) + a.get('byteOffset', 0)
    stride = bv.get('byteStride'); isz = np.dtype(dt).itemsize * n
    if stride and stride != isz:
        raw = np.frombuffer(binc, np.uint8, stride * a['count'], start).reshape(a['count'], stride)[:, :isz]
        return np.frombuffer(raw.tobytes(), dt).reshape(a['count'], n).copy(), a
    return np.frombuffer(binc, dt, a['count'] * n, start).reshape(a['count'], n).copy(), a
# пересобираем буфер: старые bufferViews (картинки — ужатые) + новые для удвоенной геометрии
new = bytearray()
def add_view(data, target=None):
    while len(new) % 4: new.append(0)
    bv = {'buffer': 0, 'byteOffset': len(new), 'byteLength': len(data)}
    if target: bv['target'] = target
    new.extend(data); j['bufferViews'].append(bv); return len(j['bufferViews']) - 1
img_views = {im['bufferView']: (idx, im) for idx, im in enumerate(j.get('images', [])) if 'bufferView' in im}
old_views = j['bufferViews']; j['bufferViews'] = []
alpha_mats = {i for i, m in enumerate(j.get('materials', [])) if m.get('alphaMode', 'OPAQUE') in ('MASK', 'BLEND') and 'baseColorTexture' in m.get('pbrMetallicRoughness', {})}
alpha_imgs = {}
for mi in alpha_mats:
    t = j['materials'][mi]['pbrMetallicRoughness']['baseColorTexture']['index']
    alpha_imgs[j['textures'][t]['source']] = j['materials'][mi].get('name', f'mat{mi}')
for i, bv in enumerate(old_views):
    s = bv.get('byteOffset', 0); data = binc[s:s + bv['byteLength']]
    if i in img_views:
        idx, im_meta = img_views[i]
        im = Image.open(io.BytesIO(data)); im.load()
        if max(im.size) > maxpx:
            k = maxpx / max(im.size); im = im.resize((max(1, int(im.size[0] * k)), max(1, int(im.size[1] * k))), Image.LANCZOS)
        has_alpha = im.mode in ('RGBA', 'LA') or (im.mode == 'P' and 'transparency' in im.info)
        if alpha_out and idx in alpha_imgs:
            os.makedirs(alpha_out, exist_ok=True)
            base = os.path.splitext(os.path.basename(dst))[0]
            im.convert('RGBA').save(os.path.join(alpha_out, f"{base}__{alpha_imgs[idx]}.png"))
        buf = io.BytesIO()
        if has_alpha:
            im.save(buf, 'PNG', optimize=True); im_meta['mimeType'] = 'image/png'
        else:
            im.convert('RGB').save(buf, 'JPEG', quality=88); im_meta['mimeType'] = 'image/jpeg'
        data = buf.getvalue()
    while len(new) % 4: new.append(0)
    nb = dict(bv); nb['byteOffset'] = len(new); nb['byteLength'] = len(data); nb['buffer'] = 0
    new.extend(data); j['bufferViews'].append(nb)
binc = bytes(binc)  # старый буфер нужен для чтения аксессоров
# восстановить старые смещения для чтения: читаем из исходного буфера по old_views
saved_views = j['bufferViews']; j['bufferViews'] = old_views
doubled = 0
if double:
    plans = []
    for mesh in j['meshes']:
        for p in mesh['primitives']:
            if p.get('material') in alpha_mats and 'indices' in p:
                attrs = {k: read_acc(v)[0] for k, v in p['attributes'].items() if k in ('POSITION', 'NORMAL', 'TEXCOORD_0', 'TEXCOORD_1', 'COLOR_0')}
                idx = read_acc(p['indices'])[0].reshape(-1).astype(np.uint32)
                plans.append((p, attrs, idx))
    j['bufferViews'] = saved_views
    for p, attrs, idx in plans:
        nV = len(attrs['POSITION'])
        for k, arr in attrs.items():
            arr2 = np.vstack([arr, -arr if k == 'NORMAL' else arr]).astype(np.float32 if arr.dtype.kind == 'f' else arr.dtype)
            if arr2.dtype != np.float32:
                arr2 = arr2.astype(np.float32)
            v = add_view(arr2.tobytes(), 34962)
            acc = {'bufferView': v, 'componentType': 5126, 'count': len(arr2), 'type': {1: 'SCALAR', 2: 'VEC2', 3: 'VEC3', 4: 'VEC4'}[arr2.shape[1]]}
            if k == 'POSITION':
                acc['min'] = arr2.min(0).tolist(); acc['max'] = arr2.max(0).tolist()
            j['accessors'].append(acc); p['attributes'][k] = len(j['accessors']) - 1
        for k in list(p['attributes']):
            if k not in attrs:
                del p['attributes'][k]  # касательные и прочее — не нужны
        tri = idx.reshape(-1, 3)
        idx2 = np.vstack([tri, tri[:, ::-1] + nV]).reshape(-1).astype(np.uint32)
        v = add_view(idx2.tobytes(), 34963)
        j['accessors'].append({'bufferView': v, 'componentType': 5125, 'count': len(idx2), 'type': 'SCALAR'}); p['indices'] = len(j['accessors']) - 1
        doubled += len(tri)
else:
    j['bufferViews'] = saved_views
while len(new) % 4: new.append(0)
j['buffers'] = [{'byteLength': len(new)}]
js = json.dumps(j, separators=(',', ':')).encode()
while len(js) % 4: js += b' '
out = struct.pack('<4sII', b'glTF', 2, 12 + 8 + len(js) + 8 + len(new)) + struct.pack('<I4s', len(js), b'JSON') + js + struct.pack('<I4s', len(new), b'BIN\x00') + bytes(new)
open(dst, 'wb').write(out)
print(f"{os.path.basename(dst)}: {len(d)//1024} KB -> {len(out)//1024} KB, удвоено треугольников: {doubled}, листва: {sorted(set(alpha_imgs.values()))}")
