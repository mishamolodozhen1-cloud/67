# -*- coding: utf-8 -*-
"""Ядро движка STICKMAN: BREAKPOINT: математика, кривые, шрифты, камера, кисти."""
import math, os, random, functools
import numpy as np
import gfx as skia

W, H = 1920, 1080
FPS = 60
BASE = [1.0]   # масштаб вывода (1.0 = 1080p; 0.5 = черновик 540p)

def base_matrix(ctx):
    ctx.identity_matrix()
    if BASE[0] != 1.0:
        ctx.scale(BASE[0], BASE[0])
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
FONT_DIR = os.path.join(ROOT, 'assets', 'fonts')

# ─────────────────────────── math ───────────────────────────
def clamp(x, a=0.0, b=1.0):
    return a if x < a else b if x > b else x

def lerp(a, b, t):
    return a + (b - a) * t

def remap(x, a, b, c=0.0, d=1.0):
    if b == a:
        return d
    return c + (d - c) * clamp((x - a) / (b - a))

def smooth(t):
    t = clamp(t); return t * t * (3 - 2 * t)

def smoother(t):
    t = clamp(t); return t * t * t * (t * (t * 6 - 15) + 10)

def ease_in(t, p=2.0):
    return clamp(t) ** p

def ease_out(t, p=2.0):
    return 1 - (1 - clamp(t)) ** p

def ease_io(t, p=2.0):
    t = clamp(t)
    return 0.5 * (2 * t) ** p if t < 0.5 else 1 - 0.5 * (2 * (1 - t)) ** p

def back_out(t, s=1.70158):
    t = clamp(t) - 1
    return t * t * ((s + 1) * t + s) + 1

def elastic_out(t):
    t = clamp(t)
    if t in (0.0, 1.0):
        return t
    return 2 ** (-10 * t) * math.sin((t * 10 - 0.75) * (2 * math.pi) / 3) + 1

EASES = {'lin': lambda t: clamp(t), 'smooth': smooth, 'smoother': smoother, 'in': ease_in, 'out': ease_out,
         'io': ease_io, 'back': back_out, 'elastic': elastic_out,
         'in3': lambda t: ease_in(t, 3), 'out3': lambda t: ease_out(t, 3), 'io3': lambda t: ease_io(t, 3),
         'hold': lambda t: 0.0 if t < 1 else 1.0}

def hash01(*a):
    h = 2166136261
    for v in a:
        for ch in str(v):
            h = ((h ^ ord(ch)) * 16777619) & 0xffffffff
    return (h & 0xffffff) / float(0xffffff)

def vnoise(x, seed=0):
    """1D value noise, плавный, детерминированный."""
    i = math.floor(x); f = x - i
    a = hash01(seed, i); b = hash01(seed, i + 1)
    return lerp(a, b, smooth(f)) * 2 - 1

def fbm(x, seed=0, oct=3):
    s, amp, fr = 0.0, 1.0, 1.0
    for k in range(oct):
        s += amp * vnoise(x * fr, seed + k * 17); amp *= 0.5; fr *= 2.0
    return s / 1.75

# ─────────────────────────── tracks ───────────────────────────
class Track:
    """Ключевые кадры: [(t, value, ease_to_next?)]. Значения — числа, кортежи или dict чисел."""
    def __init__(self, keys, default_ease='io'):
        self.keys = sorted(keys, key=lambda k: k[0])
        self.default_ease = default_ease

    def __call__(self, t):
        ks = self.keys
        if t <= ks[0][0]:
            return ks[0][1]
        if t >= ks[-1][0]:
            return ks[-1][1]
        for i in range(len(ks) - 1):
            t0, v0 = ks[i][0], ks[i][1]
            t1, v1 = ks[i + 1][0], ks[i + 1][1]
            if t0 <= t <= t1:
                e = ks[i + 1][2] if len(ks[i + 1]) > 2 else self.default_ease
                u = EASES[e]((t - t0) / max(1e-9, t1 - t0))
                return mix(v0, v1, u)
        return ks[-1][1]

def mix(a, b, u):
    if isinstance(a, dict):
        out = dict(a)
        for k, vb in b.items():
            va = a.get(k, vb)
            out[k] = mix(va, vb, u)
        return out
    if isinstance(a, (tuple, list)):
        return type(a)(mix(x, y, u) for x, y in zip(a, b))
    if isinstance(a, (int, float)) and isinstance(b, (int, float)):
        return a + (b - a) * u
    return b if u >= 0.5 else a

# ─────────────────────────── colors ───────────────────────────
def hexc(h, a=1.0):
    h = h.lstrip('#')
    r, g, b = int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)
    return skia.Color4f(r / 255, g / 255, b / 255, a)

def rgba(r, g, b, a=1.0):
    return skia.Color4f(r, g, b, a)

def cmix(c1, c2, u):
    return skia.Color4f(lerp(c1.fR, c2.fR, u), lerp(c1.fG, c2.fG, u), lerp(c1.fB, c2.fB, u), lerp(c1.fA, c2.fA, u))

def calpha(c, a):
    return skia.Color4f(c.fR, c.fG, c.fB, c.fA * a)

def c4(c):
    return c.toColor()

INK = hexc('#16131a')
PAPER = hexc('#f3efe6')
RED = hexc('#e8402f')
ORANGE = hexc('#ff9a1f')
VIOLET = hexc('#8a5cf6')
CYAN = hexc('#33e1ff')
VBLUE = hexc('#2f7bff')

# ─────────────────────────── fonts ───────────────────────────
@functools.lru_cache(None)
def typeface(name):
    return skia.Typeface(name)

@functools.lru_cache(None)
def font(name, size):
    return skia.Font(typeface(name), size)

def text_width(txt, fnt):
    return fnt.measureText(txt)

def draw_text(cv, txt, x, y, fnt, color, align='left', stroke=None, stroke_w=0, shadow=None, tracking=0.0):
    """Текст с выравниванием, обводкой и тенью. tracking — доп. интервал в px между буквами."""
    if tracking:
        w = sum(fnt.measureText(ch) for ch in txt) + tracking * (len(txt) - 1)
    else:
        w = fnt.measureText(txt)
    if align == 'center':
        x -= w / 2
    elif align == 'right':
        x -= w
    def run(paint, dx=0, dy=0):
        if tracking:
            xx = x + dx
            for ch in txt:
                cv.drawString(ch, xx, y + dy, fnt, paint)
                xx += fnt.measureText(ch) + tracking
        else:
            cv.drawString(txt, x + dx, y + dy, fnt, paint)
    if shadow is not None:
        sp = skia.Paint(AntiAlias=True, Color4f=shadow[0])
        sp.setMaskFilter(skia.MaskFilter.MakeBlur(skia.kNormal_BlurStyle, shadow[3]))
        run(sp, shadow[1], shadow[2])
    if stroke is not None and stroke_w > 0:
        p = skia.Paint(AntiAlias=True, Color4f=stroke, Style=skia.Paint.kStroke_Style, StrokeWidth=stroke_w,
                       StrokeJoin=skia.Paint.kRound_Join)
        run(p)
    p = skia.Paint(AntiAlias=True, Color4f=color)
    run(p)
    return w

# ─────────────────────────── paint helpers ───────────────────────────
def P(color, w=None, cap='round', alpha=None, blur=None):
    p = skia.Paint(AntiAlias=True)
    p.setColor4f(color if alpha is None else calpha(color, alpha))
    if w is not None:
        p.setStyle(skia.Paint.kStroke_Style)
        p.setStrokeWidth(w)
        p.setStrokeCap(skia.Paint.kRound_Cap if cap == 'round' else skia.Paint.kButt_Cap)
        p.setStrokeJoin(skia.Paint.kRound_Join)
    if blur:
        p.setMaskFilter(skia.MaskFilter.MakeBlur(skia.kNormal_BlurStyle, blur))
    return p

def line(cv, a, b, paint):
    cv.drawLine(a[0], a[1], b[0], b[1], paint)

def poly(pts, close=True):
    path = skia.Path()
    path.moveTo(*pts[0])
    for p in pts[1:]:
        path.lineTo(*p)
    if close:
        path.close()
    return path

def smooth_path(pts, close=False):
    """Catmull-Rom → кубические Безье."""
    path = skia.Path()
    n = len(pts)
    if n < 2:
        return path
    path.moveTo(*pts[0])
    P_ = list(pts)
    if close:
        P_ = [pts[-1]] + list(pts) + [pts[0], pts[1]]
    else:
        P_ = [pts[0]] + list(pts) + [pts[-1]]
    for i in range(1, len(P_) - 2):
        p0, p1, p2, p3 = P_[i - 1], P_[i], P_[i + 1], P_[i + 2]
        c1 = (p1[0] + (p2[0] - p0[0]) / 6, p1[1] + (p2[1] - p0[1]) / 6)
        c2 = (p2[0] - (p3[0] - p1[0]) / 6, p2[1] - (p3[1] - p1[1]) / 6)
        path.cubicTo(c1[0], c1[1], c2[0], c2[1], p2[0], p2[1])
    if close:
        path.close()
    return path

def vgrad(cv, rect, stops, positions=None):
    x0, y0, x1, y1 = rect
    sh = skia.GradientShader.MakeLinear([skia.Point(x0, y0), skia.Point(x0, y1)], [c4(c) for c in stops], positions)
    p = skia.Paint(AntiAlias=True); p.setShader(sh)
    cv.drawRect(skia.Rect(x0, y0, x1, y1), p)

def rgrad_paint(cx, cy, r, stops, positions=None):
    sh = skia.GradientShader.MakeRadial(skia.Point(cx, cy), r, [c4(c) for c in stops], positions)
    p = skia.Paint(AntiAlias=True); p.setShader(sh)
    return p

# ─────────────────────────── camera ───────────────────────────
class Cam:
    """Мультиплановая камера. Мир: y вниз, земля y=0, рост персонажа ≈1.
    zoom — пикселей на единицу на плане z=0; D — расстояние камеры до плана z=0."""
    __slots__ = ('x', 'y', 'zoom', 'roll', 'D', 'focus', 'aperture', 'shake')

    def __init__(self, x=0.0, y=-0.6, zoom=520.0, roll=0.0, D=3.0, focus=0.0, aperture=0.0, shake=0.0):
        self.x, self.y, self.zoom, self.roll, self.D = x, y, zoom, roll, D
        self.focus, self.aperture, self.shake = focus, aperture, shake

    def scale(self, z):
        return self.zoom * self.D / max(0.05, z + self.D)

    def blur_for(self, z):
        if self.aperture <= 0:
            return 0.0
        k = abs(1.0 - (self.focus + self.D) / max(0.05, z + self.D))
        return self.aperture * k * 14.0

    def apply(self, cv, z, t=0.0):
        s = self.scale(z)
        cv.translate(W / 2, H / 2)
        if self.roll:
            cv.rotate(self.roll)
        sx = sy = 0.0
        if self.shake:
            sx = fbm(t * 9.0, 11) * self.shake * 30
            sy = fbm(t * 9.0, 23) * self.shake * 30
        cv.translate(sx, sy)
        cv.scale(s, s)
        cv.translate(-self.x, -self.y)
        return s

    def to_screen(self, x, y, z=0.0):
        s = self.scale(z)
        dx, dy = (x - self.x) * s, (y - self.y) * s
        if self.roll:
            c, sn = math.cos(math.radians(self.roll)), math.sin(math.radians(self.roll))
            dx, dy = dx * c - dy * sn, dx * sn + dy * c
        return W / 2 + dx, H / 2 + dy

def cam_track(keys, default_ease='io'):
    """keys: [(t, dict(x=..,y=..,zoom=..,roll=..,aperture=..,focus=..,shake=..)), ...]"""
    tr = Track(keys, default_ease)
    base = keys[0][1]
    def f(t):
        d = tr(t)
        c = Cam()
        for k, v in d.items():
            setattr(c, k, v)
        return c
    return f

# ─────────────────────────── grain / textures ───────────────────────────
import cairo as _cairo
@functools.lru_cache(None)
def grain_surface(seed=7, size=384):
    rng = np.random.default_rng(seed)
    n = rng.normal(0.0, 1.0, (size, size))
    a = (np.clip(np.abs(n) * 0.5, 0, 1) * 255).astype(np.uint8)
    v = np.where(n > 0, 255, 0).astype(np.uint8)
    pre = (v.astype(np.uint16) * a // 255).astype(np.uint8)
    arr = np.dstack([pre, pre, pre, a]).copy()
    surf = _cairo.ImageSurface.create_for_data(memoryview(arr), _cairo.FORMAT_ARGB32, size, size, size * 4)
    return surf, arr

def draw_grain(cv, t, amount=0.06):
    surf, _ = grain_surface()
    k = int(t * FPS) % 16
    ox, oy = (k * 137) % 384, (k * 251) % 384
    ctx = cv.ctx
    ctx.save(); base_matrix(ctx)
    pat = _cairo.SurfacePattern(surf)
    pat.set_extend(_cairo.EXTEND_REPEAT)
    m = _cairo.Matrix(); m.translate(ox, oy); pat.set_matrix(m)
    ctx.set_source(pat)
    ctx.paint_with_alpha(amount)
    ctx.restore()

_VIG = {}
def draw_vignette(cv, amount=0.45, color=None):
    key = round(amount, 2)
    if key not in _VIG:
        surf = skia.Surface(W, H)
        c2 = surf.getCanvas()
        col = rgba(0, 0, 0, 1)
        p = rgrad_paint(W / 2, H / 2, W * 0.75, [calpha(col, 0), calpha(col, 0), calpha(col, amount)], [0, 0.55, 1.0])
        c2.drawRect(skia.Rect(0, 0, W, H), p)
        _VIG[key] = surf
    ctx = cv.ctx
    ctx.save(); base_matrix(ctx)
    ctx.set_source_surface(_VIG[key].surf, 0, 0)
    ctx.paint()
    ctx.restore()

def letterbox(cv, amount):
    """Широкоэкранные шторки (0..1)."""
    if amount <= 0:
        return
    h = 135 * amount
    p = P(rgba(0, 0, 0, 1))
    cv.drawRect(skia.Rect(0, 0, W, h), p)
    cv.drawRect(skia.Rect(0, H - h, W, H), p)

class RNG:
    def __init__(self, seed):
        self.r = random.Random(seed)
    def u(self, a=0.0, b=1.0):
        return self.r.uniform(a, b)
    def i(self, a, b):
        return self.r.randint(a, b)
    def choice(self, s):
        return self.r.choice(s)
