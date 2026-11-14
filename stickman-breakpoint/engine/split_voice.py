# -*- coding: utf-8 -*-
"""Нарезка пакетной озвучки на отдельные реплики.

Каждый пакет ElevenLabs — реплики одного голоса, разделённые тегом [long pause].
Знаем число реплик N, поэтому режем по N-1 самым длинным паузам и проверяем,
что длительность каждого куска пропорциональна длине текста.
"""
import json, os, subprocess, sys
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import lines  # noqa

SR = 48000


def load(path):
    raw = subprocess.run(['ffmpeg', '-v', 'quiet', '-i', path, '-ac', '1', '-ar', str(SR), '-f', 'f32le', '-'],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, np.float32).copy()


def save_wav(path, x):
    p = subprocess.Popen(['ffmpeg', '-v', 'quiet', '-y', '-f', 'f32le', '-ar', str(SR), '-ac', '1', '-i', '-',
                          '-c:a', 'pcm_s16le', path], stdin=subprocess.PIPE)
    p.communicate(x.astype(np.float32).tobytes())


def silences(x, thr_db=-42.0, min_len=0.18):
    hop = int(0.01 * SR)
    n = len(x) // hop
    fr = x[:n * hop].reshape(n, hop)
    db = 20 * np.log10(np.sqrt((fr ** 2).mean(1)) + 1e-9)
    quiet = db < thr_db
    out = []
    i = 0
    while i < n:
        if quiet[i]:
            j = i
            while j < n and quiet[j]:
                j += 1
            if (j - i) * 0.01 >= min_len:
                out.append((i * 0.01, j * 0.01))
            i = j
        else:
            i += 1
    return out, db


def split(batch_file, ids, outdir):
    x = load(batch_file)
    dur = len(x) / SR
    sil, db = silences(x)
    internal = [s for s in sil if s[0] > 0.05 and s[1] < dur - 0.05]
    n = len(ids)
    if len(internal) < n - 1:
        raise RuntimeError('%s: too few pauses (%d) for %d lines' % (batch_file, len(internal), n))
    # DP: выбираем N-1 пауз так, чтобы длины кусков соответствовали длине текста,
    # а сами паузы были как можно длиннее ([long pause] между репликами)
    chars = [max(4, len(lines.clean(lines.L[i][1]))) for i in ids]
    speech_total = dur - sum(b - a for a, b in internal) * 0.5
    cps = sum(chars) / max(1.0, speech_total)
    cand = internal
    m = len(cand)
    import math as _m
    INF = 1e18
    def seg_cost(a, b, k):
        d = max(0.05, b - a)
        e = chars[k] / cps + 0.25
        return (_m.log(d / e)) ** 2
    def sil_bonus(c):
        return -1.4 * _m.log(max(0.05, c[1] - c[0]) / 0.5)
    if n == 1:
        cuts = []
    else:
        dp = [[INF] * m for _ in range(n)]
        bk = [[-1] * m for _ in range(n)]
        for i in range(m):
            dp[1][i] = seg_cost(0.0, (cand[i][0] + cand[i][1]) / 2, 0) + sil_bonus(cand[i])
        for k in range(2, n):
            for i in range(m):
                mid_i = (cand[i][0] + cand[i][1]) / 2
                best, arg = INF, -1
                for j in range(i):
                    if dp[k - 1][j] >= INF:
                        continue
                    mid_j = (cand[j][0] + cand[j][1]) / 2
                    c = dp[k - 1][j] + seg_cost(mid_j, mid_i, k - 1)
                    if c < best:
                        best, arg = c, j
                if arg >= 0:
                    dp[k][i] = best + sil_bonus(cand[i]); bk[k][i] = arg
        best, arg = INF, -1
        for i in range(m):
            if dp[n - 1][i] >= INF:
                continue
            c = dp[n - 1][i] + seg_cost((cand[i][0] + cand[i][1]) / 2, dur, n - 1)
            if c < best:
                best, arg = c, i
        sel = []
        k = n - 1
        while k >= 1 and arg >= 0:
            sel.append(cand[arg]); arg = bk[k][arg]; k -= 1
        cuts = sorted(sel)
    margin = None
    if n > 1:
        chosen_min = min(c[1] - c[0] for c in cuts)
        rest = [c[1] - c[0] for c in internal if c not in cuts]
        margin = (round(chosen_min, 2), round(max(rest), 2) if rest else 0.0)
    bounds = [0.0] + [((a + b) / 2) for a, b in cuts] + [dur]
    res = []
    for k, i in enumerate(ids):
        a, b = bounds[k], bounds[k + 1]
        seg = x[int(a * SR):int(b * SR)]
        # обрезаем тишину по краям, оставляя 60 мс воздуха
        hop = int(0.01 * SR)
        m = len(seg) // hop
        e = 20 * np.log10(np.sqrt((seg[:m * hop].reshape(m, hop) ** 2).mean(1)) + 1e-9)
        loud = np.where(e > -40)[0]
        if len(loud):
            s0 = max(0, loud[0] * hop - int(0.06 * SR))
            s1 = min(len(seg), (loud[-1] + 1) * hop + int(0.12 * SR))
            seg = seg[s0:s1]
        # мягкие края против щелчков
        f = min(len(seg) // 4, int(0.008 * SR))
        if f > 0:
            seg[:f] *= np.linspace(0, 1, f)
            seg[-f:] *= np.linspace(1, 0, f)
        path = os.path.join(outdir, i + '.wav')
        save_wav(path, seg)
        chars = len(lines.clean(lines.L[i][1]))
        res.append(dict(id=i, dur=round(len(seg) / SR, 3), chars=chars, cps=round(chars / max(0.1, len(seg) / SR), 2)))
    return res, margin


if __name__ == '__main__':
    manifest = json.load(open(os.path.join(ROOT, 'build', 'voice_batches.json')))
    outdir = os.path.join(ROOT, 'build', 'voice')
    os.makedirs(outdir, exist_ok=True)
    report = {}
    rp = os.path.join(ROOT, 'build', 'voice_lines.json')
    if os.path.exists(rp):
        report = json.load(open(rp))
    for arg in sys.argv[1:]:
        k = int(arg.lstrip('B'))
        b = manifest[k]
        f = os.path.join(ROOT, 'build', 'voice_raw', 'B%d.mp3' % k)
        res, margin = split(f, b['ids'], outdir)
        print('B%d %s margin=%s' % (k, b['who'], margin))
        for r in res:
            flag = '  <-- ?' if not (6 <= r['cps'] <= 22) else ''
            print('   %-4s %5.2fs %3d ch %5.1f ch/s  %s%s' % (r['id'], r['dur'], r['chars'], r['cps'],
                                                       lines.clean(lines.L[r['id']][1])[:60], flag))
            report[r['id']] = r
    json.dump(report, open(rp, 'w'), ensure_ascii=False, indent=1)
