# -*- coding: utf-8 -*-
"""Локации Нордена: многоплановые слои (z — глубина), время суток, анимация среды."""
import math
import gfx as skia
from core import *

# ─────────────────────────── палитры времени суток ───────────────────────────
TOD = {
    'night':  dict(sky=['#070b1c', '#141c3a', '#2a2c52'], sea=('#0b1430', '#060a18'), far='#141a33', mid='#0e1428',
                   near='#0a0f20', light='#ffd27a', fog='#4a5a8a', sun=None, moon=True, stars=True, rim='#5a78c8', win=0.55),
    'dawn':   dict(sky=['#2b3566', '#8a6a9a', '#f0a88a'], sea=('#4a5a86', '#2a3358'), far='#4a4f78', mid='#353a60',
                   near='#262a48', light='#ffe0a0', fog='#c8a8b8', sun=('#ffd6a0', 0.82), moon=False, stars=False, rim='#ffd0b0', win=0.25),
    'morning': dict(sky=['#6fa6d6', '#a9cbe6', '#e6eef0'], sea=('#5c8fb8', '#3d6d96'), far='#8aa6c0', mid='#6f88a3',
                    near='#566c85', light='#fff4d8', fog='#dfe9f0', sun=('#fff6dc', 0.25), moon=False, stars=False, rim='#ffffff', win=0.0),
    'noon':   dict(sky=['#4b8fd4', '#8cc0ea', '#d8ecf6'], sea=('#3f84bf', '#2b6aa0'), far='#7f9fc0', mid='#617f9f',
                   near='#4b6585', light='#ffffff', fog='#e8f2f8', sun=('#ffffff', 0.12), moon=False, stars=False, rim='#ffffff', win=0.0),
    'golden': dict(sky=['#3a4a8a', '#d9805a', '#ffc77a'], sea=('#c2805a', '#5a4a6a'), far='#7a5a78', mid='#5a4060',
                   near='#3e2c48', light='#ffd08a', fog='#f0b088', sun=('#ffe2a0', 0.7), moon=False, stars=False, rim='#ffcf8a', win=0.15),
    'dusk':   dict(sky=['#1a2048', '#4a3a6a', '#c86a6a'], sea=('#3a3a62', '#1a1c38'), far='#2e2c50', mid='#222240',
                   near='#181830', light='#ffc870', fog='#8a7aa0', sun=('#ff9a7a', 0.92), moon=False, stars=True, rim='#c8a0d0', win=0.45),
}

def pal(tod):
    return TOD[tod]

class Layer:
    __slots__ = ('z', 'fn', 'static', 'pic', 'blur', 'name', 'soft')
    def __init__(self, z, fn, static=False, blur=True, name='', soft=0.0):
        self.z, self.fn, self.static, self.blur, self.name = z, fn, static, blur, name
        self.pic = None
        self.soft = soft   # >0: слой всегда мягкий (рендер в 1/4 разрешения с размытием soft px)
    def draw(self, cv, t):
        if self.static:
            if self.pic is None:
                rec = skia.PictureRecorder()
                c2 = rec.beginRecording(skia.Rect(-1e5, -1e5, 1e5, 1e5))
                self.fn(c2, 0.0)
                self.pic = rec.finishRecordingAsPicture()
            cv.drawPicture(self.pic)
        else:
            self.fn(cv, t)

# ─────────────────────────── небо (экранное пространство) ───────────────────────────
_SKY = {}
def _sky_surface(tod):
    if tod not in _SKY:
        import cairo as _c
        p = pal(tod)
        surf = skia.Surface(W, H + 400)
        cv = surf.getCanvas()
        cv.translate(0, 200)
        vgrad(cv, (0, -200, W, H + 200), [hexc(c) for c in p['sky']], [0.0, 0.55, 1.0])
        if p['moon']:
            mx, my = W * 0.78, H * 0.2
            cv.drawCircle(mx, my, 150, P(hexc('#9fb2ff', 0.10), blur=60))
            cv.drawCircle(mx, my, 54, P(hexc('#f2f0e0')))
            cv.drawCircle(mx + 22, my - 12, 48, P(hexc(p['sky'][0], 0.88)))
        if p['sun']:
            col, yy = p['sun']
            sx, sy = W * 0.3, H * yy
            cv.drawCircle(sx, sy, 420, P(hexc(col, 0.22), blur=120))
            cv.drawCircle(sx, sy, 80, P(hexc(col, 0.9), blur=8))
        _SKY[tod] = surf
    return _SKY[tod]

def draw_sky(cv, tod, t, cam=None, tilt=0.0):
    p = pal(tod)
    off = 0.0
    if cam is not None:
        off = clamp((cam.y + 0.6) * 25, -150, 150)
    s = _sky_surface(tod)
    ctx = cv.ctx
    ctx.save(); base_matrix(ctx)
    ctx.set_source_surface(s.surf, 0, -200 + off * 0.2)
    ctx.paint()
    ctx.restore()
    if p['stars']:
        r = RNG(42)
        for i in range(160):
            x, y = r.u(0, W), r.u(0, H * 0.7)
            tw = 0.5 + 0.5 * math.sin(t * r.u(1, 3) + i)
            a = (0.25 + 0.6 * tw) * (1.0 if tod == 'night' else 0.35)
            cv.drawCircle(x, y + off * 0.05, r.u(0.6, 1.8), P(rgba(1, 1, 1, a)))

def draw_clouds(cv, tod, t, seed=3, y0=-9.0, span=60.0, alpha=0.5, speed=0.15, scale=1.0):
    p = pal(tod)
    base = {'night': '#2a3360', 'dawn': '#f2b8b0', 'morning': '#ffffff', 'noon': '#ffffff', 'golden': '#ffd2a8', 'dusk': '#8a6a98'}[tod]
    r = RNG(seed)
    for i in range(9):
        x = (r.u(-span, span) + t * speed * r.u(0.6, 1.4)) % (span * 2) - span
        y = y0 + r.u(-2.5, 2.5)
        w = r.u(5, 12) * scale
        col = hexc(base, alpha * r.u(0.5, 1.0))
        pnt = P(col, blur=0.6 * scale)
        for k in range(5):
            cx = x + (k - 2) * w * 0.22
            cy = y - abs(k - 2) * -0.25 * scale - (0.6 if k == 2 else 0) * scale
            cv.drawOval(skia.Rect(cx - w * 0.25, cy - w * 0.12, cx + w * 0.25, cy + w * 0.12), pnt)

# ─────────────────────────── город / панорама ───────────────────────────
def institute(cv, x, y, s, tod, t, pulse=0.5):
    """Институт «Вертекс»: кольцевое здание на холме с антенной."""
    p = pal(tod)
    col = hexc(p['far'])
    dark = cmix(col, hexc('#000000'), 0.35)
    # холм: основание на линии горизонта y, вершина выше на 6s
    hill = smooth_path([(x - 34 * s, y + 0.6 * s), (x - 20 * s, y - 1.6 * s), (x - 8 * s, y - 5.2 * s), (x, y - 6.0 * s),
                        (x + 9 * s, y - 5.0 * s), (x + 22 * s, y - 1.4 * s), (x + 36 * s, y + 0.6 * s)])
    hill.lineTo(x + 36 * s, y + 40 * s); hill.lineTo(x - 34 * s, y + 40 * s); hill.close()
    cv.drawPath(hill, P(cmix(col, hexc(p['mid']), 0.45)))
    # дорога-серпантин
    road = smooth_path([(x - 14 * s, y + 0.2 * s), (x - 6 * s, y - 2.4 * s), (x - 11 * s, y - 3.6 * s), (x - 2 * s, y - 5.6 * s)])
    cv.drawPath(road, P(cmix(col, hexc('#000000'), 0.15), 0.25 * s))
    y = y - 5.4 * s
    # кольцо
    ring_r = 4.2 * s
    cv.drawOval(skia.Rect(x - ring_r, y - 2.6 * s, x + ring_r, y - 0.6 * s), P(dark))
    cv.drawRect(skia.Rect(x - ring_r, y - 2.6 * s - 1.1 * s, x + ring_r, y - 1.6 * s), P(dark))
    cv.drawOval(skia.Rect(x - ring_r, y - 4.3 * s, x + ring_r, y - 2.6 * s), P(cmix(dark, col, 0.6)))
    cv.drawOval(skia.Rect(x - ring_r * 0.68, y - 3.95 * s, x + ring_r * 0.68, y - 2.95 * s), P(cmix(dark, hexc('#000000'), 0.3)))
    # светящаяся полоса по кольцу
    glow = 0.35 + 0.65 * pulse
    gl = hexc('#4f9bff', glow)
    band = skia.Rect(x - ring_r, y - 3.0 * s, x + ring_r, y - 2.1 * s)
    cv.drawOval(band, P(gl, 0.18 * s, cap='butt'))
    cv.drawOval(band, P(hexc('#2f7bff', 0.35 * glow), 0.9 * s, blur=0.5 * s))
    # башня и антенна
    cv.drawRect(skia.Rect(x - 0.7 * s, y - 7.5 * s, x + 0.7 * s, y - 2.8 * s), P(dark))
    cv.drawRect(skia.Rect(x - 1.2 * s, y - 7.9 * s, x + 1.2 * s, y - 7.3 * s), P(dark))
    cv.drawLine(x, y - 7.9 * s, x, y - 11.5 * s, P(dark, 0.18 * s))
    blink = 1.0 if (t % 1.6) < 0.18 else 0.25
    cv.drawCircle(x, y - 11.6 * s, 0.22 * s, P(hexc('#ff4a4a', blink)))
    cv.drawCircle(x, y - 11.6 * s, 0.9 * s, P(hexc('#ff4a4a', 0.3 * blink), blur=0.5 * s))
    # окна
    if p['win'] > 0:
        r = RNG(5)
        for i in range(40):
            wx = x + r.u(-3.6, 3.6) * s
            wy = y + r.u(-2.5, -1.8) * s
            cv.drawRect(skia.Rect(wx, wy, wx + 0.18 * s, wy + 0.12 * s), P(hexc('#bfe0ff', p['win'] * r.u(0.3, 1.0))))
    # пульс-волна
    if pulse > 0.7:
        a = (pulse - 0.7) / 0.3
        cv.drawOval(skia.Rect(x - ring_r * (1 + a), y - 2.6 * s - a * 2 * s, x + ring_r * (1 + a), y - 2.4 * s + a * 2 * s),
                    P(hexc('#6fb0ff', 0.5 * (1 - a)), 0.12 * s))

def vertex_pulse(t):
    ph = (t % 6.0) / 6.0
    return 0.5 + 0.5 * math.sin(t * 1.3) * 0.6 + (max(0, 1 - abs(ph - 0.5) * 8))

def lighthouse(cv, x, y, s, tod, t):
    p = pal(tod)
    col = hexc(p['far'])
    cv.drawPath(poly([(x - 0.8 * s, y), (x - 0.45 * s, y - 6 * s), (x + 0.45 * s, y - 6 * s), (x + 0.8 * s, y)]), P(cmix(col, hexc('#e8e0d0'), 0.35)))
    for k in range(3):
        yy = y - (1 + k * 1.8) * s
        cv.drawRect(skia.Rect(x - 0.75 * s + k * 0.1 * s, yy - 0.5 * s, x + 0.75 * s - k * 0.1 * s, yy), P(cmix(col, hexc('#c84040'), 0.55)))
    cv.drawRect(skia.Rect(x - 0.6 * s, y - 7 * s, x + 0.6 * s, y - 6 * s), P(cmix(col, hexc('#000000'), 0.3)))
    if tod in ('night', 'dusk', 'dawn'):
        ang = (t * 40) % 360
        c = math.cos(math.radians(ang))
        bx = x + c * 40 * s
        beam = poly([(x, y - 6.5 * s), (bx, y - 6.5 * s - 3 * s), (bx, y - 6.5 * s + 3 * s)])
        sh = skia.GradientShader.MakeLinear([skia.Point(x, y), skia.Point(bx, y)],
                                            [c4(hexc('#fff3c0', 0.45 * abs(c))), c4(hexc('#fff3c0', 0.0))])
        bp = skia.Paint(AntiAlias=True); bp.setShader(sh)
        cv.drawPath(beam, bp)
        cv.drawCircle(x, y - 6.5 * s, 0.5 * s, P(hexc('#fff3c0', 0.9)))

def skyline_picture(seed, tod, x0, x1, base_y, hmin, hmax, wmin, wmax, color, win_alpha, crane=False, roofs=True):
    r = RNG(seed)
    rec = skia.PictureRecorder()
    cv = rec.beginRecording(skia.Rect(-1e5, -1e5, 1e5, 1e5))
    x = x0
    col = hexc(color)
    winc = hexc('#ffd88a')
    while x < x1:
        w = r.u(wmin, wmax)
        h = r.u(hmin, hmax)
        cv.drawRect(skia.Rect(x, base_y - h, x + w + 0.02, base_y + 50), P(col))
        if roofs and r.u() < 0.35:
            cv.drawPath(poly([(x, base_y - h), (x + w / 2, base_y - h - w * 0.35), (x + w, base_y - h)]), P(col))
        if r.u() < 0.2:
            cv.drawLine(x + w * 0.7, base_y - h, x + w * 0.7, base_y - h - h * 0.25, P(col, w * 0.06))
        if win_alpha > 0:
            cols = max(1, int(w / (wmax * 0.22)))
            rows = max(1, int(h / (hmax * 0.12)))
            for i in range(cols):
                for j in range(rows):
                    if r.u() < 0.42:
                        wx = x + (i + 0.3) * w / cols
                        wy = base_y - h + (j + 0.4) * h / rows
                        cv.drawRect(skia.Rect(wx, wy, wx + w / cols * 0.4, wy + h / rows * 0.35),
                                    P(calpha(winc, win_alpha * r.u(0.4, 1.0))))
        x += w + r.u(0.0, wmax * 0.15)
    if crane:
        for cx in (x0 + (x1 - x0) * 0.3, x0 + (x1 - x0) * 0.62):
            hh = hmax * 1.6
            cv.drawLine(cx, base_y, cx, base_y - hh, P(col, hmax * 0.05))
            cv.drawLine(cx - hh * 0.3, base_y - hh, cx + hh * 0.9, base_y - hh, P(col, hmax * 0.04))
            cv.drawLine(cx, base_y - hh * 1.12, cx + hh * 0.9, base_y - hh, P(col, hmax * 0.015))
            cv.drawLine(cx + hh * 0.6, base_y - hh, cx + hh * 0.6, base_y - hh * 0.6, P(col, hmax * 0.01))
    return rec.finishRecordingAsPicture()

class PicLayer(Layer):
    def __init__(self, z, pic, name=''):
        super().__init__(z, None, False, True, name)
        self.pic = pic
    def draw(self, cv, t):
        cv.drawPicture(self.pic)

def sea_layer(tod, y0, x0=-400, x1=400, depth=80):
    p = pal(tod)
    def fn(cv, t):
        vgrad(cv, (x0, y0, x1, y0 + depth), [hexc(p['sea'][0]), hexc(p['sea'][1])])
        r = RNG(9)
        glint = hexc(p['light'], 0.55 if tod in ('golden', 'dusk', 'dawn') else 0.35)
        for i in range(140):
            x = r.u(x0 * 0.3, x1 * 0.3)
            y = y0 + r.u(0.2, 12) ** 1.3
            ph = math.sin(t * r.u(0.8, 2.0) + i)
            if ph > 0.2:
                ww = r.u(0.3, 1.6) * (0.4 + (y - y0) * 0.05)
                cv.drawLine(x - ww, y, x + ww, y, P(calpha(glint, (ph - 0.2) * 0.8), 0.06 + (y - y0) * 0.004))
    return Layer(40, fn, name='sea')

def bridge_far(tod, x=0.0, y=0.0, s=1.0):
    p = pal(tod)
    col = hexc(p['mid'])
    def fn(cv, t):
        cv.drawRect(skia.Rect(x - 40 * s, y - 1.0 * s, x + 40 * s, y - 0.6 * s), P(col))
        for tx in (x - 14 * s, x + 14 * s):
            cv.drawRect(skia.Rect(tx - 0.5 * s, y - 9 * s, tx + 0.5 * s, y + 3 * s), P(col))
            cv.drawRect(skia.Rect(tx - 0.9 * s, y - 6.5 * s, tx + 0.9 * s, y - 6.1 * s), P(col))
        cab = P(col, 0.08 * s)
        for a, b in ((x - 40 * s, x - 14 * s), (x - 14 * s, x + 14 * s), (x + 14 * s, x + 40 * s)):
            pth = skia.Path(); pth.moveTo(a, y - (9 * s if a != x - 40 * s else 1 * s))
            mid = (a + b) / 2
            sag = y - 1.4 * s
            pth.quadTo(mid, sag + (2.5 * s if b - a > 20 * s else 0), b, y - (9 * s if b != x + 40 * s else 1 * s))
            cv.drawPath(pth, cab)
            for k in range(1, 12):
                xx = a + (b - a) * k / 12
                u = k / 12
                yy = (1 - u) ** 2 * (y - 9 * s) + 2 * u * (1 - u) * (sag + 2.5 * s) + u * u * (y - 9 * s)
                if b - a > 20 * s:
                    cv.drawLine(xx, yy, xx, y - 1.0 * s, P(col, 0.03 * s))
        if p['win'] > 0:
            for k in range(-30, 31):
                lx = x + k * 1.3 * s
                cv.drawCircle(lx, y - 1.15 * s, 0.12 * s, P(hexc(p['light'], 0.9)))
                cv.drawCircle(lx, y - 1.15 * s, 0.5 * s, P(hexc(p['light'], 0.18), blur=0.3 * s))
    return fn

def gulls(cv, t, n=5, seed=1, x0=-10, x1=10, y0=-6, y1=-3, size=0.25, col=None, speed=1.0):
    col = col or INK
    r = RNG(seed)
    for i in range(n):
        sp = r.u(0.6, 1.2) * speed
        span = x1 - x0
        x = x0 + ((r.u(0, span) + t * sp) % span)
        y = r.u(y0, y1) + math.sin(t * 0.7 + i) * 0.3
        flap = math.sin(t * 8 * r.u(0.8, 1.2) + i * 1.7)
        w = size * r.u(0.7, 1.2)
        pth = skia.Path()
        pth.moveTo(x - w, y - flap * w * 0.5)
        pth.quadTo(x - w * 0.4, y - w * 0.3, x, y)
        pth.quadTo(x + w * 0.4, y - w * 0.3, x + w, y - flap * w * 0.5)
        cv.drawPath(pth, P(col, w * 0.14))

def fog_layer(tod, z, y0, alpha=0.35, speed=0.2, seed=4, h=3.0):
    p = pal(tod)
    def fn(cv, t):
        r = RNG(seed)
        for i in range(10):
            x = (r.u(-80, 80) + t * speed * r.u(0.5, 1.5)) % 160 - 80
            y = y0 + r.u(-h * 0.4, h * 0.4)
            w = r.u(12, 30)
            cv.drawOval(skia.Rect(x - w, y - h * 0.5, x + w, y + h * 0.5), P(hexc(p['fog'], alpha * r.u(0.5, 1.0)), blur=h * 0.4))
    return Layer(z, fn, name='fog', soft=6.0)

def panorama_layers(tod, cy=-0.95, zoom=420.0, hpx=470.0, cx=0.0, inst=(1450, 150), lh=(260, 120),
                    bridge=(700, 18, 260), city_far=(6, 30, 120), city_mid=(70, 40, 150), sea=True, clouds=True, D=3.0):
    """Общий вид на Норден, спроектированный в пикселях для номинальной камеры (cy, zoom).
    hpx — экранная высота горизонта; inst=(x_px, height_px) — институт на холме; lh — маяк;
    bridge=(x_px, dy_px, tower_px); city_far/city_mid=(dy_px, hmin_px, hmax_px)."""
    p = pal(tod)
    def S(z): return zoom * D / (z + D)
    def wy(z, px): return cy + (px - H / 2) / S(z)
    def wx(z, px): return cx + (px - W / 2) / S(z)
    def wu(z, px): return px / S(z)
    L = []
    if clouds:
        def far(cv, t, z=260):
            draw_clouds(cv, tod, t, seed=3, y0=wy(z, hpx - 270), span=wu(z, 2600), alpha=0.35, speed=wu(z, 6), scale=wu(z, 55))
        L.append(Layer(260, far, name='clouds', soft=3.0))
    def hill(cv, t, z=140):
        if inst:
            institute(cv, wx(z, inst[0]), wy(z, hpx + 4), wu(z, inst[1]) / 17.0, tod, t, pulse=clamp(vertex_pulse(t), 0, 1))
        if lh:
            lighthouse(cv, wx(z, lh[0]) * 1.0, wy(z, hpx + 12), wu(z, lh[1]) / 7.0, tod, t)
    L.append(Layer(140, hill, name='hill'))
    if sea:
        L.append(sea_layer(tod, wy(40, hpx), x0=-wu(40, 4000), x1=wu(40, 4000), depth=wu(40, 1200)))
    if bridge:
        L.append(Layer(36, bridge_far(tod, x=wx(36, bridge[0]), y=wy(36, hpx + bridge[1]), s=wu(36, bridge[2]) / 9.0), name='bridge'))
    if city_far:
        z = 24
        L.append(PicLayer(z, skyline_picture(11, tod, -wu(z, 4000), wu(z, 4000), wy(z, hpx + city_far[0]), wu(z, city_far[1]),
                                             wu(z, city_far[2]), wu(z, 22), wu(z, 70), p['far'], p['win'], crane=True)))
    if city_mid:
        z = 12
        L.append(PicLayer(z, skyline_picture(12, tod, -wu(z, 4000), wu(z, 4000), wy(z, hpx + city_mid[0]), wu(z, city_mid[1]),
                                             wu(z, city_mid[2]), wu(z, 40), wu(z, 110), p['mid'], p['win'])))
    return L

# ─────────────────────────── интерьеры ───────────────────────────
def room_ray(tod='morning'):
    """Комната Рэя. Стена z=1.6, кровать слева, стол справа, окно с видом на Норден."""
    p = pal(tod)
    night = tod == 'night'
    wall = hexc('#2a3050') if night else hexc('#d9cdb8')
    wall2 = hexc('#20253f') if night else hexc('#c7b9a0')
    floor = hexc('#1b1f33') if night else hexc('#a98d6c')
    L = []
    def back(cv, t):
        cv.drawRect(skia.Rect(-12, -6, 12, 0.02), P(wall))
        cv.drawRect(skia.Rect(-12, -0.3, 12, 0.02), P(wall2))
        # окно
        wx0, wx1, wy0, wy1 = -0.6, 1.5, -2.25, -0.95
        cv.save()
        cv.clipRect(skia.Rect(wx0, wy0, wx1, wy1))
        vgrad(cv, (wx0, wy0, wx1, wy1), [hexc(c) for c in p['sky']])
        institute(cv, 0.95, -0.98, 0.032, tod, t, pulse=clamp(vertex_pulse(t), 0, 1))
        cv.drawPicture(SKY_PICS.setdefault(('roomcity', tod), skyline_picture(31, tod, -1, 2, -1.0, 0.05, 0.3, 0.06, 0.16, p['mid'], p['win'], roofs=True)))
        if night:
            cv.drawCircle(1.25, -2.0, 0.09, P(hexc('#f2f0e0')))
        cv.restore()
        frame = P(hexc('#5a4632') if not night else hexc('#0e1120'), 0.06)
        cv.drawRect(skia.Rect(wx0, wy0, wx1, wy1), frame)
        cv.drawLine((wx0 + wx1) / 2, wy0, (wx0 + wx1) / 2, wy1, frame)
        cv.drawLine(wx0, (wy0 + wy1) / 2, wx1, (wy0 + wy1) / 2, P(hexc('#5a4632') if not night else hexc('#0e1120'), 0.035))
        # шторы
        cc = hexc('#b8443a') if not night else hexc('#4a2030')
        cv.drawPath(poly([(wx0 - 0.25, wy0 - 0.15), (wx0 + 0.15, wy0 - 0.15), (wx0 + 0.02, wy1 + 0.35), (wx0 - 0.3, wy1 + 0.35)]), P(cc))
        cv.drawPath(poly([(wx1 - 0.15, wy0 - 0.15), (wx1 + 0.25, wy0 - 0.15), (wx1 + 0.3, wy1 + 0.35), (wx1 - 0.02, wy1 + 0.35)]), P(cc))
        # постер
        cv.drawRect(skia.Rect(-2.6, -2.1, -1.7, -0.95), P(hexc('#1f2a4a') if not night else hexc('#151a30')))
        cv.drawCircle(-2.15, -1.6, 0.25, P(hexc('#e8402f') if not night else hexc('#5a2230')))
        draw_text(cv, 'LVL 99', -2.15, -1.12, font('RussoOne', 0.15), hexc('#f3efe6', 0.8), 'center')
        # полка с перевёрнутой рамкой
        cv.drawRect(skia.Rect(2.0, -1.55, 3.0, -1.5), P(hexc('#6a4a32')))
        cv.drawPath(poly([(2.15, -1.55), (2.55, -1.55), (2.6, -1.58), (2.2, -1.58)]), P(hexc('#3a2a1a')))
        cv.drawRect(skia.Rect(2.65, -1.85, 2.85, -1.55), P(hexc('#4a6a8a')))
        cv.drawRect(skia.Rect(2.86, -1.8, 2.95, -1.55), P(hexc('#8a4a4a')))
    L.append(Layer(1.6, back, name='roomwall'))
    def floor_fn(cv, t):
        cv.drawRect(skia.Rect(-12, 0.0, 12, 4), P(floor))
        for k in range(-20, 20):
            cv.drawLine(k * 0.6, 0, k * 0.9, 4, P(cmix(floor, hexc('#000000'), 0.15), 0.01))
    L.append(Layer(0.0, floor_fn, name='floor'))
    def furniture(cv, t):
        # кровать (слева)
        cv.drawRect(skia.Rect(-3.2, -0.55, -0.9, -0.25), P(hexc('#e9e2d4') if not night else hexc('#3a4060')))
        cv.drawRect(skia.Rect(-3.25, -0.28, -0.85, 0.0), P(hexc('#6a4a32') if not night else hexc('#1a1d30')))
        cv.drawRect(skia.Rect(-3.3, -0.95, -3.15, 0.0), P(hexc('#6a4a32') if not night else hexc('#1a1d30')))
        cv.drawRoundRect(skia.Rect(-1.5, -0.68, -0.95, -0.5), 0.08, 0.08, P(hexc('#ffffff') if not night else hexc('#4a5070')))
        # тумбочка
        cv.drawRect(skia.Rect(-0.8, -0.5, -0.35, 0.0), P(hexc('#7a5a3a') if not night else hexc('#22263c')))
        # стол (справа)
        dc = hexc('#7a5a3a') if not night else hexc('#22263c')
        cv.drawRect(skia.Rect(1.9, -0.75, 3.4, -0.68), P(dc))
        cv.drawRect(skia.Rect(1.95, -0.68, 2.02, 0.0), P(dc))
        cv.drawRect(skia.Rect(3.28, -0.68, 3.35, 0.0), P(dc))
        # лампа
        cv.drawLine(3.1, -0.75, 3.0, -1.1, P(hexc('#333333'), 0.025))
        cv.drawPath(poly([(2.85, -1.1), (3.15, -1.1), (3.08, -1.25), (2.92, -1.25)]), P(hexc('#e8402f') if not night else hexc('#5a2230')))
    L.append(Layer(0.25, furniture, name='furniture'))
    return L

SKY_PICS = {}

def kitchen(tod='morning'):
    p = pal(tod)
    eve = tod in ('night', 'dusk')
    wall = hexc('#e7dcc4') if not eve else hexc('#5a4a3e')
    tile = hexc('#d8cfb6') if not eve else hexc('#4a3c32')
    L = []
    def back(cv, t):
        cv.drawRect(skia.Rect(-12, -6, 12, 0.02), P(wall))
        for i in range(-30, 30):
            for j in range(0, 6):
                cv.drawRect(skia.Rect(i * 0.22, -1.5 + j * 0.22, i * 0.22 + 0.2, -1.5 + j * 0.22 + 0.2), P(tile))
        # окно
        wx0, wx1, wy0, wy1 = -2.6, -1.0, -2.3, -1.2
        cv.save(); cv.clipRect(skia.Rect(wx0, wy0, wx1, wy1))
        vgrad(cv, (wx0, wy0, wx1, wy1), [hexc(c) for c in p['sky']])
        cv.drawPicture(SKY_PICS.setdefault(('kcity', tod), skyline_picture(41, tod, -3, 0, -1.25, 0.05, 0.35, 0.08, 0.2, p['mid'], p['win'])))
        cv.restore()
        cv.drawRect(skia.Rect(wx0, wy0, wx1, wy1), P(hexc('#f4f4f0') if not eve else hexc('#2a2420'), 0.05))
        cv.drawLine((wx0 + wx1) / 2, wy0, (wx0 + wx1) / 2, wy1, P(hexc('#f4f4f0') if not eve else hexc('#2a2420'), 0.04))
        # плита и шкафы
        cc = hexc('#5f8a86') if not eve else hexc('#2e4644')
        cv.drawRect(skia.Rect(0.6, -2.4, 3.2, -1.65), P(cc))
        for k in range(3):
            cv.drawRect(skia.Rect(0.62 + k * 0.86, -2.38, 1.44 + k * 0.86, -1.67), P(cmix(cc, hexc('#ffffff'), 0.08)))
        cv.drawRect(skia.Rect(0.6, -0.95, 3.2, 0.0), P(cc))
        cv.drawRect(skia.Rect(0.55, -1.0, 3.25, -0.92), P(hexc('#d8d2c4') if not eve else hexc('#6a6258')))
        cv.drawRect(skia.Rect(1.1, -1.05, 1.9, -1.0), P(hexc('#222222')))
        # чайник
        cv.drawOval(skia.Rect(1.25, -1.32, 1.65, -1.03), P(hexc('#e8402f')))
        cv.drawLine(1.62, -1.2, 1.78, -1.28, P(hexc('#e8402f'), 0.04))
        # полка с рамкой лицом вниз
        cv.drawRect(skia.Rect(-0.6, -1.95, 0.4, -1.9), P(hexc('#6a4a32')))
        cv.drawRect(skia.Rect(-0.4, -1.98, 0.0, -1.95), P(hexc('#3a2a1a')))
        cv.drawRect(skia.Rect(0.12, -2.25, 0.3, -1.95), P(hexc('#c8b070')))
    L.append(Layer(1.5, back, name='kwall'))
    def floor_fn(cv, t):
        cv.drawRect(skia.Rect(-12, 0.0, 12, 4), P(hexc('#8a6a4c') if not eve else hexc('#3a2c22')))
    L.append(Layer(0.0, floor_fn, name='kfloor'))
    def lamp(cv, t):
        sw = math.sin(t * 0.8) * 0.02
        cv.drawLine(0.0, -6, 0.0 + sw, -2.15, P(hexc('#222222'), 0.015))
        cv.drawPath(poly([(-0.25 + sw, -1.95), (0.25 + sw, -1.95), (0.12 + sw, -2.15), (-0.12 + sw, -2.15)]), P(hexc('#e0b040')))
        if eve:
            cv.drawCircle(sw, -1.9, 1.6, P(hexc('#ffd27a', 0.18), blur=0.6))
    L.append(Layer(0.6, lamp, name='klamp'))
    return L

def table_front(z=-0.35, color='#8a5a3a', y=-0.62, x0=-1.6, x1=1.6, items=True, eve=False):
    def fn(cv, t):
        c = hexc(color) if not eve else hexc('#4a3020')
        cv.drawRect(skia.Rect(x0, y, x1, y + 0.08), P(cmix(c, hexc('#ffffff'), 0.12)))
        cv.drawRect(skia.Rect(x0 + 0.05, y + 0.08, x1 - 0.05, y + 0.2), P(c))
        cv.drawRect(skia.Rect(x0 + 0.1, y + 0.2, x0 + 0.18, 0.4), P(c))
        cv.drawRect(skia.Rect(x1 - 0.18, y + 0.2, x1 - 0.1, 0.4), P(c))
        if items:
            cv.drawOval(skia.Rect(-0.55, y - 0.06, -0.15, y + 0.02), P(hexc('#f4f4f0')))
            cv.drawOval(skia.Rect(0.25, y - 0.06, 0.65, y + 0.02), P(hexc('#f4f4f0')))
            if eve:
                cv.drawOval(skia.Rect(-0.5, y - 0.05, -0.2, y - 0.0), P(hexc('#d07a40')))
                cv.drawOval(skia.Rect(0.3, y - 0.05, 0.6, y - 0.0), P(hexc('#d07a40')))
    return Layer(z, fn, name='table')

def classroom(tod='morning'):
    p = pal(tod)
    L = []
    def back(cv, t):
        cv.drawRect(skia.Rect(-14, -6, 14, 0.02), P(hexc('#c9d2c0')))
        cv.drawRect(skia.Rect(-14, -0.6, 14, 0.02), P(hexc('#9aa890')))
        # доска
        cv.drawRect(skia.Rect(-3.2, -2.65, 2.2, -1.05), P(hexc('#6a4a32')))
        cv.drawRect(skia.Rect(-3.12, -2.57, 2.12, -1.13), P(hexc('#1f3a30')))
        f = font('Neucha', 0.2)
        draw_text(cv, 'Упругая и пластическая', -2.95, -2.25, f, hexc('#e8efe6', 0.92))
        draw_text(cv, 'деформация.', -2.95, -2.0, f, hexc('#e8efe6', 0.92))
        draw_text(cv, 'Предел прочности σ', -2.95, -1.66, font('Neucha', 0.18), hexc('#f2e8a0', 0.9))
        # график излома
        pth = skia.Path(); pth.moveTo(0.4, -1.3); pth.lineTo(0.9, -2.0); pth.quadTo(1.3, -2.35, 1.6, -2.2); pth.lineTo(1.75, -1.75)
        cv.drawPath(pth, P(hexc('#e8efe6', 0.85), 0.02))
        cv.drawLine(0.4, -1.3, 1.95, -1.3, P(hexc('#e8efe6', 0.6), 0.015))
        cv.drawLine(0.4, -1.3, 0.4, -2.45, P(hexc('#e8efe6', 0.6), 0.015))
        cv.drawLine(1.72, -1.85, 1.8, -1.7, P(hexc('#ff8a7a', 0.9), 0.02))
        draw_text(cv, 'излом!', 1.62, -1.55, font('Neucha', 0.13), hexc('#ff8a7a', 0.9))
        # часы
        cv.drawCircle(3.2, -2.3, 0.22, P(hexc('#f4f4f0'))); cv.drawCircle(3.2, -2.3, 0.22, P(hexc('#333333'), 0.025))
        cv.drawLine(3.2, -2.3, 3.2, -2.45, P(hexc('#333333'), 0.02)); cv.drawLine(3.2, -2.3, 3.32, -2.3, P(hexc('#333333'), 0.02))
        # окна справа
        for k in range(3):
            x0 = 4.2 + k * 1.6
            cv.save(); cv.clipRect(skia.Rect(x0, -2.6, x0 + 1.2, -0.9))
            vgrad(cv, (x0, -2.6, x0 + 1.2, -0.9), [hexc(c) for c in p['sky']])
            if k == 1:
                institute(cv, x0 + 0.6, -0.93, 0.03, tod, t, pulse=clamp(vertex_pulse(t), 0, 1))
            cv.restore()
            cv.drawRect(skia.Rect(x0, -2.6, x0 + 1.2, -0.9), P(hexc('#f4f4f0'), 0.05))
    L.append(Layer(2.6, back, name='cwall'))
    def floor_fn(cv, t):
        cv.drawRect(skia.Rect(-14, 0.0, 14, 5), P(hexc('#b08a64')))
    L.append(Layer(0.0, floor_fn, name='cfloor'))
    return L

def desk(x, z, w=0.9, y=-0.62, color='#c79a62'):
    def fn(cv, t):
        c = hexc(color)
        cv.drawRect(skia.Rect(x - w / 2, y, x + w / 2, y + 0.06), P(cmix(c, hexc('#ffffff'), 0.15)))
        cv.drawRect(skia.Rect(x - w / 2 + 0.03, y + 0.06, x + w / 2 - 0.03, y + 0.22), P(c))
        cv.drawRect(skia.Rect(x - w / 2 + 0.06, y + 0.22, x - w / 2 + 0.11, 0.0), P(hexc('#555555')))
        cv.drawRect(skia.Rect(x + w / 2 - 0.11, y + 0.22, x + w / 2 - 0.06, 0.0), P(hexc('#555555')))
    return Layer(z, fn, name='desk')

def street_embank(tod='morning'):
    """Набережная: перила за героями, море, город на том берегу, холм с институтом."""
    p = pal(tod)
    L = panorama_layers(tod, cy=-0.95, zoom=420, hpx=455, inst=(1400, 230), lh=(250, 110), bridge=(620, 14, 230), city_far=(4, 25, 95), city_mid=(40, 30, 90))
    def rail(cv, t):
        rc = hexc('#2a3040') if tod not in ('morning', 'noon') else hexc('#3a4658')
        cv.drawLine(-60, -0.85, 60, -0.85, P(rc, 0.05))
        cv.drawLine(-60, -0.5, 60, -0.5, P(rc, 0.03))
        for k in range(-60, 61):
            cv.drawLine(k * 0.5, -0.85, k * 0.5, 0.0, P(rc, 0.025))
        for k in range(-12, 13):
            lx = k * 4.0
            cv.drawLine(lx, 0.0, lx, -2.6, P(rc, 0.06))
            cv.drawLine(lx, -2.6, lx + 0.35, -2.75, P(rc, 0.05))
            on = p['win'] > 0.2
            cv.drawCircle(lx + 0.38, -2.7, 0.09, P(hexc(p['light'], 0.95 if on else 0.4)))
            if on:
                cv.drawCircle(lx + 0.38, -2.65, 0.8, P(hexc(p['light'], 0.18), blur=0.4))
    L.append(Layer(0.8, rail, name='rail'))
    def ground(cv, t):
        g = {'morning': '#8d8a84', 'noon': '#8d8a84', 'golden': '#9a7a6a', 'dusk': '#4a4458', 'night': '#262838', 'dawn': '#5a5068'}[tod]
        cv.drawRect(skia.Rect(-60, 0.0, 60, 4), P(hexc(g)))
        for k in range(-60, 61):
            cv.drawLine(k * 0.8, 0, k * 1.2, 4, P(cmix(hexc(g), hexc('#000000'), 0.12), 0.012))
    L.append(Layer(0.0, ground, name='ground'))
    return L

def apple_cart(x, z=0.0):
    def fn(cv, t):
        cv.drawRect(skia.Rect(x - 0.5, -0.62, x + 0.5, -0.32), P(hexc('#8a5a3a')))
        cv.drawRect(skia.Rect(x - 0.5, -0.62, x + 0.5, -0.32), P(INK, 0.02))
        r = RNG(77)
        for i in range(16):
            ax, ay = x - 0.42 + r.u(0, 0.84), -0.66 - r.u(0, 0.1)
            cv.drawCircle(ax, ay, 0.055, P(hexc('#d93a3a') if i % 4 else hexc('#7ac24a')))
        cv.drawCircle(x - 0.3, -0.12, 0.13, P(INK, 0.025)); cv.drawCircle(x + 0.3, -0.12, 0.13, P(INK, 0.025))
        cv.drawLine(x + 0.5, -0.5, x + 0.85, -0.65, P(INK, 0.025))
        # зонтик
        cv.drawLine(x, -0.62, x, -1.6, P(INK, 0.02))
        cv.drawPath(poly([(x - 0.75, -1.45), (x, -1.75), (x + 0.75, -1.45)]), P(hexc('#e8c040')))
    return Layer(z, fn, name='cart')

def school_roof(tod='noon'):
    p = pal(tod)
    L = panorama_layers(tod, cy=-1.0, zoom=380, hpx=430, inst=(1180, 260), lh=(150, 110), bridge=(420, 20, 230), city_far=(10, 30, 120), city_mid=(90, 50, 190))
    def across(cv, t):
        # здание через улицу с крышей, где появляется незнакомец
        c = hexc(p['near'])
        cv.drawRect(skia.Rect(-14, -2.2, -6, 6), P(c))
        cv.drawRect(skia.Rect(-14.2, -2.3, -5.8, -2.2), P(cmix(c, hexc('#000000'), 0.3)))
        r = RNG(3)
        for i in range(6):
            for j in range(4):
                cv.drawRect(skia.Rect(-13.5 + i * 1.3, -1.7 + j * 1.1, -12.9 + i * 1.3, -1.2 + j * 1.1),
                            P(hexc('#a8c4dc', 0.5 + r.u(0, 0.3))))
        cv.drawRect(skia.Rect(-12.0, -3.0, -11.4, -2.3), P(cmix(c, hexc('#000000'), 0.2)))
    L.append(Layer(9.0, across, name='across'))
    def fence(cv, t):
        fc = hexc('#5a6878')
        cv.drawLine(-30, -1.4, 30, -1.4, P(fc, 0.04))
        cv.drawLine(-30, -0.05, 30, -0.05, P(fc, 0.04))
        for k in range(-40, 41):
            cv.drawLine(k * 0.75, -1.4, k * 0.75, 0.0, P(fc, 0.035))
        mesh = P(hexc('#5a6878', 0.45), 0.008)
        for k in range(-200, 201):
            x = k * 0.15
            cv.drawLine(x, -1.4, x + 1.4, 0.0, mesh)
            cv.drawLine(x, -1.4, x - 1.4, 0.0, mesh)
    L.append(Layer(1.1, fence, name='fence'))
    def floor(cv, t):
        cv.drawRect(skia.Rect(-30, 0.0, 30, 4), P(hexc('#8a8f96')))
        for k in range(-30, 31):
            cv.drawLine(k * 1.0, 0.0, k * 1.6, 4, P(hexc('#7a7f86'), 0.01))
        # бак с водой слева
        cv.drawRect(skia.Rect(-5.5, -1.6, -3.9, 0.0), P(hexc('#b8bec6')))
        cv.drawOval(skia.Rect(-5.5, -1.75, -3.9, -1.45), P(hexc('#c8ced6')))
    L.append(Layer(0.0, floor, name='rfloor'))
    return L

def stairs_embank(tod='golden'):
    p = pal(tod)
    L = panorama_layers(tod, cy=-0.9, zoom=330, hpx=500, inst=(400, 230), lh=(1650, 120), bridge=None, city_far=(4, 25, 100), city_mid=None)
    def far_bank(cv, t):
        c = hexc(p['mid'])
        cv.drawRect(skia.Rect(-80, -0.6, 80, 3), P(c))
        for k in range(-20, 21):
            lx = k * 3.2
            cv.drawLine(lx, -0.6, lx, -2.2, P(c, 0.05))
            cv.drawCircle(lx, -2.25, 0.1, P(hexc(p['light'], 0.9)))
            cv.drawCircle(lx, -2.2, 0.6, P(hexc(p['light'], 0.2), blur=0.3))
    L.append(Layer(18.0, far_bank, name='farbank'))
    def water(cv, t):
        vgrad(cv, (-60, 0.6, 60, 6), [hexc(p['sea'][0]), hexc(p['sea'][1])])
        r = RNG(17)
        for i in range(60):
            x = r.u(-12, 12); y = 0.7 + r.u(0, 3) ** 1.2
            ph = math.sin(t * r.u(1, 2) + i)
            if ph > 0:
                cv.drawLine(x - 0.3, y, x + 0.3, y, P(hexc(p['light'], 0.5 * ph), 0.025))
    L.append(Layer(2.0, water, name='water'))
    def arch(cv, t):
        c = hexc(p['near'])
        pth = skia.Path()
        pth.moveTo(-20, -4.2); pth.lineTo(20, -4.2); pth.lineTo(20, -3.6)
        pth.quadTo(6, -3.2, 3.5, 1.0); pth.lineTo(2.6, 1.0); pth.quadTo(0, -3.0, -20, -3.6); pth.close()
        cv.drawPath(pth, P(c))
        cv.drawRect(skia.Rect(-20, -4.6, 20, -4.15), P(cmix(c, hexc('#000000'), 0.3)))
    L.append(Layer(3.2, arch, name='arch'))
    def steps(cv, t):
        # набережная сверху (слева), лестница вниз вправо к воде
        sc = hexc('#9a8a7c') if tod != 'night' else hexc('#3a3a48')
        dk = cmix(sc, hexc('#000000'), 0.25)
        cv.drawRect(skia.Rect(-12, 0.0, -0.2, 3), P(sc))
        for k in range(8):
            x0 = -0.2 + k * 0.32
            y0 = k * 0.12
            cv.drawRect(skia.Rect(x0, y0, 12, y0 + 0.12), P(sc if k % 2 == 0 else cmix(sc, dk, 0.4)))
            cv.drawLine(x0, y0, 12, y0, P(dk, 0.015))
        cv.drawRect(skia.Rect(2.36, 0.96, 12, 3), P(cmix(sc, dk, 0.6)))
        # перила вдоль лестницы
        rc = hexc('#2a2a36')
        cv.drawLine(-12, -0.85, -0.2, -0.85, P(rc, 0.04))
        cv.drawLine(-0.2, -0.85, 2.4, 0.1, P(rc, 0.04))
        for k in range(-24, 0):
            cv.drawLine(k * 0.5, -0.85, k * 0.5, 0.0, P(rc, 0.02))
        # скамейка
        cv.drawRect(skia.Rect(-3.6, -0.47, -2.4, -0.4), P(hexc('#7a5032')))
        cv.drawRect(skia.Rect(-3.6, -0.8, -2.4, -0.72), P(hexc('#7a5032')))
        cv.drawLine(-3.5, -0.4, -3.5, 0.0, P(rc, 0.03)); cv.drawLine(-2.5, -0.4, -2.5, 0.0, P(rc, 0.03))
    L.append(Layer(0.0, steps, name='steps'))
    return L

def bridge_deck(tod='dusk'):
    p = pal(tod)
    L = panorama_layers(tod, cy=-1.0, zoom=330, hpx=560, inst=(1500, 220), lh=(250, 100), bridge=None, city_far=(4, 30, 110), city_mid=(30, 40, 130))
    def far_rail(cv, t):
        rc = hexc('#1a1a2a')
        cv.drawLine(-80, -0.95, 80, -0.95, P(rc, 0.05))
        for k in range(-160, 161):
            cv.drawLine(k * 0.5, -0.95, k * 0.5, 0.0, P(rc, 0.022))
        for k in range(-20, 21):
            lx = k * 3.5
            cv.drawLine(lx, 0.0, lx, -3.0, P(rc, 0.07))
            cv.drawLine(lx, -3.0, lx + 0.3, -3.1, P(rc, 0.05))
            cv.drawCircle(lx + 0.32, -3.05, 0.1, P(hexc(p['light'], 0.95)))
            cv.drawCircle(lx + 0.32, -2.9, 1.1, P(hexc(p['light'], 0.16), blur=0.5))
        # тросы моста
        cv.drawLine(-80, -6.5, 80, -6.5, P(rc, 0.05))
        for k in range(-80, 81):
            cv.drawLine(k * 1.0, -6.5, k * 1.0, -0.95, P(hexc('#1a1a2a', 0.5), 0.012))
    L.append(Layer(1.4, far_rail, name='brail'))
    def deck(cv, t):
        cv.drawRect(skia.Rect(-80, 0.0, 80, 3), P(hexc('#35304a') if tod != 'golden' else hexc('#6a5260')))
        for k in range(-80, 81):
            cv.drawLine(k * 1.0, 0, k * 1.4, 3, P(hexc('#2a2640'), 0.01))
    L.append(Layer(0.0, deck, name='deck'))
    L.append(fog_layer(tod, 0.7, -0.4, alpha=0.32, speed=0.25, seed=8, h=2.0))
    L.append(fog_layer(tod, 6.0, -1.5, alpha=0.4, speed=0.15, seed=9, h=4.0))
    return L

def bridge_rail_front(tod='dusk', z=-0.7):
    def fn(cv, t):
        rc = hexc('#0e0e18')
        cv.drawLine(-80, -0.95, 80, -0.95, P(rc, 0.06))
        for k in range(-160, 161):
            cv.drawLine(k * 0.5, -0.95, k * 0.5, 0.1, P(rc, 0.03))
    return Layer(z, fn, name='frail')

def lab():
    L = []
    def back(cv, t):
        vgrad(cv, (-20, -8, 20, 2), [hexc('#05070f'), hexc('#0c1430')])
        # большое окно-кольцо с видом на ночной город
        cv.save()
        rr = skia.RRect.MakeRectXY(skia.Rect(-4.5, -4.0, 4.5, -0.6), 1.6, 1.6)
        cv.clipRRect(rr, skia.ClipOp.kIntersect, True)
        vgrad(cv, (-4.5, -4.0, 4.5, -0.6), [hexc('#070b1c'), hexc('#1a2246')])
        cv.drawPicture(SKY_PICS.setdefault('labcity', skyline_picture(51, 'night', -5, 5, -0.6, 0.2, 1.5, 0.2, 0.6, '#0e1428', 0.6)))
        cv.restore()
        cv.drawRRect(rr, P(hexc('#2a3a6a'), 0.08))
        cv.drawRRect(rr, P(hexc('#2f7bff', 0.25), 0.25, blur=0.15))
        # колонны
        for x in (-7, -5.4, 5.4, 7):
            cv.drawRect(skia.Rect(x - 0.25, -6, x + 0.25, 0.0), P(hexc('#0a0e1c')))
            cv.drawLine(x + 0.2, -6, x + 0.2, 0, P(hexc('#2f7bff', 0.35), 0.02))
    L.append(Layer(4.0, back, name='labback'))
    def floor(cv, t):
        vgrad(cv, (-20, 0.0, 20, 3), [hexc('#0e1630'), hexc('#05070f')])
        for k in range(-20, 21):
            cv.drawLine(k * 0.8, 0, k * 1.5, 3, P(hexc('#2f7bff', 0.12), 0.01))
        for j in range(6):
            cv.drawLine(-20, j * 0.4, 20, j * 0.4, P(hexc('#2f7bff', 0.08), 0.01))
    L.append(Layer(0.0, floor, name='labfloor'))
    return L

def monitors(x, z, t_offset=0.0, alarm=0.0):
    def fn(cv, t):
        for k in range(3):
            mx = x + k * 0.75
            r = skia.Rect(mx - 0.33, -1.35, mx + 0.33, -0.92)
            cv.drawRect(r, P(hexc('#0b1226')))
            cv.drawRect(r, P(hexc('#2f7bff', 0.6), 0.015))
            pth = skia.Path()
            for i in range(60):
                u = i / 59
                xx = mx - 0.3 + u * 0.6
                amp = 0.04 + (0.12 * alarm * math.exp(-((u - 0.6) * 9) ** 2) if k == 1 else 0)
                yy = -1.13 + math.sin(u * 30 + t * 4 + k) * amp * (0.5 + 0.5 * math.sin(u * 7 + t))
                if i == 0:
                    pth.moveTo(xx, yy)
                else:
                    pth.lineTo(xx, yy)
            cv.drawPath(pth, P(hexc('#5fe0ff' if k != 1 or alarm < 0.5 else '#ff5a4a', 0.9), 0.008))
            cv.drawRect(skia.Rect(mx - 0.04, -0.92, mx + 0.04, -0.7), P(hexc('#1a2240')))
        cv.drawRect(skia.Rect(x - 0.5, -0.72, x + 2.0, -0.66), P(hexc('#1a2240')))
        cv.drawRect(skia.Rect(x - 0.45, -0.66, x + 1.95, 0.0), P(hexc('#0e1428')))
    return Layer(z, fn, name='monitors')

def holo_map(x, y, z, s=1.0, dot=None, dot_on=1.0, label=None):
    """Голографическая карта Нордена с красной точкой откатa."""
    def fn(cv, t):
        cv.save(); cv.translate(x, y); cv.scale(s, s)
        g = hexc('#4fb0ff', 0.75)
        cv.drawOval(skia.Rect(-1.5, -0.25, 1.5, 0.25), P(hexc('#2f7bff', 0.12), blur=0.05))
        # береговая линия и улицы
        coast = smooth_path([(-1.4, 0.05), (-0.8, -0.02), (-0.3, 0.06), (0.2, -0.04), (0.8, 0.03), (1.4, -0.02)])
        cv.drawPath(coast, P(g, 0.012))
        for k in range(-6, 7):
            cv.drawLine(k * 0.2, -0.2, k * 0.25, 0.2, P(hexc('#4fb0ff', 0.25), 0.005))
        for j in range(-3, 4):
            cv.drawLine(-1.4, j * 0.06, 1.4, j * 0.06, P(hexc('#4fb0ff', 0.2), 0.004))
        cv.drawLine(-0.6, 0.03, -0.1, 0.03, P(g, 0.02))  # мост
        # проекция-лучи
        cv.drawPath(poly([(-0.15, 0.6), (0.15, 0.6), (1.5, 0.0), (-1.5, 0.0)]), P(hexc('#2f7bff', 0.06)))
        if dot is not None and dot_on > 0:
            px, py = dot
            pul = 0.5 + 0.5 * math.sin(t * 6)
            cv.drawCircle(px, py, 0.05 + 0.05 * pul, P(hexc('#ff4a3a', 0.35 * dot_on), blur=0.03))
            cv.drawCircle(px, py, 0.025, P(hexc('#ff4a3a', dot_on)))
            cv.drawCircle(px, py, 0.1 + pul * 0.12, P(hexc('#ff4a3a', 0.5 * (1 - pul) * dot_on), 0.006))
            if label:
                draw_text(cv, label, px + 0.08, py - 0.08, font('Oswald-Bold', 0.07), hexc('#ff8a7a', dot_on))
        cv.restore()
    return Layer(z, fn, name='holo')

def rooftop_night():
    p = pal('night')
    L = panorama_layers('night', cy=-1.4, zoom=300, hpx=520, inst=(1450, 240), lh=(220, 110), bridge=(800, 20, 220), city_far=(6, 30, 110), city_mid=None)
    def near_city(cv, t):
        cv.drawPicture(SKY_PICS.setdefault('roofcity', skyline_picture(61, 'night', -40, 40, 2.5, 0.5, 3.5, 0.8, 2.0, '#0b1022', 0.6)))
    L.append(Layer(5.0, near_city, name='nearcity'))
    def roof(cv, t):
        c = hexc('#0a0d18')
        cv.drawRect(skia.Rect(-20, 0.0, 20, 4), P(c))
        cv.drawLine(-20, 0.0, 20, 0.0, P(hexc('#3a4a7a', 0.6), 0.02))
        # антенны и бак
        for ax in (-3.2, -2.6, 3.5):
            cv.drawLine(ax, 0, ax, -2.2, P(c, 0.03))
            for k in range(3):
                cv.drawLine(ax - 0.3 + k * 0.05, -1.6 - k * 0.2, ax + 0.3 - k * 0.05, -1.6 - k * 0.2, P(c, 0.02))
        cv.drawRect(skia.Rect(-6.5, -1.9, -5.0, 0.0), P(c))
        cv.drawPath(poly([(-6.6, -1.9), (-5.75, -2.4), (-4.9, -1.9)]), P(c))
        for lx in (-6.4, -5.1):
            cv.drawLine(lx, 0, lx, -0.5, P(c, 0.04))
    L.append(Layer(0.0, roof, name='roof'))
    return L

def abstract_bg(kind, t, a=1.0, col1='#e8402f', col2='#16131a'):
    """Экранные фоны для заставок/плашек: 'speed', 'burst', 'halftone'."""
    pass
