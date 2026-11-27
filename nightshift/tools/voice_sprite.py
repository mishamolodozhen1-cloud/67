#!/usr/bin/env python3
"""Склеить готовые реплики (clips/<голос>_<ключ>.wav) в один аудиофайл-спрайт.

  voice_sprite.py CLIPS_DIR PLANS_JSON FILE_NAME OUT_DIR ГОЛОС...

Порядок — как в plans.json (tools/eleven_scripts.py), между репликами 0.6 с тишины.
Пишет OUT_DIR/FILE_NAME.ogg и OUT_DIR/FILE_NAME.json: где в файле лежит каждая реплика
(File, Start, Stop, Text) — это вставляется в Shared/VoiceLines.lua.
v12/v15: Voice4 — герой одиночной кат-сцены (H) и четыре голоса командной (TD, TP, TL, TR).
"""
import json
import os
import subprocess
import sys
import wave

import numpy as np

SR = 44100
GAP = 0.6


def read_wav(path):
    with wave.open(path, "rb") as r:
        y = np.frombuffer(r.readframes(r.getnframes()), dtype=np.int16).astype(np.float32) / 32768
        if r.getframerate() != SR:
            raise SystemExit(f"{path}: частота {r.getframerate()}, нужна {SR}")
    return y


def main():
    clips_dir, plans_path, fname, out = sys.argv[1:5]
    voices = sys.argv[5:]
    plans = json.load(open(plans_path, encoding="utf-8"))["plans"]
    parts = [np.zeros(int(0.02 * SR), np.float32)]
    t = 0.02
    index = {}
    for v in voices:
        for key in plans[v]["order"]:
            path = os.path.join(clips_dir, f"{v}_{key}.wav")
            if not os.path.exists(path):
                print("нет реплики", v, key)
                continue
            y = read_wav(path)
            start = t
            parts.append(y)
            t += len(y) / SR
            index[f"{v}_{key}"] = {"File": fname, "Start": round(start, 3), "Stop": round(t, 3), "Text": plans[v]["texts"][key]}
            parts.append(np.zeros(int(GAP * SR), np.float32))
            t += GAP
    audio = np.concatenate(parts)
    os.makedirs(out, exist_ok=True)
    wav = os.path.join(out, fname + ".wav")
    with wave.open(wav, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((np.clip(audio, -1, 1) * 32767).astype(np.int16).tobytes())
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", wav, "-c:a", "libvorbis", "-q:a", "5", os.path.join(out, fname + ".ogg")], check=True)
    json.dump(index, open(os.path.join(out, fname + ".json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print(fname, "%.1f с," % (len(audio) / SR), "реплик:", len(index))


if __name__ == "__main__":
    main()
