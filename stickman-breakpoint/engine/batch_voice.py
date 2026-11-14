# -*- coding: utf-8 -*-
"""Пакет реплик одним голосом: скачать mp3 пакета → разрезать на реплики (DP-выравнивание).
python3 engine/batch_voice.py 26 https://...mp3"""
import os, sys, subprocess
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
k, url = int(sys.argv[1].lstrip('B')), sys.argv[2]
raw = os.path.join(ROOT, 'build', 'voice_raw', 'B%d.mp3' % k)
subprocess.run(['curl', '-sSL', '-o', raw, url], check=True)
subprocess.run([sys.executable, os.path.join(HERE, 'split_voice.py'), 'B%d' % k], check=True)
