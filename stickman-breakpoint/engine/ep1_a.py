# -*- coding: utf-8 -*-
"""Серия 1, часть A: утро Рэя, кухня, набережная, урок физики, айкатч."""
import math
import gfx as skia
from core import *
from sets import *
from stage import *
from props import *
import fx as FX
from stickman import Actor, pose

M = 'build/music/'

def sc1_room(ep):
    ep.scene('1', 'Комната Рэя', 'Квартира Рэя, утро, 07:00',
             'Будильник, одеяло и мировой рекорд по откладыванию. Знакомство с Рэем. Перевёрнутая рамка на полке.')
    S0 = ep.t
    room = room_ray('morning')
    sh = mk('morning', room)
    sh.grade = dict(light=(W * 0.62, H * 0.2, 1300, hexc('#fff0c8'), 0.35))
    # кровать: Рэй лежит под одеялом, рука высовывается
    ray = sh.add(Actor('RAY', x=-1.55, y=-0.55, face=-1, pose_='lie', eyes='closed', mouth='flat', z=0.25))
    ray.pose(0, pose('lie', rs=-90, re=10))
    blanket = Obj(0.24, lambda cv, t: d_blanket(cv, t), x=-1.95, y=-0.52)
    sh.layers.append(blanket)
    ring = [0.0]
    alarm = Obj(0.24, lambda cv, t: d_alarm(cv, t, ring=1.0 if 0.8 < t < T_off else 0.0), x=-0.58, y=-0.5)
    sh.layers.append(alarm)
    b = Beat(sh)
    b.sfx('room_morning', 0.0, gain=0.5)
    b.wait(0.8)
    sfx(sh, 'alarm_clock', 0.8, gain=0.8, dur=9.5, fade=0.2)
    sfxt(sh, 1.0, 'ДЗЫНЬ!', W * 0.7, H * 0.32, 110, color=hexc('#ffe14a'), rot=8, dur=1.4)
    # шлепок мимо, шлепок мимо, будильник падает
    t1 = 2.6
    ray.pose(t1, pose('lie', rs=-20, re=20), 0.25, 'back')
    sfx(sh, 'whoosh_small', t1, gain=0.5)
    ray.pose(t1 + 0.5, pose('lie', rs=-60, re=10), 0.3)
    t2 = 3.8
    ray.pose(t2, pose('lie', rs=5, re=10), 0.2, 'back')
    sfx(sh, 'slap', t2 + 0.18, gain=0.7)
    alarm.custom = ballistic(-0.58, -0.5, 0.9, -1.4, t2 + 0.2, g=7.0, floor=0.0, spin=-260)
    sfx(sh, 'thud', t2 + 0.65, gain=0.8)
    sfxt(sh, t2 + 0.62, 'БАМ', W * 0.62, H * 0.75, 90, color=hexc('#ffffff'), rot=-6, dur=0.8)
    T_off = 12.5
    b.t = t2 + 1.4
    b.say(ray, 'a01', gap=0.4, fx='muffled')
    b.say(None, 'a02', gap=0.3, fx='room_far', style='normal')
    b.say(ray, 'a03', gap=0.3, fx='muffled')
    ray.expr(b.t, eyes='closed', mouth='frown')
    b.say(None, 'a04', gap=0.5, fx='room_far', style='normal')
    # будильник выключается, Рэй сползает с кровати как желе
    sfx(sh, 'click', b.t - 0.3, gain=0.6)
    T_off = b.t - 0.3
    ray.expr(b.t, eyes='lazy', mouth='flat')
    b.say(ray, 'a05', gap=0.2)
    ts = b.t
    ray.move(ts, -0.9, dur=0.9, ease='in', y=0.0)
    blanket.key(ts, x=-1.4, y=-0.35, dur=0.9, ease='in')
    sfx(sh, 'slide_flop', ts + 0.6, gain=0.7)
    b.wait(1.2)
    tf = b.t
    freeze(sh, tf, tf + 3.2)
    sfx(sh, 'card_whoosh', tf, gain=0.8)
    card(sh, tf, 'РЭЙ', '17 лет · чемпион Нордена по откладыванию на потом', RED, dur=3.2)
    b.wait(3.3)
    done(ep, sh, b, tail=0.0, cam=C([(0, dict(x=-0.6, y=-1.15, zoom=330)), (3.5, dict(x=-1.1, y=-0.85, zoom=620)),
                                       (9.0, dict(x=-1.2, y=-0.8, zoom=700)), (22.0, dict(x=-1.0, y=-0.7, zoom=560)),
                                       (40.0, dict(x=-0.9, y=-0.6, zoom=520))]))
    # ── R2: встаёт, рамка на полке ────────────────────────────────
    sh = mk('morning', room_ray('morning'))
    sh.grade = dict(light=(W * 0.62, H * 0.2, 1300, hexc('#fff0c8'), 0.35))
    ray = sh.add(Actor('RAY', x=0.2, y=0.0, face=1, pose_='sit_ground', eyes='lazy'))
    b = Beat(sh)
    b.sfx('room_morning', 0.0, gain=0.45)
    ray.pose(0.4, 'stand', 0.6)
    ray.pose(1.2, 'stretch', 0.5)
    sfx(sh, 'yawn_stretch', 1.2, gain=0.0)
    ray.expr(1.2, eyes='closed', mouth='o')
    ray.pose(2.4, 'relaxed', 0.5).expr(2.4, eyes='lazy', mouth='flat')
    ray.move(2.8, 2.15, dur=2.2)
    sfx(sh, 'steps_room', 2.8, gain=0.5, dur=2.2)
    ray.pose(5.2, 'reach', 0.6, lean=6, rs=80, re=30)
    ray.expr(5.2, eyes='normal')
    ray.pose(6.6, 'relaxed', 0.5)
    ray.expr(6.6, eyes='lazy')
    ray.face(7.0, 1)
    ray.move(7.2, 4.6, dur=2.0)
    sfx(sh, 'door_close', 9.0, gain=0.6)
    b.t = 9.4
    done(ep, sh, b, tail=0.0, cam=C([(0, dict(x=0.4, y=-0.9, zoom=520, aperture=0.0)), (4.8, dict(x=1.9, y=-1.25, zoom=700, aperture=0.0)),
                                       (5.6, dict(x=2.45, y=-1.62, zoom=1500, aperture=0.9, focus=1.6), 'io3'),
                                       (7.2, dict(x=2.45, y=-1.6, zoom=1600, aperture=0.9, focus=1.6)),
                                       (9.4, dict(x=3.2, y=-1.0, zoom=600, aperture=0.0))]))
    ep.cue(M + 'bgm_daily.wav', ep.t - 9.4 + 2.0, None, gain=0.32, fade_in=2.0)

def sc2_kitchen(ep):
    ep.scene('2', 'Кухня', 'Кухня, утро', 'Мама, тост и семейные шутки. Мама задерживает взгляд на второй перевёрнутой рамке.')
    sh = mk('morning', kitchen('morning') + [table_front(y=-0.45, x0=-1.4, x1=1.4)])
    mom = sh.add(Actor('MOM', x=1.3, face=-1, pose_='stand', eyes='happy', mouth='smile', z=0.3))
    ray = sh.add(Actor('RAY', x=-3.2, face=1, pose_='relaxed', eyes='lazy', z=0.1))
    toast = Obj(-0.36, lambda cv, t: (cv.drawRoundRect(skia.Rect(-0.05, -0.08, 0.05, 0.0), 0.02, 0.02, P(hexc('#e2a85a'))),
                                      cv.drawRoundRect(skia.Rect(-0.05, -0.08, 0.05, 0.0), 0.02, 0.02, P(hexc('#8a5a2a'), 0.008))),
                x=0.35, y=-0.47)
    sh.layers.append(toast)
    b = Beat(sh)
    b.sfx('kitchen_amb', 0.0, gain=0.5)
    ray.move(0.2, -0.6, dur=1.6)
    b.wait(1.0)
    b.say(mom, 'a06', gap=0.3)
    b.say(ray, 'a07', gap=0.3)
    mom.expr(b.t, eyes='normal', mouth='smile')
    b.say(mom, 'a08', gap=0.3)
    b.say(ray, 'a09', gap=0.2)
    mom.expr(b.t, eyes='happy', mouth='grin')
    mom.pose(b.t, 'present', 0.4)
    b.say(mom, 'a10', gap=0.2)
    ray.pose(b.t - 0.6, 'reach', 0.3, lean=10, rs=70, re=20)
    tg = b.t - 0.3
    toast.key(tg, alpha=0.0)
    ray.prop(tg, 'toast')
    ray.pose(tg + 0.3, 'eat', 0.3)
    b.say(ray, 'a11', gap=0.2)
    mom.pose(b.t, 'hands_hips', 0.4).expr(b.t, eyes='happy', mouth='smile')
    b.say(mom, 'a12', gap=0.4)
    ray.face(b.t, -1)
    ray.pose(b.t, 'wave', 0.3)
    ray.move(b.t + 0.3, -4.2, dur=1.0, ease='in')
    ray.gait(b.t + 0.3, b.t + 1.4, 'run')
    sfx(sh, 'run_steps', b.t + 0.3, gain=0.5, dur=1.0)
    sfx(sh, 'door_slam', b.t + 1.4, gain=0.7)
    b.wait(1.8)
    tm = b.t
    mom.expr(tm + 0.4, eyes='normal', mouth='smile')
    mom.face(tm + 0.6, 1)
    mom.pose(tm + 0.6, 'stand', 0.5, head=-10)
    mom.expr(tm + 1.6, eyes='sad', mouth='flat')
    sfx(sh, 'kettle', tm + 0.5, gain=0.5, dur=4.0)
    b.wait(4.2)
    done(ep, sh, b, tail=0.0, cam=C([(0, dict(x=-0.8, y=-0.95, zoom=520, aperture=0.4)),
                                       (tm - 1.0, dict(x=0.2, y=-0.95, zoom=560, aperture=0.4)),
                                       (tm + 0.6, dict(x=0.8, y=-1.15, zoom=700, aperture=0.6, focus=0.3)),
                                       (tm + 3.0, dict(x=0.35, y=-1.75, zoom=1100, aperture=0.9, focus=1.5)),
                                       (tm + 4.6, dict(x=0.25, y=-1.85, zoom=1500, aperture=0.9, focus=1.5))]))

def sc3_street(ep):
    ep.scene('3', 'Набережная', 'Набережная Нордена, утро', 'Леон, вечные споры, бабушка с яблоками, слухи об институте и автобус.')
    # ── E1+E2: Рэй идёт, Леон догоняет, тост летит ─────────────────
    lay = street_embank('morning')
    sh = mk('morning', lay)
    ray = sh.add(Actor('RAY', x=-3.0, face=1, pose_='pockets', eyes='lazy', prop='toast', wind=0.5))
    leon = sh.add(Actor('LEON', x=-9.0, face=1, eyes='happy', mouth='grin', gait='run', wind=0.5))
    b = Beat(sh)
    b.sfx('amb_harbor', 0.0, gain=0.6)
    b.sfx('gulls', 1.0, gain=0.5)
    b.sfx('ferry_horn', 3.5, gain=0.45)
    ray.move(0.0, 1.2, dur=7.0, ease='lin')
    sfx(sh, 'steps_walk', 0.2, gain=0.35, dur=6.8)
    gl = lambda cv, t: gulls(cv, t, n=6, seed=2, x0=-14, x1=14, y0=-5.5, y1=-3.5, size=0.22, col=hexc('#3a4658'))
    world(sh, 6.0, gl, 'gulls')
    leon.move(2.8, -0.35, dur=2.5, ease='out')
    sfx(sh, 'run_steps', 2.8, gain=0.5, dur=2.4)
    tsl = 5.25
    leon.pose(tsl, 'shove', 0.15).pose(tsl + 0.4, 'stand', 0.4)
    sfx(sh, 'slap_back', tsl + 0.1, gain=0.8)
    ray.prop(tsl + 0.1, None)
    toast = Obj(-0.05, lambda cv, t: (cv.drawRoundRect(skia.Rect(-0.05, -0.045, 0.05, 0.045), 0.02, 0.02, P(hexc('#e2a85a'))),
                                      cv.drawRoundRect(skia.Rect(-0.05, -0.045, 0.05, 0.045), 0.02, 0.02, P(hexc('#8a5a2a'), 0.008))),
                x=0, y=0)
    xr = Track(ray.xk)(tsl + 0.1)
    toast.custom = ballistic(xr + 0.12, -0.88, 0.25, -3.2, tsl + 0.1, g=9.0, spin=720)
    toast.ak = [(0, 0.0), (tsl + 0.09, 0.0, 'hold'), (tsl + 0.1, 1.0, 'lin'), (tsl + 0.78, 1.0, 'hold'), (tsl + 0.8, 0.0, 'lin')]
    sh.layers.append(toast)
    mblur(sh, 2.8, 5.4, 4)
    mblur(sh, tsl, tsl + 0.9, 5)
    ray.pose(tsl + 0.55, 'catch', 0.15, rs=150, re=20)
    ray.prop(tsl + 0.8, 'toast')
    sfx(sh, 'catch', tsl + 0.8, gain=0.7)
    sfxt(sh, tsl + 0.8, 'ХВАТЬ', W * 0.68, H * 0.25, 100, color=hexc('#ffffff'), rot=10, dur=0.9)
    ray.pose(tsl + 1.2, 'pockets', 0.4)
    ray.face(tsl + 1.0, -1, 0.2)
    b.t = tsl + 1.4
    b.say(leon, 'a13', gap=0.3)
    b.say(ray, 'a14', gap=0.4)
    done(ep, sh, b, tail=0.2, cam=lambda t: Cam(x=Track([(0, -2.6), (6.0, 0.6), (40, 0.9)])(t), y=-0.95,
                                                 zoom=Track([(0, 420), (5.0, 440), (7.5, 640), (40, 660)])(t), aperture=0.5))
    # ── E3: идут и спорят ─────────────────────────────────────────
    sh = mk('morning', street_embank('morning'))
    ray = sh.add(Actor('RAY', x=0.0, face=1, pose_='pockets', eyes='lazy', prop='toast', wind=0.5))
    leon = sh.add(Actor('LEON', x=-0.7, face=1, eyes='happy', mouth='grin', wind=0.5))
    b = Beat(sh)
    b.sfx('amb_harbor', 0.0, gain=0.5)
    WALK = 0.55
    b.wait(0.4)
    leon.pose(b.t, 'point', 0.3)
    b.say(leon, 'a15', gap=0.3)
    ray.prop(b.t, None)
    b.say(ray, 'a16', gap=0.3)
    leon.pose(b.t, 'arms_out', 0.25).expr(b.t, eyes='angry', mouth='teeth')
    leon.set(b.t, 'vein', 1.0, dur=0.2)
    b.say(leon, 'a17', gap=0.3)
    ray.expr(b.t, eyes='lazy', mouth='smirk')
    b.say(ray, 'a18', gap=0.5)
    T = b.t
    ray.move(0, T * WALK, dur=T, ease='lin')
    leon.move(0, T * WALK - 0.7, dur=T, ease='lin')
    sfx(sh, 'steps_walk', 0.0, gain=0.3, dur=T)
    tf = b.t
    freeze(sh, tf, tf + 3.4)
    sfx(sh, 'card_whoosh', tf, gain=0.8)
    card(sh, tf, 'ЛЕОН', '17 лет · споров с Рэем: 214. побед: 0. поражений: 0.', ORANGE, dur=3.4, side='left')
    b.wait(3.5)
    done(ep, sh, b, tail=0.0, cam=lambda t: Cam(x=min(t, tf) * WALK - 0.35, y=-0.95, zoom=620, roll=Track([(0, -1.0), (tf, 1.5)])(t), aperture=0.5))
    # ── E4: бабушка и яблоко ──────────────────────────────────────
    sh = mk('morning', street_embank('morning') + [apple_cart(1.2, 0.05)])
    ray = sh.add(Actor('RAY', x=-1.6, face=1, pose_='pockets', eyes='lazy', wind=0.4))
    leon = sh.add(Actor('LEON', x=-2.3, face=1, eyes='normal', mouth='flat', wind=0.4))
    granny = sh.add(Actor('GRANNY', x=2.1, face=-1, pose_='stand', eyes='happy', mouth='smile', z=0.06))
    apple = Obj(-0.02, d_apple, x=1.0, y=-0.7)
    sh.layers.append(apple)
    b = Beat(sh)
    b.sfx('amb_harbor', 0.0, gain=0.5)
    ray.move(0, -0.3, dur=2.0, ease='out')
    leon.move(0, -0.9, dur=2.0, ease='out')
    ta = 2.0
    sfx(sh, 'cart_wobble', ta - 0.3, gain=0.5)
    apple.custom = ballistic(1.0, -0.72, -0.55, -0.6, ta, g=6.0, spin=-400)
    leon.move(ta + 0.1, 0.45, dur=0.45, ease='out')
    mblur(sh, ta, ta + 0.7, 5)
    leon.gait(ta, ta + 0.6, 'run')
    leon.pose(ta + 0.2, 'jump', 0.15, rs=60, re=30, ly=0.12)
    leon.pose(ta + 0.55, pose('crouch', rs=40, re=60), 0.15)
    tc = ta + 0.52
    apple.ak = [(0, 1.0), (tc, 1.0, 'hold'), (tc + 0.01, 0.0, 'lin')]
    leon.prop(tc, 'apple')
    sfx(sh, 'catch', tc, gain=0.7)
    sfxt(sh, tc, 'ЛОВЛЮ!', W * 0.55, H * 0.3, 96, color=ORANGE, rot=-10, dur=0.9)
    leon.pose(tc + 0.4, 'fist_up', 0.3, rs=150).expr(tc + 0.4, eyes='happy', mouth='grin')
    leon.set(tc + 0.4, 'blush', 0.0)
    b.t = tc + 1.0
    granny.pose(b.t, 'present', 0.4)
    b.say(granny, 'a19', gap=0.3)
    ray.pose(b.t, 'stand', 0.3).prop(b.t + 0.2, 'apple')
    b.say(ray, 'a20', gap=0.2)
    granny.pose(b.t, 'bow', 0.4).expr(b.t, eyes='happy', mouth='grin')
    b.say(granny, 'a21', gap=0.5)
    done(ep, sh, b, tail=0.3, cam=C([(0, dict(x=-0.4, y=-0.95, zoom=520, aperture=0.4)), (ta, dict(x=0.2, y=-0.85, zoom=600, aperture=0.4)),
                                       (tc + 0.6, dict(x=0.5, y=-0.9, zoom=560, aperture=0.4)),
                                       (60, dict(x=0.7, y=-0.95, zoom=600, aperture=0.4))]))
    # ── E5: слухи об институте ────────────────────────────────────
    sh = mk('morning', street_embank('morning'))
    ray = sh.add(Actor('RAY', x=0.0, face=1, pose_='pockets', eyes='lazy', prop='apple', wind=0.4))
    leon = sh.add(Actor('LEON', x=-0.65, face=1, eyes='normal', mouth='flat', prop='apple', wind=0.4))
    b = Beat(sh)
    b.sfx('amb_harbor', 0.0, gain=0.45)
    b.wait(0.6)
    leon.pose(b.t, 'point_up', 0.4).expr(b.t, eyes='wide', mouth='o')
    b.say(leon, 'a22', gap=0.3)
    ray.expr(b.t, eyes='lazy', mouth='flat')
    b.say(ray, 'a23', gap=0.5)
    leon.pose(b.t, 'think', 0.4).expr(b.t, eyes='normal', mouth='flat')
    b.say(leon, 'a24', gap=0.6)
    # тишина: Рэй смотрит на холм
    tq = b.t
    sfx(sh, 'hum_low', tq, gain=0.5, dur=4.5, fade=1.0)
    ray.face(tq, 1).pose(tq, 'pockets', 0.4, head=-10).expr(tq, eyes='normal', mouth='flat')
    ray.pose(tq + 2.6, 'look_hand', 0.5).expr(tq + 2.6, eyes='normal')
    b.wait(4.8)
    tb = b.t
    sfx(sh, 'bus_horn', tb, gain=0.7)
    ray.pose(tb, 'pockets', 0.3).expr(tb, eyes='wide')
    from stickman import hand_world
    hx, hy = hand_world(ray, tq + 3.4)
    done(ep, sh, b, tail=0.3, cam=C([(0, dict(x=-0.3, y=-0.95, zoom=640, aperture=0.5)), (tq, dict(x=-0.2, y=-1.0, zoom=700, aperture=0.5)),
                                       (tq + 1.0, dict(x=2.4, y=-1.9, zoom=520, aperture=0.0), 'io3'),
                                       (tq + 2.4, dict(x=2.8, y=-2.0, zoom=560, aperture=0.0)),
                                       (tq + 3.0, dict(x=hx, y=hy, zoom=2200, aperture=1.0, focus=0.0), 'io3'),
                                       (tb + 0.3, dict(x=hx, y=hy - 0.02, zoom=2300, aperture=1.0))]))
    # ── E6: автобус! бежим ────────────────────────────────────────
    sh = mk('morning', street_embank('morning'))
    ray = sh.add(Actor('RAY', x=0.0, face=1, pose_='pockets', eyes='wide', wind=0.6))
    leon = sh.add(Actor('LEON', x=-0.65, face=1, eyes='wide', mouth='o', wind=0.6))
    bus = Obj(-0.6, d_bus, x=-9.0, y=0.0)
    sh.layers.append(bus)
    b = Beat(sh)
    b.sfx('amb_harbor', 0.0, gain=0.4)
    sfx(sh, 'bus_pass', 0.0, gain=0.7)
    bus.key(0.0, x=-9.0).key(0.0, x=9.0, dur=4.0, ease='lin')
    mblur(sh, 0.0, 4.0, 4)
    b.wait(1.0)
    b.say(leon, 'a25', gap=0.1)
    tr = b.t
    leon.move(tr, 10.0, dur=4.5, ease='in')
    ray.move(tr + 0.4, 9.5, dur=4.6, ease='in')
    leon.gait(tr, tr + 6, 'run'); ray.gait(tr, tr + 6, 'run')
    ray.expr(tr + 0.4, eyes='closed', mouth='o')
    sfx(sh, 'run_steps', tr, gain=0.6, dur=4.5)
    b.wait(0.6)
    b.say(leon, 'a26', gap=0.1)
    b.say(ray, 'a27', gap=0.4)
    screen(sh, lambda cv, t: FX.speed_lines(cv, t, 0, alpha=0.45 * clamp((t - tr) / 0.5), color=PAPER, n=50))
    done(ep, sh, b, tail=0.4, cam=lambda t: Cam(x=Track([(0, -0.3), (tr, -0.3), (tr + 5.0, 8.2, 'in')])(t), y=-0.95,
                                                 zoom=Track([(0, 560), (tr, 560), (tr + 2.0, 480)])(t), roll=Track([(tr, 0), (tr + 2, -3)])(t),
                                                 aperture=0.5))

def sc4_class(ep):
    ep.scene('4', 'Урок физики', 'Школа №3, кабинет физики',
             'Виктор Палыч объясняет «точку излома». Рэй ловит мел во сне. Знакомство с Мирой. Тео и слухи о «Вертексе».')
    L = classroom('morning')
    # парты: задний ряд (статисты), наш ряд и передний план
    def mk_class():
        sh = mk('morning', L + [desk(-0.2, 0.0, 1.3), desk(1.3, 0.0, 1.3), desk(-0.2, -0.9, 1.3, color='#b88a52'),
                                desk(1.3, -0.9, 1.3, color='#b88a52')])
        return sh
    # ── C1: общий план, учитель пишет, Рэй спит ───────────────────
    sh = mk_class()
    te = sh.add(Actor('TEACHER', x=-2.1, face=-1, pose_='point_up', eyes='normal', mouth='flat', prop='chalk', z=1.2))
    ray = sh.add(Actor('RAY', x=-0.6, face=1, pose_='sit_sleep', eyes='closed', mouth='flat', z=0.05))
    mira = sh.add(Actor('MIRA', x=0.3, face=1, pose_='sit_write', eyes='normal', prop='pencil', z=0.05))
    leon = sh.add(Actor('LEON', x=1.0, face=-1, pose_='sit_desk', eyes='normal', z=0.05))
    teo = sh.add(Actor('TEO', x=1.6, face=-1, pose_='sit', eyes='normal', mouth='smile', z=0.05))
    for k, (x, who) in enumerate([(-1.3, 'EXTRA'), (2.4, 'EXTRA'), (3.0, 'EXTRA')]):
        sh.add(Actor(who, x=x, face=-1 if x > 0 else 1, pose_='sit_write', eyes='dot', z=0.6, scale=0.95))
    b = Beat(sh)
    b.sfx('class_amb', 0.0, gain=0.5)
    b.sfx('chalk_write', 0.4, gain=0.5, dur=2.4)
    sfx(sh, 'snore', 1.0, gain=0.35)
    sfxt(sh, 1.4, 'хррр...', W * 0.33, H * 0.48, 54, color=hexc('#9ab0d0'), rot=-4, dur=1.6, fontname='Neucha', shake=0)
    te.face(3.0, 1)
    te.pose(3.2, 'throw', 0.15)
    tt = 3.35
    chalk = Obj(0.03, d_chalk, x=0, y=0)
    chalk.custom = ballistic(-1.9, -1.35, 3.6, -1.2, tt, g=4.0, spin=1400)
    chalk.ak = [(0, 0.0), (tt - 0.01, 0.0, 'hold'), (tt, 1.0, 'lin'), (tt + 0.4, 1.0, 'hold'), (tt + 0.41, 0.0, 'lin')]
    sh.layers.append(chalk)
    sfx(sh, 'whoosh_small', tt, gain=0.6)
    mblur(sh, tt - 0.2, tt + 0.5, 5)
    ray.pose(tt + 0.3, pose('sit_sleep', rs=150, re=10), 0.1)
    ray.prop(tt + 0.4, 'chalk')
    sfx(sh, 'catch', tt + 0.4, gain=0.7)
    sfx(sh, 'class_ooh', tt + 0.6, gain=0.6)
    sfxt(sh, tt + 0.45, 'ТЫЦ', W * 0.47, H * 0.35, 80, color=hexc('#ffffff'), rot=8, dur=0.8)
    b.t = tt + 1.6
    te.pose(b.t, 'point', 0.4).expr(b.t, eyes='normal', mouth='flat')
    b.say(te, 'a28', gap=0.3)
    ray.pose(b.t, 'sit_desk', 0.5).expr(b.t, eyes='lazy', mouth='o')
    b.say(ray, 'a29', gap=0.2)
    sfx(sh, 'class_laugh', b.t, gain=0.6)
    b.wait(1.2)
    done(ep, sh, b, tail=0.2, cam=C([(0, dict(x=-0.8, y=-1.25, zoom=380)), (tt, dict(x=-0.6, y=-1.1, zoom=420)),
                                       (tt + 1.4, dict(x=-0.4, y=-0.95, zoom=560, aperture=0.5, focus=0.0)),
                                       (60, dict(x=-0.3, y=-0.95, zoom=600, aperture=0.5))]))
    # ── C2: лекция у доски, мел ломается ──────────────────────────
    sh = mk_class()
    te = sh.add(Actor('TEACHER', x=-1.2, face=1, pose_='present', eyes='normal', mouth='smile', prop='chalk', z=1.2))
    b = Beat(sh)
    b.sfx('class_amb', 0.0, gain=0.4)
    b.wait(0.4)
    b.say(te, 'a30', gap=0.2)
    sfx(sh, 'class_laugh_small', b.t - 0.6, gain=0.4)
    te.expr(b.t, eyes='serious', mouth='flat')
    b.say(te, 'a31', gap=0.15)
    te.pose(b.t - 1.2, 'chalk_snap', 0.4)
    tsn = b.t
    sfx(sh, 'chalk_snap', tsn, gain=0.9)
    te.prop(tsn, None)
    sfxt(sh, tsn, 'ЩЁЛК', W * 0.62, H * 0.3, 140, color=hexc('#fff4c0'), rot=-8, dur=1.3)
    screen(sh, lambda cv, t: FX.focus_lines(cv, t, alpha=0.35 * clamp(1 - abs(t - tsn - 0.3) / 0.5), color=INK, n=80, inner=0.32))
    b.wait(0.9)
    b.say(te, 'a32', gap=0.4)
    done(ep, sh, b, tail=0.2, cam=C([(0, dict(x=-0.9, y=-1.4, zoom=430)), (tsn - 0.5, dict(x=-1.1, y=-1.25, zoom=560)),
                                       (tsn + 0.05, dict(x=-1.05, y=-1.15, zoom=900), 'out3'), (60, dict(x=-1.0, y=-1.1, zoom=980))]))
    # ── C3: «А если очень попросить?» + знакомство с Мирой ───────
    sh = mk_class()
    ray = sh.add(Actor('RAY', x=-0.6, face=1, pose_='sit_desk', eyes='lazy', mouth='flat', z=0.05))
    mira = sh.add(Actor('MIRA', x=0.3, face=-1, pose_='sit_write', eyes='normal', prop='pencil', z=0.05))
    te = sh.add(Actor('TEACHER', x=-2.4, face=1, pose_='hands_hips', eyes='normal', mouth='flat', z=1.2))
    b = Beat(sh)
    b.sfx('class_amb', 0.0, gain=0.4)
    b.wait(0.3)
    ray.pose(b.t, 'raise_hand', 0.6, rs=120, re=40, lean=20, head=20, sit=0.47, lh=86, lk=86, rh=90, rk=90)
    b.say(ray, 'a33', gap=0.2)
    sfx(sh, 'class_laugh', b.t, gain=0.6)
    b.wait(0.6)
    te.expr(b.t, eyes='normal', mouth='smile')
    b.say(te, 'a34', gap=0.3)
    ray.pose(b.t, 'sit_desk', 0.5)
    b.say(ray, 'a35', gap=0.4)
    mira.expr(b.t, eyes='normal', mouth='flat')
    mira.set(b.t + 0.2, 'glint', 1.0, dur=0.1).set(b.t + 0.6, 'glint', 0.0, dur=0.3)
    sfx(sh, 'glint', b.t + 0.2, gain=0.5)
    b.say(mira, 'a36', gap=0.3)
    ray.face(b.t, 1).expr(b.t, eyes='angry', mouth='frown')
    b.say(ray, 'a37', gap=0.3)
    mira.expr(b.t, eyes='normal', mouth='smile')
    b.say(mira, 'a38', gap=0.3)
    tf = b.t
    freeze(sh, tf, tf + 3.3)
    sfx(sh, 'card_whoosh', tf, gain=0.8)
    card(sh, tf, 'МИРА', '17 лет · замечает всё. почти всё.', VIOLET, dur=3.3)
    b.wait(3.4)
    t_m = Track([])
    done(ep, sh, b, tail=0.0, cam=C([(0, dict(x=-0.3, y=-0.95, zoom=700, aperture=0.6)),
                                       (4.0, dict(x=-0.35, y=-0.9, zoom=760, aperture=0.6)),
                                       (tf - 8.5, dict(x=0.25, y=-0.88, zoom=1100, aperture=0.8), 'io3'),
                                       (tf, dict(x=0.3, y=-0.86, zoom=1200, aperture=0.8))]))
    # ── C4: Тео и слухи ───────────────────────────────────────────
    sh = mk_class()
    ray = sh.add(Actor('RAY', x=-0.6, face=1, pose_='sit_desk', eyes='lazy', z=0.05))
    mira = sh.add(Actor('MIRA', x=0.3, face=1, pose_='sit_write', eyes='normal', prop='pencil', z=0.05))
    leon = sh.add(Actor('LEON', x=1.0, face=-1, pose_='sit_desk', eyes='normal', z=0.05))
    teo = sh.add(Actor('TEO', x=1.65, face=-1, pose_='sit', eyes='happy', mouth='smile', z=0.05))
    b = Beat(sh)
    b.sfx('class_amb', 0.0, gain=0.35)
    b.wait(0.3)
    teo.pose(b.t, pose('sit', lean=-22, head=10, rs=40, re=60), 0.5)
    b.say(teo, 'a39', gap=0.3)
    leon.expr(b.t, eyes='wide', mouth='grin')
    b.say(leon, 'a40', gap=0.2)
    b.say(ray, 'a41', gap=0.3)
    # Тео улыбается на такт дольше, чем нужно
    tq = b.t
    teo.expr(tq, eyes='normal', mouth='smile')
    sfx(sh, 'sting_subtle', tq, gain=0.5)
    b.wait(2.6)
    done(ep, sh, b, tail=0.0, cam=C([(0, dict(x=0.6, y=-0.85, zoom=620, aperture=0.5)), (tq, dict(x=0.9, y=-0.85, zoom=680, aperture=0.5)),
                                       (tq + 2.6, dict(x=1.62, y=-0.86, zoom=1700, aperture=0.9), 'io')]))
    # ── C5: звонок, экскурсия, Мира смотрит в окно ────────────────
    sh = mk_class()
    te = sh.add(Actor('TEACHER', x=-1.6, face=1, pose_='point', eyes='normal', mouth='flat', z=1.2))
    ray = sh.add(Actor('RAY', x=-0.6, face=1, pose_='sit_desk', eyes='lazy', z=0.05))
    mira = sh.add(Actor('MIRA', x=0.3, face=1, pose_='sit_write', eyes='normal', prop='pencil', z=0.05))
    leon = sh.add(Actor('LEON', x=1.0, face=-1, pose_='sit_desk', eyes='normal', z=0.05))
    b = Beat(sh)
    b.sfx('school_bell', 0.0, gain=0.7)
    b.wait(1.4)
    b.say(te, 'a42', gap=0.2)
    leon.pose(b.t, pose('sit', rs=160, re=10, ls=-150, le=10), 0.3).expr(b.t, eyes='happy', mouth='grin')
    b.say(leon, 'a43', gap=0.2)
    b.say(ray, 'a44', gap=0.5)
    tw = b.t
    mira.face(tw, 1).pose(tw, 'sit', 0.5, head=-6).expr(tw, eyes='normal', mouth='flat')
    sfx(sh, 'hum_low', tw + 0.4, gain=0.35, dur=3.0)
    b.wait(3.4)
    done(ep, sh, b, tail=0.0, cam=C([(0, dict(x=-0.9, y=-1.2, zoom=420)), (tw - 0.5, dict(x=-0.4, y=-1.05, zoom=470)),
                                       (tw + 3.4, dict(x=4.1, y=-1.75, zoom=520, aperture=0.0))]))

def eyecatch(ep):
    sh = mk('night', [], sky=False, vignette=0.4)
    sh.bg = lambda cv, t: None
    d = 6.5
    screen(sh, lambda cv, t: FX.eyecatch(cv, t, d))
    sfx(sh, 'eyecatch_sting', 0.1, gain=0.9)
    sh.dur = d
    ep.append(sh)
