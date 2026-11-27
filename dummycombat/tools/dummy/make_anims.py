#!/usr/bin/env python3
"""Анимации манекена DUMMY COMBAT (R15) -> build/anims/*.rbxm (KeyframeSequence; в Roblox — ассет Animation)
и картинки поз build/anims/preview_*.png.

Кадры считаются формулами (без чужих анимаций):
  Idle            стойка: дыхание, перенос веса
  WalkF           шаг вперёд (назад — та же анимация с обратной скоростью)
  WalkL / WalkR   стрейф влево / вправо: таз развёрнут в сторону движения, грудь и голова — вперёд
  RunF            бег (только вперёд)
  CrouchIdle      присед: колени согнуты (персонаж ниже на CROUCH_DROP — его опускает HipHeight)
  CrouchF/L/R     ходьба в приседе
  Jump            толчок (не зациклена), Fall — в воздухе (цикл), Land — приземление (не зациклена)
  Climb           лазание по лестнице (цикл)

Позы — это Motor6D.Transform суставов: Pose называется именем дочерней части. Оси суставов совпадают
с осями частей: rx > 0 — бедро/плечо вперёд, колено сгибается при rx < 0, корпус наклоняется вперёд при rx < 0,
rz > 0 — нога/рука в сторону +X (вправо).
«Родная» скорость каждой походки считается по тому, как быстро стопа на опоре едет назад (studs/с):
скрипт анимации подгоняет темп под реальную скорость, и ноги не скользят по полу.

Запуск: python3 tools/dummy/make_anims.py  ->  build/anims/*.rbxm + anims.json (длины и скорости)
"""
import json
import math
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(ROOT, "tools"))
import rig  # noqa: E402
from rbxl import write_binary  # noqa: E402

OUT = os.path.join(ROOT, "build", "anims")

CROUCH_DROP = 1.0  # насколько ниже персонаж в приседе (на столько клиент уменьшает HipHeight)
SPEED = {"walk": 12.0, "run": 19.0, "crouch": 6.5}  # те же скорости, что в GameConfig.Movement

TREE = {
    "HumanoidRootPart": ["LowerTorso"],
    "LowerTorso": ["UpperTorso", "LeftUpperLeg", "RightUpperLeg"],
    "UpperTorso": ["Head", "LeftUpperArm", "RightUpperArm"],
    "LeftUpperArm": ["LeftLowerArm"], "LeftLowerArm": ["LeftHand"],
    "RightUpperArm": ["RightLowerArm"], "RightLowerArm": ["RightHand"],
    "LeftUpperLeg": ["LeftLowerLeg"], "LeftLowerLeg": ["LeftFoot"],
    "RightUpperLeg": ["RightLowerLeg"], "RightLowerLeg": ["RightFoot"],
    "Head": [], "LeftHand": [], "RightHand": [], "LeftFoot": [], "RightFoot": [],
}


class Inst:
    def __init__(self, cls, name, props=None):
        self.cls, self.name, self.props, self.children = cls, name, props or [], []

    def add(self, child):
        self.children.append(child)
        return child


def cframe(pos, rx, ry, rz):
    r = rig.rotation(rx, ry, rz)
    return (pos[0], pos[1], pos[2], r[0][0], r[0][1], r[0][2], r[1][0], r[1][1], r[1][2], r[2][0], r[2][1], r[2][2])


def pose_tree(name, joints):
    pos, rx, ry, rz = joints.get(name, ((0, 0, 0), 0, 0, 0))
    p = Inst("Pose", name, [("CFrame", "CFrame", cframe(pos, rx, ry, rz)), ("float", "Weight", 1.0),
                            ("token", "EasingStyle", 0), ("token", "EasingDirection", 0)])
    for child in TREE[name]:
        p.add(pose_tree(child, joints))
    return p


def sequence(name, length, frames, sample, priority, loop, markers=None):
    kfs = Inst("KeyframeSequence", name, [("bool", "Loop", loop), ("token", "Priority", priority)])
    marks = {}
    for (u, mname, value) in (markers or []):
        marks.setdefault(int(round(u * frames)) % (frames if loop else frames + 1), []).append((mname, value))
    for i in range(frames + 1):
        t = i / frames
        kf = Inst("Keyframe", "Keyframe", [("float", "Time", round(t * length, 4))])
        kf.add(pose_tree("HumanoidRootPart", sample(t)))
        for (mname, value) in marks.get(i, []):
            kf.add(Inst("KeyframeMarker", mname, [("string", "Value", value)]))
        kfs.add(kf)
    return kfs


def pos_part(x):
    return max(0.0, x)


def smooth(x):
    x = max(0.0, min(1.0, x))
    return x * x * (3 - 2 * x)


def keyed(keys):
    def f(t):
        if t <= keys[0][0]:
            return keys[0][1]
        for (t0, v0), (t1, v1) in zip(keys, keys[1:]):
            if t <= t1:
                return v0 + (v1 - v0) * (smooth((t - t0) / (t1 - t0)) if t1 > t0 else 1)
        return keys[-1][1]
    return f


###############################################################################
# Ноги: присед через обратную кинематику (стопа на полу, таз ниже на CROUCH_DROP)
###############################################################################
L1 = 2.8 - 1.6   # бедро
L2 = 1.6 - 0.42  # голень


def leg_ik(down, forward):
    """Углы бедра a (вперёд) и сгиба колена b, чтобы лодыжка была на down ниже бедра и на forward впереди."""
    best = None
    for a in np.linspace(-0.3, 1.8, 400):
        # лодыжка = L1*(0,-cos a,-sin a) + L2*(0,-cos(a-b),-sin(a-b)); подбираем b по высоте
        y1, z1 = -L1 * math.cos(a), -L1 * math.sin(a)
        need = (-down - y1) / L2  # = -cos(a-b)
        if abs(need) > 1:
            continue
        ab = math.acos(-need)
        for sgn in (1, -1):
            b = a - sgn * ab
            if b < 0:
                continue
            z = z1 - L2 * math.sin(a - b)
            err = abs(z - (-forward))
            if best is None or err < best[0]:
                best = (err, a, b)
    return best[1], best[2]


CROUCH_A, CROUCH_B = leg_ik(L1 + L2 - CROUCH_DROP, 0.12)


###############################################################################
# Позы
###############################################################################
def base_upper(lean=0.0, arm_fwd=0.06, elbow=0.18, breath=0.0):
    """Корпус, голова и руки в спокойной стойке."""
    j = {
        "UpperTorso": ((0, 0, 0), -lean + 0.012 * breath, 0, 0),
        "Head": ((0, 0, 0), lean * 0.8 - 0.01 * breath, 0, 0),
    }
    for side, s in (("Left", -1), ("Right", 1)):
        j[side + "UpperArm"] = ((0, 0, 0), arm_fwd + 0.015 * breath, 0, s * 0.07)
        j[side + "LowerArm"] = ((0, 0, 0), elbow, 0, 0)
        j[side + "Hand"] = ((0, 0, 0), 0.06, 0, 0)
    return j


def idle(t):
    w = 2 * math.pi * t
    breath = math.sin(w)
    shift = math.sin(w + 0.7)
    j = base_upper(lean=0.02, breath=breath)
    j["LowerTorso"] = ((0.035 * shift, -0.02 + 0.015 * breath, 0), 0, 0.02 * shift, 0.015 * shift)
    j["Head"] = ((0, 0, 0), 0.03 - 0.01 * breath, 0.05 * math.sin(w * 0.5 + 1.0), 0)
    for side, s in (("Left", -1), ("Right", 1)):
        j[side + "UpperLeg"] = ((0, 0, 0), 0.03, 0, s * 0.03 - 0.015 * shift)
        j[side + "LowerLeg"] = ((0, 0, 0), -0.06 - 0.03 * pos_part(-s * shift), 0, 0)
        j[side + "Foot"] = ((0, 0, 0), 0.03, 0, -s * 0.03)
    return j


def gait(hip, knee, knee_stance, ankle_up, ankle_push, arm, elbow, elbow_swing, lean, bob, twist, sway, head_hold,
         yaw=0.0, base_a=0.0, base_b=0.0):
    """Цикл шага. yaw — поворот таза в сторону движения (стрейф: + вправо, − влево); грудь и голова
    разворачиваются обратно и смотрят вперёд, а ноги идут обычным шагом в сторону таза.
    base_a / base_b — присед (сгиб бедра и колена)."""

    def sample(t):
        w = 2 * math.pi * t
        j = {}
        for name, s_side, ph in (("Left", -1, 0.0), ("Right", 1, math.pi)):
            s = math.sin(w + ph)
            c = math.cos(w + ph)
            swing, stance = pos_part(c), pos_part(-c)
            a = base_a + hip * s
            kb = base_b + knee * swing ** 1.3 + knee_stance * pos_part(s) * stance
            j[name + "UpperLeg"] = ((0, 0, 0), a, 0, 0)
            j[name + "LowerLeg"] = ((0, 0, 0), -kb, 0, 0)
            # стопа параллельна полу (kb − a), носок вверх в переносе, толчок носком в конце опоры
            j[name + "Foot"] = ((0, 0, 0), (kb - a) + ankle_up * swing - ankle_push * pos_part(-s) * stance, 0, 0)
            # руки навстречу ногам, кисть запаздывает; при стрейфе махи меньше (корпус развёрнут вперёд)
            sa = math.sin(w + ph - 0.22)
            k_arm = 1.0 - 0.55 * min(1.0, abs(yaw) / 1.0)
            j[name + "UpperArm"] = ((0, 0, 0), -arm * k_arm * sa + 0.05, 0, s_side * 0.07)
            j[name + "LowerArm"] = ((0, 0, 0), elbow + elbow_swing * pos_part(-math.sin(w + ph - 0.4)), 0, 0)
            j[name + "Hand"] = ((0, 0, 0), 0.05 + 0.08 * arm * math.sin(w + ph - 0.9), 0, 0)
        y = bob * math.cos(2 * w)
        shift = bob * 0.25 * math.sin(2 * w)
        # таз: −yaw (повернуть «перёд» таза в сторону +X можно только отрицательным поворотом вокруг Y)
        j["LowerTorso"] = ((0, y, shift), 0, -yaw - twist * math.sin(w), sway * math.sin(w))
        lag = math.sin(w - 0.3)
        j["UpperTorso"] = ((0, 0, 0), -lean - bob * 0.25 * math.cos(2 * w - 0.5), yaw * 0.92 + twist * 1.6 * lag, -sway * 0.6 * lag)
        j["Head"] = ((0, 0, 0), lean * head_hold + bob * 0.35 * math.cos(2 * w - 0.9), yaw * 0.08 - twist * 0.6 * lag, 0)
        return j

    return sample


def crouch_idle(t):
    w = 2 * math.pi * t
    breath = math.sin(w)
    j = base_upper(lean=0.22, arm_fwd=0.22, elbow=0.45, breath=breath)
    j["Head"] = ((0, 0, 0), 0.2 - 0.01 * breath, 0.04 * math.sin(w * 0.5), 0)
    j["LowerTorso"] = ((0, 0.01 * breath, 0), 0, 0, 0)
    for side, s in (("Left", -1), ("Right", 1)):
        j[side + "UpperLeg"] = ((0, 0, 0), CROUCH_A + (0.08 if side == "Left" else -0.06), 0, s * 0.06)
        j[side + "LowerLeg"] = ((0, 0, 0), -(CROUCH_B + (0.06 if side == "Left" else -0.05)), 0, 0)
        j[side + "Foot"] = ((0, 0, 0), CROUCH_B - CROUCH_A - 0.02, 0, -s * 0.06)
    return j


def jump(t):
    k = keyed([(0, 0), (0.35, 1), (1, 0.6)])(t)
    j = base_upper(lean=0.05 - 0.12 * k, arm_fwd=0.06 + 0.9 * k, elbow=0.2 + 0.4 * k)
    for side, s in (("Left", -1), ("Right", 1)):
        j[side + "UpperArm"] = ((0, 0, 0), 0.06 + 0.9 * k, 0, s * (0.07 + 0.15 * k))
        j[side + "UpperLeg"] = ((0, 0, 0), -0.12 * k + (0.25 * k if side == "Left" else 0), 0, s * 0.04)
        j[side + "LowerLeg"] = ((0, 0, 0), -(0.05 + (0.45 * k if side == "Left" else 0.15 * k)), 0, 0)
        j[side + "Foot"] = ((0, 0, 0), -0.35 * k, 0, 0)
    return j


def fall(t):
    w = 2 * math.pi * t
    j = base_upper(lean=0.08, arm_fwd=0.45, elbow=0.5)
    for side, s in (("Left", -1), ("Right", 1)):
        ph = 0 if side == "Left" else math.pi
        j[side + "UpperArm"] = ((0, 0, 0), 0.55 + 0.12 * math.sin(w + ph), 0, s * (0.55 + 0.08 * math.sin(w * 2 + ph)))
        j[side + "LowerArm"] = ((0, 0, 0), 0.55 + 0.1 * math.sin(w + ph + 1), 0, 0)
        j[side + "UpperLeg"] = ((0, 0, 0), 0.35 + 0.12 * math.sin(w + ph), 0, s * 0.08)
        j[side + "LowerLeg"] = ((0, 0, 0), -(0.65 + 0.15 * math.sin(w + ph + 0.6)), 0, 0)
        j[side + "Foot"] = ((0, 0, 0), 0.15, 0, 0)
    return j


def land(t):
    k = keyed([(0, 0), (0.25, 1), (1, 0)])(t)
    j = base_upper(lean=0.05 + 0.3 * k, arm_fwd=0.06 + 0.35 * k, elbow=0.2 + 0.3 * k)
    a, b = leg_ik(L1 + L2 - 0.55 * k, 0.1 * k) if k > 0.01 else (0, 0)
    for side, s in (("Left", -1), ("Right", 1)):
        j[side + "UpperLeg"] = ((0, 0, 0), a, 0, s * 0.05)
        j[side + "LowerLeg"] = ((0, 0, 0), -b, 0, 0)
        j[side + "Foot"] = ((0, 0, 0), b - a, 0, -s * 0.03)
    # таз опускается вместе с коленями (HipHeight при приземлении не меняется)
    j["LowerTorso"] = ((0, -0.55 * k, 0), 0, 0, 0)
    return j


def climb(t):
    w = 2 * math.pi * t
    j = base_upper(lean=-0.05)
    for side, s, ph in (("Left", -1, 0.0), ("Right", 1, math.pi)):
        up = 0.5 + 0.5 * math.sin(w + ph)
        j[side + "UpperArm"] = ((0, 0, 0), 1.6 + 1.0 * up, 0, s * 0.15)
        j[side + "LowerArm"] = ((0, 0, 0), 0.9 - 0.6 * up, 0, 0)
        j[side + "Hand"] = ((0, 0, 0), -0.2, 0, 0)
        leg = 0.5 + 0.5 * math.sin(w + ph + math.pi)
        j[side + "UpperLeg"] = ((0, 0, 0), 0.25 + 0.95 * leg, 0, s * 0.05)
        j[side + "LowerLeg"] = ((0, 0, 0), -(0.35 + 1.15 * leg), 0, 0)
        j[side + "Foot"] = ((0, 0, 0), 0.2 + 0.2 * leg, 0, 0)
    j["Head"] = ((0, 0, 0), 0.25, 0, 0)
    j["LowerTorso"] = ((0, 0.05 * math.cos(2 * w), 0), 0, 0, 0)
    return j


WALK = dict(hip=0.55, knee=1.0, knee_stance=0.15, ankle_up=0.3, ankle_push=0.4, arm=0.38, elbow=0.25, elbow_swing=0.3,
            lean=0.04, bob=0.07, twist=0.08, sway=0.035, head_hold=0.8)
RUN = dict(hip=0.85, knee=1.6, knee_stance=0.3, ankle_up=0.35, ankle_push=0.6, arm=0.75, elbow=1.3, elbow_swing=0.25,
           lean=0.2, bob=0.14, twist=0.1, sway=0.03, head_hold=0.9)
SIDE = dict(WALK, twist=0.03)
STRAFE_YAW = math.radians(62)  # насколько таз разворачивается при стрейфе
CROUCH_YAW = math.radians(45)  # в приседе меньше: иначе колени разъезжаются
CROUCH = dict(hip=0.5, knee=0.6, knee_stance=0.05, ankle_up=0.15, ankle_push=0.15, arm=0.18, elbow=0.5, elbow_swing=0.12,
              lean=0.22, bob=0.03, twist=0.05, sway=0.02, head_hold=0.9)
CROUCH_SIDE = dict(CROUCH, twist=0.02)

# имя: (функция кадра, приоритет: 0 Idle, 1 Movement, 2 Action; цикл?, базовая длина, вид походки, кадров)
ANIMS = {
    "Idle": (idle, 0, True, 3.6, None, 20),
    "WalkF": (gait(**WALK), 1, True, None, ("walk", "z"), 24),
    "WalkL": (gait(**SIDE, yaw=-STRAFE_YAW), 1, True, None, ("walk", "x"), 24),
    "WalkR": (gait(**SIDE, yaw=STRAFE_YAW), 1, True, None, ("walk", "x"), 24),
    "RunF": (gait(**RUN), 1, True, None, ("run", "z"), 24),
    "CrouchIdle": (crouch_idle, 0, True, 3.2, None, 16),
    "CrouchF": (gait(**CROUCH, base_a=CROUCH_A, base_b=CROUCH_B), 1, True, None, ("crouch", "z"), 24),
    "CrouchL": (gait(**CROUCH_SIDE, yaw=-CROUCH_YAW, base_a=CROUCH_A, base_b=CROUCH_B), 1, True, None, ("crouch", "x"), 24),
    "CrouchR": (gait(**CROUCH_SIDE, yaw=CROUCH_YAW, base_a=CROUCH_A, base_b=CROUCH_B), 1, True, None, ("crouch", "x"), 24),
    "Jump": (jump, 2, False, 0.45, None, 18),
    "Fall": (fall, 1, True, 1.1, None, 20),
    "Land": (land, 2, False, 0.42, None, 16),
    "Climb": (climb, 1, True, 1.0, None, 24),
}
CROUCHED = {"CrouchIdle", "CrouchF", "CrouchL", "CrouchR"}


def sole_points(info, poses, root_offset):
    """Нижняя точка каждой стопы в мире (подошва под лодыжкой)."""
    world = rig.pose_world(info, poses, root_offset)
    out = {}
    for side in ("Left", "Right"):
        R, t = world[side + "Foot"]
        c = info[side + "Foot"]["Center"]
        local = np.array([0.0, -info[side + "Foot"]["Size"][1] / 2, 0.0])
        out[side] = R @ local + t
        out[side + "C"] = c
    return out


def stride(info, sample, axis, root_offset):
    """Сколько стопа проезжает назад (вдоль axis) на опоре за цикл — в долях цикла: путь / доля опоры."""
    k = 0 if axis == "x" else 2
    n = 240
    pts = [sole_points(info, sample(i / n), root_offset) for i in range(n + 1)]
    total, frac = 0.0, 0.0
    for side in ("Left", "Right"):
        ys = np.array([p[side][1] for p in pts])
        low = ys.min()
        on = ys < low + 0.06  # стопа на полу
        travel = 0.0
        cnt = 0
        for i in range(n):
            if on[i] and on[i + 1]:
                travel += abs(pts[i + 1][side][k] - pts[i][side][k])
                cnt += 1
        total += travel
        frac += cnt / n
    # скорость = путь на опоре / время на опоре; при длине цикла T: v = (travel/2) / (T * frac/2)
    return total / 2, frac / 2


def main():
    os.makedirs(OUT, exist_ok=True)
    parts = rig.build_parts()
    info, _ = rig.spec(parts)
    meta = {}
    for name, (fn, priority, loop, length, kind, frames) in ANIMS.items():
        root_offset = (0, -CROUCH_DROP, 0) if name in CROUCHED else (0, 0, 0)
        natural = 0.0
        if kind:
            gaitname, axis = kind
            travel, frac = stride(info, fn, axis, root_offset)
            # длина цикла, при которой стопа на полу движется с нужной скоростью
            length = travel / max(1e-6, frac * SPEED[gaitname])
            natural = SPEED[gaitname]
        markers = [(0.25, "Step", "L"), (0.75, "Step", "R")] if kind else None
        seq = sequence("DC_" + name, length, frames, fn, priority, loop, markers)
        data = write_binary([seq])
        with open(os.path.join(OUT, name + ".rbxm"), "wb") as f:
            f.write(data)
        meta[name] = {"Length": round(length, 4), "Natural": natural, "Loop": loop, "Priority": priority}
        print(f"{name:10s} длина {length:5.2f} с, скорость {natural:5.1f}, {len(data)} байт")
    meta["_CrouchDrop"] = CROUCH_DROP
    with open(os.path.join(OUT, "anims.json"), "w") as f:
        json.dump(meta, f, indent=1)
    print("присед: бедро %.2f, колено %.2f рад" % (CROUCH_A, CROUCH_B))


if __name__ == "__main__":
    main()
