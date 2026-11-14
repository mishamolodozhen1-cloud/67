# -*- coding: utf-8 -*-
"""Сведение звука серии: голоса (с обработкой), SFX, эмбиенты, музыка с даккингом под речь."""
import os, subprocess, functools, math
import numpy as np
from scipy import signal

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SR = 48000
SFX_DIR = os.path.join(ROOT, 'build', 'sfx_src')

def db(x):
    return 10 ** (x / 20.0)

@functools.lru_cache(None)
def load(path):
    raw = subprocess.run(['ffmpeg', '-v', 'quiet', '-i', path, '-ac', '2', '-ar', str(SR), '-f', 'f32le', '-'],
                         capture_output=True, check=True).stdout
    x = np.frombuffer(raw, np.float32).reshape(-1, 2).copy()
    return x

def rms(x):
    return float(np.sqrt(np.mean(x.astype(np.float64) ** 2) + 1e-12))

def norm_rms(x, target_db):
    r = rms(x)
    return x * (db(target_db) / max(r, 1e-6))

def norm_peak(x, target_db=-3.0):
    p = float(np.max(np.abs(x)) + 1e-9)
    return x * (db(target_db) / p)

def lowpass(x, f, order=4):
    sos = signal.butter(order, f, 'low', fs=SR, output='sos')
    return signal.sosfilt(sos, x, axis=0).astype(np.float32)

def highpass(x, f, order=2):
    sos = signal.butter(order, f, 'high', fs=SR, output='sos')
    return signal.sosfilt(sos, x, axis=0).astype(np.float32)

@functools.lru_cache(None)
def ir(t60, seed=1, predelay=0.012):
    n = int(SR * t60 * 1.2)
    rng = np.random.default_rng(seed)
    t = np.arange(n) / SR
    env = np.exp(-6.9 * t / t60)
    l = rng.normal(0, 1, n) * env
    r = rng.normal(0, 1, n) * env
    h = np.zeros((n + int(predelay * SR), 2), np.float32)
    h[int(predelay * SR):, 0] = l
    h[int(predelay * SR):, 1] = r
    h = lowpass(h, 6000, 2)
    h /= np.sqrt(np.sum(h ** 2, axis=0, keepdims=True)) + 1e-9
    return h

def reverb(x, t60=1.0, wet=0.3):
    h = ir(round(t60, 2))
    y = np.stack([signal.fftconvolve(x[:, c], h[:, c]) for c in range(2)], 1).astype(np.float32)
    out = np.zeros_like(y)
    out[:len(x)] += x * (1 - wet)
    out += y * wet
    return out

def fades(x, fi=0.005, fo=0.01):
    n = len(x)
    a = min(n // 2, int(fi * SR)); b = min(n // 2, int(fo * SR))
    if a > 0:
        x[:a] *= np.linspace(0, 1, a)[:, None]
    if b > 0:
        x[-b:] *= np.linspace(1, 0, b)[:, None]
    return x

def loop_to(x, n, xfade=0.4):
    """Зацикливает x до длины n с кроссфейдом стыков."""
    if len(x) >= n:
        return x[:n].copy()
    xf = int(min(xfade * SR, len(x) // 4))
    out = np.zeros((n, 2), np.float32)
    pos = 0
    first = True
    while pos < n:
        seg = x.copy()
        if not first and xf > 0:
            seg[:xf] *= np.linspace(0, 1, xf)[:, None]
        if xf > 0:
            seg[-xf:] *= np.linspace(1, 0, xf)[:, None]
        m = min(len(seg), n - pos)
        out[pos:pos + m] += seg[:m]
        pos += len(seg) - xf
        first = False
    return out

# ─────────────────────────── процедурные звуки ───────────────────────────
def proc_heartbeat():
    t = np.arange(int(0.6 * SR)) / SR
    def thump(t0, f, a):
        u = np.clip(t - t0, 0, None)
        return a * np.sin(2 * np.pi * f * u * (1 - 0.3 * u)) * np.exp(-u * 18) * (t >= t0)
    y = thump(0.0, 52, 1.0) + thump(0.16, 46, 0.7)
    y = y + 0.15 * np.random.default_rng(3).normal(0, 1, len(t)) * np.exp(-t * 40)
    x = np.stack([y, y], 1).astype(np.float32)
    return norm_peak(lowpass(x, 400), -2)

def proc_tinnitus(d=3.5):
    t = np.arange(int(d * SR)) / SR
    y = np.sin(2 * np.pi * 6800 * t) * 0.6 + np.sin(2 * np.pi * 7300 * t) * 0.3
    env = np.minimum(1, t / 0.8) * np.minimum(1, (d - t) / 1.2)
    x = np.stack([y * env, y * env * 0.9], 1).astype(np.float32)
    return norm_peak(x, -18)

# ─────────────────────────── таблица звуков ───────────────────────────
A = 'amb'
S = {
    # name: (src, kind, opts)
    'alarm_clock': ('alarm_clock', 's', {}),
    'amb_bridge_fog': ('amb_beach', A, dict(lp=900, extra=('wind', 0.5))),
    'amb_city_far': ('amb_night', A, dict(lp=2500)),
    'amb_harbor': ('amb_beach', A, {}),
    'amb_night': ('amb_night', A, {}),
    'amb_room_night': ('amb_kitchen', A, dict(lp=3000)),
    'amb_street_eve': ('amb_night', A, {}),
    'amb_water_eve': ('amb_beach', A, dict(lp=2200)),
    'ball_block': ('thud', 's', dict(rate=1.3)),
    'beep_alert': ('beep_alert', 's', {}),
    'boom_deep': ('impact_title', 's', dict(lp=1500)),
    'bus_brake': ('bus_pass', 's', dict(seg=(2.5, 4.5))),
    'bus_horn': ('bus_horn', 's', {}),
    'bus_interior': ('bus_interior', A, {}),
    'bus_pass': ('bus_pass', 's', {}),
    'card_whoosh': ('whoosh', 's', {}),
    'cart_wobble': ('thud', 's', dict(rate=1.6, g=0.4)),
    'catch': ('catch', 's', {}),
    'chalk_snap': ('chalk_snap', 's', {}),
    'chalk_write': ('chalk_write', 's', {}),
    'class_amb': ('amb_hallway', A, dict(lp=4000)),
    'class_laugh': ('class_laugh', 's', {}),
    'class_laugh_small': ('class_laugh', 's', dict(g=0.5)),
    'class_ooh': ('class_ooh', 's', {}),
    'click': ('switch_click', 's', {}),
    'click_breakpoint': ('click_breakpoint', 's', {}),
    'clock_tick': ('clock_tick', A, {}),
    'clock_tick_loud': ('clock_tick', 's', dict(seg=(0.0, 0.45))),
    'cloth_grab': ('shove', 's', dict(g=0.6, rate=1.2)),
    'corridor_amb': ('amb_hallway', A, {}),
    'crack_big': ('crack', 's', {}),
    'crack_small': ('crack', 's', dict(g=0.6)),
    'door_close': ('door_close', 's', {}),
    'door_hiss': ('door_hiss', 's', {}),
    'door_slam': ('door_close', 's', dict(g=1.2)),
    'drone_menace': ('drone_menace', 's', {}),
    'eyecatch_sting': ('eyecatch_sting', 's', {}),
    'face_switch': ('sting_subtle', 's', {}),
    'ferry_horn': ('ferry_horn', 's', {}),
    'fist_clench': ('shove', 's', dict(g=0.4, rate=1.5)),
    'glass_shatter': ('glass_shatter', 's', {}),
    'glint': ('glint', 's', {}),
    'gull_call': ('gulls', 's', dict(seg=(3.0, 6.0))),
    'gull_flap': ('paper_flutter', 's', dict(rate=0.8)),
    'gulls': ('gulls', A, {}),
    'gym_amb': ('gym_amb', A, {}),
    'heartbeat': ('@heartbeat', 's', {}),
    'holo_blip': ('beep_alert', 's', dict(g=0.5, rate=1.3)),
    'hum_low': ('lab_hum', A, dict(lp=600)),
    'impact_title': ('impact_title', 's', {}),
    'kettle': ('kettle', 's', {}),
    'kitchen_amb': ('amb_kitchen', A, {}),
    'kitchen_eve': ('amb_kitchen', A, {}),
    'lab_hum': ('lab_hum', A, {}),
    'lamp_buzz': ('lamp_buzz', 's', {}),
    'library_amb': ('amb_kitchen', A, dict(lp=1500, g=0.6)),
    'page_flip': ('page_flip', 's', {}),
    'paper_crumple': ('paper_flutter', 's', dict(rate=1.3)),
    'paper_flutter': ('paper_flutter', 's', {}),
    'pen_underline': ('pen_write', 's', dict(seg=(0.0, 0.9))),
    'pen_write': ('pen_write', 's', {}),
    'pencil_snap': ('pencil_snap', 's', {}),
    'pencil_tick': ('pencil_snap', 's', dict(g=0.5, rate=1.4)),
    'phone_hangup': ('beep_alert', 's', dict(seg=(0.0, 0.3), g=0.4)),
    'phone_on': ('glint', 's', dict(g=0.7)),
    'preview_sting': ('eyecatch_sting', 's', {}),
    'rewind_whoosh': ('rewind_whoosh', 's', {}),
    'room_morning': ('gulls', A, dict(lp=2500, g=0.6)),
    'run_steps': ('run_steps', 's', {}),
    'school_bell': ('school_bell', 's', {}),
    'shatter_reverse': ('glass_shatter', 's', dict(rev=True)),
    'shatter_reverse_soft': ('glass_shatter', 's', dict(rev=True, g=0.5, lp=3000)),
    'shove': ('shove', 's', {}),
    'slap': ('catch', 's', dict(g=1.2)),
    'slap_back': ('catch', 's', dict(g=1.3, rate=0.9)),
    'slide_flop': ('thud', 's', {}),
    'sneaker_squeak': ('gym_amb', 's', dict(seg=(0.0, 0.8))),
    'snore': ('snore', 's', {}),
    'spoon_clink': ('spoon_clink', 's', {}),
    'steps_room': ('steps_walk', 's', dict(lp=2500, g=0.7)),
    'steps_stairs': ('steps_walk', 's', dict(rate=1.15)),
    'steps_walk': ('steps_walk', 's', {}),
    'sting_subtle': ('sting_subtle', 's', {}),
    'swipe': ('whoosh', 's', dict(rate=1.3, g=0.7)),
    'switch_click': ('switch_click', 's', {}),
    'thud': ('thud', 's', {}),
    'tick_mark': ('switch_click', 's', dict(rate=1.6, g=0.6)),
    'time_slow': ('rewind_whoosh', 's', dict(rate=0.55, rev=True)),
    'tinnitus': ('@tinnitus', 's', {}),
    'whoosh_big': ('whoosh', 's', dict(rate=0.75, g=1.2)),
    'whoosh_small': ('whoosh', 's', {}),
    'wind_roof': ('wind', A, {}),
    'wind_soft': ('wind', A, dict(lp=1200, g=0.7)),
    'zoom_whoosh': ('rewind_whoosh', 's', {}),
}
SILENT = {'laugh_leon', 'music_cut', 'record_scratch_soft', 'yawn_stretch', 'eat_fast'}

@functools.lru_cache(None)
def source(name):
    src, kind, o = S[name]
    if src == '@heartbeat':
        x = proc_heartbeat()
    elif src == '@tinnitus':
        x = proc_tinnitus()
    else:
        x = load(os.path.join(SFX_DIR, src + '.wav'))
    if 'seg' in o:
        a, b = o['seg']
        x = x[int(a * SR):int(b * SR)]
    if o.get('rate', 1.0) != 1.0:
        r = o['rate']
        n = int(len(x) / r)
        idx = np.linspace(0, len(x) - 1, n)
        x = np.stack([np.interp(idx, np.arange(len(x)), x[:, c]) for c in range(2)], 1).astype(np.float32)
    if o.get('rev'):
        x = x[::-1].copy()
    if o.get('lp'):
        x = lowpass(x, o['lp'])
    if kind == A:
        x = norm_rms(x, -27.0)
    else:
        x = norm_peak(x, -4.0)
    x = x * o.get('g', 1.0)
    return fades(x.astype(np.float32), 0.004, 0.02)

AMB_NAMES = {k for k, v in S.items() if v[1] == A}

def voice_fx(x, fx):
    if not fx:
        return x
    if fx == 'muffled':
        return lowpass(x, 1600) * 0.9
    if fx == 'room_far':
        y = highpass(lowpass(x, 3200), 220)
        return reverb(y, 0.6, 0.35) * 0.75
    if fx == 'hall':
        return reverb(lowpass(x, 7500), 2.4, 0.42) * 0.95
    if fx == 'whisper_close':
        return reverb(x, 0.35, 0.12) * 1.15
    if fx == 'tv':
        y = highpass(lowpass(x, 3400), 380)
        y = np.tanh(y * 3.0) / 3.0
        return reverb(norm_rms(y, -22), 0.4, 0.2) * 0.8
    return x

def build_mix(ep, out_path, music_root=ROOT):
    total = int(math.ceil(ep.duration * SR)) + SR
    voice = np.zeros((total, 2), np.float32)
    sfx = np.zeros((total, 2), np.float32)
    amb = np.zeros((total, 2), np.float32)
    music = np.zeros((total, 2), np.float32)
    # ── голоса ──
    for e in ep.audio:
        if e['kind'] != 'voice':
            continue
        p = os.path.join(ROOT, 'build', 'voice', e['lid'] + '.wav')
        if not os.path.exists(p):
            continue
        x = norm_rms(load(p), -20.0) * e.get('gain', 1.0)
        x = voice_fx(x, e.get('fx'))
        x = fades(x.copy(), 0.004, 0.03)
        i = int(e['t'] * SR)
        n = min(len(x), total - i)
        if n > 0:
            voice[i:i + n] += x[:n]
    # ── эмбиенты (слияние соседних одноимённых по стыкам шотов) ──
    ambs = []
    for e in sorted([e for e in ep.audio if e['kind'] == 'sfx' and e['name'] in AMB_NAMES], key=lambda e: e['t']):
        end = e['t'] + e['dur'] if e.get('dur') else e.get('shot_end', e['t'] + 10)
        merged = False
        for m in ambs:
            if m['name'] == e['name'] and abs(m['end'] - e['t']) < 0.08 and abs(m['gain'] - e.get('gain', 1.0)) < 0.25:
                m['end'] = end; merged = True; break
        if not merged:
            ambs.append(dict(name=e['name'], t=e['t'], end=end, gain=e.get('gain', 1.0)))
    for k, m in enumerate(ambs):
        src = source(m['name'])
        n = int((m['end'] - m['t']) * SR)
        if n <= 0:
            continue
        off = int((hash(m['name']) % 997) / 997 * max(1, len(src) - 1))
        rolled = np.roll(src, -off, axis=0)
        x = loop_to(rolled, n) * m['gain']
        extra = S[m['name']][2].get('extra')
        if extra:
            x2 = loop_to(norm_rms(load(os.path.join(SFX_DIR, extra[0] + '.wav')), -27.0), n) * extra[1] * m['gain']
            x = x + x2
        x = fades(x, 0.35, 0.35)
        i = int(m['t'] * SR)
        n2 = min(n, total - i)
        amb[i:i + n2] += x[:n2]
    # ── короткие SFX ──
    for e in ep.audio:
        if e['kind'] != 'sfx' or e['name'] in AMB_NAMES or e['name'] in SILENT:
            continue
        if e.get('gain', 1.0) <= 0:
            continue
        if e['name'] not in S:
            print('WARN no sfx', e['name'])
            continue
        x = source(e['name'])
        if e.get('dur'):
            n = int(e['dur'] * SR)
            x = loop_to(x, n) if len(x) < n else x[:n].copy()
            x = fades(x, 0.01, e.get('fade', 0.3))
        x = x * e.get('gain', 1.0)
        i = int(e['t'] * SR)
        if i < 0:
            x = x[-i:]; i = 0
        n = min(len(x), total - i)
        if n > 0:
            sfx[i:i + n] += x[:n]
    # ── музыка ──
    for c in sorted(ep.music, key=lambda c: c['t0']):
        if c['gain'] <= 0:
            continue
        t1 = c['t1'] if c['t1'] is not None else ep.duration
        n = int((t1 - c['t0']) * SR)
        if n <= 0:
            continue
        src = load(os.path.join(music_root, c['file']))
        src = norm_rms(src, -19.0)
        off = int(c.get('offset', 0.0) * SR)
        if c.get('loop', True):
            x = loop_to(src[off:], n, xfade=0.05)
        else:
            x = src[off:off + n].copy()
            if len(x) < n:
                x = np.concatenate([x, np.zeros((n - len(x), 2), np.float32)])
        fi, fo = c.get('fade_in', 1.0), c.get('fade_out', 1.5)
        x = fades(x, max(0.005, fi), max(0.005, fo)) * c['gain']
        i = int(c['t0'] * SR)
        n2 = min(n, total - i)
        music[i:i + n2] += x[:n2]
        c['_duck'] = c.get('duck', True)
    # ── даккинг под речь ──
    env = np.abs(voice).max(axis=1)
    win = int(0.02 * SR)
    env = np.convolve(env, np.ones(win) / win, 'same')
    # атака 40 мс, отпускание 450 мс (одно-полюсные)
    a_att = math.exp(-1 / (0.04 * SR)); a_rel = math.exp(-1 / (0.45 * SR))
    k = np.clip(env / 0.03, 0, 1).astype(np.float32)
    # быстрая реализация огибающей: по блокам 10 мс
    blk = int(0.01 * SR)
    nb = len(k) // blk
    kb = k[:nb * blk].reshape(nb, blk).max(1)
    g = np.zeros(nb, np.float32); s = 0.0
    aa = math.exp(-1 / 4.0); ar = math.exp(-1 / 45.0)
    for i in range(nb):
        v = kb[i]
        s = (aa * s + (1 - aa) * v) if v > s else (ar * s + (1 - ar) * v)
        g[i] = s
    gl = np.repeat(g, blk)
    gl = np.concatenate([gl, np.full(len(k) - len(gl), gl[-1] if len(gl) else 0)])
    music_duck = 1.0 - 0.5 * gl          # до −6 дБ
    amb_duck = 1.0 - 0.3 * gl
    # опенинг/эндинг не дакаются
    nod = np.zeros(len(gl), bool)
    for c in ep.music:
        if not c.get('duck', True):
            i0 = int(c['t0'] * SR); i1 = int((c['t1'] if c['t1'] else ep.duration) * SR)
            nod[i0:i1] = True
    music_duck[nod] = 1.0
    music *= music_duck[:, None]
    amb *= amb_duck[:, None]
    # ── «вата» в ушах (слоумо на мосту) ──
    for (a, b) in getattr(ep, 'muffles', []):
        i0, i1 = int(a * SR), int(b * SR)
        for bus in (music, amb, sfx):
            seg = bus[i0:i1].copy()
            f = lowpass(seg, 700)
            w = np.ones(len(seg), np.float32)
            r = min(len(seg) // 4, int(0.3 * SR))
            if r > 0:
                w[:r] = np.linspace(0, 1, r); w[-r:] = np.linspace(1, 0, r)
            bus[i0:i1] = seg * (1 - w[:, None]) + f * w[:, None] * 0.7
    mix = voice + sfx * 0.9 + amb * 0.8 + music
    # мягкий лимитер
    peak = float(np.max(np.abs(mix)))
    mix = np.tanh(mix * 1.15) / 1.15 if peak > 0.9 else mix
    mix = mix[:int(ep.duration * SR)]
    pcm = (np.clip(mix, -1, 1) * 32767).astype(np.int16)
    p = subprocess.Popen(['ffmpeg', '-v', 'quiet', '-y', '-f', 's16le', '-ar', str(SR), '-ac', '2', '-i', '-', out_path], stdin=subprocess.PIPE)
    p.communicate(pcm.tobytes())
    stems = dict(voice=voice, sfx=sfx, amb=amb, music=music)
    return {k: float(20 * np.log10(rms(v[:int(ep.duration * SR)]) + 1e-9)) for k, v in stems.items()}
