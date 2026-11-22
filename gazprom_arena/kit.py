"""Detailed play-scale kit of the Krestovsky stadium (Gazprom Arena), St. Petersburg.

Built for tabletop football with 4 cm building-brick minifigures: the roof lifts off,
the two halves of the sliding roof run on their tracks, the pitch is a separate plate,
and play goals, a ball and stud-compatible player bases are included.

The geometry is a reconstruction from public figures (roof diameter ~286 m, roof
height 79 m, pylons 110 m, two tiers of stands with a ring of 104 boxes between them,
eight inclined pylons with stay cables, 120 x 80 m sliding pitch). It is not built
from construction drawings.

Modelling is in metres; parts are exported in millimetres at 1:SCALE (default 600).
Every part is a closed manifold sized for a 220 x 220 mm bed and prints without supports.

Usage:  python3 kit.py [--scale 600] [--out out_kit]
"""

import argparse
import base64
import json
import math
import os

import numpy as np
import trimesh
from manifold3d import CrossSection, FillRule, JoinType, Manifold, OpType

from generate import box, hull, srgb_to_linear_u8, union

ap = argparse.ArgumentParser()
ap.add_argument("--scale", type=float, default=600.0)
ap.add_argument("--out", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "out_kit"))
ARGS = ap.parse_args()
SCALE = ARGS.scale
S_MM = 1000.0 / SCALE                 # metres -> millimetres


def mm(v):
    """A size in millimetres on the printed model, expressed in metres of the real stadium."""
    return v / S_MM


SEG = 192                             # segments for revolved shapes
CSEG = 96                             # segments per full turn for bowl outline corners

# ------------------------------------------------------------------ layout (metres)
PITCH_HX, PITCH_HY, PITCH_RC = 60.0, 40.0, 6.0       # sliding pitch platform 120 x 80 m
CORE = (2 * (PITCH_HX - PITCH_RC), 2 * (PITCH_HY - PITCH_RC))
Z_FIELD = 3.0                                        # grass level
WALL_TOP = 4.5                                       # pitch-side wall / front walkway
LOW_ROWS, LOW_D, LOW_H, LOW_D0 = 26, 0.85, 0.42, 1.0  # lower tier rows
D_CROSS = LOW_D0 + LOW_ROWS * LOW_D                  # back of lower tier (23.1)
Z_CROSS = WALL_TOP + LOW_ROWS * LOW_H                # cross aisle level (15.42)
D_BOXES = 26.0                                       # face of the skybox ring
Z_BOXES = Z_CROSS + 7.0                              # two storeys of boxes
UP_ROWS, UP_D, UP_H, UP_D0, UP_RISE0 = 32, 0.8, 0.55, 27.0, 0.6
D_BACK = UP_D0 + UP_ROWS * UP_D                      # back of upper tier (52.6)
Z_SEAT = 46.0                                        # top of bowl = underside of roof

PODIUM_R, PODIUM_H = 146.0, 8.0
FAC_R0, FAC_R1 = 121.0, 138.5                        # facade leans outward
RIM_R, RIM_Z, DOME_C = 141.5, 49.5, 72.0             # fixed roof
ARC_R, ARC_Z0 = 445.0, 76.0                          # carriageway track arc
OPEN_HX, OPEN_HY = 60.0, 44.0                        # roof opening (= pitch platform)
RAIL_Y0, RAIL_Y1, RAIL_X = 44.0, 50.0, 126.0
PANEL_Y, PANEL_T, PANEL_RIB = 52.0, 2.4, 0.8
PANEL_X0, PANEL_X1 = 0.25, 61.0                      # closed position of the +x panel
PANEL_SHIFT = 60.75                                  # travel to the open position

PYL_R0, PYL_TAN = 120.0, math.tan(math.radians(13.0))
PYL_ZB, PYL_ZT, PYL_TIP = 34.0, 104.0, 110.0
PYLON_ANGLES = [45.0 * k for k in range(8)]
SECTOR_START = [-22.5 + 45.0 * k for k in range(8)]   # sector k is centred on pylon k

CLEAR = mm(0.25)                                     # fit clearance
PIN_R = mm(1.0)                                      # 2.0 mm holes for 1.75 mm filament pins
CABLE_R = mm(1.0)


# ------------------------------------------------------------------ helpers
def poly(pts):
    """Polygon from points in any winding order."""
    return CrossSection([pts], FillRule.NonZero)


def prism(cs, z0, z1):
    return cs.extrude(z1 - z0).translate((0, 0, z0))


def revolve(pts, seg=SEG):
    return poly(pts).revolve(circular_segments=seg)


def outline(d):
    """Bowl outline offset d metres from the pitch platform edge."""
    return CrossSection.square(CORE, center=True).offset(
        PITCH_RC + d, JoinType.Round, circular_segments=CSEG)


def dome_z(r):
    t = np.clip(np.asarray(r, float) / RIM_R, 0, 1)
    return RIM_Z + (DOME_C - RIM_Z) * (1 - t ** 2)


def arc_z(x):
    return ARC_Z0 - (ARC_R - np.sqrt(ARC_R ** 2 - np.asarray(x, float) ** 2))


def rod(p0, p1, radius, n=16):
    p0, p1 = np.asarray(p0, float), np.asarray(p1, float)
    d = (p1 - p0) / np.linalg.norm(p1 - p0)
    a = np.cross(d, [0, 0, 1.0])
    if np.linalg.norm(a) < 1e-6:
        a = np.array([1.0, 0, 0])
    a /= np.linalg.norm(a)
    b = np.cross(d, a)
    ring = [radius * (math.cos(t) * a + math.sin(t) * b)
            for t in np.linspace(0, 2 * math.pi, n, endpoint=False)]
    return hull([p0 + v for v in ring] + [p1 + v for v in ring])


def cunion(items):
    return CrossSection.batch_boolean(list(items), OpType.Add)


def wedge(a0, a1, r=400.0):
    ts = np.radians(np.linspace(a0, a1, 24))
    pts = [(0.0, 0.0)] + [(r * math.cos(t), r * math.sin(t)) for t in ts]
    return prism(poly(pts), -60, 260)


def radial_box(r0, r1, half_w, z0, z1, ang):
    return box(r0, r1, -half_w, half_w, z0, z1).rotate((0, 0, ang))


def drop_slivers(m, min_volume=0.5):
    comps = [c for c in m.decompose() if c.volume() >= min_volume]
    return Manifold.compose(comps) if len(comps) != 1 else comps[0]


# strips perpendicular to the bowl outline, for aisles and vomitories
def strip_x(x0, sy, w):
    cs = CrossSection.square((w, 220)).translate((x0 - w / 2, 0))
    return cs if sy > 0 else cs.mirror((0, 1))


def strip_y(y0, sx, w):
    cs = CrossSection.square((220, w)).translate((0, y0 - w / 2))
    return cs if sx > 0 else cs.mirror((1, 0))


def strip_corner(sx, sy, ang, w):
    cs = CrossSection.square((220, w)).translate((0, -w / 2)).rotate(ang).translate(
        (CORE[0] / 2, CORE[1] / 2))
    if sx < 0:
        cs = cs.mirror((1, 0))
    if sy < 0:
        cs = cs.mirror((0, 1))
    return cs


def perimeter_strips(xs, ys, corner_angles, w):
    out = []
    for s in (1, -1):
        out += [strip_x(x, s, w) for x in xs]
        out += [strip_y(y, s, w) for y in ys]
    for sx in (1, -1):
        for sy in (1, -1):
            out += [strip_corner(sx, sy, a, w) for a in corner_angles]
    return cunion(out)


# ------------------------------------------------------------------ bowl
def stands():
    """Two-tier seating bowl: rows, aisles, vomitories, skybox ring, scoreboards."""
    back = outline(D_BACK + 0.6)
    steps = []

    def step(d0, z):
        steps.append(prism(back - outline(d0), 0, z))

    step(0.0, WALL_TOP)
    for k in range(LOW_ROWS):
        step(LOW_D0 + k * LOW_D, WALL_TOP + (k + 1) * LOW_H)
    step(D_BOXES, Z_BOXES)
    for k in range(UP_ROWS):
        step(UP_D0 + k * UP_D, Z_BOXES + UP_RISE0 + (k + 1) * UP_H)
    s = union(steps)

    # aisles: treads lowered by 0.3 m along strips square to the outline
    skin = s - s.translate((0, 0, -0.3))
    low = perimeter_strips([-45, -30, -15, 0, 15, 30, 45], [-24, -8, 8, 24],
                           [22.5, 45, 67.5], 1.4) ^ (outline(D_CROSS - 0.05) - outline(LOW_D0))
    up = perimeter_strips([-48, -36, -24, -12, 0, 12, 24, 36, 48], [-27, -13.5, 0, 13.5, 27],
                          [18, 36, 54, 72], 1.3) ^ (outline(D_BACK) - outline(UP_D0 + 0.4))
    s = s - (skin ^ prism(low + up, 0, 60))

    # vomitories (tunnel mouths) in both tiers
    vom_low = perimeter_strips([-37.5, -7.5, 7.5, 37.5], [-16, 16], [], 4.0) ^ (outline(15) - outline(10))
    vom_up = perimeter_strips([-42, -18, 18, 42], [-20, 20], [45], 4.0) ^ (outline(41) - outline(36))
    s = s - prism(vom_low, WALL_TOP + 10 * LOW_H - 1.5, 60)
    s = s - prism(vom_up, Z_BOXES + UP_RISE0 + 11 * UP_H - 1.5, 60)

    # skybox ring: two storeys of recessed glazing with mullions
    mullions = cunion([CrossSection.square((220, 0.35)).translate((0, -0.175)).rotate(a)
                       for a in np.arange(0, 360, 2.5)])
    band = (outline(D_BOXES + 0.6) - outline(D_BOXES - 0.1)) - mullions
    recess = union([prism(band, Z_CROSS + 0.6, Z_CROSS + 3.2),
                    prism(band, Z_CROSS + 3.8, Z_CROSS + 6.4)])
    s = s - recess
    glass_band = (outline(D_BOXES + 0.6) - outline(D_BOXES + 0.45)) - mullions
    glass = union([prism(glass_band, Z_CROSS + 0.6, Z_CROSS + 3.2),
                   prism(glass_band, Z_CROSS + 3.8, Z_CROSS + 6.4)])

    # two big video screens above the end stands
    frames, displays = [], []
    for sx in (1, -1):
        f = box(105.5, 113.5, -15, 15, 33.0, 45.3)
        dsp = box(105.2, 105.6, -14, 14, 33.8, 44.6)
        if sx < 0:
            f, dsp = f.rotate((0, 0, 180)), dsp.rotate((0, 0, 180))
        frames.append(f)
        displays.append(dsp)
    return s, glass, union(frames), union(displays)


def building():
    """Podium, facade drum and the solid structure behind the stands."""
    podium = revolve([(0, 0), (PODIUM_R, 0), (PODIUM_R, PODIUM_H - 0.6),
                      (PODIUM_R - 0.6, PODIUM_H), (0, PODIUM_H)])
    # grand staircases cut into the podium on the four axes
    stairs_cut, stairs = [], []
    for ang in (0, 90, 180, 270):
        stairs_cut.append(radial_box(132.0, 150.0, 18.0, 0.0, PODIUM_H + 1, ang))
        for i in range(15):
            stairs.append(radial_box(131.0, 132.0 + (i + 1) * 0.875, 18.0, 0.0,
                                     PODIUM_H - (i + 1) * 0.5, ang))
    podium = (podium - union(stairs_cut)) + union(stairs)

    drum = revolve([(0, 0), (FAC_R0, 0), (FAC_R0, PODIUM_H), (FAC_R1, Z_SEAT), (0, Z_SEAT)])
    inner = revolve([(0, -1), (FAC_R0 - 1.2, -1), (FAC_R0 - 1.2, PODIUM_H),
                     (FAC_R1 - 1.2, Z_SEAT + 0.5), (0, Z_SEAT + 0.5)])

    # facade trim: ceramic base band, 96 vertical ribs, 6 floor bands
    def fr(z):
        return FAC_R0 + (FAC_R1 - FAC_R0) * (z - PODIUM_H) / (Z_SEAT - PODIUM_H)

    trim = [revolve([(FAC_R0 - 0.6, PODIUM_H - 0.2), (FAC_R0 + 1.1, PODIUM_H - 0.2),
                     (fr(11.0) + 1.1, 11.0), (fr(11.0) - 0.6, 11.0)])]
    for z in (16.0, 21.5, 27.0, 32.5, 38.0, 43.5):
        z0, z1 = z - 0.4, z + 0.4
        trim.append(revolve([(fr(z0) - 0.6, z0), (fr(z0) + 0.66, z0),
                             (fr(z1) + 0.66, z1), (fr(z1) - 0.6, z1)]))
    a = np.array([fr(11.0), 11.0])
    b = np.array([fr(45.6), 45.6])
    t = (b - a) / np.linalg.norm(b - a)
    nrm = np.array([t[1], -t[0]])
    for k in range(96):
        th = 2 * math.pi * (k + 0.5) / 96
        ex = np.array([math.cos(th), math.sin(th), 0.0])
        ey = np.array([-math.sin(th), math.cos(th), 0.0])
        pts = []
        for p in (a, b):
            for off in (-0.6, 1.0):
                rz = p + off * nrm
                for side in (-0.6, 0.6):
                    pts.append(rz[0] * ex + side * ey + np.array([0, 0, rz[1]]))
        trim.append(hull(pts))
    trim = union(trim)

    # entrance portals and the gate the pitch rolls out through (south end)
    portals = [radial_box(118.0, 127.0, 24.0, PODIUM_H - 0.01, 15.0, 180.0)]
    for k in range(16):
        ang = 11.25 + 22.5 * k
        if abs(ang - 180) < 15:
            continue
        portals.append(radial_box(119.5, 127.0, 3.5, PODIUM_H - 0.01, 13.0, ang))
    portals = union(portals)

    bowl_hole = prism(outline(D_BACK), -1, Z_SEAT + 1)
    whole = (podium + drum) - bowl_hole - portals
    trim = trim - portals
    parts = {
        "podium": whole - drum,
        "facade": (whole ^ drum) - inner,
        "concrete": whole ^ inner,
        "trim": trim,
    }
    return whole, parts


# ------------------------------------------------------------------ pylons and cables
def pylon_ab(z):
    t = (z - 8.0) / 96.0
    return 5.5 + (1.9 - 5.5) * t, 4.0 + (1.6 - 4.0) * t


def pylon_frame(k):
    phi = math.radians(PYLON_ANGLES[k])
    er = np.array([math.cos(phi), math.sin(phi), 0.0])
    et = np.array([-math.sin(phi), math.cos(phi), 0.0])
    return er, et


def pylon_axis(k, z):
    er, _ = pylon_frame(k)
    return (PYL_R0 + (z - 8.0) * PYL_TAN) * er + np.array([0, 0, z])


def pylon_solid(k, clear=0.0, z0=PYL_ZB, z1=PYL_ZT, tip=True):
    er, et = pylon_frame(k)
    pts = []
    for z in (z0, z1):
        a, b = pylon_ab(z)
        c = pylon_axis(k, z)
        for sr in (-(a + clear), a + clear):
            for st in (-(b + clear), b + clear):
                pts.append(c + sr * er + st * et)
    if tip:
        pts.append(pylon_axis(k, PYL_TIP) + np.array([0, 0, clear]))
    return hull(pts)


def pylon_outer_normal(k):
    er, _ = pylon_frame(k)
    slope = PYL_TAN + (1.9 - 5.5) / 96.0
    n = er - slope * np.array([0, 0, 1.0])
    return n / np.linalg.norm(n)


CABLE_Z = (97.0, 92.0)


def cable_anchors(k):
    """Two roof anchor points for pylon k: track ends, track sides or the fixed roof."""
    ang = PYLON_ANGLES[k]
    if ang in (0.0, 180.0):
        sx = 1 if ang == 0 else -1
        return [np.array([sx * 124.0, sy * 47.0, float(arc_z(124.0)) + 0.8]) for sy in (1, -1)]
    if ang in (90.0, 270.0):
        sy = 1 if ang == 90 else -1
        return [np.array([sx * 35.0, sy * RAIL_Y1, float(arc_z(35.0)) - 1.6]) for sx in (1, -1)]
    out = []
    for d in (-12.0, 12.0):
        p = math.radians(ang + d)
        out.append(np.array([100 * math.cos(p), 100 * math.sin(p), float(dome_z(100.0))]))
    return out


def cables():
    """(pylon point, anchor) pairs."""
    res = []
    for k in range(8):
        for z, anc in zip(CABLE_Z, cable_anchors(k)):
            res.append((pylon_axis(k, z), anc))
    return res


def pylon_print(k):
    p = pylon_solid(k)
    n = pylon_outer_normal(k)
    holes = [rod(pylon_axis(k, z) - 14 * n, pylon_axis(k, z) + 14 * n, CABLE_R) for z in CABLE_Z]
    return p - union(holes)


# ------------------------------------------------------------------ roof
def roof():
    rs = np.linspace(RIM_R, 0.0, 64)
    prof = [(0.0, Z_SEAT), (FAC_R1, Z_SEAT), (RIM_R, RIM_Z - 0.4), (RIM_R, RIM_Z)]
    prof += [(float(r), float(dome_z(r))) for r in rs[1:]]
    fixed = revolve(prof)
    opening = CrossSection.square((2 * OPEN_HX - 8, 2 * OPEN_HY - 8), center=True).offset(
        4.0, JoinType.Round, circular_segments=48)
    fixed = fixed - prism(opening, Z_SEAT - 1, 120)

    # panel seams on top (engraved) and truss lines on the underside
    skin = fixed - fixed.translate((0, 0, -0.35))
    seams = cunion([CrossSection.square((80, 0.5)).translate((62, -0.25)).rotate(a)
                    for a in np.arange(3.75, 360, 7.5)])
    rings = cunion([CrossSection.circle(r + 0.25, 256) - CrossSection.circle(r - 0.25, 256)
                    for r in (92.0, 116.0)])
    fixed = fixed - (skin ^ prism(seams + rings, 0, 120))
    under = cunion([CrossSection.square((70, 0.8)).translate((64, -0.4)).rotate(a)
                    for a in np.arange(0, 360, 5.0)])
    fixed = fixed - prism(under, Z_SEAT - 1, Z_SEAT + 0.5)

    # carriageway trusses (tracks of the sliding roof) with triangular openings
    xs = np.linspace(-RAIL_X, RAIL_X, 121)
    sect = [(float(x), float(arc_z(x))) for x in xs] + [(RAIL_X, 40.0), (-RAIL_X, 40.0)]
    sect = poly(sect)
    ridge = [(float(x), float(arc_z(x)) + 0.8) for x in xs] + [(RAIL_X, 60.0), (-RAIL_X, 60.0)]
    ridge_cs = poly(ridge) ^ poly([(float(x), float(arc_z(x)) - 0.5) for x in xs]
                                 + [(RAIL_X, 100.0), (-RAIL_X, 100.0)])
    rails = []
    clip = Manifold.cylinder(80, RIM_R - 2.0, circular_segments=SEG).translate((0, 0, 40))
    for sy in (1, -1):
        def along_y(cs, y0, y1):
            m = cs.extrude(y1 - y0).rotate((90, 0, 0))     # extrusion axis -> -y
            return m.translate((0, y1, 0))

        body = along_y(sect, RAIL_Y0, RAIL_Y1)
        top = along_y(ridge_cs, 46.4, 47.6)
        tris = []
        for i, x in enumerate(np.arange(-116.0, 116.1, 8.0)):
            base = float(dome_z(math.hypot(x, RAIL_Y0))) + 1.2
            top_z = float(arc_z(x)) - 1.2
            if top_z - base < 3.0:
                continue
            if i % 2 == 0:
                tri = [(x - 3.4, base), (x + 3.4, base), (x, top_z)]
            else:
                tri = [(x - 3.4, top_z), (x + 3.4, top_z), (x, base)]
            tris.append(poly(tri))
        r = body - along_y(cunion(tris), RAIL_Y0 - 1, RAIL_Y1 + 1) if tris else body
        r = r + top
        if sy < 0:
            r = r.mirror((0, 1, 0))
        rails.append(r ^ clip)
    rails = union(rails)
    return fixed, rails


def roof_holes():
    holes = [pylon_solid(k, clear=CLEAR, z0=30.0, z1=PYL_ZT) for k in range(8)]
    for p, anc in cables():
        u = (anc - p) / np.linalg.norm(anc - p)
        holes.append(rod(anc - 1.5 * u, anc + mm(9.0) * u, CABLE_R))
    return union(holes)


def panel(x0, x1):
    """One half of the sliding roof resting on the track arcs."""
    xs = np.linspace(x0, x1, 40)
    lo = [(float(x), float(arc_z(x))) for x in xs]
    hi = [(float(x), float(arc_z(x)) + PANEL_T) for x in xs[::-1]]
    slab_cs = poly(lo + hi)

    def along_y(cs, y0, y1):
        return cs.extrude(y1 - y0).rotate((90, 0, 0)).translate((0, y1, 0))

    slab = along_y(slab_cs, -PANEL_Y, PANEL_Y)
    # grooves that ride on the track ridges
    g = CLEAR
    groove_cs = poly([(float(x), float(arc_z(x)) - 1.0) for x in xs]
                     + [(float(x), float(arc_z(x)) + 0.8 + g) for x in xs[::-1]])
    for sy in (1, -1):
        slab = slab - along_y(groove_cs, sy * 47.0 - 0.6 - g, sy * 47.0 + 0.6 + g)
    # transverse ribs and edge beams on top
    rib_top = poly([(float(x), float(arc_z(x)) + PANEL_T - 0.2) for x in xs]
                   + [(float(x), float(arc_z(x)) + PANEL_T + PANEL_RIB) for x in xs[::-1]])
    ribs = []
    n = 9
    for i in range(n + 1):
        xc = x0 + (x1 - x0) * i / n
        xc = min(max(xc, x0 + 0.6), x1 - 0.6)
        ribs.append(along_y(rib_top ^ CrossSection.square((1.2, 200)).translate((xc - 0.6, 0)),
                            -PANEL_Y, PANEL_Y))
    for sy in (1, -1):
        ribs.append(along_y(rib_top, sy * PANEL_Y - 1.2 if sy > 0 else -PANEL_Y,
                            sy * PANEL_Y if sy > 0 else -PANEL_Y + 1.2))
    return slab + union(ribs)


# ------------------------------------------------------------------ pitch
def pitch():
    plate = prism(outline(-CLEAR), 0, Z_FIELD)
    lw = max(mm(0.9), 0.3)
    L, W = 52.5, 34.0

    def frame(x0, x1, y0, y1):
        outer = CrossSection.square((x1 - x0, y1 - y0)).translate((x0, y0))
        inner = CrossSection.square((x1 - x0 - 2 * lw, y1 - y0 - 2 * lw)).translate((x0 + lw, y0 + lw))
        return outer - inner

    def annulus(r, cx=0.0, cy=0.0):
        return (CrossSection.circle(r + lw / 2, 128) - CrossSection.circle(r - lw / 2, 128)).translate((cx, cy))

    lines = [frame(-L, L, -W, W),
             CrossSection.square((lw, 2 * W)).translate((-lw / 2, -W)),
             annulus(9.15), CrossSection.circle(0.5, 32)]
    for sx in (1, -1):
        pa = frame(L - 16.5, L + lw, -20.16, 20.16)
        ga = frame(L - 5.5, L + lw, -9.16, 9.16)
        spot = CrossSection.circle(0.45, 32).translate((L - 11.0, 0))
        arc = annulus(9.15, L - 11.0, 0) ^ CrossSection.square((40, 60)).translate((L - 16.5 - 40, -30))
        corners = [annulus(1.0, L, sy * W) ^ CrossSection.square((3, 3)).translate(
            (L - 3, (W - 3) if sy > 0 else -W)) for sy in (1, -1)]
        group = cunion([pa, ga, spot, arc] + corners)
        lines.append(group if sx > 0 else group.mirror((1, 0)))
    lines = prism(cunion(lines), Z_FIELD - 0.05, Z_FIELD + 0.3)

    dug = []
    for sx in (1, -1):
        cx = sx * 13.0
        d = box(cx - 7, cx + 7, -39.2, -36.4, Z_FIELD - 0.05, Z_FIELD + 2.4)
        d = d - box(cx - 6.4, cx + 6.4, -37.4, -36.0, Z_FIELD + 0.5, Z_FIELD + 2.0)
        dug.append(d)
    return plate, lines, union(dug)


# ------------------------------------------------------------------ play items (built in mm)
def play_goal():
    W, H, D, P = 48.0, 28.0, 12.0, 2.4
    yo = W / 2 + P

    def net(plate, axis_holes):
        holes = []
        lo, hi = plate.bounding_box()[:3], plate.bounding_box()[3:]
        a0, a1 = axis_holes
        for u in np.arange(lo[a0] + 1.2, hi[a0] - 3.0, 4.0):
            for v in np.arange(lo[a1] + 1.2, hi[a1] - 3.0, 4.0):
                c = [0, 0, 0]
                sz = [0, 0, 0]
                c[a0], c[a1] = u, v
                sz[a0], sz[a1] = 3.0, 3.0
                third = 3 - a0 - a1
                c[third] = lo[third] - 1
                sz[third] = hi[third] - lo[third] + 2
                holes.append(Manifold.cube(tuple(sz)).translate(tuple(c)))
        return plate - union(holes)

    parts = [box(0, P, -yo, -W / 2, 0, H + P), box(0, P, W / 2, yo, 0, H + P),
             box(0, P, -yo, yo, H, H + P),
             box(D - P, D, -yo, yo, 0, 2.0)]
    for s in (1, -1):
        parts.append(box(0, D, *sorted((s * W / 2, s * yo)), 0, 2.0))
    parts.append(net(box(D - 1.0, D, -yo, yo, 0, H + P), (1, 2)))
    parts.append(net(box(0, D, -yo, yo, H + P - 0.8, H + P), (0, 1)))
    for s in (1, -1):
        y0, y1 = sorted((s * (W / 2 + P - 1.0), s * yo))
        parts.append(net(box(0, D, y0, y1, 0, H + P), (0, 2)))
    return union(parts)


def player_base():
    disc = Manifold.cylinder(2.2, 8.4, 9.0, circular_segments=64)
    bottom = Manifold.cylinder(0.6, 8.4, 9.0, circular_segments=64)  # chamfered lower edge
    body = bottom + Manifold.cylinder(1.6, 9.0, 9.0, circular_segments=64).translate((0, 0, 0.6))
    studs = union([Manifold.cylinder(1.7, 2.425, 2.425, circular_segments=48).translate((sx * 4.0, 0, 2.2))
                   for sx in (1, -1)])
    return body + studs


def ball():
    return Manifold.sphere(3.5, 64).translate((0, 0, 3.5))


# ------------------------------------------------------------------ export helpers
def to_tm(m, scale=1.0):
    mesh = m.to_mesh()
    v = np.asarray(mesh.vert_properties)[:, :3] * scale
    return trimesh.Trimesh(vertices=v, faces=np.asarray(mesh.tri_verts), process=False)


def bed_fit(tm):
    """Smallest footprint over rotations about Z (mm)."""
    pts = tm.vertices[:, :2]
    best = None
    for a in np.radians(np.arange(0, 90, 1.0)):
        c, s = math.cos(a), math.sin(a)
        rp = pts @ np.array([[c, -s], [s, c]])
        ext = rp.max(0) - rp.min(0)
        if best is None or max(ext) < max(best[1]):
            best = (a, ext)
    a, ext = best
    rot = trimesh.transformations.rotation_matrix(a, [0, 0, 1])
    return rot, ext


def place_on_bed(tm, rotate=True):
    if rotate:
        rot, _ = bed_fit(tm)
        tm.apply_transform(rot)
    lo, hi = tm.bounds
    tm.apply_translation([-(lo[0] + hi[0]) / 2, -(lo[1] + hi[1]) / 2, -lo[2]])
    return tm


COLORS = {
    "podium": (178, 174, 168), "facade": (98, 136, 170), "concrete": (196, 198, 202),
    "trim": (232, 236, 240), "stands": (36, 82, 150), "glass": (40, 58, 78),
    "screen_frame": (60, 64, 70), "screen": (24, 30, 38), "roof": (224, 229, 235),
    "rails": (150, 158, 168), "panel": (206, 224, 238), "pylon": (243, 244, 246),
    "cable": (80, 86, 94), "grass": (58, 138, 66), "lines": (246, 246, 242),
    "dugouts": (52, 92, 150), "goal": (245, 245, 245), "ball": (250, 250, 250),
    "base": (220, 60, 50),
}


def main():
    out = ARGS.out
    os.makedirs(out, exist_ok=True)
    report = []
    scene = trimesh.Scene()
    yup = trimesh.transformations.rotation_matrix(-math.pi / 2, [1, 0, 0])

    def add_preview(name, key, m, scale=S_MM, transform=None):
        if m.is_empty():
            return
        t = to_tm(m, scale)
        if transform is not None:
            t.apply_transform(transform)
        t.visual = trimesh.visual.TextureVisuals(material=trimesh.visual.material.PBRMaterial(
            name=key, baseColorFactor=srgb_to_linear_u8(COLORS[key]) + [255],
            metallicFactor=0.1, roughnessFactor=0.6))
        t.apply_transform(yup)
        scene.add_geometry(t, node_name=f"{name}__{key}", geom_name=f"{name}__{key}")

    def export(fname, m, count, scale=S_MM, rotate=True, pre=None):
        t = to_tm(m, scale)
        if pre is not None:
            t.apply_transform(pre)
        t = place_on_bed(t, rotate)
        t.export(os.path.join(out, fname))
        ext = t.bounds[1] - t.bounds[0]
        report.append({"file": fname, "count": count, "tris": int(len(t.faces)),
                       "watertight": bool(t.is_watertight), "volume_cm3": round(t.volume / 1000, 1),
                       "size_mm": [round(float(e), 1) for e in ext]})
        print(f"{fname:28s} x{count:<2d} {ext[0]:6.1f} x {ext[1]:6.1f} x {ext[2]:5.1f} mm "
              f"vol {t.volume / 1000:7.1f} cm3 watertight={t.is_watertight} tris={len(t.faces)}")

    # --- bowl sectors
    stands_s, glass, frames, displays = stands()
    whole, bparts = building()
    bparts["stands"] = stands_s
    bparts["screen_frame"] = frames
    bparts["screen"] = displays
    print_bowl = union([whole, stands_s, bparts["trim"], frames, displays])
    sockets = union([pylon_solid(k, clear=CLEAR, z0=PYL_ZB, z1=Z_SEAT + 2, tip=False) for k in range(8)])
    pins = []
    for a in SECTOR_START:
        er = np.array([math.cos(math.radians(a)), math.sin(math.radians(a)), 0])
        et = np.array([-er[1], er[0], 0])
        for r, z in ((70.0, 2.0), (124.0, 26.0), (128.0, 4.0)):
            c = r * er + np.array([0, 0, z])
            pins.append(rod(c - mm(7) * et, c + mm(7) * et, PIN_R))
    pins = union(pins)
    print_bowl = print_bowl - sockets - pins

    fixed, rails = roof()
    roof_pins = []
    for a in SECTOR_START:
        er = np.array([math.cos(math.radians(a)), math.sin(math.radians(a)), 0])
        et = np.array([-er[1], er[0], 0])
        for r, z in ((135.0, Z_SEAT + mm(2.0)), (100.0, Z_SEAT + 4.0)):
            c = r * er + np.array([0, 0, z])
            roof_pins.append(rod(c - mm(7) * et, c + mm(7) * et, PIN_R))
    print_roof = (fixed + rails) - roof_holes() - union(roof_pins)

    for k, a0 in enumerate(SECTOR_START):
        w = wedge(a0, a0 + 45.0)
        export(f"bowl_{k + 1}.stl", drop_slivers(print_bowl ^ w), 1)
        for key, part in bparts.items():
            add_preview(f"bowl_{k}", key, part ^ w)
        add_preview(f"bowl_{k}", "glass", glass ^ w)
        rw = drop_slivers(print_roof ^ w)
        export(f"roof_{k + 1}.stl", rw, 1, pre=trimesh.transformations.translation_matrix(
            [0, 0, -Z_SEAT * S_MM]))
        add_preview(f"roof_{k}", "roof", fixed ^ w)
        add_preview(f"roof_{k}", "rails", rails ^ w)

    # --- pylons
    for k in range(8):
        add_preview(f"pylon_{k}", "pylon", pylon_solid(k))
    p0 = pylon_print(0)
    n0 = pylon_outer_normal(0)
    lay = trimesh.geometry.align_vectors(n0, [0, 0, -1])
    export("pylon.stl", p0, 8, pre=lay)
    for i, (p, anc) in enumerate(cables()):
        add_preview(f"cable_{i}", "cable", rod(p, anc, 0.35, n=8))

    # --- sliding roof halves
    pan = panel(PANEL_X0, PANEL_X1)
    add_preview("panel_0", "panel", pan)
    add_preview("panel_1", "panel", pan.rotate((0, 0, 180)))
    pan_open = panel(PANEL_X0 + PANEL_SHIFT, PANEL_X1 + PANEL_SHIFT)
    add_preview("panelopen_0", "panel", pan_open)
    add_preview("panelopen_1", "panel", pan_open.rotate((0, 0, 180)))
    on_edge = trimesh.transformations.rotation_matrix(math.pi / 2, [1, 0, 0])
    export("roof_panel.stl", pan, 2, pre=on_edge, rotate=False)

    # --- pitch
    plate, lines, dug = pitch()
    export("pitch.stl", union([plate, lines, dug]), 1)
    add_preview("pitch", "grass", plate)
    add_preview("pitch", "lines", lines)
    add_preview("pitch", "dugouts", dug)

    # --- play items (already in mm)
    g = play_goal()
    export("goal_play.stl", g, 2, scale=1.0, rotate=False)
    pb = player_base()
    plate11 = union([pb.translate(((i % 4) * 21.0, (i // 4) * 21.0, 0)) for i in range(11)])
    export("player_bases_x11.stl", plate11, 2, scale=1.0, rotate=False)
    export("ball.stl", ball(), 1, scale=1.0, rotate=False)
    gl = 52.5 * S_MM
    zf = Z_FIELD * S_MM + 0.5
    add_preview("play_goal_0", "goal", g, scale=1.0,
                transform=trimesh.transformations.translation_matrix([gl, 0, zf]))
    add_preview("play_goal_1", "goal", g.rotate((0, 0, 180)), scale=1.0,
                transform=trimesh.transformations.translation_matrix([-gl, 0, zf]))
    add_preview("play_ball", "ball", ball(), scale=1.0,
                transform=trimesh.transformations.translation_matrix([22.0, 6.0, zf]))
    for i, (x, y) in enumerate([(-30, 12), (25, -14), (-12, -22), (40, 10)]):
        add_preview(f"play_base_{i}", "base", pb, scale=1.0,
                    transform=trimesh.transformations.translation_matrix([x, y, zf]))

    glb = os.path.join(out, "kit_preview.glb")
    scene.export(glb)
    with open(glb, "rb") as fh, open(os.path.join(out, "kit_preview.json"), "w") as fo:
        json.dump({"format": "glb", "data": base64.b64encode(fh.read()).decode()}, fo)
    with open(os.path.join(out, "kit_report.json"), "w") as fo:
        json.dump({"scale": SCALE, "parts": report}, fo, ensure_ascii=False, indent=1)
    total = sum(p["volume_cm3"] * p["count"] for p in report)
    print(f"preview {os.path.getsize(glb) / 1e6:.1f} MB, total solid volume {total:.0f} cm3")


if __name__ == "__main__":
    main()
