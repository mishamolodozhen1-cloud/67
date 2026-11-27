"""Спрайт Sfx9 (v15, командная кат-сцена): дворники (петля), смешок компании (два варианта), ручник — звуки Soundza.

  запускать из папки, где лежит sfx_raw/ со скачанными файлами; пишет Sfx9.wav, Sfx9.ogg, sfx9_index.json
Петли (дождь, мотор, поворотник) сделаны бесшовными: хвост плавно перетекает в начало.
"""
import json
import subprocess
import wave

import numpy as np

SR = 44100


def load(name, start=0.0, dur=None):
    cmd = ["ffmpeg", "-v", "error", "-ss", str(start), "-i", f"sfx_raw/{name}"]
    if dur:
        cmd += ["-t", str(dur)]
    cmd += ["-ac", "1", "-ar", str(SR), "-f", "f32le", "-"]
    return np.frombuffer(subprocess.run(cmd, capture_output=True, check=True).stdout, dtype=np.float32).copy()


def rms_norm(x, db):
    r = float(np.sqrt(np.mean(x.astype(np.float64) ** 2))) or 1e-9
    y = x * (10 ** (db / 20) / r)
    p = np.max(np.abs(y))
    return y / p * 0.95 if p > 0.95 else y


def fade(x, a=0.005, b=0.08):
    x = x.copy()
    n, m = int(a * SR), int(b * SR)
    if n:
        x[:n] *= np.linspace(0, 1, n)
    if m:
        x[-m:] *= np.linspace(1, 0, m)
    return x


def seamless(x, xf=1.0):
    n = int(xf * SR)
    body, tail = x[:-n].copy(), x[-n:]
    w = np.linspace(0, 1, n)
    body[:n] = body[:n] * w + tail * (1 - w)
    return body


items = [
    ("Wipers", seamless(rms_norm(load("wipers.wav", 1.0, 16.0), -24), 1.0), True),
    ("Chuckle", fade(rms_norm(load("chuckle_group.wav", 0, 1.42), -21), 0.01, 0.2), False),
    ("Chuckle2", fade(rms_norm(load("chuckle_crowd.wav", 0, 1.44), -22), 0.01, 0.2), False),
    ("Handbrake", fade(rms_norm(load("handbrake.wav", 0, 0.57), -20), 0.002, 0.05), False),
]
parts = [np.zeros(int(0.02 * SR), np.float32)]
t = 0.02
idx = {}
for name, x, loop in items:
    idx[name] = {"Start": round(t, 3), "Stop": round(t + len(x) / SR, 3), "Loop": loop}
    parts.append(x.astype(np.float32))
    t += len(x) / SR
    parts.append(np.zeros(int(0.6 * SR), np.float32))
    t += 0.6
a = np.concatenate(parts)
with wave.open("Sfx9.wav", "wb") as w:
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(SR)
    w.writeframes((np.clip(a, -1, 1) * 32767).astype(np.int16).tobytes())
subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", "Sfx9.wav", "-c:a", "libvorbis", "-q:a", "5", "Sfx9.ogg"], check=True)
json.dump(idx, open("sfx9_index.json", "w"), indent=1)
print("Sfx9 %.1f с" % (len(a) / SR))
print(json.dumps(idx))
