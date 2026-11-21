"""Закрасить на атласах области, которые используют только запрещённые продукты (алкоголь, таблетки)."""
import sys, os, json, numpy as np
from PIL import Image, ImageFilter
P = sys.argv[1]
BANNED = {'SM_Beer_Bottle_01', 'SM_Beer_Can_01', 'SM_Beer_Can_02', 'SM_Wine_Bottle_01', 'SM_Pills_Box_01'}
rects = json.load(open(P + '/uv/rects.json'))
os.makedirs(P + '/clean', exist_ok=True)
for atlas in ('Asset', 'Asset_2'):
    ban = np.zeros((1024, 1024), bool); ok = np.zeros((1024, 1024), bool)
    for name, (mat, bb) in rects.items():
        if mat != atlas: continue
        m = np.array(Image.open(P + '/uv/mask_' + name + '.png')) > 0
        if name in BANNED: ban |= m
        else: ok |= m
    okd = np.array(Image.fromarray((ok * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(5))) > 0
    paint = ban & ~okd
    paint = np.array(Image.fromarray((paint * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(3))) > 0
    print(atlas, 'banned px', int(ban.sum()), 'shared px', int((ban & ok).sum()), 'painted px', int(paint.sum()))
    Image.fromarray((paint * 255).astype(np.uint8)).save(P + '/clean/paint_' + atlas + '.png')
    for kind, fill in (('baseColor', (150, 152, 156)), ('normal', (128, 128, 255)), ('metallicRoughness', (255, 180, 0))):
        im = np.array(Image.open(P + '/food1k/textures/%s_%s.png' % (atlas, kind)).convert('RGB'))
        im[paint] = fill
        Image.fromarray(im).save(P + '/clean/%s_%s.png' % (atlas, kind))
