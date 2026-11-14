# -*- coding: utf-8 -*-
"""Реквизит и спецобъекты сцены: предметы с дорожками, осколки, автобус, вставки-панели."""
import math
import gfx as skia
from core import *
from sets import Layer, pal, institute, skyline_picture, SKY_PICS, vertex_pulse
from stickman import Look, draw_char, pose

class Obj(Layer):
    """Предмет на глубине z с дорожками x/y/rot/scale/alpha и функцией рисования draw(cv, t)."""
    def __init__(self, z, draw, x=0.0, y=0.0, rot=0.0, scale=1.0, alpha=1.0, name='obj'):
        super().__init__(z, None, name=name)
        self.drawfn = draw
        self.xk = [(0.0, x)]; self.yk = [(0.0, y)]; self.rk = [(0.0, rot)]; self.sk = [(0.0, scale)]; self.ak = [(0.0, alpha)]
        self.custom = None   # fn(t) -> (x, y, rot) переопределение (баллистика)
    def key(self, t, x=None, y=None, rot=None, scale=None, alpha=None, ease='io', dur=0.0):
        for k, v in (('xk', x), ('yk', y), ('rk', rot), ('sk', scale), ('ak', alpha)):
            if v is None:
                continue
            arr = getattr(self, k)
            last = Track(arr)(t)
            if dur > 0:
                arr.append((t, last, 'hold')); arr.append((t + dur, v, ease))
            else:
                arr.append((t, last, 'hold')); arr.append((t + 1e-4, v, 'lin'))
        return self
    def draw(self, cv, t):
        a = Track(self.ak)(t)
        if a <= 0.001:
            return
        if self.custom:
            x, y, r = self.custom(t)
        else:
            x, y, r = Track(self.xk)(t), Track(self.yk)(t), Track(self.rk)(t)
        s = Track(self.sk)(t)
        cv.save(); cv.translate(x, y); cv.rotate(r); cv.scale(s, s)
        if a < 0.999:
            cv.saveLayerAlpha(None, int(a * 255))
        self.drawfn(cv, t)
        if a < 0.999:
            cv.restore()
        cv.restore()

def ballistic(x0, y0, vx, vy, t0, g=9.0, floor=None, spin=0.0):
    """Баллистика предмета: старт в t0. Возвращает fn(t)->(x,y,rot)."""
    def f(t):
        if t < t0:
            return x0, y0, 0.0
        u = t - t0
        x = x0 + vx * u
        y = y0 + vy * u + 0.5 * g * u * u
        if floor is not None and y > floor:
            y = floor
        return x, y, spin * u
    return f

# ─────────────────────────── отдельные предметы ───────────────────────────
def d_alarm(cv, t, ring=0.0):
    sh = math.sin(t * 60) * 0.012 * ring
    cv.translate(sh, 0)
    cv.drawCircle(0, -0.1, 0.09, P(hexc('#e8402f'))); cv.drawCircle(0, -0.1, 0.09, P(INK, 0.012))
    cv.drawCircle(0, -0.1, 0.065, P(PAPER))
    cv.drawLine(0, -0.1, 0, -0.15, P(INK, 0.01)); cv.drawLine(0, -0.1, 0.03, -0.1, P(INK, 0.01))
    for sx in (-1, 1):
        cv.drawCircle(sx * 0.06, -0.19, 0.03, P(hexc('#c8c8c8'))); cv.drawCircle(sx * 0.06, -0.19, 0.03, P(INK, 0.008))
        cv.drawLine(sx * 0.05, -0.03, sx * 0.07, 0.0, P(INK, 0.012))
    if ring > 0:
        for k in range(3):
            a = (t * 6 + k / 3) % 1.0
            cv.drawArc(skia.Rect(-0.15 - a * 0.1, -0.25 - a * 0.1, 0.15 + a * 0.1, 0.05 + a * 0.1), 200, 50, False,
                       P(calpha(INK, (1 - a) * ring), 0.01))
            cv.drawArc(skia.Rect(-0.15 - a * 0.1, -0.25 - a * 0.1, 0.15 + a * 0.1, 0.05 + a * 0.1), 290, 50, False,
                       P(calpha(INK, (1 - a) * ring), 0.01))

def d_blanket(cv, t, breathe=True, night=False):
    b = math.sin(t * 1.4) * 0.01 if breathe else 0
    col = hexc('#3d6fb0') if not night else hexc('#24365a')
    pth = smooth_path([(-1.2, 0.02), (-1.0, -0.22 - b), (-0.4, -0.28 - b), (0.3, -0.24 - b), (0.85, -0.18), (1.05, 0.02)])
    pth.lineTo(1.05, 0.06); pth.lineTo(-1.2, 0.06); pth.close()
    cv.drawPath(pth, P(col)); cv.drawPath(pth, P(INK, 0.018))
    for k in range(4):
        cv.drawLine(-0.9 + k * 0.45, -0.2, -0.75 + k * 0.45, 0.0, P(cmix(col, INK, 0.25), 0.01))

def d_phone(cv, t, lit=0.0, crack=0.0):
    r = skia.RRect.MakeRectXY(skia.Rect(-0.045, -0.08, 0.045, 0.08), 0.015, 0.015)
    cv.drawRRect(r, P(hexc('#222833'))); cv.drawRRect(r, P(INK, 0.008))
    cv.drawRect(skia.Rect(-0.035, -0.065, 0.035, 0.065), P(cmix(hexc('#1a2a44'), hexc('#8fd0ff'), lit)))
    if lit > 0.3:
        # фото: мальчик с папой
        cv.drawCircle(-0.012, -0.015, 0.012, P(PAPER)); cv.drawLine(-0.012, -0.003, -0.012, 0.03, P(INK, 0.004))
        cv.drawCircle(0.015, -0.03, 0.015, P(PAPER)); cv.drawLine(0.015, -0.015, 0.015, 0.035, P(INK, 0.005))
        cv.drawLine(-0.012, 0.01, 0.015, 0.0, P(INK, 0.004))
    if crack > 0:
        r_ = RNG(5)
        for k in range(int(3 + 5 * crack)):
            x0, y0 = r_.u(-0.03, 0.03), r_.u(-0.06, 0.06)
            cv.drawLine(x0, y0, x0 + r_.u(-0.04, 0.04), y0 + r_.u(-0.04, 0.04), P(PAPER, 0.004))

def d_apple(cv, t):
    cv.drawCircle(0, 0, 0.045, P(hexc('#e23b3b'))); cv.drawCircle(0, 0, 0.045, P(INK, 0.008))
    cv.drawLine(0, -0.045, 0.01, -0.07, P(hexc('#5a3a1a'), 0.008))
    cv.drawOval(skia.Rect(0.01, -0.075, 0.045, -0.055), P(hexc('#5ab040')))

def d_chalk(cv, t):
    cv.drawLine(-0.03, 0, 0.03, 0, P(PAPER, 0.02))

def d_pencil(cv, t, broken=0.0, glow=0.0):
    gap = 0.06 * broken
    ang = 18 * broken
    for side in (-1, 1):
        cv.save(); cv.translate(side * gap, 0); cv.rotate(side * ang * 0.5)
        if side < 0:
            cv.drawLine(-0.16, 0, 0.0, 0, P(hexc('#f2c230'), 0.022))
            cv.drawPath(poly([(-0.16, -0.011), (-0.2, 0), (-0.16, 0.011)]), P(hexc('#e8c8a0')))
            cv.drawCircle(-0.198, 0, 0.004, P(INK))
        else:
            cv.drawLine(0.0, 0, 0.16, 0, P(hexc('#f2c230'), 0.022))
            cv.drawLine(0.16, 0, 0.19, 0, P(hexc('#e8a0a0'), 0.022, cap='butt'))
        cv.restore()
    if glow > 0:
        cv.drawLine(-0.01, -0.015, 0.01, 0.015, P(calpha(RED, glow), 0.006))
        cv.drawCircle(0, 0, 0.05, P(calpha(RED, 0.4 * glow), blur=0.03))

def d_bun(cv, t):
    cv.drawOval(skia.Rect(-0.06, -0.035, 0.06, 0.035), P(hexc('#d9954a'))); cv.drawOval(skia.Rect(-0.06, -0.035, 0.06, 0.035), P(INK, 0.007))

def d_frame_down(cv, t):
    cv.drawRect(skia.Rect(-0.12, -0.025, 0.12, 0.0), P(hexc('#3a2a1a')))
    cv.drawRect(skia.Rect(-0.12, -0.025, 0.12, 0.0), P(INK, 0.006))

def d_soup(cv, t, steam=True):
    if steam:
        for k in range(3):
            ph = (t * 0.6 + k / 3) % 1.0
            x = -0.05 + k * 0.05 + math.sin(t * 2 + k) * 0.02
            cv.drawLine(x, -0.06 - ph * 0.25, x + 0.02, -0.1 - ph * 0.25, P(rgba(1, 1, 1, 0.4 * (1 - ph)), 0.01))

def d_bus(cv, t):
    col = hexc('#f2b632')
    cv.drawRoundRect(skia.Rect(0, -1.45, 4.2, -0.25), 0.15, 0.15, P(col))
    cv.drawRoundRect(skia.Rect(0, -1.45, 4.2, -0.25), 0.15, 0.15, P(INK, 0.03))
    for k in range(6):
        cv.drawRect(skia.Rect(0.25 + k * 0.62, -1.3, 0.75 + k * 0.62, -0.85), P(hexc('#9cc8e8')))
        cv.drawRect(skia.Rect(0.25 + k * 0.62, -1.3, 0.75 + k * 0.62, -0.85), P(INK, 0.015))
    cv.drawRect(skia.Rect(0, -0.6, 4.2, -0.5), P(hexc('#e8402f')))
    for wx in (0.8, 3.4):
        a = -t * 400
        cv.drawCircle(wx, -0.22, 0.22, P(INK)); cv.drawCircle(wx, -0.22, 0.1, P(hexc('#8a8a8a')))
        cv.drawLine(wx, -0.22, wx + 0.09 * math.cos(math.radians(a)), -0.22 + 0.09 * math.sin(math.radians(a)), P(INK, 0.02))
    draw_text(cv, '7  ШКОЛА', 3.0, -1.32, font('Oswald-Bold', 0.14), INK, 'center')

def d_gate(cv, t):
    c = hexc('#3a4458')
    cv.drawRect(skia.Rect(-0.15, -2.6, 0.15, 0.0), P(c)); cv.drawRect(skia.Rect(3.85, -2.6, 4.15, 0.0), P(c))
    cv.drawRect(skia.Rect(-0.2, -2.85, 4.2, -2.6), P(c))
    draw_text(cv, 'ШКОЛА № 3', 2.0, -2.66, font('RussoOne', 0.2), PAPER, 'center')
    for k in range(9):
        cv.drawLine(4.2 + k * 0.3, -1.6, 4.2 + k * 0.3, 0.0, P(c, 0.03))
    cv.drawLine(4.2, -1.6, 7.0, -1.6, P(c, 0.04))
    for k in range(9):
        cv.drawLine(-3.0 + k * 0.3, -1.6, -3.0 + k * 0.3, 0.0, P(c, 0.03))
    cv.drawLine(-3.0, -1.6, -0.2, -1.6, P(c, 0.04))

def d_chair_director(cv, t, glint=0.0):
    c = hexc('#05070f')
    cv.drawRoundRect(skia.Rect(-0.45, -1.7, 0.45, -0.3), 0.2, 0.2, P(c))
    cv.drawRect(skia.Rect(-0.55, -0.6, 0.55, -0.35), P(c))
    cv.drawLine(0, -0.3, 0, 0, P(c, 0.06)); cv.drawLine(-0.3, 0, 0.3, 0, P(c, 0.05))
    cv.drawRoundRect(skia.Rect(-0.47, -1.72, 0.47, -0.28), 0.2, 0.2, P(hexc('#2f7bff', 0.35), 0.015))
    # силуэт головы и очки-блик
    cv.drawCircle(0.0, -1.35, 0.12, P(hexc('#0a0e1a')))
    if glint > 0:
        for gx in (-0.045, 0.045):
            cv.drawCircle(gx, -1.36, 0.032, P(hexc('#9fd0ff', glint)))
            cv.drawCircle(gx, -1.36, 0.08, P(hexc('#4fa0ff', 0.4 * glint), blur=0.04))

def d_lamppost(cv, t, on=1.0, col='#ffd27a'):
    c = hexc('#15151f')
    cv.drawLine(0, 0, 0, -2.4, P(c, 0.05)); cv.drawLine(0, -2.4, 0.3, -2.5, P(c, 0.04))
    cv.drawCircle(0.32, -2.46, 0.08, P(hexc(col, 0.4 + 0.6 * on)))
    if on > 0:
        cv.drawPath(poly([(0.22, -2.42), (0.42, -2.42), (0.95, 0.0), (-0.3, 0.0)]), P(hexc(col, 0.10 * on)))
        cv.drawCircle(0.32, -2.4, 0.7, P(hexc(col, 0.18 * on), blur=0.35))

# ─────────────────────────── осколки телефона ───────────────────────────
class Shards(Layer):
    """Осколки: разлёт в t_hit, «откат» (обратный полёт) в t_back..t_back+back_dur."""
    def __init__(self, z, x, y, t_hit, t_back, back_dur=0.55, n=26, seed=9):
        super().__init__(z, None, name='shards')
        r = RNG(seed)
        self.x, self.y, self.t_hit, self.t_back, self.back_dur = x, y, t_hit, t_back, back_dur
        self.p = []
        for i in range(n):
            ang = r.u(-math.pi * 0.95, -math.pi * 0.05)
            sp = r.u(0.6, 2.4)
            self.p.append(dict(vx=math.cos(ang) * sp, vy=math.sin(ang) * sp, rot=r.u(-900, 900), s=r.u(0.012, 0.035),
                               col=r.choice(['#1a2a44', '#222833', '#8fd0ff', '#2a3a55'])))
    def pos(self, q, u):
        g = 6.0
        x = self.x + q['vx'] * u
        y = self.y + q['vy'] * u + 0.5 * g * u * u
        if y > self.y + 0.02:
            y = self.y + 0.02
        return x, y
    def draw(self, cv, t):
        if t < self.t_hit:
            return
        fly_end = self.t_back
        if t < fly_end:
            u = min(t - self.t_hit, 0.9)
        else:
            k = clamp((t - self.t_back) / self.back_dur)
            if k >= 1:
                return
            u = min(fly_end - self.t_hit, 0.9) * (1 - ease_in(k, 2.2))
        for q in self.p:
            x, y = self.pos(q, u)
            cv.save(); cv.translate(x, y); cv.rotate(q['rot'] * u)
            s = q['s']
            cv.drawPath(poly([(-s, -s * 0.6), (s, -s), (s * 0.6, s), (-s * 0.8, s * 0.7)]), P(hexc(q['col'])))
            cv.drawPath(poly([(-s, -s * 0.6), (s, -s), (s * 0.6, s), (-s * 0.8, s * 0.7)]), P(PAPER, 0.003))
            if t >= self.t_back:
                cv.drawLine(0, 0, -q['vx'] * 0.06, -q['vy'] * 0.06, P(calpha(RED, 0.6), 0.004))
            cv.restore()

# ─────────────────────────── экранные вставки ───────────────────────────
def notebook_panel(cv, t, lines_, title=None, sketch=None, a=1.0, x=W * 0.5, y=H * 0.5, w=980, h=640, rot=-3, underline=None):
    """Страница блокнота Миры (экранная вставка)."""
    if a <= 0:
        return
    cv.save(); cv.translate(x, y); cv.rotate(rot)
    cv.saveLayerAlpha(None, int(255 * a))
    cv.drawRect(skia.Rect(-w / 2 + 14, -h / 2 + 18, w / 2 + 14, h / 2 + 18), P(rgba(0, 0, 0, 0.35)))
    cv.drawRect(skia.Rect(-w / 2, -h / 2, w / 2, h / 2), P(hexc('#f7efcf')))
    for k in range(13):
        yy = -h / 2 + 90 + k * 42
        cv.drawLine(-w / 2 + 20, yy, w / 2 - 20, yy, P(hexc('#9ab4d0', 0.6), 2))
    cv.drawLine(-w / 2 + 90, -h / 2, -w / 2 + 90, h / 2, P(hexc('#e88a8a', 0.8), 2))
    for k in range(8):
        cv.drawCircle(-w / 2 + 40, -h / 2 + 60 + k * 75, 10, P(hexc('#2a2a2a')))
    yy = -h / 2 + 76
    if title:
        draw_text(cv, title, -w / 2 + 110, yy, font('Neucha', 50), hexc('#2a2f8a'))
        yy += 70
    fnt = font('Neucha', 36)
    for i, ln in enumerate(lines_):
        k = clamp((t - 0.25 - i * 0.55) / 0.5)
        if k <= 0:
            continue
        txt = ln[:max(1, int(len(ln) * k))]
        draw_text(cv, txt, -w / 2 + 110, yy + i * 42 * 1.0, fnt, hexc('#22264a'))
    if underline is not None:
        i, k = underline
        uw = fnt.measureText(lines_[i])
        ku = clamp(k)
        for j in range(2):
            kk = clamp(ku * 2 - j)
            cv.drawLine(-w / 2 + 110, yy + i * 42 + 8 + j * 9, -w / 2 + 110 + uw * kk, yy + i * 42 + 6 + j * 9, P(hexc('#d2302a'), 4))
    if sketch:
        sketch(cv, t, w, h)
    cv.restore()
    cv.restore()

def photo_panel(cv, t, a=1.0, x=W / 2, y=H / 2, rot=4, wind=0.0):
    """Порванное фото незнакомца: подросток держит за руку малыша в красном шарфе. Лица оторваны."""
    if a <= 0:
        return
    cv.save(); cv.translate(x + math.sin(t * 3) * 6 * wind, y); cv.rotate(rot + math.sin(t * 2.3) * 2 * wind)
    cv.saveLayerAlpha(None, int(255 * a))
    w, h = 760, 520
    tear = [(-w / 2, -h / 2 + 150)]
    r = RNG(3)
    for k in range(1, 12):
        tear.append((-w / 2 + k * w / 11, -h / 2 + 150 + r.u(-28, 28)))
    shape = [(-w / 2, h / 2), (w / 2, h / 2), (w / 2, -h / 2 + 150)] + tear[::-1]
    cv.drawPath(poly([(px + 12, py + 14) for px, py in shape]), P(rgba(0, 0, 0, 0.4)))
    cv.drawPath(poly(shape), P(hexc('#e9dcc0')))
    cv.save(); cv.clipPath(poly(shape))
    vgrad(cv, (-w / 2, -h / 2, w / 2, h / 2), [hexc('#c9a878'), hexc('#a88a60')])
    # мост на фоне
    cv.drawLine(-w / 2, 40, w / 2, 30, P(hexc('#7a6448'), 8))
    for k in range(6):
        cv.drawLine(-w / 2 + k * 140, 40, -w / 2 + k * 140 + 30, -60, P(hexc('#7a6448'), 4))
    # подросток (тело без лица) и малыш в красном шарфе
    ink = hexc('#2a2018')
    def fig(x0, sc, scarf=False):
        hip = (x0, 120 * sc + 60)
        neck = (x0, hip[1] - 120 * sc)
        cv.drawLine(hip[0], hip[1], neck[0], neck[1], P(ink, 10 * sc))
        cv.drawLine(hip[0], hip[1], hip[0] - 30 * sc, hip[1] + 110 * sc, P(ink, 10 * sc))
        cv.drawLine(hip[0], hip[1], hip[0] + 30 * sc, hip[1] + 110 * sc, P(ink, 10 * sc))
        if scarf:
            cv.drawLine(neck[0] - 18 * sc, neck[1] + 6, neck[0] + 18 * sc, neck[1] + 4, P(hexc('#c8402f'), 14 * sc))
            cv.drawLine(neck[0] - 10 * sc, neck[1] + 8, neck[0] - 40 * sc, neck[1] + 60 * sc, P(hexc('#c8402f'), 10 * sc))
        cv.drawCircle(neck[0], neck[1] - 40 * sc, 38 * sc, P(hexc('#efe6d0')))
        cv.drawCircle(neck[0], neck[1] - 40 * sc, 38 * sc, P(ink, 6 * sc))
        return neck
    n1 = fig(-80, 1.25)
    n2 = fig(110, 0.75, scarf=True)
    cv.drawLine(n1[0] + 10, n1[1] + 50, n2[0] - 10, n2[1] + 40, P(ink, 9))
    cv.restore()
    cv.drawPath(poly(shape), P(hexc('#5a4a30'), 3))
    cv.restore()
    cv.restore()

def thought_bubble(cv, t, a, x, y, w, h, draw_inside):
    if a <= 0:
        return
    cv.save()
    cv.saveLayerAlpha(None, int(255 * a))
    k = back_out(clamp(a))
    cv.translate(x, y); cv.scale(k, k)
    pth = skia.Path()
    r = RNG(8)
    pts = []
    for i in range(18):
        ang = i / 18 * 2 * math.pi
        rr = 1.0 + 0.08 * math.sin(i * 2.7)
        pts.append((math.cos(ang) * w / 2 * rr, math.sin(ang) * h / 2 * rr))
    cv.drawPath(smooth_path(pts, True), P(PAPER))
    cv.drawPath(smooth_path(pts, True), P(INK, 6))
    for i, (bx, by, br) in enumerate([(-w * 0.35, h * 0.62, 26), (-w * 0.45, h * 0.8, 16), (-w * 0.52, h * 0.93, 9)]):
        cv.drawCircle(bx, by, br, P(PAPER)); cv.drawCircle(bx, by, br, P(INK, 5))
    cv.save(); cv.clipPath(smooth_path(pts, True))
    draw_inside(cv, t, w, h)
    cv.restore()
    cv.restore()
    cv.restore()
