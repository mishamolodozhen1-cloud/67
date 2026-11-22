#!/usr/bin/env python3
"""Режет длинную озвучку (все реплики одного голоса подряд, ElevenLabs) на отдельные реплики.

  voice_split.py AUDIO PLAN_JSON VOICE OUT_DIR

PLAN_JSON — plans.json (для голоса VOICE: порядок ключей order и тексты texts).
Как режет:
  1. распознаёт всю запись (faster-whisper, слова с отметками времени);
  2. находит паузы (тише порога дольше 0.16 с) — резать можно посередине паузы или, если паузы нет,
     в самом тихом месте между двумя распознанными словами (паузы выгоднее);
  3. перебором (динамика) выбирает, в каких паузах резать, чтобы слова в каждом куске
     больше всего совпали с текстом своей реплики (difflib по словам);
  4. каждую реплику чистит: срез НЧ ниже 80 Гц, тишина по краям (порог от громкости самой реплики —
     шёпот не обрезается), громкость около −19 dBFS: крик остаётся громче, шёпот тише (разница вдвое меньше);
  5. пишет OUT_DIR/clips/<VOICE>_<ключ>.wav и отчёт OUT_DIR/split_<VOICE>.json
     (для каждой реплики: начало, конец, сколько слов совпало).
Проверка распознаванием каждой отдельной реплики — tools/voice_check.py (без пересинтеза).
"""
import difflib
import json
import os
import re
import subprocess
import sys
import wave

import numpy as np

SR = 44100


def norm_tokens(s):
    s = s.lower().replace("ё", "е")
    s = re.sub(r"\[[^\]]*\]", " ", s)  # теги подачи [scared] не произносятся
    return re.sub(r"[^а-яa-z0-9]+", " ", s).split()


def load(path, sr):
    out = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-ac", "1", "-ar", str(sr), "-f", "f32le", "-"], capture_output=True, check=True).stdout
    return np.frombuffer(out, dtype=np.float32).copy()


def save(path, y):
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((np.clip(y, -1, 1) * 32767).astype(np.int16).tobytes())


def level_db(y):
    """Громкость речи (RMS только по звучащим кускам), dB."""
    win = int(0.03 * SR)
    env = np.sqrt(np.convolve(y.astype(np.float64) ** 2, np.ones(win) / win, "same"))
    loud = y[env > max(1e-4, 0.15 * float(np.percentile(env, 95)))]
    r = float(np.sqrt(np.mean(loud.astype(np.float64) ** 2))) if len(loud) else 1e-9
    return 20 * np.log10(max(r, 1e-9))


def clean(y, ref_db):
    """Срез НЧ, тишина по краям (порог — от громкости самой реплики, чтобы не съесть шёпот),
    громкость: −19 dB плюс половина отличия реплики от средней громкости голоса
    (крик остаётся громче, шёпот — тише, но разница вдвое меньше), пик не выше −1 dB."""
    out = subprocess.run(["ffmpeg", "-v", "error", "-f", "f32le", "-ar", str(SR), "-ac", "1", "-i", "-", "-af", "highpass=f=80", "-f", "f32le", "-"],
                         input=y.astype(np.float32).tobytes(), capture_output=True, check=True).stdout
    y = np.frombuffer(out, dtype=np.float32).copy()
    env = np.sqrt(np.convolve(y ** 2, np.ones(441) / 441, "same"))
    thr = max(0.0012, 0.12 * float(np.percentile(env, 95)))
    on = np.where(env > thr)[0]
    if len(on):
        y = y[max(0, on[0] - int(0.05 * SR)): min(len(y), on[-1] + int(0.14 * SR))]
    clip_db = level_db(y)
    target = -19 + 0.5 * (clip_db - ref_db)
    y = y * (10 ** ((target - clip_db) / 20))
    pk = float(np.max(np.abs(y)))
    if pk > 0.89:
        y = y * (0.89 / pk)
    n, m = int(0.01 * SR), int(0.05 * SR)
    y[:n] *= np.linspace(0, 1, n)
    y[-m:] *= np.linspace(1, 0, m)
    return y


def main():
    audio, plan_path, voice, out = sys.argv[1:5]
    plan = json.load(open(plan_path))["plans"][voice]
    order, texts = plan["order"], plan["texts"]
    os.makedirs(os.path.join(out, "clips"), exist_ok=True)
    from faster_whisper import WhisperModel
    model = WhisperModel("small", device="cpu", compute_type="int8", download_root=os.environ.get("WHISPER_DIR", "whisper"))
    a16 = load(audio, 16000)
    segs, _ = model.transcribe(a16, language="ru", beam_size=5, word_timestamps=True, vad_filter=False)
    words = []
    for s in segs:
        for w in s.words or []:
            for t in norm_tokens(w.word):
                words.append((t, w.start, w.end))
    spans = [[None, None, 0, 0] for _ in order]
    a = load(audio, SR)
    dur = len(a) / SR
    # паузы: громкость (окно 30 мс) ниже порога дольше 0.16 с; кандидаты на разрез — середины пауз
    win = int(0.03 * SR)
    env = np.sqrt(np.convolve(a ** 2, np.ones(win) / win, "same"))
    speech = env[env > 0.01]
    thr = max(0.006, 0.08 * float(np.median(speech))) if len(speech) else 0.01
    quiet = (env < thr).astype(np.int8)
    edges = np.diff(np.concatenate([[0], quiet, [0]]))
    starts, ends = np.where(edges == 1)[0], np.where(edges == -1)[0]
    gaps = [((i + j) / 2 / SR, (j - i) / SR) for i, j in zip(starts, ends) if (j - i) / SR >= 0.16 and i > 0 and j < len(quiet)]
    cand = [g[0] for g in gaps]
    glen = {g[0]: g[1] for g in gaps}
    # ещё кандидаты: между соседними распознанными словами (если пауза там слишком короткая и не нашлась) —
    # в самом тихом месте между словами
    ws = sorted((w[1], w[2]) for w in words)
    for (s0, e0), (s1, e1) in zip(ws, ws[1:]):
        lo, hi = e0, s1
        if hi - lo < 0.02 or any(lo <= c <= hi for c in cand):
            continue
        i0, i1 = int(lo * SR), int(hi * SR)
        cand.append((i0 + int(np.argmin(env[i0:i1]))) / SR)
    cand.sort()
    # слова по времени (середина слова)
    import bisect
    wmid = sorted(((w[1] + w[2]) / 2, w[0]) for w in words)
    wtimes = [m for m, _ in wmid]

    def seg_words(t0, t1):
        return [t for _, t in wmid[bisect.bisect_left(wtimes, t0):bisect.bisect_left(wtimes, t1)]]

    line_tokens = [norm_tokens(texts[k]) for k in order]
    N, G = len(order), len(cand)
    points = [0.0] + cand + [dur]  # индексы 0..G+1
    import functools

    @functools.lru_cache(maxsize=None)
    def score(li, a_i, b_i):
        toks = seg_words(points[a_i], points[b_i])
        exp = line_tokens[li]
        if not exp:
            return 0.0
        r = difflib.SequenceMatcher(None, exp, toks, autojunk=False).ratio()
        # чуть выгоднее резать по длинным паузам
        bonus = 0.05 * min(1.0, glen.get(points[b_i], 0.5) / 0.6) if b_i <= G else 0.05
        return r + bonus

    # динамика: best[li][p] — лучшая сумма для первых li+1 реплик, последняя кончается в точке p
    NEG = -1e9
    best = [[NEG] * (G + 2) for _ in range(N)]
    back = [[-1] * (G + 2) for _ in range(N)]
    for p_i in range(1, G + 2):
        best[0][p_i] = score(0, 0, p_i)
    for li in range(1, N):
        for p_i in range(li + 1, G + 2):
            bv, bk = NEG, -1
            for q in range(li, p_i):
                if best[li - 1][q] <= NEG / 2:
                    continue
                # реплика не длиннее 9 с
                if points[p_i] - points[q] > 9:
                    continue
                v = best[li - 1][q] + score(li, q, p_i)
                if v > bv:
                    bv, bk = v, q
            best[li][p_i], back[li][p_i] = bv, bk
    cuts_idx = [G + 1]
    p_i = G + 1
    for li in range(N - 1, 0, -1):
        p_i = back[li][p_i]
        cuts_idx.append(p_i)
    cuts_idx.append(0)
    cuts_idx.reverse()
    cuts = [points[c] for c in cuts_idx]
    for li in range(N):
        toks = seg_words(cuts[li], cuts[li + 1])
        spans[li][2] = round(difflib.SequenceMatcher(None, line_tokens[li], toks, autojunk=False).ratio(), 2)
    ref_db = level_db(a)
    report = {}
    for li, k in enumerate(order):
        y = a[int(cuts[li] * SR): int(cuts[li + 1] * SR)]
        if len(y) < SR * 0.15:
            report[k] = {"error": "слишком коротко"}
            continue
        save(os.path.join(out, "clips", f"{voice}_{k}.wav"), clean(y, ref_db))
        report[k] = {"From": round(cuts[li], 3), "To": round(cuts[li + 1], 3), "Match": spans[li][2]}
    json.dump(report, open(os.path.join(out, f"split_{voice}.json"), "w"), ensure_ascii=False, indent=1)
    weak = [k for k, r in report.items() if "error" in r or r["Match"] < 0.6]
    print(voice, "реплик:", len(order), "слабых:", weak)


if __name__ == "__main__":
    main()
