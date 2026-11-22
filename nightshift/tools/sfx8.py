"""Спрайт Sfx8 (v12, кат-сцена): салон машины под дождём, мотор, радио с помехами, щелчок,
датчик автоматических дверей, вибрация телефона, поворотник — звуки Soundza.

  запускать из папки, где лежит sfx_raw/ со скачанными файлами; пишет Sfx8.wav, Sfx8.ogg, sfx8_index.json
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
    ("CarRain", seamless(rms_norm(load("RainInCar.wav", 2.0, 15.0), -22), 1.0), True),
    ("CarEngine", seamless(rms_norm(load("EngineInCar.wav", 1.0, 13.0), -20), 1.0), True),
    ("RadioStatic", fade(rms_norm(load("RadioStatic.wav", 0, 4.7), -20), 0.02, 0.4), False),
    ("RadioOff", fade(rms_norm(load("RadioOff.wav", 0, 0.36), -18), 0.002, 0.05), False),
    ("DoorSensor", fade(rms_norm(load("SensorBeep.wav", 0, 0.55), -20), 0.002, 0.05), False),
    ("PhoneBuzz", fade(rms_norm(load("PhoneBuzz.wav", 0.12, 0.95), -18), 0.005, 0.05), False),
    ("TurnSignal", seamless(rms_norm(load("TurnSignal.wav", 1.0, 5.0), -24), 0.25), True),
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
with wave.open("Sfx8.wav", "wb") as w:
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(SR)
    w.writeframes((np.clip(a, -1, 1) * 32767).astype(np.int16).tobytes())
subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", "Sfx8.wav", "-c:a", "libvorbis", "-q:a", "5", "Sfx8.ogg"], check=True)
json.dump(idx, open("sfx8_index.json", "w"), indent=1)
print("Sfx8 %.1f с" % (len(a) / SR))
print(json.dumps(idx))
