#!/usr/bin/env python3
"""Собственные анимации персонажей NIGHT SHIFT (R15): ходьба, бег и ожидание.

Кадры считаются формулами (цикл шага), а не берутся у Roblox. Результат — файлы .rbxm
с KeyframeSequence в build/anims/, их загружают в Roblox как ассет типа Animation.

Как устроен шаг (t — доля цикла 0..1, левая нога впереди при t = 0.25):
  • бедро качается по синусу, колено сгибается, пока нога идёт вперёд (фаза переноса),
    стопа приподнимает носок в переносе и отталкивается в конце опоры;
  • руки идут навстречу ногам, локти чуть согнуты (сильнее, когда рука впереди);
  • таз два раза за цикл опускается и поднимается, слегка поворачивается и кренится,
    грудь поворачивается навстречу тазу, голова держит взгляд ровно.

Запуск: python3 tools/make_anims.py  ->  build/anims/walk.rbxm, run.rbxm, idle.rbxm
"""
import math
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)
import build  # noqa: E402  (бинарный писатель .rbxl/.rbxm)

Inst = build.Inst
OUT = os.path.join(ROOT, "build", "anims")

# Иерархия суставов R15: имя детали -> дочерние детали
TREE = {
    "HumanoidRootPart": ["LowerTorso"],
    "LowerTorso": ["UpperTorso", "LeftUpperLeg", "RightUpperLeg"],
    "UpperTorso": ["Head", "LeftUpperArm", "RightUpperArm"],
    "LeftUpperArm": ["LeftLowerArm"],
    "LeftLowerArm": ["LeftHand"],
    "RightUpperArm": ["RightLowerArm"],
    "RightLowerArm": ["RightHand"],
    "LeftUpperLeg": ["LeftLowerLeg"],
    "LeftLowerLeg": ["LeftFoot"],
    "RightUpperLeg": ["RightLowerLeg"],
    "RightLowerLeg": ["RightFoot"],
    "Head": [],
    "LeftHand": [],
    "RightHand": [],
    "LeftFoot": [],
    "RightFoot": [],
}


def matmul(a, b):
    return [[sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)] for i in range(3)]


def rot(rx=0.0, ry=0.0, rz=0.0):
    """Поворот как CFrame.Angles(rx, ry, rz) в Roblox (X, затем Y, затем Z)."""
    cx, sx = math.cos(rx), math.sin(rx)
    cy, sy = math.cos(ry), math.sin(ry)
    cz, sz = math.cos(rz), math.sin(rz)
    rxm = [[1, 0, 0], [0, cx, -sx], [0, sx, cx]]
    rym = [[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]]
    rzm = [[cz, -sz, 0], [sz, cz, 0], [0, 0, 1]]
    return matmul(matmul(rxm, rym), rzm)


def cframe(pos=(0, 0, 0), rx=0.0, ry=0.0, rz=0.0):
    r = rot(rx, ry, rz)
    return (pos[0], pos[1], pos[2], r[0][0], r[0][1], r[0][2], r[1][0], r[1][1], r[1][2], r[2][0], r[2][1], r[2][2])


def pose_tree(name, joints):
    """joints: имя детали -> (pos, rx, ry, rz). Возвращает Pose со всеми дочерними."""
    pos, rx, ry, rz = joints.get(name, ((0, 0, 0), 0, 0, 0))
    p = Inst("Pose", name, [
        ("CFrame", "CFrame", cframe(pos, rx, ry, rz)),
        ("float", "Weight", 1.0),
        ("token", "EasingStyle", 0),  # Linear: кадры частые, между ними — прямая интерполяция
        ("token", "EasingDirection", 0),
    ])
    for child in TREE[name]:
        p.add(pose_tree(child, joints))
    return p


def sequence(name, length, frames, sample, priority):
    kfs = Inst("KeyframeSequence", name, [("bool", "Loop", True), ("token", "Priority", priority)])
    for i in range(frames + 1):
        t = i / frames
        kf = Inst("Keyframe", "Keyframe", [("float", "Time", round(t * length, 4))])
        kf.add(pose_tree("HumanoidRootPart", sample(t)))
        kfs.add(kf)
    return kfs


def pos_part(x):
    return max(0.0, x)


def gait(hip, knee, knee_stance, ankle_up, ankle_push, arm, elbow, elbow_swing, lean, bob, twist, sway, head_hold):
    """Возвращает функцию t -> позы суставов для шага с заданными амплитудами (радианы, studs)."""

    def sample(t):
        w = 2 * math.pi * t
        j = {}
        for side, ph in (("Left", 0.0), ("Right", math.pi)):
            s = math.sin(w + ph)          # >0 — нога впереди
            c = math.cos(w + ph)          # >0 — нога идёт вперёд (перенос)
            swing = pos_part(c)
            stance = pos_part(-c)
            # бедро: вперёд-назад; колено: сгиб в переносе и немного при постановке на пятку
            j[side + "UpperLeg"] = ((0, 0, 0), hip * s, 0, 0)
            j[side + "LowerLeg"] = ((0, 0, 0), -(knee * swing ** 1.3 + knee_stance * pos_part(s) * stance), 0, 0)
            # стопа: носок вверх в переносе, толчок носком в конце опоры
            j[side + "Foot"] = ((0, 0, 0), ankle_up * swing - ankle_push * pos_part(-s) * stance, 0, 0)
            # рука навстречу ноге той же стороны
            a = -arm * s
            j[side + "UpperArm"] = ((0, 0, 0), a, 0, (0.06 if side == "Left" else -0.06))
            j[side + "LowerArm"] = ((0, 0, 0), elbow + elbow_swing * pos_part(-s), 0, 0)
            j[side + "Hand"] = ((0, 0, 0), 0.05, 0, 0)
        # таз: два подъёма за цикл (выше всего, когда ноги проходят друг мимо друга), поворот и крен
        y = bob * math.cos(2 * w)
        j["LowerTorso"] = ((0, y, 0), 0, -twist * math.sin(w), sway * math.sin(w))
        # грудь: наклон вперёд, поворот навстречу тазу
        j["UpperTorso"] = ((0, 0, 0), -lean, twist * 1.6 * math.sin(w), -sway * 0.6 * math.sin(w))
        # голова гасит повороты и наклон
        j["Head"] = ((0, 0, 0), lean * head_hold, -twist * 0.6 * math.sin(w), 0)
        return j

    return sample


def idle_sample(t):
    w = 2 * math.pi * t
    breath = math.sin(w)            # один вдох за цикл
    shift = math.sin(w + 0.7)       # переступает с ноги на ногу
    j = {
        "LowerTorso": ((0.03 * shift, -0.02 + 0.015 * breath, 0), 0, 0.02 * shift, 0.015 * shift),
        "UpperTorso": ((0, 0, 0), -0.02 + 0.012 * breath, -0.02 * shift, -0.01 * shift),
        "Head": ((0, 0, 0), 0.03 - 0.01 * breath, 0.04 * math.sin(w * 0.5 + 1.0), 0),
        "LeftUpperArm": ((0, 0, 0), 0.03 + 0.015 * breath, 0, 0.07),
        "RightUpperArm": ((0, 0, 0), 0.03 + 0.015 * breath, 0, -0.07),
        "LeftLowerArm": ((0, 0, 0), 0.16, 0, 0),
        "RightLowerArm": ((0, 0, 0), 0.18, 0, 0),
        "LeftHand": ((0, 0, 0), 0.08, 0, 0),
        "RightHand": ((0, 0, 0), 0.08, 0, 0),
        "LeftUpperLeg": ((0, 0, 0), 0.02, 0, -0.015 * shift),
        "RightUpperLeg": ((0, 0, 0), 0.02, 0, -0.015 * shift),
        "LeftLowerLeg": ((0, 0, 0), -0.04 - 0.03 * max(0, -shift), 0, 0),
        "RightLowerLeg": ((0, 0, 0), -0.04 - 0.03 * max(0, shift), 0, 0),
        "LeftFoot": ((0, 0, 0), 0.02, 0, 0),
        "RightFoot": ((0, 0, 0), 0.02, 0, 0),
    }
    return j


# Длина цикла и «родная» скорость (studs/с при росте 1): скрипт анимации подстраивает темп под скорость
ANIMS = {
    # спокойный шаг: длинные медленные шаги, взгляд ровно
    "walk": dict(length=0.84, natural=9.0, priority=1, sample=gait(
        hip=0.52, knee=0.95, knee_stance=0.18, ankle_up=0.3, ankle_push=0.42,
        arm=0.34, elbow=0.22, elbow_swing=0.3, lean=0.05, bob=0.07, twist=0.07, sway=0.035, head_hold=0.8)),
    # бег: корпус вперёд, высокие колени, руки согнуты
    "run": dict(length=0.6, natural=17.0, priority=1, sample=gait(
        hip=0.85, knee=1.55, knee_stance=0.35, ankle_up=0.35, ankle_push=0.6,
        arm=0.75, elbow=1.25, elbow_swing=0.25, lean=0.2, bob=0.16, twist=0.1, sway=0.03, head_hold=0.9)),
    # ожидание: дыхание и лёгкое переступание
    "idle": dict(length=4.0, natural=0, priority=0, sample=idle_sample),
}


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, a in ANIMS.items():
        frames = 24 if name != "idle" else 16
        seq = sequence("NS_" + name.capitalize(), a["length"], frames, a["sample"], a["priority"])
        data = build.write_binary([seq])
        path = os.path.join(OUT, name + ".rbxm")
        with open(path, "wb") as f:
            f.write(data)
        print(f"{path}: {len(data)} байт, цикл {a['length']} с, скорость {a['natural']}")


if __name__ == "__main__":
    main()
