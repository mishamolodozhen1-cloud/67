"""Манекен DUMMY COMBAT: форма частей тела и скелет R15.

Все размеры — в studs, в позе покоя (руки вниз), пол — y = 0, персонаж смотрит в −Z, правая сторона +X.
Рост 5.62. Суставы — как у R15 (Root, Waist, Neck, плечи, локти, запястья, бёдра, колени, лодыжки):
в Roblox их строит Humanoid:BuildRigFromAttachments по парам «<Сустав>RigAttachment».
"""
import math

import numpy as np

import geometry as g

HRP_CENTER = (0.0, 2.95, 0.0)
HRP_SIZE = (2.0, 2.0, 1.0)
HIP_HEIGHT = HRP_CENTER[1] - HRP_SIZE[1] / 2  # 1.95: от пола до низа HumanoidRootPart

# Суставы: имя -> (родитель, ребёнок, точка в мире)
JOINTS = {
    "Root": ("HumanoidRootPart", "LowerTorso", (0.0, 2.95, 0.0)),
    "Waist": ("LowerTorso", "UpperTorso", (0.0, 3.12, 0.0)),
    "Neck": ("UpperTorso", "Head", (0.0, 4.6, 0.0)),
}
for side, s in (("Left", -1), ("Right", 1)):
    JOINTS[side + "Shoulder"] = ("UpperTorso", side + "UpperArm", (s * 1.0, 4.38, 0.0))
    JOINTS[side + "Elbow"] = (side + "UpperArm", side + "LowerArm", (s * 1.12, 3.4, 0.0))
    JOINTS[side + "Wrist"] = (side + "LowerArm", side + "Hand", (s * 1.13, 2.47, 0.0))
    JOINTS[side + "Hip"] = ("LowerTorso", side + "UpperLeg", (s * 0.43, 2.8, 0.0))
    JOINTS[side + "Knee"] = (side + "UpperLeg", side + "LowerLeg", (s * 0.43, 1.6, 0.0))
    JOINTS[side + "Ankle"] = (side + "LowerLeg", side + "Foot", (s * 0.43, 0.42, 0.0))

# Точки крепления аксессуаров и оружия (косметика — этап 10, оружие — этап 4): часть -> [(имя, точка в мире)]
EXTRA_ATTACHMENTS = {
    "Head": [("HatAttachment", (0, 5.62, 0)), ("HairAttachment", (0, 5.62, 0)), ("FaceFrontAttachment", (0, 5.1, -0.5)), ("FaceCenterAttachment", (0, 5.1, 0))],
    "UpperTorso": [("BodyFrontAttachment", (0, 3.95, -0.55)), ("BodyBackAttachment", (0, 3.95, 0.55)), ("NeckAttachment", (0, 4.6, 0)),
                   ("LeftCollarAttachment", (-0.6, 4.55, 0)), ("RightCollarAttachment", (0.6, 4.55, 0))],
    "LowerTorso": [("WaistCenterAttachment", (0, 2.84, 0)), ("WaistFrontAttachment", (0, 2.84, -0.48)), ("WaistBackAttachment", (0, 2.84, 0.48))],
    "LeftUpperArm": [("LeftShoulderAttachment", (-1.12, 4.62, 0))],
    "RightUpperArm": [("RightShoulderAttachment", (1.12, 4.62, 0))],
    "LeftHand": [("LeftGripAttachment", (-1.14, 2.02, -0.04))],
    "RightHand": [("RightGripAttachment", (1.14, 2.02, -0.04))],
    "LeftFoot": [("LeftFootAttachment", (-0.43, 0.0, -0.18))],
    "RightFoot": [("RightFootAttachment", (0.43, 0.0, -0.18))],
}

# Какие части сталкиваются с миром (остальные — нет: конечности не должны цепляться за стены и дёргать
# персонажа; столкновения тела держат корпус и голова). В регдолле (этап 3) это поменяется.
COLLIDE = {"HumanoidRootPart", "LowerTorso", "UpperTorso", "Head"}

PART_ORDER = ["Head", "UpperTorso", "LowerTorso",
              "LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm", "RightLowerArm", "RightHand",
              "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg", "RightLowerLeg", "RightFoot"]


def head():
    m = g.superellipsoid((0, 5.08, 0), (0.46, 0.54, 0.5), e=0.94, seg_u=36, seg_v=22)
    m.add(g.capsule(4.48, 4.9, 0.2, 0.2, seg=20, color="joint", dome=0.3))  # шея (резина)
    m.add(g.superellipsoid((0, 5.25, -0.445), (0.3, 0.045, 0.05), e=0.8, seg_u=20, seg_v=8, color="body_shade"))  # надбровье
    m.add(g.superellipsoid((0, 5.07, -0.49), (0.06, 0.11, 0.08), e=0.9, seg_u=14, seg_v=10))  # нос
    for s in (-1, 1):
        m.add(g.superellipsoid((s * 0.17, 5.16, -0.455), (0.085, 0.06, 0.03), e=1.0, seg_u=16, seg_v=8, color="eye"))
        m.add(g.marker((s * 0.465, 5.12, 0), (s, 0, 0), 0.17))
    return m


def upper_torso():
    rings = [(3.1, 0.62, 0.42), (3.3, 0.68, 0.44), (3.6, 0.8, 0.49), (3.95, 0.92, 0.52), (4.2, 0.97, 0.53),
             (4.38, 0.95, 0.5), (4.5, 0.86, 0.45), (4.58, 0.65, 0.38), (4.63, 0.38, 0.3)]
    m = g.lathe(rings, seg=36, n=2.6, pole_bottom=3.08, pole_top=4.65, center=(0, 0, -0.02))
    for s in (-1, 1):
        m.add(g.superellipsoid((s * 1.0, 4.38, 0), (0.28, 0.28, 0.28), e=1.0, seg_u=22, seg_v=12, color="joint"))  # плечевые шарниры
    m.add(g.superellipsoid((0, 3.98, -0.5), (0.62, 0.42, 0.07), e=0.45, seg_u=28, seg_v=10, color="body_shade"))  # нагрудная пластина
    for s in (-1, 1):
        m.add(g.superellipsoid((s * 0.42, 4.22, -0.565), (0.05, 0.05, 0.03), e=1.0, seg_u=10, seg_v=6, color="metal"))  # болты пластины
        m.add(g.superellipsoid((s * 0.42, 3.74, -0.565), (0.05, 0.05, 0.03), e=1.0, seg_u=10, seg_v=6, color="metal"))
    m.add(g.marker((0, 4.0, 0.535), (0, 0, 1), 0.2))  # метка на спине
    return m


def lower_torso():
    m = g.superellipsoid((0, 2.84, 0.02), (0.74, 0.34, 0.47), e=0.55, seg_u=32, seg_v=16)
    m.add(g.torus((0, 3.1, 0), 0.58, 0.09, seg=36, seg_minor=10, color="joint", aspect=0.72))  # пояс-шарнир
    for s in (-1, 1):
        m.add(g.marker((s * 0.745, 2.84, 0.02), (s, 0, 0), 0.16))
    return m


def upper_arm(s):
    x = s * 1.12
    m = g.capsule(3.32, 4.52, 0.21, 0.26, seg=24, bulge=0.08, bulge_at=0.65, center=(x, 0, 0))
    m.add(g.torus((x, 3.42, 0), 0.21, 0.06, color="joint"))
    return m


def lower_arm(s):
    x = s * 1.13
    m = g.capsule(2.4, 3.48, 0.16, 0.21, seg=24, bulge=0.1, bulge_at=0.7, center=(x, 0, 0))
    m.add(g.torus((x, 2.48, 0), 0.155, 0.05, color="joint"))
    return m


def hand(s):
    x = s * 1.14
    m = g.superellipsoid((x, 2.14, -0.01), (0.12, 0.3, 0.21), e=0.55, seg_u=24, seg_v=14)
    thumb = g.superellipsoid((0, 0, 0), (0.065, 0.15, 0.07), e=1.0, seg_u=14, seg_v=8)
    m.add(thumb.transformed(g.rot_x(0.35) @ g.rot_z(-s * 0.35), (x - s * 0.06, 2.26, -0.19)))
    return m


def upper_leg(s):
    x = s * 0.43
    m = g.capsule(1.5, 2.95, 0.26, 0.35, seg=28, aspect=1.05, bulge=0.06, center=(x, 0, 0))
    m.add(g.torus((x, 1.62, 0), 0.25, 0.075, color="joint"))
    return m


def lower_leg(s):
    x = s * 0.43
    m = g.capsule(0.36, 1.66, 0.19, 0.25, seg=26, bulge=0.12, bulge_at=0.62, center=(x, 0, 0))
    m.add(g.torus((x, 0.46, 0), 0.19, 0.06, color="joint"))
    return m


def foot(s):
    x = s * 0.43
    m = g.superellipsoid((x, 0.22, -0.18), (0.3, 0.19, 0.56), e=0.45, seg_u=28, seg_v=14)
    m.add(g.superellipsoid((x, 0.05, -0.18), (0.315, 0.05, 0.575), e=0.3, seg_u=28, seg_v=8, color="sole"))
    return m


def build_parts():
    parts = {"Head": head(), "UpperTorso": upper_torso(), "LowerTorso": lower_torso()}
    for side, s in (("Left", -1), ("Right", 1)):
        parts[side + "UpperArm"] = upper_arm(s)
        parts[side + "LowerArm"] = lower_arm(s)
        parts[side + "Hand"] = hand(s)
        parts[side + "UpperLeg"] = upper_leg(s)
        parts[side + "LowerLeg"] = lower_leg(s)
        parts[side + "Foot"] = foot(s)
    return parts


def spec(parts):
    """Данные скелета: центр и размер каждой части (по габаритам меша), точки суставов в осях частей."""
    info = {"HumanoidRootPart": {"Center": np.array(HRP_CENTER), "Size": np.array(HRP_SIZE)}}
    for name in PART_ORDER:
        lo, hi = parts[name].bbox()
        info[name] = {"Center": (lo + hi) / 2, "Size": hi - lo}
    atts = {name: [] for name in info}
    for joint, (p0, p1, world) in JOINTS.items():
        w = np.array(world, float)
        for part in (p0, p1):
            atts[part].append((joint + "RigAttachment", w - info[part]["Center"]))
    for part, lst in EXTRA_ATTACHMENTS.items():
        for name, world in lst:
            atts[part].append((name, np.array(world, float) - info[part]["Center"]))
    return info, atts


def joint_frames(info):
    """C0 и C1 каждого сустава (только смещения: оси суставов совпадают с осями частей)."""
    out = {}
    for joint, (p0, p1, world) in JOINTS.items():
        w = np.array(world, float)
        out[joint] = (p0, p1, w - info[p0]["Center"], w - info[p1]["Center"])
    return out


def rotation(rx, ry, rz):
    """Как CFrame.Angles(rx, ry, rz) в Roblox."""
    return g.rot_x(rx) @ g.rot_y(ry) @ g.rot_z(rz)


def pose_world(info, poses, root_offset=(0, 0, 0)):
    """Мировые матрицы частей для поз суставов. poses: часть -> (pos, rx, ry, rz) — Transform её сустава
    (как Pose в KeyframeSequence: Pose называется именем дочерней части)."""
    frames = joint_frames(info)
    child_joint = {p1: (j, p0, c0, c1) for j, (p0, p1, c0, c1) in frames.items()}
    world = {"HumanoidRootPart": (np.eye(3), np.array(HRP_CENTER, float) + np.asarray(root_offset, float))}

    def resolve(part):
        if part in world:
            return world[part]
        j, p0, c0, c1 = child_joint[part]
        R0, t0 = resolve(p0)
        pos, rx, ry, rz = poses.get(part, ((0, 0, 0), 0, 0, 0))
        Rt = rotation(rx, ry, rz)
        # Part1 = Part0 * C0 * Transform * C1^-1
        R = R0 @ Rt
        t = t0 + R0 @ (c0 + np.asarray(pos, float)) - R @ c1
        world[part] = (R, t)
        return world[part]

    for name in PART_ORDER:
        resolve(name)
    return world
