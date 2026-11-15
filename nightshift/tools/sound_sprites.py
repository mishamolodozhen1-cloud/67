"""Собирает звуковые спрайты для NIGHT SHIFT: ambience, sfx, voice (моно) и music (стерео)."""
import json, subprocess, sys, math
import numpy as np

RAW = sys.argv[1]
OUT = sys.argv[2]
SR = 44100

def load(name, start=0.0, dur=None, mono=True):
    cmd = ["ffmpeg", "-v", "error", "-ss", str(start), "-i", f"{RAW}/{name}"]
    if dur:
        cmd += ["-t", str(dur)]
    cmd += ["-ac", "1" if mono else "2", "-ar", str(SR), "-f", "f32le", "-"]
    data = np.frombuffer(subprocess.run(cmd, capture_output=True, check=True).stdout, dtype=np.float32)
    return data if mono else data.reshape(-1, 2)

def peak_norm(x, db=-1.0):
    p = np.max(np.abs(x)) or 1.0
    return x * (10 ** (db / 20) / p)

def rms_norm(x, db=-20.0):
    r = math.sqrt(float(np.mean(x.astype(np.float64) ** 2))) or 1e-9
    y = x * (10 ** (db / 20) / r)
    p = np.max(np.abs(y))
    return y / p * 0.98 if p > 0.98 else y

def fade(x, fin=0.01, fout=0.05):
    x = x.copy()
    a, b = int(fin * SR), int(fout * SR)
    if a: x[:a] *= np.linspace(0, 1, a)
    if b: x[-b:] *= np.linspace(1, 0, b)
    return x

def seamless(x, xf=1.0):
    """Бесшовная петля: хвост плавно перетекает в начало."""
    n = int(xf * SR)
    body, tail = x[:-n].copy(), x[-n:]
    w = np.linspace(0, 1, n)
    body[:n] = body[:n] * w + tail * (1 - w)
    return body

def tone(freqs, dur, decay=3.0, vol=0.4):
    t = np.arange(int(dur * SR)) / SR
    y = sum(np.sin(2 * np.pi * f * t) * (0.6 ** i) for i, f in enumerate(freqs))
    return (y * np.exp(-decay * t) * vol).astype(np.float32)

def pa_chime():
    notes = [784.0, 659.3, 523.3]  # соль, ми, до — классический гонг громкой связи
    out = np.zeros(int(2.6 * SR), dtype=np.float32)
    for i, f in enumerate(notes):
        s = tone([f, f * 2, f * 3], 1.6, decay=2.2)
        o = int(i * 0.42 * SR)
        out[o:o + len(s)] += s
    return peak_norm(out, -3)

def mix(*parts):
    n = max(len(p) + int(o * SR) for p, o in parts)
    out = np.zeros(n, dtype=np.float32)
    for p, o in parts:
        s = int(o * SR)
        out[s:s + len(p)] += p
    return out

def pa_filter(x):
    """Эффект громкоговорителя: полоса 300–3400 Гц и лёгкое эхо зала."""
    p = subprocess.run(["ffmpeg", "-v", "error", "-f", "f32le", "-ar", str(SR), "-ac", "1", "-i", "-",
                        "-af", "highpass=f=320,lowpass=f=3600,aecho=0.8:0.55:70|140:0.3|0.18,acompressor=threshold=-18dB:ratio=3",
                        "-f", "f32le", "-"], input=x.astype(np.float32).tobytes(), capture_output=True, check=True)
    return np.frombuffer(p.stdout, dtype=np.float32)

def build(name, items, gap=0.6, stereo=False):
    """items: [(key, samples, looped)] -> файл ogg и таблица отрезков."""
    chunks, table, t = [], {}, 0.0
    sil = np.zeros((int(gap * SR), 2) if stereo else int(gap * SR), dtype=np.float32)
    for key, x, looped in items:
        x = x.astype(np.float32)
        dur = len(x) / SR
        table[key] = {"start": round(t + 0.02, 3), "stop": round(t + dur - 0.02, 3), "loop": looped}
        chunks += [x, sil]
        t += dur + gap
    data = np.concatenate(chunks)
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(SR), "-ac", "2" if stereo else "1", "-i", "-",
                    "-c:a", "libvorbis", "-q:a", "5", f"{OUT}/{name}.ogg"], input=data.tobytes(), check=True)
    print(name, f"{t:.1f}s", len(items), "items")
    return table

lib = {}
# ---------- Фоновые петли
lib["amb"] = build("amb", [
    ("Fridge", seamless(rms_norm(load("fridge.wav", 30, 17), -18)), True),
    ("Vent", seamless(rms_norm(load("ac.wav", 0, 14.1), -18)), True),
    ("Fluorescent", seamless(rms_norm(load("fluor.wav", 0, 11.8), -20)), True),
    ("NightOutside", seamless(rms_norm(load("night.wav", 40, 21), -20), 1.5), True),
    ("Drone", seamless(rms_norm(load("drone.wav", 0, 30.7), -18), 1.5), True),
    ("Heartbeat", seamless(peak_norm(load("heart.wav", 0, 4.9), -2), 0.15), True),
    ("Static", seamless(rms_norm(load("glitch.wav", 2.0, 4.2), -20), 0.3), True),
])
# ---------- Короткие эффекты
metal = load("metal.wav")
cans = mix((peak_norm(metal), 0), (peak_norm(metal) * 0.7, 0.17), (peak_norm(metal) * 0.8, 0.31), (peak_norm(metal) * 0.5, 0.52),
           (peak_norm(load("boxdrop.wav", 0, 1.2)) * 0.5, 0.05))
lib["sfx"] = build("sfx", [
    ("Scan", fade(peak_norm(load("beep.wav"), -3), 0.002, 0.01), False),
    ("ScanError", fade(peak_norm(load("error.wav"), -4), 0.002, 0.02), False),
    ("Payment", fade(peak_norm(load("drawer.wav"), -2)), False),
    ("DoorChime", fade(peak_norm(load("chime.wav"), -3)), False),
    ("AutoDoor", fade(peak_norm(load("autodoor.wav"), -2)), False),
    ("Knock", fade(peak_norm(load("knock.wav"), -1)), False),
    ("KnockHard", fade(peak_norm(load("knock2.wav"), -1)), False),
    ("PowerDown", fade(peak_norm(load("powerdown.wav"), -1)), False),
    ("PowerUp", fade(peak_norm(load("poweron.wav", 0, 5.5), -2), 0.01, 0.6), False),
    ("Flicker", fade(peak_norm(load("flicker.wav"), -2)), False),
    ("CansFall", fade(peak_norm(cans, -1)), False),
    ("DoorSlam", fade(peak_norm(load("doorclose.wav"), -1)), False),
    ("FreezerDoor", fade(peak_norm(load("vault.wav"), -2)), False),
    ("DoorOpen", fade(peak_norm(load("dooropen.wav"), -2)), False),
    ("StepsFar", fade(peak_norm(load("steps_far.wav"), -3)), False),
    ("Steps", fade(peak_norm(load("steps.wav"), -3)), False),
    ("Stinger", fade(peak_norm(load("stinger.wav"), -2), 0.005, 0.8), False),
    ("BoxPick", fade(peak_norm(load("boxopen.wav"), -3)), False),
    ("BoxDrop", fade(peak_norm(load("boxdrop.wav", 0, 1.4), -3)), False),
    ("Phone", fade(peak_norm(load("phone.wav"), -3)), False),
    ("Cart", fade(peak_norm(load("cart.wav"), -2), 0.2, 0.6), False),
    ("Mop", fade(peak_norm(load("mop.wav"), -3)), False),
    ("CameraSwitch", fade(peak_norm(load("glitch.wav", 0, 0.9), -4), 0.005, 0.15), False),
    ("PAChime", pa_chime(), False),
])
# ---------- Объявления диктора (границы — по найденным паузам)
cuts = [(0.0, 6.9, "Welcome"), (7.52, 10.83, "CallRegister"), (11.42, 17.68, "Discount"), (18.25, 25.28, "NeverCloses"),
        (26.01, 30.15, "ColdRoom"), (30.75, 32.99, "RegisterZero"), (33.67, 36.1, "DontTurn"), (36.74, 39.52, "ShiftOver")]
voice = load("announcer.mp3")
lib["voice"] = build("voice", [(key, fade(peak_norm(pa_filter(voice[max(0, int((a - 0.05) * SR)):int((b + 0.25) * SR)]), -1), 0.02, 0.2), False)
                               for a, b, key in cuts], gap=0.8)
# ---------- Музыка (стерео, бесшовная)
m = load("music.wav", 0, None, mono=False)
m = m * (10 ** (-16 / 20) / (np.sqrt(np.mean(m.astype(np.float64) ** 2)) or 1))
n = int(1.5 * SR)
body = m[:-n].copy()
w = np.linspace(0, 1, n)[:, None]
body[:n] = body[:n] * w + m[-n:] * (1 - w)
lib["music"] = build("music", [("StoreMusic", np.clip(body, -0.98, 0.98), True)], gap=0.0, stereo=True)
json.dump(lib, open(f"{OUT}/sprites.json", "w"), indent=1, ensure_ascii=False)
