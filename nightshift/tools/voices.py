#!/usr/bin/env python3
"""Озвучка реплик NIGHT SHIFT (v10): синтез речи Piper (голоса ru_RU), обработка и сборка в спрайты.

  voices.py VOICES_DIR OUT_DIR [--reuse]   (запускать интерпретатором окружения, где стоит piper-tts)
  --reuse: уже готовые clips/*.wav не синтезируются заново (например, после отбора лучших дублей)

VOICES_DIR — папка с моделями ru_RU-*.onnx(.json). В OUT_DIR появятся:
  clips/<голос>_<ключ>.wav   — отдельные реплики (для проверки распознаванием речи)
  Voice2.ogg                 — мужские голоса покупателей (M1, M2)
  Voice3.ogg                 — женский голос покупателей (F1) и голос охранника (P)
  Voice4.ogg                 — (v12) герой кат-сцены (H), если есть готовые clips/H_<ключ>.wav из ElevenLabs
  voice_index.json           — где в спрайте лежит каждая реплика (файл, начало, конец, текст)

Обработка каждой реплики: тишина по краям срезается, срез НЧ ниже 90 Гц, громкость выравнивается
(RMS −19 dBFS, пик не выше −1 dB), короткие фейды. «Нервные» реплики — быстрее (length 0.92)
и на полтона выше.
"""
import json
import os
import subprocess
import sys
import wave

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import voice_lines as VL  # noqa: E402

SR = 44100
GAP = 0.6


def synth(voice, text, length):
    import io
    from piper.config import SynthesisConfig
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        voice.synthesize_wav(text, w, syn_config=SynthesisConfig(length_scale=length, noise_scale=0.6, noise_w_scale=0.75))
    buf.seek(0)
    with wave.open(buf, "rb") as r:
        sr = r.getframerate()
        data = np.frombuffer(r.readframes(r.getnframes()), dtype=np.int16).astype(np.float32) / 32768
    return data, sr


def process(data, sr, semitones):
    # ресэмплинг и сдвиг тона (ffmpeg: asetrate + atempo, темп сохраняется)
    args = ["ffmpeg", "-v", "error", "-f", "f32le", "-ar", str(sr), "-ac", "1", "-i", "-"]
    filt = []
    if abs(semitones) > 0.01:
        k = 2 ** (semitones / 12)
        filt.append(f"asetrate={int(sr * k)},aresample={SR},atempo={1 / k:.5f}")
    else:
        filt.append(f"aresample={SR}")
    filt.append("highpass=f=90")
    args += ["-af", ",".join(filt), "-ac", "1", "-ar", str(SR), "-f", "f32le", "-"]
    out = subprocess.run(args, input=data.astype(np.float32).tobytes(), capture_output=True, check=True).stdout
    y = np.frombuffer(out, dtype=np.float32).copy()
    # обрезать тишину
    env = np.sqrt(np.convolve(y ** 2, np.ones(441) / 441, "same"))
    on = np.where(env > 0.01)[0]
    if len(on):
        a = max(0, on[0] - int(0.03 * SR))
        b = min(len(y), on[-1] + int(0.08 * SR))
        y = y[a:b]
    # громкость
    rms = float(np.sqrt(np.mean(y.astype(np.float64) ** 2))) or 1e-9
    y = y * (10 ** (-19 / 20) / rms)
    pk = float(np.max(np.abs(y)))
    if pk > 0.89:
        y = y * (0.89 / pk)
    n = int(0.012 * SR)
    y[:n] *= np.linspace(0, 1, n)
    m = int(0.04 * SR)
    y[-m:] *= np.linspace(1, 0, m)
    return y


def save_wav(path, y):
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((np.clip(y, -1, 1) * 32767).astype(np.int16).tobytes())


def main():
    vdir, out = sys.argv[1], sys.argv[2]
    os.makedirs(os.path.join(out, "clips"), exist_ok=True)
    from piper import PiperVoice
    models = {}
    clips = {}  # (voice, key) -> (audio, text)
    plan = []
    for v in ("M1", "M2", "F1"):
        for key, (text, text_f, nervous) in VL.CUSTOMER.items():
            plan.append((v, key, text_f if (v == "F1" and text_f) else text, nervous))
    for key, text in VL.PLAYER.items():
        plan.append(("P", key, text, False))
    reuse = "--reuse" in sys.argv
    # v12: реплики героя кат-сцены — только готовые записи ElevenLabs (clips/H_<ключ>.wav), Piper их не делает
    hero = [k for k in VL.HERO if os.path.exists(os.path.join(out, "clips", f"H_{k}.wav"))]
    for key in hero:
        plan.append(("H", key, VL.HERO[key][0], False))
    for v, key, text, nervous in plan:
        cfg = VL.VOICES.get(v)
        path = os.path.join(out, "clips", f"{v}_{key}.wav")
        if reuse and os.path.exists(path):
            with wave.open(path, "rb") as r:
                y = np.frombuffer(r.readframes(r.getnframes()), dtype=np.int16).astype(np.float32) / 32768
            clips[(v, key)] = (y, text)
            continue
        if cfg is None:
            continue
        if cfg["model"] not in models:
            models[cfg["model"]] = PiperVoice.load(os.path.join(vdir, cfg["model"] + ".onnx"))
        data, sr = synth(models[cfg["model"]], text, cfg["length"] * (0.92 if nervous else 1.0))
        y = process(data, sr, cfg["semitones"] + (0.5 if nervous else 0.0))
        clips[(v, key)] = (y, text)
        save_wav(os.path.join(out, "clips", f"{v}_{key}.wav"), y)
    files = {"Voice2": ["M1", "M2"], "Voice3": ["F1", "P"]}
    if hero:
        files["Voice4"] = ["H"]  # v12: герой кат-сцены
    index = {}
    for fname, voices in files.items():
        parts = []
        t = 0.02
        parts.append(np.zeros(int(0.02 * SR), np.float32))
        for v in voices:
            for (vv, key), (y, text) in clips.items():
                if vv != v:
                    continue
                start = t
                parts.append(y)
                t += len(y) / SR
                index[f"{v}_{key}"] = {"File": fname, "Start": round(start, 3), "Stop": round(t, 3), "Text": text}
                parts.append(np.zeros(int(GAP * SR), np.float32))
                t += GAP
        audio = np.concatenate(parts)
        wav = os.path.join(out, fname + ".wav")
        save_wav(wav, audio)
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", wav, "-c:a", "libvorbis", "-q:a", "5", os.path.join(out, fname + ".ogg")], check=True)
        # позиции пересчитываются по реальным сэмплам (после склейки)
        print(fname, "%.1f с" % (len(audio) / SR))
    json.dump(index, open(os.path.join(out, "voice_index.json"), "w"), ensure_ascii=False, indent=1)
    print("реплик:", len(index))


if __name__ == "__main__":
    main()
