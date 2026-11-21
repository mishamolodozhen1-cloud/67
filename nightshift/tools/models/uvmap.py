"""Карта UV: какая область атласа принадлежит какому продукту. argv: scene.gltf, textures_dir, out_dir"""
import sys, os, json, base64, numpy as np
from PIL import Image, ImageDraw, ImageFont
sys.path.insert(0, os.path.dirname(__file__))
gl, tex, out = sys.argv[1], sys.argv[2], sys.argv[3]
j = json.load(open(gl))
binc = open(os.path.join(os.path.dirname(gl), j['buffers'][0]['uri']), 'rb').read()
import glbread
mats = {0: 'Plane', 1: 'Asset', 2: 'Asset_2'}
imgs = {k: Image.open(os.path.join(tex, k + '_baseColor.png')).convert('RGB') for k in ('Asset', 'Asset_2')}
draws = {k: ImageDraw.Draw(v) for k, v in imgs.items()}
font = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf', 15)
masks = {}
pal = [(255,0,0),(0,200,0),(0,80,255),(255,0,255),(0,200,200),(255,150,0),(150,0,255),(255,255,0)]
rects = {}
for i, m in enumerate(j['meshes']):
    p = m['primitives'][0]; mat = mats[p['material']]
    if mat == 'Plane': continue
    name = m['name'].split('_Asset')[0]
    uv = glbread.accessor(j, binc, p['attributes']['TEXCOORD_0'])
    idx = glbread.accessor(j, binc, p['indices']).astype(int).reshape(-1, 3)
    W, H = imgs[mat].size
    mask = Image.new('L', (W, H), 0); md = ImageDraw.Draw(mask)
    col = pal[i % len(pal)]
    for t in idx:
        tu = uv[t]
        if tu[:, 0].max() - tu[:, 0].min() > 0.3 or tu[:, 1].max() - tu[:, 1].min() > 0.3:
            continue  # шов, который переходит через край — не рисуем
        off = np.floor(tu.mean(0))
        pts = [((uv[k][0] - off[0]) * W, (uv[k][1] - off[1]) * H) for k in t]
        md.polygon(pts, fill=255)
        draws[mat].line(pts + [pts[0]], fill=col, width=1)
    masks[name] = (mat, mask)
    bb = mask.getbbox()
    rects[name] = (mat, bb)
    if bb:
        draws[mat].text(((bb[0]+bb[2])/2 - 40, (bb[1]+bb[3])/2), name.replace('SM_', ''), fill=col, font=font, stroke_width=2, stroke_fill=(0,0,0))
os.makedirs(out, exist_ok=True)
for k, v in imgs.items(): v.save(os.path.join(out, 'uv_' + k + '.png'))
for name, (mat, mask) in masks.items(): mask.save(os.path.join(out, 'mask_' + name + '.png'))
json.dump({k: [v[0], v[1]] for k, v in rects.items()}, open(os.path.join(out, 'rects.json'), 'w'), indent=0)
