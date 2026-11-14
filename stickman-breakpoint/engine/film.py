# -*- coding: utf-8 -*-
"""Плёнка: шоты, таймлайн, рендер кадра (мультиплан + DOF + грейд + субтитры)."""
import math
import numpy as np
import gfx as skia
from core import *
from sets import Layer, draw_sky, pal
from stickman import Actor, draw_char

class Shot:
    def __init__(self, dur, tod='morning', layers=None, cam=None, name='', sky=True, rim=None,
                 grade=None, vignette=0.35, grain=0.025, letterbox=0.0, mblur=1, bg=None):
        self.dur = dur
        self.tod = tod
        self.layers = list(layers or [])
        self.actors = []
        self.cam = cam or (lambda t: Cam())
        self.name = name
        self.sky = sky
        self.rim = rim if rim is not None else hexc(pal(tod)['rim'])
        self.grade = grade or {}
        self.vignette = vignette
        self.grain = grain
        self.letterbox = letterbox
        self.screen_fx = []    # fn(cv, t) — поверх, экранные координаты
        self.pre_fx = []       # fn(cv, t) — под сценой (экран)
        self.world_fx = []     # Layer — мировые эффекты на глубине
        self.post = []         # fn(img_array, t) -> img_array (numpy пост-обработка)
        self.mblur = mblur     # число подкадров для motion blur
        self.mblur_ranges = [] # [(t0, t1, n)]
        self.bg = bg           # fn(cv, t) — экранный фон вместо неба
        self.actor_over = {}   # who -> fn(t) -> dict overrides
        self.start = 0.0

    def add(self, actor):
        self.actors.append(actor)
        return actor

    def layer(self, z, fn, name=''):
        self.layers.append(Layer(z, fn, name=name))

import cairo as _cairo
from PIL import Image as _Image, ImageFilter as _IF

_SMALL = {}
def _small_surface(f):
    key = (f, BASE[0])
    if key not in _SMALL:
        s = _cairo.ImageSurface(_cairo.FORMAT_ARGB32, max(1, int(W * f * BASE[0])), max(1, int(H * f * BASE[0])))
        _SMALL[key] = s
    return _SMALL[key]

_KEEP = []
def blur_surface(surf, sigma):
    w, h = surf.get_width(), surf.get_height()
    surf.flush()
    img = _Image.frombuffer('RGBA', (w, h), bytes(surf.get_data()), 'raw', 'RGBA', 0, 1)
    r = max(1, int(round(sigma * 1.1)))
    img = img.filter(_IF.BoxBlur(r)).filter(_IF.BoxBlur(max(1, r // 2 + 1)))
    out = bytearray(img.tobytes())
    s2 = _cairo.ImageSurface.create_for_data(out, _cairo.FORMAT_ARGB32, w, h, w * 4)
    _KEEP[:] = [out]
    return s2

def _draw_item(cv, shot, t, cam, z, kind, obj):
    cv.save()
    cam.apply(cv, z, t)
    if kind == 0:
        obj.draw(cv, t)
    else:
        over = shot.actor_over.get(obj.who)
        ov = over(t) if over else {}
        L = obj.state(t, **ov)
        if L.halo is None:
            L.halo = shot.rim
        draw_char(cv, L)
    cv.restore()

def _blur_of(cam, item):
    z, kind, obj = item
    b = cam.blur_for(z)
    if kind == 0 and getattr(obj, 'soft', 0):
        b = max(b, obj.soft)
    return b

def draw_world(cv, shot, t, cam):
    items = []
    for L in shot.layers + shot.world_fx:
        items.append((L.z, 0, L))
    for a in shot.actors:
        if getattr(a, 'hidden', None) and a.hidden(t):
            continue
        items.append((a.z, 1, a))
    items.sort(key=lambda it: (-it[0], it[1]))
    i = 0
    n = len(items)
    while i < n:
        z, kind, obj = items[i]
        b = _blur_of(cam, items[i])
        if b <= 0.7:
            _draw_item(cv, shot, t, cam, z, kind, obj)
            i += 1
            continue
        # серия соседних размытых слоёв с похожим радиусом -> один проход в пониженном разрешении
        run = [items[i]]
        j = i + 1
        while j < n:
            b2 = _blur_of(cam, items[j])
            if b2 > 0.7 and 0.4 * b <= b2 <= 2.5 * b:
                run.append(items[j]); j += 1
            else:
                break
        f = 0.5 if b < 2.5 else 0.25
        small = _small_surface(f)
        sctx = _cairo.Context(small)
        sctx.set_operator(_cairo.OPERATOR_CLEAR); sctx.paint(); sctx.set_operator(_cairo.OPERATOR_OVER)
        sctx.scale(f * BASE[0], f * BASE[0])
        scv = skia.Canvas(sctx, small)
        bs = 0.0
        for (z2, k2, o2) in run:
            _draw_item(scv, shot, t, cam, z2, k2, o2)
            bs += _blur_of(cam, (z2, k2, o2))
        bs /= len(run)
        bl = blur_surface(small, max(0.5, bs * f * BASE[0]))
        ctx = cv.ctx
        ctx.save(); ctx.identity_matrix()
        ctx.scale(1.0 / f, 1.0 / f)
        ctx.set_source_surface(bl, 0, 0)
        ctx.get_source().set_filter(_cairo.FILTER_BILINEAR)
        ctx.paint()
        ctx.restore()
        i = j

def apply_grade(cv, g, t):
    """Грейд: tint (цвет, сила, режим), duotone, invert, flash."""
    if not g:
        return
    if 'tint' in g:
        col, amt = g['tint'][0], g['tint'][1]
        mode = g['tint'][2] if len(g['tint']) > 2 else 'overlay'
        a = amt(t) if callable(amt) else amt
        if a > 0:
            p = P(calpha(col, a))
            p.setBlendMode({'overlay': skia.BlendMode.kOverlay, 'multiply': skia.BlendMode.kMultiply,
                            'screen': skia.BlendMode.kScreen, 'normal': skia.BlendMode.kSrcOver,
                            'color': skia.BlendMode.kColor, 'soft': skia.BlendMode.kSoftLight}[mode])
            cv.drawRect(skia.Rect(0, 0, W, H), p)
    if 'light' in g:
        # мягкий свет из угла: (x, y, r, color, alpha)
        x, y, r, col, a = g['light']
        p = rgrad_paint(x, y, r, [calpha(col, a), calpha(col, 0)])
        p.setBlendMode(skia.BlendMode.kScreen)
        cv.drawRect(skia.Rect(0, 0, W, H), p)

def duotone_filter(amount, dark=(0.08, 0.0, 0.02), light=(1.0, 0.25, 0.18), invert=True):
    """Цветовая матрица: инверсия яркости и перекраска в дуотон (красный/чёрный) — момент отката."""
    # luminance
    lr, lg, lb = 0.299, 0.587, 0.114
    s = -1.0 if invert else 1.0
    off = 1.0 if invert else 0.0
    m = []
    for c in range(3):
        d, l_ = dark[c], light[c]
        k = (l_ - d)
        m += [k * lr * s, k * lg * s, k * lb * s, 0, d + k * off]
    m += [0, 0, 0, 1, 0]
    ident = [1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0]
    mm = [lerp(a, b, amount) for a, b in zip(ident, m)]
    return skia.ColorFilters.Matrix(mm)

def color_matrix_np(cv, mm):
    arr = cv_array(cv)
    f = arr[..., :3].astype(np.float32)
    B, G, R = f[..., 0], f[..., 1], f[..., 2]
    out = np.empty_like(f)
    out[..., 2] = mm[0] * R + mm[1] * G + mm[2] * B + mm[4] * 255
    out[..., 1] = mm[5] * R + mm[6] * G + mm[7] * B + mm[9] * 255
    out[..., 0] = mm[10] * R + mm[11] * G + mm[12] * B + mm[14] * 255
    arr[..., :3] = np.clip(out, 0, 255).astype(np.uint8)
    cv.surface.mark_dirty()

def cv_array(cv):
    s = cv.surface
    s.flush()
    return np.ndarray((s.get_height(), s.get_width(), 4), np.uint8, s.get_data(), strides=(s.get_stride(), 4, 1))

def world_time(shot, t):
    tm = getattr(shot, 'timemap', None)
    if tm is not None:
        return tm(t)
    fr = getattr(shot, 'freeze', None)
    if fr is not None:
        a, b = fr
        if t < a:
            return t
        if t <= b:
            return a
        return t - (b - a)
    return t

def render_shot(cv, shot, t):
    tw = world_time(shot, t)
    cam = shot.cam(tw)
    cv.clear(skia.ColorBLACK)
    duo = shot.grade.get('duotone')
    duo_a = duo(t) if callable(duo) else (duo or 0.0)
    if shot.bg is not None:
        shot.bg(cv, t)
    elif shot.sky:
        draw_sky(cv, shot.tod, tw, cam)
    for f in shot.pre_fx:
        f(cv, t)
    draw_world(cv, shot, tw, cam)
    apply_grade(cv, shot.grade, t)
    if duo_a > 0.001:
        color_matrix_np(cv, duotone_filter(duo_a)[1])
    for f in shot.screen_fx:
        f(cv, t)
    if shot.vignette > 0:
        draw_vignette(cv, shot.vignette)
    lb = shot.letterbox(t) if callable(shot.letterbox) else shot.letterbox
    letterbox(cv, lb)
    if shot.grain > 0:
        draw_grain(cv, t, shot.grain)

class Timeline:
    def __init__(self):
        self.shots = []
        self.audio = []      # dict(kind, file, t, gain, ...)
        self.subs = []       # (t0, t1, speaker, text, style)
        self.notes = []      # (t, scene_id, text) для сценария
        self.overlays = []   # (t0, t1, fn(cv, tl)) глобальные экранные оверлеи (переходы)
        self.t = 0.0

    def append(self, shot):
        shot.start = self.t
        self.shots.append(shot)
        self.t += shot.dur
        return shot

    @property
    def duration(self):
        return self.t

    def shot_at(self, T):
        lo, hi = 0, len(self.shots) - 1
        while lo < hi:
            mid = (lo + hi + 1) // 2
            if self.shots[mid].start <= T:
                lo = mid
            else:
                hi = mid - 1
        return self.shots[lo]

SUB_FONT = 'Inter-SemiBold'
SUB_FONT_I = 'Inter-SemiBoldItalic'

def wrap(text, fnt, maxw):
    words = text.split(' ')
    lines_, cur = [], ''
    for w_ in words:
        tryl = (cur + ' ' + w_).strip()
        if fnt.measureText(tryl) <= maxw:
            cur = tryl
        else:
            if cur:
                lines_.append(cur)
            cur = w_
    if cur:
        lines_.append(cur)
    return lines_

def draw_subs(cv, tl, T):
    active = [s for s in tl.subs if s[0] <= T < s[1]]
    if not active:
        return
    y = H - 70
    for (t0, t1, who, text, style) in active[-2:][::-1]:
        fnt = font(SUB_FONT_I if style == 'vo' else SUB_FONT, 40)
        a = clamp((T - t0) / 0.12) * clamp((t1 - T) / 0.12)
        ls = wrap(text, fnt, W * 0.72)
        for ln in ls[::-1]:
            draw_text(cv, ln, W / 2, y, fnt, rgba(1, 1, 1, a), 'center', stroke=rgba(0, 0, 0, 0.85 * a), stroke_w=7,
                      shadow=(rgba(0, 0, 0, 0.5 * a), 0, 3, 4))
            y -= 50
        y -= 10

def render_frame(cv, tl, T, subs=True):
    shot = tl.shot_at(T)
    t = T - shot.start
    render_shot(cv, shot, t)
    for (t0, t1, fn) in tl.overlays:
        if t0 <= T < t1:
            fn(cv, T)
    if subs:
        draw_subs(cv, tl, T)
