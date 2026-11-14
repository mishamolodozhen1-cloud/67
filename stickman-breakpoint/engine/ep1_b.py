# -*- coding: utf-8 -*-
"""Серия 1, часть B: крыша, после уроков, лестница (откат), мост, ужин, «Вертекс», крыша ночью, финал, эндинг, превью."""
import math
import gfx as skia
from core import *
from sets import *
from stage import *
from props import *
import fx as FX
from stickman import Actor, pose, draw_char, Look

M = 'build/music/'

def bench(x, z=0.08, w=1.9):
    def fn(cv, t):
        c = hexc('#7a5032')
        cv.drawRect(skia.Rect(x - w / 2, -0.5, x + w / 2, -0.43), P(c))
        cv.drawRect(skia.Rect(x - w / 2, -0.5, x + w / 2, -0.43), P(INK, 0.012))
        for lx in (x - w / 2 + 0.1, x + w / 2 - 0.1):
            cv.drawLine(lx, -0.43, lx, 0.0, P(hexc('#3a3a46'), 0.03))
    return Layer(z, fn, name='bench')

def sc5_roof(ep):
    ep.scene('5', 'Крыша школы', 'Крыша школы, большая перемена',
             'Булочный спор, блокнот Миры «Странности Нордена», семь невозможных случаев — и человек на крыше напротив.')
    def base():
        sh = mk('noon', school_roof('noon') + [bench(0.0, 0.12, 2.4)])
        return sh
    # ── F1: булки ─────────────────────────────────────────────────
    sh = base()
    leon = sh.add(Actor('LEON', x=-0.75, face=1, pose_='sit_eat', eyes='happy', mouth='grin', prop='bun', prop2='bun', z=0.1))
    ray = sh.add(Actor('RAY', x=0.0, face=-1, pose_='sit_eat', eyes='lazy', prop='bun', z=0.1))
    mira = sh.add(Actor('MIRA', x=0.75, face=-1, pose_='sit_write', eyes='normal', prop='notebook', z=0.1))
    b = Beat(sh)
    b.sfx('wind_roof', 0.0, gain=0.4)
    b.sfx('amb_city_far', 0.0, gain=0.35)
    b.wait(0.6)
    b.say(leon, 'a00' if False else 'b01', gap=0.3)
    ray.expr(b.t, eyes='lazy', mouth='smirk')
    b.say(ray, 'b02', gap=0.2)
    leon.expr(b.t, eyes='closed', mouth='chew')
    sfx(sh, 'eat_fast', b.t, gain=0.5, dur=2.0)
    ray.pose(b.t + 0.2, 'reach', 0.25, sit=0.47, lh=86, lk=86, rh=90, rk=90, lean=12, rs=95, re=10)
    tg = b.t + 0.5
    leon.prop(tg, None, hand=2)
    ray.prop(tg, 'bun')
    sfx(sh, 'swipe', tg, gain=0.6)
    sfxt(sh, tg, 'ЦАП', W * 0.45, H * 0.32, 90, color=hexc('#ffffff'), rot=-8, dur=0.8)
    ray.pose(tg + 0.3, 'sit_eat', 0.3).expr(tg + 0.3, eyes='lazy', mouth='chew')
    b.t = tg + 1.2
    leon.expr(b.t, eyes='shock', mouth='scream').set(b.t, 'vein', 1.0, dur=0.2).set(b.t, 'sweat', 1.0, dur=0.2)
    leon.pose(b.t, pose('sit', rs=70, re=20, ls=-60, le=30), 0.2)
    b.say(leon, 'b03', gap=0.2)
    b.say(ray, 'b04', gap=0.2)
    leon.pose(b.t, pose('sit', rs=120, re=30, ls=-120, le=30, head=-10), 0.2).expr(b.t, eyes='angry', mouth='scream')
    b.say(leon, 'b05', gap=0.2)
    screen(sh, lambda cv, t, a=b.t - 3.0: FX.focus_lines(cv, t, alpha=0.3 * clamp(1 - abs(t - a - 1.2) / 1.4), color=ORANGE, n=70, inner=0.3))
    ray.expr(b.t, eyes='lazy', mouth='smirk')
    b.say(ray, 'b06', gap=0.4)
    leon.pose(b.t, 'sit_eat', 0.5).expr(b.t, eyes='sad', mouth='frown').set(b.t, 'gloom', 1.0, dur=0.4)
    b.wait(0.5)
    done(ep, sh, b, tail=0.0, cam=C([(0, dict(x=-0.4, y=-0.75, zoom=700, aperture=0.6)), (6.0, dict(x=-0.35, y=-0.75, zoom=760, aperture=0.6)),
                                       (60.0, dict(x=-0.1, y=-0.75, zoom=820, aperture=0.6))]))
    # ── F2: блокнот Миры ──────────────────────────────────────────
    sh = base()
    leon = sh.add(Actor('LEON', x=-0.75, face=1, pose_='sit_eat', eyes='normal', prop='bun', z=0.1))
    ray = sh.add(Actor('RAY', x=0.0, face=1, pose_='sit_eat', eyes='lazy', prop='bun', z=0.1))
    mira = sh.add(Actor('MIRA', x=0.75, face=-1, pose_='hold_front', eyes='normal', prop='notebook', z=0.1))
    b = Beat(sh)
    b.sfx('wind_roof', 0.0, gain=0.35)
    b.wait(0.3)
    b.say(mira, 'b07', gap=0.2)
    b.say(leon, 'b08', gap=0.25)
    tn = b.t
    t0, t1 = b.say(mira, 'b09', gap=0.3)
    # вставка: страница блокнота с тремя случаями
    page = ['• Аптека на Портовой: витрина разбита ночью →', '   утром целая. Ни следа.', '• Горшок с 5-го этажа: ни одной трещины.',
            '• Велосипед под грузовиком — ездит.', '• ...и ещё четыре.']
    def sk(cv, t, w, h):
        # маленькие наброски: окно, горшок, велосипед
        base_x, base_y = w * 0.18, h * 0.12
        pen = P(hexc('#22264a'), 3)
        cv.drawRect(skia.Rect(base_x, base_y - 120, base_x + 130, base_y - 20), pen)
        cv.drawLine(base_x + 20, base_y - 100, base_x + 60, base_y - 60, pen)
        cv.drawLine(base_x + 60, base_y - 60, base_x + 40, base_y - 30, pen)
        cv.drawPath(poly([(base_x + 20, base_y + 30), (base_x + 110, base_y + 30), (base_x + 95, base_y + 110), (base_x + 35, base_y + 110)]), pen)
        cv.drawCircle(base_x + 30, base_y + 190, 32, pen); cv.drawCircle(base_x + 120, base_y + 190, 32, pen)
        cv.drawLine(base_x + 30, base_y + 190, base_x + 75, base_y + 150, pen); cv.drawLine(base_x + 75, base_y + 150, base_x + 120, base_y + 190, pen)
    def nb(cv, t):
        a = clamp((t - t0 + 0.2) / 0.3) * clamp((t1 + 0.6 - t) / 0.4)
        FX_t = t - t0
        notebook_panel(cv, FX_t * 1.6, page, title='Странности Нордена', sketch=sk, a=a, x=W * 0.52, y=H * 0.47)
    screen(sh, nb)
    sfx(sh, 'page_flip', t0, gain=0.6)
    leon.expr(b.t, eyes='happy', mouth='grin')
    leon.pose(b.t, pose('sit', rs=150, re=20, ls=-140, le=20), 0.3)
    b.say(leon, 'b10', gap=0.2)
    mira.expr(b.t, eyes='angry', mouth='flat')
    leon.pose(b.t, 'sit_eat', 0.4)
    b.say(mira, 'b11', gap=0.3)
    ray.expr(b.t, eyes='lazy', mouth='chew')
    b.say(ray, 'b12', gap=0.3)
    mira.expr(b.t, eyes='normal', mouth='flat')
    t2, t3 = b.say(mira, 'b13', gap=0.2)
    def mapins(cv, t):
        a = clamp((t - t2) / 0.3) * clamp((t3 + 1.4 - t) / 0.4)
        if a <= 0:
            return
        def draw_map(cv2, tt, w, h):
            pen = P(hexc('#22264a'), 3)
            for k in range(-4, 5):
                cv2.drawLine(-w / 2 + 120, k * 50, w / 2 - 40, k * 50 + 10, P(hexc('#22264a', 0.35), 2))
                cv2.drawLine(k * 90, -h / 2 + 100, k * 90 + 20, h / 2 - 30, P(hexc('#22264a', 0.35), 2))
            draw_text(cv2, 'школа', 0, 8, font('Neucha', 34), hexc('#22264a'), 'center')
            kk = clamp((tt - 0.2) / 1.0)
            cv2.drawArc(skia.Rect(-220, -200, 220, 200), -90, 360 * kk, False, P(hexc('#d2302a'), 6))
            r = RNG(4)
            for i in range(7):
                if kk > i / 7:
                    ang = r.u(0, 2 * math.pi); rr = r.u(40, 180)
                    cv2.drawLine(math.cos(ang) * rr - 12, math.sin(ang) * rr - 12, math.cos(ang) * rr + 12, math.sin(ang) * rr + 12, P(hexc('#d2302a'), 5))
                    cv2.drawLine(math.cos(ang) * rr - 12, math.sin(ang) * rr + 12, math.cos(ang) * rr + 12, math.sin(ang) * rr - 12, P(hexc('#d2302a'), 5))
            draw_text(cv2, '1 км', 160, -170, font('Neucha', 30), hexc('#d2302a'))
        notebook_panel(cv, t - t2, [], title=None, sketch=draw_map, a=a, x=W * 0.5, y=H * 0.48, rot=2)
    screen(sh, mapins)
    sfx(sh, 'page_flip', t2, gain=0.5)
    tstop = b.t + 0.3
    ray.expr(tstop, eyes='wide', mouth='o')
    sfx(sh, 'record_scratch_soft', tstop, gain=0.0)
    b.wait(1.3)
    ray.expr(b.t, eyes='lazy', mouth='smirk')
    b.say(ray, 'b14', gap=0.2)
    sfx(sh, 'laugh_leon', b.t - 0.2, gain=0.0)
    leon.expr(b.t - 0.3, eyes='happy', mouth='grin_open')
    b.wait(0.8)
    mira.expr(b.t, eyes='normal', mouth='flat')
    b.say(mira, 'b15', gap=0.3)
    ray.expr(b.t, eyes='lazy', mouth='flat')
    b.say(ray, 'b16', gap=0.3)
    mira.pose(b.t, 'write', 0.4)
    b.say(mira, 'b17', gap=0.5)
    sfx(sh, 'pen_write', b.t - 0.5, gain=0.5)
    done(ep, sh, b, tail=0.2, cam=C([(0, dict(x=0.4, y=-0.8, zoom=760, aperture=0.6)), (tn, dict(x=0.5, y=-0.8, zoom=800, aperture=0.6)),
                                       (tstop - 0.5, dict(x=0.1, y=-0.8, zoom=760, aperture=0.6)),
                                       (tstop, dict(x=0.0, y=-0.86, zoom=1500, aperture=0.9), 'out3'),
                                       (tstop + 6.0, dict(x=0.35, y=-0.8, zoom=900, aperture=0.6)),
                                       (90, dict(x=0.45, y=-0.8, zoom=950, aperture=0.6))]))
    # ── F3: человек на крыше напротив ─────────────────────────────
    sh = mk('noon', school_roof('noon') + [bench(0.0, 0.12, 2.4)])
    ray = sh.add(Actor('RAY', x=0.0, face=-1, pose_='sit_eat', eyes='lazy', prop='bun', z=0.1))
    leon = sh.add(Actor('LEON', x=-0.75, face=1, pose_='sit_eat', eyes='normal', z=0.1))
    mira = sh.add(Actor('MIRA', x=0.75, face=-1, pose_='write', eyes='normal', prop='notebook', z=0.1))
    man = sh.add(Actor('MAN', x=-11.7, y=-2.3, face=1, pose_='pockets', eyes='cold', z=9.0, wind=0.8))
    b = Beat(sh)
    b.sfx('wind_roof', 0.0, gain=0.35)
    b.wait(0.6)
    ray.face(b.t, -1).expr(b.t, eyes='normal', mouth='flat').pose(b.t, 'sit', 0.4, head=-6)
    tz = b.t + 0.8
    sfx(sh, 'zoom_whoosh', tz, gain=0.7)
    mblur(sh, tz - 0.05, tz + 0.5, 5)
    sfx(sh, 'drone_menace', tz, gain=0.7)
    def men(cv, t):
        if tz < t < tz + 3.8:
            FX.menacing(cv, t, W * 0.5, H * 0.42, alpha=clamp((t - tz) / 0.4) * clamp((tz + 3.8 - t) / 0.3), n=6, seed=6)
    screen(sh, men)
    b.t = tz + 1.2
    b.say(ray, 'b18', gap=0.2, lead=0.0)
    b.say(leon, 'b19', gap=0.1)
    tc = b.t
    man.place(tc, x=-60.0)  # исчез
    sfx(sh, 'gull_flap', tc + 0.1, gain=0.6)
    gull_t = tc
    world(sh, 9.0, lambda cv, t: gulls(cv, t - gull_t + 2.0, n=1, seed=33, x0=-12.5, x1=-6.0, y0=-3.0, y1=-2.6, size=0.35,
                                         col=hexc('#3a4658'), speed=2.0) if t > gull_t else None, 'gull')
    b.wait(1.4)
    leon.expr(b.t, eyes='normal', mouth='smile')
    b.say(leon, 'b20', gap=0.2)
    ray.expr(b.t, eyes='lazy', mouth='flat')
    b.say(ray, 'b21', gap=0.4)
    tw = b.t
    def nb2(cv, t):
        a = clamp((t - tw) / 0.3) * clamp((tw + 3.8 - t) / 0.4)
        notebook_panel(cv, (t - tw) * 1.3, ['12:47 — Рэй видел человека на крыше.'], title='Наблюдения', a=a, x=W * 0.5, y=H * 0.5, rot=-2,
                       underline=(0, (t - tw - 2.2) / 0.8))
    screen(sh, nb2)
    sfx(sh, 'pen_write', tw + 0.3, gain=0.6)
    sfx(sh, 'pen_underline', tw + 2.2, gain=0.6)
    b.wait(4.0)
    done(ep, sh, b, tail=0.0, cam=C([(0, dict(x=0.0, y=-0.86, zoom=1300, aperture=0.8)),
                                       (tz, dict(x=-0.3, y=-0.95, zoom=1100, aperture=0.6)),
                                       (tz + 0.45, dict(x=-11.7, y=-3.2, zoom=1450, aperture=0.0), 'io3'),
                                       (tc - 0.1, dict(x=-11.7, y=-3.25, zoom=1550, aperture=0.0)),
                                       (tc, dict(x=-11.7, y=-3.25, zoom=1550, aperture=0.0), 'hold'),
                                       (tc + 1.2, dict(x=-11.6, y=-3.2, zoom=1500, aperture=0.0)),
                                       (tc + 1.6, dict(x=-0.4, y=-0.8, zoom=760, aperture=0.6), 'io3'),
                                       (90, dict(x=-0.2, y=-0.8, zoom=800, aperture=0.6))]))

def sc6_gate(ep):
    ep.scene('6', 'После уроков', 'Ворота школы, вечереет', 'Леон убегает на тренировку, Мира — в библиотеку. «Будь осторожнее».')
    gate = Obj(0.4, d_gate, x=-2.4, y=0.0, scale=0.72)
    sh = mk('golden', street_embank('golden') + [gate])
    ray = sh.add(Actor('RAY', x=0.0, face=1, pose_='pockets', eyes='lazy', wind=0.4))
    leon = sh.add(Actor('LEON', x=-0.7, face=1, eyes='happy', mouth='grin', wind=0.4))
    mira = sh.add(Actor('MIRA', x=0.7, face=-1, pose_='hold_front', eyes='normal', prop='notebook', wind=0.4))
    b = Beat(sh)
    b.sfx('amb_street_eve', 0.0, gain=0.5)
    b.wait(0.4)
    leon.pose(b.t, 'fist_up', 0.3)
    b.say(leon, 'b22', gap=0.2)
    b.say(ray, 'b23', gap=0.2)
    leon.expr(b.t, eyes='happy', mouth='grin_open').pose(b.t, 'wave', 0.3)
    b.say(leon, 'b24', gap=0.1)
    leon.face(b.t - 0.6, -1).move(b.t - 0.5, -7.0, dur=2.2, ease='in')
    leon.gait(b.t - 0.6, b.t + 3, 'run')
    sfx(sh, 'run_steps', b.t - 0.5, gain=0.4, dur=2.0)
    b.wait(0.6)
    b.say(mira, 'b25', gap=0.2)
    ray.expr(b.t, eyes='normal', mouth='o')
    b.say(ray, 'b26', gap=0.2)
    b.say(mira, 'b27', gap=0.3)
    mira.face(b.t, 1).move(b.t + 0.2, 6.0, dur=4.0, ease='in')
    sfx(sh, 'steps_walk', b.t + 0.2, gain=0.3, dur=3.0)
    ray.pose(b.t + 1.2, 'shrug', 0.4).expr(b.t + 1.2, eyes='lazy', mouth='flat')
    ray.pose(b.t + 2.2, 'pockets', 0.4)
    ray.move(b.t + 2.6, 4.0, dur=3.4, ease='in')
    b.wait(4.6)
    done(ep, sh, b, tail=0.0, cam=C([(0, dict(x=0.0, y=-0.95, zoom=560, aperture=0.4)), (20, dict(x=0.3, y=-0.95, zoom=620, aperture=0.4)),
                                       (60, dict(x=1.8, y=-1.0, zoom=520, aperture=0.4))]))

def sc7_stairs(ep):
    ep.scene('7', 'Набережная, лестница', 'Лестница к воде под мостом, закат',
             'Хулиганы отнимают телефон у Тима. Рэй вмешивается. Телефон разбивается — и собирается обратно. Незнакомец видел всё.')
    T_scene = ep.t
    lay = stairs_embank('golden')
    # ── G1: Рэй идёт, слышит крик ─────────────────────────────────
    sh = mk('golden', lay)
    ray = sh.add(Actor('RAY', x=-6.0, face=1, pose_='pockets', eyes='lazy', wind=0.4))
    b = Beat(sh)
    b.sfx('amb_water_eve', 0.0, gain=0.55)
    ray.move(0.0, -1.0, dur=4.2, ease='out')
    sfx(sh, 'steps_walk', 0.0, gain=0.35, dur=4.0)
    b.wait(3.6)
    b.say(None, 'b28', gap=0.3, style='normal')
    ray.expr(b.t - 1.0, eyes='normal', mouth='flat').pose(b.t - 1.0, 'pockets', 0.3, head=8)
    b.wait(0.4)
    done(ep, sh, b, tail=0.0, cam=C([(0, dict(x=-4.5, y=-1.0, zoom=480, aperture=0.4)), (4.2, dict(x=-1.4, y=-0.95, zoom=560, aperture=0.4)),
                                       (20, dict(x=-1.1, y=-0.95, zoom=640, aperture=0.4))]))
    # ── G2: хулиганы и Тим у воды ─────────────────────────────────
    sh = mk('golden', lay)
    kos = sh.add(Actor('KOSTYA', x=1.75, y=0.72, face=-1, pose_='phone_up', eyes='angry', mouth='grin', prop='phone'))
    shn = sh.add(Actor('SHNUR', x=2.45, y=0.84, face=-1, pose_='cross', eyes='normal', mouth='smirk'))
    tim = sh.add(Actor('TIM', x=1.1, y=0.6, face=1, pose_='reach', eyes='sad', mouth='frown'))
    b = Beat(sh)
    b.sfx('amb_water_eve', 0.0, gain=0.5)
    ep.cue(M + 'bgm_tense.wav', ep.t, None, gain=0.32, fade_in=2.5)
    for k in range(6):
        tim.pose(0.6 + k * 0.9, 'jump', 0.25, rs=170, re=5, ls=40, le=30, ly=0.14).pose(1.0 + k * 0.9, 'reach', 0.25, rs=150, re=10)
    b.wait(0.5)
    b.say(kos, 'b29', gap=0.2)
    tim.expr(b.t, eyes='sad', mouth='scream')
    b.say(tim, 'b30', gap=0.2)
    b.say(kos, 'b31', gap=0.1)
    shn.expr(b.t, eyes='happy', mouth='grin_open')
    b.say(shn, 'b32', gap=0.4)
    done(ep, sh, b, tail=0.0, cam=C([(0, dict(x=1.7, y=0.0, zoom=620, aperture=0.4)), (30, dict(x=1.9, y=-0.05, zoom=700, aperture=0.4))]))
    # ── G3: Рэй вздыхает, окликает, спускается ───────────────────
    sh = mk('golden', lay)
    ray = sh.add(Actor('RAY', x=-1.0, face=1, pose_='pockets', eyes='lazy', wind=0.4))
    kos = sh.add(Actor('KOSTYA', x=1.75, y=0.72, face=-1, pose_='phone_up', eyes='angry', mouth='grin', prop='phone'))
    shn = sh.add(Actor('SHNUR', x=2.45, y=0.84, face=-1, pose_='cross', eyes='normal', mouth='smirk'))
    tim = sh.add(Actor('TIM', x=1.1, y=0.6, face=1, pose_='reach', eyes='sad', mouth='frown'))
    b = Beat(sh)
    b.sfx('amb_water_eve', 0.0, gain=0.45)
    b.wait(0.3)
    ray.pose(b.t, 'pockets', 0.4, head=14).expr(b.t, eyes='normal', mouth='flat')
    b.say(ray, 's01', gap=0.5)
    ray.expr(b.t - 0.2, eyes='lazy', mouth='flat')
    b.say(ray, 'b33', gap=0.3)
    ray.pose(b.t, 'pockets', 0.3, head=0)
    b.say(ray, 'b34', gap=0.25)
    kos.face(b.t - 0.3, -1).pose(b.t - 0.3, 'hands_hips', 0.3, rs=60, re=60).expr(b.t, eyes='angry', mouth='teeth')
    kos.prop(b.t - 0.3, 'phone')
    b.say(kos, 'b35', gap=0.25)
    # Рэй спускается по ступеням: каждая ступень 0.32 по x и 0.12 по y
    ts = b.t
    ray.move(ts, 0.95, dur=3.2, ease='lin', y=0.0)
    def ray_y(t, ray=ray):
        x = Track(ray.xk)(t)
        if x <= -0.2:
            return 0.0
        k = clamp((x + 0.2) / 0.32, 0, 7.5)
        return min(7, int(k)) * 0.12 + (0.12 * smooth(k - int(k)) if k < 7 else 0)
    sh.actor_over['RAY'] = lambda t, f=ray_y: dict(y=f(t))
    sfx(sh, 'steps_stairs', ts, gain=0.45, dur=3.0)
    b.say(ray, 'b36', gap=0.2)
    shn.expr(b.t, eyes='wide', mouth='o')
    b.say(shn, 'b37', gap=0.3)
    done(ep, sh, b, tail=0.0, cam=C([(0, dict(x=-0.9, y=-1.0, zoom=900, aperture=0.6)), (ts, dict(x=0.2, y=-0.6, zoom=520, aperture=0.4)),
                                       (ts + 4.0, dict(x=1.1, y=-0.15, zoom=600, aperture=0.4)), (40, dict(x=1.3, y=-0.15, zoom=640, aperture=0.4))]))
    # ── G4: «Повтори.» — схватил за шарф; переключение лица ──────
    sh = mk('golden', lay)
    ray = sh.add(Actor('RAY', x=1.15, y=0.6, face=1, pose_='pockets', eyes='lazy', wind=0.5))
    kos = sh.add(Actor('KOSTYA', x=1.6, y=0.72, face=-1, pose_='grab', eyes='angry', mouth='teeth', prop='phone'))
    b = Beat(sh)
    b.sfx('amb_water_eve', 0.0, gain=0.4)
    sfx(sh, 'cloth_grab', 0.1, gain=0.7)
    b.wait(0.4)
    b.say(kos, 'b38', gap=0.5)
    tsw = b.t
    sfx(sh, 'music_cut', tsw, gain=0.8)
    ray.expr(tsw, eyes='serious', mouth='flat')
    sfx(sh, 'face_switch', tsw, gain=0.7)
    screen(sh, lambda cv, t: FX.focus_lines(cv, t, alpha=0.45 * clamp(1 - abs(t - tsw - 0.4) / 0.6), color=INK, n=100, inner=0.25))
    b.wait(0.7)
    b.say(ray, 'b39', gap=0.5)
    done(ep, sh, b, tail=0.0, cam=C([(0, dict(x=1.45, y=-0.2, zoom=1100, aperture=0.6)), (tsw - 0.05, dict(x=1.42, y=-0.24, zoom=1250, aperture=0.6)),
                                       (tsw + 0.05, dict(x=1.2, y=-0.33, zoom=2600, aperture=0.9), 'out3'),
                                       (30, dict(x=1.2, y=-0.33, zoom=2750, aperture=0.9))]))
    ep.music_cut = ep.t - (b.t + 0.0 - tsw)
    # ── G5: толчок — телефон летит — разбивается — ОТКАТ ─────────
    sh = mk('golden', lay)
    ray = sh.add(Actor('RAY', x=1.15, y=0.6, face=1, pose_='stand', eyes='serious', wind=0.6))
    kos = sh.add(Actor('KOSTYA', x=1.6, y=0.72, face=-1, pose_='grab', eyes='angry', mouth='teeth', prop='phone'))
    shn = sh.add(Actor('SHNUR', x=2.45, y=0.84, face=-1, pose_='cross', eyes='wide', mouth='o'))
    tim = sh.add(Actor('TIM', x=0.55, y=0.36, face=1, pose_='cower', eyes='sad', mouth='frown'))
    phone = Obj(-0.03, lambda cv, t: d_phone(cv, t, lit=0.0), x=0, y=0)
    sh.layers.append(phone)
    b = Beat(sh)
    b.sfx('amb_water_eve', 0.0, gain=0.35)
    tsh = 0.5
    kos.pose(tsh, 'shove', 0.12)
    sfx(sh, 'shove', tsh + 0.1, gain=0.8)
    ray.move(tsh + 0.1, 0.55, dur=0.5, ease='out', y=0.36)
    ray.pose(tsh + 0.1, 'stumble', 0.2)
    ray.pose(tsh + 0.35, pose('stumble', rs=80, re=0), 0.15)  # рука тянется к телефону
    tmark = tsh + 0.42
    ray.set(tmark, 'notch', 1.0, dur=0.03).set(tmark + 0.12, 'notch', 0.0, dur=0.1)
    sfx(sh, 'tick_mark', tmark, gain=0.4)
    tthrow = tsh + 0.75
    kos.pose(tthrow - 0.2, 'throw', 0.15, rs=150)
    kos.prop(tthrow, None)
    sfx(sh, 'whoosh_big', tthrow, gain=0.8)
    # слоумо полёта: мировое время замедляется
    SLOW_A, SLOW_B, K = tthrow + 0.05, tthrow + 3.0, 0.22
    def tm(t):
        if t < SLOW_A:
            return t
        if t < SLOW_B:
            return SLOW_A + (t - SLOW_A) * K
        return SLOW_A + (SLOW_B - SLOW_A) * K + (t - SLOW_B)
    sh.timemap = tm
    mblur(sh, tsh, tthrow + 0.05, 5)
    phone_hit_world = tthrow + 0.62
    phone.custom = ballistic(1.75, -0.95, 1.6, -2.4, tthrow, g=9.5, floor=0.97, spin=900)
    phone.ak = [(0, 0.0), (tthrow - 0.01, 0.0, 'hold'), (tthrow, 1.0, 'lin'), (phone_hit_world, 1.0, 'hold'), (phone_hit_world + 0.01, 0.0, 'lin')]
    shards = Shards(-0.04, 2.73, 0.95, phone_hit_world, 99.0, n=30, seed=7)
    sh.layers.append(shards)
    # экранное время удара
    def inv(tw):
        if tw < SLOW_A:
            return tw
        if tw < SLOW_A + (SLOW_B - SLOW_A) * K:
            return SLOW_A + (tw - SLOW_A) / K
        return SLOW_B + (tw - (SLOW_A + (SLOW_B - SLOW_A) * K))
    t_hit = inv(phone_hit_world)
    sfx(sh, 'glass_shatter', t_hit, gain=1.0)
    sfxt(sh, t_hit, 'ДЗЗЫНЬ', W * 0.62, H * 0.62, 140, color=hexc('#bfe0ff'), rot=6, dur=1.4)
    b.t = t_hit + 0.15
    tim.expr(b.t, eyes='shock', mouth='scream')
    b.say(tim, 'b40', gap=0.1)
    done(ep, sh, b, tail=0.6, cam=C([(0, dict(x=1.1, y=-0.3, zoom=700, aperture=0.4)),
                                       (tthrow, dict(x=1.5, y=-0.35, zoom=640, aperture=0.4)),
                                       (t_hit - 0.4, dict(x=2.5, y=0.45, zoom=900, aperture=0.6, focus=-0.04), 'io'),
                                       (t_hit, dict(x=2.7, y=0.7, zoom=1300, aperture=0.8, focus=-0.04, shake=0.6)),
                                       (t_hit + 0.4, dict(x=2.7, y=0.7, zoom=1320, aperture=0.8, focus=-0.04, shake=0.0)),
                                       (30, dict(x=2.7, y=0.7, zoom=1400, aperture=0.8, focus=-0.04))]))
    # ── G6: сердце, дуотон, ЩЕЛЧОК — осколки летят назад ─────────
    sh = mk('golden', lay)
    ray = sh.add(Actor('RAY', x=0.55, y=0.36, face=1, pose_='stumble', eyes='wide', mouth='o', wind=0.0))
    kos = sh.add(Actor('KOSTYA', x=1.6, y=0.72, face=-1, pose_='throw', eyes='angry', mouth='teeth'))
    shn = sh.add(Actor('SHNUR', x=2.45, y=0.84, face=-1, pose_='cross', eyes='wide', mouth='o'))
    tim = sh.add(Actor('TIM', x=1.0, y=0.48, face=1, pose_='cower', eyes='shock', mouth='scream'))
    tb = 2.6       # щелчок
    shards = Shards(-0.04, 2.73, 0.95, -5.0, tb, back_dur=0.55, n=30, seed=7)
    sh.layers.append(shards)
    phone = Obj(-0.04, lambda cv, t: d_phone(cv, t, lit=0.0), x=2.73, y=0.93, rot=90)
    phone.ak = [(0, 0.0), (tb + 0.5, 0.0, 'hold'), (tb + 0.55, 1.0, 'lin')]
    sh.layers.append(phone)
    b = Beat(sh)
    sfx(sh, 'heartbeat', 0.0, gain=0.9)
    sfx(sh, 'heartbeat', 0.9, gain=0.9)
    sfx(sh, 'heartbeat', 1.7, gain=1.0)
    sfx(sh, 'click_breakpoint', tb, gain=1.0)
    sfx(sh, 'shatter_reverse', tb, gain=1.0)
    mblur(sh, tb - 0.05, tb + 0.6, 6)
    sfx(sh, 'rewind_whoosh', tb - 0.1, gain=0.7)
    sh.grade = dict(duotone=lambda t: clamp(t / 0.25) * (1 - clamp((t - tb - 0.6) / 0.25)))
    ray.set(tb - 0.1, 'notch', 1.0, dur=0.05).set(tb + 0.7, 'notch', 0.0, dur=0.5)
    ray.pose(tb - 0.15, pose('stumble', rs=70, re=0, head=10), 0.1)
    screen(sh, lambda cv, t: FX.glitch(cv, clamp(1 - abs(t - tb - 0.2) / 0.3) * 0.8, t, seed=3))
    screen(sh, lambda cv, t: FX.focus_lines(cv, t, alpha=0.6 * clamp(1 - abs(t - tb) / 0.5), color=RED, n=110, inner=0.15))
    def hb(cv, t):
        for k, tk in enumerate((0.0, 0.9, 1.7)):
            u = t - tk
            if 0 <= u <= 0.5:
                FX.flash(cv, 0.18 * (1 - u / 0.5), RED)
    screen(sh, hb)
    sfxt(sh, tb, 'ЩЁЛК', W * 0.42, H * 0.25, 150, color=RED, rot=-10, dur=1.0)
    b.t = tb + 2.0
    done(ep, sh, b, tail=0.0, cam=C([(0, dict(x=0.42, y=-0.25, zoom=2400, aperture=0.9)), (1.8, dict(x=0.42, y=-0.27, zoom=2800, aperture=0.9)),
                                       (tb - 0.05, dict(x=0.42, y=-0.27, zoom=2900, aperture=0.9)),
                                       (tb + 0.25, dict(x=2.6, y=0.75, zoom=1300, aperture=0.8, focus=-0.04), 'io3'),
                                       (tb + 2.0, dict(x=2.65, y=0.78, zoom=1450, aperture=0.8, focus=-0.04))]))
    # ── G7: «Он же разбился» — хулиганы уходят, Тим и телефон ─────
    sh = mk('golden', lay)
    ray = sh.add(Actor('RAY', x=0.55, y=0.36, face=1, pose_='stand', eyes='wide', mouth='o'))
    kos = sh.add(Actor('KOSTYA', x=1.6, y=0.72, face=-1, pose_='stand', eyes='wide', mouth='wavy'))
    shn = sh.add(Actor('SHNUR', x=2.2, y=0.84, face=-1, pose_='point', eyes='shock', mouth='o'))
    tim = sh.add(Actor('TIM', x=1.0, y=0.48, face=1, pose_='cower', eyes='wide', mouth='o'))
    phone = Obj(-0.04, lambda cv, t: d_phone(cv, t, lit=1.0 if t > T_lit else 0.0), x=2.73, y=0.93, rot=90)
    sh.layers.append(phone)
    T_lit = 999
    b = Beat(sh)
    b.sfx('amb_water_eve', 0.0, gain=0.4)
    b.wait(0.8)
    b.say(shn, 'b41', gap=0.2)
    kos.expr(b.t, eyes='angry', mouth='wavy').set(b.t, 'sweat', 1.0, dur=0.2)
    b.say(kos, 'b42', gap=0.1)
    kos.face(b.t, 1).move(b.t + 0.1, 7.0, dur=2.4, ease='in', y=0.96)
    shn.face(b.t, 1).move(b.t + 0.2, 7.5, dur=2.4, ease='in', y=0.96)
    kos.gait(b.t, b.t + 3, 'run'); shn.gait(b.t, b.t + 3, 'run')
    sfx(sh, 'run_steps', b.t + 0.1, gain=0.5, dur=2.0)
    b.wait(1.4)
    tim.move(b.t, 2.55, dur=1.0, ease='io', y=0.96).pose(b.t, 'stand', 0.3)
    tim.gait(b.t, b.t + 1.0, 'run')
    tim.pose(b.t + 1.0, 'crouch', 0.3)
    tp = b.t + 1.3
    phone.key(tp, alpha=0.0)
    tim.prop(tp, 'phone').pose(tp + 0.2, 'hold_front', 0.4, rs=70, re=80)
    T_lit = tp
    tim.expr(tp + 0.5, eyes='happy', mouth='grin_open')
    sfx(sh, 'phone_on', tp + 0.4, gain=0.6)
    b.t = tp + 1.0
    b.say(tim, 'b43', gap=0.3)
    ray.expr(b.t, eyes='lazy', mouth='smile')
    b.say(ray, 'b44', gap=0.2)
    tim.face(b.t, 1).move(b.t + 0.1, 7.0, dur=2.0, ease='in').gait(b.t, b.t + 3, 'run')
    b.wait(1.0)
    done(ep, sh, b, tail=0.0, cam=C([(0, dict(x=1.5, y=0.0, zoom=600, aperture=0.4)), (8.0, dict(x=1.7, y=0.1, zoom=640, aperture=0.4)),
                                       (tp - 0.6, dict(x=2.3, y=0.25, zoom=820, aperture=0.5)), (tp + 3.0, dict(x=1.9, y=0.1, zoom=760, aperture=0.5)),
                                       (60, dict(x=1.0, y=0.0, zoom=700, aperture=0.5))]))
    # ── G8: рука, метка гаснет, контур «пунктиром», сел ──────────
    sh = mk('golden', lay)
    ray = sh.add(Actor('RAY', x=0.55, y=0.36, face=1, pose_='look_hand', eyes='normal', mouth='flat'))
    b = Beat(sh)
    b.sfx('amb_water_eve', 0.0, gain=0.35)
    sfx(sh, 'tinnitus', 0.2, gain=0.35, dur=3.5)
    ray.set(0.6, 'notch', 0.9, dur=0.4).set(2.6, 'notch', 0.0, dur=1.2)
    ray.set(1.4, 'dash', 1.0, dur=0.3).set(2.6, 'dash', 0.0, dur=0.6)
    ray.set(1.4, 'thin', 0.55, dur=0.3).set(2.6, 'thin', 1.0, dur=0.6)
    ray.pose(3.2, 'sit_dizzy', 0.8, ly=0.0)
    ray.move(3.2, 0.62, dur=0.8, y=0.38)
    b.t = 4.4
    b.say(ray, 'b45', gap=0.6)
    from stickman import hand_world
    hx, hy = hand_world(ray, 1.5)
    done(ep, sh, b, tail=0.0, cam=C([(0, dict(x=hx, y=hy, zoom=2300, aperture=0.9)), (3.0, dict(x=hx, y=hy + 0.02, zoom=2500, aperture=0.9)),
                                       (4.2, dict(x=0.6, y=-0.1, zoom=900, aperture=0.6)), (20, dict(x=0.55, y=-0.05, zoom=820, aperture=0.6))]))
    # ── G9: на другом берегу — незнакомец ────────────────────────
    sh = mk('golden', lay)
    ray = sh.add(Actor('RAY', x=0.62, y=0.38, face=1, pose_='sit_dizzy', eyes='closed', mouth='flat'))
    man = sh.add(Actor('MAN', x=6.2, y=-0.6, face=-1, pose_='pockets', eyes='cold', z=18.0, wind=0.6))
    world(sh, 18.0, lambda cv, t: (cv.save(), cv.translate(6.9, -0.6), d_lamppost(cv, t, on=1.0), cv.restore()), 'lamp')
    b = Beat(sh)
    b.sfx('amb_water_eve', 0.0, gain=0.4)
    b.wait(2.2)
    done(ep, sh, b, tail=0.0, cam=C([(0, dict(x=1.4, y=-0.5, zoom=420, aperture=0.0)), (2.2, dict(x=3.2, y=-1.6, zoom=380, aperture=0.0))]))
    # крупно незнакомец (отдельный ракурс у фонаря)
    sh = mk('golden', panorama_layers('golden', cy=-1.0, zoom=900, hpx=640, inst=(300, 160), lh=None, bridge=None,
                                       city_far=(4, 25, 80), city_mid=None))
    def railbank(cv, t):
        c = hexc('#2a2036')
        cv.drawRect(skia.Rect(-20, 0.0, 20, 3), P(hexc('#4a3a50')))
        cv.drawLine(-20, -0.85, 20, -0.85, P(c, 0.04))
        for k in range(-40, 41):
            cv.drawLine(k * 0.5, -0.85, k * 0.5, 0.0, P(c, 0.02))
        cv.save(); cv.translate(0.7, 0.0); d_lamppost(cv, t, on=1.0); cv.restore()
    sh.layers.append(Layer(0.6, railbank, name='railbank'))
    man = sh.add(Actor('MAN', x=0.0, face=-1, pose_='pockets', eyes='cold', wind=0.6))
    b = Beat(sh)
    b.sfx('amb_water_eve', 0.0, gain=0.35)
    sfx(sh, 'drone_menace', 0.0, gain=0.5)
    screen(sh, lambda cv, t: FX.menacing(cv, t, W * 0.32, H * 0.4, alpha=0.75, n=5, seed=9))
    b.wait(0.8)
    b.say(man, 'b46', gap=0.6)
    man.pose(b.t - 0.4, 'hat_tip', 0.5)
    done(ep, sh, b, tail=0.4, cam=C([(0, dict(x=0.0, y=-1.0, zoom=900, aperture=0.6)), (30, dict(x=0.02, y=-1.1, zoom=1500, aperture=0.8))]))

def sc8_bridge(ep):
    ep.scene('8', 'Мост в тумане', 'Большой мост Нордена, сумерки',
             'Фонари загораются один за другим. Незнакомец проходит мимо и шепчет: «Береги чернила, Рэй».')
    sh = mk('dusk', bridge_deck('dusk') + [bridge_rail_front('dusk', z=-0.7)])
    ray = sh.add(Actor('RAY', x=-3.0, face=1, pose_='pockets', eyes='lazy', wind=0.6))
    man = sh.add(Actor('MAN', x=4.4, face=-1, pose_='pockets', eyes='cold', wind=0.6, z=0.02))
    extras = []
    r = RNG(51)
    for i in range(7):
        z = r.u(0.4, 2.5)
        x0 = r.u(-8, 8)
        f = 1 if r.u() < 0.5 else -1
        e = sh.add(Actor('EXTRA', x=x0, face=f, eyes='dot', z=z, scale=r.u(0.9, 1.05), sil=0.8))
        e.move(0, x0 + f * r.u(5, 9), dur=14, ease='lin')
    b = Beat(sh)
    b.sfx('amb_bridge_fog', 0.0, gain=0.55)
    b.sfx('ferry_horn', 1.0, gain=0.35)
    ray.move(0.0, 0.45, dur=8.0, ease='lin')
    man.move(0.0, -2.8, dur=8.0, ease='lin')
    sfx(sh, 'steps_walk', 0.0, gain=0.3, dur=8.0)
    # они поравнялись около t=4.6 (x≈-0.05)
    tp = 4.6
    SA, SB, K = tp - 0.7, tp + 1.6, 0.25
    def tm(t):
        if t < SA:
            return t
        if t < SB:
            return SA + (t - SA) * K
        return SA + (SB - SA) * K + (t - SB)
    sh.timemap = tm
    def inv(tw):
        if tw < SA:
            return tw
        if tw < SA + (SB - SA) * K:
            return SA + (tw - SA) / K
        return SB + (tw - (SA + (SB - SA) * K))
    tw_end_walk = 8.0
    b.t = SA + 0.25
    b.say(man, 'b47', gap=0.1, fx='whisper_close')
    sfx(sh, 'time_slow', SA, gain=0.6)
    sh.muffle = (SA, SB)
    # разворот Рэя (в мировом времени после слоумо)
    t_turn_w = tp + 1.5
    ray.face(t_turn_w, -1, 0.12).expr(t_turn_w, eyes='wide', mouth='o')
    man.place(t_turn_w - 0.05, x=-40.0)
    sfx(sh, 'whoosh_small', inv(t_turn_w), gain=0.6)
    b.t = inv(t_turn_w) + 0.6
    b.say(ray, 'b48', gap=0.5)
    sfx(sh, 'ferry_horn', b.t - 0.4, gain=0.5)
    b.wait(1.2)
    done(ep, sh, b, tail=0.0, cam=lambda t: Cam(x=Track([(0, -2.4), (SA, -0.4), (SB, 0.0), (60, 0.6)])(tm(t)), y=-0.95,
                                                 zoom=Track([(0, 520), (SA, 700), (SB, 820), (SB + 2, 640), (60, 600)])(t),
                                                 roll=Track([(0, 0), (SA, -2.0), (SB, 1.5), (60, 0)])(t), aperture=0.6))

def sc9_dinner(ep):
    ep.scene('9', 'Ужин', 'Кухня, вечер', 'Дедушка, чайки и Адмирал. Разрешение на экскурсию в «Вертекс». Рамка, которую нельзя чинить.')
    ep.cue(M + 'bgm_home.wav', ep.t + 1.0, None, gain=0.30, fade_in=2.5)
    def base():
        sh = mk('dusk', kitchen('dusk') + [table_front(eve=True, y=-0.45, x0=-1.3, x1=1.3)])
        sh.grade = dict(light=(W * 0.5, H * 0.1, 1100, hexc('#ffcf7a'), 0.25))
        return sh
    sh = base()
    mom = sh.add(Actor('MOM', x=0.6, face=-1, pose_='sit_eat', eyes='happy', mouth='smile', prop='spoon', z=0.1))
    ray = sh.add(Actor('RAY', x=-0.6, face=1, pose_='sit_eat', eyes='lazy', mouth='flat', prop='spoon', z=0.1))
    for k in (-0.35, 0.35):
        world(sh, -0.36, lambda cv, t, k=k: (cv.save(), cv.translate(k, -0.47), d_soup(cv, t), cv.restore()), 'soup')
    b = Beat(sh)
    b.sfx('kitchen_eve', 0.0, gain=0.45)
    b.sfx('clock_tick', 0.0, gain=0.25, dur=60)
    b.wait(0.8)
    b.say(mom, 'b49', gap=0.4)
    ray.expr(b.t, eyes='normal', mouth='flat')
    b.say(ray, 'b50', gap=0.3)
    mom.expr(b.t, eyes='happy', mouth='grin')
    tg0, tg1 = b.say(mom, 'b51', gap=0.3)
    b.say(ray, 'b52', gap=0.3)
    tA0, tA1 = b.say(mom, 'b53', gap=0.3)
    def bubble(cv, t):
        a = clamp((t - tg0 - 0.6) / 0.3) * clamp((tA1 + 0.8 - t) / 0.3)
        def inside(c2, tt, w, h):
            vgrad(c2, (-w / 2, -h / 2, w / 2, h / 2), [hexc('#bfe0f0'), hexc('#f4e8c8')])
            c2.drawLine(-w / 2, h * 0.22, w / 2, h * 0.22, P(hexc('#7a8a9a'), 6))
            c2.save(); c2.translate(-60, h * 0.22); c2.scale(170, 170)
            Lk = Look('EXTRA', x=0, y=0, face=1, ps=pose('present', head=-6), eyes='happy', mouth='grin_open' if math.sin(tt * 9) > 0 else 'smile',
                      t=tt, halo=None)
            Lk.blink = False
            draw_char(c2, Lk)
            c2.restore()
            # дед: усы и кепка поверх
            c2.drawPath(poly([(-60 - 30, h * 0.22 - 185), (-60 + 34, h * 0.22 - 188), (-60 + 30, h * 0.22 - 176), (-60 - 26, h * 0.22 - 173)]), P(hexc('#5a5a5a')))
            # чайка Адмирал
            gx, gy = 110, h * 0.22 - 40
            c2.drawOval(skia.Rect(gx - 55, gy - 40, gx + 55, gy + 30), P(PAPER)); c2.drawOval(skia.Rect(gx - 55, gy - 40, gx + 55, gy + 30), P(INK, 5))
            c2.drawCircle(gx + 45, gy - 55, 26, P(PAPER)); c2.drawCircle(gx + 45, gy - 55, 26, P(INK, 5))
            c2.drawPath(poly([(gx + 68, gy - 58), (gx + 100, gy - 50), (gx + 68, gy - 46)]), P(hexc('#f2b632')))
            c2.drawCircle(gx + 52, gy - 60, 5, P(INK))
            c2.drawPath(poly([(gx + 20, gy - 75), (gx + 45, gy - 100), (gx + 70, gy - 75)]), P(hexc('#1e2a4a')))  # треуголка адмирала
            if tt > tA0 - tg0:
                draw_text(c2, 'АДМИРАЛ', gx, gy + 70, font('RussoOne', 30), hexc('#1e2a4a'), 'center')
        thought_bubble(cv, t, a, W * 0.73, H * 0.27, 520, 330, inside)
    screen(sh, bubble)
    sfx(sh, 'gull_call', tg0 + 1.0, gain=0.45)
    ray.expr(b.t, eyes='happy', mouth='smile')
    b.say(ray, 'b54', gap=0.6)
    done(ep, sh, b, tail=0.0, cam=C([(0, dict(x=0.0, y=-0.85, zoom=620, aperture=0.5)), (tg0, dict(x=0.2, y=-0.85, zoom=660, aperture=0.5)),
                                       (60, dict(x=-0.1, y=-0.85, zoom=700, aperture=0.5))]))
    # ── K2: разрешение на экскурсию ───────────────────────────────
    sh = base()
    mom = sh.add(Actor('MOM', x=0.6, face=-1, pose_='sit_eat', eyes='happy', mouth='smile', prop='spoon', z=0.1))
    ray = sh.add(Actor('RAY', x=-0.6, face=1, pose_='sit_eat', eyes='lazy', mouth='flat', prop='paper', z=0.1))
    b = Beat(sh)
    b.sfx('kitchen_eve', 0.0, gain=0.4)
    b.sfx('clock_tick', 0.0, gain=0.25, dur=60)
    b.wait(0.4)
    ray.pose(b.t, 'present', 0.4, sit=0.47, lh=86, lk=86, rh=90, rk=90, rs=75, re=20)
    b.say(ray, 'b55', gap=0.15)
    tstop = b.t
    sfx(sh, 'spoon_clink', tstop, gain=0.5)
    mom.pose(tstop, pose('sit_eat', rs=40, re=60), 0.2).expr(tstop, eyes='wide', mouth='flat')
    sfx(sh, 'sting_subtle', tstop + 0.2, gain=0.4)
    b.wait(1.2)
    mom.expr(b.t, eyes='sad', mouth='flat')
    b.say(mom, 'b56', gap=0.3)
    ray.pose(b.t, 'sit_eat', 0.4).expr(b.t, eyes='lazy', mouth='smile')
    b.say(ray, 'b57', gap=0.3)
    mom.expr(b.t, eyes='angry', mouth='flat')
    b.say(mom, 'b58', gap=0.6)
    done(ep, sh, b, tail=0.0, cam=C([(0, dict(x=-0.2, y=-0.85, zoom=700, aperture=0.5)), (tstop, dict(x=0.1, y=-0.85, zoom=760, aperture=0.5)),
                                       (tstop + 0.6, dict(x=0.5, y=-0.93, zoom=1250, aperture=0.8), 'io3'),
                                       (60, dict(x=0.5, y=-0.93, zoom=1350, aperture=0.8))]))
    # ── K3: рамка ─────────────────────────────────────────────────
    sh = base()
    mom = sh.add(Actor('MOM', x=0.6, face=-1, pose_='sit_eat', eyes='normal', mouth='flat', prop='spoon', z=0.1))
    ray = sh.add(Actor('RAY', x=-0.6, face=1, pose_='sit_eat', eyes='normal', mouth='flat', prop='spoon', z=0.1))
    b = Beat(sh)
    b.sfx('kitchen_eve', 0.0, gain=0.35)
    b.sfx('clock_tick', 0.0, gain=0.35, dur=60)
    ray.pose(0.3, 'sit_eat', 0.4, head=-22).face(0.3, 1)
    b.wait(1.6)
    b.say(ray, 'b59', gap=0.4)
    mom.expr(b.t, eyes='sad', mouth='flat')
    b.say(mom, 'b60', gap=0.3)
    ray.expr(b.t, eyes='lazy', mouth='smile')
    b.say(ray, 'b61', gap=0.2)
    tfz = b.t
    mom.pose(tfz, 'sit_eat', 0.2, head=6).expr(tfz, eyes='wide', mouth='flat')
    sfx(sh, 'clock_tick_loud', tfz + 0.3, gain=0.6)
    sfx(sh, 'clock_tick_loud', tfz + 1.3, gain=0.6)
    b.wait(2.2)
    mom.expr(b.t, eyes='sad', mouth='smile')
    b.say(mom, 'b62', gap=0.6)
    tlh = b.t
    ray.pose(tlh, 'look_hand', 0.5, sit=0.47, lh=86, lk=86, rh=90, rk=90, rs=45, re=100)
    ray.set(tlh + 1.0, 'notch', 0.25, dur=0.6).set(tlh + 2.4, 'notch', 0.0, dur=0.6)
    b.wait(3.2)
    from stickman import hand_world
    HX, HY = hand_world(ray, tlh + 1.2)
    done(ep, sh, b, tail=0.0, cam=C([(0, dict(x=-0.4, y=-0.9, zoom=800, aperture=0.6)),
                                       (1.0, dict(x=0.3, y=-1.85, zoom=1300, aperture=0.9, focus=1.5), 'io3'),
                                       (5.5, dict(x=0.32, y=-1.86, zoom=1500, aperture=0.9, focus=1.5)),
                                       (tfz - 0.5, dict(x=0.1, y=-0.85, zoom=700, aperture=0.6), 'io3'),
                                       (tfz + 0.2, dict(x=0.5, y=-0.93, zoom=1250, aperture=0.8), 'out3'),
                                       (tlh, dict(x=0.5, y=-0.93, zoom=1350, aperture=0.8)),
                                       (tlh + 1.0, dict(x=HX, y=HY, zoom=1900, aperture=0.9), 'io3'),
                                       (tlh + 3.2, dict(x=HX, y=HY, zoom=2100, aperture=0.9))]))

def sc10_vertex(ep):
    ep.scene('10', 'Институт «Вертекс»', 'Лаборатория, ночь', 'Красная точка на карте: 16:42, «чистый откат». Директор Грейн выходит из тени.')
    ep.cue(M + 'bgm_mystery.wav', ep.t, None, gain=0.34, fade_in=1.5)
    sh = mk('night', lab() + [monitors(-2.6, 0.45, alarm=0.3), holo_map(0.2, -1.35, -0.15, s=1.25, dot=(-0.35, 0.02), label='16:42')])
    nils = sh.add(Actor('NILS', x=-1.75, face=1, pose_='sit_desk', eyes='wide', mouth='flat'))
    sol = sh.add(Actor('SOL', x=1.4, face=-1, pose_='stand', eyes='normal', mouth='flat', prop='clipboard', z=0.3))
    chairL = Obj(3.0, lambda cv, t: d_chair_director(cv, t, glint=G(t)), x=0.0, y=0.0)
    G = lambda t: 0.0
    b = Beat(sh)
    b.sfx('lab_hum', 0.0, gain=0.55)
    b.sfx('holo_blip', 0.4, gain=0.5)
    b.wait(0.8)
    nils.face(b.t, -1)
    b.say(nils, 'b63', gap=0.3)
    sol.expr(b.t, eyes='cold', mouth='flat')
    b.say(sol, 'b64', gap=0.3)
    nils.expr(b.t, eyes='normal', mouth='o')
    b.say(nils, 'b65', gap=0.2)
    b.say(sol, 'b66', gap=0.5)
    done(ep, sh, b, tail=0.0, cam=C([(0, dict(x=0.0, y=-1.35, zoom=1300, aperture=0.6, focus=-0.15)), (3.0, dict(x=-0.3, y=-1.2, zoom=900, aperture=0.6)),
                                       (60, dict(x=0.3, y=-1.05, zoom=700, aperture=0.6))]))
    # ── директор ──────────────────────────────────────────────────
    sh = mk('night', lab() + [holo_map(0.2, -1.35, -0.15, s=1.25, dot=(-0.35, 0.02), label='16:42')])
    sol = sh.add(Actor('SOL', x=-0.6, face=1, pose_='stand', eyes='normal', mouth='flat', prop='clipboard', z=0.3))
    glint = [(0.0, 0.0)]
    chair = Obj(3.0, lambda cv, t: d_chair_director(cv, t, glint=Track(glint)(t)), x=2.2, y=0.0)
    sh.layers.append(chair)
    b = Beat(sh)
    b.sfx('lab_hum', 0.0, gain=0.5)
    sfx(sh, 'door_hiss', 0.2, gain=0.7)
    b.wait(1.4)
    glint += [(b.t - 0.3, 0.0, 'hold'), (b.t, 1.0, 'lin')]
    sfx(sh, 'drone_menace', b.t - 0.3, gain=0.6)
    b.say(None, 'b67', gap=0.3, fx='hall', style='normal')
    sol.face(b.t - 1.0, 1).expr(b.t - 1.0, eyes='wide', mouth='flat')
    b.say(sol, 'b68', gap=0.3)
    b.say(None, 'b69', gap=0.3, fx='hall', style='normal')
    sol.expr(b.t, eyes='sad', mouth='flat')
    b.say(sol, 'b70', gap=0.8)
    b.say(None, 'b71', gap=0.5, fx='hall', style='normal')
    tcl = b.t
    sol.pose(tcl, 'stand', 0.3, rs=30, re=40)
    sfx(sh, 'paper_crumple', tcl, gain=0.5)
    b.wait(1.6)
    done(ep, sh, b, tail=0.0, cam=C([(0, dict(x=-0.4, y=-1.0, zoom=700, aperture=0.5)), (2.0, dict(x=1.6, y=-1.2, zoom=520, aperture=0.5, focus=3.0)),
                                       (tcl - 6.0, dict(x=1.8, y=-1.3, zoom=600, aperture=0.6, focus=3.0)),
                                       (tcl, dict(x=-0.5, y=-0.6, zoom=1800, aperture=0.9, focus=0.3), 'io3'),
                                       (tcl + 1.6, dict(x=-0.5, y=-0.6, zoom=1900, aperture=0.9, focus=0.3))]))

def sc11_rooftop(ep):
    ep.scene('11', 'Крыша, ночь', 'Крыша многоэтажки, ночь', 'Незнакомец звонит: «Институту я его не отдам». Порванная фотография.')
    sh = mk('night', rooftop_night())
    man = sh.add(Actor('MAN', x=0.4, face=1, pose_='phone_ear', eyes='cold', mouth='flat', prop='phone', wind=0.9))
    b = Beat(sh)
    b.sfx('wind_roof', 0.0, gain=0.6)
    b.sfx('amb_night', 0.0, gain=0.4)
    b.wait(1.0)
    b.say(man, 'b72', gap=0.4)
    b.say(man, 'b73', gap=0.6)
    tp = b.t
    sfx(sh, 'phone_hangup', tp - 0.3, gain=0.5)
    man.prop(tp, 'photo').pose(tp, 'hold_front', 0.5, rs=60, re=80)
    def ph(cv, t):
        a = clamp((t - tp - 0.8) / 0.4) * clamp((tp + 5.6 - t) / 0.5)
        photo_panel(cv, t, a=a, wind=0.8)
    screen(sh, ph)
    sfx(sh, 'paper_flutter', tp + 0.8, gain=0.5)
    b.wait(5.8)
    man.prop(b.t - 0.2, None).pose(b.t - 0.2, 'pockets', 0.5)
    b.wait(1.0)
    done(ep, sh, b, tail=0.0, cam=C([(0, dict(x=0.6, y=-1.1, zoom=1300, roll=-1.5)), (tp, dict(x=0.5, y=-1.05, zoom=1100, roll=0)),
                                       (tp + 6.8, dict(x=1.5, y=-2.6, zoom=420, roll=2.0))]))

def sc12_night(ep):
    ep.scene('12', 'Комната Рэя, ночь', 'Квартира Рэя, ночь', 'Проверка с карандашом. Ничего. Свет гаснет — и карандаш срастается.')
    sh = mk('night', room_ray('night'))
    ray = sh.add(Actor('RAY', x=-1.55, y=-0.55, face=-1, pose_='lie', eyes='normal', mouth='flat', z=0.25))
    sh.layers.append(Obj(0.24, lambda cv, t: d_blanket(cv, t, night=True), x=-1.95, y=-0.52))
    lamp_on = [(0.0, 1.0)]
    pencil = Obj(0.24, lambda cv, t: d_pencil(cv, t, broken=Track(brk)(t), glow=Track(glw)(t)), x=2.55, y=-0.77)
    brk = [(0.0, 0.0)]; glw = [(0.0, 0.0)]
    sh.layers.append(pencil)
    def lampglow(cv, t):
        a = Track(lamp_on)(t)
        if a > 0:
            cv.drawCircle(3.0, -1.1, 1.6, P(hexc('#ffd27a', 0.22 * a), blur=0.8))
    world(sh, 0.24, lampglow, 'lampglow')
    b = Beat(sh)
    b.sfx('amb_room_night', 0.0, gain=0.45)
    b.wait(1.2)
    ray.pose(b.t, pose('lie', rs=170, re=10), 0.8)
    ray.set(b.t + 0.6, 'notch', 0.5, dur=0.6)
    b.wait(1.8)
    import ep1_extra as _X
    _X.bedtime_vo(sh, b, ray)
    b.say(ray, 'b74', gap=0.4)
    # встаёт к столу
    ray.set(b.t, 'notch', 0.0, dur=0.3)
    ray.move(b.t, 2.1, dur=1.6, y=0.0).pose(b.t, 'stand', 0.5).face(b.t + 0.2, 1)
    sfx(sh, 'steps_room', b.t + 0.2, gain=0.4, dur=1.4)
    b.wait(1.8)
    ray.pose(b.t, 'reach', 0.4, lean=10, rs=60, re=40)
    tsn = b.t + 0.9
    brk += [(tsn, 0.0, 'hold'), (tsn + 0.06, 1.0, 'lin')]
    sfx(sh, 'pencil_snap', tsn, gain=0.8)
    sfxt(sh, tsn, 'щёлк', W * 0.62, H * 0.4, 80, color=hexc('#ffe9a0'), rot=-6, dur=0.9)
    b.wait(1.4)
    ray.pose(b.t, 'look_hand', 0.4)
    b.wait(1.8)
    ray.pose(b.t, 'relaxed', 0.4)
    b.say(ray, 'b75', gap=0.4)
    tl = b.t + 0.4
    ray.pose(tl - 0.4, 'reach', 0.3, rs=75, re=40)
    lamp_on += [(tl, 1.0, 'hold'), (tl + 0.03, 0.0, 'lin')]
    sfx(sh, 'switch_click', tl, gain=0.7)
    sh.grade = dict(tint=(rgba(0.02, 0.03, 0.08, 1), lambda t: 0.35 if t > tl else 0.0, 'multiply'))
    ray.move(tl + 0.3, -1.55, dur=1.8, y=-0.55).pose(tl + 0.3, 'lie', 0.6).face(tl + 0.3, -1).expr(tl + 1.4, eyes='closed')
    # срастание карандаша в темноте
    tfix = tl + 3.4
    brk += [(tfix, 1.0, 'hold'), (tfix + 0.35, 0.0, 'out')]
    glw += [(tfix, 0.0, 'hold'), (tfix + 0.1, 1.0, 'lin'), (tfix + 1.4, 0.0, 'lin')]
    sfx(sh, 'click_breakpoint', tfix, gain=0.6)
    sfx(sh, 'shatter_reverse_soft', tfix, gain=0.4)
    b.t = tfix + 1.8
    done(ep, sh, b, tail=0.0, cam=C([(0, dict(x=-1.1, y=-0.9, zoom=700, aperture=0.4)), (6.0, dict(x=-1.0, y=-0.95, zoom=760, aperture=0.4)),
                                       (8.0, dict(x=2.0, y=-0.95, zoom=640, aperture=0.4)), (tl, dict(x=2.3, y=-0.95, zoom=700, aperture=0.4)),
                                       (tl + 2.4, dict(x=2.55, y=-0.8, zoom=1900, aperture=0.9, focus=0.24), 'io3'),
                                       (tfix + 1.8, dict(x=2.55, y=-0.79, zoom=2100, aperture=0.9, focus=0.24))]))
    # ── финал: окно → ночной город, закадровый голос ──────────────
    sh = mk('night', rooftop_night())
    b = Beat(sh)
    b.sfx('amb_night', 0.0, gain=0.45)
    b.wait(1.0)
    b.say(None, 'b76', gap=0.6)
    tc = b.t
    def tbc(cv, t):
        a = clamp((t - tc) / 0.6)
        FX.fade_black(cv, 0.55 * a)
        draw_text(cv, 'Продолжение следует', W * 0.5, H * 0.52, font('Unbounded-Medium', 52), calpha(PAPER, a), 'center', tracking=3)
        FX.breakpoint_mark(cv, W * 0.5 + 360, H * 0.52 - 18, 12, a, t)
    screen(sh, tbc)
    sfx(sh, 'click_breakpoint', tc, gain=0.5)
    b.wait(3.4)
    done(ep, sh, b, tail=0.0, cam=C([(0, dict(x=0.0, y=-1.0, zoom=900, roll=0)), (tc + 3.4, dict(x=1.5, y=-4.5, zoom=320, roll=-2.0))]))

def ending(ep):
    ep.scene('ED', 'Эндинг', '—', 'Финальные титры под спокойную тему.')
    T0 = ep.t
    D = 86.0
    stills = [
        ('night', lambda: room_ray('night'), [('RAY', dict(x=-1.55, y=-0.55, face=-1, pose_='lie', eyes='closed', z=0.25))], (-1.2, -0.9, 650), (-0.9, -0.95, 760)),
        ('dusk', lambda: street_embank('dusk'), [('LEON', dict(x=0.0, face=1, pose_='fist_up', eyes='happy', mouth='grin', wind=0.6))], (-0.5, -1.0, 600), (0.4, -0.95, 700)),
        ('night', lambda: classroom('morning'), [('MIRA', dict(x=0.0, face=-1, pose_='write', eyes='normal', prop='notebook'))], (0.3, -1.0, 800), (0.0, -0.95, 900)),
        ('dusk', lambda: bridge_deck('dusk'), [('MAN', dict(x=0.0, face=-1, pose_='pockets', eyes='cold', wind=0.7))], (0.5, -1.2, 500), (-0.3, -1.1, 620)),
        ('night', lambda: rooftop_night(), [], (0.0, -2.5, 300), (1.0, -3.4, 300)),
    ]
    credits = [
        [('ОРИГИНАЛЬНАЯ ИСТОРИЯ', 'STICKMAN: BREAKPOINT'), ('СЕРИЯ 1', 'Обычный вторник')],
        [('РЭЙ', 'Kup (ElevenLabs)'), ('ЛЕОН', 'Evgeniy Rybakov'), ('МИРА', 'Kate')],
        [('НЕЗНАКОМЕЦ', 'Maxim'), ('МАМА', 'Elena'), ('ВИКТОР ПАЛЫЧ', 'Dima Cernousov')],
        [('ДОКТОР СОЛ', 'Serafima Voloshina'), ('НИЛЬС', 'danik'), ('ДИРЕКТОР', 'Ivan')],
        [('МУЗЫКА', 'Soundza · AI (Lyria / Stable)'), ('ЗВУКИ', 'Soundza'), ('ГОЛОСА', 'ElevenLabs eleven_v4')],
    ]
    seg = D / len(stills)
    for i, (tod, setf, acts, c0, c1) in enumerate(stills):
        sh = mk(tod, setf())
        for who, kw in acts:
            sh.add(Actor(who, **kw))
        if i == 0:
            sh.layers.append(Obj(0.24, lambda cv, t: d_blanket(cv, t, night=True), x=-1.95, y=-0.52))
        cr = credits[i]
        def f(cv, t, cr=cr, i=i):
            a = clamp(t / 0.8) * clamp((seg - t) / 0.8)
            FX.fade_black(cv, 0.35)
            FX.credits_block(cv, cr, W * 0.08, H * 0.36, a, size=40)
            if i == len(stills) - 1:
                FX.title_logo(cv, t, W * 0.68, H * 0.5, 0.55, alpha=a)
        screen(sh, f)
        sh.cam = C([(0, dict(x=c0[0], y=c0[1], zoom=c0[2], aperture=0.5)), (seg, dict(x=c1[0], y=c1[1], zoom=c1[2], aperture=0.5))])
        sh.dur = seg
        ep.append(sh)
    ep.cue(M + 'ed_theme.wav', T0, ep.t, gain=0.8, fade_in=0.5, fade_out=3.0, loop=False, offset=0.0, duck=False)

def preview(ep):
    ep.scene('PV', 'Превью следующей серии', '—', 'Рэй анонсирует серию 2 «Заусенцы».')
    sh = mk('noon', school_roof('noon'))
    leon = sh.add(Actor('LEON', x=-0.9, face=1, pose_='point', eyes='happy', mouth='grin'))
    mira = sh.add(Actor('MIRA', x=0.0, face=-1, pose_='hands_hips', eyes='angry', mouth='flat', prop='notebook'))
    ray = sh.add(Actor('RAY', x=0.9, face=-1, pose_='sit_ground', eyes='closed', mouth='flat'))
    b = Beat(sh)
    sfx(sh, 'preview_sting', 0.0, gain=0.8)
    def hdr(cv, t):
        a = clamp(t / 0.4)
        cv.drawRect(skia.Rect(0, 0, W, 140), P(rgba(0.05, 0.04, 0.07, 0.85 * a)))
        draw_text(cv, 'В СЛЕДУЮЩЕЙ СЕРИИ', 80, 92, font('Unbounded-ExtraBold', 54), calpha(PAPER, a), 'left', tracking=4)
        FX.breakpoint_mark(cv, W - 120, 70, 16, a, t)
    screen(sh, hdr)
    b.wait(1.0)
    b.say(None, 'p01', gap=0.4)
    tt = b.t
    b.say(None, 'p02', gap=0.6)
    def ttl(cv, t):
        a = clamp((t - tt) / 0.5)
        FX.fade_black(cv, 0.5 * a)
        draw_text(cv, 'СЕРИЯ 2', W / 2, H * 0.45, font('Unbounded-Medium', 46), calpha(PAPER, a), 'center', tracking=10)
        draw_text(cv, '«ЗАУСЕНЦЫ»', W / 2, H * 0.58, font('Unbounded-ExtraBold', 120), calpha(RED, a), 'center', stroke=calpha(INK, a), stroke_w=12)
        draw_text(cv, '«ЗАУСЕНЦЫ»', W / 2, H * 0.58, font('Unbounded-ExtraBold', 120), calpha(RED, a), 'center')
        FX.fade_black(cv, clamp((t - (sh.dur - 1.0)) / 1.0))
    screen(sh, ttl)
    b.wait(1.0)
    done(ep, sh, b, tail=0.0, cam=C([(0, dict(x=-0.4, y=-0.9, zoom=520, aperture=0.4)), (30, dict(x=0.6, y=-0.9, zoom=640, aperture=0.4))]))
    ep.cue(M + 'bgm_daily.wav', sh.start, ep.t, gain=0.3, fade_in=0.5, fade_out=1.0)
