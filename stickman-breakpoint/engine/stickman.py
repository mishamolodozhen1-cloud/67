# -*- coding: utf-8 -*-
"""Стикмен-риг: скелет, позы, походка, лица, аксессуары персонажей."""
import math
import gfx as skia
from core import *

HEAD_R, NECK, TORSO = 0.105, 0.035, 0.33
UA, FA, TH, SH, FOOT = 0.20, 0.19, 0.245, 0.245, 0.06
LW = 0.030

def rad(a):
    return a * math.pi / 180.0

def D(a):
    a = rad(a)
    return (math.sin(a), math.cos(a))

def add(p, v, k=1.0):
    return (p[0] + v[0] * k, p[1] + v[1] * k)

# ─────────────────────────── позы ───────────────────────────
BASE = dict(lean=0, head=0, ls=-6, le=8, rs=6, re=10, lh=-4, lk=2, rh=5, rk=3, ly=0.0, sit=0.0)

POSES = {
    'stand':     dict(),
    'relaxed':   dict(lean=-2, head=-3, ls=-4, le=4, rs=3, re=5, lh=-6, rh=7),
    'pockets':   dict(lean=-3, head=-4, ls=-12, le=-35, rs=10, re=-38, lh=-5, rh=6),
    'cross':     dict(lean=-2, ls=20, le=105, rs=25, re=100),
    'point':     dict(lean=3, rs=80, re=4, ls=-8, le=10),
    'point_up':  dict(lean=-6, head=-14, rs=150, re=5, ls=-10, le=15),
    'wave':      dict(rs=150, re=25, ls=-5),
    'shrug':     dict(head=6, ls=-40, le=-80, rs=40, re=80),
    'think':     dict(head=8, rs=30, re=135, ls=20, le=90),
    'facepalm':  dict(lean=8, head=18, rs=55, re=140, ls=-6),
    'hands_hips': dict(ls=-35, le=-110, rs=35, re=110),
    'fist_up':   dict(lean=-4, head=-8, rs=160, re=10, ls=-15, le=25),
    'reach':     dict(lean=14, head=6, rs=95, re=0, ls=60, le=10, lh=-20, lk=8, rh=22, rk=6),
    'catch':     dict(lean=4, rs=110, re=40, ls=-10, le=20),
    'shove':     dict(lean=18, rs=88, re=0, ls=80, le=5, lh=-25, lk=10, rh=20, rk=10),
    'stumble':   dict(lean=-18, head=-12, ls=-60, le=30, rs=50, re=60, lh=-18, lk=6, rh=25, rk=20),
    'grab':      dict(lean=10, rs=70, re=20, ls=-15, le=20),
    'phone_up':  dict(lean=-4, head=-6, rs=172, re=4, ls=-10, le=15),
    'hold_front': dict(head=10, rs=55, re=70, ls=40, le=80),
    'write':     dict(head=16, lean=6, rs=45, re=85, ls=40, le=95),
    'eat':       dict(head=-2, rs=55, re=120, ls=-6, le=10),
    'raise_hand': dict(lean=-3, head=4, rs=165, re=20, ls=-8, le=10),
    'throw':     dict(lean=6, rs=120, re=10, ls=-30, le=20),
    'snap':      dict(head=12, rs=55, re=75, ls=50, le=70),
    'arms_out':  dict(ls=-70, le=0, rs=70, re=0),
    'cower':     dict(lean=14, head=20, ls=40, le=120, rs=45, re=125, lh=-12, lk=25, rh=15, rk=30),
    'jump':      dict(lean=-6, ls=-150, le=10, rs=150, re=10, lh=-30, lk=60, rh=40, rk=70, ly=0.18),
    'crouch':    dict(lean=22, head=-10, ls=20, le=40, rs=30, re=50, lh=55, lk=110, rh=65, rk=115),
    'sit':       dict(lean=-4, ls=10, le=60, rs=18, re=70, lh=88, lk=88, rh=92, rk=92, sit=0.47),
    'sit_eat':   dict(lean=-2, head=-2, ls=12, le=70, rs=50, re=125, lh=86, lk=86, rh=90, rk=90, sit=0.47),
    'sit_write': dict(lean=14, head=18, ls=50, le=85, rs=55, re=90, lh=86, lk=86, rh=90, rk=90, sit=0.47),
    'sit_desk':  dict(lean=24, head=20, ls=70, le=80, rs=72, re=82, lh=86, lk=86, rh=90, rk=90, sit=0.47),
    'sit_sleep': dict(lean=58, head=40, ls=95, le=95, rs=100, re=100, lh=86, lk=86, rh=90, rk=90, sit=0.47),
    'sit_ground': dict(lean=-10, head=6, ls=20, le=40, rs=30, re=50, lh=70, lk=100, rh=80, rk=120, sit=0.17),
    'sit_dizzy': dict(lean=22, head=26, ls=50, le=60, rs=58, re=130, lh=60, lk=95, rh=70, rk=105, sit=0.20),
    'lie':       dict(lean=-90, head=-5, ls=-100, le=10, rs=-80, re=20, lh=-90, lk=5, rh=-88, rk=10, sit=0.06),
    'run_pose':  dict(lean=16, ls=-50, le=80, rs=55, re=85, lh=-35, lk=40, rh=45, rk=20),
    'hat_tip':   dict(head=4, rs=150, re=95, ls=-5),
    'phone_ear': dict(head=8, rs=40, re=150, ls=-6, le=8),
    'pocket_one': dict(lean=-2, ls=-12, le=-35, rs=6, re=10),
    'slap_down': dict(lean=6, head=4, rs=70, re=-20, ls=-6),
    'stretch':   dict(lean=-8, head=-16, ls=-170, le=0, rs=170, re=0),
    'bow':       dict(lean=40, head=10, ls=10, le=10, rs=15, re=10),
    'lean_rail': dict(lean=24, head=-12, ls=60, le=40, rs=65, re=35, lh=-8, rh=12),
    'look_hand': dict(head=24, lean=8, rs=60, re=95, ls=-8),
    'tired_hand': dict(head=18, lean=10, rs=48, re=100, ls=-6, le=10),
    'desk_lean': dict(lean=12, head=5, ls=40, le=30, rs=45, re=35),
    'chalk_snap': dict(head=8, rs=55, re=75, ls=48, le=72),
    'present':   dict(lean=2, rs=65, re=40, ls=-8),
}

def pose(name, **over):
    d = dict(BASE)
    d.update(POSES.get(name, {}))
    d.update(over)
    return d

# ─────────────────────────── походка ───────────────────────────
def gait(phase, mode='walk'):
    p = 2 * math.pi * phase
    if mode == 'run':
        A, KB, ARM = 46, 95, 55
        d = dict(lean=16, head=-4, ly=0.035 * abs(math.sin(p)))
        ea = 95
    elif mode == 'sneak':
        A, KB, ARM = 18, 40, 10
        d = dict(lean=10, head=-4, ly=0.0)
        ea = 40
    else:
        A, KB, ARM = 24, 46, 18
        d = dict(lean=3, head=-1, ly=0.0)
        ea = 18
    for side, off in (('r', 0.0), ('l', math.pi)):
        q = p + off
        d[side + 'h'] = A * math.sin(q)
        d[side + 'k'] = 6 + KB * max(0.0, math.cos(q)) ** 1.4
    d['rs'] = -ARM * math.sin(p)
    d['ls'] = ARM * math.sin(p)
    d['re'] = ea + 10 * math.sin(p)
    d['le'] = ea - 10 * math.sin(p)
    return d

# ─────────────────────────── геометрия ───────────────────────────
def skeleton(ps):
    """Скелет в локальных координатах (лицом вправо), бедро в (0,0). Возвращает dict точек."""
    lean = ps['lean']
    hip = (0.0, 0.0)
    td = D(180 - lean)  # вверх и вперёд
    td = (math.sin(rad(lean)), -math.cos(rad(lean)))
    neck = add(hip, td, TORSO)
    sh = add(hip, td, TORSO - 0.03)
    hd = (math.sin(rad(lean + ps['head'])), -math.cos(rad(lean + ps['head'])))
    head = add(neck, hd, NECK + HEAD_R)
    pts = dict(hip=hip, neck=neck, sh=sh, head=head, hang=lean + ps['head'])
    for s in ('l', 'r'):
        a1 = ps[s + 's']
        e = add(sh, D(a1), UA)
        w = add(e, D(a1 + ps[s + 'e']), FA)
        pts[s + 'elb'] = e; pts[s + 'wr'] = w; pts[s + 'fa'] = a1 + ps[s + 'e']
        h1 = ps[s + 'h']
        k = add(hip, D(h1), TH)
        an = add(k, D(h1 - ps[s + 'k']), SH)
        sa = h1 - ps[s + 'k']
        toe = add(an, (math.cos(rad(sa)), -math.sin(rad(sa))), FOOT)
        pts[s + 'kn'] = k; pts[s + 'an'] = an; pts[s + 'toe'] = toe
    return pts

def ground_offset(pts):
    return max(pts['lan'][1], pts['ran'][1], pts['ltoe'][1] - 0.01, pts['rtoe'][1] - 0.01)

# ─────────────────────────── персонажи ───────────────────────────
SPECS = {
    'RAY':   dict(color=RED, hair='messy', scarf=True, scale=1.0),
    'LEON':  dict(color=ORANGE, hair='spiky', band=True, scale=1.02),
    'MIRA':  dict(color=VIOLET, hair='bob', glasses='round', scale=0.97),
    'MAN':   dict(color=CYAN, hat=True, coat=True, scar=True, scale=1.16),
    'MOM':   dict(color=hexc('#2bb5a0'), hair='bun', apron=True, scale=0.98),
    'TEACHER': dict(color=hexc('#c9a227'), hair='bald', glasses='rect', mustache=True, tie=True, scale=1.04),
    'TEO':   dict(color=hexc('#3ccf6e'), hair='short', phones=True, scale=0.99),
    'GRANNY': dict(color=hexc('#d9467a'), scarfhead=True, scale=0.86),
    'KOSTYA': dict(color=hexc('#b5332a'), cap=True, brow=True, scale=1.15, thick=1.25),
    'SHNUR': dict(color=hexc('#7d8794'), hood=True, scale=1.06, thick=0.9),
    'TIM':   dict(color=hexc('#f2c230'), hair='short', backpack=True, scale=0.68),
    'SOL':   dict(color=hexc('#e8eef6'), hair='bun_high', glasses='rect', labcoat=True, scale=1.03),
    'NILS':  dict(color=hexc('#9db3c9'), hair='messy2', labcoat=True, scale=1.0),
    'DIRECTOR': dict(color=hexc('#8899aa'), glasses='round', scale=1.05),
    'EXTRA': dict(color=hexc('#9aa0a8'), scale=1.0),
}

class Look:
    """Состояние персонажа на конкретный кадр (передаётся в draw)."""
    def __init__(self, who, x=0.0, y=0.0, face=1.0, ps=None, eyes='normal', mouth='flat', talk=0.0,
                 brow=0.0, look=(0.0, 0.0), blush=0.0, sweat=0.0, vein=0.0, gloom=0.0, notch=0.0,
                 dash=0.0, thin=1.0, prop=None, prop2=None, t=0.0, vx=0.0, wind=0.25, alpha=1.0,
                 halo=None, halo_w=0.022, ink=None, tint=None, scale=1.0, sil=0.0, glint=0.0):
        self.__dict__.update(locals())
        del self.__dict__['self']
        self.ps = ps or pose('stand')

def draw_char(cv, L):
    sp = SPECS.get(L.who, SPECS['EXTRA'])
    sc = sp.get('scale', 1.0) * L.scale
    pts = skeleton(L.ps)
    g = ground_offset(pts)
    if L.ps.get('sit', 0) > 0:
        hip_y = -L.ps['sit'] * 1.0
    else:
        hip_y = -g
    hip_y -= L.ps.get('ly', 0.0)
    cv.save()
    cv.translate(L.x, L.y)
    cv.scale(sc * L.face, sc)
    cv.translate(0, hip_y)
    if L.ps.get('rot'):
        cv.rotate(L.ps['rot'])
    ink = L.ink or INK
    if L.sil > 0:
        ink = cmix(ink, rgba(0.02, 0.02, 0.04, 1), L.sil)
    thick = sp.get('thick', 1.0) * L.thin
    lw = LW * thick
    halo = L.halo
    alpha = L.alpha
    if alpha < 1.0:
        cv.saveLayerAlpha(None, int(255 * alpha))

    def stroke_paint(color, w):
        p = P(color, w)
        if L.dash > 0:
            on = lerp(0.2, 0.035, L.dash)
            p.setPathEffect(skia.DashPathEffect.Make([on, 0.03 * L.dash + 0.005], (L.t * 0.3) % 1.0))
        return p

    def limb_path(names):
        path = skia.Path()
        for chain in names:
            path.moveTo(*pts[chain[0]])
            for n in chain[1:]:
                path.lineTo(*pts[n])
        return path

    far = limb_path([('sh', 'lelb', 'lwr'), ('hip', 'lkn', 'lan', 'ltoe')])
    body = limb_path([('hip', 'neck'), ('hip', 'rkn', 'ran', 'rtoe')])
    near = limb_path([('sh', 'relb', 'rwr')])
    farcol = cmix(ink, rgba(0.5, 0.5, 0.55, 1), 0.18) if L.sil < 0.5 else ink

    # --- позади тела ---
    if sp.get('scarf'):
        draw_scarf_tail(cv, pts, L, sp['color'], back=True)
    if sp.get('band'):
        draw_band_tail(cv, pts, L, sp['color'])
    if sp.get('backpack'):
        bp = add(pts['hip'], (math.sin(rad(L.ps['lean'])), -math.cos(rad(L.ps['lean']))), 0.2)
        r = skia.RRect.MakeRectXY(skia.Rect(bp[0] - 0.17, bp[1] - 0.12, bp[0] - 0.02, bp[1] + 0.12), 0.04, 0.04)
        if halo is not None:
            cv.drawRRect(r, P(halo, L.halo_w * 2))
        cv.drawRRect(r, P(cmix(sp['color'], ink, L.sil)))
        cv.drawRRect(r, P(ink, lw * 0.6))
    if sp.get('coat'):
        draw_coat(cv, pts, L, ink, back=True)
    if halo is not None:
        hp = stroke_paint(halo, lw + L.halo_w * 2)
        cv.drawPath(far, hp); cv.drawPath(body, hp); cv.drawPath(near, hp)
    cv.drawPath(far, stroke_paint(farcol, lw))
    if sp.get('labcoat'):
        draw_labcoat(cv, pts, L, ink)
    cv.drawPath(body, stroke_paint(ink, lw))
    if sp.get('coat'):
        draw_coat(cv, pts, L, ink, back=False)
    if sp.get('apron'):
        draw_apron(cv, pts, L, ink)
    if sp.get('tie'):
        a = add(pts['neck'], (0, 0.02)); b = add(pts['neck'], (math.sin(rad(L.ps['lean'])) * 0.14, 0.14))
        cv.drawPath(poly([a, (b[0] - 0.02, b[1] - 0.03), (b[0], b[1]), (b[0] + 0.02, b[1] - 0.03)]),
                    P(cmix(sp['color'], ink, L.sil)))
    if sp.get('scarf'):
        draw_scarf_wrap(cv, pts, L, sp['color'])
    # --- голова ---
    draw_head(cv, pts, L, sp, ink, lw)
    # --- ближняя рука поверх ---
    cv.drawPath(near, stroke_paint(ink, lw))
    if L.prop:
        draw_prop(cv, L.prop, pts['rwr'], pts['rfa'], ink, L)
    if L.prop2:
        draw_prop(cv, L.prop2, pts['lwr'], pts['lfa'], ink, L)
    if L.notch > 0:
        w = pts['rwr']
        glow = P(calpha(RED, 0.65 * L.notch), blur=0.03)
        cv.drawCircle(w[0], w[1], 0.05, glow)
        cv.drawPath(poly([(w[0] - 0.018, w[1] - 0.03), (w[0] + 0.012, w[1]), (w[0] - 0.018, w[1] + 0.03)], False),
                    P(calpha(hexc('#ff6a50'), L.notch), 0.014))
    if alpha < 1.0:
        cv.restore()
    cv.restore()
    return pts

# ─────────────────────────── голова и лицо ───────────────────────────
def draw_head(cv, pts, L, sp, ink, lw):
    hx, hy = pts['head']
    r = HEAD_R
    cv.save()
    cv.translate(hx, hy)
    cv.rotate(pts['hang'] * 0.6)
    halo = L.halo
    if sp.get('hair') == 'bob':
        draw_hair_back(cv, r, sp, L, ink)
    if halo is not None:
        cv.drawCircle(0, 0, r + L.halo_w + lw * 0.5, P(halo))
    paper = cmix(PAPER, rgba(0.05, 0.05, 0.08, 1), L.sil)
    if L.tint is not None:
        paper = cmix(paper, L.tint, 0.35)
    cv.drawCircle(0, 0, r, P(paper))
    if L.sil < 0.95:
        draw_face(cv, r, L, sp, ink)
    cv.drawCircle(0, 0, r, P(ink, lw * 0.85))
    draw_hair(cv, r, sp, L, ink)
    if L.sil > 0.6 and sp.get('scar'):
        pass
    cv.restore()

def draw_hair_back(cv, r, sp, L, ink):
    col = cmix(hexc('#2a1f3d'), ink, L.sil)
    path = smooth_path([(-r * 1.05, -r * 0.2), (-r * 1.18, r * 0.55), (-r * 0.9, r * 1.02), (-r * 0.2, r * 0.75)], False)
    path.lineTo(r * 0.2, -r * 0.3); path.close()
    cv.drawPath(path, P(col))

def draw_hair(cv, r, sp, L, ink):
    h = sp.get('hair')
    t = L.t
    wob = math.sin(t * 2.3 + hash01(L.who) * 6) * 0.04 * (0.4 + L.wind)
    if h == 'messy':
        pts = [(-r * 1.0, -r * 0.1), (-r * 1.35, -r * 0.55 + wob * r), (-r * 0.75, -r * 0.7),
               (-r * 1.0, -r * 1.25 + wob * r), (-r * 0.25, -r * 0.95), (-r * 0.15, -r * 1.45 + wob * r),
               (r * 0.35, -r * 0.95), (r * 0.75, -r * 1.25 + wob * r * 0.5), (r * 0.85, -r * 0.6),
               (r * 0.98, -r * 0.2), (r * 0.5, -r * 0.55), (-r * 0.1, -r * 0.62), (-r * 0.7, -r * 0.45)]
        cv.drawPath(poly(pts), P(ink))
    elif h == 'messy2':
        pts = [(-r * 1.0, -r * 0.2), (-r * 1.2, -r * 0.7), (-r * 0.6, -r * 0.85), (-r * 0.5, -r * 1.25),
               (0, -r * 0.95), (r * 0.4, -r * 1.3), (r * 0.6, -r * 0.85), (r * 1.1, -r * 0.8), (r * 0.95, -r * 0.3),
               (r * 0.2, -r * 0.6), (-r * 0.6, -r * 0.5)]
        cv.drawPath(poly(pts), P(cmix(hexc('#4a3a2a'), ink, L.sil)))
    elif h == 'spiky':
        pts = [(-r * 1.0, -r * 0.05)]
        spikes = [(-1.4, -0.5), (-1.05, -1.15), (-0.45, -1.55), (0.2, -1.6), (0.75, -1.3), (1.25, -0.85)]
        base = [(-0.9, -0.55), (-0.6, -0.85), (-0.15, -1.0), (0.35, -0.98), (0.8, -0.75), (0.98, -0.25)]
        for (sx, sy), (bx, by) in zip(spikes, base):
            pts.append((sx * r, sy * r + wob * r * 0.6))
            pts.append((bx * r, by * r))
        pts += [(r * 0.6, -r * 0.55), (-r * 0.4, -r * 0.6)]
        cv.drawPath(poly(pts), P(ink))
        # повязка
        band = P(cmix(sp['color'], ink, L.sil), r * 0.28, cap='butt')
        cv.drawArc(skia.Rect(-r * 0.98, -r * 0.98, r * 0.98, r * 0.98), 196, 148, False, band)
    elif h == 'bob':
        col = cmix(hexc('#2a1f3d'), ink, L.sil)
        path = skia.Path()
        path.moveTo(-r * 1.08, r * 0.55)
        path.cubicTo(-r * 1.25, -r * 0.6, -r * 0.6, -r * 1.3, r * 0.15, -r * 1.12)
        path.cubicTo(r * 0.8, -r * 1.02, r * 1.15, -r * 0.55, r * 1.08, -r * 0.05)
        path.cubicTo(r * 0.75, -r * 0.55, r * 0.35, -r * 0.62, r * 0.1, -r * 0.45)  # чёлка
        path.cubicTo(-r * 0.2, -r * 0.62, -r * 0.55, -r * 0.5, -r * 0.7, -r * 0.2)
        path.cubicTo(-r * 0.8, r * 0.1, -r * 0.82, r * 0.35, -r * 1.08, r * 0.55)
        cv.drawPath(path, P(col))
        cv.drawCircle(r * 0.62, -r * 0.62, r * 0.12, P(cmix(sp['color'], ink, L.sil)))
    elif h == 'bun':
        col = cmix(hexc('#3b2a22'), ink, L.sil)
        cv.drawCircle(-r * 0.75, -r * 0.85, r * 0.42, P(col))
        cv.drawArc(skia.Rect(-r * 1.02, -r * 1.02, r * 1.02, r * 1.02), 190, 150, True, P(col))
    elif h == 'bun_high':
        col = cmix(hexc('#c9c2b0'), ink, L.sil)
        cv.drawCircle(-r * 0.2, -r * 1.25, r * 0.35, P(col))
        cv.drawArc(skia.Rect(-r * 1.02, -r * 1.02, r * 1.02, r * 1.02), 185, 170, True, P(col))
    elif h == 'short':
        cv.drawArc(skia.Rect(-r * 1.05, -r * 1.08, r * 1.05, r * 1.0), 180, 180, True, P(ink))
        cv.drawPath(poly([(r * 0.2, -r * 0.95), (r * 0.9, -r * 0.6), (r * 0.5, -r * 0.4)]), P(ink))
    elif h == 'bald':
        col = cmix(hexc('#8a8a8a'), ink, L.sil)
        cv.drawPath(poly([(-r * 1.02, -r * 0.1), (-r * 1.12, -r * 0.45), (-r * 0.85, -r * 0.55), (-r * 0.8, -r * 0.1)]), P(col))
    if sp.get('scarfhead'):
        col = cmix(sp['color'], ink, L.sil)
        path = skia.Path()
        path.moveTo(-r * 1.15, r * 0.35)
        path.cubicTo(-r * 1.3, -r * 0.9, r * 0.6, -r * 1.5, r * 1.05, -r * 0.2)
        path.lineTo(r * 0.7, -r * 0.35)
        path.cubicTo(r * 0.2, -r * 0.8, -r * 0.6, -r * 0.6, -r * 0.8, r * 0.3)
        path.close()
        cv.drawPath(path, P(col))
        for k in range(5):
            cv.drawCircle(-r * 0.6 + k * r * 0.3, -r * 0.8 + abs(k - 2) * r * 0.12, r * 0.06, P(PAPER))
        cv.drawPath(poly([(-r * 1.0, r * 0.4), (-r * 1.45, r * 0.95), (-r * 0.95, r * 0.85)]), P(col))
    if sp.get('cap'):
        col = cmix(sp['color'], ink, L.sil)
        cv.drawArc(skia.Rect(-r * 1.04, -r * 1.06, r * 1.04, r * 1.0), 180, 180, True, P(col))
        cv.drawPath(poly([(-r * 0.95, -r * 0.2), (-r * 1.7, -r * 0.05), (-r * 1.6, r * 0.12), (-r * 0.95, r * 0.02)]), P(col))
        cv.drawLine(-r * 1.0, -r * 0.1, r * 1.0, -r * 0.1, P(ink, r * 0.08))
    if sp.get('hood'):
        col = cmix(sp['color'], ink, L.sil)
        path = skia.Path()
        path.addArc(skia.Rect(-r * 1.3, -r * 1.3, r * 1.3, r * 1.3), 100, 230)
        path.lineTo(r * 0.7, -r * 0.6)
        path.arcTo(skia.Rect(-r * 1.0, -r * 1.0, r * 1.0, r * 1.0), 300, -200, False)
        path.close()
        cv.drawPath(path, P(col))
    if sp.get('phones'):
        col = cmix(sp['color'], ink, L.sil)
        cv.drawArc(skia.Rect(-r * 1.15, -r * 1.25, r * 1.15, r * 1.05), 200, 140, False, P(ink, r * 0.12))
        cv.drawRoundRect(skia.Rect(-r * 1.3, -r * 0.35, -r * 0.85, r * 0.25), r * 0.15, r * 0.15, P(col))
    if sp.get('hat'):
        col = cmix(hexc('#1e2230'), ink, L.sil * 0.5)
        cv.drawPath(poly([(-r * 1.65, -r * 0.55), (r * 1.75, -r * 0.62), (r * 1.6, -r * 0.42), (-r * 1.5, -r * 0.36)]), P(col))
        cv.drawPath(poly([(-r * 0.95, -r * 0.5), (-r * 0.85, -r * 1.55), (r * 0.9, -r * 1.6), (r * 1.0, -r * 0.55)]), P(col))
        cv.drawLine(-r * 0.92, -r * 0.72, r * 0.98, -r * 0.76, P(hexc('#5a6070'), r * 0.14, cap='butt'))
    g = sp.get('glasses')
    if g:
        gx = r * 0.32 * 1.0
        gp = P(ink, r * 0.09)
        if g == 'round':
            cv.drawCircle(gx - r * 0.38, -r * 0.05, r * 0.24, gp)
            cv.drawCircle(gx + r * 0.32, -r * 0.05, r * 0.24, gp)
        else:
            cv.drawRect(skia.Rect(gx - r * 0.62, -r * 0.2, gx - r * 0.14, r * 0.1), gp)
            cv.drawRect(skia.Rect(gx + r * 0.08, -r * 0.2, gx + r * 0.56, r * 0.1), gp)
        cv.drawLine(gx - r * 0.14, -r * 0.08, gx + r * 0.08, -r * 0.08, gp)
        if L.glint > 0:
            gl = P(calpha(rgba(1, 1, 1, 1), L.glint))
            for cxg in (gx - r * 0.38, gx + r * 0.32):
                cv.drawCircle(cxg, -r * 0.05, r * 0.24, P(calpha(rgba(1, 1, 1, 1), 0.85 * L.glint)))
    if sp.get('mustache'):
        col = cmix(hexc('#5a5a5a'), ink, L.sil)
        cv.drawPath(smooth_path([(r * 0.0, r * 0.38), (r * 0.25, r * 0.26), (r * 0.5, r * 0.3), (r * 0.78, r * 0.42),
                                 (r * 0.5, r * 0.45), (r * 0.25, r * 0.42)], True), P(col))

EYE_Y = -0.05
def draw_face(cv, r, L, sp, ink):
    fo = r * 0.32  # смещение лица к направлению взгляда (3/4 вид)
    ex = [fo - r * 0.38, fo + r * 0.32]
    ey = r * EYE_Y + r * L.look[1] * 0.15
    lx = r * L.look[0] * 0.12
    eyes = L.eyes
    # моргание
    if eyes in ('normal', 'lazy', 'serious', 'angry', 'sad', 'wide') and L.blink:
        eyes = 'closed'
    p_ink = P(ink)
    s_ink = P(ink, r * 0.11)
    for k, x in enumerate(ex):
        x += lx
        if sp.get('scar') and k == 0:
            # глаз под шрамом
            cv.drawLine(x - r * 0.15, ey, x + r * 0.15, ey, P(ink, r * 0.09))
            continue
        if eyes == 'dot':
            cv.drawCircle(x, ey, r * 0.075, p_ink)
        elif eyes == 'normal':
            cv.drawOval(skia.Rect(x - r * 0.1, ey - r * 0.16, x + r * 0.1, ey + r * 0.16), p_ink)
            cv.drawCircle(x + r * 0.03, ey - r * 0.07, r * 0.04, P(PAPER))
        elif eyes == 'lazy':
            cv.save()
            cv.clipRect(skia.Rect(x - r * 0.2, ey - r * 0.02, x + r * 0.2, ey + r * 0.3))
            cv.drawOval(skia.Rect(x - r * 0.11, ey - r * 0.14, x + r * 0.11, ey + r * 0.16), p_ink)
            cv.restore()
            cv.drawLine(x - r * 0.15, ey - r * 0.02, x + r * 0.15, ey - r * 0.04, P(ink, r * 0.08))
        elif eyes == 'serious':
            pth = poly([(x - r * 0.14, ey - r * 0.08), (x + r * 0.14, ey - r * 0.14), (x + r * 0.12, ey + r * 0.1),
                        (x - r * 0.12, ey + r * 0.08)])
            cv.drawPath(pth, p_ink)
            cv.drawCircle(x + r * 0.04, ey - r * 0.04, r * 0.035, P(PAPER))
            cv.drawLine(x - r * 0.2, ey - r * 0.26 + (k * 2 - 1) * r * 0.04, x + r * 0.18, ey - r * 0.2 - (k * 2 - 1) * r * 0.05,
                        P(ink, r * 0.09))
        elif eyes == 'angry':
            cv.drawOval(skia.Rect(x - r * 0.1, ey - r * 0.13, x + r * 0.1, ey + r * 0.15), p_ink)
            dy = (r * 0.09) * (1 if k == 0 else -1)
            cv.drawLine(x - r * 0.18, ey - r * 0.25 - dy, x + r * 0.18, ey - r * 0.25 + dy, P(ink, r * 0.1))
        elif eyes == 'sad':
            cv.drawOval(skia.Rect(x - r * 0.1, ey - r * 0.13, x + r * 0.1, ey + r * 0.15), p_ink)
            dy = (r * 0.08) * (1 if k == 0 else -1)
            cv.drawLine(x - r * 0.17, ey - r * 0.24 + dy, x + r * 0.17, ey - r * 0.24 - dy, P(ink, r * 0.08))
        elif eyes == 'closed':
            cv.drawArc(skia.Rect(x - r * 0.13, ey - r * 0.1, x + r * 0.13, ey + r * 0.1), 10, 160, False, s_ink)
        elif eyes == 'happy':
            cv.drawArc(skia.Rect(x - r * 0.13, ey - r * 0.08, x + r * 0.13, ey + r * 0.16), 190, 160, False, s_ink)
        elif eyes == 'wide':
            cv.drawCircle(x, ey, r * 0.17, P(PAPER))
            cv.drawCircle(x, ey, r * 0.17, P(ink, r * 0.07))
            cv.drawCircle(x + lx * 0.5, ey, r * 0.05, p_ink)
        elif eyes == 'shock':
            cv.drawCircle(x, ey, r * 0.2, P(PAPER))
            cv.drawCircle(x, ey, r * 0.2, P(ink, r * 0.06))
            cv.drawCircle(x, ey, r * 0.03, p_ink)
        elif eyes == 'cold':
            cv.drawPath(poly([(x - r * 0.15, ey - r * 0.02), (x + r * 0.15, ey - r * 0.08), (x + r * 0.13, ey + r * 0.06),
                              (x - r * 0.13, ey + r * 0.06)]), p_ink)
            cv.drawCircle(x + r * 0.02, ey, r * 0.045, P(CYAN))
            cv.drawCircle(x + r * 0.02, ey, r * 0.12, P(calpha(CYAN, 0.35), blur=r * 0.08))
    if sp.get('scar'):
        cv.drawLine(ex[0] - r * 0.35, ey - r * 0.45, ex[0] + r * 0.25, ey + r * 0.45, P(ink, r * 0.07))
    if sp.get('brow') and eyes not in ('angry', 'serious'):
        cv.drawLine(ex[0] - r * 0.15, ey - r * 0.24, ex[1] + r * 0.15, ey - r * 0.24, P(ink, r * 0.1))
    if L.brow:
        for k, x in enumerate(ex):
            dy = L.brow * r * 0.1 * (1 if k == 0 else -1)
            cv.drawLine(x - r * 0.15, ey - r * 0.27 - dy, x + r * 0.15, ey - r * 0.27 + dy, P(ink, r * 0.07))
    # рот
    mx, my = fo * 0.85, r * 0.45
    if sp.get('mustache'):
        my += r * 0.05
    m = L.mouth
    a = clamp(L.talk)
    if a > 0.06 and m not in ('grin_open', 'scream'):
        h = r * (0.05 + 0.26 * a)
        w_ = r * (0.16 + 0.08 * a)
        cv.drawOval(skia.Rect(mx - w_, my - h * 0.55, mx + w_, my + h * 0.65), p_ink)
        if a > 0.35:
            cv.drawOval(skia.Rect(mx - w_ * 0.55, my + h * 0.05, mx + w_ * 0.55, my + h * 0.55), P(hexc('#c0453a')))
        return
    mp = P(ink, r * 0.09)
    if m == 'flat':
        cv.drawLine(mx - r * 0.13, my, mx + r * 0.13, my, mp)
    elif m == 'smile':
        cv.drawArc(skia.Rect(mx - r * 0.2, my - r * 0.18, mx + r * 0.2, my + r * 0.1), 20, 140, False, mp)
    elif m == 'grin':
        pth = skia.Path(); pth.moveTo(mx - r * 0.25, my - r * 0.06)
        pth.quadTo(mx, my + r * 0.36, mx + r * 0.27, my - r * 0.08); pth.close()
        cv.drawPath(pth, p_ink)
        cv.drawRect(skia.Rect(mx - r * 0.2, my - r * 0.04, mx + r * 0.22, my + r * 0.03), P(PAPER))
    elif m == 'frown':
        cv.drawArc(skia.Rect(mx - r * 0.18, my - r * 0.02, mx + r * 0.18, my + r * 0.24), 200, 140, False, mp)
    elif m == 'o':
        cv.drawOval(skia.Rect(mx - r * 0.08, my - r * 0.1, mx + r * 0.08, my + r * 0.12), p_ink)
    elif m == 'smirk':
        pth = skia.Path(); pth.moveTo(mx - r * 0.14, my + r * 0.02); pth.quadTo(mx + r * 0.05, my + r * 0.06, mx + r * 0.2, my - r * 0.08)
        cv.drawPath(pth, mp)
    elif m == 'wavy':
        pth = skia.Path(); pth.moveTo(mx - r * 0.2, my)
        for k in range(4):
            pth.quadTo(mx - r * 0.15 + k * r * 0.1, my + (r * 0.08 if k % 2 == 0 else -r * 0.08), mx - r * 0.1 + k * r * 0.1, my)
        cv.drawPath(pth, P(ink, r * 0.07))
    elif m == 'teeth':
        cv.drawRect(skia.Rect(mx - r * 0.22, my - r * 0.08, mx + r * 0.22, my + r * 0.1), p_ink)
        cv.drawRect(skia.Rect(mx - r * 0.17, my - r * 0.04, mx + r * 0.17, my + r * 0.05), P(PAPER))
        for k in range(-1, 2):
            cv.drawLine(mx + k * r * 0.09, my - r * 0.04, mx + k * r * 0.09, my + r * 0.05, P(ink, r * 0.03))
    elif m == 'scream':
        cv.drawOval(skia.Rect(mx - r * 0.2, my - r * 0.2, mx + r * 0.2, my + r * 0.3), p_ink)
    elif m == 'grin_open':
        pth = skia.Path(); pth.moveTo(mx - r * 0.25, my - r * 0.08)
        pth.quadTo(mx, my + r * 0.5, mx + r * 0.27, my - r * 0.1); pth.close()
        cv.drawPath(pth, p_ink)
    elif m == 'chew':
        k = math.sin(L.t * 14)
        cv.drawOval(skia.Rect(mx - r * 0.14, my - r * 0.04 - k * r * 0.03, mx + r * 0.14, my + r * 0.08 + k * r * 0.03), p_ink)
    # эмоции
    if L.blush > 0:
        bp = P(calpha(hexc('#ff6b6b'), 0.55 * L.blush))
        for x in ex:
            cv.drawOval(skia.Rect(x - r * 0.18, r * 0.18, x + r * 0.12, r * 0.3), bp)
    if L.sweat > 0:
        sx, sy = r * 1.05, -r * 0.6 + (L.t * 0.4 % 1.0) * r * 0.5 * L.sweat
        pth = skia.Path(); pth.moveTo(sx, sy - r * 0.3)
        pth.cubicTo(sx + r * 0.2, sy, sx + r * 0.15, sy + r * 0.2, sx, sy + r * 0.2)
        pth.cubicTo(sx - r * 0.15, sy + r * 0.2, sx - r * 0.2, sy, sx, sy - r * 0.3)
        cv.drawPath(pth, P(hexc('#8fd3ff', 0.9 * L.sweat)))
        cv.drawPath(pth, P(ink, r * 0.04))
    if L.vein > 0:
        vx, vy = r * 0.55, -r * 0.65
        vp = P(calpha(hexc('#e8402f'), L.vein), r * 0.08)
        for ang in (0, 90, 180, 270):
            c, s_ = math.cos(rad(ang + 45)), math.sin(rad(ang + 45))
            cv.drawArc(skia.Rect(vx + c * r * 0.12 - r * 0.1, vy + s_ * r * 0.12 - r * 0.1,
                                 vx + c * r * 0.12 + r * 0.1, vy + s_ * r * 0.12 + r * 0.1), ang + 135, 90, False, vp)
    if L.gloom > 0:
        gp = P(calpha(rgba(0.25, 0.2, 0.45, 1), 0.7 * L.gloom), r * 0.05)
        for k in range(6):
            x = -r * 0.8 + k * r * 0.32
            cv.drawLine(x, -r * 1.05, x, -r * 0.25 - (k % 2) * r * 0.2, gp)

# ─────────────────────────── аксессуары ───────────────────────────
def scarf_wave(L, k, n):
    t = L.t
    wind = L.wind + min(1.2, abs(L.vx) * 0.8)
    amp = 0.035 * (0.5 + wind)
    return math.sin(t * (5 + wind * 4) - k * 0.9) * amp * (k / n) + fbm(t * 1.3 + k * 0.2, 5) * 0.02 * wind

def draw_scarf_wrap(cv, pts, L, col):
    n = pts['neck']
    c = cmix(col, INK, L.sil)
    cv.drawLine(n[0] - 0.05, n[1] + 0.02, n[0] + 0.05, n[1] + 0.005, P(c, 0.05))
    if L.halo is not None:
        pass

def draw_scarf_tail(cv, pts, L, col, back=True):
    n = pts['neck']
    c = cmix(col, INK, L.sil)
    wind = L.wind + min(1.2, abs(L.vx) * 0.8)
    length = 0.36
    N = 7
    pts_top, pts_bot = [], []
    for k in range(N + 1):
        u = k / N
        dx = -u * length * (0.55 + 0.45 * clamp(wind))
        dy = u * length * (0.75 - 0.6 * clamp(wind)) + scarf_wave(L, k, N)
        x, y = n[0] - 0.02 + dx, n[1] + 0.03 + dy
        w = 0.032 * (1 - 0.5 * u)
        pts_top.append((x, y - w)); pts_bot.append((x, y + w))
    path = smooth_path(pts_top + pts_bot[::-1], close=True)
    if L.halo is not None:
        cv.drawPath(path, P(L.halo, L.halo_w * 2))
    cv.drawPath(path, P(c))
    # второй хвост
    pts2 = []
    for k in range(N + 1):
        u = k / N
        dx = -u * length * 0.8 * (0.5 + 0.5 * clamp(wind))
        dy = u * length * 0.9 * (0.8 - 0.6 * clamp(wind)) + scarf_wave(L, k + 3, N) * 1.2
        pts2.append((n[0] + dx, n[1] + 0.04 + dy))
    cv.drawPath(smooth_path(pts2), P(cmix(c, INK, 0.25), 0.04))

def draw_band_tail(cv, pts, L, col):
    h = pts['head']
    c = cmix(col, INK, L.sil)
    wind = L.wind + min(1.2, abs(L.vx) * 0.8)
    for j in (0, 1):
        ps_ = []
        for k in range(6):
            u = k / 5
            ps_.append((h[0] - HEAD_R * 0.9 - u * 0.2 * (0.6 + 0.4 * clamp(wind)),
                        h[1] - HEAD_R * 0.55 + u * 0.12 * (1 - clamp(wind)) + j * 0.03 + scarf_wave(L, k + j * 2, 5)))
        cv.drawPath(smooth_path(ps_), P(c, 0.028 - j * 0.006))

def draw_coat(cv, pts, L, ink, back):
    col = cmix(hexc('#262b38'), ink, L.sil * 0.6)
    sh, hip = pts['sh'], pts['hip']
    t = L.t
    flap = math.sin(t * 2.2) * 0.03 * (0.5 + L.wind) + fbm(t * 0.9, 3) * 0.04 * L.wind
    knee_y = hip[1] + 0.36
    if back:
        path = poly([(sh[0] - 0.06, sh[1] - 0.02), (sh[0] + 0.05, sh[1] - 0.02),
                     (hip[0] + 0.12, knee_y), (hip[0] - 0.2 - flap * 2.5, knee_y + 0.03 + flap)])
        if L.halo is not None:
            cv.drawPath(path, P(L.halo, L.halo_w * 2))
        cv.drawPath(path, P(col))
    else:
        cv.drawLine(sh[0] + 0.02, sh[1] + 0.02, hip[0] + 0.1, knee_y - 0.02, P(hexc('#3c4354'), 0.012))
        cv.drawPath(poly([(sh[0] - 0.02, sh[1] - 0.03), (sh[0] + 0.07, sh[1] - 0.06), (sh[0] + 0.03, sh[1] + 0.08)]),
                    P(hexc('#3c4354')))

def draw_labcoat(cv, pts, L, ink):
    col = cmix(hexc('#f4f7fb'), ink, L.sil * 0.8)
    sh, hip = pts['sh'], pts['hip']
    path = poly([(sh[0] - 0.06, sh[1] - 0.01), (sh[0] + 0.06, sh[1] - 0.01), (hip[0] + 0.1, hip[1] + 0.22),
                 (hip[0] - 0.13, hip[1] + 0.24)])
    cv.drawPath(path, P(col))
    cv.drawPath(path, P(ink, 0.01))

def draw_apron(cv, pts, L, ink):
    sh, hip = pts['sh'], pts['hip']
    col = cmix(hexc('#f6d7c3'), ink, L.sil)
    path = poly([(sh[0] + 0.0, sh[1] + 0.08), (sh[0] + 0.06, sh[1] + 0.08), (hip[0] + 0.1, hip[1] + 0.12), (hip[0] - 0.06, hip[1] + 0.14)])
    cv.drawPath(path, P(col)); cv.drawPath(path, P(ink, 0.008))

# ─────────────────────────── реквизит в руке ───────────────────────────
def draw_prop(cv, prop, w, ang, ink, L):
    cv.save()
    cv.translate(*w)
    cv.rotate(-ang)  # ось предплечья
    if prop == 'phone':
        r = skia.RRect.MakeRectXY(skia.Rect(-0.035, -0.0, 0.035, 0.11), 0.012, 0.012)
        cv.drawRRect(r, P(hexc('#222833'))); cv.drawRRect(r, P(ink, 0.008))
        cv.drawRect(skia.Rect(-0.026, 0.012, 0.026, 0.096), P(hexc('#6fb6ff', 0.9)))
    elif prop == 'notebook':
        r = skia.Rect(-0.08, -0.01, 0.07, 0.17)
        cv.drawRect(r, P(hexc('#f7e7a8'))); cv.drawRect(r, P(ink, 0.008))
        for k in range(5):
            cv.drawLine(-0.06, 0.03 + k * 0.025, 0.05, 0.03 + k * 0.025, P(hexc('#8a7a50'), 0.004))
    elif prop == 'toast':
        cv.drawRoundRect(skia.Rect(-0.05, 0.0, 0.05, 0.09), 0.02, 0.02, P(hexc('#e2a85a')))
        cv.drawRoundRect(skia.Rect(-0.05, 0.0, 0.05, 0.09), 0.02, 0.02, P(hexc('#8a5a2a'), 0.008))
    elif prop == 'apple':
        cv.drawCircle(0, 0.04, 0.04, P(hexc('#e23b3b'))); cv.drawCircle(0, 0.04, 0.04, P(ink, 0.007))
        cv.drawLine(0, 0.0, 0.01, -0.02, P(hexc('#5a3a1a'), 0.008))
    elif prop == 'bun':
        cv.drawOval(skia.Rect(-0.055, 0.0, 0.055, 0.07), P(hexc('#d9954a'))); cv.drawOval(skia.Rect(-0.055, 0.0, 0.055, 0.07), P(ink, 0.007))
    elif prop == 'chalk':
        cv.drawLine(0, 0.0, 0, 0.06, P(PAPER, 0.018))
    elif prop == 'pencil':
        cv.drawLine(0, -0.03, 0, 0.11, P(hexc('#f2c230'), 0.016))
        cv.drawLine(0, 0.11, 0, 0.13, P(ink, 0.01))
    elif prop == 'clipboard':
        r = skia.Rect(-0.09, -0.02, 0.07, 0.19)
        cv.drawRect(r, P(hexc('#b08a5a'))); cv.drawRect(skia.Rect(-0.075, 0.0, 0.055, 0.17), P(PAPER))
        cv.drawRect(r, P(ink, 0.008))
    elif prop == 'paper':
        r = skia.Rect(-0.07, -0.0, 0.06, 0.15)
        cv.drawRect(r, P(PAPER)); cv.drawRect(r, P(ink, 0.006))
    elif prop == 'spoon':
        cv.drawLine(0, 0, 0, 0.09, P(hexc('#b8bec8'), 0.01)); cv.drawOval(skia.Rect(-0.015, 0.08, 0.015, 0.12), P(hexc('#b8bec8')))
    elif prop == 'photo':
        r = skia.Rect(-0.06, -0.01, 0.07, 0.1)
        cv.drawRect(r, P(hexc('#e8dcc0'))); cv.drawRect(r, P(ink, 0.006))
    elif prop == 'pointer':
        cv.drawLine(0, 0, 0, 0.45, P(hexc('#7a4a2a'), 0.012))
    cv.restore()

# ─────────────────────────── актёр ───────────────────────────
class Actor:
    """Персонаж в кадре: дорожки позиции/позы/лица + процедурные слои (дыхание, моргание, речь, походка)."""
    def __init__(self, who, x=0.0, y=0.0, face=1, pose_='stand', eyes='normal', mouth='flat', z=0.0, **kw):
        self.who = who
        self.z = z
        self.xk = [(0.0, x)]
        self.yk = [(0.0, y)]
        self.fk = [(0.0, float(face))]
        self.pk = [(0.0, pose(pose_) if isinstance(pose_, str) else pose_, 'io')]
        self.ek = [(0.0, eyes)]
        self.mk = [(0.0, mouth)]
        self.extra = {}       # имя -> [(t, value)] (числовые параметры: blush, sweat, notch, dash...)
        self.props = [(0.0, kw.pop('prop', None))]
        self.props2 = [(0.0, kw.pop('prop2', None))]
        self.gait_mode = kw.pop('gait', 'walk')
        self.talks = []       # (t0, envelope_fn, dur)
        self.kw = kw          # постоянные параметры Look
        self.seed = hash01(who, x, face) * 100
        self.locked_gait = None
        self.gait_override = []  # [(t0, t1, mode)]

    # --- ключи ---
    def move(self, t, x, dur=1.0, ease='io', y=None):
        lx = self._last(self.xk, t)
        self.xk.append((t, lx, 'hold'))
        self.xk.append((t + dur, x, ease))
        if y is not None:
            ly = self._last(self.yk, t)
            self.yk.append((t, ly, 'hold'))
            self.yk.append((t + dur, y, ease))
        return self

    def place(self, t, x=None, y=None):
        if x is not None:
            self.xk.append((t, x, 'hold'))
        if y is not None:
            self.yk.append((t, y, 'hold'))
        return self

    def face(self, t, f, dur=0.18):
        lf = self._last(self.fk, t)
        self.fk.append((t, lf, 'hold'))
        self.fk.append((t + dur, float(f), 'io'))
        return self

    def pose(self, t, name, dur=0.35, ease='io', **over):
        ps = pose(name, **over) if isinstance(name, str) else name
        cur = self._last_pose(t)
        self.pk.append((t, cur, 'hold'))
        self.pk.append((t + dur, ps, ease))
        return self

    def expr(self, t, eyes=None, mouth=None):
        if eyes is not None:
            self.ek.append((t, eyes))
        if mouth is not None:
            self.mk.append((t, mouth))
        return self

    def set(self, t, name, value, dur=0.0, ease='io'):
        k = self.extra.setdefault(name, [(0.0, 0.0 if not isinstance(value, tuple) else value)])
        last = self._last(k, t)
        if dur > 0:
            k.append((t, last, 'hold'))
            k.append((t + dur, value, ease))
        else:
            k.append((t, last, 'hold'))
            k.append((t + 1e-4, value, 'lin'))
        return self

    def prop(self, t, name, hand=1):
        (self.props if hand == 1 else self.props2).append((t, name))
        return self

    def talk(self, t0, env, dur):
        self.talks.append((t0, env, dur))
        return self

    def gait(self, t0, t1, mode):
        self.gait_override.append((t0, t1, mode))
        return self

    # --- внутренние ---
    @staticmethod
    def _last(keys, t):
        tr = Track(keys)
        return tr(t)

    def _last_pose(self, t):
        return Track(self.pk)(t)

    @staticmethod
    def _step(keys, t):
        v = keys[0][1]
        for tk, val in sorted(keys, key=lambda k: k[0]):
            if tk <= t:
                v = val
        return v

    def x_at(self, t):
        return Track(self.xk)(t)

    def state(self, t, **over):
        xt, yt = Track(self.xk), Track(self.yk)
        x, y = xt(t), yt(t)
        over = dict(over)
        if 'x' in over:
            x = over.pop('x')
        if 'y' in over:
            y = over.pop('y')
        nog = over.pop('nogesture', False)
        dt = 1 / 60.0
        vx = (xt(t + dt) - xt(t - dt)) / (2 * dt)
        f = Track(self.fk)(t)
        ps = dict(Track(self.pk)(t))
        # походка
        speed = abs(vx)
        mode = self.gait_mode
        for (a, b, m) in self.gait_override:
            if a <= t <= b:
                mode = m
        stride = 0.95 if mode == 'run' else 0.62
        if speed > 0.02:
            # фаза по пройденному пути — без проскальзывания ступней
            dist = self._dist(t)
            g = gait(dist / stride, mode)
            w = clamp(speed / (0.35 if mode != 'run' else 0.8))
            w = smooth(w)
            ps = mix(ps, g, w)
        # дыхание и микродвижения
        br = math.sin(t * 1.6 + self.seed) * 1.2
        ps['lean'] = ps.get('lean', 0) + br * 0.4
        ps['head'] = ps.get('head', 0) + fbm(t * 0.35, int(self.seed)) * 2.5
        ps['ls'] = ps.get('ls', 0) - br * 0.8
        ps['rs'] = ps.get('rs', 0) + br * 0.8
        # речь
        a = 0.0
        for (t0, env, dur) in self.talks:
            if t0 - 0.05 <= t <= t0 + dur + 0.05:
                a = max(a, env(t - t0))
        if a > 0:
            ps['head'] += math.sin(t * 7.0 + self.seed) * 2.5 * a
            if not nog:
                ps['rs'] = ps.get('rs', 0) + (fbm(t * 0.9, int(self.seed) + 3) * 14) * a
                ps['re'] = ps.get('re', 0) + (fbm(t * 1.1, int(self.seed) + 9) * 18) * a
        eyes = self._step(self.ek, t)
        mouth = self._step(self.mk, t)
        # моргание
        period = 3.1 + (self.seed % 1.7)
        ph = (t + self.seed) % period
        blink = ph < 0.11
        kw = dict(self.kw)
        for name, keys in self.extra.items():
            kw[name] = Track(keys)(t)
        kw.update(over)
        Lk = Look(self.who, x=x, y=y, face=f, ps=ps, eyes=eyes, mouth=mouth, talk=a, t=t, vx=vx,
                  prop=self._step(self.props, t), prop2=self._step(self.props2, t), **kw)
        Lk.blink = blink
        return Lk

    def _dist(self, t):
        # длина пройденного по x пути до t: кумулятивная таблица с шагом 1/240 с
        if getattr(self, '_dtab', None) is None:
            xt = Track(self.xk)
            tmax = max(k[0] for k in self.xk) + 2.0
            n = int(tmax * 240) + 2
            xs = np.array([xt(i / 240.0) for i in range(n)])
            self._dtab = np.concatenate([[0.0], np.cumsum(np.abs(np.diff(xs)))])
        i = t * 240.0
        if i <= 0:
            return 0.0
        if i >= len(self._dtab) - 1:
            return float(self._dtab[-1])
        k = int(i); f = i - k
        return float(self._dtab[k] * (1 - f) + self._dtab[k + 1] * f)


def hand_world(actor, t, hand='r'):
    """Мировые координаты кисти персонажа в момент t (для крупных планов руки)."""
    L = actor.state(t)
    sp = SPECS.get(actor.who, SPECS['EXTRA'])
    sc = sp.get('scale', 1.0) * L.scale
    pts = skeleton(L.ps)
    g = ground_offset(pts)
    hip_y = -L.ps['sit'] if L.ps.get('sit', 0) > 0 else -g
    hip_y -= L.ps.get('ly', 0.0)
    wx, wy = pts[hand + 'wr']
    return (L.x + L.face * sc * wx, L.y + sc * (wy + hip_y))
