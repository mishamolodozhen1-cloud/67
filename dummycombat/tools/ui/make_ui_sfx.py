#!/usr/bin/env python3
"""Звуки интерфейса DUMMY COMBAT — синтез (свои, без чужих записей), один файл-спрайт.

  python3 tools/ui/make_ui_sfx.py  -> build/ui/UiSfx.ogg, build/ui/ui_sfx_index.json

Попадание (тихий щелчок), в голову (звонкий «тинь»), убийство (глухой удар + звон), смерть, кнопки, покупка,
новый уровень, отсчёт, начало матча, победа, поражение, ошибка. Тембры — синусы с обертонами, короткие
огибающие, немного шума для атаки: чисто и современно, без «ретро».
"""
import json
import os
import subprocess
import wave

import numpy as np

SR = 44100
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "build", "ui")
rng = np.random.default_rng(7)


def t_axis(dur):
    return np.arange(int(dur * SR)) / SR


def env(dur, attack=0.002, decay=0.1, sustain=0.0, release=None):
    t = t_axis(dur)
    a = np.clip(t / max(attack, 1e-4), 0, 1)
    d = np.exp(-np.maximum(t - attack, 0) / max(decay, 1e-4))
    e = a * (sustain + (1 - sustain) * d)
    if release:
        n = int(release * SR)
        e[-n:] *= np.linspace(1, 0, n) ** 2
    return e


def tone(freq, dur, partials=((1, 1.0),), **kw):
    t = t_axis(dur)
    f = np.asarray(freq(t) if callable(freq) else np.full_like(t, freq))
    phase = 2 * np.pi * np.cumsum(f) / SR
    y = sum(a * np.sin(phase * k) for k, a in partials)
    return y * env(dur, **kw)


def noise(dur, lp=None, hp=None, **kw):
    from scipy import signal
    y = rng.standard_normal(int(dur * SR))
    if hp:
        y = signal.sosfilt(signal.butter(2, hp, "highpass", fs=SR, output="sos"), y)
    if lp:
        y = signal.sosfilt(signal.butter(2, lp, "lowpass", fs=SR, output="sos"), y)
    return y * env(dur, **kw)


def mix(*parts):
    n = max(len(p[1]) for p in parts)
    y = np.zeros(n)
    for start, p in parts:
        i = int(start * SR)
        y[i:i + len(p)] += p[: n - i]
    return y


def norm(y, peak):
    return y / (np.max(np.abs(y)) + 1e-9) * peak


def chord(freqs, dur, **kw):
    return sum(tone(f, dur, partials=((1, 1.0), (2, 0.25), (3, 0.08)), **kw) for f in freqs)


def build():
    s = {}
    s["Hit"] = norm(mix((0, noise(0.02, hp=3000, decay=0.004)), (0, tone(2600, 0.06, decay=0.018))), 0.5)
    s["HitHead"] = norm(mix((0, noise(0.02, hp=4000, decay=0.004)),
                            (0, tone(3900, 0.22, partials=((1, 1.0), (2.76, 0.4), (5.4, 0.15)), decay=0.07))), 0.6)
    s["Kill"] = norm(mix((0, tone(lambda t: 120 - 50 * t / 0.2, 0.22, decay=0.07)),
                         (0, noise(0.04, lp=1800, decay=0.012) * 0.5),
                         (0.015, tone(1560, 0.45, partials=((1, 1.0), (2, 0.35), (3.01, 0.12)), decay=0.14)),
                         (0.015, tone(2340, 0.4, decay=0.11) * 0.45)), 0.7)
    s["Death"] = norm(mix((0, tone(lambda t: 260 * np.exp(-t * 1.6), 0.9, partials=((1, 1.0), (2, 0.3)), attack=0.01, decay=0.35)),
                          (0, noise(0.6, lp=600, attack=0.02, decay=0.25) * 0.3)), 0.55)
    s["Click"] = norm(mix((0, noise(0.012, hp=2500, decay=0.003) * 0.6), (0, tone(1250, 0.05, decay=0.012))), 0.35)
    s["Hover"] = norm(tone(2100, 0.035, decay=0.008), 0.15)
    s["Purchase"] = norm(mix((0, tone(1320, 0.25, partials=((1, 1.0), (2.0, 0.3), (3.0, 0.1)), decay=0.08)),
                             (0.07, tone(1975, 0.4, partials=((1, 1.0), (2.0, 0.3)), decay=0.12))), 0.5)
    notes = [523.25, 659.25, 783.99, 1046.5]
    s["LevelUp"] = norm(mix(*[(i * 0.09, tone(f, 0.7, partials=((1, 1.0), (2, 0.3), (3, 0.12)), decay=0.25)) for i, f in enumerate(notes)],
                            (0.36, chord([523.25, 659.25, 783.99], 1.0, attack=0.02, decay=0.5) * 0.4)), 0.55)
    s["Xp"] = norm(tone(1760, 0.18, partials=((1, 1.0), (2, 0.2)), decay=0.05), 0.25)
    s["Count"] = norm(tone(880, 0.16, partials=((1, 1.0), (3, 0.1)), attack=0.003, decay=0.09), 0.45)
    s["CountGo"] = norm(tone(1318.5, 0.5, partials=((1, 1.0), (2, 0.25), (3, 0.08)), attack=0.003, decay=0.22), 0.55)
    s["MatchStart"] = norm(mix((0, noise(0.8, hp=400, lp=6000, attack=0.6, decay=0.15) * 0.25),
                               (0.55, chord([220, 329.63, 440, 659.25], 1.3, attack=0.01, decay=0.5))), 0.6)
    s["Victory"] = norm(mix((0, chord([392, 493.88, 587.33], 0.6, attack=0.01, decay=0.25)),
                            (0.35, chord([523.25, 659.25, 783.99, 1046.5], 1.8, attack=0.02, decay=0.9))), 0.6)
    s["Defeat"] = norm(mix((0, chord([293.66, 349.23, 440], 0.7, attack=0.01, decay=0.3)),
                           (0.4, chord([220, 261.63, 329.63], 1.8, attack=0.03, decay=0.8))), 0.5)
    s["Error"] = norm(tone(180, 0.18, partials=((1, 1.0), (2, 0.5), (3, 0.3)), decay=0.08), 0.35)
    s["Explosion"] = norm(mix((0, noise(2.2, lp=900, attack=0.003, decay=0.55) * 0.9),
                              (0, tone(lambda t: 70 * np.exp(-t * 1.5) + 28, 1.6, attack=0.002, decay=0.45) * 1.2),
                              (0, noise(0.25, hp=1200, lp=7000, attack=0.001, decay=0.05) * 0.6),
                              (0.05, noise(1.6, hp=300, lp=2500, attack=0.05, decay=0.5) * 0.35)), 0.9)
    s["Warning"] = norm(tone(1046.5, 0.12, partials=((1, 1.0), (2, 0.3), (3, 0.15)), attack=0.002, decay=0.06), 0.4)
    s["Equip"] = norm(mix((0, noise(0.05, hp=1500, lp=7000, decay=0.015)), (0.03, noise(0.04, hp=2500, decay=0.01) * 0.7)), 0.3)
    return s


def main():
    os.makedirs(OUT, exist_ok=True)
    sounds = build()
    gap = 0.25
    parts, t, index = [np.zeros(int(0.05 * SR))], 0.05, {}
    for name, y in sounds.items():
        index[name] = {"Start": round(t, 4), "Stop": round(t + len(y) / SR, 4)}
        parts += [y, np.zeros(int(gap * SR))]
        t += len(y) / SR + gap
    audio = np.concatenate(parts)
    wav = os.path.join(OUT, "UiSfx.wav")
    with wave.open(wav, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((np.clip(audio, -1, 1) * 32767).astype(np.int16).tobytes())
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", wav, "-c:a", "libvorbis", "-q:a", "6", os.path.join(OUT, "UiSfx.ogg")], check=True)
    os.remove(wav)
    with open(os.path.join(OUT, "ui_sfx_index.json"), "w") as f:
        json.dump({"Length": round(len(audio) / SR, 3), "Sounds": index}, f, indent=1)
    print("UiSfx %.2f с, %d звуков" % (len(audio) / SR, len(index)))


if __name__ == "__main__":
    main()
