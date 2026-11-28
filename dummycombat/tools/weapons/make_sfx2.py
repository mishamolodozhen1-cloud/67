#!/usr/bin/env python3
"""Второй звуковой спрайт оружия DUMMY COMBAT: выстрелы пистолета, ПП, дробовика, снайперской винтовки,
затвор снайперской и затвор-кожух пистолета (первый спрайт — make_sfx.py: AK-47, механика, попадания).

  python3 tools/weapons/make_sfx2.py <папка со скачанными файлами Soundza>
  → build/weapons/WeaponSfx2.ogg, sfx2_index.json, preview_sfx2.png

Исходники — звуки библиотеки Soundza (бесплатная лицензия, атрибуция не обязательна), см. SOURCES. Обработка
та же, что у AK: начало точно с атаки, слои по атаке, громкость по RMS, мягкое ограничение пиков, хвост улицы.
"""
import json
import os
import subprocess
import sys
import wave

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import make_sfx as m  # noqa: E402

SR = m.SR
OUT = m.OUT
SOURCES = {
    "pistol_9mm.wav": "https://soundza.com/sound/real-9mm-pistol-shot",
    "pistol_1911.wav": "https://soundza.com/sound/colt-1911-pistol-shot",
    "pistol_game.wav": "https://soundza.com/sound/pistol-shot",
    "gunshot2.wav": "https://soundza.com/sound/gunshot-2",
    "shotgun_20g.wav": "https://soundza.com/sound/20-gauge-shotgun-shot",
    "shotgun_crisp.wav": "https://soundza.com/sound/shotgun-shot-crisp",
    "rifle_405.wav": "https://soundza.com/sound/405-winchester-rifle-shot",
    "rifle_hp.wav": "https://soundza.com/sound/high-powered-rifle-shot",
    "bolt_open.wav": "https://soundza.com/sound/quick-gun-cock",
    "bolt_close.wav": "https://soundza.com/sound/short-gun-cock-click",
    "slide.wav": "https://soundza.com/sound/metal-slide-whoosh",
}


def layer(raw, name, dur, db, hp=None, lp=None, rel=0.25, t0=None, t1=None, delay=0.0):
    x = m.trim_from_onset(m.load(raw, name), dur, rel)
    if hp:
        x = m.filt(x, "highpass", hp, 2)
    if lp:
        x = m.filt(x, "lowpass", lp, 2)
    if t0 is not None:
        x = m.decay(x, t0, t1)
    x = m.level(m.fade(x, 0.001, 0.06), db, 1.0)
    if delay:
        x = np.concatenate([np.zeros(int(delay * SR)), x])
    return x


def pitch(x, k):
    """Сдвиг высоты передискретизацией (k > 1 — выше и короче)."""
    n = int(len(x) / k)
    return np.interp(np.arange(n) * k, np.arange(len(x)), x)


def build(raw):
    items = []

    def add(name, x, group, db):
        items.append((name, m.fade(m.level(x, db), 0.0005, 0.1), group))

    # пистолет: два разных выстрела, сухие, короткий хвост
    p1 = m.mix(layer(raw, "pistol_9mm.wav", 0.75, -15, hp=120, t0=0.12, t1=0.75),
               layer(raw, "pistol_game.wav", 0.4, -19, hp=200))
    p2 = m.mix(layer(raw, "pistol_1911.wav", 0.8, -15, hp=110, t0=0.14, t1=0.8),
               layer(raw, "pistol_game.wav", 0.4, -21, hp=250))
    add("Pistol1", p1, "ShotPistol", -17)
    add("Pistol2", p2, "ShotPistol", -17)
    # ПП: тот же калибр, но короче и суше (очередь не должна «звенеть»), чуть выше
    s1 = m.mix(pitch(layer(raw, "pistol_game.wav", 0.35, -16, hp=180), 1.06),
               layer(raw, "gunshot2.wav", 0.45, -19, hp=150, t0=0.06, t1=0.45))
    s2 = m.mix(pitch(layer(raw, "pistol_9mm.wav", 0.45, -16, hp=160, t0=0.06, t1=0.45), 1.08),
               layer(raw, "gunshot2.wav", 0.4, -21, hp=200, t0=0.05, t1=0.4))
    add("Smg1", s1, "ShotSMG", -17.5)
    add("Smg2", s2, "ShotSMG", -17.5)
    # дробовик: плотный низ + хлёсткая атака
    g1 = m.mix(layer(raw, "shotgun_20g.wav", 1.2, -14, hp=60, t0=0.2, t1=1.2),
               layer(raw, "shotgun_crisp.wav", 0.45, -18, hp=300))
    add("Shotgun1", g1, "ShotShotgun", -17)
    add("Shotgun2", pitch(g1, 0.96), "ShotShotgun", -17)
    # снайперская: удар и долгий раскат
    r1 = m.mix(layer(raw, "rifle_405.wav", 1.8, -14, hp=50, t0=0.35, t1=1.8),
               layer(raw, "rifle_hp.wav", 1.6, -19, hp=200, t0=0.2, t1=1.6))
    add("Sniper1", r1, "ShotSniper", -17)
    # механика
    add("BoltOpen", layer(raw, "bolt_open.wav", 0.4, -20, hp=200, rel=0.3), "BoltOpen", -20)
    add("BoltClose", layer(raw, "bolt_close.wav", 0.35, -19, hp=200, rel=0.3), "BoltClose", -19)
    add("Slide", layer(raw, "slide.wav", 0.5, -20, hp=200, rel=0.3), "Slide", -20)

    gap = 0.35
    parts, t, index = [np.zeros(int(0.05 * SR))], 0.05, {}
    for name, x, group in items:
        index[name] = {"Start": round(t, 4), "Stop": round(t + len(x) / SR, 4), "Group": group}
        parts += [x, np.zeros(int(gap * SR))]
        t += len(x) / SR + gap
    return np.concatenate(parts), index, items


def main():
    raw = sys.argv[1]
    os.makedirs(OUT, exist_ok=True)
    audio, index, items = build(raw)
    wav = os.path.join(OUT, "WeaponSfx2.wav")
    with wave.open(wav, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((np.clip(audio, -1, 1) * 32767).astype(np.int16).tobytes())
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", wav, "-c:a", "libvorbis", "-q:a", "6",
                    os.path.join(OUT, "WeaponSfx2.ogg")], check=True)
    with open(os.path.join(OUT, "sfx2_index.json"), "w") as f:
        json.dump({"Length": round(len(audio) / SR, 3), "Sounds": index, "Sources": SOURCES}, f, indent=1)
    m.preview(items, os.path.join(OUT, "preview_sfx2.png"))
    print("WeaponSfx2: %.2f с, %d звуков" % (len(audio) / SR, len(index)))


if __name__ == "__main__":
    main()
