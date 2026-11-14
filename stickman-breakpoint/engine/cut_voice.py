# -*- coding: utf-8 -*-
"""Ручная нарезка пакета, если автоматическое выравнивание ошиблось.
python3 engine/cut_voice.py B24 k17=18.54:22.29 s01=23.09:25.57 ..."""
import os, sys
import numpy as np
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
ROOT = os.path.dirname(HERE)
import split_voice as S
import lines as LN
k = int(sys.argv[1].lstrip('B'))
x = S.load(os.path.join(ROOT, 'build', 'voice_raw', 'B%d.mp3' % k))
for arg in sys.argv[2:]:
    lid, rng = arg.split('=')
    a, b = [float(v) for v in rng.split(':')]
    seg = x[max(0, int((a - 0.05) * S.SR)):int((b + 0.1) * S.SR)].copy()
    f = int(0.008 * S.SR)
    seg[:f] *= np.linspace(0, 1, f); seg[-f:] *= np.linspace(1, 0, f)
    S.save_wav(os.path.join(ROOT, 'build', 'voice', lid + '.wav'), seg)
    n = len(LN.clean(LN.L[lid][1]))
    print('%-4s %5.2fs %5.1f ch/s  %s' % (lid, len(seg) / S.SR, n / (len(seg) / S.SR), LN.clean(LN.L[lid][1])[:60]))
