# -*- coding: utf-8 -*-
"""Серия 1: коридор (перемена), установочные планы, монолог на мосту, эпилог Сол, сцена после титров."""
import math
import gfx as skia
from core import *
from sets import *
from stage import *
from props import *
import fx as FX
from stickman import Actor, pose

def corridor(tod='noon'):
    p = pal(tod)
    L = []
    def back(cv, t):
        cv.drawRect(skia.Rect(-20, -6, 20, 0.02), P(hexc('#d8dccb')))
        cv.drawRect(skia.Rect(-20, -0.9, 20, 0.02), P(hexc('#8fa3a0')))
        cv.drawLine(-20, -0.9, 20, -0.9, P(hexc('#5f7471'), 0.03))
        # шкафчики
        for k in range(-12, 4):
            x = k * 0.5
            c = hexc('#4f7fa8') if k % 3 else hexc('#5a8ab2')
            cv.drawRect(skia.Rect(x, -1.75, x + 0.47, -0.02), P(c))
            cv.drawRect(skia.Rect(x, -1.75, x + 0.47, -0.02), P(hexc('#2a4a68'), 0.012))
            for j in range(3):
                cv.drawLine(x + 0.1, -1.6 + j * 0.05, x + 0.37, -1.6 + j * 0.05, P(hexc('#2a4a68'), 0.01))
            cv.drawRect(skia.Rect(x + 0.38, -1.0, x + 0.42, -0.85), P(hexc('#c8c8c8')))
        # окна
        for k in range(3):
            x0 = 2.4 + k * 1.6
            cv.save(); cv.clipRect(skia.Rect(x0, -2.5, x0 + 1.2, -1.05))
            vgrad(cv, (x0, -2.5, x0 + 1.2, -1.05), [hexc(c) for c in p['sky']])
            if k == 0:
                institute(cv, x0 + 0.6, -1.12, 0.026, tod, t, pulse=clamp(vertex_pulse(t), 0, 1))
            cv.restore()
            cv.drawRect(skia.Rect(x0, -2.5, x0 + 1.2, -1.05), P(hexc('#f4f4f0'), 0.05))
        # доска объявлений
        cv.drawRect(skia.Rect(-7.4, -2.4, -6.0, -1.85), P(hexc('#a07a50')))
        for k, txt in enumerate(['ЭКСКУРСИЯ', '«ВЕРТЕКС»', 'ПЯТНИЦА']):
            draw_text(cv, txt, -6.7, -2.22 + k * 0.13, font('Oswald-Bold', 0.1), hexc('#1e2a4a'), 'center')
        cv.drawRect(skia.Rect(-7.32, -2.33, -6.08, -1.92), P(hexc('#f4f4f0', 0.5)))
    L.append(Layer(1.4, back, name='corrwall'))
    def floor(cv, t):
        cv.drawRect(skia.Rect(-20, 0.0, 20, 4), P(hexc('#b4a68c')))
        for k in range(-40, 41):
            cv.drawLine(k * 0.6, 0, k * 0.9, 4, P(hexc('#9a8c74'), 0.012))
    L.append(Layer(0.0, floor, name='corrfloor'))
    return L

def stairwell():
    """Лестничный пролёт: перила сверху, пол этажом ниже (вид вниз)."""
    L = []
    def back(cv, t):
        cv.drawRect(skia.Rect(-10, -4, 10, 6), P(hexc('#c8ccbc')))
        # пролёты лестницы, уходящие вниз
        for j in range(5):
            y = 0.4 + j * 0.25
            cv.drawRect(skia.Rect(-3 + j * 0.25, y, 3 - j * 0.25, y + 0.12), P(hexc('#9aa090')))
            cv.drawLine(-3 + j * 0.25, y, 3 - j * 0.25, y, P(hexc('#6a7064'), 0.012))
        cv.drawRect(skia.Rect(-1.8, 1.55, 1.8, 6), P(hexc('#b4a68c')))
    L.append(Layer(1.0, back, name='swback'))
    def rail(cv, t):
        c = hexc('#3a4458')
        cv.drawLine(-6, -0.95, 6, -0.95, P(c, 0.05))
        for k in range(-24, 25):
            cv.drawLine(k * 0.25, -0.95, k * 0.25, 0.0, P(c, 0.02))
        cv.drawRect(skia.Rect(-6, 0.0, 6, 0.12), P(hexc('#9aa090')))
    L.append(Layer(0.0, rail, name='swrail'))
    return L

SCN = {'1': ('Комната Рэя', 'Квартира Рэя, утро'), '4': ('Урок физики', 'Школа №3'), '5': ('Крыша школы', 'Крыша школы'),
       '7': ('Набережная, лестница', 'Набережная'), '8': ('Мост в тумане', 'Большой мост'), '9': ('Ужин', 'Кухня, вечер'),
       '10': ('Институт «Вертекс»', 'Лаборатория, ночь')}

def est(ep, tod, layers, cam0, cam1, label, dur=7.0, amb=None, gain=0.5, sub=None, sid=None):
    """Установочный план с плашкой места/времени."""
    if sid:
        ep.scene(sid, SCN[sid][0], SCN[sid][1])
    sh = mk(tod, layers)
    b = Beat(sh)
    if amb:
        for a in (amb if isinstance(amb, (list, tuple)) else [amb]):
            b.sfx(a, 0.0, gain=gain)
    def lab_(cv, t):
        a = clamp((t - 0.6) / 0.5) * clamp((dur - 0.4 - t) / 0.5)
        if a <= 0:
            return
        x, y = 90, 120
        cv.drawRect(skia.Rect(x - 20, y - 56, x + 26 + font('Unbounded-Medium', 34).measureText(label) * a, y + 20), P(rgba(0.04, 0.03, 0.06, 0.7 * a)))
        cv.drawRect(skia.Rect(x - 20, y - 56, x - 12, y + 20), P(calpha(RED, a)))
        draw_text(cv, label[:max(1, int(len(label) * clamp((t - 0.6) / 0.7)))], x, y, font('Unbounded-Medium', 34), calpha(PAPER, a), 'left', tracking=3)
        if sub:
            draw_text(cv, sub, x, y + 52, font('Inter-SemiBold', 26), calpha(hexc('#d8d0e8'), a), 'left')
    screen(sh, lab_)
    b.t = dur
    sh.cam = C([(0, dict(x=cam0[0], y=cam0[1], zoom=cam0[2], roll=cam0[3] if len(cam0) > 3 else 0)),
                (dur, dict(x=cam1[0], y=cam1[1], zoom=cam1[2], roll=cam1[3] if len(cam1) > 3 else 0))])
    sh.dur = dur
    ep.append(sh)
    return sh

def est_morning(ep):
    l = panorama_layers('dawn', cy=-1.4, zoom=300, hpx=560, inst=(1500, 230), lh=(260, 110), bridge=(820, 20, 240),
                        city_far=(6, 30, 110), city_mid=(60, 50, 170))
    def roofs(cv, t):
        cv.drawPicture(SKY_PICS.setdefault('dawn_roofs', skyline_picture(72, 'dawn', -40, 40, 3.2, 0.6, 3.0, 0.8, 2.2, '#2a2848', 0.25)))
    l.append(Layer(5.0, roofs, name='roofs'))
    l.append(Layer(6.0, lambda cv, t: gulls(cv, t, n=5, seed=7, x0=-12, x1=12, y0=-6, y1=-3.5, size=0.3, col=hexc('#2a2848')), name='g'))
    est(ep, 'dawn', l, (-1.0, -2.2, 300), (1.0, -1.7, 330), 'ВТОРНИК · 06:58', 7.5, amb=['amb_harbor', 'gulls'], gain=0.45,
        sub='Норден просыпается. Как обычно.', sid='1')

def est_school(ep):
    l = panorama_layers('morning', cy=-1.2, zoom=330, hpx=560, inst=(1500, 220), lh=(200, 100), bridge=(700, 18, 220),
                        city_far=(6, 30, 110), city_mid=(50, 40, 140))
    def school(cv, t):
        c = hexc('#c9a27a'); d = hexc('#8a6a4a')
        cv.drawRect(skia.Rect(-6, -4.2, 6, 0.0), P(c))
        cv.drawRect(skia.Rect(-6.2, -4.4, 6.2, -4.2), P(d))
        for i in range(10):
            for j in range(3):
                x = -5.4 + i * 1.1; y = -3.7 + j * 1.2
                cv.drawRect(skia.Rect(x, y, x + 0.7, y + 0.75), P(hexc('#9cc8e8')))
                cv.drawRect(skia.Rect(x, y, x + 0.7, y + 0.75), P(d, 0.04))
        cv.drawRect(skia.Rect(-0.8, -1.4, 0.8, 0.0), P(d))
        draw_text(cv, 'ШКОЛА № 3', 0, -3.95, font('RussoOne', 0.42), PAPER, 'center')
        cv.drawRect(skia.Rect(-20, 0.0, 20, 3), P(hexc('#8d8a84')))
    l.append(Layer(3.0, school, name='school'))
    est(ep, 'morning', l, (-0.5, -2.4, 300), (0.5, -2.0, 330), 'ШКОЛА № 3 · 08:00', 6.5, amb=['amb_city_far'], gain=0.4, sid='4')

def est_lunch(ep):
    est(ep, 'noon', school_roof('noon'), (-2.0, -2.6, 300), (0.0, -1.6, 360), 'БОЛЬШАЯ ПЕРЕМЕНА · 12:40', 5.5, amb=['wind_roof'], gain=0.4, sid='5')

def est_evening(ep):
    est(ep, 'golden', stairs_embank('golden'), (-3.5, -2.2, 320), (-2.0, -1.3, 360), 'НАБЕРЕЖНАЯ · 16:38', 6.0, amb=['amb_water_eve'], gain=0.45, sid='7')

def est_home(ep):
    l = panorama_layers('dusk', cy=-1.4, zoom=300, hpx=600, inst=(1500, 230), lh=(260, 110), bridge=(820, 20, 240),
                        city_far=(6, 30, 110), city_mid=(60, 50, 170))
    def block(cv, t):
        c = hexc('#2a2440')
        cv.drawRect(skia.Rect(-3, -6.5, 3, 0.0), P(c))
        r = RNG(14)
        for i in range(8):
            for j in range(9):
                x = -2.6 + i * 0.66; y = -6.1 + j * 0.68
                on = r.u() < 0.55
                if (i, j) == (5, 6):
                    on = True
                cv.drawRect(skia.Rect(x, y, x + 0.4, y + 0.42), P(hexc('#ffd27a', 0.85) if on else hexc('#3a3456')))
        cv.drawRect(skia.Rect(-20, 0.0, 20, 3), P(hexc('#1e1a30')))
    l.append(Layer(4.0, block, name='block'))
    est(ep, 'dusk', l, (0.0, -3.2, 300), (0.6, -2.4, 360), 'ДОМ · 19:20', 6.0, amb=['amb_street_eve'], gain=0.4, sid='9')

def est_institute(ep):
    from ep1_cold import institute_close
    est(ep, 'night', institute_close('night'), (0.8, -1.45, 250), (-0.4, -1.8, 320), 'ИНСТИТУТ «ВЕРТЕКС» · 23:05', 6.5, amb=['hum_low', 'amb_night'], gain=0.4, sid='10')

def sc45_corridor(ep):
    ep.scene('4.5', 'Коридор', 'Школьный коридор, перемена',
             'Кран отбирает обед у Тима. Рэй: «Не моё дело». Мира проверяет свою гипотезу карандашом.')
    sh = mk('noon', corridor('noon'))
    kos = sh.add(Actor('KOSTYA', x=-3.6, face=1, pose_='stand', eyes='angry', mouth='grin', z=0.4))
    tim = sh.add(Actor('TIM', x=-3.0, face=-1, pose_='hold_front', eyes='sad', mouth='frown', prop='bun', z=0.4))
    ray = sh.add(Actor('RAY', x=0.2, face=-1, pose_='pockets', eyes='lazy', z=0.0))
    leon = sh.add(Actor('LEON', x=0.85, face=-1, pose_='stand', eyes='normal', z=0.0))
    for k, x in enumerate((-5.5, 2.4, 3.2)):
        e = sh.add(Actor('EXTRA', x=x, face=1 if k % 2 else -1, eyes='dot', z=0.9, scale=0.95))
        e.move(0, x + (2.5 if k % 2 else -2.5), dur=12, ease='lin')
    b = Beat(sh)
    b.sfx('corridor_amb', 0.0, gain=0.5)
    b.wait(0.8)
    kos.pose(b.t, 'grab', 0.3)
    b.say(kos, 'k01', gap=0.2)
    tg = b.t - 0.4
    tim.prop(tg, None); kos.prop(tg, 'bun')
    sfx(sh, 'swipe', tg, gain=0.5)
    tim.pose(b.t, 'cower', 0.3)
    b.say(tim, 'k02', gap=0.2)
    kos.pose(b.t, 'eat', 0.3).expr(b.t, eyes='happy', mouth='grin')
    b.say(kos, 'k03', gap=0.5)
    kos.face(b.t, -1).move(b.t + 0.2, -8.0, dur=4.0, ease='in')
    leon.pose(b.t, 'point', 0.3).expr(b.t, eyes='angry', mouth='teeth').set(b.t, 'vein', 1.0, dur=0.2)
    b.say(leon, 'k04', gap=0.3)
    ray.expr(b.t, eyes='lazy', mouth='flat')
    b.say(ray, 'k05', gap=0.3)
    leon.pose(b.t, 'cross', 0.4).expr(b.t, eyes='sad', mouth='frown').set(b.t, 'vein', 0.0, dur=0.3)
    b.say(leon, 'k06', gap=0.4)
    ray.pose(b.t, 'pockets', 0.4, head=14).expr(b.t, eyes='normal', mouth='flat')
    t7, t7e = b.say(ray, 'k07', gap=0.3)
    # кулак в кармане сжимается: крупно
    tfist = b.t
    sfx(sh, 'fist_clench', tfist + 0.2, gain=0.6)
    b.wait(1.6)
    tim.face(b.t, 1).move(b.t, -6.0, dur=2.5, ease='in')
    from stickman import hand_world
    hx, hy = hand_world(ray, tfist + 0.5)
    done(ep, sh, b, tail=0.0, cam=C([(0, dict(x=-2.0, y=-0.9, zoom=520, aperture=0.4, focus=0.4)), (t7 - 2.0, dict(x=-0.2, y=-0.9, zoom=600, aperture=0.4)),
                                       (tfist, dict(x=0.3, y=-0.85, zoom=760, aperture=0.5)),
                                       (tfist + 0.3, dict(x=hx, y=hy, zoom=2000, aperture=0.9, focus=0.0), 'io3'),
                                       (tfist + 1.6, dict(x=hx, y=hy, zoom=2100, aperture=0.9))]))
    # ── Мира уводит Рэя; Леон к капитану ─────────────────────────
    sh = mk('noon', corridor('noon'))
    ray = sh.add(Actor('RAY', x=0.2, face=-1, pose_='pockets', eyes='lazy'))
    leon = sh.add(Actor('LEON', x=0.85, face=-1, pose_='cross', eyes='normal'))
    mira = sh.add(Actor('MIRA', x=-2.6, face=1, pose_='hold_front', eyes='normal', prop='notebook'))
    b = Beat(sh)
    b.sfx('corridor_amb', 0.0, gain=0.45)
    mira.move(0.0, -0.5, dur=1.4, ease='out')
    b.wait(1.4)
    b.say(mira, 'k08', gap=0.25)
    leon.expr(b.t, eyes='happy', mouth='grin').pose(b.t, 'point', 0.3).set(b.t, 'blush', 1.0, dur=0.3)
    b.say(leon, 'k09', gap=0.2)
    ray.face(b.t, 1).expr(b.t, eyes='lazy', mouth='flat')
    b.say(ray, 'k10', gap=0.2)
    leon.face(b.t, 1).pose(b.t, 'fist_up', 0.3).expr(b.t, eyes='happy', mouth='grin_open').set(b.t, 'blush', 0.0, dur=0.2)
    b.say(leon, 'k11', gap=0.1)
    leon.move(b.t - 0.8, 7.0, dur=1.8, ease='in').gait(b.t - 0.8, b.t + 2, 'run')
    sfx(sh, 'run_steps', b.t - 0.8, gain=0.5, dur=1.6)
    b.wait(1.0)
    done(ep, sh, b, tail=0.0, cam=C([(0, dict(x=-0.3, y=-0.9, zoom=560, aperture=0.4)), (60, dict(x=0.4, y=-0.9, zoom=640, aperture=0.4))]))
    # ── лестничный пролёт: карандаш ───────────────────────────────
    sh = mk('noon', stairwell())
    ray = sh.add(Actor('RAY', x=-0.55, face=1, pose_='pockets', eyes='lazy'))
    mira = sh.add(Actor('MIRA', x=0.25, face=-1, pose_='stand', eyes='normal', prop='pencil'))
    pen = Obj(-0.1, lambda cv, t: d_pencil(cv, t, broken=Track(pk)(t)), x=0, y=0)
    pk = [(0.0, 0.0)]
    sh.layers.append(pen)
    b = Beat(sh)
    b.sfx('corridor_amb', 0.0, gain=0.3)
    b.wait(0.5)
    b.say(mira, 'k12', gap=0.3)
    b.say(ray, 'k13', gap=0.3)
    mira.face(b.t, 1).pose(b.t, 'reach', 0.4, lean=8, rs=95, re=0)
    td = b.t + 0.7
    mira.prop(td, None)
    pen.custom = ballistic(0.47, -0.95, 0.05, 0.0, td, g=6.0, floor=1.55, spin=500)
    pen.ak = [(0, 0.0), (td - 0.01, 0.0, 'hold'), (td, 1.0, 'lin')]
    t_land = td + math.sqrt(2 * (1.55 + 0.95) / 6.0)
    pk += [(t_land, 0.0, 'hold'), (t_land + 0.05, 0.6, 'lin')]
    sfx(sh, 'whoosh_small', td, gain=0.3)
    sfx(sh, 'pencil_tick', t_land, gain=0.8)
    sfxt(sh, t_land, 'тк', W * 0.55, H * 0.7, 70, color=hexc('#ffffff'), rot=0, dur=0.7)
    b.t = t_land + 1.4
    mira.pose(b.t - 0.6, 'think', 0.4)
    b.say(mira, 'k14', gap=0.3)
    ray.expr(b.t, eyes='wide', mouth='o').set(b.t, 'sweat', 1.0, dur=0.3)
    b.say(ray, 'k15', gap=0.3)
    mira.expr(b.t, eyes='normal', mouth='smile')
    b.say(mira, 'k16', gap=0.3)
    ray.expr(b.t, eyes='lazy', mouth='flat').set(b.t, 'sweat', 0.0, dur=0.3)
    b.say(ray, 'k17', gap=0.3)
    mira.set(b.t, 'glint', 1.0, dur=0.1).set(b.t + 0.4, 'glint', 0.0, dur=0.3)
    b.say(mira, 'k18', gap=0.3)
    mira.face(b.t, -1).move(b.t + 0.2, -4.0, dur=2.6, ease='in')
    ray.pose(b.t + 0.8, 'shrug', 0.4)
    b.wait(2.4)
    done(ep, sh, b, tail=0.0, cam=C([(0, dict(x=-0.15, y=-0.95, zoom=820, aperture=0.5)), (td - 0.2, dict(x=0.2, y=-0.9, zoom=760, aperture=0.5)),
                                       (td + 0.15, dict(x=0.45, y=0.3, zoom=600, aperture=0.0), 'io'),
                                       (t_land + 0.2, dict(x=0.5, y=1.3, zoom=900, aperture=0.0)),
                                       (t_land + 1.2, dict(x=-0.1, y=-0.9, zoom=760, aperture=0.5), 'io3'),
                                       (90, dict(x=0.0, y=-0.9, zoom=800, aperture=0.5))]))

def bridge_vo(ep):
    """Внутренний монолог Рэя на мосту (до встречи с незнакомцем)."""
    ep.scene('8', 'Мост в тумане', 'Большой мост Нордена, сумерки')
    sh = mk('dusk', bridge_deck('dusk') + [bridge_rail_front('dusk', z=-0.7)])
    ray = sh.add(Actor('RAY', x=-9.0, face=1, pose_='pockets', eyes='normal', wind=0.6))
    b = Beat(sh)
    b.sfx('amb_bridge_fog', 0.0, gain=0.5)
    lamps_on = []
    def lamps(cv, t):
        # фонари загораются по одному (вспышка-ореол)
        for k in range(6):
            tk = 0.8 + k * 0.9
            a = clamp((t - tk) / 0.15)
            if a <= 0:
                continue
            x = -12 + k * 3.5
            cv.drawCircle(x + 0.32, -3.05, 0.22, P(hexc('#ffe3a0', 0.6 * a * clamp(1 - (t - tk) / 0.6) + 0.0), blur=0.12))
    world(sh, 1.39, lamps, 'lamps')
    for k in range(6):
        sfx(sh, 'lamp_buzz', 0.8 + k * 0.9, gain=0.25)
    ray.move(0.0, -3.4, dur=14.0, ease='lin')
    sfx(sh, 'steps_walk', 0.0, gain=0.25, dur=13.0)
    b.wait(2.0)
    b.say(None, 's02', gap=0.8)
    b.say(None, 's03', gap=0.8)
    b.t = max(b.t, 12.0)
    done(ep, sh, b, tail=0.0, cam=lambda t: Cam(x=Track([(0, -9.5), (14, -3.8)])(t), y=-0.98, zoom=Track([(0, 900), (14, 760)])(t),
                                                 roll=-1.0, aperture=0.6))

def sol_epilogue(ep):
    """Сол одна в лаборатории: папка «Дело №7», имя «Сорен»."""
    sh = mk('night', lab())
    sol = sh.add(Actor('SOL', x=0.0, face=1, pose_='hold_front', eyes='sad', mouth='flat', prop='clipboard'))
    def file(cv, t):
        a = clamp((t - 0.8) / 0.4)
        if a <= 0:
            return
        cv.save(); cv.translate(W * 0.68, H * 0.48); cv.rotate(-5)
        cv.drawRect(skia.Rect(-260, -170, 260, 170), P(rgba(0, 0, 0, 0.4 * a)))
        cv.drawRect(skia.Rect(-250, -180, 250, 160), P(calpha(hexc('#d8c088'), a)))
        cv.drawRect(skia.Rect(-250, -180, -120, -150), P(calpha(hexc('#c8ac70'), a)))
        draw_text(cv, 'ДЕЛО № 7', -220, -100, font('RussoOne', 46), calpha(hexc('#3a2a1a'), a))
        draw_text(cv, 'ОБЪЕКТ: С. Х—', -220, -40, font('Oswald-Bold', 36), calpha(hexc('#3a2a1a'), a))
        cv.save(); cv.translate(80, 60); cv.rotate(-14)
        cv.drawRect(skia.Rect(-150, -40, 150, 40), P(calpha(hexc('#c8302a'), a), 6))
        draw_text(cv, 'ЗАКРЫТО', 0, 16, font('RussoOne', 48), calpha(hexc('#c8302a'), a), 'center')
        cv.restore()
        cv.restore()
    screen(sh, file)
    b = Beat(sh)
    b.sfx('lab_hum', 0.0, gain=0.4)
    sfx(sh, 'paper_flutter', 0.8, gain=0.4)
    b.wait(1.8)
    b.say(sol, 's04', gap=0.8)
    done(ep, sh, b, tail=0.4, cam=C([(0, dict(x=0.1, y=-0.95, zoom=1100, aperture=0.7)), (20, dict(x=0.15, y=-0.98, zoom=1400, aperture=0.8))]))

def post_credits(ep):
    ep.scene('PC', 'После титров', 'Комната Тео, ночь', 'Тео звонит дяде из «Вертекса».')
    sh = mk('night', room_ray('night'))
    teo = sh.add(Actor('TEO', x=0.4, face=-1, pose_='phone_ear', eyes='normal', mouth='flat', prop='phone'))
    sh.grade = dict(tint=(rgba(0.05, 0.08, 0.05, 1), 0.3, 'multiply'))
    def glow(cv, t):
        cv.drawCircle(W * 0.5, H * 0.45, 500, P(hexc('#6fd08a', 0.08), blur=200))
    screen(sh, glow)
    b = Beat(sh)
    b.sfx('amb_room_night', 0.0, gain=0.4)
    b.wait(1.4)
    b.say(teo, 's05', gap=0.6)
    teo.expr(b.t, eyes='cold', mouth='smile')
    sfx(sh, 'sting_subtle', b.t, gain=0.6)
    b.wait(2.0)
    def fade(cv, t):
        FX.fade_black(cv, clamp((t - (sh.dur - 0.8)) / 0.8))
    screen(sh, fade)
    done(ep, sh, b, tail=0.0, cam=C([(0, dict(x=0.3, y=-0.95, zoom=900, aperture=0.6)), (30, dict(x=0.4, y=-0.95, zoom=1500, aperture=0.8))]))

def library_set():
    L = []
    def back(cv, t):
        cv.drawRect(skia.Rect(-20, -6, 20, 0.02), P(hexc('#3a2e26')))
        r = RNG(19)
        for k in range(-8, 9):
            x = k * 1.1
            cv.drawRect(skia.Rect(x, -3.2, x + 1.0, 0.0), P(hexc('#5a3e2a')))
            for j in range(5):
                y = -3.05 + j * 0.62
                cv.drawRect(skia.Rect(x + 0.05, y + 0.5, x + 0.95, y + 0.55), P(hexc('#3a2618')))
                xx = x + 0.08
                while xx < x + 0.9:
                    w = r.u(0.04, 0.09)
                    h = r.u(0.32, 0.46)
                    cv.drawRect(skia.Rect(xx, y + 0.5 - h, xx + w, y + 0.5),
                                P(hexc(r.choice(['#8a3a2a', '#2a4a6a', '#6a6a2a', '#4a2a5a', '#a07a3a', '#2a5a4a']))))
                    xx += w + 0.008
        # окно-арка с закатом
        cv.save(); cv.clipRect(skia.Rect(3.2, -3.0, 4.6, -1.2))
        vgrad(cv, (3.2, -3.0, 4.6, -1.2), [hexc('#3a4a8a'), hexc('#ffb07a')])
        cv.restore()
    L.append(Layer(1.5, back, name='libback'))
    def floor(cv, t):
        cv.drawRect(skia.Rect(-20, 0.0, 20, 4), P(hexc('#4a3424')))
    L.append(Layer(0.0, floor, name='libfloor'))
    def table(cv, t):
        cv.drawRect(skia.Rect(-1.4, -0.45, 1.4, -0.38), P(hexc('#6a4a32')))
        cv.drawRect(skia.Rect(-1.3, -0.38, -1.22, 0.0), P(hexc('#4a3424'))); cv.drawRect(skia.Rect(1.22, -0.38, 1.3, 0.0), P(hexc('#4a3424')))
        # лампа с зелёным абажуром
        cv.drawLine(0.9, -0.45, 0.9, -0.8, P(hexc('#b89a5a'), 0.02))
        cv.drawPath(poly([(0.72, -0.8), (1.08, -0.8), (1.0, -0.92), (0.8, -0.92)]), P(hexc('#2a6a4a')))
        cv.drawCircle(0.9, -0.6, 0.9, P(hexc('#ffe0a0', 0.18), blur=0.4))
        # стопка подшивок газет
        for k in range(4):
            cv.drawRect(skia.Rect(-1.15, -0.5 - k * 0.05, -0.55, -0.45 - k * 0.05), P(hexc('#d8cfb0' if k % 2 else '#c8bf9a')))
    L.append(Layer(-0.3, table, name='libtable'))
    return L

def library(ep):
    ep.scene('6.5', 'Библиотека', 'Городская библиотека, архив газет',
             'Мира находит в подшивке «Северного вестника» заметку семилетней давности: упавший фонарь на Большом мосту «сам встал на место».')
    sh = mk('golden', library_set())
    mira = sh.add(Actor('MIRA', x=0.0, face=1, pose_='sit_write', eyes='normal', prop='paper', z=0.0))
    b = Beat(sh)
    b.sfx('library_amb', 0.0, gain=0.5)
    sfx(sh, 'page_flip', 0.8, gain=0.5)
    sfx(sh, 'page_flip', 1.8, gain=0.5)
    b.wait(2.4)
    t0, t1 = b.say(mira, 'm01', gap=0.4)
    def clip(cv, t):
        a = clamp((t - t0 - 0.8) / 0.4) * clamp((t1 + 1.6 - t) / 0.4)
        if a <= 0:
            return
        cv.save(); cv.translate(W * 0.5, H * 0.46); cv.rotate(2)
        cv.drawRect(skia.Rect(-430, -260, 450, 280), P(rgba(0, 0, 0, 0.35 * a)))
        cv.drawRect(skia.Rect(-440, -280, 440, 260), P(calpha(hexc('#efe6cc'), a)))
        draw_text(cv, 'СЕВЕРНЫЙ ВЕСТНИК', 0, -205, font('RussoOne', 54), calpha(hexc('#2a2418'), a), 'center')
        cv.drawLine(-400, -180, 400, -180, P(calpha(hexc('#2a2418'), a), 3))
        draw_text(cv, '14 октября · семь лет назад', 0, -150, font('Inter-SemiBold', 24), calpha(hexc('#5a5040'), a), 'center')
        draw_text(cv, 'ФОНАРЬ «ВСТАЛ НА МЕСТО»', -400, -90, font('Oswald-Bold', 48), calpha(hexc('#2a2418'), a))
        draw_text(cv, 'Очевидцы на Большом мосту утверждают:', -400, -40, font('Inter-SemiBold', 26), calpha(hexc('#3a3428'), a))
        draw_text(cv, 'упавший фонарный столб поднялся сам.', -400, -6, font('Inter-SemiBold', 26), calpha(hexc('#3a3428'), a))
        # «фото»: мост и фонарь
        cv.drawRect(skia.Rect(80, -70, 400, 200), P(calpha(hexc('#8a8270'), a)))
        cv.drawLine(80, 120, 400, 110, P(calpha(hexc('#2a2418'), a), 6))
        cv.drawLine(240, 120, 240, -20, P(calpha(hexc('#2a2418'), a), 6))
        cv.drawCircle(240, -24, 12, P(calpha(hexc('#f2e8c0'), a)))
        for k in range(6):
            yy = 40 + k * 34
            cv.drawLine(-400, yy, 40, yy, P(calpha(hexc('#8a8270'), a), 6))
        cv.drawOval(skia.Rect(-412, -128, 60, -60), P(calpha(hexc('#d2302a'), 0.9 * a), 4))
        cv.restore()
    screen(sh, clip)
    mira.expr(b.t, eyes='wide', mouth='flat')
    b.say(mira, 'm02', gap=0.6)
    mira.pose(b.t, 'sit_write', 0.5, head=-10).expr(b.t, eyes='sad', mouth='flat')
    b.say(mira, 'm03', gap=0.8)
    done(ep, sh, b, tail=0.2, cam=C([(0, dict(x=-0.6, y=-0.8, zoom=620, aperture=0.6, focus=0.0)),
                                       (t0, dict(x=0.1, y=-0.75, zoom=900, aperture=0.7)), (60, dict(x=0.15, y=-0.85, zoom=1300, aperture=0.8))]))

def gym_set():
    L = []
    def back(cv, t):
        cv.drawRect(skia.Rect(-20, -8, 20, 0.02), P(hexc('#c8b48a')))
        cv.drawRect(skia.Rect(-20, -1.2, 20, 0.02), P(hexc('#2a4a7a')))
        for k in range(-6, 7):
            cv.drawRect(skia.Rect(k * 2.4, -5.5, k * 2.4 + 1.6, -4.0), P(hexc('#e8f0f4')))
        # кольцо
        cv.drawRect(skia.Rect(2.6, -3.4, 3.6, -2.7), P(hexc('#f4f4f0'))); cv.drawRect(skia.Rect(2.6, -3.4, 3.6, -2.7), P(hexc('#c8402f'), 0.03))
        cv.drawLine(3.1, -2.7, 3.1, -2.6, P(hexc('#c8402f'), 0.03))
        cv.drawOval(skia.Rect(2.85, -2.62, 3.35, -2.52), P(hexc('#e8602f'), 0.03))
        for k in range(6):
            cv.drawLine(2.88 + k * 0.09, -2.57, 2.95 + k * 0.07, -2.3, P(hexc('#f4f4f0'), 0.008))
        cv.drawLine(3.1, -3.4, 4.2, -4.4, P(hexc('#555555'), 0.06))
        # табло
        cv.drawRect(skia.Rect(-3.0, -4.8, -1.0, -3.8), P(hexc('#111111')))
        draw_text(cv, '12 : 0', -2.0, -4.12, font('Oswald-Bold', 0.5), hexc('#ff5a3a'), 'center')
    L.append(Layer(2.0, back, name='gymback'))
    def floor(cv, t):
        cv.drawRect(skia.Rect(-20, 0.0, 20, 4), P(hexc('#d2a26a')))
        for k in range(-40, 41):
            cv.drawLine(k * 0.4, 0, k * 0.6, 4, P(hexc('#b88a52'), 0.01))
        cv.drawLine(-20, 0.4, 20, 0.4, P(hexc('#f4f4f0'), 0.02))
    L.append(Layer(0.0, floor, name='gymfloor'))
    return L

def practice(ep):
    ep.scene('6.2', 'Спортзал', 'Школьный спортзал', 'Леон против капитана. 0:12 — и абсолютно счастливый Леон.')
    sh = mk('noon', gym_set())
    leon = sh.add(Actor('LEON', x=-0.8, face=1, pose_='crouch', eyes='serious', mouth='flat'))
    cap = sh.add(Actor('EXTRA', x=0.9, face=-1, pose_='hands_hips', eyes='dot', mouth='smirk', scale=1.12))
    ball = Obj(-0.02, lambda cv, t: (cv.drawCircle(0, 0, 0.09, P(hexc('#e8702f'))), cv.drawCircle(0, 0, 0.09, P(INK, 0.01)),
                                     cv.drawLine(-0.09, 0, 0.09, 0, P(INK, 0.008)), cv.drawLine(0, -0.09, 0, 0.09, P(INK, 0.008))), x=0, y=0)
    sh.layers.append(ball)
    b = Beat(sh)
    b.sfx('gym_amb', 0.0, gain=0.5)
    tj = 0.8
    leon.pose(tj, 'jump', 0.2, rs=170, re=10, ls=150, le=10, ly=0.3)
    sfx(sh, 'sneaker_squeak', tj - 0.2, gain=0.5)
    ball.custom = ballistic(-0.75, -1.35, 2.2, -4.2, tj + 0.2, g=7.0, spin=500)
    ball.ak = [(0, 0.0), (tj + 0.19, 0.0, 'hold'), (tj + 0.2, 1.0, 'lin'), (tj + 1.15, 1.0, 'hold'), (tj + 1.16, 0.0, 'lin')]
    # капитан отбивает
    cap.pose(tj + 0.5, 'jump', 0.2, rs=170, re=10, ly=0.25).pose(tj + 1.1, 'hands_hips', 0.4)
    sfx(sh, 'ball_block', tj + 1.15, gain=0.8)
    sfxt(sh, tj + 1.15, 'БЛОК!', W * 0.55, H * 0.25, 110, color=hexc('#ffffff'), rot=6, dur=0.9)
    leon.pose(tj + 1.0, 'stand', 0.3)
    leon.pose(tj + 1.6, 'sit_ground', 0.3).expr(tj + 1.6, eyes='closed', mouth='grin_open').set(tj + 1.6, 'sweat', 1.0, dur=0.3)
    sfx(sh, 'thud', tj + 1.7, gain=0.5)
    b.t = tj + 2.4
    leon.pose(b.t, pose('sit_ground', rs=160, re=10), 0.3)
    b.say(leon, 'l01', gap=0.6)
    done(ep, sh, b, tail=0.2, cam=C([(0, dict(x=0.0, y=-1.2, zoom=420)), (tj + 1.2, dict(x=0.3, y=-1.5, zoom=380)),
                                       (tj + 2.2, dict(x=-0.7, y=-0.5, zoom=900, aperture=0.6)), (30, dict(x=-0.7, y=-0.5, zoom=1000, aperture=0.6))]))

def bus_interior(tod='morning'):
    """Салон автобуса: окна с проезжающим городом (параллакс), поручни, экран новостей."""
    p = pal(tod)
    L = []
    SPEED = 6.0
    def outside(cv, t):
        # город за окном едет справа налево
        off = -(t * SPEED) % 40
        cv.save(); cv.translate(off, 0)
        cv.drawPicture(SKY_PICS.setdefault('busview', skyline_picture(81, tod, -60, 60, -0.9, 0.6, 2.4, 0.7, 1.8, p['mid'], 0.0)))
        cv.translate(40, 0)
        cv.drawPicture(SKY_PICS['busview'])
        cv.restore()
        institute(cv, 3.0, -1.0, 0.06, tod, t, pulse=clamp(vertex_pulse(t), 0, 1))
    L.append(Layer(6.0, outside, name='busout'))
    def poles(cv, t):
        off = -(t * SPEED * 0.8) % 6
        for k in range(-4, 5):
            x = k * 6 + off
            cv.drawLine(x, -3.5, x, 0.5, P(hexc('#3a4458'), 0.08))
    L.append(Layer(2.4, poles, name='streetpoles'))
    def body(cv, t):
        c = hexc('#e8d27a'); d = hexc('#b89a4a')
        sway = math.sin(t * 1.7) * 0.01
        cv.save(); cv.translate(0, sway)
        # стенка с окнами
        path = skia.Path()
        path.moveTo(-12, -3); path.lineTo(12, -3); path.lineTo(12, 0.1); path.lineTo(-12, 0.1); path.close()
        for k in range(-5, 6):
            x0 = k * 1.6 - 0.65
            path.moveTo(x0, -2.2); path.lineTo(x0, -1.05); path.lineTo(x0 + 1.3, -1.05); path.lineTo(x0 + 1.3, -2.2); path.close()
        cv.ctx.set_fill_rule(__import__('cairo').FILL_RULE_EVEN_ODD)
        cv.drawPath(path, P(c))
        cv.ctx.set_fill_rule(__import__('cairo').FILL_RULE_WINDING)
        for k in range(-5, 6):
            x0 = k * 1.6 - 0.65
            cv.drawRect(skia.Rect(x0, -2.2, x0 + 1.3, -1.05), P(d, 0.05))
        cv.drawRect(skia.Rect(-12, -0.75, 12, -0.68), P(d))
        # экран новостей
        TY = 0.55
        cv.drawLine(-0.4, -2.9, -0.4, -2.35 + TY, P(hexc('#555555'), 0.02)); cv.drawLine(0.4, -2.9, 0.4, -2.35 + TY, P(hexc('#555555'), 0.02))
        cv.drawRect(skia.Rect(-0.55, -2.35 + TY, 0.55, -1.72 + TY), P(hexc('#101820')))
        cv.drawRect(skia.Rect(-0.5, -2.3 + TY, 0.5, -1.77 + TY), P(hexc('#2a4a7a')))
        cv.drawCircle(-0.2, -2.08 + TY, 0.08, P(PAPER)); cv.drawLine(-0.2, -2.0 + TY, -0.2, -1.82 + TY, P(INK, 0.02))
        draw_text(cv, 'НОВОСТИ', 0.18, -2.15 + TY, font('Oswald-Bold', 0.07), PAPER, 'center')
        cv.drawRect(skia.Rect(-0.5, -1.87 + TY, 0.5, -1.79 + TY), P(hexc('#c8302a')))
        tick = 'ВЕРТЕКС: ПЕРЕБОИ ЭЛЕКТРИЧЕСТВА · ПРИЧИН ДЛЯ БЕСПОКОЙСТВА НЕТ · '
        cv.save(); cv.clipRect(skia.Rect(-0.5, -1.87 + TY, 0.5, -1.79 + TY))
        draw_text(cv, tick * 2, -0.5 - (t * 0.25) % 2.4, -1.815 + TY, font('Inter-SemiBold', 0.055), PAPER, 'left')
        cv.restore()
        # поручень на уровне поднятых рук
        cv.drawLine(-12, -1.22, 12, -1.22, P(hexc('#c8c8c8'), 0.03))
        for k in range(-6, 7):
            cv.drawLine(k * 1.8 + 0.9, -1.22, k * 1.8 + 0.9, 0.0, P(hexc('#c8c8c8'), 0.025))
        cv.restore()
    L.append(Layer(1.2, body, name='busbody'))
    def floor(cv, t):
        cv.drawRect(skia.Rect(-12, 0.0, 12, 3), P(hexc('#4a4a52')))
    L.append(Layer(0.0, floor, name='busfloor'))
    return L

def bus(ep):
    ep.scene('3.5', 'Автобус', 'Автобус №7, утро', 'Новости про «Вертекс», Рэй спит стоя, и первая победа Леона в споре — №215.')
    sh = mk('morning', bus_interior('morning'))
    sh.sky = True
    ray = sh.add(Actor('RAY', x=0.1, face=1, pose_='raise_hand', eyes='closed', mouth='flat', z=0.2))
    ray.pose(0, pose('stand', rs=172, re=4, head=12))
    leon = sh.add(Actor('LEON', x=-0.65, face=1, pose_='stand', eyes='normal', z=0.2))
    leon.pose(0, pose('stand', rs=172, re=4))
    pas = []
    for k, x in enumerate((-2.2, 1.4, 2.3)):
        e = sh.add(Actor('EXTRA', x=x, face=-1 if k else 1, eyes='dot', z=0.5, pose_='sit' if k == 1 else 'stand', scale=0.98))
        pas.append(e)
    b = Beat(sh)
    b.sfx('bus_interior', 0.0, gain=0.55)
    b.wait(0.6)
    b.say(None, 'n01', gap=0.3, fx='tv', style='normal')
    leon.expr(b.t, eyes='wide', mouth='grin')
    b.say(leon, 'n02', gap=0.3)
    b.say(ray, 'n03', gap=0.3)
    leon.expr(b.t, eyes='happy', mouth='smirk')
    b.say(leon, 'n04', gap=0.2)
    b.say(ray, 'n05', gap=0.0)
    # поворот: всех кренит, Рэй падает на соседа
    tt = b.t
    sfx(sh, 'bus_brake', tt - 0.2, gain=0.7)
    ray.pose(tt, 'stumble', 0.2).move(tt, 1.25, dur=0.5, ease='in')
    ray.pose(tt + 0.5, pose('lie', rs=-60), 0.25).move(tt + 0.5, 1.45, dur=0.2, y=-0.1)
    pas[1].expr(tt + 0.6, eyes='angry', mouth='frown').set(tt + 0.6, 'vein', 1.0, dur=0.2)
    leon.pose(tt, 'stand', 0.2, lean=-14, rs=172, re=4)
    sfx(sh, 'thud', tt + 0.6, gain=0.7)
    sfxt(sh, tt + 0.6, 'БУХ', W * 0.62, H * 0.62, 110, color=hexc('#ffffff'), rot=-8, dur=0.9)
    b.t = tt + 1.4
    b.say(ray, 'n06', gap=0.2, fx='muffled')
    leon.pose(b.t, 'fist_up', 0.3).expr(b.t, eyes='happy', mouth='grin_open')
    screen(sh, lambda cv, t, a=b.t: FX.focus_lines(cv, t, alpha=0.35 * clamp(1 - abs(t - a - 1.5) / 1.6), color=ORANGE, n=80, inner=0.28))
    b.say(leon, 'n07', gap=0.6)
    done(ep, sh, b, tail=0.2, cam=lambda t: Cam(x=Track([(0, -0.1), (tt, 0.2), (tt + 1.0, 0.7), (60, 0.2)])(t), y=-1.15,
                                                 zoom=Track([(0, 520), (8, 560), (tt, 600), (tt + 0.8, 520), (60, 560)])(t),
                                                 roll=math.sin(t * 1.3) * 0.8 + Track([(tt - 0.2, 0), (tt + 0.2, -5), (tt + 1.2, 0)])(t),
                                                 aperture=0.3))

def witness(ep):
    ep.scene('7.5', 'Свидетель', 'Набережная, сумерки', 'Мира встречает Тима. «Его парень в красном шарфе спас».')
    sh = mk('dusk', stairs_embank('dusk'))
    mira = sh.add(Actor('MIRA', x=-2.4, face=1, pose_='hold_front', eyes='normal', prop='notebook'))
    tim = sh.add(Actor('TIM', x=-0.3, face=-1, pose_='hold_front', eyes='happy', mouth='smile', prop='phone'))
    b = Beat(sh)
    b.sfx('amb_water_eve', 0.0, gain=0.4)
    mira.move(0.0, -1.0, dur=1.6, ease='out')
    b.wait(1.6)
    b.say(mira, 'w01', gap=0.3)
    tim.expr(b.t, eyes='happy', mouth='grin_open').pose(b.t, 'arms_out', 0.3)
    b.say(tim, 'w02', gap=0.3)
    mira.expr(b.t, eyes='wide', mouth='flat')
    b.say(mira, 'w03', gap=0.2)
    tim.pose(b.t, 'wave', 0.3)
    b.say(tim, 'w04', gap=0.2)
    tim.face(b.t, 1).move(b.t + 0.1, 6.0, dur=2.4, ease='in').gait(b.t, b.t + 3, 'run')
    tw = b.t + 0.4
    mira.pose(tw, 'write', 0.4)
    sfx(sh, 'pen_write', tw + 0.4, gain=0.5)
    def nb(cv, t):
        a = clamp((t - tw - 0.4) / 0.3) * clamp((tw + 4.8 - t) / 0.4)
        notebook_panel(cv, (t - tw) * 1.2, ['16:42 — набережная, лестница.', 'Свидетель: Тим (5-й класс).', 'Телефон: разбит → целый.',
                                            'Красный шарф = Рэй?'], title='Наблюдения', a=a, x=W * 0.5, y=H * 0.5, rot=-2,
                       underline=(3, (t - tw - 3.4) / 0.8))
    screen(sh, nb)
    b.wait(5.2)
    done(ep, sh, b, tail=0.0, cam=C([(0, dict(x=-1.6, y=-0.9, zoom=600, aperture=0.4)), (60, dict(x=-0.8, y=-0.9, zoom=700, aperture=0.4))]))

def bedtime_vo(sh, b, ray):
    """Вставляется в сцену 12 перед «Ладно. Давай проверим»."""
    b.say(None, 'r01', gap=0.6)
    b.say(None, 'r02', gap=0.6)

def vertex_morning(ep):
    ep.scene('3.7', '«Вертекс», утро', 'Лаборатория института, утро', 'Сол объясняет Нильсу, что такое «заусенцы» — и почему их отсутствие пугает.')
    sh = mk('morning', lab() + [monitors(-2.6, 0.45, alarm=0.0), holo_map(1.5, -1.25, -0.1, s=0.85, dot=(-0.35, 0.02))])
    nils = sh.add(Actor('NILS', x=-1.75, face=1, pose_='sit_desk', eyes='normal', mouth='flat'))
    sol = sh.add(Actor('SOL', x=0.9, face=-1, pose_='hold_front', eyes='normal', mouth='flat', prop='clipboard', z=0.3))
    b = Beat(sh)
    b.sfx('lab_hum', 0.0, gain=0.45)
    b.wait(1.0)
    nils.face(b.t, -1)
    b.say(nils, 'v01', gap=0.3)
    sol.pose(b.t, 'present', 0.4)
    t0, t1 = b.say(sol, 'v02', gap=0.3)
    def scissors(cv, t):
        a = clamp((t - t0 - 1.0) / 0.4) * clamp((t1 + 0.6 - t) / 0.4)
        if a <= 0:
            return
        cv.save(); cv.translate(W * 0.68, H * 0.38)
        cv.drawRect(skia.Rect(-280, -150, 280, 150), P(rgba(0.02, 0.05, 0.12, 0.8 * a)))
        cv.drawRect(skia.Rect(-280, -150, 280, 150), P(hexc('#4fb0ff', a), 3))
        # «ткань» и разрыв с заусенцами
        cv.drawLine(-240, 0, 240, 0, P(hexc('#4fb0ff', 0.4 * a), 2))
        k = clamp((t - t0 - 1.2) / 1.5)
        x = -240 + 480 * k
        pth = skia.Path(); pth.moveTo(-240, 0)
        r = RNG(2)
        xx = -240
        while xx < x:
            pth.lineTo(xx, r.u(-14, 14)); xx += 18
        cv.drawPath(pth, P(hexc('#ff5a4a', a), 4))
        r = RNG(5)
        xx = -230
        while xx < x:
            cv.drawLine(xx, 0, xx + r.u(-8, 8), r.u(-40, 40), P(hexc('#ff8a7a', 0.8 * a), 2)); xx += 30
        draw_text(cv, 'ЗАУСЕНЦЫ', 0, 120, font('Oswald-Bold', 40), calpha(hexc('#bfe0ff'), a), 'center', tracking=6)
        cv.restore()
    screen(sh, scissors)
    nils.expr(b.t, eyes='wide', mouth='wavy')
    b.say(nils, 'v03', gap=0.4)
    sol.pose(b.t, 'hold_front', 0.4).expr(b.t, eyes='cold', mouth='flat')
    b.say(sol, 'v04', gap=0.8)
    done(ep, sh, b, tail=0.2, cam=C([(0, dict(x=-1.0, y=-1.0, zoom=640, aperture=0.6)), (t0, dict(x=-0.2, y=-1.0, zoom=600, aperture=0.6)),
                                       (60, dict(x=0.6, y=-1.0, zoom=900, aperture=0.7))]))
