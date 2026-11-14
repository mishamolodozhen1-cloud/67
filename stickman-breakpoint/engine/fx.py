# -*- coding: utf-8 -*-
"""Экранные эффекты в стилистике манги/аниме: фокус-линии, звукоподражания, плашки персонажей,
трещина-переход, «давящие» буквы, метка точки останова, вспышки, глитч."""
import math
import numpy as np
import gfx as skia
from core import *

def flash(cv, a, color=None):
    if a <= 0:
        return
    color = color or rgba(1, 1, 1, 1)
    cv.drawRect(skia.Rect(0, 0, W, H), P(calpha(color, clamp(a))))

def fade_black(cv, a):
    flash(cv, a, rgba(0, 0, 0, 1))

def focus_lines(cv, t, cx=W / 2, cy=H / 2, alpha=0.6, color=None, n=90, inner=0.42, seed=3, width=1.0):
    """Манга-фокус: радиальные клинья от краёв к центру."""
    color = color or INK
    r = RNG(seed + int(t * 12))
    R = math.hypot(W, H)
    for i in range(n):
        a = r.u(0, 2 * math.pi)
        w = r.u(0.002, 0.012) * width
        r0 = R * r.u(inner, inner + 0.18)
        x0, y0 = cx + math.cos(a) * r0, cy + math.sin(a) * r0
        x1, y1 = cx + math.cos(a - w) * R, cy + math.sin(a - w) * R
        x2, y2 = cx + math.cos(a + w) * R, cy + math.sin(a + w) * R
        cv.drawPath(poly([(x0, y0), (x1, y1), (x2, y2)]), P(calpha(color, alpha * r.u(0.4, 1.0))))

def speed_lines(cv, t, angle=0.0, alpha=0.5, color=None, n=40, seed=5, speed=3000):
    """Параллельные линии скорости (бег, рывок)."""
    color = color or rgba(1, 1, 1, 1)
    r = RNG(seed)
    ca, sa = math.cos(math.radians(angle)), math.sin(math.radians(angle))
    for i in range(n):
        y = r.u(-H * 0.2, H * 1.2)
        ln = r.u(200, 700)
        x = (r.u(0, W + 1400) - t * speed * r.u(0.7, 1.3)) % (W + 1400) - 700
        x0, y0 = x, y
        x1, y1 = x + ln, y
        X0 = W / 2 + (x0 - W / 2) * ca - (y0 - H / 2) * sa; Y0 = H / 2 + (x0 - W / 2) * sa + (y0 - H / 2) * ca
        X1 = W / 2 + (x1 - W / 2) * ca - (y1 - H / 2) * sa; Y1 = H / 2 + (x1 - W / 2) * sa + (y1 - H / 2) * ca
        cv.drawLine(X0, Y0, X1, Y1, P(calpha(color, alpha * r.u(0.3, 1.0)), r.u(1.5, 5)))

def sfx_text(cv, txt, x, y, size, t_local, color=None, outline=None, rot=-8, dur=1.2, fontname='RubikMonoOne', shake=4.0, skew=0.0):
    """Звукоподражание: выпрыгивает с перелётом, дрожит, гаснет."""
    if t_local < 0 or t_local > dur:
        return
    color = color or hexc('#ffe14a')
    outline = outline or INK
    k_in = back_out(t_local / 0.18)
    a = clamp((dur - t_local) / 0.25)
    sc = 0.4 + 0.6 * k_in
    fnt = font(fontname, size)
    cv.save()
    jx = fbm(t_local * 30, 3) * shake
    jy = fbm(t_local * 30, 7) * shake
    cv.translate(x + jx, y + jy)
    cv.rotate(rot)
    cv.scale(sc, sc)
    if skew:
        cv.ctx.transform(__import__('cairo').Matrix(1, 0, skew, 1, 0, 0))
    draw_text(cv, txt, 0, size * 0.35, fnt, calpha(color, a), 'center', stroke=calpha(outline, a), stroke_w=size * 0.22)
    draw_text(cv, txt, 0, size * 0.35, fnt, calpha(color, a), 'center', stroke=calpha(rgba(1, 1, 1, 1), a), stroke_w=size * 0.06)
    cv.restore()

def name_card(cv, t_local, name, line2, color, dur=3.2, side='right'):
    """Плашка-знакомство с персонажем: диагональная лента, большое имя, ироничная подпись."""
    if t_local < 0 or t_local > dur:
        return
    kin = ease_out(t_local / 0.35, 3)
    kout = ease_in(clamp((t_local - (dur - 0.3)) / 0.3), 2)
    off = (1 - kin) * 1400 + kout * 1600
    sgn = 1 if side == 'right' else -1
    cv.save()
    cv.translate(sgn * off, 0)
    # тёмная подложка-полоса под углом
    band = poly([(W * 0.42 if side == 'right' else 0, H * 0.58), (W, H * 0.5), (W, H * 0.86), (W * 0.36 if side == 'right' else 0, H * 0.92)]) \
        if side == 'right' else poly([(0, H * 0.5), (W * 0.58, H * 0.58), (W * 0.64, H * 0.92), (0, H * 0.86)])
    cv.drawPath(band, P(rgba(0.05, 0.04, 0.07, 0.88)))
    stripe = poly([(W * 0.45, H * 0.56), (W, H * 0.48), (W, H * 0.5), (W * 0.45, H * 0.58)]) if side == 'right' else \
        poly([(0, H * 0.48), (W * 0.55, H * 0.56), (W * 0.55, H * 0.58), (0, H * 0.5)])
    cv.drawPath(stripe, P(color))
    x0 = W * 0.5 if side == 'right' else W * 0.06
    # имя — буквы рассыпаются из стороны и собираются
    fn = font('Unbounded-ExtraBold', 120)
    xx = x0
    for i, ch in enumerate(name):
        ki = ease_out(clamp((t_local - 0.12 - i * 0.04) / 0.3), 3)
        dy = (1 - ki) * 80
        draw_text(cv, ch, xx, H * 0.75 + dy, fn, calpha(PAPER, ki), 'left', stroke=calpha(color, ki), stroke_w=10)
        draw_text(cv, ch, xx, H * 0.75 + dy, fn, calpha(PAPER, ki), 'left')
        xx += fn.measureText(ch) + 4
    k2 = ease_out(clamp((t_local - 0.5) / 0.4), 2)
    f2 = font('Inter-SemiBold', 38)
    draw_text(cv, line2, x0 + 6, H * 0.83, f2, calpha(color, k2), 'left')
    cv.restore()

def menacing(cv, t, x, y, color=None, n=5, size=90, seed=1, alpha=1.0, ch='Д'):
    """«Давящие» буквы, плывущие вокруг угрожающей фигуры (жанровый приём)."""
    color = color or hexc('#9b5cff')
    r = RNG(seed)
    fnt = font('RubikMonoOne', size)
    for i in range(n):
        ph = t * 0.6 + i * 0.37
        u = ph % 1.0
        xx = x + r.u(-260, 260) + math.sin(t * 1.3 + i) * 12
        yy = y + r.u(-200, 160) - u * 60
        a = alpha * math.sin(u * math.pi)
        s = r.u(0.7, 1.2)
        cv.save(); cv.translate(xx, yy); cv.rotate(r.u(-14, 14)); cv.scale(s, s)
        draw_text(cv, ch, 0, 0, fnt, calpha(color, a), 'center', stroke=calpha(INK, a), stroke_w=size * 0.12)
        cv.restore()

def breakpoint_mark(cv, x, y, r, a=1.0, t=0.0):
    """Метка точки останова: красная точка-кольцо как у отладчика."""
    if a <= 0:
        return
    pulse = 0.5 + 0.5 * math.sin(t * 8)
    cv.drawCircle(x, y, r * (2.2 + pulse * 0.4), P(calpha(RED, 0.25 * a), blur=r))
    cv.drawCircle(x, y, r, P(calpha(RED, a)))
    cv.drawCircle(x, y, r * 1.35, P(calpha(hexc('#ffd2c8'), 0.9 * a), r * 0.18))
    cv.drawLine(x - r * 0.35, y, x + r * 0.35, y, P(calpha(PAPER, a), r * 0.22))

def crack_path(seed, x0, y0, x1, y1, n=14, jag=40):
    r = RNG(seed)
    pts = [(x0, y0)]
    for i in range(1, n):
        u = i / n
        px = x0 + (x1 - x0) * u + r.u(-jag, jag)
        py = y0 + (y1 - y0) * u + r.u(-jag, jag)
        pts.append((px, py))
    pts.append((x1, y1))
    return pts

def crack(cv, prog, seed=7, color=None, width=6, glow=True, x0=-50, y0=H * 0.62, x1=W + 50, y1=H * 0.38):
    """Трещина по экрану, растёт с prog 0..1."""
    if prog <= 0:
        return
    color = color or PAPER
    pts = crack_path(seed, x0, y0, x1, y1)
    n = len(pts)
    m = prog * (n - 1)
    k = int(m)
    path = skia.Path(); path.moveTo(*pts[0])
    for i in range(1, k + 1):
        path.lineTo(*pts[i])
    if k < n - 1:
        f = m - k
        a, b = pts[k], pts[k + 1]
        path.lineTo(a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f)
    if glow:
        cv.drawPath(path, P(calpha(RED, 0.5), width * 4))
    cv.drawPath(path, P(color, width))
    # ответвления
    r = RNG(seed + 1)
    for i in range(1, k):
        if r.u() < 0.5:
            a = pts[i]
            ln = r.u(30, 110)
            ang = r.u(0, 2 * math.pi)
            cv.drawLine(a[0], a[1], a[0] + math.cos(ang) * ln, a[1] + math.sin(ang) * ln, P(color, width * 0.4))

def split_screen_by_crack(cv, img_surf, prog, seed=7):
    pass

def title_logo(cv, t, x=W / 2, y=H / 2, scale=1.0, alpha=1.0, crack_prog=1.0):
    """Логотип STICKMAN: BREAKPOINT."""
    cv.save(); cv.translate(x, y); cv.scale(scale, scale)
    f1 = font('Unbounded-ExtraBold', 120)
    f2 = font('RussoOne', 84)
    jit = fbm(t * 20, 2) * 2
    draw_text(cv, 'STICKMAN', 0, -40 + jit, f1, calpha(PAPER, alpha), 'center', stroke=calpha(INK, alpha), stroke_w=16, tracking=6)
    draw_text(cv, 'STICKMAN', 0, -40 + jit, f1, calpha(PAPER, alpha), 'center', tracking=6)
    # BREAKPOINT с «надломом»
    txt = 'BREAKPOINT'
    w = sum(f2.measureText(c) for c in txt) + 10 * (len(txt) - 1)
    xx = -w / 2
    for i, ch in enumerate(txt):
        dy = 70 + (8 if i >= 5 else 0) * crack_prog
        rot = (3 if i >= 5 else 0) * crack_prog
        cv.save(); cv.translate(xx, dy); cv.rotate(rot)
        col = RED if i >= 5 else PAPER
        draw_text(cv, ch, 0, 0, f2, calpha(col, alpha), 'left', stroke=calpha(INK, alpha), stroke_w=12)
        draw_text(cv, ch, 0, 0, f2, calpha(col, alpha), 'left')
        cv.restore()
        xx += f2.measureText(ch) + 10
    breakpoint_mark(cv, w / 2 + 50, 40, 16, alpha * crack_prog, t)
    cv.ctx.new_path()
    cv.restore()

def glitch(cv, amount, t, seed=0):
    """Горизонтальные срезы со сдвигом + разведение каналов (numpy по готовому кадру)."""
    if amount <= 0.01:
        return
    s = cv.surface
    s.flush()
    arr = np.ndarray((s.get_height(), s.get_width(), 4), np.uint8, s.get_data(), strides=(s.get_stride(), 4, 1))
    r = RNG(seed + int(t * 30))
    for i in range(int(6 + 14 * amount)):
        y0 = r.i(0, H - 40); h = r.i(6, int(20 + 80 * amount))
        dx = int(r.u(-60, 60) * amount)
        arr[y0:y0 + h] = np.roll(arr[y0:y0 + h], dx, axis=1)
    sh = int(10 * amount)
    if sh:
        arr[:, :, 2] = np.roll(arr[:, :, 2], sh, axis=1)
        arr[:, :, 0] = np.roll(arr[:, :, 0], -sh, axis=1)
    s.mark_dirty()

def ink_wipe(cv, prog, color=None, seed=2, direction=1):
    """Переход «мазок тушью»: широкая кисть закрывает кадр."""
    if prog <= 0:
        return
    color = color or INK
    r = RNG(seed)
    for k in range(7):
        y = (k + 0.5) * H / 7
        p = clamp(prog * 1.6 - k * 0.08)
        if p <= 0:
            continue
        x_end = -100 + p * (W + 400)
        if direction < 0:
            pth = poly([(W + 100, y - 110), (W + 100 - p * (W + 400), y - 90 + r.u(-20, 20)),
                        (W + 100 - p * (W + 400) - 60, y + r.u(-10, 10)), (W + 100 - p * (W + 400), y + 100), (W + 100, y + 110)])
        else:
            pth = poly([(-100, y - 110), (x_end, y - 90 + r.u(-20, 20)), (x_end + 60, y + r.u(-10, 10)), (x_end, y + 100), (-100, y + 110)])
        cv.drawPath(pth, P(color))

def eyecatch(cv, t, dur=7.0):
    """Айкатч в середине серии."""
    vgrad(cv, (0, 0, W, H), [hexc('#16131a'), hexc('#2a1420')])
    focus_lines(cv, t * 0.2, alpha=0.18, color=RED, n=70, inner=0.25, seed=11)
    k = ease_out(clamp(t / 0.6), 3)
    title_logo(cv, t, W / 2, H * 0.42, 0.75 + 0.05 * k, alpha=k)
    a = clamp((t - 0.8) / 0.5) * clamp((dur - t) / 0.4)
    draw_text(cv, 'СЕРИЯ 1 · ОБЫЧНЫЙ ВТОРНИК', W / 2, H * 0.72, font('Unbounded-Medium', 34), calpha(PAPER, a), 'center', tracking=4)

def credits_block(cv, lines_, x, y, a=1.0, size=34, align='left', gap=1.45, color=None):
    color = color or PAPER
    for i, (k, v) in enumerate(lines_):
        yy = y + i * size * gap * 1.6
        draw_text(cv, k, x, yy, font('Inter-SemiBold', size * 0.62), calpha(hexc('#c8c0d8'), a * 0.85), align)
        draw_text(cv, v, x, yy + size * 1.0, font('Unbounded-Medium', size), calpha(color, a), align)
