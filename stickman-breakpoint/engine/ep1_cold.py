# -*- coding: utf-8 -*-
"""Серия 1: холодное открытие, титул, опенинг."""
import math
import gfx as skia
from core import *
from sets import *
from stage import *
from props import *
import fx as FX
from stickman import Actor, pose, draw_char, Look

M = 'build/music/'

def institute_close(tod='night'):
    """Институт крупно: холм на среднем плане, кольцо с антенной, прожекторы, забор."""
    p = pal(tod)
    L = panorama_layers(tod, cy=-1.2, zoom=300, hpx=700, inst=None, lh=(200, 90), bridge=(500, 10, 160),
                        city_far=(4, 20, 70), city_mid=None)
    def big(cv, t):
        institute(cv, 0.0, 0.6, 0.32, tod, t, pulse=clamp(vertex_pulse(t), 0, 1))
        # прожекторы
        for k, ang0 in enumerate((-30, 25)):
            ang = ang0 + math.sin(t * 0.4 + k) * 18
            a = math.radians(ang - 90)
            x0, y0 = (-0.6 + k * 1.2), -0.15
            x1, y1 = x0 + math.cos(a) * 9, y0 + math.sin(a) * 9
            pth = poly([(x0, y0), (x1 - 0.8, y1), (x1 + 0.8, y1)])
            sh = skia.GradientShader.MakeLinear([skia.Point(x0, y0), skia.Point(x1, y1)],
                                                [c4(hexc('#9fd0ff', 0.28)), c4(hexc('#9fd0ff', 0.0))])
            bp = skia.Paint(); bp.setShader(sh)
            cv.drawPath(pth, bp)
    L.append(Layer(8.0, big, name='instbig'))
    def fence(cv, t):
        c = hexc('#05070f')
        cv.drawRect(skia.Rect(-30, -0.05, 30, 3), P(c))
        for k in range(-80, 81):
            cv.drawLine(k * 0.35, -1.0, k * 0.35, 0.0, P(c, 0.03))
        cv.drawLine(-30, -1.0, 30, -1.0, P(c, 0.04))
        for k in range(-80, 81):
            cv.drawLine(k * 0.35 - 0.1, -1.08, k * 0.35 + 0.1, -0.92, P(c, 0.015))
        # табличка
        cv.drawRect(skia.Rect(-0.9, -0.85, 0.9, -0.45), P(hexc('#0e1630')))
        cv.drawRect(skia.Rect(-0.9, -0.85, 0.9, -0.45), P(hexc('#2f7bff', 0.6), 0.02))
        draw_text(cv, 'ИНСТИТУТ «ВЕРТЕКС»', 0, -0.68, font('Oswald-Bold', 0.13), hexc('#bfe0ff'), 'center')
        draw_text(cv, 'ВХОД ПО ПРОПУСКАМ', 0, -0.52, font('Inter-SemiBold', 0.08), hexc('#6f8fbf'), 'center')
    L.append(Layer(0.6, fence, name='fence'))
    return L

def cold_open(ep):
    ep.scene('0', 'Холодное открытие', 'Норден, ночь',
             'Ночной Норден с высоты. Голос Рэя знакомит с городом. Институт «Вертекс» на холме, лаборатория, незнакомец на крыше.')
    # ── 0.1 крановый спуск над ночным городом ─────────────────────
    sh = mk('night', panorama_layers('night', cy=-1.4, zoom=300, hpx=560, inst=(1500, 230), lh=(260, 110),
                                     bridge=(820, 20, 240), city_far=(6, 30, 110), city_mid=(60, 50, 170)))
    def roofs(cv, t):
        cv.drawPicture(SKY_PICS.setdefault('cold_roofs', skyline_picture(71, 'night', -40, 40, 3.2, 0.6, 3.0, 0.8, 2.2, '#0a0e1d', 0.6)))
    sh.layers.append(Layer(5.0, roofs, name='roofs'))
    sh.layers.append(fog_layer('night', 9.0, -1.2, alpha=0.25, speed=0.3, seed=21, h=3.0))
    b = Beat(sh)
    b.sfx('amb_night', 0.0, gain=0.6)
    b.sfx('wind_soft', 0.0, gain=0.4)
    b.wait(2.2)
    t0, t1 = b.say(None, 'c01', gap=0.9)
    # кинетическая типографика по нарративу
    txt = 'Норден. Северный город на краю карты. Сто сорок дней в году — туман. Триста — ветер. И ровно ноль — чудес.'
    def at(word):
        return t0 + (t1 - t0) * (txt.index(word) / len(txt))
    tN, t140, t300, t0c = at('Норден'), at('Сто сорок'), at('Триста'), at('ноль')
    def kin(cv, t):
        def big(label, sub, ts, x, y, col, size=220, dur=2.4):
            u = t - ts
            if u < 0 or u > dur:
                return
            a = ease_out(clamp(u / 0.4)) * clamp((dur - u) / 0.5)
            dx = (1 - ease_out(clamp(u / 0.6), 3)) * 60
            draw_text(cv, label, x + dx, y, font('Unbounded-ExtraBold', size), calpha(col, a * 0.92), 'left', tracking=2)
            draw_text(cv, sub, x + dx + 8, y + 64, font('Unbounded-Medium', 40), calpha(PAPER, a * 0.85), 'left', tracking=6)
        u = t - tN
        if 0 <= u <= 3.0:
            a = ease_out(clamp(u / 0.6)) * clamp((3.0 - u) / 0.6)
            draw_text(cv, 'Н О Р Д Е Н', W / 2, H * 0.30, font('Unbounded-Medium', 72), calpha(PAPER, a), 'center', tracking=8)
            cv.drawLine(W / 2 - 260 * a, H * 0.30 + 30, W / 2 + 260 * a, H * 0.30 + 30, P(calpha(RED, a), 3))
        big('140', 'ДНЕЙ ТУМАНА', t140, 140, H * 0.42, hexc('#bcd0ff'))
        big('300', 'ДНЕЙ ВЕТРА', t300, W * 0.52, H * 0.42, hexc('#bcd0ff'))
        u = t - t0c
        if 0 <= u <= 2.6:
            a = ease_out(clamp(u / 0.3)) * clamp((2.6 - u) / 0.5)
            draw_text(cv, '0', W / 2, H * 0.58, font('Unbounded-ExtraBold', 300), calpha(PAPER, a), 'center')
            draw_text(cv, 'ЧУДЕС', W / 2, H * 0.58 + 80, font('Unbounded-Medium', 46), calpha(PAPER, a), 'center', tracking=10)
            if u > 0.9:
                FX.crack(cv, clamp((u - 0.9) / 0.3) * a, seed=4, x0=W / 2 - 120, y0=H * 0.58 - 230, x1=W / 2 + 90, y1=H * 0.58 + 20, width=5)
    screen(sh, kin)
    b.sfx('crack_small', t0c - b.t + 0.9 if False else 0.0, gain=0.0)
    sfx(sh, 'crack_small', t0c + 0.9, gain=0.5)
    b.say(None, 'c02', gap=0.6)
    b.wait(0.4)
    sh.letterbox = 1.0
    done(ep, sh, b, tail=0.2, cam=C([(0, dict(x=-3.0, y=-9.5, zoom=300)), (8.0, dict(x=-1.0, y=-3.0, zoom=300), 'io'),
                                       (19.0, dict(x=2.0, y=-1.6, zoom=320, roll=0.0), 'io'),
                                       (24.0, dict(x=3.0, y=-1.5, zoom=330, roll=1.0), 'io')]))
    # ── 0.2 институт крупно ───────────────────────────────────────
    sh = mk('night', institute_close('night'))
    sh.letterbox = 1.0
    b = Beat(sh)
    b.sfx('hum_low', 0.0, gain=0.6)
    b.wait(1.0)
    b.say(None, 'c03', gap=0.5)
    tp = b.t
    sfx(sh, 'boom_deep', tp, gain=0.9)
    def pulsewave(cv, t):
        u = t - tp
        if 0 <= u <= 1.6:
            a = 1 - u / 1.6
            cv.drawOval(skia.Rect(W / 2 - 1600 * u, H * 0.45 - 400 * u, W / 2 + 1600 * u, H * 0.45 + 400 * u), P(hexc('#6fb0ff', 0.7 * a), 8 * a + 1))
            FX.flash(cv, 0.35 * a * a, hexc('#9fd0ff'))
    screen(sh, pulsewave)
    b.wait(1.4)
    done(ep, sh, b, tail=0.1, cam=C([(0, dict(x=-0.4, y=-1.45, zoom=260, aperture=0.0)), (7.0, dict(x=0.1, y=-1.8, zoom=340, roll=-1.0))]))
    # ── 0.3 лаборатория ───────────────────────────────────────────
    lab_l = lab()
    sh = mk('night', lab_l + [monitors(-2.6, 0.45, alarm=0.0), holo_map(1.5, -1.25, -0.1, s=0.85)])
    sh.layers[-2] = monitors(-2.6, 0.45, alarm=1.0)
    nils = sh.add(Actor('NILS', x=-1.75, face=1, pose_='sit_desk', eyes='wide', mouth='wavy'))
    sol = sh.add(Actor('SOL', x=0.9, face=-1, pose_='stand', eyes='normal', mouth='flat', prop='clipboard', z=0.3))
    def chair(cv, t):
        cv.drawRect(skia.Rect(-1.95, -0.52, -1.45, -0.45), P(hexc('#1a2240')))
        cv.drawLine(-1.7, -0.45, -1.7, 0.0, P(hexc('#1a2240'), 0.04))
        cv.drawLine(-1.95, -0.52, -2.0, -1.0, P(hexc('#1a2240'), 0.05))
    world(sh, 0.05, chair, 'chair')
    b = Beat(sh)
    b.sfx('lab_hum', 0.0, gain=0.6)
    b.sfx('beep_alert', 0.3, gain=0.5)
    b.wait(1.2)
    nils.face(b.t, -1)
    b.say(nils, 'c04', gap=0.3)
    sol.expr(b.t, eyes='cold')
    b.say(sol, 'c05', gap=0.25)
    nils.pose(b.t, 'shrug', 0.4)
    b.say(nils, 'c06', gap=0.4)
    sol.move(b.t, 0.2, dur=1.4)
    b.say(sol, 'c07', gap=0.3)
    nils.pose(b.t, 'sit_desk', 0.4).face(b.t, -1)
    b.say(nils, 'c08', gap=0.3)
    sol.face(b.t + 0.3, 1)
    b.say(sol, 'c09', gap=0.2)
    sol.move(b.t - 0.5, 3.4, dur=2.8, ease='in')
    b.wait(1.6)
    done(ep, sh, b, tail=0.2, cam=C([(0, dict(x=-2.0, y=-1.15, zoom=1500, aperture=0.0)),
                                       (2.2, dict(x=-1.2, y=-1.0, zoom=640, aperture=0.6, focus=0.0), 'io3'),
                                       (14.0, dict(x=-0.6, y=-0.95, zoom=600, aperture=0.6)),
                                       (22.0, dict(x=0.2, y=-1.0, zoom=720, aperture=0.6)),
                                       (40.0, dict(x=0.8, y=-1.0, zoom=600, aperture=0.6))]))
    # ── 0.4 крыша: незнакомец ─────────────────────────────────────
    sh = mk('night', rooftop_night())
    man = sh.add(Actor('MAN', x=0.4, face=1, pose_='pockets', eyes='cold', wind=0.9))
    b = Beat(sh)
    b.sfx('wind_roof', 0.0, gain=0.7)
    b.sfx('drone_menace', 0.5, gain=0.6)
    screen(sh, lambda cv, t: FX.menacing(cv, t, W * 0.62, H * 0.42, alpha=clamp((t - 1.5) / 1.0) * 0.9, n=6, seed=3))
    b.wait(3.2)
    b.say(man, 'c10', gap=0.4)
    man.pose(b.t, 'pockets', 0.3, head=-8)
    b.wait(1.6)
    tc = b.t
    sfx(sh, 'crack_big', tc, gain=1.0)
    screen(sh, lambda cv, t: FX.crack(cv, clamp((t - tc) / 0.35), seed=12, width=7))
    screen(sh, lambda cv, t: FX.flash(cv, clamp((t - tc - 0.3) / 0.15), rgba(0, 0, 0, 1)))
    b.wait(0.5)
    done(ep, sh, b, tail=0.0, cam=C([(0, dict(x=0.6, y=-1.6, zoom=420, roll=-2.0)), (5.0, dict(x=0.5, y=-1.05, zoom=1200, roll=-1.0)),
                                       (9.0, dict(x=0.52, y=-1.12, zoom=1900, roll=0.0))]))

def title_card(ep):
    sh = mk('night', [], sky=False, vignette=0.5)
    sh.bg = lambda cv, t: vgrad(cv, (0, 0, W, H), [hexc('#0b0910'), hexc('#1c0d14')])
    b = Beat(sh)
    sfx(sh, 'impact_title', 0.15, gain=1.0)
    def logo(cv, t):
        FX.focus_lines(cv, t, alpha=0.25 * clamp(t / 0.3), color=RED, n=80, inner=0.3, seed=9)
        k = back_out(clamp(t / 0.35))
        FX.title_logo(cv, t, W / 2, H * 0.48, 0.6 + 0.4 * k, alpha=clamp(t / 0.15), crack_prog=clamp((t - 0.6) / 0.3))
        FX.flash(cv, clamp(1 - t / 0.25), PAPER)
        FX.fade_black(cv, clamp((t - 3.6) / 0.6))
    screen(sh, logo)
    sfx(sh, 'click_breakpoint', 0.95, gain=0.8)
    b.wait(4.3)
    done(ep, sh, b, tail=0.0)

def opening(ep):
    """Опенинг ~88 с под AI-трек Soundza; монтаж по сильным долям (150 BPM → такт 1.6 с)."""
    ep.scene('OP', 'Опенинг', '—', 'Музыкальная заставка: герои, город, институт, незнакомец; титры.')
    T0 = ep.t
    BAR = 1.6
    segs = []
    def seg(nbars, build):
        sh = build(nbars * BAR)
        sh.dur = nbars * BAR
        ep.append(sh)
    # 1. чернильный всплеск и логотип (4 такта)
    def s1(d):
        sh = mk('night', [], sky=False)
        sh.bg = lambda cv, t: vgrad(cv, (0, 0, W, H), [hexc('#120d16'), hexc('#2a0f18')])
        def f(cv, t):
            r = RNG(3)
            for i in range(40):
                k = clamp((t - r.u(0, 1.2)) / 0.4)
                if k <= 0: continue
                x, y, rr = r.u(0, W), r.u(0, H), r.u(20, 140) * k
                cv.drawCircle(x, y, rr, P(calpha(RED if i % 5 == 0 else INK, 0.9)))
            FX.focus_lines(cv, t, alpha=0.3, color=PAPER, n=60, inner=0.35)
            k = ease_out(clamp((t - 2.0) / 0.5), 3)
            FX.title_logo(cv, t, W / 2, H * 0.5, 0.5 + 0.45 * k, alpha=k, crack_prog=clamp((t - 3.4) / 0.4))
            draw_text(cv, 'ОРИГИНАЛЬНАЯ ИСТОРИЯ', W / 2, H * 0.82, font('Unbounded-Medium', 26), calpha(PAPER, clamp((t - 4.0) / 0.5)), 'center', tracking=8)
        screen(sh, f)
        return sh
    seg(4, s1)
    # 2. Рэй на мосту на рассвете (4 такта)
    def s2(d):
        sh = mk('dawn', bridge_deck('dawn'))
        ray = sh.add(Actor('RAY', x=0.0, face=1, pose_='pockets', eyes='lazy', wind=1.2))
        ray.pose(d * 0.6, 'pockets', 0.4, head=-12)
        ray.expr(d * 0.6, eyes='serious')
        card(sh, 0.8, 'РЭЙ', 'ленивый. язвительный. не терпит несправедливости', RED, dur=d - 1.0, side='right')
        sh.cam = C([(0, dict(x=-0.8, y=-0.9, zoom=520)), (d, dict(x=0.3, y=-0.95, zoom=700, roll=2.0))])
        return sh
    seg(4, s2)
    # 3. Леон бежит (4 такта)
    def s3(d):
        sh = mk('morning', street_embank('morning'))
        leon = sh.add(Actor('LEON', x=-4.0, face=1, eyes='happy', mouth='grin', gait='run'))
        leon.move(0, 6.0, dur=d, ease='lin')
        screen(sh, lambda cv, t: FX.speed_lines(cv, t, 0, alpha=0.5, color=PAPER, n=50))
        sh.mblur_ranges.append((0, d, 3))
        card(sh, 0.6, 'ЛЕОН', 'спорит со всеми. проигрывает с достоинством', ORANGE, dur=d - 0.8, side='left')
        sh.cam = lambda t: Cam(x=-4.0 + t * 6.0 / d + 0.3, y=-0.85, zoom=520, roll=-3.0)
        return sh
    seg(4, s3)
    # 4. Мира и блокнот (4 такта)
    def s4(d):
        sh = mk('noon', school_roof('noon'))
        mira = sh.add(Actor('MIRA', x=0.0, face=-1, pose_='write', eyes='normal', prop='notebook'))
        mira.set(d * 0.55, 'glint', 1.0, dur=0.1).set(d * 0.55 + 0.2, 'glint', 0.0, dur=0.3)
        sfx(sh, 'glint', d * 0.55, gain=0.5)
        card(sh, 0.6, 'МИРА', 'замечает всё. почти всё', VIOLET, dur=d - 0.8, side='right')
        sh.cam = C([(0, dict(x=0.3, y=-0.95, zoom=1300, aperture=0.8)), (d, dict(x=0.1, y=-0.9, zoom=900, aperture=0.8))])
        return sh
    seg(4, s4)
    # 5. Незнакомец в тумане (4 такта)
    def s5(d):
        sh = mk('dusk', bridge_deck('dusk'))
        man = sh.add(Actor('MAN', x=0.0, face=-1, pose_='pockets', eyes='cold', wind=0.8))
        screen(sh, lambda cv, t: FX.menacing(cv, t, W * 0.5, H * 0.45, alpha=0.85, n=7, seed=8))
        card(sh, 0.6, '???', 'наблюдает', CYAN, dur=d - 0.8, side='left')
        sh.cam = C([(0, dict(x=0.0, y=-1.1, zoom=420, aperture=0.6)), (d, dict(x=0.0, y=-1.15, zoom=780, aperture=0.6))])
        sh.grade = dict(tint=(hexc('#2a1a4a'), 0.35, 'multiply'))
        return sh
    seg(4, s5)
    # 6. Институт и доктор Сол (4 такта)
    def s6(d):
        sh = mk('night', institute_close('night'))
        sh.cam = C([(0, dict(x=-1.0, y=-1.45, zoom=250)), (d, dict(x=0.8, y=-1.75, zoom=320, roll=-2))])
        def f(cv, t):
            draw_text(cv, 'ИНСТИТУТ «ВЕРТЕКС»', W * 0.08, H * 0.82, font('Unbounded-ExtraBold', 54), calpha(hexc('#bfe0ff'), clamp(t / 0.5)), 'left', tracking=4)
            draw_text(cv, 'что они ищут?', W * 0.08, H * 0.88, font('Inter-SemiBold', 30), calpha(PAPER, clamp((t - 0.6) / 0.5)), 'left')
        screen(sh, f)
        return sh
    seg(4, s6)
    # 7. Бег троих на закате, монтаж по долям (8 тактов: 4 вставки по 2 такта)
    def s7(d):
        sh = mk('golden', bridge_deck('golden'))
        r = sh.add(Actor('RAY', x=-1.0, face=1, gait='run', eyes='serious', wind=1.0))
        l_ = sh.add(Actor('LEON', x=-1.8, face=1, gait='run', eyes='happy', mouth='grin'))
        m = sh.add(Actor('MIRA', x=-2.6, face=1, gait='run', eyes='normal'))
        for a, off in ((r, 0.0), (l_, -0.8), (m, -1.6)):
            a.move(0, 9.0 + off, dur=d, ease='lin')
        sh.cam = lambda t: Cam(x=-1.6 + t * 9.0 / d, y=-0.9, zoom=420, roll=-2 + 4 * t / d)
        sh.grade = dict(light=(W * 0.2, H * 0.3, 1400, hexc('#ffb070'), 0.35))
        screen(sh, lambda cv, t: FX.speed_lines(cv, t, 0, alpha=0.35, color=hexc('#ffe0b0'), n=40))
        return sh
    seg(4, s7)
    def s8(d):
        sh = mk('night', [], sky=False)
        sh.bg = lambda cv, t: vgrad(cv, (0, 0, W, H), [hexc('#14060a'), hexc('#2a0a10')])
        def f(cv, t):
            FX.focus_lines(cv, t, alpha=0.35, color=RED, n=90, inner=0.18)
            # рука с меткой — крупно (рисуем как линии)
            k = ease_out(clamp(t / 0.5))
            cv.save(); cv.translate(W * 0.5, H * 0.6); cv.scale(1 + 0.1 * t / d, 1 + 0.1 * t / d)
            cv.drawLine(-700, 300, -40, -20, P(INK, 70)); cv.drawLine(-700, 300, -40, -20, P(PAPER, 6))
            FX.breakpoint_mark(cv, -10, -36, 30 * k, k, t)
            cv.restore()
            draw_text(cv, 'ТОЧКА ОСТАНОВА', W - 90, H * 0.3, font('Unbounded-ExtraBold', 60), calpha(PAPER, clamp((t - 0.8) / 0.4)), 'right')
        screen(sh, f)
        return sh
    seg(2, s8)
    def s9(d):
        sh = mk('golden', stairs_embank('golden'))
        sh.layers.append(Shards(-0.05, 0.6, 0.48, 0.0, d * 0.45, back_dur=0.6, n=40, seed=4))
        phone = Obj(-0.05, lambda cv, t: d_phone(cv, t, lit=1.0 if t > d * 0.45 + 0.6 else 0.0), x=0.6, y=0.45, rot=80)
        phone.ak = [(0.0, 0.0), (d * 0.45 + 0.55, 0.0, 'hold'), (d * 0.45 + 0.6, 1.0, 'lin')]
        sh.layers.append(phone)
        sh.cam = C([(0, dict(x=0.6, y=0.3, zoom=1500)), (d, dict(x=0.6, y=0.35, zoom=1900))])
        sh.grade = dict(duotone=lambda t: 1.0 if t < d * 0.45 + 0.6 else 0.0)
        return sh
    seg(2, s9)
    def s10(d):
        sh = mk('morning', classroom('morning'))
        te = sh.add(Actor('TEACHER', x=-1.6, face=1, pose_='point', eyes='normal', mouth='smile', prop='chalk'))
        teo = sh.add(Actor('TEO', x=1.6, face=-1, pose_='wave', eyes='happy', mouth='grin'))
        sh.cam = C([(0, dict(x=-1.0, y=-1.1, zoom=420)), (d, dict(x=1.0, y=-1.1, zoom=460))])
        return sh
    seg(2, s10)
    def s11(d):
        sh = mk('dusk', kitchen('dusk') + [table_front(eve=True, y=-0.45)])
        mom = sh.add(Actor('MOM', x=0.0, face=1, pose_='stand', eyes='sad', mouth='flat'))
        world(sh, 0.9, lambda cv, t: (cv.save(), cv.translate(0.85, -1.92), d_frame_down(cv, t), cv.restore()), 'frame')
        sh.cam = C([(0, dict(x=0.0, y=-1.1, zoom=600, aperture=0.6)), (d, dict(x=0.6, y=-1.5, zoom=900, aperture=0.6, focus=0.9))])
        return sh
    seg(2, s11)
    # 8. Крыша, трое смотрят на город, кран вверх (8 тактов)
    def s12(d):
        sh = mk('dusk', school_roof('dusk'))
        sh.add(Actor('LEON', x=-0.9, face=-1, pose_='hands_hips', eyes='happy', mouth='grin', wind=0.8))
        sh.add(Actor('RAY', x=0.0, face=-1, pose_='pockets', eyes='lazy', wind=0.8))
        sh.add(Actor('MIRA', x=0.8, face=-1, pose_='hold_front', eyes='normal', prop='notebook', wind=0.8))
        sh.cam = C([(0, dict(x=0.0, y=-0.9, zoom=520)), (d, dict(x=-0.5, y=-3.2, zoom=380, roll=-2))])
        def f(cv, t):
            a = clamp((t - 2) / 0.6) * clamp((d - t) / 0.8)
            FX.credits_block(cv, [('ГОЛОСА', 'ElevenLabs (v4)'), ('МУЗЫКА И ЗВУК', 'Soundza · AI-треки')], 120, H * 0.66, a, size=34)
        screen(sh, f)
        return sh
    seg(8, s12)
    # 8b. Директор и карта с красной точкой (4 такта)
    def s12b(d):
        sh = mk('night', lab() + [holo_map(0.2, -1.35, -0.15, s=1.25, dot=(-0.35, 0.02), label='16:42')])
        glint = [(0.0, 0.0), (d * 0.5, 0.0, 'hold'), (d * 0.5 + 0.2, 1.0, 'lin')]
        sh.layers.append(Obj(3.0, lambda cv, t: d_chair_director(cv, t, glint=Track(glint)(t)), x=1.6, y=0.0))
        sh.cam = C([(0, dict(x=-0.4, y=-1.3, zoom=900, aperture=0.6, focus=-0.15)), (d, dict(x=1.2, y=-1.2, zoom=520, aperture=0.5, focus=3.0))])
        return sh
    seg(4, s12b)
    # 8c. Рэй один на мосту в тумане (4 такта)
    def s12c(d):
        sh = mk('dusk', bridge_deck('dusk') + [bridge_rail_front('dusk', z=-0.7)])
        r = sh.add(Actor('RAY', x=-1.5, face=1, pose_='pockets', eyes='normal', wind=0.8))
        r.move(0, 1.0, dur=d, ease='lin')
        r.set(d * 0.6, 'notch', 1.0, dur=0.3)
        sh.cam = C([(0, dict(x=-1.6, y=-1.0, zoom=700, aperture=0.6)), (d, dict(x=1.0, y=-0.95, zoom=900, aperture=0.6, roll=2))])
        return sh
    seg(4, s12c)
    # 9. Финальный логотип на кульминации (до конца трека ~ 10 тактов)
    rest = 88.4 - (ep.t - T0)
    def s13(d):
        sh = mk('night', [], sky=False)
        sh.bg = lambda cv, t: vgrad(cv, (0, 0, W, H), [hexc('#0b0910'), hexc('#1c0d14')])
        def f(cv, t):
            FX.focus_lines(cv, t, alpha=0.22, color=RED, n=80, inner=0.28, seed=5)
            k = ease_out(clamp(t / 0.6), 3)
            FX.title_logo(cv, t, W / 2, H * 0.45, 0.8 + 0.06 * t / d, alpha=k, crack_prog=1.0)
            a = clamp((t - 1.5) / 0.6) * clamp((d - 1.0 - t) / 0.6)
            draw_text(cv, 'Анимация: процедурный движок vizavi-motion · Python + cairo', W / 2, H * 0.8, font('Inter-SemiBold', 28), calpha(PAPER, a * 0.8), 'center')
            FX.fade_black(cv, clamp((t - (d - 1.0)) / 1.0))
        screen(sh, f)
        return sh
    seg(rest / BAR, s13)
    ep.cue(M + 'op_theme.wav', T0, T0 + 72.0, gain=0.85, fade_in=0.0, fade_out=0.8, loop=False, offset=0.0, duck=False)
    ep.cue(M + 'op_theme.wav', T0 + 71.6, ep.t, gain=0.85, fade_in=0.4, fade_out=0.3, loop=False, offset=140.4, duck=False)
