"""glTF (+bin, текстуры) -> GLB с текстурами не больше 1024 px.
pack_glb.py scene.gltf out.glb [--blank-badges]
--blank-badges: текстура значков (Carbadges) заменяется однотонным хромом, чтобы не было логотипов."""
import sys, os, json, io, struct
from PIL import Image
src, out = sys.argv[1], sys.argv[2]
blank = '--blank-badges' in sys.argv
base = os.path.dirname(src)
j = json.load(open(src))
binary = bytearray(open(os.path.join(base, j['buffers'][0]['uri']), 'rb').read()) if j.get('buffers') else bytearray()
def align():
    while len(binary) % 4: binary.append(0)
for im in j.get('images', []):
    uri = im.pop('uri', None)
    if uri is None: continue
    path = os.path.join(base, uri)
    img = Image.open(path)
    fmt = 'JPEG' if uri.lower().endswith(('.jpg', '.jpeg')) else 'PNG'
    if blank and 'adge' in os.path.basename(uri) and 'baseColor' in uri:
        img = Image.new('RGBA', (64, 64), (150, 152, 156, 255)); fmt = 'PNG'
    if max(img.size) > 1024:
        k = 1024 / max(img.size)
        img = img.resize((max(1, int(img.size[0] * k)), max(1, int(img.size[1] * k))), Image.LANCZOS)
    bio = io.BytesIO()
    if fmt == 'JPEG':
        img.convert('RGB').save(bio, 'JPEG', quality=90)
    else:
        img.save(bio, 'PNG', optimize=True)
    data = bio.getvalue()
    align()
    off = len(binary); binary.extend(data)
    j['bufferViews'].append({'buffer': 0, 'byteOffset': off, 'byteLength': len(data)})
    im['bufferView'] = len(j['bufferViews']) - 1
    im['mimeType'] = 'image/jpeg' if fmt == 'JPEG' else 'image/png'
align()
j['buffers'] = [{'byteLength': len(binary)}]
js = json.dumps(j, separators=(',', ':')).encode()
while len(js) % 4: js += b' '
glb = struct.pack('<4sII', b'glTF', 2, 12 + 8 + len(js) + 8 + len(binary))
glb += struct.pack('<I4s', len(js), b'JSON') + js + struct.pack('<I4s', len(binary), b'BIN\x00') + bytes(binary)
open(out, 'wb').write(glb)
print(out, round(len(glb) / 1e6, 2), 'MB')
