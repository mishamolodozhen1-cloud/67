#!/usr/bin/env python3
"""Позы оружия DUMMY COMBAT: вид от первого лица (руки манекена + AK-47 у камеры) и от третьего лица
(оружие у плеча, руки по ИК). Один источник правды: числа отсюда записываются в Configs/WeaponPoses.lua,
а превью рисуется тем же расчётом, что повторяет клиент (Shared/ArmIK).

  python3 tools/weapons/viewmodel.py  -> src/ReplicatedStorage/Configs/WeaponPoses.lua,
                                          build/weapons/preview_viewmodel.png, preview_third.png

Системы координат:
  • вид от первого лица — оси камеры Roblox (смотрит в −Z, верх +Y, право +X), начало — в камере;
  • от третьего лица — оси UpperTorso (центр части), как Motor6D-позы;
  • точки на оружии — от центра детали Body (как Configs/WeaponModels).
Рука: плечо — сустав плеча, локоть — по двухзвенной ИК (длины плеча и предплечья — из скелета манекена),
кисть — целевое положение (ладонь на рукояти / цевье / магазине).
"""
import math
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(ROOT, "tools", "dummy"))
sys.path.insert(0, HERE)
import ak47  # noqa: E402
import guns  # noqa: E402
import geometry as g  # noqa: E402
import render  # noqa: E402
import rig  # noqa: E402
from make_dummy import colored  # noqa: E402

OUT = os.path.join(ROOT, "build", "weapons")


###############################################################################
# CFrame как (R, p): поворот 3×3 и точка; Angles — как CFrame.Angles (X, затем Y, затем Z)
###############################################################################
def cf(p=(0, 0, 0), rx=0.0, ry=0.0, rz=0.0):
    return (rig.rotation(rx, ry, rz), np.asarray(p, float))


def mul(a, b):
    return (a[0] @ b[0], a[1] + a[0] @ b[1])


def inv(a):
    return (a[0].T, -a[0].T @ a[1])


def point(a, v):
    return a[1] + a[0] @ np.asarray(v, float)


def unit(v):
    v = np.asarray(v, float)
    return v / np.linalg.norm(v)


def basis(palm, fingers, side):
    """Поворот кисти: ладонь смотрит в palm, пальцы — в fingers. У правой кисти ладонь — это −X части,
    у левой — +X; пальцы — −Y (кисть в покое висит пальцами вниз, ладонью к телу)."""
    f = unit(fingers)
    n = unit(np.asarray(palm, float) - f * np.dot(palm, f))
    x = -n if side == "Right" else n
    y = -f
    z = np.cross(x, y)
    return np.column_stack([x, y, z])


def slerp_cf(a, b, t):
    """Плавный переход между CFrame (как CFrame:Lerp: позиция линейно, поворот по кратчайшей дуге)."""
    from scipy.spatial.transform import Rotation, Slerp
    rots = Rotation.from_matrix(np.stack([a[0], b[0]]))
    r = Slerp([0, 1], rots)([t]).as_matrix()[0]
    return (r, a[1] + (b[1] - a[1]) * t)


def smooth(t):
    t = min(1.0, max(0.0, t))
    return t * t * (3 - 2 * t)


###############################################################################
# Скелет руки манекена (из того же rig, что и модель): точки суставов в осях частей
###############################################################################
PARTS = rig.build_parts()
INFO, ATTS = rig.spec(PARTS)


def att(part, name):
    for n, v in ATTS[part]:
        if n == name:
            return np.asarray(v, float)
    raise KeyError(part + "." + name)


def arm_dims(side):
    up, lo, hand = side + "UpperArm", side + "LowerArm", side + "Hand"
    return {
        "ShoulderUp": att(up, side + "ShoulderRigAttachment"),
        "ElbowUp": att(up, side + "ElbowRigAttachment"),
        "ElbowLo": att(lo, side + "ElbowRigAttachment"),
        "WristLo": att(lo, side + "WristRigAttachment"),
        "WristHand": att(hand, side + "WristRigAttachment"),
        "ShoulderTorso": att("UpperTorso", side + "ShoulderRigAttachment"),
    }


ARMS = {s: arm_dims(s) for s in ("Right", "Left")}


def align(local_dir, local_side, world_dir, world_side):
    """Поворот, переводящий направление кости local_dir в world_dir, а боковую ось local_side — как можно
    ближе к world_side (ось сгиба локтя)."""
    e1 = unit(local_dir)
    e2 = unit(local_side - e1 * np.dot(local_side, e1))
    e3 = np.cross(e1, e2)
    t1 = unit(world_dir)
    t2 = unit(world_side - t1 * np.dot(world_side, t1))
    t3 = np.cross(t1, t2)
    return np.column_stack([t1, t2, t3]) @ np.column_stack([e1, e2, e3]).T


def arm_ik(side, shoulder, hand_cf, pole):
    """Двухзвенная ИК. shoulder — точка сустава плеча, hand_cf — CFrame кисти (центр части), pole — куда
    смотрит локоть. Возвращает CFrame-ы UpperArm, LowerArm, Hand (центры частей)."""
    d = ARMS[side]
    l1 = np.linalg.norm(d["ElbowUp"] - d["ShoulderUp"])
    l2 = np.linalg.norm(d["WristLo"] - d["ElbowLo"])
    wrist = point(hand_cf, d["WristHand"])
    to = wrist - shoulder
    dist = float(np.linalg.norm(to))
    u = to / max(dist, 1e-6)
    dist = min(max(dist, abs(l1 - l2) + 1e-3), l1 + l2 - 1e-3)
    a = (l1 * l1 - l2 * l2 + dist * dist) / (2 * dist)
    h = math.sqrt(max(0.0, l1 * l1 - a * a))
    v = np.asarray(pole, float) - u * np.dot(pole, u)
    v = unit(v) if np.linalg.norm(v) > 1e-6 else unit(np.cross(u, (1, 0, 0)))
    elbow = shoulder + u * a + v * h
    wrist = shoulder + u * dist  # если рука не достаёт — кисть у предела вытянутой руки
    # ось сгиба локтя: перпендикуляр к плоскости руки; у части в покое это +X (предплечье сгибается вперёд)
    hinge = np.cross(elbow - shoulder, wrist - elbow)
    if np.linalg.norm(hinge) < 1e-6:
        hinge = np.cross(u, v)
    hinge = unit(hinge)
    R_up = align(d["ElbowUp"] - d["ShoulderUp"], np.array([1.0, 0, 0]), elbow - shoulder, hinge)
    up = (R_up, shoulder - R_up @ d["ShoulderUp"])
    R_lo = align(d["WristLo"] - d["ElbowLo"], np.array([1.0, 0, 0]), wrist - elbow, hinge)
    lo = (R_lo, elbow - R_lo @ d["ElbowLo"])
    hand = (hand_cf[0], wrist - hand_cf[0] @ d["WristHand"])
    return up, lo, hand


###############################################################################
# Оружие: точки (от центра Body) и хваты. Все стволы — из guns.all_models() (AK-47 — из ak47.py).
# setup(name) выставляет глобальные POINTS, HANDS, VM, TP, RELOADS… для выбранного оружия: на них работают
# расчёт, превью и запись конфига ниже.
###############################################################################
MODELS = guns.all_models()
WEAPONS = ["AK47", "SMG", "Shotgun", "Sniper", "Pistol"]
_PX = {}


def atlas_px(kind):
    if kind not in _PX:
        _PX[kind] = np.asarray((ak47.atlas_png() if kind == "ak" else guns.atlas_png())[1], float)
    return _PX[kind]


def centers(parts):
    out = {}
    for n in ("Body", "Magazine", "ChargingHandle", "Casing"):
        lo, hi = parts[n].bbox()
        out[n] = (lo + hi) / 2
    return out


_AK = centers(MODELS["AK47"][0])
AK_GRIP = np.asarray(ak47.POINTS["GripRight"], float) - _AK["Body"]


def anchored(pose, grip):
    """Поза AK-47 для другого ствола: тот же поворот, а рукоять (GripRight) — там же, где у AK."""
    R, p = pose
    return (R, p + R @ (AK_GRIP - grip))


def at_grip(target, grip, rx=0.0, ry=0.0, rz=0.0):
    """Поза, в которой рукоять grip оказывается в точке target (повороты — как CFrame.Angles)."""
    R = rig.rotation(rx, ry, rz)
    return (R, np.asarray(target, float) - R @ grip)


# Поза AK-47 — основа (вид от первого лица: в осях камеры)
AK_VM = {
    "Hip": cf((0.36, -0.5, -1.22), 0.035, 0.045, 0.06),
    "Sprint": cf((0.22, -0.72, -1.2), -0.55, 0.62, 0.5),
    "Reload": cf((0.3, -0.5, -1.35), 0.2, 0.28, -0.5),
    "Equip": cf((0.5, -1.6, -0.9), -0.9, 0.3, 0.2),
}
VM_SHOULDERS = {"Right": np.array([1.1, -1.45, 0.15]), "Left": np.array([-0.5, -1.25, -0.5])}
VM_POLES = {"Right": np.array([0.8, -1.0, 0.1]), "Left": np.array([-0.7, -1.0, 0.0])}

# Характеристики поз по оружию: ход затвора, расстояние прицела от глаза, поле зрения в прицеле
SPECS = {
    "AK47": {"Charge": 0.42, "AimDist": 2.0, "AimFov": 55},
    "SMG": {"Charge": 0.3, "AimDist": 1.3, "AimFov": 58},
    "Shotgun": {"Charge": 0.34, "AimDist": 1.15, "AimFov": 60},
    "Sniper": {"Charge": 0.26, "AimDist": 1.05, "AimFov": 20},
    "Pistol": {"Charge": 0.19, "AimDist": 1.3, "AimFov": 62},
}


def rifle_reloads():
    return {
        "Tactical": {
            "Length": 2.5,
            "Gun": [(0.0, 0.0), (0.3, 1.0), (1.95, 1.0), (2.4, 0.0)],
            "LeftHand": [(0.0, "Left"), (0.28, "Left"), (0.55, "LeftMag"), (0.66, "LeftMag"), (0.98, "Below"), (1.2, "Below"),
                         (1.42, "Enter"), (1.6, "LeftMag"), (1.68, "LeftMag"), (1.98, "Left")],
            "RightHand": [(0.0, "Right")],
            "MagInHand": (0.62, 1.58),
            "Sounds": [(0.62, "MagOut"), (1.56, "MagIn")],
        },
        "Empty": {
            "Length": 3.1,
            "Gun": [(0.0, 0.0), (0.3, 1.0), (1.7, 1.0), (1.95, 0.6), (2.6, 0.6), (3.0, 0.0)],
            "LeftHand": [(0.0, "Left"), (0.28, "Left"), (0.55, "LeftMag"), (0.66, "LeftMag"), (0.98, "Below"), (1.2, "Below"),
                         (1.42, "Enter"), (1.6, "LeftMag"), (1.66, "LeftMag"), (1.95, "Left")],
            "RightHand": [(0.0, "Right"), (1.7, "Right"), (1.98, "RightCharge"), (2.12, "RightChargePulled"), (2.2, "RightChargePulled"),
                          (2.55, "Right")],
            "MagInHand": (0.62, 1.58),
            "Charge": (2.0, 2.12, 2.2),  # начало оттяжки, рукоять в крайнем заднем, отпущена
            "Sounds": [(0.62, "MagOut"), (1.56, "MagIn"), (2.02, "Charge")],
        },
    }


def scaled(r, k):
    """Те же ключи перезарядки, но быстрее/медленнее в k раз."""
    out = {}
    for kind, v in r.items():
        w = dict(v)
        w["Length"] = round(v["Length"] * k, 3)
        for key in ("Gun", "LeftHand", "RightHand", "Sounds"):
            w[key] = [(round(t * k, 3), x) for t, x in v[key]]
        w["MagInHand"] = tuple(round(t * k, 3) for t in v["MagInHand"])
        if "Charge" in v:
            w["Charge"] = tuple(round(t * k, 3) for t in v["Charge"])
        out[kind] = w
    return out


def setup(name):
    """Выставить глобальные данные поз для оружия name."""
    global NAME, PARTS_W, ATLAS_KIND, INFO_W, BODY_C, POINTS, MAG_C, CH_C, HANDS, HANDS_EXTRA, VM, TP, RELOADS, CHARGE_TRAVEL
    NAME = name
    PARTS_W, pts, ATLAS_KIND = MODELS[name]
    INFO_W = centers(PARTS_W)
    BODY_C = INFO_W["Body"]
    POINTS = {k: np.asarray(v, float) - BODY_C for k, v in pts.items()}
    MAG_C = INFO_W["Magazine"] - BODY_C
    CH_C = INFO_W["ChargingHandle"] - BODY_C
    spec = SPECS[name]
    CHARGE_TRAVEL = spec["Charge"]
    grip = POINTS["GripRight"]
    pistol = name == "Pistol"
    # Хваты — CFrame кисти (центр части) в осях оружия
    HANDS = {
        # правая: ладонь на правой стороне пистолетной рукояти, пальцы вниз-вперёд вокруг неё
        "Right": (basis(palm=(-1, 0.05, 0), fingers=(0.0, -0.6, -0.8), side="Right"), grip + np.array([0.15, -0.02, 0.1])),
        # левая: ладонь снизу на цевье, пальцы обхватывают его справа-сверху
        "Left": (basis(palm=(0.25, 1, 0.05), fingers=(0.92, 0.2, -0.33), side="Left"), POINTS["GripLeft"] + np.array([-0.06, -0.17, 0.02])),
        # левая держит магазин спереди-слева (перезарядка)
        "LeftMag": (basis(palm=(1, 0.1, 0.1), fingers=(0.25, -0.45, -0.86), side="Left"), MAG_C + np.array([-0.17, -0.05, -0.12])),
        # правая отпускает рукоять и тянет рукоять затвора (она справа): ладонь к ствольной коробке
        "RightCharge": (basis(palm=(-1, 0.1, 0), fingers=(0.0, -0.35, -0.94), side="Right"), POINTS["ChargingHandle"] + np.array([0.16, -0.02, 0.1])),
    }
    if name == "Shotgun":
        HANDS["LeftMag"] = (HANDS["LeftMag"][0], MAG_C + np.array([-0.18, -0.05, -0.12]))
    below = (basis(palm=(1, 0.2, 0), fingers=(0.2, -0.3, -0.9), side="Left"), MAG_C + np.array([-0.35, -1.25, 0.25]))
    enter = (HANDS["LeftMag"][0], HANDS["LeftMag"][1] + np.array([0.0, -0.32, -0.12]))
    if pistol:
        # обе руки на рукояти: правая держит, левая обхватывает правую снизу-слева
        HANDS["Right"] = (HANDS["Right"][0], grip + np.array([0.14, -0.02, 0.08]))
        HANDS["Left"] = (basis(palm=(1, 0.15, 0.1), fingers=(0.3, -0.55, -0.78), side="Left"), grip + np.array([-0.15, -0.07, 0.0]))
        # магазин из рукояти: левая берёт его за дно снизу
        HANDS["LeftMag"] = (basis(palm=(0.5, 0.85, 0.0), fingers=(0.35, -0.15, -0.92), side="Left"), MAG_C + np.array([-0.1, -0.3, 0.02]))
        # затвор-кожух левая передёргивает сверху (ладонь на кожухе, пальцы на правую сторону)
        HANDS["LeftCharge"] = (basis(palm=(0.15, -1, 0.0), fingers=(1.0, -0.35, 0.1), side="Left"), POINTS["ChargingHandle"] + np.array([-0.03, 0.14, 0.0]))
        below = (basis(palm=(1, 0.2, 0), fingers=(0.2, -0.3, -0.9), side="Left"), MAG_C + np.array([-0.3, -0.95, 0.25]))
        enter = (HANDS["LeftMag"][0], HANDS["LeftMag"][1] + np.array([0.0, -0.3, 0.05]))
    HANDS = {k: (np.asarray(r), np.asarray(p)) for k, (r, p) in HANDS.items()}
    HANDS_EXTRA = {
        "Below": below,
        "Enter": enter,
        "RightChargePulled": (HANDS["RightCharge"][0], HANDS["RightCharge"][1] + np.array([0, 0, CHARGE_TRAVEL])),
    }
    if pistol:
        HANDS_EXTRA["LeftChargePulled"] = (HANDS["LeftCharge"][0], HANDS["LeftCharge"][1] + np.array([0, 0, CHARGE_TRAVEL]))

    # Вид от первого лица: CFrame детали Body относительно камеры
    aim = cf(-POINTS["SightRear"] + np.array([0, 0, -spec["AimDist"]]))
    if pistol:
        poses = {
            "Hip": at_grip((0.3, -0.52, -1.5), grip, 0.06, 0.22, 0.1),
            "Aim": aim,
            "Sprint": at_grip((0.28, -0.72, -1.05), grip, -0.9, 0.3, 0.15),
            "Reload": at_grip((0.16, -0.42, -1.2), grip, 0.6, 0.45, -0.3),
            "Equip": at_grip((0.4, -1.5, -0.8), grip, -0.9, 0.3, 0.2),
        }
    else:
        poses = {k: anchored(v, grip) for k, v in AK_VM.items()}
        poses["Aim"] = aim
        poses = {k: poses[k] for k in ("Hip", "Aim", "Sprint", "Reload", "Equip")}
    VM = {"Shoulders": VM_SHOULDERS, "Poles": VM_POLES, "Poses": poses, "AimFov": spec["AimFov"]}

    # От третьего лица: оружие у плеча, корпус развёрнут («боевая стойка»); в осях UpperTorso
    if pistol:
        TP = {"Twist": -0.2, "Poles": {"Right": np.array([0.7, -1.0, 0.3]), "Left": np.array([-0.7, -1.0, 0.2])}}

        def tp(target, rx=0.0, ry=0.0, rz=0.0):
            tw = cf((0, 0, 0), 0, TP["Twist"], 0)
            return mul(inv(tw), at_grip(target, grip, rx, ry, rz))
        TP["Poses"] = {
            "Ready": tp((0.12, 0.05, -1.3), -0.45, 0.0, 0.0),
            "Aim": tp((0.05, 0.66, -1.62), 0.0, 0.0, 0.0),
            "Sprint": tp((0.4, -0.25, -0.75), -1.1, 0.2, 0.1),
            "Reload": tp((0.1, 0.1, -1.15), 0.45, 0.25, -0.3),
        }
    else:
        TP = {"Twist": -0.55, "Poles": {"Right": np.array([0.7, -1.0, 0.3]), "Left": np.array([-0.35, -1.0, -0.1])}}

        def tp(p, rx=0.0, ry=0.0, rz=0.0):
            # p и углы — в «прямых» осях (корпус не развёрнут); оружие разворачиваем обратно на Twist
            tw = cf((0, 0, 0), 0, TP["Twist"], 0)
            return mul(inv(tw), anchored(cf(p, rx, ry, rz), grip))
        TP["Poses"] = {
            "Ready": tp((0.55, 0.38, -1.38), -0.1, 0.0, 0.0),
            "Aim": tp((0.36, 0.72, -1.42), 0.0, 0.0, 0.0),
            "Sprint": tp((0.15, 0.0, -1.05), -0.7, 0.85, 0.3),
            "Reload": tp((0.4, 0.3, -1.3), 0.25, 0.35, -0.5),
        }
        if name == "Sniper":
            # прицел выше, чем у AK: оружие ниже на столько же, чтобы окуляр был у глаза
            dy = POINTS["SightRear"][1] - POINTS["GripRight"][1] - (0.135 - (-0.27))
            R, p = TP["Poses"]["Aim"]
            TP["Poses"]["Aim"] = (R, p - R @ np.array([0, dy, 0]))

    # Перезарядка: ключи времени (с). Gun — вес позы Reload (0 — обычная поза, 1 — наклонена к левой руке),
    # LeftHand/RightHand — имена хватов, MagInHand — когда магазин в левой руке, Charge — ход затвора
    if pistol:
        RELOADS = {
            "Tactical": {
                "Length": 1.8,
                "Gun": [(0.0, 0.0), (0.22, 1.0), (1.4, 1.0), (1.75, 0.0)],
                "LeftHand": [(0.0, "Left"), (0.2, "Left"), (0.4, "LeftMag"), (0.47, "LeftMag"), (0.72, "Below"), (0.88, "Below"),
                             (1.06, "Enter"), (1.2, "LeftMag"), (1.26, "LeftMag"), (1.5, "Left")],
                "RightHand": [(0.0, "Right")],
                "MagInHand": (0.45, 1.22),
                "Sounds": [(0.45, "MagOut"), (1.2, "MagIn")],
            },
            "Empty": {
                "Length": 2.35,
                "Gun": [(0.0, 0.0), (0.22, 1.0), (1.3, 1.0), (1.48, 0.55), (1.95, 0.55), (2.3, 0.0)],
                "LeftHand": [(0.0, "Left"), (0.2, "Left"), (0.4, "LeftMag"), (0.47, "LeftMag"), (0.72, "Below"), (0.88, "Below"),
                             (1.06, "Enter"), (1.2, "LeftMag"), (1.26, "LeftMag"), (1.5, "LeftCharge"), (1.62, "LeftChargePulled"),
                             (1.68, "LeftChargePulled"), (1.75, "LeftCharge"), (2.05, "Left")],
                "RightHand": [(0.0, "Right")],
                "MagInHand": (0.45, 1.22),
                "Charge": (1.5, 1.62, 1.68),
                "Sounds": [(0.45, "MagOut"), (1.2, "MagIn"), (1.52, "Slide")],
            },
        }
    elif name == "SMG":
        RELOADS = scaled(rifle_reloads(), 0.85)
    elif name == "Shotgun":
        RELOADS = scaled(rifle_reloads(), 1.05)
    elif name == "Sniper":
        RELOADS = scaled(rifle_reloads(), 1.05)
        for r in RELOADS.values():
            r["Sounds"] = [(t, "BoltOpen" if s == "Charge" else s) for t, s in r["Sounds"]]
        # передёрнуть затвор после выстрела: правая рука на рукоять, назад, вперёд, на место
        RELOADS["Cycle"] = {
            "Length": 0.95,
            "Gun": [(0.0, 0.0), (0.16, 0.3), (0.72, 0.3), (0.95, 0.0)],
            "LeftHand": [(0.0, "Left")],
            "RightHand": [(0.0, "Right"), (0.2, "RightCharge"), (0.36, "RightChargePulled"), (0.46, "RightChargePulled"),
                          (0.6, "RightCharge"), (0.88, "Right")],
            "MagInHand": (0.0, 0.0),
            "Charge": (0.2, 0.36, 0.46, 0.14),  # 4-е число — сколько времени затвор досылают вперёд
            "Sounds": [(0.22, "BoltOpen"), (0.5, "BoltClose")],
        }
    else:
        RELOADS = rifle_reloads()


setup("AK47")


def hand_key(name):
    return HANDS.get(name) or HANDS_EXTRA[name]


def track(keys, t, lerp):
    if t <= keys[0][0]:
        return keys[0][1]
    for (t0, a), (t1, b) in zip(keys, keys[1:]):
        if t <= t1:
            return lerp(a, b, smooth((t - t0) / max(t1 - t0, 1e-6)))
    return keys[-1][1]


def reload_state(kind, t):
    r = RELOADS[kind]
    w = track(r["Gun"], t, lambda a, b, k: a + (b - a) * k)
    left = track([(k, hand_key(n)) for k, n in r["LeftHand"]], t, slerp_cf)
    right = track([(k, hand_key(n)) for k, n in r["RightHand"]], t, slerp_cf)
    mag_hand = r["MagInHand"][0] <= t < r["MagInHand"][1]
    charge = 0.0
    if "Charge" in r:
        c0, c1, c2 = r["Charge"][:3]
        back = r["Charge"][3] if len(r["Charge"]) > 3 else 0.05
        if c0 <= t < c1:
            charge = smooth((t - c0) / (c1 - c0))
        elif c1 <= t < c2:
            charge = 1.0  # держат в крайнем заднем
        elif c2 <= t < c2 + back:
            charge = 1.0 - (t - c2) / back  # отпустили: рама влетает вперёд пружиной (или затвор досылают рукой)
    return w, left, right, mag_hand, charge


###############################################################################
# Сцена для превью
###############################################################################
ARM_PARTS = ["RightUpperArm", "RightLowerArm", "RightHand", "LeftUpperArm", "LeftLowerArm", "LeftHand"]


def ak_items(gun_cf, mag_cf=None, charge=0.0, show_mag=True):
    """Детали текущего оружия (setup) в позе gun_cf — для превью."""
    px = atlas_px(ATLAS_KIND)
    out = []
    for name in ("Body", "Magazine", "ChargingHandle"):
        if name == "Magazine" and not show_mag:
            continue
        m = PARTS_W[name]
        col = px[np.clip((m.uv[:, 1] * 1024).astype(int), 0, 1023), np.clip((m.uv[:, 0] * 1024).astype(int), 0, 1023)]
        pos = m.pos - BODY_C
        if name == "ChargingHandle":
            pos = pos + np.array([0, 0, CHARGE_TRAVEL * charge])
        frame = gun_cf
        if name == "Magazine" and mag_cf is not None:
            frame = mag_cf
            pos = m.pos - INFO_W["Magazine"]
        out.append((pos @ frame[0].T + frame[1], m.nrm @ frame[0].T, col, m.idx))
    return out


def arm_items(frames):
    out = []
    for name, (R, t) in frames.items():
        local = PARTS[name].transformed(None, -INFO[name]["Center"])
        out.append(colored(local, R, t))
    return out


def arms_for(gun_cf, shoulders, poles, right_cf=None, left_cf=None, upper=True):
    frames = {}
    rh = right_cf if right_cf is not None else mul(gun_cf, hand_key("Right"))
    lh = left_cf if left_cf is not None else mul(gun_cf, hand_key("Left"))
    for side, hcf in (("Right", rh), ("Left", lh)):
        up, lo, hand = arm_ik(side, shoulders[side], hcf, poles[side])
        if upper:
            frames[side + "UpperArm"] = up
        frames[side + "LowerArm"], frames[side + "Hand"] = lo, hand
    return frames


def backdrop():
    # пол и стена-ориентир (чтобы видеть, где горизонт и центр)
    floor = render.ground(size=40, step=2.0, y=-5.6)
    return [floor]


def view(items, fov, W=560, H=315):
    img = render.render(backdrop() + items, (0, 0, 0), (0, 0, -1), fov=fov, W=W, H=H, bg=(120, 140, 160), near=0.1)
    from PIL import ImageDraw
    d = ImageDraw.Draw(img)
    cx, cy = W // 2, H // 2
    d.line((cx - 6, cy, cx + 6, cy), fill=(255, 60, 60))
    d.line((cx, cy - 6, cx, cy + 6), fill=(255, 60, 60))
    return img


def vm_frame(pose_cf, left_cf=None, right_cf=None, mag_cf=None, charge=0.0):
    frames = arms_for(pose_cf, VM["Shoulders"], VM["Poles"], right_cf=right_cf, left_cf=left_cf, upper=False)
    return ak_items(pose_cf, mag_cf, charge) + arm_items(frames)


def preview_viewmodel():
    imgs = []
    suffix = "" if NAME == "AK47" else "_" + NAME.lower()
    for name, fov in (("Hip", 72), ("Aim", VM["AimFov"]), ("Sprint", 78), ("Equip", 72)):
        imgs.append(render.label(view(vm_frame(VM["Poses"][name]), fov), name))
    frames = [("Tactical", RELOADS["Tactical"]["MagInHand"][0] + d) for d in (0.0, 0.38, 0.8)]
    frames += [("Empty", RELOADS["Empty"]["Charge"][0] + d) for d in (0.0, 0.14)]
    if "Cycle" in RELOADS:
        frames += [("Cycle", 0.4)]
    for kind, t in frames:
        if True:
            w, left_gun, right_gun, mag_hand, charge = reload_state(kind, t)
            gun = slerp_cf(VM["Poses"]["Hip"], VM["Poses"]["Reload"], w)
            left = mul(gun, left_gun)
            right = mul(gun, right_gun)
            mag = None
            if mag_hand:
                grab = hand_key("LeftMag")
                hand_to_mag = mul(inv(grab), cf(MAG_C))
                mag = mul(left, hand_to_mag)
            imgs.append(render.label(view(vm_frame(gun, left, right, mag, charge), 72), "%s %.2f" % (kind, t)))
    render.sheet(imgs, 2).save(os.path.join(OUT, "preview_viewmodel%s.png" % suffix))


def preview_third():
    imgs = []
    suffix = "" if NAME == "AK47" else "_" + NAME.lower()
    from make_dummy import posed_items
    for name in ("Ready", "Aim", "Sprint", "Reload"):
        # корпус развёрнут на Twist (Waist), голова — обратно вперёд (Neck)
        poses = {"UpperTorso": ((0, 0, 0), 0, TP["Twist"], 0), "Head": ((0, 0, 0), 0, -TP["Twist"], 0)}
        world = rig.pose_world(INFO, poses)
        R_t, p_t = world["UpperTorso"]
        torso = (R_t, p_t)
        gun = mul(torso, TP["Poses"][name])
        sh = {s: point(torso, ARMS[s]["ShoulderTorso"]) for s in ("Right", "Left")}
        poles = {s: torso[0] @ TP["Poles"][s] for s in ("Right", "Left")}
        left = None
        if name == "Reload":
            left = mul(gun, hand_key("LeftMag"))
        frames = arms_for(gun, sh, poles, left_cf=left)
        body = [it for it, n in zip(posed_items(PARTS, INFO, poses), rig.PART_ORDER) if n not in ARM_PARTS]
        items = body + arm_items(frames) + ak_items(gun) + [render.ground(size=6)]
        for vname, eye in (("сбоку", (6.5, 3.6, -1.0)), ("спереди", (2.8, 4.2, -6.5))):
            imgs.append(render.label(render.render(items, eye, (0, 3.4, -0.6), fov=38, W=420, H=420), "%s, %s" % (name, vname)))
    render.sheet(imgs, 4).save(os.path.join(OUT, "preview_third%s.png" % suffix))


###############################################################################
# Конфиг для игры
###############################################################################
def lua_cf(c):
    R, p = c
    f = lambda v: "Vector3.new(%.4f, %.4f, %.4f)" % tuple(v)  # noqa: E731
    return "CFrame.fromMatrix(%s, %s, %s, %s)" % (f(p), f(R[:, 0]), f(R[:, 1]), f(R[:, 2]))


def lua_v3(v):
    return "Vector3.new(%.4f, %.4f, %.4f)" % tuple(v)


def config_block():
    """Блок WeaponPoses для текущего оружия (setup)."""
    L = ["\t%s = table.freeze({" % NAME, "\t\tHands = table.freeze({"]
    for k in list(HANDS) + list(HANDS_EXTRA):
        L.append("\t\t\t%s = %s," % (k, lua_cf(hand_key(k))))
    L += ["\t\t}),", "\t\tMagazine = %s," % lua_v3(MAG_C), "\t\tChargeTravel = %.3f," % CHARGE_TRAVEL, "\t\tViewmodel = table.freeze({"]
    L.append("\t\t\tAimFov = %d," % VM["AimFov"])
    L.append("\t\t\tShoulders = table.freeze({ Right = %s, Left = %s })," % (lua_v3(VM["Shoulders"]["Right"]), lua_v3(VM["Shoulders"]["Left"])))
    L.append("\t\t\tPoles = table.freeze({ Right = %s, Left = %s })," % (lua_v3(VM["Poles"]["Right"]), lua_v3(VM["Poles"]["Left"])))
    L.append("\t\t\tPoses = table.freeze({")
    for k, v in VM["Poses"].items():
        L.append("\t\t\t\t%s = %s," % (k, lua_cf(v)))
    L += ["\t\t\t}),", "\t\t}),", "\t\tThirdPerson = table.freeze({", "\t\t\tTwist = %.4f," % TP["Twist"]]
    L.append("\t\t\tPoles = table.freeze({ Right = %s, Left = %s })," % (lua_v3(TP["Poles"]["Right"]), lua_v3(TP["Poles"]["Left"])))
    L.append("\t\t\tPoses = table.freeze({")
    for k, v in TP["Poses"].items():
        L.append("\t\t\t\t%s = %s," % (k, lua_cf(v)))
    L += ["\t\t\t}),", "\t\t}),", "\t\tReloads = table.freeze({"]
    for kind, r in RELOADS.items():
        L.append("\t\t\t%s = table.freeze({" % kind)
        L.append("\t\t\t\tLength = %g," % r["Length"])
        L.append("\t\t\t\tGun = table.freeze({ %s })," % ", ".join("{ %g, %g }" % k for k in r["Gun"]))
        L.append("\t\t\t\tLeftHand = table.freeze({ %s })," % ", ".join("{ %g, \"%s\" }" % k for k in r["LeftHand"]))
        L.append("\t\t\t\tRightHand = table.freeze({ %s })," % ", ".join("{ %g, \"%s\" }" % k for k in r["RightHand"]))
        L.append("\t\t\t\tMagInHand = { %g, %g }," % tuple(r["MagInHand"]))
        if "Charge" in r:
            L.append("\t\t\t\tCharge = { %s }," % ", ".join("%g" % x for x in r["Charge"]))
        L.append("\t\t\t\tSounds = table.freeze({ %s })," % ", ".join("{ %g, \"%s\" }" % k for k in r["Sounds"]))
        L.append("\t\t\t}),")
    L += ["\t\t}),"]
    # контрольные значения для теста: ИК рук в позе Hip (клиентский расчёт должен совпасть)
    frames = arms_for(VM["Poses"]["Hip"], VM["Shoulders"], VM["Poles"])
    L.append("\t\tCheck = table.freeze({")
    for name in ("RightUpperArm", "RightLowerArm", "RightHand", "LeftUpperArm", "LeftLowerArm", "LeftHand"):
        L.append("\t\t\t%s = %s," % (name, lua_cf(frames[name])))
    L += ["\t\t}),", "\t}),"]
    return L


def write_config(blocks):
    L = [
        "-- WeaponPoses: позы оружия и рук (создаётся tools/weapons/viewmodel.py — не править вручную).",
        "-- Viewmodel: всё в осях камеры (−Z — взгляд). Poses — CFrame детали Body; Shoulders/Poles — точки плеч",
        "-- и направления локтей для ИК рук. ThirdPerson: в осях UpperTorso; Twist — разворот корпуса (рад).",
        "-- Hands — CFrame кистей (центр части) в осях оружия. Reloads — ключи перезарядки (см. viewmodel.py);",
        "-- Cycle — передёргивание затвора после выстрела (снайперская винтовка).",
        "return table.freeze({",
    ]
    for b in blocks:
        L += b
    L.append("})")
    path = os.path.join(ROOT, "src", "ReplicatedStorage", "Configs", "WeaponPoses.lua")
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(L) + "\n")
    print(path)


def reach_report():
    """Достают ли руки: расстояние плечо—запястье против длины руки (если больше — рука вытянута не до конца)."""
    for side in ("Right", "Left"):
        d = ARMS[side]
        reach = np.linalg.norm(d["ElbowUp"] - d["ShoulderUp"]) + np.linalg.norm(d["WristLo"] - d["ElbowLo"])
        for pname, pose in VM["Poses"].items():
            hk = "Right" if side == "Right" else "Left"
            wrist = point(mul(pose, hand_key(hk)), d["WristHand"])
            dist = np.linalg.norm(wrist - VM["Shoulders"][side])
            flag = "  <-- не достаёт" if dist > reach else ""
            if flag:
                print("VM %-6s %-5s плечо-запястье %.2f / %.2f%s" % (pname, side, dist, reach, flag))


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    only = sys.argv[1:] or WEAPONS
    blocks = []
    for w in WEAPONS:
        setup(w)
        print("==", w)
        reach_report()
        blocks.append(config_block())
        if w in only:
            preview_viewmodel()
            preview_third()
    write_config(blocks)
