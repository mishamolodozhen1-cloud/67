# -*- coding: utf-8 -*-
"""Серия 1: сцены без голоса — спор у дверей школы, Норден днём, журнал незнакомца, «тем временем»."""
import math
import gfx as skia
from core import *
from sets import *
from stage import *
from props import *
import fx as FX
from stickman import Actor, pose
from ep1_extra import est
from ep1_b import bench

M = 'build/music/'

def abubble(sh, actor, t0, text, dur=2.6, kind='speech', dx=110, dy=-300, size=42, tail=None, maxw=560):
    """Пузырь, привязанный к голове персонажа (экранная позиция считается по камере шота)."""
    hy = HY(actor.who)
    def fn(cv, t):
        if t < t0 or t > t0 + dur:
            return
        x, y = sh.cam(t).to_screen(actor.x_at(t), hy, actor.z)
        tl = tail or (-dx * 0.55, 60)
        FX.bubble(cv, t - t0, text, x + dx, y + dy, dur=dur, size=size, tail=tl, kind=kind, maxw=maxw)
    screen(sh, fn)

# ---------------------------------------------------------------- 3.9 спор у дверей
def school_front(tod='morning'):
    L = []
    def wall(cv, t):
        c = hexc('#c9a27a'); d = hexc('#8a6a4a')
        cv.drawRect(skia.Rect(-12, -6.0, 12, 0.0), P(c))
        for i in range(-10, 11):
            for j in range(3):
                x = i * 1.1 - 0.35; y = -5.2 + j * 1.25
                if j == 2 and abs(x - 3.2) < 1.0:
                    continue
                cv.drawRect(skia.Rect(x, y, x + 0.7, y + 0.78), P(hexc('#9cc8e8')))
                cv.drawRect(skia.Rect(x, y, x + 0.7, y + 0.78), P(d, 0.04))
        cv.drawRect(skia.Rect(-12, -0.35, 12, 0.0), P(hexc('#a8845e')))
        # главная дверь
        cv.drawRect(skia.Rect(2.65, -1.55, 3.75, 0.0), P(d))
        cv.drawRect(skia.Rect(2.75, -1.45, 3.18, -0.02), P(hexc('#5a3e28')))
        cv.drawRect(skia.Rect(3.22, -1.45, 3.65, -0.02), P(hexc('#5a3e28')))
        cv.drawLine(3.13, -0.8, 3.13, -0.6, P(hexc('#d8d0b0'), 0.03))
        cv.drawLine(3.27, -0.8, 3.27, -0.6, P(hexc('#d8d0b0'), 0.03))
        # листок на двери
        cv.save(); cv.translate(3.43, -1.05); cv.rotate(4)
        cv.drawRect(skia.Rect(-0.16, -0.12, 0.16, 0.12), P(hexc('#f4f0e2')))
        for k in range(4):
            cv.drawLine(-0.12, -0.07 + k * 0.045, 0.1, -0.07 + k * 0.045, P(hexc('#555566'), 0.01))
        cv.restore()
        # часы над дверью
        cx, cy = 3.2, -2.1
        cv.drawCircle(cx, cy, 0.3, P(hexc('#f4f0e2'))); cv.drawCircle(cx, cy, 0.3, P(INK, 0.03))
        mm = 58 + clamp((t - 18.3) / 1.2) * 2
        a_m = math.radians(mm * 6 - 90); a_h = math.radians((7 + mm / 60) * 30 - 90)
        cv.drawLine(cx, cy, cx + math.cos(a_m) * 0.24, cy + math.sin(a_m) * 0.24, P(INK, 0.025))
        cv.drawLine(cx, cy, cx + math.cos(a_h) * 0.15, cy + math.sin(a_h) * 0.15, P(INK, 0.035))
        draw_text(cv, 'ШКОЛА № 3', 3.2, -2.7, font('RussoOne', 0.34), PAPER, 'center')
        # калитка во двор
        gx = 0.6
        cv.drawRect(skia.Rect(gx - 0.5, -1.25, gx + 0.5, 0.0), P(hexc('#6a7a5a')))
        for k in range(9):
            xx = gx - 0.45 + k * 0.11
            cv.drawLine(xx, -1.2, xx, 0.0, P(hexc('#3a4438'), 0.025))
        cv.drawLine(gx - 0.5, -1.2, gx + 0.5, -1.2, P(hexc('#3a4438'), 0.04))
        cv.drawRect(skia.Rect(gx - 0.42, -1.75, gx + 0.42, -1.42), P(hexc('#2a5a8a')))
        draw_text(cv, 'ДВОР', gx, -1.52, font('Oswald-Bold', 0.2), PAPER, 'center')
    L.append(Layer(0.35, wall, name='schoolfront'))
    def ground(cv, t):
        cv.drawRect(skia.Rect(-20, 0.0, 20, 4), P(hexc('#8d8a84')))
        for k in range(-40, 41):
            cv.drawLine(k * 0.7, 0, k * 1.1, 4, P(hexc('#7a7770'), 0.012))
    L.append(Layer(0.0, ground, name='yard'))
    def bushes(cv, t):
        r = RNG(31)
        for k in range(14):
            x = -9 + k * 1.5 + r.u(-0.3, 0.3)
            cv.drawCircle(x, 0.55, 0.42 + r.u(0, 0.2), P(hexc('#3c6a3a')))
            cv.drawCircle(x + 0.3, 0.48, 0.3 + r.u(0, 0.15), P(hexc('#4a7c44')))
    L.append(Layer(-0.9, bushes, name='bushes'))
    return L

def race(ep):
    ep.scene('3.9', 'Спор у дверей', 'Школьный двор, 07:58',
             'Спор №216: «до дверей — кто последний, тот покупает булки». Леон летит, Рэй идёт пешком — и всё равно выигрывает.')
    sh = mk('morning', school_front('morning'))
    ray = sh.add(Actor('RAY', x=-5.4, face=1, pose_='pockets', eyes='lazy', mouth='flat', wind=0.3))
    leon = sh.add(Actor('LEON', x=-5.0, face=1, eyes='happy', mouth='grin', wind=0.3))
    b = Beat(sh)
    b.sfx('amb_schoolyard', 0.0, gain=0.35)
    ray.move(0.0, -3.4, dur=1.8, ease='out'); leon.move(0.0, -2.9, dur=1.7, ease='out')
    sfx(sh, 'steps_walk', 0.0, gain=0.3, dur=1.8)
    leon.pose(1.9, 'point', 0.3).expr(1.9, eyes='happy', mouth='grin_open')
    abubble(sh, leon, 2.0, 'Спор №216! До дверей! Кто последний — с того булки!', dur=3.0, dx=200, dy=-300, size=52, maxw=600)
    ray.expr(5.0, eyes='lazy', mouth='flat')
    abubble(sh, ray, 5.1, '...Лень.', dur=1.8, kind='thought', dx=-150, dy=-260, tail=(60, 60), size=56)
    leon.pose(6.3, 'crouch', 0.25).expr(6.3, eyes='serious', mouth='grin')
    sfx(sh, 'sneaker_squeak', 6.4, gain=0.6)
    tr = 6.9
    leon.pose(tr, 'run_pose', 0.15).move(tr, 3.0, dur=1.45, ease='io').gait(tr, tr + 1.6, 'run')
    sfx(sh, 'whoosh_big', tr, gain=0.7)
    sfx(sh, 'run_steps', tr, gain=0.5, dur=1.5)
    sfxt(sh, tr + 0.05, 'ВЖУХ!', W * 0.42, H * 0.3, 130, color=hexc('#ffb347'), rot=-10, dur=0.8)
    screen(sh, lambda cv, t: FX.speed_lines(cv, t, alpha=0.45 * clamp((t - tr) / 0.1) * clamp((tr + 1.5 - t) / 0.2)) if tr <= t <= tr + 1.5 else None)
    mblur(sh, tr, tr + 1.5, 5)
    # Рэй просто идёт
    ray.move(tr + 0.4, 0.45, dur=5.6, ease='lin')
    ta = tr + 1.5
    leon.pose(ta, 'fist_up', 0.25).expr(ta, eyes='happy', mouth='grin_open')
    sfxt(sh, ta + 0.1, 'ПЕРВЫЙ!', W * 0.5, H * 0.24, 120, color=hexc('#f2c230'), rot=6, dur=1.1)
    tg = ta + 1.3
    leon.pose(tg, 'grab', 0.2).expr(tg, eyes='normal', mouth='o')
    sfx(sh, 'thud', tg + 0.15, gain=0.6); sfx(sh, 'thud', tg + 0.45, gain=0.5)
    sfxt(sh, tg + 0.15, 'ДЁРГ', W * 0.72, H * 0.3, 80, color=PAPER, rot=-4, dur=0.6)
    sfxt(sh, tg + 0.45, 'ДЁРГ', W * 0.78, H * 0.4, 80, color=PAPER, rot=5, dur=0.6)
    ts = tg + 1.0
    def sign(cv, t, a0=ts):
        u = t - a0
        if u < 0 or u > 2.8:
            return
        k = back_out(clamp(u / 0.25)) * clamp((2.8 - u) / 0.3)
        cv.save(); cv.translate(W * 0.5, H * 0.46); cv.rotate(3); cv.scale(k, k)
        cv.drawRect(skia.Rect(-372, -212, 388, 228), P(rgba(0, 0, 0, 0.35)))
        cv.drawRect(skia.Rect(-380, -220, 380, 220), P(hexc('#f4f0e2')))
        draw_text(cv, 'ЗАКРЫТО НА РЕМОНТ', 0, -110, font('Oswald-Bold', 72), hexc('#c8302a'), 'center')
        draw_text(cv, 'Вход — со двора, через калитку', 0, -10, font('Neucha', 50), hexc('#22264a'), 'center')
        draw_text(cv, '(да, уже вторую неделю)', 0, 70, font('Neucha', 40), hexc('#5a5a6a'), 'center')
        draw_text(cv, '— Администрация', 200, 160, font('Neucha', 36), hexc('#22264a'), 'center')
        cv.restore()
    screen(sh, sign)
    sfx(sh, 'paper_flutter', ts, gain=0.4)
    leon.expr(ts + 0.6, eyes='shock', mouth='o').set(ts + 0.6, 'sweat', 1.0, dur=0.3)
    tb = ts + 3.0
    leon.face(tb, -1)
    ray.pose(tb - 0.4, 'grab', 0.25)
    sfx(sh, 'click', tb - 0.2, gain=0.5)
    ray.pose(tb + 0.4, pose('pockets', rs=150, re=30), 0.3)   # ленивый взмах, не оборачиваясь
    sfx(sh, 'tick_mark', tb + 0.9, gain=0.6)
    def board(cv, t, a0=tb + 0.8):
        u = t - a0
        if u < 0 or u > 3.0:
            return
        k = ease_out(clamp(u / 0.3), 3) * clamp((3.0 - u) / 0.3)
        cv.save(); cv.translate(W * 0.5, H * 0.2); cv.scale(k, k)
        cv.drawRect(skia.Rect(-430, -110, 430, 110), P(hexc('#111111')))
        cv.drawRect(skia.Rect(-430, -110, 430, 110), P(hexc('#444444'), 6))
        flip = u > 1.0
        draw_text(cv, 'СПОР № 216', 0, -60, font('Oswald-Bold', 34), hexc('#ff9a5a'), 'center', tracking=6)
        sc = '0 : 1' if flip else '1 : 0'
        draw_text(cv, 'ЛЕОН', -260, 50, font('Oswald-Bold', 56), hexc('#ff5a3a'), 'center')
        draw_text(cv, sc, 0, 60, font('Oswald-Bold', 96), hexc('#ff5a3a'), 'center')
        draw_text(cv, 'РЭЙ', 260, 50, font('Oswald-Bold', 56), hexc('#ff5a3a'), 'center')
        if 0.95 < u < 1.25:
            cv.drawRect(skia.Rect(-430, -110, 430, 110), P(rgba(1, 0.45, 0.2, 0.35 * (1 - (u - 0.95) / 0.3))))
        cv.restore()
    screen(sh, board)
    sfx(sh, 'tick_mark', tb + 1.8, gain=0.7)
    ray.extra['alpha'] = [(0.0, 1.0)]
    ray.move(tb + 1.3, 0.75, dur=0.8, ease='in')
    ray.set(tb + 1.6, 'alpha', 0.0, dur=0.5)
    tk = tb + 3.9
    leon.pose(tk, 'arms_out', 0.2).expr(tk, eyes='angry', mouth='scream').set(tk, 'vein', 1.0, dur=0.2)
    sfxt(sh, tk + 0.05, 'ДА КАК?!', W * 0.5, H * 0.3, 150, color=hexc('#ff5a3a'), rot=-6, dur=1.4)
    sfx(sh, 'school_bell', tk + 1.0, gain=0.5)
    leon.face(tk + 1.4, -1).pose(tk + 1.4, 'run_pose', 0.15).move(tk + 1.4, -1.5, dur=1.2, ease='in').gait(tk + 1.4, tk + 2.8, 'run')
    sfx(sh, 'run_steps', tk + 1.4, gain=0.5, dur=1.1)
    b.t = tk + 2.4
    cam = C([(0, dict(x=-3.4, y=-0.95, zoom=470, aperture=0.4)), (1.8, dict(x=-3.1, y=-0.9, zoom=560, aperture=0.4)),
             (tr - 0.1, dict(x=-2.9, y=-0.9, zoom=580, aperture=0.4)), (tr + 1.4, dict(x=2.8, y=-1.0, zoom=600, aperture=0.4)),
             (tg, dict(x=3.0, y=-1.0, zoom=700, aperture=0.4)), (ts + 2.6, dict(x=3.0, y=-1.05, zoom=760, aperture=0.4)),
             (tb + 0.6, dict(x=1.7, y=-1.0, zoom=480, aperture=0.4)), (tk, dict(x=2.2, y=-1.0, zoom=560, aperture=0.4)),
             (tk + 2.4, dict(x=1.0, y=-1.0, zoom=520, aperture=0.4))])
    done(ep, sh, b, tail=0.0, cam=cam)

# ---------------------------------------------------------------- 5.5 Норден днём
def ferry_layer(z, y, x0, x1, t0, t1):
    def fn(cv, t):
        u = clamp((t - t0) / (t1 - t0))
        x = x0 + (x1 - x0) * u
        cv.save(); cv.translate(x, y)
        cv.drawPath(poly([(-1.6, 0), (1.8, 0), (1.4, 0.45), (-1.3, 0.45)]), P(hexc('#e8eef4')))
        cv.drawRect(skia.Rect(-1.6, 0.3, 1.8, 0.45), P(hexc('#c8302a')))
        cv.drawRect(skia.Rect(-0.9, -0.6, 0.9, 0.0), P(hexc('#f4f6f8')))
        for k in range(6):
            cv.drawRect(skia.Rect(-0.8 + k * 0.28, -0.45, -0.62 + k * 0.28, -0.25), P(hexc('#3a5068')))
        cv.drawRect(skia.Rect(0.2, -1.1, 0.5, -0.6), P(hexc('#c8302a')))
        cv.drawCircle(0.6 + (t * 0.3 % 1.0) * 0.6, -1.3 - (t * 0.3 % 1.0) * 0.6, 0.2 + (t * 0.3 % 1.0) * 0.3,
                      P(rgba(1, 1, 1, 0.35 * (1 - (t * 0.3 % 1.0))), blur=0.1))
        cv.restore()
    return Layer(z, fn, name='ferry')

def gull_sprite(cv, t, flap=1.0):
    w = math.sin(t * 18) * 0.5 * flap
    c = hexc('#f4f4f0')
    cv.drawOval(skia.Rect(-0.12, -0.05, 0.14, 0.05), P(c)); cv.drawOval(skia.Rect(-0.12, -0.05, 0.14, 0.05), P(INK, 0.012))
    cv.drawCircle(0.15, -0.04, 0.045, P(c)); cv.drawCircle(0.15, -0.04, 0.045, P(INK, 0.012))
    cv.drawLine(0.19, -0.04, 0.25, -0.02, P(hexc('#f2b030'), 0.02))
    pth = skia.Path(); pth.moveTo(-0.02, -0.02); pth.quadTo(-0.12, -0.25 * (0.3 + w), -0.3, -0.18 * (0.2 + w) - 0.05)
    cv.drawPath(pth, P(INK, 0.018))

def norden_day(ep):
    ep.scene('5.5', 'Норден днём', 'Гавань и набережная, после обеда',
             'Город живёт своей жизнью: паром, чайка-воришка и бабушка с яблоками.')
    l = panorama_layers('noon', cy=-1.3, zoom=320, hpx=560, inst=(1500, 230), lh=(250, 110), bridge=(820, 20, 240),
                        city_far=None, city_mid=None)
    Sz = 320 * 3.0 / 33.0
    l.append(ferry_layer(30.0, -1.3 + 90 / Sz, -700 / Sz, 500 / Sz, 0.0, 9.0))
    def pier(cv, t):
        cv.drawRect(skia.Rect(-30, -0.25, 30, 3), P(hexc('#6a5a4a')))
        for k in range(-30, 31):
            cv.drawLine(k * 0.9, -0.25, k * 0.9, 3, P(hexc('#4a3e32'), 0.03))
        for k in range(-8, 9):
            cv.drawRect(skia.Rect(k * 3.2 - 0.12, -0.75, k * 3.2 + 0.12, -0.25), P(hexc('#3a3430')))
            cv.drawCircle(k * 3.2, -0.78, 0.14, P(hexc('#3a3430')))
    l.append(Layer(1.0, pier, name='pier'))
    l.append(Layer(6.0, lambda cv, t: gulls(cv, t, n=6, seed=9, x0=-10, x1=10, y0=-6, y1=-3.2, size=0.3, col=hexc('#2a2848')), name='g'))
    est(ep, 'noon', l, (-1.6, -1.6, 300), (0.4, -1.4, 330), 'НОРДЕН · 14:10', 7.0, amb=['amb_harbor', 'gulls'], gain=0.45,
        sub='Гавань. Паром на Каменный остров — каждые сорок минут.', extra=lambda sh, b: sfx(sh, 'ferry_horn', 2.2, gain=0.55))
    # чайка-воришка
    sh = mk('noon', street_embank('noon') + [apple_cart(0.4, z=0.05)])
    gran = sh.add(Actor('GRANNY', x=1.35, face=-1, pose_='hold_front', eyes='happy', mouth='smile'))
    b = Beat(sh)
    b.sfx('amb_harbor', 0.0, gain=0.35); b.sfx('gulls', 0.0, gain=0.3)
    tg = 1.6
    gull = Obj(-0.1, lambda cv, t: gull_sprite(cv, t), x=0, y=0)
    def gpath(t):
        u = t - tg
        if u < 1.2:
            k = ease_out(clamp(u / 1.2), 2)
            return (-4.0 + 4.25 * k, -3.0 + 2.3 * k, 0.0)
        if u < 1.5:
            return (0.25, -0.72, 0.0)
        k = ease_in(clamp((u - 1.5) / 1.6), 2)
        return (0.25 + 5.0 * k, -0.72 - 3.0 * k, -12 * k)
    gull.custom = gpath
    sh.layers.append(gull)
    apple = Obj(-0.11, d_apple, x=0, y=0, scale=0.9)
    apple.custom = lambda t: ((0.25 + 5.0 * ease_in(clamp((t - tg - 1.5) / 1.6), 2) + 0.27), -0.72 - 3.0 * ease_in(clamp((t - tg - 1.5) / 1.6), 2) + 0.05, 0.0)
    apple.ak = [(0, 0.0), (tg + 1.4, 0.0, 'hold'), (tg + 1.41, 1.0, 'lin')]
    sh.layers.append(apple)
    sfx(sh, 'gull_flap', tg + 0.6, gain=0.5); sfx(sh, 'gull_call', tg + 1.3, gain=0.6)
    sfxt(sh, tg + 1.35, 'ЦАП!', W * 0.42, H * 0.45, 100, color=hexc('#ffffff'), rot=-8, dur=0.8)
    gran.expr(tg + 1.6, eyes='shock', mouth='o')
    gran.face(tg + 2.2, 1).pose(tg + 2.3, 'fist_up', 0.2).expr(tg + 2.3, eyes='angry', mouth='scream').set(tg + 2.3, 'vein', 1.0, dur=0.2)
    sfx(sh, 'cart_wobble', tg + 2.3, gain=0.5)
    abubble(sh, gran, tg + 2.4, 'Опять ты, Адмирал!!', dur=2.2, dx=-60, dy=-280, tail=(40, 70))
    gran.pose(tg + 5.0, 'hands_hips', 0.4).expr(tg + 5.0, eyes='closed', mouth='smile').set(tg + 5.0, 'vein', 0.0, dur=0.3)
    b.t = tg + 6.0
    done(ep, sh, b, tail=0.0, cam=C([(0, dict(x=0.6, y=-1.0, zoom=600, aperture=0.4)), (tg + 1.4, dict(x=0.4, y=-1.0, zoom=640, aperture=0.4)),
                                       (tg + 3.0, dict(x=1.4, y=-1.4, zoom=520, aperture=0.4)), (tg + 6.0, dict(x=1.2, y=-1.3, zoom=560, aperture=0.4))]))
    # маяк и мост, время идёт
    l2 = panorama_layers('golden', cy=-1.2, zoom=320, hpx=560, inst=(1550, 230), lh=(700, 160), bridge=(1300, 22, 260),
                         city_far=(6, 30, 110), city_mid=(60, 50, 170))
    est(ep, 'golden', l2, (1.2, -2.0, 300), (-0.2, -1.6, 340), 'НОРДЕН · 15:50', 5.5, amb=['wind_soft', 'gulls'], gain=0.4,
        sub='Последний урок. Скоро звонок.')

# ---------------------------------------------------------------- 6.8 журнал незнакомца
def dark_notebook(cv, t, lines_, a, strike=None, x=W * 0.5, y=H * 0.5, rot=2):
    if a <= 0:
        return
    w, h = 900, 600
    cv.save(); cv.translate(x, y); cv.rotate(rot)
    cv.saveLayerAlpha(None, int(255 * a))
    cv.drawRect(skia.Rect(-w / 2 + 16, -h / 2 + 20, w / 2 + 16, h / 2 + 20), P(rgba(0, 0, 0, 0.4)))
    cv.drawRoundRect(skia.Rect(-w / 2 - 22, -h / 2 - 22, w / 2 + 22, h / 2 + 22), 18, 18, P(hexc('#1e2430')))
    cv.drawRect(skia.Rect(-w / 2, -h / 2, w / 2, h / 2), P(hexc('#ece4cc')))
    cv.drawLine(0, -h / 2, 0, h / 2, P(hexc('#b8ae94'), 3))
    cv.drawLine(w / 2 - 60, -h / 2 - 22, w / 2 - 60, h / 2 + 22, P(hexc('#8a2a2a'), 8))   # ляссе
    fnt = font('Neucha', 38)
    draw_text(cv, 'Р. · вторник', -w / 2 + 40, -h / 2 + 70, font('Neucha', 48), hexc('#1b2333'))
    yy = -h / 2 + 140
    for i, ln in enumerate(lines_):
        k = clamp((t - 0.3 - i * 0.9) / 0.7)
        if k <= 0:
            continue
        col = hexc('#1b2333')
        draw_text(cv, ln[:max(1, int(len(ln) * k))], -w / 2 + 40, yy + i * 64, fnt, col)
        if strike is not None and i == strike[0]:
            ks = clamp(strike[1])
            if ks > 0:
                ww = fnt.measureText(ln)
                for j in range(3):
                    cv.drawLine(-w / 2 + 34, yy + i * 64 - 12 + j * 6, -w / 2 + 34 + (ww + 12) * clamp(ks * 1.5 - j * 0.25), yy + i * 64 - 16 + j * 7,
                                P(hexc('#1b2333'), 4))
    cv.restore()
    cv.restore()

def observer(ep):
    ep.scene('6.8', 'Журнал наблюдений', 'Набережная, скамейка, 16:25',
             'Незнакомец ведёт журнал: где был «Р.» весь день. «Сказать ему?» — зачёркнуто. «Не вмешиваться».')
    sh = mk('golden', street_embank('golden') + [bench(0.3, z=0.08)])
    man = sh.add(Actor('MAN', x=0.3, face=-1, pose_='sit_write', eyes='cold', mouth='flat', prop='notebook', wind=0.5))
    b = Beat(sh)
    b.sfx('amb_water_eve', 0.0, gain=0.4)
    b.sfx('wind_soft', 0.0, gain=0.3)
    lines_ = ['07:31 — набережная. Бабушка, яблоки.', '08:12 — автобус № 7. Спор № 215.', '12:40 — крыша школы. Ничего.',
              'Сказать ему?', 'Не вмешиваться.']
    tn = 1.6
    sfx(sh, 'pen_write', tn + 0.4, gain=0.45); sfx(sh, 'pen_write', tn + 1.4, gain=0.45); sfx(sh, 'pen_write', tn + 2.3, gain=0.45)
    sfx(sh, 'pen_write', tn + 3.1, gain=0.45)
    sfx(sh, 'pen_underline', tn + 4.2, gain=0.6)
    sfx(sh, 'pen_write', tn + 4.9, gain=0.5)
    def nb(cv, t):
        a = clamp((t - tn) / 0.4) * clamp((tn + 7.6 - t) / 0.4)
        dark_notebook(cv, t - tn, lines_, a, strike=(3, (t - tn - 4.0) / 0.5), x=W * 0.52, y=H * 0.48)
    screen(sh, nb)
    sfx(sh, 'page_flip', tn + 7.4, gain=0.5)
    tl = tn + 8.0
    man.prop(tl, None).pose(tl, 'sit', 0.5).face(tl + 0.6, 1)
    man.expr(tl + 0.6, eyes='serious', mouth='flat')
    screen(sh, lambda cv, t: FX.menacing(cv, t - tl - 0.8, W * 0.74, H * 0.34, color=hexc('#4fd0e8'), n=4, size=80, seed=3,
                                         alpha=clamp((t - tl - 0.8) / 0.5) * clamp((tl + 5.0 - t) / 0.5)) if t > tl + 0.8 else None)
    sfx(sh, 'drone_menace', tl + 0.7, gain=0.35, dur=4.0)
    b.t = tl + 4.6
    done(ep, sh, b, tail=0.0, cam=C([(0, dict(x=-0.6, y=-1.1, zoom=420, aperture=0.4)), (tn, dict(x=0.2, y=-0.9, zoom=640, aperture=0.5)),
                                       (tl, dict(x=0.3, y=-0.85, zoom=760, aperture=0.6)), (tl + 4.6, dict(x=0.6, y=-0.9, zoom=980, aperture=0.7))]))
    # POV: Рэй вдали, незнакомец — размытый передний план
    sh2 = mk('golden', street_embank('golden') + [bench(-0.75, z=-1.3, w=2.4)])
    man2 = sh2.add(Actor('MAN', x=-0.75, face=1, pose_='sit', eyes='cold', mouth='flat', z=-1.3, wind=0.5))
    ray = sh2.add(Actor('RAY', x=-0.6, face=1, pose_='pockets', eyes='lazy', mouth='flat', wind=0.4, z=0.6))
    b2 = Beat(sh2)
    b2.sfx('amb_water_eve', 0.0, gain=0.4)
    ray.move(0.2, 1.8, dur=6.5, ease='lin')
    sfx(sh2, 'steps_walk', 0.2, gain=0.15, dur=6.0)
    man2.pose(5.6, 'stand', 0.6)
    b2.t = 7.0
    done(ep, sh2, b2, tail=0.0, cam=C([(0, dict(x=-0.1, y=-0.95, zoom=520, aperture=0.9, focus=0.6)),
                                         (7.0, dict(x=0.15, y=-0.95, zoom=540, aperture=0.9, focus=0.6))]))

# ---------------------------------------------------------------- 11.5 тем временем
def room_simple(wall='#3a3456', floor='#2a2438', lamp=(1.6, -2.0), poster=None):
    L = []
    def back(cv, t):
        cv.drawRect(skia.Rect(-12, -6, 12, 0.02), P(hexc(wall)))
        cv.drawRect(skia.Rect(-12, -0.12, 12, 0.02), P(cmix(hexc(wall), hexc('#000000'), 0.3)))
        lx, ly = lamp
        cv.drawCircle(lx, ly, 2.2, P(hexc('#ffd27a', 0.16), blur=0.8))
        cv.drawCircle(lx, ly, 0.12, P(hexc('#ffe2a0')))
        if poster:
            poster(cv, t)
        # окно с ночным городом
        cv.save(); cv.clipRect(skia.Rect(-3.6, -2.6, -2.2, -1.3))
        vgrad(cv, (-3.6, -2.6, -2.2, -1.3), [hexc('#0b1026'), hexc('#1e1a3a')])
        r = RNG(4)
        for k in range(30):
            cv.drawRect(skia.Rect(-3.6 + r.u(0, 1.4), -1.7 + r.u(0, 0.4), -3.56 + r.u(0, 1.4), -1.66 + r.u(0, 0.4)), P(hexc('#ffd27a', 0.7)))
        cv.restore()
        cv.drawRect(skia.Rect(-3.6, -2.6, -2.2, -1.3), P(hexc('#1a1626'), 0.05))
        cv.drawLine(-2.9, -2.6, -2.9, -1.3, P(hexc('#1a1626'), 0.03))
    L.append(Layer(0.6, back, name='rback'))
    L.append(Layer(0.0, lambda cv, t: cv.drawRect(skia.Rect(-12, 0.0, 12, 4), P(hexc(floor))), name='rfloor'))
    return L

def meanwhile(ep):
    ep.scene('11.5', 'Тем временем', 'Комнаты Леона и Миры, ночь',
             'Леон приседает до сотни и бросает Рэю новый спор. Мира собирает на пробковой доске всё, что видела за день.')
    def poster(cv, t):
        cv.drawRect(skia.Rect(0.2, -2.6, 1.2, -1.4), P(hexc('#e8702f')))
        draw_text(cv, 'НЕ СДАВАЙСЯ', 0.7, -2.3, font('Oswald-Bold', 0.16), PAPER, 'center')
        cv.drawCircle(0.7, -1.85, 0.25, P(hexc('#f2c230')))
        cv.drawRect(skia.Rect(-1.6, -2.4, -0.7, -1.9), P(hexc('#2a6ab8')))
        draw_text(cv, '№ 215', -1.15, -2.08, font('Oswald-Bold', 0.18), PAPER, 'center')
    sh = mk('night', room_simple('#4a3a52', '#2e2638', lamp=(2.4, -2.2), poster=poster), grade=dict(tint=(hexc('#ff9a5a'), 0.10, 'soft')))
    leon = sh.add(Actor('LEON', x=-0.4, face=1, pose_='stand', eyes='serious', mouth='grin'))
    b = Beat(sh)
    b.sfx('amb_room_night', 0.0, gain=0.4)
    t0 = 0.6
    for i in range(4):
        tt = t0 + i * 0.9
        leon.pose(tt, 'crouch', 0.35, ls=70, le=10, rs=75, re=10).pose(tt + 0.45, 'stand', 0.35, ls=70, le=10, rs=75, re=10)
        sfx(sh, 'cloth_grab', tt + 0.3, gain=0.25)
        sfxt(sh, tt + 0.35, ['97!', '98!', '99!', '100!!'][i], W * (0.62 + 0.04 * i), H * (0.32 - 0.03 * i), 80 + i * 18,
             color=hexc('#ffb347'), rot=-6 + i * 4, dur=0.8)
    tf = t0 + 4.0
    leon.pose(tf, 'sit_ground', 0.3).expr(tf, eyes='closed', mouth='grin_open').set(tf, 'sweat', 1.0, dur=0.3)
    sfx(sh, 'thud', tf + 0.15, gain=0.5)
    tp = tf + 1.2
    leon.prop(tp, 'phone').pose(tp, pose('sit_ground', rs=60, re=95), 0.3).expr(tp, eyes='happy', mouth='grin')
    sfx(sh, 'phone_on', tp + 0.1, gain=0.5)
    def chat(cv, t, a0=tp + 0.4):
        u = t - a0
        if u < 0 or u > 5.0:
            return
        k = back_out(clamp(u / 0.3)) * clamp((5.0 - u) / 0.3)
        cv.save(); cv.translate(W * 0.66, H * 0.48); cv.scale(k, k); cv.rotate(-3)
        cv.drawRoundRect(skia.Rect(-230, -380, 230, 380), 40, 40, P(hexc('#1e2430')))
        cv.drawRect(skia.Rect(-205, -330, 205, 330), P(hexc('#eef2f6')))
        draw_text(cv, 'Рэй', 0, -280, font('Inter-SemiBold', 30), hexc('#1e2430'), 'center')
        cv.drawLine(-205, -255, 205, -255, P(hexc('#c8ccd4'), 2))
        def msg(y, txt, right, appear):
            if u < appear:
                return
            fnt = font('Inter-SemiBold', 28)
            tw = fnt.measureText(txt)
            x0 = 185 - tw - 30 if right else -185
            col = hexc('#ff8a3a') if right else hexc('#d8dce4')
            cv.drawRoundRect(skia.Rect(x0, y - 36, x0 + tw + 30, y + 14), 20, 20, P(col))
            draw_text(cv, txt, x0 + 15, y, fnt, PAPER if right else hexc('#1e2430'))
        msg(-190, 'Спор №217:', True, 0.4)
        msg(-130, 'завтра я первый в школе!', True, 0.9)
        msg(-60, 'И не через калитку!!', True, 1.5)
        msg(30, 'zzz', False, 3.0)
        cv.restore()
    screen(sh, chat)
    sfx(sh, 'click', tp + 0.8, gain=0.4); sfx(sh, 'click', tp + 1.3, gain=0.4); sfx(sh, 'click', tp + 1.9, gain=0.4)
    sfx(sh, 'beep_alert', tp + 3.4, gain=0.3)
    leon.expr(tp + 3.5, eyes='angry', mouth='grin_open').set(tp + 3.5, 'vein', 1.0, dur=0.2)
    sfxt(sh, tp + 3.6, 'ХА! ПРИНЯТО!', W * 0.3, H * 0.25, 90, color=hexc('#ffb347'), rot=-8, dur=1.2)
    b.t = tp + 5.6
    done(ep, sh, b, tail=0.0, cam=C([(0, dict(x=-0.2, y=-1.0, zoom=560, aperture=0.4)), (tf, dict(x=-0.3, y=-0.8, zoom=620, aperture=0.4)),
                                       (tp + 5.6, dict(x=0.1, y=-0.7, zoom=700, aperture=0.5))]))
    # Мира и доска
    notes = [(-0.15, -1.95, 'МОСТ\n7 лет назад', '#efe6cc'), (0.75, -2.05, 'Лестница\n16:42', '#fff2a0'),
             (0.3, -1.3, 'Телефон:\nразбит — цел', '#fff2a0'), (1.25, -1.45, 'Рэй?', '#ffd0d0')]
    def board(cv, t):
        cv.drawRect(skia.Rect(-0.6, -2.45, 1.75, -0.9), P(hexc('#b88a5a')))
        cv.drawRect(skia.Rect(-0.6, -2.45, 1.75, -0.9), P(hexc('#6a4a2a'), 0.04))
        r = RNG(8)
        for k in range(60):
            cv.drawCircle(-0.55 + r.u(0, 2.25), -2.4 + r.u(0, 1.45), 0.008, P(hexc('#8a6a3a')))
        for i, (x, y, txt, col) in enumerate(notes):
            ap = 1.0 if i < 3 else clamp((t - 6.2) / 0.2)
            if ap <= 0:
                continue
            cv.save(); cv.translate(x, y); cv.rotate([-4, 3, -2, 6][i])
            cv.drawRect(skia.Rect(-0.28, -0.2, 0.28, 0.2), P(hexc(col, ap)))
            for j, ln in enumerate(txt.split('\n')):
                draw_text(cv, ln, 0, -0.04 + j * 0.11, font('Neucha', 0.085 if i < 3 else 0.12), hexc('#22264a', ap), 'center')
            cv.drawCircle(0, -0.17, 0.025, P(hexc('#d2302a', ap)))
            cv.restore()
        # красная нить
        segs = [(0, 1, 1.0), (1, 2, 1.0), (2, 3, clamp((t - 6.6) / 0.8)), (0, 3, clamp((t - 7.4) / 0.8))]
        for (i, j, k) in segs:
            if k <= 0:
                continue
            x0, y0 = notes[i][0], notes[i][1] - 0.17; x1, y1 = notes[j][0], notes[j][1] - 0.17
            cv.drawLine(x0, y0, x0 + (x1 - x0) * k, y0 + (y1 - y0) * k, P(hexc('#d2302a'), 0.012))
    sh2 = mk('night', room_simple('#2e3448', '#22283a', lamp=(-1.6, -1.9)) + [Layer(0.5, board, name='board')],
             grade=dict(tint=(hexc('#6a8aff'), 0.10, 'soft')))
    mira = sh2.add(Actor('MIRA', x=-1.6, face=1, pose_='stand', eyes='normal', mouth='flat', prop='notebook'))
    b2 = Beat(sh2)
    b2.sfx('amb_room_night', 0.0, gain=0.4)
    sfx(sh2, 'clock_tick', 0.0, gain=0.25, dur=11.0)
    mira.move(1.0, -0.85, dur=1.6)
    mira.pose(4.0, 'think', 0.4).expr(4.0, eyes='serious', mouth='flat')
    mira.prop(5.6, 'paper').pose(5.6, 'reach', 0.4, rs=140, re=10)
    sfx(sh2, 'click', 6.2, gain=0.6)
    sfx(sh2, 'pen_underline', 6.6, gain=0.35); sfx(sh2, 'pen_underline', 7.4, gain=0.35)
    mira.prop(6.4, None).pose(6.6, 'hold_front', 0.4)
    mira.expr(8.4, eyes='cold', mouth='flat')
    sfx(sh2, 'sting_subtle', 8.4, gain=0.5)
    b2.t = 10.6
    done(ep, sh2, b2, tail=0.0, cam=C([(0, dict(x=-0.5, y=-1.25, zoom=460, aperture=0.15)), (4.0, dict(x=0.2, y=-1.45, zoom=560, aperture=0.15)),
                                         (8.2, dict(x=0.35, y=-1.55, zoom=680, aperture=0.15)), (10.6, dict(x=0.2, y=-1.45, zoom=700, aperture=0.15))]))
