#!/usr/bin/env python3
"""Звуковой спрайт оружия DUMMY COMBAT (этап 4): выстрел AK-47, дальний выстрел, механика, гильзы, попадания.

  python3 tools/weapons/make_sfx.py <папка со скачанными файлами Soundza>
  → build/weapons/WeaponSfx.wav, WeaponSfx.ogg, sfx_index.json, preview_sfx.png

Исходники — звуки библиотеки Soundza (бесплатная лицензия, без обязательной атрибуции); имена файлов —
те, под которыми их сохранили при скачивании (см. SOURCES). Выстрел собран из трёх слоёв, выровненных по
атаке: сухой хлопок винтовки + низ (одиночный выстрел из автоматической очереди) + хвост-эхо улицы.
Всё приводится к одной частоте 44.1 кГц, моно; громкость — по RMS, пики ограничены.
"""
import json
import os
import subprocess
import sys
import wave

import numpy as np
from scipy import signal

SR = 44100
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "build", "weapons")

SOURCES = {
    "shot_realistic.wav": "https://soundza.com/sound/realistic-assault-rifle-shot",
    "shot_deep.wav": "https://soundza.com/sound/deep-rifle-shot",
    "dist_crisp.wav": "https://soundza.com/sound/crisp-distant-gunshot",
    "dist_ar15.wav": "https://soundza.com/sound/ar15-rifle-shot-distant",
    "dry_click.wav": "https://soundza.com/sound/empty-gun-click",
    "cock_slow.wav": "https://soundza.com/sound/long-slow-gun-cock",
    "safety.wav": "https://soundza.com/sound/gun-safety-click",
    "chamber.wav": "https://soundza.com/sound/bullet-chamber-click",
    "case_release.wav": "https://soundza.com/sound/gun-case-release",
    "shell_hit.wav": "https://soundza.com/sound/metallic-shell-hit",
    "shell_bright.wav": "https://soundza.com/sound/bright-bullet-drop",
    "imp_metal.wav": "https://soundza.com/sound/metallic-bullet-impact-1",
    "imp_concrete.wav": "https://soundza.com/sound/concrete-smash-impact",
    "imp_debris.wav": "https://soundza.com/sound/concrete-debris-drop",
    "imp_dirt.wav": "https://soundza.com/sound/rock-hit-dirt-impact",
    "imp_wood.wav": "https://soundza.com/sound/rock-on-wood-impact",
    "imp_woodbreak.wav": "https://soundza.com/sound/wood-breaking-1",
    "imp_meaty.wav": "https://soundza.com/sound/meaty-impact-hit",
    "imp_flesh.wav": "https://soundza.com/sound/wet-impact-flesh-hit",
}


def load(raw, name, start=0.0, dur=None):
    cmd = ["ffmpeg", "-v", "error", "-ss", str(start), "-i", os.path.join(raw, name)]
    if dur:
        cmd += ["-t", str(dur)]
    cmd += ["-ac", "1", "-ar", str(SR), "-f", "f32le", "-"]
    out = subprocess.run(cmd, capture_output=True, check=True).stdout
    return np.frombuffer(out, dtype=np.float32).astype(np.float64)


def rms(x):
    return float(np.sqrt(np.mean(x ** 2))) or 1e-9


def level(x, db, peak=0.93):
    y = x * (10 ** (db / 20) / rms(x))
    p = float(np.max(np.abs(y)))
    if p > peak:
        y = soft_limit(y, peak)
    return y


def soft_limit(x, ceiling):
    # мягкий лимитер: компрессия только пиков (tanh), тело звука не трогаем
    k = ceiling * 0.7
    y = x.copy()
    m = np.abs(y) > k
    y[m] = np.sign(y[m]) * (k + (ceiling - k) * np.tanh((np.abs(y[m]) - k) / (ceiling - k)))
    return y


def fade(x, a=0.002, b=0.06):
    x = x.copy()
    n, m = int(a * SR), int(b * SR)
    if n:
        x[:n] *= np.linspace(0, 1, n)
    if m:
        x[-m:] *= np.linspace(1, 0, m) ** 2
    return x


def filt(x, kind, freq, order=4):
    sos = signal.butter(order, freq, btype=kind, fs=SR, output="sos")
    return signal.sosfilt(sos, x)


def onset(x, rel=0.25):
    a = np.abs(x)
    i = int(np.argmax(a > rel * a.max()))
    return max(0, i - int(0.0015 * SR))


def trim_from_onset(x, dur, rel=0.25):
    i = onset(x, rel)
    return x[i:i + int(dur * SR)]


def decay(x, t0, t1):
    # огибающая: 1 до t0, затем экспоненциально к ~-60 дБ к t1
    env = np.ones(len(x))
    i0, i1 = int(t0 * SR), min(len(x), int(t1 * SR))
    if i1 > i0:
        k = np.linspace(0, 1, i1 - i0)
        env[i0:i1] = 10 ** (-3 * k)
        env[i1:] = 0.001
    return x * env


def mix(*layers):
    n = max(len(l) for l in layers)
    y = np.zeros(n)
    for l in layers:
        y[:len(l)] += l
    return y


def shot(raw, body_index):
    # 1) сухой хлопок (атака и механика затвора)
    crack = trim_from_onset(load(raw, "shot_realistic.wav"), 0.9)
    crack = level(filt(crack, "highpass", 140, 2), -16, 1.0)
    # 2) низ: одиночный выстрел из очереди (выстрелы идут каждые ~0.115 с)
    burst = load(raw, "shot_deep.wav")
    t = body_index * 0.1155
    body = burst[int(t * SR):int((t + 0.16) * SR)]
    body = trim_from_onset(body, 0.13)
    body = filt(body, "lowpass", 1600, 4)
    body = level(fade(body, 0.001, 0.05), -15, 1.0)
    # 3) хвост улицы: раскат дальнего выстрела, только низ-середина, тише
    tail = trim_from_onset(load(raw, "dist_crisp.wav"), 1.05, 0.5)
    tail = filt(filt(tail, "lowpass", 2600, 2), "highpass", 70, 2)
    tail = level(decay(tail, 0.15, 1.05), -25, 1.0)
    tail = np.concatenate([np.zeros(int(0.012 * SR)), tail])
    y = mix(crack, body * 0.9, tail)
    return fade(level(y, -14.5), 0.0005, 0.12)


def distant(raw):
    x = trim_from_onset(load(raw, "dist_ar15.wav"), 1.5, 0.3)
    x = filt(filt(x, "lowpass", 3200, 2), "highpass", 60, 2)
    return fade(level(decay(x, 0.3, 1.5), -21), 0.001, 0.15)


def piece(raw, name, start, dur, db, hp=None, lp=None, a=0.002, b=0.05, rel=0.3):
    # кусок начинается прямо с атаки (без тишины перед ней), иначе звук попадания запаздывает
    x = trim_from_onset(load(raw, name, start, dur + 0.3), dur, rel)
    if hp:
        x = filt(x, "highpass", hp, 2)
    if lp:
        x = filt(x, "lowpass", lp, 2)
    return fade(level(x, db), a, b)


def build(raw):
    items = []

    def add(name, x, group):
        items.append((name, x, group))

    add("Shot1", shot(raw, 0), "Shot")
    add("Shot2", shot(raw, 5), "Shot")
    add("Shot3", shot(raw, 9), "Shot")
    add("Distant", distant(raw), "Distant")
    add("Dry", piece(raw, "dry_click.wav", 1.0, 0.13, -20, hp=300), "Dry")
    add("Select", piece(raw, "safety.wav", 1.47, 0.2, -23, hp=300), "Select")
    add("MagOut", piece(raw, "case_release.wav", 0.30, 0.44, -21, hp=180), "MagOut")
    add("MagIn", piece(raw, "chamber.wav", 0.10, 0.36, -19, hp=150), "MagIn")
    add("Charge", piece(raw, "cock_slow.wav", 0.0, 0.46, -19, hp=150), "Charge")
    add("Casing1", piece(raw, "shell_hit.wav", 0.17, 0.32, -28, hp=500), "Casing")
    add("Casing2", piece(raw, "shell_hit.wav", 0.52, 0.34, -28, hp=500), "Casing")
    add("Casing3", piece(raw, "shell_bright.wav", 0.0, 0.55, -29, hp=500), "Casing")
    # металл: в длинном файле — серия отдельных попаданий, берём три
    for i, t in enumerate((5.96, 2.90, 7.71)):
        add("Metal%d" % (i + 1), piece(raw, "imp_metal.wav", t, 0.5, -20, hp=120, b=0.12), "Metal")
    add("Concrete1", piece(raw, "imp_debris.wav", 0.0, 0.55, -20, hp=90), "Concrete")
    add("Concrete2", piece(raw, "imp_concrete.wav", 0.0, 0.38, -21, hp=110, b=0.12), "Concrete")
    add("Concrete3", piece(raw, "imp_dirt.wav", 0.32, 0.6, -24, hp=90, b=0.15), "Concrete")
    wood = mix(piece(raw, "imp_wood.wav", 0.13, 0.22, -20, hp=100),
               np.concatenate([np.zeros(int(0.004 * SR)), piece(raw, "imp_woodbreak.wav", 0.06, 0.08, -26, hp=400)]))
    add("Wood1", fade(level(wood, -20), 0.001, 0.05), "Wood")
    add("Wood2", piece(raw, "imp_woodbreak.wav", 0.0, 0.09, -22, hp=200, rel=0.7), "Wood")
    add("Body1", piece(raw, "imp_meaty.wav", 0.0, 0.30, -18, hp=70), "Body")
    add("Body2", piece(raw, "imp_flesh.wav", 0.0, 0.34, -19, hp=70), "Body")

    gap = 0.4
    parts = [np.zeros(int(0.05 * SR))]
    t = 0.05
    index = {}
    for name, x, group in items:
        index[name] = {"Start": round(t, 4), "Stop": round(t + len(x) / SR, 4), "Group": group}
        parts.append(x)
        t += len(x) / SR
        parts.append(np.zeros(int(gap * SR)))
        t += gap
    return np.concatenate(parts), index, items


def preview(items, path):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    n = len(items)
    cols = 4
    rows = (n + cols - 1) // cols
    fig, axs = plt.subplots(rows, cols, figsize=(16, 1.9 * rows), squeeze=False)
    for k, (name, x, _) in enumerate(items):
        ax = axs[k // cols, k % cols]
        ax.plot(np.arange(len(x)) / SR, x, lw=0.4)
        ax.set_ylim(-1, 1)
        ax.set_title("%s  %.2fs  rms %.1f dB" % (name, len(x) / SR, 20 * np.log10(rms(x))), fontsize=8)
    for k in range(n, rows * cols):
        axs[k // cols, k % cols].axis("off")
    plt.tight_layout()
    plt.savefig(path, dpi=70)


def main():
    raw = sys.argv[1]
    os.makedirs(OUT, exist_ok=True)
    audio, index, items = build(raw)
    wav = os.path.join(OUT, "WeaponSfx.wav")
    with wave.open(wav, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((np.clip(audio, -1, 1) * 32767).astype(np.int16).tobytes())
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", wav, "-c:a", "libvorbis", "-q:a", "6",
                    os.path.join(OUT, "WeaponSfx.ogg")], check=True)
    with open(os.path.join(OUT, "sfx_index.json"), "w") as f:
        json.dump({"Length": round(len(audio) / SR, 3), "Sounds": index, "Sources": SOURCES}, f, indent=1)
    preview(items, os.path.join(OUT, "preview_sfx.png"))
    print("WeaponSfx: %.2f с, %d звуков" % (len(audio) / SR, len(index)))


if __name__ == "__main__":
    main()
