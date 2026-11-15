# -*- coding: utf-8 -*-
"""Опоры для сидящих: каждому, кто сидит «на стуле» без скамьи под собой, ставится стул нужного типа.
Высота сиденья — SEAT_Y (ступни сидящего стоят на полу). Вызывается в конце сборки серии."""
import gfx as skia
from core import *
from sets import Layer, desk
from stickman import SEAT_Y

STYLE = {'0': 'office', '3.7': 'office', '10': 'office', '3.5': 'bus', '4': 'school',
         '6.5': 'wood', '9': 'kitchen', '2': 'kitchen'}

def draw_chair(cv, X, f, style):
    """Стул в профиль: таз сидящего в X, f — куда он смотрит (спинка сзади)."""
    y0 = SEAT_Y
    bx = X - f * 0.17          # задний край сиденья (у спинки)
    fx = X + f * 0.19          # передний край
    x0, x1 = min(bx, fx), max(bx, fx)
    if style == 'office':
        seat, frame = hexc('#232c52'), hexc('#3a4a7a')
        cv.drawRoundRect(skia.Rect(x0, y0, x1, y0 + 0.055), 0.025, 0.025, P(seat))
        cv.drawRoundRect(skia.Rect(x0, y0, x1, y0 + 0.055), 0.025, 0.025, P(frame, 0.008))
        cv.drawRect(skia.Rect(X - 0.018, y0 + 0.055, X + 0.018, -0.06), P(frame))
        cv.drawLine(X - 0.17, -0.045, X + 0.17, -0.045, P(frame, 0.022))
        for wx in (X - 0.16, X + 0.16):
            cv.drawCircle(wx, -0.022, 0.022, P(hexc('#11162a')))
        # спинка на дуге
        cv.drawLine(bx, y0 + 0.02, bx - f * 0.02, y0 - 0.12, P(frame, 0.02))
        cv.drawRoundRect(skia.Rect(min(bx - f * 0.07, bx + f * 0.02), y0 - 0.42, max(bx - f * 0.07, bx + f * 0.02), y0 - 0.1),
                         0.03, 0.03, P(seat))
    elif style == 'bus':
        seat, frame = hexc('#2f5aa8'), hexc('#8a8f99')
        cv.drawRoundRect(skia.Rect(x0 - 0.02, y0, x1, y0 + 0.07), 0.03, 0.03, P(seat))
        back = skia.Rect(min(bx - f * 0.09, bx + f * 0.01), y0 - 0.6, max(bx - f * 0.09, bx + f * 0.01), y0 + 0.05)
        cv.drawRoundRect(back, 0.04, 0.04, P(seat))
        cv.drawRoundRect(back, 0.04, 0.04, P(hexc('#1d3a70'), 0.01))
        cv.drawLine(bx - f * 0.04, y0 - 0.6, bx - f * 0.04, y0 - 0.68, P(frame, 0.02))
        cv.drawLine(bx - f * 0.04, y0 - 0.68, bx + f * 0.06, y0 - 0.68, P(frame, 0.02))
        cv.drawRect(skia.Rect(X - 0.03, y0 + 0.07, X + 0.03, 0.0), P(frame))
    else:
        if style == 'school':
            wood, leg = hexc('#c79a62'), hexc('#4a4a52')
        elif style == 'kitchen':
            wood, leg = hexc('#7a5032'), hexc('#5a3a24')
        else:
            wood, leg = hexc('#5a3e2a'), hexc('#3e2a1c')
        cv.drawRect(skia.Rect(x0, y0, x1, y0 + 0.045), P(wood))
        cv.drawRect(skia.Rect(x0, y0, x1, y0 + 0.045), P(cmix(wood, INK, 0.4), 0.006))
        for lx in (bx, fx - f * 0.02):
            cv.drawLine(lx, y0 + 0.045, lx, 0.0, P(leg, 0.022))
        # задняя стойка и спинка
        cv.drawLine(bx, y0, bx - f * 0.015, y0 - 0.36, P(leg if style == 'school' else wood, 0.024))
        if style == 'school':
            cv.drawRoundRect(skia.Rect(min(bx - f * 0.05, bx + f * 0.03), y0 - 0.38, max(bx - f * 0.05, bx + f * 0.03), y0 - 0.22),
                             0.02, 0.02, P(wood))
        else:
            for yy in (y0 - 0.33, y0 - 0.2):
                cv.drawLine(bx - f * 0.015, yy, bx + f * 0.03, yy, P(wood, 0.03))

def chair_layer(z, X, f, style):
    L = Layer(z, lambda cv, t: draw_chair(cv, X, f, style), name='chair')
    L.seat = (X - 0.2, X + 0.2)
    return L

def _has_support(sh, a, x):
    for L in sh.layers:
        sp = getattr(L, 'seat', None)
        if sp and sp[0] - 0.05 <= x <= sp[1] + 0.05 and abs(L.z - a.z) < 0.35:
            return True
    return False

def _has_desk(sh, a, x):
    for L in sh.layers:
        sp = getattr(L, 'span', None)
        if sp and sp[0] - 0.1 <= x <= sp[1] + 0.1 and -0.6 < (a.z - L.z) < 0.4:
            return True
    return False

def add_seats(ep):
    added = []
    for sc in ep.scenes:
        style = STYLE.get(sc['id'], 'wood')
        for sh in sc['shots']:
            for a in sh.actors:
                pos = None
                n = int(sh.dur * 5) + 1
                for i in range(n):
                    L = a.state(i / 5.0)
                    s = L.ps.get('sit', 0.0)
                    if 0.2 <= s <= 0.29 and abs(L.ps.get('rot', 0.0)) < 1.0:
                        pos = (L.x, 1.0 if L.face >= 0 else -1.0, L.ps)
                        break
                if pos is None:
                    continue
                X, f, ps = pos
                if _has_support(sh, a, X):
                    continue
                sh.layers.append(chair_layer(a.z + 0.012, X, f, style))
                added.append((sc['id'], a.who, round(X, 2), style))
                # ученик за партой без парты — ставим парту перед ним
                if style == 'school' and not _has_desk(sh, a, X):
                    d = desk(X + f * 0.35, a.z - 0.04, 0.8)
                    d.span = (X + f * 0.35 - 0.4, X + f * 0.35 + 0.4)
                    sh.layers.append(d)
                    added.append((sc['id'], a.who, 'desk'))
    return added


def apply_terrain(ep):
    """Стоящие персонажи на плане рельефа (лестница) ступают по его поверхности."""
    n = 0
    for sh in ep.shots:
        fns = [L for L in sh.layers if getattr(L, 'ground_fn', None) is not None]
        if not fns:
            continue
        for a in sh.actors:
            if any(abs(a.z - L.z) < 0.05 for L in fns):
                a.ground = fns[0].ground_fn
                a._dtab = None
                n += 1
    return n

def reframe_seated(ep, dy=0.2):
    """Сидящие стали ниже на ~0.2: в шотах, где больше половины времени кто-то сидит на стуле, камера опускается."""
    from core import Cam
    n = 0
    for sh in ep.shots:
        if not sh.actors:
            continue
        cnt = tot = 0
        for i in range(int(sh.dur * 4) + 1):
            t = i / 4.0
            tot += 1
            for a in sh.actors:
                L = a.state(t)
                s = L.ps.get('sit', 0.0)
                if 0.2 <= s <= 0.32 and abs(L.ps.get('rot', 0.0)) < 1.0:
                    cnt += 1
                    break
        if cnt < 0.5 * tot:
            continue
        old = sh.cam
        def cam(t, f=old):
            c = f(t)
            return Cam(x=c.x, y=c.y + dy, zoom=c.zoom, roll=c.roll, D=c.D, focus=c.focus, aperture=c.aperture, shake=c.shake)
        sh.cam = cam
        n += 1
    return n

FLOOR_NAMES = ('floor', 'cfloor', 'corrfloor', 'libfloor', 'gymfloor', 'labfloor', 'rfloor', 'yard', 'kfloor', 'busfloor', 'ground', 'deck')
WALL_NAMES = ('roomwall', 'cwall', 'corrwall', 'libback', 'gymback', 'labback', 'rback', 'kwall', 'schoolfront', 'busbody', 'rail', 'fence', 'brail')

def fill_floor_gaps(ep):
    """Пол в интерьерах нарисован вертикальной плоскостью у героев; между ней и дальней стеной камера видит щель.
    Дублируем пол на глубине стены — щели нет, персонажи стоят на полу."""
    n = 0
    for sh in ep.shots:
        floors = [L for L in sh.layers if getattr(L, 'name', '') in FLOOR_NAMES]
        walls = [L for L in sh.layers if getattr(L, 'name', '') in WALL_NAMES]
        if not floors or not walls:
            continue
        f = min(floors, key=lambda L: abs(L.z))
        wz = max(L.z for L in walls)
        if wz <= f.z + 0.05:
            continue
        sh.layers.append(Layer(wz - 0.01, f.fn, name='farfloor'))
        n += 1
    return n
