"""Approximate printable scale model of the Krestovsky stadium (Gazprom Arena), St. Petersburg.

The geometry is a simplified reconstruction from public figures (roof diameter ~286 m,
height ~75 m without pylons, 8 steel pylons with stay cables, sliding roof panels,
105 x 68 m pitch). It is not built from architectural drawings, so it is a
recognisable souvenir model rather than a survey-accurate copy.

All modelling is done in metres and the result is scaled to millimetres on export.

Usage:
    python3 generate.py [--scale 2000] [--out out]

Writes:
    out/gazprom_arena_closed.stl   roof closed, one piece, prints without supports
    out/gazprom_arena_open.stl     roof open (pitch and lower stands visible), one piece
    out/preview.glb                coloured parts for the web preview (both variants)
"""

import argparse
import math
import os

import numpy as np
import trimesh
from manifold3d import CrossSection, JoinType, Manifold, OpType

SEG = 256  # circular segments for the big revolved shapes

# ---------------------------------------------------------------- dimensions (m)
PODIUM_LOW_R, PODIUM_LOW_H = 176.0, 3.0      # lower terrace of the hill
PODIUM_UP_R, PODIUM_UP_H = 160.0, 8.0        # upper terrace / concourse level
FACADE_R0 = 121.0                            # facade radius at concourse level
FACADE_R1, FACADE_Z1 = 137.5, 44.0           # facade top (leans outward, "saucer")
RIM_R, RIM_Z = 141.5, 48.0                   # roof rim (286 m class diameter incl. trim)
DOME_TOP = 66.0                              # roof crown of the fixed roof
BAND_LIFT = 3.5                              # sliding-roof track structure above roof
BAND_X, BAND_Y = 130.0, 62.0                 # half sizes of the track band
PANEL_LIFT = 7.0                             # top of sliding panels above roof (=> ~73-75 m)
PANEL_Y = 59.0                               # half width of a sliding panel
PANEL_LEN = 77.0                             # length of each of the two panels
PYLON_R = 143.5                              # radius of pylon axis
PYLON_TOP = 104.0                            # top of pylon shaft
PYLON_TIP = 110.0                            # tip of the spire (110 m with pylons)
FIELD_Z = 9.0                                # pitch level inside the bowl (open variant)
FIELD_HX, FIELD_HY, FIELD_RC = 55.0, 37.0, 10.0   # pitch + run-off area
OPEN_D = 20.0                                # roof opening = field area offset by this


def dome_z(r):
    """Height of the fixed roof surface at radius r."""
    t = np.clip(np.asarray(r, dtype=float) / RIM_R, 0.0, 1.0)
    return RIM_Z + (DOME_TOP - RIM_Z) * (1.0 - t ** 2)


def revolve(profile):
    return CrossSection([profile]).revolve(circular_segments=SEG)


def dome_solid(lift, z_floor=40.0):
    """Solid of revolution whose top is the roof surface raised by `lift`."""
    rs = np.linspace(RIM_R, 0.0, 48)
    pts = [(0.0, z_floor), (RIM_R, z_floor)]
    pts += [(float(r), float(dome_z(r) + lift)) for r in rs]
    return revolve(pts)


def box(x0, x1, y0, y1, z0, z1):
    return Manifold.cube((x1 - x0, y1 - y0, z1 - z0)).translate((x0, y0, z0))


def rounded_rect(hx, hy, rc):
    rc = min(rc, hx - 0.01, hy - 0.01)
    core = CrossSection.square((2 * (hx - rc), 2 * (hy - rc)), center=True)
    return core.offset(rc, JoinType.Round, circular_segments=96)


def hull(points):
    return Manifold.hull_points(np.asarray(points, dtype=float))


def rod(p0, p1, radius, n=8):
    """Convex rod (octagonal prism) between two points."""
    p0, p1 = np.asarray(p0, float), np.asarray(p1, float)
    d = p1 - p0
    d /= np.linalg.norm(d)
    a = np.cross(d, [0, 0, 1.0])
    if np.linalg.norm(a) < 1e-6:
        a = np.array([1.0, 0, 0])
    a /= np.linalg.norm(a)
    b = np.cross(d, a)
    ring = [radius * (math.cos(t) * a + math.sin(t) * b)
            for t in np.linspace(0, 2 * math.pi, n, endpoint=False)]
    return hull([p0 + v for v in ring] + [p1 + v for v in ring])


def union(parts):
    parts = [p for p in parts if not p.is_empty()]
    return Manifold.batch_boolean(parts, OpType.Add)


# ---------------------------------------------------------------- parts
def podium():
    lower = revolve([(0, 0), (PODIUM_LOW_R, 0), (PODIUM_LOW_R, 1.0),
                     (PODIUM_LOW_R - 3.0, PODIUM_LOW_H), (0, PODIUM_LOW_H)])
    upper = revolve([(0, PODIUM_LOW_H - 0.5), (PODIUM_UP_R, PODIUM_LOW_H - 0.5),
                     (PODIUM_UP_R, PODIUM_UP_H - 1.0), (PODIUM_UP_R - 1.5, PODIUM_UP_H),
                     (0, PODIUM_UP_H)])
    parts = [lower, upper]
    # grand staircases on the four main axes: upper terrace -> lower terrace -> ground
    for ang in (0, 90, 180, 270):
        steps = []
        n_up = 5
        for i in range(n_up):
            z_top = PODIUM_UP_H - (i + 1) * (PODIUM_UP_H - PODIUM_LOW_H) / (n_up + 1)
            r0 = PODIUM_UP_R - 2.0
            r1 = PODIUM_UP_R + (i + 1) * 2.6
            steps.append(box(r0, r1, -22, 22, PODIUM_LOW_H - 0.5, z_top))
        for i in range(3):
            z_top = PODIUM_LOW_H - (i + 1) * PODIUM_LOW_H / 4
            steps.append(box(PODIUM_LOW_R - 4.0, PODIUM_LOW_R + (i + 1) * 2.6,
                             -26, 26, 0, z_top))
        parts.append(union(steps).rotate((0, 0, ang)))
    return union(parts)


def body():
    """Facade drum + fixed roof as one solid of revolution."""
    rs = np.linspace(RIM_R, 0.0, 48)
    pts = [(0.0, PODIUM_UP_H - 0.5), (FACADE_R0, PODIUM_UP_H - 0.5),
           (FACADE_R0, PODIUM_UP_H), (FACADE_R1, FACADE_Z1), (RIM_R, RIM_Z - 0.4)]
    pts += [(float(r), float(dome_z(r))) for r in rs]
    return revolve(pts)


def facade_ribs(n=72):
    """Vertical mullion ribs following the outward-leaning facade."""
    a = np.array([FACADE_R0, PODIUM_UP_H - 0.3])
    b = np.array([FACADE_R1, FACADE_Z1 - 0.8])
    t = (b - a) / np.linalg.norm(b - a)
    nrm = np.array([t[1], -t[0]])            # outward normal in (r, z)
    w, depth = 0.9, 1.3                      # half width, protrusion
    ribs = []
    for k in range(n):
        th = 2 * math.pi * (k + 0.5) / n
        c, s = math.cos(th), math.sin(th)
        ex = np.array([c, s, 0.0])
        ey = np.array([-s, c, 0.0])
        pts = []
        for p in (a, b):
            for off in (-0.6, depth):
                rz = p + off * nrm
                for side in (-w, w):
                    pts.append(rz[0] * ex + side * ey + np.array([0, 0, rz[1]]))
        ribs.append(hull(pts))
    return union(ribs)


def track_band():
    band = dome_solid(BAND_LIFT) ^ box(-BAND_X, BAND_X, -BAND_Y, BAND_Y, 40, 90)
    band = band ^ Manifold.cylinder(60, RIM_R - 2.0, circular_segments=SEG).translate((0, 0, 40))
    # raised rails along both long edges of the band
    rails = dome_solid(BAND_LIFT + 1.6) ^ union([
        box(-BAND_X, BAND_X, BAND_Y - 2.6, BAND_Y - 0.6, 40, 90),
        box(-BAND_X, BAND_X, -BAND_Y + 0.6, -BAND_Y + 2.6, 40, 90)])
    rails = rails ^ Manifold.cylinder(60, RIM_R - 2.5, circular_segments=SEG).translate((0, 0, 40))
    return band + rails


def sliding_panels(open_roof):
    """Two roof panels; closed: meet at the centre, open: parked at the ends."""
    top = dome_solid(PANEL_LIFT)
    ribs_top = dome_solid(PANEL_LIFT + 1.0)
    panels, ribs = [], []
    for sgn in (1, -1):
        if open_roof:
            x0, x1 = OPEN_D + FIELD_HX + 2.0, OPEN_D + FIELD_HX + 2.0 + PANEL_LEN
        else:
            x0, x1 = 0.75, PANEL_LEN
        lo, hi = sorted((sgn * x0, sgn * x1))
        panels.append(box(lo, hi, -PANEL_Y, PANEL_Y, 40, 95))
        for i in range(1, 6):
            xc = sgn * (x0 + (x1 - x0) * i / 6)
            ribs.append(box(xc - 0.8, xc + 0.8, -PANEL_Y + 1, PANEL_Y - 1, 40, 95))
    clip = Manifold.cylinder(60, RIM_R - 3.0, circular_segments=SEG).translate((0, 0, 40))
    p = (top ^ union(panels)) ^ clip
    r = (ribs_top ^ union(ribs)) ^ clip
    return p + r


def pylons():
    """8 tapered steel pylons with spires and two stay cables each."""
    shafts, stays = [], []
    for k in range(8):
        phi = math.radians(22.5 + 45 * k)
        er = np.array([math.cos(phi), math.sin(phi), 0.0])
        et = np.array([-math.sin(phi), math.cos(phi), 0.0])
        base = PYLON_R * er
        pts = []
        for z, dr, dt in ((PODIUM_UP_H - 0.5, 5.0, 3.8), (PYLON_TOP, 1.9, 1.6)):
            for sr in (-dr, dr):
                for st in (-dt, dt):
                    pts.append(base + sr * er + st * et + np.array([0, 0, z]))
        pts.append(base + np.array([0, 0, PYLON_TIP]))
        shafts.append(hull(pts))
        top = base + np.array([0, 0, PYLON_TOP - 2.5])
        for dphi in (-7.0, 7.0):
            ph = phi + math.radians(dphi)
            r = 108.0
            q = np.array([r * math.cos(ph), r * math.sin(ph), float(dome_z(r)) - 1.0])
            stays.append(rod(top, q, 1.25))
    return union(shafts), union(stays)


def bowl_parts():
    """Cavity for the open roof plus terraced stands and pitch."""
    opening = rounded_rect(FIELD_HX + OPEN_D, FIELD_HY + OPEN_D, FIELD_RC + OPEN_D)
    cavity = opening.extrude(120).translate((0, 0, FIELD_Z))

    def ring(d0, z_top):
        outer = rounded_rect(FIELD_HX + OPEN_D + 0.5, FIELD_HY + OPEN_D + 0.5,
                             FIELD_RC + OPEN_D + 0.5)
        inner = rounded_rect(FIELD_HX + d0, FIELD_HY + d0, FIELD_RC + d0)
        return (outer - inner).extrude(z_top - FIELD_Z + 1.0).translate((0, 0, FIELD_Z - 1.0))

    steps = []
    z = FIELD_Z
    for k in range(8):                    # lower tier: 8 rows, 2 m deep, ~35 deg
        z += 1.4
        steps.append(ring(2.0 * (k + 1), z))
    z_mid = z + 9.0                       # front wall of the upper tier
    steps.append(ring(16.0, z_mid))
    for k in range(3):                    # upper tier front rows
        steps.append(ring(16.0 + 1.33 * (k + 1), z_mid + 1.6 * (k + 1)))
    stands = union(steps)
    pitch = rounded_rect(52.5, 34.0, 0.01).extrude(1.5).translate((0, 0, FIELD_Z - 1.0))
    return cavity, stands, pitch


# ---------------------------------------------------------------- assembly
def build(open_roof):
    """Return (print solid, coloured preview parts). The parts union to the solid."""
    drum = body()
    lower = box(-200, 200, -200, 200, 0, FACADE_Z1)
    parts = {
        "podium": podium(),
        "facade": drum ^ lower,
        "roof": drum - lower,
        "ribs": facade_ribs(),
        "roof_band": track_band(),
        "panels": sliding_panels(open_roof),
    }
    parts["pylons"], parts["stays"] = pylons()
    if open_roof:
        cavity, stands, pitch = bowl_parts()
        wall_zone = rounded_rect(FIELD_HX + OPEN_D + 2.5, FIELD_HY + OPEN_D + 2.5,
                                 FIELD_RC + OPEN_D + 2.5).extrude(120).translate((0, 0, FIELD_Z - 2))
        for key in ("facade", "roof", "roof_band"):
            parts[key] = parts[key] - cavity
        parts["stands"] = stands
        parts["pitch"] = pitch
    # the print solid is built from whole parts; splitting is only for preview colours
    solid = drop_slivers(union(list(parts.values())))
    if open_roof:
        walls = []
        for key in ("facade", "roof", "roof_band"):
            walls.append(parts[key] ^ wall_zone)
            parts[key] = parts[key] - wall_zone
        parts["bowl_wall"] = union(walls)
    return solid, parts


def drop_slivers(m, min_volume=1.0):
    """Remove zero-volume fragments that coplanar booleans can leave behind."""
    comps = [c for c in m.decompose() if c.volume() >= min_volume]
    return Manifold.compose(comps) if len(comps) > 1 else comps[0]


def to_trimesh(m, scale):
    mesh = m.to_mesh()
    v = np.asarray(mesh.vert_properties)[:, :3] * scale
    f = np.asarray(mesh.tri_verts)
    return trimesh.Trimesh(vertices=v, faces=f, process=False)


COLORS = {  # sRGB display colours for the preview
    "podium": (176, 172, 166), "facade": (92, 132, 168), "ribs": (232, 236, 240),
    "roof": (226, 230, 235), "bowl_wall": (150, 156, 164),
    "roof_band": (214, 220, 227), "panels": (160, 170, 182), "pylons": (244, 245, 247),
    "stays": (198, 204, 212), "stands": (34, 74, 138), "pitch": (58, 140, 70),
}


def srgb_to_linear_u8(c):
    """glTF baseColorFactor is linear; convert sRGB 0-255 to linear 0-255."""
    out = []
    for v in c:
        v = v / 255.0
        lin = v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4
        out.append(int(round(lin * 255)))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--scale", type=float, default=2000.0, help="model scale 1:N")
    ap.add_argument("--out", default=os.path.join(os.path.dirname(__file__), "out"))
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)
    s = 1000.0 / args.scale                # metres -> millimetres at 1:N

    scene = trimesh.Scene()
    for open_roof in (False, True):
        name = "open" if open_roof else "closed"
        solid, parts = build(open_roof)
        tm = to_trimesh(solid, s)
        path = os.path.join(args.out, f"gazprom_arena_{name}.stl")
        tm.export(path)
        ext = tm.bounds[1] - tm.bounds[0]
        print(f"{name}: {len(tm.faces)} tris, watertight={tm.is_watertight}, "
              f"genus={solid.genus()}, volume={tm.volume / 1000:.1f} cm3, "
              f"size={ext[0]:.1f} x {ext[1]:.1f} x {ext[2]:.1f} mm -> {path}")
        for key, part in parts.items():
            pm = to_trimesh(part, s)
            rgba = srgb_to_linear_u8(COLORS[key]) + [255]
            pm.visual = trimesh.visual.TextureVisuals(
                material=trimesh.visual.material.PBRMaterial(
                    name=key, baseColorFactor=rgba,
                    metallicFactor=0.1 if key != "facade" else 0.35,
                    roughnessFactor=0.55 if key != "facade" else 0.3))
            # glTF is Y-up: rotate Z-up model
            pm.apply_transform(trimesh.transformations.rotation_matrix(-math.pi / 2, [1, 0, 0]))
            scene.add_geometry(pm, node_name=f"{name}__{key}", geom_name=f"{name}__{key}")
    glb = os.path.join(args.out, "preview.glb")
    scene.export(glb)
    print("preview:", glb, os.path.getsize(glb) // 1024, "KB")
    # the web preview can only fetch JSON, so ship the GLB base64-encoded as well
    import base64, json
    with open(glb, "rb") as fh, open(os.path.join(args.out, "preview_model.json"), "w") as out:
        json.dump({"format": "glb", "data": base64.b64encode(fh.read()).decode()}, out)


if __name__ == "__main__":
    main()
