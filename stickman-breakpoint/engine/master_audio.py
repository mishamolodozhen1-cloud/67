# -*- coding: utf-8 -*-
"""Мастеринг дорожки: усиление до целевой громкости + лимитер по истинному пику (4× передискретизация).
python3 engine/master_audio.py build/mix.wav build/master.wav -16 -1.5"""
import sys, json, subprocess
import numpy as np
from scipy.io import wavfile
from scipy.signal import resample_poly
from scipy.ndimage import minimum_filter1d, uniform_filter1d

def integrated(path):
    r = subprocess.run(['ffmpeg', '-v', 'info', '-i', path, '-af', 'ebur128', '-f', 'null', '-'], capture_output=True, text=True)
    i = r.stderr.rfind('I:')
    return float(r.stderr[i + 2:].split('LUFS')[0])

def master(src, dst, target_i=-16.0, ceil_db=-1.5):
    sr, x = wavfile.read(src)
    kind = x.dtype.kind
    x = x.astype(np.float64)
    if kind == 'i':
        x /= 32768.0
    cur = integrated(src)
    g = 10 ** ((target_i - cur) / 20)
    x *= g
    # истинный пик: максимум по каналам на сетке 4×
    up = np.abs(resample_poly(x, 4, 1, axis=0)).max(1)
    tp = up.reshape(-1, 4).max(1)[:len(x)]
    ceil = 10 ** ((ceil_db - 0.3) / 20)
    need = np.minimum(1.0, ceil / np.maximum(tp, 1e-9))
    L = int(0.006 * sr)
    gain = uniform_filter1d(minimum_filter1d(need, 2 * L + 1), L + 1)
    gain = np.minimum(gain, need)
    y = x * gain[:, None]
    print('gain %.2f dB, limited samples %d, min gain %.2f dB' % (20 * np.log10(g), int((need < 1).sum()), 20 * np.log10(gain.min())))
    wavfile.write(dst, sr, y.astype(np.float32))

def fix_overshoots(master_wav, video, out, ceil=0.85, rounds=3):
    """AAC иногда «перелетает» на резких щелчках: кодируем, ищем перелёты, локально приглушаем, повторяем."""
    import os
    sr, m = wavfile.read(master_wav)
    m = m.astype(np.float32)
    for r in range(rounds):
        wavfile.write(master_wav, sr, m)
        subprocess.run(['ffmpeg', '-v', 'error', '-y', '-i', video, '-i', master_wav, '-map', '0:v:0', '-map', '1:a:0', '-c:v', 'copy',
                        '-c:a', 'aac', '-b:a', '192k', '-ar', '48000', '-movflags', '+faststart', out], check=True)
        dec = subprocess.run(['ffmpeg', '-v', 'error', '-i', out, '-map', '0:a', '-f', 'f32le', '-acodec', 'pcm_f32le', '-'],
                             capture_output=True, check=True).stdout
        a = np.abs(np.frombuffer(dec, np.float32).reshape(-1, 2)).max(1)
        idx = np.where(a > ceil)[0]
        print('round %d: overshoots %d, max %.3f' % (r, len(idx), a.max()))
        if not len(idx):
            return
        for i in idx:
            i0, i1 = max(0, i - int(0.04 * sr)), min(len(m), i + int(0.04 * sr))
            k = ceil / a[i] * 0.95
            env = np.ones(i1 - i0, np.float32) * k
            f = int(0.006 * sr)
            env[:f] = np.linspace(1, k, f); env[-f:] = np.linspace(k, 1, f)
            m[i0:i1] *= np.minimum(1.0, env)[:, None]

if __name__ == '__main__':
    master(sys.argv[1], sys.argv[2], float(sys.argv[3]) if len(sys.argv) > 3 else -16.0, float(sys.argv[4]) if len(sys.argv) > 4 else -1.5)
