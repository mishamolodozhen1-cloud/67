# -*- coding: utf-8 -*-
"""Рендер отдельных кадров для проверки: python3 engine/snap.py out_prefix T1 T2 ... | --shot sceneid:shotidx:t"""
import sys, os
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
os.chdir(os.path.dirname(HERE))
import core, gfx
from film import render_frame
import episode01
ep = episode01.build()
scale = float(os.environ.get('SNAP_SCALE', '0.5'))
core.BASE[0] = scale
out = sys.argv[1]
times = []
for a in sys.argv[2:]:
    if ':' in a:
        sid, k, t = a.split(':')
        sc = next(s for s in ep.scenes if s['id'] == sid)
        sh = sc['shots'][int(k)]
        times.append(sh.start + (float(t) if float(t) >= 0 else sh.dur + float(t)))
    else:
        times.append(float(a))
from PIL import Image
ims = []
for T in times:
    surf = gfx.Surface(int(1920 * scale), int(1080 * scale)); surf.ctx.scale(scale, scale)
    render_frame(surf.getCanvas(), ep, T)
    p = '/tmp/claude-0/-home-user-67/d8d329cf-aa63-5451-bcc1-ca67abe4df34/scratchpad/_snap.png'
    surf.makeImageSnapshot().save(p)
    ims.append(Image.open(p).convert('RGB'))
cols = min(3, len(ims)); rows = (len(ims) + cols - 1) // cols
w, h = ims[0].size
sheet = Image.new('RGB', (w * cols, h * rows))
for i, im in enumerate(ims):
    sheet.paste(im, ((i % cols) * w, (i // cols) * h))
sheet.save(out)
print('saved', out, ['%.2f' % t for t in times])
