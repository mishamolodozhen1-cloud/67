# -*- coding: utf-8 -*-
"""Одиночные реплики (Flash v2.5): скачать mp3 → обрезать тишину → build/voice/<id>.wav.
python3 engine/single_voice.py id=url id=url ..."""
import os, sys, subprocess
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
ROOT = os.path.dirname(HERE)
from split_voice import split
import lines as LN
for arg in sys.argv[1:]:
    lid, url = arg.split('=', 1)
    raw = os.path.join(ROOT, 'build', 'voice_raw', 'L_%s.mp3' % lid)
    subprocess.run(['curl', '-sSL', '-o', raw, url], check=True)
    res, _ = split(raw, [lid], os.path.join(ROOT, 'build', 'voice'))
    r = res[0]
    print('%-4s %5.2fs %5.1f ch/s  %s' % (lid, r['dur'], r['cps'], LN.clean(LN.L[lid][1])[:60]))
